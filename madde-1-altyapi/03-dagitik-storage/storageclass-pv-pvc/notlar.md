# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Podun disk istemesi ile o diskin nereden geleceği birbirinden ayrı olmalı. Pod "bana 100 GB disk lazım" der, nereden geldiğini bilmez. Ceph'ten mi yoksa Longhorn'dan mı yoksa local diskten mi? Bu soyutlamayı StorageClass->PV->PVC zinciri sağlar.

Temel:
StorageClass -> "Ben Ceph'ten dinamik PV sağlarım" diyen şablon
PV-> Cluster'daki gerçek disk kaynağı
PVC-> Podun disk talebi ("Bana 100 GB RWO yada RWX lazım")

Akış:
1- Admin StorageClass tanımlar (Ceph yada Longhorn)
2- Pod PVC talep eder: "10GB, ReadWriteOnce(RWO)"
3- K8s uygun StorageClass'ı bulur
4- StorageClass dinamik olarak PV oluşturur
5- PVC->PV bind olur
6- Pod PVC'yi mount eder

Access Mode'lar:
ReadWriteOnce(RWO)-> tek pod okur/yazar(RBD, Longhorn)
ReadWriteMany(RWX)-> çok pod okur/yazar(CephFS)
ReadOnlyMany(ROX)-> Çok okur, kimse yazmaz. 

Örnek Soru:
Bir pod silinirse PVC ve PV ne olur? Veri kaybolur mu?
Cevap:
PVC bizim tanımlamalarımızı yaparken zaten söylediğimiz limitler dahilidir yani kaybolmaz bir şey olmaz yaml içerisinde veya o podu tanımlayan deployment içerisinde zaten durur, e PV de zaten podun değil clusterın disk kaynağı isterse silinsin pod bunlar birbirinden izole ve veri kaybı olmaz ha diyelim komple uçtuk Replica Factor denen kavram var zaten veriler başka yerde aynı anda yedekleniyor ve eşleniyor.
Yanlız tek bir nüans var, PVC'nin ne olacağı Reclaim Policy ile belirlenir yani,
Delete -> PVC silinince PV'de silinir, veri gider (default dinamik PV'lerde)
Retain -> PVC silinse de PV kalır, veri korunur(Manuel temizleme gerekir)
Recycle -> Eski, artık kullanılmıyor.
Yani pod silinirse PVC ve PV'ye bir şey olmaz ama PVC silinirse Reclaim Policy'e göre PV ve veri silinebilir. Bu production'da kritik bir detay.
Replication factor kısmı da doğru Ceph/Longhorn zaten 3 kopya tutuyor, tek disk gitse bile veri başka node'da yaşıyor.
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
