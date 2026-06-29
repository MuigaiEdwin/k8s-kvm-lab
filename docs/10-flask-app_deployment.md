# 10 Deploying a Flask App to Kubernetes

## Overview

Built a Flask backend, containerized it, pushed to Harbor, and deployed to the cluster using Kubernetes manifests.

## App Structure

```
lab-app/
  backend/
    app.py
    requirements.txt
    Dockerfile
  manifests/
    deployment.yaml
    service.yaml
```

## Steps

**1. Build and push the image**

```bash
docker build -t <harbor-ip>/library/flask-backend:v1 .
docker login <harbor-ip>
docker push <harbor-ip>/library/flask-backend:v1
```

**2. Create the Harbor image pull secret**

```bash
kubectl create secret docker-registry harbor-secret \
  --docker-server=<harbor-ip> \
  --docker-username=admin \
  --docker-password=<password> \
  --namespace=default
```

**3. Apply the manifests**

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

**4. Verify**

```bash
kubectl get pods -l app=flask-backend
kubectl get svc flask-backend
```

Expected output:

```
NAME                             READY   STATUS    RESTARTS   AGE
flask-backend-777cb86f4d-2xxmp   1/1     Running   0          2m
flask-backend-777cb86f4d-9sc8t   1/1     Running   0          2m
```

**5. Test**

```bash
curl http://<node-ip>:30500
```
Response:
![app-screenshot](../images/flask-app.py)

## Key Notes

- Manifests live in `k8s/` in the repo
- Harbor is a private registry so the image pull secret is required in the Deployment spec
- Liveness and readiness probes both hit `/health`
- App runs on 2 replicas across worker nodes, exposed via NodePort 30500

## Next Steps

GitHub Actions pipeline to automate build, push, and rollout via `kubectl set image`, then GitOps with ArgoCD.
