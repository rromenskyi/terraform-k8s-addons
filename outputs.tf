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

# Grafana's chart-side Ingress is intentionally disabled (see monitoring.tf) —
# this module publishes no public route for Grafana. Downstream consumers
# attach their own (IngressRoute, Ingress, Gateway API, kubectl port-forward,
# …) at the cluster-internal Service below and control hostname / TLS / auth
# themselves. We therefore return *endpoint coordinates*, not a URL.
output "grafana_credentials" {
  description = "Grafana admin credentials and in-cluster Service coordinates. Password is randomly generated and kept in Terraform state. Null when `enable_monitoring = false`. Consumers assemble their own public URL — this module does not publish Grafana through Traefik."
  value = var.enable_monitoring ? {
    username     = "admin"
    password     = random_password.grafana["enabled"].result
    namespace    = var.monitoring_namespace
    service_name = "kube-prometheus-stack-grafana"
    service_port = 80
    cluster_host = "kube-prometheus-stack-grafana.${var.monitoring_namespace}.svc.cluster.local"
  } : null
  sensitive = true
}

output "ops_statefulset_name" {
  description = "Name of the demo ops StatefulSet. Null when `enable_ops_workload = false`."
  value       = var.enable_ops_workload ? kubernetes_stateful_set_v1.ops["enabled"].metadata[0].name : null
}
