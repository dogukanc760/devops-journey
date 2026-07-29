#!/bin/bash
# ============================================================
# Immutable Infrastructure — Pratik Görevler
# ============================================================
# NOT: Fiziksel/sanal Ubuntu makine yerine Docker kullanıldı.
# Packer'ın docker builder'ı ile golden image bir Docker image
# olarak inşa edildi, VM yerine container açıldı. Immutable
# Infrastructure prensibi (önceden hazırlanmış, değişmez imajdan
# sıfırdan ayağa kaldırma) birebir aynı kaldı.
# ============================================================

# ------------------------------------------------------------
# GÖREV 1: Packer ile golden image yaz (Ubuntu + nginx)
# ------------------------------------------------------------

# HashiCorp ürünleri artık kendi tap'inde (standart brew'dan kaldırıldı)
brew tap hashicorp/tap
brew install hashicorp/tap/packer
packer version

cd madde-2-iac/02-immutable-infrastructure

# golden-image.pkr.hcl: docker builder ile ubuntu:22.04 üstüne
# nginx kurup golden-nginx:v1 olarak commit ediyor
packer init golden-image.pkr.hcl
packer build golden-image.pkr.hcl

docker images | grep golden-nginx
# Beklenen: golden-nginx   v1   ...


# ------------------------------------------------------------
# GÖREV 2: Terraform ile bu image'dan container (VM yerine) aç
# ------------------------------------------------------------

terraform init
terraform apply
# yes onayı ver

# HATA: "Bind for 0.0.0.0:8080 failed: port is already allocated"
# SEBEP: Madde 1'deki k3d HA cluster'ın 8080:80 port mapping'i
# zaten o portu kullanıyordu.
# ÇÖZÜM: main.tf'te external portu 8090 yaptım.

curl http://localhost:8090
docker ps | grep golden-nginx
# Çıktı: "Golden Image - Immutable Infrastructure Demo" + build tarihi


# ------------------------------------------------------------
# GÖREV 3-4: Sorun simüle et, destroy+apply döngüsü, süre ölç
# ------------------------------------------------------------

# Container'ı "boz" (mutable yaklaşımdaki hatayı simüle et)
docker exec golden-nginx-instance sh -c "echo 'BOZULDU! Sistem cortladi' > /var/www/html/index.html"
curl http://localhost:8090
# Çıktı: "BOZULDU! Sistem cortladi"

# Immutable yaklaşım: içine girip düzeltme, öldür ve yeniden yarat
terraform destroy
# yes onayı ver

time terraform apply
# yes onayı ver
# GERÇEK SONUÇ: terraform apply 0,17s user 0,07s system 12% cpu 1,910 total
# Yani sıfırdan sağlıklı container'ın ayağa kalkma süresi: ~1.9 saniye

curl http://localhost:8090
# Çıktı: golden image'ın orijinal, temiz içeriği geri geldi
# "Golden Image - Immutable Infrastructure Demo" + build tarihi
# Hiç manuel müdahale (SSH, dosya düzeltme) yapılmadı.


# ------------------------------------------------------------
# GÖREV 5: Blue-Green deployment senaryosu
# ------------------------------------------------------------

# Green için ikinci bir golden image (v2) inşa et
packer init golden-image-v2.pkr.hcl
packer build golden-image-v2.pkr.hcl
docker images | grep golden-nginx
# Beklenen: golden-nginx v1 VE golden-nginx v2 ikisi de listelenir

# Blue-Green senaryosu ayrı bir klasörde, ayrı state ile
mkdir -p blue-green
cd blue-green

# main.tf içeriği:
#   docker_network "app_net"
#   docker_container "blue"  (golden-nginx:v1, her zaman ayakta)
#   docker_container "green" (golden-nginx:v2, her zaman ayakta)
#   docker_container "proxy" (nginx:alpine, command içinde
#   var.active_version'a göre proxy_pass hedefi belirleniyor)
#
# ÖNEMLİ TASARIM NOKTASI: trafik kaydırma işini proxy container'ın
# "command" attribute'u üstünden yaptık. command değişince Terraform
# bunu ForceNew olarak görüyor (docker container'ın komutu yerinde
# güncellenemez), yani var.active_version değiştirmek proxy'yi
# "-/+ replace" ettiriyor. Blue ve Green container'larına dokunulmuyor.

terraform init
terraform apply
# yes onayı ver (default: active_version = "blue")

curl http://localhost:8100
# Çıktı: Blue içeriği ("Golden Image - Immutable Infrastructure Demo")

# --- TRAFİĞİ GREEN'E KAYDIR ---
terraform apply -var="active_version=green"
# Plan çıktısında: docker_container.proxy için "-/+ replace"
# (create/destroy değil, ForceNew nedeniyle replace)
# yes onayı ver

curl http://localhost:8100
# Çıktı: Green içeriği ("GREEN DEPLOYMENT - Versiyon 2")
# Blue container hâlâ ayakta ve sağlıklı, sadece proxy artık ona
# yönlendirmiyor. Trafik kesintisiz kaydı.

# Geri almak istersen (Blue'ya dön):
terraform apply -var="active_version=blue"


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# 1. Packer: Golden image (Docker image) inşa etti
# 2. Terraform: O image'dan container açtı
# 3. Bozma: Container'ı elle bozduk (mutable hata simülasyonu)
# 4. Onarım: destroy + apply ile 1.9 saniyede temiz hale döndü
# 5. Blue-Green: İki versiyon paralel ayakta, trafik proxy
#    üzerinden (ve "command" ForceNew mekanizmasıyla) kesintisiz
#    kaydırıldı.
