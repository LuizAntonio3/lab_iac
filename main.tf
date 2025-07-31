data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.ca_certificate)
  }
}

module "gke" {
  source                     = "terraform-google-modules/kubernetes-engine/google"
  project_id                 = var.project_id
  name                       = local.cluster_name
  region                     = local.cluster_region
  network                    = "vpc-01"
  subnetwork                 = "us-central1-01"
  ip_range_pods              = "us-central1-01-gke-01-pods"
  ip_range_services          = "us-central1-01-gke-01-services"
  http_load_balancing        = false
  network_policy             = false
  horizontal_pod_autoscaling = true
  filestore_csi_driver       = false
  dns_cache                  = false

  node_pools = [
    {
      name                        = "tekton-node-pool"
      machine_type                = "e2-medium"
      min_count                   = 1
      max_count                   = 10      
      disk_size_gb                = 100
      disk_type                   = "pd-standard"
      initial_node_count          = 5
    },
    {
      name                        = "apps-node-pool"
      machine_type                = "e2-medium"
      min_count                   = 1
      max_count                   = 10      
      disk_size_gb                = 50
      disk_type                   = "pd-standard"
      initial_node_count          = 5
    }
  ]

  node_pools_oauth_scopes = {
    all = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }

  node_pools_taints = {
    all = []

    tekton-node-pool = [
      {
        key    = "tekton-node-pool"
        value  = true
        effect = "PREFER_NO_SCHEDULE"
      },
    ]
  }

  node_pools_tags = {
    all = []
    tekton-node-pool = ["tekton-node-pool"]
    app-node-pool = ["app-node-pool"]
  }
}

resource "kubernetes_namespace" "tekton" {
  metadata {
    name = "tekton-pipelines"
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
  repository = "https://github.com/cdfoundation/tekton-helm-chart"
  namespace = kubernetes_namespace.tekton.metadata[0].name

  set {
    name = "controller.tolerations[0].key"
    value = "tekton-node-pool"
  }

  set {
    name = "controller.tolerations[0].value"
    value = "true"
  }

  set {
    name = "controller.tolerations[0].effect"
    value = "PREFER_NO_SCHEDULE"
  }
}