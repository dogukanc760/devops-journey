#!/bin/bash
# ============================================================
# State Management Mimarisi — Pratik Görevler
# ============================================================

# ------------------------------------------------------------
# GÖREV 1: MinIO kur (S3 uyumlu, self hosted remote backend)
# ------------------------------------------------------------

cd madde-2-iac/03-state-management

# docker-compose.yml: minio/minio image, ilk denemede 9000/9001
# portlarıyla yazıldı ama başka bir projeden (echoes-minio) kalma
# container zaten o portları tutuyordu. docker inspect ile kendi
# container'ımızın NetworkSettings.Ports alanının bos {} döndüğünü
# görünce, container'ın hiç ayağa kalkmadığını anladık. Diğer
# projelere dokunmadan kendi portlarımızı 9010/9011'e taşıdık.

docker compose up -d
docker compose ps
# HATA (ilk denemede): Bind for 0.0.0.0:9000 failed, port is already allocated
# ÇÖZÜM: docker-compose.yml portlari 9010:9000 / 9011:9001 yapildi

docker ps | grep minio-state-backend
# Beklenen: 0.0.0.0:9010->9000/tcp, 0.0.0.0:9011->9001/tcp

# Web arayüzü: http://localhost:9011
# Giriş: minioadmin / minioadmin123
# Bucket olustur: terraform-state


# ------------------------------------------------------------
# GÖREV 2: Terraform backend'i MinIO'ya yönlendir
# ------------------------------------------------------------

cd remote-backend-demo

# main.tf içinde backend "s3" bloğu, endpoints.s3 = http://localhost:9010
# (MinIO'nun yeni port mapping'ine göre güncellendi)

terraform init
# HATA: Failed to load state: invalid syntax: unexpected end of JSON input
# SEBEP: .terraform/terraform.tfstate dosyası 0 byte (bozuk), muhtemelen
# önceki bir apply yarıda kesilmiş (.terraform.tfstate.lock.info da
# kalmıştı, bu da bunu doğruluyor).
# ÇÖZÜM:
rm -rf .terraform
terraform init
# Bu sefer temiz basladi, backend MinIO'ya basariyla baglandi.

terraform apply
# yes onayı ver
# Beklenen: terraform-state bucket'inda state-management-demo/terraform.tfstate objesi olusur


# ------------------------------------------------------------
# GÖREV 3: Lock mekanizmasını test et
# ------------------------------------------------------------

# Once main.tf'te kucuk bir degisiklik yaptik (content string'ine
# "Versiyon 2" eklendi) ki apply gercekten bir onay ekraninda beklesin.

# Terminal 1:
terraform apply
# "Enter a value:" ekraninda YES DEME, bekle

# Terminal 2 (ayni klasorde):
terraform apply
# ILK DENEME (use_lockfile olmadan): ikinci terminal de sorunsuz onay
# bekledi, HICBIR kilit hatasi cikmadi. Bu, backend'de locking'in hic
# aktif olmadiginin kanitiydi (S3 backend'de kilit ya dynamodb_table
# ya da use_lockfile ile acilir, ikisi de yoksa kilitlenmiyor).

# ÇÖZÜM: main.tf'teki backend blogune eklendi:
#   use_lockfile = true
terraform init -reconfigure

# TEKRAR TEST (use_lockfile ile):
# Terminal 1: terraform apply, onay ekraninda bekletildi
# Terminal 2: terraform apply
# SONUÇ: Terminal 2 su hatayi aldi:
#   Error: Error acquiring the state lock
#   api error PreconditionFailed: At least one of the pre-conditions
#   you specified did not hold
#   Lock Info: ID, Path, Operation, Who, Version, Created bilgileriyle
# Terminal 1'de yes denince apply tamamlandi, ardindan Terminal 2
# tekrar denendiginde kilit bos oldugu icin sorunsuz calisti
# ("No changes. Your infrastructure matches the configuration.")


# ------------------------------------------------------------
# GÖREV 4: State dosyasını incele (hangi hassas veriler var)
# ------------------------------------------------------------

terraform state pull > /tmp/state-dump.json
cat /tmp/state-dump.json | python3 -m json.tool

# GÖZLEM: state icinde "sensitive_attributes" alani var, ornegin
# local_file provider'inin sensitive_content attribute'unu sensitive
# olarak isaretliyor. Ama bu sadece CLI ciktisinda gizleniyor, deger
# state dosyasinin kendisinde (kullanilsaydi) yine duz metin olarak
# dururdu. Bu yuzden state backend'inin encryption at rest ve erisim
# kontrolu olmasi sart, gercekten kritik sirlar Vault gibi bir yerde
# tutulup Terraform'a sadece referans olarak cekilmeli.


# ------------------------------------------------------------
# GÖREV 5: Dev/staging/prod için ayrı workspace kur
# ------------------------------------------------------------

terraform workspace list
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod
terraform workspace list

terraform workspace select dev
terraform apply
# yes onayı ver
# SONUÇ: "Plan: 1 to add" cikti, cunku dev workspace'inin state'i
# tamamen bostu, prod'daki local_file kaynagindan habersizdi.
# Bu, workspace izolasyonunun kaniti.

# MinIO konsolunda dogrulama: terraform-state bucket'inda artik
# env:/dev/state-management-demo/terraform.tfstate gibi ayri bir
# path/obje olustugu goruldu. Workspace, backend key'inin basina
# otomatik olarak env:/<workspace-adi>/ ekliyor.


# ------------------------------------------------------------
# GÖREV 6: State backup politikası oluştur
# ------------------------------------------------------------

# MinIO web konsolunda bucket versioning secenegi aranildi ama bu
# kurulumda (standalone/tek node MinIO) UI'da boyle bir toggle
# cikmadi. Bunun yerine backup-state.sh scripti yazildi: her
# calistiginda aktif workspace'in state'ini zaman damgali ayri bir
# dosyaya (backups/ klasoru) yedekliyor, son 10 yedegi tutup
# eskilerini siliyor. Bu klasor .gitignore'a eklendi cunku state
# icerigi tasidigi icin hassas.

chmod +x backup-state.sh
./backup-state.sh
ls -la backups/
# Beklenen: backups/terraform-dev-<timestamp>.tfstate.json


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# 1. MinIO: self hosted S3 uyumlu remote backend olarak kuruldu
#    (port cakismasi yuzunden 9010/9011'e tasindi)
# 2. Terraform backend "s3" MinIO'ya yonlendirildi, bozuk local
#    .terraform state cache'i temizlenerek cozuldu
# 3. use_lockfile = true ile native S3 lock mekanizmasi acildi,
#    iki terminal testiyle kilit calistigi HTTP 412 hatasiyla
#    dogrulandi
# 4. terraform state pull ile state icerigi incelendi,
#    sensitive_attributes'in sadece CLI gizlemesi oldugu,
#    dosyanin sifrelenmedigi gorundu
# 5. dev/staging/prod workspace'leri kuruldu, her birinin
#    kendi ayri state dosyasi oldugu dogrulandi
# 6. Versioning UI'da olmadigi icin terraform state pull
#    tabanli manuel backup scripti ile yedekleme politikasi
#    uygulandi
