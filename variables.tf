# --------------------------------------------------------------------------
# Required inputs
# --------------------------------------------------------------------------

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file for the target cluster. Typically wired from `module.<cluster>.kubeconfig_path` where <cluster> is `terraform-minikube-k8s`, `terraform-k3s-k8s`, or any other module exporting that output. The file is opened lazily at API-call time, so it may not exist yet when this module is planned — convenient for single-phase `terraform apply` against a cold cluster."
  type        = string
}

variable "cluster_name" {
  description = "Logical name of the target cluster. Propagates into `common_labels` and pins `random_password.grafana.keepers` so provider-version upgrades do not silently rotate the Grafana admin password. Should match the cluster module's `cluster_name`."
  type        = string
  default     = "tf-local"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.cluster_name))
    error_message = "cluster_name must be lowercase alphanumeric with hyphens, max 63 characters."
  }
}

# --------------------------------------------------------------------------
# Cluster distribution hint (labels + storage class defaults)
# --------------------------------------------------------------------------

variable "cluster_distribution" {
  description = "Distribution the target cluster runs. Consumed as a label and as context for human-readable outputs. Acceptable values are free-form strings; the sibling cluster modules emit `minikube` or `k3s` via their `cluster_distribution` output."
  type        = string
  default     = "unknown"
}

# --------------------------------------------------------------------------
# Namespaces
# --------------------------------------------------------------------------

variable "cert_manager_namespace" {
  description = "Namespace for the cert-manager Helm release. Helm creates it with `create_namespace = true` and deletes it on release destroy. Not labeled with Pod Security Standards by this module because the webhook/cainjector need host-access permissions that `baseline` denies."
  type        = string
  default     = "cert-manager"
}

variable "ingress_controller_namespace" {
  description = "Namespace for the Traefik Helm release. Named after the role (not the product) so downstream stacks can address it the same way across distributions."
  type        = string
  default     = "ingress-controller"
}

variable "monitoring_namespace" {
  description = "Namespace for the kube-prometheus-stack Helm release (Prometheus / Grafana / Alertmanager / node-exporter / kube-state-metrics / operator). The module does not publish Grafana on a public hostname — downstream stacks wire their own Ingress/IngressRoute at the `kube-prometheus-stack-grafana` Service in this namespace."
  type        = string
  default     = "monitoring"
}

variable "namespaces" {
  description = "Namespaces the module creates with PodSecurity labels, a default `ResourceQuota`, and a default `LimitRange`. Helm-managed namespaces (`cert_manager_namespace`, `ingress_controller_namespace`, `monitoring_namespace`) are NOT in this list because the charts create them — chart-managed namespaces intentionally skip our PodSecurity labels since some workloads need privileged pods (kube-prometheus-stack's node-exporter, cert-manager's webhook, …)."
  type        = list(string)
  default     = ["ops"]
}

variable "namespace_pod_security_level" {
  description = "Pod Security Standards level applied to module-managed namespaces (enforce + audit + warn). `baseline` is safe for most workloads. `restricted` is strictest and may break charts requiring privileged pods. `privileged` effectively disables enforcement."
  type        = string
  default     = "baseline"

  validation {
    condition     = contains(["privileged", "baseline", "restricted"], var.namespace_pod_security_level)
    error_message = "namespace_pod_security_level must be one of: privileged, baseline, restricted."
  }
}

variable "enable_namespace_limits" {
  description = "Apply a default `ResourceQuota` and `LimitRange` to each module-managed namespace. Disable only if quotas are enforced out-of-band."
  type        = bool
  default     = true
}

# --------------------------------------------------------------------------
# DNS
# --------------------------------------------------------------------------

variable "base_domain" {
  description = "Base domain used to derive the Traefik dashboard hostname (`traefik.<base>`) when `enable_traefik_dashboard = true`. Not used by monitoring — this module does not publish Grafana publicly. Defaults to `localhost` for local-only use; set to a real domain for remote access."
  type        = string
  default     = "localhost"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.base_domain))
    error_message = "base_domain must be a valid DNS label sequence (lowercase alphanumerics, dots, hyphens)."
  }
}

# --------------------------------------------------------------------------
# Traefik
# --------------------------------------------------------------------------

variable "enable_traefik" {
  description = "Deploy Traefik as the cluster ingress controller via Helm. Traefik lands in the `ingress-controller` namespace regardless of distribution."
  type        = bool
  default     = true
}

variable "enable_traefik_dashboard" {
  description = "Expose the Traefik dashboard via `IngressRoute` at `traefik.<base_domain>`. Requires `enable_traefik = true`."
  type        = bool
  default     = true
}

variable "traefik_version" {
  description = "Traefik Helm chart version"
  type        = string
  default     = "34.2.0"
}

# --------------------------------------------------------------------------
# cert-manager
# --------------------------------------------------------------------------

variable "enable_cert_manager" {
  description = "Deploy cert-manager plus Let's Encrypt staging/production `ClusterIssuer`s. Requires `enable_traefik = true` because the HTTP-01 solver template hardcodes ingress class `traefik`."
  type        = bool
  default     = true
}

variable "cert_manager_version" {
  description = "cert-manager Helm chart version"
  type        = string
  default     = "v1.16.1"
}

variable "letsencrypt_email" {
  description = "Email registered with Let's Encrypt (required when `enable_cert_manager = true`). Must be a real mailbox — Let's Encrypt rate-limits RFC-2606 reserved domains (example.com, example.org, example.net, example.invalid, test, localhost)."
  type        = string
  default     = "admin@example.com"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.letsencrypt_email))
    error_message = "letsencrypt_email must be a valid email address."
  }

  validation {
    condition     = !can(regex("@(example\\.(com|org|net|invalid)|test|localhost)$", var.letsencrypt_email))
    error_message = "letsencrypt_email must not use an RFC-2606 reserved domain — Let's Encrypt rejects those."
  }
}

# --------------------------------------------------------------------------
# Monitoring
# --------------------------------------------------------------------------

variable "enable_monitoring" {
  description = "Deploy kube-prometheus-stack (Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics + operator). This module does NOT publish Grafana on any public hostname; its Service `kube-prometheus-stack-grafana.<monitoring_namespace>` is reachable cluster-internal, and consumers wire their own Ingress/IngressRoute at the domain of their choice."
  type        = bool
  default     = true
}

variable "kube_prometheus_stack_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
  default     = "70.0.0"
}

# --------------------------------------------------------------------------
# Demo ops workload
# --------------------------------------------------------------------------

variable "enable_ops_workload" {
  description = "Create a demo `ops` StatefulSet that exercises the cluster's default StorageClass. Used as a smoke test; safe to disable in production stacks."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace for the demo ops StatefulSet. Must appear in `var.namespaces` or be created out-of-band — the StatefulSet depends on the namespace existing."
  type        = string
  default     = "ops"
}

variable "ops_image" {
  description = "Container image for the ops demo workload"
  type        = string
  default     = "alpine:3.20"
}

variable "ops_storage_class_name" {
  description = "StorageClass used by the ops StatefulSet's PVC. Leave as `null` to pick the distribution-appropriate built-in: `local-path` on k3s, `standard` on minikube, otherwise the cluster's default StorageClass. Override with any explicit StorageClass name when the operator wants a specific provisioner."
  type        = string
  default     = null
}

variable "traefik_service_type" {
  description = "Kubernetes Service type for the Traefik ingress-controller Service. Leave as `null` to pick the distribution-appropriate default: `LoadBalancer` on k3s (klipper-lb assigns the node IP, so `helm --wait` passes), `ClusterIP` on minikube (no built-in LB; External-IP would stay `<pending>` forever and block the release). Override with `NodePort` when an operator wants host-bound ports without klipper-lb or tunnel-style ingress."
  type        = string
  default     = null

  validation {
    condition     = var.traefik_service_type == null || contains(["LoadBalancer", "ClusterIP", "NodePort"], coalesce(var.traefik_service_type, ""))
    error_message = "traefik_service_type must be one of LoadBalancer / ClusterIP / NodePort, or null to auto-pick by cluster_distribution."
  }
}
