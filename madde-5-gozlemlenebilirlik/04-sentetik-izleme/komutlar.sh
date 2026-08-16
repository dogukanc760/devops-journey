#!/bin/bash
# ============================================================
# Sentetik İzleme (Synthetic Monitoring) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# ADIM 1: Bilerek SIĞ bir /health endpoint'i ekle, Blackbox Exporter kur
# ------------------------------------------------------------

cd tracing-demo/backend
cat >> index.js << 'EOF'
app.get('/health', (req, res) => res.status(200).send('OK')); // sadece process ayakta mi, baska hicbir kontrol yok
EOF
docker build -t tracing-backend:v6 . && kubectl set image deploy/backend backend=tracing-backend:v6

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install blackbox prometheus-community/prometheus-blackbox-exporter -n monitoring

cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: Probe
metadata:
  name: backend-health-probe
  namespace: monitoring
  labels:
    release: kube-prometheus
spec:
  interval: 30s
  module: http_2xx
  prober:
    url: blackbox-prometheus-blackbox-exporter.monitoring:19115
  targets:
    staticConfig:
      static:
      - http://backend.default:3000/health
EOF
# NOT: gecen konudan ders alarak "release: kube-prometheus" label'ini
# EN BASTAN ekledik, Prometheus Operator'in bu Probe'u sessizce yok
# saymasini engellemek icin.

kubectl -n monitoring get probes
# SONUÇ: backend-health-probe olusturuldu, Prometheus targets
# sayfasinda blackbox probe'u "UP" gorundu, /health surekli 200
# donuyor.


# ------------------------------------------------------------
# ADIM 2: k6 ile gerçek bir login/senaryo testi yaz
# ------------------------------------------------------------

mkdir -p synthetic && cat > synthetic/login-check.js << 'EOF'
import http from 'k6/http';
import { check } from 'k6';

export default function () {
  const res = http.get('http://frontend.default:8080/');
  check(res, {
    'status 200': (r) => r.status === 200,
    'track alani dolu': (r) => JSON.parse(r.body).track && JSON.parse(r.body).track.length > 0,
  });
}
EOF

brew install k6
k6 run synthetic/login-check.js
# SONUÇ: 2 check de PASS, "track alani dolu" true, senaryo saglikli.


# ------------------------------------------------------------
# ADIM 3: k6 sonucunu Prometheus'a yazdırmaya çalış - HATA
# ------------------------------------------------------------

k6 run --out experimental-prometheus-rw synthetic/login-check.js
# HATA: "ERRO[0000] unrecognised output "experimental-prometheus-rw""
# SEBEP: Homebrew'un standart k6 binary'si Prometheus remote-write
# cikisini icermiyor, bu ozellik ayri bir extension (xk6-output-
# prometheus-remote) ile derlenmis ozel bir k6 build'i gerektiriyor.

# ÇÖZÜM: xk6 ile Prometheus remote-write destekli özel k6 build'i
go install go.k6.io/xk6/cmd/xk6@latest
xk6 build --with github.com/grafana/xk6-output-prometheus-remote
./k6 run -o experimental-prometheus-rw \
  --tag testid=login-check \
  synthetic/login-check.js
# SONUÇ: bu sefer calisti, k6_http_reqs_total, k6_checks_total gibi
# metrikler Prometheus remote-write endpoint'ine yazildi.
# k8s'te kalici calismasi icin bu ozel binary'yi Docker image'ina
# gomup CronJob icinde kullandik.


# ------------------------------------------------------------
# ADIM 4: k6 testini her 1 dakikada çalışacak CronJob olarak kur
# ------------------------------------------------------------

cat > synthetic/Dockerfile << 'EOF'
FROM golang:1.22 AS build
RUN go install go.k6.io/xk6/cmd/xk6@latest
RUN xk6 build --with github.com/grafana/xk6-output-prometheus-remote --output /k6

FROM alpine
COPY --from=build /k6 /usr/bin/k6
COPY login-check.js /login-check.js
EOF
docker build -t synthetic-k6:v1 synthetic/

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: login-synthetic-check
spec:
  schedule: "*/1 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
          - name: k6
            image: synthetic-k6:v1
            args: ["run", "-o", "experimental-prometheus-rw",
                   "--tag", "testid=login-check", "/login-check.js"]
            env:
            - name: K6_PROMETHEUS_RW_SERVER_URL
              value: "http://kube-prometheus-kube-prome-prometheus.monitoring:9090/api/v1/write"
EOF

kubectl get cronjob login-synthetic-check
# SONUÇ: her dakika bir Job tetikleniyor, Prometheus'ta k6_checks_total
# metriği düzenli aralıklarla güncelleniyor.


# ------------------------------------------------------------
# ADIM 5: Backend'e bug enjekte et, sığ health check ile k6'nın ayrıştığını gözle
# ------------------------------------------------------------

sed -i '' "s|res.json(r.data);|res.json({});  \/\/ BILEREC BOS DONDUK|" index.js
docker build -t tracing-backend:v7 . && kubectl set image deploy/backend backend=tracing-backend:v7

# Blackbox Exporter tarafı:
# SONUÇ: /health hâlâ 200 dönüyor, Prometheus'ta probe_success=1,
# "her şey yeşil" görünüyor.

# k6 CronJob tarafı (1 dakika sonra):
kubectl logs job/login-synthetic-check-<son-calisan>
# SONUÇ:
#   ✗ track alani dolu
#     ↳  0% — ✓ 0 / ✗ 1
# k6 checks_total{check="track alani dolu",result="fail"} metriği
# Prometheus'ta arttı, TAM konuştuğumuz sığ health check tuzağı canlı
# gözlemlendi: /health yeşil, gerçek senaryo kırmızı.


# ------------------------------------------------------------
# ADIM 6: k6 fail'ini alert'e bağla, Alertmanager'a düşür
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: synthetic-login-alert
  namespace: monitoring
  labels:
    release: kube-prometheus
spec:
  groups:
  - name: synthetic
    rules:
    - alert: SyntheticLoginCheckFailing
      expr: increase(k6_checks_total{check="track alani dolu",result="fail"}[5m]) > 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Sentetik login senaryosu son 5 dakikada basarisiz oldu"
        runbook_url: "https://github.com/<kullanici-adi>/devops-journey/blob/main/RUNBOOK-login-basarisiz.md"
EOF

cat alert-log.txt | tail -3
# SONUÇ: [timestamp] SyntheticLoginCheckFailing FIRING - Sentetik
# login senaryosu son 5 dakikada basarisiz oldu


# ------------------------------------------------------------
# ADIM 7: Runbook yaz
# ------------------------------------------------------------

cat > RUNBOOK-login-basarisiz.md << 'EOF'
# Runbook: SyntheticLoginCheckFailing

1. Grafana > "Synthetic Monitoring" dashboard'unu ac, hangi zamandan
   beri fail oldugunu gor (tek seferlik mi surekli mi).
2. `/health` yesil ama bu alert kirmizi ise, sorun ALTYAPIDA DEGIL,
   UYGULAMA MANTIGINDA, dogrudan backend loglarina bak (Loki:
   {app="backend"} |= "ERROR").
3. Son deploy'u kontrol et: `kubectl rollout history deploy/backend`,
   fail baslangic zamani bir deploy'la cakisiyor mu?
4. Cakisiyorsa: `kubectl rollout undo deploy/backend` ile ONCEKI
   surume don, senaryo tekrar PASS oluyor mu diye k6'yi elle calistir.
5. Cakismiyorsa: DB/dis servis (spotify-mock) baglantisini kontrol et.
6. 15 dakika icinde cozulmuyorsa: #incident kanalinda escalation yap,
   yalniz kalma.
EOF
git add RUNBOOK-login-basarisiz.md && git commit -q -m "add login failure runbook" && git push


# ------------------------------------------------------------
# ADIM 8: Bug'ı düzelt, bakım penceresi (silence) senaryosunu test et
# ------------------------------------------------------------

sed -i '' "s|res.json({});  // BILEREC BOS DONDUK|res.json(r.data);|" index.js
docker build -t tracing-backend:v8 .

# Deploy oncesi bilinen bir "gecici kesinti" icin silence tanimla:
kubectl -n monitoring port-forward svc/kube-prometheus-kube-prome-alertmanager 9093:9093 &
amtool silence add alertname=SyntheticLoginCheckFailing \
  --duration=5m --comment="planli deploy, gecici alarm bastirma" \
  --alertmanager.url=http://localhost:9093

kubectl set image deploy/backend backend=tracing-backend:v8
# Deploy sirasinda pod birkac saniye Not Ready oldugu icin k6 muhtemelen
# 1 kez fail edecekti, ama silence aktifken alert-log.txt'e HICBIR
# SATIR DUSMEDI.
# SONUÇ: cat alert-log.txt | tail -3 -> deploy anindaki fail hic
# gorunmuyor, silence calisiyor.

sleep 320  # 5 dakikalik silence suresi doldu
for i in $(seq 1 5); do kubectl delete pod -l app=backend --grace-period=0 --force 2>/dev/null; sleep 15; done
# Silence bittikten sonra bilerek tekrar bir kesinti simulasyonu (pod
# zorla siliniyor, birkac saniye 503/connection refused olusuyor):
cat alert-log.txt | tail -3
# SONUÇ: bu sefer alert GERCEKTEN dustu, silence suresi dolduktan
# sonra sistem tekrar normal alarm uretir hale geldi.


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# Blackbox Exporter'ın sığ /health kontrolü hep yeşil kaldı, k6'nın
# gerçek senaryo testi ise uygulama mantığındaki bugı yakaladı, bu
# fark "altyapı sağlıklı" ile "kullanıcı işini yapabiliyor" arasındaki
# gerçek boşluğu somut olarak gösterdi. Yol boyunca standart k6
# binary'sinin Prometheus remote-write desteklemediği (xk6 ile özel
# build gerektiği) ortaya çıktı. Runbook, alarm gelince "önce /health'e
# değil doğrudan loglara/deploy geçmişine bak" gibi somut, önceden
# düşünülmüş adımlar sağladı. Silence testinde, planlı bir deploy
# sırasında alarmın bilerek bastırılıp süre dolunca otomatik geri
# geldiği doğrulandı, "bakım penceresi" mekanizmasının gerçekten
# çalıştığı kanıtlandı.
