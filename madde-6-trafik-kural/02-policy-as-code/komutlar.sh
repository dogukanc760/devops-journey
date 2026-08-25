#!/bin/bash
# ============================================================
# Policy as Code (Kyverno/OPA Gatekeeper) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# ADIM 1: Kyverno kurulumu
# ------------------------------------------------------------

helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno -n kyverno-system --create-namespace
kubectl -n kyverno-system get pods
# SONUÇ: kyverno-admission-controller, kyverno-background-controller,
# kyverno-cleanup-controller, kyverno-reports-controller Running.


# ------------------------------------------------------------
# ADIM 2: Audit modunda üç ClusterPolicy yaz
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-root-container
spec:
  validationFailureAction: Audit
  background: true
  rules:
  - name: check-runasnonroot
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "Container'lar root olarak calisamaz, runAsNonRoot: true zorunlu."
      pattern:
        spec:
          =(securityContext):
            =(runAsNonRoot): "true"
EOF

cat <<EOF | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-registries
spec:
  validationFailureAction: Audit
  background: true
  rules:
  - name: only-internal-registry
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "Imajlar sadece myregistry.internal registrysinden cekilebilir."
      pattern:
        spec:
          containers:
          - image: "myregistry.internal/*"
EOF

cat <<EOF | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: Audit
  background: true
  rules:
  - name: check-required-labels
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "app ve env label'lari zorunludur."
      pattern:
        metadata:
          labels:
            app: "?*"
            env: "?*"
EOF

kubectl get clusterpolicy
# SONUÇ: uc policy de "Audit" modunda ve READY=true gorundu.


# ------------------------------------------------------------
# ADIM 3: Audit raporunu incele - BEKLENENDEN FAZLA ihlal çıktı
# ------------------------------------------------------------

sleep 60  # background scan'in tum mevcut kaynaklari taramasi icin
kubectl get clusterpolicyreport
# SONUÇ: clusterpolicyreport'ta disallow-root-container icin 14 FAIL,
# restrict-registries icin 6 FAIL, require-labels icin 9 FAIL gorundu.
# Beklenenden fazla ihlal cikmasi, audit-once mantigina tam ihtiyac
# oldugunu somut olarak gosterdi, dogrudan Enforce'a gecilseydi bu 29
# kaynagin bir kismi bir sonraki deploy'da aniden reddedilecekti.

kubectl get clusterpolicyreport -o jsonpath='{.items[0].results[?(@.result=="fail")].resources[0].name}'
# SONUÇ: ihlal eden kaynaklardan biri "legacy-billing-worker" cikti,
# eski bir servis, uzun suredir root calisiyor ve hicbir env label'i yok.


# ------------------------------------------------------------
# ADIM 4: Registry kısıtlamasını Enforce'a al - İLK DENEME HATALI
# ------------------------------------------------------------

kubectl patch clusterpolicy restrict-registries --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'

# CI pipeline yeni bir build tetikledi, base image olarak public nginx kullaniyor:
docker build -t tracing-frontend:v10 -f Dockerfile.nginx .
kubectl apply -f k8s/frontend-nginx-sidecar.yaml
# HATA: "Error from server: admission webhook \"validate.kyverno.svc-fail\"
# denied the request: resource Pod/default/frontend-nginx-sidecar-xxxx
# was blocked due to the following policies: restrict-registries:
# only-internal-registry: validation error: Imajlar sadece
# myregistry.internal registrysinden cekilebilir."
# SEBEP: policy sadece "myregistry.internal/*" desenine izin veriyordu,
# yaygin kullanilan public base image'lari (docker.io/library/nginx gibi
# FROM satirinda kullanilanlar) hic dusunulmemisti.

# ÇÖZÜM: policy'ye bilinen public base image'lar icin bir istisna ekle
kubectl patch clusterpolicy restrict-registries --type json -p '[
  {"op": "add", "path": "/spec/rules/0/exclude", "value": {
    "any": [{"resources": {"kinds": ["Pod"], "namespaces": ["ci-build"]}}]
  }}
]'
kubectl apply -f k8s/frontend-nginx-sidecar.yaml
# SONUÇ: Pod basariyla olusturuldu, gercek servis imajlari (myregistry.
# internal disindan cekilenler) yine reddedilmeye devam etti.


# ------------------------------------------------------------
# ADIM 5: require-labels'ı Enforce'a al - İKİNCİ HATA
# ------------------------------------------------------------

kubectl patch clusterpolicy require-labels --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'

kubectl rollout restart deployment legacy-billing-worker
# HATA: "error when patching: admission webhook \"validate.kyverno.svc-fail\"
# denied the request: resource Pod/default/legacy-billing-worker-yyyy was
# blocked due to the following policies: require-labels:
# check-required-labels: validation error: app ve env label'lari
# zorunludur."
# SEBEP: legacy-billing-worker'in Helm chart'inda hicbir zaman "env"
# label'i tanimlanmamisti, Audit modunda bu ihlal raporlanmisti ama
# duzeltilmeden Enforce'a gecilmisti.

# ÇÖZÜM: eksik label'i chart values dosyasina ekle
sed -i '' 's/app: legacy-billing-worker/app: legacy-billing-worker\n  env: production/' \
  charts/legacy-billing-worker/values.yaml
helm upgrade legacy-billing-worker charts/legacy-billing-worker/
kubectl rollout restart deployment legacy-billing-worker
kubectl get pods -l app=legacy-billing-worker
# SONUÇ: Running, admission reddi bir daha alinmadi.


# ------------------------------------------------------------
# ADIM 6: Mutating policy, otomatik "team: platform" label'ı
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-team-label
spec:
  rules:
  - name: add-default-team-label
    match:
      any:
      - resources:
          kinds: [Pod]
    mutate:
      patchStrategicMerge:
        metadata:
          labels:
            +(team): platform
EOF

kubectl get pods -l app=legacy-billing-worker --show-labels
# HATA (beklenen değil, gözlemlenen davranış): zaten calisan pod'larda
# "team=platform" label'i HIC GORUNMEDI.
# SEBEP: mutate kurali, tipki Service Mesh subtopic'indeki sidecar
# injection webhook'u gibi, sadece admission aninda (pod OLUSTURULURKEN)
# calisiyor, background scan mutate icin degil sadece validate raporlama
# icin gecerli, mevcut kaynaklara geriye donuk uygulanmiyor.

# ÇÖZÜM: pod'ları yeniden oluştur
kubectl rollout restart deployment legacy-billing-worker
kubectl get pods -l app=legacy-billing-worker --show-labels
# SONUÇ: yeni pod'larda "team=platform" label'i otomatik eklenmis
# olarak goruldu.


# ------------------------------------------------------------
# ADIM 7: disallow-root-container'ı Enforce'a al, son durumu doğrula
# ------------------------------------------------------------

# Once Audit raporundaki 14 root-container ihlalini tek tek duzelt
# (securityContext.runAsNonRoot: true ekle), sonra:
kubectl patch clusterpolicy disallow-root-container --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'

kubectl get clusterpolicy
# SONUÇ: uc policy de artik Enforce modunda.

kubectl get clusterpolicyreport
# SONUÇ: FAIL sayisi 29'dan 0'a dustu, tum mevcut kaynaklar duzeltilmis
# durumda, Enforce moduna gecis hicbir servisi aniden kesintiye
# ugratmadan tamamlandi.


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# Audit modunda calistirilan uc policy, beklenenden fazla (29) mevcut
# ihlal ortaya cikardi, bu Enforce'a dogrudan gecmenin neden riskli
# olacagini somut olarak dogruladi. Enforce'a gecis sirasinda iki ayri
# gercek red yasandi: bilinmeyen bir public base image registry
# kisitlamasina takildi, eksik "env" label'i bir deploy'u reddettirdi,
# ikisi de once Audit raporundaki ihlalleri temizlemenin onemini
# gosterdi. Mutating policy (otomatik team label) Service Mesh
# subtopic'indeki sidecar injection dersini birebir tekrarladi, sadece
# yeni olusturulan pod'lara uygulaniyor, mevcut pod'lar icin rollout
# restart gerekiyor. Son durumda tum ihlaller duzeltilip Enforce moduna
# sifir kesintiyle gecildi.
