# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
CI/CD Mimari'de artık imajı otomatik build edip production'a deploy edebiliyoruz, ama "deploy et" dediğimiz an yeni sürüm birden %100 trafiği alırsa ne olur? Yeni kodda gözden kaçan bir bug varsa, tüm kullanıcılar aynı anda etkilenir, sen fark edene kadar (ki genelde şikayetler gelince fark edilir) herkes hatalı sürümü kullanmış olur. Bu olmasaydı ne olurdu diye sorarsak, her deploy bir kumar olurdu, ya tamamen iyi gider ya da tüm kullanıcı tabanını aynı anda etkileyen bir felaket olur, geri dönüş de ancak fark edildikten sonra, elle yapılırdı.

Temel:

- Canary: yeni sürüme önce küçük bir trafik dilimi (örn. %10) verilir, metrikler izlenir, sorun yoksa kademeli artırılır
- Argo Rollouts: standart K8s Deployment'ın yerini alan, canary/blue-green gibi stratejileri destekleyen bir controller
- Analysis Template: "başarılı" saymanın kriterini tanımlar, genelde Prometheus'tan çekilen bir metrik (örn. error rate, latency)
- Otomatik rollback: analiz metriği eşiği aşarsa (örn. error rate %5'i geçerse) sistem kendiliğinden eski sürüme döner, insan müdahalesi beklemez
- Flagger: benzer amaca hizmet eden alternatif bir araç, genelde Istio/Linkerd gibi bir service mesh ile birlikte çalışır

Örnek Soru:
Argo Rollouts ile bir canary stratejisi kurdun: %10 → bekle, metrikleri kontrol et → sorun yoksa %30 → bekle, kontrol et → %60 → %100. Yeni sürümde çok nadir tetiklenen bir bug var, sadece belirli bir kullanıcı segmentinde (örneğin belirli bir tarayıcıda) ortaya çıkıyor ve error rate'i sadece %1 artırıyor, senin eşiğin ise %5. Bu senaryoda canary süreci bu bug'ı yakalayabilir mi? Yakalayamazsa, bunu yakalamak için tasarımına ne eklemen gerekir?

Cevap:
Küçük trafik yüzdesinde örneklem boyutunun küçük olup istatistiksel gürültü yaratabileceği noktası doğru ve değerli, ama senaryonun asıl can alıcı noktası başka yerde. Bug'ın etkisi "error rate'i sadece %1 artırıyor" diye SABİT tanımlanmıştı, yani hangi aşamada (%10 mu %99 mu) ortaya çıktığından bağımsız olarak toplam (blended) error rate her zaman %5 eşiğinin altında kalır. Sorun "hangi aşamada çıktığı" değil, tek bir toplu metriğin dar bir segmentteki gerçek sinyali seyreltmesi: 1000 kullanıcının 20'si (dar bir tarayıcı segmenti) hata alsa bile, geri kalan 980'i sorunsuzsa toplam error rate küçük kalır, eşiği hiç geçmez. Çözüm "daha fazla gözlem aracı eklemek" değil, AnalysisTemplate'in sorgusunu SEGMENTE etmek: error rate'i tüm trafik için değil, user-agent/browser bazlı KIRARAK ölçmek.

İkinci ve daha kritik nokta: eklenmesi düşünülen araçların (Cilium/Hubble eBPF, Prometheus/Grafana) hepsi backend/network seviyesinde çalışır. Eğer bug "belirli bir tarayıcıda" ortaya çıkan bir şeyse, bu çoğu zaman CLIENT-SIDE (tarayıcıda çalışan JS kodunda) bir hatadır, backend'e hiçbir zaman bir 5xx ya da anormal istek olarak yansımayabilir, backend'in gözünde her şey normal görünür. Bu durumda ne kadar backend observability eklenirse eklensin bu bug yakalanamaz, çünkü hata backend'e hiç ulaşmaz. Bunun için gereken backend gözlemi değil, frontend/RUM (Real User Monitoring, Sentry gibi client-side error tracking) katmanıdır: tarayıcıda çalışan JS kodu kendi hatalarını (exception, promise rejection, network isteği başarısızlığı) doğrudan bir RUM servisine raporlar, backend'in bu hatadan hiç haberi olmasa bile.

Sonuç: tasarıma eklenmesi gereken iki şey, (1) analiz metriğini kullanıcı segmentine göre kırılmış (dimensioned) hale getirmek, tek bir blended sayı yerine, (2) hata client-side olabiliyorsa backend observability'nin yanına bir de frontend/RUM katmanı eklemek, çünkü ikisi tamamen farklı katmanları gözlemler ve biri diğerinin yerini tutamaz.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- Rollout objesi, Deployment'ın yerini alır ama `strategy.canary.steps` altında yüzde/bekleme adımlarını tanımlamana izin verir, controller bu adımları otomatik yürütür.
- AnalysisTemplate, Prometheus'a atılan bir sorgu ve bir `successCondition` tanımlar, her `pause` sonrası bu sorgu çalışır, sonucu koşulu geçmezse Rollout otomatik olarak "Degraded" olur ve geri döner.
- Blended/aggregate metrik tuzağı: tek bir toplu error rate sayısı, dar bir kullanıcı segmentindeki gerçek bir sorunu geri kalan büyük, sağlıklı trafiğin içinde seyreltip görünmez kılabilir. Test ederken gerçekten doğruladık: aynı bug, segmentsiz sorguda hiç yakalanmadı (%100'e kadar geçti), `max by (user_agent)` ile segmentli sorguda ilk adımda (%10) yakalandı.
- Segmentli Prometheus sorgusu (`by (user_agent)`, `max by (...)`) AnalysisTemplate'in neyi "kötü" sayacağını belirler, bu tasarım kararı otomatik rollback'in ne kadar duyarlı olacağını doğrudan etkiler.
- Backend observability (Cilium/Hubble, Prometheus/Grafana) ile frontend/RUM (Real User Monitoring) birbirinin yerini tutmaz. Client-side (tarayıcıda çalışan JS) bir hata, backend'e hiçbir zaman bir 5xx olarak yansımayabilir, bu durumda backend tarafında ne kadar iyi/segmentli gözlem olursa olsun hata görülemez, ayrı bir frontend error tracking katmanı (Sentry vb.) gerekir.
- Otomatik rollback, insan müdahalesi beklemeden Rollout'u önceki stabil sürüme döndürür, bu "kalite kapısı" mantığının canlı trafik üzerindeki hali.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Canary'nin işe yaraması için iki ayrı şeyin doğru olması lazım: doğru bir rollout stratejisi (yüzde yüzde artan trafik, aralarda bekleme) VE doğru bir analiz metriği. Stratejiyi doğru kursan bile, analiz metriğin yanlış tasarlanmışsa (tek bir toplu sayı) canary sana yalan güvenlik hissi verir, "her şey yeşil" der ama aslında dar bir kullanıcı grubu zarar görüyordur.

Bunu gerçekten test ettim: aynı bug'ı önce geniş/kaba (tüm trafiğin %14'ünü etkileyen) bir hata olarak enjekte ettim, segmentsiz metrik bunu hemen yakaladı, rollback tetiklendi, beklenen davranış. Sonra aynı bug'ı dar bir segmente (belirli bir User-Agent) hapsettim, aggregate error rate hiç eşiği geçmedi, bug %100 trafiğe kadar sızdı. Sorguyu `max by (user_agent)` ile segmentli hale getirince, aynı bug ilk adımda (%10 trafikte) yakalandı.

Bir de şunu unutmamak lazım: bazı hatalar backend'e hiç ulaşmaz, tamamen tarayıcı içinde patlar (JS exception gibi). O zaman backend'de ne kadar iyi/segmentli metrik olursa olsun hiçbir şey göremezsin, çünkü bakılan katman yanlış. Böyle durumlar için ayrı bir frontend/RUM aracı (Sentry gibi) backend observability'nin yanına eklenmeli, biri diğerinin yerine geçmiyor.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
Segmentsiz AnalysisTemplate ile dar segment bug'ını enjekte ettiğimde "hata" diye bir şey çıkmadı, tam tersi: Rollout hiçbir uyarı vermeden "Healthy" durumuna geçti, tüm adımları (%10 → %100) sorunsuzca geçti. Bu asıl tehlikeli olan senaryoydu, sistem "başarılı" dedi ama gerçekte bir kullanıcı segmenti %100 hata alıyordu. Kök sebep, AnalysisTemplate sorgusunun tüm trafiği tek bir sayıda toplaması, dar segmentteki sinyalin büyük/sağlıklı trafiğin içinde kaybolmasıydı. Çözüm sorguyu `by (user_agent)` ile kırıp `max` ile en kötü segmenti almaktı.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- Argo Rollouts resmi dokümantasyonu (canary strategy, AnalysisTemplate, Prometheus provider)
- Prometheus PromQL `by`/`sum`/`max` aggregation operators dokümantasyonu
