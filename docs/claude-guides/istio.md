Here's a complete guide for installing Istio ambient mode with waypoints on EKS Auto Mode using Helm.

---

## Istio Ambient Mode on EKS Auto Mode (Helm)

### How it works

Ambient mode replaces sidecars with two components:

- **ztunnel** — a per-node DaemonSet handling mTLS and L4 policy
- **waypoints** — optional per-namespace/service L7 proxies you deploy via the Gateway API

The Helm install deploys four charts in order: `base` → `istiod` → `cni` → `ztunnel`.

---

### Prerequisites

EKS Auto Mode uses Amazon's VPC CNI. EKS nodes have security groups that may block inter-node traffic on port **15008** (HBONE — the tunnel protocol ambient uses). You need to allow this between nodes.

```bash
# Get the cluster security group ID
NODE_SG=$(aws eks describe-cluster --name <your-cluster> \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

# Open port 15008 for HBONE between nodes
aws ec2 authorize-security-group-ingress \
  --group-id $NODE_SG \
  --protocol tcp \
  --port 15008 \
  --source-group $NODE_SG
```

Also install the Kubernetes Gateway API CRDs (required for waypoints):

```bash
kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null || \
  kubectl apply --server-side -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/experimental-install.yaml
```

---

### Step 1 — Add the Istio Helm repo

```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
```

---

### Step 2 — Install the four charts in order

The components must be installed separately to allow controlled upgrades.

```bash
# 1. CRDs and base resources
helm install istio-base istio/base \
  -n istio-system \
  --create-namespace \
  --wait

# 2. Control plane (istiod) with ambient profile
helm install istiod istio/istiod \
  -n istio-system \
  --set profile=ambient \
  --wait

# 3. CNI node agent — chains with VPC CNI on EKS
helm install istio-cni istio/cni \
  -n istio-system \
  --set profile=ambient \
  --wait

# 4. ztunnel DaemonSet (per-node L4 proxy)
helm install ztunnel istio/ztunnel \
  -n istio-system \
  --wait
```

> **EKS-specific note:** The CNI binary directory on EKS is `/opt/cni/bin`. If Istio doesn't auto-detect it, add `--set cni.cniBinDir=/opt/cni/bin` to the `istio-cni` install.

---

### Step 3 — Verify the install

```bash
kubectl get pods -n istio-system
# Expected:
# istiod-xxx          1/1 Running
# istio-cni-node-xxx  1/1 Running  (one per node)
# ztunnel-xxx         1/1 Running  (one per node)
```

---

### Step 4 — Enroll namespaces in the mesh

```bash
# Label any namespace to opt its pods into the ambient mesh
kubectl label namespace <your-namespace> istio.io/dataplane-mode=ambient
```

---

### Step 5 — Deploy a waypoint (for L7 policy)

Waypoints are optional but needed for HTTP-level traffic management, authorization policies, retries, etc.

```bash
# Deploy a waypoint for a namespace
istioctl waypoint apply --namespace <your-namespace> --enroll-namespace

# Or via kubectl (Gateway API)
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: waypoint
  namespace: <your-namespace>
  labels:
    istio.io/waypoint-for: namespace
spec:
  gatewayClassName: istio-waypoint
  listeners:
  - name: mesh
    port: 15008
    protocol: HBONE
EOF
```

Verify the waypoint is running:

```bash
kubectl get gateway -n <your-namespace>
kubectl get pods -n <your-namespace> -l gateway.istio.io/managed=soloist
```

---

### EKS SecurityGroup gotcha

If you're using EKS pod-attached SecurityGroups via `SecurityGroupPolicy` with Pod ENI trunking enabled, `POD_SECURITY_GROUP_ENFORCING_MODE` must be explicitly set to `standard`, or pod health probes will fail. This is because Istio uses link-local SNAT addresses for kubelet health probes, which VPC CNI misroutes in strict mode.

---

### Uninstall (reverse order)

```bash
helm uninstall ztunnel    -n istio-system
helm uninstall istio-cni  -n istio-system
helm uninstall istiod     -n istio-system
helm uninstall istio-base -n istio-system
kubectl delete namespace istio-system
```
