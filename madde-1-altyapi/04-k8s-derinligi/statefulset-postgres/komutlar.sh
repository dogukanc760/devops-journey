#!/bin/bash
# ============================================================
# Pratik Görev: StatefulSet ile PostgreSQL Deploy Et
#               Pod Restart Sonrası Veri Kalsın
# ============================================================

# 1. StatefulSet + Service oluştur
kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15
        env:
        - name: POSTGRES_PASSWORD
          value: "password123"
        - name: POSTGRES_DB
          value: "testdb"
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
YAML

# 2. Pod ayağa kalksın bekle
kubectl get pods -w

# 3. Veri yaz
kubectl exec -it postgres-0 -- psql -U postgres -d testdb -c "CREATE TABLE test (id serial, name text);"
kubectl exec -it postgres-0 -- psql -U postgres -d testdb -c "INSERT INTO test (name) VALUES ('veri kaybolmadi');"
kubectl exec -it postgres-0 -- psql -U postgres -d testdb -c "SELECT * FROM test;"

# 4. Pod'u sil (StatefulSet yenisini açar)
kubectl delete pod postgres-0
kubectl get pods -w

# 5. Veri hâlâ var mı?
kubectl exec -it postgres-0 -- psql -U postgres -d testdb -c "SELECT * FROM test;"
# Output:
#  id |      name
# ----+-----------------
#   1 | veri kaybolmadi
# Veri kaybolmadı ✅
