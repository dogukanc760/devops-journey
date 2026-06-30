#!/bin/bash
# ============================================================
# vmstat / iostat / sar — Sistem Metrikleri
# ============================================================
# k3d node'u minimal olduğu için Ubuntu pod içinde çalıştırılır:
# kubectl run metrics-test --image=ubuntu --restart=Never -it -- bash
# apt update && apt install -y procps sysstat
# ============================================================

# -----------------------------------------------------------
# VMSTAT — Sistem Genel Durumu
# -----------------------------------------------------------

# Her 1 saniyede bir, 5 kez
vmstat 1 5

# Çıktı yorumu:
# r      → run queue (kaç process CPU bekliyor, yüksekse CPU darboğazı)
# b      → blocked process (disk/IO bekliyor)
# swpd   → swap kullanımı (0 olmalı, değilse memory yetersiz)
# si/so  → swap in/out (0 olmalı)
# bi/bo  → disk block in/out
# us/sy  → user/system CPU kullanımı
# id     → idle CPU (yüksek olmalı, ~95 sağlıklı)
# wa     → iowait (yüksekse disk darboğazı)

# Örnek sağlıklı çıktı:
#  r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa
#  2  0      0 250144 194936 3865404   0    0   461  1652 10706  17  3  2 95  0

# -----------------------------------------------------------
# IOSTAT — Disk I/O Durumu
# -----------------------------------------------------------

# Her 1 saniyede bir, 5 kez
iostat 1 5

# Çıktı yorumu:
# %user    → user space CPU kullanımı
# %system  → kernel CPU kullanımı
# %iowait  → CPU'nun disk beklemesi (>10 ise sorun var)
# %idle    → boşta CPU (~95 sağlıklı)
# tps      → saniyedeki transfer sayısı
# kB_read/s → okuma hızı
# kB_wrtn/s → yazma hızı

# Örnek çıktı:
# avg-cpu: %user  %nice  %system  %iowait  %steal  %idle
#           2.52   0.00     2.01     0.20    0.00   95.27
# Device    tps   kB_read/s  kB_wrtn/s
# vda     114.06     373.35    1662.03   ← K8s başlarken yüksek write normal

# -----------------------------------------------------------
# SAR — Geçmişe Dönük Metrik
# -----------------------------------------------------------

# CPU kullanımı
sar -u 1 5

# Memory kullanımı
sar -r 1 5

# Disk I/O
sar -d 1 5

# -----------------------------------------------------------
# BOZMA SENARYOLARI — Ne görürsen ne anlarsın?
# -----------------------------------------------------------

# swpd > 0      → memory yetersiz, swap kullanılıyor → node upgrade gerekebilir
# iowait > 10   → disk darboğazı → storage class veya disk değiştir
# r sürekli > 4 → CPU darboğazı → node sayısını artır veya pod limit koy
# b > 0         → process'ler disk/IO bekliyor → I/O yoğun workload var
