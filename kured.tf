resource "helm_release" "kured" {
  for_each = var.enable_kured ? toset(["enabled"]) : toset([])

  name             = "kured"
  repository       = "https://kubereboot.github.io/charts/"
  chart            = "kured"
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
      # `metrics` are off by default in the chart; flip them on so
      # the kube-prometheus-stack ServiceMonitor (when present)
      # picks up reboot-pending counters out of the box.
      metrics = {
        create = true
      }
    })
  ]
}
