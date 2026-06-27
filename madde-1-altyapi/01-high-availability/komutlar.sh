#!/bin/bash
# ============================================================
# Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ha-cluster yaml ı commit ediyoruz k3d ile cluster oluşturmak adına.
# ============================================================


# ADIM-1 HA-Cluster oluştur. 
k3d cluster create --config ha-cluster.yaml


# ADIM-2 Cluster durumunu kontrol et.
kubectl get nodes -o wide

# Totalde 5 node görüyor olmalısınız 3 node, control-plane ve 2 worker node.


# ADIM-3 YÜKSEK KULLANILABİLİRLİK (HA) Cluster durumunu kontrol et.
kubectl get pods -A -o wide
docker ps --format "{{.Names}}"

# Bir adet master node u durdurun.
docker stop k3d-ha-cluster-server-1

# Ve daha sonra cluster durumlarını kontrol edin. Dönen sonuçta 2 adet master node görmelisiniz
kubectl get nodes


# ADIM-5 Işimiz bittiğine göre memory ve cpu kaynaklarını temizleyelim.
k3d cluster delete ha-cluster