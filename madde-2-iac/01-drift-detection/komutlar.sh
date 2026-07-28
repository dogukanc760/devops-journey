#!/bin/bash
# ============================================================
# Drift Detection — Pratik Görevler
# ============================================================

# ------------------------------------------------------------
# GÖREV 1-4: local_file ile drift oluştur, gözlemle, geri al
# ------------------------------------------------------------
# main.tf içinde local_file resource'u tanımlı.

cd madde-2-iac/01-drift-detection

terraform init
terraform apply
# yes onayı ver → drift-test.txt oluşur, içinde "Versiyon: 1"

cat drift-test.txt

# --- DRIFT OLUŞTUR: dosyayı Terraform'un bilmediği yoldan değiştir ---
echo "Bu dosya elle degistirildi! Versiyon: 999" > drift-test.txt
cat drift-test.txt

# --- DRIFT'İ GÖZLEMLE ---
terraform plan
# ÇIKTI: "+ create" gösterir (update değil!)
# SEBEP: local_file'ın id'si content'in SHA1 hash'i. Refresh sırasında
# dosyadaki hash state'teki hash ile tutmuyor, provider resource'u
# "yok" sayıyor (silinmiş gibi davranıyor). Bu yüzden create görürüz,
# update değil. Gerçek cloud kaynaklarında (örn. AWS instance tag)
# attribute bazlı kısmi update mümkün olduğundan "~ update in-place"
# görülür. local_file bu nüansı göstermiyor çünkü content ForceNew.

# State'teki gerçek değerleri incelemek için:
terraform state list
python3 -c "import json; d=json.load(open('terraform.tfstate')); print(json.dumps(d['resources'][0]['instances'][0]['attributes'], indent=2))"

# --- DRIFT'İ GERİ AL ---
terraform apply
# yes onayı ver → drift-test.txt tekrar "Versiyon: 1" içeriğine döner
cat drift-test.txt


# ------------------------------------------------------------
# GÖREV 5: Atlantis kur, PR'da otomatik plan çalışsın
# ------------------------------------------------------------
# NOT: Atlantis bir Git provider'dan (GitHub/GitLab) webhook almak
# zorunda. Bu yüzden gerçek bir GitHub reposu + Personal Access Token
# + (local test ediyorsan) ngrok gibi bir tünel gerekiyor, ya da
# senin intranet GitLab'ın varsa doğrudan onunla (tünelsiz, aynı ağda).
# Aşağıdaki adımlar GitHub ile örneklenmiştir, GitLab'da webhook URL'i
# ve token türü değişir ama akış birebir aynıdır.

# 1. GitHub'da yeni bir repo oluştur (örn: terraform-drift-demo)
#    ve içine bu madde-2-iac/01-drift-detection klasöründeki main.tf'i koy.

# 2. Atlantis için bir GitHub kullanıcısı/bot ve Personal Access Token oluştur
#    (repo + webhook izinleriyle). GitHub Settings → Developer Settings → PAT

# 3. Docker Compose ile Atlantis'i ayağa kaldır
mkdir -p atlantis-server && cd atlantis-server

cat > docker-compose.yml << 'EOF'
version: "3"
services:
  atlantis:
    image: ghcr.io/runatlantis/atlantis:latest
    ports:
      - "4141:4141"
    environment:
      ATLANTIS_GH_USER: "atlantis-bot"
      ATLANTIS_GH_TOKEN: "${GITHUB_TOKEN}"
      ATLANTIS_GH_WEBHOOK_SECRET: "${WEBHOOK_SECRET}"
      ATLANTIS_REPO_ALLOWLIST: "github.com/KULLANICI_ADIN/terraform-drift-demo"
      ATLANTIS_PORT: "4141"
    volumes:
      - ./atlantis-data:/home/atlantis/.atlantis
EOF

# .env dosyası (gerçek token'ları buraya koy, GİT'E COMMITLEME)
cat > .env << 'EOF'
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
WEBHOOK_SECRET=rastgele-guclu-bir-secret
EOF

docker compose --env-file .env up -d

# 4. Local Atlantis'i dışarıdan (GitHub webhook'unun) erişebilir yapmak için
#    ngrok ile tünel aç (intranet GitLab kullanıyorsan bu adıma gerek yok,
#    aynı ağdaysan direkt Atlantis'in IP:4141 adresini webhook URL'i yaparsın)
ngrok http 4141
# ngrok çıktısındaki https://xxxx.ngrok.io adresini not al

# 5. GitHub repo → Settings → Webhooks → Add webhook
#    Payload URL: https://xxxx.ngrok.io/events
#    Content type: application/json
#    Secret: (yukarıdaki WEBHOOK_SECRET ile aynı)
#    Events: Pull requests, Pushes, Issue comments

# 6. TEST: main.tf'te bir değişiklik yap, yeni bir branch'e push et, PR aç
git checkout -b test-atlantis-plan
echo '# yorum satırı ekle' >> main.tf
git add main.tf && git commit -m "test atlantis plan"
git push origin test-atlantis-plan
# GitHub'da PR aç

# Beklenen sonuç: Atlantis birkaç saniye içinde PR'a otomatik yorum atar,
# içinde "terraform plan" çıktısı vardır. PR'da "atlantis apply" yazarsan
# apply de otomatik tetiklenir.


# ------------------------------------------------------------
# GÖREV 6: Drift olunca Slack webhook ile alert gönder
# ------------------------------------------------------------
# NOT: Slack workspace'inde bir Incoming Webhook URL'i oluşturman gerekiyor:
# Slack → Apps → Incoming Webhooks → Add to Slack → kanal seç → URL kopyala
# URL formatı: https://hooks.slack.com/services/T000/B000/XXXXXXXX

cd ../  # 01-drift-detection köküne dön

cat > check-drift.sh << 'EOF'
#!/bin/bash
# Cron ile periyodik çalıştırılacak drift kontrol scripti

SLACK_WEBHOOK_URL="https://hooks.slack.com/services/SENIN/WEBHOOK/URLIN"

cd "$(dirname "$0")"

# terraform plan -detailed-exitcode:
#   0 = değişiklik yok (drift yok)
#   1 = hata
#   2 = değişiklik var (drift VAR)
terraform plan -detailed-exitcode -no-color -input=false > /tmp/plan-output.txt 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 2 ]; then
  echo "DRIFT TESPİT EDİLDİ, Slack'e bildirim gönderiliyor..."
  PLAN_SUMMARY=$(tail -20 /tmp/plan-output.txt)

  curl -X POST -H 'Content-type: application/json' \
    --data "{\"text\": \"⚠️ *Terraform Drift Tespit Edildi* — \`01-drift-detection\`\n\`\`\`${PLAN_SUMMARY}\`\`\`\"}" \
    "$SLACK_WEBHOOK_URL"

elif [ $EXIT_CODE -eq 0 ]; then
  echo "Drift yok, her şey desired state ile uyumlu."
else
  echo "terraform plan hata verdi, exit code: $EXIT_CODE"
fi
EOF

chmod +x check-drift.sh

# Manuel test: önce drift oluştur, sonra scripti çalıştır
echo "elle degisiklik" > drift-test.txt
./check-drift.sh
# Slack kanalında bildirim gelmeli

# Cron ile otomatikleştir (her 15 dakikada bir kontrol)
crontab -e
# Şu satırı ekle:
# */15 * * * * /tam/yol/01-drift-detection/check-drift.sh >> /tmp/drift-check.log 2>&1
