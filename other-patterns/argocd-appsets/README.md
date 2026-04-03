# ArgoCD ApplicationSet Auto-Discovery

This directory contains an ArgoCD deployment using the **ApplicationSet auto-discovery pattern**, migrated from a FluxCD setup. ApplicationSets automatically discover and deploy infrastructure charts, infrastructure resources, and applications across multiple clusters.

## Directory Structure

```
argocd-appsets/
├── bootstrap/
│   └── root-app.yaml              # Root Application that watches appsets/
├── appsets/
│   ├── infra-charts.yaml           # ApplicationSet for Helm chart discovery
│   ├── infra-resources.yaml        # ApplicationSet for raw/kustomize resource discovery
│   └── apps.yaml                   # ApplicationSet for application discovery
├── infrastructure/
│   ├── charts/                     # Helm charts (discovered by infra-charts.yaml)
│   │   ├── cert-manager/
│   │   │   ├── config.yaml         # Chart metadata for auto-discovery
│   │   │   └── values.yaml         # Base Helm values
│   │   ├── traefik/
│   │   │   ├── config.yaml
│   │   │   ├── values.yaml         # Base values (shared across clusters)
│   │   │   ├── values-test.yaml    # Test cluster overrides
│   │   │   ├── values-staging.yaml # Staging cluster overrides
│   │   │   └── values-production.yaml
│   │   └── kro/
│   │       ├── config.yaml
│   │       └── values.yaml
│   └── resources/                  # Raw manifests / Kustomize (discovered by infra-resources.yaml)
│       ├── gateway-api/
│       │   └── kustomization.yaml
│       ├── namespaces/
│       │   ├── demo.yaml
│       │   └── traefik.yaml
│       ├── cluster-issuer/
│       │   └── cluster-issuer.yaml
│       └── kro-definitions/
│           └── service.yaml
└── apps/                           # Applications (discovered by apps.yaml)
    └── demo/
        ├── Chart.yaml
        ├── values.yaml
        ├── values-test.yaml
        ├── values-staging.yaml
        ├── values-production.yaml
        └── templates/
            └── kro-service.yaml
```

## Clusters

| Cluster    | Domain                  | Label                  |
|------------|-------------------------|------------------------|
| test       | test.domain.local       | environment: test       |
| staging    | k8s.orb.local           | environment: staging    |
| production | production.domain.local | environment: production |

All clusters must be registered as ArgoCD cluster secrets with the label `argocd.argoproj.io/secret-type: cluster`.

## How It Works

### Bootstrap

1. Apply `bootstrap/root-app.yaml` to your ArgoCD instance:
   ```bash
   kubectl apply -f argocd-appsets/bootstrap/root-app.yaml
   ```
2. The root Application syncs the `appsets/` directory, which contains three ApplicationSets.
3. Each ApplicationSet uses a **Matrix generator** combining a Git generator (for auto-discovery) with a Clusters generator (for multi-cluster targeting).

### Auto-Discovery Flow

```
root-app.yaml
  └── watches appsets/
        ├── infra-charts.yaml
        │     └── discovers infrastructure/charts/*/config.yaml
        │           → creates one ArgoCD Application per chart × cluster
        ├── infra-resources.yaml
        │     └── discovers infrastructure/resources/*/
        │           → creates one ArgoCD Application per resource dir × cluster
        └── apps.yaml
              └── discovers apps/*/
                    → creates one ArgoCD Application per app × cluster
```

### Infrastructure Charts (`infra-charts.yaml`)

Uses the **Git file generator** to discover `config.yaml` files under `infrastructure/charts/`. Each `config.yaml` defines chart metadata (repo URL, chart name, version, namespace, sync wave). The ApplicationSet creates **multi-source Applications**:

- **Source 1**: The upstream Helm chart with base values + cluster-specific value overrides
- **Source 2**: This Git repo (referenced as `$values`) to provide the values files

Cluster-specific values files (e.g., `values-staging.yaml`) are optional via `ignoreMissingValueFiles: true`.

### Infrastructure Resources (`infra-resources.yaml`)

Uses the **Git directory generator** to discover directories under `infrastructure/resources/`. Each directory becomes a plain-manifest or Kustomize Application deployed to every cluster.

### Applications (`apps.yaml`)

Uses the **Git directory generator** to discover directories under `apps/`. Directories containing a `Chart.yaml` are auto-detected as Helm charts. Cluster-specific values are loaded via `values-<clusterName>.yaml` with `ignoreMissingValueFiles: true`.

## Adding New Components

### Add a new Helm chart

1. Create `infrastructure/charts/<name>/config.yaml`:
   ```yaml
   name: my-chart
   chart: my-chart
   repoURL: https://charts.example.com
   version: "1.0.0"
   namespace: my-namespace
   createNamespace: "true"
   syncWave: "0"
   ```
2. Create `infrastructure/charts/<name>/values.yaml` with base values.
3. Optionally create `values-test.yaml`, `values-staging.yaml`, `values-production.yaml` for cluster-specific overrides.
4. Commit and push — ArgoCD discovers and deploys automatically.

### Add a new infrastructure resource

1. Create a directory under `infrastructure/resources/<name>/`.
2. Add Kubernetes manifests or a `kustomization.yaml`.
3. Commit and push.

### Add a new application

1. Create a directory under `apps/<name>/`.
2. Add a `Chart.yaml` for Helm apps, or plain manifests for directory apps.
3. Optionally add `values-<clusterName>.yaml` for per-cluster overrides.
4. Commit and push.

## Prerequisites

Before bootstrapping, ensure the following ArgoCD AppProjects exist:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: infrastructure
  namespace: argocd
spec:
  description: Infrastructure components
  sourceRepos:
    - "*"
  destinations:
    - namespace: "*"
      server: "*"
  clusterResourceWhitelist:
    - group: "*"
      kind: "*"
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: apps
  namespace: argocd
spec:
  description: Application workloads
  sourceRepos:
    - "*"
  destinations:
    - namespace: "*"
      server: "*"
  clusterResourceWhitelist:
    - group: "*"
      kind: "*"
```

## Key Design Decisions

- **Go templates** are enabled on all ApplicationSets (`goTemplate: true`) with `missingkey=error` for strict validation.
- **`ignoreMissingValueFiles: true`** allows charts and apps to work without cluster-specific overrides — the base `values.yaml` is always sufficient.
- **Sync waves** control deployment ordering (e.g., cert-manager at `-3`, kro at `-2`, traefik at `-1`).
- **KRO CEL expressions** use `${}` syntax (not `$${}` as required by FluxCD's variable substitution escaping).
- **OCI Helm registries** (e.g., kro) use the registry URL without the `oci://` prefix, as ArgoCD handles the protocol automatically.
