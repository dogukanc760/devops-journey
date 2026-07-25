#!/bin/bash
# ============================================================
# Pratik Görev: Tinkerbell ile Bare-Metal Provisioning
# CNCF projesi — workflow tabanlı, GitOps-friendly
# Gereksinim: Ubuntu 22.04 makine (Tinkerbell stack host)
#             + en az 1 hedef bare-metal node
# ============================================================

# -----------------------------------------------------------
# 1. TİNKERBELL STACK KURULUMU (Docker Compose)
# -----------------------------------------------------------

# Prerequisite
apt update && apt install -y docker.io docker-compose-plugin curl

# Tinkerbell repo'yu indir
git clone https://github.com/tinkerbell/sandbox.git
cd sandbox/deploy/stack/compose

# .env dosyasını düzenle
cat > .env << 'EOF'
# Tinkerbell stack IP (bu makinenin eth0 IP'si)
PUBLIC_IP=10.0.1.1
TINKERBELL_HOST_IP=10.0.1.1

# DHCP aralığı
DHCP_RANGE_START=10.0.1.2
DHCP_RANGE_END=10.0.1.14
EOF

# Stack'i başlat
docker compose up -d

# Servislerin ayakta olduğunu doğrula
docker compose ps
# Beklenen: boots, hegel, tink-server, tink-controller, db, nginx

# -----------------------------------------------------------
# 2. HARDWARe KAYDINI OLUŞTUR
# -----------------------------------------------------------

# Hedef makinenin MAC adresini öğren (BMC veya fiziksel bakış)
TARGET_MAC="AA:BB:CC:DD:EE:FF"
TARGET_IP="10.0.1.10"

# Hardware manifest
cat > hardware.yaml << 'EOF'
apiVersion: "tinkerbell.org/v1alpha1"
kind: Hardware
metadata:
  name: worker-node-01
  namespace: tink-system
spec:
  disks:
    - device: /dev/sda
  metadata:
    facility:
      facility_code: lab
    instance:
      hostname: worker-01
      id: "worker-01-id"
      operating_system:
        distro: ubuntu
        os_slug: ubuntu_22_04
        version: "22.04"
  interfaces:
    - dhcp:
        arch: x86_64
        hostname: worker-01
        ip:
          address: 10.0.1.10
          gateway: 10.0.1.1
          netmask: 255.255.255.240
        mac: AA:BB:CC:DD:EE:FF
        name_servers:
          - 8.8.8.8
        uefi: false
      netboot:
        allowPXE: true
        allowWorkflow: true
EOF

# Hardware'i kaydet
kubectl apply -f hardware.yaml -n tink-system
# VEYA tink CLI ile:
docker exec -i tink-cli tink hardware push < hardware.yaml

# -----------------------------------------------------------
# 3. TEMPLATE — PROVISIONING WORKFLOW'U TANIMLA
# -----------------------------------------------------------

cat > template-ubuntu.yaml << 'EOF'
apiVersion: "tinkerbell.org/v1alpha1"
kind: Template
metadata:
  name: ubuntu-22-04
  namespace: tink-system
spec:
  data: |
    version: "0.1"
    name: ubuntu-22-04
    global_timeout: 600
    tasks:
      - name: "os-installation"
        worker: "{{.device_1}}"
        volumes:
          - /dev:/dev
          - /dev/console:/dev/console
          - /lib/firmware:/lib/firmware:ro
        actions:

          - name: "stream-ubuntu-image"
            image: quay.io/tinkerbell-actions/image2disk:v1.0.0
            timeout: 600
            environment:
              DEST_DISK: /dev/sda
              IMG_URL: "http://10.0.1.1/ubuntu-22.04-preinstalled-server-amd64.img.gz"
              COMPRESSED: true

          - name: "grow-partition"
            image: quay.io/tinkerbell-actions/cexec:v1.0.0
            timeout: 90
            environment:
              BLOCK_DEVICE: /dev/sda
              FS_TYPE: ext4
              CHROOT: y
              DEFAULT_INTERPRETER: "/bin/sh -c"
              CMD_LINE: "growpart /dev/sda 1 && resize2fs /dev/sda1"

          - name: "install-cloud-init"
            image: quay.io/tinkerbell-actions/writefile:v1.0.0
            timeout: 90
            environment:
              DEST_DISK: /dev/sda
              DEST_PATH: /var/lib/cloud/seed/nocloud/user-data
              FS_TYPE: ext4
              CONTENTS: |
                #cloud-config
                hostname: worker-01
                users:
                  - name: ubuntu
                    sudo: ALL=(ALL) NOPASSWD:ALL
                    ssh_authorized_keys:
                      - ssh-rsa AAAA...SENIN_PUBLIC_KEY'IN
                package_update: true
                runcmd:
                  - echo "Tinkerbell provisioning complete" > /etc/motd

          - name: "reboot"
            image: quay.io/tinkerbell-actions/reboot:v1.0.0
            timeout: 90
            volumes:
              - /worker:/worker
EOF

kubectl apply -f template-ubuntu.yaml -n tink-system

# -----------------------------------------------------------
# 4. WORKFLOW — HARDWARE + TEMPLATE'İ BAĞLA
# -----------------------------------------------------------

cat > workflow.yaml << 'EOF'
apiVersion: "tinkerbell.org/v1alpha1"
kind: Workflow
metadata:
  name: workflow-worker-01
  namespace: tink-system
spec:
  templateRef: ubuntu-22-04
  hardwareRef: worker-node-01
  hardwareMap:
    device_1: AA:BB:CC:DD:EE:FF
EOF

kubectl apply -f workflow.yaml -n tink-system

# -----------------------------------------------------------
# 5. WORKFLOW'U İZLE
# -----------------------------------------------------------

# Workflow durumunu takip et
kubectl get workflow workflow-worker-01 -n tink-system -w

# Action-level detay
kubectl describe workflow workflow-worker-01 -n tink-system

# tink CLI ile
docker exec tink-cli tink workflow events workflow-worker-01

# -----------------------------------------------------------
# 6. DOĞRULAMA
# -----------------------------------------------------------

# SSH ile bağlan (provisioning tamamlandıktan sonra)
ssh ubuntu@10.0.1.10

# Workflow tamamlandı mı?
kubectl get workflow workflow-worker-01 -n tink-system \
  -o jsonpath='{.status.state}'
# Beklenen: STATE_SUCCESS

# -----------------------------------------------------------
# TINKERBELL vs MAAS FARK
# -----------------------------------------------------------
# MaaS:        GUI + API odaklı, büyük datacenter yönetimi
# Tinkerbell:  GitOps odaklı, workflow = kod, CNCF ekosistemi
#              Her adım bir container action → değiştirilebilir
#              Kubernetes-native, Helm ile kurulabilir
