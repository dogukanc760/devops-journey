# 📝 Notlar

## Neden var?
Normal pod'lar ölüp yeniden doğunca kimliği değişir, yeni IP, yeni isim, yeni disk. Veritabanı için bu felaket. PostgreSQL replica'sı "ben kimim, hangi verileri saklıyorum?" bilemez. StatefulSet pod'lara kalıcı kimlik kartı verir. Sabit isim, sabit disk, sabit sıra.

Temel:
Deployment: pod-abc123, pod-xyz789 (rastgele isim, ölünce değişir)
StatefulSet: pod-0, pod-1, pod-2 (sıralı, sabit isim, hep aynı)

Her pod'un sabit DNS adı var: pod-0.service.namespace.svc.cluster.local
Her pod'un kendi PVC'si var, pod-0 ölüp yeniden doğsa bile aynı diske bağlanır.
Pod'lar sırayla başlar: pod-0 Running olmadan pod-1 başlamaz.
Scale Down da tersten gider: pod-2 önce silinir, sonra pod-1.

Neden PostgreSQL primary/replica için StatefulSet?
Primary Pod ölüp yeniden doğsa Deployment'ta farklı bir PVC'ye bağlanır ya da PVC hiç yoksa disk verisi tamamen kaybolur. StatefulSet'te pod-0 her zaman kendi PVC'sine döner, veri korunur.

Primary pod ölünce iki senaryo:
1. Geçici ölüm: Secondary'ler okuma alır, Primary geri gelir, sync olur.
2. Kalıcı ölüm: Secondary'den biri yeni Primary seçilir (failover), controller-manager yeni replica açar, desired state korunur, zero downtime.

## Anahtar Kavramlar
- Stable Network Identity: pod-0, pod-1 isimleri asla rastgele değil. DNS adresi de sabit: pod-0.my-service.default.svc.cluster.local.
- volumeClaimTemplates: Her pod için ayrı PVC tanımı. pod-0 kendi PVC'sine, pod-1 kendi PVC'sine bağlanır, aynı disk değil.
- Ordered Startup/Shutdown: pod-0 Ready olmadan pod-1 başlamaz. DB cluster'larında primary önce ayakta olmalı kuralına uyuyor.
- Headless Service: StatefulSet ile birlikte kullanılır. ClusterIP olmayan servis, DNS üzerinden direkt pod IP'ye gidilir.
- StatefulSet vs Deployment: Deployment = ephemeral, kimliksiz pod'lar. StatefulSet = kimlikli, kalıcı diskli pod'lar. DB için StatefulSet, stateless app için Deployment.

## Kendi Notum
PostgreSQL için StatefulSet kullanılır çünkü Primary pod ölüp yeniden doğsa bile aynı diske (PVC) bağlanır, veri kaybolmaz. Deployment'ta kullanılsa yeni pod farklı PVC'ye bağlanır veya disk hiç olmaz, veri gider.

Takım arkadaşına şöyle anlatırdım: bir restoranda masalar var. Deployment masaları numarasız, müşteri gelince boş masaya otur. StatefulSet ise rezervasyonlu sistem, her müşterinin kendi masası var, her geldiğinde aynı masa (ve yanında o masaya ait çekmece). DB replica'ları bu çekmecede kendi verilerini tutuyor, masa değişince çekmece de değişirdi, bu felaket olurdu.

## Karşılaştığım Hatalar
postgres:15 image ile StatefulSet kurdum, pod Running'e geçince içine girip veri yazdım:
```bash
kubectl exec -it postgres-0 -- psql -U postgres -d testdb -c "INSERT INTO test VALUES ('merhaba');"
kubectl delete pod postgres-0
# pod yeniden başlıyor...
kubectl exec -it postgres-0 -- psql -U postgres -d testdb -c "SELECT * FROM test;"
# veri hala orada!
```
Bu çalıştı. Deployment ile aynı testi yapınca yeni pod farklı PVC olmamasına rağmen (local-path) farklı path'e mount etti ve veri gitti. Farkı gözlemlemek çok netleştirdi.

## Kaynaklar
- K8s StatefulSet belgeleri: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- StatefulSet vs Deployment: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- CloudNativePG Operator (PostgreSQL için): https://cloudnative-pg.io/
