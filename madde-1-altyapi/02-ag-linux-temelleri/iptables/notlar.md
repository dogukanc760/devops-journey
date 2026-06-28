# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Linuxta gelen/giden her ağ pakedi çekirdeğin içinden geçer. Iptables bu geçişi kontrol eder, "şu IP'den gelen pakedi kabul et, şu porta gideni reddet, şunu başka yere yönlendir". K8s'in kube-proxy'si de arka planda iptables kuralları yazarak Service->Pod yönlendirmesini yapar. Bunu bilmeden K8s networkingi kör edersiniz.

Temel:
3 temel table var,
filter-> Kabul et/reddet(INPUT, OUTPUT, FORWARD)
nat-> adres çeviri(PREROUTING, POSTROUTING) - DNAT/SNAT burası.
mangle->paket headerını değiştir(nadiren kullanırız.)

5 Temel Chain:

INPUT-> Bu makineye gelen paketler,
OUTPUT-> Bu makineden çıkan paketler,
FORWARD-> Bu makineden geçen paketler(router gibi)
PREROUTING-> bu makineye girmeden önce(DNAT burada)
POSTROUTING-> bu makineden çıkmadan önce(SNAT ve Masquerade burada.)
## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
-  5 Temel Chain aslında keywordsleridir. 

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Örnek Use Case:
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v

### Kural ekle: 8080 portuna sadece 10.0.1.5'ten erişim
sudo iptables -A INPUT -p tcp --dport 8080 -s 10.0.1.5 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8080 -j DROP

### K8s DNAT kurallarını gör
sudo iptables -t nat -L KUBE-SERVICES -n -v

Bu iptables yapısı, askeriyede ki nizamiyeye benzer. Nasıl ki askeri bir karargaha girerken nizamiye çavuşu, geçip geçemeyeceğimizi, veya geçersek nereye gidebileceğimizi, girerken kimlik verip(örneğin bir httpcallda ki sessionId) çıkarkende kimlik verebilir gibi.

Ornek Soru:
PREROUTING ILE INPUT chain farkı nedir? Bir paket makineye geldiğinde önce hangisi çalışır?
Cevap:
Once Prerouting çalısmalıdır, çünkü bize gelen istek bir dış IP veya K8s içinde bir domain label adıyla gelecek. Bir yapının araya girip onu localde ki gitmek istediği adresin karşılıgında ki ip ile değiştirmesi lazım(Düz bir makinede bu direkt PREROUTING olabilirken bunu K8s de LoadBalancer veya NodePort aracılığı ile yaparız). Bu sebeple önce PREROUTING çalısır daha sonra iptables ise INPUT olup olamayacağını söyler makineye veya gerekiyorsa FORWARD eder.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- 
