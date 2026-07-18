#!/bin/bash
# ============================================================
# Pratik Görev: Kubelet Loglarını İncele
# NOT: k3d'de journalctl yok, alternatif yollar kullanılır
# ============================================================

# k3d node içindeki kubelet process'i gör
docker exec -it k3d-ha-cluster-server-0 sh -c "ps aux | grep kubelet"

# Kubelet logları (k3s içine gömülü)
docker logs k3d-ha-cluster-server-0 2>&1 | tail -30

# Node event'leri
kubectl get events --field-selector reason=NodeReady
kubectl describe node k3d-ha-cluster-server-0 | grep -A 5 "Events"
