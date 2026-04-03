# Bootstrapping

## FluxCD

1. Create a k8s CLuster
2. Bootstrap FluxCD

```bash
flux bootstrap github \
  --owner="$(gh repo view --json owner -q '.owner.login')" \
  --repository=$(gh repo view --json name -q '.name') \
  --branch=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name') \
  --path=./fluxcd/clusters/staging \
  --interval=30s \
  --personal
```

3. To force flux to reconcile

```bash
flux reconcile source git flux-system && flux reconcile kustomization flux-system
```

4. To validate that kustomize can build flux

```bash
kubectl kustomize clusters/staging | kubeconform -strict -summary \
  -kubernetes-version 1.31.0 \
  -schema-location default \
  -skip CustomResourceDefinition \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```
