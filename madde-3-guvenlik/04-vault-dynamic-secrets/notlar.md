# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Normalde bir uygulamanın DB'ye bağlanmak için ihtiyaç duyduğu kullanıcı adı/şifre ya kod içine ya da bir K8s Secret'a statik olarak yazılır ve bu sır aylarca hatta yıllarca değişmeden aynı kalır. Bu olmasaydı ne olurdu diye sorarsak, bu statik sır bir şekilde sızarsa (git'e yanlışlıkla commit, log'a basılması, bir makineye sızılması) sızıntı fark edilene kadar tamamen geçerli kalırdı, üstelik tüm pod'lar/servisler aynı şifreyi paylaştığı için sızıntının kaynağını (hangi pod, hangi servis, ne zaman) ayırt etmek neredeyse imkansız olurdu.

Temel:

- Vault: merkezi bir sır deposu, statik saklamanın ötesinde dinamik sır üretebilen bir sistem
- Database secrets engine: Vault'un bir DB'ye admin yetkisiyle bağlanıp kullanıcı açıp kapatmasını sağlayan eklenti
- Dinamik sır (dynamic secret): her istekte sıfırdan üretilen, biricik (unique), kısa ömürlü (TTL'li) kullanıcı adı/şifre
- Lease: üretilen her dinamik sırın bir kimliği (lease_id) ve ömrü (TTL, default_ttl/max_ttl) vardır, süre dolunca ya da elle revoke edilince otomatik silinir
- Revocation statements: TTL dolduğunda veya elle revoke edildiğinde Vault'un DB'ye çalıştıracağı temizlik SQL'i, boş bırakılırsa plugin'in kendi varsayılanı (Postgres'te DROP ROLE IF EXISTS gibi) kullanılır

Örnek Soru:
Bir uygulamanın PostgreSQL'e bağlanması gerekiyor. Statik bir yaklaşımda DB kullanıcı adı/şifresini bir K8s Secret'a koyup pod'a mount edersin. Vault'un dinamik sır özelliğini kullanırsan bunun yerine ne olur, ve bu senin "biri bu şifreyi çaldı" senaryosundaki riskini nasıl değiştirir? Vault'un burada DB ile nasıl bir ilişkisi olması gerekir (sadece şifreyi saklamaktan farkı ne)?

Cevap:
Statik yaklaşımda Vault da olsa bir "kasa" gibi davranır, önceden oluşturulmuş bir kullanıcı adı/şifreyi saklar, isteyen gelip aynı şifreyi çeker, herkes aynı şifreyi paylaşır. Dinamik sırlarda Vault'un DB üzerinde kendi admin yetkisi vardır (database secrets engine ile yapılandırılır). Bir istemci sır istediğinde Vault, DB'ye kendi admin yetkisiyle bağlanıp o an için sıfırdan yeni bir kullanıcı açar, bu kullanıcıya bir TTL atar, biricik kullanıcı adı/şifreyi döner. Süre dolunca Vault otomatik olarak o kullanıcıyı DB'den siler. Risk açısından fark şu: statik senaryoda şifre çalınırsa biri fark edip elle rotate edene kadar sınırsız süre geçerlidir ve herkes aynı şifreyi kullandığı için kaynağı ayırt etmek zordur. Dinamik senaryoda her istemci kendi biricik kullanıcısını alır, sızsa bile TTL dolunca kendiliğinden ölür, şüphelenilirse elle de anında revoke edilebilir, ve her lease'in kendi kimliği olduğu için hangi lease'in hangi pod'a ait olduğu izlenebilir.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- database secrets engine, Vault'a sadece saklama değil, DB üzerinde CREATE ROLE/DROP ROLE çalıştırabilecek aktif bir admin yetkisi verir (database/config).
- roles (database/roles/...), Vault'un her credential isteğinde çalıştıracağı gerçek SQL'i (creation_statements) ve üretilen kullanıcının ömrünü (default_ttl, max_ttl) tanımlar.
- Her `vault read database/creds/<role>` çağrısı öncekinin cevabını tekrar vermez, her seferinde SIFIRDAN yeni, biricik bir kullanıcı üretir.
- `vault lease revoke` komutu "Success! Revoked" demez, "All revocation operations queued successfully!" der. Revoke İŞLEMİ ASENKRONDUR, komut kabul edildiğini söyler, gerçek DROP ROLE arka planda kısa bir süre sonra çalışır. Bunu `docker logs vault-dev` içinde `expiration: revoked lease: lease_id=...` satırıyla doğruladık.
- revocation_statements boş bırakılırsa (bizim durumumuzda öyleydi) postgresql-database-plugin kendi varsayılanını kullanır, bu genelde `DROP ROLE IF EXISTS "{{name}}"` gibi idempotent bir SQL'dir. Bu yüzden DB'deki kullanıcıyı Vault'a haber vermeden elle sildik, sonra revoke ettik, hiçbir hata çıkmadı, çünkü IF EXISTS zaten var olmayan bir rolü silmeye çalışmayı hataya çevirmiyor.
- Revoke edilmiş (tamamlanmış) bir lease için `vault lease lookup` "invalid lease" hatası verir. Bu bir arıza değil, tam tersi kanıt: lease tamamen temizlendiği için Vault'un kendi kayıtlarından da silinmiş, aranacak bir şey kalmamış demektir.
- Lease ID, hangi kullanıcı/pod'un hangi credential'ı ne zaman aldığını izlemeyi sağlar, bu da sızıntı sonrası "kaynağı bul" sürecini statik sırlara göre çok kolaylaştırır.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Ben DevOps ekibinin başıyım, sen yeni geldin, repolarda secret arıyorsun kendi lokal makinende infrayı test edip öğrenmek için ama bulamazsın, çünkü biz açık secret'ları repolarda tutmuyoruz, makinelerde ya da K8s'te açık açık yazmıyoruz, biri girip çözerse başımıza iş açar. Klasik statik bir Vault olsa bile o da çözülürse yine yandık, çünkü bütün pod'lar/kaynaklar aynı secret'ı kullanıyor olacak, kim, nereden geldi, çözemeyiz.

O yüzden Vault'u dynamic secret engine ve tanımlarıyla ihtiyaca göre kullanıyoruz. Diyelim bir API pod'u DB'ye bağlanacak, secret'ları o an bilmiyor ama kendi yetkisiyle ve önceden kurduğumuz zero-trust yaklaşımıyla güvenli bir şekilde Vault aracılığıyla o DB'ye bağlanmak için ihtiyaç duyduğu bilgileri `vault read` ile alır. Bunlar sonsuza kadar geçerli olmaz, Redis'teki gibi bir TTL'i vardır. Süre dolduğunda bile tekrar `vault read` ile gittiğimizde bize yeni kullanıcı bilgileri döner, biz de işe devam ederiz.

"Peki biri sızdı, o an ki dynamic secret'ı öğrendi, bize ne olur?" dersen: biz veya watcher'larımız fark edene kadar geçerli kalır ama TTL kısa olduğundan ve her lease bir ID'ye sahip olduğundan zafiyetin nereden geldiğini ayırt etmek kolay, diğer log/metriklerle birleştirip önüne geçeriz.

"Biz DB'den Vault'un ürettiği credential'ı elle sildik, o arada otomatik revoke çalıştı, bir şey olur mu?" dersen: bu tamamen revoke statement'ına bağlı, default boş bırakırsan DROP ROLE IF EXISTS gibi bir kural çalışır, sen kendi kuralını da verebilirsin. Biz gerçekten denedik: DB'de kullanıcıyı elle sildik, sonra `vault lease revoke` çalıştırdık, hiç hata almadık, log'da "revoked lease" olarak temiz şekilde kapandığını gördük, çünkü Vault'un varsayılan SQL'i zaten "var olmayan bir rolü silmeye çalışmak" durumuna karşı dayanıklı yazılmış.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
1. İlk `docker exec -it vault-postgres psql -U postgres -c "\du"` çağrılarında tablo çıktısı hiç görünmedi, sadece Docker'ın "What's next / Try Docker Debug" ipucu geldi. Gerçek bir hata değildi, terminal/kopyalama zincirinde `-it` (tty) çıktısının bir kısmı kayboldu, komut tek başına tekrar çalıştırılınca gerçek `\du` tablosu (role list) görüldü.
2. `vault lease revoke <lease_id>` komutu "Success! Revoked lease" DEĞİL, "All revocation operations queued successfully!" döndü. İlk bakışta hata gibi görünmedi ama beklenen mesajdan farklıydı, bu da revoke'un senkron değil asenkron çalıştığını gösterdi, `docker logs vault-dev` içindeki `expiration: revoked lease: lease_id=...` satırıyla gerçek tamamlanma zamanı doğrulandı.
3. DB'deki dinamik kullanıcıyı Vault'a haber vermeden elle `DROP ROLE` ile sildik, sonra aynı lease için `vault lease revoke` çalıştırdık, hiçbir hata çıkmadı. Sebep bir arıza değildi, revocation_statements boş bırakıldığı için plugin'in varsayılan `DROP ROLE IF EXISTS` SQL'i idempotent çalıştı, var olmayan bir rolü silmeye çalışmak Postgres'te hataya sebep olmadı.
4. Revoke edilmiş bir lease için `vault lease lookup <lease_id>` "invalid lease" hatası verdi. Bu da bir arıza değildi, lease tamamen temizlendiği için Vault'un kendi kayıtlarından silinmiş olması bekleniyordu, hata mesajı aslında işlemin başarıyla tamamlandığının kanıtıydı.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- HashiCorp Vault Database Secrets Engine resmi dokümantasyonu (postgresql-database-plugin, creation_statements, revocation_statements)
- HashiCorp Vault Lease, Renew, and Revoke kavramları dokümantasyonu
