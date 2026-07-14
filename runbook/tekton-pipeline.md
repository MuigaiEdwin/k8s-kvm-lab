# Tekton Pipelines Install — Commands Reference

Companion to the main README. This documents the actual commands run, in order, with placeholders in place of any cluster-identifying or sensitive values.

## 1. CLI setup (Windows)

```powershell

Expand-Archive -Path "$HOME\Downloads\oc.zip" -DestinationPath "C:\oc"

# Copy into a folder already on PATH (used before admin rights were available)
Copy-Item C:\oc\oc.exe C:\Users\<user>\.local\bin\oc.exe

# Verify
oc version --client
```

## 2. Login

```powershell
oc login --token=<token> --server=https://<cluster-api-url>:6443
```

Token generated via console: username menu → Copy login command → Display Token. Regenerated fresh for each session; not reused long-term.

## 3. Install OpenShift Pipelines operator

```powershell
notepad pipelines-operator.yaml
```

Contents:

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

Apply and watch:

```powershell
oc apply -f pipelines-operator.yaml
oc get csv -n openshift-operators -w
```

Verify pods:

```powershell
oc get pods -n openshift-pipelines
```

## 4. Diagnosing the Tekton Results / storage issue

```powershell
# Confirm which pods are unhealthy
oc get pods -n openshift-pipelines

# Check underlying cause
oc get pvc -n openshift-pipelines
oc describe pod tekton-results-postgres-0 -n openshift-pipelines
oc get events -n openshift-pipelines --sort-by='.lastTimestamp'
oc get storageclass
```

Key finding from events: PVC stuck due to `no persistent volumes available for this claim and no storage class is set`.

## 5. Node investigation

```powershell
# Confirm node count / topology
oc get nodes -o wide

# Confirm bare metal vs virtualized
oc get node <node-name> -o jsonpath='{.spec.providerID}'
oc get node <node-name> -o yaml | findstr -i "virtual kubevirt provider platform hypervisor"

# Check for available raw disks
oc debug node/<node-name>
chroot /host
lsblk -f

# Check resource headroom before adding a storage layer
oc adm top node <node-name>
```

## 6. Ceph via Rook (OpenShift-specific) — in progress

```powershell
git clone --single-branch --branch v1.14.x https://github.com/rook/rook.git
cd rook/deploy/examples

# Apply OpenShift-required Security Context Constraints
oc create -f scc.yaml

# Deploy operator using the OpenShift-specific manifest
oc create -f crds.yaml -f common.yaml -f operator-openshift.yaml
oc get pods -n rook-ceph

# Deploy single-node-safe test cluster (no replication)
oc create -f cluster-test.yaml
oc get pods -n rook-ceph --watch

# Create and set default StorageClass
oc create -f csi/rbd/storageclass-test.yaml
oc patch storageclass rook-ceph-block -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## Nb

- All hostnames, tokens, and internal URLs in this document are placeholders.
- `cluster-test.yaml` config is intentionally non-replicated (`size: 1`), appropriate only for single-node/dev use, not production.