resource "kubernetes_manifest" "require-waypoint" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "Gateway"
    "metadata" = {
      "name"      = "waypoint"
      "namespace" = var.namespace_name
      "labels" = {
        "istio.io/waypoint-for" = "namespace"
      }
      "annotations" = {
        "istio.io/waypoint-inbound-binding" = "STRICT"
      }
    }
    "spec" = {
      "gatewayClassName" = "istio-waypoint"
      "listeners" = [
        {
          "name"     = "mesh"
          "port"     = 15008
          "protocol" = "HBONE"
        }
      ]
    }
  }
}
