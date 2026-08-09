#!/bin/bash
# ============================================================
# Kimlik ve Erişim (OIDC/IAM) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# ADIM 1: Keycloak'u ayağa kaldır, realm/client/user oluştur
# ------------------------------------------------------------
# Keycloak zaten bildigin bir arac oldugu icin UI yerine kcadm CLI
# ile hizlica realm/client/user olusturuyoruz.

docker run -d --name keycloak \
  -p 8180:8080 \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=admin123 \
  quay.io/keycloak/keycloak:latest start-dev

sleep 15

docker exec keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user admin --password admin123

docker exec keycloak /opt/keycloak/bin/kcadm.sh create realms -s realm=k8s-realm -s enabled=true

docker exec keycloak /opt/keycloak/bin/kcadm.sh create clients -r k8s-realm \
  -s clientId=k8s-client -s enabled=true -s publicClient=true \
  -s 'redirectUris=["http://localhost:8000/*"]' \
  -s directAccessGrantsEnabled=true

docker exec keycloak /opt/keycloak/bin/kcadm.sh create users -r k8s-realm \
  -s username=devuser -s enabled=true -s email=devuser@example.com

docker exec keycloak /opt/keycloak/bin/kcadm.sh set-password -r k8s-realm \
  --username devuser --new-password devpass123


# ------------------------------------------------------------
# ADIM 2: "Issuer eslesmesi" sorununu onceden coz
# ------------------------------------------------------------
# MANTIK: K8s API server, bir token'i kabul etmeden once JWT'nin
# icindeki "iss" (issuer) alaninin, kendisine --oidc-issuer-url ile
# soylenen adresle BIREBIR ayni string olmasini sart kosar. Ayrica
# apiserver bu issuer adresine kendisi de HTTP ile ulasip OIDC
# discovery (/.well-known/openid-configuration) yapar.
#
# Sorun: apiserver, k3d container'inin ICINDEN calisiyor. Sen
# (host makine) Keycloak'a "localhost:8180" ile ulasiyorsun, ama
# container'in icinden "localhost" o container'in kendisi demek,
# Keycloak'a degil. Container'lar host makineye "host.k3d.internal"
# adresiyle ulasabiliyor (k3d bunu otomatik CoreDNS'e enjekte ediyor).
#
# Eger sen token'i "localhost:8180" uzerinden alirsan, JWT'nin icine
# "iss": "http://localhost:8180/realms/k8s-realm" yazilir. Ama
# apiserver'a "host.k3d.internal:8180" adresini soylersek, apiserver
# bu iki string'in (localhost vs host.k3d.internal) ES OLMADIGINI
# gorup token'i REDDEDER, cunku issuer string'leri tam eslesmiyor.
#
# COZUM: Hem host makineden hem k3d container'larindan AYNI adresle
# (host.k3d.internal) Keycloak'a ulasilabilmesini sagliyoruz. Bunun
# icin host makinenin /etc/hosts dosyasina host.k3d.internal'i
# 127.0.0.1'e yonlendiren bir satir ekliyoruz. Boylece hem sen hem
# apiserver ayni issuer string'ini gorur.

sudo sh -c 'echo "127.0.0.1 host.k3d.internal" >> /etc/hosts'

# Dogrula:
ping -c 1 host.k3d.internal


# ------------------------------------------------------------
# ADIM 3: K8s cluster'ini OIDC'ye guvenecek sekilde kur
# ------------------------------------------------------------
# MANTIK: kube-apiserver'in --oidc-* flag'leri, "bu issuer'dan gelen,
# bu client-id'ye ait, imzasi gecerli bir token'i kimlik olarak kabul
# et" der. oidc-username-claim, JWT icindeki hangi alanin K8s
# kullanici adi olarak kullanilacagini belirler (Keycloak'ta bu
# genelde "preferred_username").

k3d cluster delete oidc-cluster 2>/dev/null || true

k3d cluster create oidc-cluster \
  --k3s-arg '--kube-apiserver-arg=oidc-issuer-url=http://host.k3d.internal:8180/realms/k8s-realm@server:*' \
  --k3s-arg '--kube-apiserver-arg=oidc-client-id=k8s-client@server:*' \
  --k3s-arg '--kube-apiserver-arg=oidc-username-claim=preferred_username@server:*' \
  --k3s-arg '--kube-apiserver-arg=oidc-groups-claim=groups@server:*'

kubectl get nodes


# ------------------------------------------------------------
# ADIM 4: RBAC - devuser'a sadece readonly yetkisi ver
# ------------------------------------------------------------
# MANTIK: OIDC sadece "bu kisi kim oldugunu kanitladi" (authentication)
# der, "bu kisi ne yapabilir" (authorization) sorusunu RBAC cevaplar.
# Ikisi ayri katmanlar. Token'i kabul etmek, otomatik olarak yetki
# vermek anlamina gelmez, ayrica bir RoleBinding ile bu kullanici
# adini (preferred_username claim'inden gelen "devuser") bir Role'e
# baglamak gerekir.

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: readonly
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: devuser-readonly
  namespace: default
subjects:
- kind: User
  name: devuser
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: readonly
  apiGroup: rbac.authorization.k8s.io
EOF


# ------------------------------------------------------------
# ADIM 5: devuser olarak token al, kubectl ile test et
# ------------------------------------------------------------
# MANTIK: "Resource Owner Password Credentials" grant'i ile (sadece
# lab/test icin uygun, production'da tarayici tabanli login flow'u
# kullanilir) Keycloak'tan dogrudan bir id_token istiyoruz. K8s'in
# kabul ettigi token id_token'dir, access_token degil.

TOKEN=$(curl -s -X POST http://host.k3d.internal:8180/realms/k8s-realm/protocol/openid-connect/token \
  -d grant_type=password \
  -d client_id=k8s-client \
  -d username=devuser \
  -d password=devpass123 | python3 -c "import sys,json; print(json.load(sys.stdin)['id_token'])")

echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool
# JWT'nin payload kismini decode edip "iss" ve "preferred_username"
# alanlarinin beklendigi gibi oldugunu goz ile dogrula.

# Izin verilen islem (okuma):
kubectl --token="$TOKEN" get pods
# Beklenen: SONUÇ doner (readonly Role izin veriyor)

# Izin verilmeyen islem (yazma):
kubectl --token="$TOKEN" delete pod some-pod-adi
# Beklenen: Error from server (Forbidden), cunku readonly Role'de
# "delete" verb'u hic tanimli degil

# Izin verilmeyen kapsam (namespace disi):
kubectl --token="$TOKEN" get pods -n kube-system
# Beklenen: Error from server (Forbidden), cunku RoleBinding sadece
# "default" namespace'inde tanimli, kube-system'da degil


# ------------------------------------------------------------
# ADIM 6: Farkli roller (dev, ops, readonly) + Audit logging
# ------------------------------------------------------------
# MANTIK: audit-policy-file, apiserver'a "hangi istekleri, ne
# detayda logla" der. level: Metadata sadece "kim ne zaman hangi
# kaynaga hangi fiili uyguladi" bilgisini loglar (govde/body yok).
# level: RequestResponse hem istegi hem cevabi tam loglar (pods icin
# ozellikle secildi, cunku pod'lar uzerindeki her hareketi detayli
# gormek istiyoruz). Audit flag'leri sicak eklenemedigi icin cluster
# yeniden kuruldu, OIDC flag'leri de korunarak.

cat > audit-policy.yaml << 'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: RequestResponse
  resources:
  - group: ""
    resources: ["pods"]
- level: Metadata
  omitStages:
  - RequestReceived
EOF

k3d cluster delete oidc-cluster

k3d cluster create oidc-cluster \
  --volume "$(pwd)/audit-policy.yaml:/etc/rancher/k3s/audit-policy.yaml" \
  --k3s-arg '--kube-apiserver-arg=oidc-issuer-url=http://host.k3d.internal:8180/realms/k8s-realm@server:*' \
  --k3s-arg '--kube-apiserver-arg=oidc-client-id=k8s-client@server:*' \
  --k3s-arg '--kube-apiserver-arg=oidc-username-claim=preferred_username@server:*' \
  --k3s-arg '--kube-apiserver-arg=oidc-groups-claim=groups@server:*' \
  --k3s-arg '--kube-apiserver-arg=audit-policy-file=/etc/rancher/k3s/audit-policy.yaml@server:*' \
  --k3s-arg '--kube-apiserver-arg=audit-log-path=/var/log/k8s-audit.log@server:*'

kubectl get nodes

# RBAC'i (readonly) ve iki yeni rolu (dev, ops) tekrar uygula, cluster
# yeniden kuruldugu icin state sifirlandi.
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: readonly
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: dev
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ops
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
# NOT: ops bile secrets/rbac.authorization.k8s.io kaynaklarina hic
# erisemiyor, "operasyon yap ama yetki sistemine dokunma" prensibi.
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: devuser-readonly
  namespace: default
subjects:
- kind: User
  name: devuser
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: readonly
  apiGroup: rbac.authorization.k8s.io
EOF

# devuser icin token'i yeniden al (cluster yeniden kuruldu ama
# Keycloak container'i ayakta kaldigi icin realm/client/user duruyor)
TOKEN=$(curl -s -X POST http://host.k3d.internal:8180/realms/k8s-realm/protocol/openid-connect/token \
  -d grant_type=password \
  -d client_id=k8s-client \
  -d username=devuser \
  -d password=devpass123 | python3 -c "import sys,json; print(json.load(sys.stdin)['id_token'])")

# Yetkisiz erisim denemesi uret (devuser kube-system'a delete atmaya calissin)
kubectl --token="$TOKEN" delete pod fake-pod -n kube-system
# Beklenen: Forbidden hatasi doner

# Bu denemenin audit log'a dustugunu dogrula
docker exec k3d-oidc-cluster-server-0 tail -n 20 /var/log/k8s-audit.log | python3 -m json.tool 2>/dev/null || \
docker exec k3d-oidc-cluster-server-0 grep "devuser" /var/log/k8s-audit.log | tail -5
# Beklenen: user.username: devuser, verb: delete, gecerli olmayan
# yetki nedeniyle responseStatus.code: 403 iceren bir audit kaydi


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# Akis: Keycloak kimlik dogrular (authentication) -> RBAC yetki
# sinirlarini cizer (authorization, readonly/dev/ops uc ayri seviye)
# -> audit log her istegi (ozellikle pod'larin tam govdesini,
# digerlerini metadata seviyesinde) kaydeder, yetkisiz bir deneme
# audit log'da devuser + delete + 403 olarak goruluyor.

