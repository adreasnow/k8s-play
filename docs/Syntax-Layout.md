# How Flux/Kustomize Works

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

## Layout

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

### Ordering

Any resource that's defined in `clusters/<clustername>/kustomization.yaml` will automatically be applied at the same time however many resources are dependent and need to be applied in order.

To accomplish this instead of referencing it in a kustomization's `resources` use use the `kustomize.toolkit.fluxcd.io/v1` `Kustomization` object to create a dependency chain, by defining a directory as a named fluxcd `Kustomization` with `wait=true`, and create another with a depends-on.

e.g. traefik depends on having certs which depdnends on there being a cluster issuer, which depends on cert-manager being installed, so in the `infrastructure/base` directory we:

1. Reference the `certificates` directory in the top level `kustomization.yaml`
2. Create `resources/certificates/cert-manager-ks.yaml` which applies `resources/certificates/cert-manager`
3. Create `resources/certificates/cluster-issuer.yaml` which waits for `cert-manager` before applying `resources/certificates/cluster-issuer.yaml`
4. Create `resources/certificates/traefik-cert-ks.yaml` which waits for `cluster-issuer` before applying `resources/certificates/traefik-cert`
5. Create a top level `traefik-ks.yaml` which waits for `traefik-cert` before applying `resources/traefik`
