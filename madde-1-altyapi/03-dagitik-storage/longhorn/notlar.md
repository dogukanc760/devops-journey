# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Ceph + Rook güçlü ama kurulum ve operasyonu Rook olmasına rağmen yinede ağır. Küçük/Orta ölçekli K8s clusterları için fazla karmaşık olabilir. Longhorn daha lightweight, K8s-native bir alternatif. Kurulumu basit, UI'ı var, Ceph kadar güçlü olmasa da çoğu ihtiyacı karşılar. 

Temel:
K8s-native, Ceph gibi dışarıdan gelmiyor. K8s için tasarlandı.
Her node'daki diski otomatik algılar ve Cluster'a ekler.
Her Volume için bir replica sayısı belirlersin (default:3)
Longhorn UI-> Browserdan disk durumu, replicalar, backup görülebilir
CSI driver ile çalışır -> PVC talep edince otomatik volume sağlar
Snapshot ve backup(S3'e) desteği var.

Ceph + Rook  → Enterprise, büyük cluster, çok özellik, karmaşık
Longhorn     → Lightweight, K8s-native, kolay kurulum, orta ölçek

Örnek Soru:
Sorum: Ceph'in RBD'si var, Longhorn'un da block storage'ı var. İkisi arasında nasıl seçim yaparsın? Hangi durumda Longhorn, hangi durumda Ceph tercih edilir?
Cevap:
Ceph seç:

Object Storage (S3-uyumlu MinIO alternatifi) veya CephFS (ReadWriteMany) lazımsa → Longhorn bunu yapamaz
Çok büyük cluster (10+ node), enterprise ortam
OS seviyesinde disk yönetimi, advanced feature lazımsa

Longhorn seç:

Sadece block storage (ReadWriteOnce) yeterliyse
3-10 node arası cluster, kurulum kolaylığı öncelikliyse
UI üzerinden görsel yönetim istiyorsan

postgresql örneğinde ikisi de çalışır  100-150 pod DB'ye bağlanıyor ama storage'a yazan sadece PostgreSQL pod'u, ReadWriteOnce yeterli. Buradaki seçim kriteri yoğunluk değil, cluster büyüklüğü ve ihtiyaç duyulan feature'lar.

Longhorn → sadece RWO block storage yeterliyse, küçük/orta cluster
Ceph     → RWX, Object Storage, büyük cluster, enterprise
## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- 

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- 
