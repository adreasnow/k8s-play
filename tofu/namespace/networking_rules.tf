resource "kubernetes_manifest" "require-waypoint" {
  manifest = {
    "apiVersion" = "security.istio.io/v1"
    "kind"       = "AuthorizationPolicy"
    "metadata" = {
      "name"      = "require-waypoint"
      "namespace" = var.namespace_name
    }
    "spec" = {
      "action" = "DENY"
      "rules" = [
        {
          "from" = [
            {
              "source" = {
                "notPrincipals" = ["cluster.local/ns/${var.namespace_name}/sa/waypoint"]
              }
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_network_policy_v1" "allow_same_namespace_communication" {
  metadata {
    name      = "allow-same-namespace-communication"
    namespace = var.namespace_name
  }

  spec {
    action       = "ALLOW"
    policy_types = ["Egress", "Ingress"]
    egress {
      to {
        source {
          namespaces = [
            var.namespace_name
          ]
        }
      }
    }
    ingress {
      from {
        source {
          namespaces = [
            var.namespace_name
          ]
        }
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "block_system_namespace_egress" {
  metadata {
    name      = "block-system-namespace-egress"
    namespace = var.namespace_name
  }

  spec {
    action       = "DENY"
    policy_types = ["Egress"]
    egress {
      to {
        operation {
          namespaces = [
            "kube-system",
            "istio-system",
            "kube-public",
            "kube-node-lease",
            "traefik"
          ]
        }
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "allow_dns_egress" {
  metadata {
    name      = "allow-dns-egress"
    namespace = var.namespace_name
  }

  spec {
    action       = "ALLOW"
    policy_types = ["Egress"]
    pod_selector {}
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }
      ports {
        protocol = "UDP"
        port     = 53
      }
      ports {
        protocol = "TCP"
        port     = 53
      }
    }
  }
}

# Allow egress to external networks
# Does not overwrite existing DENY rules
# all east-west traffic still goes through Istio with STRICT routing
resource "kubernetes_network_policy_v1" "allow_egress" {
  metadata {
    name      = "allow-egress"
    namespace = var.namespace_name
  }

  spec {
    action       = "ALLOW"
    policy_types = ["Egress"]
    pod_selector {}
    egress {}
  }
}
