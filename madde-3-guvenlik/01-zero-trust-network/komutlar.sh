#!/bin/bash
# ============================================================
# Zero-Trust Network (Cilium) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# Cluster kurulumu (flannel'siz, Cilium icin temiz zemin)
# ------------------------------------------------------------
# NOT: ha-cluster'a dokunmadik, bu konuya ozel ayri bir cluster actik.
# k3d varsayilan olarak flannel CNI ile gelir, Cilium'u duzgun kurmak
# icin flannel ve varsayilan network policy denetleyicisini kapatmak
# gerekiyor.

k3d cluster create zero-trust-cluster \
  --k3s-arg '--flannel-backend=none@server:*' \
  --k3s-arg '--disable-network-policy@server:*' \
  --agents 1

brew install cilium-cli
cilium version


# ------------------------------------------------------------
# Cilium kurulumu - ILK DENEME (hatali)
# ------------------------------------------------------------

cilium install
# HATA: cilium ve cilium-operator pod'lari "Init:Error" durumunda
# takili kaldi. kubectl describe pod ile incelenince config init
# container'inin su hatayi verdigi gorundu:
#   KUBERNETES_SERVICE_HOST: 0.0.0.0
#   KUBERNETES_SERVICE_PORT: 56309
#   error="dial tcp 0.0.0.0:56309: connect: connection refused"
#
# SEBEP: Tavuk-yumurta problemi. Cilium kube-proxy'siz modda kuruldu,
# yani "kubernetes" Service'inin ClusterIP'sine giden yolu normalde
# kube-proxy programlar, ama biz bu isi Cilium'a devrettik. Cilium
# henuz ayaga kalkmadigi icin (tam da su an baslamaya calistigi an)
# bu ClusterIP'ye giden yolu kimse programlamamis durumda. Cilium
# kendi baslamasi icin ihtiyac duydugu API server baglantisini, yine
# kendisinin kuracagi bir mekanizma uzerinden aramaya calisiyor, bu
# yuzden 0.0.0.0 gibi gecersiz bir adrese dusuyor.
#
# ÇÖZÜM: Cilium'a API server'in gercek adresini (sanal ClusterIP
# degil) acikca soylemek gerekiyor. k3d'de butun node container'lar
# ayni Docker network'unde oldugu icin, server container'inin adi
# Docker'in kendi DNS'i uzerinden cozulebiliyor.

# Yarim kalan uninstall/install denemesi cilium-secrets namespace'ini
# "terminating" durumunda tikadi, o yuzden cluster'i tamamen silip
# temiz baslamak en hizli cozum oldu:
k3d cluster delete zero-trust-cluster

k3d cluster create zero-trust-cluster \
  --k3s-arg '--flannel-backend=none@server:*' \
  --k3s-arg '--disable-network-policy@server:*' \
  --agents 1

cilium install \
  --set k8sServiceHost=k3d-zero-trust-cluster-server-0 \
  --set k8sServicePort=6443

cilium status --wait
# SONUÇ: Cilium: OK, Operator: OK, Envoy DaemonSet: OK
# Cluster Pods: 6/6 managed by Cilium

kubectl get nodes
# Node'lar artik Ready (Cilium CNI'yi devreye aldigi icin)


# ------------------------------------------------------------
# Kendin Dene: default-allow problemini gozle gor
# ------------------------------------------------------------
# Hicbir NetworkPolicy yokken client'in server'a serbestce eristigini
# gostermek icin basit bir server + client kurduk.

kubectl run server --image=nginx --labels="app=server" --port=80
kubectl expose pod server --port=80 --name=server-svc

kubectl run client --image=busybox --labels="app=client" -it --rm --restart=Never -- wget -qO- --timeout=2 server-svc
# SONUÇ: nginx'in "Welcome to nginx!" sayfasi geldi, hicbir kisitlama yok.
# NOT: "kubectl run server" ile DNS ile "server" adiyla erisilemiyor,
# HATA: wget: bad address 'server' -> SEBEP: K8s DNS sadece Service'lere
# calisir, ciplak pod adina degil. kubectl expose pod ile Service eklendi.


# ------------------------------------------------------------
# Simdi Boz: default-deny uygula
# ------------------------------------------------------------

# ILK DENEME (CiliumNetworkPolicy ile, hatali):
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: default-deny
spec:
  endpointSelector: {}
  ingress: []
EOF
# HATA: kubectl get cnp default-deny -> VALID: False
# kubectl describe cnp default-deny -> Message: "rule must have at
# least one of Ingress, IngressDeny, Egress, EgressDeny"
# SEBEP: CiliumNetworkPolicy CRD semasi, bos "ingress: []" listesini
# "hic kural tanimlanmamis" sayip geciriyor, standart K8s NetworkPolicy'
# deki "bos ingress = hepsini reddet" mantigi burada calismiyor.

kubectl delete cnp default-deny

# ÇÖZÜM: standart Kubernetes NetworkPolicy kullan (Cilium bunu da
# CNI olarak dogru sekilde uyguluyor)
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

kubectl run client --image=busybox --labels="app=client" -it --rm --restart=Never -- wget -qO- --timeout=2 server-svc
# SONUÇ: "wget: download timed out" -> default-deny gercekten calisiyor.


# ------------------------------------------------------------
# Spesifik izin ekle (additive model)
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-to-server
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: client
EOF

kubectl run client --image=busybox --labels="app=client" -it --rm --restart=Never -- wget -qO- --timeout=2 server-svc
# SONUÇ: nginx sayfasi tekrar geldi. default-deny taban olarak duruyor,
# spesifik allow kurali onun ustune ekleniyor (additive model dogrulandi).


# ------------------------------------------------------------
# L7 Policy: HTTP metod seviyesinde kisitlama (standart NetworkPolicy'nin yapamadigi)
# ------------------------------------------------------------

kubectl delete networkpolicy default-deny allow-client-to-server

cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: l7-allow-get-only
spec:
  endpointSelector:
    matchLabels:
      app: server
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: client
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - method: "GET"
EOF

# curl kullanabilen bir client lazim, busybox'in wget'i method degistiremiyor
kubectl run client --image=curlimages/curl --labels="app=client" -it --rm --restart=Never -- curl -s -o /dev/null -w "GET durum kodu: %{http_code}\n" --max-time 2 http://server-svc
# SONUÇ: GET durum kodu: 200

kubectl run client --image=curlimages/curl --labels="app=client" -it --rm --restart=Never -- curl -s -X DELETE -o /dev/null -w "DELETE durum kodu: %{http_code}\n" --max-time 2 http://server-svc
# SONUÇ: DELETE durum kodu: 403
# Ayni IP/port uzerinden gitmesine ragmen GET gecti DELETE reddedildi,
# standart bir L3/L4 firewall bunu asla ayirt edemezdi.


# ------------------------------------------------------------
# Hubble: trafik akisini gozlemle
# ------------------------------------------------------------

cilium hubble enable --ui
cilium status --wait

brew install hubble
cilium hubble ui &
cilium hubble port-forward &

hubble observe --protocol http -n default
# SONUÇ:
# ... http-request FORWARDED (HTTP/1.1 GET http://server-svc/)
# ... http-response FORWARDED (HTTP/1.1 200 ... (GET http://server-svc/))
# ... http-request DROPPED (HTTP/1.1 DELETE http://server-svc/)
# ... http-response FORWARDED (HTTP/1.1 403 ... (DELETE http://server-svc/))
#
# NOT: DELETE'in kendisi DROPPED, ama response yine FORWARDED gorunuyor,
# cunku Envoy istegi engelleyip kendisi 403 cevabini uretip client'a
# geri gonderiyor (request drop, ama response'un kendisi iletiliyor).


# ------------------------------------------------------------
# Policy ihlalini logla ve alert uret
# ------------------------------------------------------------
# NOT: Su an gercek bir Slack workspace'i kurulu degil, bu yuzden
# asagidaki script YAZILDI/DOKUMANTE EDILDI ama gercekten calistirilip
# Slack'e gonderim yapilmadi. Mantik Drift Detection'daki (Madde 2)
# Slack webhook scriptiyle birebir ayni.

cat > watch-policy-violations.sh << 'EOF'
#!/bin/bash
# hubble observe ciktisini surekli izler, DROPPED gecen bir satir
# gorunce Slack'e bildirim gonderir.

SLACK_WEBHOOK_URL="https://hooks.slack.com/services/SENIN/WEBHOOK/URLIN"

hubble observe --protocol http -n default -f | while read -r line; do
  if echo "$line" | grep -q "DROPPED"; then
    echo "POLICY IHLALI TESPIT EDILDI: $line"

    curl -X POST -H 'Content-type: application/json' \
      --data "{\"text\": \"⚠️ *Cilium Policy İhlali* — \`\`\`${line}\`\`\`\"}" \
      "$SLACK_WEBHOOK_URL"
  fi
done
EOF

chmod +x watch-policy-violations.sh
# Calistirmak icin: ./watch-policy-violations.sh &
# (arka planda calisir, DROPPED gecen her satirda Slack'e mesaj atar)


