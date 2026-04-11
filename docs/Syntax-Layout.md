# Flux and Kustomize Syntaxa and Layout

## Layout

```bash
fluxcd
├── apps
│   ├── common
│   │   └── apps
│   ├── internal
│   │   └── apps
│   └── bellroy
│       └── apps
├── clusters
│   ├── bellroy-test
│   ├── bellroy-staging
│   ├── bellroy-production
│   ├── internal-staging
│   └── internal
└── infrastructure
    ├── common
    │   ├── namespaces
    │   └── resources
    ├── bellroy
    │   ├── namespaces
    │   └── resources
    └── internal
        ├── namespaces
        └── resources
```

## Flux

Flux Operator is controlled from the `FluxInstance` defined in the manually applied manifest `./fluxcd/flux-instance-<cluster name>.yaml`.

This specifies the root path that the flux controller looks to for all defintions. Within that directory it looks for a `kustomization.yaml` file that references all the other resources in a big tree.

## Kustomize

- Kustomize references from `kustomize.config.k8s.io/v1beta1` are all relative to the current directoy
- Kustomize does not include any `.yaml` files unless they are explicitly referenced, e.g.
  - If pointed at a directory, it will only include any `kustomization.yaml` files which must include all the other files in the directory
  - Resources can be external manifests

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - infrastructure-rs.yaml
  - resources
  - https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
```

- In order to create a named resource with kustomize, flux adds it's own `Kustomization` resource in api `kustomize.toolkit.fluxcd.io/v1`. This resource allows you to control how flux manages the reosurce, and how it handles the resulting DAG, e.g. managing dependencies, whether to remove the objects after they're orphaned, how many times to keep trying the deployment, how long to wait for the resource to come up, etc.
  - Names must be uniquem or resources will be overwritten witthout warning
  - Paths in these Kustomizations are relative to the root of the git directory.
  - Naming convention of these files is to append `-ks.yaml`
  - Dependency chaining is managed by adding a `dependsOn` block to the kutomizations, which is a list of the named dependencies

- Flux Operator adds a new `ResourceSet` object in the `fluxcd.controlplane.io/v1` api which allows FluxCD Kustomizations to be templated based on a list of input. Unfortunately it uses its own templating language that is different to KOR/Helm
  - Naming convention of these files is to append `-rs.yaml`

- Global variables are handled with the use of a `ConfigMap`. Any Kustomization can use a post-build substitution step as such
  - This will substitute any strings from the map in the form of `${VAR_NAME}`
  - This Kustomization postBuild step happens before KRO builds it's templates, so to use both KRO variables must be in the form `$${variable-name}`

```yaml
postBuild:
  substituteFrom:
    - kind: ConfigMap
      name: cluster-vars
```

- Helm resources are created as a pair of `HelmRepository` and `HelmRelease` objects.
  - The `HelmRelease` object specifies the version of the helm chart, as well as any values to be set.
  - They are typically kept in teh same directory as each other and must have a `kustomization.yaml` file.
