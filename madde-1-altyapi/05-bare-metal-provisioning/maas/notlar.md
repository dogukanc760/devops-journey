# 📝 Notlar

## Neden var?
PXE boot'u manuel kurmak: dnsmasq config, TFTP server, OS imajları, autoinstall, her şeyi elle yapmak zaman alan ve hata açık bir süreç. MaaS bunu bir UI ve API arkasına koyar. Sunucuyu rafa tak, MaaS'a tanıt, tek tıkla OS kur, K8s node'una ekle. Canonical'ın bare-metal'i cloud gibi yönetmeni sağlayan çözümü.

Temel:
Sunucuları inventory'e eklersin (MAC adresi ile tanıtırsın).
MaaS PXE üzerinden sunucuyu komisyona alır (donanım keşfi).
İstediğin OS'u seç, deploy et: MaaS PXE + cloud-init ile kurar.
API üzerinden otomatize edebilirsin: Terraform MaaS provider var.
Network yönetimi de yapabilir: VLAN, subnet, IP assignment.

Akış: Sunucu -> MaaS inventory'e ekle -> Commission (donanım keşfi) -> OS seç -> Deploy -> Hazır node

MaaS ile Tinkerbell farkı?
MaaS: Canonical tarafından geliştirildi, UI + API odaklı, kullanımı kolay, kendi içinde DHCP/DNS/PXE barındırır. Büyük datacenter'lar için ideal.
Tinkerbell: CNCF projesi, cloud-native, workflow tabanlı, her provisioning adımı ayrı bir container action. K8s içinde çalışır, GitOps ile entegre edilebilir. Daha esnek ama daha karmaşık.

## Anahtar Kavramlar
- Commission: MaaS'ın yeni sunucuya "seni tanıyayım" dediği aşama. PXE ile boot eder, donanım bilgilerini (CPU, RAM, disk) toplar.
- Enlist: Sunucunun MaaS'a kendini tanıttığı an. PXE boot edince MaaS "yeni makine var" diye görür.
- Deploy: Commission sonrası seçilen OS'un kurulumu. MaaS tüm zinciri kendisi yönetir.
- Release: Deploy edilmiş sunucuyu geri almak. OS silinir, yeniden deploy edilebilir hale gelir.
- IPMI/BMC entegrasyonu: MaaS IPMI üzerinden sunucuyu uzaktan açıp kapatabilir. Fiziksel butona gerek kalmaz.
- Terraform MaaS provider: Infrastructure as Code ile MaaS yönetimi. `maas_machine` resource ile sunucu deploy edebilirsin.

## Kendi Notum
Şöyle düşün: bir bulut provider'ın (AWS, GCP) data center'ını kendi içinde kuruyorsun ama kendi fiziksel sunucularınla. AWS'de "bir EC2 aç" diyorsun ve 30 saniyede hazır. MaaS bunu fiziksel sunucu için yapıyor. Sunucuyu rafa takıyorsun, MaaS'a tanıtıyorsun, deploy butonuna basıyorsun, 10-15 dakika sonra SSH ile bağlanabiliyorsun. Aynı hız, aynı kolaylık, ama donanım senin.

Terraform ile birleşince tam IaC oluyor: `terraform apply` ile 10 sunucu deploy et, K8s cluster'ına ekle, silmek istediğinde `terraform destroy`. Tüm fleet böyle yönetiliyor büyük data center'larda.

## Karşılaştığım Hatalar
Fiziksel donanım olmadığı için MaaS'ı gerçek ortamda test edemedim. Komutlar `maas/komutlar.sh`'da belgelenmiş.

MaaS kurulumunda en yaygın sorun PostgreSQL bağlantısı, connection string yanlış yazılırsa MaaS sessizce fail ediyor. `journalctl -u snap.maas.supervisor --no-pager` ile log bakmak gerekiyor. Bir de MaaS'ın kendi DHCP'si ile ağda başka bir DHCP çakışırsa sunucular yanlış IP alıyor, ağda başka DHCP varsa MaaS network interface'inde DHCP disable edilmeli.

## Kaynaklar
- MaaS resmi döküman: https://maas.io/docs
- Terraform MaaS provider: https://registry.terraform.io/providers/maas/maas/latest/docs
- MaaS CLI referansı: https://maas.io/docs/maas-cli
