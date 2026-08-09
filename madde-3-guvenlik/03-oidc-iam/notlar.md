# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Normalde bir K8s cluster'ına kim erişebilir sorusunun cevabı ya statik bir kubeconfig dosyasının elden ele dolaşması ya da herkesin aynı admin service account token'ını kullanmasıdır. Bu ölçeklenmez, biri işten ayrıldığında token'ı iptal etmek zor, kimin ne zaman ne yaptığını denetlemek imkansız, herkes aynı yetkiye sahipse en az yetki diye bir şey kalmaz. Bu olmasaydı ne olurdu diye sorarsak, işten ayrılan biri hâlâ cluster'a girebilirdi ya da bir junior mühendis yanlışlıkla production'da bir şeyi silebilirdi çünkü herkes admin yetkisindeydi.

Temel:

OIDC (OpenID Connect): merkezi bir kimlik sağlayıcı (Keycloak, Google, Dex) üzerinden kullanıcı kimliğini doğrulama standardı, K8s API server buna güvenip token'ı kabul eder
K8s RBAC: Role (namespace-scoped yetki tanımı), ClusterRole (cluster genelinde yetki), RoleBinding/ClusterRoleBinding (kimin hangi role sahip olduğu)
Service Account: pod'ların (insan değil, uygulamaların) K8s API'sine erişim kimliği
Least Privilege: birine ihtiyacı olandan fazla yetki verme
Audit logging: kim, ne zaman, hangi kaynağa, ne yaptı sorusunun cevabı, sonradan denetlenebilir kayıt

Örnek Soru:
Bir "readonly" kullanıcı rolü tanımlayacaksın, bu kullanıcı sadece pod'ları ve deployment'ları görebilsin ama hiçbirini silemesin, değiştiremesin. Bunu K8s RBAC'ta hangi iki kaynak üzerinden, hangi fiillerle tanımlarsın, ve bu kuralı belirli bir namespace'e mi yoksa cluster geneline mi uygularsın, neden?

Cevap:
İki ayrı kaynak grubu var çünkü pod'lar core API grubunda (apiGroups: [""]), deployment'lar ise apps grubunda (apiGroups: ["apps"]). Fiiller sadece okuma işlemleriyle sınırlı: ["get", "list", "watch"], hiçbir yerde create/update/patch/delete yok. Varsayılan olarak Role + RoleBinding (namespace-scoped) tercih edilir, çünkü least privilege prensibi sadece ihtiyacın olan yere der. Eğer bu yetkiyi birden fazla namespace'te tekrar tanımlamak istemiyorsan, yaygın bir pattern şu: ClusterRole tanımlarsın (yetki tanımı tek yerde yaşar) ama her namespace'e ayrı ayrı RoleBinding ile bağlarsın, böylece hem tekrar etmezsin hem her namespace bağımsız kontrol edilir. Gerçek cluster geneli erişim ancak o zaman ClusterRole + ClusterRoleBinding ile yapılır.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- OIDC: kimlik doğrulama (authentication), "bu kişi gerçekten iddia ettiği kişi mi" sorusuna cevap verir.
- RBAC: yetkilendirme (authorization), "bu kişi ne yapabilir" sorusuna cevap verir. İkisi tamamen ayrı katmanlar, biri diğerini otomatik sağlamaz. Token kabul edilmesi yetki verildiği anlamına gelmez, ayrıca RoleBinding gerekir.
- oidc-username-claim: JWT içindeki hangi alanın K8s kullanıcı adı sayılacağını belirler (Keycloak'ta genelde preferred_username).
- id_token vs access_token: K8s'in kabul ettiği id_token'dır, access_token değil.
- Çoklu rol tasarımı (readonly/dev/ops): least privilege tek bir rolle değil, sorumluluk seviyesine göre ayrı katmanlarda uygulanır. readonly sadece get/list/watch yapar. dev, pod/service/deployment üzerinde create/update/patch de yapabilir ama delete yapamaz, namespace-scoped Role'dür. ops ise delete dahil tüm operasyonel fiillere sahip ama secrets ve rbac.authorization.k8s.io kaynaklarına hiç erişemez, ClusterRole olarak tanımlanır çünkü operasyon genelde tek namespace'le sınırlı kalmaz. "Operasyon yapabilsin ama yetki sistemine dokunamasın" prensibi burada.
- Audit logging: level: Metadata sadece kim, ne zaman, hangi kaynağa, hangi fiili uyguladı bilgisini loglar, istek/cevap gövdesi yok. level: RequestResponse hem isteği hem cevabı tam gövdesiyle loglar, maliyetli olduğu için sadece kritik kaynaklara (burada pods) uygulanır, geri kalan her şey Metadata seviyesinde kalır. omitStages: [RequestReceived] gereksiz "istek geldi ama henüz işlenmedi" kaydını atlar.
- apiserver flag'leri (--oidc-*, --audit-policy-file) k3d'de sıcak değiştirilemez, sadece cluster create anında set edilir. Yeni bir flag eklemek (audit) cluster'ı yeniden kurmayı gerektirir, bu yüzden var olan OIDC flag'leri kaybolmasın diye aynı create komutunda tekrar verilir. Audit ile OIDC birbirinden bağımsız iki konu, sadece bu teknik zorunluluktan aynı komutta bir araya geliyorlar.
- ServiceAccount, insan kullanıcıdan (OIDC ile doğrulanan devuser) tamamen ayrı bir kimlik türüdür, pod'ların K8s API'sine erişimi için kullanılır. Bir pod'a ServiceAccount atanınca, pod kendi token'ını `/var/run/secrets/kubernetes.io/serviceaccount/token` yolundan okuyup API server'a "Authorization: Bearer" header'ıyla konuşur. Aynı Role (örneğin readonly) hem bir insana (RoleBinding ile) hem bir ServiceAccount'a (yine bir RoleBinding ile, subject.kind: ServiceAccount) bağlanabilir, RBAC'in Role tanımı kimin kullandığından bağımsızdır.

## Uçtan Uca Akış: Issuer Eşleşmesi Problemi (K8s + k3d + Keycloak)
<!-- Bu konunun asıl zor kısmı, adım adım -->
K8s API server bir token'ı kabul etmeden önce iki şeyi kontrol eder: JWT'nin imzası geçerli mi (Keycloak'un public key'iyle doğrulanır) ve JWT'nin içindeki "iss" (issuer) alanı, apiserver'a --oidc-issuer-url ile söylenen adresle birebir aynı string mi. Apiserver ayrıca bu issuer adresine kendisi HTTP ile ulaşıp OIDC discovery (/.well-known/openid-configuration) yapar.

Sorun şurada çıkıyor: apiserver bir k3d container'ının içinde çalışıyor. Host makineden (senin Mac'inden) Keycloak'a "localhost:8180" ile ulaşırsın, ama container'ın içinden "localhost" o container'ın kendisi demektir, Keycloak'a değil. Container'lar host makineye "host.k3d.internal" adresiyle ulaşabiliyor, k3d bunu otomatik CoreDNS'e enjekte ediyor.

Eğer token'ı "localhost:8180" üzerinden alırsan, JWT'nin içine "iss": "http://localhost:8180/realms/k8s-realm" yazılır. Ama apiserver'a "host.k3d.internal:8180" adresini söylersek, apiserver bu iki string'in (localhost vs host.k3d.internal) aynı olmadığını görüp token'ı reddeder, çünkü issuer string'leri tam eşleşmiyor, karakter karakter aynı olmaları gerekiyor.

Çözüm: hem host makineden hem k3d container'larından AYNI adresle (host.k3d.internal) Keycloak'a ulaşılabilmesini sağlamak. Bunun için host makinenin /etc/hosts dosyasına host.k3d.internal'i 127.0.0.1'e yönlendiren bir satır eklendi. Böylece hem token alırken hem apiserver doğrularken aynı issuer string'i kullanılıyor.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Cluster'a girişi statik kubeconfig dosyaları veya paylaşılan admin token'larla değil, gerçek bir kimlik sağlayıcı (Keycloak) üzerinden yönettik. Mantık iki ayrı katmanda çalışıyor: önce OIDC "bu kişi gerçekten devuser mi" sorusunu cevaplıyor (authentication), sonra RBAC "devuser ne yapabilir" sorusunu cevaplıyor (authorization). Token'ın kabul edilmesi hiçbir yetki vermiyor, RoleBinding olmadan devuser hiçbir şey yapamaz.

En can alıcı kısım, K8s API server'ın container içinden çalışması yüzünden çıkan "issuer eşleşmesi" sorunuydu: token'ı nereden aldığın (localhost mu host.k3d.internal mi) JWT'nin içine "iss" olarak yazılıyor, apiserver da bu string'i kendi bildiği issuer adresiyle karakter karakter karşılaştırıyor. İkisi aynı olmazsa token reddediliyor. Çözüm, hem host makineden hem k3d container'larından aynı adresle (host.k3d.internal, /etc/hosts'a eklenerek) Keycloak'a ulaşılmasını sağlamaktı.

Sonuçta devuser sadece default namespace'inde pod/deployment okuyabiliyor, silme veya başka namespace'e erişim deneyince Forbidden alıyor, tam istediğimiz least-privilege davranışı.

Bunun üstüne iki şey daha ekledik: birincisi tek bir readonly rolü yerine üç seviyeli bir yetki modeli (readonly, dev, ops), her biri bir öncekinin üstüne fiil ekliyor ama hiçbiri secrets veya rbac kaynaklarına dokunamıyor, çünkü "işini yap ama yetki sistemine dokunma" prensibi hepsinde geçerli. İkincisi audit logging: her isteğin kim tarafından, ne zaman, hangi kaynağa yapıldığı ayrı bir log dosyasına yazılıyor, pod'lar gibi kritik kaynaklarda isteğin/cevabın tam gövdesi tutuluyor, geri kalanında sadece özet (kim/ne/ne zaman) tutuluyor. Bu iki değişiklik cluster'ı yeniden kurmayı gerektirdi çünkü apiserver flag'leri sıcak değiştirilemiyor, OIDC ile audit'in kendisi aslında birbirinden bağımsız konular, sadece aynı cluster create komutunda bir araya geldiler.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
Bu konuda gerçek bir hataya düşülmedi, çünkü issuer eşleşmesi problemi (K8s API server'ın container içinden Keycloak'a farklı bir hostname ile ulaşması) önceden bilinip /etc/hosts düzeltmesiyle baştan engellendi. Normal şartlarda bu adım atlanırsa alınacak hata şu olurdu: apiserver token'ı "invalid issuer" veya benzeri bir mesajla reddederdi, ya da OIDC discovery adımı (host.k3d.internal'e host makineden erişilemediği için) timeout ile başarısız olurdu.
## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- Kubernetes OIDC Authentication resmi dokümantasyonu (kube-apiserver --oidc-* flag'leri)
- Keycloak kcadm.sh CLI referansı
- Kubernetes Auditing resmi dokümantasyonu (audit-policy.yaml, level: None/Metadata/Request/RequestResponse)
