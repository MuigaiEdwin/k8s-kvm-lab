# Log Aggregation with Loki + Promtail

Centralized logging for the k8s-kvm-lab cluster. Instead of `kubectl logs` on one pod at a time, all logs land in one place and I can search across the whole cluster from Grafana.

Base guide: [Deploy Loki for Log Aggregation in Kubernetes](https://computingforgeeks.com/deploy-loki-kubernetes/), adapted for a Ceph-backed cluster instead of local-path storage.

## Stack

| Component | Role |
|---|---|
| Loki | Stores and indexes logs |
| Promtail | Ships logs from every node into Loki |
| Grafana | Queries and displays logs (already running from the Prometheus stack) |

## Prerequisites

- A working cluster with a `monitoring` namespace and the kube-prometheus-stack already deployed
- A working StorageClass. I use Ceph via `csi-rbd-sc` — check yours before starting:

```bash
kubectl get storageclass
```

## Setup

### 1. Add the Helm repo

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### 2. Configure Loki

The tutorial's values file assumes `local-path` storage. Swap that for whatever StorageClass my s cluster actually has:

```yaml
# loki-values.yaml
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h
  storage:
    type: filesystem

deploymentMode: SingleBinary
singleBinary:
  replicas: 1
  persistence:
    enabled: true
    storageClass: csi-rbd-sc
    size: 10Gi
```

### 3. Install Loki

```bash
helm install loki grafana/loki --namespace monitoring --values loki-values.yaml --wait --timeout 5m
```

### 4. Verify

The Loki image ships without `curl` or `wget`, so I did check from outside the pod:

```bash
kubectl port-forward -n monitoring svc/loki 3100:3100 &
curl http://localhost:3100/ready
```

Expected: `ready` and funny enoguh : came ready

### 5. Install Promtail

Loki stores logs; Promtail collects them. Point it at Loki's push endpoint:

```yaml
# promtail-values.yaml
config:
  clients:
    - url: http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push
```

```bash
helm install promtail grafana/promtail --namespace monitoring --values promtail-values.yaml --wait
```

Promtail runs as a DaemonSet, so confirm every node has a pod:

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail -o wide
```

### 6. Confirm logs are flowing

```bash
curl "http://localhost:3100/loki/api/v1/query_range" --data-urlencode 'query={namespace="monitoring"}'
```

A non-empty result means Promtail is successfully shipping logs into Loki.

### 7. Add Loki as a Grafana data source

Grafana → **Connections** → **Data Sources** → **Add new data source** → **Loki**

URL:
```
http://loki.monitoring.svc.cluster.local:3100
```

Save & Test.

### 8. Query in Explore

Grafana → **Explore** → select the Loki data source → run a query:

```
{namespace="monitoring"}
```

Live log lines should appear from every pod in that namespace.

## Troubleshooting log

### Pod stuck `Pending`, PVC never binds

**Symptom:** `helm install` times out waiting for the StatefulSet.

**Cause:** the values file referenced a StorageClass that doesn't exist on this cluster (copied the tutorial's `local-path` without checking).

**Fix:** confirm the real StorageClass first, then set it explicitly:

```bash
kubectl get storageclass
kubectl get pvc -n monitoring   # a stuck PVC with no bound volume is the tell
```

### Grafana: "Unable to connect with Loki"

**Symptom:** Save & Test fails, Loki itself responds fine to `curl` from a port-forward.

**Diagnosis:** checked Grafana's own pod logs, since the error banner doesn't say much:

```bash
kubectl logs -n monitoring <grafana-pod> -c grafana --tail=30
```

Found the real error underneath:

```
dial tcp <node-ip>:3100: i/o timeout
```

That IP has nothing to do with the cluster. Something was resolving the Loki hostname to the wrong address.

**Root cause:** this cluster injects a corporate DNS search domain into every pod's resolver config, on top of the usual Kubernetes ones:

```
search monitoring.svc.cluster.local svc.cluster.local cluster.local ocpkiboswa01.safaricom.net
options ndots:5
```

With `ndots:5`, any hostname with fewer than 5 dots gets each search domain tried first, in order, before the resolver tries it as-is. `loki.monitoring.svc.cluster.local` has 4 dots, so it fell into that path — and the corporate domain has what looks like a wildcard DNS record, so the bogus lookup "succeeded" before the correct one was ever tried.

`nslookup` didn't show the problem because it queries the name mostly as given. `getent hosts` and Grafana's own resolver (Go, using the OS-level path) walk the full search list and hit the wildcard.

**Fix:** anchor the URL with a trailing dot so the resolver treats it as already fully qualified and skips the search list:

```
http://loki.monitoring.svc.cluster.local.:3100
```

## Takeaways

- On a managed or corporate cluster, inspect `/etc/resolv.conf` from inside a pod early. The `ndots` + search-domain interaction is a Kubernetes classic, and it'll surface on any internal service call, not just this one
- Going forward, internal service URLs on this cluster get a trailing dot by default, to route around the corporate DNS wildcard for good