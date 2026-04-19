# terraform-k8s-addons Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- `var.namespaces` default no longer contains `"monitoring"`. The value contradicted the variable's own documentation ("Helm-managed namespaces (`ingress-controller`, `cert-manager`, `monitoring`) are NOT in this list because the charts create them") and made this module race `helm_release.monitoring`'s `create_namespace = true` — our `kubernetes_namespace_v1` won the race, stamped `pod-security.kubernetes.io/enforce: baseline` on the namespace, and `kube-prometheus-stack-prometheus-node-exporter` then failed admission (`hostNetwork`, `hostPID`, hostPath volumes, `hostPort: 9100` require `privileged`). The DaemonSet pod was never created, so `helm --wait` blocked until its 15-minute timeout and flipped the release to `failed`. New default: `["ops"]`. Operators who relied on the old default and want the `monitoring` namespace PSS-labeled should set `namespace_pod_security_level = "privileged"` for that namespace — but the chart already creates the namespace itself, so the clean path is to leave it chart-managed.

## [0.1.0] - 2026-04-18

Initial release. Extracted from `terraform-minikube-k8s` v2.1.x and `terraform-k3s-k8s` v0.2.x so the platform layer (Traefik / cert-manager / kube-prometheus-stack / namespaces / demo ops workload) can be consumed uniformly on top of any cluster module that exports a `kubeconfig_path`.

### Added
- Traefik `helm_release` (chart-managed `ingress-controller` namespace) + `IngressClass` `traefik`, optional dashboard via `IngressRoute`
- cert-manager `helm_release` with `commonLabels` under `global.` (v1.14+ schema-compatible) + local `cert-manager-cluster-issuers` Helm chart for Let's Encrypt staging + production `ClusterIssuer`s
- kube-prometheus-stack `helm_release` (Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics) with `random_password.grafana` keyed on `cluster_name` so provider bumps do not rotate the admin password
- `kubernetes_ingress_v1.grafana` exposing `grafana.<base_domain>` through Traefik with `websecure` + TLS router annotations
- PodSecurity-labeled namespaces (`enforce` + `audit` + `warn`) with optional default `ResourceQuota` + `LimitRange`
- Demo `ops` `StatefulSet` with `runAsNonRoot`, `readOnlyRootFilesystem`, all Linux capabilities dropped, `RuntimeDefault` seccomp, bounded resources — compatible with `restricted` PodSecurity
- `kubeconfig_path`-based provider wiring that is safe for single-phase apply against a cold cluster
- MIT LICENSE, README, CHANGELOG
