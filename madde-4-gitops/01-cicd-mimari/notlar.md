# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Şu ana kadar hep manuel olarak `docker build`, `kubectl apply` gibi komutları elle çalıştırdık. Gerçek bir ekipte bu ölçeklenmez: biri kod push eder, testleri unutur, güvenlik taramasını atlar, yanlış ortama deploy eder, ya da sadece kendi makinesinde "bende çalışıyordu" der. Bu olmasaydı ne olurdu diye sorarsak, her deploy insan hafızasına ve disiplinine bağlı kalırdı, bir adımı unutmak (test, scan, doğru tag) production'a kırık ya da güvensiz kod sızmasına yol açardı, iki farklı geliştirici iki farklı şekilde deploy ederdi, tutarlılık olmazdı.

Temel:

- Pipeline: kodun repoya girmesinden production'a çıkmasına kadar geçen, otomatik ve sıralı adımlar zinciri (Lint → Test → Security Scan → Build → Publish → Deploy)
- Pipeline as Code: pipeline tanımı da Git'te yaşar (`.github/workflows/`), versiyonlanır, review edilir
- Self-hosted runner: pipeline'ın adımlarını çalıştıran işçi, kendi altyapında barındırılır, izole ve kontrollü
- Runner isolation: her job temiz, sıfırdan bir container içinde başlar, bir job'un kalıntısı diğerini etkilemez
- Paralel job: birbirine bağımlı olmayan adımlar (örn. lint ve test) aynı anda çalıştırılıp süre kısaltılır
- Artifact: pipeline'ın ürettiği çıktı (docker imajı, binary), versiyonlu saklanır, sonraki job'lara aktarılır
- Cache stratejisi: dependency indirmelerini (npm/pip/go modülleri) tekrar tekrar yapmamak için önbelleğe alma

Örnek Soru:
Bir pipeline'ın şu aşamaları var: Lint → Test → Security Scan → Build → Publish → Deploy. "Security Scan" adımı 4 dakika, "Test" adımı 3 dakika sürüyor ve ikisi de birbirinden bağımsız, ama ikisi de "Build" adımından önce tamamlanmış olmalı. Bu pipeline'ı nasıl tasarlarsın ki hem doğru sıralama korunsun hem de toplam süre gereksiz yere uzamasın? Ayrıca, "Deploy" adımı neden pipeline'ın en sonunda ve neden bazı organizasyonlarda otomatik değil, manuel onaya bağlı olur?

Cevap:
Test ve Security Scan paralel çalıştırılır (aralarında bağımlılık yok), Build ise ikisine de bağımlı olur (`needs: [test, security-scan]`), yani ikisi de bitmeden başlamaz. Sıralı çalışsaydı 3+4=7 dakika sürerdi, paralelde ikisinin en yavaşı kadar (4 dakika) sürer, 3 dakika kazanılır. Buna ek olarak Build adımının kendisi de multi-stage Docker build ve layer caching ile hızlandırılabilir, değişmeyen katmanlar (örn. dependency install) yeniden build edilmez, bu ayrı bir optimizasyon boyutu ama aynı toplam süreyi düşürme hedefine hizmet eder. Deploy'un en sonda olması mantıken zorunlu: henüz build edilip publish edilmemiş bir imaj deploy edilemez, fiziksel olarak elde ortada bir şey yoktur. Manuel onay ise organizasyonel bir karar, production'a giden yolun kalite kontrolünden (test, scan) geçmesi yetmeyebilir, insan onayı ekstra bir güvenlik/kalite katmanı ekler, özellikle prod branch'i için.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- Job bağımlılığı (`needs`): birbirine `needs` ile bağlı olmayan job'lar GitHub Actions'ta otomatik olarak paralel çalışır, bu varsayılan davranıştır, elle "paralel çalıştır" demeye gerek yoktur, sadece bağımlılık YAZMAMAK yeterlidir.
- `needs: [lint, test, security-scan]` gibi çoklu bağımlılık, o job'un listedeki HEPSİ bitmeden başlamayacağı anlamına gelir, en yavaş olanı ne kadar sürerse taban o kadar olur.
- Bir job fail olunca ona `needs` ile bağımlı olan downstream job'lar hiç TETİKLENMEZ (skipped), bu "kalite kapısı" davranışının somut hali, lint hatası varken build'in çalışmaması israf değil, güvenlik.
- Multi-stage Docker build: `deps` katmanı sadece `package*.json` değişince yeniden build edilir, kod değişikliği bu katmanı tetiklemez, cache'ten gelir, build süresini kısaltır.
- Dependency cache (`actions/setup-node` içindeki `cache: 'npm'`), `npm ci`'ın internetten indirme yerine cache'ten okumasını sağlar, küçük projede saniyeler, büyük monorepo'da dakikalar kazandırır.
- Job output'ları (`outputs: image_tag`) bir job'da üretilen bir değerin (örn. imaj tag'i) sonraki job'lara güvenli şekilde aktarılmasını sağlar, dosyaya yazıp okumak yerine pipeline'ın kendi mekanizması kullanılır.
- `if: github.ref == 'refs/heads/main'` koşulu, bir job'un sadece belirli bir branch'te çalışmasını sağlar, feature branch'lerinde deploy gibi riskli adımlar hiç tetiklenmez.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Pipeline'ı bir kalite kapısı gibi düşün, sadece "script çalıştıran bir sistem" değil. Lint, Test ve Security Scan birbirinden bağımsız olduğu için paralel çalıştırdık, aralarında `needs` tanımlamadık, GitHub Actions bunu otomatik paralel yapıyor. Build ise üçüne de bağımlı, `needs: [lint, test, security-scan]`, hiçbiri bitmeden başlamıyor. Süre olarak sıralı çalışsaydı üçünün toplamı kadar sürerdi, paralelde en yavaşı kadar sürüyor, gerçek pipeline'da bu dakikalar mertebesinde fark yaratıyor.

En can alıcı davranış, bir job fail olunca ona bağımlı olan job'ların hiç tetiklenmemesi. Lint'i kasıtlı bozduğumuzda build hiç çalışmadı bile, bu tam istediğimiz şey, kırık/güvensiz kod bir sonraki adıma hiç geçmiyor. Deploy'u da hem mantıken en sona koyduk (imaj yoksa deploy edilecek bir şey de yok) hem de `if: github.ref == 'refs/heads/main'` ile sadece main branch'ine kısıtladık, feature branch'lerinde push yapınca deploy hiç tetiklenmiyor, riskli adım sadece doğru koşulda çalışıyor.

Cache de gözden kaçmaması gereken bir detay, `npm ci`'ın her seferinde internetten indirmesi yerine cache'ten okuması küçük bir projede bile gözle görülür süre kazandırdı.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
Kasıtlı olarak lint'i bozduk (`index.js` içine geçersiz bir syntax eklendi), lint job'u ESLint hatasıyla (fazladan noktalı virgül) fail oldu. Beklenen ve istenen davranış gerçekleşti: `needs: [lint, test, security-scan]` bağımlılığı yüzünden build job'u hiç tetiklenmedi, "skipped" olarak göründü. Bu bir arıza değil, pipeline'ın tam da tasarlandığı gibi çalışması, kırık kod bir sonraki adıma hiç geçmedi.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- GitHub Actions resmi dokümantasyonu (jobs.<job_id>.needs, self-hosted runners)
- Docker multi-stage build resmi dokümantasyonu
