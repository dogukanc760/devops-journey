# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
K8s'de podlar farklı nodelarda çalışır ama veri tek bir diskte olursa o node ölünce veri gider. Ceph veriyi birden fazla node'a dagıtarak hem yüksek erişilebilirlilik hemde yüksek performans sağlar. Olmasa, distributed sistem için merkezi bir storage çözümüne mahkum kalırız, bu da "single point of failure" olur.

3 Temel Storage tipi var,
RBD(RADOS Block Device) -> Tek bir pod'a bağlanan block storage, TIpkı bir sabit disk gibi, sadece bir pod okuyup yazabilir. PostgreSQLgibi DB'ler için ideal.

CephFS -> Birden fazla podun aynı anda okuyup yazabildiği dosya sistemi. ReadWriteMany PVC gerektiğinde kullanılır.

Object Storage ->S3 Uyumlu, HTTP API üzerinden erişilen nesne depolama, Resim, Video, backup gibi büyük dosyalar içindir.


Örnek soru:
RBD ve CephFS farkı nedir? Bir Web uygulamasında statik dosyaları (CSS, js) saklamak için hangisini kullanırsın?
Cevap:
Statik dosyalar için RBD daha doğru bir yaklasım, sebebi şu:
Statik dosyalar (CSS, JS, Resim...) genellikle tek bir pod tarafından serve edilir (örn: nginx pod). O pod tek başına okur, başka pod aynı anda yazmaz. RBD burada yeterli ve daha performanslı.

CephFS'i seçmen gerek durum, birden falza podun aynı anda aynı dosyalara erişmesi gerektiğinde. Örneğin 5 nginx replicasının aynı statik dosyaları serve etmesi, o zaman ReadWriteMany lazım, yani CephFS doğru seçim.

RBD sadece ReadWriteOnce, yani tek pod bağlanabilir. Birden fazla pod aynı RBD'ye bağlanamaz. 

Örnek bir senaryoyla, diyelim ki Microservice mimarisinde geliştirdiğimiz bir backend ağımız var. Bu ağda 50 tane servis aynı DB poduna erişiyor çünkü geniş bir data consistency konusuyla uğraşmak istemiyorlar. Şimdi burada RBD'mi yoksa CephFS mi? E tek pod için demiştik RBD'yi?

Örnek Senaryo için cevabımız şöyle, burada kafa karıştıran o uygulama veya serve edilen kaynağa yazma işini kaç pod yapıyor? Yani storage'a kaç pod yazıyor? Bu önemli 50 tane pod erişsede aslında orada storega'a yazma konusunu PostgreSQL containerını yöneten pod hallediyor ve DB kendi concurrency'sini yönetebiliyor. Bu sebeple bu örnek senaryo içinde RBD tercih edilmesi önerilir.

Başka bir örnek soru:
O zaman diyelim ki S3 yaklasımı için Minio deploy ettim Object Storage mı yoksa CephFS mi ?
Cevap:
Object Storage  MinIO zaten S3-uyumlu object storage'ın ta kendisi. HTTP API üzerinden PUT/GET/DELETE ile çalışır, dosya sistemi değil.
CephFS ile MinIO'yu karıştırma  MinIO kendi başına bir object storage çözümü, Ceph'in Object Storage özelliğiyle aynı kategoride rakipler. İkisini aynı anda kullanman gerekmez.
K8s'de MinIO'nun kendi verilerini saklamak için RBD kullanırsın. MinIO pod'u tek başına yazar, block storage yeterli.
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
