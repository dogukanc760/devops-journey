# 📝 Notlar

## Neden var?
PXE ile OS imajını indirdin, kurulum başladı ama kurulum sırasında "disk nereye, kullanıcı adı ne, SSH key hangisi, paketler hangisi" diye sorular sorar. 100 sunucu için 100 kez manuel cevap vermek imkansız. cloud-init ve autoinstall bu soruları önceden YAML ile cevaplanmış şekilde sunar, kurulum tamamen otomatiğe gider.

Temel:
autoinstall: Ubuntu'nun kurulum otomasyonu. PXE boot sırasında HTTP'den bir user-data YAML dosyası çeker, kurulum parametrelerini oradan alır.
cloud-init: OS kurulduktan sonra ilk boot'ta çalışır. SSH key ekle, paket kur, hostname ayarla, script çalıştır: "ilk açılışta ne yapılsın" tanımı.

Fark: autoinstall kurulum sırasında, cloud-init kurulum sonrasında çalışır.

```yaml
# autoinstall örneği (user-data)
autoinstall:
  version: 1
  identity:
    hostname: k8s-node-01
    username: ubuntu
    password: "$6$hash..."
  ssh:
    install-server: true
    authorized-keys:
      - "ssh-rsa AAAA..."
  packages:
    - curl
    - open-iscsi
  late-commands:
    - curtin in-target -- systemctl enable --now open-iscsi
```

## Anahtar Kavramlar
- cloud-init datasource: cloud-init nereden config alacağını nasıl anlıyor? EC2 ise AWS metadata API, NoCloud ise local ISO veya HTTP URL, MaaS ise MaaS'ın kendi datasource'u.
- `#cloud-config`: YAML dosyasının ilk satırı bu olmalı, cloud-init'in tanıması için şart.
- autoinstall late-commands: Kurulumun en sonunda çalışan komutlar. `curtin in-target --` ile kurulu sisteme chroot yapılıp komut çalıştırılır.
- user-data: cloud-init'e veya autoinstall'a gönderilen YAML içeriği. PXE'de HTTP üzerinden sunulur.
- meta-data: Instance ID ve hostname bilgisi. NoCloud datasource için user-data yanında mutlaka olmalı, boş bile olsa.
- `cloud-init status --wait`: cloud-init tamamlanana kadar bekler. VM veya bare-metal boot sonrası provisioning bitti mi kontrol etmek için kullanılır.

## Kendi Notum
Şöyle anlatırdım: bir ofis kuruyorsun ve 50 masaya bilgisayar kuracaksın. Tek tek "dil Türkçe mi İngilizce mi, kullanıcı adı ne, hangi programlar yüklensin" sorup cevap almak yerine bir form hazırlıyorsun (autoinstall.yaml), her bilgisayar açıldığında bu formu okuyor ve otomatik kuruluyor. cloud-init ise bilgisayar kurulduktan sonra "ilk açılışta Teams'i aç, antivirüs güncelle, VPN bağlan" gibi şirket politikalarını uygulayan şey.

DevOps bağlamında: 20 K8s worker node kuruyorsun. autoinstall ile hepsi Ubuntu kuruyor, diskleri bölünüyor, SSH key ekleniyor. cloud-init ile `open-iscsi` yükleniyor, kernel parametreleri ayarlanıyor, K8s join komutu çalıştırılıyor. Sen sadece sunucuları açıyorsun, 15 dakika sonra hepsi cluster'a katılmış.

## Karşılaştığım Hatalar
Fiziksel donanım olmadığı için autoinstall'ı gerçek bir kurulumda test edemedim. Local test için QEMU + NoCloud seed ISO yaklaşımı var (`cloud-localds` komutu ile), bunu `cloud-init/komutlar.sh`'da belgeledim.

cloud-init syntax hatası sessizce geçebiliyor, `cloud-init status` success dese de aslında bazı block'lar fail etmiş olabilir. `/var/log/cloud-init-output.log` ve `cloud-init analyze show` ile detaylı bakılması gerekiyor.

## Kaynaklar
- cloud-init resmi döküman: https://cloudinit.readthedocs.io/
- Ubuntu autoinstall referansı: https://ubuntu.com/server/docs/install/autoinstall-reference
- NoCloud datasource: https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html
