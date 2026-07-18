#!/bin/bash
# ============================================================
# Pratik Görev: etcd Backup Al ve Restore Et
# ============================================================

# k3s ile etcd snapshot al
docker exec -it k3d-ha-cluster-server-0 sh -c "k3s etcd-snapshot save"
# Output: INFO Snapshot on-demand-k3d-ha-cluster-server-0-XXXX saved.

# Snapshot'ı listele
docker exec -it k3d-ha-cluster-server-0 sh -c "ls /var/lib/rancher/k3s/server/db/snapshots/"

# Snapshot'ı dışarı kopyala
docker cp k3d-ha-cluster-server-0:/var/lib/rancher/k3s/server/db/snapshots/ ./etcd-snapshots/

# RESTORE (bare-metal ortamında yapılacak)
# k3s server'ı durdur
# systemctl stop k3s
# Restore et
# k3s etcd-snapshot restore /var/lib/rancher/k3s/server/db/snapshots/on-demand-xxx
# k3s server'ı başlat
# systemctl start k3s

# NOT: k3d'de restore farklı cluster gerektirir — bare-metal'a ertelendi
