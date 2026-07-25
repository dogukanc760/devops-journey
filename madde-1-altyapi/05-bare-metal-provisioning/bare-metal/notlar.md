# 📝 Notlar

## Neden var?
VM veya container üzerine değil, doğrudan fiziksel donanım üstünde çalışan sistem. "Bare" = çıplak, araya hiçbir sanallaştırma katmanı girmiyor.

Katmanlar:
Bare-Metal: Donanım -> OS -> Uygulama
VM: Donanım -> Hypervisor -> VM -> OS -> Uygulama
Container: Donanım -> OS -> Container Runtime -> Container

Bare-metal'da hypervisor yok, VM overhead'i yok. Maksimum performans, maksimum kaynak kullanımı.

Ne zaman bare-metal tercih edilir?
Veritabanı sunucuları (PostgreSQL, MySQL), latency kritik.
GPU Cluster'ları (ML/AI workload).
Yüksek I/O gerektiren storage sistemleri (Ceph bir örnektir).
Telekom, finans gibi latency-sensitive sektörler.

Ne zaman VM/Container tercih edilir?
Çoklu tenant, izolasyon gerektiğinde.
Hızlı scale up/down.
Maliyet optimizasyonu.

K8s node'ları bare-metal mı, VM mi? Trade-off nedir?
Her K8s node'u bare-metal veya VM olmalı diye bir kıstas yoktur, duruma göre karar vermek gerekebilir. Eğer aynı hypervisor üstünde çok fazla VM varsa ve PostgreSQL node'u da oradaysa, donanım yükü paylaşımı latency'yi olumsuz etkiler. Bu sebeple karar mekanizması ne zaman hangisi tercih edileceği ile alakalıdır. Trade-off: bankacılıktayız, kritik, bare-metal. Ama çok hızlı scale up lazım, bare-metal cevap vermez çünkü fiziksel sunucu eklemek uzun sürer. Hybrid yaklaşım da çok yaygın: kritik DB'ler bare-metal, uygulama katmanı VM/container.

## Anahtar Kavramlar
- Bare-Metal: Fiziksel donanım üstünde direkt OS. Sanallaştırma yok, overhead yok. Maksimum performans.
- Hypervisor: VM'leri yöneten yazılım katmanı. Type 1 (VMware ESXi, Proxmox) donanım üstünde, Type 2 (VirtualBox) OS üstünde çalışır.
- IPMI/BMC: Bare-metal sunucuların uzaktan yönetim arayüzü. OS çalışmasa bile network üzerinden sunucuyu açıp kapatabilirsin. MaaS ve provisioning araçları buna bağlanır.
- Hybrid Approach: Kritik workload'lar bare-metal, stateless servisler VM/container. En yaygın gerçek dünya seçimi.
- iLO/DRAC: HPE ve Dell'in IPMI implementasyonları. Bare-metal server yönetimi için kullanılır.

## Kendi Notum
Şöyle anlatırdım: düşün arabanı aldın ve fabrikadan çıktığı gibi. Motor üstünde hiçbir şey yok, direkt sen kullanıyorsun. İşte bare-metal bu, donanım direkt sana ait, arada kimse yok. Şimdi bir de düşün araba bir kiralık araç, kiralayanlar (hypervisor) arabanın birden fazla kişi tarafından paylaşılmasını sağlıyor. Her kiracı kendi arabasını kullandığını sanıyor ama aslında aynı motor paylaşılıyor. İşte VM bu. Container ise o araçta ek olarak çalışan bir taksi uygulaması gibi, koltukları paylaşan ama her biri kendi rotasında çalışan bir yapı.

Finans veya telekom için neden bare-metal: her milisaniye para. VM overhead'i var, hypervisor context switch yapıyor, bu latency ekliyor. Bare-metal'da bu yok.

## Karşılaştığım Hatalar
Fiziksel donanım erişimim olmadığı için bu konuyu tamamen teorik geçtim. k3d'de zaten "donanım üstünde değil, container içinde container" yapısı olduğu için bare-metal simülasyonu mümkün değil. Rook ve Longhorn pratiklerinde bu kısıtla karşılaştım.

Bare-metal lab kurulduğunda ilk yapılacak: IPMI/BMC erişimini test et, sonra PXE boot zincirini kur.

## Kaynaklar
- Proxmox (Type 1 Hypervisor, ücretsiz): https://www.proxmox.com/
- IPMI standart: https://www.intel.com/content/www/us/en/products/docs/servers/ipmi/ipmi-second-gen-interface-spec-v2-rev1-1.html
- Bare-metal vs VM K8s karşılaştırması: https://kubernetes.io/docs/setup/best-practices/
