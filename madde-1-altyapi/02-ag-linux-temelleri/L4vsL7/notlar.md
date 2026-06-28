# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Tek sunucuya gelen trafik onu çökertebilir, LB trafiği birden fazla backend'e dağıtır ama tüm trafik aynı değil, bazısı TCP pakedi, bazısı HTTP isteği. L4 pakede bakar, L7 içeriğe bakar. İkisini bilmeden MetalLB'mi, Nginx mi yoksa Istio mu kullanacağını bilemezsin. 

Temel:

L4(Transport Layer) -> TCP/UDP pakedine bakar, içine bakmaz
Kaynak/hedef IP veya porta göre yönlendirir.
Hızlı, düşük latency
Araçlar: MetalLB, HAProxy(L4 Modu), iptables

L7(Application Layer) -> HTTP Header'larına, path'e, host'a bakar.
/api->backend-1, /web->backend-2 yapabilir
TLS termination burada olur
Araçlar: Nginx, Traefik, Kong veya Istio olabilir.

K8s'de ise:
Dışarıdan gelen istek-> L7 Ingress(Örneğin Nginx)->ClusterIP Service->L4 Kube Proxy(iptables)->Pod şeklinde olur. 

Örnek bir use-case:
# k3d cluster'ında Nginx Ingress kur
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

# Basit bir Ingress kuralı yaz:
# /api → api-service
# /web → web-service
kubectl get ingress

Örnek Soru:
Neden TLS termination L7'de yapılır da, L4'te yapılmaz veya yapılamaz mı?:
Cevap:
Yapılamaz çünkü L4 paket içeriğiyle ilgilenmez eposta mı oyun mu bir api call mu bilmez bile sadece TCP/UDP kısmına bakar alıcı(ip) ve kapı numarası(port) ile ilgilenir. SSL/TLS gibi şifrelenmiş veri olsa dahi bu onu alakadar etmez çünkü pakedi iptables veya MetalLB kurallarına göre hedefe geçirebiliyorsa geçirir yoksa yallah der bu sebeple hızlı çalışır.
Ufak bir ekleme:
TLS passthrough diye bir şeyde vardır ve L7 LB şifreyi çözmeden pakedi olduğu gibi backende iletir. Backend kendisi TLS'i çözer. Bu teknik olarak L4 davranışıdır ama L7 araçta yapılır. Bazen end-to-end encryption gerektiren durumlarda kullanılabilir.
## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- 
L4: L4(Layer 4 - Transport Layer) TCP/UDP katmanında çalışır, görevi gelen pakedi net olarak söylenen adrese iletmektir. Paket içeriğiyle ilgilenmez sadece yazılmış kurallara (iptables rules) göre pakedi iletebiliyorsa iletir, iletemezse cycle sonlanır. Bu sebeple basit ve hızlı çalışır. Hatta şifrelenmiş verileri(SSL/TLS) direkt ilettiğinden de güvenlidir çünkü paket içeriğine karışmaz/dokunmaz.
L7: L7(Layer 7 - Application/Presantation Layer) Application katmanında çalışır, gelen isteği komple ele alabilir. Gelen isteğin URL'sine, çerezlerine, veya görsel mi metin mi olduğuna bakarak akıllı bir yönlendirme yapabilir. Örneğin 
/api ile gelen suffixli isteklerde içeride ki /api karşılıgında yer alan servislere yönlendirmesi,
/web ile gelen suffixli istteklerde ise içeride yer alan frontend servis/applerine yönlendirmesi gibi. L4'e göre yavaştır çünkü paket içeriğini doğrudan ele alır ve buna göre yapılandırılma şekline göre karar verip yönlendirme yapar.  

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Aga şöyle anlatayım, yine kargodan gidelim paket dağıtım kisvesi altında :D. Şöyle ki, sen bir kargo firması çalışanısın ve firma sana bir paket verip şuraya git diyor. Sen pakedin içeriğiyle ilgilenmezsin ve belirtilen adrese pakedi götürürsün. Tek ilgilendiğin Address ve kapı numarısıdr yani ip si ve portudur, işte buna L4 denir. Yani direkt TCP/UDP yani Transport Layer da çalışan kısım. 

Bir de güvenlikli site vardır, içeri giremezsin pakedi güvenliğe teslim edersin o içeride ki alıcıya götürür bu da L7' ye yani application/presentation layer'a bir örnektir. Sen ingress kaynağı olarak pakedi teslim edersin ingress üstünden L7 de bullunan herhangi bir trafik yönlendirme aracı(Nginx, Traefik vs...) aracı içeride Cluster IP Service'ine bunu verir ve daha sonra Kube Proxy yani L4(bu da site içinde ki bir çalışan olabilir ve pakedi sana getiriyordur hademe mesela ve bu hademenin adı MetalLB veya HAProxy olabilir.) kısmında sadece iletimi sağlar o da artık poda yani kargo pakedinin gerçek alıcısına ulaşmış olur. 

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- 
