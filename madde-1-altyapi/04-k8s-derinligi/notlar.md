# 📝 Notlar — K8s Derinliği (Genel)

## Neden var?
K8s'i pod deploy etmenin ötesinde gerçekten anlamak için. Control Plane'nin nasıl çalıştığını, kubelet'in ne yaptığını, Ingress'in nasıl TLS terminate ettiğini, StatefulSet'in neden Deployment'tan farklı olduğunu bilmeden "K8s kullanıyorum" diyebilirsin ama trouble-shoot edemezsin, tasarım kararı veremezsin.

## Anahtar Kavramlar
Bu başlık altındaki her konunun kendi notlar.md'si var. Özet:
- Control Plane: kube-apiserver, etcd, kube-scheduler, kube-controller-manager. Cluster'ın beyni.
- Kubelet: Her node'daki ajan. Control Plane'nin sahadaki temsilcisi. Pod'ları başlatır, izler, raporlar.
- kube-proxy: Her node'da iptables DNAT kuralları yazar. Service -> Pod yönlendirmesi buradan.
- Ingress + TLS: Tek IP'den birden fazla servise HTTP yönlendirme. TLS Controller'da terminate olur.
- StatefulSet: Kalıcı kimlikli pod'lar. DB'ler için. pod-0, pod-1 sabit isim, kendi PVC'si.
- Operator Pattern: CRD + Controller döngüsü. Karmaşık uygulamaları K8s'e "yerlileştirme" deseni.

## Kendi Notum
Bu konuları öğrendikten sonra K8s'e bakışım değişti. Artık "bir hata aldım, pod restart oluyor" deyince önce kubelet log'una bakıyorum, liveness probe'u kontrol ediyorum, etcd'nin sağlığına bakıyorum. Debug süreci çok daha yapısal hale geldi.

## Karşılaştığım Hatalar
Her konunun kendi notlar.md'sinde belgelenmiştir.

## Kaynaklar
- K8s bileşen mimarisi: https://kubernetes.io/docs/concepts/overview/components/
- K8s the Hard Way: https://github.com/kelseyhightower/kubernetes-the-hard-way
- CNCF landscape: https://landscape.cncf.io/
