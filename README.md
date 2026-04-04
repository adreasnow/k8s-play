# Playground for k8s

This repo creates a minikube k8s cluster with multiple nodes. It sets up FluxCD to automatically sync the resource definitions into the cluster using the credentials created during the fluxcd bootstrapping phase.

## Tool Requirements

- [FluxCD](https://fluxcd.io/) - Lightweight, stateless, self-managed GitOps tool for k8s
- [gh](https://cli.github.com) - Used for authenticating with GitHub
- Local k8s cluster - see [./docs/Create-k8s-cluster.md] for details/options
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - For managing k8s resources

### Reccomendations

- [k9s](https://k9scli.io) - TUI for exploring/managing k8s resources
- [flux9s](https://github.com/dgunzy/flux9s) - TUI or exploring/managing the status of FluxCD in a k9s way
- [kubeconform](https://github.com/yannh/kubeconform) - validates that the

## Base Tools used

These are the tools used to manage the repository itself

- [FluxCD](https://fluxcd.io/) - this could also be ArgoCD, but Flux solves the chicken-and-egg problem of defining it's own configuration
- [Flux Operator](https://fluxoperator.dev) - More feature rich implementation of FluxCD
- [Kutstomize](https://kustomize.io) - Tool that allows you modify k8s manifest files by creating amendments to the base defintions
- [Helm](https://helm.sh) - Package manager for k8s that builds upon the idea of templating values

## Services exposed

- Demo app - [demo.k8s.orb.local]
- Capacitor - [capacitor.k8s.orb.local]
- Traefik dasboard - [dashboard.k8s.orb.local]
- Flux-Operator Dashboard - [flux-operator.k8s.orb.local]

## Other TODO

- [x] Compare FluxCD with ArgoCD
  - ArgoCD feels more feature rick, but feels much less controllable and lean as a result
  - The main thing it adds is an interactive dashboard, but adds many more resources, and loses a DAG in favou of "sync waves"
- [ ] EKS via tofu
- [ ] AWS resource definitons
  - [ ] Maybe we could create IAM roles from within the KRO definition?

## Components

- [x] FluxCD
- [x] [cert-manager](https://cert-manager.io) - Used to generate certificates for TLS
  - [ ] Generate certw tih letsencrypt (must be in EKS environment)
- [x] [traefik](https://doc.traefik.io/traefik/) - RP that routes traffic to services inside of k8s
- [ ] [Gateway API CRDs](https://gateway-api.sigs.k8s.io) - CRDs that enable the use of the Gateway API
- [x] [KRO](https://kro.run) - Kube Resource Orchestrator - abstracts resource grupings into CRDs
  - [ ] App KR
    - TODO: test this
    - KRO keeps getting stuck...
  - [ ] Namespace KR
  - [ ] Cron KR
- [ ] Cloudflare-controller
- [ ] ExternalDNS?
- [ ] Istio Ambient Mode
  - if we want internal TLS. EKS Auto Mode handles TLS between nodes
- [ ] Traefik Gateway API CRDs?
- [ ] Gateway/GatewayClass Definitions
- [ ] Gateway API CRDs
- [ ] AWS ASCP
- [ ] Secrets Store CSI driver
- [ ] KEDA
- [ ] OTEL Colelctor driver
  - [ ] Node level collector
  - [ ] Cluster level collector
- [ ] OPA for enforcing rules
  - e.g. limits, PDBs, annotations must be set

## Productionising Alternatives

- Install Flux Operator via tofu with github app rather than cli bootstrap
- Cert manager to self-genrate certs with certbot
- All dashboards behind cloudflare-operator with access policies

If using Istio

- Uncomment annotations

When moving to EKS

- Uncomment LB for Traefik
- 
