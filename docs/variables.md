# Flux Post-Build Variable Substitution

This project uses [Flux post-build variable substitution](https://fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitution) to centralise configuration values (like the cluster domain) so they can be changed in one place and propagated across all manifests.

## How It Works

1. Variables are defined in a `ConfigMap` in the `flux-system` namespace.
2. Each Flux `Kustomization` that needs access to those variables includes a `postBuild.substituteFrom` reference to the ConfigMap.
3. Manifests use `${VARIABLE_NAME}` syntax, and Flux replaces these at reconciliation time — after kustomize builds the manifests but before they are applied to the cluster.

## Variable Definitions

Variables live in [`infrastructure/staging/cluster-vars.yaml`](../infrastructure/staging/cluster-vars.yaml):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-vars
  namespace: flux-system
data:
  DOMAIN: k8s.orb.local
```

This ConfigMap is included in the staging kustomization so Flux keeps it in sync:

```yaml
# infrastructure/staging/kustomization.yaml
resources:
  - namespaces-ks.yaml
  - cluster-vars.yaml
```

## Available Variables

| Variable | Description                  | Example Value    |
|----------|------------------------------|------------------|
| `DOMAIN` | Base domain for all services | `k8s.orb.local`  |

## Referencing Variables in Flux Kustomizations

Any Flux `Kustomization` that needs variable substitution must include a `postBuild` block:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: example
  namespace: flux-system
spec:
  # ... other fields ...
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: cluster-vars
```

The following Kustomizations currently have this configured:

- `traefik` — [`infrastructure/base/traefik-ks.yaml`](../infrastructure/base/traefik-ks.yaml)
- `kro-definitions` — [`infrastructure/base/kro-definitions.yaml`](../infrastructure/base/kro-definitions.yaml)
- `demo` — [`apps/staging/demo-ks.yaml`](../apps/staging/demo-ks.yaml)

> **Note:** If you add a new Flux Kustomization that needs access to these variables, you must add the `postBuild` block to it — it is not inherited automatically.

## Using Variables in Manifests

Reference any variable with `${VARIABLE_NAME}`:

```yaml
# infrastructure/base/resources/traefik/certificate.yaml
spec:
  commonName: "*.${DOMAIN}"
  dnsNames:
    - "*.${DOMAIN}"
    - "${DOMAIN}"
```

```yaml
# apps/staging/demo/kro-service.yaml
spec:
  hostname: demo.${DOMAIN}
```

Flux replaces `${DOMAIN}` with the value from the ConfigMap (e.g. `k8s.orb.local`) before applying the manifest.

## Escaping `${}` for kro

kro's `ResourceGraphDefinition` resources use the same `${...}` syntax for CEL expressions (e.g. `${schema.spec.name}`). If Flux sees these, it will try to substitute them and fail.

To prevent this, **double the dollar sign** — write `$${...}` in the YAML. Flux strips one `$` during substitution, so kro receives the intended `${...}`:

```yaml
# In the RGD file (infrastructure/base/resources/kro-definitions/service.yaml)
# What you write:
metadata:
  name: $${schema.spec.name}

# What kro sees after Flux substitution:
metadata:
  name: ${schema.spec.name}
```

This escaping is required for **every** `${...}` expression in any manifest managed by a Flux Kustomization that has `postBuild.substituteFrom` configured. If a Flux Kustomization does *not* have `postBuild`, no escaping is needed.

### Quick reference

| In YAML source         | After Flux substitution | Used by   |
|------------------------|-------------------------|-----------|
| `${DOMAIN}`            | `k8s.orb.local`         | Flux      |
| `$${schema.spec.name}` | `${schema.spec.name}`   | kro       |

## Changing the Domain

To change the domain for the entire cluster:

1. Edit `infrastructure/staging/cluster-vars.yaml` and update the `DOMAIN` value.
2. Commit and push.
3. Flux will reconcile and update all affected resources automatically.

No other files need to change.

## Adding a New Variable

1. Add the key/value pair to the `data` section of `infrastructure/staging/cluster-vars.yaml`.
2. Use `${NEW_VARIABLE}` in any manifest whose Flux Kustomization has `postBuild.substituteFrom` configured.
3. If the variable is needed in a Flux Kustomization that doesn't yet have `postBuild`, add the block (see [Referencing Variables](#referencing-variables-in-flux-kustomizations) above).
4. Document the variable in the [Available Variables](#available-variables) table above.
