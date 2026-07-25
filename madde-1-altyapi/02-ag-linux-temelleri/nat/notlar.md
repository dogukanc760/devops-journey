# 📝 Notlar

## Neden var?
Senin cihazın IP'si 192.168.1.5, bu PRIVATE IP, internete çıkamaz. Router bunu public IP'ye çevirir. K8s'de de aynı, pod'un IP'si 10.0.2.15, dış dünya bunu bilmez. NAT olmasa podlar internete çıkamaz, dışarıdan da podlara erişemeyiz.

Açılımı Network Address Translation = NAT

3 temel keyword:
SNAT (Source NAT): Giden trafikte kaynak IP'yi değiştirir. Pod 10.0.2.15 internete istek atar, router bunu 203.0.113.1 (herhangi bir public IP) olarak gönderir. K8s tarafında pod dışarı çıkarken node IP'sine göre masquerade edilir.

DNAT (Destination NAT): Gelen trafikte hedef IP'yi değiştirir. Dışarıdan 203.0.113.1:80'e istek gelir, router bunu 10.0.2.15:8080'e yönlendirir. K8s'de LoadBalancer veya NodePort servisi tam bu dıştan gelen trafiği pod IP'sine DNAT eder.

Masquerade (Maskeleme): SNAT'ın dinamik hali, kaynak IP'yi otomatik olarak çıkış interface'inin IP'sine çevirir.

NodePort vs LoadBalancer NAT açısından farkı:
NodePort: iptables DNAT yapar, trafik NodeIP:30080 -> PodIP:8080 çevrilir. Dışarıdan Node'un IP'sini ve portunu bilmen lazım.
LoadBalancer: Önüne external bir LB gelir (MetalLB, CloudLB), LB'nin IP'si -> NodePort -> Pod'a DNAT zinciri kurulur. Yani DNAT iki kez olur: LB IP -> Node IP, sonra NodeIP -> PodIP. LoadBalancer, NodePort'un önüne ekstra bir DNAT katmanı koyar, NodePort hala altta çalışıyor olur.

## Anahtar Kavramlar
- SNAT: Kaynak IP değiştirir, pod'dan dışarıya çıkışta kullanılır. K8s'de Masquerade ile yapılır.
- DNAT: Hedef IP değiştirir, dışarıdan pod'a girişte kullanılır. NodePort ve LoadBalancer bunu yapar.
- Masquerade: SNAT'ın dinamik versiyonu, çıkış interface'inin IP'sini otomatik kullanır. Sabit public IP yoksa bu tercih edilir.
- KUBE-SERVICES chain: K8s'in iptables'a yazdığı DNAT zincirleri burada. `iptables -t nat -L KUBE-SERVICES` ile görülür.
- Double DNAT: LoadBalancer arkasındaki NodePort mimarisinde DNAT iki kez oluyor. Önce LB IP'den Node IP'ye, sonra Node IP'den Pod IP'ye.

## Kendi Notum
Agam şimdi şöyle, sen bir ürün sipariş ettin internetten. Satıcı senin dış adres bilgilerini aldı ve kargo firmasına adres bilgileriyle birlikte paketi verdi. Kargo firması senin adresini teyit etti ve sana doğru paketle birlikte yola çıktı. Daha sonra senin oturduğun sitenin güvenlik birimine paketi bıraktı ama hala daire kaçta olduğunu, hangi blokta vs olduğunu bilmiyor. Daha sonra güvenlik görevlisi kargocudan paketi alıp, senin bloğundaki senin dairene getirdi ve güvenle teslim etti. Aynı şekilde tam tersi bir durumda sen evinden bir kargo gönderirken paketi güvenliğe verdin ve güvenlikte kargo firmasına adres bilgileriyle paketi teslim etti. İşte bu NAT ve alt keyword'lerine (SNAT, DNAT ve Masquerade) bir örnektir.

Kargonun evine gelme süreci DNAT yani Destination NAT'tir ve LoadBalancer + NodePort ile senin infraya dışarıdan bir isteğin erişebilmesi durumudur. İsteği yapan kişi senin adresini biliyor ve paket gönderiyor ancak site girişindeki güvenlik ise DNAT'tir, yani dışarıdan gelen isteği içeride sadece kendi bildiğimiz private (local) IP'ye götürüyor ve istek karşılık buluyor.

Evden kargo gönderme ise DNAT'in tersi SNAT'tir. Güvenlik ise Masquerade oluyor, yani aradaki maskeleme işini yapan birim.

Eğer direkt apartman dairesinde oturuyorsan ve kargoyu kargocudan alıp bize götüren güvenlik olmasaydı, bu aslında NodePort'a direkt örnekti, yani üstünde çalışan bir LB yapısı yok, ekstra DNAT yok. Direkt iptables kurallarına göre erişilebilir veya erişemez durumuna bakılıyor.

## Karşılaştığım Hatalar
Mac'te `sudo pfctl -s nat` ile NAT kurallarını görmek istedim ama pfctl MacOS'ta farklı çalışıyor ve k3d tüneli farklı bir mekanizma kullanıyor. Gerçek Linux'ta `sudo iptables -t nat -L -n -v` gerekiyor, k3d node içinde de izin kısıtları var.

Ayrıca K8s DNAT zincirini takip ederken KUBE-SERVICES -> KUBE-SVC-xxx -> KUBE-SEP-xxx akışını kavramak biraz zaman aldı. KUBE-SEP = Service End Point, yani gerçek pod IP'si orada.

## Kaynaklar
- iptables NAT referansı: https://www.netfilter.org/documentation/
- K8s Service ağ detayları: https://kubernetes.io/docs/concepts/services-networking/service/
- Linux Advanced Routing: https://lartc.org/
