# 05 > Deploy nginx (Cluster Verification)

With all 3 nodes `Ready` and Cilium healthy, a simple nginx deployment was used to verify end-to-end cluster networking and service exposure.


## Deploy and Expose

```bash
# Create a 2-replica nginx deployment
kubectl create deployment nginx --image=nginx --replicas=2

# Expose it via NodePort
kubectl expose deployment nginx --port=80 --type=NodePort

# Check the assigned port
kubectl get svc nginx
# NAME    TYPE       CLUSTER-IP    PORT(S)              AGE
# nginx   NodePort   10.x.x.x      80:<NODE_PORT>/TCP   1m
```

## Access

```bash
curl http://<ANY_NODE_IP>:<NODE_PORT>
```

A successful response returns the nginx welcome page — confirming pod scheduling, Cilium networking, and NodePort service routing all work end-to-end. ✅

> Equivalent manifest-based version of this deployment lives in `manifests/nginx-deployment.yaml` and `manifests/nginx-service.yaml`, for anyone who wants to `kubectl apply -f` instead of using imperative commands.

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
