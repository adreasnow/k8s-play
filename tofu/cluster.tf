# resource "orbstack_k8s" "cluster" {
#   enabled         = true
#   expose_services = true
# }

# Only needed for orbstack
resource "kubernetes_labels" "node" {
  api_version = "v1"
  kind        = "Node"
  metadata {
    name = "orbstack"
  }
  labels = {
    "topology.kubernetes.io/region" = "us-east-1"
    "topology.kubernetes.io/zone"   = "us-east-1a"
  }
}
