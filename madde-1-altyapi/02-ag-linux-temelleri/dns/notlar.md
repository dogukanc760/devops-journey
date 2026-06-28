# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
10.0.2.25'e istek atmak yerine api.myapp.com yazarsın, IP'ler değişir, domain değişmez. K8s içinde durum aynı, bir pod database-service adına istek atar, CoreDNS bunu IP'ye çevirir. CoreDNS olmasa her pod her servisin IP'sini hardcode bilmek zorunda kalır, pod restart'ta IP değişir ve her şey çöker.
## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- DNS ve CoreDNS davranışları

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Agam bak şimdi diyelim sen bir frontend geliştiricisisin ve bir apiyi frontende entegre ediyorsun fakat sürekli apiye ait IP bir sebeple değişiyor ve sen her seferinde istek attığın host bilgisini editlemek durumundasın. İşte DNS burada devreye giriyor sen IP'ye istek atmak yerine bir domaine gidiyorsun ve domaini yöneten yapı her neyse (örn: Cloudflare veya ağın geçtiği bir gateway) sana o domainin karşılığında ki ip ile iletişim kurmanı sağlıyor. K8s tarafında da bu işi yapan birimin adı CoreDNS, CoreDNS gelen bütün isteklerin gideceği destination address karşılığında ki domaini çözümleyip ilgili pod/service veya her neyse o IP'ye yönlendirilmesini sağlıyor. Böylece ister K8s olsun, ister global ağlarda ki bir api sunucusu olsun, IP değişse dahi DNS aracılığıyla sorunsuz iletişim kurabiliyorlar. 
Temelde Çalışma Prensibi şöyledir => 
Client → Recursive Resolver → Root NS → TLD NS → Authoritative NS → IP

K8s içinde de şöyle çalışır => 
my-service.my-namespace.svc.cluster.local → ClusterIP

Edge Case bir soru:
Split Horizon DNS (veya Bölünmüş DNS) ne işe yarar?:
Split Horizon DNS aynı alan adı için ağın içinden ve dışında gelen sorgulara/isteklere farklı IP adresleriyle yanıt verilmesini sağlayan bir yapıdır. 

K8s Contextinde ki bir kullanım örneği de şu olabilir:
Diyelim intranette çalısması gereken bir app'iniz var. Bu app sadece o şirket içi ağda çalışan ve şirkete özel olan bir app. Fakat aynı domainde başka bir appte var ve bu app sadece dış ağlardan erişilebiliyor. Dış ağlardan erişenler şirkete dair bir tanıtım/kurumsal web sitesi görürken, şirket içinden erişenler ise şirket içinde kullanılan özel bir web uygulaması görürler. Işte bu da bir use-case örneğidir. 
Bir diğer kullanım örneğide yine K8s contextinde şöyle spesifik bir yaklasım var,
diyelim ki api.myapp.com dışarıdan LoadBalancer IP'ye çözümlenir ama cluster içinden aynı domain direkt ClusterIP'ye çözümlenir. Böylece trafik gereksiz yere dışarı çıkıp geri gelmez.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- 
