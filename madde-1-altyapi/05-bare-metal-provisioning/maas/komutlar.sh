#!/bin/bash
# ============================================================
# Pratik Görev: MaaS (Metal as a Service) Kur, Node Ekle
# Gereksinim: Ubuntu 22.04, en az 2 fiziksel makine
#             (1 MaaS controller + 1+ bare-metal node)
# ============================================================

# -----------------------------------------------------------
# 1. MAAS CONTROLLER KURULUMU
# -----------------------------------------------------------

# snap ile kur (stable kanal)
snap install --channel=3.4/stable maas

# Veritabanı başlat (PostgreSQL)
snap install postgresql14
/snap/bin/postgresql14.createcluster -d /var/snap/postgresql14/current/data 14 main
snap start postgresql14

# PostgreSQL'de MaaS kullanıcısı oluştur
sudo -u postgres psql << 'EOF'
CREATE USER maas WITH ENCRYPTED PASSWORD 'maaspass';
CREATE DATABASE maasdb OWNER maas;
GRANT ALL PRIVILEGES ON DATABASE maasdb TO maas;
EOF

# MaaS'ı başlat ve yapılandır
maas init region+rack \
  --database-uri "postgres://maas:maaspass@localhost/maasdb" \
  --maas-url "http://10.0.1.1:5240/MAAS"

# Admin kullanıcısı oluştur
maas createadmin \
  --username admin \
  --password admin123 \
  --email admin@lab.local \
  --ssh-import lp:GITHUB_KULLANICI_ADIN  # ya da manuel ekle

# MaaS'a giriş (API üzerinden)
maas login admin http://10.0.1.1:5240/MAAS/api/2.0/ \
  $(maas apikey --username admin)

# -----------------------------------------------------------
# 2. NETWORK AYARLARI — DHCP ve PXE
# -----------------------------------------------------------

# Subnet oluştur
maas admin subnets create \
  cidr=10.0.1.0/28 \
  gateway_ip=10.0.1.1 \
  dns_servers=10.0.1.1

# VLAN al
VLAN_ID=$(maas admin vlans read 0 | python3 -c "import sys,json; data=json.load(sys.stdin); print(data[0]['id'])")

# DHCP aktif et (MaaS kendi DHCP'sini yönetir)
maas admin vlan update 0 $VLAN_ID dhcp_on=True primary_rack=$(maas admin rack-controllers read | python3 -c "import sys,json; data=json.load(sys.stdin); print(data[0]['system_id'])")

# -----------------------------------------------------------
# 3. NODE (BARE-METAL MAKİNE) KAYDI
# -----------------------------------------------------------

# Yöntem A: İpmi/BMC üzerinden otomatik discovery
# Makinenin BMC bilgilerini gir, MaaS keşfeder ve PXE ile önyükler

maas admin machines create \
  architecture=amd64 \
  mac_addresses=AA:BB:CC:DD:EE:FF \
  power_type=ipmi \
  power_parameters_power_address=10.0.1.100 \
  power_parameters_power_user=admin \
  power_parameters_power_pass=bmc_password

# Yöntem B: PXE ile manuel enrollment
# Makineyi PXE ile başlat → MaaS enlistment OS yükler
# → MaaS web UI'da "New" olarak görünür → "Commission" et

# Node ID'yi öğren
NODE_ID=$(maas admin machines read | python3 -c "
import sys,json
data = json.load(sys.stdin)
print(data[0]['system_id'])
")

echo "Node ID: $NODE_ID"

# -----------------------------------------------------------
# 4. COMMISSIONING — DONANIM TESTİ
# -----------------------------------------------------------

# Commission: MaaS node'u önyükler, donanım bilgilerini toplar
maas admin machine commission $NODE_ID

# Durumu takip et
watch -n 5 "maas admin machine read $NODE_ID | python3 -c \"import sys,json; d=json.load(sys.stdin); print(d['status_name'])\""

# Beklenen akış: Commissioning → Testing → Ready

# -----------------------------------------------------------
# 5. DEPLOY — İŞLETİM SİSTEMİ YÜKLE
# -----------------------------------------------------------

# Ubuntu 22.04 yükle
maas admin machine deploy $NODE_ID \
  distro_series=jammy \
  hwe_kernel=ga-22.04

# Alternatif: cloud-init user_data ile birlikte deploy
USER_DATA=$(cat << 'EOF'
#cloud-config
package_update: true
packages:
  - curl
  - git
runcmd:
  - curl -fsSL https://get.docker.com | sh
EOF
)

maas admin machine deploy $NODE_ID \
  distro_series=jammy \
  user_data=$(echo "$USER_DATA" | base64)

# -----------------------------------------------------------
# 6. DOĞRULAMA
# -----------------------------------------------------------

# Node durumu
maas admin machine read $NODE_ID | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f\"Hostname: {d['hostname']}\")
print(f\"Status: {d['status_name']}\")
print(f\"IP: {d.get('ip_addresses', [])}\")
print(f\"CPU: {d['cpu_count']} cores\")
print(f\"RAM: {d['memory']} MB\")
"

# Release (sil ve geri al, tekrar deploy için)
maas admin machine release $NODE_ID comment="test bitti"

# -----------------------------------------------------------
# SONUÇ: MAAS AKIŞI
# -----------------------------------------------------------
# Enlist → Commission → Test → Ready → Deploy → Deployed
# Her aşamada MaaS web UI'dan da takip edilebilir:
# http://10.0.1.1:5240/MAAS
