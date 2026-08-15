# Vaka 01: Hastane Şubeleri için Hub-and-Spoke VPN Mimarisi

Durum: Üretimde çalışıyor (gerçek iş, MikroTik). İleride birlikte derinleştirilecek.

## Bağlam

Şirketin müşterisi olan hastaneler Türkiye'nin farklı bölgelerinde, hepsi kendi intranet'inde. Ofiste ikinci bir internet hattı var, bunun statik bir WAN çıkışı mevcut. Bu statik IP'yi merkez (hub) noktası olarak kullanan bir mimari kuruldu:

- Ofis MikroTik'inde bu statik dış IP'ye bind edilmiş yeni bir interface açıldı.
- IPSec IKEv2 ve SSTP ile VPN ayarlandı, self-signed sertifika sağlandı.
- Her hastane için ayrı bir "user" (secret) tanımlandı, yani her şubenin kendi kimliği var.
- Topoloji tersine çevrildi: ofis hastanelere bağlanmıyor, hastaneler ofise bağlanıp kendi kanalını açıyor (hub-and-spoke, spoke'lar bağlantıyı başlatıyor). Bu sayede hastane tarafında statik/bilinen bir IP'ye ihtiyaç kalmadı.
- Hastanelerin private IP aralıkları çakışabileceği için (birçoğu muhtemelen aynı 192.168.x.0/24 gibi aralıkları kullanıyor), gelen her hastane bağlantısına NAT, bazılarında ek olarak masquerade uygulandı.
- Gelen-giden her taraf sertifika sağlamak zorunda, yani mTLS'e benzer karşılıklı kimlik doğrulama var, tek taraflı değil.

Sonuç: VPN'i elle açıp kapatmaya gerek kalmadan, hastanelerde operasyonel işlemler doğrudan yapılabiliyor, operasyonel hız arttı.

## Roadmap ile bağlantısı

Bu vaka, Madde 3 (Ağ, Güvenlik ve Sır Yönetimi) içinde öğrenilen iki kavramın gerçek dünyadaki (K8s dışı, network seviyesinde) karşılığı:

- **mTLS** (02-api-ingress-guvenligi): orada K8s Ingress seviyesinde openssl ile kurulan mini CA zinciri, burada IPSec/IKEv2 seviyesinde sertifika bazlı karşılıklı doğrulama olarak karşımıza çıkıyor, aynı prensip (iki taraf da kimliğini kanıtlar) farklı bir katmanda uygulanmış.
- **Zero-Trust** (01-zero-trust-network): "kimseye güvenme, herkesi doğrula" prensibi burada da geçerli, IP/aralık çakışsa bile sertifikası olmayan biri içeri giremiyor.

## Ele Alınacaklar (ileride birlikte çözülecek)

- [ ] Bu manuel MikroTik konfigürasyonunu Infrastructure as Code'a (Terraform RouterOS provider ya da Ansible) taşımak, "bir hastane daha eklendiğinde tek komutla" seviyesine getirmek.
- [ ] Sertifika rotasyonu şu an nasıl yönetiliyor, otomatik mi elle mi? Süresi dolan bir sertifikanın fark edilmesi/yenilenmesi için bir süreç var mı?
- [ ] Gözlemlenebilirlik: hangi hastane ne zaman bağlandı/koptu, hangi tünelde anormal trafik var, bunları merkezi olarak (Prometheus/Grafana ile MikroTik metrikleri, ya da syslog toplama) izleyen bir katman var mı?
- [ ] Bir hastanenin sertifikası/secret'ı sızarsa (çalınırsa), bunu nasıl hızlıca revoke edip yeni bir kimlik dağıtırsın? (Madde 3'teki Vault dynamic secrets mantığıyla karşılaştırmalı düşünülebilir.)
- [ ] NAT/masquerade kurallarının hastane sayısı arttıkça (onlarca, yüzlerce) nasıl yönetileceği, kural karmaşıklığı bir eşiği geçince ne yapılır (örneğin merkezi bir IPAM/adres planlama ihtiyacı doğar mı)?
- [ ] Ofisteki tek statik WAN hattı tek nokta arıza (single point of failure) mı? Yedekli/failover bir ikinci hat senaryosu var mı, olmalı mı?
- [ ] Denetim/uyumluluk açısından (hastane verisi, KVKK gibi düşünülürse) bu VPN üzerinden geçen trafiğin loglanması ve saklanması nasıl yönetiliyor?
