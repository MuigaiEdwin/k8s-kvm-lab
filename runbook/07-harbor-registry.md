# Harbor Registry Installation 

Private container registry set up on the  nodes to support image storage and CI/CD for the k8s-kvm-lab cluster.

## Steps

```bash
# 1. Download and extract
wget https://github.com/goharbor/harbor/releases/download/v2.13.1/harbor-offline-installer-v2.13.1.tgz
mv harbor-offline-installer-v2.13.1.tgz /usr/local/
cd /usr/local/
tar -xvzf harbor-offline-installer-v2.13.1.tgz
cd harbor

# 2. Create config
cp harbor.yml.tmpl harbor.yml
nano harbor.yml
```

**In `harbor.yml`, set:**
| Setting | Value |
|---|---|
| `hostname` | Master node's IP |
| `https` block | Commented out (HTTP only, no cert in lab) |
| `http.port` | `80` |
| `harbor_admin_password` | Changed from default |

```bash
# 3. Install (handles image loading + prep internally)
./install.sh
```

All 10 containers should start: `harbor-log, redis, harbor-portal, harbor-db, registryctl, registry, harbor-core, nginx, harbor-jobservice`.

## Access

```
http://<node-ip>
```
Login: `admin` / password set in `harbor.yml`

## Note

Plain HTTP, no TLS - cluster nodes' containerd will need to be configured to trust this as an **insecure registry** before pulling/pushing images.

## Next Steps
- [X] Configure containerd insecure registry on cluster nodes
- [ ] Create a project in Harbor
- [ ] Test manual `docker push`/`pull`
- [ ] Deploy a workload pulling from Harbor
- [ ] Wire up CI to auto-push on commit
