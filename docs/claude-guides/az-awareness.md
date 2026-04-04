# EKS Auto Mode: Traefik + NLB + Cross-AZ Optimization

## 1. Gateway API CRDs

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
```

## 2. cert-manager

Required because Traefik's built-in ACME does not issue certs for Gateway API listeners.

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set crds.enabled=true
```

See the cert-manager artifact for ClusterIssuer, IAM, and Certificate setup.

## 3. Traefik

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
```

### values.yaml

```yaml
ports:
  web:
    port: 80
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    port: 443

providers:
  kubernetesIngress:
    enabled: false
  kubernetesGateway:
    enabled: true
    nativeLBByDefault: true # Routes via ClusterIP so PreferClose works

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
          name: my-wildcard-cert # Created by cert-manager
          group: ""

service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "instance"
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
  spec:
    externalTrafficPolicy: Local

deployment:
  replicas: 2

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: traefik

podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

```bash
helm install traefik traefik/traefik \
  -n traefik --create-namespace \
  --values values.yaml
```

## 4. Cross-AZ optimization

### On every Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  trafficDistribution: PreferClose
  selector:
    app: my-app
  ports:
    - port: 80
```

### On every Deployment

```yaml
spec:
  template:
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: my-app
```

### CoreDNS

```bash
kubectl annotate service kube-dns -n kube-system \
  service.kubernetes.io/topology-mode=Auto
```

## 5. Example app with HTTPRoute

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
  namespace: my-app
spec:
  replicas: 4
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: whoami
      containers:
        - name: whoami
          image: traefik/whoami
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: whoami
  namespace: my-app
spec:
  trafficDistribution: PreferClose
  selector:
    app: whoami
  ports:
    - port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: whoami
  namespace: my-app
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
  hostnames:
    - "whoami.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: whoami
          port: 80
```

## Why each annotation/setting matters

| Setting                                       | Why                                                            |
| --------------------------------------------- | -------------------------------------------------------------- |
| `aws-load-balancer-type: external`            | Uses the EKS Auto Mode LB controller                           |
| `aws-load-balancer-scheme: internet-facing`   | Public NLB                                                     |
| `aws-load-balancer-nlb-target-type: instance` | Routes to NodePort                                             |
| `aws-load-balancer-backend-protocol: tcp`     | TCP passthrough — 16x cheaper NLCUs than TLS                   |
| `externalTrafficPolicy: Local`                | NLB only targets nodes with Traefik pods, avoids cross-AZ hop  |
| `nativeLBByDefault: true`                     | Traefik routes via ClusterIP so kube-proxy applies PreferClose |
| `trafficDistribution: PreferClose`            | kube-proxy routes to same-AZ pods first                        |
| `topologySpreadConstraints`                   | Ensures pods are evenly distributed across AZs                 |

## Encryption in transit

EKS Auto Mode runs on Nitro instances which encrypt all inter-node traffic at the hardware level (AES-256-GCM) with zero config and zero performance cost. If you later need workload identity (mTLS), add Istio Ambient Mode on top — nothing here conflicts with it.
