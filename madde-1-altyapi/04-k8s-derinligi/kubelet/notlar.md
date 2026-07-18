# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Control Plane "bu pod şu node'a gitsin" der ama kim o node'da pod'u gerçekten başlatır? Kim container'ı çalıştırır, sağlığını kontrol eder ve ölünce haber verir? Işte Kubelet. Her node'da çalışan bir ajan. Control PLane'nin sahada ki temsilcisidir. 

Temel:
- Her node'da bir Kubelet çalışır
- apiserverdan "bu pod sence çalışacak" talimatını alır
- Container runtime'a(containerd) podu başlatmasını söyler
- Pod'un liveness/readiness probelarını çalıstırır
- Node'un CPU/memory metriklerini raporlar

apiserver->kubelet->containerd->container(pod)
Kubelet apiserver çökse bile kendi node'unda ki podları aykata tutar.

Örnek Soru:
Kubelet ile kube-proxy arasında ki fark nedir? İkiside node da çalısıyor ama farklı şeyler yapıyor.
Cevap:
Kubelet her node da bir tane bulunan ajan, control planeden o node a gelen emirleri uygular fakat kube-proxy o node içerisinde çalışan gelen isteklerin adreslerine karsılık hangi podun olduğu nu bilen ve isteği yönlendiren yani dnat yaptıgımız kısımdır
Kubelet    → node'da pod yaşam döngüsü (başlat, durdur, izle)
kube-proxy → node'da ağ kuralları (iptables DNAT, servis → pod yönlendirme)
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


 