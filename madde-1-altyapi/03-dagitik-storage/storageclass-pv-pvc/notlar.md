# 📝 Notlar

## Neden var?
Pod'un disk istemesi ile o diskin nereden geleceği birbirinden ayrı olmalı. Pod "bana 100 GB disk lazım" der, nereden geldiğini bilmez. Ceph'ten mi, Longhorn'dan mı, local diskten mi? Bu soyutlamayı StorageClass -> PV -> PVC zinciri sağlar.

Temel:
StorageClass: "Ben Ceph'ten dinamik PV sağlarım" diyen şablon.
PV: Cluster'daki gerçek disk kaynağı.
PVC: Pod'un disk talebi ("Bana 100 GB RWO lazım").

Akış:
1. Admin StorageClass tanımlar (Ceph veya Longhorn).
2. Pod PVC talep eder: "10 GB, ReadWriteOnce".
3. K8s uygun StorageClass'ı bulur.
4. StorageClass dinamik olarak PV oluşturur.
5. PVC -> PV bind olur.
6. Pod PVC'yi mount eder.

Access Mode'lar:
ReadWriteOnce (RWO): Tek pod okur/yazar (RBD, Longhorn).
ReadWriteMany (RWX): Çok pod okur/yazar (CephFS).
ReadOnlyMany (ROX): Çok okur, kimse yazmaz.

Pod silinirse PVC ve PV ne olur? Veri kaybolur mu?
Pod silinirse PVC ve PV'ye bir şey olmaz, birbirinden izole. Ama PVC silinirse Reclaim Policy'e göre PV'nin durumu değişir:
Delete: PVC silinince PV de silinir, veri gider (default dinamik PV'lerde).
Retain: PVC silinse de PV kalır, veri korunur (manuel temizleme gerekir).
Recycle: Eski, artık kullanılmıyor.

## Anahtar Kavramlar
- StorageClass: PV'nin nasıl sağlanacağını tanımlar. Provisioner (ceph.rook.io, driver.longhorn.io), Reclaim Policy, ve parametreler burada.
- Dynamic Provisioning: PVC oluşturunca StorageClass otomatik PV açar. Admin elle PV oluşturmak zorunda kalmaz.
- Static Provisioning: Admin önceden PV oluşturur, PVC onu bulur. Eski yöntem, büyük cluster'da yönetilmez.
- Reclaim Policy Delete: Production'da dikkat. PVC silinirse veri de gider. Yanlışlıkla silinebilir.
- Reclaim Policy Retain: DB volume'leri için tercih. PVC silinse bile veri duruyor, elle temizlenir.
- Bound: PVC ve PV eşleşti, pod bağlanabilir.
- Pending: PVC için uygun PV bulunamadı veya henüz provisioning devam ediyor.

## Kendi Notum
Şöyle düşün, bir otel rezervasyon sistemi gibi. StorageClass = "standart oda" veya "suit oda" kategorisi. PVC = "suit oda istiyorum" rezervasyonu. PV = gerçek 301 numaralı suit oda. K8s bu rezervasyonu karşılayan odayı buluyor ve sana veriyor (bind). Pod gidince oda boşalıyor ama oda hala orada (Retain). Otel müdürü (Admin) "bu oda artık kirlendi, sil" derse o zaman gider (Delete).

Production'da kritik olan şu: PVC'yi yanlışlıkla silersen ve Reclaim Policy Delete ise verini kaybedersin. Önemli volume'lerde Retain kullan, en kötü ihtimalle veriyi elle temizlersin ama geri dönemezsin.

## Karşılaştığım Hatalar
k3d'de local-path StorageClass ile PVC oluşturup pod'a mount ettim, bu çalıştı. Pod silinince PVC kaldı, veri de kaldı. Sonra PVC'yi sildim, local-path default Reclaim Policy Delete olduğu için PV de gitti. Bunu kasıtlı test ettim, production'da Retain ne kadar önemli, gözlemledim.

Disk simülasyonu: `k3d node stop` ile node'u durdurunca o node'daki pod başka node'a taşındı ama local-path storage o node'da kaldığı için pod yeni node'da volume'ü bulamadı ve `Pending` kaldı. Gerçek distributed storage (Ceph/Longhorn) olsaydı veri başka node'dan gelirdi.

## Kaynaklar
- K8s Storage belgeleri: https://kubernetes.io/docs/concepts/storage/
- StorageClass kavramları: https://kubernetes.io/docs/concepts/storage/storage-classes/
- PVC lifecycle: https://kubernetes.io/docs/concepts/storage/persistent-volumes/#lifecycle-of-a-volume-and-claim
