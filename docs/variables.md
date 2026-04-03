# Flux Post-Build Variable Substitution

This project uses [Flux post-build variable substitution](https://fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitution) to centralise configuration values so they can be changed in one place and propagated across all manifests.

## How It Works

1. Variables are defined in a `ConfigMap` in the `flux-system` namespace.
1. Each Flux `Kustomization` that needs access to those variables includes a `postBuild.substituteFrom` reference to the ConfigMap.
1. Manifests use `${VARIABLE_NAME}` syntax, and Flux replaces these at reconciliation time — after kustomize builds the manifests but before they are applied to the cluster.

## Variable Definitions

Variables live in [`infrastructure/staging/cluster-vars.yaml`](../infrastructure/staging/cluster-vars.yaml), e.g.:

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

> **Note:** If you add a new Flux Kustomization that needs access to these variables, you must add the `postBuild` block to it — it is not inherited automatically.

## Using Variables in Manifests

Reference any variable with `${VARIABLE_NAME}`, e.g.:

```yaml
# infrastructure/base/resources/traefik/certificate.yaml
spec:
  commonName: "*.${DOMAIN}"
  dnsNames:
    - "*.${DOMAIN}"
    - "${DOMAIN}"
```

Flux replaces `${DOMAIN}` with the value from the ConfigMap (e.g. `k8s.orb.local`) before applying the manifest.

## Escaping `${}` for KRO

KRO's `ResourceGraphDefinition` resources use the same `${...}` syntax for CEL expressions (e.g. `${schema.spec.name}`). If Flux sees these, it will try to substitute them and fail.

To prevent this, **double the dollar sign** — write `$${...}` in the YAML. Flux strips one `$` during substitution, so kro receives the intended `${...}`:

```yaml
metadata:
  name: $${schema.spec.name}
```

This escaping is required for **every** `${...}` expression in any manifest managed by a Flux Kustomization that has `postBuild.substituteFrom` configured. If a Flux Kustomization does _not_ have `postBuild`, no escaping is needed.

### Quick reference

| In YAML source         | After Flux substitution | Used by |
| ---------------------- | ----------------------- | ------- |
| `${DOMAIN}`            | `k8s.orb.local`         | Flux    |
| `$${schema.spec.name}` | `${schema.spec.name}`   | kro     |
