# 📝 Notlar — Ağ ve Linux Temelleri (Genel)

## Neden var?
Ağ bilmeden K8s'in neyin nereye gittiğini anlayamazsın. Bir servis neden erişilemiyor, pod neden dışarı çıkamıyor, iptables kuralı neden çakışıyor — bunların hepsinin altında IP, routing, NAT, DNS var. Bu başlık altındaki konular birbirinin üstüne inşa ediliyor: önce IP/CIDR anlarsın, sonra VLAN'la izolasyon yaparsın, NAT ile içten dışa çıkışı anlarsın, DNS ile isimlendirmeyi anlarsın, iptables ile kuralları yazarsın. Hepsini bilmeden "ağ sorunu var" deyip geçersin, ne olduğunu anlayamazsın.

## Anahtar Kavramlar
Bu başlık altındaki her konunun kendi notlar.md'si var. Özet:
- IP/CIDR/Subnetting: Ağı mantıksal bloklara ayırma. K8s'de her namespace, her node, her servis kendi subnet'inde.
- VLAN: Aynı fiziksel switche bağlı cihazları mantıksal olarak izole etme.
- DNS/CoreDNS: İsimden IP'ye çeviri. K8s içinde her servis DNS adıyla bulunuyor.
- NAT (SNAT/DNAT): Özel IP'den public IP'ye geçiş ve geri dönüş. K8s'de her pod-dışı trafik bunun üzerinden geçiyor.
- iptables: Linux'un paket filtreleme motoru. K8s'in kube-proxy'si arka planda iptables yazıyor.
- L4 vs L7: Hangi katmanda ne yapıldığı. MetalLB L4, Nginx L7, Service Mesh ikisi birden.
- Linux Network Namespace: Her pod'un kendi izole ağ stack'i. Sidecar pattern'ının temeli.
- vmstat/iostat/sar: Node'un iç organlarını okuma. Bottleneck nerede bulmak için.

## Kendi Notum
Bu konular başlangıçta "neden bu kadar temel şeyi öğreniyoruz" hissettiriyor ama ilk ağ sorununla karşılaştığında anlıyorsun. K8s'de bir servis dışarıya açılmıyor: MetalLB mi sorunlu, iptables kuralı mı eksik, CoreDNS mi yanlış çözümleyip, NAT mı yanlış? Bunları ayırt edebilmek için katmanları bilmek zorundasın.

## Karşılaştığım Hatalar
Her konunun kendi notlar.md'sinde belgelenmiştir.

## Kaynaklar
- Linux Networking Cookbook: https://www.oreilly.com/library/view/linux-networking-cookbook/9780596102487/
- K8s networking modeli: https://kubernetes.io/docs/concepts/cluster-administration/networking/
- Brendan Gregg (Linux performance): https://brendangregg.com/
