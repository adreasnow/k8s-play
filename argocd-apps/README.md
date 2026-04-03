# ArgoCD Apps — App-of-Apps with Kustomize Overlays

This directory contains the ArgoCD deployment configuration, migrated from FluxCD. It uses the **app-of-apps** pattern with **Kustomize base + per-cluster overlays** to manage multiple clusters from a single repo.

## Pattern Overview

- **No ApplicationSets** — every ArgoCD `Application` is explicitly defined.
- A `base/` directory contains `Application` CRDs for every component with placeholder/default values.
- Per-cluster overlay directories (`clusters/<cluster>/`) use Kustomize to patch the base Applications with cluster-specific values (destination server, Helm values files, etc.).
- A **root Application** per cluster (in `bootstrap/`) points at that cluster's overlay directory, forming the app-of-apps entrypoint.

## Clusters

| Cluster    | Domain                   | ArgoCD Server URL                  |
|------------|--------------------------|------------------------------------|
| test       | test.domain.local        | `https://test.domain.local`        |
| staging    | k8s.orb.local            | `https://kubernetes.default.svc`   |
| production | production.domain.local  | `https://production.domain.local`  |

## Directory Structure

```text
argocd-apps/
├── bootstrap/                        # Root Applications — apply ONE per cluster
│   ├── test.yaml
│   ├── staging.yaml
│   └── production.yaml
├── clusters/                         # Kustomize overlays (per-cluster patches)
│   ├── test/
│   │   └── kustomization.yaml
│   ├── staging/
│   │   └── kustomization.yaml
│   └── production/
│       └── kustomization.yaml
├── base/                             # Base Application CRDs (cluster-agnostic)
│   ├── kustomization.yaml
│   ├── cert-manager.yaml
│   ├── traefik.yaml
│   ├── kro.yaml
│   ├── gateway-api.yaml
│   ├── namespaces.yaml
│   ├── cluster-issuer.yaml
│   ├── kro-definitions.yaml
│   └── demo.yaml
├── infrastructure/                   # Helm values & raw manifests for infra
│   ├── cert-manager/
│   │   └── values.yaml
│   ├── traefik/
│   │   ├── values.yaml              # Shared base values
│   │   ├── values-test.yaml
│   │   ├── values-staging.yaml
│   │   └── values-production.yaml
│   ├── kro/
│   │   └── values.yaml
│   ├── gateway-api/
│   │   └── kustomization.yaml
│   ├── namespaces/
│   │   ├── demo.yaml
│   │   └── traefik.yaml
│   ├── cluster-issuer/
│   │   └── cluster-issuer.yaml
│   └── kro-definitions/
│       └── service.yaml             # KRO ResourceGraphDefinition
└── apps/                             # Application workloads
    └── demo/
        ├── Chart.yaml
        ├── values.yaml
        ├── values-test.yaml
        ├── values-staging.yaml
        ├── values-production.yaml
        └── templates/
            └── kro-service.yaml
```

## How It Works

### Sync Waves

Components are ordered via ArgoCD sync-wave annotations:

| Wave | Components                                  |
|------|---------------------------------------------|
| -3   | cert-manager, gateway-api CRDs, namespaces  |
| -2   | cluster-issuer, kro                         |
| -1   | kro-definitions, traefik                    |
|  0   | demo (application workloads)                |

### Multi-Source Applications

Applications that consume **external Helm charts** (cert-manager, traefik, kro) use ArgoCD's multi-source feature (`spec.sources`). One source points to the Helm registry, the other to this Git repo (using `$values` ref) so that `values.yaml` files are read from Git.

Applications that are **fully in-repo** (gateway-api, namespaces, cluster-issuer, kro-definitions, demo) use a single `spec.source` pointing to their Git path.

### Per-Cluster Customisation

The `clusters/<cluster>/kustomization.yaml` overlays use **JSON Patch (RFC 6902)** to:

1. Set `spec.destination.server` on **all** Applications to the correct cluster API server.
2. Replace placeholder `values-CLUSTER.yaml` references with the real per-cluster values file (e.g. `values-test.yaml`).

## Getting Started

### 1. Install ArgoCD on the management cluster

```text
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 2. Apply the bootstrap Application for your cluster

For the **staging** cluster (where ArgoCD is running locally):

```text
kubectl apply -f argocd-apps/bootstrap/staging.yaml
```

For a **remote** cluster (test or production), first register the cluster with ArgoCD:

```text
argocd cluster add <context-name> --name test
kubectl apply -f argocd-apps/bootstrap/test.yaml
```

### 3. ArgoCD takes over

The root Application syncs the cluster overlay, which renders all the child Applications via Kustomize. ArgoCD then syncs each child Application respecting sync-wave ordering.

## Migration Notes (FluxCD → ArgoCD)

- FluxCD's `$${}` escaping for KRO CEL expressions has been replaced with `${}` (ArgoCD has no variable substitution that conflicts).
- FluxCD `Kustomization` dependency chains are replaced by ArgoCD **sync-wave annotations**.
- FluxCD `HelmRepository` + `HelmRelease` objects are replaced by ArgoCD `Application` CRDs with Helm chart sources.
- FluxCD's `postBuild.substituteFrom` cluster variables are replaced by per-cluster Helm values files selected via Kustomize overlay patches.
