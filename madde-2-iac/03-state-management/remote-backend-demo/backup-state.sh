#!/bin/bash
# ============================================================
# State Backup Script
# ============================================================
# Amac: her calistirildiginda aktif workspace'in state'ini
# zaman damgali bir dosya olarak backups/ klasorune yedekler.
# Boylece MinIO/S3 backend'de versioning olmasa bile, state
# yanlislikla bozulursa/silinirse geri donebilecegimiz bir
# gecmis kaydimiz olur.
#
# Gercek bir prod ortaminda bu script cron ile (ornegin her
# apply sonrasi bir CI/CD pipeline adimi olarak, ya da
# gunluk cron ile) calistirilir ve yedekler state backend'in
# kendisinden ayri, sifreli bir yerde (ornegin ayri bir
# encrypted S3 bucket, offsite storage) tutulur.

set -e

cd "$(dirname "$0")"

WORKSPACE=$(terraform workspace show)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="backups"

mkdir -p "$BACKUP_DIR"

BACKUP_FILE="$BACKUP_DIR/terraform-${WORKSPACE}-${TIMESTAMP}.tfstate.json"

terraform state pull > "$BACKUP_FILE"

echo "State yedeklendi: $BACKUP_FILE (workspace: $WORKSPACE)"

# Eski yedekleri temizle, sadece son 10 tanesini tut
ls -t "$BACKUP_DIR"/terraform-${WORKSPACE}-*.tfstate.json 2>/dev/null | tail -n +11 | xargs -r rm --
