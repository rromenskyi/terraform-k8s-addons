# User-declared namespaces with Pod Security Standards labels, a default
# `ResourceQuota`, and a default `LimitRange`. Helm-managed namespaces
# (`ingress-controller`, `cert-manager`, `monitoring`) are created by the
# charts themselves and intentionally skip these labels — some of those
# workloads need privileged pods (kube-prometheus-stack's node-exporter,
# cert-manager's webhook).

resource "kubernetes_namespace_v1" "namespaces" {
  for_each = toset(var.namespaces)

  metadata {
    name = each.key
    labels = merge(local.common_labels, {
      "pod-security.kubernetes.io/enforce" = var.namespace_pod_security_level
      "pod-security.kubernetes.io/audit"   = var.namespace_pod_security_level
      "pod-security.kubernetes.io/warn"    = var.namespace_pod_security_level
    })
  }
}

resource "kubernetes_resource_quota_v1" "namespaces" {
  for_each   = var.enable_namespace_limits ? toset(var.namespaces) : toset([])
  depends_on = [kubernetes_namespace_v1.namespaces]

  metadata {
    name      = "default-quota"
    namespace = each.key
    labels    = local.common_labels
  }

  spec {
    hard = {
      "requests.cpu"    = "4"
      "requests.memory" = "8Gi"
      "limits.cpu"      = "8"
      "limits.memory"   = "16Gi"
      "pods"            = "50"
    }
  }
}

resource "kubernetes_limit_range_v1" "namespaces" {
  for_each   = var.enable_namespace_limits ? toset(var.namespaces) : toset([])
  depends_on = [kubernetes_namespace_v1.namespaces]

  metadata {
    name      = "default-limits"
    namespace = each.key
    labels    = local.common_labels
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}
