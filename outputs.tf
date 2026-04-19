output "namespaces" {
  description = "Namespaces created by this module"
  value       = [for ns in kubernetes_namespace_v1.namespaces : ns.metadata[0].name]
}

output "ingress_class" {
  description = "IngressClass name (Traefik). Null when `enable_traefik = false`."
  value       = var.enable_traefik ? "traefik" : null
}

output "traefik_enabled" {
  description = "Whether Traefik is deployed"
  value       = var.enable_traefik
}

output "cert_manager_enabled" {
  description = "Whether cert-manager is deployed"
  value       = var.enable_cert_manager
}

output "monitoring_enabled" {
  description = "Whether the Prometheus + Grafana stack is deployed"
  value       = var.enable_monitoring
}

output "traefik_dashboard_url" {
  description = "Traefik dashboard URL. Null when the dashboard is not exposed."
  value       = var.enable_traefik && var.enable_traefik_dashboard ? "http://traefik.${var.base_domain}" : null
}

output "grafana_url" {
  description = "Grafana URL. Resolves against the Traefik ingress — add an /etc/hosts entry or real DNS to reach it by `base_domain`."
  value       = var.enable_monitoring ? "https://grafana.${var.base_domain}" : null
}

output "grafana_credentials" {
  description = "Grafana login credentials. Password is randomly generated and kept in Terraform state."
  value = var.enable_monitoring ? {
    url      = "https://grafana.${var.base_domain}"
    username = "admin"
    password = random_password.grafana["enabled"].result
  } : null
  sensitive = true
}

output "ops_statefulset_name" {
  description = "Name of the demo ops StatefulSet. Null when `create_ops_workload = false`."
  value       = var.create_ops_workload ? kubernetes_stateful_set_v1.ops["enabled"].metadata[0].name : null
}
