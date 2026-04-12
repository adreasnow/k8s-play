resource "helm_release" "flux_instance" {
  depends_on = [helm_release.flux_operator]

  name       = "flux"
  namespace  = helm_release.flux_operator.namespace
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-instance"

  # https://fluxoperator.dev/docs/crd/fluxinstance/
  values = [yamlencode({
    instance = {
      components = [
        "source-controller",
        "kustomize-controller",
        "helm-controller",
        "notification-controller"
      ]
      distribution = {
        version  = "2.8.5"
        registry = "ghcr.io/fluxcd"
        artifact = "oci://ghcr.io/controlplaneio-fluxcd/flux-operator-manifests"
      }
      cluster = {
        type          = "aws"
        size          = var.flux_cluster_config.cluster.size
        multitenant   = false # TODO ?
        networkPolicy = true
        domain        = var.flux_cluster_config.cluster.domain
      }
      sync = {
        kind       = "GitRepository"
        url        = "ssh://git@github.com/adreasnow/k8s-play"
        ref        = var.flux_cluster_config.sync.ref
        path       = var.flux_cluster_config.sync.path
        pullSecret = "github-auth"
        # provider   = "github" # TODO: For use with github app
      }
    }
  })]
}
