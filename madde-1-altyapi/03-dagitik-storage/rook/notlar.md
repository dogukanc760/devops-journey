# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Ceph güçlü ama kurmak ve yönetmek karmaşık, onlarca config dosyası, manuel cluster kurulumu, disk yönetimi... Rook bunu K8s Operator Pattern ile otomatize eder. "Ceph'i K8s'e sığdıran wrapper" diyebilirsin. Rook olmasa Ceph'i K8s dışında ayrı bir sistem olarak yönetmek zorunda kalırsın. 

Temel:
Rook bir K8s Operatorüdür, CRD'ler aracılığıyla Ceph Clusterını K8s kaynağı gibi yönetir.
CephCluster, CephBlockPool, CephFileSystem gibi custom resourceları tanımlar.
Disk ekle/çıkar, node ekle/çıkar -> Rook otomatik halleder.
StorageClass oluşturur-> PVC talep edince Rook Ototmatik PV sağlar. 

kubectl apply -f cephcluster.yaml
          ↓
Rook Operator görür
          ↓
Ceph cluster ayağa kalkar
          ↓
StorageClass hazır → PVC → otomatik PV

Soru: Operator Pattern nedir? Rook neden bir Operator, sadece bir Helm chart değil?
Cevap: Operator Pattern (Operatör Deseni), genellikle Kubernetes ortamında kullanılan bir tasarım modelidir. İnsan operatörlerin manuel olarak yönettiği karmaşık uygulama süreçlerini (kurulum, ölçeklendirme, yedekleme) otomatize eder. Bunu, sistemin mevcut durumu ile istenen durumunu(state) sürekli karşılaştırarak ve aradaki farkı kapatacak asiyonlar alarak yapar. 
Bu desen Kubernetes'in, yerleşik yönetim mantığını kendi özel yazılımınızla genişletmenize olanak tanır. 
Üç temel bileşenden oluşur:
Custom Resource(CR): Kubernetes API'sine eklenen özel kaynak tanımıdır(Örn: Veritabanı veya yedekleme).
Custom Resource Definition(CRD): Bu özel kaynağın yapısını ve şemasını sisteme tanıtan dosyadır.
Controller(Denetleyici): Sürekli olarak durumu izleyen ve tanımlanan hedefe ulaşmak için çalışan arka plan yazılım döngüsüdür.

Nasıl Çalışır?:
1- Kallanıcı veya başka bir sistem, istenen hedef durumunu (Desired State) sisteme girer.
2- Controller, Kubernetes API üstünden durumu izler
3- Mevcut Durum (Current State) ile hedef durum araısnda bir sapma veya eksiklik tespit eder.
4- Operatör, hedef duruma ulaşmak için gerekli olan API çağrılarını yapar ve sistemi dengeler. 

Örneğin, bir veritabanı operatörü, çökme durumunda veritabanını otomatik olarak ayağa kaldırabilir, versiyon güncellemelerini yönetebilir veya otomatik yedekleme alabilir.
Popüler örnekleri, 
ArgoCD, Prometheus, Operator SDK, Kubebuilder.

Rook ise sadece bir helm chart olamazdı çünkü Helm ve Operatör desenleri tamamen birbirinden farklıdır. Aralarında ki temel fark şu anatoloji ile açıklanabilir; "Helm bir Paket Servis Kurye elemanı gibidir, Operatör ise içeride çalışan Uzman Bir Robot aşçıdır".
Helm, Rook'un kendisini ve gerekli tanımlarını Kubernetes kümenize ilk gün kurmanız için kullanılan harika bir araçtır. Ancak kurulduktan sonra aradan çekilir. Rook gibi karmaşık bir depolama(storage) 2. gün operasyonlarında akıllı bir yöneticiye ihtiyaçları vardır. 
Rook'un sadece bir Helm Chart değil, bir Operatör olmasının sebebi şunlardır:

1- Sürekli Durum Takibi(Day 2 Operations):
Helm: Kurulum anında şablonları(YAML dosyalarını) Kubernetes'e gönderir ve görevi biter. Eğer cluster içinde bir disk arızalanırsa Helm'in bundan haberi olmaz ve müdahale edemez.
Rook: Sürekli olarak (7/24) çalışan aktif bir kod döngüsüdür. Kümedeki disklerin sağlığını, Ceph bileşenlerinin(MON, OSD, MGR) durumunu anlık izler.

2- Akıllı Arıza Yönetimi ve Kendi Kendini İyileştirme (Self-healing):
Bir Kubernetes düğümü(node) çöktüğünde üzerinde ki diskler de erişilmez olur.
Helm Chart bu durumda bir şey yapamazken, Rook operatörü durumu anlar. Ceph verilerinin replikasyonunu(kopyalarını) korumak için diğer sağlam düğümlerde ki boş diskleri devreye sokarak veriyi otomatik olarak yeniden dengeler(rebalancing).

3- Karmaşık Güncelleme ve Ölçme Mantığı 
Depolama sistemlerinde (Ceph gibi) tüm podları aynı anda kapatıp açamazsınız, aksi takdirde veri kaybı yaşanır.
Rook Operatörü, veritabanı veya depolama mantığını bildiği için güncellemeleri sırayla yapar(rolling update). Önce bir monitör podunu günceller, onun sağlıklı çalıştığından emin olduktan sonra diğerlerine geçer. Helm bu tarz karmaşık "uygulama içi" mantıkları tek başına yönetemez. 

4- Altyapı ile doğrudan konusma yeteneği
Rook, düğümlerin üzerinde ki ham diskleri(/dev/sdb gibi lokal cihazları) algılamak, bunları formatlamak ve Ceph'e dahil etmek zorundadır.

Bu işlem dinamik bir keşif (discovery) ve işletim sistemi seviyesinde yönetim gerektirir. Statik YAML şablonları üreten Helm, o an makinede hangi disklerin takılı olduğunu bilemez. 
 
## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- 
Operator Pattern nedir
CRD / CR nedir
Controller loop nedir

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Bak Junior arkadaşım, K8s de depolamayı yöneten Ceph'i sana anlattık ama karmaşası ve yönetim zorluğundan hiç bahsetmeidk. Iste burada bir Operator Patterni ile karşımızda Rook var. Bu Rook ne yapar? O koca koca OS seviyesinde çalışan ve yönetmesi çok zor olan Ceph'i K8s clusteri içerisinde tıkıştıran işleri yapar. Yani senin Cephte elle yapacağın her şeyi, senin CR-CRD tanımlarını bilerek Rook senin yerine halleder ve sende hangi node'da hangi veri var? Hangi lokal cihaz içinde hangi veri var nereye yazdık? gibi düşüncelerle uğraşmazsın. Tek yapacağın Rook'u sisteme tanıtmak ve geri kalanı ona bırakmak, storage yönetimini, hangi diskin sökülüp takılacağı gibi her şeyi o kendi halledecektir. 
## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- 
