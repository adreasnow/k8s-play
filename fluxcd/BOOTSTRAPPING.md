# Bootstrapping

## FluxCD

1. Create a k8s CLuster
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
kubectl apply -f fluxcd/flux-instance-staging.yaml
```

## Day-to-Day Operations

### To force flux to reconcile

```bash
flux reconcile source git flux-system && flux reconcile kustomization flux-system
```

### Diff your changes against main

```bash
flux diff kustomization flux-system --path=./fluxcd/clusters/staging
```

### Build the whole k8s manifest

```bash
flux build kustomization flux-system --path=./fluxcd/clusters/staging
```

### Check Status

```bash
kubectl get fluxinstance -n flux-system
kubectl get fluxreport -n flux-system -o yaml
kubectl get resourcesets -n flux-system
kubectl get kustomizations -n flux-system
```

### Access the Web UI

```bash
kubectl -n flux-system port-forward svc/flux-operator 9080:9080
# Open http://localhost:9080
```

### To validate that kustomize can build flux

```bash
kubectl kustomize clusters/staging | kubeconform -strict -summary \
  -kubernetes-version 1.31.0 \
  -schema-location default \
  -skip CustomResourceDefinition \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```
