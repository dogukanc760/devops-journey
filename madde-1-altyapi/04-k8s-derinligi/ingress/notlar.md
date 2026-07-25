# 📝 Notlar

## Neden var?
Her servis için ayrı LoadBalancer açsan her biri ayrı external IP ister. Hem pahalı hem yönetilmez. Ingress Controller tek bir giriş noktasından HTTP/HTTPS trafiğini domain ve path'e göre doğru servise yönlendirir. Olmasa 10 servisin için 10 ayrı IP, 10 ayrı port gerekir ve tam bir kaostur.

Temel:
Client -> Ingress Controller (L7) -> Service -> Pod
domain.com/api -> api-service
domain.com/web -> frontend-service

Ingress Resource: "Bu domain/path şu servise gitsin" kuralı.
Ingress Controller: O kuralı uygulayan şey (Nginx, Traefik, Kong).
TLS termination burada olur: sertifikayı Controller taşır, pod'lar HTTP konuşur.

Ingress Controller ile LoadBalancer Service farkı?
Ingress standart olarak L7'de çalışırken LoadBalancer L4'te çalışır. Dışarıdan trafik önce L4'te MetalLB karşılar ve Nginx'e iletir, Nginx L7'de HTTP routing yaparak doğru pod'a yönlendirir. Yani ikisi aynı anda çalışır ama farklı katmanlarda. MetalLB L4, Nginx L7.

NodePort ise LoadBalancer olmadan direkt NodeIP:port üzerinden erişim sağlar, bu da L4'tür. Tek bileşen hem L4 hem L7 yapan ise Service Mesh'tir (Istio/Linkerd): sidecar proxy olarak her pod'a inject edilir.

## Anahtar Kavramlar
- Ingress Resource: YAML ile yazılan kural. Host, path ve hedef service tanımı. Controller bu kuralı okur ve uygular.
- Ingress Controller: Kuralları uygulayan gerçek yazılım. Nginx, Traefik, Kong, HAProxy. Cluster'a ayrıca kurulur.
- TLS Termination: Sertifika Controller'da. Pod HTTPS'den habersiz, HTTP alır. Secret olarak `tls.crt` ve `tls.key` gerekir.
- Host-based routing: `api.myapp.com -> api-service`, `app.myapp.com -> frontend-service`. Tek IP, birden fazla domain.
- Path-based routing: `myapp.com/api -> api-service`, `myapp.com/web -> frontend-service`. Tek domain, farklı path'ler.
- IngressClass: Birden fazla Ingress Controller varsa hangisinin kural uygulayacağını belirler.

## Kendi Notum
Şöyle düşün: şehirde tek bir gümrük kapısı var, tüm kargo oradan giriyor. Gümrükteki yönlendirici "api.myapp.com dışında fatura var mı" diyor, varsa api-service'e yönlendiriyor. "web yazan fatura var mı" diye bakıyor, varsa frontend-service'e. Bu gümrük yönlendiricisi Ingress Controller, kapı ise tek bir external IP.

Bunu olmadan: her servisin kendi kapısı olurdu (LoadBalancer), her kapı ayrı IP, ayrı sertifika, ayrı yönetim. 20 serviste 20 LoadBalancer, 20 IP, 20 sertifika. Hem pahalı hem kaos.

## Karşılaştığım Hatalar
k3d'de MetalLB yoktu, bu yüzden Ingress Controller'ın external IP'si `<pending>` kaldı. Port-forward ile çözdük:
```bash
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 9443:443
curl -k -H "Host: myapp.local" https://127.0.0.1:9443
```

Self-signed sertifika oluştururken `openssl req` komutunda `-subj` parametresini unuttum, interactive prompt açıldı ve dondu. `-subj "/CN=myapp.local/O=myapp"` parametresi zorunlu.

Ayrıca `curl` k3d container içinde yüklü değildi, Alpine minimal image. Mac terminalinden port-forward üzerinden test etmek gerekti.

## Kaynaklar
- K8s Ingress belgeleri: https://kubernetes.io/docs/concepts/services-networking/ingress/
- NGINX Ingress Controller: https://kubernetes.github.io/ingress-nginx/
- cert-manager (otomatik sertifika): https://cert-manager.io/docs/
