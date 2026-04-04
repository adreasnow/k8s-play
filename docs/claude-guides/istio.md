# EKS Auto Mode: Traefik + NLB + Istio Ambient + Cross-AZ Optimization

A complete Helm-based setup for EKS Auto Mode that minimizes bandwidth-billed AWS resources, provides mTLS via Istio Ambient, uses Traefik as the ingress controller behind an NLB with EIPs, and aggressively reduces cross-AZ data transfer costs.

---

## Architecture overview

```
Internet
  │
  ▼
NLB (TCP passthrough, EIPs, ~$16/mo + negligible LCU)
  │
  ▼
Traefik Proxy (hostNetwork, TLS termination, L7 routing)
  │
  ▼
┌─────────────────────────────────────────────┐
│  Istio Ambient Mesh (ztunnel per node)      │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐    │
│  │ Pod AZ-a│  │ Pod AZ-b│  │ Pod AZ-a│    │
│  └─────────┘  └─────────┘  └─────────┘    │
│  mTLS everywhere · zone-aware routing       │
└─────────────────────────────────────────────┘
```

---

## Part 1: Istio Ambient Mode

### 1a. Add the Istio Helm repo

```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
```

### 1b. Install in order (4 charts)

```bash
# 1. CRDs and base
helm install istio-base istio/base \
  -n istio-system --create-namespace

# 2. Control plane (istiod) in ambient profile
helm install istiod istio/istiod \
  -n istio-system \
  --set profile=ambient \
  --set pilot.resources.requests.cpu=200m \
  --set pilot.resources.requests.memory=512Mi

# 3. CNI plugin (required for ambient — runs as DaemonSet)
#    EKS Auto Mode uses Bottlerocket; confirm paths if issues arise
helm install istio-cni istio/cni \
  -n istio-system \
  --set profile=ambient \
  --set cni.cniBinDir=/opt/cni/bin \
  --set cni.cniConfDir=/etc/cni/net.d

# 4. ztunnel (the per-node L4 proxy — this is the mesh data plane)
helm install ztunnel istio/ztunnel \
  -n istio-system
```

### 1c. Enroll namespaces (no pod restarts needed)

```bash
kubectl label namespace my-app istio.io/dataplane-mode=ambient
```

That's it — mTLS is now active for all pods in `my-app`. Certificates auto-rotate every 12 hours. No sidecars, no init containers, no application changes.

### 1d. Verify mTLS is working

```bash
# Check ztunnel sees your workloads
istioctl ztunnel-config workload

# Check certificates are issued
istioctl ztunnel-config certificates

# Confirm HBONE tunnels are established
kubectl logs -n istio-system -l app=ztunnel --tail=50 | grep "inbound"
```

---

## Part 2: Traefik Proxy behind NLB

### 2a. Install Gateway API CRDs

Gateway API CRDs are not included by default on most clusters. Install them before Traefik:

```bash
# Standard channel (HTTPRoute, GRPCRoute)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml

# Optional: Experimental channel (adds TCPRoute, TLSRoute)
# kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/experimental-install.yaml
```

### 2b. Add the Traefik Helm repo

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
```

### 2c. Create a values file

```yaml
# traefik-values.yaml

# --- Deployment configuration ---
deployment:
  replicas: 2 # One per AZ minimum

# --- Use hostNetwork for direct node binding ---
hostNetwork: true

# --- Providers ---
# Use Gateway API instead of Ingress. Disable the legacy Ingress provider.
providers:
  kubernetesIngress:
    enabled: false
  kubernetesGateway:
    enabled: true
    # Route via ClusterIP so kube-proxy applies PreferClose topology
    nativeLBByDefault: true

# --- Gateway listeners (Helm creates the GatewayClass + Gateway for you) ---
gateway:
  listeners:
    web:
      port: 80
      protocol: HTTP
      namespacePolicy:
        from: All
    websecure:
      port: 443
      protocol: HTTPS
      namespacePolicy:
        from: All
      mode: Terminate
      certificateRefs:
        - kind: Secret
          name: my-wildcard-cert # From cert-manager (see Part 5)
          group: ""

# --- Ports ---
ports:
  web:
    port: 8080
    hostPort: 80
    protocol: TCP
  websecure:
    port: 8443
    hostPort: 443
    protocol: TCP

# --- NLB Service ---
service:
  enabled: true
  type: LoadBalancer
  annotations:
    # Use the EKS Auto Mode managed LB controller
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "instance"

    # Attach your Elastic IPs (one per AZ/subnet)
    service.beta.kubernetes.io/aws-load-balancer-eip-allocations: "eipalloc-AAAA,eipalloc-BBBB"

    # Specify your public subnets explicitly
    service.beta.kubernetes.io/aws-load-balancer-subnets: "subnet-pub-a,subnet-pub-b"

    # TCP passthrough — no TLS termination at NLB (16x cheaper than TLS listener)
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"

    # Enable cross-zone load balancing so both AZs are reachable
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"

    # Health check against Traefik's ping endpoint
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-path: "/ping"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "8080"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: "HTTP"

  spec:
    externalTrafficPolicy: Local # Preserves client IP, avoids extra hop

# --- Topology spread: one Traefik per AZ ---
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: traefik

# --- Pod disruption budget ---
podDisruptionBudget:
  enabled: true
  minAvailable: 1

# --- Enable ping endpoint for health checks ---
additionalArguments:
  - "--ping"
  - "--ping.entryPoint=web"

# --- TLS termination at Traefik (not NLB) ---
# Use cert-manager with Let's Encrypt for free, auto-renewed certs.
# See Part 5 below for cert-manager setup.
# Example with a default TLS store:
#   tlsStore:
#     default:
#       defaultCertificate:
#         secretName: my-wildcard-cert

# --- Resource requests ---
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: "1"
    memory: 512Mi

# --- Exclude Traefik from the ambient mesh ---
# Traefik handles external traffic; meshing it can cause
# conflicts with ztunnel's traffic interception.
podAnnotations:
  ambient.istio.io/redirection: disabled
```

### 2d. Install Traefik

```bash
helm install traefik traefik/traefik \
  -n traefik --create-namespace \
  -f traefik-values.yaml
```

### 2e. Deploy HTTPRoute resources

With the Helm chart's `gateway.listeners` block, the GatewayClass and Gateway are created automatically during `helm install`. You only need to create HTTPRoutes for your services:

```yaml
# httproute.yaml — example route for a backend service
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app-route
  namespace: my-app
spec:
  parentRefs:
    - name: traefik
      namespace: traefik
      sectionName: websecure
  hostnames:
    - "app.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-app-service # Must have trafficDistribution: PreferClose
          port: 80
```

### 2f. Key notes for EKS Auto Mode

- **`externalTrafficPolicy: Local`** is important — it prevents the kube-proxy from bouncing NLB traffic cross-AZ to reach a Traefik pod in a different zone.
- **`hostNetwork: true`** means Traefik binds directly to the node's network interface, so NLB target type must be `instance` (not `ip`).
- **`nativeLBByDefault: true`** is critical for AZ-aware routing — without it, Traefik routes directly to pod IPs, bypassing kube-proxy and ignoring `trafficDistribution: PreferClose` on your Services.
- **Gateway listener ports must match Traefik's entrypoint ports.** The Gateway says port 80/443, which map to Traefik's `web` (8080→hostPort 80) and `websecure` (8443→hostPort 443).
- Traefik pods should be **excluded from the ambient mesh** (`ambient.istio.io/redirection: disabled`) since they handle external ingress traffic. Internal traffic from Traefik to your backend services will enter the mesh at the backend pod's ztunnel.
- **TCP passthrough on the NLB** avoids TLS NLCU pricing (16x more expensive than TCP NLCUs for new connections). TLS terminates at Traefik using cert-manager + Let's Encrypt.

---

## Part 3: Minimizing cross-AZ data transfer

Cross-AZ transfer costs $0.01/GB each way ($0.02/GB round trip) on AWS. In a 3-AZ cluster, roughly two thirds of service-to-service traffic crosses AZ boundaries by default. There are four layers to address this.

### 3a. Istio ztunnel zone-aware routing (your biggest lever)

Istio Ambient Mode's ztunnel supports a native traffic distribution annotation that routes traffic to same-zone endpoints first, with automatic fallback to other zones when local endpoints are unavailable.

**Apply per-namespace (recommended):**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  labels:
    istio.io/dataplane-mode: ambient
  annotations:
    networking.istio.io/traffic-distribution: PreferSameZone
```

**Or per-service for fine-grained control:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: orders-service
  namespace: my-app
  annotations:
    networking.istio.io/traffic-distribution: PreferSameZone
spec:
  selector:
    app: orders
  ports:
    - port: 80
      targetPort: 8080
```

**Available modes:**

| Mode             | Behavior                                                        |
| ---------------- | --------------------------------------------------------------- |
| `PreferSameZone` | Routes to same AZ first, falls back to other AZs if unavailable |
| `PreferSameNode` | Routes to same node first, then same AZ, then anywhere          |

`PreferSameZone` is the right default for cost optimization with resilience. Unlike Kubernetes TAR, which hard-locks traffic to a zone with no failover, Istio's implementation gracefully degrades.

### 3b. Kubernetes-native traffic distribution (belt + suspenders)

For any services NOT in the Istio mesh (e.g., Traefik talking to backends before mesh enrollment), use the Kubernetes-native `trafficDistribution` field (available since K8s 1.31):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  trafficDistribution: PreferClose # Routes to same-AZ endpoints first
  selector:
    app: my-app
  ports:
    - port: 80
```

Or the older annotation-based approach:

```yaml
metadata:
  annotations:
    service.kubernetes.io/topology-mode: Auto
```

**Caveat:** Kubernetes TAR requires roughly equal endpoint counts per zone to activate. If you have 3 pods in AZ-a and 1 in AZ-b, the EndpointSlice controller may disable hints entirely. Always pair with topology spread constraints.

### 3c. Pod topology spread constraints (essential foundation)

Zone-aware routing only works if pods are evenly distributed. Add this to every Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
  namespace: my-app
spec:
  replicas: 4 # At least 2 per AZ
  template:
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: orders
```

`DoNotSchedule` is strict — if an AZ can't fit the pod, it stays pending rather than creating imbalance. Use `ScheduleAnyway` if availability matters more than cost.

### 3d. NLB + Traefik: keep ingress traffic in-zone

The NLB configuration above already handles this:

- **`externalTrafficPolicy: Local`** ensures the NLB only routes to Traefik pods in the same AZ as the NLB endpoint node. No cross-AZ hop for ingress.
- **`cross-zone-load-balancing-enabled: true`** on the NLB itself means clients can reach either AZ's EIP, but the NLB forwards to a local Traefik pod. If one AZ has no healthy Traefik pod, cross-zone kicks in as failover.

### 3e. Consider: reduce to 2 AZs

If your workloads don't require 3-AZ redundancy, dropping to 2 AZs reduces worst-case cross-AZ traffic from 66% to 50% (without zone-aware routing) and makes topology spread constraints easier to balance. EKS Auto Mode works fine with 2 AZs.

### 3f. What you can't avoid

Some cross-AZ traffic is unavoidable:

- **EKS control plane communication** — API server, etcd, istiod xDS updates
- **CoreDNS** — unless you annotate the kube-dns service with `service.kubernetes.io/topology-mode: Auto` (manually, as EKS doesn't set this by default)
- **External AWS services** (RDS, ElastiCache, SQS) — if the primary is in a different AZ from your pod. Pin stateful services and their consumers to the same AZ when possible.

---

## Part 4: Putting it all together

### Installation order

```bash
# 1. Gateway API CRDs (before Traefik)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml

# 2. Istio Ambient
helm install istio-base istio/base -n istio-system --create-namespace
helm install istiod istio/istiod -n istio-system --set profile=ambient
helm install istio-cni istio/cni -n istio-system --set profile=ambient
helm install ztunnel istio/ztunnel -n istio-system

# 3. Traefik (creates GatewayClass + Gateway via Helm values)
helm install traefik traefik/traefik -n traefik --create-namespace -f traefik-values.yaml

# 4. Label application namespaces
kubectl label namespace my-app istio.io/dataplane-mode=ambient
kubectl annotate namespace my-app networking.istio.io/traffic-distribution=PreferSameZone

# 5. Annotate CoreDNS for zone-aware resolution
kubectl annotate service kube-dns -n kube-system service.kubernetes.io/topology-mode=Auto

# 6. Deploy HTTPRoutes for your services
kubectl apply -f httproute.yaml
```

### What you're paying for (monthly, ~10 services, moderate traffic)

| Resource                                | Cost             | Bandwidth-billed?  |
| --------------------------------------- | ---------------- | ------------------ |
| NLB hourly                              | ~$16.43          | No                 |
| NLB LCU (data component)                | ~$3–6 for 500GB  | Minimal            |
| EIPs (2, attached)                      | Free (attached)  | No                 |
| Istio Ambient compute                   | ~$15–30 marginal | No                 |
| Traefik compute                         | ~$10–20 marginal | No                 |
| Cross-AZ transfer (with PreferSameZone) | ~$2–5 residual   | Yes, but minimized |
| **Total**                               | **~$47–78/mo**   |                    |

Compare to: ALB (~$30–50/mo + significant LCU) + VPC Lattice (~$250+/mo) + unoptimized cross-AZ ($20+/mo).

### Ongoing maintenance

| Task                                                | Frequency            | Effort                         |
| --------------------------------------------------- | -------------------- | ------------------------------ |
| Istio minor upgrade (CRDs → istiod → cni → ztunnel) | Every ~6 months      | Medium (Helm upgrade in order) |
| Traefik upgrade                                     | As needed            | Low (Helm upgrade)             |
| Certificate rotation                                | Automatic (12hr)     | None                           |
| Node recycling                                      | Every 21 days (auto) | None — ztunnel auto-schedules  |

---

## Appendix: Validating cross-AZ savings

To see whether zone-aware routing is working:

```bash
# Check EndpointSlice hints (for K8s TAR)
kubectl get endpointslices -n my-app -o yaml | grep -A2 "hints"

# Check ztunnel locality awareness
istioctl ztunnel-config workload -o yaml | grep -A3 "locality"

# Monitor cross-AZ bytes with VPC Flow Logs
# Filter by source/dest AZ in Athena or CloudWatch Insights
```

For ongoing visibility, the AWS blog post "Getting visibility into your Amazon EKS Cross-AZ pod to pod network bytes" provides a CloudWatch-based approach using VPC flow logs filtered by availability zone.
