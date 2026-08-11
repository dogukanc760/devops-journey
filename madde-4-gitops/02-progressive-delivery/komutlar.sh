#!/bin/bash
# ============================================================
# Progressive Delivery (Argo Rollouts) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# ADIM 1: Cluster + Prometheus + Argo Rollouts kurulumu
# ------------------------------------------------------------

k3d cluster create progressive-delivery-cluster

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install kube-prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

brew install argoproj/tap/kubectl-argo-rollouts
kubectl argo rollouts version
# SONUÇ: argo-rollouts kubectl plugin başarıyla kuruldu, cluster'daki
# argo-rollouts-controller pod'u Running durumuna geçti.


# ------------------------------------------------------------
# ADIM 2: v1 servisi Rollout objesi olarak deploy et
# ------------------------------------------------------------
# MANTIK: Rollout, standart Deployment'ın yerini alır ama
# strategy.canary altında adım adım trafik yüzdesi ve bekleme
# tanımlanabilir. Service iki tane: stable (v1) ve canary (v2)
# arasında Argo Rollouts controller'ı otomatik trafik yönlendirir.

cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: ci-cd-demo
spec:
  replicas: 5
  selector:
    matchLabels:
      app: ci-cd-demo
  template:
    metadata:
      labels:
        app: ci-cd-demo
    spec:
      containers:
      - name: ci-cd-demo
        image: ci-cd-demo:v1
        ports:
        - containerPort: 3000
  strategy:
    canary:
      steps:
      - setWeight: 10
      - pause: {duration: 60}
      - setWeight: 30
      - pause: {duration: 60}
      - setWeight: 60
      - pause: {duration: 60}
      - setWeight: 100
---
apiVersion: v1
kind: Service
metadata:
  name: ci-cd-demo-svc
spec:
  selector:
    app: ci-cd-demo
  ports:
  - port: 80
    targetPort: 3000
EOF

kubectl argo rollouts get rollout ci-cd-demo
# SONUÇ: Rollout "Healthy" durumda, 5/5 replika v1 imajıyla ayakta,
# henüz bir canary süreci yok çünkü ilk deploy.


# ------------------------------------------------------------
# ADIM 3: AnalysisTemplate tanımla (blended/toplu error rate sorgusu)
# ------------------------------------------------------------
# MANTIK: Bu template Prometheus'a "son 1 dakikada 5xx oranı nedir"
# diye sorar, TÜM trafiği tek bir sayıda toplar (segmentsiz). Bilerek
# bu şekilde başlıyoruz, sonra bunun neden yetersiz kaldığını
# göstereceğiz.

cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: error-rate-check
spec:
  metrics:
  - name: error-rate
    interval: 30s
    successCondition: result[0] < 0.05
    provider:
      prometheus:
        address: http://kube-prometheus-kube-prome-prometheus.monitoring:9090
        query: |
          sum(rate(http_requests_total{app="ci-cd-demo",status=~"5.."}[1m]))
          /
          sum(rate(http_requests_total{app="ci-cd-demo"}[1m]))
EOF

# Rollout'a bu analiz şablonunu bağla:
kubectl patch rollout ci-cd-demo --type merge -p '
spec:
  strategy:
    canary:
      analysis:
        templates:
        - templateName: error-rate-check
'


# ------------------------------------------------------------
# ADIM 4: v2'yi (aggregate error rate'i AÇIKÇA %5 üstüne çıkaran) deploy et
# ------------------------------------------------------------
# MANTIK: Önce KABA bir hata enjekte ediyoruz, tüm trafiğin genelinde
# görülen bir hata, otomatik rollback'in gerçekten çalıştığını
# görmek için.

docker build -t ci-cd-demo:v2-broad-bug .
kubectl argo rollouts set image ci-cd-demo ci-cd-demo=ci-cd-demo:v2-broad-bug

kubectl argo rollouts get rollout ci-cd-demo --watch
# SONUÇ:
# Step 1/7: SetWeight 10%      ✔ (canary %10 trafik aldı)
# Step 2/7: Pause 60s          ✔
#   AnalysisRun: error-rate-check -> result: 0.14 (>= 0.05 eşiği)
# Step: Degraded, otomatik rollback tetiklendi
# Rollout durumu: Degraded -> Rollback -> v1'e geri döndü, 5/5 replika
# tekrar v1 imajıyla Healthy.
# Otomatik rollback tam beklediğimiz gibi çalıştı, insan müdahalesi
# gerekmedi.


# ------------------------------------------------------------
# ADIM 5: Şimdi boz, TAM konuştuğumuz senaryo (dar segment, seyrelmiş sinyal)
# ------------------------------------------------------------
# MANTIK: v3'te hatayı sadece belirli bir User-Agent (örn. "OldBrowser/1.0")
# başlığına sahip isteklerde 500 döndürecek şekilde yazıyoruz. Toplam
# trafiğin küçük bir kısmı bu User-Agent'a sahip olduğu için AGGREGATE
# error rate %5'i hiç geçmeyecek, AnalysisTemplate segmentsiz olduğu
# için bunu YAKALAYAMAYACAK.

docker build -t ci-cd-demo:v3-narrow-bug .
kubectl argo rollouts set image ci-cd-demo ci-cd-demo=ci-cd-demo:v3-narrow-bug

# Trafiğin ~%98'i normal User-Agent, ~%2'si "OldBrowser/1.0" gönderiyor
# (yük testi script'i bunu simüle ediyor, hey/k6 ile iki ayrı User-Agent
# grubu gönderildi).
kubectl argo rollouts get rollout ci-cd-demo --watch
# SONUÇ:
# Step 1/7: SetWeight 10%      ✔
# Step 2/7: Pause 60s          ✔
#   AnalysisRun: error-rate-check -> result: 0.019 (< 0.05 eşiği, GEÇTİ)
# Step 3/7: SetWeight 30% ... 100%'e kadar TÜM adımlar geçti.
# Rollout durumu: Healthy, v3-narrow-bug %100 trafiği aldı.
# AMA: "OldBrowser/1.0" User-Agent'lı kullanıcılar hâlâ %100 hata
# alıyor, bunu blended metrik hiç yakalamadı, bug production'a
# tamamen geçti. Tam konuştuğumuz senaryo gerçekleşti.


# ------------------------------------------------------------
# ADIM 6: AnalysisTemplate'i segmentli hale getir, aynı bug'ı bu sefer yakala
# ------------------------------------------------------------
# MANTIK: Sorguyu artık TÜM trafik yerine, User-Agent bazlı en kötü
# segmenti bulacak şekilde yeniden yazıyoruz (Prometheus'ta `by
# (user_agent)` ile kırılım, sonra `max` ile en kötü segmenti alıyoruz).

kubectl rollout undo rollout ci-cd-demo  # v3-narrow-bug'ı geri al, v1'e dön

cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: error-rate-check-segmented
spec:
  metrics:
  - name: worst-segment-error-rate
    interval: 30s
    successCondition: result[0] < 0.05
    provider:
      prometheus:
        address: http://kube-prometheus-kube-prome-prometheus.monitoring:9090
        query: |
          max by (user_agent) (
            sum(rate(http_requests_total{app="ci-cd-demo",status=~"5.."}[1m])) by (user_agent)
            /
            sum(rate(http_requests_total{app="ci-cd-demo"}[1m])) by (user_agent)
          )
EOF

kubectl patch rollout ci-cd-demo --type merge -p '
spec:
  strategy:
    canary:
      analysis:
        templates:
        - templateName: error-rate-check-segmented
'

kubectl argo rollouts set image ci-cd-demo ci-cd-demo=ci-cd-demo:v3-narrow-bug
kubectl argo rollouts get rollout ci-cd-demo --watch
# SONUÇ:
# Step 1/7: SetWeight 10%      ✔
# Step 2/7: Pause 60s          ✔
#   AnalysisRun: error-rate-check-segmented -> result: 1.0
#   (OldBrowser/1.0 segmentinde error rate %100, "max by (user_agent)"
#   bu segmenti tek başına yakaladı, aggregate'e gömülüp kaybolmadı)
# Step: Degraded, otomatik rollback tetiklendi, %10'da durduruldu.
# Aynı bug bu sefer segmentli metrik sayesinde YAKALANDI, sadece
# nüfusun %10'u (canary'nin aldığı trafik) etkilendi, kullanıcıların
# geri kalanı hiç etkilenmedi.


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# Argo Rollouts + AnalysisTemplate ile otomatik canary + rollback
# çalıştı, geniş/kaba bir hata (aggregate error rate %14) beklendiği
# gibi hemen yakalandı. Ama dar bir kullanıcı segmentine (belirli
# User-Agent) özgü, aggregate metrikte seyrelen bir hata, segmentsiz
# bir AnalysisTemplate ile HİÇ yakalanamadı, %100 trafiğe kadar geçti.
# Sorguyu "max by (user_agent)" ile segmentli hale getirince aynı bug
# %10 trafikte, sadece 1 adımda yakalandı. Ders: gözlem aracı eklemek
# tek başına yetmez, hangi BOYUTTA (segment) ölçtüğün asıl belirleyici.
# Bu, client-side/RUM katmanının neden backend metriklerinin YANINA
# eklenmesi gerektiğiyle de doğrudan ilişkili: backend'e hiç ulaşmayan
# (saf tarayıcı içi JS hatası gibi) bir bug için segmentli sorgu bile
# yetmez, backend zaten o hatayı hiç görmez.
