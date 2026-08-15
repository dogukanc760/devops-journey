#!/bin/bash
# ============================================================
# Merkezi Loglama ve Metrik Alarmları (Loki/Promtail/Grafana) - Komutlar & Notlar
# ============================================================
# Her komutu çalıştırmadan önce ne yaptığını anla.
# Çıktıyı gözlemle, notlar.md'ye ekle.
# ============================================================

# ------------------------------------------------------------
# ADIM 1: Cluster + kube-prometheus-stack + loki-stack kurulumu
# ------------------------------------------------------------

k3d cluster create observability-cluster

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace
# SONUÇ: Prometheus, Grafana, Alertmanager ve kube-state-metrics
# hepsi birden ayağa kalktı, Grafana'ya Prometheus datasource'u
# otomatik eklendi.

helm install loki grafana/loki-stack \
  -n monitoring \
  --set grafana.enabled=false \
  --set promtail.enabled=true
# SONUÇ: loki-0 (StatefulSet) ve promtail (DaemonSet, her node'da
# bir pod) Running durumuna geçti.

kubectl -n monitoring get pods
# SONUÇ: prometheus, grafana, alertmanager, kube-state-metrics,
# loki-0, promtail-xxxxx (node sayısı kadar) hepsi Running.


# ------------------------------------------------------------
# ADIM 2: Grafana'ya Loki'yi datasource olarak ekle
# ------------------------------------------------------------

kubectl -n monitoring port-forward svc/kube-prometheus-grafana 3000:80 &
# Grafana admin şifresi:
kubectl -n monitoring get secret kube-prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d
# SONUÇ: şifre decode edildi, http://localhost:3000 üzerinden giriş
# yapıldı.

# Grafana UI > Connections > Data Sources > Add data source > Loki
# URL: http://loki.monitoring:3100
# SONUÇ: "Data source is working" onayı alındı.


# ------------------------------------------------------------
# ADIM 3: Kasıtlı crash loop yapan bir pod tanımla
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: crash-loop-demo
  labels:
    app: crash-loop-demo
spec:
  restartPolicy: Always
  containers:
  - name: crasher
    image: busybox
    command: ["sh", "-c", "echo 'ERROR: veritabani baglantisi kurulamadi, cikiliyor'; sleep 5; exit 1"]
EOF

kubectl get pod crash-loop-demo --watch
# SONUÇ:
# NAME               READY   STATUS             RESTARTS   AGE
# crash-loop-demo    0/1     CrashLoopBackOff    1          25s
# crash-loop-demo    0/1     CrashLoopBackOff    2          55s
# crash-loop-demo    0/1     CrashLoopBackOff    3          95s
# crash-loop-demo    0/1     CrashLoopBackOff    5          3m


# ------------------------------------------------------------
# ADIM 4: kubectl logs'un sınırını, Loki'nin sınırsızlığını karşılaştır
# ------------------------------------------------------------

kubectl logs crash-loop-demo
# SONUÇ: sadece EN SON (current) container denemesinin logu geldi.

kubectl logs crash-loop-demo --previous
# SONUÇ: bir önceki (restart'tan hemen önceki) denemenin logu geldi,
# bundan öncekiler (1. ve 2. restart) ARTIK ERİŞİLEMEZ, tamamen kayıp.

# Grafana > Explore > Loki datasource, LogQL sorgusu:
# {app="crash-loop-demo"}
# SONUÇ: TÜM restart'ların ("ERROR: veritabani baglantisi kurulamadi,
# cikiliyor" satırı) her biri, zaman damgalarıyla birlikte eksiksiz
# listelendi, kubectl logs --previous'un gösteremediği 1. ve 2.
# restart'ın logları da dahil. Promtail'in sürekli/anlık gönderimi
# sayesinde pod'un yaşam döngüsünden bağımsız kalıcılık doğrulandı.


# ------------------------------------------------------------
# ADIM 5: kube-state-metrics üzerinden restart sayısını PromQL ile izle
# ------------------------------------------------------------

kubectl -n monitoring port-forward svc/kube-prometheus-kube-prome-prometheus 9090:9090 &

# Prometheus UI > Graph, PromQL sorgusu:
# kube_pod_container_status_restarts_total{pod="crash-loop-demo"}
# SONUÇ: değer zamanla 1, 2, 3, 5 şeklinde artan bir sayaç olarak
# göründü, K8s'in kendi tuttuğu OBJE DURUMU, hiçbir log parse etmeye
# gerek kalmadan.


# ------------------------------------------------------------
# ADIM 6: PromQL bazlı alert rule yaz (restart eşiği)
# ------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: crash-loop-alert
  namespace: monitoring
  labels:
    release: kube-prometheus
spec:
  groups:
  - name: crash-loop
    rules:
    - alert: PodCrashLoopingTooMuch
      expr: kube_pod_container_status_restarts_total{pod="crash-loop-demo"} > 3
      for: 30s
      labels:
        severity: critical
      annotations:
        summary: "{{ \$labels.pod }} 3'ten fazla restart oldu"
EOF

kubectl -n monitoring port-forward svc/kube-prometheus-kube-prome-alertmanager 9093:9093 &
# Alertmanager UI'da alert:
# SONUÇ: PodCrashLoopingTooMuch alert'i "firing" durumuna geçti,
# restart sayısı 3'ü geçtiği an (5. restart'ta) tetiklendi.
# Gerçek Slack workspace'i yoktu, Alertmanager'ın receiver'ı yerel
# bir webhook alıcısına (basit bir python http.server, gelen POST'u
# alert-log.txt'e yazan) yönlendirildi:
cat alert-log.txt
# SONUÇ: [timestamp] PodCrashLoopingTooMuch FIRING - crash-loop-demo
# 3'ten fazla restart oldu


# ------------------------------------------------------------
# ADIM 7: Karşılaştırma için LogQL bazlı bir alert de dene
# ------------------------------------------------------------
# MANTIK: Bu sefer "ERROR" içeren log satırlarının sıklığını Loki'nin
# kendi metrik-benzeri sorgu fonksiyonuyla (count_over_time) izleyip
# alert'e bağlıyoruz, PromQL'e alternatif olarak.

# Grafana > Alerting > New alert rule, Loki datasource, sorgu:
# count_over_time({app="crash-loop-demo"} |= "ERROR" [1m])
# Koşul: > 3

# SONUÇ: Bu alert de tetiklendi, AMA PromQL tabanlı alert'ten daha
# GEÇ tetiklendi (log satırının Promtail tarafından toplanıp Loki'ye
# yazılması, indekslenmesi bir miktar gecikme ekliyor), ayrıca "ERROR"
# string'i uygulamanın GERÇEKTEN o satırı loglamasına bağımlı, eğer
# process sinyal yiyip hiç log basamadan ölseydi (örn. OOMKilled) bu
# alert HİÇ tetiklenmezdi, PromQL tabanlı restart sayacı ise K8s
# seviyesinde tutulduğu için her durumda çalışırdı.


# ------------------------------------------------------------
# ÖZET
# ------------------------------------------------------------
# kubectl logs, pod'un container runtime'ının tuttuğu çok sınırlı bir
# kopyaya bakar, restart'ları aşamaz. Loki, Promtail'in sürekli/anlık
# gönderimi sayesinde pod'un yaşam döngüsünden bağımsız kalıcı bir
# log deposu sağladı, TÜM restart'ların logu eksiksiz sorgulanabildi.
# Crash loop ALERT'i için PromQL (kube_pod_container_status_restarts_total)
# hem daha hızlı hem daha güvenilir çıktı, çünkü K8s'in kendi tuttuğu
# yapısal bir durumu okuyor, uygulamanın bir şey loglamasına bağımlı
# değil. LogQL tabanlı alert de çalıştı ama daha yavaş ve uygulamanın
# gerçekten o satırı basabilmiş olmasına bağımlı, yani daha kırılgan.
# Genel kural doğrulandı: yapısal/sayısal veri varsa PromQL, sadece
# serbest metinde aranıyorsa LogQL.
