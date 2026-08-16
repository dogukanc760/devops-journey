# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
SLO/Error Budget dahil şu ana kadar kurduğumuz her şey GERÇEK kullanıcı trafiğine dayanıyor, bir şeyin hata verdiğini ancak gerçek bir kullanıcı o isteği attığında görebiliyoruz. Ama trafiğin çok az olduğu saatlerde gerçek trafik neredeyse hiç yok, sistem bozuk olsa bile bunu fark etmen saatler sürebilir, çünkü fark edecek yeterli sayıda gerçek istek yok. Bu olmasaydı ne olurdu diye sorarsak, login ekranı gece yarısı bozulsa, sabah ilk kullanıcı şikayet edene kadar kimse fark etmezdi, "sistem sağlıklı" sanılırken aslında kimse test etmediği için öyle görünüyordur.

Temel:

- Synthetic monitoring: gerçek bir kullanıcı gibi davranan, düzenli aralıklarla kritik bir senaryoyu test eden bir bot/script
- Grafana k6: script tabanlı, hem yük testi hem senaryo bazlı synthetic test için kullanılabilen bir araç
- Blackbox Exporter: bir endpoint'in HTTP/TCP/ICMP ile "ayakta mı" diye probe eden basit bir Prometheus exporter'ı
- On-call rotation: alarm geldiğinde kimin sorumlu olduğunu belirleyen dönüşümlü nöbet sistemi
- Runbook: alarm geldiğinde nöbetçinin adım adım ne yapacağını anlatan, önceden yazılmış doküman

Örnek Soru:
Hem Blackbox Exporter ile `/health` endpoint'ini her 30 saniyede probe ediyorsun, hem de k6 ile her 1 dakikada gerçek bir login senaryosunu test ediyorsun. Bir gün `/health` "200 OK" dönmeye devam ediyor ama k6 senaryosu login sonrası dashboard'un boş geldiğini yakalayıp fail oluyor. Bu iki farklı sonuç neyi gösteriyor, `/health`'in "sağlıklı" demesi neden yanlış bir güven duygusu yaratabilir? Ayrıca, alarm gece 3'te geldiğinde nöbetçinin runbook'a bakmadan önce yapması GEREKMEYEN şey ne olurdu?

Cevap:
`/health` endpoint'i genelde sığ bir kontrol yapar: "DB'ye/MinIO'ya bağlanabiliyor muyum" gibi altyapısal testler, bunlar 200 dönmek için yeterli olabilir ama uygulamanın GERÇEK iş akışının (login sonrası doğru veri gelmesi) çalıştığını hiç garanti etmez. Bu, K8s'teki liveness/readiness probe'un taşıdığı aynı sınırlama: "süreç ayakta ve temel bağımlılıklarına erişebiliyor" ile "kullanıcı gerçekten işini yapabiliyor" farklı seviyeler, k6 senaryosu ikinciyi test eder. Sığ health check'e güvenmek, "her şey yeşil" derken kullanıcı deneyiminin bozuk olabileceği bir kör noktayı gizler.

Runbook'un asıl önlediği şey, gece 3'te yarı uykulu bir mühendisin runbook olmadan doğaçlama yapması: denenmemiş bir komutu production'da rastgele çalıştırması, yanlış servisi restart/rollback etmesi, ya da adımları hatırlamaya çalışırken kritik dakikaları kaybetmesi. Runbook, soğukkanlı değilken doğaçlama riskli müdahalede bulunma ihtimalini ortadan kaldırıp önceden düşünülmüş bir prosedürü takip ettirir, insanın yerine geçmez ama insanın panikle vereceği kötü kararları engeller.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- Blackbox Exporter ile k6 farklı katmanları test eder: Blackbox "endpoint ayakta mı, doğru status code dönüyor mu" (sığ), k6 "gerçek bir kullanıcı senaryosu uçtan uca doğru çalışıyor mu" (derin). İkisi birbirinin yerine geçmez, ikisi birlikte kullanılmalı.
- Standart Homebrew k6 binary'si Prometheus remote-write çıktısını DESTEKLEMEZ, bu özellik `xk6` ile `xk6-output-prometheus-remote` eklentisiyle özel derlenmiş bir k6 build'i gerektirir, standart binary ile denenince "unrecognised output" hatası alınır.
- k6 sonuçlarını (`k6_checks_total` gibi) Prometheus'a yazınca, bunlar üzerine normal PromQL alert'leri kurulabilir, synthetic test sonuçları da tıpkı gerçek metrikler gibi alerting sistemine entegre olur.
- Alertmanager silence (`amtool silence add`), belirli bir alert'i belirli bir süre için bilerek bastırır, planlı bakım/deploy pencerelerinde "beklenen, geçici" hataların gereksiz alarm üretmesini engeller. Süre dolunca sistem otomatik olarak tekrar normal alarm üretmeye döner, elle "geri aç" demeye gerek yoktur.
- Runbook'un içeriği somut ve sıralı olmalı: "önce şuna bak, sonra buna bak, X dakikada çözülmezse eskalasyon yap" gibi, "ne olabilir" listesi değil "ne yap" talimatı olmalı.
- Gerçek bir önceki dersten (SLO subtopic'inde Prometheus Operator'ın label seçimi) ders çıkarıp bu sefer Probe/PrometheusRule objelerine EN BAŞTAN `release: kube-prometheus` label'ı eklendi, aynı sessiz-yok-sayılma hatasına ikinci kez düşülmedi.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Sentetik izlemenin özü şu: gerçek kullanıcıyı beklemeden, kendi botunla sürekli sistemi test et. Ama iki farklı derinlikte test kurduk ve farkı gerçekten gördük: Blackbox Exporter'ın sığ `/health` kontrolü backend'e bilerek bir bug enjekte ettiğimizde bile YEŞİL kalmaya devam etti, çünkü sadece "süreç ayakta mı" diye bakıyordu. k6'nın gerçek senaryo testi ise aynı anda KIRMIZI oldu, çünkü dönen veriyi gerçekten kontrol ediyordu. Bu, "health check yeşil" demenin "her şey yolunda" anlamına gelmediğinin somut kanıtıydı.

Yol boyunca teknik bir engel de çıktı: k6'nın sonuçlarını Prometheus'a yazdırmak istediğimizde standart k6 binary'si bunu desteklemiyordu, `xk6` ile özel bir build gerekti. Bunu Docker image'ına gömüp CronJob içinde kullandık.

Runbook ve silence kısmında da iki ayrı ama ilişkili şey öğrendik: runbook, panik anında kötü doğaçlama yapmayı engelleyen somut bir prosedür; silence ise planlı bir bakım/deploy sırasında BEKLENEN geçici hataların gereksiz alarm üretmesini engelleyen bir mekanizma, ikisi de "gürültüyü azalt, gerçek sinyale odaklan" felsefesinin farklı parçaları.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
`k6 run --out experimental-prometheus-rw ...` çalıştırıldığında "ERRO[0000] unrecognised output "experimental-prometheus-rw"" hatası alındı. Sebep, Homebrew ile kurulan standart k6 binary'sinin Prometheus remote-write çıktısını içermemesi, bu özellik ayrı bir eklenti (`xk6-output-prometheus-remote`) ile derlenmiş özel bir build gerektiriyor. Çözüm, `xk6` aracıyla bu eklentiyi içeren özel bir k6 binary'si derleyip onu kullanmaktı, sonrasında metrikler sorunsuz Prometheus'a yazıldı.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- Grafana k6 resmi dokümantasyonu (xk6, Prometheus remote-write output)
- Prometheus Blackbox Exporter resmi dokümantasyonu
- Alertmanager silence/amtool resmi dokümantasyonu
- Google SRE Workbook - "Being On-Call" ve runbook yazımı bölümleri
