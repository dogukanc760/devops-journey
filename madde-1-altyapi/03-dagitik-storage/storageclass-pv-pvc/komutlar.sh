#!/bin/bash
# ============================================================
# Pratik Görev: PVC Oluştur → Pod'a Bağla → Veri Yaz
#               Disk Simülasyonu: Node kapat → Veri erişilebilir mi?
# ============================================================

# -----------------------------------------------------------
# PVC OLUŞTUR
# -----------------------------------------------------------
kubectl apply -f - <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
YAML

# PVC Bound oldu mu?
kubectl get pvc test-pvc

# -----------------------------------------------------------
# POD OLUŞTUR, PVC'YI MOUNT ET, VERİ YAZ
# -----------------------------------------------------------
kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
  - name: test
    image: busybox
    command: ["/bin/sh", "-c", "echo 'veri yazildi' > /data/test.txt && sleep 3600"]
    volumeMounts:
    - mountPath: /data
      name: test-volume
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: test-pvc
YAML

# Veri yazıldı mı kontrol et
kubectl exec test-pod -- cat /data/test.txt

# -----------------------------------------------------------
# DİSK SİMÜLASYONU — Node kapat, veri erişilebilir mi?
# -----------------------------------------------------------
kubectl get nodes

# Agent node'u durdur
k3d node stop k3d-rook-cluster-agent-0

# Pod ve PVC durumu
kubectl get pods
kubectl get pvc

# Node'u geri aç
k3d node start k3d-rook-cluster-agent-0

# -----------------------------------------------------------
# RECLAIM POLICY — PVC silinince ne olur?
# -----------------------------------------------------------
# PV listesi ve Reclaim Policy'yi gör
kubectl get pv

# Delete → PVC silinince PV de silinir (dinamik PV default)
# Retain → PVC silinse de PV kalır (production tercih)
