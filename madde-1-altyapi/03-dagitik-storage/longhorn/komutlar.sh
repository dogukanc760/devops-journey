#!/bin/bash
# ============================================================
# Pratik Görev: Longhorn Kur, PVC Oluştur, Disk Simülasyonu
# k3d üzerinde çalışır
# ============================================================

# Helm repo ekle
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Longhorn kur
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace

# Pod'ları izle
kubectl -n longhorn-system get pods -w

# StorageClass kontrol et (longhorn otomatik oluşur)
kubectl get storageclass
