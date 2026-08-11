# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
CI/CD Mimari'de imajı build edip Publish'e kadar getirdik, Progressive Delivery'de canary ile tek bir ortamda güvenli deploy yapmayı öğrendik. Ama gerçek bir organizasyonda tek ortam yoktur, en az dev/staging/production üçlüsü vardır ve kod bu ortamlar arasında belirli bir sırayla, belirli kapılardan geçerek ilerlemelidir. Bu olmasaydı ne olurdu diye sorarsak, biri staging'i hiç test etmeden doğrudan production'a deploy edebilirdi, ya da her ortam farklı insanlar tarafından elle, farklı şekillerde güncellenirdi, "staging'de çalışıyordu ama prod'da neden farklı davranıyor" sorularına kimse net cevap veremezdi çünkü ortamlar arasında neyin gerçekten aynı olduğu belirsiz kalırdı.

Temel:

- GitOps: Git, sistemin "tek gerçek kaynağı" (single source of truth) olur, cluster'ın o an ne çalıştırdığı sorusunun cevabı her zaman bir Git commit'idir
- ArgoCD: Git repo'sundaki manifest'leri sürekli izleyip cluster'daki gerçek durumla karşılaştıran, farkı otomatik senkronize eden bir controller
- ApplicationSet: birden fazla ortamı (dev/staging/prod) tek bir template'ten üretme mekanizması
- Promotion gate: bir ortamdan bir sonrakine geçişin önündeki koşul, örneğin "staging'deki testler geçmeden prod'a hiç geçilemez"
- Manual approval: bazı gate'ler otomatik değil, bir insanın onayını gerektirir (GitHub Environment Protection Rules gibi mekanizmalarla)
- Image updater: yeni bir imaj tag'i registry'ye geldiğinde, ArgoCD'nin bunu otomatik fark edip ilgili ortamı güncellemesi

Örnek Soru:
Dev, staging ve production için üç ayrı ArgoCD Application'ın var. Bir geliştirici staging'de test ettiği bir değişikliği production'a taşımak istiyor. Bunu "production branch'ine merge et" diyerek mi (yeniden build), yoksa "production'daki imaj tag'ini staging'de doğrulanmış olanla değiştir" diyerek mi yaparsın? Bu iki yaklaşım arasındaki fark ne, ve GitOps'un "Git tek gerçek kaynak" prensibiyle hangisi daha tutarlı? Ayrıca, ArgoCD Image Updater otomatik olarak yeni bir tag'i prod'a da uygulasaydı, bu Promotion gate/manual approval kavramıyla nasıl çelişirdi?

Cevap:
Doğru yaklaşım "build once, promote everywhere": imaj SADECE BİR KERE build edilir (immutable bir tag, örn. git SHA alır), dev'e deploy edilen, staging'de test edilen ve prod'a giden AYNI imaj (aynı digest/SHA256) olmalı. Promotion, yeniden build tetiklemek değil, Git'teki prod overlay'inin `image:` referansını staging'de doğrulanmış olan digest'e (farklı bir ortam-suffix'i taşıyan tag ile, örn. `-prod`) güncellemektir. Eğer prod için yeniden build edilseydi, "staging'de test ettiğim şey" ile "prod'a giden şey" teorik olarak aynı olması gereken ama pratikte farklı olabilecek iki ayrı artifact olurdu (build zamanı farklı dependency versiyonu çözülebilir, base image güncellenmiş olabilir, build ortamı deterministik olmayabilir), bu da "staging'de doğruladım" garantisini anlamsız kılardı. Retagging (aynı digest'e yeni bir isim eklemek) ile rebuilding (yeniden inşa etmek) FARKLI ŞEYLER: `docker tag` altta yatan SHA256 digest'i DEĞİŞTİRMEZ, sadece ikinci bir isim ekler, bu yüzden ortam-bazlı suffix (`-staging`, `-prod`) ile retag'lemek hem "build once" prensibini korur hem de her ortamın image updater'ının (tag filter regex ile) sadece kendine ait tag'i izlemesini sağlayarak ortamları izole eder.

Image Updater otomatik olarak yeni bir tag'i prod'a da uygulasaydı, bu promotion gate/manual approval kavramıyla doğrudan çelişirdi: promotion sürecindeki koşullar (test, kalite kontrol, insan onayı) yok sayılmış, hiç onaylanmamış bir işlem sahte bir "onaylanmış" görünümüyle yayına gitmiş olurdu.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- Build once, promote everywhere: imaj bir kere build edilir, ortamlar arasında sadece Git'teki tag referansı değişir, yeniden build edilmez. `docker inspect --format='{{.Id}}'` ile iki farklı tag'in aynı digest'e işaret ettiği doğrulanabilir.
- Kustomize overlay yapısı (`base` + `overlays/dev|staging|prod`), ortak manifest'i tekrar etmeden her ortamın kendi image tag'ini/config'ini tutmasını sağlar.
- ApplicationSet, tek bir template'ten (generator ile) birden fazla ArgoCD Application üretir, üç ortam için üç kez aynı YAML'ı yazmaya gerek kalmaz.
- GitHub Environment Protection Rules (`environment: production` + required reviewers), bir workflow job'unun belirli bir noktada durup insan onayı beklemesini sağlar, onay gelmeden job hiç başlamaz.
- ArgoCD Image Updater'ın `allow-tags` regex'i (örn. `^.*-prod$`), her Application'ın SADECE kendi ortamına ait suffix'li tag'leri izlemesini sağlar, bu da ortamlar arası yanlışlıkla imaj sızmasını (staging'in prod tag'ini alması gibi) engeller.
- ÖNEMLİ BULGU: manuel onay (`environment: production`) sadece CI job'unu korur, Git repo'suna DOĞRUDAN yapılan bir push'u (branch protection olmadan) durdurmaz. Onay mekanizması tek başına yeterli değil, prod overlay yoluna ayrıca CODEOWNERS + branch protection (zorunlu PR review) eklenmesi gerekir, yoksa onay süreci turnikeden değil yandan atlanabilir.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Environment Promotion'ın özü "build once, promote everywhere". İmajı bir kere build ediyoruz, sonra dev'den staging'e, staging'den prod'a giderken YENİDEN BUILD ETMİYORUZ, sadece aynı digest'e ortam bazlı bir isim (retag) ekleyip Git'teki ilgili overlay'in tag referansını güncelliyoruz. Bunu `docker inspect` ile doğruladık, iki farklı tag birebir aynı SHA256'ya işaret ediyordu, yani prod'a giden şey staging'de test edilenle bayt bayt aynıydı.

Prod'a geçişi GitHub'ın "environment" onay mekanizmasıyla insan onayına bağladık, onay gelmeden job bekledi, tam istediğimiz kalite kapısı. Ama en öğretici kısım "boz" testinde çıktı: onay mekanizması sadece CI pipeline'ının İÇİNDEN geçen yolu koruyor, biri doğrudan Git'e (pipeline'ı hiç kullanmadan) push yaparsa, ArgoCD bunu normal bir değişiklik sayıp sync ediyor, hiçbir onay istemiyor. Yani "manuel onay var" demek tek başına yeterli güvenlik değil, arka kapı (doğrudan Git push'u) kapatılmadıkça o onay bir turnike değil, sadece önerilen bir yol oluyor. Gerçek bir kurulumda bu yüzden branch protection + CODEOWNERS zorunlu, sadece CI job seviyesinde onay yeterli değil.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
Onay adımını atlamak için prod overlay dosyasına doğrudan, pipeline'ı hiç kullanmadan bir commit push ettik (registry'de var olmayan uydurma bir tag'e işaret edecek şekilde). ArgoCD bu değişikliği normal bir Git değişikliği olarak gördü ve sync etmeye çalıştı, sonuç `ImagePullBackOff` oldu çünkü işaret edilen imaj registry'de hiç yoktu. Asıl önemli olan hata mesajının kendisi değildi, asıl bulgu şuydu: onay mekanizması (GitHub Environment Protection) bu doğrudan push'u HİÇ ENGELLEMEDİ, çünkü o mekanizma sadece CI workflow'unun içindeki bir job'u koruyor, Git'in kendisine yapılan bir push'u değil. Bu, "onay var" demenin, "her yol o onaydan geçiyor" demek olmadığını gösteren gerçek bir güvenlik boşluğuydu, branch protection/CODEOWNERS eksikliği yüzünden ortaya çıktı.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- ArgoCD ApplicationSet resmi dokümantasyonu
- ArgoCD Image Updater resmi dokümantasyonu (tag filtering, allow-tags)
- GitHub Environments/Protection Rules resmi dokümantasyonu
- Kustomize resmi dokümantasyonu (overlay yapısı, `kustomize edit set image`)
