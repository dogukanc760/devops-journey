# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Ansible ile çalışan bir sunucuda hata çıktığında klasik yaklaşım içine SSH ile girip elle yamalamaktır(patch).
Ama bunu yıllarca yapa yapa sunucu artık kisme tam olarak ne olduğunu bilmeyen, üstüne üstüne yama yapılmış bir 
"kar topu" haline gelir. Bir gün neden çalıştığını kimse açıklayamaz (configuration driftin en kötü hali, snowflake server denir). Immutable Infrastructe bunun tam tersini yapıyor; sunucuya hiç dokunmuyorsun, sorun çıkınca onu tamamen öldürüp Terraform ile sıfırdan, önceden tanımlanmış "doğru" haliyle yeniden ayağa kaldırıyorsun. 

Temel:
- Mutable: Sunucu zamanla üstüne yama yapılarak değişiyor (Ansible playbook tekrar tekrar çalıştırılıyor)
  Immutable: Sunucu hiç değişmiyor, değişiklik gerekiyorsa yenisi kuruluyor eskisi siliniyor.
- Packer: Önceden hazırlanmış, tüm gerekli paketleri/config'i içeren bir "Golden Image"(VM image veya container image)
  oluşturan araç. Terraform bu image'dan VM açar.
- Pet vs Cattle:
   Pet(Evcil hayvan) = Tek, özel ismi var, hastalanınca tedavi edilir.
   Cattle(Sığır) = Sürü halinde, numaralı, hastalanınca değiştirilir. Sunucular cattle olmalı
- Blue-Green deployment: Yeni sürüm(Green) paralel ayağa kalkar, sağlıklı olduğu doğrulanınca trafik Blue'dan
  Green'e kaydırılır, sonra Blue silinir. Kesintisiz geçiş.
- terraform taint (eski) / terraform apply -replace(yeni): Bir resource'u "bozuk" işaretleyip bir sonraki    
  apply'da zorla yok edip yeniden oluşturmasını sağlar.

  Sorun tespit edilir (sunucu bozuk/güncel değil)
        ↓
    terraform apply -replace="aws_instance.web"
            ↓
    Eski sunucu silinir → Packer image'dan yeni sunucu açılır
            ↓
    Birkaç saniye/dakika içinde "doğru" sunucu hazır   

Örnek Soru:
Blue-Green deployment'ta yeni sürüm (Green) ayağa kalkarken hâlâ eski sürüm (Blue) de çalışıyor, yani bir an için iki farklı sürüm aynı anda prod'da. Bu durumda eğer uygulaman bir veritabanına bağlıysa ve yeni sürüm veritabanı şemasında bir değişiklik gerektiriyorsa (örneğin yeni bir kolon), bu geçişi nasıl güvenli yaparsın?
Cevap: 
Bu problemin çözümü expand/contract pattern (parallel change) denen bir tekniktir. Blue-Green'de uygulama kodu anlık geçiş yapabilir ama veritabanı şeması öyle değil, ikisi paylaşımlı bir kaynak, o yüzden şema değişikliğini kendi içinde adımlara bölmen gerekiyor:

1. Expand (genişlet) — Blue hâlâ tek başına çalışırken:
Yeni kolonu ekle ama eski kolonu silme, ikisini birden tut. Örneğin email kolonunu email_address olarak yeniden adlandırmak istiyorsan, önce email_address kolonunu ekle, email'i silme. Bu değişiklik hem Blue (eski kod) hem Green (yeni kod) ile uyumlu olmalı  Blue eski email kolonunu kullanmaya devam eder, yeni kolon onun umurunda değil.

2. Migrate (taşı):
Mevcut veriyi eski kolondan yeni kolona kopyala (background job veya migration script). Bu sırada ideal olarak hem yazma işlemi ikisine de yapılır (dual write) ki Blue hâlâ eski kolona yazarken veri kaybı olmasın.

3. Green'i ayağa kaldır ve trafiği kaydır:
Green artık yeni email_address kolonunu kullanıyor. Trafik Blue'dan Green'e kayınca, artık kimse eski kolona yazmıyor.

4. Contract (daralt) — Blue tamamen silindikten sonra:
Artık eski email kolonuna ihtiyaç kalmadı, ayrı bir migration ile onu temizle.

Kısacası: Şema değişikliğini "kod deploy'u" ile aynı anda yapmıyorsun. Önce şemayı her iki sürümle de uyumlu hale getiriyorsun (genişletme), sonra kod geçişini yapıyorsun (Blue→Green), en son eski şema kalıntısını temizliyorsun (daraltma). Bu üç adım ayrı ayrı, güvenli sırayla yapılıyor asla tek adımda "yeni sürüm + yeni şema" birlikte deploy edilmiyor, çünkü o an ikisi de prod'da aynı anda çalışıyor olabilir.
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
