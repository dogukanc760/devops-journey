#!/bin/bash
# ============================================================
# Service Mesh (Istio/Linkerd) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# ADIM 1: Cluster + Istio kurulumu
# ------------------------------------------------------------

k3d cluster create service-mesh-cluster --agents 1

brew install istioctl
istioctl install --set profile=demo -y
# SONUÇ: istiod, istio-ingressgateway, istio-egressgateway Running.

kubectl label namespace default istio-injection=enabled
# NOT: Bu label SADECE BUNDAN SONRA olusturulacak pod'lara sidecar
# ekletir, mevcut pod'lari otomatik degistirmez.

kubectl apply -f samples/addons/kiali.yaml
kubectl apply -f samples/addons/prometheus.yaml
kubectl apply -f samples/addons/grafana.yaml
kubectl -n istio-system get pods
# SONUÇ: istiod, kiali, prometheus, grafana Running.


# ------------------------------------------------------------
# ADIM 2: tracing-demo pod'larını mesh'e al - İLK DENEME HATALI
# ------------------------------------------------------------

kubectl apply -f k8s/backend.yaml
kubectl apply -f k8s/frontend.yaml
kubectl get pod backend-xxxx -o jsonpath='{.spec.containers[*].name}'
# HATA: sadece "backend" container'i goruldu, sidecar (istio-proxy)
# HIC EKLENMEMIS, 1/1 Running.
# SEBEP: namespace label'ini pod'lar zaten ayaktayken degil, ONCESINDE
# eklemis olsak bile, mevcut pod'lar zaten calisiyor oldugu icin
# webhook onlara dokunmadi, injection sadece YENI olusturulan pod'lara
# uygulanir.

# ÇÖZÜM: pod'lari (deployment'i) yeniden olustur
kubectl rollout restart deployment backend
kubectl rollout restart deployment frontend
kubectl get pods
# SONUÇ: backend-yyyy 2/2 Running, frontend-yyyy 2/2 Running,
# istio-proxy sidecar'i artik var.


# ------------------------------------------------------------
# ADIM 3: PeerAuthentication ile STRICT mTLS zorla
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT
EOF

# Mesh disinda, sidecar'siz bir pod'dan baglanmayi dene:
kubectl run plain-client --image=curlimages/curl -n kube-system \
  -it --rm --restart=Never -- curl -s -o /dev/null -w "%{http_code}\n" --max-time 3 http://backend.default:3000/health
# SONUÇ: curl: (56) Recv failure / boş cevap, bağlantı reddedildi,
# çünkü sidecar'sız pod mTLS handshake yapamıyor, STRICT mod bunu
# hiç kabul etmiyor.

# Mesh icinden (sidecar'li) bir pod'dan dene:
kubectl run mesh-client --image=curlimages/curl \
  -it --rm --restart=Never -- curl -s -o /dev/null -w "%{http_code}\n" --max-time 3 http://backend.default:3000/health
# SONUÇ: 200, mesh içi otomatik mTLS sorunsuz çalıştı.


# ------------------------------------------------------------
# ADIM 4: DestinationRule ile Circuit Breaker kur
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: backend-circuit-breaker
spec:
  host: backend.default.svc.cluster.local
  trafficPolicy:
    outlierDetection:
      consecutiveErrors: 5
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
EOF

# Backend'i bilerek sürekli 500 dönecek şekilde bozup art arda istek at:
for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code}\n" http://frontend:8080/; done
# SONUÇ: ilk ~5 istek 500 döndü, sonrasında istekler backend'e hiç
# gitmeden anında 503 (UF, upstream failure/eject) dönmeye başladı,
# devre kesildi (Open).

sleep 30
curl -s -o /dev/null -w "%{http_code}\n" http://frontend:8080/
# SONUÇ: 30 saniye sonra bir "deneme" isteği backend'e gitti (Half-Open),
# backend hâlâ bozuk olduğu için yine 500/503 alındı, devre tekrar kapandı.

# Backend'i düzelttikten sonra:
kubectl rollout undo deployment backend
sleep 30
curl -s -o /dev/null -w "%{http_code}\n" http://frontend:8080/
# SONUÇ: 200, deneme isteği bu sefer başarılı oldu, devre tam açıldı
# (Closed), normal trafiğe dönüldü.


# ------------------------------------------------------------
# ADIM 5: Kiali'de trafik akışını incele
# ------------------------------------------------------------

istioctl dashboard kiali &
# Kiali UI > Graph sekmesi:
# SONUÇ: frontend -> backend arasında bir çizgi, üzerinde kilit
# ikonu (mTLS aktif göstergesi), backend node'unda circuit breaker
# tetiklendiği dönemlerde kırmızı bir uyarı ikonu göründü.


# ------------------------------------------------------------
# ADIM 6: VirtualService ile Retry policy kur
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: backend-retry
spec:
  hosts:
  - backend.default.svc.cluster.local
  http:
  - route:
    - destination:
        host: backend.default.svc.cluster.local
    retries:
      attempts: 3
      perTryTimeout: 25ms
      retryOn: 5xx
EOF

# Backend'e %20 ihtimalle hata verecek bir bug enjekte et:
sed -i '' "s|res.json(r.data);|if (Math.random() < 0.2) return res.status(500).send('x'); res.json(r.data);|" tracing-demo/backend/index.js
docker build -t tracing-backend:v9 . && kubectl set image deploy/backend backend=tracing-backend:v9

for i in $(seq 1 50); do curl -s -o /dev/null -w "%{http_code}\n" http://frontend:8080/; done | sort | uniq -c
# HATA (ilk denemede): retries hiç işe yaramamış gibi göründü, hâlâ
# ~%20 oranında 500 alınıyordu.
# SEBEP: perTryTimeout 25ms olarak COK KISA verilmişti, backend'in
# normal cevap süresi (spotify-mock çağrısı + simülasyon) 25ms'den
# UZUN olduğu için her deneme "timeout" sayılıp retry tüketiliyordu,
# retryOn: 5xx'e hiç ulaşmadan 3 deneme de timeout'tan bitiyordu.

# ÇÖZÜM: perTryTimeout'u gerçekçi bir değere çek
kubectl patch virtualservice backend-retry --type merge -p '
spec:
  http:
  - route:
    - destination:
        host: backend.default.svc.cluster.local
    retries:
      attempts: 3
      perTryTimeout: 500ms
      retryOn: 5xx
'
for i in $(seq 1 50); do curl -s -o /dev/null -w "%{http_code}\n" http://frontend:8080/; done | sort | uniq -c
# SONUÇ: 50 istekten 50'si de 200 döndü (retry olmadan teorik olarak
# ~10 tanesi 500 dönmesi beklenirdi), retry mekanizması artık gerçekten
# çalışıyor, ilk hatalı denemeyi client hiç görmüyor.


# ------------------------------------------------------------
# ADIM 7: Linkerd ile karşılaştırma - AYRI CLUSTER GEREKTİ
# ------------------------------------------------------------
# İLK DENEME - HATA: ayni cluster'da Istio kuruluyken Linkerd de
# kurmaya calisildi.

linkerd check --pre
# HATA: "‼ no other Service Mesh installs" kontrolü FAILED,
# "Istio is already installed in the cluster" uyarisi.
# SEBEP: Iki service mesh ayni pod'lara ayni anda sidecar enjekte
# etmeye calisirsa (cift proxy) trafik tamamen bozulur, Linkerd
# bunu preflight check'te tespit edip kurulumu durduruyor.

# ÇÖZÜM: ayrı bir cluster'da dene
k3d cluster create linkerd-cluster
linkerd check --pre
# SONUÇ: preflight check gecti.
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check
# SONUÇ: kurulum basarili.

kubectl annotate namespace default linkerd.io/inject=enabled
kubectl apply -f k8s/backend.yaml k8s/frontend.yaml
kubectl get pods
# SONUÇ: 2/2 Running, linkerd-proxy sidecar'i eklendi.
# Kaynak kullanimi karsilastirmasi:
kubectl top pod -l app=backend
# SONUÇ: Istio+Envoy sidecar'i ~120Mi RAM, Linkerd (Rust, linkerd2-proxy)
# ~15Mi RAM kullaniyordu, Linkerd gozle gorulur sekilde daha hafif.


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# İki ayrı yaygın hataya düşüldü: (1) namespace injection label'ı
# mevcut pod'ları etkilemiyor, deployment restart gerekiyor, (2)
# perTryTimeout gerçekçi olmayan bir değerle retry mekanizmasını
# sessizce işe yaramaz hale getiriyor (her deneme timeout'tan
# tükeniyor). mTLS (STRICT PeerAuthentication) sidecar'sız trafiği
# tamamen reddetti, circuit breaker (outlierDetection) art arda 5
# hatadan sonra devreyi kesip half-open ile kademeli geri döndü.
# Linkerd karşılaştırmasında iki mesh'in aynı cluster'da birlikte
# kurulamayacağı (preflight check tarafından engellendi) ve Linkerd'in
# kaynak tüketiminin Istio'ya göre çok daha düşük olduğu doğrulandı.
