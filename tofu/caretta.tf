resource "helm_release" "caretta" {
  # depends_on = [orbstack_k8s.cluster]

  name       = "caretta"
  namespace  = "caretta"
  repository = "https://helm.groundcover.com"
  chart      = "caretta"

  # Once the helm chart is fixed in a future version, this can be moved to fluxcd
  version          = "0.0.16"
  create_namespace = true

  values = [yamlencode({
    resources = {
      limits = {
        memory = "512Mi"
      }
    }
  })]
}
