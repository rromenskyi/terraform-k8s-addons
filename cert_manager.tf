resource "helm_release" "cert_manager" {
  for_each = var.enable_cert_manager ? toset(["enabled"]) : toset([])

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_version
  namespace        = var.cert_manager_namespace
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  values = [
    # cert-manager's values.schema.json (v1.14+) keeps `commonLabels` under
    # `global.`, not at the root. Passing it at the root is rejected with
    # "Additional property commonLabels is not allowed" and the release
    # fails to plan. The local `cluster_issuers` chart below is our own —
    # its schema stays flat.
    yamlencode({
      global = {
        commonLabels = local.common_labels
      }
    })
  ]
}

# Let's Encrypt ClusterIssuers are delivered via a small local Helm chart so
# the Helm provider can plan the release before the Kubernetes API is reachable.
resource "helm_release" "cluster_issuers" {
  for_each   = var.enable_cert_manager ? toset(["enabled"]) : toset([])
  depends_on = [helm_release.cert_manager]

  name             = "cert-manager-cluster-issuers"
  chart            = "${path.module}/charts/cert-manager-cluster-issuers"
  namespace        = var.cert_manager_namespace
  create_namespace = true

  values = [
    yamlencode({
      commonLabels      = local.common_labels
      letsencrypt_email = var.letsencrypt_email
    })
  ]

  lifecycle {
    precondition {
      condition     = var.enable_traefik
      error_message = "Let's Encrypt ClusterIssuers require Traefik — the HTTP-01 solver template hardcodes ingress class 'traefik'. Set enable_traefik = true or disable cert-manager."
    }
  }
}
