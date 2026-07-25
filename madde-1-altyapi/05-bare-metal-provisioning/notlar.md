# 📝 Notlar — Bare-Metal Provisioning (Genel)

## Neden var?
Cloud provider'larda "VM aç" butonu var. Kendi data center'ında aynı kolaylığı sağlamak için provisioning araçları gerekiyor. Yoksa 50 sunucuya tek tek USB takıp kurulum yaparsın, bu hem yavaş hem hata prone hem de tekrarlanamaz. Bare-metal provisioning bu süreci otomatize eder, sunucuyu fişe tak ve sisteme bırak.

## Anahtar Kavramlar
Bu başlık altındaki her konunun kendi notlar.md'si var. Özet:
- Bare-Metal: Sanallaştırma yok, doğrudan fiziksel donanım. Maksimum performans, minimum overhead.
- PXE Boot: Ağ üzerinden OS indirme ve kurma. DHCP + TFTP + HTTP zinciri.
- MaaS: Canonical'ın bare-metal cloud'u. GUI + API ile sunucu yönetimi.
- Tinkerbell: CNCF, GitOps-friendly, workflow tabanlı provisioning.
- cloud-init / autoinstall: OS kurulum ve ilk boot otomasyonu. YAML ile her şey tanımlanır.

## Kendi Notum
Bu subtask fiziksel donanım erişimim olmadığı için tamamen teorik + simülatif geçti. Komutlar belgelendi, bare-metal lab kurulduğunda sırayla PXE -> MaaS veya Tinkerbell -> cloud-init zincirini gerçek ortamda çalıştıracağız.

## Karşılaştığım Hatalar
Donanım olmadığı için pratik hata yok. Teorik olarak en kritik nokta: dnsmasq ile mevcut ağ DHCP'sinin çakışması. PXE boot denerken ağda başka DHCP varsa sunucu yanlış IP alır ve boot loader bulunamaz.

## Kaynaklar
- PXE boot guide: https://ipxe.org/
- MaaS döküman: https://maas.io/docs
- Tinkerbell CNCF: https://tinkerbell.org/
- Ubuntu autoinstall: https://ubuntu.com/server/docs/install/autoinstall-reference
