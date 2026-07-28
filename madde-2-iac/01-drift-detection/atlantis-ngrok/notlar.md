# 📝 Notlar — Atlantis + ngrok

## Neden var?
Drift Detection'ı otomatikleştirmenin pratik hali bu ikisi. Atlantis, GitHub'da açılan bir PR'ı görüp otomatik `terraform plan` çalıştırıp sonucu PR'a yorum olarak yazan bir araç, elle `terraform plan` çalıştırmana gerek kalmıyor, kod review sürecinin bir parçası oluyor. Ama Atlantis GitHub'dan webhook alabilmesi için dışarıdan (internetten) erişilebilir bir adrese ihtiyaç duyuyor. Benim local Mac'im `localhost:4141`'de çalışıyor, GitHub'ın sunucuları oraya giremiyor. ngrok bu ikisi arasına geçici bir köprü kuruyor: local portu geçici bir public URL'e bağlıyor.

Bu olmasaydı: her PR'da elle `terraform plan` çalıştırıp çıktıyı kopyala yapıştır PR'a yazmak zorunda kalırdım, ekip büyüdükçe bu sürdürülemez olur, biri unutur, drift fark edilmeden merge olur.

## Anahtar Kavramlar
- Atlantis, repo içindeki her `.tf` dosyası olan klasörü ayrı bir "proje" gibi ele alıyor. PR'da birden fazla klasör değiştiyse, her biri için ayrı ayrı plan çalıştırıyor (bizim örnekte `01-drift-detection` ve `01-drift-detection/atlantis-server` iki ayrı proje olarak planlandı).
- Atlantis'in webhook doğrulaması iki katmanlı: (1) GitHub imza header'ı (HMAC secret ile), (2) `ATLANTIS_REPO_ALLOWLIST`. Repo bu listede değilse istek 403 ile reddediliyor, imza doğru olsa bile.
- ngrok her ücretsiz oturumda farklı bir URL veriyor. Yani ngrok'u kapatıp tekrar açarsan, GitHub webhook'undaki eski URL geçersiz kalır, tekrar güncellemek gerekir.
- ngrok sadece geliştirme/test amaçlı bir araç. Prod ortamında Atlantis, herkesin (veya sadece GitHub/GitLab'ın) erişebileceği sabit bir public adreste (K8s Ingress, sabit bir sunucu, vs.) barındırılır, ngrok'a hiç gerek kalmaz.
- `docker compose logs` her zaman `docker-compose.yml`'ın bulunduğu klasörden çalıştırılmalı, yoksa "no configuration file provided" hatası alınır.
- GitHub'ın secret scanning push protection özelliği, bir commit içinde tanıdığı formatta bir credential (örneğin GitHub PAT) görürse push'u tamamen engelliyor. Bu koruma sadece dosya adına değil, dosyanın (binary dahil) içeriğine bakıyor.

## Kendi Notum
Atlantis kalıcı bir araç, gerçek CI/CD pipeline'ının parçası olacak şey. ngrok ise sadece bugün, benim local Mac'im internete kapalı olduğu için ihtiyaç duyduğum geçici bir yardımcı, GitHub'ın "webhook'u nereye göndereyim" sorusuna geçici bir cevap. Prod'da Atlantis bir sunucuda/cluster'da sabit bir adreste çalışır, ngrok tamamen devre dışı kalır.

Süreç boyunca en çok öğrendiğim şey: bir entegrasyonun çalışmaması "tek bir sebep" değil, katman katman debug edilmesi gereken bir zincir. Önce isteğin hedefe ulaşıp ulaşmadığına (ngrok/network), sonra hedefin isteği kabul edip etmediğine (secret/imza), sonra hedefin isteği işleyip işlemediğine (allowlist) bakmak gerekiyor. Her katmanda farklı bir hata mesajı, farklı bir çözüm var.

İkinci büyük ders secret sızıntısı yaşadığımızda geldi. Atlantis'in kendi çalışma verisini (BoltDB, `atlantis.db`) tuttuğu `atlantis-data` klasörünü hiç düşünmeden git'e commit'lemiştim. O dosyanın içinde `ATLANTIS_GH_TOKEN` olarak verdiğim GitHub PAT saklı duruyormuş. GitHub'ın push protection'ı bunu commit içeriğinde tanıyıp push'u tamamen durdurdu. Bunu State Management konusunda konuştuğumuz "state dosyası hassas veri içerebilir" meselesiyle aynı kefeye koyabilirim: sadece Terraform state değil, herhangi bir aracın local çalışma verisi de (Atlantis'in BoltDB'si gibi) credential taşıyabiliyor, hepsi `.gitignore`'da olmalı.

## Karşılaştığım Hatalar

**1. `docker compose logs atlantis` → "no configuration file provided: not found"**
Sebep: `docker-compose.yml`'ın olduğu `atlantis-server/` klasöründe değildim.
Çözüm: `cd atlantis-server` sonra komutu tekrar çalıştırdım.

**2. `ngrok http 4141` → `zsh: command not found: ngrok`**
Sebep: ngrok hiç kurulu değildi.
Çözüm: `brew install ngrok`, sonra `ngrok config add-authtoken <TOKEN>` (ücretsiz hesap açıp dashboard'dan token alındı).

**3. GitHub webhook Recent Deliveries → "Invalid HTTP Response: 400"**
Atlantis log: `"msg":"missing signature"`
Sebep: GitHub webhook ayarlarında Secret alanı boş bırakılmıştı. GitHub, Secret alanı doluysa isteğe imza (HMAC) ekliyor, boşsa hiç eklemiyor. Atlantis ise `ATLANTIS_GH_WEBHOOK_SECRET` set edildiği için imza zorunlu tutuyor, imzasız isteği reddediyor.
Çözüm: `.env` dosyasındaki `WEBHOOK_SECRET` değerini GitHub webhook'unun Secret alanına aynen yapıştırdım.

**4. PR push sonrası webhook → "403 Forbidden"**
Atlantis log: `"pull request event from non-allowlisted repo 'github.com/dogukanc760/devops-journey'"`
Sebep: `docker-compose.yml`'daki `ATLANTIS_REPO_ALLOWLIST` hâlâ örnek/placeholder değeri (`github.com/KULLANICI_ADIN/terraform-drift-demo`) tutuyordu, gerçek repo adıyla (`github.com/dogukanc760/devops-journey`) eşleşmiyordu.
Çözüm: `ATLANTIS_REPO_ALLOWLIST` değerini gerçek repo yoluna güncelledim, `docker compose down` ve `docker compose --env-file .env up -d` ile yeniden başlattım.

**5. `git push` → GitHub "GH013: Repository rule violations found" (secret scanning push protection)**
Sebep: `atlantis-server/atlantis-data/atlantis.db` (Atlantis'in BoltDB dosyası) yanlışlıkla commit'lenmişti, içinde `ATLANTIS_GH_TOKEN` olarak verdiğim GitHub Personal Access Token saklıydı. GitHub bunu commit içeriğinde tanıyıp push'u engelledi.
Çözüm: Push henüz remote'a gitmediği için (reddedildi) token dışarı sızmadı.
1. `.gitignore`'a `atlantis-data/` ve `.env` eklendi.
2. `git rm -r --cached atlantis-server/atlantis-data` ile dosya git index'inden çıkarıldı (diskte kaldı).
3. İlk denemede yanlış path verdiğim için (`madde-2-iac/01-drift-detection/...` yerine sadece `atlantis-server/atlantis-data` olmalıydı, zaten o klasörün içindeydim) `git restore --staged` sessizce başarısız oldu ve dosya tekrar commit'e girdi. `git rm -r --cached` ile net bir şekilde tekrar denedim.
4. `git commit --amend --no-edit` ile son commit'i dosya olmadan yeniden yazdım, sonra push ettim.

**Sonuç:** Beş katmanlı hata zincirini (yanlış klasör, ngrok eksik, secret eksik, allowlist yanlış, secret sızıntısı) tek tek çözünce PR'da Atlantis'in otomatik plan yorumu başarıyla geldi: "Plan: 1 to add, 0 to change, 0 to destroy."

## Kaynaklar
- Atlantis resmi döküman: https://www.runatlantis.io/docs/
- Atlantis repo allowlist: https://www.runatlantis.io/docs/server-configuration.html#repo-allowlist
- Atlantis webhook secrets: https://www.runatlantis.io/docs/webhook-secrets.html
- ngrok döküman: https://ngrok.com/docs
- GitHub push protection: https://docs.github.com/code-security/secret-scanning/working-with-secret-scanning-and-push-protection/working-with-push-protection-from-the-command-line
