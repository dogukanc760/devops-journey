# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
Madde 4'te Kyverno'yu dar bir amaç için kullanmıştık, sadece imzasız imajları reddetmek. Ama gerçek bir organizasyonda cluster'a girmesini istemediğin çok daha fazla şey var, root çalışan container'lar, bilinmeyen registry'lerden çekilen imajlar, zorunlu label'ı olmayan kaynaklar. Bu olmasaydı ne olurdu diye sorarsak, her takım kendi manifestini istediği gibi yazardı, kimse root kısıtlaması ya da label standardı uygulamak zorunda kalmazdı, ihlaller ancak bir incident sonrası fark edilirdi, önceden engellenmezdi.

Temel:

- Admission Controller: bir kaynak cluster'a kabul edilmeden önce araya giren, onu kabul eden/reddeden/değiştiren mekanizma
- Kyverno: Kubernetes'e özel, politikaları YAML ile yazan bir policy engine
- OPA/Gatekeeper: Kubernetes'in dışında da kullanılabilen, politikaları Rego diliyle yazan genel amaçlı bir policy engine
- Audit mode: politikayı hemen reddetmeden sadece mevcut kaynakları tarayıp kaç tanesinin kuralı ihlal ettiğini raporlayan güvenli başlangıç modu
- Enforce mode: kuralı ihlal eden kaynağın cluster'a girişini fiilen reddeden mod
- Mutating policy: bir kaynağı reddetmek yerine otomatik olarak değiştiren/tamamlayan policy türü (örn. eksik label'ı otomatik ekleme)

Örnek Soru:
Bir Kyverno policy'si yazıyorsun, root container'lar reddedilsin. Bunu doğrudan `validationFailureAction: Enforce` ile production cluster'ına uygulamak yerine, önce neden `Audit` modunda çalıştırman akıllıca olur? Ayrıca, bu policy'yi hem Kyverno hem OPA/Gatekeeper ile yazabilirsin, ikisi de aynı işi yapar ama bir organizasyon hangi kritere göre birini diğerine tercih eder?

Cevap:
Gerçek bir production cluster'ında muhtemelen zaten root çalışan onlarca pod vardır, bu yeni bir kural değil, geçmişten kalma bir alışkanlık. Direkt Enforce ile başlarsan, bu kural o pod'ların bir sonraki güncellemesinde tüm bu meşru ama kurala uymayan iş akışlarını aniden bloke eder, kendi kendine bir kesinti yaratmış olursun, üstelik kimse buna hazırlıklı değildir. Audit mode, mevcut kaynakları tarayıp "şu an kaç kaynak bu kuralı ihlal ediyor" sorusunun cevabını önceden görmeni sağlar, bir nevi blast-radius (etki alanı) ölçümü, Enforce'a geçmeden önce düzeltilmesi gereken kaynakları temizlemene fırsat tanır. Aynı mantığı Madde 4'te `.trivyignore` ile de görmüştük, aniden kesmek yerine önce ölç, sonra kademeli sık.

Kyverno ile OPA/Gatekeeper arasındaki asıl seçim kriteri "hangisi imajı, hangisi geri kalanı yapar" değil, ikisi de Kubernetes içinde root container reddi, label zorunluluğu, resource limit kontrolü gibi her şeyi yapabilir. Asıl fark kapsamda, Kyverno sadece Kubernetes için tasarlanmış, OPA ise Kubernetes'in dışında da kullanılan genel amaçlı bir policy motoru, mikroservisler arası yetkilendirme kararlarında, Terraform plan'ını apply etmeden önce doğrulamada, CI/CD pipeline gate'lerinde de çalışır. Bir organizasyon sadece Kubernetes'i değil birden fazla farklı sistemi tek bir politika diliyle (Rego) yönetmek istiyorsa OPA/Gatekeeper'a yatırım yapar, politika ihtiyacı sadece Kubernetes admission'la sınırlıysa Kyverno'nun YAML tabanlı, K8s'e zaten aşina bir ekip için ekstra dil öğrenmeyi gerektirmeyen yapısı yeterli ve daha basit kalır.

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- Kyverno politikaları tamamen YAML ile yazılır, K8s manifestlerine zaten aşina bir ekip için yeni bir dil öğrenmeye gerek kalmaz, ama sadece Kubernetes içinde çalışır.
- OPA/Gatekeeper politikaları Rego dilinde yazılır, öğrenme eğrisi daha yüksektir ama Kubernetes dışında da (API gateway, CI/CD, Terraform) aynı motorla kullanılabilir.
- `validationFailureAction: Audit`, kuralı ihlal eden kaynağı reddetmez, sadece `PolicyReport`/`ClusterPolicyReport` objesine bir ihlal kaydı düşer, cluster'ın gerçek durumunu göstermiş olur.
- `mutate` tipi Kyverno kuralları, tıpkı Madde 6'nın Service Mesh subtopic'indeki sidecar injection webhook'u gibi, sadece kaynak OLUŞTURULURKEN (admission anında) çalışır, zaten var olan çalışan kaynaklara geriye dönük uygulanmaz.
- `background: true` (varsayılan), validate policy'lerin sadece yeni gelen isteklerde değil, cluster'da zaten var olan kaynaklarda da periyodik olarak taranıp raporlanmasını sağlar, mutate kurallarında bu tarama otomatik geriye dönük DEĞİŞİKLİK yapmaz, sadece validate raporlaması için geçerlidir.
- Bir policy'yi Audit'ten Enforce'a geçirmeden önce, mevcut ihlallerin sıfırlanmış ya da bilinçli olarak istisna (exclude/exception) listesine alınmış olması gerekir, aksi halde Enforce anında meşru ama düzeltilmemiş kaynaklar aniden reddedilmeye başlar.

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->
Policy as Code'u "cluster'ın kapısındaki güvenlik görevlisi" gibi düşün, bir kaynak içeri girmeden önce kurallara uyup uymadığına bakılır. Madde 4'te bu görevliye tek bir iş vermiştik, imza kontrolü. Şimdi ona root container var mı, bilinmeyen registry'den mi geliyor, zorunlu label'lar tam mı gibi çok daha fazla iş verdik.

En öğretici kısım Audit modunda ortaya çıkan gerçek tabloydu, cluster'da beklediğimizden çok daha fazla root çalışan ve label'ı eksik kaynak vardı, bunları görünce Enforce'a atlamadan önce audit'in ne kadar doğru bir ilk adım olduğunu bizzat gördük. İkinci öğretici kısım, mutate policy'nin (otomatik `team: platform` label'ı ekleyen) mevcut pod'lara hiç dokunmaması oldu, tıpkı Istio injection'da yaşadığımız gibi, admission seviyesindeki her mekanizma sadece yeni oluşturulan kaynaklarda çalışıyor, bu artık bizim için tekrar eden ve içselleştirdiğimiz bir Kubernetes gerçeği.

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->
1. Registry kısıtlama policy'si Audit'ten Enforce'a geçirilince, CI pipeline'ındaki bir build `docker.io/library/nginx` public base image'ını temel alan bir Dockerfile kullandığı için reddedildi ("image validation failed: docker.io not in allowed registries"). Sebep, sadece kendi internal registry'mizi (`myregistry.internal/*`) izin listesine almış, yaygın kullanılan public base image'ları unutmuştuk. Çözüm, policy'ye bir istisna deseni (`docker.io/library/*` sadece base image FROM satırları için) eklemekti, gerçek servis imajları yine sadece internal registry'den geçebiliyordu.
2. `require-labels` policy'si Enforce moduna alınınca, eski bir servisin rutin bir deploy'u "admission webhook \"validate.kyverno.svc\" denied the request: validation failure: env label is required" hatasıyla reddedildi. Sebep, o servisin Helm chart'ında `env` label'ının hiç tanımlı olmaması, Audit modunda bu ihlal raporlanmış ama düzeltilmeden Enforce'a geçilmişti. Çözüm, chart'ın values dosyasına eksik label'ı eklemek ve deploy'u tekrar çalıştırmaktı.
3. `team: platform` etiketini otomatik ekleyen mutate policy uygulandıktan sonra, zaten çalışan pod'larda bu label hiç görünmedi. Sebep, mutate kurallarının (tıpkı Service Mesh sidecar injection'da olduğu gibi) sadece admission anında, yani kaynak YENİDEN oluşturulurken tetiklenmesi, geriye dönük bir background mutation mekanizması olmaması. Çözüm, `kubectl rollout restart` ile ilgili deployment'ları yeniden oluşturmaktı, sonrasında yeni pod'larda label otomatik göründü.

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- Kyverno resmi dokümantasyonu (ClusterPolicy, validationFailureAction, mutate/validate/generate kuralları, PolicyReport)
- OPA/Gatekeeper resmi dokümantasyonu (Rego, ConstraintTemplate, Constraint)
- Kubernetes Admission Controllers resmi dokümantasyonu
