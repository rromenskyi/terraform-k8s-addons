resource "random_password" "grafana" {
  for_each = var.enable_monitoring ? toset(["enabled"]) : toset([])

  length  = 16
  special = false

  # Pin regeneration to the cluster identity so provider-version bumps do
  # not silently rotate the admin password and lock users out of Grafana.
  keepers = {
    cluster = var.cluster_name
  }
}

resource "helm_release" "monitoring" {
  for_each = var.enable_monitoring ? toset(["enabled"]) : toset([])

  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kube_prometheus_stack_version
  namespace        = "monitoring"
  create_namespace = true

  # kube-prometheus-stack pulls ~10 container images (prometheus, grafana,
  # alertmanager, node-exporter, kube-state-metrics, prometheus-operator,
  # CRD init jobs). On a cold host over a slow or rate-limited connection,
  # the default 5-minute Helm `--wait` timeout trips before the last pod
  # reaches Ready and the release is flagged `failed` even though everything
  # is still converging. Bumping to 15 minutes is generous enough for
  # worst-case bring-up (Docker Hub TLS handshake timeouts, quay.io
  # throttling) without masking genuine failures.
  timeout = 900

  set {
    name  = "grafana.adminPassword"
    value = random_password.grafana["enabled"].result
  }

  set {
    name  = "grafana.enabled"
    value = "true"
  }

  # Grafana's chart-side Ingress is left disabled on purpose. The Ingress
  # exposing `grafana.<base_domain>` is managed below as
  # `kubernetes_ingress_v1.grafana`, which carries the Traefik-specific
  # router annotations the chart would not.

  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.requests.cpu"
    value = "200m"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "512Mi"
  }

  values = [
    yamlencode({
      commonLabels = local.common_labels
      grafana = {
        sidecar = {
          dashboards = {
            enabled = true
          }
        }
      }
    })
  ]
}

resource "kubernetes_ingress_v1" "grafana" {
  for_each   = var.enable_monitoring ? toset(["enabled"]) : toset([])
  depends_on = [helm_release.monitoring]

  metadata {
    name      = "grafana"
    namespace = "monitoring"
    labels    = local.common_labels
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
    }
  }

  spec {
    ingress_class_name = "traefik"
    rule {
      host = "grafana.${var.base_domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "kube-prometheus-stack-grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
