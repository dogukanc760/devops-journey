# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Normal pdoalr ölüp yeniden doğunca kimliği değişir, yeni IP, yeni isim, yeni disk. VEritabanı için bu felaket. PostgreSQL replicası "ben kimim, hangi verileri saklıyorum?" bilemez. StatefulSet podlara kalıcı kimlik kartı verir. Sabit isim, sabit disk, sabit sıra.

Temel: 
Deployment  → pod-abc123, pod-xyz789  (rastgele isim, ölünce değişir)
StatefulSet → pod-0, pod-1, pod-2    (sıralı, sabit isim, hep aynı)

- Her podun sabit DNS adı var: pod-0.service.namespace.svc.cluster.local
- Her podun kendi PVC'si var, pod-0 ölüp yeniden doğsa bile aynı diske bağlanır.
- Podlar sırayla başlar: pod-0 Running olmadan pod-1 başlamaz
- Scale Down da tersten gider: pod-2 önce silinir, sonra pod-1 

Örnek soru:
Neden PostgreSQL primar/replica için Deployment değil Statefulset kullanılır?
Primary Pod ölüp yeniden doğsa ne olur deploymentta? 
Cevap:
StatefulSet kullanılmasının sebebi Neden Var da anlattıgın gibi kalıcı disk ve kalıcı isim içindir aksi halde hem veriler gider hemde her seferinde bu db ye erişen applerimizde isim düzenlemes iyapmak gerekebilirdi bağlantı şeklimize göre tabii bu 
Primary pod ölürse bildiğim kadarıyla durumlar şöyle, bağlantı istekleri veya gelen giden diğer istekler primary dışında ki Secondaryr podlara iletilir Primary ayağa kalkınca tekrar primaryden süreç akmaya devam eder. Yada Primary pod ölür, secondary podlardan biri onun yerine primary olur anında ve Desired state'e uyması için current state in yeni bir secondary pod ayağa kalkar ve pod sayısı da tamamlanmış olur ve zero downtime iddiası devam eder.
Deployment'ta Primary ölünce yeni pod farklı bir PVC'ye bağlanır  ya da PVC hiç yoksa disk verisi tamamen kaybolur. StatefulSet'te pod-0 her zaman kendi PVC'sine döner, veri korunur.

## Anahtar Kavramlar
- Deployment: pod-abc123 rastgele isim, ölünce değişir, disk kaybolabilir
- StatefulSet: pod-0, pod-1 sabit isim, her pod kendi PVC'sine sahip
- Pod'lar sırayla başlar: pod-0 Running olmadan pod-1 başlamaz
- Scale down tersten gider: pod-2 önce silinir

## Kendi Notum
PostgreSQL için StatefulSet kullanılır çünkü Primary pod ölüp yeniden 
doğsa bile aynı diske (PVC) bağlanır, veri kaybolmaz. Deployment'ta 
kullanılsa yeni pod farklı PVC'ye bağlanır veya disk hiç olmaz, veri gider.

Primary pod ölünce iki senaryo:
1. Geçici ölüm → Secondary'ler okuma alır, Primary geri gelir, sync olur
2. Kalıcı ölüm → Secondary'den biri yeni Primary seçilir (failover), 
   controller-manager yeni replica açar, desired state korunur, zero downtime
## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- 
