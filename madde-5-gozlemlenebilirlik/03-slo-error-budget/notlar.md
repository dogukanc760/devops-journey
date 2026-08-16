# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Loglama ve tracing ile artık "bir şey ne zaman hata verdi, nerede yavaşladı" sorularını cevaplayabiliyoruz. Ama bu bilgiler tek başına "sistemimiz sağlıklı mı" sorusuna cevap vermiyor, sürekli tek tek olaylara bakıp karar vermek subjektif kalır. Bu olmasaydı ne olurdu diye sorarsak, ekip içinde "ne kadar hata kabul edilebilir" konusunda ortak bir dil olmazdı, her deploy sonrası "acaba her şey yolunda mı" sorusu belirsiz kalırdı, "bu ay çok fazla kesinti yaşadık" gibi iddialar somut bir sayıya dayanmadan tartışılırdı.

Temel:

- SLI (Service Level Indicator): gerçekte ölçtüğün değer (örn. "son 30 günde isteklerin %99.95'i başarılı döndü")
- SLO (Service Level Objective): hedeflediğin değer (örn. "%99.9 başarı oranı istiyoruz")
- SLA (Service Level Agreement): müşteriyle yapılan resmi anlaşma, genelde SLO'dan biraz daha gevşek tutulur
- Error Budget: SLO'nun tersinden okunuşu, %99.9 hedefliyorsan ayda ~43 dakikalık "hata hakkın" var demektir
- Burn rate: error budget'ının ne HIZDA tüketildiği, normalden hızlı tüketim erken uyarı sinyalidir
- Sloth/Pyrra: SLO tanımından otomatik Prometheus recording/alerting rule'ları üreten araçlar

Örnek Soru:
Bir servisin SLO'su %99.9 availability (ayda ~43 dakika error budget). Ayın 5. günü tek seferlik 30 dakikalık bir kesinti yaşandı. İki senaryo: (1) geri kalan 25 günde küçük hatalar birikip kalan ~13 dakika da tükenirse, (2) hiç ek hata olmazsa ay sonunda bütçenin %70'i harcanmış ama SLO teknik olarak tutturulmuş olur. Bu iki senaryoda "error budget tükendiğinde deploy dur" politikası nasıl farklı davranır, ve burn rate kavramı bu iki senaryoyu ayırt etmede neden tek başına aylık toplam yüzdeden daha faydalı bir sinyal?

Cevap:
Birinci senaryoda bütçe fiziksel olarak sıfırlanır, "deploy dur" politikası devreye girer, ayın geri kalanında sadece stabilite çalışması yapılabilir, bu resmi bir SLO ihlalidir. İkinci senaryoda "error budget tükendi" durumu hiç gerçekleşmez, politika deploy'ları durdurmaz çünkü SLO teknik olarak karşılanmıştır, ama %70'in tek bir olayla gitmiş olması yine de bir uyarı sinyali olmalı, sistemin tamponu ince kalmıştır.

Burn rate'in aylık toplam yüzdeden daha faydalı olmasının sebebi zamanlama/hız bilgisini taşımasıdır. Toplam yüzde sadece "ne kadar harcandı" der, "ne kadar hızlı harcandı" demez. Burn rate, "normal hızda tükenmiş olsaydım bu günde ne kadar harcamış olmam gerekirdi" ile "gerçekte ne kadar harcadım" oranını karşılaştırır. Birinci senaryoda burn rate başlangıçta çok yüksektir (5. günde normalden çok daha fazlası gitmiştir), bu erken ve net bir alarm verir, bütçe tamamen tükenmeden müdahale imkanı sağlar. Toplam yüzdeye bakan bir sistem ise ancak bütçe fiilen bitince tepki verir, çok geç kalmış olabilir. Burn rate, trendi erken yakalayan bir öncü göstergedir, toplam yüzde sadece "şu an neredeyiz" diyen bir anlık fotoğraftır.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- Sloth, bir SLO tanımından (`PrometheusServiceLevel` custom resource) otomatik olarak Prometheus recording rule'ları (SLI'yi zamanla hesaplayan) ve alerting rule'ları (burn rate eşiğini izleyen) üretir, elle PromQL yazmaktan kurtarır.
- Prometheus Operator'ın `ruleSelector`'ı (kube-prometheus-stack'te varsayılan `release: kube-prometheus` label'ı) hangi PrometheusRule objelerini gerçekten okuyacağını belirler, bu label eksikse kural cluster'da var olur ama HİÇBİR HATA VERMEDEN sessizce yok sayılır, bu Prometheus Operator ekosisteminde sık düşülen bir tuzak.
- Kısa pencereli (5m) ve uzun pencereli (1h/1d) burn rate birlikte kullanılır: kısa pencere hızlı ama gürültülü sinyal verir, uzun pencere daha yavaş ama daha güvenilir, Sloth'un ürettiği multi-window burn rate alert'leri ikisini birleştirip false-positive'i azaltır.
- Error budget aylık KÜMÜLATİF bir pencere üzerinden hesaplanır, bir bug düzeltilip burn rate anlık olarak normale dönse bile, o ay içinde HARCANMIŞ olan bütçe geri gelmez, sadece zamanla (pencere ilerleyip eski kötü veri pencereden çıkınca) iyileşir. "İyileşmek" (burn rate normale dönmek) ile "bütçeyi geri kazanmak" farklı şeylerdir.
- `slo:sli_error:ratio_rate30d` ve `slo:error_budget:ratio` gibi Sloth'un ürettiği recording rule isimleri, ham SLI/SLO hesaplamalarını PromQL ile her seferinde yeniden hesaplamak yerine önceden hesaplanmış, hazır sorgulanabilir metrikler olarak sunar.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
SLO/Error Budget'ı "ne kadar hata kabul edilebilir" sorusuna somut bir sayı vermek olarak düşün. Sloth ile bunu Prometheus'a otomatik kurallar olarak yazdırdık, elle PromQL yazmadık. Ama gerçek bir hataya düştük: Sloth'un ürettiği kurallar cluster'da vardı ama Prometheus onları hiç okumuyordu, hiçbir hata mesajı da yoktu, sessizce yok sayılıyordu. Sebep, Prometheus Operator'ın sadece belirli bir label'a (`release: kube-prometheus`) sahip kuralları seçecek şekilde kurulu olması, Sloth'un çıktısında bu label eksikti. Bunu `kubectl get prometheusrules ... -o yaml` ile kuralın gerçekten var olduğunu ama label'ının eksik olduğunu görünce anladık.

Kötü deploy simülasyonunda en öğretici kısım, bug düzeltilince "her şey düzeldi" hissi versa da error budget'ın hemen geri gelmemesiydi. Burn rate (anlık tüketim hızı) normale döndü ama o ay için HARCANMIŞ olan bütçe hâlâ harcanmış durumda kaldı, çünkü error budget aylık kümülatif bir pencere. Bu, "artık iyiyiz" ile "artık tam bütçemiz var" arasındaki farkı gösterdi, ikincisi sadece zaman geçtikçe (pencere kaydıkça) düzelir.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
Sloth ile üretilen PrometheusRule cluster'a apply edildikten sonra Prometheus UI'ın Rules/Alerts sayfasında hiç görünmedi, ama `kubectl get prometheusrules` ile obje gerçekten vardı, hiçbir apply hatası da yoktu. Kök sebep, Prometheus Operator'ın `ruleSelector`'ının sadece `release: kube-prometheus` label'ına sahip PrometheusRule'ları izlemesi, Sloth'un varsayılan ürettiği YAML'da bu label'ın olmamasıydı. Çözüm, üretilen dosyaya `yq` ile elle bu label'ı eklemekti, sonrasında kurallar birkaç saniye içinde Prometheus'ta göründü. Bu hata özellikle sinsi çünkü "sessiz başarısızlık" (silent failure) kategorisinde, hiçbir log/hata mesajı seni doğru yöne yönlendirmiyor, doğrudan Prometheus Operator'ın seçim mantığını bilmek gerekiyor.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- Sloth resmi dokümantasyonu (PrometheusServiceLevel CRD, multi-window burn rate alerting)
- Prometheus Operator resmi dokümantasyonu (ruleSelector, PrometheusRule seçim mantığı)
- Google SRE Workbook - "Implementing SLOs" bölümü
