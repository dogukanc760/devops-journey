# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Terraform state dosyası varsayılan olarak local'de (terraform.tfstate) tutulur. Ekip halinde çalışırken bu ölümcül bir problem: iki mühendis aynı anda terraform apply çalıştırırsa, ikisi de kendi local state'ine göre hareket eder, birbirlerinin değişikliklerini görmez, sonunda state dosyaları çakışır ve altyapı tutarsız hale gelir (ya da biri diğerinin yaptığı kaynağı siler). State'i S3 uyumlu bir remote storage'da (MinIO gibi on-premise) ve lock mekanizmasıyla tutmak bu çakışmayı engelliyor.

Temel:

Remote backend: State dosyası artık local'de değil, merkezi bir yerde (S3, MinIO, Terraform Cloud) tutuluyor. Herkes aynı state'e bakıyor.
State locking: Biri apply çalıştırırken state kilitlenir, o sırada başka biri apply çalıştırmaya çalışırsa "state locked" hatası alır, beklemek zorunda kalır. AWS'de bu DynamoDB tablosuyla yapılır, MinIO'da da benzer bir lock mekanizması kurulabilir.
State encryption: State dosyası bazen hassas veri içerir (örneğin bir DB şifresi resource attribute'u olarak state'e yazılmış olabilir). Remote backend'de encryption at rest şart.
Workspace: Aynı Terraform kodunu farklı ortamlar (dev/staging/prod) için farklı state dosyalarıyla çalıştırma. terraform workspace new prod gibi. Aynı kod, farklı state, farklı gerçek altyapı.

Mühendis A: terraform apply → state'i kilitler → değişikliği yapar → kilidi açar
Mühendis B (aynı anda): terraform apply → "Error: state is locked" → bekler

Örnek Soru: 
 State dosyası hassas veri içerebiliyor dedik (DB şifresi gibi). Diyelim ki state'i MinIO'da tutuyorsun ama encryption kurmadın ve MinIO bucket'ına erişimi olan biri (belki başka bir takımdan bir DevOps mühendisi) bu state dosyasını okuyabiliyor. Bu ne gibi bir güvenlik riski yaratır, ve state içindeki hassas veriyi en baştan state'e hiç yazdırmamak için Terraform'da ne yapabilirsin?

Cevap:
Vault (dinamik/kısa ömürlü secret) + state encryption at rest + state'e erişimi least-privilege ile kısıtlamak. Vault tek başına yeterli değil, state'i de "hassas dosya" gibi korumak şart.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- Remote backend: state dosyasını local diskten alıp S3 uyumlu bir depoya (bizde MinIO) taşımak. Herkes aynı state'e bakar.
- use_lockfile: Terraform'un yeni (1.10+) native S3 kilit mekanizması. Ayrı bir DynamoDB tablosuna gerek kalmadan, state dosyasının yanına conditional PUT (If None Match) ile bir kilit dosyası yazarak çalışır. Kilit tutuluyorsa ikinci yazma denemesi HTTP 412 (PreconditionFailed) alır.
- terraform state pull: state'in güncel halini backend'den çekip JSON olarak ekrana/dosyaya basar. State'in içine bakmanın standart yolu, çünkü artık local'de dosya olarak durmuyor.
- sensitive_attributes: State şemasında bir alanın "sensitive" işaretli olduğunu gösterir ama bu sadece CLI çıktısında o değeri gizler. State dosyasının kendisinde değer yine düz metin olarak durur, state şifrelenmiyor.
- Workspace: Aynı kod, farklı state. terraform workspace new ile oluşturulan her workspace, backend'deki key'in başına env:/<workspace-adı>/ ekleyerek kendi ayrı state dosyasını tutar. Bu sayede dev'de apply atmak prod state'ine dokunmaz.
- State backup: Backend'in kendisi versioning desteklemese bile (bizim MinIO kurulumunda versioning seçeneği UI'da yoktu), terraform state pull ile periyodik, zaman damgalı yedekler alarak state'in geçmiş bir haline dönebilme imkanı oluşturulabilir. Gerçek prod'da bu genelde CI/CD pipeline'ın bir adımı veya cron job olur.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
State'i local'de tutmak tek kişilik oyunlarda sorun değil ama ekipte iki kişi aynı anda apply atarsa felaket. Bunu çözmek için state'i MinIO gibi S3 uyumlu bir yere taşıyıp (remote backend), üstüne bir de kilit mekanizması (use_lockfile) ekliyoruz. Kilit varken ikinci apply "state locked" hatası alıp bekliyor, böylece iki kişi aynı anda state'i yazamıyor. Workspace'ler aynı kodu dev/staging/prod için ayrı state dosyalarıyla çalıştırmamızı sağlıyor. En kritik öğrendiğim şey şu, state dosyası hassas veri içerebiliyor ve "sensitive" işaretlemek sadece ekrana yazdırmayı engelliyor, dosyanın kendisini şifrelemiyor. Bu yüzden state backend'inin encryption ve erişim kontrolü olması şart, gerçekten kritik sırlar Vault gibi bir sistemde tutulup Terraform'a sadece referans olarak çekilmeli.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
1. Port çakışması: docker compose up denediğimde "Bind for 0.0.0.0:9000 failed, port is already allocated" hatası aldım. Sebep, benim Docker ortamımda başka bir projeden (echoes) kalma echoes-minio container'ı zaten 9000/9001 portlarını kullanıyordu. docker inspect ile container'ımın NetworkSettings.Ports alanının boş {} döndüğünü görünce, container'ımın hiç ayağa kalkmadığını, o portlara aslında başka bir container'ın cevap verdiğini anladım. Çözüm olarak kendi docker-compose.yml'imdeki portları 9010/9011'e taşıdım, main.tf'teki backend endpoint'ini de buna göre güncelledim. Diğer projeleri kapatmak yerine kendi portumu değiştirmeyi tercih ettim çünkü makinemde k3d cluster, echoes ve fikir projeleri gibi birçok başka şey aynı anda çalışıyor.
2. Giriş bilgileri kabul edilmiyor: MinIO web arayüzünde minioadmin/minioadmin123 ile login denedim, "invalid login" aldım, ama docker inspect Config.Env çıktısında bu bilgiler doğru görünüyordu. Gerçek sebep, benim container'ım (minio-state-backend) port çakışması yüzünden hiç çalışmıyordu, ben aslında başka bir container'ın (echoes-minio, farklı credential'lara sahip) arayüzüne giriş yapmaya çalışıyordum. docker ps ile tam liste görülünce ortaya çıktı.
3. "Failed to load state: invalid syntax: unexpected end of JSON input" hatası init ve apply'da tekrar tekrar çıktı. Kök sebep, .terraform/terraform.tfstate dosyasının 0 byte (bozuk) kalmasıydı, muhtemelen önceki bir apply yarıda kesilmişti (yanında kalan .terraform.tfstate.lock.info dosyası da bunu doğruluyordu). Çözüm, .terraform klasörünü tamamen silip terraform init ile temiz baştan başlamak oldu.
4. Lock testinde ilk denemede (use_lockfile eklemeden önce) iki terminalde de apply aynı anda onay bekledi, hiçbir kilit hatası çıkmadı. Bu, backend'de hiç locking aktif olmadığının kanıtıydı çünkü MinIO/S3 backend'de kilit ya dynamodb_table ile ya da use_lockfile = true ile açılıyor, ikisi de yoksa hiç kilitlenmiyor. use_lockfile = true ekleyip terraform init -reconfigure yaptıktan sonra ikinci terminal gerçekten "Error acquiring the state lock" (HTTP 412 PreconditionFailed) hatası aldı.
5. MinIO versioning'i UI üzerinden bucket'a açmaya çalıştım ama böyle bir seçenek görünmedi (muhtemelen bu MinIO kurulumunda/standalone modda kısıtlı). Bunun yerine terraform state pull ile zaman damgalı manuel backup script'i yazarak backup politikasını uyguladım.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- Terraform S3 backend dokümantasyonu (use_lockfile, endpoints, use_path_style parametreleri)
- MinIO dokümantasyonu (S3 uyumlu API, docker ile local kurulum)
