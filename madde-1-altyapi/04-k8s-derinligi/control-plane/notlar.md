# 📝 Notlar

## Neden var?
K8s'de yüzlerce pod, node ve servis var. Bunları kim yönetiyor? Kim "bu pod şu node'a gitsin" diyor? Kim "bu pod öldü, yenisini aç" diyor? İşte Control Plane bunları halleder. Olmasa cluster kör uçar. Pod'lar nereye gideceğini bilemez, arızalar fark edilmez, hiçbir şey orkestre edilemez.

4 Temel Bileşeni:
1. kube-apiserver: Tüm K8s iletişiminin geçtiği tek kapı. kubectl komutunun, bir pod'un bir başka pod'a sorması, her şey buradan geçer, REST API sunar.
2. etcd: Cluster'ın beyni. Tüm state burada, hangi pod nerede, hangi node ayakta, hangi config ne. etcd ölürse cluster ne yapacağını unutur.
3. kube-scheduler: Yeni pod geldi, hangi node'a gitsin? CPU/memory'e bakar, affinity kurallarına bakar, en uygun node'u seçer.
4. kube-controller-manager: "İstenen durum" ile "mevcut durumu" karşılaştırır. 3 replica istiyorsun ama 2 var, yenisini aç. Node öldü, pod'ları taşı. Sürekli döngüde çalışır.

kube-apiserver çökerse cluster'a ne olur? Çalışan pod'lar ölür mü?
Hayır çalışan pod'lar ölmez, kubelet node üzerinde pod'ları ayakta tutar. Ancak cluster içindeki iletişim durur, yeni pod açılamaz, scaling yapılamaz, kubectl çalışmaz. Controller-manager ve scheduler da apiserver üzerinden konuşur, onlar da kör kalır.

## Anahtar Kavramlar
- kube-apiserver: Tüm bileşenler burada konuşur. kubectl de, kubelet de, controller-manager da. Kapanırsa iletişim kesilir ama çalışan pod'lar etkilenmez.
- etcd: Distributed key-value store. Cluster state'inin tek kaynağı. Quorum gerektirir (2n+1), 3 replica için 1 arıza tolere eder. HA cluster'da kritik.
- kube-scheduler: Pod için uygun node seçimi. Node affinity, taints/tolerations, resource request/limit bunları değerlendirip karar verir.
- kube-controller-manager: İçinde onlarca controller var (ReplicaSet, Deployment, Node controller vs.). Hepsi aynı binary içinde çalışır, ayrı ayrı süreç değil.
- Reconciliation: Desired state ile current state'i karşılaştırma döngüsü. Tüm K8s mantığının temeli bu.

## Kendi Notum
Şöyle anlatırdım: Control Plane bir şirketin genel müdürlüğü gibi. kube-apiserver CEO'nun sekreteri, her talebi önce o alıyor ve yönlendiriyor. etcd şirketin hafızası, tüm kararlar, organizasyon şeması, kim nerede çalışıyor burada. kube-scheduler HR gibi, yeni çalışan geldi (pod), hangi departmana (node) yerleşeceğine karar veriyor. kube-controller-manager ise sürekli kontrol eden müdür, "bu departmanda 3 kişi olması lazım, 2 tane var, birini işe al" döngüsü.

Bunların hepsi HA cluster'da 3 node'da çalışıyor (etcd quorum için). Biri düşse diğerleri devam ediyor.

## Karşılaştığım Hatalar
k3d HA cluster'da etcd snapshot aldım:
```bash
docker exec k3d-ha-cluster-server-0 k3s etcd-snapshot save
```
Çıktı: `Snapshot on-demand-k3d-ha-cluster-server-0-1784385844 saved`. Snapshot `/var/lib/rancher/k3s/server/db/snapshots/` altında. Restore bare-metal'a ertelendi çünkü k3d'de etcdctl binary yok, k3s kendi komutlarını kullanıyor.

`etcdctl` aramak yerine k3s'in kendi komutlarını kullanmak gerekiyor, bu farkı bulmak biraz zaman aldı.

## Kaynaklar
- K8s Control Plane bileşenleri: https://kubernetes.io/docs/concepts/overview/components/
- etcd K8s'de nasıl kullanılır: https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/
- kube-scheduler nasıl çalışır: https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/
