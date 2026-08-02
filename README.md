# DevOps Journey — Senior DevOps & Platform Engineer Yol Haritası

> Türkçe DevOps/Platform Engineering kaynak eksikliğine karşı hazırlanmış, uygulamalı bir öğretim kaynağı.
> Her konu **neden var → nasıl çalışır → lab ortamında gerçekten uygulanır → gerçek hatalarıyla belgelenir** formatında işlenir.

---

Bu kaynak sadece araç tanıtımı değil, Platform Engineering ve DevSecOps'a odaklanan, AWS temelleriyle genişleyen uçtan uca bir öğretim materyali. Her konu gerçek hata mesajlarıyla, gerçek debug süreçleriyle işlenir, çünkü asıl öğrenilmesi gereken şey araçların isimleri değil, karar verme yargısı.

Detaylı ilerleme takibi (Durum, Öncelik, checkbox'lar) **Notion'daki roadmap veritabanında** tutuluyor, bu README sadece genel yapının haritası.

---

## Öğrenme Metodolojisi

Her konu için 7 adım sırayla işlenir:

1. **Neden var?** — "Bu olmasaydı ne olurdu?" formatında anlatım + örnek soru-cevap
2. **İpucu** — Hangi araç, nereden başlanır
3. **Kendin dene** — Çalıştır, çıktıyı gözlemle
4. **Ne gördün?** — Çıktıyı yorumla
5. **Şimdi boz** — Kasıtlı hata yap, sistemi gözlemle
6. **Bana anlat** — Feynman tekniği: 2 dakikada anlat
7. **Kendi Notum** — `notlar.md`'ye kendi kelimelerinle yaz

**Kural:** Pratik görevler, bir subtask'ın (klasörün) tüm konuları kavramsal olarak bitmeden başlamaz.

```
Konu 1 → Konu 2 → ... → Tüm Konular Bitti → Pratik Görevler
```

---

## Klasör Yapısı Kuralı

```
madde-X-isim/
└── NN-subtask-adi/
    ├── notlar.md     → Neden var, Anahtar Kavramlar, Kendi Notum, Karşılaştığım Hatalar, Kaynaklar
    ├── komutlar.sh   → gerçekten çalıştırılan komutlar + gerçek hata/çözüm belgesi
    └── *.tf / *.yaml → varsa manifest/config dosyaları
```

Not: `-` ve `—` gibi tire işaretleri notlarda kullanılmıyor.

---

## Lab Ortamı

| Bileşen | Araç | Not |
|---|---|---|
| Local Kubernetes | k3d (Docker/OrbStack içinde K3s) | Mac Apple Silicon uyumlu |
| Container | Docker / OrbStack | Madde 2'de Packer/Terraform ile |
| Self-hosted S3 | MinIO | State backend, felaket kurtarma testleri |
| Bulut | AWS (ücretsiz katman) | Madde 9 sonrası devreye giriyor |
| CNI | Cilium (eBPF) | Madde 3'te k3d'de flannel'siz kuruldu |

---

## Yol Haritası

| # | Madde | Durum | Klasör |
|---|---|---|---|
| 1 | Temel Altyapı, Sanallaştırma ve Storage | ✅ Tamamlandı | `madde-1-altyapi/` |
| 2 | Kod Olarak Altyapı ve Konfigürasyon | ✅ Tamamlandı | `madde-2-iac/` |
| 3 | Ağ, Güvenlik ve Sır Yönetimi | 🔥 Devam ediyor (1/5) | `madde-3-guvenlik/` |
| 4 | GitOps ve Sürekli Dağıtım | 🗂 Backlog | `madde-4-gitops/` |
| 5 | İleri Seviye Gözlemlenebilirlik | 🗂 Backlog | `madde-5-gozlemlenebilirlik/` |
| 6 | Gelişmiş Trafik ve Kural Yönetimi | 🗂 Backlog | `madde-6-trafik-kural/` |
| 7 | K8s Geliştiriciliği ve Özel Araçlar | 🗂 Backlog | `madde-7-k8s-dev/` |
| 8 | Platform Mühendisliği / IDP | 🗂 Backlog | `madde-8-platform/` |
| 9 | Felaket Kurtarma ve Çoklu Cluster | 🗂 Backlog | `madde-9-felaket-kurtarma/` |
| 10 | SRE Kültürü ve Olay Yönetimi | 🗂 Backlog | `madde-10-sre-olay-yonetimi/` |
| 11 | Performans ve Kapasite Testi | 🗂 Backlog | `madde-11-performans-kapasite/` |
| 12 | Çok Kiracılı Platform (Multi-Tenancy) | 🗂 Backlog | `madde-12-multi-tenancy/` |
| 13 | Veritabanı Operasyonları ve Migration | 🗂 Backlog | `madde-13-veritabani-operasyonlari/` |
| 14 | Bulut Mimarisi ve Serverless | 🗂 Backlog | `madde-14-bulut-mimarisi/` |
| 15 | Bulut Güvenliği ve Uyumluluk | 🗂 Backlog | `madde-15-bulut-guvenlik/` |
| 16 | Veri ve Streaming Platformları | 🗂 Backlog | `madde-16-veri-streaming/` |
| 17 | MLOps ve AI Altyapısı | 🗂 Backlog | `madde-17-mlops/` |
| 18 | Sertifikasyon Yolu ve Derinlemesine Tecrübe | 🗂 Backlog | `madde-18-sertifikasyon/` |

**Toplam: 18 madde.** Madde 1-8 klasik on-premise/local Kubernetes derinliğini, Madde 9-13 gerçek dünya olgunluğunu (felaket kurtarma, SRE, kapasite, çok kiracılılık, veritabanı), Madde 14-17 bulut mimarisi ve uzmanlık alanlarını (serverless, güvenlik/uyumluluk, veri platformları, MLOps), Madde 18 ise AWS temellerinden SAA-C03 sertifikasyonuna ve gerçek dünya tecrübesine evrilen kapanış maddesini kapsıyor.

### Alt konu haritası

<details>
<summary>Madde 1 — Temel Altyapı, Sanallaştırma ve Storage</summary>

- `01-high-availability/` — etcd quorum, HA cluster
- `02-ag-linux-temelleri/` — IP/CIDR, VLAN, DNS, NAT, iptables, L4/L7
- `03-dagitik-storage/` — Ceph, Rook, Longhorn, StorageClass/PV/PVC
- `04-k8s-derinligi/` — Control Plane, StatefulSet, Operator, Ingress TLS
- `05-bare-metal-provisioning/` — PXE, MaaS, Tinkerbell, cloud-init
</details>

<details>
<summary>Madde 2 — Kod Olarak Altyapı ve Konfigürasyon</summary>

- `01-drift-detection/` — Terraform plan/apply, Atlantis, drift alarmı
- `02-immutable-infrastructure/` — Packer golden image, Blue-Green deployment
- `03-state-management/` — MinIO remote backend, state locking, workspace
</details>

<details>
<summary>Madde 3 — Ağ, Güvenlik ve Sır Yönetimi</summary>

- `01-zero-trust-network/` — Cilium, eBPF, default-deny, L7 policy, Hubble ✅
- `02-api-ingress-guvenligi/` — Rate limiting, WAF, mTLS
- `03-oidc-iam/` — Keycloak, RBAC, Service Account
- `04-vault-dynamic-secrets/` — HashiCorp Vault, dinamik DB credential
- `05-sops-sealed-secrets/` — SOPS, Sealed Secrets, GitOps uyumu
</details>

<details>
<summary>Madde 4 — GitOps ve Sürekli Dağıtım</summary>

- `01-cicd-mimari/` — Self-hosted runner, pipeline aşamaları
- `02-progressive-delivery/` — Argo Rollouts, canary, Flagger
- `03-shift-left-security/` — Trivy, SBOM, Cosign, Kyverno
- `04-environment-promotion/` — ArgoCD, dev/staging/prod promotion
</details>

<details>
<summary>Madde 5 — İleri Seviye Gözlemlenebilirlik</summary>

- `01-merkezi-loglama/` — Loki, Promtail, Grafana, LogQL
- `02-distributed-tracing/` — Tempo, OpenTelemetry, Beyla
- `03-slo-error-budget/` — SLI/SLO/SLA, burn rate, Sloth
- `04-sentetik-izleme/` — Blackbox Exporter, k6, runbook
</details>

<details>
<summary>Madde 6 — Gelişmiş Trafik ve Kural Yönetimi</summary>

- `01-service-mesh/` — Istio, mTLS, Circuit Breaker
- `02-policy-as-code/` — Kyverno, OPA Gatekeeper
- `03-chaos-engineering/` — Chaos Mesh, blast radius, game day
</details>

<details>
<summary>Madde 7 — K8s Geliştiriciliği ve Özel Araçlar</summary>

- `01-crd-operator-pattern/` — Kubebuilder, controller-runtime, reconcile loop
- `02-mutating-validating-webhooks/` — Admission Controller, Golang
- `03-devops-cli/` — Cobra, Viper, client-go
</details>

<details>
<summary>Madde 8 — Platform Mühendisliği / IDP</summary>

- `01-backstage-idp/` — Software Catalog, Scaffolder, TechDocs
- `02-finops-kubecost/` — Namespace maliyet ayrıştırma, VPA
- `03-devex-telepresence/` — Telepresence, Skaffold, inner loop
</details>

<details>
<summary>Madde 9 — Felaket Kurtarma ve Çoklu Cluster</summary>

- `01-backup-restore-velero/` — Velero, RTO/RPO
- `02-coklu-bolge-cluster-mimarisi/` — Route53 failover, cross-region S3
- `03-dr-tatbikati-runbook/` — Tabletop exercise, gerçek DR tatbikatı
</details>

<details>
<summary>Madde 10 — SRE Kültürü ve Olay Yönetimi</summary>

- `01-olay-siddeti-surec-tasarimi/` — Severity, incident commander
- `02-postmortem-toil-azaltma/` — Blameless postmortem, 5 Whys
- `03-oncall-alerting-mimarisi/` — PagerDuty, escalation policy
- `04-error-budget-karar-alma/` — Deploy freeze politikası
</details>

<details>
<summary>Madde 11 — Performans ve Kapasite Testi</summary>

- `01-load-stress-soak-test/` — k6, p50/p95/p99
- `02-kapasite-planlama/` — Little's Law, bottleneck analizi
- `03-autoscaler-aws-olcekleme/` — HPA/VPA/Cluster Autoscaler, Spot instance
</details>

<details>
<summary>Madde 12 — Çok Kiracılı Platform (Multi-Tenancy)</summary>

- `01-namespace-vcluster-izolasyon/` — vcluster, noisy neighbor
- `02-maliyet-chargeback-tenant/` — Kubecost chargeback, onboarding/offboarding
- `03-aws-node-iam-izolasyon/` — IRSA, taint/toleration
</details>

<details>
<summary>Madde 13 — Veritabanı Operasyonları ve Migration Stratejisi</summary>

- `01-zero-downtime-migration/` — Expand-contract pattern
- `02-buyuk-tablo-online-schema-change/` — gh-ost mantığı, backfill
- `03-aws-managed-db-operasyonlari/` — RDS/Aurora Blue-Green
</details>

<details>
<summary>Madde 14 — Bulut Mimarisi ve Serverless/Event-Driven Sistemler</summary>

- `01-mimari-karar-well-architected/` — RFC yazma, mimari kurul savunması
- `02-serverless-event-driven/` — Lambda, Step Functions, SQS/SNS, DLQ
- `03-maliyet-modelleme-finops/` — Break-even analizi
</details>

<details>
<summary>Madde 15 — Bulut Güvenliği ve Uyumluluk</summary>

- `01-organizasyonel-guvenlik-kisitlari/` — AWS Organizations, SCP, CSPM
- `02-tedarik-zinciri-guvenligi/` — SLSA, SBOM
- `03-uyumluluk-denetimi-pentest/` — SOC2 control matrix, pentest simülasyonu
</details>

<details>
<summary>Madde 16 — Veri ve Streaming Platformları</summary>

- `01-kafka-streaming-temelleri/` — Broker, partition, consumer group
- `02-schema-registry-veri-sozlesmesi/` — Avro/Protobuf, compatibility
- `03-stream-processing/` — ksqlDB, windowing
</details>

<details>
<summary>Madde 17 — MLOps ve AI Altyapısı</summary>

- `01-model-serving-altyapisi/` — KServe, GPU scheduling
- `02-training-pipeline-versiyonlama/` — MLflow, canary model deployment
- `03-production-monitoring-drift/` — Model drift, otomatik yeniden eğitim
- `04-vector-db-rag-altyapisi/` — Qdrant/Weaviate, RAG
</details>

<details>
<summary>Madde 18 — Sertifikasyon Yolu ve Derinlemesine Tecrübe</summary>

- `01-aws-temel-hizmetleri/` — IAM, S3, EC2, VPC, terraform import
- `02-derinlemesine-vaka-analizi/` — Postmortem analizi, tekrarlanan game-day
- `03-aws-saa-c03-evrim/` — SAA-C03 sınav hazırlığı ve sertifikasyon
</details>

---

## Kullanım

Bu repo açık geliştiriliyor, gerçek zamanlı öğrenme sürecinin kaydı olduğu için bazı klasörler boş şablon, bazıları tam dolu olabilir. Her `komutlar.sh`, gerçekten çalıştırılmış komutları ve karşılaşılan gerçek hataları/çözümleri içerir, kopyala-yapıştır bir tutorial değildir.
