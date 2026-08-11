# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
CI/CD Mimari'de bir "Security Scan" adımından bahsetmiştik ama detayına girmemiştik. Normalde güvenlik taraması geleneksel olarak production'a çıktıktan sonra, ayrı bir güvenlik ekibi tarafından yapılır, ya da hiç yapılmaz. Bu durumda bir zafiyet (örneğin eski, açık bulunan bir base image) production'a kadar hiç fark edilmeden gider, tespit edildiğinde ise zaten canlıda çalışıyordur ve düzeltmek acil bir yangın söndürme haline gelir. Bu olmasaydı ne olurdu diye sorarsak, güvenlik açığı olan bir imaj aylarca production'da sessizce çalışabilir, saldırgan senden önce onu bulabilir, düzeltme maliyeti (o an her şeyi durdurup patch geçmek) geliştirme aşamasında yakalamaktan çok daha yüksek olur.

Temel:

- Shift-Left: güvenlik kontrolünü sürecin sonundan (production/post-deploy) başına (geliştirme/CI) taşımak, "erken yakala, ucuz düzelt"
- Trivy: bir imajın, dosya sisteminin, repo'nun veya K8s cluster'ının içindeki bilinen zafiyetleri (CVE) tarayan bir araç
- CVE severity: CRITICAL/HIGH/MEDIUM/LOW, genelde CRITICAL bulununca pipeline durdurulur
- SBOM (Software Bill of Materials): bir imajın içindeki tüm bağımlılıkların (ve versiyonlarının) tam listesi, "bu imajın içinde tam olarak ne var" sorusunun cevabı
- Cosign: bir imajı kriptografik olarak imzalama aracı, "bu imajı gerçekten biz oluşturduk, değiştirilmedi" garantisi verir
- İmza doğrulama zorunluluğu: cluster'a sadece imzalı imajların girmesine izin verme (Kyverno gibi bir policy engine ile)

Örnek Soru:
Trivy taraması bir CRITICAL CVE buldu ve pipeline'ı durdurdu, ama bu CVE aslında imajdaki bir kütüphanede var, o kütüphanenin güvenlik açığı olan fonksiyonu uygulama hiçbir yerde çağırmıyor. Bu durumda pipeline'ı otomatik durdurmak doğru bir davranış mı, yoksa aşırı katı mı? Bunu nasıl yönetirsin ki hem gerçek riskleri kaçırmayasın hem de her false-positive'te pipeline'ın kilitlenmesini önleyesin? Ayrıca, Cosign ile imza doğrulamanın SBOM'dan farkı ne, ikisi aynı sorunu mu çözüyor?

Cevap:
Katı davranmak savunulabilir bir pozisyon: kod çağırmasa bile o kütüphane imajın içinde, çalışan pod'un içinde duruyor, supply-chain saldırılarının asıl mantığı zaten "hiç çağırmadığın ama orada duran bir kod parçası" üzerinden çalışmak. Reachability (kod gerçekten çağırıyor mu) analizi tek başına yeterli bir güvenlik sınırı değil, statik analiz her zaman doğru sonuç vermez (dinamik import, reflection, dolaylı bağımlılık zinciri gibi yollarla çağrılabilir), bu her zaman görülemez.

Ama "her zaman katı ol" tek başına operasyonel bir sorun yaratır: upstream'de henüz patch'i çıkmamış bir CVE varsa (düzeltecek bir şey yok), ya da CVE test-only bir bağımlılıktaysa, "her zaman durdur" politikası deploy'u sonsuza kadar engelleyebilir. Gerçek pratik: varsayılan davranış katı kalır (CRITICAL bulunca dur), ama buna resmi, denetlenebilir bir istisna (waiver) mekanizması eklenir, `.trivyignore` dosyasına sadece CVE ID + gerekçe + kim onayladı + son geçerlilik tarihi ile birlikte girilebilir bir istisna girilir. Bu "sessizce görmezden gel" değil, "bilerek, kayıt altına alarak, süreli kabul et" demek, süre dolunca tekrar değerlendirilir.

SBOM ile Cosign farklı sorulara cevap verir: SBOM "bu imajın içinde ne var" (bağımlılık listesi), Cosign "bu imajı kim üretti, değiştirilmedi mi" (kimlik/bütünlük). Örneğin birden fazla backend ekibi varsa, A ekibinin çıkardığı imaj Cosign ile A ekibinin key'iyle imzalanır, sorumluluk net olur, SBOM ise sadece dependency tree'yi listeler, kimin ürettiğiyle ilgilenmez.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- `.trivyignore` ile CVE istisnası tanımlarken sadece CVE ID yazmak yetmez, gerekçe + onaylayan + son geçerlilik tarihi eklemek istisnayı "sessiz görmezden gelme"den "denetlenebilir kabul"e çevirir.
- SBOM (CycloneDX formatı), imajın içindeki her bağımlılığın adını/versiyonunu/lisansını listeler, "içerik" sorusuna cevap verir, kimlik/imza ile ilgisi yoktur.
- Cosign, private/public key çifti üretip (`cosign generate-key-pair`) imajı imzalar (`cosign sign`), imza imajın yanına ayrı bir OCI artifact olarak kaydedilir. `cosign verify` ile doğrulama yapılır, imzasız bir imaj doğrulamadan hep "no matching signatures" hatasıyla geçer.
- Cosign doğrulaması elle çalıştırılan bir komut olduğu sürece atlatılabilir, asıl güvenlik cluster'ın kendisinin (admission webhook seviyesinde, Kyverno gibi bir policy engine ile) imzasız imajı reddetmesidir.
- Kyverno `verifyImages` kuralı, bir Pod oluşturulmadan ÖNCE image referansının imzasını kontrol eder, imzasız/geçersiz imza varsa pod hiç oluşturulmaz, "Forbidden" değil doğrudan admission reddi olarak döner.
- Shift-Left'in özeti: aynı kontrolü (CVE tarama, imza doğrulama) production'da elle/sonradan yapmak yerine, hem CI'da (erken yakala) hem cluster admission'ında (son savunma hattı) iki farklı noktada uygulamak, tek bir noktaya güvenmemek.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Shift-Left basitçe şu: güvenliği "sona bırakma, en başa çek". Trivy ile CI'da imajı tarıyoruz, CRITICAL/HIGH bulununca pipeline kırmızı oluyor, imaj production'a hiç gidemiyor. Ama katı olmak tek başına yeterli değil, çünkü her CVE gerçek bir risk taşımayabilir (upstream'de patch yoksa, ya da kod o fonksiyonu hiç çağırmıyorsa). Bunun için `.trivyignore` ile gerekçeli, süreli istisnalar tanımladık, "görmezden geldik" değil "bilerek kabul ettik ve kaydını tuttuk" dedik.

SBOM ve Cosign'ı karıştırmamak lazım, ikisi farklı iş yapıyor. SBOM "bu imajın içinde tam olarak neler var" listesi, bir envanter. Cosign ise "bu imajı gerçekten biz ürettik, kimse araya girip değiştirmedi" imzası, bir kimlik/bütünlük garantisi. Birini yapıp diğerini yapmamak eksik kalır, ikisi birlikte tam bir tedarik zinciri güvenliği hikayesi anlatıyor.

En kritik nokta, Cosign'ın kendisini elle çalıştırmanın yeterli olmaması. Biri imzasız bir imajı yine de `kubectl apply` ile cluster'a sokabilir, elle kontrol atlanabilir. Bu yüzden Kyverno ile cluster'ın KENDİSİNE "imzasız imaj asla kabul etme" dedik, admission webhook seviyesinde, insan hatasına bağlı olmayan bir son savunma hattı kurduk.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
İmzasız bir imajla (`ci-cd-demo:v1-unsigned`) hem `cosign verify` hem Kyverno seviyesinde ayrı ayrı test ettik. `cosign verify` "Error: no matching signatures: ... no signatures found" dedi, bu beklenen ve doğru bir "hata", imza gerçekten yoktu. Kyverno seviyesinde ise pod oluşturma isteğinin kendisi reddedildi: "admission webhook ... denied the request: image verification failed ... failed to verify signature". İki farklı katmanda iki farklı ama tutarlı ret aldık, bu bilerek tasarlanan bir tekrarlayan savunma (defense in depth), biri atlatılsa bile diğeri yakalıyor.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- Trivy resmi dokümantasyonu (.trivyignore, SBOM/CycloneDX formatı)
- Sigstore/Cosign resmi dokümantasyonu (keyless signing, key-based signing)
- Kyverno verifyImages policy dokümantasyonu
