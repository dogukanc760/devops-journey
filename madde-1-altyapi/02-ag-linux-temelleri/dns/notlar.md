# 📝 Notlar

## Neden var?
10.0.2.25'e istek atmak yerine api.myapp.com yazarsın, IP'ler değişir, domain değişmez. K8s içinde durum aynı, bir pod database-service adına istek atar, CoreDNS bunu IP'ye çevirir. CoreDNS olmasa her pod her servisin IP'sini hardcode bilmek zorunda kalır, pod restart'ta IP değişir ve her şey çöker.

## Anahtar Kavramlar
- DNS çözümleme zinciri: Client → Recursive Resolver → Root NS → TLD NS → Authoritative NS → IP
- CoreDNS: K8s'in kendi DNS sunucusu. Her servis ve pod için kayıt tutar. my-service.my-namespace.svc.cluster.local gibi bir adı ClusterIP'ye çözümler.
- ConfigMap ile özelleştirme: CoreDNS kube-system namespace'indeki ConfigMap üzerinden ayarlanır. Custom domain eklemek için Corefile'a blok yazılır.
- Split Horizon DNS: Aynı domain için içeriden ve dışarıdan farklı IP dönmek. Cluster içindeysen ClusterIP, dışarıdaysan LoadBalancer IP görürsün. Trafik gereksiz yere dışarı çıkıp geri gelmez.
- nslookup / dig: DNS sorgusunu test etmek için kullanılan araçlar. K8s içinde busybox pod'undan çalıştırılır.

## Kendi Notum
Agam bak şimdi, diyelim sen bir frontend geliştiricisisin ve bir API'yi frontende entegre ediyorsun fakat sürekli API'ye ait IP bir sebeple değişiyor ve sen her seferinde istek attığın host bilgisini editlemek durumundasın. İşte DNS burada devreye giriyor, sen IP'ye istek atmak yerine bir domaine gidiyorsun ve domaini yöneten yapı her neyse (örn: Cloudflare veya ağın geçtiği bir gateway) sana o domainin karşılığındaki IP ile iletişim kurmanı sağlıyor. K8s tarafında da bu işi yapan birimin adı CoreDNS, CoreDNS gelen bütün isteklerin gideceği destination address karşılığındaki domaini çözümleyip ilgili pod/service veya her neyse o IP'ye yönlendirilmesini sağlıyor. Böylece ister K8s olsun, ister global ağlarda bir API sunucusu olsun, IP değişse dahi DNS aracılığıyla sorunsuz iletişim kurabiliyorlar.

K8s içinde de şöyle çalışır: my-service.my-namespace.svc.cluster.local → ClusterIP

## Karşılaştığım Hatalar
CoreDNS'e custom domain eklerken ConfigMap'i yanlış namespace'e uyguladım önce, kube-system olmak zorunda. Ayrıca CoreDNS pod'unu restart etmeden değişiklik aktif olmadı:
```
kubectl rollout restart deployment/coredns -n kube-system
```
Test için busybox pod'unu `--restart=Never` olmadan açınca timed out aldım. `--restart=Never` şart.

## Kaynaklar
- CoreDNS resmi döküman: https://coredns.io/
- K8s DNS belgeleri: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
- CoreDNS Corefile referansı: https://coredns.io/plugins/
