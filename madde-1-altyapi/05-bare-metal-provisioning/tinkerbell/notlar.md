# 📝 Notlar — Tinkerbell

## Neden var?

MaaS gibi araçlar bare-metal yönetimi yapıyor ama temelde GUI ve API odaklılar, her şey bir web paneline veya komut satırına bağlı. Tinkerbell olmadan her makineyi tek tek el ile kurmak zorunda kalırsın ya da bash scriptlerini USB'ye yazıp fiziksel olarak her sunucuya takarsın. Tinkerbell bunu "bir workflow tanımla, makine boot edince otomatik koşsun" haline getiriyor. Üstelik her adım bir container olduğu için istediğin aşamayı değiştirebilirsin — MaaS'ta bunu yapamazsın.

## Anahtar Kavramlar

### 1. Hardware, Template, Workflow — bu üçlü ne anlama geliyor?

- **Hardware:** "Bu MAC adresine sahip makineye şu IP'yi ver, PXE'den boot etmesine izin ver" diyor. Yani fiziksel makineyi sisteme tanıtıyorsun.
- **Template:** Provisioning adımlarını tanımlıyor. "Önce imajı yaz, sonra partition'ı büyüt, sonra cloud-init dosyasını koy, son olarak reboot et." Her adım bir container image.
- **Workflow:** Hardware + Template'i birbirine bağlıyor. "Bu makinede şu template'i çalıştır" diyorsun. Workflow oluşturunca makine boot ettiğinde otomatik başlıyor.

### 2. Neden her adım bir container?

Çünkü adımları değiştirebilirsin. Diyelim Ubuntu değil de Rocky Linux kurmak istiyorsun — sadece `image2disk` action'ının URL'sini değiştiriyorsun, geri kalanı aynı kalıyor. Ya da aralarına "firmware update" adımı ekleyebilirsin. MaaS'ta böyle bir esneklik yok.

### 3. Tinkerbell bileşenleri neler?

- **Boots:** DHCP + iPXE sunucusu. Makine açılınca IP ve boot script buradan geliyor.
- **Hegel:** Metadata sunucusu. Makine çalışırken kendi bilgilerini (IP, hostname vb.) buradan çekebiliyor — cloud-init'in EC2 metadata API'sine benziyor.
- **Tink Server:** Workflow'ları saklıyor ve dağıtıyor.
- **Tink Controller:** Kubernetes controller, Hardware/Template/Workflow CRD'lerini izliyor.
- **Tink Worker:** Hedef makinede çalışıyor (HookOS içinde), adımları sırayla execute ediyor.

### 4. HookOS nedir?

Tinkerbell'in kendi minimal Linux'u. Makine PXE'den boot edince önce HookOS yükleniyor, HookOS içinde Tink Worker çalışıyor ve template'deki action'ları sırayla container olarak koşturuyor. Yani makine daha Ubuntu kurulmadan önce Tinkerbell'in kontrolüne giriyor.

### 5. MaaS ile fark nerede?

| | MaaS | Tinkerbell |
|--|------|------------|
| Odak | Datacenter yönetimi | Provisioning workflow'u |
| Arayüz | Web UI + CLI | YAML + kubectl |
| Esneklik | Sabit akış | Her adım değiştirilebilir |
| Ekosistem | Canonical | CNCF (vendor-neutral) |
| GitOps | Zor | Doğal (YAML = kod) |

Büyük bir datacenter'ı yöneteceksen MaaS daha pratik. Workflow'lar üzerinde tam kontrol istiyorsan ve K8s ekosisteminle uyumlu olmasını istiyorsan Tinkerbell.

### 6. Workflow state'leri neler?

```
STATE_PENDING → STATE_RUNNING → STATE_SUCCESS
                              → STATE_FAILED
                              → STATE_TIMEOUT
```

Bir action başarısız olursa tüm workflow durur, sonraki action'lar koşmaz.

## Kendi Notum

Şöyle anlatırdım: diyelim 50 sunucu aldın ve hepsine K8s worker node kuracaksın. USB takıp tek tek kurmak 2 gün alır. Tinkerbell ile şunu yapıyorsun: bir kere Hardware kaydını yapıyorsun (MAC adresleri), bir Template yazıyorsun ("Ubuntu kur, open-iscsi ekle, SSH key'i yükle"), her sunucu için Workflow oluşturuyorsun. Bundan sonra 50 sunucuyu ağa takıp açıyorsun — hepsi sırayla kendini kuruyor. Sen sadece izliyorsun. Üstelik bu YAML dosyaları Git'te duruyor, 6 ay sonra yeni sunucu aldığında aynı template'i kullanıyorsun.

## Karşılaştığım Hatalar

Fiziksel donanım erişimim olmadığı için bu pratik görev simülasyon ortamında yapılamadı. Komutlar `komutlar.sh`'da belgelenmiş, bare-metal lab kurulduğunda çalıştırılacak.

Dikkat edilmesi gereken nokta: `hardwareMap`'teki MAC adresi `Hardware` manifest'indeki MAC ile birebir eşleşmeli, yoksa Workflow tetiklenmiyor.

## Kaynaklar

- [Tinkerbell Docs](https://docs.tinkerbell.org)
- [Tinkerbell Sandbox (Docker Compose)](https://github.com/tinkerbell/sandbox)
- [CNCF Tinkerbell Proje Sayfası](https://www.cncf.io/projects/tinkerbell/)
