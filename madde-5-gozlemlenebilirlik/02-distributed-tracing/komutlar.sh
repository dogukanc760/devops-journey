#!/bin/bash
# ============================================================
# Distributed Tracing (Tempo/OpenTelemetry/Beyla) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# ADIM 1: Tempo kur, Grafana'ya bağla
# ------------------------------------------------------------

helm repo add grafana https://grafana.github.io/helm-charts
helm install tempo grafana/tempo -n monitoring
kubectl -n monitoring get pods -l app.kubernetes.io/name=tempo
# SONUÇ: tempo-0 Running.

# Grafana UI > Connections > Data Sources > Add > Tempo
# URL: http://tempo.monitoring:3100
# SONUÇ: "Data source is working"


# ------------------------------------------------------------
# ADIM 2: frontend -> backend -> spotify-mock zincirini kur
# ------------------------------------------------------------

mkdir -p tracing-demo/{frontend,backend,spotify-mock} && cd tracing-demo

cat > spotify-mock/index.js << 'EOF'
const express = require('express');
const app = express();
app.get('/track', (req, res) => setTimeout(() => res.json({track: "demo"}), 150));
app.listen(4000);
EOF

cat > backend/index.js << 'EOF'
const express = require('express');
const axios = require('axios');
const app = express();
app.get('/api/track', async (req, res) => {
  const r = await axios.get('http://spotify-mock:4000/track'); // ~150ms
  await new Promise(resolve => setTimeout(resolve, 2500));       // "DB yazma + logic" simülasyonu
  res.json(r.data);
});
app.listen(3000);
EOF

cat > frontend/index.js << 'EOF'
const express = require('express');
const axios = require('axios');
const app = express();
app.get('/', async (req, res) => {
  const r = await axios.get('http://backend:3000/api/track');
  res.json(r.data);
});
app.listen(8080);
EOF
# NOT: backend'de bilerek 150ms'lik gerçek API çağrısını 2500ms'lik
# "DB yazma + logic" simülasyonuyla AYNI SPAN'A gömeceğiz, mislabeling
# senaryosunu üretmek için.


# ------------------------------------------------------------
# ADIM 3: Backend'e OTel SDK ekle, TEK BÜYÜK span ile başla (bilerek yanlış)
# ------------------------------------------------------------

cd backend
npm install @opentelemetry/api @opentelemetry/sdk-node \
  @opentelemetry/exporter-trace-otlp-http @opentelemetry/auto-instrumentations-node

cat > tracing.js << 'EOF'
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({ url: 'http://tempo:4318/v1/traces' }),
});
sdk.start();
EOF

cat > index.js << 'EOF'
require('./tracing');
const { trace } = require('@opentelemetry/api');
const express = require('express');
const axios = require('axios');
const app = express();
const tracer = trace.getTracer('backend');

app.get('/api/track', async (req, res) => {
  const span = tracer.startSpan('spotify-api-call'); // TEK BUYUK SPAN
  const r = await axios.get('http://spotify-mock:4000/track');
  await new Promise(resolve => setTimeout(resolve, 2500)); // DB+logic de bu span'in icinde
  span.end();
  res.json(r.data);
});
app.listen(3000);
EOF

docker build -t tracing-backend:v1 . && kubectl apply -f ../k8s/backend.yaml
# İLK DENEME - HATA:
kubectl logs deploy/backend | tail -20
# HATA: "OTLPExporterError: connect ECONNREFUSED tempo:4318"
# SEBEP: Tempo Service'i port 4318'i (OTLP HTTP) DEĞİL, sadece 3100
# (Tempo'nun kendi query API'si) ve 4317'yi (OTLP gRPC) expose ediyordu.
kubectl get svc tempo -n monitoring -o jsonpath='{.spec.ports}'
# SONUÇ: portlar arasinda 4318 yoktu, sadece 3100/4317/9095 vardi.

# ÇÖZÜM: OTLP HTTP yerine OTLP gRPC exporter'a geç
cat > tracing.js << 'EOF'
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({ url: 'http://tempo:4317' }),
});
sdk.start();
EOF
npm install @opentelemetry/exporter-trace-otlp-grpc
docker build -t tracing-backend:v1 . && kubectl rollout restart deploy/backend
# SONUÇ: trace'ler Tempo'ya ulaşmaya başladı.


# ------------------------------------------------------------
# ADIM 4: Tek büyük span'ı Grafana'da incele, yanıltıcılığı gözle gör
# ------------------------------------------------------------

curl http://frontend/  # birkaç kez tetikle

# Grafana > Explore > Tempo, trace ID'ye tıkla:
# SONUÇ:
# frontend (2.9s)
#  └─ backend /api/track (2.85s)
#      └─ spotify-api-call (2.65s)   <-- TEK BUYUK SPAN
# Span adı "spotify-api-call" olduğu için ilk bakışta "demek Spotify
# API 2.65 saniye sürüyor" gibi görünüyor, ama gerçekte içinde 150ms
# gerçek HTTP çağrısı + 2500ms bizim kendi "DB+logic" simülasyonumuz
# gömülü, span bunu ayırt ettirmiyor, TAM konuştuğumuz mislabeling
# tuzağı.


# ------------------------------------------------------------
# ADIM 5: Span'ı child span'lara böl, gerçeği ortaya çıkar
# ------------------------------------------------------------

cat > index.js << 'EOF'
require('./tracing');
const { trace } = require('@opentelemetry/api');
const express = require('express');
const axios = require('axios');
const app = express();
const tracer = trace.getTracer('backend');

app.get('/api/track', async (req, res) => {
  const httpSpan = tracer.startSpan('http-call-to-spotify');
  const r = await axios.get('http://spotify-mock:4000/track');
  httpSpan.end();

  const logicSpan = tracer.startSpan('db-write-and-business-logic');
  await new Promise(resolve => setTimeout(resolve, 2500));
  logicSpan.end();

  res.json(r.data);
});
app.listen(3000);
EOF

docker build -t tracing-backend:v2 . && kubectl set image deploy/backend backend=tracing-backend:v2
curl http://frontend/

# Grafana > Explore > Tempo:
# SONUÇ:
# frontend (2.9s)
#  └─ backend /api/track (2.85s)
#      ├─ http-call-to-spotify (152ms)         <-- gerçek Spotify süresi
#      └─ db-write-and-business-logic (2.5s)   <-- asıl darboğaz BİZDE
# Gerçek darboğaz Spotify değil, bizim "DB yazma + logic" kodumuzmuş.
# Doğru instrumentation ile "Spotify yavaş" yanılgısı düzeltildi.


# ------------------------------------------------------------
# ADIM 6: Beyla ile aynı zinciri zero-instrumentation olarak izle
# ------------------------------------------------------------

helm repo add grafana https://grafana.github.io/helm-charts
helm install beyla grafana/beyla -n monitoring \
  --set config.data.discovery.services[0].k8s_namespace=default \
  --set config.data.otel_traces_export.endpoint=http://tempo.monitoring:4317

kubectl -n monitoring logs -l app.kubernetes.io/name=beyla --tail=20
# SONUÇ: Beyla, backend<->spotify-mock arasındaki HTTP çağrısını
# kendiliğinden (kod hiç değişmeden) yakaladı, Tempo'da ayrı bir
# trace olarak göründü: "GET /track (~150ms)".
# AMA: backend'in kendi içindeki "db-write-and-business-logic" (2.5s)
# HİÇ görünmedi, çünkü o adım hiçbir network syscall'ı üretmiyor
# (sadece bir setTimeout/CPU bekleme), Beyla'nın görebileceği bir
# sınır (syscall/paket) hiç oluşmuyor. Beyla'nın "kod içi mantığı
# göremem" sınırı canlı doğrulandı.


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# İlk denemede OTLP exporter'ı yanlış porta (4318 HTTP) yönlendirdik,
# Tempo Service sadece 4317 (gRPC) ve 3100'ü expose ediyordu, gRPC
# exporter'a geçince çözüldü. Tek büyük span ("spotify-api-call")
# gerçek Spotify süresini (150ms) kendi kodumuzun süresiyle (2.5s)
# karıştırıp yanıltıcı bir "Spotify yavaş" görünümü yarattı, child
# span'lara bölünce asıl darboğazın kendi kodumuzda olduğu net çıktı.
# Beyla aynı zinciri kod değiştirmeden izleyebildi ama sadece network
# çağrısını gördü, kod içi (CPU'da geçen) süreyi hiç yakalayamadı,
# OTel'in neden bazen zorunlu olduğunu somut olarak kanıtladı.
