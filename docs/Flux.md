# FluxCD

FluxCD is a GitOpts tool for managing k8s resources in a declarative manner. It uses GitHub (or another git provider) as a source of truth and ensures that what you have defined in source is what is deployed in your cluster

Under the hood FluxCD simply generates a giant k8s manifest file from a repository and uses Kustomize and its own CRDs to build a DAG of all the reources it manages. It then procedurally triggers the k8s api to reconcile these dependencies in order.

While FluxCD will check its definiton of the desired state against the source of truth evern 10 minutes (otr however frequently you tell it to), it will periodially check the resources in the cluster for drift and correct them if they do not match the spec. This timeframe is determined per-object.

## Flux's Ownership

Flux is a CNCF Graduated project. While its original corportate owners no longer maintain it, as a CNCF Graduated project it is actively developed and maintined by the community.

## Flux Operator

Flux Operator is a set of tooling that runs on top of FluxCD and provides a set of extra CRDs and controllers for making it significantly more powerful.

Among other, these include the `FluxInstance` which provides a bootstrap free CRD for provisioning/manging FluxCD installations, and `ResourceSets` which template resources to minimise the amount of boilerplate in kustomizations

It provides a few extra interfaces for the API, such as read only dashboard, and an MCP server.

There's also a CRD for creating ephemeral resources that are created and torn down with the lifecycle of a GitHub PR.
