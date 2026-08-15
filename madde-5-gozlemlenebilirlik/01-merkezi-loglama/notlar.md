# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Şu ana kadar bir sorunu debug etmek istediğinde tek tek pod'lara girip `kubectl logs` çalıştırdık. Gerçek bir sistemde onlarca, yüzlerce pod var, biri hata verdiğinde hangi pod olduğunu bile bilmeyebilirsin. Bu olmasaydı ne olurdu diye sorarsak, bir hata production'da olduğunda hangi pod'un hangi node'da çalıştığını bulup tek tek log'una bakmak zorunda kalırdın, pod restart olup silindiyse (K8s'te pod'lar ölümlü, "ephemeral") o log sonsuza kadar kaybolurdu, hiçbir zaman ne olduğunu öğrenemezdin.

Temel:

- Loki: Prometheus'un log versiyonu gibi düşünülebilir, label bazlı çalışır, tüm log içeriğini indekslemez (maliyeti düşürür), sadece label'ları indeksler
- Promtail: her node'da çalışan, log dosyalarını toplayıp Loki'ye gönderen ajan (DaemonSet olarak deploy edilir)
- LogQL: Loki'nin sorgu dili, `{namespace="prod"} |= "ERROR"` gibi, önce label ile daralt sonra içerik filtrele
- Grafana: hem Loki loglarını hem Prometheus metriklerini aynı dashboard'da, yan yana gösterebilir
- Alert threshold: belirli bir metriğin (disk doluluk, error rate, crash loop) hangi değeri aşınca "alarm" sayılacağının tanımı
- Notification channel: alarm tetiklenince nereye bildirim gideceği (Slack, e-posta, PagerDuty)

Örnek Soru:
Loki + Promtail + Grafana stack'i kurulu, tüm namespace'lerin logları akıyor. Bir gün production'da bir pod sürekli crash loop'a giriyor (CrashLoopBackOff), sen fark etmeden önce pod 5 kere restart olmuş, her restart'ta eski loglar gitmiş. Loki bu durumda nasıl yardımcı olur ki `kubectl logs` tek başına yetersiz kalsın? Ayrıca, "pod crash loop başlayınca alert at" dediğimizde, bu alert'i LogQL sorgusuyla mı yoksa Prometheus metric'iyle mi tetiklersin, ikisi arasında ne fark var, hangisi bu senaryo için daha doğru?

Cevap:
`kubectl logs`, container runtime'ın kendi tuttuğu çok sınırlı bir kopyaya (genelde sadece current + `--previous`) bakar, restart'ları aşamaz. Promtail ise her log satırını ÜRETİLDİĞİ ANDA Loki'ye gönderir, yani Loki'deki kopya pod'un yaşam döngüsünden tamamen bağımsızdır, pod 5 kere restart olsa da her 5 restart'ın logu da Loki'de durur. Bunun üstüne Loki'nin sadece label'ları indeksleyip tüm metni indekslememesi, bu büyük hacimli tarihsel veride bile aramayı hem ucuz hem hızlı tutar, yani "loglar kaybolmuyor" (Promtail'in sürekli gönderimi) ile "bu kaybolmayan logda arama yapmak ucuz/pratik" (label bazlı indeksleme) iki ayrı ama birbirini tamamlayan gerçek, ikisi birlikte Loki'nin gücünü açıklıyor.

LogQL ile PromQL arasındaki seçim, verinin zaten YAPISAL/SAYISAL bir metrik olarak var olup olmadığına bağlı. Disk doluluk (`node_filesystem_*`, node-exporter) ve error budget/burn rate (Prometheus üzerinden hesaplanan bir oran) zaten hazır metrikler olduğu için PromQL ile izlenir, loglardan grep'lemeye çalışmak hem yanlış katman hem gereksiz maliyetlidir. Crash loop senaryosu için de asıl doğru araç PromQL: crash loop durumu zaten Kubernetes'in kendisi (kubelet/API server) tarafından tespit edilip bir OBJE DURUMU olarak tutulur, `kube-state-metrics` üzerinden `kube_pod_container_status_restarts_total` / `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}` gibi hazır bir metrik olarak zaten mevcuttur. Uygulamanın kendi logunda "crash loop'a girdim" diye bir satır yazmasına gerek yoktur, çoğu zaman çökerken bunu yazacak fırsatı bile bulamaz, bu yüzden bu durumu LogQL ile yakalamaya çalışmak güvenilmezdir.

Genel prensip: bir şey zaten yapısal/sayısal bir state olarak (K8s objesi, node metriği, uygulamanın instrument ettiği sayaç) mevcutsa PromQL kullanılır, sadece SERBEST METİN içeriğinde (belirli bir exception mesajı, hiçbir metrikte karşılığı olmayan bir iş mantığı hatası) aranıyorsa LogQL kullanılır (Loki'nin `count_over_time`/`rate()` fonksiyonlarıyla log eşleşmeleri bile bir metriğe çevrilip alert'e bağlanabilir, ama bu son çaredir, öncelik her zaman var olan metriktir).

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- `kubectl logs --previous` bile sadece BİR restart öncesine gidebilir, 2. ve öncesi restart'ların logu tamamen kaybolur. Loki'de ise Promtail'in sürekli/anlık gönderimi sayesinde TÜM restart'ların logu, zaman damgalarıyla birlikte sorgulanabilir kalır.
- `kube-state-metrics`, K8s obje durumlarını (restart sayısı, pod phase, waiting reason gibi) Prometheus'un okuyabileceği metriklere çevirir, `kube_pod_container_status_restarts_total` bunlardan biri, log parse etmeye hiç gerek kalmadan restart sayısını izlemeyi sağlar.
- PromQL alert'i (yapısal state'e dayandığı için) LogQL alert'inden daha hızlı VE daha güvenilir çıktı, çünkü LogQL alert'i uygulamanın gerçekten "ERROR" satırını basabilmiş olmasına bağımlı, PromQL ise K8s'in kendi tuttuğu duruma bağımlı, uygulama hiç log basamasa bile (örn. OOMKilled) çalışmaya devam eder.
- Genel karar kuralı: veri zaten yapısal/sayısal bir metrik olarak mevcutsa PromQL, sadece serbest metin içeriğinde aranıyorsa LogQL (ve LogQL'in `count_over_time` gibi fonksiyonlarıyla bile log eşleşmeleri metriğe çevrilip alert'e bağlanabilir, ama bu son çaredir).
- Grafana Explore ekranı, Loki ve Prometheus datasource'larını aynı arayüzde ayrı sorgu dilleriyle (LogQL/PromQL) sorgulamayı sağlar, ikisini karşılaştırmak veya bir metrikten bir log'a "drill down" yapmak için kullanılır.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
`kubectl logs` pod'un kendi hafızasına bakar, o hafıza restart'larda siliniyor. Loki bunun tam çözümü: Promtail her satırı ANLIK olarak Loki'ye gönderiyor, yani Loki'deki kopya pod'un yaşam döngüsünden bağımsız, pod 5 kere restart olsa da 5 restart'ın da logu duruyor. Gerçekten test ettik: `kubectl logs --previous` sadece bir önceki denemeyi gösterdi, Loki'de aynı pod'un TÜM restart'ları LogQL ile sorgulanabildi.

Alert kısmında asıl önemli ders şuydu: crash loop gibi bir durumu tespit etmek için LogQL değil PromQL kullanmak lazım, çünkü crash loop zaten K8s'in kendisinin tuttuğu bir obje durumu (`kube_pod_container_status_restarts_total`), uygulamanın bunu loglamasına hiç gerek yok. Gerçekten iki alert de kurduk, PromQL tabanlı olan hem daha hızlı tetiklendi hem de uygulamanın log basıp basmamasından bağımsız çalıştı, LogQL tabanlı olan ise daha yavaştı ve "ERROR" satırının gerçekten loglanmış olmasına bağımlıydı. Genel kural: veri zaten bir metrikse PromQL, sadece serbest metinde aranıyorsa LogQL.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
Gerçek bir hata değil ama öğretici bir gözlem: LogQL tabanlı alert (`count_over_time({app="crash-loop-demo"} |= "ERROR" [1m]) > 3`) PromQL tabanlı alert'ten (`kube_pod_container_status_restarts_total > 3`) daha GEÇ tetiklendi. Sebep, log satırının Promtail tarafından toplanıp Loki'ye yazılması ve indekslenmesi arasında küçük bir gecikme olması, PromQL ise doğrudan kube-state-metrics'in anlık ölçtüğü bir sayacı okuyor, aradaki toplama/gönderme adımı yok. Bu, "hangisini seçmeliyim" sorusuna hız açısından da somut bir kanıt oldu.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- Grafana Loki resmi dokümantasyonu (LogQL, label indeksleme mimarisi)
- kube-state-metrics resmi dokümantasyonu (hangi K8s obje durumları hangi metriklere karşılık geliyor)
- Prometheus Alerting/PrometheusRule (Operator) resmi dokümantasyonu
