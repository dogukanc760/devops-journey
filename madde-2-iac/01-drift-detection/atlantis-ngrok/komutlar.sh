#!/bin/bash
# ============================================================
# Atlantis + ngrok — Gerçek Kurulum ve Debug Süreci
# ============================================================
# Bu dosya, madde-2-iac/01-drift-detection'daki Görev 5'i (Atlantis
# kur, PR'da otomatik plan çalışsın) uçtan uca gerçekleştirirken
# atılan adımları VE karşılaşılan hataları sırayla belgeliyor.
# ============================================================

# ------------------------------------------------------------
# 1. ATLANTIS'İ AYAĞA KALDIR
# ------------------------------------------------------------
cd madde-2-iac/01-drift-detection/atlantis-server

docker compose ps
docker compose logs atlantis --tail 5
# Beklenen: "Atlantis started, listening on port 4141"


# ------------------------------------------------------------
# 2. NGROK KUR VE TÜNEL AÇ
# ------------------------------------------------------------
# HATA: zsh: command not found: ngrok
# ÇÖZÜM: kurulum
brew install ngrok

# HATA (ilk çalıştırmada olası): ERR_NGROK_4018 authentication required
# ÇÖZÜM: ücretsiz hesap aç (dashboard.ngrok.com/signup), authtoken al
ngrok config add-authtoken <SENIN_TOKENIN>

# Tüneli başlat (ayrı bir terminalde, açık kalmalı)
ngrok http 4141

# Tam forwarding URL'ini almak için (terminal satırı kesiliyorsa)
curl -s http://127.0.0.1:4040/api/tunnels | python3 -c "import sys,json; print(json.load(sys.stdin)['tunnels'][0]['public_url'])"
# örnek çıktı: https://untried-kindred-enlarging.ngrok-free.dev


# ------------------------------------------------------------
# 3. GITHUB WEBHOOK'U KUR
# ------------------------------------------------------------
# GitHub → repo → Settings → Webhooks → Add webhook
# Payload URL: https://<ngrok-url>/events
# Content type: application/json

# HATA 1: Recent Deliveries → "Invalid HTTP Response: 400"
# Atlantis log: "msg":"missing signature"
# SEBEP: GitHub webhook formundaki Secret alanı boş bırakılmıştı.
# Secret boşsa GitHub imza (X-Hub-Signature-256) header'ı eklemiyor,
# Atlantis ise ATLANTIS_GH_WEBHOOK_SECRET set edildiği için
# imzasız isteği kabul etmiyor.
# ÇÖZÜM: .env dosyasındaki WEBHOOK_SECRET değerini kopyala,
# GitHub webhook formundaki Secret alanına yapıştır, kaydet.
cat .env


# ------------------------------------------------------------
# 4. REPO ALLOWLIST HATASI
# ------------------------------------------------------------
# HATA 2: PR'a push sonrası → "403 Forbidden"
# Atlantis log:
#   "pull request event from non-allowlisted repo
#    'github.com/dogukanc760/devops-journey'"
# SEBEP: docker-compose.yml'daki ATLANTIS_REPO_ALLOWLIST hala
# placeholder değeri tutuyordu:
#   "github.com/KULLANICI_ADIN/terraform-drift-demo"
# Gerçek repo: github.com/dogukanc760/devops-journey

# ÇÖZÜM: docker-compose.yml içindeki satırı güncelle
#   ATLANTIS_REPO_ALLOWLIST: "github.com/dogukanc760/devops-journey"

docker compose down
docker compose --env-file .env up -d
docker compose logs atlantis --tail 5


# ------------------------------------------------------------
# 5. TEKRAR TETİKLE VE DOĞRULA
# ------------------------------------------------------------
cd ../

git commit --allow-empty -m "retrigger atlantis"
git push origin test-atlantis-plan

# PR sayfasını yenile, Atlantis'in otomatik yorumu:
# "Ran Plan for 2 projects:
#    1. dir: madde-2-iac/01-drift-detection
#    2. dir: madde-2-iac/01-drift-detection/atlantis-server
#  Plan: 1 to add, 0 to change, 0 to destroy."


# ------------------------------------------------------------
# 6. SECRET SIZINTISI: GITHUB PUSH PROTECTION
# ------------------------------------------------------------
# HATA 3: git push → "GH013: Repository rule violations found"
# "GITHUB PUSH PROTECTION: Push cannot contain secrets"
# "GitHub Personal Access Token" tespit edildi, konum:
#   atlantis-server/atlantis-data/atlantis.db
# SEBEP: Atlantis'in local BoltDB'si (atlantis-data/) yanlışlıkla
# commit'lenmişti. Bu dosyanın içinde ATLANTIS_GH_TOKEN olarak
# verdiğimiz GitHub PAT saklı duruyordu.

# ÇÖZÜM ADIM 1: gitignore ekle
cat >> ../../.gitignore << 'EOF'
madde-2-iac/01-drift-detection/atlantis-server/atlantis-data/
madde-2-iac/01-drift-detection/atlantis-server/.env
EOF

# ÇÖZÜM ADIM 2: dosyayı git index'inden çıkar (diskte kalır)
cd madde-2-iac/01-drift-detection   # zaten bu klasördeysen atla
git rm -r --cached atlantis-server/atlantis-data

git status
# "deleted: atlantis-server/atlantis-data/atlantis.db" görmen lazım,
# atlantis-data artık staged listesinde olmamalı.

# ÇÖZÜM ADIM 3: son (henüz push edilmemiş) commit'i düzelt
git commit --amend --no-edit

# ÇÖZÜM ADIM 4: tekrar push et
git push origin test-atlantis-plan
# Bu sefer GH013 hatası gelmemeli.

# NOT: git restore --staged komutunu ilk denememde yanlış path'le
# çalıştırdım (repo kökünden path verdim ama zaten alt klasördeydim),
# komut sessizce hiçbir şey yapmadı ve dosya commit'te kaldı.
# git rm -r --cached net bir "bu path'i artık takip etme" komutu
# olduğu için ikinci denemede sorunsuz çalıştı.


# ------------------------------------------------------------
# ÖZET: HATA ZİNCİRİ VE KATMANLAR
# ------------------------------------------------------------
# Katman 1, Network:       ngrok çalışmıyor        → istek hiç ulaşmadı
# Katman 2, Kimlik:        webhook secret eksik    → 400 missing signature
# Katman 3, Yetki:         repo allowlist yanlış   → 403 non-allowlisted
# Katman 4, Güvenlik:      secret commit'lenmiş    → GH013 push protection
# Katman 5, Başarı:        hepsi düzelince         → 200 OK + otomatik plan yorumu
#
# Her katman farklı bir hata koduyla (network hatası, 400, 403, GH013)
# kendini gösterdi. Debug sırası: en dıştan (network) en içe
# (yetkilendirme, güvenlik) doğru ilerlemek mantıklı.
