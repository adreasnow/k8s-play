# Playground for k8s

This repo creates a minikube k8s cluster with multiple nodes. It sets up FluxCD to automatically sync the resource definitions into the cluster using the credentials created during the fluxcd bootstrapping phase.

## Tool Requirements

- [Minikube](https://minikube.sigs.k8s.io/docs/) - Allows you to create local k8s clusters in docker
- [FluxCD](https://fluxcd.io/) - Lightweight, stateless, self-managed GitOps tool for k8s
- [gh](https://cli.github.com) - Used for authenticating with GitHub

## Base Tools used

These are the tools used to manage the repository itself

- [FluxCD](https://fluxcd.io/) - this could also be ArgoCD, but Flux solves the chicken-and-egg problem of defining it's own configuration
- [Kutstomize](https://kustomize.io) - Tool that allows you modify k8s manifest files by creating amendments to the base defintions
- [Helm](https://helm.sh) - Package manager for k8s that builds upon the idea of templating values

## Components

- [cert-manager](https://cert-manager.io) - Used to generate certificates for TLS
- [traefik-proxy]()

## Layout

FluxCD reads the resources from the `./clusters/<clustername>` directory but does not traverse through the tree. A top level `clusters/<clustername>/kustomization.yaml` file is used to specify all the appropriate manifest defintitons that are required for that cluster.

The typical structure will look something like this, though `apps` is often swapped out for `teams` with a `CODEOWNERS.md`:

```bash
├── apps
│   ├── base
│   ├── production
│   └── staging
├── infrastructure
│   ├── base
│   ├── production
│   └── staging
└── clusters
    ├── production
    └── staging
```

Within each cluster the `kustomization.yaml` will reference:

- `flux-system` (FluxCD's self-definitions)
- `../infrastructure/base` (common infra for all clusters)
- `../infrastructure/<clustername>` (infrastructure/kustomizations for that cluster)
- `../apps/base` (common apps for all clusters)
- `../apps/<clustername>` (ifnrastructure/kustomizations for that cluster)

### Resources

Each resource that comes from a helm repository is defined in three steps:

1. A `HelmRepository` object which specifies the repository as a source to pull helm templates from
2. A `HelmRelease` object which lets you specify the version of the helm template, and populate it with any input specifications
3. (optional) A kustomization file that combines the two manifests into one. This isn't strictly necessary, but is best practice

### Ordering

Any resource that's defined in `clusters/<clustername>/kustomization.yaml` will automatically be applied at the same time however many resources are dependent and need to be applied in order.

To accomplish this instead of referencing it in a kustomization's `resources` use use the `kustomize.toolkit.fluxcd.io/v1` `Kustomization` object to create a dependency chain, by defining a directory as a named fluxcd `Kustomization` with `wait=true`, and create another with a depends-on.

e.g. traefik depends on having certs which depdnends on there being a cluster issuer, which depends on cert-manager being installed, so in the `infrastructure/base` directory we:

1. Reference the `certificates` directory in the top level `kustomization.yaml`
2. Create `resources/certificates/cert-manager-ks.yaml` which applies `resources/certificates/cert-manager`
3. Create `resources/certificates/cluster-issuer.yaml` which waits for `cert-manager` before applying `resources/certificates/cluster-issuer.yaml`
4. Create `resources/certificates/traefik-cert-ks.yaml` which waits for `cluster-issuer` before applying `resources/certificates/traefik-cert`
5. Create a top level `traefik-ks.yaml` which waits for `traefik-cert` before applying `resources/traefik`

## Getting Started

1. Fork this repo into your gh account
2. Ensure that you're logged into gh cli with said account
3. Create minikube cluster

```bash
minikube start \
  -p k8s-play \
  --ports=80:30000 \
  --ports=443:30001 \
  --driver=docker \
  '--addons=[dashboard]'
```

4. Bootstrap flux from current repo

```bash
flux bootstrap github \
  --owner="$(gh api user --jq '.login')" \
  --repository=k8s-play \
  --branch=main \
  --path=./clusters/staging \
  --interval=30s \
  --personal
```

## Stopping

To stop the cluster:

```bash
minikube stop -p k8s-play
```

To destroy the cluster:

```bash
minikube delete -p k8s-play
```
