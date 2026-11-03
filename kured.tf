resource "helm_release" "kured" {
  for_each = var.enable_kured ? toset(["enabled"]) : toset([])

  name       = "kured"
  repository = "https://kubereboot.github.io/charts/"
  chart      = "kured"
  # Helm keeps one Secret per revision; each holds the full rendered
  # manifest, so unbounded history slowly fills etcd.
  max_history      = 3
  version          = var.kured_version
  namespace        = var.kured_namespace
  create_namespace = false # Default `kube-system` always exists; override at your own risk.

  # Maintenance-window knobs go through `set` (single values
  # native-typed) and `values` (the `configuration` map below) so
  # operators get the time-of-day / day-of-week / timezone gating
  # without editing this module.
  set = [
    {
      name  = "configuration.timeZone"
      value = var.kured_time_zone
    },
    {
      name  = "configuration.startTime"
      value = var.kured_start_time
    },
    {
      name  = "configuration.endTime"
      value = var.kured_end_time
    },
    {
      name  = "configuration.rebootDays"
      value = "{${join(",", var.kured_reboot_days)}}"
    },
  ]

  values = [
    yamlencode({
      commonLabels = local.common_labels
      # Reboots wait while one of `kured_blocking_alerts` is pending or
      # firing: kured asks Prometheus for active alerts and, with match-only,
      # blocks only on the names in the regexp (everything else is ignored).
      # Pending counts too (alertFiringOnly stays false): right after a node
      # comes back, a resync alert is still inside its `for:` window.
      configuration = local.kured_block_on_alerts ? {
        prometheusUrl        = var.kured_prometheus_url
        alertFilterRegexp    = "^(${join("|", var.kured_blocking_alerts)})$"
        alertFilterMatchOnly = true
      } : {}
      # `metrics` are off by default in the chart; flip them on so
      # the kube-prometheus-stack ServiceMonitor (when present)
      # picks up reboot-pending counters out of the box.
      metrics = {
        create = true
      }
      # Null optional attributes stripped so the chart doesn't render
      # `value: null` / `operator: null` into the pod spec.
      tolerations = [
        for t in var.kured_tolerations : { for k, v in t : k => v if v != null }
      ]
    })
  ]
}

locals {
  kured_block_on_alerts = var.kured_prometheus_url != "" && length(var.kured_blocking_alerts) > 0
}
