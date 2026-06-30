# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
K8s de podlar ölür, başka node da yeniden doğar. Pod'un yazdığı veri o node'un diskinde kalırsa, pod başka node'a geçince veri kaybolur. Distrubuted Storage veriyi birden fazla node'a replike eder, hangi node ölse veri kaybolmaz. 

Örnek sorular:
Soru: Replication Factor 3 Ne demektir?
Cevap: Replication Factor 3 (3'lü çoğaltma faktörü), dağıtık sistemlerde(Apache Kafka, Hadoop, MongoDB vs...)
veri kaybını önlemek için her bir veri parçasının(partition veya shard) sistem üzerinde tam 3 farklı kopyasının tutulması anlamına gelir.
3 tercih edilmesinin sebeplerinin başında Yüksek Hata Toleransı gelir, örneğin sistemde ki 2 sunucu (broker yada node) aynı anda çökse dahi verileriniz kaybolmaz ve sistem çalışmaya devam eder.
Diğer bir sebebi ise Güvenlik ve Performans Dengesi, veri bütünlüğü(durability) korumakla birlikte, depolama maliyetini (storage overhead) aşırıya kaçmadan ideal bir denge sağlar.
Çalışma prensibi de şöyledir, 3 kopyadan biri lider olarak atanır ve tüm okuma/yazma işlemlerini karşılar. Diğer 2 kopya ise (Follower/Replica) olur ve pasif olarak lideri dinleyip veriyi eşitlerler.
Lider sunucu çökse dahi, sistemde ki yedek kopyalardan biri anında yeni lider olarak atanır/seçilir ve kesintisiz çalışmaya devam eder.
Sıkıntılı kısımlarıda şöyle, depolama maliyeti fazladır çünkü fazladan %200 depolama alanına gerek duyulur. 
Bir diğer sıkıntılı durumda şöyle, sunucular araısnda ki senkronizasyon(replication) ağı daha fazla meşgul edebilir.

Soru: 5 node'lu cluster'da 2 disk aynı anda çökerse ne olur?
Cevap: 5 Node'lu bir clusterda 2 disk aynı anda çökerse veriye hiç bir şey olmaz ve sistem kesintisiz çalışmaya devam eder.
Replication Factor 3 yapıda ki sisteiniz, herhangi bir veri parçasının 2 kopyasını birden kaybetse bile kalan son 1 kopya üzerinden ayakta kalır. 
Eğer diskler aynı sunuculardaysa, her bir veri parçasının(partition/shard) en az 2 kopyası hala sapasağlamdır bu sebeple sistem tamamen kayıpsız ve yüksek performansla çalısmaya devam eder. Arka planda çöken disklerded ki verileri kalan 3 sağlam sunucuya otomatik olarak yeniden kopyalamaya (re-replication) başlar. 
Bir de disklerin ayın verinin kopyalarını barındırdığı durum var bu biraz kritik bir senaryo o da şöyle,
Çöken 2 disk, tesadüfen aynı verinin(örneğin x Partitionun) Lider ve 1. yedek kopyalarını taşıyor olabilir, buna göre sonuçta o veri parçasından geriye tüm clusterda sadece 1 adet sağlam kopya(2. yedek) kalmıştır. 
Bu durumda da sistem hemen o kalan son kopyayı Leader ilan eder. Okuma ve yazma talepleri bu sunucu üzerinden akmaya devam eder; kullanıcı hiç bir kesinti hisstemez. Ancak sistem "kritik" duruma geçer çünkü artık o veri parçası için hata toleransı sıfıra inmiştir.  
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
