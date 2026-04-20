# terraform-k8s-addons

Opinionated platform layer for a local Kubernetes cluster: **Traefik** (ingress
controller + IngressClass, optional dashboard via `IngressRoute`), **cert-manager**
(plus Let's Encrypt staging + production ClusterIssuers), **kube-prometheus-stack**
(Prometheus + Grafana + Alertmanager + exporters — services stay cluster-internal,
downstream stacks wire their own public route), PodSecurity-labeled namespaces
with default `ResourceQuota` / `LimitRange`, and a demo `ops` StatefulSet that
exercises persistent storage.

The module is **distribution-agnostic**: it consumes a `kubeconfig_path`
input and deploys everything via the `kubernetes` and `helm` providers.
Swap the cluster module underneath without touching the addons stack.

## Composition

Designed to sit on top of either of the sibling cluster modules:

```hcl
module "k8s" {
  source = "git::https://github.com/rromenskyi/terraform-k3s-k8s.git?ref=vX.Y.Z"
  # ...cluster-shape inputs...
}

module "addons" {
  source = "git::https://github.com/rromenskyi/terraform-k8s-addons.git?ref=vX.Y.Z"

  kubeconfig_path      = module.k8s.kubeconfig_path
  cluster_name         = module.k8s.cluster_name
  cluster_distribution = module.k8s.cluster_distribution
  letsencrypt_email    = "you@example.com"
  base_domain          = "localhost"

  # optional toggles (all default `true`)
  enable_traefik      = true
  enable_cert_manager = true
  enable_monitoring   = true
  enable_ops_workload = true
}
```

Any cluster module that exports `kubeconfig_path`, `cluster_name`, and
`cluster_distribution` outputs is a drop-in producer. Both
`terraform-minikube-k8s` and `terraform-k3s-k8s` satisfy that contract.

## Why a separate module

The same Helm releases and Kubernetes primitives used to live copy-pasted
inside both cluster modules. A single typo (Traefik namespace drift, a
chart-schema bump, a missing `global.` prefix) had to be patched twice, and
routinely wasn't. Lifting the addons out collapses the duplication, makes
the cluster modules truly single-responsibility (just bootstrap), and lets
the platform root stack compose cluster + addons + tenant workloads in a
clean three-layer stack.

## What this module creates

| Resource | Namespace | Controlled by |
|---|---|---|
| Traefik Helm release + IngressClass `traefik` | `ingress-controller` | `enable_traefik` |
| cert-manager Helm release | `cert-manager` | `enable_cert_manager` |
| Let's Encrypt staging + production `ClusterIssuer`s (via local Helm chart) | `cert-manager` | `enable_cert_manager` |
| kube-prometheus-stack (Prometheus + Grafana + Alertmanager + exporters) | `monitoring` | `enable_monitoring` |
| PodSecurity-labeled namespaces (`ops` by default; chart-managed ones stay unlabeled) | per `var.namespaces` | always |
| Default `ResourceQuota` + `LimitRange` on each namespace | per `var.namespaces` | `enable_namespace_limits` |
| Demo `ops` StatefulSet (hardened `restricted`-compatible security context) | `var.namespace` | `enable_ops_workload` |

### Reaching Grafana

The chart-side Grafana `Ingress` stays disabled on purpose. This module
ships no public route for Grafana — the Service
`kube-prometheus-stack-grafana` in `var.monitoring_namespace` is
cluster-internal only. Downstream stacks attach their own route (
`IngressRoute`, `Ingress`, Gateway API, whatever) at the domain of their
choice. The `grafana_credentials` output returns the admin username,
password, and Service coordinates to wire up.

Quick local access without an ingress:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# → http://localhost:3000  (admin / <password from terraform output>)
```

## Distribution-aware defaults

Two inputs default to `null` and pick their effective value from
`var.cluster_distribution`:

| Input | `cluster_distribution = "k3s"` | `cluster_distribution = "minikube"` | Why |
|---|---|---|---|
| `ops_storage_class_name` | `local-path` | `standard` | `local-path-provisioner` is the built-in StorageClass on k3s; `k8s.io/minikube-hostpath` ships under the name `standard` on minikube and is its only default. |
| `traefik_service_type` | `LoadBalancer` | `ClusterIP` | klipper-lb assigns an external IP on k3s so `helm_release`'s default `wait = true` passes; minikube has no built-in LB so a `LoadBalancer` Service sits in `EXTERNAL-IP: <pending>` until the 5-minute helm timeout. `ClusterIP` is correct when an edge tunnel (cloudflared, Tailscale funnel, ngrok) terminates traffic at the cluster service. |

Consumers who want a specific value (for example, `NodePort` on minikube
with `minikube tunnel` running out of band) set the input explicitly and
their value wins unchanged.

## Provider wiring

The module configures its own `kubernetes` and `helm` providers from
`var.kubeconfig_path`. `config_path` is opened lazily at API-call time, so
the file does not have to exist at plan — convenient when the cluster
module that produces the kubeconfig has not run yet and you want a single-
phase `terraform apply` against a cold state.

## License

MIT — see [LICENSE](LICENSE).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.17 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | 2.17.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 2.38.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.cert_manager](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.cluster_issuers](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.monitoring](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.traefik](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_limit_range_v1.namespaces](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/limit_range_v1) | resource |
| [kubernetes_namespace_v1.namespaces](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_resource_quota_v1.namespaces](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/resource_quota_v1) | resource |
| [kubernetes_stateful_set_v1.ops](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/stateful_set_v1) | resource |
| [random_password.grafana](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_base_domain"></a> [base\_domain](#input\_base\_domain) | Base domain used to derive the Traefik dashboard hostname (`traefik.<base>`) when `enable_traefik_dashboard = true`. Not used by monitoring — this module does not publish Grafana publicly. Defaults to `localhost` for local-only use; set to a real domain for remote access. | `string` | `"localhost"` | no |
| <a name="input_cert_manager_namespace"></a> [cert\_manager\_namespace](#input\_cert\_manager\_namespace) | Namespace for the cert-manager Helm release. Helm creates it with `create_namespace = true` and deletes it on release destroy. Not labeled with Pod Security Standards by this module because the webhook/cainjector need host-access permissions that `baseline` denies. | `string` | `"cert-manager"` | no |
| <a name="input_cert_manager_version"></a> [cert\_manager\_version](#input\_cert\_manager\_version) | cert-manager Helm chart version | `string` | `"v1.16.1"` | no |
| <a name="input_cluster_distribution"></a> [cluster\_distribution](#input\_cluster\_distribution) | Distribution the target cluster runs. Consumed as a label and as context for human-readable outputs. Acceptable values are free-form strings; the sibling cluster modules emit `minikube` or `k3s` via their `cluster_distribution` output. | `string` | `"unknown"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Logical name of the target cluster. Propagates into `common_labels` and pins `random_password.grafana.keepers` so provider-version upgrades do not silently rotate the Grafana admin password. Should match the cluster module's `cluster_name`. | `string` | `"tf-local"` | no |
| <a name="input_enable_cert_manager"></a> [enable\_cert\_manager](#input\_enable\_cert\_manager) | Deploy cert-manager plus Let's Encrypt staging/production `ClusterIssuer`s. Requires `enable_traefik = true` because the HTTP-01 solver template hardcodes ingress class `traefik`. | `bool` | `true` | no |
| <a name="input_enable_monitoring"></a> [enable\_monitoring](#input\_enable\_monitoring) | Deploy kube-prometheus-stack (Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics + operator). This module does NOT publish Grafana on any public hostname; its Service `kube-prometheus-stack-grafana.<monitoring_namespace>` is reachable cluster-internal, and consumers wire their own Ingress/IngressRoute at the domain of their choice. | `bool` | `true` | no |
| <a name="input_enable_namespace_limits"></a> [enable\_namespace\_limits](#input\_enable\_namespace\_limits) | Apply a default `ResourceQuota` and `LimitRange` to each module-managed namespace. Disable only if quotas are enforced out-of-band. | `bool` | `true` | no |
| <a name="input_enable_ops_workload"></a> [enable\_ops\_workload](#input\_enable\_ops\_workload) | Create a demo `ops` StatefulSet that exercises the cluster's default StorageClass. Used as a smoke test; safe to disable in production stacks. | `bool` | `true` | no |
| <a name="input_enable_traefik"></a> [enable\_traefik](#input\_enable\_traefik) | Deploy Traefik as the cluster ingress controller via Helm. Traefik lands in the `ingress-controller` namespace regardless of distribution. | `bool` | `true` | no |
| <a name="input_enable_traefik_dashboard"></a> [enable\_traefik\_dashboard](#input\_enable\_traefik\_dashboard) | Expose the Traefik dashboard via `IngressRoute` at `traefik.<base_domain>`. Requires `enable_traefik = true`. | `bool` | `true` | no |
| <a name="input_ingress_controller_namespace"></a> [ingress\_controller\_namespace](#input\_ingress\_controller\_namespace) | Namespace for the Traefik Helm release. Named after the role (not the product) so downstream stacks can address it the same way across distributions. | `string` | `"ingress-controller"` | no |
| <a name="input_kube_prometheus_stack_version"></a> [kube\_prometheus\_stack\_version](#input\_kube\_prometheus\_stack\_version) | kube-prometheus-stack Helm chart version | `string` | `"70.0.0"` | no |
| <a name="input_kubeconfig_path"></a> [kubeconfig\_path](#input\_kubeconfig\_path) | Path to the kubeconfig file for the target cluster. Typically wired from `module.<cluster>.kubeconfig_path` where <cluster> is `terraform-minikube-k8s`, `terraform-k3s-k8s`, or any other module exporting that output. The file is opened lazily at API-call time, so it may not exist yet when this module is planned — convenient for single-phase `terraform apply` against a cold cluster. | `string` | n/a | yes |
| <a name="input_letsencrypt_email"></a> [letsencrypt\_email](#input\_letsencrypt\_email) | Email registered with Let's Encrypt (required when `enable_cert_manager = true`). Must be a real mailbox — Let's Encrypt rate-limits RFC-2606 reserved domains (example.com, example.org, example.net, example.invalid, test, localhost). | `string` | `"admin@example.com"` | no |
| <a name="input_monitoring_namespace"></a> [monitoring\_namespace](#input\_monitoring\_namespace) | Namespace for the kube-prometheus-stack Helm release (Prometheus / Grafana / Alertmanager / node-exporter / kube-state-metrics / operator). The module does not publish Grafana on a public hostname — downstream stacks wire their own Ingress/IngressRoute at the `kube-prometheus-stack-grafana` Service in this namespace. | `string` | `"monitoring"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace for the demo ops StatefulSet. Must appear in `var.namespaces` or be created out-of-band — the StatefulSet depends on the namespace existing. | `string` | `"ops"` | no |
| <a name="input_namespace_pod_security_level"></a> [namespace\_pod\_security\_level](#input\_namespace\_pod\_security\_level) | Pod Security Standards level applied to module-managed namespaces (enforce + audit + warn). `baseline` is safe for most workloads. `restricted` is strictest and may break charts requiring privileged pods. `privileged` effectively disables enforcement. | `string` | `"baseline"` | no |
| <a name="input_namespaces"></a> [namespaces](#input\_namespaces) | Namespaces the module creates with PodSecurity labels, a default `ResourceQuota`, and a default `LimitRange`. Helm-managed namespaces (`cert_manager_namespace`, `ingress_controller_namespace`, `monitoring_namespace`) are NOT in this list because the charts create them — chart-managed namespaces intentionally skip our PodSecurity labels since some workloads need privileged pods (kube-prometheus-stack's node-exporter, cert-manager's webhook, …). | `list(string)` | ```[ "ops" ]``` | no |
| <a name="input_ops_image"></a> [ops\_image](#input\_ops\_image) | Container image for the ops demo workload | `string` | `"alpine:3.20"` | no |
| <a name="input_ops_storage_class_name"></a> [ops\_storage\_class\_name](#input\_ops\_storage\_class\_name) | StorageClass used by the ops StatefulSet's PVC. Leave as `null` to pick the distribution-appropriate built-in: `local-path` on k3s, `standard` on minikube, otherwise the cluster's default StorageClass. Override with any explicit StorageClass name when the operator wants a specific provisioner. | `string` | `null` | no |
| <a name="input_traefik_service_type"></a> [traefik\_service\_type](#input\_traefik\_service\_type) | Kubernetes Service type for the Traefik ingress-controller Service. Leave as `null` to pick the distribution-appropriate default: `LoadBalancer` on k3s (klipper-lb assigns the node IP, so `helm --wait` passes), `ClusterIP` on minikube (no built-in LB; External-IP would stay `<pending>` forever and block the release). Override with `NodePort` when an operator wants host-bound ports without klipper-lb or tunnel-style ingress. | `string` | `null` | no |
| <a name="input_traefik_version"></a> [traefik\_version](#input\_traefik\_version) | Traefik Helm chart version | `string` | `"34.2.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cert_manager_enabled"></a> [cert\_manager\_enabled](#output\_cert\_manager\_enabled) | Whether cert-manager is deployed |
| <a name="output_grafana_credentials"></a> [grafana\_credentials](#output\_grafana\_credentials) | Grafana admin credentials and in-cluster Service coordinates. Password is randomly generated and kept in Terraform state. Null when `enable_monitoring = false`. Consumers assemble their own public URL — this module does not publish Grafana through Traefik. |
| <a name="output_ingress_class"></a> [ingress\_class](#output\_ingress\_class) | IngressClass name (Traefik). Null when `enable_traefik = false`. |
| <a name="output_monitoring_enabled"></a> [monitoring\_enabled](#output\_monitoring\_enabled) | Whether the Prometheus + Grafana stack is deployed |
| <a name="output_namespaces"></a> [namespaces](#output\_namespaces) | Namespaces created by this module |
| <a name="output_ops_statefulset_name"></a> [ops\_statefulset\_name](#output\_ops\_statefulset\_name) | Name of the demo ops StatefulSet. Null when `enable_ops_workload = false`. |
| <a name="output_traefik_dashboard_url"></a> [traefik\_dashboard\_url](#output\_traefik\_dashboard\_url) | Traefik dashboard URL. Null when the dashboard is not exposed. |
| <a name="output_traefik_enabled"></a> [traefik\_enabled](#output\_traefik\_enabled) | Whether Traefik is deployed |
<!-- END_TF_DOCS -->
