# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Merkezi loglamayla artık bir pod'un ne zaman hata verdiğini görebiliyoruz. Ama gerçek sistemlerde bir istek tek bir servisten geçmez, kullanıcı frontend'e istek atar, frontend backend'e, backend DB'ye ve belki bir üçüncü parti API'ye gider. İstek yavaşladığında hangi log'a bakacağını bile bilemezsin, çünkü her servisin kendi logu ayrı ayrı duruyor, aralarında "bu log satırları aynı isteğe ait" bağlantısı yok. Bu olmasaydı ne olurdu diye sorarsak, bir istek 3 saniye sürdüğünde bu sürenin ne kadarının hangi serviste geçtiğini anlamak için servis servis, log log dedektiflik yapmak zorunda kalırdın, gerçek darboğazı bulmak saatler alabilirdi.

Temel:

- Trace: bir isteğin sistemdeki uçtan uca tüm yolculuğunu temsil eden kayıt, tüm servisleri kapsar
- Span: trace içindeki tek bir operasyon (örn. "backend'in DB'ye attığı sorgu"), bir trace birden fazla span'dan oluşur, span'lar iç içe/ardışık olabilir
- Context propagation: bir trace ID'nin, istek bir servisten diğerine geçerken (HTTP header'ları üzerinden) taşınması, bu sayede farklı servislerdeki span'lar aynı trace'e ait olduğu anlaşılır
- OpenTelemetry (OTel): tracing için vendor-neutral bir standart, hangi backend'i (Tempo, Jaeger, vs.) kullanırsan kullan aynı SDK ile kod içine entegre edilir
- Beyla: eBPF tabanlı, kod içine hiç dokunmadan (zero-instrumentation) network seviyesinde trace üretebilen bir araç
- Grafana Tempo: trace'lerin saklandığı depo, Loki gibi bu da genelde sadece trace ID'yi indeksler, maliyeti düşük tutar

Örnek Soru:
Bir isteğin frontend → backend → Spotify API zincirinde toplam 3 saniye sürdüğünü gördün, trace'e baktığında backend'in kendi işi 200ms, ama backend'den Spotify API'ye giden span 2.7 saniye görünüyor. Bunu görünce direkt "Spotify API yavaş, bizim suçumuz yok" diyebilir misin? Bu span'ın süresini yanlış yorumlatabilecek en az iki farklı teknik sebep düşün. Ayrıca, OpenTelemetry SDK ile manuel instrumentation yapmak yerine Beyla ile zero-instrumentation kullanmanın hangi durumda tercih edilir, hangi durumda yetersiz kalır?

Cevap:
İki geçerli teknik sebep var. Birincisi, egress katmanları: pod'dan çıkışta geçtiği security katmanları, gereksiz kontroller, NAT/SNAT öncesi işlemler, ayrıca DNS çözümleme ve TLS handshake, bunların hepsi span'ın içine dahil olur ama Spotify'ın gerçek işlem süresi değildir, senin tarafındaki network hazırlık maliyetidir. İkincisi, ve daha sinsi olanı, span mislabeling: span'ın adı "spotify-api-call" olsa da, kodun bu span'ı hangi satırda kapattığı önemli. Eğer geliştirici span'ı "istek gönder + cevabı al + DB'ye yaz + logic çalıştır" bloğunun TAMAMININ etrafına sarmışsa, ölçülen süre gerçekte "Spotify + benim sonrasında yaptığım her şey"in toplamıdır, Spotify çok hızlı yanıt vermiş olabilir.

Bu ikinci sorunu çözmenin doğru yolu eBPF/Beyla DEĞİL, daha ince taneli OpenTelemetry span'ları. eBPF, kernel/network seviyesinde syscall'ları ve paketleri gözlemler, fonksiyonun İÇİNDE "şimdi DB'ye yazıyorum" ya da "şimdi business logic çalıştırıyorum" gibi bir ayrım YAPAMAZ, çünkü bunlar network'e hiç çıkmayan, salt CPU'da çalışan kod parçalarıdır, eBPF'in görebileceği bir syscall/paket sınırı yoktur. Doğru çözüm, OTel SDK ile o büyük span'ı alt span'lara bölmek: `http-call-to-spotify` (sadece network isteği), `db-write` (sadece DB yazma), `business-logic` (geri kalan işlem), üçü ayrı child span olunca hangisinin gerçekten uzun sürdüğü net görünür.

OTel'in bir şekilde uygulamaya entegre olması gerekir (SDK ya da otomatik instrumentation agent, "kullanıcı alanında" çalışır), Beyla/Hubble gibi eBPF araçları ise kod hiç değişmeden, kullanıcı alanının altında/kernel seviyesinde çalışır. Uygulamaya dokunma imkanın yoksa (legacy sistem, üçüncü parti servis, apps'e entegre edecek bir ortamın yoksa) Beyla tercih edilir. Ama Beyla'nın zayıf yanı da tam burada: kod içi (in-process) mantığı, business logic'in kendisini GÖREMEZ, sadece dışarıya çıkan/gelen çağrıları görür. Yani "kod içindeki gizli süreyi bulmak" tam olarak Beyla'nın YAPAMADIĞI, OTel'in yaptığı şeydir, ikisi birbirinin yerini tutmaz, tamamlayıcıdır.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- Span sınırı, geliştiricinin kodda `span.end()` çağırdığı yere bağlıdır, "doğru" bir sınır değildir, yanlış yerde kapatılırsa (birden fazla farklı işi tek span'a gömerse) yanıltıcı bir süre gösterir. Gerçekten test ettik: tek span'da Spotify %5, kendi kodumuz %95 zaman aldığı halde span adı sadece "spotify-api-call"dı.
- OTLP exporter'ın hangi porta konuşacağı (HTTP/4318 vs gRPC/4317) Tempo Service'in hangi portları expose ettiğine bağlı, bu ikisi eşleşmezse `ECONNREFUSED` alınır, `kubectl get svc ... -o jsonpath='{.spec.ports}'` ile gerçek expose edilen portlar doğrulanmalı.
- Child span'lara bölmek (`http-call-to-spotify`, `db-write-and-business-logic`), aynı toplam süreyi ayrıştırıp gerçek darboğazı ortaya çıkardı, dış API değil kendi kodumuz asıl yavaş olan taraftı.
- Beyla, kod hiç değişmeden network seviyesindeki (HTTP/gRPC) çağrıları yakalayabildi, ama saf CPU'da geçen (network/syscall üretmeyen) kod bloklarını (`setTimeout` ile simüle edilen "business logic") HİÇ göremedi, bu sınır gerçekten gözlemlendi.
- Bu ikisi (OTel manuel instrumentation ve Beyla zero-instrumentation) birbirinin yerini tutmuyor: Beyla hızlı, kod değiştirmeden genel görünürlük sağlar ama kod içi mantığı göremez; OTel kod içi detaya inebilir ama entegrasyon emeği ister.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Bir trace'te span'ın adına güvenme, span'ın SINIRINA (nerede başlayıp nerede bittiğine) bak. Biz bilerek "spotify-api-call" adlı bir span'ın içine hem gerçek 150ms'lik HTTP çağrısını hem kendi 2.5 saniyelik "DB+logic" simülasyonumuzu gömdük, sonuç: trace ekranında "Spotify 2.65 saniye sürüyor" gibi göründü, oysa Spotify'ın suçu yoktu. Span'ı ikiye bölünce (`http-call-to-spotify` ve `db-write-and-business-logic`) gerçek tablo ortaya çıktı, darboğaz bizdeydi.

Beyla ile aynı zinciri de izledik, kod hiç değişmeden backend-spotify arası HTTP çağrısını doğru yakaladı, ama bizim "DB+logic" kısmımızı (network'e hiç çıkmayan, sadece CPU'da bekleyen bir kod bloğu) hiç göremedi. Bu, Beyla'nın (ve genel olarak eBPF'in) sınırını somut şekilde gösterdi: network/syscall sınırının dışında kalan hiçbir şeyi gözlemleyemez, bunun için OTel'in kod içine girmesi şart.

Yol boyunca bir de gerçek bir hata aldık: OTLP exporter'ı yanlış porta (4318, HTTP) yönlendirmiştik, Tempo Service sadece gRPC (4317) exposed ediyordu, `ECONNREFUSED` aldık, Service'in gerçek portlarını kontrol edip exporter'ı gRPC'ye çevirince çözüldü. Bu, "dokümantasyonda öyle yazıyor" demenin yetmediğini, gerçek Service tanımına bakmak gerektiğini hatırlattı.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
`OTLPExporterError: connect ECONNREFUSED tempo:4318` hatası alındı, backend OTel exporter'ı Tempo'nun 4318 (OTLP HTTP) portuna bağlanmaya çalışıyordu ama `kubectl get svc tempo -n monitoring -o jsonpath='{.spec.ports}'` ile bakıldığında bu portun hiç expose edilmediği görüldü, sadece 3100 (query API) ve 4317 (OTLP gRPC) vardı. Çözüm, `@opentelemetry/exporter-trace-otlp-http` yerine `@opentelemetry/exporter-trace-otlp-grpc` paketine geçip URL'i `http://tempo:4317` olarak güncellemekti.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- OpenTelemetry Node.js SDK resmi dokümantasyonu (manuel span oluşturma, OTLP exporter'lar)
- Grafana Tempo resmi dokümantasyonu (OTLP HTTP/gRPC portları)
- Grafana Beyla resmi dokümantasyonu (eBPF ile zero-instrumentation, desteklenen protokoller)
