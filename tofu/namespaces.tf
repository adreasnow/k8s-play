
locals {
  namespaces = [
    { name = "demo", roles = [] },
  ]
}

resource "kubernetes_config_map_v1" "app_namespaces" {
  metadata {
    name = "app-namespaces"
  }

  data = {
    namespaces = yamlencode(local.namespaces)
  }
}
