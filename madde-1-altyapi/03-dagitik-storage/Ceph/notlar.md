# 📝 Notlar

## Neden var?
K8s'de podlar farklı node'larda çalışır ama veri tek bir diskte olursa o node ölünce veri gider. Ceph veriyi birden fazla node'a dağıtarak hem yüksek erişilebilirlik hem de yüksek performans sağlar. Olmasa distributed sistem için merkezi bir storage çözümüne mahkum kalırız, bu da "single point of failure" olur.

3 Temel Storage tipi var:
RBD (RADOS Block Device): Tek bir pod'a bağlanan block storage. Tıpkı bir sabit disk gibi, sadece bir pod okuyup yazabilir. PostgreSQL gibi DB'ler için ideal.
CephFS: Birden fazla pod'un aynı anda okuyup yazabildiği dosya sistemi. ReadWriteMany PVC gerektiğinde kullanılır.
Object Storage: S3 uyumlu, HTTP API üzerinden erişilen nesne depolama. Resim, video, backup gibi büyük dosyalar içindir.

RBD ve CephFS farkı nedir? Statik dosyalar için hangisi?
Statik dosyalar için RBD daha doğru, sebebi şu: statik dosyalar (CSS, JS, resim) genellikle tek bir pod tarafından serve edilir. O pod tek başına okur, başka pod aynı anda yazmaz. RBD burada yeterli ve daha performanslı.
CephFS'i seçmen gereken durum: birden fazla pod'un aynı anda aynı dosyalara erişmesi gerektiğinde. Örneğin 5 nginx replica'sının aynı statik dosyaları serve etmesi, o zaman ReadWriteMany lazım, yani CephFS doğru seçim.

MinIO Object Storage mu yoksa CephFS mi?
MinIO zaten S3 uyumlu object storage'ın ta kendisi. HTTP API üzerinden PUT/GET/DELETE ile çalışır, dosya sistemi değil. MinIO ile CephFS'i karıştırma, MinIO kendi başına bir object storage çözümü, Ceph'in Object Storage özelliğiyle aynı kategoride rakipler. K8s'de MinIO'nun kendi verilerini saklamak için RBD kullanırsın.

## Anahtar Kavramlar
- RADOS: Ceph'in alttaki dağıtık nesne deposu. Her şeyin altında bu var, RBD ve CephFS üstüne inşa edilmiş.
- RBD: ReadWriteOnce. Tek pod bağlanır. DB workload'ları için.
- CephFS: ReadWriteMany. Birden fazla pod aynı anda okuyup yazabilir. Shared file system senaryoları için.
- Object Storage (Ceph): S3 uyumlu. Uygulama HTTP API üzerinden erişir. Backup, medya dosyaları için.
- CRUSH algoritması: Ceph'in veriyi node'lara dağıtma algoritması. Hangi verinin hangi OSD'de olduğunu deterministik olarak hesaplar.
- OSD (Object Storage Daemon): Her disk için bir OSD process. Veriyi fiziksel olarak saklayan bileşen.
- MON (Monitor): Cluster state'ini tutar, OSD'lerin sağlığını izler. Quorum gerektirir, tek sayı olmalı.

## Kendi Notum
Bak kanki şöyle anlatayım: diyelim 10 node'lu bir K8s cluster'ın var ve PostgreSQL çalıştırıyorsun. Tek node'un diskine yazdın, o node öldü, verin gitti. Ceph bunu çözüyor. Her yazdığın veri aynı anda 3 farklı node'un diskine yazılıyor (replication factor 3). O node ölse dahi veri iki farklı yerde daha var, PostgreSQL hiç fark etmedi bile.

Üç farklı interface sunması da önemli: veritabanıysa RBD kullan, birden fazla pod aynı dosyaları okuyacaksa CephFS kullan, resim/video/backup gibi büyük blob'lar depolayacaksan Object Storage (veya MinIO) kullan. Hepsini aynı Ceph cluster'ı sağlıyor.

## Karşılaştığım Hatalar
k3d'de Rook üzerinden Ceph kurmaya çalıştım ama:
- Rook v18 yükledim, "minimum version 19.2.0-0 squid" hatası aldım. `kubectl patch` ile image'ı `quay.io/ceph/ceph:v19` yaptım.
- Sonra `chown: changing ownership of '/run/ceph/ceph-mon.c.asok': Invalid argument` hatası geldi. Bu k3d'nin nested container ortamında kernel Unix socket chown kısıtından kaynaklanıyor, çözümü yok. Bare-metal gerekiyor.

Pratik görev bare-metal lab'a ertelendi, `rook-ceph/komutlar.sh` dosyasında komutlar hazır.

## Kaynaklar
- Ceph resmi döküman: https://docs.ceph.com/
- Rook-Ceph: https://rook.io/docs/rook/latest/
- Ceph RADOS açıklaması: https://docs.ceph.com/en/latest/architecture/
