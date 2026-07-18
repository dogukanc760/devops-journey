#!/bin/bash
# ============================================================
# Pratik Görev: Control Plane Sağlığını Kontrol Et
# ============================================================

# Control Plane bileşen durumu
kubectl get componentstatuses
# Output:
# NAME                 STATUS    MESSAGE   ERROR
# scheduler            Healthy   ok
# controller-manager   Healthy   ok
# etcd-0               Healthy   ok

# Node durumu ve Kubelet conditions
kubectl describe node k3d-ha-cluster-server-0 | grep -A 10 "Conditions"
# Sağlıklı node:
# MemoryPressure: False
# DiskPressure:   False
# Ready:          True
