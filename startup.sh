#!/bin/bash

# Kill any existing port-forwards to avoid conflicts
pkill -f "port-forward" 2>/dev/null; sleep 2

# Optional: restart kubelet on worker node if it has
# persistent connectivity issues. Requires SSH key auth.
# ssh <worker-node-user>@<worker-node-ip> "sudo systemctl restart kubelet" 2>/dev/null \
#   && echo "worker node kubelet restarted" \
#   || echo "worker node ssh skipped"

echo "=== Checking nodes ==="
kubectl get nodes

echo "=== Checking for unhealthy pods ==="
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

echo "=== Starting Harbor ==="
cd /usr/local/harbor && docker compose up -d
cd ~

echo "=== Cilium status ==="
cilium status

echo "=== Starting port-forwards ==="
# Hubble UI
kubectl -n kube-system port-forward --address 0.0.0.0 svc/hubble-ui 12000:80 &

# Hubble relay (required for hubble observe CLI)
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &

# Kubernetes dashboard
kubectl -n kubernetes-dashboard port-forward --address 0.0.0.0 svc/kubernetes-dashboard-kong-proxy 8443:443 &

echo ""
echo "=== All done - all services ==="
echo "Grafana:       http://<master-ip>:30723"
echo "Prometheus:    http://<master-ip>:31971"
echo "Harbor:        http://<master-ip>"
echo "Hubble UI:     http://<master-ip>:12000"
echo "Dashboard:     https://<master-ip>:8443"
echo ""
echo "Hubble CLI:    hubble observe --follow"
echo ""
echo "Dashboard token:"
kubectl -n kubernetes-dashboard create token kubernetes-dashboard
