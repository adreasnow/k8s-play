variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "cluster_domain" {
  description = "Domain of the cluster"
  type        = string
}

variable "flux_cluster_config" {
  description = "Configuration for the FluxInstance object"
  type = object({
    cluster = object({
      size   = string
      domain = string
    })
    sync = object({
      ref  = string
      path = string
    })
  })
}
