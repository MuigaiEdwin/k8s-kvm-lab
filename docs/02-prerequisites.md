# 02 > Kubernetes Prerequisites (All Nodes)

These steps were run on **every node** (`master`, `node1`, `node2`) as root, after the VMs were provisioned (see `01-virtualization.md`).


## VM Specs Used

| Item | Spec |
|---|---|
| VM OS | Ubuntu 20.04 LTS |
| VM CPU | 2–4 vCPU per VM |
| VM RAM | 2–4 GB per VM |
| VM Disk | 20–50 GB per VM |
| Kernel | 5.15+ required for Cilium eBPF (see note below) |

**Kernel note:** Ubuntu 20.04 ships with kernel 5.4 by default. Cilium's eBPF dataplane requires `bpf_get_current_cgroup_id()`, which the stock 5.4 kernel build doesn't fully expose even though the version number technically meets the minimum. The HWE kernel (5.15) was installed on all nodes before installing Cilium.


## 2.1 - Disable swap

```bash
swapoff -a
# Comment out the swap line to survive reboots
sed -i '/swap/s/^/#/' /etc/fstab
# Verify
free -h | grep Swap   # should show 0B
```

## 2.2 - Enable kernel modules

```bash
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
```

## 2.3 - Configure sysctl

```bash
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
```

## 2.4 - Install containerd

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

## 2.5 - Configure containerd (critical step)

The default containerd install ships with the CRI plugin disabled. This config must be regenerated with `SystemdCgroup` enabled - skipping this causes `kubeadm join` to fail with a CRI error.

```bash
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

# Enable SystemdCgroup
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd
systemctl status containerd   # must show active (running)
```

## 2.6 - Install kubeadm, kubelet, kubectl

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
# kubelet will show 'activating' until kubeadm init runs - this is normal
```

## 2.7 - Install the HWE kernel (required for Cilium)

```bash
apt-get install -y linux-generic-hwe-20.04
update-grub

# Reboot one node at a time - do NOT reboot all simultaneously
reboot
```

After reboot, verify:

```bash
uname -r   # should show 5.15.x or higher
```


Once all three nodes pass these steps, proceed to `03-cluster-init.md`.
