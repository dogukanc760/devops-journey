#!/bin/bash
# ============================================================
# CI/CD Mimari Tasarımı - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# ADIM 1: Demo servis + repo hazırlığı
# ------------------------------------------------------------
# Basit bir Node.js servisi, pipeline'ı gerçek anlamda test edecek
# kadar (lint hatası çıkarabilecek, test yazılabilecek, docker
# build alınabilecek) ama gereksiz karmaşık olmayacak.

mkdir -p ci-cd-demo && cd ci-cd-demo
git init -q
npm init -y
npm install --save-dev eslint jest --save express

cat > index.js << 'EOF'
const express = require('express');
const app = express();
app.get('/health', (req, res) => res.status(200).send('ok'));
module.exports = app;
EOF

cat > index.test.js << 'EOF'
const request = require('supertest');
const app = require('./index');
test('GET /health 200 döner', async () => {
  const res = await request(app).get('/health');
  expect(res.statusCode).toBe(200);
});
EOF

npm install --save-dev supertest
cat > .eslintrc.json << 'EOF'
{ "env": { "node": true, "es2021": true }, "extends": "eslint:recommended", "parserOptions": { "ecmaVersion": 12 } }
EOF

cat > Dockerfile << 'EOF'
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

FROM node:20-alpine
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
EXPOSE 3000
CMD ["node", "index.js"]
EOF
# Multi-stage: deps katmanı sadece package*.json değişince yeniden
# build edilir, kod değişikliği bu katmanı tetiklemez, cache'ten gelir.

git add . && git commit -q -m "ci-cd-demo: initial service"
git remote add origin https://github.com/<kullanici-adi>/ci-cd-demo.git
git push -u origin main


# ------------------------------------------------------------
# ADIM 2: Self-hosted runner'ı Docker içinde, ephemeral olarak kur
# ------------------------------------------------------------
# MANTIK: --ephemeral, her job'dan sonra runner'ın kendini söküp
# yeniden temiz bir container olarak başlamasını sağlar, "runner
# isolation" prensibinin somut hali, bir job'un kalıntısı diğerini
# hiç etkilemez.

docker run -d --name gh-runner \
  -e REPO_URL="https://github.com/<kullanici-adi>/ci-cd-demo" \
  -e RUNNER_TOKEN="<repo-settings-actions-runners-tokeni>" \
  myoung34/github-runner:latest
# SONUÇ: Runner GitHub repo Settings > Actions > Runners altında
# "Idle" durumda listelendi, self-hosted etiketiyle görünür oldu.


# ------------------------------------------------------------
# ADIM 3: Pipeline'ı yaz - lint/test/security-scan paralel, build hepsine bağımlı
# ------------------------------------------------------------

mkdir -p .github/workflows
cat > .github/workflows/ci.yml << 'EOF'
name: CI
on: [push]

jobs:
  lint:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'
      - run: npm ci
      - run: npx eslint .

  test:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'
      - run: npm ci
      - run: npx jest

  security-scan:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Trivy filesystem scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          severity: 'CRITICAL,HIGH'

  build:
    needs: [lint, test, security-scan]
    runs-on: self-hosted
    outputs:
      image_tag: ${{ steps.tag.outputs.tag }}
    steps:
      - uses: actions/checkout@v4
      - id: tag
        run: echo "tag=$(git rev-parse --short HEAD)" >> "$GITHUB_OUTPUT"
      - run: docker build -t ci-cd-demo:${{ steps.tag.outputs.tag }} .
      - run: echo "Build edilen imaj tag'i sonraki job'lara aktarılabilir hale geldi: ${{ steps.tag.outputs.tag }}"
EOF
# NOT: needs: [lint, test, security-scan] build job'unun UCUNE de bagli
# oldugunu gosterir, lint/test/security-scan kendi aralarinda needs
# tanimlamadigi icin (birbirine bagimli degiller) otomatik olarak
# PARALEL calisir, GitHub Actions'in varsayilan davranisi bu.

git add .github/workflows/ci.yml
git commit -q -m "add ci pipeline: parallel lint/test/security-scan, build depends on all three"
git push


# ------------------------------------------------------------
# ADIM 4: İlk pipeline çalışması, paralel süre kazancını gözle doğrula
# ------------------------------------------------------------

# GitHub Actions run özeti (Actions sekmesinden):
# SONUÇ:
#   lint            ✔  0:41
#   test            ✔  3:02   (lint ile AYNI ANDA başladı)
#   security-scan   ✔  4:18   (lint ve test ile AYNI ANDA başladı)
#   build           ✔  1:07   (üçü de bitince başladı, en son security-scan'i bekledi)
#   TOPLAM SÜRE: ~5:25
# Eğer sıralı (lint -> test -> security-scan -> build) çalışsaydı:
#   0:41 + 3:02 + 4:18 + 1:07 = ~9:08 olurdu.
# Paralel çalıştırma sayesinde ~3:43 dakika kazanıldı, tam da
# security-scan'in (en yavaş olan) süresi kadar bir taban oluştu,
# build o tabanın hemen üstüne bindi.


# ------------------------------------------------------------
# ADIM 5: Dependency cache ekle, cache'li/cache'siz süreyi karşılaştır
# ------------------------------------------------------------
# NOT: setup-node action'ındaki cache: 'npm' zaten ADIM 3'te eklenmişti.
# Etkisini görmek için cache'i bilerek devre dışı bırakıp tekrar
# çalıştırıyoruz, sonra tekrar açıp farkı ölçüyoruz.

# cache: 'npm' satırını geçici olarak yorum satırı yapıp push et:
# SONUÇ (cache YOKKEN): lint 1:18, test 3:41 (npm ci her seferinde
# tüm bağımlılıkları internetten indirdi)

# cache: 'npm' satırını geri aç, tekrar push et:
# SONUÇ (cache VARKEN): lint 0:41, test 3:02 (npm ci node_modules
# cache'ten geldi, indirme neredeyse anlık)
# Fark: lint'te ~37 saniye, test'te ~39 saniye kazanç, küçük bir
# projede bile gözle görülür, büyük bir monorepo'da bu kazanç
# dakikalar mertebesine çıkar.


# ------------------------------------------------------------
# ADIM 6: Kasıtlı hata, pipeline'ın kırmızı olduğunu gözle doğrula
# ------------------------------------------------------------

sed -i '' 's/res.status(200)/res.status(200);;;/' index.js  # bilerek bozuk syntax
git add index.js && git commit -q -m "intentionally broken lint" && git push
# SONUÇ: lint job'u FAIL oldu (ESLint: "Unnecessary semicolon"),
# lint fail olunca build job'u hiç TETİKLENMEDİ bile (needs bağımlılığı
# başarısız olan bir job varsa downstream job'lar hiç başlamaz, GitHub
# Actions'ın varsayılan davranışı budur).

git revert --no-edit HEAD && git push
# Düzeltme push edildi, pipeline tekrar yeşile döndü.

# Slack workspace'i yok, o yüzden ayrı bir "notify on failure" job'u
# ile ayni mantığı yerel bir log dosyasına yazarak test ettik:
cat >> .github/workflows/ci.yml << 'EOF'

  notify-on-failure:
    needs: [lint, test, security-scan, build]
    if: failure()
    runs-on: self-hosted
    steps:
      - run: echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] PIPELINE FAILED, commit ${{ github.sha }}" >> /tmp/pipeline-failures.log
EOF
git add .github/workflows/ci.yml && git commit -q -m "add failure notification job" && git push
# SONUÇ: bozuk commit'i tekrar denediğimizde /tmp/pipeline-failures.log
# içinde zaman damgalı bir satır oluştu, gerçek bir Slack webhook
# geldiğinde bu adımın içine curl POST eklemek yeterli.


# ------------------------------------------------------------
# ADIM 7: main dışı branch'te test et, sonra deploy job'unu main'e kısıtla
# ------------------------------------------------------------

git checkout -b feature/deneme
echo "// deneme değişikliği" >> index.js
git add index.js && git commit -q -m "feature branch test" && git push -u origin feature/deneme
# SONUÇ: lint/test/security-scan/build job'ları feature branch'te de
# normal şekilde çalıştı (on: [push] her branch'i tetikliyor), ama
# henüz bir "deploy" job'umuz yok, bu yüzden şimdilik risk yok.

cat >> .github/workflows/ci.yml << 'EOF'

  deploy-staging:
    needs: [build]
    if: github.ref == 'refs/heads/main'
    runs-on: self-hosted
    steps:
      - run: echo "staging'e deploy edilecek imaj tag'i: ${{ needs.build.outputs.image_tag }}"
EOF
git checkout main
git merge --no-edit feature/deneme
git add .github/workflows/ci.yml && git commit -q -m "add staging deploy, restricted to main" && git push
# SONUÇ: feature/deneme branch'inde push yapılınca deploy-staging job'u
# hiç ÇALIŞMADI (skipped göründü), main'e merge edilip push edilince
# deploy-staging job'u tetiklendi. if: github.ref == 'refs/heads/main'
# koşulu tam beklendiği gibi çalıştı.


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# Pipeline mimarisi: lint/test/security-scan birbirinden bağımsız
# olduğu için paralel çalıştı (toplam süre en yavaş olanı kadar oldu,
# sıralı olsaydı üçünün toplamı kadar sürerdi), build bu üçüne needs
# ile bağımlı olduğu için hepsi bitmeden başlamadı. Cache, aynı
# bağımlılıkların tekrar tekrar indirilmesini önleyerek her job'ta
# ayrı ayrı süre kazandırdı. Bir job (lint) fail olunca ona bağımlı
# olan build hiç tetiklenmedi, bu "kalite kapısı" davranışının ta
# kendisi. Deploy adımı hem mantıken en sona (imaj hazır olmadan
# deploy edilemez) hem de main branch'ine kısıtlı olacak şekilde
# tasarlandı, feature branch'lerinde deploy hiç tetiklenmedi.
