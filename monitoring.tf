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
  namespace        = var.monitoring_namespace
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

  # v3 helm provider: `set` is a list-of-objects attribute, not a
  # repeating block. Grouping all overrides into one list keeps the
  # diff readable on apply.
  set = [
    {
      name  = "grafana.adminPassword"
      value = random_password.grafana["enabled"].result
    },
    {
      name  = "grafana.enabled"
      value = "true"
    },
    # Grafana's chart-side Ingress stays disabled on purpose. This
    # module ships no public route for Grafana — consumers attach
    # their own (Ingress, IngressRoute, Gateway API, whatever) to the
    # ClusterIP Service
    # `kube-prometheus-stack-grafana.<monitoring_namespace>`.
    {
      name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
      value = "false"
    },
    {
      name  = "prometheus.prometheusSpec.resources.requests.cpu"
      value = "200m"
    },
    {
      name  = "prometheus.prometheusSpec.resources.requests.memory"
      value = "512Mi"
    },
  ]

  values = [
    yamlencode({
      commonLabels = local.common_labels
      # Module-side Grafana defaults — sidecar dashboards enabled
      # (kube-prometheus-stack ships its dashboard library through
      # this sidecar). Operator-supplied overrides land via
      # `var.monitoring_grafana_extra_values` and merge per
      # top-level key (override wins on conflict). Common operator
      # cases: `envFromSecret` for OIDC env injection,
      # `grafana.ini.auth.generic_oauth` for SSO config, persistence
      # block, plugin list. Module stays opinion-free on those.
      grafana = merge(
        {
          sidecar = {
            dashboards = {
              enabled = true
            }
          }
        },
        var.monitoring_grafana_extra_values,
      )
    })
  ]
}

# Grafana has no Ingress here on purpose. The chart's Service
# `kube-prometheus-stack-grafana` is reachable cluster-wide via its
# ClusterIP; consumers wire their own IngressRoute (or Ingress) at the
# domain of their choice. The sibling platform repo exposes Grafana via
# a tenant IngressRoute that cross-namespace-references this Service.
