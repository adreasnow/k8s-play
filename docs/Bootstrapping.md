# Bootstrapping

## Updating

Run renovate with docker

```bash
docker run --rm -e RENOVATE_REPOSITORIES=adreasnow/k8s-play renovate/renovate --token $(gh auth token)
```

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
