# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Kubernetes'te varsayılan davranış şu: bir pod ayağa kalktığı anda cluster içindeki her pod ile serbestçe konuşabilir, hiçbir kısıtlama yoktur. Bu "içeride herkes güvenilir" varsayımına dayanır. Container'lardan biri bir güvenlik açığı üzerinden ele geçirilirse, saldırgan o pod'dan cluster'daki her yere serbestçe sıçrayabilir (lateral movement). Bu olmasaydı ne olurdu diye sorarsak: bir tane zayıf halka, tüm sistemi tehlikeye atardı.

Temel:

Zero-Trust: "kimseye güvenme, herkesi doğrula" prensibi, içeride de dışarıda da geçerli
eBPF: Linux çekirdeğinde çalışan, paketi kullanıcı alanına çıkarmadan kernel içinde filtreleyen teknoloji
Standart K8s NetworkPolicy: sadece IP/port seviyesinde (L3/L4) çalışır
Cilium'un CiliumNetworkPolicy'si: HTTP metod/path seviyesinde (L7) çalışır, çünkü araya Envoy proxy koyup trafiği gerçekten okur
Default-deny: önce her şeyi kapat, sonra ihtiyaç oldukça tek tek izin aç
Hubble: Cilium'un gözlemlenebilirlik katmanı, hangi pod hangi pod'a ne zaman bağlandığını gerçek zamanlı gösterir

Senaryo: Frontend pod'un hiç ilgisi olmayan bir "billing-db" pod'una bağlanması gerekmiyor ama varsayılan K8s'te bunu engelleyen hiçbir şey yok. Biri frontend'i ele geçirirse doğrudan billing-db'ye sızabilir.

Örnek Soru:
Diyelim ki Cilium'u kurdun ve default-deny policy'sini aktif ettin, artık hiçbir pod birbirine bağlanamıyor. Şimdi frontend'in sadece backend'e, backend'in sadece database'e erişmesi gerekiyor. Bunu nasıl bir sırayla yapılandırırsın, yani default-deny'ı açtıktan hemen sonra sırada ne var, neden o sırayla?

Cevap:
NetworkPolicy (ya da CiliumNetworkPolicy) ile çözülür, db'ye sadece backend'den, backend'e sadece frontend'den izin verilir. İki kritik detay var. Birincisi, kurallar IP adresine değil label selector'a göre yazılır (app: backend gibi), çünkü pod'lar sürekli ölüp yeniden doğuyor ve her seferinde yeni IP alıyor, IP bazlı kural pod restart olunca anlamsız kalır. İkincisi, her policy hem kimin bu kurala tabi olduğunu (podSelector) hem yönünü (ingress/egress) ayrı tanımlar, db pod'una "sadece backend label'lı pod'lardan gelen ingress'e izin ver" denir, backend'e de "sadece frontend'den gelen ingress'e izin ver" denir. Sıralama şöyle işler: önce default-deny taban çizgisi olarak durur, üstüne bu iki spesifik allow kuralı eklenir, çünkü NetworkPolicy'ler additive'dir (toplanır).

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- Zero-Trust: klasik firewall mantığı dışarıyı korur, içeride herkese güvenir. Bir pod ele geçirilirse firewall'ın arkasında serbestçe yayılır (lateral movement). Zero-Trust bunun çözümü, içeride de kimseye güvenme.
- eBPF: iptables kullanıcı alanına çıkıp kural listesini sırayla kontrol eder, yavaştır. eBPF paketi kernel içinde, kullanıcı alanına hiç çıkmadan karara bağlar, hem çok daha hızlı hem çok daha detaylı filtreleme yapabilir.
- Default-deny felsefesi: her ihtiyacı önceden tek tek hesaplamak yerine, önce her şeyi kapat, gerçek ihtiyaçlar zamanla ortaya çıktıkça tek tek aç. Daha az karmaşık ve daha güvenli.
- L3/L4 vs L7: standart K8s NetworkPolicy (herhangi bir CNI'de) sadece IP/port seviyesinde (L3/L4) çalışır, "kiminle konuşabilirsin" sorusuna cevap verir. Cilium'un CiliumNetworkPolicy'si Envoy proxy'yi araya koyarak HTTP isteğinin içeriğini okur (L7), "ne konuşabilirsin" sorusuna cevap verir (örn. GET'e izin ver, DELETE'i reddet), aynı IP/port üzerinden gitmesine rağmen. Bu, standart bir firewall'un asla yapamayacağı bir ayrım.
- Hubble: Cilium'un gözlemlenebilirlik katmanı, adını Hubble teleskobundan alıyormuş gibi düşünülebilir, "gözlemleme/observation" için var. Hangi isteğin FORWARDED hangi isteğin DROPPED olduğunu gerçek zamanlı gösterir.
- Policy ihlali alerting: gerçek bir Slack workspace'i olmadığı için, `hubble observe`'un DROPPED çıktısını yakalayıp gerçek bir Slack webhook'una göndermek yerine aynı mantığı (satırı yakala, zaman damgalı bir alert üret) yerel bir `policy-violations.log` dosyasına yazacak şekilde kurguladık. Slack'e POST atan kısım koda hazır ama yorum satırı, gerçek bir webhook geldiğinde direkt açılabilir.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Bizim klasik firewall'larımızın mantığı dışarıya karşı güvende tutayım, içerisi zaten bizim güvenilir şeklinde. Ama bu noktada içeride bir pod bir şekilde ele geçirilirse çöker, çünkü o firewall'ın direkt arkasında her şeye serbestçe erişip bütün sistemi ele geçirebilir. Bu sebeple pod'lar aynı network namespace'de olsa dahi birbirine yüzde yüz güvenmiyoruz, hatta hiç güvenmiyoruz. Bunu da CNI seviyesinde, kullanıcı alanına çıkmadan, çok temelde dipte bir yerde çözmek istiyoruz ki iptables'a takılmadan, yılanın başını küçükken ezelim. İşte bu tekniğin adı Zero-Trust Network.

Bunun için Cilium CNI ile Container Network Interface'imizi kurduk ve varsayılan olarak default-deny tanımladık, sebebi de şu: tek tek hepsini önceden hesaplamak yerine, kim nerede ne kullanacak ihtiyaç oldukça açmayı seçtik, çünkü hem daha az karmaşık hem de gerçek ihtiyaçlar kendi kendine ortaya çıkacak. Ek olarak kullanıcı alanının altında, iptables'a hiç gelmeden çok hızlı hallettiğimiz için bu çözüm kernel seviyesinde çalışıyor, hızlı çalışıyor, teknik adı eBPF.

Bunu gözlemlemek için de Cilium'a entegre olan Hubble UI'yi kullandık, adı Hubble teleskobundan geliyor, gözlem/observation için.

Eksik bıraktığım nokta şuydu: default-deny ve IP/port bazlı izin aslında Cilium olmadan da (herhangi bir CNI'de standart NetworkPolicy ile) yapılabilirdi. Cilium'u asıl özel kılan, aynı IP/port üzerinden giden bir isteğin içine bakıp "GET'e izin ver ama DELETE'i reddet" diyebilmesi (L7), bunu Envoy proxy ile HTTP'yi gerçekten okuyarak yapıyor, iptables bunu asla yapamaz çünkü sadece paket başlığına bakar.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
Cilium'u ilk kurduğumda cilium ve cilium-operator pod'ları Init:Error durumunda takıldı. kubectl describe pod ile baktığımda config init container'ının KUBERNETES_SERVICE_HOST değerinin 0.0.0.0 göründüğünü ve API server'a bağlanamadığını gördüm. Sebep bir tavuk yumurta problemiydi, Cilium kube-proxy'siz modda kuruluyor, yani kubernetes Service'inin ClusterIP'sine giden yolu normalde kube-proxy programlar ama bu iş Cilium'a devredilmiş, Cilium henüz ayağa kalkmadığı için kendi başlaması için gereken API server bağlantısını bulamıyor. Çözüm, cilium install'a --set k8sServiceHost ve --set k8sServicePort ile API server'ın gerçek adresini (k3d'de server container'ının adı, aynı Docker network'ünde DNS ile çözülüyor) açıkça vermek oldu. Yarım kalan bir uninstall denemesi de cilium-secrets namespace'ini terminating durumunda kitledi, cluster'ı silip temiz baştan kurmak en hızlı çözüm oldu.
## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- 
