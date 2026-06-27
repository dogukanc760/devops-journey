# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Fiziksel olarak aynı switche bağlı cihazlar varsayılan olarak birbirini görebilirler. Fabrika örneğinde olduğu gibi (ip-subnettingte geçiyor) tüm çalışanlar aynı kordiroda, birbirinin masasına bakıyor. Vlan olmasa stroage trafiği, mgmt(klasik infrayı yönettiğimiz managementin kısatlmasıdır örn: kubectl komutları...) trafiğini görür, güvenlik açığı + performans kaybı olur. Vlan fiziksel donanımı değiştirmeden mantıksal izolasyon sağlar. Yani her bir grup masada çalışan kişiler için tek tek switch almak yerine bir switchte vlanlar oluşturup mantıksal izolasyon sağlarız virutal olarak ki açılımı zaten Virtual Lan = Vlan dır. Burada 2 temel kavram var, access port ve trunk port. 
Farkı şudur, access port tek vlan gerektiren durumlar içindir, trunk port ise birden fazla Vlan grubu olacağı durumlardadır.
Örneğin, 
Şirkette çalışanların cihazları ile test makinesi aynı switchte ama ben bunların birbirine erişmesini istemiyorum bu sebeple bir access port oluşturup test makinesi ile çalışanları birbirinden ayırabilirim ama 
Bir cluster'ım var ve etcd/storage, mgmt trafiği veya k8s-nodes(namespacelerde ki podlar kendi app imizde olabilir veya CoreDNS gibi temel kube araçları olabilir)
trafiği var ve çok fazla varlık MetalLB aracılığı ile ip alıp iç k8s networkünde var oluyor. Bu çokluğu, tek bir vlanla yönetemeyiz çünkü yine tek bir vlana hapsetmek izolasyonu sağlamaz bu sebeple trunk port yaparız ve her bir gruba bir Vlan grubu atarız örneğin => 
VLAN 10 → mgmt      (10.0.1.0/28)
VLAN 20 → k8s-nodes (10.0.2.0/24)
VLAN 30 → storage   (10.0.3.0/29)
Hem subnet olarak birbirlerinden izole olurlar hemde switchten de ayırdığımız için varsayılan olarak birbirlerini görüp ulaşmaları neredeyse imkansızdır. 
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


NEDEN VAR KISMINDA HEPSİNE CEVAP VERDİM AYRI AYRI BAŞLIGA GİRMİYORUM.