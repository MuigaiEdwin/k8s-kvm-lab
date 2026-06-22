# 03 — Cluster Initialization (kubeadm init + join)

With prerequisites satisfied on all nodes (`02-prerequisites.md`), the control plane was initialized on `master`, then `node1` and `node2` joined as workers.


## Phase 3 — Initialize the Cluster (MASTER ONLY)

```bash
kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=<MASTER_IP>
```

At the end of the output, `kubeadm` prints a join command — copy it immediately, it's needed in Phase 4.

### Configure kubectl

```bash
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Verify — master will show NotReady until Cilium is installed
kubectl get nodes
```

---

## Phase 4 — Join Worker Nodes (node1 AND node2)

SSH into each worker and run the join command captured above:

```bash
kubeadm join <MASTER_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

If the token has expired (tokens last 24 hours), generate a fresh one on master:

```bash
kubeadm token create --print-join-command
```

On master, verify both workers joined:

```bash
kubectl get nodes
# All 3 will show NotReady — correct, no CNI yet
```

---

Next step: install Cilium so all nodes flip to `Ready` — see `04-cilium.md`.
