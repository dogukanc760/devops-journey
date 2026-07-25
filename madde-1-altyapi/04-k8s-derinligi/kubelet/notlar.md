# 📝 Notlar

## Neden var?
Control Plane "bu pod şu node'a gitsin" der ama kim o node'da pod'u gerçekten başlatır? Kim container'ı çalıştırır, sağlığını kontrol eder ve ölünce haber verir? İşte Kubelet. Her node'da çalışan bir ajan. Control Plane'nin sahada temsilcisi.

Temel:
Her node'da bir Kubelet çalışır.
API Server'dan "bu pod sende çalışacak" talimatını alır.
Container runtime'a (containerd) pod'u başlatmasını söyler.
Pod'un liveness/readiness probe'larını çalıştırır.
Node'un CPU/memory metriklerini raporlar.

apiserver -> kubelet -> containerd -> container (pod)

Kubelet ile kube-proxy farkı?
Kubelet her node'da bir tane bulunan ajan, Control Plane'den o node'a gelen emirleri uygular. kube-proxy ise o node içerisinde çalışan ve gelen isteklerin adreslerine karşılık hangi pod'un olduğunu bilen ve isteği yönlendiren, yani DNAT yapan kısımdır.
Kubelet: node'da pod yaşam döngüsü (başlat, durdur, izle).
kube-proxy: node'da ağ kuralları (iptables DNAT, servis -> pod yönlendirme).

## Anahtar Kavramlar
- Kubelet: Node'un beyni. API Server'dan manifest alır, container runtime'a verir, pod'un sağlığını izler.
- Container Runtime Interface (CRI): Kubelet'in container runtime ile konuşma protokolü. containerd, CRI-O bunun örnekleri.
- Liveness Probe: "Bu pod hala canlı mı?" Fail olursa pod restart edilir.
- Readiness Probe: "Bu pod trafik alabilir mi?" Fail olursa Service endpoint'ten çıkarılır, restart edilmez.
- Static Pod: Kubelet'in API Server'a danışmadan doğrudan başlattığı pod. Control Plane bileşenleri (kube-apiserver, etcd) static pod olarak çalışır.
- Node Condition: Kubelet node'un durumunu raporlar. Ready, MemoryPressure, DiskPressure, PIDPressure bunlar.

## Kendi Notum
Şöyle düşün: Control Plane bir şirket genel merkezidir ve sahaya direktif verir. Kubelet ise sahadaki bölge müdürü. Genel merkez "bu bölgede 3 kişi çalışsın" diyor (desired state). Bölge müdürü gidip insanları işe alıyor (container başlatıyor), onları izliyor (probe), biri hastalanınca (liveness probe fail) rapor edip yerine yenisini koyuyor. Genel merkez kapansa bile bölge müdürü sahada olanları idare etmeye devam eder, şirketi kapatmaz.

Bu yüzden kube-apiserver çöktüğünde çalışan pod'lar ölmüyor: kubelet zaten sahadaydı ve pod'ları tutmaya devam ediyor.

## Karşılaştığım Hatalar
k3d'de kubelet'e direkt erişim yok çünkü k3d container içinde çalışıyor. Kubelet log'larını görmek için:
```bash
docker exec k3d-ha-cluster-server-0 journalctl -u k3s --no-pager | tail -50
```
k3s single binary olduğu için kubelet ayrı süreç değil, k3s binary'sinin içinde. Bu başta kafayı karıştırdı.

Readiness probe başarısız olunca pod'un Service'ten çıktığını test ettim: port numarasını yanlış girdim probe'a, pod Running'de kaldı ama endpoint'e gelmedi, Service üzerinden erişim kesildi. Bu farkı gözlemlemek önemliydi.

## Kaynaklar
- Kubelet referansı: https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/
- Liveness/Readiness probe: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- CRI (Container Runtime Interface): https://kubernetes.io/docs/concepts/architecture/cri/
