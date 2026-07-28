# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Terraform state dosyası varsayılan olarak local'de (terraform.tfstate) tutulur. Ekip halinde çalışırken bu ölümcül bir problem: iki mühendis aynı anda terraform apply çalıştırırsa, ikisi de kendi local state'ine göre hareket eder, birbirlerinin değişikliklerini görmez, sonunda state dosyaları çakışır ve altyapı tutarsız hale gelir (ya da biri diğerinin yaptığı kaynağı siler). State'i S3 uyumlu bir remote storage'da (MinIO gibi on-premise) ve lock mekanizmasıyla tutmak bu çakışmayı engelliyor.

Temel:

Remote backend: State dosyası artık local'de değil, merkezi bir yerde (S3, MinIO, Terraform Cloud) tutuluyor. Herkes aynı state'e bakıyor.
State locking: Biri apply çalıştırırken state kilitlenir, o sırada başka biri apply çalıştırmaya çalışırsa "state locked" hatası alır, beklemek zorunda kalır. AWS'de bu DynamoDB tablosuyla yapılır, MinIO'da da benzer bir lock mekanizması kurulabilir.
State encryption: State dosyası bazen hassas veri içerir (örneğin bir DB şifresi resource attribute'u olarak state'e yazılmış olabilir). Remote backend'de encryption at rest şart.
Workspace: Aynı Terraform kodunu farklı ortamlar (dev/staging/prod) için farklı state dosyalarıyla çalıştırma. terraform workspace new prod gibi. Aynı kod, farklı state, farklı gerçek altyapı.

Mühendis A: terraform apply → state'i kilitler → değişikliği yapar → kilidi açar
Mühendis B (aynı anda): terraform apply → "Error: state is locked" → bekler

Örnek Soru: 
 State dosyası hassas veri içerebiliyor dedik (DB şifresi gibi). Diyelim ki state'i MinIO'da tutuyorsun ama encryption kurmadın ve MinIO bucket'ına erişimi olan biri (belki başka bir takımdan bir DevOps mühendisi) bu state dosyasını okuyabiliyor. Bu ne gibi bir güvenlik riski yaratır, ve state içindeki hassas veriyi en baştan state'e hiç yazdırmamak için Terraform'da ne yapabilirsin?

Cevap:
Vault (dinamik/kısa ömürlü secret) + state encryption at rest + state'e erişimi least-privilege ile kısıtlamak. Vault tek başına yeterli değil, state'i de "hassas dosya" gibi korumak şart.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- 

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- 
