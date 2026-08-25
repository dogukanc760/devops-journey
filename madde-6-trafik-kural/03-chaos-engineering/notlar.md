# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Şu ana kadar circuit breaker, retry, mTLS gibi mekanizmaları kurduk ama hepsini sadece biz gerçek bir bug ya da restart ile tetiklediğimizde test ettik. Production'da bir node'un çökmesi, network'ün gecikmesi, bir pod'un öldürülmesi gibi olaylar senin kontrolünde değil, ne zaman olacağını bilmiyorsun. Bu olmasaydı ne olurdu diye sorarsak, kurduğun circuit breaker'ın veya retry policy'nin gerçekten işe yarayıp yaramadığını ancak gerçek bir kesinti anında, en kötü zamanda öğrenirdin, kontrollü ve önceden planlanmış bir şekilde değil.

Temel:

- Chaos Engineering: sisteme kontrollü şekilde bilerek arıza enjekte edip dayanıklılığı doğrulama disiplini
- Chaos Mesh: Kubernetes üzerinde CRD tabanlı (PodChaos, NetworkChaos vs) çalışan bir chaos engineering aracı
- Blast radius: bir deneyin etkilediği kaynak alanı, ne kadar dar tutulursa deneyin yan etkisi o kadar sınırlı kalır
- Steady state hypothesis: "sistem normalde şöyle davranır" varsayımı, deney öncesi ve sonrası bu varsayımın hâlâ geçerli olup olmadığına bakılır
- Duration: bir chaos deneyinin kendiliğinden ne zaman sona ereceğini belirleyen süre, elle müdahale gerekmeden fault'un geri alınmasını garantiler

Örnek Soru:
Chaos Mesh ile bilerek `backend` pod'unu öldüren bir deney (`PodChaos`) çalıştırıyorsun ve sistemin kendini toparladığını gözlemliyorsun, her şey yeşil görünüyor. Ama bunu production'da değil, sadece staging'de düşük trafik saatinde çalıştırdın. Bu deneyin sonucuna "production'da da böyle davranır" diye güvenmek neden riskli olabilir? Ayrıca, bir chaos deneyini durduramaz hale gelirsen (deney scriptin bug'lıysa ya da Chaos Mesh controller'ın kendisi bir sorun yaşıyorsa) elinde hangi güvenlik ağı olmalı?

Cevap:
İki kere ölç bir kere kes mantığı doğru yönde, hiçbir chaos aracı "her senaryoyu yakaladım" garantisi vermez, bu yüzden az az ve kontrollü ilerlemek her zaman daha güvenlidir. Ama staging sonucunun prod'a taşınmamasının somut bir teknik sebebi var, staging genelde gerçek trafik hacmine sahip değildir, bağımlılıkların bir kısmı mock/stub'dır, cluster daha küçüktür. Circuit breaker'ın half-open denemesi düşük trafikte sorunsuz görünebilir ama prod'da aynı anda binlerce isteğin recovery anına denk gelmesi ani bir yük patlaması yaratıp devreyi hemen tekrar açabilir, ya da birden fazla replikada aynı anda tetiklenen circuit breaker'lar zincirleme etkileşime girebilir, bunlar düşük trafikli staging'de asla görünmez. Kademeli olarak daha gerçekçi ortamlara (staging düşük trafik, staging yüksek trafik simülasyonu, sonra prod'da küçük blast radius) taşımak doğru yaklaşım.

Güvenlik ağı konusunda blast radius'u izole etme fikri doğru yönde ama Chaos Mesh'in asıl sağladığı mekanizma biraz farklı çalışıyor. Her deney bir Kubernetes CRD'si (PodChaos, NetworkChaos vs) olarak tanımlanır, deneyin kendisi uygulamanın içine hiç girmez, ayrı bir controller üzerinden fault enjekte eder. Asıl "acil durdur" mekanizması script'i durdurmaya çalışmak değil, doğrudan `kubectl delete podchaos <isim>` ile o CR'ı silmek, bu komut deneyi sonlandırır ve enjekte edilen fault'u geri alır. Buna ek olarak her deneye bir `duration` alanı koymak, script çalışmaz hale gelse bile deneyin kendiliğinden süresi dolup sonlanmasını garantiler, ve selector'da `mode: one` ya da `fixed-percent` kullanmak deneyin tüm replikaları değil sadece küçük bir kısmını hedeflemesini sağlar, blast radius'u baştan sınırlar. Güvenlik ağı üç katmanlı, otomatik süre sınırı, dar hedef seçimi, elle anında durdurabilme.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- `PodChaos` ile `mode: one`, deneyi rastgele SEÇİLEN tek bir replikaya uygular, tüm sistemi değil sadece dayanıklılık mekanizmalarını (circuit breaker, retry) test eder.
- `NetworkChaos` ile enjekte edilen gecikme (`delay`), önceki subtopic'te kurduğumuz `perTryTimeout` gibi zaman bazlı ayarların gerçek dünyada ne kadar kırılgan olduğunu ortaya çıkarır, iki farklı katmanın (chaos + service mesh) ayarları birbiriyle çakışabilir.
- `mode: all` ile bir deneyi TÜM repliklara aynı anda uygulamak, dayanıklılığı test etmek yerine gerçek bir kesinti yaratır, çünkü sağlıklı bir replika kalmayınca circuit breaker'ın yönlendirebileceği hiçbir yer kalmaz.
- Chaos Mesh CR'ları silinirken bir finalizer üzerinden temizlik yapar, hedef pod'lar CR silinmeden önce zaten başka bir sebeple (örn. otomatik yeniden zamanlama) ortadan kalkmışsa finalizer bu pod'ları bulamayıp CR'ı "Terminating" durumunda takılı bırakabilir, bu durumda finalizer elle temizlenmelidir.
- `duration` alanı olmayan ya da çok uzun tutulan bir deney, script çökse bile kendiliğinden sonlanmaz, bu yüzden her deneyde makul bir süre sınırı zorunlu tutulmalı.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Chaos Engineering'i "kendi kendine yangın tatbikatı yapmak" gibi düşün, gerçek bir yangın çıkmasını beklemek yerine kontrollü şekilde küçük bir yangın çıkarıp tatbikatın işe yarayıp yaramadığını görüyorsun. En öğretici kısım, dar hedefli (mode: one) bir deney ile gerçekten yıkıcı (mode: all) bir deney arasındaki farkı bizzat görmekti, ilki circuit breaker'ın işe yaradığını kanıtladı, ikincisi ise circuit breaker'ın da hiçbir işe yaramadığı bir tam kesinti yarattı çünkü yönlendirebileceği sağlıklı hiçbir replika kalmamıştı.

İkinci öğretici kısım, NetworkChaos ile enjekte ettiğimiz gecikmenin, Service Mesh subtopic'inde kurduğumuz perTryTimeout ile çakışmasıydı, iki farklı katmanın ayarları birbirinden habersiz çalışınca beklenmedik bir başarısızlık ortaya çıkabiliyor. Üçüncüsü ise Chaos Mesh'in "acil durdur" mekanizmasının her zaman anında çalışmayabileceğini gördük, finalizer'ın takılı kalması gerçek bir tedirginlik yarattı ama elle müdahale ile çözülebilir bir durumdu.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
1. `NetworkChaos` ile backend'e 2 saniyelik gecikme enjekte edildikten sonra, Service Mesh subtopic'inde kurulan retry policy hâlâ %100 başarısız isteklerle sonuçlandı. Sebep, `perTryTimeout`'un 500ms olarak ayarlı olması, enjekte edilen 2 saniyelik gecikmeden çok daha kısa kalması, her deneme retryOn koşuluna (5xx) hiç ulaşmadan timeout'tan tükeniyordu, tıpkı Service Mesh subtopic'inde yaşanan ilk hataya benzer bir mantıkla ama bu sefer sebep chaos deneyiydi, yanlış policy değildi. Çözüm, bu deney süresince `perTryTimeout`'u geçici olarak 3 saniyeye çekmekti, sonrasında retry mekanizması gecikmeyi tolere edip başarılı sonuç döndü.
2. Blast radius kasıtlı olarak `mode: all` yapılıp backend'in TÜM replikaları aynı anda öldürüldüğünde, sistem circuit breaker'a rağmen tam kesintiye girdi, tüm istekler 503 döndü. Sebep, circuit breaker'ın sadece kötü bir replikayı devre dışı bırakabilmesi, yönlendirebileceği sağlıklı hiçbir replika kalmayınca korumanın hiçbir anlamı kalmamasıydı. Bu, blast radius'un neden mutlaka dar tutulması gerektiğinin canlı kanıtı oldu.
3. Deneyi durdurmak için `kubectl delete podchaos backend-kill-all` çalıştırıldığında CR "Terminating" durumunda takılı kaldı, silinmedi. Sebep, hedef pod'ların CR silinmeden önce zaten Kubernetes tarafından otomatik olarak yeniden zamanlanıp değişmiş olması, Chaos Mesh finalizer'ının temizlemeye çalıştığı orijinal pod referanslarını bulamamasıydı. Çözüm, `kubectl patch podchaos backend-kill-all -p '{"metadata":{"finalizers":[]}}' --type=merge` ile finalizer'ı elle temizlemekti, CR hemen ardından silindi.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- Chaos Mesh resmi dokümantasyonu (PodChaos, NetworkChaos, duration, finalizer davranışı)
- Principles of Chaos Engineering (principlesofchaos.org)
- Netflix Chaos Monkey ve blast radius kavramı üzerine yazılar
