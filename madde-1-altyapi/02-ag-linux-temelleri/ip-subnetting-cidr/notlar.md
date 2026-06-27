# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
K8S Clusterında her node, her servis ayrı bir IP alır. Bunları rastgele dağıtamayız, mgmt trafiği, storage trafiği, uygulama trafiği bunların hepsi birbirinden izole olmalıdır. CIDR bilmeden ne MetalLB ayarlarsın ne de iptables kuralı yazarsın. 

### Temel
1.0.0.0/24 -> /24 prefix lenght demektir, ilk 24 bit network, son 8 bit hosttur.
 - Subnet mask: 255.255.255.0
 - Kullanılabilir host: 2⁸ - 2 = 254 (network + broadcast çıkar)
 - Host aralığı: 10.0.0.1 - 10.0.0.254 olur
 - /16 -> 65534 host, /28 -> 14 host 

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- IP Subnetting, CIDR, Prefix, ipcalc toolsu. 
kısaca bunlar her pod, her node veya her bir ip alabilen kubernetes öğesi için birbirinden farklı izolasyon (örn: storage/etcd subneti ayrı, node subneti ayrı, mgmt subnet ayrı) durumu yaratmak için kullanıyoruz. Bunları bilmeden MetalLB veya iptables rules yapamayız çünkü gelen giden bütün trafik hem makinede hemde kubernetes içinde ayarladıgımız subnet kurallarıyla ölçülür, makinenin trafiği ayrı kubernetesin kendi iç trafiği ayrıdır ve aslınd abunlarda birer subnet örneği olabilir çünkü birbirinden izoledirler. 

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
BAk kanki bu subnetting ve cidr ın amacı şu, diyelim bir fabrikan var ve her bölüm fabrikanın temel taşı ve fabrikayı oluşturuyor ama hepsi birbirinden izole olacak ama kullandıkları yollarda bir noktada aynı olabilir. Bu sebeple hepsinin çalışma alanını birbirinden ayırıp ihtiyaç duyduğu büyüklükte bir çalısma alanı veriyorsun yani birbirinden doğru hacimli alanda izole ediyorsun bu fabrikanın çalısma alanlarını. Işte CIDR/subnetting ikilisi de bu işi yapıyor, k8s üstünden örnekle mgmt trafiğ, storage trafiği veya k8s içinde yer alan kendi applerimizin oluşturdugu trafiği kendi öznelinde tutup birbirinden ayrıştırıyor izole ediyor ama bu şu demek değil "katiyen bunlar birbirine bir noktada gidip ihtiyaç duydugu iç iletişimi kuramaz". Kurabilir ama bunlarında haliyle ayrı yapılandırmaası ve kuralları var. ß

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
ipcalc komutunu çalıstırırken son bloğu yazmayı unutmuşum ipde gözümden de kaçmış ahaha :D yazarken kontrol edin. 
## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- ipcalc docs. 

## Örnek bir case
K8s cluster'ın için 3 ayrı subnet tasarla  mgmt, k8s-nodes, storage. Hangi CIDR'ları seçersin ve neden?

mgmt subnet => 10.0.1.0/28 => 10 adet ip alan varlık var ve 28 maskesinde 14 ip boşluğumuz olur.
k8s-nodes subnet => MetalLB üstünden ip alabilen çok fazla pod olabileceğinden farazi ortalama bir sayıyla 10.0.2.0/24 => 254 küsur ip alabilen varlık olur.
storage subnet => Diyelim ki HA uygladık ve 5 node var. Aynı anda minimum 3-4 etcd varlığı demek, bu sebeple 10.0.3.0/29 deriz yaklasık 6 tane boşluk yakalamış oluruz. ß