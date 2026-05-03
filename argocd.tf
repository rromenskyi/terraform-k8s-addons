resource "helm_release" "argocd" {
  for_each = var.enable_argocd ? toset(["enabled"]) : toset([])

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = var.argocd_namespace
  create_namespace = true

  # Chart bring-up is heavier than monitoring (operator + repo-server
  # + application-controller + dex + redis). 15 min covers cold image
  # pulls on a slow link without masking real failures.
  timeout = 900

  values = [
    yamlencode({
      commonLabels = local.common_labels

      # Public-facing URL. Drives every redirect URI Argo CD emits
      # plus the OIDC callback shape Dex registers with the upstream
      # IdP. Empty when the operator hasn't wired a route yet — the
      # chart leaves the field unset and the install still works
      # for cluster-internal use (port-forward / kubectl).
      configs = {
        cm = merge(
          var.argocd_hostname == "" ? {} : {
            url = "https://${var.argocd_hostname}"
          },
          # OIDC config block, gated on all three inputs being
          # non-empty. Argo CD's chart wraps this YAML into a
          # Secret-backed `oidc.config` field; the in-tree login
          # page renders a `Sign in with OIDC` button when this is
          # populated. requestedScopes covers the standard OIDC +
          # group/role assertion shape Zitadel emits; consumers
          # using a different IdP override scopes/claims via
          # `var.argocd_extra_values` (NOT exposed here yet —
          # follow-up if a real demand surfaces).
          (var.argocd_oidc_issuer == "" ||
            var.argocd_oidc_client_id == "" ||
            var.argocd_oidc_client_secret == "") ? {} : {
            "oidc.config" = yamlencode({
              name         = "OIDC"
              issuer       = var.argocd_oidc_issuer
              clientID     = var.argocd_oidc_client_id
              clientSecret = var.argocd_oidc_client_secret
              requestedScopes = [
                "openid",
                "profile",
                "email",
                "groups",
              ]
              requestedIDTokenClaims = {
                groups = { essential = true }
              }
            })
          }
        )

        # RBAC: any OIDC user whose token carries one of the
        # `argocd_oidc_admin_groups` claims maps to Argo CD's
        # built-in `role:admin`. Empty list collapses to a single
        # safe-defaults policy block (only the chart-generated
        # local admin keeps any access). Operators that need a
        # more granular RBAC matrix override the rendered ConfigMap
        # post-install — exposing the full RBAC DSL through TF is
        # premature.
        rbac = length(var.argocd_oidc_admin_groups) == 0 ? {} : {
          "policy.csv" = join("\n", [
            for grp in var.argocd_oidc_admin_groups :
            "g, ${grp}, role:admin"
          ])
          scopes = "[groups]"
        }
      }

      # The chart's own Ingress is intentionally off. Consumers
      # already own ingress concerns (this module drops Traefik
      # plus IngressRoute templates upstream); a chart-rendered
      # NGINX-style Ingress would conflict at the IngressClass
      # default level. Operators wire their own IngressRoute
      # against the `argocd-server.<namespace>` Service.
      server = {
        ingress = {
          enabled = false
        }
      }
    })
  ]
}
