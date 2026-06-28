# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Senin cihazın IP'si 192.168.1.5, bu PRIVATE IP, internete çıkamaz. Router bunu public IP'ye çevirir. K8s'de de aynı, podun IP'si 10.0.2.15, dış dünya da bunu bilmez. NAT olmasa podlar interenete çıkamz, dışarıdan da podlara erişemeyiz. 

Açılımı Network Address Translation = NAT

Temel:
NAT konusunda karşımıza çıkan 3 temel keyword var,

SNAT(Source NAT) -> giden trafikte kaynak IP'yi değiştirir
Pod 10.0.2.15-> internete istek atar -> router bunu 203.0.113.1(herhangi bir public IP) olarak gönderir
K8s tarafında ise pod dışarı çıkarken node IP'sine göre masquerade edilir.

DNAT(Destination NAT)-> gelen trafikte hedef ip'yi değiştirir.
Dışarıdan 203.0.113.1:80'e istek gelir-> router bunu 10.0.2.15:8080'e yönlendirir.
K8s'de tarafında ise, LoadBalancer veya NodePort service tam bu dıştan gelen trafik pod IP'sine DNAT edilir. 

Masquerade(Maskeleme)-> SNAT'In dinamik halidir, kaynak IP'yi otomatik olarak çıkış interface'inin IP'sine çevirir. 

Örnek NAT işlemleri
# Mac'te NAT kurallarını gör
sudo pfctl -s nat

# Linux'ta (VM veya k3d node içinde)
sudo iptables -t nat -L -n -v

# K8s'de bir servis oluştur, arkasındaki DNAT kuralını bul
kubectl get svc
sudo iptables -t nat -L KUBE-SERVICES -n -v

Örnek bir use-case sorusu: 
Soru: NodePort Service ile LoadBalancer Service'in NAT Açısından farkı nedir?
Cevap: 
Öncelikle, LoadBalancer dışarıdan gelen istekleri/trafiği içeride uygun olan bir node veya app'e yönlendirir, NodePort tarafında bu yoktur, NodePort direkt dışarı açıktır ve şak diye NodePort adresi bildiğimiz bir pod/service'e erişebiliriz. 

NAT tarafında ise

NodePort -> iptables DNAT yapar, trafik NodeIP:30080->PodIP:8080 çevrilir. Dışarıdan Node'un ipsini ve portunu bilmen lazım.

LoadBalancer -> Önüne external bir LB gelir(MetalLB, CloudLB etc...), 
LB'nin IP'si-> NodePort-> Pod'a DNAT zinciri kurulur. 
Yani DNAT iki kez olur: 
LB IP -> Node IP, sonra NodeIP-> PodIP.

Kısacası LoadBalancer, NodePort'unun önüne ekstra bir DNAT katmanı koyar. NodePort hala altta çalısıyor olur. 

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- 

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Agam şimdi şöyle, sen bir ürün sipariş ettin internetten. Satıcı senin dış adres bilgilerini aldı ve kargo firmasına (kargo firması iletişim protokolünü de temsil ediyor olabilir) address bilgileriyle birlikte pakedi verdi. Kargo firması senin adresini teyit etti (tcp handshake örneği :D) ve sana doğru paketle birlikte yola çıktı. Daha sonra senin oturdugun sitenin güvenlik birimine pakedi bıraktı ama hala daire kaçta olduğunu, hangi blokta vs olduğunu bilmiyor. Daha sonra güvenlik görevlisi kargocudan pakedi alıp, senin bloğunda ki senin dairene getirdi ve güvenle teslim etti. AYnı şekilde tam tersi bir durumda sen evinden bir kargo gönderirken, pakedi güvenliğe verdin ve güvenlikte kargo firmasına adress bilgileriyle pakedi teslim etti. İşte bu NAT ve alt keywordlerine (SNAT, DNAT ve Masquerade) bir örnektir. 

Kargonun evine gelme süreci DNAT yani Destination NAT'tir. ve LoadBalancer + NodePort ile senin infrana dışarıdan bir isteğin/sorgunun erişebilime durumudur. Şöyle ki, isteği yapan kişi senin addresini biliyor ve paket gönderiyor ancak site girişinde ki güvenlik ise DNAT'tir yani dışarıdan gelen isteği içeride sadece kendi bildiğimiz private(local) ip'ye götürüyor(çeviriyor) ve istek karşılık buluyor.

Evden kargo gönderme ise DNAT'in tersi yani SNAT'tir, yani Source NAT. Sen dışarıya çıkmadan kendi private(local) ip'inden sitenin güvenliğinde (aslında güvenlik masquerade işlemini yapan birim oluyor bu noktada) paket ve address ile birlikte veriyorsun, o da gidip kargo firmasına iletiyor yani dış IP de gitmek istediğin yere.

Güvenlik ise Masquerade(External LB, MetalLB veya CloudLB gibi) oluyor, yani arada ki maskeleme işini yapan birim.

Şöyle bir nokta da var eğer direkt site de oturmayıp normal bir apartman dairesinde olsaydık ve kargoyu, kargocudan alıp bize götüren veya tam tersi kargoyu bizden alıp kargocuya teslim eden güvenlik olmasaydı bu aslında NodePorta direkt örnekti, yani üstünde çalışan bir LB yapısı yok, ekstra DNAT yok. Direkt iptables rules larına göre erişilebilir veya erişemez kurallarına bakıp erişebiliyorsa pakedi içeride biz alıyoruz (zili basıyor ve kapıyı açıyoruz) mantığı oluyor e haliyle tabi yukarıda yazdıgım gibi Ip ve portu direkt net olarak bilmesi gerekiyor.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- 
