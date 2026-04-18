terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.19.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "orbstack"
}

provider "kubectl" {
  config_path    = "~/.kube/config"
  config_context = "orbstack"
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}
