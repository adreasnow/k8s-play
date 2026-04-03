# Bootstrapping

## Architecture

This setup uses the [Flux Operator](https://fluxoperator.dev) to manage Flux itself and `ResourceSet` CRDs to dynamically generate Flux Kustomization objects — similar to ArgoCD ApplicationSets.

Unlike vanilla FluxCD (which uses `flux bootstrap`), the Flux Operator:

- Manages Flux controllers via a `FluxInstance` CRD
- Can be installed with Helm, kubectl, Terraform, or the `flux-operator` CLI
- Supports `ResourceSet` for templated resource generation

### Multi-Cluster Design

Each cluster gets its own `FluxInstance` pointing at its own sync path in the same Git repo. The base infrastructure resources (cert-manager, traefik, kro, etc.) are shared across all clusters — only cluster-specific config differs:

```
flux-operator/
├── flux-instance-staging.yaml         # applied on the staging cluster
├── flux-instance-production.yaml      # applied on the production cluster
├── clusters/
│   ├── staging/                       # staging cluster-specific config
│   │   ├── cluster-vars.yaml          #   DOMAIN: k8s.orb.local
│   │   └── resourcesets-ks.yaml       #   → resourcesets/staging/
│   └── production/                    # production cluster-specific config
│       ├── cluster-vars.yaml          #   DOMAIN: k8s.production.local
│       └── resourcesets-ks.yaml       #   → resourcesets/production/
├── resourcesets/
│   ├── staging/                       # ResourceSets for staging
│   └── production/                    # ResourceSets for production
├── infrastructure/
│   ├── base/resources/                # shared across all clusters
│   ├── staging/namespaces/            # staging-specific namespaces
│   └── production/namespaces/         # production-specific namespaces
└── apps/
    ├── staging/demo/                  # staging app config
    └── production/demo/               # production app config
```

### Reconciliation Order (per cluster)

```
FluxInstance (manages Flux + syncs repo)
└── clusters/<env>/ (root sync path)
    ├── cluster-vars ConfigMap
    └── resourcesets Kustomization
        ├── infrastructure ResourceSet
        │   ├── namespaces
        │   ├── cert-manager
        │   ├── cluster-issuer      → depends on: cert-manager
        │   ├── gateway-api
        │   ├── kro                 → depends on: namespaces
        │   ├── kro-definitions     → depends on: kro, gateway-api
        │   └── traefik             → depends on: cluster-issuer, gateway-api, namespaces
        └── apps ResourceSet        (depends on infrastructure ResourceSet)
            └── demo                → depends on: namespaces
```

### Adding a New App

1. Create a directory under `apps/staging/<app-name>/` with your manifests
2. Add an input entry to `resourcesets/staging/apps.yaml`:

```yaml
- name: my-new-app
  path: ./flux-operator/apps/staging/my-new-app
  namespace: my-new-app
```

3. If needed, add a namespace to `infrastructure/staging/namespaces/`

### Adding a New Infrastructure Component

1. Create a directory under `infrastructure/base/resources/<component>/`
2. Add an input entry to `resourcesets/staging/infrastructure.yaml`:

```yaml
- name: my-component
  path: ./flux-operator/infrastructure/base/resources/my-component
  deps: "cert-manager" # optional
  usePostBuild: "true" # optional
  timeout: "10m" # optional
  prune: "false" # optional
  force: "true" # optional
```

## Initial Setup (Staging)

1. Create a Kubernetes cluster

2. Install the Flux Operator via Helm

```bash
helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace
```

3. Create the Git auth secret

```bash
ssh-keygen -t ed25519 -C "ArgoCD Deploy Key" -N "" -f ./deploy-key
gh repo deploy-key add ./deploy-key.pub --title "ArgoCD Deploy Key"

flux create secret git flux-system \
  --namespace=flux-system \
  --url=ssh://git@github.com/adreasnow/k8s-play \
  --private-key-file=./deploy-key
```

4. Apply the FluxInstance to bootstrap the cluster

```bash
kubectl apply -f flux-operator/flux-instance-staging.yaml
```

5. Verify the deployment

```bash
kubectl get fluxinstance -n flux-system
kubectl get fluxreport -n flux-system -o yaml
kubectl get resourcesets -n flux-system
```

## Day-to-Day Operations

### Check Status

```bash
kubectl get fluxinstance -n flux-system
kubectl get fluxreport -n flux-system -o yaml
kubectl get resourcesets -n flux-system
kubectl get kustomizations -n flux-system
```

### Force Reconciliation

```bash
flux reconcile source git flux-system && flux reconcile kustomization flux-system
```

### Access the Web UI

```bash
kubectl -n flux-system port-forward svc/flux-operator 9080:9080
# Open http://localhost:9080
```
