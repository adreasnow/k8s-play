locals {
  namespaces = [
    { name = "demo", role = "" },
    { name = "test", role = "" },
  ]
}

# This resource creates ResourceSetInputProviders for each namespace
# There is a ResourceSet that looks for these ResourceSetInputProviders to create namespaces based on the template
resource "kubernetes_manifest" "app_namespaces_rsip" {
  depends_on = [helm_release.flux_operator]

  for_each = { for ns in local.namespaces : ns.name => ns }

  manifest = {
    apiVersion = "fluxcd.controlplane.io/v1"
    kind       = "ResourceSetInputProvider"
    metadata = {
      name      = "app-namespaces-${each.value.name}"
      namespace = "flux-system"
      labels = {
        template = local.namespace-rsip-template-name
      }
    }
    spec = {
      type = "Static"
      defaultValues = {
        name = each.value.name
        role = each.value.role
      }
    }
  }
}
