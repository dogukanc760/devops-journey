#!/bin/bash
# ============================================================
# Chaos Engineering (Chaos Mesh) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# ADIM 1: Chaos Mesh kurulumu
# ------------------------------------------------------------

helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh -n chaos-mesh \
  --create-namespace --set dashboard.create=true
kubectl -n chaos-mesh get pods
# SONUÇ: chaos-controller-manager, chaos-daemon (her node'da bir tane),
# chaos-dashboard Running.


# ------------------------------------------------------------
# ADIM 2: Dar hedefli PodChaos, tek replika öldür
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: backend-kill-one
spec:
  action: pod-kill
  mode: one
  duration: "60s"
  selector:
    namespaces: [default]
    labelSelectors:
      app: backend
EOF

kubectl get pods -l app=backend -w &
sleep 5
kubectl get pods -l app=backend
# SONUÇ: bir replika (backend-abc123) Terminating oldu, deployment
# hemen yerine yeni bir pod olusturdu, diger replikalar hic etkilenmedi,
# frontend'den atilan isteklerde kisa bir 503 dalgasi disinda kesinti
# gozlenmedi.

for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code}\n" http://frontend:8080/; done | sort | uniq -c
# SONUÇ: 20 istekten 18'i 200, 2'si 503 (tam pod degisimi anina denk
# gelen istekler), sistem kendini birkac saniyede toparladi.


# ------------------------------------------------------------
# ADIM 3: NetworkChaos ile gecikme enjekte et - RETRY İLE ÇAKIŞMA
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: backend-delay
spec:
  action: delay
  mode: all
  duration: "120s"
  selector:
    namespaces: [default]
    labelSelectors:
      app: backend
  delay:
    latency: "2s"
EOF

for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://frontend:8080/; done | sort | uniq -c
# HATA: 20 istekten 20'si de 500/504 dondu, retry policy (Service Mesh
# subtopic'inde kurulan) hicbir isteği kurtaramadi.
# SEBEP: VirtualService'teki perTryTimeout: 500ms, enjekte edilen 2
# saniyelik gecikmeden cok daha kisa, her deneme retryOn: 5xx'e hic
# ulasmadan "timeout" sayilip tukeniyordu, tipki Service Mesh
# subtopic'indeki ilk hataya benzer bir mekanizma ama bu sefer sebep
# gercek bir kod hatasi degil, chaos deneyinin kendisiydi.

# ÇÖZÜM: bu deney sureligine perTryTimeout'u gecikmeyi tolere edecek
# sekilde gecici olarak yukselt
kubectl patch virtualservice backend-retry --type merge -p '
spec:
  http:
  - route:
    - destination:
        host: backend.default.svc.cluster.local
    retries:
      attempts: 3
      perTryTimeout: 3s
      retryOn: 5xx
'
for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code}\n" --max-time 8 http://frontend:8080/; done | sort | uniq -c
# SONUÇ: 20 istekten 20'si de 200 dondu (gecikmeli de olsa), retry
# gercek gecikmeyi tolere edip basarili sonuc dondurdu.

kubectl delete networkchaos backend-delay
# NetworkChaos deneyi sonlandi, gecikme kalkti.


# ------------------------------------------------------------
# ADIM 4: Bilerek geniş blast radius (mode: all) - TAM KESİNTİ
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: backend-kill-all
spec:
  action: pod-kill
  mode: all
  duration: "30s"
  selector:
    namespaces: [default]
    labelSelectors:
      app: backend
EOF

for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code}\n" --max-time 3 http://frontend:8080/; done | sort | uniq -c
# HATA: 20 istekten 20'si de 503 dondu, TAM kesinti yasandi.
# SEBEP: mode: all ile backend'in TUM repliklari ayni anda oldurulunce,
# circuit breaker'in yonlendirebilecegi hicbir saglikli replika kalmadi,
# koruma mekanizmasi bu durumda hicbir ise yaramadi, bu blast radius'un
# neden dar tutulmasi gerektiginin canli kaniti oldu.


# ------------------------------------------------------------
# ADIM 5: Deneyi elle durdurmaya çalış - CR "Terminating"de takılı kaldı
# ------------------------------------------------------------

kubectl delete podchaos backend-kill-all
# HATA: komut takildi, birkac saniye sonra ayri bir terminalde:
kubectl get podchaos backend-kill-all
# SONUÇ: STATUS "Terminating", silinmiyor.
# SEBEP: hedef pod'lar CR silinmeden once zaten Kubernetes tarafindan
# otomatik olarak yeniden zamanlanip degismisti (deployment kendi
# pod'larini yeniledi), Chaos Mesh finalizer'i temizlemeye calistigi
# orijinal pod referanslarini bulamadi, CR'i serbest birakamadi.

# ÇÖZÜM: finalizer'ı elle temizle
kubectl patch podchaos backend-kill-all -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl get podchaos backend-kill-all
# SONUÇ: NotFound, CR basariyla silindi, sistem normal duruma dondu.

kubectl get pods -l app=backend
# SONUÇ: tum repliklar Running, frontend'den atilan istekler tekrar
# %100 200 donuyor.


# ------------------------------------------------------------
# ADIM 6: Güvenli, dar hedefli son bir deney ile kapat
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: backend-kill-safe
spec:
  action: pod-kill
  mode: fixed-percent
  value: "25"
  duration: "45s"
  selector:
    namespaces: [default]
    labelSelectors:
      app: backend
EOF

kubectl get pods -l app=backend
# SONUÇ: repliklarin sadece %25'i (4 repladan 1 tanesi) etkilendi,
# diger 3 replika kesintisiz calismaya devam etti, frontend'den atilan
# isteklerde hicbir 503 gozlenmedi, dar blast radius'un beklenen
# koruyucu etkisi net gorundu.

kubectl delete podchaos backend-kill-safe
# SONUÇ: deney duration'i zaten dolmustu, CR temiz sekilde silindi,
# finalizer sorunu bu sefer yasanmadi.


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# Dar hedefli (mode: one, fixed-percent) deneyler sistemin dayaniklilik
# mekanizmalarinin gercekten calistigini kanitladi, kisa bir 503
# dalgasi disinda kesinti olmadi. Genis blast radius'lu (mode: all)
# deney ise circuit breaker'a ragmen tam kesintiye yol acti, cunku
# yonlendirilecek hicbir saglikli replika kalmamisti. NetworkChaos ile
# enjekte edilen gecikme, Service Mesh subtopic'indeki perTryTimeout
# ayarinin gercek dunya kosullarinda ne kadar kirilgan olabildigini
# gosterdi. Deneyi elle durdurmaya calisirken CR'in finalizer yuzunden
# Terminating'de takili kalmasi, "acil durdur" mekanizmasinin her zaman
# aninda calismayabilecegini, elle mudahale gerekebilecegini ortaya
# koydu.
