locals {
  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "terraform-k8s-addons"
    "platform.cluster"             = var.cluster_name
    "platform.distribution"        = var.cluster_distribution
  }
}
