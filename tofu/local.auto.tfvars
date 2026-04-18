cluster_name   = "internal-staging"
cluster_domain = "k8s.orb.local"

flux_cluster_config = {
  cluster = {
    size   = "medium"
    domain = "cluster.local"
  }
  sync = {
    ref  = "refs/heads/main" # TODO: pin to tag for progressive rollout
    path = "fluxcd/clusters/internal"
  }
}
