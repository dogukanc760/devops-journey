#!/bin/bash
# ============================================================
# Dağıtık Storage — Pratik Görevler İndeksi
# ============================================================
# Her pratik görev kendi klasöründe:
#
# rook-ceph/komutlar.sh         → Rook-Ceph kur, 3-node Ceph cluster
#                                  NOT: k3d'de çalışmaz, bare-metal gerekir
#
# longhorn/komutlar.sh          → Longhorn kur (k3d'de çalışır)
#
# storageclass-pv-pvc/komutlar.sh → PVC oluştur, pod'a bağla, veri yaz
#                                    Disk simülasyonu, Reclaim Policy
# ============================================================
