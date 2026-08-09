#!/bin/bash
# ============================================================
# Git Ortamı için Secret Yönetimi (SOPS / Sealed Secrets) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# BÖLÜM A: SOPS
# ------------------------------------------------------------

# ------------------------------------------------------------
# ADIM 1: sops ve age kur, key çifti üret
# ------------------------------------------------------------
# MANTIK: age, PGP'ye göre çok daha basit bir asimetrik sifreleme
# aracı. age-keygen bir public/private key cifti uretir, public key
# ile sifrelenir, private key ile cozulur.

brew install sops age

age-keygen -o age-key.txt
cat age-key.txt
# SONUÇ (gerçek çıktı):
# # created: 2026-08-09T20:46:25+03:00
# # public key: age1ykmq5qpw700654ah5prgeqa0rv7lanqmuqlhfd3g5srxfq7jd3ysuj0kpa
# AGE-SECRET-KEY-1RZJF3Y6GLSLP8Z8L3R8SSUN3SV6VCNCGPJZQ46NNLCV78KVDR8EQZEV39Z

export SOPS_AGE_KEY_FILE="$(pwd)/age-key.txt"
AGE_PUBLIC_KEY=$(grep "public key" age-key.txt | cut -d: -f2 | tr -d ' ')
echo "AGE_PUBLIC_KEY=$AGE_PUBLIC_KEY"
# SONUÇ: AGE_PUBLIC_KEY=age1ykmq5qpw700654ah5prgeqa0rv7lanqmuqlhfd3g5srxfq7jd3ysuj0kpa


# ------------------------------------------------------------
# ADIM 2: Şifrelenecek sahte bir secret dosyası oluştur
# ------------------------------------------------------------
# MANTIK: Bu bir Terraform tfvars, Ansible group_vars, ya da düz
# bir config dosyası olabilir, SOPS format bağımsız çalışır.

cat > secrets.yaml << 'EOF'
db_username: admin
db_password: cok-gizli-sifre-123
api_key: sk-test-abcdef123456
EOF

cat secrets.yaml
# Şifrelemeden önceki hali: her şey düz metin.


# ------------------------------------------------------------
# ADIM 3: Dosyayı şifrele, key'lerin düz value'ların şifreli kaldığını gözle
# ------------------------------------------------------------

sops --encrypt --age "$AGE_PUBLIC_KEY" secrets.yaml > secrets.enc.yaml

cat secrets.enc.yaml
# SONUÇ (gerçek çıktı):
# db_username: ENC[AES256_GCM,data:l3AFR1o=,iv:...,tag:...,type:str]
# db_password: ENC[AES256_GCM,data:SS2esr/+XKJxNdsMjrK4k4ZFOw==,iv:...,tag:...,type:str]
# api_key: ENC[AES256_GCM,data:S9ptKJ9LuqMgVRUz2hJRhAd5baw=,iv:...,tag:...,type:str]
# sops:
#     age:
#         - enc: |
#             -----BEGIN AGE ENCRYPTED FILE-----
#             ...
#             -----END AGE ENCRYPTED FILE-----
#           recipient: age1ykmq5qpw700654ah5prgeqa0rv7lanqmuqlhfd3g5srxfq7jd3ysuj0kpa
#     lastmodified: "2026-08-09T17:47:15Z"
#     mac: ENC[...]
#     unencrypted_suffix: _unencrypted
#     version: 3.13.3
# Key'ler (db_username, db_password, api_key) tamamen okunabilir kaldı,
# sadece value'lar şifrelendi, tam beklenen davranış.


# ------------------------------------------------------------
# ADIM 4: Şifreyi çöz, orijinaline döndüğünü doğrula
# ------------------------------------------------------------

sops --decrypt secrets.enc.yaml
# SONUÇ (gerçek çıktı, ADIM 2'deki orijinalle birebir aynı):
# db_username: admin
# db_password: cok-gizli-sifre-123
# api_key: sk-test-abcdef123456


# ------------------------------------------------------------
# ADIM 5: Şifreli dosyayı GERÇEKTEN Git'e commit et, düz metnin hiç girmediğini doğrula
# ------------------------------------------------------------
# MANTIK: secrets.yaml (düz metin) ASLA commit edilmemeli,
# .gitignore'a eklenmeli. secrets.enc.yaml (şifreli) commit edilebilir.
# Pratik Görevler listesindeki ".env dosyasını encrypt et, Git'e
# commit et" maddesi için bu adımın gerçekten çalıştırılması gerekiyor.

mkdir -p sops-demo && cd sops-demo
git init -q
echo "secrets.yaml" > .gitignore
echo "age-key.txt" >> .gitignore
cp ../secrets.enc.yaml .
git add secrets.enc.yaml .gitignore
git commit -q -m "encrypted secrets via SOPS"
git show --stat HEAD
git show HEAD -- secrets.enc.yaml
# Beklenen: commit içeriğinde sadece ENC[...] bloklarını görürsün,
# "cok-gizli-sifre-123" gibi düz metin hiçbir yerde geçmez, reviewer
# bile gerçek şifreyi göremez. git log'da secrets.yaml (düz metin) hiç
# görünmez çünkü .gitignore'da.

cd ..


# ------------------------------------------------------------
# BÖLÜM B: Sealed Secrets
# ------------------------------------------------------------

# ------------------------------------------------------------
# ADIM 6: Sealed Secrets controller'ı cluster'a kur
# ------------------------------------------------------------
# MANTIK: Controller kendi private/public key çiftini cluster
# içinde üretir, sadece bu cluster bu private key'e sahip olur.

k3d cluster create sealed-secrets-cluster
kubectl create namespace kube-system 2>/dev/null || true

kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.1/controller.yaml

kubectl get pods -n kube-system -l name=sealed-secrets-controller
# SONUÇ (gerçek çıktı, CRD/RBAC kurulumu tam listelendi):
# clusterrole.rbac.authorization.k8s.io/secrets-unsealer created
# customresourcedefinition.apiextensions.k8s.io/sealedsecrets.bitnami.com created
# ...
# deployment.apps/sealed-secrets-controller created
# NAME                                         READY   STATUS              RESTARTS   AGE
# sealed-secrets-controller-846d677755-bh52h   0/1     ContainerCreating   0          0s


# ------------------------------------------------------------
# ADIM 7: kubeseal CLI'ı kur
# ------------------------------------------------------------
# NOT: Bu ortamda kubeseal zaten kuruluydu, brew install/version
# çıktısı ayrıca doğrulanmadı, doğrudan ADIM 9'a geçildi.

brew install kubeseal

kubeseal --version


# ------------------------------------------------------------
# ADIM 8: Normal bir K8s Secret manifesti yaz (apply ETME)
# ------------------------------------------------------------

cat > db-secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
  namespace: default
type: Opaque
stringData:
  password: cok-gizli-sifre-123
EOF


# ------------------------------------------------------------
# ADIM 9: kubeseal ile SealedSecret'e çevir
# ------------------------------------------------------------
# MANTIK: kubeseal, controller'ın public key'ini cluster'dan otomatik
# çeker (--fetch-cert de edilebilir), bu key ile şifreler. Çıktı
# artık normal bir Secret değil, SealedSecret CRD'si, Git'e güvenle
# commit edilebilir.

kubeseal --format=yaml < db-secret.yaml > db-sealed-secret.yaml

cat db-sealed-secret.yaml
# SONUÇ (gerçek çıktı, kısaltılmış):
# apiVersion: bitnami.com/v1alpha1
# kind: SealedSecret
# metadata:
#   name: db-secret
#   namespace: default
# spec:
#   encryptedData:
#     password: AgBwJEu0HVXI0fKhJ/TIuhLcF1QP4DHEBC1+PjBmvjMLZdAybLZuVMN6gQE4b1uz... (uzun şifreli string)
#   template:
#     metadata:
#       name: db-secret
#       namespace: default
#     type: Opaque
# Düz metin şifre hiçbir yerde görünmedi, tam beklenen.


# ------------------------------------------------------------
# ADIM 10: SealedSecret'i apply et, gerçek Secret'a dönüştüğünü doğrula
# ------------------------------------------------------------

kubectl apply -f db-sealed-secret.yaml

kubectl get sealedsecret db-secret
kubectl get secret db-secret -o jsonpath='{.data.password}' | base64 -d
# SONUÇ (gerçek çıktı):
# sealedsecret.bitnami.com/db-secret created
# NAME        AGE
# db-secret   0s
# cok-gizli-sifre-123
# Controller SealedSecret'i görüp otomatik olarak gerçek bir Secret'a
# çevirdi, decode edilince orijinal şifre eksiksiz çıktı.


# ------------------------------------------------------------
# ADIM 11: Şimdi boz, aynı SealedSecret'i private key'i olmayan bir cluster'a uygula
# ------------------------------------------------------------
# MANTIK: Her cluster'ın Sealed Secrets controller'ı kendi private
# key'ini üretir. Aynı şifreli SealedSecret'i başka (ya da yeniden
# kurulmuş, dolayısıyla yeni private key üretmiş) bir cluster'a
# verirsek, o cluster bu şifreyi çözemez.

k3d cluster delete sealed-secrets-cluster
k3d cluster create sealed-secrets-cluster-2
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.1/controller.yaml
kubectl get pods -n kube-system -l name=sealed-secrets-controller
# Yeni cluster, yeni private key üretti.

kubectl apply -f db-sealed-secret.yaml
kubectl get secret db-secret
kubectl logs -n kube-system -l name=sealed-secrets-controller --tail=20
# SONUÇ (gerçek çıktı, beklenenle birebir uyuştu):
# sealedsecret.bitnami.com/db-secret created
# Error from server (NotFound): secrets "db-secret" not found
# ...controller loglarında:
# level=INFO msg=Updating key=default/db-secret
# level=INFO msg="Event(...): type: 'Warning' reason: 'ErrUnsealFailed'
#   Failed to unseal: no key could decrypt secret (password)"
# level=ERROR msg="Error updating, will retry" key=default/db-secret
#   error="no key could decrypt secret (password)"
# ... (birkaç retry sonrası)
# level=ERROR msg="Error updating, giving up" key=default/db-secret
#   error="no key could decrypt secret (password)"
# Yeni cluster'ın controller'ı kendi yeni private key'ini ürettiği
# için eski cluster'ın public key'iyle şifrelenmiş SealedSecret'i
# çözemedi, birkaç kez retry etti, sonunda "giving up" deyip vazgeçti.
# Gerçek Secret hiçbir zaman oluşmadı. Sealed Secrets'ın cluster'a
# sıkı sıkıya bağlı güven sınırının somut kanıtı.


# ------------------------------------------------------------
# BÖLÜM C: CI Pipeline'da SOPS decrypt (simülasyon)
# ------------------------------------------------------------

# ------------------------------------------------------------
# ADIM 12: CI pipeline'ın yapacağı decrypt adımını lokal olarak simüle et
# ------------------------------------------------------------
# NOT: Gerçek bir GitHub Actions/GitLab CI ortamı kurulu değil, bu
# yüzden CI pipeline'ın YAPACAĞI ADIMI birebir aynı şekilde (private
# key'i bir ortam değişkeninden okuyup decrypt etme) lokal bir script
# ile GERÇEKTEN çalıştırıyoruz. Mantık, gerçek bir CI runner'da da
# birebir aynı olurdu, tek fark key'in nereden geldigi (CI secret store).

cat > ci-decrypt-simulation.sh << 'EOF'
#!/bin/bash
# Gerçek bir CI pipeline'da bu script bir job step'i olurdu, private
# key CI'nin kendi secret store'undan (GitHub Actions secrets,
# GitLab CI variables vb.) SOPS_AGE_KEY ortam değişkenine enjekte edilir.
set -e
if [ -z "$SOPS_AGE_KEY" ]; then
  echo "HATA: SOPS_AGE_KEY ortam değişkeni set değil, CI'da secret olarak tanımlanmalı"
  exit 1
fi
export SOPS_AGE_KEY
sops --decrypt sops-demo/secrets.enc.yaml > decrypted-for-deploy.yaml
echo "Decrypt başarılı, uygulama deploy edilmeye hazır."
EOF
chmod +x ci-decrypt-simulation.sh

# Gerçek bir CI runner'da secret nasıl enjekte edilirse, biz de private
# key'i ortam değişkenine koyup script'i çalıştırıyoruz:
export SOPS_AGE_KEY=$(grep AGE-SECRET-KEY age-key.txt)
./ci-decrypt-simulation.sh
cat decrypted-for-deploy.yaml
# Beklenen: "Decrypt başarılı..." mesajı ve ardından düz metin secret
# içeriği, CI'nin decrypt adımının gerçekten çalıştığının kanıtı.

rm -f decrypted-for-deploy.yaml  # CI'da da decrypt edilmiş dosya kalıcı tutulmaz


# ------------------------------------------------------------
# BÖLÜM D: SealedSecret'i Git'e push et, ArgoCD'nin deploy etmesini izle
# ------------------------------------------------------------

# ------------------------------------------------------------
# ADIM 13: Basit bir git sunucusu (Gitea) ve ArgoCD kur
# ------------------------------------------------------------
# NOT: Gerçek bir GitHub/GitLab remote'u yerine, ayni GitOps mantığını
# uçtan uca göstermek için lokalde bir Gitea (hafif, kendi git sunucun)
# container'ı ayağa kaldırıyoruz. ArgoCD bu repo'yu izleyip sync edecek.

docker run -d --name gitea -p 3000:3000 -p 2222:22 gitea/gitea:latest
sleep 10
# İlk kurulum: http://localhost:3000 üzerinden tarayıcıda tek seferlik
# "Install Gitea" adımını tamamla (admin kullanıcı oluştur), ya da
# gitea admin CLI ile otomatik kurulum yapılabilir.

# ArgoCD'yi sealed-secrets-cluster-2'ye kur:
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl -n argocd get pods
# Beklenen: argocd-server, argocd-repo-server, argocd-application-controller vb. Running


# ------------------------------------------------------------
# ADIM 14: Gitea'da bir repo oluştur, SealedSecret'i push et
# ------------------------------------------------------------

cd sops-demo
git remote add gitea http://localhost:3000/<gitea-kullanici>/gitops-secrets-demo.git
cp ../db-sealed-secret.yaml .
git add db-sealed-secret.yaml
git commit -q -m "add sealed secret for argocd"
git push gitea main
cd ..
# Beklenen: push başarılı, Gitea repo'sunda db-sealed-secret.yaml görünür.


# ------------------------------------------------------------
# ADIM 15: ArgoCD Application tanımla, sync'lenip deploy ettiğini gözle doğrula
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitops-secrets-demo
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://gitea.gitea.svc.cluster.local:3000/<gitea-kullanici>/gitops-secrets-demo.git
    targetRevision: main
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

kubectl -n argocd get application gitops-secrets-demo
kubectl get sealedsecret db-secret
kubectl get secret db-secret
# Beklenen: ArgoCD Application "Synced/Healthy" durumuna geçer,
# repo'daki SealedSecret otomatik apply edilir, controller onu gerçek
# bir Secret'a çevirir, tüm zincir (Git commit -> ArgoCD sync -> K8s
# apply -> Sealed Secrets decrypt) elle hiçbir kubectl apply olmadan
# tamamlanmış olur.


# ------------------------------------------------------------
# BÖLÜM E: SOPS + Terraform, tfvars dosyasını şifreli tut
# ------------------------------------------------------------

# ------------------------------------------------------------
# ADIM 16: Bir terraform.tfvars dosyasını SOPS ile şifrele, plan/apply öncesi çöz
# ------------------------------------------------------------
# MANTIK: Terraform, düz metin bir tfvars dosyası bekler, SOPS'un
# şifreli formatını doğrudan okuyamaz. Bu yüzden akış şu: şifreli
# halini Git'e commit et, apply etmeden HEMEN önce decrypt edip
# Terraform'un okuyacağı düz dosyayı üret, apply bitince düz dosyayı sil.

cat > terraform.tfvars << 'EOF'
db_admin_password = "cok-gizli-tfvars-sifre-789"
EOF

sops --encrypt --age "$AGE_PUBLIC_KEY" terraform.tfvars > terraform.tfvars.enc

cat terraform.tfvars.enc
# Beklenen: "db_admin_password" key'i düz, value'su ENC[...] şifreli.

git -C sops-demo add ../terraform.tfvars.enc 2>/dev/null || true

# Apply öncesi decrypt (gerçek bir CI/CD pipeline'da bu bir stage olurdu):
sops --decrypt terraform.tfvars.enc > terraform.tfvars
cat terraform.tfvars
# Beklenen: düz metin geri geldi, artık `terraform plan/apply` bu
# dosyayı normal bir tfvars gibi okuyabilir.

rm -f terraform.tfvars  # apply bitince düz dosya diskte kalmamalı


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# SOPS: dosya bazlı, key backend'i (age/PGP/KMS) key'e erişimi olan
# HERKESİN çözebileceği şekilde çalışır, K8s'e bağımlı değil, Git'e
# şifreli haliyle commit edilir, decrypt için canlı bir sunucuya
# ihtiyaç yok.
# Sealed Secrets: K8s'e özel, sadece o cluster'ın controller'ı
# (private key sahibi) çözebilir, başka cluster'da decrypt imkansız,
# bu da onu "bu secret sadece bu cluster'a ait" senaryolarında daha
# sıkı bir güven sınırı yapar.
# CI pipeline: decrypt adımı sadece private key'in CI'nin kendi secret
# store'undan geldiği bir ortam değişkeni farkıyla, lokal decrypt ile
# birebir aynı mantık.
# ArgoCD + Gitea: GitOps zincirinin ucu, Git'e commit/push edilen
# SealedSecret'i insan hiç kubectl apply çalıştırmadan otomatik olarak
# cluster'a taşır, "her şey Git'ten deploy edilsin" prensibinin somut
# hali.
# Terraform + SOPS: tfvars dosyası Terraform'un anlayacağı formatta
# olmak zorunda olduğu için şifreli halde tutulup, apply'dan hemen önce
# decrypt edilip hemen sonra silinir, düz metin diskte kalıcı olmaz.
