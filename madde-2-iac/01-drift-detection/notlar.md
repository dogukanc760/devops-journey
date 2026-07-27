# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Terraform'a "altyapı şöyle olsun" dediğinde bunu bir state dosyasında tutar(desired state). 
Ama gerçek dünyada bir iconsole'a girip elle bir değişiklik yapabilir, acil bir prod sorununu gece yarısı
manuel çözer mesela. Terraform bundan haberi olmadan bir sonra ki apply'da bu değişikliği fark etmez veya üstüne
yazıp kaybeder. DRift detection, kod(desired state) ile gerçek altyapı(current state) arasında ki bu sessiz
sapmayı görünür kılan mekanizma.

Temel:
- terraform plan her çalıştığında desired state(kod) ile current state'i (gerçek altyapı, provider API'sinden çekilir)
   karşılaştırır
- Drift: State dosyasının bildiği durum ile gerçek altyapının o an olduğu durum arasındaki fark.
- terraform refresh: state dosyasını gerçek altyapıyla senkronize eder, kod değişmez ama state güncellenir.
- Atlantis/Terraform Cloud: PR açılınca otomatik plan çalıştırıp drift'i veya değişikliği gösterir, merge olunca  
  apply    eder.
- Scheduled drift check: cron ile düzenli terraform plan çalıştırıp fark varsa Slack'e bildirim.

    Kod (main.tf) → terraform apply → Gerçek Altyapı + State dosyası
                                            ↓
                                Biri elle değişiklik yapar (drift)
                                            ↓
                                terraform plan → farkı gösterir
                                            ↓
                                terraform apply → koda zorla geri döner

Örnek Soru:
terraform plan drift'i tespit ettiğinde, sana "bu kaynağı eski haline döndüreceğim" der ama bazen drift aslında bilinçli ve doğru bir değişiklik olabilir (örneğin acil bir güvenlik yaması). Bu durumda Terraform'un kodu "yanlış" olan, gerçek altyapıyı "doğru" kabul edip state'i güncellemek istersen ne yaparsın?

Cevap:
Genel prensip (araçtan bağımsız): Drift'i "kabul etmek" demek, .tf kodunu manuel yapılan değişikliğe göre güncelleyip Git'e (hangi Git olursa olsun) push etmek, sonra bu kodu bir plan/apply döngüsünden geçirip state'i gerçeklikle senkronize etmektir. Terraform'un kendisi bu konuda Atlantis mi, Terraform Cloud mu, yoksa senin intranet GitLab pipeline'ın mı çalıştırdığını bilmez — hepsi aynı plan → apply çağrısını farklı bir orkestrasyon katmanından tetikliyor.

Atlantis / Terraform Cloud'da:

.tf dosyasını manuel değişikliğe göre güncelle, PR aç
Atlantis/TFC webhook ile PR'ı yakalar, otomatik terraform plan çalıştırır, sonucu PR'a yorum olarak yazar
Plan'da "0 to change" görürsün çünkü kod zaten gerçek durumla eşleşiyor
PR'ı merge edersin, Atlantis/TFC otomatik apply tetikler (yine no-op ama state resmi olarak senkronize/kayıtlı hale gelir)

 Intranet GitLab çözümünde:

Aynı şekilde .tf dosyasını güncelle, MR aç
GitLab CI pipeline (senin tanımladığın .gitlab-ci.yml job'ı) terraform plan stage'ini tetikler, çıktıyı MR'a yazabilir veya pipeline log'unda gösterir
Aynı şekilde "0 to change" görürsün
MR'ı merge edersin, apply stage'i (manuel onaylı veya otomatik) tetiklenir

Fark sadece şurada: Atlantis/Terraform Cloud bu plan/apply tetikleme, kilitleme (locking) ve PR yorumlama işini senin için hazır bir şekilde yapan bir SaaS/self-hosted araç. Senin GitLab çözümün ise bunu kendi CI pipeline script'inle elle inşa etmiş halin — işlevsel olarak aynı şeyi yapıyor, sadece "kutudan çıkma" özellik seti (otomatik PR yorumu, state locking UI, policy check) yok, onu sen kendi pipeline'ında implement ediyorsun.

İkisinde de temel gerçek değişmiyor: kod = tek doğruluk kaynağı, drift kabul edilirse önce kod güncellenir, sonra plan/apply ile state buna hizalanır.

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
