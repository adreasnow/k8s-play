# https://artifacthub.io/packages/helm/flux-operator/flux-operator
resource "helm_release" "flux_operator" {
  # depends_on = [orbstack_k8s.cluster]

  name             = "flux-operator"
  namespace        = "flux-system"
  repository       = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  version          = "0.46.0"
  chart            = "flux-operator"
  create_namespace = true
}
