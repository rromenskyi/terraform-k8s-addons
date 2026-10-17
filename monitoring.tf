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

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  # Helm keeps one Secret per revision; each holds the full rendered
  # manifest, so unbounded history slowly fills etcd.
  max_history      = 3
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
      value = var.monitoring_prometheus_memory_request
    },
  ]

  values = [
    yamlencode({
      commonLabels = local.common_labels
      # Helm never upgrades the CRDs in the chart's `crds/`; this
      # pre-upgrade hook Job server-side applies the CRDs of the chart
      # version being installed, so a chart bump brings its CRDs along.
      crds = {
        upgradeJob = {
          enabled = true
        }
      }
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
      # Operator-supplied Alertmanager overrides (no module-side
      # defaults). Helm deep-merges this over the chart's `alertmanager:`
      # block, so an empty map is a no-op. Typical use: pin
      # `alertmanagerSpec.externalUrl` so notification links resolve to a
      # browser-reachable host instead of the in-cluster Service name.
      alertmanager = var.monitoring_alertmanager_extra_values
      # Operator-supplied Prometheus overrides. Helm deep-merges over the
      # chart's `prometheus:` block (the `prometheusSpec.resources` requests
      # set above stay applied), so an empty map is a no-op. Typical use: pin
      # `prometheusSpec.externalUrl` so an alert's Source/generator link
      # resolves to a browser-reachable host instead of the Service name.
      prometheus = var.monitoring_prometheus_extra_values
    }),
    # k3s runs the controller-manager, scheduler, proxy and etcd inside the
    # single k3s process with metrics bound to localhost, so the chart's
    # scrape targets never come up and their `*Down` alerts fire forever.
    # Turning the components off drops both the ServiceMonitors and the
    # matching alert rules.
    #
    # The same single process serves one metrics registry on both the
    # kubelet's `/metrics` and the apiserver's `/metrics`, so on a k3s server
    # every apiserver/etcd/scheduler series was stored twice. The kubelet job
    # drops the control-plane families; the apiserver job keeps them.
    var.cluster_distribution == "k3s" ? yamlencode({
      kubeControllerManager = { enabled = false }
      kubeScheduler         = { enabled = false }
      kubeProxy             = { enabled = false }
      kubeEtcd              = { enabled = false }
      kubelet = {
        serviceMonitor = {
          # Helm replaces lists, so the chart's own default comes along.
          metricRelabelings = concat(local.kubelet_chart_metric_relabelings, [{
            sourceLabels = ["__name__"]
            regex        = local.k3s_control_plane_metrics_regex
            action       = "drop"
          }])
        }
      }
    }) : "{}",
    length(var.monitoring_apiserver_drop_metrics) > 0 ? yamlencode({
      kubeApiServer = {
        serviceMonitor = {
          # Helm replaces lists, so the chart's own default comes along.
          metricRelabelings = concat(local.apiserver_chart_metric_relabelings, [{
            sourceLabels = ["__name__"]
            regex        = "(${join("|", var.monitoring_apiserver_drop_metrics)})"
            action       = "drop"
          }])
        }
      }
    }) : "{}",
    length(local.monitoring_guard_rule_groups) > 0 ? yamlencode({
      additionalPrometheusRulesMap = {
        "monitoring-guards" = { groups = local.monitoring_guard_rule_groups }
      }
    }) : "{}",
  ]
}

locals {
  # kube-prometheus-stack's default `kubelet.serviceMonitor.metricRelabelings`
  # (chart 91.8.2). Keep in step with the chart when bumping it.
  kubelet_chart_metric_relabelings = [{
    sourceLabels = ["__name__", "le"]
    regex        = "(csi_operations|storage_operation_duration)_seconds_bucket;(0.25|2.5|15|25|120|600)(\\.0)?"
    action       = "drop"
  }]

  # kube-prometheus-stack's default `kubeApiServer.serviceMonitor.metricRelabelings`
  # (chart 91.8.2). Keep in step with the chart when bumping it.
  apiserver_chart_metric_relabelings = [{
    sourceLabels = ["__name__", "le"]
    regex        = "(etcd_request|apiserver_request_slo|apiserver_request_sli|apiserver_request)_duration_seconds_bucket;(0\\.15|0\\.2|0\\.3|0\\.35|0\\.4|0\\.45|0\\.6|0\\.7|0\\.8|0\\.9|1\\.25|1\\.5|1\\.75|2|3|3\\.5|4|4\\.5|6|7|8|9|15|20|40|45|50)(\\.0)?"
    action       = "drop"
  }]

  # Metric families of the k3s control plane that a k3s server's kubelet
  # endpoint serves on top of the kubelet's own: the families a server's
  # kubelet exposes and an agent's does not (measured on k3s v1.37). The
  # `KubeletMetricsIncludeControlPlane` alert below catches a family a later
  # version adds.
  k3s_control_plane_metrics_regex = "(apiserver|etcd|scheduler|apiextensions|aggregator|authorization|authentication|authenticated|watch_cache|field_validation|lasso|grpc|kube_apiserver|serviceaccount|pod_security|node_authorizer|version)_.*"

  monitoring_guard_rule_groups = concat(
    var.cluster_distribution == "k3s" ? [{
      name = "k3s-kubelet-metrics"
      rules = [{
        alert = "KubeletMetricsIncludeControlPlane"
        expr  = "max by (node) (scrape_samples_post_metric_relabeling{job=\"kubelet\",metrics_path=\"/metrics\"}) > ${var.monitoring_kubelet_samples_alert_threshold}"
        for   = "30m"
        labels = {
          severity = "warning"
        }
        annotations = {
          summary     = "The kubelet on {{ $labels.node }} returns {{ $value }} samples per scrape"
          description = "A kubelet's own metrics are a few thousand samples. On k3s the kubelet endpoint also serves the control plane's metrics, and this module drops their families from the kubelet job (they are stored once, from the apiserver). More samples than this means a new control-plane family leaks in and is stored twice: extend `k3s_control_plane_metrics_regex` in terraform-k8s-addons."
        }
      }]
    }] : [],
    var.monitoring_head_series_budget > 0 ? [{
      name = "prometheus-series-budget"
      rules = [{
        alert = "PrometheusHeadSeriesOverBudget"
        expr  = "max by (pod) (prometheus_tsdb_head_series) > ${var.monitoring_head_series_budget}"
        for   = "1h"
        labels = {
          severity = "warning"
        }
        annotations = {
          summary     = "Prometheus {{ $labels.pod }} holds {{ $value }} series, over the budget of ${var.monitoring_head_series_budget}"
          description = "Prometheus memory grows with the number of series. Find what grew (Prometheus UI, Status → TSDB status, or count by (__name__) over the last day) and drop it at the scrape, or raise the budget."
        }
      }]
    }] : [],
  )
}

# Grafana has no Ingress here on purpose. The chart's Service
# `kube-prometheus-stack-grafana` is reachable cluster-wide via its
# ClusterIP; consumers wire their own IngressRoute (or Ingress) at the
# domain of their choice. The sibling platform repo exposes Grafana via
# a tenant IngressRoute that cross-namespace-references this Service.
