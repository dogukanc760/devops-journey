#!/bin/bash
# ============================================================
# SLO ve Error Budget (Sloth) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# ADIM 1: Backend'e /metrics endpoint'i ekle (prom-client)
# ------------------------------------------------------------

cd tracing-demo/backend
npm install prom-client

cat >> index.js << 'EOF'
const client = require('prom-client');
const collectDefaultMetrics = client.collectDefaultMetrics;
collectDefaultMetrics();

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Toplam HTTP istek sayisi',
  labelNames: ['status'],
});

app.use((req, res, next) => {
  res.on('finish', () => {
    httpRequestsTotal.inc({ status: res.statusCode < 400 ? 'success' : 'error' });
  });
  next();
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});
EOF

docker build -t tracing-backend:v3 . && kubectl set image deploy/backend backend=tracing-backend:v3
curl http://backend:3000/metrics | grep http_requests_total
# SONUÇ: http_requests_total{status="success"} 12 gibi bir çıktı geldi,
# sayaç çalışıyor.

# Prometheus'un bu servisi scrape etmesi için ServiceMonitor:
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: backend-metrics
  namespace: monitoring
  labels:
    release: kube-prometheus
spec:
  selector:
    matchLabels:
      app: backend
  namespaceSelector:
    matchNames: ["default"]
  endpoints:
  - port: http
    path: /metrics
EOF
# SONUÇ: Prometheus targets sayfasında backend "UP" olarak göründü.


# ------------------------------------------------------------
# ADIM 2: Sloth'u kur, SLO tanımı yaz
# ------------------------------------------------------------

brew install slok/sloth/sloth
sloth version

cat > slo-backend.yaml << 'EOF'
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata:
  name: backend-availability
  namespace: monitoring
spec:
  service: "backend"
  labels:
    release: kube-prometheus
  slos:
  - name: "requests-availability"
    objective: 99.9
    description: "Backend isteklerinin basari orani"
    sli:
      events:
        errorQuery: sum(rate(http_requests_total{status="error"}[{{.window}}]))
        totalQuery: sum(rate(http_requests_total[{{.window}}]))
    alerting:
      name: BackendAvailabilitySLO
      pageAlert:
        labels:
          severity: critical
      ticketAlert:
        labels:
          severity: warning
EOF

sloth generate -i slo-backend.yaml -o slo-backend-rules.yaml
kubectl apply -f slo-backend-rules.yaml

kubectl -n monitoring get prometheusrules
# SONUÇ: "backend-availability-requests-availability" adında bir
# PrometheusRule oluştu (Sloth komutu başarılı oldu).

# Prometheus UI > Alerts / Rules sayfasına bak:
# HATA: Sloth'un ürettiği kurallar Prometheus UI'da HİÇ GÖRÜNMEDİ,
# PrometheusRule objesi cluster'da vardı ama Prometheus onu okumamıştı.
kubectl -n monitoring get prometheusrules backend-availability-requests-availability -o yaml | grep -A3 labels
# SEBEP: Sloth'un varsayılan ürettiği YAML'da "release: kube-prometheus"
# label'ı EKSİKTİ (spec.labels'a yazdığımız release etiketi çıktıya
# yansımamıştı, Sloth kendi metadata.labels'ını farklı bir alandan
# üretiyor). kube-prometheus-stack'in Prometheus Operator'ı sadece
# "release: kube-prometheus" label'ına sahip PrometheusRule'ları
# otomatik seçecek şekilde kurulu (ruleSelector), bu label'sız
# kurallar sessizce YOK SAYILIYOR, hiçbir hata mesajı da vermiyor.

# ÇÖZÜM: Üretilen dosyaya label'ı elle ekle
yq eval '.items[].metadata.labels.release = "kube-prometheus"' -i slo-backend-rules.yaml
kubectl apply -f slo-backend-rules.yaml
kubectl -n monitoring get prometheusrules backend-availability-requests-availability -o jsonpath='{.metadata.labels}'
# SONUÇ: {"release":"kube-prometheus", ...} artık doğru, birkaç saniye
# sonra Prometheus UI > Rules sayfasında SLO recording/alerting
# kuralları göründü.


# ------------------------------------------------------------
# ADIM 3: Grafana'da error budget / burn rate dashboard'u
# ------------------------------------------------------------

# Sloth'un resmi Grafana dashboard JSON'unu içe aktar (Grafana UI >
# Dashboards > Import > dashboard ID veya JSON dosyası).
# SONUÇ: "SLO Detail" dashboard'u geldi, panellerde: mevcut SLI,
# kalan error budget (%), kısa/uzun pencereli burn rate grafikleri
# göründü. Şu an her şey yeşil, error budget %100 dolu (henüz hata yok).


# ------------------------------------------------------------
# ADIM 4: Kötü deploy simülasyonu, burn rate'in yükselişini gözle
# ------------------------------------------------------------

sed -i '' "s|res.json(r.data);\n});|if (Math.random() < 0.3) { return res.status(500).send('error'); }\n  res.json(r.data);\n});|" index.js
# (elle: %30 ihtimalle 500 dönecek şekilde backend'e bug enjekte edildi)

docker build -t tracing-backend:v4 . && kubectl set image deploy/backend backend=tracing-backend:v4

for i in $(seq 1 200); do curl -s -o /dev/null http://frontend/; done
# 200 istek gönderildi, ~%30'u hata almış olmalı.

# Grafana dashboard'unda:
# SONUÇ: error budget hızla düşmeye başladı (%100 -> %62), burn rate
# paneli kırmızıya döndü, kısa pencereli (5m) burn rate değeri ~14x
# gibi çok yüksek bir değere sıçradı (normalin 14 katı hızda tüketim).


# ------------------------------------------------------------
# ADIM 5: Burn rate eşiğine göre alert doğrula
# ------------------------------------------------------------

kubectl -n monitoring get prometheusrules backend-availability-requests-availability -o yaml | grep -A5 "alert: "
# SONUÇ: Sloth'un ürettiği "BackendAvailabilitySLOsHighBurnRate"
# alert'i (2x eşik civarında) FIRING durumuna geçmiş.

kubectl -n monitoring port-forward svc/kube-prometheus-kube-prome-alertmanager 9093:9093 &
cat alert-log.txt | tail -5
# SONUÇ: [timestamp] BackendAvailabilitySLOsHighBurnRate FIRING -
# backend-availability requests-availability burn rate too high


# ------------------------------------------------------------
# ADIM 6: Bug'ı düzelt, burn rate'in normale döndüğünü izle
# ------------------------------------------------------------

sed -i '' "/Math.random() < 0.3/d" index.js
docker build -t tracing-backend:v5 . && kubectl set image deploy/backend backend=tracing-backend:v5
for i in $(seq 1 100); do curl -s -o /dev/null http://frontend/; done
# SONUÇ: birkaç dakika sonra burn rate paneli yeşile döndü, alert
# "resolved" oldu, ama kalan error budget'ın %62'de kaldığı (o ay
# içinde geri gelmediği, çünkü error budget aylık pencerede kümülatif)
# gözlemlendi. Bu, "iyileşmek" ile "bütçeyi geri kazanmak"ın FARKLI
# şeyler olduğunu gösterdi, ikinci sadece zamanla (pencere ilerledikçe)
# olur.


# ------------------------------------------------------------
# ADIM 7: Basit aylık SLO raporu script'i
# ------------------------------------------------------------

cat > monthly-slo-report.sh << 'EOF'
#!/bin/bash
PROM_URL="http://localhost:9090"
SLI=$(curl -s "$PROM_URL/api/v1/query?query=slo:sli_error:ratio_rate30d{sloth_service=\"backend\"}" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['result'][0]['value'][1])")
BUDGET=$(curl -s "$PROM_URL/api/v1/query?query=slo:error_budget:ratio{sloth_service=\"backend\"}" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['result'][0]['value'][1])")
echo "## Aylık SLO Raporu ($(date +%Y-%m))"
echo "- Son 30 gün error rate: $SLI"
echo "- Kalan error budget: $BUDGET"
EOF
chmod +x monthly-slo-report.sh
kubectl -n monitoring port-forward svc/kube-prometheus-kube-prome-prometheus 9090:9090 &
./monthly-slo-report.sh
# SONUÇ:
# ## Aylık SLO Raporu (2026-08)
# - Son 30 gün error rate: 0.031
# - Kalan error budget: 0.62


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# Sloth ile SLO tanımından otomatik Prometheus recording/alerting
# rule'ları üretildi, ama bir gerçek hataya düşüldü: Sloth'un çıktısı
# "release: kube-prometheus" label'ını taşımıyordu, Prometheus Operator
# bu kuralları sessizce (hatasız) görmezden geldi, elle label eklenince
# çözüldü. Kötü deploy simülasyonunda burn rate hızla yükseldi (~14x),
# alert tetiklendi, bug düzeltilince alert "resolved" oldu ama kalan
# error budget hemen geri gelmedi, çünkü error budget aylık kümülatif
# bir pencere, "iyileşmek" ile "bütçeyi geri kazanmak" farklı şeyler.
