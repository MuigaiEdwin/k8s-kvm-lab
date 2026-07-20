# Setting Up Local Domains for Kubernetes Services

## What I Did

I updated the /etc/hosts files on RHEL host, master node, and Windows to map local domains to the cluster node IP. I flushed DNS caches and verified that services were accessible via domain names instead of random port numbers.

## The Process

### I Updated RHEL Host /etc/hosts

```bash
sudo nano /etc/hosts
```

I added the mappings:

```
<CLUSTER_NODE_IP>  grafana.local
<CLUSTER_NODE_IP>  prometheus.local
<CLUSTER_NODE_IP>  alertmanager.local
```

### I Updated Master Node /etc/hosts

```bash
sudo nano /etc/hosts
```

I added the same mappings on the master node.

### I Tested DNS Resolution

```bash
ping grafana.local
```

It resolved correctly to `<CLUSTER_NODE_IP>`.

### I Flushed DNS on Windows

I opened PowerShell as Administrator and ran:

```powershell
ipconfig /flushdns
```

### I Updated Windows /etc/hosts

I opened Notepad as Administrator and edited:

```
C:\Windows\System32\drivers\etc\hosts
```

I added the same domain mappings.

### I Flushed DNS Again

```powershell
ipconfig /flushdns
```

### I Verified in Browser

I tested accessing services:

```
http://grafana.local:32081/
http://prometheus.local:32081/
http://alertmanager.local:32081/
```

## Nb
The corporate proxy is blocking the access...on local machine normally it would since it is pinginig