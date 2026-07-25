# 📝 Notlar

## Neden var?
K8s'de podlar ölür, başka node'da yeniden doğar. Pod'un yazdığı veri o node'un diskinde kalırsa, pod başka node'a geçince veri kaybolur. Distributed Storage veriyi birden fazla node'a replike eder, hangi node ölse veri kaybolmaz.

Replication Factor 3 ne demektir?
Her bir veri parçasının sistem üzerinde 3 farklı kopyasının tutulması. 3 tercih edilmesinin sebebi hem yüksek hata toleransı (2 node aynı anda çökse veri kaybolmaz) hem de maliyet/güvenlik dengesi. 3 kopyadan biri lider olarak atanır, diğer 2 kopya follower olarak liderden veriyi eşitler. Lider çökünce follower'lardan biri lider seçilir.

5 node'lu cluster'da 2 disk aynı anda çökerse ne olur?
Replication Factor 3 yapıda her veri parçasının en az 2 kopyası hala sağlam kaldığı için sistem kesintisiz çalışır. Arka planda çöken disklerdeki verileri kalan sağlam node'lara re-replication ile kopyalamaya başlar. Kritik senaryo: eğer çöken 2 disk aynı verinin lider ve ilk follower'ını taşıyorsa, o veri için sadece 1 kopya kalır. Sistem o kopyayı lider ilan eder ama hata toleransı sıfıra iner, risk artar.

## Anahtar Kavramlar
- Replication Factor: Verinin kaç farklı node'a kopyalanacağı. 3 en yaygın değer, 2 node arıza toleransı sağlar.
- Erasure Coding: Replication'ın alternatifi. Daha az disk alanı kullanır ama hesaplama maliyeti var. Ceph destekler.
- Leader/Follower: Dağıtık sistemlerde yazan tek lider, okuyan/sync olan follower'lar. Lider düşünce follower seçilir.
- Re-replication: Bir node veya disk kaybedilince, mevcut kopyalardan yenisi oluşturulur. Arka planda otomatik.
- Split Brain: İki taraf da kendini lider sanıyor, tutarsız veri yazılıyor. Quorum (çoğunluk) kararı bu yüzden şart.

## Kendi Notum
Şöyle anlatırdım: diyelim önemli bir dökümanın tek kopyası bir bilgisayarda. Bilgisayar bozuldu, döküman gitti. 3 farklı yere kaydetseydin, 2 tanesi bozulsa bile bir tanesi kalırdı. Distributed storage tam bunu yapıyor ama bunu otomatik ve şeffaf olarak, sen sadece "yazdım" diyorsun, sistem arka planda 3 farklı node'a yazıyor. Pod'un bunu bilmesine gerek yok.

K8s'de neden kritik: podlar ölüp başka node'da yeniden doğuyor. Eğer veriyi sadece local diske yazdıysan pod başka node'a geçtiğinde veri kayboldu. Distributed storage bu problemi çözüyor, veri cluster'a ait, hangi node'dan erişirsen eriş aynı veriyi görürsün.

## Karşılaştığım Hatalar
Bu konu tamamen teorik geçti, fiziksel lab ortamı olmadığı için distributed storage'ı gerçekten kuramadık. Rook-Ceph ve Longhorn pratikleri k3d'de kernel kısıtları yüzünden çalışmadı, bare-metal lab'a ertelendi.

## Kaynaklar
- Distributed systems primer: https://book.mixu.net/distsys/
- Ceph mimari: https://docs.ceph.com/en/latest/architecture/
- CAP theorem: https://en.wikipedia.org/wiki/CAP_theorem
