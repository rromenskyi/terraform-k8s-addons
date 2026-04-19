resource "helm_release" "traefik" {
  for_each = var.enable_traefik ? toset(["enabled"]) : toset([])

  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = var.traefik_version
  # The ingress controller lives in a role-named namespace so downstream
  # stacks can address it identically regardless of distribution.
  namespace        = var.ingress_controller_namespace
  create_namespace = true

  # Service type is distribution-aware (see `local.traefik_service_type_effective`).
  # k3s → `LoadBalancer` (klipper-lb assigns the node IP so `helm_release` 's
  # default `wait = true` passes). minikube → `ClusterIP` (no built-in LB;
  # External-IP would stay `<pending>` forever and block the release).
  # Consumers can force any value via `var.traefik_service_type`.
  set {
    name  = "service.type"
    value = local.traefik_service_type_effective
  }

  set {
    name  = "ports.web.port"
    value = "80"
  }

  set {
    name  = "ports.websecure.port"
    value = "443"
  }

  set {
    name  = "ports.websecure.tls.enabled"
    value = "true"
  }

  # Let the Traefik chart own the `traefik` IngressClass. Creating an
  # identically-named `kubernetes_ingress_class_v1` ourselves would conflict
  # with the chart's install-time ownership check ("IngressClass traefik
  # exists and cannot be imported into the current release: invalid
  # ownership metadata; label validation error: key 'app.kubernetes.io/managed-by'
  # must equal 'Helm'"). Single owner per resource keeps the teardown/install
  # behavior predictable.
  set {
    name  = "ingressClass.enabled"
    value = "true"
  }

  set {
    name  = "ingressClass.isDefaultClass"
    value = "true"
  }

  # Allow IngressRoutes to reference Services in a different namespace. The
  # platform tenant IngressRoutes live in `phost-<slug>-<env>` namespaces but
  # may need to route at pre-existing cluster services — e.g. Grafana in
  # `monitoring`, or any other platform-owned Service. Without this, Traefik
  # silently drops the route with "forbidden cross-namespace service
  # reference". Single-cluster platforms can safely enable it.
  set {
    name  = "providers.kubernetesCRD.allowCrossNamespace"
    value = "true"
  }

  values = [
    yamlencode({
      commonLabels = local.common_labels
      ingressRoute = {
        dashboard = {
          enabled     = var.enable_traefik_dashboard
          entryPoints = ["web"]
          matchRule   = "Host(`traefik.${var.base_domain}`)"
        }
      }
    })
  ]
}
