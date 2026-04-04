# Istio Ambient Mode on EKS Auto Mode

Optional add-on for mTLS (workload identity) and zone-aware routing via ztunnel. Everything in the Traefik artifact works without this — Nitro handles encryption in transit, and `trafficDistribution: PreferClose` handles AZ-aware routing. Add this when you need cryptographic proof of _which_ workload is talking to which.

## 1. Install (4 Helm charts, in order)

```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

helm install istio-base istio/base -n istio-system --create-namespace --wait
helm install istiod istio/istiod -n istio-system --set profile=ambient --wait
helm install istio-cni istio/cni -n istio-system --set profile=ambient --wait
helm install ztunnel istio/ztunnel -n istio-system --wait
```

## 2. Enrol namespaces

```bash
kubectl label namespace my-app istio.io/dataplane-mode=ambient
```

mTLS is now active for all pods in that namespace. No sidecars, no pod restarts, no application changes. Certificates auto-rotate every 12 hours.

## 3. Zone-aware routing (optional, replaces PreferClose)

If you're using Istio, its ztunnel can handle AZ-aware routing instead of Kubernetes `trafficDistribution`. Apply per-namespace:

```bash
kubectl annotate namespace my-app \
  networking.istio.io/traffic-distribution=PreferSameZone
```

Or per-service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  annotations:
    networking.istio.io/traffic-distribution: PreferSameZone
```

This is additive — if you also have `trafficDistribution: PreferClose` on the Service, both mechanisms apply. No harm in keeping both.

## 4. Exclude Traefik from the mesh

Traefik handles external traffic and should not be intercepted by ztunnel:

```bash
kubectl label namespace traefik istio.io/dataplane-mode-
```

Or annotate the Traefik pods directly in your Helm values:

```yaml
podAnnotations:
  ambient.istio.io/redirection: disabled
```

Traffic from Traefik to backend pods enters the mesh at the destination pod's ztunnel.

## 5. Verify

```bash
# Check ztunnel sees your workloads
istioctl ztunnel-config workload

# Check certificates are issued
istioctl ztunnel-config certificates

# Check pods are running
kubectl get pods -n istio-system
```

Expected pods:

```
istio-cni-node-xxxxx   1/1   Running   (one per node)
istiod-xxxxx           1/1   Running
ztunnel-xxxxx          1/1   Running   (one per node)
```

## 6. Upgrades

Upgrade order: CRDs → istiod → istio-cni → ztunnel. Istio releases quarterly; stay within N-2 minor versions.

```bash
helm upgrade istio-base istio/base -n istio-system --wait
helm upgrade istiod istio/istiod -n istio-system --set profile=ambient --wait
helm upgrade istio-cni istio/cni -n istio-system --set profile=ambient --wait
helm upgrade ztunnel istio/ztunnel -n istio-system --wait
```

## What it gives you

| Feature               | Without Istio                      | With Istio Ambient                           |
| --------------------- | ---------------------------------- | -------------------------------------------- |
| Encryption in transit | Nitro hardware (inter-node)        | mTLS (all traffic, including same-node)      |
| Workload identity     | None                               | SPIFFE certs per ServiceAccount              |
| AZ-aware routing      | `trafficDistribution: PreferClose` | `PreferSameZone` via ztunnel (with failover) |
| L4 authorization      | NetworkPolicy only                 | Istio AuthorizationPolicy                    |
| Observability         | None built-in                      | L4 metrics and access logs via ztunnel       |

## EKS Auto Mode notes

- **istio-cni** and **ztunnel** run as DaemonSets — this works on Auto Mode because it uses managed EC2 nodes (not Fargate)
- **21-day node recycling** is fine — DaemonSets auto-schedule onto new nodes
- **No SSH/SSM** — all debugging via `kubectl logs`, `kubectl exec`, and `istioctl`
- **CNI chaining** — istio-cni chains alongside the managed VPC CNI. If you hit path issues on Bottlerocket, check `cni.cniBinDir` and `cni.cniConfDir` Helm values
