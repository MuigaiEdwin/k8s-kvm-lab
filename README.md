# Kubernetes 3-Node Cluster on KVM/QEMU
### Ubuntu 20.04 · kubeadm · Cilium CNI · nginx Deployment

A fully reproducible guide to setting up a 3-node Kubernetes cluster from scratch using KVM virtual machines on a Linux host — including every real issue hit during setup and exactly how they were fixed.

---

## Architecture

```
Linux Host (KVM + QEMU + libvirt)
        │
        ├── master   (control-plane)   <MASTER_IP>
        ├── node1    (worker)          <NODE1_IP>
        └── node2    (worker)          <NODE2_IP>

Network: NAT (192.X.X.X/24) or Bridge to host LAN
CNI:     Cilium (eBPF)
Runtime: containerd
```

---

## Prerequisites

| Item | Spec |
|---|---|
| Host OS | RHEL 9 / Ubuntu 22.04 or similar |
| KVM | kvm, qemu-kvm, libvirt, virt-install |
| VM OS | Ubuntu 20.04 LTS (each VM) |
| VM CPU | 2–4 vCPU per VM |
| VM RAM | 2–4 GB per VM |
| VM Disk | 20–50 GB per VM |
| Kernel | Must be 5.15+ for Cilium eBPF (see note below) |

> **Kernel note:** Ubuntu 20.04 ships with kernel 5.4 by default. Cilium's eBPF dataplane requires `bpf_get_current_cgroup_id()` which the stock 5.4 kernel build does not fully expose even though the version number technically meets the minimum. Install the HWE kernel (5.15) on all nodes before installing Cilium.

---

## Phase 1 — Create the VMs

```bash
# Create each VM — repeat for node1 and node2 changing --name and --disk path
virt-install \
  --name master \
  --virt-type kvm \
  --ram 4096 \
  --vcpus 4 \
  --disk path=/var/lib/libvirt/images/master.qcow2,size=50,format=qcow2 \
  --os-variant ubuntu20.04 \
  --network network=default \
  --graphics vnc,listen=0.0.0.0 \
  --cdrom /path/to/ubuntu-20.04-server.iso \
  --noautoconsole
```

During Ubuntu installation on each VM:
- Set hostname: `master` / `node1` / `node2`
- Create a user account
- ✅ **Tick "Install OpenSSH server"**
- Skip all optional snaps

---

## Phase 2 — Kubernetes Prerequisites (ALL 3 NODES)

SSH into each node and run the following as root.

### 2.1 Disable swap

```bash
swapoff -a
# Comment out the swap line to survive reboots
sed -i '/swap/s/^/#/' /etc/fstab
# Verify
free -h | grep Swap   # should show 0B
```

### 2.2 Enable kernel modules

```bash
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
```

### 2.3 Configure sysctl

```bash
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
```

### 2.4 Install containerd

```bash
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y containerd.io
```

### 2.5 Configure containerd (critical step)

The default containerd install ships with the CRI plugin disabled. Regenerate a clean config and enable SystemdCgroup — if you skip this, `kubeadm join` will fail with a CRI error.

```bash
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

# Enable SystemdCgroup
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd
systemctl status containerd   # must show active (running)
```

### 2.6 Install kubeadm, kubelet, kubectl

```bash
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' \
  | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubeadm kubelet kubectl
apt-mark hold kubeadm kubelet kubectl

systemctl enable --now kubelet
# kubelet will show 'activating' until kubeadm init runs — this is normal
```

### 2.7 Install the HWE kernel (required for Cilium)

```bash
apt-get install -y linux-generic-hwe-20.04
update-grub

# Reboot one node at a time — do NOT reboot all simultaneously
reboot
```

After reboot, verify:
```bash
uname -r   # should show 5.15.x or higher
```

---

## Phase 3 — Initialize the Cluster (MASTER ONLY)

```bash
kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=<MASTER_IP>
```

At the end of the output, kubeadm prints a join command. **Copy it immediately** — you need it in Phase 4.

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

SSH into each worker and run the join command from Phase 3:

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

## Phase 5 — Install Cilium CNI (MASTER ONLY)

```bash
curl -LO https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz
tar xzvf cilium-linux-amd64.tar.gz
sudo mv cilium /usr/local/bin/

cilium install
cilium status --wait
```

Once Cilium reports OK, all nodes flip to Ready:

```bash
kubectl get nodes
# NAME     STATUS   ROLES           VERSION
# master   Ready    control-plane   v1.29.x
# node1    Ready    <none>          v1.29.x
# node2    Ready    <none>          v1.29.x
```

---

## Phase 6 — Deploy nginx (Verification)

```bash
# Create a 2-replica nginx deployment
kubectl create deployment nginx --image=nginx --replicas=2

# Expose it via NodePort
kubectl expose deployment nginx --port=80 --type=NodePort

# Check the assigned port
kubectl get svc nginx
# NAME    TYPE       CLUSTER-IP    PORT(S)        AGE
# nginx   NodePort   10.x.x.x      80:<NODE_PORT>/TCP   1m

# Access from browser or curl
curl http://<ANY_NODE_IP>:<NODE_PORT>
```

You should get the nginx welcome page. ✅

---

## Known Issues & Fixes

### CRI not running on kubeadm join
**Error:** `container runtime is not running: unknown service runtime.v1.RuntimeService`

**Fix:** The default containerd config has the CRI plugin disabled. Regenerate it:
```bash
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl restart containerd
```

---

### Cilium agent fails on Ubuntu 20.04 stock kernel
**Error:** `bpf_get_current_cgroup_id() not available`

**Fix:** Install the HWE kernel to get 5.15:
```bash
apt-get install -y linux-generic-hwe-20.04
update-grub && reboot
```

---

### Swap re-enables after reboot, kubelet fails to start
**Fix:** Comment out the swap entry in `/etc/fstab`:
```bash
sed -i '/swap/s/^/#/' /etc/fstab
swapoff -a
```

---

### Node loses IP after reboot (DHCP delay)
**Fix:** If SSH is unreachable after reboot, use console access and renew DHCP:
```bash
netplan apply
# or
networkctl renew <interface>
```

For the master node specifically, set a **static IP via netplan** to avoid this:
```yaml
# /etc/netplan/50-cloud-init.yaml
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: false
      addresses:
        - <MASTER_IP>/24
      routes:
        - to: default
          via: <GATEWAY>
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
```
```bash
netplan apply
```

---

### Pod stuck in Terminating
**Fix:** Force delete it:
```bash
kubectl delete pod <pod-name> --grace-period=0 --force
```
Then regenerate containerd config if the issue persists (cgroup path mismatch):
```bash
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl restart containerd
```

---

## Verification Checklist

```bash
# All nodes Ready
kubectl get nodes

# All system pods running
kubectl get pods -n kube-system

# Cilium healthy
cilium status

# nginx accessible
curl http://<ANY_NODE_IP>:<NODE_PORT>
```

---

## What's Next

- [ ] Set static IPs on node1 and node2 (currently DHCP)
- [ ] Deploy Harbor private container registry
- [ ] Set up ingress controller (nginx-ingress or Traefik)
- [ ] Add persistent storage (local-path-provisioner or NFS)
