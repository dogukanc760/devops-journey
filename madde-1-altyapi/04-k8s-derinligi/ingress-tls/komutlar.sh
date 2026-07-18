#!/bin/bash
# ============================================================
# Pratik Görev: Nginx Ingress Kur, TLS Termination ile Dış Trafik Yönlendir
# ============================================================

# 1. Nginx Ingress Controller kur
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
kubectl -n ingress-nginx get pods -w

# 2. Self-signed TLS sertifikası oluştur
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=myapp.local/O=myapp"

# 3. TLS secret oluştur
kubectl create secret tls myapp-tls --key tls.key --cert tls.crt

# 4. Deployment + Service + Ingress oluştur
kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: nginx
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: myapp-svc
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.local
    secretName: myapp-tls
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp-svc
            port:
              number: 80
YAML

# 5. /etc/hosts'a ekle (Mac'te)
echo "127.0.0.1 myapp.local" | sudo tee -a /etc/hosts

# 6. Test et
# NOT: k3d'de MetalLB olmadığı için external IP <pending> kalır
# Nginx'e port-forward ile ulaş
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 9443:443

# Yeni terminalde:
curl -k -H "Host: myapp.local" https://127.0.0.1:9443
# Output: Welcome to nginx!

# Akış:
# curl HTTPS → port-forward → Nginx Ingress (TLS termination) → myapp-svc → Pod
