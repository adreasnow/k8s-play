# Common Management tasks

For most things you'll want to just use

- `k9s` to view the contents/status of cluster resources
- `flux9s` to view the status of Flux and it's recinciliation.

Below are some other helpful commands and tools for debugging what's going on.

## To force flux to reconcile

```bash
flux reconcile kustomization flux-system --with-source --timeout=2m && \
flux reconcile kustomization infrastructure --with-source --timeout=15m && \
flux reconcile kustomization apps --with-source --timeout=15m

```

## To force the reconciliation of a specific manifest

This destoys and re-creates the resources, so use with caution

```bash
flux reconcile helmrelease linkerd-control-plane --force
```

## To re-create a failed flux helm installed chart

```bash
helm list -n flux-system

helm uninstall <chart name> -n flux-system

flux reconcile helmrelease <flux helmRelease name> --force
```

## Diff your changes against main

```bash
flux diff kustomization flux-system --path=./fluxcd/clusters/internal
```

## Build the whole k8s manifest

```bash
flux build kustomization flux-system --path=./fluxcd/clusters/internal
```

## Check Status

```bash
kubectl get fluxinstance -n flux-system
kubectl get fluxreport -n flux-system -o yaml
kubectl get resourcesets -n flux-system
kubectl get kustomizations -n flux-system
```

## Access the Web UI

This is also exposed at `flux-operator.k8s.orb.local`

```bash
kubectl -n flux-system port-forward svc/flux-operator 9080:9080
```

## To validate that kustomize can build flux

```bash
kubectl kustomize fluxcd/clusters/internal | kubeconform -strict -summary \
  -kubernetes-version 1.31.0 \
  -schema-location default \
  -skip CustomResourceDefinition \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```
