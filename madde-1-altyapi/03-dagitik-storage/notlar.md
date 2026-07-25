# 📝 Notlar — Dağıtık Storage (Genel)

## Neden var?
Pod'lar ölüp başka node'da doğar. Veri tek bir node'un diskinde durursa pod taşınınca veri kaybolur. Dağıtık storage veriyi birden fazla node'a replike eder, hangi node ölse veri kaybolmaz. K8s'de storage'ı anlamadan stateful uygulama kuramazsın.

## Anahtar Kavramlar
Bu başlık altındaki her konunun kendi notlar.md'si var. Özet:
- Dağıtık Depolama: Veri çoğaltma, replication factor, leader/follower.
- Ceph: RBD (block), CephFS (dosya sistemi), Object Storage. Büyük cluster için.
- Rook: Ceph'i K8s Operator Pattern ile yöneten araç. CRD + Controller.
- Longhorn: K8s-native, lightweight block storage. Küçük/orta cluster için.
- StorageClass/PV/PVC: Soyutlama zinciri. Pod nereden geldiğini bilmeden disk kullanır.

## Kendi Notum
Bu başlık altındaki konular birbirinin üzerine kurulu: önce distributed storage'ın neden var olduğunu anladım, sonra Ceph'in ne sağladığını, Rook'un Ceph'i K8s'e nasıl taşıdığını, Longhorn'un ne zaman daha iyi seçim olduğunu, en sonunda PVC/PV/StorageClass soyutlama katmanını. Hepsini tek tek bilmek yetmiyor, birbirleriyle ilişkiyi anlamak önemli: StorageClass -> PV -> PVC zinciri; altta Ceph mi Longhorn mu çalışıyor, pod bunu bilmiyor.

k3d'de ikisi de çalışmadı ama komutlar hazır, bare-metal lab'da çalıştırılacak.

## Karşılaştığım Hatalar

Rook-Ceph: `chown: changing ownership of '/run/ceph/ceph-mon.c.asok': Invalid argument`
Sebep: k3d nested container ortamında kernel Unix socket chown izni yok.
Çözüm: Bare-metal veya gerçek VM ortamı gerekiyor.

Longhorn: `failed to check environment: iscsiadm/open-iscsi not found on host`
Sebep: k3d node'larında open-iscsi yüklü değil.
Çözüm: Bare-metal ortamında `apt install open-iscsi` ile kurulur.

Pratik görevler bare-metal lab'a ertelendi. Komutlar hazır:
- `rook-ceph/komutlar.sh`
- `longhorn/komutlar.sh`
- `storageclass-pv-pvc/komutlar.sh`

## Kaynaklar
- CNCF Storage landscape: https://landscape.cncf.io/card-mode?category=cloud-native-storage
- K8s storage belgeleri: https://kubernetes.io/docs/concepts/storage/
