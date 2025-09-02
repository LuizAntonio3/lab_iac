# Version: 2025-08-01 - 09:47

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = "https://${module.gke.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.ca_certificate)
  }
}

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 11.1"

  project_id   = var.project_id
  network_name = local.network_name
  routing_mode = "GLOBAL"

  subnets = [
      {
          subnet_name           = "${local.network_name}-subnet-01"
          subnet_ip             = "10.10.10.0/24"
          subnet_region         = local.cluster_region
      },
      {
          subnet_name           = "${local.network_name}-subnet-02"
          subnet_ip             = "10.10.20.0/24"
          subnet_region         = local.cluster_region
          subnet_private_access = "true"
          subnet_flow_logs      = "true"
      },
  ]

  secondary_ranges = {
    "${local.network_name}-subnet-02" = [
      {
        range_name    = "${local.network_name}-subnet-02-pods"
        ip_cidr_range = "192.168.64.0/20"
      },
    ]
}
}

module "gke" {
  source                     = "terraform-google-modules/kubernetes-engine/google"
  project_id                 = var.project_id
  name                       = local.cluster_name
  region                     = local.cluster_region
  network                    = module.vpc.network_name
  subnetwork                 = "${local.network_name}-subnet-02"
  ip_range_pods              = "${local.network_name}-subnet-02-pods"
  http_load_balancing        = false
  network_policy             = false
  horizontal_pod_autoscaling = true
  filestore_csi_driver       = false
  dns_cache                  = false

  depends_on = [ module.vpc ]

  deletion_protection = false

  node_pools = [
    {
      name                        = "tekton-node-pool"
      machine_type                = "e2-medium"
      min_count                   = 1
      max_count                   = 1   
      disk_size_gb                = 100
      disk_type                   = "pd-standard"
      initial_node_count          = 1
    },
  ]

  node_pools_oauth_scopes = {
    all = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }

  node_pools_taints = {
    all = []
  }

  node_pools_tags = {
    all = []
    tekton-node-pool = ["tekton-node-pool"]
  }
}

resource "kubernetes_namespace" "tekton" {
  metadata {
    name = "tekton-pipelines"
    
    # to handle helm bug of not creating namespace before the release
    labels = {
      "app.kubernetes.io/managed-by" = "Helm"
    }
    annotations = {
      "meta.helm.sh/release-name"      = "tekton"
      "meta.helm.sh/release-namespace" = "tekton-pipelines"
    }
  }
}

resource "kubernetes_namespace" "apps" {
  metadata {
    name = "apps-deployments"
  }
}

resource "helm_release" "tekton_pipeline" {
  name = "tekton"
  chart = "tekton-pipeline"
  repository = "https://cdfoundation.github.io/tekton-helm-chart/"
  namespace = kubernetes_namespace.tekton.metadata[0].name

  create_namespace = false

  depends_on = [ kubernetes_namespace.tekton ]
}