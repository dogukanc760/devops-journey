# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
HA-Cluster High-Availability yaklasımı herhangi bir olası node'un çökme durumunda
bütün varlığı tek bir node'a saklayıp bütün sistemin erişilmez hale gelmesindense
Tek sayılı miktarda node oluşturup, bir node çökse dahi erişimin devam etmesini sağlar. 
## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- HA, HA-Cluster, k3d komutları 
 ### 1. servers: 3 yazdın — neden 2 değil 3? etcd quorum açısından açıkla.
- etcd quorum, manifestte server kısmına 3 yazdım, neden 2 değilde 3? tek sayının amacı brain spliti önlemek. Raft algoritması, leader seçimi için majority(çoğunluk) ister 2 node'dan biri ölünce 1/2=%50 yani çoğunluk yok ve seçim yapamaz, cluster donar ama 3 node'dan biri ölünce 2/3 = çoğunluk var => seçim yapılır ve cluster devam eder. Tek sayı bunun için algoritmanın yetersizliği değil, bir matematiksel zorunluluktur. 
 ### 2. --tls-san=127.0.0.1 ne işe yarıyor, neden ekledin?
- TLS-SAN( Subject Alternative Name) cert'e "bu IP'de benim" dedirtiyor. Olmasaydı kubectl 127.0.0.1 e bağlanırken, "hostname does not match certificate" hatası verirdi.

### 3. agents: 2 olan worker node'lardan biri çökerse ne olur? Pod'lar otomatik taşınır mı, neye bağlı?
- kube-controller-manager halleder bunu, Bir node not-ready olunca controller-manager fark eder, podları o node'dan siler ve scheduler baska node'a yeniden planlar. Load-balancer sadece dış trafiği yönlendirir, pod-scheduling ile bir ilgisi yoktur. 

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Şöyle anlatırdım, diyelim ki bir e-ticaret uygulaman var,
ve çok yoğun bir kampanya dönemine giriyorsun ve tek bir erişim dahi para demek,
ancak infra seviyesinde bu yoğunluk çökmelere yol açabilir,
etcd kitlenebilir, network/proxy veya controller-manager gerekli taskları yerine getiremez,
bu sebeple birden fazla node ayağa kaldırıyoruz ve sistemi tek bir noktada değil,
bir çok noktada kendi inframızda/intranetimizde dağıtıyoruz. 
Bu sebeple bir node cortlasa bile geride sağ kalan node her zaman olacağından erişim hiç kesilmez ve şirketimiz para kaybetmez.
## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
Çok hard task değildi bir hata ile karşılaşmadım
## Kaynaklar
<!-- Faydalı bulduğun linkler -->
orbstack + k3d bağlamını ilk kez kullandıgım için Google'da araştırdım
örnek Ha-cluster yaml içeriği + komutlarını ve bu 2 toolun nasıl kurulduğuna baktım ve o şekilde gerçekleştirdim. 
- 
