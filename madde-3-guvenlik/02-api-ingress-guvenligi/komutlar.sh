#!/bin/bash
# ============================================================
# API ve Ingress Güvenliği - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# Rate Limiting (Traefik Middleware)
# ------------------------------------------------------------
# NOT: Notion gorevi "NGINX Ingress'e rate limit ekle" diyordu, ama
# zero-trust-cluster'da k3d'nin varsayilan getirdigi Traefik zaten
# calisiyordu. Ikinci bir ingress controller kurup kaynak israf etmek
# yerine, ayni ogretici degeri tasiyan Traefik'in kendi rate limit
# Middleware'ini kullandik.

kubectl get crd | grep traefik
# CRD grubu dogrulandi: traefik.io/v1alpha1

# Onceki konudan (Zero-Trust) kalma L7 policy, sadece app=client
# etiketli pod'lara izin veriyordu, Traefik'in trafigini de
# bloklayabilirdi, temizlendi:
kubectl delete cnp l7-allow-get-only

cat <<EOF | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
spec:
  rateLimit:
    average: 10
    burst: 20
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: server-route
spec:
  entryPoints:
    - web
  routes:
    - match: Host(\`server.local\`)
      kind: Rule
      services:
        - name: server-svc
          port: 80
      middlewares:
        - name: rate-limit
EOF

kubectl port-forward -n kube-system svc/traefik 8080:80 &

brew install hey
hey -n 200 -c 20 -host server.local http://localhost:8080/
# SONUÇ: Status code distribution: [200] 20 responses, [429] 180 responses
# burst: 20 ayari sayesinde ilk 20 istek gecti, geri kalan 180 istek
# 429 Too Many Requests ile reddedildi. Rate limiting dogrulandi.


# ------------------------------------------------------------
# WAF (Coraza / OWASP ModSecurity CRS)
# ------------------------------------------------------------
# NOT: Coraza'yi Traefik plugin sistemine (Yaegi/WASM) entegre etmek
# k3d'de kirilgan ve zaman alici olurdu. Bunun yerine OWASP'in resmi
# hazir image'i ile standalone bir Docker demosu kuruldu, ayni
# ogretici degeri (kotu niyetli payload'in uygulamaya ulasmadan
# reddedilmesi) tasiyor.

docker network create waf-demo
docker run -d --name waf-backend --network waf-demo nginx
docker run -d --name coraza-waf --network waf-demo -p 8090:8080 \
  -e BACKEND=http://waf-backend:80 \
  -e PARANOIA=1 \
  owasp/modsecurity-crs:nginx-alpine

curl -s -o /dev/null -w "Normal istek: %{http_code}\n" http://localhost:8090/
# SONUÇ: Normal istek: 200

# ILK DENEME (hatali, shell tek tirnaklari yanlis yorumladi):
curl -s -o /dev/null -w "SQLi payload: %{http_code}\n" "http://localhost:8090/?id=1' OR '1'='1"
# SONUÇ: SQLi payload: 000 (baglanti kurulamadi/koptu gibi gorundu)
# SEBEP: Terminal/shell, URL icindeki tek tirnaklari (') kendi
# quoting kurallarina gore yorumlayip curl'e bozuk bir istek gonderdi,
# WAF'in kendisiyle ilgisi yoktu.

# ÇÖZÜM: URL-encode edilmis payload ile tekrar dene, -v ile dogrula
curl -v "http://localhost:8090/?id=1%27%20OR%20%271%27=%271" 2>&1 | tail -30
docker logs coraza-waf --tail 50
# SONUÇ: HTTP/1.1 403 Forbidden
# docker logs icinde: "SQL Injection Attack Detected via libinjection"
# rule id 942100 (REQUEST-942-APPLICATION-ATTACK-SQLI.conf)
# + "Inbound Anomaly Score Exceeded (Total Score: 5)" rule id 949110
# WAF hem imza tabanli (libinjection) hem skor tabanli (anomaly
# scoring, PARANOIA=1 seviyesinde esik 5) calisiyor, tek bir kural
# degil, birikimli risk puanina gore karar veriyor.


# ------------------------------------------------------------
# mTLS (Mutual TLS)
# ------------------------------------------------------------
# NOT: cert-manager yerine (Madde 1'de zaten self-signed sertifika
# deneyimlenmisti) burada openssl ile elle bir mini CA zinciri
# kuruldu, ayni mTLS dogrulama mantigini daha az soyut sekilde
# gostermek icin.

kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik \
  -o jsonpath='{.items[0].spec.containers[0].args}' | tr ',' '\n' | grep entryPoint
# websecure entrypoint :8443/tcp, tls=true zaten aktif geliyor

mkdir -p mtls-certs && cd mtls-certs

# Kendi mini CA'miz
openssl req -x509 -newkey rsa:2048 -days 365 -nodes \
  -keyout ca.key -out ca.crt -subj "/CN=demo-ca"

# Server sertifikasi, CA tarafindan imzali
openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/CN=server.local"
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365

# Client sertifikasi, ayni CA tarafindan imzali
openssl req -newkey rsa:2048 -nodes -keyout client.key -out client.csr -subj "/CN=demo-client"
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client.crt -days 365

kubectl create secret tls server-tls --cert=server.crt --key=server.key
kubectl create secret generic ca-secret --from-file=ca.crt=ca.crt

cat <<EOF | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: TLSOption
metadata:
  name: mtls-opt
spec:
  clientAuth:
    secretNames:
      - ca-secret
    clientAuthType: RequireAndVerifyClientCert
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: server-route-mtls
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`server.local\`)
      kind: Rule
      services:
        - name: server-svc
          port: 80
  tls:
    secretName: server-tls
    options:
      name: mtls-opt
EOF

# HATA: kubectl port-forward -n kube-system svc/traefik 8443:8443
# "error: Service traefik does not have a service port 8443"
# SEBEP: Container'in kendi entrypoint portu 8443 ama Service
# seviyesinde bu targetPort adi "websecure" olarak 443'e baglanmis.
# kubectl get svc -n kube-system traefik -o jsonpath='{.spec.ports}'
# ile dogrulandi.

# ÇÖZÜM:
kubectl port-forward -n kube-system svc/traefik 8443:443 &

# Client sertifikasi OLMADAN dene:
curl -v --cacert ca.crt https://server.local:8443/ --resolve server.local:8443:127.0.0.1
# SONUÇ: SSL_read hatasi ile baglanti koptu (tlsv13 alert certificate
# required), Traefik client sertifikasi talep edip alamayinca
# baglantiyi reddetti.

# Client sertifikasi ILE dene:
curl -s --cacert ca.crt --cert client.crt --key client.key \
  -o /dev/null -w "mTLS ile durum kodu: %{http_code}\n" \
  https://server.local:8443/ --resolve server.local:8443:127.0.0.1
# SONUÇ: mTLS ile durum kodu: 200

