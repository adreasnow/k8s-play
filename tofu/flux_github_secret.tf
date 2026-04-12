# TODO: configure for github app - https://fluxoperator.dev/docs/crd/gitrepository/#github

# resource "kubernetes_secret" "flux_github" {
#   # depends_on = [orbstack_k8s.cluster]

#   metadata {
#     name      = "github-auth"
#     namespace = "flux-system"
#   }

#   data = {
#     githubAppID                = ""
#     githubAppInstallationOwner = ""
#     githubAppInstallationID    = ""
#     githubAppPrivateKey        = ""
#   }

#   type = "Opaque"
# }

resource "kubernetes_secret" "flux_github" {
  # depends_on = [orbstack_k8s.cluster]

  metadata {
    name      = "github-auth"
    namespace = helm_release.flux_operator.namespace
  }

  data = {
    identity       = file("../deploy-key")
    "identity.pub" = file("../deploy-key.pub")
    known_hosts    = "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
  }

  type = "Opaque"
}
