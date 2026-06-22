# 01 — Virtualization Setup (KVM/QEMU on RHEL Host)

This document covers how the lab's 3-node Kubernetes cluster was virtualized on a single RHEL 9 host using KVM/QEMU + libvirt, before any Kubernetes installation happened.


## Phase 1 — Environment Check

Before enabling virtualization, the host was validated for OS version, available RAM/CPU, nested virtualization support, and free disk space.

```bash
cat /etc/redhat-release
free -h && echo "---" && nproc
grep -E 'vmx|svm' /proc/cpuinfo | head -3
df -h /var/lib/libvirt/images 2>/dev/null || df -h /
```

**Findings:**
- OS: RHEL 9.x ✅
- RAM/CPU: sufficient for 3 lightweight VMs (≥4GB free RAM, ≥4 cores)
- Nested virtualization flag (`vmx`/`svm`) present in `/proc/cpuinfo`
- Disk space: ≥30–40GB free under `/var/lib/libvirt/images`

---

## Phase 2 — Enable Nested Virtualization

CPU vendor was identified first:

```bash
lscpu | grep -E 'Vendor|Model name'
```

For an Intel host, nested virt state was checked and enabled:

```bash
cat /sys/module/kvm_intel/parameters/nested

# If off:
echo "options kvm-intel nested=1" > /etc/modprobe.d/kvm-intel.conf
modprobe -r kvm_intel
modprobe kvm_intel

# Confirm:
cat /sys/module/kvm_intel/parameters/nested   # should return Y
```

(AMD equivalent uses `kvm_amd` / `kvm-amd.conf` with the same pattern.)

---

## Phase 3 — Install KVM Hypervisor

```bash
dnf install -y qemu-kvm libvirt libvirt-client virt-install bridge-utils virt-viewer
systemctl enable --now libvirtd
systemctl status libvirtd
lsmod | grep kvm
virsh list --all
virsh nodeinfo
```

| Package | Purpose |
|---|---|
| `qemu-kvm` | Hypervisor engine |
| `libvirt` | VM management daemon |
| `libvirt-client` | CLI tools for libvirt |
| `virt-install` | Creates new VMs |
| `bridge-utils` | Networking for VM bridges |
| `virt-viewer` | Optional VM screen viewer |

Result: `libvirtd` active and running, KVM modules loaded, `virsh` operational with an empty VM list.

---

## Phase 4 — Networking

```bash
virsh net-list --all
virsh net-start default        # if inactive
virsh net-autostart default
virsh net-dumpxml default
```

A default NAT-based virtual network (bridge `virbr0`) was confirmed active, providing DHCP-assigned IPs to VMs in a private subnet (`<VIRT_NETWORK_CIDR>`, e.g. a `/24` range).

```
<HOST_VM>
    │
┌───┴────┐
│ virbr0 │  ← virtual bridge / DHCP
└───┬────┘
┌───┼────┐
node1  node2  node3   ← <NODE_IP_1> / <NODE_IP_2> / <NODE_IP_3>
```

---

## Phase 5 — VM Disk Storage

```bash
mkdir -p /var/lib/libvirt/images
df -h /var/lib/libvirt/images

cd /var/lib/libvirt/images
curl -LO https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9-latest-x86_64-minimal.iso
ls -lh Rocky-9-latest-x86_64-minimal.iso
```

Rocky Linux 9 (RHEL-compatible, free) was used as the guest OS for all three nodes.

---

## Phase 6 — Create the 3 VMs

Each node was provisioned with `virt-install` using identical specs (1 vCPU, 1GB RAM, 15GB qcow2 disk), differing only by `--name`:

```bash
virt-install \
  --name node1 \
  --ram 1024 \
  --vcpus 1 \
  --disk path=/var/lib/libvirt/images/node1.qcow2,size=15,format=qcow2 \
  --os-variant rocky9 \
  --network network=default \
  --graphics none \
  --console pty,target_type=serial \
  --location /var/lib/libvirt/images/Rocky-9-latest-x86_64-minimal.iso \
  --extra-args 'console=ttyS0,115200n8 serial' \
  --noreboot
```

The same command was repeated for `node2` and `node3`.

**Verify creation and start:**

```bash
virsh list --all
virsh start node1
virsh start node2
virsh start node3
virsh list --all
```

**Resolve assigned IPs:**

```bash
virsh domifaddr node1
virsh domifaddr node2
virsh domifaddr node3
```

Resulting mapping (placeholders):

| Node | IP |
|---|---|
| node1 | `<NODE_IP_1>` |
| node2 | `<NODE_IP_2>` |
| node3 | `<NODE_IP_3>` |

---

## Phase 7 — Per-VM Configuration

For each VM, connected via serial console:

```bash
virsh console node1
# Ctrl + ] to exit
```

**Set hostname:**

```bash
hostnamectl set-hostname node1
```

**Set a static IP** (so cluster addressing stays fixed across reboots):

```bash
nmcli con mod "System eth0" ipv4.addresses <NODE_IP_n>/24 \
  ipv4.gateway <GATEWAY_IP> \
  ipv4.dns 8.8.8.8 \
  ipv4.method manual
nmcli con up "System eth0"
```

**Add cluster hosts entries** (repeated identically on every node):

```bash
cat >> /etc/hosts << 'EOF'
<NODE_IP_1>  node1
<NODE_IP_2>  node2
<NODE_IP_3>  node3
EOF
```

This step was repeated on `node2` and `node3` with their respective hostnames set.

---

## Outcome

At the end of this phase:
- 3 Rocky Linux 9 VMs running under KVM/QEMU on a single RHEL 9 host
- Static IPs assigned and resolvable via `/etc/hosts` across all nodes
- Nested virtualization and libvirt networking confirmed working

This formed the base infrastructure on top of which Kubernetes prerequisites and `kubeadm` cluster initialization were performed (see `02-prerequisites.md` and `03-cluster-init.md`).

---

## Known Issue — Node Loses IP After Reboot (DHCP delay)

**Symptom:** A VM is unreachable over SSH after a reboot.

**Cause:** DHCP lease renewal on the virtual bridge (`virbr0`) can lag behind the VM finishing boot, so the node comes up without (or with a stale) IP.

**Fix — from the VM console:**

```bash
netplan apply
# or, depending on the network stack:
networkctl renew <interface>
```

**Permanent fix for `master`:** set a static IP via netplan instead of relying on DHCP:

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

Static IPs avoid this class of issue entirely and keep `kubeadm`'s `--apiserver-advertise-address` stable across reboots.
