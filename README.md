# DevOps & Platform Engineering Handbook

> Türkçe DevOps kaynak eksikliğine karşı oluşturulmuş pratik el kitabı.  
> Her konu: **neden var → nasıl çalışır → lab ortamında nasıl uygulanır** formatında ele alınır.

---

## Bu Kitap Hakkında

Türkiye'de Senior DevOps / Platform Engineer olmak isteyenler için Türkçe kapsamlı kaynak bulmak hâlâ zor. Bu handbook:

- İngilizce dokümantasyonu takip etmek için gerekli altyapıyı Türkçe kurar
- Her konuyu soyut bırakmaz; **çalışan komutlar, gerçek hata mesajları ve çözümleri** içerir
- Lab ortamı olarak **Mac + k3d** kullanır, bare-metal senaryolar için ayrıca belgelenmiştir
- Production-grade kararların arkasındaki **"neden?"** sorusunu yanıtlar

---

## Kapsam

```
madde-1-altyapi/
├── 01-high-availability/         → etcd quorum, HA cluster, k3d multi-node
├── 02-ag-linux-temelleri/        → IP/CIDR, VLAN, DNS, NAT, iptables, L4/L7
├── 03-dagitik-storage/           → Ceph, Rook, Longhorn, StorageClass/PV/PVC
├── 04-k8s-derinligi/             → Control Plane, StatefulSet, Operator, Ingress TLS
└── 05-bare-metal-provisioning/   → PXE, MaaS, Tinkerbell, cloud-init

madde-2-iac/                      → Terraform, Ansible, Helm, Kustomize
madde-3-guvenlik/                 → OPA/Gatekeeper, Vault, mTLS, RBAC, NetworkPolicy
madde-4-gitops/                   → ArgoCD, Flux, GitOps prensipleri
madde-5-gozlemlenebilirlik/       → Prometheus, Grafana, Loki, Jaeger, OpenTelemetry
madde-6-trafik-kural/             → Istio, Linkerd, Service Mesh, Envoy, Rate Limiting
madde-7-k8s-dev/                  → Operator SDK, CRD, Admission Webhook, Controller
madde-8-platform/                 → Backstage, IDP, Golden Path, Developer Portal
```

**Toplam:** 8 madde / 25 subtopic / 181 pratik görev

---

## Lab Ortamı

| Bileşen | Araç | Not |
|---------|------|-----|
| Local Kubernetes | k3d (Docker içinde K3s) | Mac M-serisi uyumlu |
| Bare-Metal Sim. | k3d multi-node | Kernel kısıtları belgeli |
| Bare-Metal Gerçek | MaaS veya Tinkerbell | 05 klasörü |
| Container Runtime | containerd | k3d içinde gömülü |
| Ingress | Nginx Ingress Controller | MetalLB olmadan port-forward |
| Storage (local) | local-path provisioner | k3d default |
| Storage (prod) | Rook-Ceph / Longhorn | Bare-metal gerektirir |

---

## Madde 1 — Temel Altyapı, Sanallaştırma ve Storage

### 1.1 High Availability (HA)

**Neden:** Tek node olan bir cluster, node düşünce servisi tamamen keser. HA, etcd quorum ile bu riski dağıtır.

**Temel kavramlar:**
- **etcd:** K8s'in tüm state'ini tutan distributed key-value store. Quorum için `2n+1` node gerekir (3 node → 1 arıza tolere eder).
- **Control Plane bileşenleri:** API Server (tüm istekler buraya gelir), Controller Manager (desired state'i korur), Scheduler (pod → node ataması), etcd.
- **k3d HA cluster:**

```bash
k3d cluster create ha-cluster \
  --config madde-1-altyapi/01-high-availability/ha-cluster.yaml
```

`ha-cluster.yaml` içinde: 3 server (etcd quorum), 2 agent, port mapping 8080→80 / 8443→443.

---

### 1.2 Ağ ve Linux Temelleri

#### IP / CIDR / Subnetting

- `/28` = 16 IP, 14 kullanılabilir host
- K8s pod CIDR: `10.244.0.0/16` (65536 adres — her pod kendi IP'sini alır)

#### VLAN (802.1Q)

- **Access port:** Tek VLAN, tag'siz (son kullanıcı cihazları)
- **Trunk port:** Birden fazla VLAN, 802.1Q tag'li (switch-switch, switch-router)

#### DNS / CoreDNS

K8s içinde `myapp.local` custom domain:

```bash
# CoreDNS ConfigMap'e custom zone ekle
kubectl apply -f madde-1-altyapi/02-ag-linux-temelleri/dns/coredns-custom.yaml
# Test
kubectl run test-dns --image=busybox --restart=Never --rm -it -- nslookup myapp.local
```

#### NAT — SNAT / DNAT

- **SNAT (Masquerade):** Pod'dan internet'e → kaynak IP değişir (pod IP → node IP)
- **DNAT:** Dışarıdan servise → hedef IP değişir (NodePort/LB IP → pod IP)
- **K8s DNAT zinciri:** `KUBE-SERVICES → KUBE-SVC-xxx → KUBE-SEP-xxx`

#### L4 vs L7 Load Balancing

| | L4 (TCP/UDP) | L7 (HTTP/gRPC) |
|-|-------------|----------------|
| İncelediği | IP + Port | URL, Header, Body |
| Örnek | MetalLB, kube-proxy | Nginx Ingress, Traefik |
| Her ikisi | — | **Service Mesh** (Istio/Linkerd) |

**Gelen istek akışı:** `İnternet → MetalLB (L4) → Nginx Ingress (L7) → Pod`

#### iptables

```bash
# K8s DNAT zincirini gözlemle
iptables -t nat -L KUBE-SERVICES --line-numbers
```

---

### 1.3 Dağıtık Storage

#### Ceph (Rook Operator)

- **RBD (Block):** PVC → single pod, ReadWriteOnce — veritabanları için
- **CephFS (File):** PVC → multi-pod, ReadWriteMany — paylaşımlı dosya sistemi
- **Object (S3-compat.):** HTTP API, MinIO da Object Storage'dır

```bash
# Rook operator (bare-metal'da çalışır)
helm install rook-ceph rook-release/rook-ceph -n rook-ceph --create-namespace
kubectl apply -f rook-ceph/komutlar.sh  # CephCluster CRD
```

> **Not:** k3d'de Unix socket chown kısıtı var, bare-metal gerektirir.

#### Longhorn

Lightweight distributed block storage, K8s-native.

```bash
helm install longhorn longhorn/longhorn -n longhorn-system --create-namespace
```

> **Not:** k3d node'larında `open-iscsi` yüklü değil, bare-metal gerektirir.

#### StorageClass → PV → PVC Zinciri

```
StorageClass (tanım)
  └── PVC oluştur (talep)
        └── PV otomatik yaratılır (provisioner)
              └── Pod'a mount edilir
```

**Reclaim Policy:**
- `Delete`: PVC silinince PV de silinir (default, ephemeral data)
- `Retain`: PV kalır, veri korunur (production DB'ler için)

---

### 1.4 Kubernetes Derinliği

#### Ingress + TLS

```bash
# Self-signed sertifika
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=myapp.local"
kubectl create secret tls myapp-tls --key tls.key --cert tls.crt

# Test (MetalLB olmadan)
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 9443:443
curl -k -H "Host: myapp.local" https://127.0.0.1:9443
```

#### StatefulSet

Deployment'tan farkı:
- **Stable identity:** `postgres-0`, `postgres-1` (rastgele değil)
- **Sıralı başlatma/kapatma:** 0 → 1 → 2 (Deployment paralel)
- **volumeClaimTemplates:** Her pod kendi PVC'sini alır

```bash
kubectl delete pod postgres-0   # pod ölür
# → postgres-0 olarak yeniden başlar, AYNI PVC'ye bağlanır
```

#### etcd Backup

```bash
# k3d HA cluster'da
docker exec k3d-ha-cluster-server-0 k3s etcd-snapshot save
# Snapshot: /var/lib/rancher/k3s/server/db/snapshots/
```

#### Operator Pattern

CRD + Controller. `CephCluster` yazdın → Rook controller Ceph'i ayağa kaldırdı. Aynı mantık CloudNativePG, cert-manager vb.

---

### 1.5 Bare-Metal Provisioning

#### PXE Boot Zinciri

```
Makine açılır
  → DHCP'den IP + next-server alır (dnsmasq)
  → TFTP'den iPXE loader indirir
  → HTTP'den OS imajı + autoinstall config indirir
  → Ubuntu kurulur
```

Komutlar: `05-bare-metal-provisioning/pxe-boot/komutlar.sh`

#### MaaS (Metal as a Service)

Canonical'ın datacenter provisioning çözümü. Fiziksel makineyi:  
`Enlist → Commission → Test → Ready → Deploy → Deployed`

BMC (IPMI) üzerinden makineleri uzaktan açıp kapatabilir.

Komutlar: `05-bare-metal-provisioning/maas/komutlar.sh`

#### Tinkerbell (CNCF)

GitOps-friendly, workflow tabanlı. Her provisioning adımı bir container action.

```yaml
# Workflow: hardware + template bağlar
kind: Workflow
spec:
  templateRef: ubuntu-22-04
  hardwareRef: worker-node-01
```

Komutlar: `05-bare-metal-provisioning/tinkerbell/komutlar.sh`

#### cloud-init / autoinstall

- **cloud-init:** OS boot sonrası çalışır, kullanıcı/paket/dosya/komut yapılandırır
- **autoinstall:** Ubuntu kurulum sırasında okunur (subiquity), disk bölümleme dahil

```yaml
#cloud-config
packages: [curl, git, open-iscsi]
runcmd:
  - systemctl enable --now open-iscsi
```

Komutlar: `05-bare-metal-provisioning/cloud-init/komutlar.sh`

---

## Klasör Yapısı Kuralları

Her konu klasöründe:

```
konu-adi/
├── notlar.md       → kendi kelimelerinle özet (Feynman tekniği)
├── komutlar.sh     → çalıştırılan komutlar + açıklamalar
└── *.yaml          → manifest / config dosyaları
```

Pratik görevler o subtask'ın tüm konuları bittikten sonra yapılır.

---

## Katkı ve Kullanım

Bu handbook açık geliştirilmektedir. Hata, eksik veya Türkçe çeviri önerisi için PR açabilirsiniz.

Her komut gerçek lab ortamında test edilmiştir. Hata mesajları ve çözümleri ilgili `notlar.md` ve `komutlar.sh` dosyalarına eklenmiştir.
