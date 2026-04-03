# Playground for k8s

This repo creates a minikube k8s cluster with multiple nodes. It sets up FluxCD to automatically sync the resource definitions into the cluster using the credentials created during the fluxcd bootstrapping phase.

## Tool Requirements

- [FluxCD](https://fluxcd.io/) - Lightweight, stateless, self-managed GitOps tool for k8s
- [gh](https://cli.github.com) - Used for authenticating with GitHub
- Local k8s cluster
  - [orbstack](https://orbstack.dev) - Better, faster, lighter, less corporate docker-compatible container runtime thatn Docker
  - [Minikube](https://minikube.sigs.k8s.io/docs/) - Allows you to create local k8s clusters in docker
    - Requires a container runtime such as containerd, CRI-O, orbstack, or Docker
  - Another cluster of your choosing such as kind, k3s, or Docker

### Reccomendations

- [k9s](https://k9scli.io) - TUI for exploring/managing k8s resources
- [flux9s](https://github.com/dgunzy/flux9s) - TUI or exploring/managing the status of FluxCD in a k9s way
- [kubeconform](https://github.com/yannh/kubeconform) - validates that the

## Base Tools used

These are the tools used to manage the repository itself

- [FluxCD](https://fluxcd.io/) - this could also be ArgoCD, but Flux solves the chicken-and-egg problem of defining it's own configuration
- [Kutstomize](https://kustomize.io) - Tool that allows you modify k8s manifest files by creating amendments to the base defintions
- [Helm](https://helm.sh) - Package manager for k8s that builds upon the idea of templating values

## Services exposed

- Demo app - https://demo.k8s.orb.local
- Capacitor - https://capacitor.k8s.orb.local
- Traefik dasboard - https://dashboard.k8s.orb.local

## Other TODO

- [ ] Compare FluxCD with ArgoCD
- [ ] EKS via tofu
- [ ] AWS resource definitons
  - [ ] Maybe we could create IAM roles from within the KRO definition?

## Components

- [x] FluxCD
- [x] [cert-manager](https://cert-manager.io) - Used to generate certificates for TLS
- [x] [traefik](https://doc.traefik.io/traefik/) - RP that routes traffic to services inside of k8s
- [x] [KRO](https://kro.run) - Kube Resource Orchestrator - abstracts resource grupings into CRDs
  - [ ] App KR
    - TODO: test this
    - KRO keeps getting stuck...
  - [ ] Namespace KR
  - [ ] Cron KR
- [ ] ExternalDNS?
- [ ] Linkerd2 service mesh ()
- [ ] Traefik Gateway API CRDs?
- [ ] Gateway/GatewayClass Definitions
- [ ] Gateway API CRDs
- [ ] AWS ASCP
- [ ] Secrets Store CSI driver
- [ ] KEDA
- [ ] OTEL Colelctor driver
  - [ ] Node level collector
  - [ ] Cluster level collector

## Productionising Alternatives

- Install Flux via tofu with github app rather than cli bootstrap ([example](https://github.com/controlplaneio-fluxcd/flux-operator/blob/main/config/terraform/main.tf))
- Traefik to self-geenrate certs with certbot

## Layout

FluxCD reads the resources from the `./clusters/<clustername>` directory but does not traverse through the tree. Flux always follows the directions of `kustomization.yaml`, and there must always be a kustomization.yaml in a directory for Flux to know what to apply.

A top level `clusters/<clustername>/kustomization.yaml` file is used to specify all the appropriate manifest defintitons that are required for that cluster.

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
   - Minikube - `minikube start -p staging --ports=80:30000 --ports=443:30001`
     - If using minikube, you will also need to change the domain [infrastructure/staging/cluster-vars.yaml](.infrastructure/staging/cluster-vars.yaml) to `docker.localhost`
   - OrbStack - `orb start k8s`
4. Bootstrap flux from current repo

```bash
flux bootstrap github \
  --owner="$(gh repo view --json owner -q '.owner.login')" \
  --repository=$(gh repo view --json name -q '.name') \
  --branch=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name') \
  --path=./clusters/staging \
  --interval=30s \
  --personal
```

- To force flux to reconcile now:

```bash
flux reconcile source git flux-system && flux reconcile kustomization flux-system
```

- To validate that kustomize can build flux

```bash
kubectl kustomize clusters/staging | kubeconform -strict -summary \
  -kubernetes-version 1.31.0 \
  -schema-location default \
  -skip CustomResourceDefinition \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

## Stopping

To stop the cluster:

- Minikube - `minikube stop -p k8s-play`
- OrbStack - `orb stop k8s`

To destroy the cluster:

- Minikube - `minikube delete -p k8s-play`
- OrbStack - `orb delete k8s -fa`
