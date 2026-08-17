terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
  }

  backend "s3" {
    bucket                      = "dozzle"
    key                         = "kubernetes/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://d17eb09b6bce2f90e16e800bb2a6baf9.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace_v1" "dozzle" {
  metadata { name = "dozzle" }
}

# 1. Service Account for Dozzle
resource "kubernetes_service_account_v1" "dozzle_pod_viewer" {
  metadata {
    name      = "dozzle-pod-viewer"
    namespace = kubernetes_namespace_v1.dozzle.metadata[0].name
  }
}

# 2. Cluster Role to allow log reading
resource "kubernetes_cluster_role_v1" "dozzle_reader" {
  metadata { name = "dozzle-log-reader" }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "nodes", "events", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }
}

# 3. Bind the Role to the Service Account
resource "kubernetes_cluster_role_binding_v1" "dozzle_binding" {
  metadata { name = "dozzle-global-binding" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.dozzle_reader.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.dozzle_pod_viewer.metadata[0].name
    namespace = kubernetes_namespace_v1.dozzle.metadata[0].name
  }
}

# 4. The Deployment
resource "kubernetes_deployment_v1" "dozzle" {
  metadata {
    name      = "dozzle"
    namespace = kubernetes_namespace_v1.dozzle.metadata[0].name
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "dozzle" } }
    template {
      metadata { labels = { app = "dozzle" } }
      spec {
        service_account_name = kubernetes_service_account_v1.dozzle_pod_viewer.metadata[0].name
        container {
          name  = "dozzle"
          image = "amir20/dozzle:v10.6.6"
          port { container_port = 8080 }

          env {
            name  = "DOZZLE_MODE"
            value = "k8s"
          }
          env {
            name  = "DOZZLE_LEVEL"
            value = "info"
          }
          resources {
            limits   = { memory = "128Mi", cpu = "200m" }
            requests = { memory = "64Mi", cpu = "50m" }
          }
        }
      }
    }
  }
}

# 5. Service & Ingress
resource "kubernetes_service_v1" "dozzle_svc" {
  metadata {
    name      = "dozzle"
    namespace = kubernetes_namespace_v1.dozzle.metadata[0].name
  }
  spec {
    selector = { app = "dozzle" }
    port {
      port        = 80
      target_port = 8080
    }
  }
}

resource "kubernetes_ingress_v1" "dozzle_ingress" {
  metadata {
    name      = "dozzle-ingress"
    namespace = kubernetes_namespace_v1.dozzle.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"    = "traefik"
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
    }
  }
  spec {
    tls {
      hosts       = ["dozzle.darkroasted.vps-kinghost.net"]
      secret_name = "dozzle-tls-certs"
    }
    rule {
      host = "dozzle.darkroasted.vps-kinghost.net"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.dozzle_svc.metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }
}
