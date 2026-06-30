#!/bin/bash
# ============================================================
# iptables Komutlar & Notlar
# ============================================================
# k3d cluster node'u içinde çalıştırılır:
# docker exec -it k3d-ha-cluster-server-0 sh
# ============================================================

# -----------------------------------------------------------
# MEVCUT KURALLARI GÖRÜNTÜLE
# -----------------------------------------------------------

# Tüm filter table kuralları
iptables -L -n -v

# NAT table kuralları (K8s DNAT kuralları burada)
iptables -t nat -L -n -v | head -50

# FORWARD chain — satır numarasıyla
iptables -L FORWARD --line-numbers

# INPUT chain — satır numarasıyla
iptables -L INPUT --line-numbers -n

# -----------------------------------------------------------
# SENARYO 1: BU NODE'A BELİRLİ PORTTAN SADECE BELİRLİ IP'DEN ERİŞİM
# (Pratik görev senaryosu)
# -----------------------------------------------------------

# 9090 portuna sadece 10.42.0.1'den erişime izin ver
iptables -A INPUT -p tcp --dport 9090 -s 10.42.0.1 -j ACCEPT

# Diğer tüm kaynaklardan 9090'a gelen trafiği drop et
iptables -A INPUT -p tcp --dport 9090 -j DROP

# Kontrol et
iptables -L INPUT --line-numbers -n

# BOZMA SENARYOSU: DROP kuralını sil → her yerden erişim açılır
iptables -D INPUT -p tcp --dport 9090 -j DROP
iptables -L INPUT --line-numbers -n

# -----------------------------------------------------------
# SENARYO 2: NAT GATEWAY / ROUTER SENARYOSU
# (Dogukan'ın yazdığı — daha advanced)
# Bir iç IP'ye (192.168.1.5:80) dışarıdan gelen trafiği yönlendir
# -----------------------------------------------------------

# FORWARD: 192.168.1.5'e port 80 trafiğini kabul et
iptables -A FORWARD -p tcp -d 192.168.1.5 --dport 80 -j ACCEPT

# PREROUTING: dışarıdan 80'e gelen trafik → 192.168.1.5:80'e DNAT
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 192.168.1.5:80

# POSTROUTING: eth0'dan çıkan 192.168.1.0/24 trafiğini masquerade et (SNAT)
iptables -t nat -A POSTROUTING -o eth0 -s 192.168.1.0/24 -j MASQUERADE

# Kontrol et
iptables -L FORWARD --line-numbers
iptables -t nat -L -n -v

# -----------------------------------------------------------
# K8S DNAT KURALLARINI GÖZLEMLE
# -----------------------------------------------------------

# K8s Service DNAT zinciri — pod IP'lerine yönlendirme burada
iptables -t nat -L KUBE-SERVICES -n -v

# CNI port forward DNAT — 80/443 → pod IP
# Çıktıda şunu görürsün:
# DNAT tcp dpt:80  to:10.42.0.7:80
# DNAT tcp dpt:443 to:10.42.0.7:443
