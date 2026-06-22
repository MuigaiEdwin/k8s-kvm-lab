# 04 — Cilium CNI Install + Kernel Fix

After all 3 nodes joined the cluster (still showing `NotReady` — expected, no CNI yet), Cilium was installed as the CNI on the **master** node.

## Phase 5 — Install Cilium CNI (MASTER ONLY)

```bash
curl -LO https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz
tar xzvf cilium-linux-amd64.tar.gz
sudo mv cilium /usr/local/bin/

cilium install
cilium status --wait
```

Once Cilium reports `OK`, all nodes flip to `Ready`:

```bash
kubectl get nodes
# NAME     STATUS   ROLES           VERSION
# master   Ready    control-plane   v1.29.x
# node1    Ready    <none>          v1.29.x
# node2    Ready    <none>          v1.29.x
```

---

## Kernel Fix (root cause hit during setup)

**Symptom:**
```
Error: bpf_get_current_cgroup_id() not available
```

**Cause:** Ubuntu 20.04's stock kernel (5.4) doesn't fully expose the eBPF helpers Cilium's dataplane needs, even though the version number nominally clears the minimum.

**Fix:** Install the HWE kernel (5.15) on every node before installing Cilium — this is covered in `02-prerequisites.md` step 2.7:

```bash
apt-get install -y linux-generic-hwe-20.04
update-grub && reboot
```

Confirm post-reboot:

```bash
uname -r   # 5.15.x or higher
```

---

## Verify Cilium Health

```bash
cilium status
kubectl get pods -n kube-system
```

All Cilium agent pods should be `Running`, and `cilium status` should report overall health as `OK`.

Next: deploy the verification workload — see `05-deploy-nginx.md`.

---

## Known Issue — Pod Stuck in `Terminating`

**Symptom:** A pod hangs indefinitely in `Terminating` state and never fully deletes.

**Cause:** Usually a cgroup path mismatch between containerd and kubelet, or a stale CNI attachment left behind by Cilium during a network change.

**Fix — force delete the pod:**

```bash
kubectl delete pod <pod-name> --grace-period=0 --force
```

**If it recurs**, re-check that the containerd config still has `SystemdCgroup` enabled and restart it:

```bash
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl restart containerd
```
