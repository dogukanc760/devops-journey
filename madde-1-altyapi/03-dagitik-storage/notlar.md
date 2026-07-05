# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- 

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->

## Karşılaştığım Hatalar

### Rook-Ceph — k3d'de çalışmıyor
- Hata: `chown: changing ownership of '/run/ceph/ceph-mon.c.asok': Invalid argument`
- Sebep: k3d nested container ortamında kernel Unix socket chown izni yok
- Çözüm: Bare-metal veya gerçek VM ortamı gerekiyor

### Longhorn — k3d'de çalışmıyor  
- Hata: `failed to check environment: iscsiadm/open-iscsi not found on host`
- Sebep: k3d node'larında open-iscsi yüklü değil
- Çözüm: Bare-metal ortamında `apt install open-iscsi` ile kurulur

### ⚠️ Pratik Görevler Ertelendi
Rook-Ceph ve Longhorn pratikleri Subtask 5 (Bare-Metal Provisioning) sırasında
gerçek lab ortamında yapılacak. Komutlar hazır:
- `rook-ceph/komutlar.sh`
- `longhorn/komutlar.sh`
- `storageclass-pv-pvc/komutlar.sh`

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- 
