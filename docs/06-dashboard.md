# 06 — Deploy and Access the Kubernetes Dashboard

With the cluster up, Cilium healthy, and the nginx verification deployment working (`05-deploy-nginx.md`), the Kubernetes Dashboard was deployed as a web UI for inspecting and managing cluster resources.

Reference: [Deploy and Access the Kubernetes Dashboard — kubernetes.io](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/)

## Step 1 — Deploy the Dashboard

Run on the **master** node (or anywhere with `kubectl` configured against the cluster):

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/<DASHBOARD_VERSION>/aio/deploy/recommended.yaml
```

> Check the [Dashboard releases page](https://github.com/kubernetes/dashboard/releases) for the latest stable tag to substitute for `<DASHBOARD_VERSION>` (e.g. `v2.7.0`).

This creates a dedicated `kubernetes-dashboard` namespace along with the dashboard Deployment, Service, Secrets, and RBAC resources.

**Verify the pods came up:**

```bash
kubectl get pods -n kubernetes-dashboard
kubectl get svc -n kubernetes-dashboard
```

All pods should reach `Running`.

---

## Step 2 — Create an Admin Service Account

The Dashboard needs a token to authenticate. A dedicated admin service account was created rather than reusing the default one:

```bash
kubectl create serviceaccount dashboard-admin-sa -n kubernetes-dashboard
```

Bind it to the built-in `cluster-admin` ClusterRole:

```bash
kubectl create clusterrolebinding dashboard-admin-sa \
  --clusterrole=cluster-admin \
  --serviceaccount=kubernetes-dashboard:dashboard-admin-sa
```

> **Note:** `cluster-admin` grants full cluster access. That's fine for a personal lab; for anything shared or production-like, scope this down to a narrower Role/ClusterRole instead.

---

## Step 3 — Generate a Login Token

```bash
kubectl -n kubernetes-dashboard create token dashboard-admin-sa
```

This prints a token (`<TOKEN>`) — copy it. It's short-lived by default; regenerate with the same command whenever it expires.

---

## Step 4 — Access the Dashboard

The Dashboard's API server is ClusterIP-only by default, so it's not reachable directly from outside the cluster. `kubectl proxy` was used to tunnel access:

```bash
kubectl proxy
```

With the proxy running, the Dashboard is reachable at:

```
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

Open that URL in a browser, choose **Token** as the sign-in method, and paste the `<TOKEN>` from Step 3.

---

## Known Issues & Fixes

### Dashboard pod stuck in `Pending`
**Cause:** Usually insufficient resources on the node, or scheduling constraints left over from taints on `master`.

**Fix:** Check events and confirm worker nodes have capacity:
```bash
kubectl describe pod -n kubernetes-dashboard <pod-name>
kubectl get nodes -o wide
```

### `kubectl proxy` connection refused remotely
**Cause:** `kubectl proxy` binds to `localhost` by default, so it isn't reachable from another machine over the network.

**Fix (lab-only, not for production):** bind to all interfaces and accept any host:
```bash
kubectl proxy --address='0.0.0.0' --accept-hosts='^.*$'
```
Treat this as throwaway-lab convenience only — it removes a layer of access control.

### Token expired / login rejected
**Fix:** Tokens created via `kubectl create token` are short-lived. Generate a fresh one:
```bash
kubectl -n kubernetes-dashboard create token dashboard-admin-sa
```

---

## Verification Checklist

```bash
# Dashboard pods running
kubectl get pods -n kubernetes-dashboard

# Service exists
kubectl get svc -n kubernetes-dashboard

# Token generates successfully
kubectl -n kubernetes-dashboard create token dashboard-admin-sa

# Proxy reachable
curl -sk http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/ -o /dev/null -w "%{http_code}\n"
```
