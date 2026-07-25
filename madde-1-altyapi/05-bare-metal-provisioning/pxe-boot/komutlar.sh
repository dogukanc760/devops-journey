#!/bin/bash
# ============================================================
# Pratik Görev: PXE Boot Server Kur (dnsmasq + nginx)
# Gereksinim: Ubuntu 22.04 fiziksel makine veya VM (hypervisor)
# ============================================================

# -----------------------------------------------------------
# 1. KURULUM ÖNCESİ HAZIRLIK
# -----------------------------------------------------------

# Statik IP ayarla (PXE server sabit IP'de olmalı)
# /etc/netplan/00-installer-config.yaml
cat > /etc/netplan/00-installer-config.yaml << 'EOF'
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 10.0.1.1/28       # mgmt subnet'imiz
      nameservers:
        addresses: [8.8.8.8]
EOF
netplan apply

# -----------------------------------------------------------
# 2. DNSMASQ — DHCP + TFTP SERVER
# -----------------------------------------------------------

apt update && apt install -y dnsmasq

cat > /etc/dnsmasq.conf << 'EOF'
# DHCP ayarları
interface=eth0
dhcp-range=10.0.1.2,10.0.1.14,255.255.255.240,12h   # /28 subnet
dhcp-option=3,10.0.1.1                                 # gateway

# PXE Boot — TFTP sunucusu bu makine
dhcp-boot=pxelinux.0,pxeserver,10.0.1.1

# TFTP server aktif et
enable-tftp
tftp-root=/var/lib/tftpboot

# iPXE ile gelen makinelere boot script gönder
dhcp-match=set:ipxe,175
dhcp-boot=tag:ipxe,http://10.0.1.1/boot.ipxe
EOF

systemctl restart dnsmasq
systemctl enable dnsmasq

# -----------------------------------------------------------
# 3. TFTP — BOOT LOADER DOSYALARI
# -----------------------------------------------------------

apt install -y pxelinux syslinux-common ipxe

mkdir -p /var/lib/tftpboot/pxelinux.cfg

# Boot loader dosyalarını kopyala
cp /usr/lib/PXELINUX/pxelinux.0 /var/lib/tftpboot/
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 /var/lib/tftpboot/
cp /usr/lib/syslinux/modules/bios/libcom32.c32 /var/lib/tftpboot/
cp /usr/lib/syslinux/modules/bios/libutil.c32 /var/lib/tftpboot/
cp /usr/lib/syslinux/modules/bios/vesamenu.c32 /var/lib/tftpboot/

# iPXE script — HTTP'ye yönlendir
cat > /var/lib/tftpboot/boot.ipxe << 'EOF'
#!ipxe
dhcp
kernel http://10.0.1.1/ubuntu/casper/vmlinuz
initrd http://10.0.1.1/ubuntu/casper/initrd
imgargs vmlinuz autoinstall ds=nocloud-net;s=http://10.0.1.1/cloud-init/ quiet
boot
EOF

# Default PXE menüsü
cat > /var/lib/tftpboot/pxelinux.cfg/default << 'EOF'
DEFAULT ubuntu-autoinstall
LABEL ubuntu-autoinstall
  KERNEL ubuntu/casper/vmlinuz
  APPEND initrd=ubuntu/casper/initrd autoinstall ds=nocloud-net;s=http://10.0.1.1/cloud-init/ quiet
EOF

# -----------------------------------------------------------
# 4. NGINX — HTTP FILE SERVER (OS İMAJI + CLOUD-INIT)
# -----------------------------------------------------------

apt install -y nginx

# Ubuntu ISO'yu indir ve mount et
wget -O /tmp/ubuntu-22.04-live-server-amd64.iso \
  https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso

mkdir -p /var/www/html/ubuntu
mount -o loop /tmp/ubuntu-22.04-live-server-amd64.iso /mnt
cp -r /mnt/* /var/www/html/ubuntu/
umount /mnt

# cloud-init dosyalarını hazırla (bir sonraki adımda)
mkdir -p /var/www/html/cloud-init

systemctl restart nginx
systemctl enable nginx

# -----------------------------------------------------------
# 5. TEST
# -----------------------------------------------------------

# Servislerin çalıştığını doğrula
systemctl status dnsmasq
systemctl status nginx

# TFTP dosyalarının erişilebilir olduğunu test et
tftp 10.0.1.1 -c get pxelinux.0 /tmp/test-pxelinux.0

# Artık yeni bir makineyi ağa bağladığında:
# 1. DHCP'den IP alır
# 2. TFTP'den iPXE loader indirir
# 3. HTTP'den Ubuntu imajı + autoinstall config indirir
# 4. Ubuntu otomatik kurulur
