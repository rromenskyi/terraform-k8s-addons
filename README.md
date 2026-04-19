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
