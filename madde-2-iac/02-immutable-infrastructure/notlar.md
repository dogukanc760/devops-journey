# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Ansible ile çalışan bir sunucuda hata çıktığında klasik yaklaşım içine SSH ile girip elle yamalamaktır(patch).
Ama bunu yıllarca yapa yapa sunucu artık kisme tam olarak ne olduğunu bilmeyen, üstüne üstüne yama yapılmış bir 
"kar topu" haline gelir. Bir gün neden çalıştığını kimse açıklayamaz (configuration driftin en kötü hali, snowflake server denir). Immutable Infrastructe bunun tam tersini yapıyor; sunucuya hiç dokunmuyorsun, sorun çıkınca onu tamamen öldürüp Terraform ile sıfırdan, önceden tanımlanmış "doğru" haliyle yeniden ayağa kaldırıyorsun. 

Temel:
- Mutable: Sunucu zamanla üstüne yama yapılarak değişiyor (Ansible playbook tekrar tekrar çalıştırılıyor)
  Immutable: Sunucu hiç değişmiyor, değişiklik gerekiyorsa yenisi kuruluyor eskisi siliniyor.
- Packer: Önceden hazırlanmış, tüm gerekli paketleri/config'i içeren bir "Golden Image"(VM image veya container image)
  oluşturan araç. Terraform bu image'dan VM açar.
- Pet vs Cattle:
   Pet(Evcil hayvan) = Tek, özel ismi var, hastalanınca tedavi edilir.
   Cattle(Sığır) = Sürü halinde, numaralı, hastalanınca değiştirilir. Sunucular cattle olmalı
- Blue-Green deployment: Yeni sürüm(Green) paralel ayağa kalkar, sağlıklı olduğu doğrulanınca trafik Blue'dan Green'e kaydırılır, sonra Blue silinir. Kesintisiz geçiş.
- terraform taint (eski) / terraform apply -replace(yeni): Bir resource'u "bozuk" işaretleyip bir sonraki    
  apply'da zorla yok edip yeniden oluşturmasını sağlar.

  Sorun tespit edilir (sunucu bozuk/güncel değil)
        ↓
    terraform apply -replace="aws_instance.web"
            ↓
    Eski sunucu silinir → Packer image'dan yeni sunucu açılır
            ↓
    Birkaç saniye/dakika içinde "doğru" sunucu hazır   

Örnek Soru:
Blue-Green deployment'ta yeni sürüm (Green) ayağa kalkarken hâlâ eski sürüm (Blue) de çalışıyor, yani bir an için iki farklı sürüm aynı anda prod'da. Bu durumda eğer uygulaman bir veritabanına bağlıysa ve yeni sürüm veritabanı şemasında bir değişiklik gerektiriyorsa (örneğin yeni bir kolon), bu geçişi nasıl güvenli yaparsın?
Cevap: 
Bu problemin çözümü expand/contract pattern (parallel change) denen bir tekniktir. Blue-Green'de uygulama kodu anlık geçiş yapabilir ama veritabanı şeması öyle değil, ikisi paylaşımlı bir kaynak, o yüzden şema değişikliğini kendi içinde adımlara bölmen gerekiyor:

1. Expand (genişlet), Blue hâlâ tek başına çalışırken:
Yeni kolonu ekle ama eski kolonu silme, ikisini birden tut. Örneğin email kolonunu email_address olarak yeniden adlandırmak istiyorsan, önce email_address kolonunu ekle, email'i silme. Bu değişiklik hem Blue (eski kod) hem Green (yeni kod) ile uyumlu olmalı, Blue eski email kolonunu kullanmaya devam eder, yeni kolon onun umurunda değil.

2. Migrate (taşı):
Mevcut veriyi eski kolondan yeni kolona kopyala (background job veya migration script). Bu sırada ideal olarak hem yazma işlemi ikisine de yapılır (dual write) ki Blue hâlâ eski kolona yazarken veri kaybı olmasın.

3. Green'i ayağa kaldır ve trafiği kaydır:
Green artık yeni email_address kolonunu kullanıyor. Trafik Blue'dan Green'e kayınca, artık kimse eski kolona yazmıyor.

4. Contract (daralt), Blue tamamen silindikten sonra:
Artık eski email kolonuna ihtiyaç kalmadı, ayrı bir migration ile onu temizle.

Kısacası: Şema değişikliğini "kod deploy'u" ile aynı anda yapmıyorsun. Önce şemayı her iki sürümle de uyumlu hale getiriyorsun (genişletme), sonra kod geçişini yapıyorsun (Blue'dan Green'e), en son eski şema kalıntısını temizliyorsun (daraltma). Bu adımlar ayrı ayrı, güvenli sırayla yapılıyor, asla tek adımda "yeni sürüm + yeni şema" birlikte deploy edilmiyor, çünkü o an ikisi de prod'da aynı anda çalışıyor olabilir.
## Uçtan Uca Akış: Bu Task'ta Her Şey Nereden Geldi, Neden Kullanıldı

### Neden Packer'a hiç ihtiyaç duyduk, Terraform tek başına yapamaz mıydı?
Terraform "bir container/VM aç" diyebilir ama içine hangi paketlerin kurulu olacağını yönetmek Terraform'un işi değil. Packer olmasaydı, container'ı Terraform ile açtıktan SONRA bir provisioner (`remote-exec` gibi) ile nginx kurdurabilirdik, ama bu "deploy anında kurulum" olurdu: her yeni instance açılışında yeniden paket indirip kuruyor olurduk. Bu hem yavaş hem de riskli, çünkü kurulum internet bağlantısına, paket versiyonlarına bağımlı hale gelir, bugün kurduğun ile yarın kurduğun birebir aynı olmayabilir.

Packer'ın işi tam olarak bunu engellemek: kurulumu DEPLOY ANINDA değil, ÖNCEDEN bir kere yapıp sonucu dondurmak (bir "imaj" olarak). Sonra bu donmuş imajdan istediğin kadar birebir aynı kopya açabiliyorsun, hiç yeniden kurulum yapmadan. Golden Image dediğimiz şey bu donmuş, test edilmiş, referans kopya. "Golden" (altın) ismi de buradan geliyor, tıpkı bir CD basım fabrikasının "master" kopyası gibi, herkes bu tek doğru kaynaktan çoğaltılıyor, kimse elle farklı bir şekilde kurmuyor.

### Neden Packer'ın `docker` builder'ını kullandık, "gerçek" builder'ları değil?
Packer'ın en yaygın kullanımı `amazon-ebs` (AWS AMI inşa eder), `qemu`, `virtualbox-iso` gibi gerçek VM/bulut image builder'ları. Bizim elimizde ne bulut hesabı ne de gerçek bir Ubuntu VM ortamı olduğu için `docker` builder'ını kullandık, bu VM image yerine bir Docker image inşa ediyor. Prensip birebir aynı kalıyor (bir base al, üstüne paket kur, sonucu imaj olarak dondur), sadece çıktının formatı VM image değil Docker image.

### `packer build` çalışınca perde arkasında ne oluyor, adım adım
1. `source "docker" "golden_nginx"` bloğunda `image = "ubuntu:22.04"` yazdık. Packer bu base image'dan GEÇİCİ, bizim görmediğimiz bir container başlatıyor.
2. `provisioner "shell"` bloğundaki komutlar (`apt-get install -y nginx curl` gibi) bu geçici container'ın İÇİNDE çalıştırılıyor, yani nginx o geçici container'a kuruluyor.
3. `commit = true` dediğimiz için, bu geçici container'ın o anki hali (nginx kurulu hali) yeni bir Docker image olarak dondurulyor, tıpkı elle `docker commit` komutu çalıştırmış gibi.
4. `post-processor "docker-tag"` bu yeni oluşan, henüz isimsiz image'a bir isim ve tag veriyor: `golden-nginx:v1`.
5. Geçici container siliniyor, elimizde sadece `golden-nginx:v1` adlı, nginx kurulu, kalıcı bir Docker image kalıyor.

### En kritik soru: Terraform bu imajı nereden gördü, Packer ondan Terraform'a nasıl "geçti"?
Burada bir dosya transferi veya Packer'dan Terraform'a bir "el sıkışma" YOK. Packer'ın ürettiği image bir dosya değil, Docker daemon'ın kendi iç image deposunda (senin durumunda Docker Desktop/OrbStack'in yönettiği Linux VM içinde) saklanan bir varlık. `docker images` komutu bu depoyu listeliyor, "golden-nginx v1" orada göründü çünkü Packer onu doğrudan o depoya yazdı.

`main.tf`'te şunu yazdık:
```
resource "docker_container" "golden_nginx" {
  image = "golden-nginx:v1"
  ...
}
```
Buradaki `image` alanı sadece bir İSİM STRING'İ, bir dosya yolu ya da referans değil. `terraform apply` çalışınca, `kreuzwerker/docker` provider'ı Docker daemon'a (Docker API üzerinden) şunu soruyor: "golden-nginx:v1 adında bir image var mı?" Docker daemon "evet, local'de duruyor" diyor, Terraform da o image'ı kullanarak container'ı başlatıyor.

Yani bağlantı Packer'dan Terraform'a değil, ikisinin de AYNI Docker daemon'ı paylaşmasından geliyor. Packer image'ı Docker'ın deposuna yazdı, Terraform aynı depodan okudu. Eğer image local'de olmasaydı (bir registry'de duruyor olsaydı), Docker önce `docker pull` ile onu indirirdi, ama bizim durumumuzda ikisi de aynı makinede aynı Docker daemon'ı kullandığı için hiç indirme gerekmedi.

Gerçek prod ortamında bu image genelde bir registry'ye (Docker Hub, AWS ECR, Google GCR) push edilir, Terraform da `image = "myregistry.com/golden-nginx:v1"` şeklinde o registry'den çeker. Biz local test yaptığımız için registry hiç devreye girmedi.

### Neden Blue-Green kullandık, destroy+apply döngüsü yetmiyor muydu?
Golden image + Terraform ile "sıfırdan temiz kurulum" yapmayı `destroy`+`apply` ile öğrendik. Ama bunun bir sorunu var: `terraform destroy` çalıştığın an eski container tamamen ölüyor, yenisi ayağa kalkana kadar (bizim ölçtüğümüz ~1.9 saniye) HİÇBİR ŞEY kullanıcıya cevap vermiyor. Prod'da yüksek trafikli bir sistemde bu kısa kesinti bile kabul edilemez olabilir.

Blue-Green bu kesintiyi ortadan kaldırıyor: yeni sürümü (Green) eskisini (Blue) hiç öldürmeden paralel ayağa kaldırıyorsun. Green'in sağlıklı çalıştığını doğruladıktan sonra trafiği bir anda Blue'dan Green'e çeviriyorsun, kullanıcı hiçbir kesinti hissetmiyor çünkü Green zaten hazır bekliyordu, sadece "kime bakılacağı" değişti.

### Bizim Blue-Green kurulumumuzda tam olarak ne oldu, adım adım
1. İki ayrı golden image inşa ettik: `golden-nginx:v1` (Blue içeriği) ve `golden-nginx:v2` (Green içeriği, farklı bir index.html mesajıyla).
2. Terraform ile İKİ container'ı AYNI ANDA açtık: `app-blue` (v1'den) ve `app-green` (v2'den). İkisi de aynı Docker network'ünde (`bluegreen-net`), yani birbirlerini isimleriyle bulabiliyorlar.
3. Üçüncü bir container açtık: `bg-proxy` (nginx:alpine tabanlı), görevi dışarıdan gelen isteği (port 8100) ya `app-blue`'ya ya da `app-green`'e yönlendirmek.
4. Proxy'nin hangisine yönlendireceğini bir Terraform variable'ı (`active_version`) belirliyor. Bu değeri proxy'nin başlatma komutuna (`command`) gömdük, container açılırken o anki `active_version` değerine göre bir nginx.conf yazıp nginx'i başlatıyor.
5. `-var="active_version=green"` ile apply çalıştırınca, `command` string'i değişti. Terraform bunu ForceNew olarak algıladı (Docker'da çalışan bir container'ın komutu yerinde değiştirilemez), proxy container'ı yok edip yeniden yarattı (`-/+ replace`).
6. Bu replace SADECE proxy'yi etkiledi, `app-blue` ve `app-green`'e hiç dokunulmadı, onlar zaten ikisi de ayaktaydı. Yani kullanıcı açısından "kesinti" olan tek an proxy'nin birkaç saniyelik yeniden başlama süresiydi, gerçek uygulama container'ları hiç etkilenmedi.

Gerçek prod ortamında bu "proxy" yerine genelde bir Load Balancer (AWS ALB, Nginx Ingress, Kubernetes Service) kullanılır, trafik kaydırma "hangi target group'a yönlendiriliyor" ayarını değiştirerek yapılır. Bizim `command` ile yaptığımız iş, o gerçek dünyadaki "LB config güncelleme" işleminin basitleştirilmiş bir simülasyonu.

## Anahtar Kavramlar
- Golden Image: Önceden hazırlanmış, test edilmiş, tüm bağımlılıkları içeren bir imaj (VM image veya container image). Packer bunu inşa eder, Terraform bu imajdan kaynak açar.
- Mac'te gerçek Ubuntu VM'i olmadan da bu pratik yapılabiliyor: Packer'ın `docker` builder'ı ile golden image bir Docker image olarak inşa edilebiliyor, VM yerine container kullanılıyor ama immutable infrastructure prensibi (önceden hazırlanmış, değişmez imajdan sıfırdan ayağa kaldırma) birebir aynı kalıyor.
- ForceNew attribute: Bir kaynağın bazı özellikleri (örneğin bir container'ın `command`'ı) değiştiğinde Terraform o kaynağı güncelleyemez, yerine yenisini koymak zorunda kalır (`-/+ replace`). Bu, immutable infrastructure'ın Terraform seviyesindeki karşılığı, bazı değişiklikler doğası gereği "yerinde güncelleme" değil "yeniden yaratma" gerektiriyor.
- Blue-Green'de trafik kaydırma pratikte bir proxy'nin (nginx gibi) hangi backend'e yönlendiğini değiştirmekle oluyor. Bizim örneğimizde bu değişikliği bir Terraform variable (`active_version`) ile tetikledik, `-var` ile değeri değiştirip apply çalıştırdık.
- `terraform destroy` + `terraform apply` döngüsü, mutable yaklaşımdaki "içine gir düzelt" yerine "öldür, temiz halinden yeniden doğur" yaklaşımının canlı örneği.

## Kendi Notum
Bu konuyu şöyle özetlerdim: normalde bir sunucuda sorun çıkınca refleks SSH ile içine girip düzeltmektir. Ama bu her yapıldığında sunucu biraz daha "özel" hale gelir, kimse tam olarak üstünde neler olduğunu bilmez. Immutable Infrastructure bu alışkanlığı tersine çeviriyor: sorunlu sunucuya hiç dokunma, öldür, golden image'dan yenisini aç. Docker ile pratik yapınca bunu çok net gördüm, container'ı bozdum (`index.html`'i elle değiştirdim), sonra `terraform destroy` + `apply` ile 1.9 saniyede tertemiz bir kopya geldi. Gerçek bir VM'de bu süre daha uzun olur ama mantık birebir aynı.

Blue-Green kısmında en çok şaşırdığım şey, trafiği kaydırmanın aslında bir "in-place update" değil bir "replace" olarak gerçekleşmesiydi: proxy container'ın `command`'ı değişince Terraform onu yok edip yeniden yarattı. Bu da normal, çünkü Docker'da çalışan bir container'ın komutunu "yerinde" değiştiremezsin, konteyner olarak yeniden başlatman gerekiyor. Blue ve Green container'larına hiç dokunulmadı, sadece aralarındaki yönlendirici değişti.

## Karşılaştığım Hatalar

**1. `terraform apply` (container aç) → "Bind for 0.0.0.0:8080 failed: port is already allocated"**
Sebep: Madde 1'deki k3d HA cluster'ın `8080:80` port mapping'i zaten o portu kullanıyordu.
Çözüm: `main.tf`'te `external` portu `8090` olarak değiştirdim.

## Kaynaklar
- Packer Docker builder dokümantasyonu: https://developer.hashicorp.com/packer/integrations/hashicorp/docker
- Terraform Docker provider (kreuzwerker): https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs
- Martin Fowler, Blue-Green Deployment: https://martinfowler.com/bliki/BlueGreenDeployment.html
- Expand/Contract pattern: https://www.prisma.io/dataguide/types/relational/expand-and-contract-pattern
