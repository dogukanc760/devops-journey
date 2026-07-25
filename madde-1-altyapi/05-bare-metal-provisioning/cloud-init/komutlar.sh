#!/bin/bash
# ============================================================
# Pratik Görev: cloud-init / autoinstall ile OS Yapılandırması
# ============================================================
# cloud-init: Ubuntu'ya özel değil, tüm cloud provider'larda çalışır
# autoinstall: Ubuntu Server kurulum otomasyonu (subiquity tabanlı)
# ============================================================

# -----------------------------------------------------------
# SENARYO A: cloud-init — MEVCUT MAKINEYI YAPILANDIR
# -----------------------------------------------------------

# cloud-init yapılandırması test etmek için local VM veya LXD kullan
# (LXD Mac'te çalışmaz, Ubuntu host gerekir)

# cloud-init durumunu kontrol et
cloud-init status
cloud-init status --wait   # tamamlanmasını bekle

# cloud-init logları
journalctl -u cloud-init --no-pager
cat /var/log/cloud-init-output.log

# ---
# Temel user-data örnekleri (YAML / #cloud-config formatı)
# ---

# Örnek 1: Paket kur + kullanıcı ekle + komut çalıştır
cat > /tmp/user-data-temel.yaml << 'EOF'
#cloud-config

# Sistem hostname'i ayarla
hostname: devops-node-01
fqdn: devops-node-01.lab.local

# Kullanıcı ekle
users:
  - name: devops
    groups: sudo, docker
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-rsa AAAA...SENIN_PUBLIC_KEY'IN

# Root SSH kapat (güvenlik)
disable_root: true
ssh_pwauth: false

# Paketleri güncelle ve kur
package_update: true
package_upgrade: true
packages:
  - curl
  - git
  - htop
  - jq
  - net-tools
  - open-iscsi        # Longhorn için
  - nfs-common        # NFS storage için

# Dosya yaz
write_files:
  - path: /etc/sysctl.d/99-k8s.conf
    content: |
      net.ipv4.ip_forward = 1
      net.bridge.bridge-nf-call-iptables = 1
      vm.swappiness = 0
    permissions: '0644'

  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter
    permissions: '0644'

# Komutlar çalıştır (boot sonrası)
runcmd:
  - sysctl --system
  - modprobe overlay
  - modprobe br_netfilter
  - systemctl enable --now open-iscsi
  - curl -fsSL https://get.docker.com | sh
  - usermod -aG docker devops

# Final mesajı
final_message: |
  cloud-init tamamlandı!
  Sistem hazır: $HOSTNAME
  Geçen süre: $UPTIME saniye
EOF

echo "user-data hazır"

# -----------------------------------------------------------
# SENARYO B: autoinstall — UBUNTU SUNUCU KURULUMUNU OTOMATIZE ET
# -----------------------------------------------------------

# autoinstall.yaml → Ubuntu Server kurulumu sırasında okunur
# PXE boot veya USB ile dağıtılır

cat > /var/www/html/cloud-init/autoinstall.yaml << 'EOF'
#cloud-config
autoinstall:
  version: 1

  # Locale ve keyboard
  locale: tr_TR.UTF-8
  keyboard:
    layout: tr

  # Ağ yapılandırması
  network:
    ethernets:
      eth0:
        dhcp4: true    # PXE'den IP aldı, devam et
    version: 2

  # Disk bölümleme (otomatik, tüm diski kullan)
  storage:
    layout:
      name: lvm
      sizing-policy: all    # tüm diski LVM'e ver

  # Alternatif: manuel bölümleme
  # storage:
  #   config:
  #     - type: disk
  #       id: disk0
  #       path: /dev/sda
  #     - type: partition
  #       id: part-efi
  #       device: disk0
  #       size: 512M
  #       flag: boot
  #     - type: partition
  #       id: part-root
  #       device: disk0
  #       size: -1          # kalan alanın tamamı
  #     - type: format
  #       id: fmt-root
  #       fstype: ext4
  #       volume: part-root
  #     - type: mount
  #       device: fmt-root
  #       path: /

  # Admin kullanıcısı
  identity:
    hostname: k8s-worker-01
    username: ubuntu
    password: "$6$rounds=4096$saltsalt$HASHED_PASSWORD"   # mkpasswd -m sha-512
    # Şifre hash üret: python3 -c "import crypt; print(crypt.crypt('sifreniz', crypt.mksalt(crypt.METHOD_SHA512)))"

  # SSH server aktif et
  ssh:
    install-server: true
    authorized-keys:
      - ssh-rsa AAAA...PUBLIC_KEY
    allow-pw: false

  # Paket yükle
  packages:
    - open-iscsi
    - nfs-common
    - curl
    - git

  # Kurulum tamamlandıktan sonra çalışacak cloud-init user-data
  user-data:
    #cloud-config
    runcmd:
      - sysctl -w net.ipv4.ip_forward=1
      - echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
      - systemctl enable --now open-iscsi

  # Kurulum bitince kapatmak yerine yeniden başlat
  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
    - echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /target/etc/sudoers.d/ubuntu

  # Hata durumunda bekle (debug için kapat, production'da açık bırak)
  error-commands:
    - curtin in-target -- journalctl -b --no-pager > /target/var/log/install-error.log
EOF

echo "autoinstall.yaml hazır"

# -----------------------------------------------------------
# SENARYO C: NoCloud — LOCAL TEST (ISO ile)
# -----------------------------------------------------------

# cloud-init'i local test etmek için seed ISO oluştur
mkdir -p /tmp/cidata

# user-data
cat > /tmp/cidata/user-data << 'EOF'
#cloud-config
hostname: test-node
packages:
  - curl
runcmd:
  - echo "cloud-init test OK" > /tmp/cloud-init-success.txt
EOF

# meta-data (zorunlu, boş olsa bile)
cat > /tmp/cidata/meta-data << 'EOF'
instance-id: test-instance-001
local-hostname: test-node
EOF

# Seed ISO oluştur
apt install -y cloud-image-utils
cloud-localds /tmp/seed.iso /tmp/cidata/user-data /tmp/cidata/meta-data

# QEMU'da test et
apt install -y qemu-system-x86
wget -O /tmp/ubuntu-22.04-cloud.img \
  https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

qemu-system-x86_64 \
  -m 2048 \
  -drive file=/tmp/ubuntu-22.04-cloud.img,format=qcow2 \
  -drive file=/tmp/seed.iso,format=raw \
  -net nic \
  -net user \
  -nographic

# -----------------------------------------------------------
# DOĞRULAMA — cloud-init başarılı mı çalıştı?
# -----------------------------------------------------------

# VM içinde
cloud-init status --wait
cloud-init analyze show        # adım adım süre analizi
cat /var/log/cloud-init-output.log

# Başarı işareti
ls /tmp/cloud-init-success.txt   # Senaryo C için

# cloud-init'i sıfırla (test için — production'da yapma!)
cloud-init clean --logs
cloud-init init

# -----------------------------------------------------------
# ÖZET: CLOUD-INIT VERİ KAYNAKLARI (datasource)
# -----------------------------------------------------------
# NoCloud     → local ISO, PXE HTTP (lab ortamı)
# ConfigDrive → OpenStack
# EC2         → AWS
# GCE         → Google Cloud
# Azure       → Azure
# MaaS        → MaaS kendi datasource'unu inject eder
# Tinkerbell  → writefile action ile inject eder
