# 📝 Notlar

## Neden var?
Ceph güçlü ama kurmak ve yönetmek karmaşık, onlarca config dosyası, manuel cluster kurulumu, disk yönetimi. Rook bunu K8s Operator Pattern ile otomatize eder. "Ceph'i K8s'e sığdıran wrapper" diyebilirsin. Rook olmasa Ceph'i K8s dışında ayrı bir sistem olarak yönetmek zorunda kalırsın.

Temel:
Rook bir K8s Operator'üdür, CRD'ler aracılığıyla Ceph Cluster'ını K8s kaynağı gibi yönetir.
CephCluster, CephBlockPool, CephFileSystem gibi custom resource'ları tanımlar.
Disk ekle/çıkar, node ekle/çıkar: Rook otomatik halleder.
StorageClass oluşturur: PVC talep edince Rook otomatik PV sağlar.

kubectl apply -f cephcluster.yaml → Rook Operator görür → Ceph cluster ayağa kalkar → StorageClass hazır → PVC → otomatik PV

Operator Pattern nedir? Rook neden bir Operator, sadece bir Helm chart değil?
Operator Pattern, insan operatörlerin manuel olarak yönettiği karmaşık uygulama süreçlerini otomatize eder. Sistemin mevcut durumu ile istenen durumunu sürekli karşılaştırarak aradaki farkı kapatır.
Helm: Kurulum anında YAML'ları K8s'e gönderir ve görevi biter. Disk arızalanırsa Helm'in haberi olmaz.
Rook: 7/24 çalışan aktif bir kod döngüsü. Disklerin sağlığını, Ceph bileşenlerinin (MON, OSD, MGR) durumunu anlık izler, arıza olunca re-rebalancing yapar.

## Anahtar Kavramlar
- Operator Pattern: CRD + Controller döngüsü. Sen "istenen durumu" YAML ile tanımlarsın, controller sürekli "mevcut durum" ile karşılaştırır ve farkı kapatır.
- CRD (Custom Resource Definition): K8s API'sine yeni kaynak tipi ekler. `CephCluster`, `CephBlockPool` bunun örnekleri.
- CR (Custom Resource): O CRD'den türetilen gerçek nesne. `kubectl apply -f cephcluster.yaml` yaptığında bir CR oluşturursun.
- Controller loop: Reconciliation döngüsü. Watch → Compare → Act. Desired state != current state ise harekete geçer.
- OSD (Object Storage Daemon): Rook her disk için bir OSD pod'u açar. Diskleri Rook yönetir, sen elle dokunmazsın.
- Day 2 Operations: Kurulumdan sonraki operasyonel görevler. Disk ekle, versiyon güncelle, node çıkar. Helm bunları yapamaz, Operator yapabilir.

## Kendi Notum
Bak junior arkadaşım, K8s'de depolamayı yöneten Ceph'i anlattık ama karmaşası ve yönetim zorluğundan hiç bahsetmedik. İşte burada bir Operator Pattern ile karşımızda Rook var. Bu Rook ne yapar? O koca koca OS seviyesinde çalışan ve yönetmesi çok zor olan Ceph'i K8s cluster'ı içerisinde tıkıştıran işleri yapar. Yani senin Ceph'te elle yapacağın her şeyi, senin CR-CRD tanımlarını bilerek Rook senin yerine halleder ve sen "hangi node'da hangi veri var, hangi lokal cihaz içinde hangi veri var" gibi düşüncelerle uğraşmazsın. Tek yapacağın Rook'u sisteme tanıtmak ve geri kalanı ona bırakmak.

## Karşılaştığım Hatalar
Rook kurulumunda ilk sürüm hatası aldım: `failed the ceph version check: minimum version 19.2.0-0 squid`. Helm chart'taki image v18'di, `kubectl patch` ile v19'a güncelledim:
```bash
kubectl patch CephCluster rook-ceph -n rook-ceph --type merge \
  -p '{"spec":{"cephVersion":{"image":"quay.io/ceph/ceph:v19"}}}'
```

Sonra k3d'ye özgü asıl hata geldi: `chown: changing ownership of '/run/ceph/ceph-mon.c.asok': Invalid argument`. Nested container ortamında kernel Unix socket chown izni yok, bu k3d'nin bir kısıtı. Çözümü yok, bare-metal veya gerçek VM gerekiyor. Pratik görev ertelendi.

## Kaynaklar
- Rook resmi döküman: https://rook.io/docs/rook/latest/
- Operator SDK: https://sdk.operatorframework.io/
- K8s CRD kavramları: https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/
