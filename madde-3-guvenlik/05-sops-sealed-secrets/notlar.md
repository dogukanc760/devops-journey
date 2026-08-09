# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Vault ile pod çalışırken dinamik sırları çözdük ama bir sorun daha var: Terraform/K8s manifest'lerini Git'e commit ederken sırları nereye koyacaksın? Sırrı düz metin yazarsan Git history'ye sonsuza kadar girer, silsen bile geçmiş commit'lerde kalır. Sırrı hiç yazmazsan, IaC'nin "her şey kod içinde, tek kaynaktan izlenebilir" prensibi bozulur, biri manuel bir yerden şifreyi bulup elle girmek zorunda kalır. Bu olmasaydı ne olurdu diye sorarsak, ya git repo'suna sızan biri düz metin sırları direkt okurdu, ya da GitOps akışı (her şey Git'ten deploy edilsin) yarım kalırdı çünkü sırlar Git dışında bir yerde saklanıp elle enjekte edilmek zorunda kalırdı.

Temel:

- SOPS (Secrets OPerationS): bir dosyanın (YAML/JSON/env) sadece value'larını şifreleyip key'leri düz bırakan bir araç, şifreli haliyle Git'e commit edilebilir
- Sealed Secrets (Bitnami): K8s'e özel bir CRD, cluster'ın private key'iyle şifrelenmiş bir SealedSecret objesi Git'e commit edilir, cluster içindeki bir controller bunu çözüp normal Secret'a çevirir
- Asimetrik şifreleme mantığı: şifrelemek için public key yeterli (herkes şifreleyebilir), çözmek için sadece private key'e sahip olan yetkilidir
- GitOps uyumluluğu: hem SOPS hem Sealed Secrets, "her şey Git'te, şifreli ama izlenebilir" prensibini bozmadan sırrı da versiyon kontrolüne sokar
- Vault'tan farkı: Vault çalışma zamanında (runtime) dinamik sır üretir/sağlar, SOPS/Sealed Secrets ise Git'e commit edilecek statik bir sırrı güvenli hale getirir, ikisi farklı problemi çözer

Örnek Soru:
Bir takım arkadaşın diyor ki: "Zaten Vault kullanıyoruz, neden SOPS veya Sealed Secrets'a da ihtiyacımız var, hepsini Vault'ta tutsak olmaz mı?" Buna ne cevap verirsin? Ayrıca SOPS ile Sealed Secrets arasında, ikisi de "şifreli sırrı Git'e koy" dese de, nerede/nasıl şifre çözüldüğü açısından temel bir fark var, bu fark ne, ve bu fark hangi senaryoda hangisini tercih edeceğini nasıl etkiler?

Cevap:
Sadece Vault yetmez, çünkü bootstrapping (tavuk-yumurta) problemi var: Vault'un kendisini ayağa kaldırmak için bile bazı sırlara ihtiyaç olur, örneğin Terraform'un Vault'u barındıracak altyapıyı kurabilmesi için cloud credential'ları, ya da Ansible'ın makineleri configure edebilmesi için SSH key/ilk DB root şifresi, henüz Vault diye bir şey ayakta bile değilken lazım. Vault'un kendi unseal key'lerini yine Vault'ta saklayamazsın. Ayrıca Terraform/Ansible review süreci (plan, diff) sırasında her seferinde canlı bir Vault bağlantısına ihtiyaç duymak, Vault çökerse tüm IaC akışını kilitler, SOPS bu bağımlılığı kaldırır çünkü şifreli değer zaten repo'nun içinde, sadece apply anında bir key (age/PGP/KMS) gerekir.

SOPS ile Sealed Secrets'ın temel farkı, şifrenin NEREDE çözüldüğü. Sealed Secrets, K8s'e özel bir CRD. Şifreleme cluster controller'ının public key'iyle yapılır (asimetrik), herkes şifreleyebilir. Ama şifre çözme SADECE o cluster'ın içindeki controller'da olur, çünkü private key sadece orada var. Bir SealedSecret manifestini başka bir cluster'a apply etsen çözülemez, sıkı bir cluster-bağımlı güven sınırı var. SOPS ise K8s'e özel değil, genel amaçlı bir dosya şifreleme aracı, farklı key backend'leri (PGP/age/KMS) destekler. Şifre çözme, key'e erişimi olan HERHANGİ bir yerde yapılabilir (laptop, CI pipeline, Ansible controller), sadece K8s değil. Bu da SOPS'u runtime dışı, Terraform/Ansible bootstrap senaryoları için esnek yapar. Seçim kriteri: sır sadece K8s Secret olarak kullanılacaksa ve "sadece bu cluster çözebilsin" garantisi isteniyorsa Sealed Secrets; sır K8s dışında da (Terraform, Ansible, CI/CD env dosyaları) kullanılacaksa veya birden fazla cluster/ortam aynı key'i paylaşacaksa SOPS.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- SOPS, sadece bir dosyanın value'larını şifreler, key'ler (alan adları) düz kalır, bu sayede şifreli dosya bile git diff'te "hangi alan değişti" diye okunabilir kalır.
- age, PGP'ye göre çok daha basit bir asimetrik şifreleme aracı, `age-keygen` ile public/private key çifti üretilir, SOPS bu key ile çalışabilir.
- SOPS_AGE_KEY_FILE ortam değişkeni, decrypt sırasında hangi private key dosyasının kullanılacağını SOPS'a söyler, elle key belirtmeye gerek kalmaz.
- Sealed Secrets, K8s'e özel bir CRD (SealedSecret), controller cluster içinde kendi private/public key çiftini üretir, kubeseal CLI bu public key'i cluster'dan otomatik çekip şifreler.
- SealedSecret bir cluster'a apply edildiğinde controller onu otomatik olarak normal bir K8s Secret'a çevirir, uygulama tarafında hiçbir ekstra kod gerekmez.
- Sealed Secrets'ın güven sınırı cluster'a kilitlidir: private key sadece o cluster'ın controller'ında yaşar, aynı SealedSecret başka bir cluster'da (ya da yeniden kurulmuş aynı cluster'da, çünkü private key de sıfırlanır) asla çözülemez.
- SOPS'un güven sınırı ise key backend'ine (age dosyası, PGP, ya da bulut KMS) bağlıdır, K8s'e bağımlı değildir, bu yüzden Terraform/Ansible gibi K8s dışı IaC akışlarında ve Vault bootstrap öncesi senaryolarda kullanılır.
- Bulut KMS (AWS KMS, GCP KMS, Azure Key Vault), SOPS'un entegre olabildiği merkezi bir şifreleme servisidir, kimin şifre çözebileceğini IAM policy ile kontrol eder. Bu, Windows'un lisans aktivasyonu için kullandığı "KMS" (Key Management Service) ile sadece isim benzerliği taşır, ikisi tamamen farklı teknolojilerdir.
- CI pipeline'da SOPS decrypt: mantık lokal decrypt ile birebir aynı, tek fark private key'in CI'nin kendi secret store'undan (GitHub Actions secrets, GitLab CI variables) bir ortam değişkenine enjekte edilmesi. Decrypt edilmiş dosya asla kalıcı olarak diskte/repo'da bırakılmaz.
- ArgoCD + GitOps zinciri: Git'e commit/push edilen bir SealedSecret'i insan hiç `kubectl apply` çalıştırmadan ArgoCD otomatik olarak algılayıp cluster'a uygular, Sealed Secrets controller da onu gerçek bir Secret'a çevirir. "Her şey Git'ten deploy edilsin" prensibinin secret'lar için de geçerli olduğunun somut hali.
- Terraform + SOPS: Terraform düz metin bir tfvars dosyası bekler, SOPS'un şifreli formatını doğrudan okuyamaz. Bu yüzden şifreli hali Git'e commit edilir, `terraform apply`'dan hemen önce decrypt edilip düz dosya üretilir, apply bitince düz dosya diskten silinir, kalıcı olarak bırakılmaz.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Diyelim ki bizim sadece spesifik bir K8s cluster'ı içinde, o cluster'ın controller'ında çözülecek şifrelenmiş bir verimiz var (yaml, json, env, fark etmez). Bu sadece burada çözülecekse Sealed Secrets kullanıyoruz, K8s'e özel bir CRD. Bir cluster'ın controller'ına bağlı şifrelenmiş herhangi bir şeyi başkası çözemez, çünkü o private key sadece orada var.

Fakat diyelim ki makinede Vault bile yok, çözülecek yapı K8s'deki spesifik bir cluster-controller'a ait değil, herhangi bir yerde şifreleme yapmak lazım bir dosya veya secret için, yani runtime dışı, Terraform/Ansible tandemi ayağa kalkarken veya Vault'u kurarken bile (mesela bulut hesap key'leri gerekiyorsa) bu noktada SOPS kullanılır, çünkü şifre çözme yetkisi tek bir cluster'a değil, key'e sahip olan herkese bağlı. Kontrol istiyorsan da bir bulut KMS (AWS KMS, GCP KMS, Azure Key Vault) kurup erişimi IAM policy ile yönetirsin, kimin çözebileceğini oradan kısarsın.

Kısacası: "sadece bu cluster çözebilsin" istiyorsan Sealed Secrets, "K8s'ten bağımsız, ihtiyaç anında herhangi bir yerde çözülsün ama erişimi ben kontrol edeyim" istiyorsan SOPS + KMS.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
Bu konuda "hata" değil, tam beklediğimiz bir "boz" senaryosu gerçekleşti. Bir SealedSecret'i (sealed-secrets-cluster üzerinde üretilmiş) sildiğimiz cluster'ın yerine kurulan yeni bir cluster'a (sealed-secrets-cluster-2, kendi yeni private key'ini üretmiş) apply ettik. Sonuç: `kubectl apply` SealedSecret objesini kabul etti (sealedsecret.bitnami.com/db-secret created), ama gerçek Secret hiç oluşmadı (`Error from server (NotFound): secrets "db-secret" not found`). Controller loglarında net sebep vardı: `Failed to unseal: no key could decrypt secret (password)`, birkaç retry sonrası `Error updating, giving up`. Yeni cluster'ın private key'i eskisiyle eşleşmediği için şifre asla çözülemedi. Bu, Sealed Secrets'ın "sadece üretildiği cluster çözebilir" garantisinin somut kanıtıydı, sistemin bozulması değil, tam da tasarlandığı gibi çalışması.
## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- Mozilla SOPS resmi GitHub dokümantasyonu (age/PGP/KMS entegrasyonları)
- Bitnami Sealed Secrets resmi GitHub dokümantasyonu (kubeseal, controller mimarisi)
