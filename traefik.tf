# Helm installs a chart's `crds/` once and never upgrades them, so a
# chart bump alone leaves Traefik on the CRDs of the first install.
# Render them from the pinned chart version and server-side apply them
# (the chart's own upgrade guide does the same with kubectl). Note: if
# this module is called with a module-level `depends_on`, Terraform defers
# this data source to apply while the dependency has pending changes and
# the for_each below fails at plan.
data "helm_template" "traefik_crds" {
  for_each = var.enable_traefik ? toset(["enabled"]) : toset([])

  name         = "traefik"
  namespace    = var.ingress_controller_namespace
  repository   = "https://traefik.github.io/charts"
  chart        = "traefik"
  version      = var.traefik_version
  include_crds = true
  # Offline render: without a cluster Helm assumes an old Kubernetes and
  # the chart's kubeVersion constraint (>= 1.25) rejects it. The value
  # only satisfies that check; CRD content doesn't depend on it.
  kube_version = "1.30.0"
}

resource "kubectl_manifest" "traefik_crds" {
  for_each = {
    for doc in try(data.helm_template.traefik_crds["enabled"].crds, []) :
    yamldecode(doc).metadata.name => doc
  }

  yaml_body         = each.value
  server_side_apply = true
  force_conflicts   = true
}

resource "helm_release" "traefik" {
  for_each = var.enable_traefik ? toset(["enabled"]) : toset([])

  depends_on = [kubectl_manifest.traefik_crds]

  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = var.traefik_version
  # The ingress controller lives in a role-named namespace so downstream
  # stacks can address it identically regardless of distribution.
  namespace        = var.ingress_controller_namespace
  create_namespace = true

  # v3 helm provider: `set` is a list-of-objects attribute, not a
  # repeating block. Comments preserved inline against the relevant
  # entries for context.
  set = [
    {
      name  = "ports.web.port"
      value = "80"
    },
    {
      name  = "ports.websecure.port"
      value = "443"
    },
    # `ports.websecure.tls.enabled = true` is the chart-side default
    # for the `websecure` entrypoint, so we do not set it explicitly.
    # Chart 39.x added stricter values-schema validation that rejects
    # the explicit set as `Additional property tls is not allowed`
    # under `ports.websecure` despite the same path being valid in
    # 34.x. Behavior is unchanged either way — leaving TLS termination
    # on the websecure entrypoint enabled by chart default.
    # Let the Traefik chart own the `traefik` IngressClass. Creating
    # an identically-named `kubernetes_ingress_class_v1` ourselves
    # would conflict with the chart's install-time ownership check
    # ("IngressClass traefik exists and cannot be imported into the
    # current release: invalid ownership metadata; label validation
    # error: key 'app.kubernetes.io/managed-by' must equal 'Helm'").
    # Single owner per resource keeps the teardown/install behavior
    # predictable.
    {
      name  = "ingressClass.enabled"
      value = "true"
    },
    {
      name  = "ingressClass.isDefaultClass"
      value = "true"
    },
    # Allow IngressRoutes to reference Services in a different
    # namespace. The platform tenant IngressRoutes live in
    # `phost-<slug>-<env>` namespaces but may need to route at
    # pre-existing cluster services — e.g. Grafana in `monitoring`,
    # or any other platform-owned Service. Without this, Traefik
    # silently drops the route with "forbidden cross-namespace
    # service reference". Single-cluster platforms can safely enable
    # it.
    {
      name  = "providers.kubernetesCRD.allowCrossNamespace"
      value = "true"
    },
  ]

  values = [
    yamlencode(merge(
      {
        commonLabels = local.common_labels
        # Service type is distribution-aware (see
        # `local.traefik_service_type_effective`). k3s → `LoadBalancer`
        # (klipper-lb assigns the node IP so `helm_release`'s default
        # `wait = true` passes). minikube → `ClusterIP` (no built-in LB;
        # External-IP would stay `<pending>` forever and block the
        # release). Consumers can force any value via
        # `var.traefik_service_type`. Chart 41 dropped `service.type`; the
        # type now goes into `service.spec`, together with the optional
        # externalTrafficPolicy (one map, since merge() is shallow).
        service = {
          spec = merge(
            { type = local.traefik_service_type_effective },
            var.traefik_external_traffic_policy != null ? {
              externalTrafficPolicy = var.traefik_external_traffic_policy
            } : {},
          )
        }
        ingressRoute = {
          dashboard = {
            enabled     = var.enable_traefik_dashboard
            entryPoints = ["web"]
            matchRule   = "Host(`traefik.${var.base_domain}`)"
          }
        }
      },
      var.traefik_deployment_kind != null ? {
        deployment = {
          kind = var.traefik_deployment_kind
        }
      } : {},
      length(var.traefik_tolerations) > 0 ? {
        tolerations = var.traefik_tolerations
      } : {},
      length(var.traefik_node_selector) > 0 ? {
        nodeSelector = var.traefik_node_selector
      } : {},
    ))
  ]
}
