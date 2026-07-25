# 📝 Notlar

## Neden var?
Cluster'ında bir şeyler yavaş, disk mi, CPU mu yoksa memory mi? Bunu bilmeden nereye bakacağını bilemezsin. Bu araçlar Linux'un iç organlarını okumaya yarar. vmstat genel sistem durumuna bakar, iostat disk I/O'ya odaklanır, sar ise geçmişe dönük metrik toplar. Bu üçü olmadan "yavaş" diyip oturursun, hangisinin yavaş olduğunu bilemezsin.

## Anahtar Kavramlar
- vmstat: Her 1 saniyede sistem genelini verir. r = run queue (kaç process CPU bekliyor), b = blocked, swpd = swap kullanımı, wa = iowait. `swpd > 0` ise memory yetersiz, `wa > 10` ise disk darboğazı var demektir.
- iostat: Disk I/O'ya özel. tps (saniyedeki transfer), kB_read/s, kB_wrtn/s, %iowait. K8s başlarken yüksek write normal.
- sar: Geçmişe dönük metrik. `-u` CPU, `-r` memory, `-d` disk. Log dosyalarından da okuyabilir.
- iowait: CPU'nun disk beklemesi. 10'dan yüksekse storage class'ı veya diski değiştir.
- run queue (r): Kaç process CPU sırası bekliyor. 4'ten yüksekse CPU darboğazı, node sayısını artır veya pod limit koy.

## Kendi Notum
Agam bak, bir pod sürekli yavaş ve sen ne olduğunu anlamaya çalışıyorsun. Önce vmstat ile genel bakış atıyorsun, swpd 0 mı wa kaçta diyor. Sonra iostat ile "aa bu disk saniyede yalnızca 50 tps yapıyor, PVC'nin oturduğu storage class mı yavaş?" diye bakıyorsun. Sar ile de "sabah 3'te ne oldu?" diye geçmişe bakabiliyorsun. Bu üç araç bir arada kullanınca bir node'un neden yavaşladığını 5 dakikada anlarsın, yoksa körlemesine pod'u restart edersin bir şey çözmez.

Not: k3d node'ları Alpine tabanlı minimal image, bu araçlar orada yüklü gelmiyor. Ubuntu pod açıp orada çalıştırmak lazım:
```
kubectl run metrics-test --image=ubuntu --restart=Never -it -- bash
apt update && apt install -y procps sysstat
```

## Karşılaştığım Hatalar
k3d node içinde `vmstat` deyince "command not found" aldım çünkü k3d node'ları Alpine tabanlı ve minimal. `procps` ve `sysstat` paketleri yüklü değil. Çözüm: Ubuntu pod açıp orada çalıştırdım. Ayrıca `sar` ilk çalıştırmada "Cannot open /var/log/sysstat/sa..." gibi hata verir çünkü sysstat servisi daha veri toplamaya başlamamış olabilir, `sar -u 1 5` ile anlık bakılabilir.

## Kaynaklar
- man vmstat: `man vmstat`
- Sysstat proje sayfası: https://github.com/sysstat/sysstat
- Linux Performance Analysis: https://brendangregg.com/linuxperf.html
