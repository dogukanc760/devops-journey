# 📝 Notlar

## Neden var?
Linux'ta gelen/giden her ağ paketi çekirdeğin içinden geçer. iptables bu geçişi kontrol eder, "şu IP'den gelen paketi kabul et, şu porta gideni reddet, şunu başka yere yönlendir". K8s'in kube-proxy'si de arka planda iptables kuralları yazarak Service->Pod yönlendirmesini yapar. Bunu bilmeden K8s networking'i kör yönetirsin.

3 temel table var:
filter: Kabul et/reddet (INPUT, OUTPUT, FORWARD)
nat: Adres çeviri (PREROUTING, POSTROUTING) - DNAT/SNAT burası.
mangle: Paket header'ını değiştir (nadiren kullanırız).

5 Temel Chain:
INPUT: Bu makineye gelen paketler.
OUTPUT: Bu makineden çıkan paketler.
FORWARD: Bu makineden geçen paketler (router gibi).
PREROUTING: Bu makineye girmeden önce (DNAT burada).
POSTROUTING: Bu makineden çıkmadan önce (SNAT ve Masquerade burada).

## Anahtar Kavramlar
- Table/Chain ayrımı: Table "ne yapıyoruz" (filter, nat, mangle), chain "ne zaman" (INPUT, PREROUTING vs.). Kural yazarken ikisini birden belirtmek gerekiyor.
- PREROUTING önce çalışır: Gelen paket makineye girmeden önce PREROUTING chain'i geçer, orada DNAT yapılır, sonra INPUT chain karar verir. Bu sıra değiştirilemez.
- `-j ACCEPT / DROP / DNAT / MASQUERADE`: Kuralın sonunda ne yapılacağı. ACCEPT geç, DROP sessizce düşür, REJECT hata mesajıyla reddet.
- K8s KUBE-SERVICES chain'i: kube-proxy her Service için otomatik iptables kuralı yazar. `iptables -t nat -L KUBE-SERVICES` ile görülür.
- Rule sırası önemli: iptables kuralları yukarıdan aşağı işlenir, ilk eşleşen kazanır. Geniş bir ACCEPT kuralı üste yazılırsa DROP kuralı çalışmaz.

## Kendi Notum
Bu iptables yapısı, askeriyedeki nizamiyeye benzer. Nasıl ki askeri bir karargaha girerken nizamiye çavuşu, geçip geçemeyeceğimizi, veya geçersek nereye gidebileceğimizi, girerken kimlik verip çıkarken de kimlik verebilir gibi kontrol eder.

Pratik olarak şöyle anlatırdım: diyelim ki bir K8s servisine gelen istek nereye gidiyor merak ediyorsun. `sudo iptables -t nat -L KUBE-SERVICES -n -v` yazıyorsun ve ClusterIP adresine yapılan isteklerin KUBE-SVC-xxx chain'ine gittiğini, oradan KUBE-SEP-xxx chain'lerine dağıtıldığını yani pod IP'lerine DNAT yapıldığını görüyorsun. Load balancing aslında iptables kurallarıdır, görünmez ama oradadır.

Örnek kural ekleme:
```bash
# 8080 portuna sadece 10.0.1.5'ten erişim
sudo iptables -A INPUT -p tcp --dport 8080 -s 10.0.1.5 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8080 -j DROP
```

## Karşılaştığım Hatalar
k3d node içinde iptables kurallarını görmeye çalıştım ama k3d container'lar içinde iptables read-only geliyordu. `sudo iptables -t nat -L KUBE-SERVICES -n -v` komutunu Mac üzerinde doğrudan çalıştırmak mümkün değil. Gerçek Linux node'u veya VM gerekiyor. Teorik olarak geçtik, bare-metal veya VM lab'ında yapılacak.

Ayrıca kural eklerken önce ACCEPT sonra DROP yazmazsan, DROP kuralı ACCEPT'i kapsıyor gibi görünse de sıra önemli. Test ederken bunu gözden kaçırmak kolay.

## Kaynaklar
- iptables man page: `man iptables`
- K8s iptables proxy mode: https://kubernetes.io/docs/concepts/services-networking/service/#proxy-mode-iptables
- Netfilter proje sayfası: https://www.netfilter.org/
