terraform {
  required_providers {
    minikube = {
      source = "scott-the-programmer/minikube"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

resource "minikube_cluster" "docker" {
  driver       = "docker"
  cluster_name = "staging"
  ports = [
    { host = "80", guest = "30000" },
    { host = "443", guest = "30001" }
  ]
}

provider "kubernetes" {
  host = minikube_cluster.docker.host

  client_certificate     = minikube_cluster.docker.client_certificate
  client_key             = minikube_cluster.docker.client_key
  cluster_ca_certificate = minikube_cluster.docker.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host = minikube_cluster.docker.host

    client_certificate     = minikube_cluster.docker.client_certificate
    client_key             = minikube_cluster.docker.client_key
    cluster_ca_certificate = minikube_cluster.docker.cluster_ca_certificate
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

  depends_on = [minikube_cluster.docker]
}

resource "kubernetes_manifest" "argocd_root_app" {
  manifest = yamldecode(file("${path.module}/bootstrap/root-app.yaml"))

  depends_on = [helm_release.argocd]
}
