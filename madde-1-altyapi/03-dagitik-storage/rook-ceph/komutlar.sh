#!/bin/bash
# ============================================================
# Pratik Görev: Rook-Ceph Kur, 3-node Ceph Cluster Oluştur
# NOT: k3d'de çalışmıyor (Unix socket chown kısıtı)
#      Bare-metal veya gerçek VM ortamında çalıştır
# ============================================================

# Helm repo ekle
helm repo add rook-release https://charts.rook.io/release
helm repo update

# Rook operator kur
helm install --create-namespace --namespace rook-ceph rook-ceph rook-release/rook-ceph

# Operator durumu izle
kubectl -n rook-ceph get pods -w

# CephCluster oluştur (minimum versiyon: v19 squid)
kubectl apply -f - <<EOF
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v19
  dataDirHostPath: /var/lib/rook
  mon:
    count: 3
    allowMultiplePerNode: true
  dashboard:
    enabled: true
  storage:
    useAllNodes: true
    useAllDevices: false
EOF

# Cluster durumu
kubectl -n rook-ceph get cephcluster
kubectl -n rook-ceph describe cephcluster rook-ceph | tail -30

# Ceph status (cluster ayaktaysa)
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status

# HATA: k3d'de alınan hata
# chown: changing ownership of '/run/ceph/ceph-mon.c.asok': Invalid argument
# Sebep: nested container ortamında kernel Unix socket chown izni yok
