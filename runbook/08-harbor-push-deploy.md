# Pushing to Harbor and Deploying into the Cluster

Got Harbor running as my private registry, then proved it actually works end-to-end -> push an image in, pull it back out from inside Kubernetes.

## Why

No point running a private registry if the cluster can't actually use it. Wanted to confirm the full loop: build/pull an image → push to Harbor → have a pod inside the cluster pull that exact image back from Harbor instead of the public internet.

## Steps

### 1. Logged into Harbor from Docker

```bash
docker login <NODE_IP>
```

Used my admin credentials. Confirmed login succeeded before touching anything else.

### 2. Pulled a test image

```bash
docker pull nginx
```

Used nginx since it's small and quick to validate the pipeline with — didn't need anything fancy for this test.

### 3. Tagged it for my Harbor registry

```bash
docker tag nginx <NODE_IP>/library/nginx:v1
```

Harbor needs the image tagged with its registry address and project name (`library` is the default project) before it'll accept a push.

### 4. Pushed it to Harbor

```bash
docker push <NODE_IP>/library/nginx:v1
```

Went through clean. Confirmed in the Harbor UI (`<NODE_IP>` → library project → Repositories) that `library/nginx:v1` was sitting there.

### 5. Pointed a Kubernetes deployment at the Harbor image

```bash
kubectl set image deployment/nginx nginx=<NODE_IP>/library/nginx:v1
```

This is the actual test -> telling an existing deployment to pull from my registry instead of Docker Hub.

### 6. Hit the first wall - containerd refused the pull

```
failed to resolve reference "<NODE_IP>/library/nginx:v1": 
dial tcp <NODE_IP>:443: connect: connection refused
```

Containerd was trying HTTPS by default. Harbor's running plain HTTP (no TLS cert set up), so this was always going to fail until containerd was told to trust it as an insecure/HTTP registry.

### 7. Fixed containerd on master

Edited `/etc/containerd/config.toml`, added a mirror entry for Harbor's IP under the CRI registry config:

```toml
[plugins."io.containerd.grpc.v1.cri".registry.mirrors]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."<NODE_IP>"]
    endpoint = ["<NODE_IP>"]
```

Restarted containerd:

```bash
sudo systemctl restart containerd
```

### 8. Forced the deployment to retry

```bash
kubectl rollout restart deployment/nginx
kubectl get pods -w
```

Pods came up `1/1 Running` on the retry.

### 9. Checked where the pods actually landed

```bash
kubectl get pods -o wide
```

Both replicas landed on node1 and node2 - not master. That mattered, because it meant the worker nodes needed to pull from Harbor too, not just master.

### 10. Confirmed worker nodes were already fine

Checked containerd config on node1 and node2 for the same Harbor mirror entry — turned out they pulled successfully without needing the manual fix I'd applied on master. Worth flagging as a slightly unresolved question (why they didn't need it), but the pulls worked, confirmed by `kubectl describe pod` showing the correct Harbor image on both.

## Result

- Image pushed to Harbor: ✅
- Pod pulling that exact image from Harbor instead of Docker Hub: ✅
- Confirmed on both worker nodes, not just master: ✅

Cluster now has a working private registry it can actually pull from - next step is wiring this into CI so the push happens automatically on every commit instead of by hand.
I will have to switch this repo to a private one due to harbor
