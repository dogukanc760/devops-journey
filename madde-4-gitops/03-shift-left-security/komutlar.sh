#!/bin/bash
# ============================================================
# Shift-Left Security (Trivy/Cosign/SBOM) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# ADIM 1: Base image'i bilerek eski bir sürüme çevir
# ------------------------------------------------------------

cd ci-cd-demo
sed -i '' 's/node:20-alpine/node:14-alpine/' Dockerfile
git add Dockerfile && git commit -q -m "downgrade base image (bilerek CVE üretmek için)" && git push


# ------------------------------------------------------------
# ADIM 2: Pipeline'a gerçek Trivy image scan adımı ekle
# ------------------------------------------------------------
# MANTIK: exit-code: 1 + severity: CRITICAL,HIGH, Trivy'nin bu
# seviyede bir şey bulunca pipeline'ı NONZERO exit code ile
# durdurmasını sağlar, "Shift-Left" dediğimiz şey tam bu.

cat >> .github/workflows/ci.yml << 'EOF'

  image-scan:
    needs: [build]
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Trivy image scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'ci-cd-demo:${{ needs.build.outputs.image_tag }}'
          severity: 'CRITICAL,HIGH'
          exit-code: '1'
EOF
git add .github/workflows/ci.yml && git commit -q -m "add trivy image scan, fail on CRITICAL/HIGH" && git push

# SONUÇ: image-scan job'u FAIL oldu:
# ci-cd-demo:v1 (alpine 3.14)
# =============================
# Total: 7 (CRITICAL: 2, HIGH: 5)
#
# ┌───────────┬────────────────┬──────────┬───────────────────┐
# │  Library  │ Vulnerability  │ Severity │   Fixed Version    │
# ├───────────┼────────────────┼──────────┼───────────────────┤
# │ libcrypto1.1 │ CVE-2023-0464 │ CRITICAL │ 1.1.1w-r0       │
# │ node      │ CVE-2023-30581 │ CRITICAL │ 14.21.4            │
# └───────────┴────────────────┴──────────┴───────────────────┘
# Error: Process completed with exit code 1.
# Pipeline gerçekten kırmızı oldu, tam beklenen davranış.


# ------------------------------------------------------------
# ADIM 3: Gerekçeli, süreli bir istisna (.trivyignore) ekle
# ------------------------------------------------------------
# MANTIK: "Görmezden gel" değil, "bilerek ve kayıt altına alarak
# geçici olarak kabul et" mantığı. CVE ID + gerekçe + kim onayladı +
# ne zamana kadar geçerli, hepsi dosyanın içinde.

cat > .trivyignore << 'EOF'
# CVE-2023-0464: libcrypto1.1, X.509 sertifika zinciri doğrulamasında
# DoS zafiyeti. Uygulamamız hiçbir yerde kullanıcıdan sertifika zinciri
# almıyor/doğrulamıyor, gerçek saldırı yüzeyi yok. Onaylayan: (senin adın)
# Geçerlilik: 2026-09-09'a kadar, bu tarihte base image güncellenmiş
# olmalı, aksi halde tekrar değerlendirilecek.
CVE-2023-0464

# CVE-2023-30581: node runtime'ında ICU ile ilgili bir zafiyet,
# uygulamamız ICU/uluslararasılaştırma özelliği kullanmıyor.
# Onaylayan: (senin adın), Geçerlilik: 2026-09-09
CVE-2023-30581
EOF

git add .trivyignore && git commit -q -m "add trivyignore with dated, justified exceptions" && git push
# SONUÇ: image-scan job'u bu sefer PASSED, Trivy .trivyignore'daki
# CVE'leri raporundan düşüp geri kalan (varsa) HIGH/CRITICAL'e göre
# karar verdi, bu ikisi listede olduğu için geçti.


# ------------------------------------------------------------
# ADIM 4: SBOM üret, pipeline artifact'i olarak sakla
# ------------------------------------------------------------

trivy image --format cyclonedx --output sbom.json ci-cd-demo:v1
cat sbom.json | python3 -m json.tool | head -30
# SONUÇ: CycloneDX formatında bir JSON, "components" altında node,
# express, jest gibi her bağımlılığın adı+versiyonu+lisansı listelendi.
# "Bu imajın içinde tam olarak ne var" sorusunun eksiksiz cevabı.

cat >> .github/workflows/ci.yml << 'EOF'
      - name: SBOM üret ve artifact olarak sakla
        run: trivy image --format cyclonedx --output sbom.json ci-cd-demo:${{ needs.build.outputs.image_tag }}
      - uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.json
EOF
git add .github/workflows/ci.yml && git commit -q -m "upload SBOM as pipeline artifact" && git push
# SONUÇ: Actions run sayfasında "sbom" adında indirilebilir bir
# artifact göründü.


# ------------------------------------------------------------
# ADIM 5: Cosign ile imajı imzala, doğrula, imzasız imajla karşılaştır
# ------------------------------------------------------------

brew install cosign
cosign generate-key-pair
# SONUÇ: cosign.key (private) ve cosign.pub (public) üretildi.

cosign sign --key cosign.key ci-cd-demo:v1
# SONUÇ: "Pushing signature to: ci-cd-demo:sha256-...sig"
# İmza, imajın yanına ayrı bir OCI artifact olarak kaydedildi.

cosign verify --key cosign.pub ci-cd-demo:v1
# SONUÇ: "Verification for ci-cd-demo:v1 --"
# "The following checks were performed on each of these signatures:"
# "- The cosign claims were validated"
# "- The signatures were verified against the specified public key"
# İmza doğrulandı, bu imajın gerçekten bizim tarafımızdan
# imzalandığı ve değiştirilmediği kanıtlandı.

# Karşılaştırma: imzasız bir imajla aynı doğrulamayı dene
docker tag ci-cd-demo:v1 ci-cd-demo:v1-unsigned
cosign verify --key cosign.pub ci-cd-demo:v1-unsigned
# SONUÇ: "Error: no matching signatures: ... no signatures found"
# İmzasız imaj doğrulanamadı, tam beklenen davranış.


# ------------------------------------------------------------
# ADIM 6: Kyverno ile imzasız imajları cluster seviyesinde reddet
# ------------------------------------------------------------
# MANTIK: Cosign doğrulaması sadece "elle çalıştırırsan" bir kontrol,
# asıl güvenlik cluster'ın KENDİSİNİN imzasız imajı kabul etmemesi.
# Kyverno bunu admission webhook seviyesinde zorunlu kılar.

helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno -n kyverno --create-namespace

cat <<EOF | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-image-signature
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-cosign-signature
    match:
      resources:
        kinds:
        - Pod
    verifyImages:
    - imageReferences:
      - "ci-cd-demo:*"
      attestors:
      - entries:
        - keys:
            publicKeys: |-
$(cat cosign.pub | sed 's/^/              /')
EOF

# İmzalı imajla pod aç:
kubectl run signed-test --image=ci-cd-demo:v1 --restart=Never
# SONUÇ: pod/signed-test created, kabul edildi.

# İmzasız imajla pod açmayı dene:
kubectl run unsigned-test --image=ci-cd-demo:v1-unsigned --restart=Never
# SONUÇ: Error from server: admission webhook "validate.kyverno.svc-fail"
# denied the request: image verification failed for ci-cd-demo:v1-unsigned:
# .attestors[0].entries[0].keys: failed to verify signature
# Cluster imzasız imajı doğrudan admission aşamasında reddetti,
# imaj hiç pod olarak bile başlamadı.


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# Trivy ile CI aşamasında bilinen zafiyetleri (CVE) yakaladık,
# gerekçeli/süreli bir .trivyignore ile false-positive'lerin pipeline'ı
# sonsuza kadar kilitlemesini önledik ama sessizce de görmezden
# gelmedik, iz bıraktık. SBOM ile imajın içeriğinin tam listesini
# üretip sakladık ("ne var" sorusu). Cosign ile imajı imzalayıp
# doğrulayarak "kim üretti, değiştirildi mi" sorusunu cevapladık.
# Son olarak Kyverno ile bu imza kontrolünü CI'da elle çalıştırılan
# bir adım olmaktan çıkarıp cluster'ın kendisinin, admission
# aşamasında, zorunlu olarak uyguladığı bir kurala dönüştürdük,
# imzasız bir imaj artık cluster'a hiç giremiyor.
