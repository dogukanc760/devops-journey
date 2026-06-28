# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
K8s'de her pod birbirini göremez, aynı node'da çalışsalar bile. Bu sihir network namespace sayesinde olur. Her pod'un kendi network stack'i var; kendi IP'si, kendi routing tablosu, kendi iptables kuralları. Namespace olmasa tüm podlar aynı networkü paylaşır, port çakışması olur ve izolasyon olmaz. 

Temel:
Her pod = 1 Network Namespace
Pod içinde ki tüm containerlar aynı namespace'i paylaşır(Bu yüzden localhost ile birbirlerine erişebilirler)
veth pair -> namespace'i localhost networküne bağlayan sanal bir kablodur, bir ucu podda bir ucu hosttadır. 
CNI(Calico, Cilium, Flannel vs...) -> bu veth pairleri otomatik kuran şeydir. 

Örnek kullanım şekilleri:
# Mevcut namespace'leri gör
ip netns list

# Yeni namespace oluştur
sudo ip netns add test-ns

# Namespace içinde komut çalıştır
sudo ip netns exec test-ns ip addr

# veth pair oluştur, namespace'e bağla
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth1 netns test-ns
sudo ip addr add 10.0.0.1/24 dev veth0
sudo ip netns exec test-ns ip addr add 10.0.0.2/24 dev veth1
sudo ip link set veth0 up
sudo ip netns exec test-ns ip link set veth1 up

# Ping at
ping 10.0.0.2
sudo ip netns exec test-ns ping 10.0.0.1

Örnek bir soru:
Soru: Bir pod içinde iki container var — nginx ve sidecar. nginx 80 portunu dinliyor. sidecar nasıl localhost:80'e erişebilir?
Cevap: Çok basit, aynı network namespace i paylaştıkları için, direkt localhost ile sidecar localhost:80 e erişebilir.
Bu K8s'in sidecar pattern'ının temelidir. Istio'nun envoy proxy'si de tam bu şekilde çalışır, her pod'a inject edilen sidecar aynı namespace üzerinden trafiği intercept eder.
## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- 

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Agam düşün ki senle aynı şirketteyiz ama farklı projelerde çalışan 2 backend deviz ve aynı ağ ortamında benzer adreslere istek atıyoruz. Diyelim ki çok edge case ama kendi backendimize bir servisi entegre ediyoruz ve ikimizde aynı ağda olduğumuzdan localhost:1925 e istek atıyoruz fakat ikimizde farklı servislere gitmeyi umuyoruz. Bu noktada o hedef servisle kendi servisimizi (illa ki localhost:1925 ile gidip sidecar olarak çalıstıracaksak tabii ki) aynı pod içerisinde bir sidecar(farklı bir container ) olarak koyuyoruz, otomatikman aynı network namespace i paylaştıkları için kendi servisimiz, kendi hedef servisimize erişebiliyor ve birbirimizden de izole oluyoruz ve kavga dövüş çıkmıyor. Sidecar eklediğimiz örnek bir senaryoda şu,  sidecar genellikle kendi servisine transparent proxy, logging veya auth katmanı eklemek için kullanılır, sadece izolasyon için değil. Istio'nun envoy'u bunun en iyi örneği.

# Ek notlar
Transparent Proxy:
Transparent Proxy (Şeffaf Vekil Sunucu), kullanıcıların veya cihazların varlığından haberdar olmadığı, tarayıcı veya sistem üzerinde hiçbir özel ayar yapılmasına gerek kalmadan trafiği kendiliğinden yakalayıp yönlendiren bir ara sunucudur.

### Sidecar ve Transparent Proxy Neden Birlikte Kullanılır?
Modern bulut sistemlerinde (İstio veya Linkerd gibi Service Mesh yapılarında) her uygulamanın yanına bir sidecar proxy (örneğin Envoy Proxy) yerleştirilir. Bu noktada transparent proxy yönteminin kullanılmasının 4 kritik sebebi vardır:

#### 1. Uygulama Koduna Dokunmamak (Zero-Code Modification)
Eğer transparent proxy kullanılmasaydı, yazdığınız her mikroservisin kodunun içine proxy IP adreslerini ve sertifikalarını gömmeniz gerekirdi. Transparent proxy sayesinde, uygulamanız sanki doğrudan internete veya diğer servise bağlanıyormuş gibi davranır. Trafik ağ seviyesinde (iptables ile) otomatik olarak sidecar proxy'ye yönlendirilir. Yazılımcıların proxy ayarlarıyla uğraşması gerekmez.

#### 2. Güvenlik ve Şifreleme (mTLS)
Uygulamanız şifresiz düz metin (HTTP) olarak konuşsa bile, sidecar transparent proxy bu trafiği yakalar. Diğer servisin önündeki sidecar proxy ile kendi arasında otomatik olarak güvenli ve şifreli bir tünel (mTLS) kurar. Uygulamanın ruhu bile duymadan tüm iç ağ trafiğiniz şifrelenmiş olur.

#### 3. Gelişmiş Trafik Yönetimi ve İzlenebilirlik
Trafik ağ seviyesinde sidecar transparent proxy'ye aktarıldığı için, sistem şunları otomatik olarak yapabilir:Yük Dengeleme: Trafiği arkadaki sağlam servislere dağıtır.Hata Toleransı (Circuit Breaking): Bir servis çöktüğünde trafiği anında keser.Loglama ve Metrik Toplama: Hangi servisin ne kadar sürede yanıt verdiğini uygulamadan bağımsız olarak ölçer.

#### 4. Merkezi Politika Yönetimi
Şirket içinde "A servisi, B servisine bağlanamasın" gibi güvenlik kurallarını tek bir merkezden değiştirebilirsiniz. Transparent proxy bu kuralları ağ seviyesinde hemen uygular; servisleri tek tek yeniden başlatmanız veya kodlarını güncellemeniz gerekmez.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- 
