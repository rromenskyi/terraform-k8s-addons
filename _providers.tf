# The module configures its own kubernetes/helm providers from the caller-
# supplied kubeconfig path. `config_path` is opened lazily at API-call time,
# so the file does not need to exist at plan time — it is legal for the
# caller to pass a path produced by another module whose resources have not
# been created yet (e.g. a k3s installer `null_resource`). That pattern is
# how the sibling cluster modules (`terraform-minikube-k8s`,
# `terraform-k3s-k8s`) hand their kubeconfig to this module without forcing
# a two-phase apply.

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  # v3 schema: the `kubernetes` configuration is now a nested
  # attribute (`kubernetes = {}`) instead of a block (`kubernetes {}`).
  # No semantic change — same `config_path` flows through.
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}
