# Optional demo StatefulSet that exercises persistent storage via the
# cluster's default StorageClass. The pod runs non-root with a read-only
# root filesystem, all Linux capabilities dropped, and bounded resources —
# compatible with a `restricted` PodSecurity level, not just `baseline`.

resource "kubernetes_stateful_set_v1" "ops" {
  for_each = var.enable_ops_workload ? toset(["enabled"]) : toset([])
  # Ensure the target namespace exists before the StatefulSet is created.
  # Without this, `var.namespace` defaulting to `ops` would race the
  # namespace creation and the pod might land in a namespace Terraform
  # later tries to create (or drop into `default`).
  depends_on = [kubernetes_namespace_v1.namespaces]

  metadata {
    name      = "ops"
    namespace = var.namespace
    labels    = merge(local.common_labels, { app = "ops" })
  }

  spec {
    service_name = "ops"
    replicas     = 1

    selector {
      match_labels = { app = "ops" }
    }

    template {
      metadata {
        labels = merge(local.common_labels, { app = "ops" })
      }

      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name    = "ops"
          image   = var.ops_image
          command = ["sh", "-c", "tail -f /dev/null"]

          security_context {
            allow_privilege_escalation = false
            privileged                 = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 1000

            capabilities {
              drop = ["ALL"]
            }
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        termination_grace_period_seconds = 10
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = local.ops_storage_class_name_effective
        resources {
          requests = {
            storage = "1Gi"
          }
        }
      }
    }
  }
}
