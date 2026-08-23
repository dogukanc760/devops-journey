# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Madde 3'te Cilium ile L3/L4 ve L7 network policy'lerini, Madde 5'te tracing ile isteklerin servisler arası yolculuğunu izlemeyi öğrendik. Ama gerçek bir mikroservis ortamında iki büyük sorun daha var: biri çökünce ona bağımlı olan her servis de etkilenir ve zincirleme çöküş (cascading failure) yaşanır, ayrıca servisler arası trafiğin şifreli ve kimlik doğrulamalı olması her uygulamanın kendi kodunda ayrı ayrı çözmesi gereken bir yük haline gelir. Bu olmasaydı ne olurdu diye sorarsak, bir servis yavaşladığında ona istek atan her servis de bekleyip kaynaklarını tüketirdi, tek bir zayıf halka tüm sistemi aşağı çekebilirdi, her takım kendi uygulamasında ayrı ayrı retry/mTLS/timeout mantığı yazmak zorunda kalırdı.

Temel:

- Service Mesh: servisler arası TÜM trafiği bir proxy üzerinden geçiren mimari (sidecar pattern), uygulama kodu bunun farkında bile olmaz
- Envoy proxy: Istio'nun her pod'a otomatik eklediği sidecar, gerçek trafik yönetimi burada olur
- mTLS: mesh içindeki tüm pod-to-pod trafik otomatik şifreli ve karşılıklı kimlik doğrulamalı hale gelir
- Circuit Breaker: bir servise art arda belirli sayıda hata olursa, mesh o servise istek göndermeyi geçici olarak keser (fast fail), zincirleme çöküşü önler
- Retry: başarısız bir isteği otomatik olarak tekrar dener, uygulama kodu bunu bilmez
- Traffic splitting: aynı anda iki sürüme belirli yüzdelerde trafik yönlendirme

Örnek Soru:
Bir servise Circuit Breaker kuruyorsun: "5 ardışık hata olursa devre kes, 30 saniye boyunca istek gönderme". 30 saniye sonra mesh bu servisin düzelip düzelmediğini nasıl anlar, hemen eski haline mi döner yoksa farklı bir yöntem mi izler? Hemen sınırsız trafiğe dönerse ve servis hâlâ kötüyse ne olur? Circuit Breaker ile Progressive Delivery'deki (Madde 4) otomatik rollback arasındaki fark ne?

Cevap:
Mesh 30 saniye dolunca hemen tam trafiğe dönmez, "half-open" (yarı açık) ara durumunu kullanır: sadece bir/birkaç deneme isteği gönderilir, başarılı olursa devre tam açılır, başarısız olursa tekrar kapanır. Üç durumlu bir mekanizma: Closed → Open → Half-Open → Closed ya da tekrar Open. Eğer mesh hemen sınırsız trafiğe dönseydi ve servis hâlâ kötüyse, birden gelen tam yük servisi tekrar kötüleştirir, devre hemen yeniden kesilir, bu "flapping" (sürekli aç-kapa) haline gelir.

Circuit Breaker ile rollback farkı, hangi sorunu ve hangi hızda çözdüklerinde. Circuit Breaker network/çağrı seviyesinde, saniyeler içinde, "şu an çalışan koda güvenmiyorum, geçici olarak istek göndermeyeyim" der, hiçbir deploy yapmaz, zaten deploy edilmiş ama geçici sorun yaşayan bir servisi korur. Rollback ise deploy seviyesinde, dakikalar süren bir analiz penceresiyle, "yeni deploy ettiğim KOD kötü" der, çözüm kodu değiştirmektir (önceki sürüme dönmek). Circuit Breaker geçici koruma, rollback kalıcı düzeltmedir.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- `istio-injection=enabled` namespace label'ı sadece BUNDAN SONRA oluşturulacak pod'lara sidecar ekletir, zaten çalışan pod'lar etkilenmez, injection'ın uygulanması için `kubectl rollout restart` ile pod'ların yeniden yaratılması gerekir.
- `PeerAuthentication` ile `STRICT` mTLS zorlanınca, mesh dışından (sidecar'sız) gelen bir bağlantı TAMAMEN reddedilir, handshake seviyesinde kopar, mesh içinden gelen bağlantı ise otomatik ve şeffaf şekilde şifrelenip geçer.
- `DestinationRule.outlierDetection`, circuit breaker'ın gerçek yapılandırmasıdır (`consecutiveErrors`, `baseEjectionTime`, `maxEjectionPercent`), bir servis "eject" edildiğinde istekler ona hiç gitmeden anında hata (503/UF) döner.
- `VirtualService.retries.perTryTimeout`, her deneme için ayrılan süredir, bu değer gerçek yanıt süresinden KISA verilirse retry mekanizması sessizce işe yaramaz hale gelir, her deneme "timeout" sayılıp tüketilir, `retryOn: 5xx` koşuluna hiç ulaşılmadan deneme hakları biter. Bu, "retry kurdum ama çalışmıyor" şikayetinin en sık sebeplerinden biri.
- Aynı cluster'da iki service mesh (Istio + Linkerd) aynı anda kurulamaz, ikisi de aynı pod'lara sidecar enjekte etmeye çalışırsa trafik bozulur, Linkerd bunu `linkerd check --pre` ile proaktif olarak tespit edip kurulumu durdurur.
- Linkerd'in Rust tabanlı proxy'si (linkerd2-proxy), Envoy tabanlı Istio sidecar'ına göre gözle görülür şekilde daha az kaynak (RAM) tüketir, bu "hafif alternatif" olma iddiasının somut karşılığıdır.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Service mesh'i "her pod'un yanına sessizce oturan bir trafik polisi" gibi düşün, uygulama kodu hiçbir şey bilmeden mTLS, retry, circuit breaker hepsi bu sidecar üzerinden yönetiliyor. İki gerçek hata bunu net gösterdi. Birincisi: namespace'e injection label'ı ekledik ama zaten çalışan pod'lara hiç etki etmedi, "label ekledim, neden sidecar yok" diye şaşırdık, sebebi injection'ın webhook seviyesinde SADECE pod OLUŞTURULURKEN çalışması, restart şart. İkincisi: retry policy kurduk ama hata oranı hiç düşmedi, sebebi perTryTimeout'u gerçek yanıt süresinden kısa vermiş olmamız, her deneme "timeout" sayılıp retry hakkı gerçek hatayı (5xx) hiç görmeden tükeniyordu, süreyi gerçekçi bir değere çekince retry gerçekten işe yaramaya başladı.

Circuit breaker'ı gerçekten test ettik: backend'i bozunca 5 hatadan sonra devre kesildi, istekler backend'e hiç gitmeden anında 503 döndü, 30 saniye sonra bir "deneme" isteği gönderildi (half-open), backend hâlâ bozukken bu deneme de başarısız oldu ve devre tekrar kapandı, backend'i düzeltince bir sonraki deneme başarılı oldu ve devre tam açıldı. Bu davranış otomatik rollback'ten tamamen farklı, burada hiçbir kod değişmedi, sadece trafik akışı geçici olarak durduruldu ve kendi kendine test edildi.

Linkerd karşılaştırmasında ilginç bir engelle karşılaştık: aynı cluster'da Istio kuruluyken Linkerd kurmaya çalışınca preflight check bunu reddetti, iki mesh'in birlikte yaşayamayacağını gösterdi. Ayrı cluster'da kurunca ise Linkerd'in kaynak tüketiminin (özellikle RAM) Istio'ya göre çok daha düşük olduğunu gözle gördük.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
1. Namespace'e `istio-injection=enabled` label'ı eklendikten sonra mevcut pod'larda sidecar hiç görünmedi (1/1 Running kaldı). Sebep, injection'ın bir mutating webhook üzerinden SADECE pod oluşturma anında tetiklenmesi, zaten var olan pod'lara geriye dönük uygulanmaması. Çözüm `kubectl rollout restart deployment` ile pod'ları yeniden yaratmaktı, sonrasında 2/2 Running görüldü.
2. Retry policy kurulduktan sonra hata oranında hiç değişiklik gözlenmedi (%20 civarı 500 almaya devam edildi). Sebep, `perTryTimeout: 25ms` değerinin backend'in gerçek yanıt süresinden (spotify-mock çağrısı dahil) çok kısa olması, her deneme retryOn koşuluna (5xx) hiç ulaşmadan timeout'tan tükeniyordu. Çözüm, `perTryTimeout`'u 500ms'ye çekmekti, sonrasında retry mekanizması gerçekten çalışıp client'a giden hata oranını sıfıra indirdi.
3. Aynı cluster'da Linkerd kurulmaya çalışılınca `linkerd check --pre` "Istio is already installed" uyarısıyla FAILED verdi. Sebep, iki mesh'in aynı pod'lara çift sidecar enjekte etmeye çalışmasının trafiği bozacak olması. Çözüm, Linkerd'i ayrı bir cluster'da kurmaktı.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- Istio resmi dokümantasyonu (sidecar injection, PeerAuthentication, DestinationRule outlierDetection, VirtualService retries)
- Linkerd resmi dokümantasyonu (preflight checks, linkerd2-proxy mimarisi)
- Kiali resmi dokümantasyonu (trafik grafiği, mTLS göstergeleri)
