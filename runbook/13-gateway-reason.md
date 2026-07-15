# API Gateway: Why Enterprise Use It

## What I Discovered

I've been exposing Kubernetes services using NodePorts:

```
Grafana:       http://<CLUSTER_NODE_IP>:30723
Prometheus:    http://<CLUSTER_NODE_IP>:31971
K8s-Dashboard: http://<CLUSTER_NODE_IP>:31169
Harbor:        http://<CLUSTER_NODE_IP>
Hubble UI:     http://<CLUSTER_NODE_IP>:12000
AlertManager:  http://<CLUSTER_NODE_IP>:9094
```

I've noted that in K8s, each service gets exposed on a random NodePort. When services restart or get redeployed, they get assigned different ports. This is chaos.

Managing 7 services across 7 different ports is already messy. Imagine managing 50 or 100 services. Impossible.

## The Solution I Implemented

I deployed an API Gateway (Traefik) that sits in front of all services. Now everything goes through ONE entry point on port 80/443.

Instead of remembering port numbers, clients access services by domain:

```
http://grafana.local/       → Traefik routes to Grafana
http://prometheus.local/    → Traefik routes to Prometheus  
http://alertmanager.local/  → Traefik routes to Alertmanager
```

The gateway handles all the routing. Backend port changes don't affect clients.

## Why Enterprise Uses API Gateways

1. **Scalability** - 1000 services, 1 port. Without a gateway, 1000 ports to manage.

2. **Stability** - Services restart and get new ports. Gateway abstracts this. Clients always hit the same domain.

3. **Security** - Single point to enforce authentication, rate limiting, encryption. Do it once at the gateway instead of 50 times per service.

4. **Operations** - One configuration to manage instead of juggling ports.

## What I Learned About HAProxy

HAProxy (similar to Traefik) is a reverse proxy that does the same thing. It receives traffic on one port and intelligently routes it to backends based on domain or path.

The key insight: One entry point. Unlimited backends. Simple.

## What I Built

Deployed Traefik with both IngressRoute (Traefik-specific) and Gateway API (Kubernetes standard). Both methods route through the same gateway to the same services.

Result: Clean, scalable, enterprise-grade platform instead of random port chaos.

## Takeaway

API Gateways transform messy, unmaintainable infrastructure into something that scales. This is why every enterprise uses them.