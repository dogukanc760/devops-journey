# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Her servis için ayrı LoadBalancer açsan her biri ayrı external IP ister. Hem pahalı hem yönetilmez. Ingress Controller tek bir giriş noktasından HTTP/HTTPS trafiğini domain ve path'e göre doğru servise yönlendirir. Olmasa 10 servisin için 10 ayrı IP, 10 ayrı port gerekir ve tam bir kaostur.

Temel:
Client-> Ingress Controller(L7) -> Service -> Pod
         domain.com/api -> api-service
         domain.com/web -> frontend-service

- Ingress Resource -> "Bu domain/path şu servise gitsin" kuralı
- Ingress Controller -> O kuralı uygulayan şey (Ngnix, Traefik, Kong)
- TLS termination burada olur - sertifikayı Controller taşır, pod'lar HTTP konuşur. 


Örnek soru: 
Ingress Controller ile LoadBalancer Service farkı nedir? İkisi de dışarıdan trafik alıyor ama ne zaman hangisini kullanırsın?

Cevap:
Ingress standart olarak L7'de çalışırken LoadBalancer L4'te çalışır. 
Dışarıdan trafik önce L1'den girer, L4'te MetalLB karşılar ve Nginx'e 
iletir, Nginx L7'de HTTP routing yaparak doğru pod'a yönlendirir. 
Yani ikisi aynı anda çalışır ama farklı katmanlarda, farklı bileşenlerle — 
MetalLB L4, Nginx L7.

NodePort ise LoadBalancer olmadan direkt NodeIP:port üzerinden erişim sağlar, 
bu da L4'tür. Eğer önüne Nginx koyarsan yine L4 + L7 olur ama NodePort'un 
kendisi sadece L4'te çalışır.

"Tek bileşen hem L4 hem L7" yapan şey ise Service Mesh'tir (Istio/Linkerd) — 
sidecar proxy olarak her pod'a inject edilir ve her iki katmanda da çalışır.

Örnek L4+L7 akısı:
L1 (Physical) → L2 (Ethernet/MAC) → L3 (IP routing) → L4 (MetalLB, TCP/port)
                                                              ↓
                                                        L7 (Nginx, HTTP routing)
                                                              ↓
                                                           Pod
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
