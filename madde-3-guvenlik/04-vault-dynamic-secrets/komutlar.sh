#!/bin/bash
# ============================================================
# Dinamik Sır Yönetimi (HashiCorp Vault) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# ADIM 1: Vault ve Postgres'i ayağa kaldır (ayni network'te)
# ------------------------------------------------------------
# MANTIK: Vault dev mode'da otomatik unseal olur (root token elle
# verilir), production'da asla kullanilmaz ama lab icin pratik.
# Postgres, Vault'un uzerinde kullanici acip silecegi hedef DB.

docker network create vault-demo

docker run -d --name vault-dev --network vault-demo \
  -p 8200:8200 \
  -e VAULT_DEV_ROOT_TOKEN_ID=root \
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
  hashicorp/vault:latest

docker run -d --name vault-postgres --network vault-demo \
  -e POSTGRES_PASSWORD=postgres123 \
  -e POSTGRES_USER=postgres \
  postgres:16

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=root

vault status
# SONUÇ (gerçek çıktı):
# Seal Type       shamir
# Initialized     true
# Sealed          false
# Total Shares    1
# Threshold       1
# Version         2.0.4
# Storage Type    inmem
# HA Enabled      false


# ------------------------------------------------------------
# ADIM 2: Database secrets engine'i etkinleştir
# ------------------------------------------------------------
# MANTIK: Vault varsayılan olarak sadece statik key/value sır
# saklar (secret/ path'i). Dinamik DB kullanıcısı üretebilmesi için
# ayrı bir "database" secrets engine'i açıkça enable etmek gerekir.

vault secrets enable database
# SONUÇ: Success! Enabled the database secrets engine at: database/


# ------------------------------------------------------------
# ADIM 3: Vault'a Postgres'e kendi admin yetkisiyle bağlanmayı öğret
# ------------------------------------------------------------
# MANTIK: Vault'un DB'de yeni kullanıcı açıp silebilmesi için önce
# kendisinin DB'ye bir admin/root credential ile bağlanması lazım.
# Bu adımdan sonra Vault, Postgres üzerinde CREATE ROLE / DROP ROLE
# çalıştırabilecek yetkiye sahip olur.

vault write database/config/vault-postgres \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@vault-postgres:5432/postgres?sslmode=disable" \
  allowed_roles="readonly-role" \
  username="postgres" \
  password="postgres123"

# Doğrula:
vault read database/config/vault-postgres


# ------------------------------------------------------------
# ADIM 4: Rol tanımla (Vault ne kadar süreli, ne yetkili kullanıcı açsın)
# ------------------------------------------------------------
# MANTIK: creation_statements, Vault'un her credential isteğinde
# Postgres'e çalıştıracağı gerçek SQL'dir. {{name}} ve {{password}}
# Vault tarafından otomatik üretilip yerine konur. default_ttl,
# üretilen kullanıcının varsayılan ömrü, max_ttl ise uzatılsa bile
# aşamayacağı üst sınır.

vault write database/roles/readonly-role \
  db_name=vault-postgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="60s" \
  max_ttl="5m"

# Doğrula:
vault read database/roles/readonly-role


# ------------------------------------------------------------
# ADIM 5: Dinamik credential iste, gerçekten oluştuğunu gözle doğrula
# ------------------------------------------------------------
# MANTIK: Bu komut Vault'a "bana readonly-role'e uygun bir kullanıcı
# üret" der. Vault bu anda Postgres'e bağlanıp CREATE ROLE çalıştırır,
# biricik (unique) bir username/password döner, bir lease_id ile
# birlikte (bu lease_id sonradan elle iptal etmek için lazım).

vault read database/creds/readonly-role
# SONUÇ (gerçek çıktı):
# Key                Value
# ---                -----
# lease_id           database/creds/readonly-role/h5bsZKv8cg4OSHVefeZbFjG7
# lease_duration     1m
# lease_renewable    true
# password           qET2-3fg3mYPz4rdfR1Y
# username           v-token-readonly-gR34tYsGJtsnzUSLeFOr-1786288824

# Bu username/password'ü değişkene al (kendi çıktına göre elle de yazabilirsin)
# NOT: Bu komut vault read'i TEKRAR çağırdığı için Vault yeni, ikinci bir
# kullanıcı daha üretti (v-token-readonly-9MRFn8gCUPtHToZ3lUxD-1786288838),
# yani her "vault read database/creds/..." çağrısı her seferinde SIFIRDAN
# yeni bir kullanıcı demek, önceki çağrının cevabını tekrar vermiyor.
CREDS=$(vault read -format=json database/creds/readonly-role)
DB_USER=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['username'])")
DB_PASS=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['password'])")
LEASE_ID=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['lease_id'])")
echo "DB_USER=$DB_USER LEASE_ID=$LEASE_ID"
# SONUÇ: DB_USER=v-token-readonly-9MRFn8gCUPtHToZ3lUxD-1786288838
#        LEASE_ID=database/creds/readonly-role/PueCgNDfLc4q1eyN04gtLZYU

# Postgres içinde bu kullanıcının GERÇEKTEN açıldığını gözle doğrula:
docker exec -it vault-postgres psql -U postgres -c "\du"
# SONUÇ: DB_USER ile aynı isimde bir role listede göründü, gerçekten
# Vault tarafından CREATE ROLE ile açılmış.

# Bu kullanıcıyla gerçekten bağlanabildiğini de doğrula:
docker exec -e PGPASSWORD="$DB_PASS" vault-postgres psql -U "$DB_USER" -d postgres -c "SELECT current_user;"
# SONUÇ: current_user olarak DB_USER döndü.


# ------------------------------------------------------------
# ADIM 6: TTL dolunca kullanıcının kendiliğinden silindiğini gözle
# ------------------------------------------------------------
# MANTIK: default_ttl=60s verdiğimiz için Vault, lease süresi
# dolduğunda arka planda otomatik olarak DROP ROLE çalıştırır.
# Elle hiçbir şey yapmadan bu kullanıcı ortadan kalkmalı.

sleep 70
docker exec -it vault-postgres psql -U postgres -c "\du"
# SONUÇ: DB_USER artık listede yok, Vault süresi dolan lease'i kendisi
# fark edip DROP ROLE ile temizledi, elle hiçbir şey yapmadık.


# ------------------------------------------------------------
# ADIM 7: Elle erken iptal (revoke) senaryosu
# ------------------------------------------------------------
# MANTIK: Süre dolmasını beklemeden de "bu credential'dan şüpheleniyorum,
# hemen iptal et" diyebilmek lazım, gerçek bir sızıntı şüphesinde bu
# kritik. Yeni bir credential üretip bu sefer süresi dolmadan elle
# revoke ediyoruz.

CREDS2=$(vault read -format=json database/creds/readonly-role)
DB_USER2=$(echo "$CREDS2" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['username'])")
LEASE_ID2=$(echo "$CREDS2" | python3 -c "import sys,json; print(json.load(sys.stdin)['lease_id'])")
echo "DB_USER2=$DB_USER2 LEASE_ID2=$LEASE_ID2"
# SONUÇ: DB_USER2=v-token-readonly-m1kbGyxKQG1U8KyE06VH-1786288959
#        LEASE_ID2=database/creds/readonly-role/HIKlBYfu7cmf4D8d5gPMdDMN

docker exec -it vault-postgres psql -U postgres -c "\du"
# SONUÇ: DB_USER2 listede var, henüz süresi dolmadı.

vault lease revoke "$LEASE_ID2"
# SONUÇ (gerçek çıktı, tahmin ettiğimden farklı çıktı):
# "All revocation operations queued successfully!"
# NOT: Vault "Success! Revoked lease: ..." demiyor, revoke işlemini
# ASENKRON bir kuyruğa (queue) atıyor, komut hemen dönüyor ama
# gerçek DROP ROLE arka planda az sonra çalışıyor. Yani "queued"
# ile "revoked" ayrı şeyler, komutun dönmesi işin bittiği anlamına
# gelmiyor, kısa bir gecikme olabilir.

docker exec -it vault-postgres psql -U postgres -c "\du"
# SONUÇ: DB_USER2 artık listede yok, TTL dolmadan elle (revoke ile)
# silindi. Son \du çıktısında sadece "postgres" (superuser) kaldı:
#                              List of roles
#  Role name |                         Attributes
# -----------+------------------------------------------------------------
#  postgres  | Superuser, Create role, Create DB, Replication, Bypass RLS
# Yani her iki dinamik kullanıcı da (biri TTL ile, biri elle revoke ile)
# temizlendi, ortada Vault'un ürettiği hiçbir kalıntı kullanıcı kalmadı.


# ------------------------------------------------------------
# ADIM 8: Şimdi boz, Vault'a haber vermeden DB'de elle sil, sonra revoke et
# ------------------------------------------------------------
# MANTIK: revocation_statements'i hiç tanımlamadık (boş), yani
# Postgres plugin'i kendi varsayilan revoke SQL'ini kullaniyor.
# Soru: Vault'un haberi olmadan credential'i DB'den elle silersek,
# sonra ayni lease icin revoke istersek ne olur, hata mi verir?

CREDS3=$(vault read -format=json database/creds/readonly-role)
DB_USER3=$(echo "$CREDS3" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['username'])")
LEASE_ID3=$(echo "$CREDS3" | python3 -c "import sys,json; print(json.load(sys.stdin)['lease_id'])")
echo "DB_USER3=$DB_USER3 LEASE_ID3=$LEASE_ID3"
# SONUÇ: DB_USER3=v-token-readonly-tiyCCWcKFUNmizWzFhr9-1786289301
#        LEASE_ID3=database/creds/readonly-role/MEFV1pahjkRUXaeH68LcwNtf

# Vault'a hic haber vermeden DB'de elle sil:
docker exec -it vault-postgres psql -U postgres -c "DROP ROLE \"$DB_USER3\";"
# SONUÇ: DROP ROLE (basarili, rol elle silindi)

# Simdi Vault'a bu lease'i revoke etmesini soyle:
vault lease revoke "$LEASE_ID3"
# SONUÇ: "All revocation operations queued successfully!"
# Hicbir hata cikmadi, DB'de rol zaten yok olmasina ragmen.

# Perde arkasinda gercekten ne oldugunu Vault'un kendi loglarindan dogrula:
docker logs vault-dev --tail 20
# SONUÇ: "expiration: revoked lease: lease_id=database/creds/readonly-role/MEFV1pahjkRUXaeH68LcwNtf"
# hicbir error/warn yok, Vault revoke'u TAMAMEN basarili sayiyor.

# Ayni lease'i tekrar sorgulamayi dene:
vault lease lookup "$LEASE_ID3"
# SONUÇ: "error looking up lease id ...: Code: 400. Errors: * invalid lease"
# Bu bir ariza degil, tam tersi kanit: lease tamamen revoke edildigi
# icin Vault'un kendi lease store'undan da silinmis, aranacak bir sey
# kalmamis.

# SEBEP (arastirilip dogrulanan): revocation_statements bos birakildigi
# icin postgresql-database-plugin varsayilan olarak DROP ROLE IF EXISTS
# gibi idempotent bir SQL calistiriyor. Rol zaten yoksa bile IF EXISTS
# sayesinde Postgres hata firlatmiyor, Vault de bu SQL'in hatasiz
# donmesini "revoke basarili" olarak kabul ediyor. Yani Vault'un
# temizlik mekanizmasi, hedefin zaten silinmis olmasina karsi dayanikli
# (idempotent) tasarlanmis.


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# Akış: Vault'a Postgres'e kendi admin yetkisiyle bağlanmayı öğrettik
# (database/config) -> hangi SQL ile ne kadar ömürlü kullanıcı
# açılacağını tanımladık (database/roles) -> her istek anında Vault
# gerçekten yeni, biricik bir DB kullanıcısı üretti (database/creds)
# -> süre dolunca ya da elle revoke edince Vault bu kullanıcıyı
# kendisi sildi. Statik bir Secret'tan fark: sır burada Vault'ta
# saklı bir şey değil, ihtiyaç anında üretilen ve kısa ömürlü olan
# bir şey.
