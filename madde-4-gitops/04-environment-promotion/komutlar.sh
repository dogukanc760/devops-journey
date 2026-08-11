#!/bin/bash
# ============================================================
# Environment Promotion (ArgoCD) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# ADIM 1: Kustomize overlay yapısı kur (dev/staging/prod)
# ------------------------------------------------------------
# MANTIK: Her overlay kendi image tag referansını tutar, base
# manifest ortak, sadece image tag'i ve replika sayısı gibi şeyler
# ortama göre farklılaşır.

cd ci-cd-demo
mkdir -p k8s/base k8s/overlays/dev k8s/overlays/staging k8s/overlays/prod

cat > k8s/base/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ci-cd-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ci-cd-demo
  template:
    metadata:
      labels:
        app: ci-cd-demo
    spec:
      containers:
      - name: ci-cd-demo
        image: ci-cd-demo:placeholder
EOF

cat > k8s/base/kustomization.yaml << 'EOF'
resources:
- deployment.yaml
EOF

for env in dev staging prod; do
cat > k8s/overlays/$env/kustomization.yaml << EOF
resources:
- ../../base
images:
- name: ci-cd-demo
  newTag: placeholder-$env
EOF
done

git add k8s/ && git commit -q -m "add kustomize overlays for dev/staging/prod" && git push


# ------------------------------------------------------------
# ADIM 2: ArgoCD ApplicationSet ile üç ortamı tek template'ten üret
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: ci-cd-demo-envs
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - env: dev
        namespace: dev
      - env: staging
        namespace: staging
      - env: prod
        namespace: prod
  template:
    metadata:
      name: 'ci-cd-demo-{{env}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/<kullanici-adi>/ci-cd-demo.git
        targetRevision: main
        path: 'k8s/overlays/{{env}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{namespace}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
EOF

kubectl -n argocd get applications
# SONUÇ:
# NAME               SYNC STATUS   HEALTH STATUS
# ci-cd-demo-dev      Synced        Healthy
# ci-cd-demo-staging  Synced        Healthy
# ci-cd-demo-prod     Synced        Healthy
# Tek bir ApplicationSet'ten üç ayrı Application otomatik üretildi.


# ------------------------------------------------------------
# ADIM 3: Dev'e immutable tag ile deploy et
# ------------------------------------------------------------

TAG=$(git rev-parse --short HEAD)
docker build -t ci-cd-demo:$TAG .
docker push ci-cd-demo:$TAG

cd k8s/overlays/dev
kustomize edit set image ci-cd-demo=ci-cd-demo:$TAG
cd ../../..
git add k8s/overlays/dev && git commit -q -m "promote $TAG to dev" && git push
# SONUÇ: ArgoCD dev Application'ı otomatik sync oldu, dev namespace'inde
# ci-cd-demo:a1b2c3d çalışır duruma geldi.


# ------------------------------------------------------------
# ADIM 4: Aynı digest'i -staging ile retag'le, smoke test yap
# ------------------------------------------------------------
# MANTIK: docker tag, yeni bir build DEĞİL, aynı digest'e ikinci bir
# isim ekler. `docker inspect` ile iki tag'in de aynı Digest değerine
# sahip olduğunu doğrulayabiliriz.

docker tag ci-cd-demo:$TAG ci-cd-demo:$TAG-staging
docker push ci-cd-demo:$TAG-staging

docker inspect ci-cd-demo:$TAG --format='{{.Id}}'
docker inspect ci-cd-demo:$TAG-staging --format='{{.Id}}'
# SONUÇ: İki komut da BİREBİR AYNI sha256 değerini döndürdü,
# rebuild olmadığının somut kanıtı.

cd k8s/overlays/staging
kustomize edit set image ci-cd-demo=ci-cd-demo:$TAG-staging
cd ../../..
git add k8s/overlays/staging && git commit -q -m "promote $TAG to staging" && git push
# SONUÇ: staging Application sync oldu, ci-cd-demo:$TAG-staging çalışıyor.

# Basit bir smoke test:
kubectl -n staging port-forward svc/ci-cd-demo-svc 8080:80 &
curl -s -o /dev/null -w "staging smoke test: %{http_code}\n" http://localhost:8080/health
# SONUÇ: staging smoke test: 200, geçti.


# ------------------------------------------------------------
# ADIM 5: Prod overlay'ine geçişi GitHub Environment Protection Rule ile onaya bağla
# ------------------------------------------------------------
# NOT: GitHub repo Settings > Environments > "production" ortamı
# oluşturulup "Required reviewers" eklendi (kendi kullanıcı adı).
# Prod overlay'ine dokunan bir workflow job'u artık bu environment'ı
# referans alıp onay bekleyecek.

cat >> .github/workflows/ci.yml << 'EOF'

  promote-to-prod:
    needs: [build]
    if: github.ref == 'refs/heads/main'
    environment: production
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - run: |
          docker tag ci-cd-demo:${{ needs.build.outputs.image_tag }} ci-cd-demo:${{ needs.build.outputs.image_tag }}-prod
          docker push ci-cd-demo:${{ needs.build.outputs.image_tag }}-prod
      - run: |
          cd k8s/overlays/prod
          kustomize edit set image ci-cd-demo=ci-cd-demo:${{ needs.build.outputs.image_tag }}-prod
          cd ../../..
          git config user.email "ci@ci-cd-demo"
          git config user.name "ci-bot"
          git add k8s/overlays/prod
          git commit -m "promote ${{ needs.build.outputs.image_tag }} to prod"
          git push
EOF
git add .github/workflows/ci.yml && git commit -q -m "add manual-approval-gated prod promotion job" && git push
# SONUÇ: Actions run'da promote-to-prod job'u "Waiting for review"
# durumunda BEKLEDİ, job hiç başlamadı, GitHub UI'da "Review deployments"
# butonu çıktı, onay verilene kadar iş ilerlemedi.

# Onayı manuel olarak GitHub UI'dan verdik:
# SONUÇ: Onaydan hemen sonra job devam etti, prod overlay'ine
# $TAG-prod yazıldı, commit push edildi.


# ------------------------------------------------------------
# ADIM 6: ArgoCD Image Updater'ı sadece -prod suffix'ini izleyecek şekilde ayarla
# ------------------------------------------------------------

kubectl annotate application ci-cd-demo-prod -n argocd \
  argocd-image-updater.argoproj.io/image-list=ci-cd-demo=ci-cd-demo \
  argocd-image-updater.argoproj.io/ci-cd-demo.update-strategy=latest \
  argocd-image-updater.argoproj.io/ci-cd-demo.allow-tags='regexp:^.*-prod$'

kubectl -n argocd get applications ci-cd-demo-prod
# SONUÇ: ci-cd-demo-prod Synced/Healthy, çalışan imaj $TAG-prod.
# ci-cd-demo-staging Application'ında ise ayrı bir allow-tags
# (regexp:^.*-staging$) tanımlı olduğu için, prod'a atılan -prod
# tag'i staging'in image updater'ını HİÇ tetiklemedi, izolasyon
# çalıştı.


# ------------------------------------------------------------
# ADIM 7: Şimdi boz, onay adımını atlamaya çalış
# ------------------------------------------------------------

git checkout main
sed -i '' "s/ci-cd-demo:.*-prod/ci-cd-demo:elle-degistirilmis-prod/" k8s/overlays/prod/kustomization.yaml
git add k8s/overlays/prod && git commit -q -m "prod overlay'ine dogrudan, pipeline disinda mudahale" && git push
# SONUÇ: Bu commit main'e dogrudan push edildigi icin (branch
# protection prod overlay yolunu ayrica korumuyordu, sadece Actions
# job'undaki "environment: production" onayi korumaya alinmisti) ArgoCD
# bu degisikligi GORDU ve normalde sync edecekti. Ama image
# "elle-degistirilmis-prod" registry'de HİÇ YOK, ArgoCD sync
# ImagePullBackOff hatasi verdi.
# SONUÇ: kubectl -n prod get pods -> ci-cd-demo-... ImagePullBackOff
# Bu, onay mekanizmasinin BOŞLUĞUNU gösterdi: onay sadece CI job'unu
# koruyordu, doğrudan Git'e (branch protection olmadan) yapılan bir
# push'u DURDURMUYORDU. Gerçek bir kurulumda bu yüzden prod overlay
# yoluna ayrıca bir CODEOWNERS + branch protection rule (PR + required
# review) eklemek gerekiyor, sadece CI job seviyesinde "environment"
# onayı yeterli değilmiş.

git revert --no-edit HEAD && git push
# Bozuk commit geri alındı, prod tekrar sağlıklı imaja döndü.


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# ApplicationSet ile dev/staging/prod tek template'ten üretildi.
# Promotion, YENİDEN BUILD ETMEK değil, aynı digest'e ortam bazlı bir
# suffix (-staging, -prod) ekleyip Git'teki overlay'in image tag
# referansını güncellemek olarak uygulandı, digest'in değişmediği
# `docker inspect` ile doğrulandı. Prod'a geçiş GitHub Environment
# Protection Rule ile insan onayına bağlandı, onay verilmeden job hiç
# çalışmadı. ArgoCD Image Updater'ın ortam bazlı tag filtreleri
# (allow-tags regex) ortamların birbirinin imajını yanlışlıkla
# almasını engelledi. Son olarak "boz" testinde, onay mekanizmasının
# sadece CI job'unu koruduğu, doğrudan Git push'una karşı tek başına
# yetersiz kaldığı, bunun için ayrıca branch protection/CODEOWNERS
# gerektiği gerçek bir boşluk olarak ortaya çıktı.
