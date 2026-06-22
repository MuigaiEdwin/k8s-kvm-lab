# k8s-kvm-lab

A complete, reproducible guide to building a 3-node Kubernetes cluster from scratch using KVM virtual machines on a Linux host.

This isn't a "just run this script" guide. Every step is explained, every real error encountered during setup is documented with its fix, and the reasoning behind each decision is included so you understand what you're doing and why.

---

## What This Builds

```
Linux Host (RHEL/Ubuntu) — KVM + QEMU + libvirt
        │
        ├── master    Control plane    <MASTER_IP>
        ├── node1     Worker node      <NODE1_IP>
        └── node2     Worker node      <NODE2_IP>

Stack:
  Hypervisor  →  KVM + QEMU
  OS          →  Ubuntu 20.04 LTS (each VM)
  Runtime     →  containerd
  Cluster     →  kubeadm (Kubernetes v1.29)
  CNI         →  Cilium (eBPF)
  Test app    →  nginx (NodePort)
```

---

## Guides — Follow in Order

| # | Document | What it covers |
|---|---|---|
| 01 | [Virtualization Setup](./docs/01-virtualization.md) | Install KVM on RHEL host, create 3 VMs |
| 02 | [Kubernetes Prerequisites](./docs/02-prerequisites.md) | Prepare all 3 nodes before kubeadm |
| 03 | [Cluster Initialization](./docs/03-cluster-init.md) | kubeadm init on master, join workers |
| 04 | [Cilium CNI](./docs/04-cilium.md) | Install CNI, fix HWE kernel requirement |
| 05 | [Deploy & Verify](./docs/05-deploy-nginx.md) | nginx deployment, NodePort, verification |
| 06 | [Deploy and access the web UI dashboard](./docs/06-dashboard.md) | nginx deployment, NodePort, verification |

---

## Quick Specs

| Item | Value |
|---|---|
| Host OS | RHEL 9 (or Ubuntu 22.04) |
| VM OS | Ubuntu 20.04 LTS |
| vCPU per VM | 4 |
| RAM per VM | 4 GB |
| Disk per VM | 50 GB |
| Kubernetes | v1.29 |
| CNI | Cilium |
| Container runtime | containerd |
| Kernel required | 5.15+ (HWE) |

---

## Known Issues Quick Reference

| Error | Fix | Doc |
|---|---|---|
| `unknown service runtime.v1.RuntimeService` | Regenerate containerd config | [02](./docs/02-prerequisites.md) |
| `bpf_get_current_cgroup_id() not available` | Install HWE kernel (5.15) | [04](./docs/04-cilium.md) |
| Swap re-enables after reboot | Comment out swap in `/etc/fstab` | [02](./docs/02-prerequisites.md) |
| Node loses IP after reboot | Set static IP on master via netplan | [01](./docs/01-virtualization.md) |
| Pod stuck in `Terminating` | Force delete + restart containerd | [04](./docs/04-cilium.md) |

---

## Manifests

Ready-to-use Kubernetes manifests are in the [`manifests/`](manifests/) folder:

- `nginx-deployment.yaml` — 2-replica nginx deployment
- `nginx-service.yaml` — NodePort service

---

## Confidentiality Note

All IP addresses, hostnames, MAC addresses, tokens, and certificate hashes in this guide are placeholders. Replace them with your own values. 
