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
