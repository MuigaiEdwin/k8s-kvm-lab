# Ceph Deployment Runbook - cephadm, No Rook

This is a first-person account of standing up Ceph on my `k8s-kvm-lab` cluster using `cephadm`, deliberately without Rook, so I could learn the manual operational side of Ceph rather than have Kubernetes abstract it away. A parallel team was doing the Rook version at the same time, this runbook documents the other path.

## Architecture

Ceph runs on three of the four VMs in the lab: `node1`, `node2`, `node3`. The Kubernetes control-plane node (`master`) is deliberately excluded, Ceph and Kubernetes are hyperconverged on the worker nodes, but I kept storage off the control plane so a Ceph problem can never take down the API server, etcd, or scheduler alongside it.

| Host  | Role (k8s)     | Role (Ceph)      | IP              | OSD disk |
|-------|----------------|-------------------|-----------------|----------|
| master| control-plane  | -                 | Node-ip   | -        |
| node1 | worker         | MON, MGR (active), OSD | Node-ip | vdb (20G) |
| node2 | worker         | MON, MGR (standby), OSD | Node-ip | vdb (20G) |
| node3 | worker         | MON, OSD          | Node-ip   | vdb (20G) |

Each node's OSD disk is a raw, unpartitioned `vdb` block device, separate from the OS disk (`vda`), attached via `virsh attach-disk`.

## Prerequisites

Before bootstrapping, each host needs:
- A container engine (I used Docker; Podman wasn't available in this environment)
- `cephadm` installed from the Ceph apt repo
- A raw, unformatted block device for the OSD
- Root SSH access from the bootstrap host to every other host (cephadm manages the cluster over SSH, not through Kubernetes)
- Time sync running (`chrony`, verified automatically during bootstrap)

## Step 1 - Attach the OSD disk to each node

Run on the KVM hypervisor host, not on the guest VMs.

```bash
qemu-img create -f qcow2 /lab/<node>-ceph-disk.qcow2 20G
qemu-img info /lab/<node>-ceph-disk.qcow2   # confirm "virtual size: 20 GiB" before attaching
virsh attach-disk <node> /lab/<node>-ceph-disk.qcow2 vdb --targetbus virtio --subdriver qcow2 --persistent
virsh domblklist <node>
```

**Gotcha:** without `--subdriver qcow2`, libvirt can misdetect the disk format as raw instead of qcow2, which makes the guest see a bogus few-hundred-KB device instead of the real 20G. Check the domain XML if a disk shows the wrong size:

```bash
virsh dumpxml <node> | grep -A 5 "target dev='vdb'"
```

**Gotcha:** a guest-level `reboot` does not always force the VM to re-read a freshly reattached disk. If `lsblk` inside the guest still shows the old (wrong) size after a reboot, power-cycle at the hypervisor level instead:

```bash
virsh destroy <node>
virsh start <node>
```

## Step 2 - Install cephadm and a container engine on the bootstrap host

I used `node1` as the bootstrap host.

```bash
apt-get update
apt-get install -y curl gnupg2 software-properties-common
curl --silent --remote-name --location https://download.ceph.com/keys/release.asc
apt-key add release.asc
apt-add-repository 'deb https://download.ceph.com/debian-octopus/ focal main'
apt-get update
apt-get install -y cephadm docker.io
systemctl enable --now docker
```

## Step 3 - Bootstrap the cluster

```bash
cephadm bootstrap --mon-ip <bootstrap-host-ip>
```

This single command creates `/etc/ceph/`, pulls the Ceph container image, stands up the first MON and MGR, generates an SSH keypair for cephadm's own orchestration (`/etc/ceph/ceph.pub`), and prints a dashboard URL plus a temporary admin password. Save that output, the password isn't shown again.

Install the CLI directly on the host so you don't need to enter a shell container for every command:

```bash
cephadm add-repo --release octopus
cephadm install ceph-common
ceph -v
```

## Step 4 - Get root SSH working to every other host

cephadm's orchestration is SSH-based and expects root access by default. On a stock Ubuntu server install, root login over SSH is usually disabled and the root account has no password set. On every additional host:

```bash
passwd root
grep -i permitrootlogin /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl restart sshd
```

Then, from the bootstrap host, push cephadm's key and add the host:

```bash
ssh-copy-id -f -i /etc/ceph/ceph.pub root@<node-ip>
ceph orch host add <node-name> <node-ip>
```

I initially tried switching cephadm to a non-root user with passwordless sudo, per a preference for not using root SSH. It caused repeated, hard-to-diagnose failures in `ceph orch host add` (key mismatches, hostname resolution issues, container-vs-host filesystem confusion). I abandoned that approach and went back to root-based SSH, which is the documented default and worked reliably once the account/sshd config issues above were fixed.

## Step 5 - Confirm every host and disk is visible

```bash
ceph orch host ls
ceph orch device ls --refresh
ceph orch device ls
```

Every host's `vdb` should show `Available: Yes`. If a disk shows `Available: No`, it likely has leftover LVM or partition signatures from a previous Ceph deployment on that disk. Wipe it cleanly:

```bash
ceph orch device zap <node-name> /dev/vdb --force
```

## Step 6 - Fix MON placement for your actual host count

cephadm's default MON placement targets a count of 5. With only 3 hosts, it will happily try (and fail) to satisfy that forever, sitting at something like `mon 3/5`. Pin it explicitly to your real hosts:

```bash
ceph orch apply mon --placement="node1,node2,node3"
ceph orch ls   # confirm mon shows 3/3
```

## Step 7 - Resolve the hyperconverged monitoring conflict

If your Ceph hosts are the same machines running Kubernetes with a monitoring stack (e.g. `kube-prometheus-stack`), cephadm's default monitoring services will conflict with it. Specifically, cephadm deploys its own `node-exporter` on port 9100, the same port a Kubernetes `node-exporter` DaemonSet already binds via host networking. Since kubelet actively manages and restarts its own pod, cephadm's container loses that fight every time and the MGR log fills with repeated `Address already in use` errors.

Since the Kubernetes monitoring stack already covers node-level metrics, I removed cephadm's duplicate monitoring layer entirely and kept only the core storage services:

```bash
ceph orch rm node-exporter
ceph orch rm prometheus
ceph orch rm grafana
ceph orch rm alertmanager
```

## Step 8 - Deploy OSDs

```bash
ceph orch apply osd --all-available-devices
```

This claims every available raw disk on every host as an OSD. Give it a minute or two, it pulls the OSD container and runs `ceph-volume` on each disk.

## Step 9 - Verify the cluster is actually working

Status and structural checks:

```bash
ceph -s
ceph mon stat
ceph osd tree
ceph orch host ls
ceph orch ls
```

I was looking for `osd: 3 osds: 3 up, 3 in` and PGs in `active+clean` state.

The real proof, actual data through the cluster:

```bash
ceph osd pool create testpool 8
ceph osd pool application enable testpool rbd
echo "hello ceph" > /tmp/test-object.txt
rados -p testpool put test-object /tmp/test-object.txt
rados -p testpool get test-object /tmp/readback.txt
cat /tmp/readback.txt   # should print "hello ceph"
```

Status output and health checks confirm the daemons report themselves healthy. Writing and reading an object back through a pool is what actually confirms the cluster does its job.

Dashboard access, for visual confirmation and day-to-day monitoring:

```
https://<bootstrap-host-ip>:8443/
```

To reset the dashboard admin password without needing to recover the original bootstrap output:

```bash
echo "<new-password>" > /tmp/new-pass.txt
ceph dashboard ac-user-set-password admin -i /tmp/new-pass.txt
rm /tmp/new-pass.txt
```

## Known warnings and open items

- **`mon <host> is low on available space`** - this refers to the host's root filesystem (where `/var/lib/ceph/` lives), not the OSD disk. Check with `df -h /` on the affected host. Not urgent at low disk usage, but worth monitoring since MON data grows over time.
- **Networking on VM creation** - if a VM can't reach its gateway despite a correct static IP, check whether `virt-install` attached it to libvirt's default NAT network (`virbr0`) instead of a macvtap/bridged interface to the physical NIC. Compare `virsh domiflist <node>` against a known-good host. Fix by recreating with `--network type=direct,source=<physical-nic>,source_mode=bridge,model=virtio`.

## Lessons learned

- Root SSH is the documented default for cephadm for a reason, deviating from it (non-root + sudo) cost more time than it saved.
- Always verify a disk's actual size after attach/detach operations (`qemu-img info`, then `lsblk` inside the guest) before assuming it worked. A silent format-mismatch bug produced a device that looked attached but was functionally useless.
- A guest-level reboot is not always enough to refresh block device state after a hypervisor-side disk change; a full `virsh destroy`/`start` is more reliable.
- On a hyperconverged Kubernetes + Ceph setup, expect port and resource contention between the two stacks' default add-ons (monitoring, in this case). Decide deliberately which stack owns which function rather than running both.