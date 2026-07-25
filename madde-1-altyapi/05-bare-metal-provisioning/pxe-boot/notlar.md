# 📝 Notlar

## Neden var?
100 sunucun var, hepsine tek tek USB takıp OS kurmak zorunda kalsaydın haftalarca sürer, hata riski de yüksek. PXE Boot sunucuyu fişe taktığın an ağ üzerinden otomatik OS kurar. "Fişe tak, 10 dakika bekle, hazır node."

3 Bileşen:
DHCP: Sunucu ağa bağlanır, "IP adresim ne?" diye sorar. DHCP IP verir ve "boot dosyan şu TFTP sunucusunda" der.
TFTP: Sunucu TFTP'den boot loader'ı (iPXE/pxelinux) indirir. TFTP basit, güvenliksiz bir dosya transfer protokolü, sadece boot için kullanılır.
HTTP: Boot loader ayağa kalktıktan sonra OS imajını, autoinstall config'ini HTTP üzerinden indirir.

Akış:
Sunucu açılır -> DHCP: "IP al + TFTP sunucusu şurada" -> TFTP: Boot loader indir (iPXE) -> HTTP: OS imajı + autoinstall config indir -> Ubuntu otomatik kurulur.

TFTP yerine neden HTTP kullanılmıyor direkt?
Makine o an sadece NIC firmware'iyle çalışıyor, TCP stack yok, OS yok, HTTP client yok. TFTP UDP üzerinden çalışır, implement etmesi çok basit, bu yüzden firmware'e gömülebilir. HTTP sonradan devreye girer çünkü o zaman artık iPXE boot loader ayaktadır, TCP stack var, HTTP yapabilir.

NIC firmware: sadece UDP/TFTP biliyor.
iPXE loader: TCP/HTTP yapabiliyor.

## Anahtar Kavramlar
- PXE (Preboot Execution Environment): NIC'in içine gömülü küçük program. OS yokken DHCP ve TFTP'yi kullanarak boot loader indiriyor.
- iPXE: PXE'nin daha yetenekli versiyonu. HTTP, iSCSI, FCoE gibi protokolleri biliyor. Script yazılabiliyor.
- TFTP (Trivial File Transfer Protocol): UDP tabanlı, güvenliksiz, sadece dosya transferi. Ağ boot için yeterli.
- dnsmasq: Tek bir araçta DHCP + TFTP sunucusu. Lab ortamı için ideal, enterprise'da ayrı servisler kullanılır.
- next-server: DHCP'nin "boot dosyaları şu sunucudan al" dediği alan. TFTP server'ın IP'si buraya giriyor.
- Preseed / autoinstall / cloud-init: PXE boot sonrası kurulumu otomatize eden konfigürasyon formatları. Ubuntu'da autoinstall kullanılıyor.

## Kendi Notum
Şöyle düşün: yeni bir çalışan işe başladı ve bilgisayarına bir şey kurulmamış. IT departmanı ona "şu ağa bağlan" diyor, bilgisayar ağa bağlanınca IT'nin sunucusunu buluyor, oradan işletim sistemi indiriliyor ve otomatik kuruluyor. Çalışanın hiçbir şey yapmasına gerek yok. PXE Boot tam bunu yapıyor.

Teknik olarak NIC firmware önce DHCP'e "IP ver" diyor, DHCP IP'yi ve TFTP sunucusunun adresini veriyor, NIC TFTP'den iPXE'yi indiriyor, iPXE çalışınca artık HTTP yapabiliyor ve oradan OS imajını + kurulum configini alıyor. Bundan sonrası autoinstall'ın işi.

## Karşılaştığım Hatalar
Fiziksel donanım olmadığı için PXE boot'u gerçek ortamda test edemedim. Komutlar `pxe-boot/komutlar.sh`'da belgelenmiş.

Teorik olarak en yaygın sorunlar şunlar: dnsmasq ile mevcut bir DHCP çakışması (ağda router'ın DHCP'si varsa konflikt çıkar), TFTP dosya izin sorunları (`/var/lib/tftpboot` 644 olmalı), ve HTTP üzerinden imaj URL'si yanlış yazılınca iPXE "file not found" ile donuyor.

## Kaynaklar
- iPXE resmi döküman: https://ipxe.org/docs
- dnsmasq PXE kurulumu: https://wiki.archlinux.org/title/Dnsmasq
- Ubuntu autoinstall + PXE: https://ubuntu.com/server/docs/install/netboot-amd64
