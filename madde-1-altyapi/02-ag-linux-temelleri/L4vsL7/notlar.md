# 📝 Notlar

## Neden var?
Tek sunucuya gelen trafik onu çökertebilir, LB trafiği birden fazla backend'e dağıtır ama tüm trafik aynı değil, bazısı TCP paketi, bazısı HTTP isteği. L4 pakete bakar, L7 içeriğe bakar. İkisini bilmeden MetalLB mi, Nginx mi yoksa Istio mu kullanacağını bilemezsin.

Temel:
L4 (Transport Layer) -> TCP/UDP paketine bakar, içine bakmaz. Kaynak/hedef IP veya porta göre yönlendirir. Hızlı, düşük latency. Araçlar: MetalLB, HAProxy (L4 modu), iptables.

L7 (Application Layer) -> HTTP header'larına, path'e, host'a bakar. /api -> backend-1, /web -> backend-2 yapabilir. TLS termination burada olur. Araçlar: Nginx, Traefik, Kong veya Istio.

K8s'de ise: Dışarıdan gelen istek -> L7 Ingress (örneğin Nginx) -> ClusterIP Service -> L4 Kube Proxy (iptables) -> Pod şeklinde olur.

Örnek soru:
Neden TLS termination L7'de yapılır da L4'te yapılmaz veya yapılamaz mı?
Yapılamaz çünkü L4 paket içeriğiyle ilgilenmez, eposta mı oyun mu bir api call mu bilmez bile, sadece TCP/UDP kısmına bakar, alıcı (ip) ve kapı numarası (port) ile ilgilenir. SSL/TLS gibi şifrelenmiş veri olsa dahi bu onu alakadar etmez çünkü paketi iptables veya MetalLB kurallarına göre hedefe geçirebiliyorsa geçirir yoksa yallah der. Bu sebeple hızlı çalışır.
Ufak bir ekleme: TLS passthrough diye bir şey de vardır ve L7 LB şifreyi çözmeden paketi olduğu gibi backende iletir. Backend kendisi TLS'i çözer. Bu teknik olarak L4 davranışıdır ama L7 araçta yapılır. Bazen end-to-end encryption gerektiren durumlarda kullanılabilir.

## Anahtar Kavramlar
- L4: TCP/UDP paketine bakıyor, IP + port üzerinden yönlendiriyor. Paketi açmıyor, içine bakmıyor. Hızlı ve basit. MetalLB, iptables, kube-proxy bunun örnekleri.
- L7: HTTP içeriğini okuyor. URL path'e, header'a, cookie'ye göre yönlendirebiliyor. TLS burada çözülüyor. Nginx Ingress, Traefik bunun örnekleri.
- TLS Termination: Şifrelenmiş isteği L7 de çözüp backend'e plain HTTP olarak iletmek. Pod'lar sertifika yönetmek zorunda kalmaz.
- TLS Passthrough: L7 araç şifreyi çözmeden paketi olduğu gibi geçiriyor. End-to-end şifreleme gerektiğinde kullanılır.
- Service Mesh (Istio/Linkerd): Tek başına hem L4 hem L7 yapabilen tek bileşen. Sidecar olarak her pod'a inject edilir.

## Kendi Notum
Aga şöyle anlatayım, yine kargodan gidelim paket dağıtım kisvesi altında. Şöyle ki sen bir kargo firması çalışanısın ve firma sana bir paket verip şuraya git diyor. Sen paketin içeriğiyle ilgilenmezsin ve belirtilen adrese pakedi götürürsün. Tek ilgilendiğin adres ve kapı numarasıdır yani IP'si ve portunudur, işte buna L4 denir. Yani direkt TCP/UDP yani Transport Layer'da çalışan kısım.

Bir de güvenlikli site vardır, içeri giremezsin paketi güvenliğe teslim edersin o içerideki alıcıya götürür, bu da L7'ye yani application/presentation layer'a bir örnektir. Sen ingress kaynağı olarak paketi teslim edersin, ingress üstünden L7'de bulunan herhangi bir trafik yönlendirme aracı (Nginx, Traefik vs.) aracı içerideki ClusterIP Service'ine bunu verir ve daha sonra kube-proxy yani L4 kısmında sadece iletimi sağlar, o da artık poda yani kargo paketinin gerçek alıcısına ulaşmış olur.

## Karşılaştığım Hatalar
k3d'de MetalLB olmadığı için Ingress Controller'ın external IP'si `<pending>` kalıyordu. Çözüm olarak `kubectl port-forward svc/ingress-nginx-controller 9443:443` ile test ettik. Bu production'da yapılmaz tabii, sadece local lab için.

Ayrıca `curl -H "Host: myapp.local" http://127.0.0.1:9443` yaptığımda 308 redirect aldım, `-k` ile HTTPS üzerinden gitmek gerekti: `curl -k -H "Host: myapp.local" https://127.0.0.1:9443`.

## Kaynaklar
- Kubernetes Ingress belgeleri: https://kubernetes.io/docs/concepts/services-networking/ingress/
- NGINX Ingress Controller: https://kubernetes.github.io/ingress-nginx/
- MetalLB: https://metallb.universe.tf/
