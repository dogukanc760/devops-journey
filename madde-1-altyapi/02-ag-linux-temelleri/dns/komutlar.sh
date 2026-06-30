#!/bin/bash
# ============================================================
# DNS & CoreDNS Komutlar
# ============================================================

# -----------------------------------------------------------
# TEMEL DNS SORGULARI
# -----------------------------------------------------------

# DNS çözümleme
dig google.com
dig google.com @8.8.8.8

# Reverse lookup (IP → domain)
dig -x 8.8.8.8

# -----------------------------------------------------------
# COREDNS CONFIG'İ GÖRÜNTÜLE
# -----------------------------------------------------------

kubectl get configmap coredns -n kube-system -o yaml

# -----------------------------------------------------------
# CUSTOM DOMAIN SENARYOSU: myapp.local → ClusterIP
# -----------------------------------------------------------

# 1. Test deployment ve servis kur
kubectl create deployment test-app --image=nginx
kubectl expose deployment test-app --port=80 --name=test-app-svc

# 2. ClusterIP'yi al
kubectl get svc test-app-svc
# Output:
# NAME           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
# test-app-svc   ClusterIP   10.43.162.62   <none>        80/TCP    9s

# 3. Custom CoreDNS ConfigMap ekle
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  myapp.server: |
    myapp.local:53 {
        errors
        cache 30
        hosts {
            10.43.162.62 myapp.local
            fallthrough
        }
    }
EOF

# 4. CoreDNS'i yeniden başlat
kubectl rollout restart deployment coredns -n kube-system

# 5. Test et — pod içinden domain'i çözümle
kubectl run test-dns --image=busybox --restart=Never --rm -it -- nslookup myapp.local
# Output:
# Server:    10.43.0.10        ← CoreDNS'in IP'si
# Address:   10.43.0.10:53
# Name:      myapp.local
# Address:   10.43.162.62      ← servisin ClusterIP'si

# -----------------------------------------------------------
# AKIŞ ÖZETI
# -----------------------------------------------------------
# nslookup myapp.local
#   → CoreDNS "myapp.local = 10.43.162.62" döner
#   → Client 10.43.162.62:80'e istek atar
#   → kube-proxy (iptables DNAT) → PodIP:80
#   → nginx pod cevap verir
