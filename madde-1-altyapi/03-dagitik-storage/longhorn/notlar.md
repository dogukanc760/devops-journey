# 📝 Notlar

## Neden var?
Ceph + Rook güçlü ama kurulum ve operasyonu ağır. Küçük/orta ölçekli K8s cluster'ları için fazla karmaşık olabilir. Longhorn daha lightweight, K8s-native bir alternatif. Kurulumu basit, UI'ı var, Ceph kadar güçlü olmasa da çoğu ihtiyacı karşılar.

Temel:
K8s-native, Ceph gibi dışarıdan gelmiyor, K8s için tasarlandı.
Her node'daki diski otomatik algılar ve cluster'a ekler.
Her volume için bir replica sayısı belirlersin (default: 3).
Longhorn UI: Browserdan disk durumu, replica'lar, backup görülebilir.
CSI driver ile çalışır: PVC talep edince otomatik volume sağlar.
Snapshot ve backup (S3'e) desteği var.

Ceph seç:
Object Storage (S3 uyumlu) veya CephFS (ReadWriteMany) lazımsa. Longhorn bunu yapamaz.
Çok büyük cluster (10+ node), enterprise ortam.
OS seviyesinde disk yönetimi, advanced feature lazımsa.

Longhorn seç:
Sadece block storage (ReadWriteOnce) yeterliyse.
3-10 node arası cluster, kurulum kolaylığı öncelikliyse.
UI üzerinden görsel yönetim istiyorsan.

## Anahtar Kavramlar
- K8s-native: Longhorn Kubernetes içinde yaşıyor, CRD'ler ve controller'larla yönetiliyor. Ayrı bir sistem değil.
- CSI (Container Storage Interface): K8s'in storage araçlarıyla konuşma standardı. Longhorn bu interface'i uygular, PVC talep ettiğinde sistem Longhorn'u çağırır.
- Volume Replica: Longhorn her volume'ü belirtilen sayıda kopyalar. Bir node çökünce replica'dan okumaya devam eder.
- Longhorn UI: Ngin pod'u gibi, browser üzerinden diskler, volume'ler, snapshot'lar ve backup'ları görselleştirir.
- Snapshot: Volume'ün belirli bir andaki hali. Hızlı, incremental. Yanlış bir migration öncesinde snapshot alınır.
- Backup (S3): Snapshot'ları S3 uyumlu bir storage'a gönderir. Cluster'dan bağımsız, disaster recovery için.
- ReadWriteOnce (RWO): Tek pod bağlanır. Longhorn sadece RWO destekler, RWX için Ceph'e geçmek gerekir.

## Kendi Notum
Bak agam şöyle düşün, Ceph bir enterprise araç, kurulumu, yönetimi, kapasitesi hepsi büyük. Ama sen 5 node'lu bir K8s cluster kuruyorsun ve basit block storage lazım, DB volume'leri, persistent volume'ler. Ceph'i kurup yönetmek için ekstra efor harcamak istemiyorsun. İşte Longhorn tam buna karşı çıkmış. Helm install yazıyorsun, 5 dakika sonra UI'dan bütün node disklerini görüyorsun, PVC talep ediyorsun, otomatik yaratılıyor. Yeterliyse bunu kullan, Object Storage veya RWX lazımsa Ceph'e geç.

## Karşılaştığım Hatalar
k3d'de Longhorn kurmaya çalıştım:
```
helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace
```
Kurulum geçti ama pod'lar `iscsiadm/open-iscsi not found on host` hatası verdi. Sebep: k3d node'ları minimal Alpine tabanlı ve `open-iscsi` yüklü değil. Gerçek Linux node'unda `apt install open-iscsi` ile çözülür.

Bu pratik görev bare-metal lab'a ertelendi. `longhorn/komutlar.sh`'da komutlar hazır.

## Kaynaklar
- Longhorn resmi döküman: https://longhorn.io/docs/
- Longhorn GitHub: https://github.com/longhorn/longhorn
- Longhorn vs Ceph karşılaştırması: https://longhorn.io/docs/latest/what-is-longhorn/
