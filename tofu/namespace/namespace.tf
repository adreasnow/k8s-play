resource "kubernetes_namespace" "namesapce" {
  metadata {
    name = var.namespace_name

    labels = {
      "istio.io/dataplane-mode" = "ambient"
      "istio.io/use-waypoint"   = "waypoint"
    }

    spec = {
      trafficDistribution = "preferClose"
    }
  }
}
