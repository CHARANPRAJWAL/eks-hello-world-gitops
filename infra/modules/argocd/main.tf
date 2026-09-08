# -----------------------------------------------------------------------------
# Argo CD bootstrap.
#
# This is the ONE piece of in-cluster software Terraform installs directly.
# Rationale: something has to install the tool that installs everything else,
# and Argo CD cannot install itself. Terraform's responsibility ends here — at
# "the cluster exists and Argo CD is running". Everything after this (the app,
# Prometheus/Grafana, platform controllers) is declared in gitops/ and applied
# by Argo CD, never by Terraform.
#
# The root Application below is the app-of-apps entrypoint: it points Argo at
# gitops/bootstrap, which in turn defines every child Application.
# -----------------------------------------------------------------------------

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  # Wait for the CRDs and server to be ready before Terraform applies the root
  # Application, otherwise the Application kind may not exist yet.
  wait    = true
  timeout = 600

  values = [yamlencode({
    global = {
      # Keep the footprint small for a dev cluster.
    }
    configs = {
      params = {
        # No TLS/domain in this demo; the server runs insecure behind a
        # port-forward. Documented limitation. Production terminates TLS at an
        # ingress with a real cert.
        "server.insecure" = true
      }
    }
    # Single replica of each component: this is dev. Production runs the
    # application-controller and repo-server with multiple replicas.
    controller = { replicas = 1 }
    repoServer = { replicas = 1 }
    server     = { replicas = 1 }
    redis      = {}
  })]
}

# Root app-of-apps Application. Committed as a raw manifest rather than Helm so
# the bootstrap has no chart of its own to maintain. It watches gitops/bootstrap
# in the repo and creates every child Application found there.
resource "kubernetes_manifest" "root_app" {
  depends_on = [helm_release.argocd]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = "argocd"
      # The finalizer makes deleting this Application cascade-delete its
      # children, so `terraform destroy` leaves nothing orphaned.
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_target_revision
        path           = "gitops/bootstrap"
        # Recurse so the child Applications under bootstrap/apps/ are picked up,
        # not just project.yaml at the top of the path.
        directory = {
          recurse = true
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }
}
