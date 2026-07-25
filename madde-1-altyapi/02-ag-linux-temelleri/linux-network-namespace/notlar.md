# 📝 Notlar

## Neden var?
K8s'de her pod birbirini göremez, aynı node'da çalışsalar bile. Bu sihir network namespace sayesinde olur. Her pod'un kendi network stack'i var: kendi IP'si, kendi routing tablosu, kendi iptables kuralları. Namespace olmasa tüm podlar aynı ağı paylaşır, port çakışması olur ve izolasyon olmaz.

Temel:
Her pod = 1 Network Namespace
Pod içindeki tüm containerlar aynı namespace'i paylaşır (bu yüzden localhost ile birbirlerine erişebilirler).
veth pair: Namespace'i host ağına bağlayan sanal kablodur, bir ucu pod'da bir ucu host'tadır.
CNI (Calico, Cilium, Flannel vs.): Bu veth pair'leri otomatik kuran şeydir.

Soru: Bir pod içinde iki container var, nginx ve sidecar. nginx 80 portunu dinliyor. sidecar nasıl localhost:80'e erişebilir?
Cevap: Çok basit, aynı network namespace'i paylaştıkları için direkt localhost ile sidecar localhost:80'e erişebilir. Bu K8s'in sidecar pattern'ının temelidir. Istio'nun envoy proxy'si de tam bu şekilde çalışır, her pod'a inject edilen sidecar aynı namespace üzerinden trafiği intercept eder.

## Anahtar Kavramlar
- Network Namespace: Her pod'a özel izole ağ stack'i. Kendi IP'si, routing tablosu ve iptables kuralları var.
- veth pair: İki uçlu sanal ethernet kablosu. Bir ucu pod namespace'inde, diğer ucu host'un bridge'inde. Pod ile dış dünya bu kablo üzerinden konuşur.
- Pod içi container iletişimi: Aynı pod'daki containerlar aynı namespace'i paylaşır, localhost:port ile birbirini bulur. Sidecar pattern'ı buna dayanır.
- CNI plugin: veth pair'leri kuran, IP atayan, routing ayarlayan araç. Flannel, Calico, Cilium gibi.
- Transparent Proxy: Uygulamanın haberi olmadan trafiği yakalayıp yönlendiren proxy. Istio'nun Envoy'u bunu iptables kurallarıyla yapar, uygulamanın tek satır kodunu değiştirmeden mTLS ve traffic management ekler.

## Kendi Notum
Agam düşün ki senle aynı şirketteyiz ama farklı projelerde çalışan 2 backend deviz ve aynı ağ ortamında benzer adreslere istek atıyoruz. Diyelim ki çok edge case ama kendi backendimize bir servisi entegre ediyoruz ve ikimiz de aynı ağda olduğumuzdan localhost:1925'e istek atıyoruz fakat ikimiz de farklı servislere gitmeyi umuyoruz. Bu noktada o hedef servisle kendi servisimizi aynı pod içerisinde bir sidecar olarak koyuyoruz, otomatikman aynı network namespace'i paylaştıkları için kendi servisimiz kendi hedef servisimize erişebiliyor ve birbirimizden de izole oluyoruz.

Sidecar eklediğimiz örnek bir senaryo şu: sidecar genellikle kendi servisine transparent proxy, logging veya auth katmanı eklemek için kullanılır, sadece izolasyon için değil. Istio'nun envoy'u bunun en iyi örneği. Uygulamanın kodunu hiç değiştirmeden tüm trafik intercept edilip mTLS ile şifreleniyor, metrik toplanıyor, circuit breaker çalışıyor.

## Karşılaştığım Hatalar
`ip netns list` k3d node içinde çalıştırınca boş geldi, k3d kendi namespace'lerini farklı gösteriyor. Gerçek bir Linux ortamında `lsns -t net` ile tüm network namespace'leri görebilirsin. Bunun yerine K8s container inspection yöntemi daha güvenilir:
```bash
kubectl exec -it pod-name -- cat /proc/1/net/fib_trie
```

veth pair oluşturup namespace'e bağlarken `ip link set veth1 netns test-ns` komutunu çalıştırmadan önce namespace'in var olduğundan emin olmak gerekiyor, yoksa "Cannot find network namespace" hatası geliyor.

## Kaynaklar
- Linux Namespaces belgeleri: https://man7.org/linux/man-pages/man7/namespaces.7.html
- K8s CNI spec: https://github.com/containernetworking/cni
- Istio sidecar injection: https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/
