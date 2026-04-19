locals {
  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "terraform-k8s-addons"
    "platform.cluster"             = var.cluster_name
    "platform.distribution"        = var.cluster_distribution
  }

  # Distribution-aware defaults for inputs the operator left as `null`.
  # k3s ships `local-path-provisioner` as its built-in StorageClass, and
  # klipper-lb as its built-in LoadBalancer controller; minikube ships
  # `k8s.io/minikube-hostpath` under the name `standard` and has no
  # cluster-internal LB. When the input is explicitly set by the
  # consumer, their value wins unchanged.
  distribution_storage_class_default = var.cluster_distribution == "minikube" ? "standard" : "local-path"
  distribution_traefik_service_type  = var.cluster_distribution == "minikube" ? "ClusterIP" : "LoadBalancer"

  ops_storage_class_name_effective = coalesce(var.ops_storage_class_name, local.distribution_storage_class_default)
  traefik_service_type_effective   = coalesce(var.traefik_service_type, local.distribution_traefik_service_type)
}
