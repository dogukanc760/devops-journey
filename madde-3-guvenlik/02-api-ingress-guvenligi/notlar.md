# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Cluster'In içini Zero-Trust ile ne kadar sıklaştırırsan sıklaştır, dışarıdan gelen trafiğin girdiği kapı(ingress) korunmazsa hepsi boşa gider. Bu kapıda üç ayrı tehdit var; birincisi hacim saldırısı(biri saniyede binlerce istek atıp sistemi çökertmeye çalışır, DDoS), ikincisi içerik saldırısı(SQL Injection, XSS gibi kötü niyetli payloadlar HTTP isteğinin içinde gizlenir.), üçünüsü ise kimlik sahteciliğidir(biri kendini gerçek bir client gibi göstermeye çalışır). Bu olmasaydı ne olurdu diye sorarsak; clusterın içi ne kadar güvenli olursa olsun, kapıdan istediği gibi giren biri iç güvenliği anlamsız kılardı.

Temel:
- Rate Limiting: Dakikada/saniyede N istek, bunu aşan clientlar geçici olarak reddedilir, DDoSa karşı ilk savunma hattı
- WAF(Web Application Firewall): HTTP isteğinin içeriğini bilinen saldırı imzalarına(SQL Injection, XSS, path travelsal) karşı tarar, uygulamaya hiç ulaşmadan reddeder.
- mTLS(mutual TLS): normal TLS'te sadece sunucu kimliğini kanıtlar, mTLS'te client de kendi sertifikasını sunar, iki taraf birbirini doğrular.
- NGINX Ingress/Treafik: rate limit ve temel filtreleme genelde ingress controller seviyesinde yapılır.
- Coraza: OWASP Core Rule Set'i K8s'e taşıyan, Cillium/Envoy ekosistemiyle uyumlu bir WAF motoru.

Örnek Soru:
Diyelim ki production'da bir servis çok yavaşladı, kullanıcılar timeout alıyor. Bunun rate limiting'in devreye girip meşru kullanıcıları da reddetmesinden mi, yoksa WAF'ın her isteği derinlemesine tarayıp gecikme yaratmasından mı, yoksa uygulamanın kendisinin mi yavaş olduğunu nasıl ayırt edersin, hangi loga/metriğe bakarsın?

Cevap:
Cillium + Hubble UI olduğundan eBPF seviyesinde bu poda/servise gelen istek sayısı beklenen trafiğin anormalk olarak üstünde mi d iye network monitoringe bakarım, şayet burası temizde sorun ya CPU spike yada RAM spike dadır. yine Grafana UI + Prometheus entegresi ile bu spike a sebep olan istek/işlem tespit edilir ve troubleshooting başlatılır.
İyi bir refleks, ama asıl ayırt edici sinyali eksik bıraktın: client'a dönen HTTP status code. Üç senaryonun her biri farklı bir kod bırakır, bu yüzden önce ingress/WAF loglarına bakmak, metrik dashboard'undan önce gelir.
Rate limiting devredeyse, reddedilen istekler 429 Too Many Requests döner, ingress controller (NGINX/Traefik) loglarında bunu direkt görürsün, "spike" değil "reddetme" durumudur. WAF bir isteği bloke ediyorsa 403 Forbidden döner ve genelde hangi kuralın (SQL injection imzası, XSS pattern'i vb.) tetiklendiğini log'a yazar. Eğer client hiç hata almıyor ama yanıt gerçekten yavaşsa (200 dönüyor ama geç dönüyor), o zaman WAF'ın kendi tarama gecikmesi (WAF genelde milisaniyeler seviyesinde ek gecikme yaratır, saniyeler değil) ya da gerçekten uygulama/altyapı kaynaklı bir yavaşlık söz konusudur, senin dediğin gibi Hubble ile trafik hacminin anormal olup olmadığına, Grafana+Prometheus ile CPU/RAM spike'ına bakmak bu noktada devreye girer. Yani sıralama şöyle işler: önce status code dağılımı (429 mu 403 mü 200 mi), sonra eğer 200 ise Hubble/Prometheus ile kaynak ve trafik analizi.
## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- Rate Limiting: Traefik Middleware'de average/burst olarak tanımlanır, limiti aşan istekler 429 Too Many Requests ile reddedilir. Gerçek testte (hey ile 200 istek, burst:20) ilk 20 istek geçti, 180'i reddedildi.
- WAF: imza tabanlı (libinjection gibi bilinen saldırı kalıplarını tanıyan motor) ve skor tabanlı (anomaly scoring, her şüpheli belirti puan ekler, eşik aşılınca reddedilir) iki katmanda çalışır. Kimliğe değil, isteğin taşıdığı içeriğe bakar.
- mTLS: normal TLS sadece sunucunun kimliğini kanıtlar, mTLS'te client de sertifika sunar, sunucu bunu kendi CA'sına karşı doğrular. Client sertifikası yoksa TLS handshake'in kendisi başarısız olur (certificate required alert), HTTP seviyesine hiç gelinmez.
- Ayırt edici sinyal HTTP status code'dur: 429 = rate limit, 403 = WAF, 200 ama yavaş = kaynak/uygulama sorunu.
- NGINX yerine Traefik, Coraza yerine OWASP ModSecurity CRS kullanıldı (aynı OWASP Core Rule Set), ortamda zaten var olan/daha stabil araçlarla aynı kavram gösterildi.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Evinin içinde her önlemi aldın, kameralar taktın, güvenlik tuttun, her odanın kapısını kapatıp kilitledin ve anahtarları sakladın (Zero-Trust), ama evin dış kapısı korumasız ve ardına kadar açıksa, isteyen istediği kadar istediği şiddette girip çıkar. API ve Ingress güvenliği bunun karşılığı: Rate Limiting, WAF ve mTLS.

Rate Limiting, birinin belirli bir süre içinde evine ne kadar girip çıkabileceğini söyler. WAF, birinin evine girerken üstünde ne taşıdığını kontrol eder, kimliğine değil taşıdığına bakar (silah/kötü niyetli payload var mı). mTLS ise karşılıklı tanışıklıktır, hem senin onu tanıman hem onun seni tanıması, parmak izi (sertifika) ile doğrulanır, tek taraflı değil.

Kıssadan hisse: iç güvenlik (Zero-Trust) ile dış kapı güvenliği (API/Ingress) birbirinin yerine geçmez, ikisi birlikte tam bir savunma oluşturur.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
1. WAF testinde SQL injection payload'ını tek tırnaklarla (`'`) terminale yazınca `curl` durum kodu `000` döndü, yani bağlantı hiç kurulamamış gibi göründü. Sebep WAF değil, shell'in URL içindeki tek tırnakları kendi quoting kurallarına göre yorumlayıp curl'e bozuk bir istek göndermesiydi. URL-encode edilmiş payload (`%27` vb.) ve `-v` ile doğrulanınca gerçek sonuç (403, libinjection ile SQL injection tespiti) ortaya çıktı.
2. mTLS testinde `kubectl port-forward -n kube-system svc/traefik 8443:8443` "Service traefik does not have a service port 8443" hatası verdi. Sebep, container'ın kendi entrypoint portu 8443 olsa da, Service seviyesinde bu port adı "websecure" olarak 443'e bağlanmıştı. `kubectl get svc ... -o jsonpath='{.spec.ports}'` ile doğrulanıp port-forward 8443:443 olarak düzeltildi.
3. Rate limiting testinden önce, Zero-Trust konusundan kalma `l7-allow-get-only` CiliumNetworkPolicy'si sadece `app=client` etiketli pod'lara izin veriyordu, Traefik'in trafiğini bloklayabilirdi, teste başlamadan önce silindi.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- Traefik Middleware/IngressRoute/TLSOption resmi dokümantasyonu
- OWASP ModSecurity Core Rule Set (CRS) dokümantasyonu
