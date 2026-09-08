# Architecture

Component-by-component design and the reasoning behind each choice. The guiding
principle throughout: **one system writes to the cluster (Argo CD), and access is
scoped deliberately at every boundary.**

## Data flow

1. A developer pushes to `main`.
2. **GitHub Actions (`ci-main`)** assumes a short-lived AWS role via OIDC, builds the
   image, scans it with Trivy, and pushes it to **ECR** tagged by commit SHA. It reads
   back the resulting **digest**.
3. The same workflow commits that digest into
   `gitops/apps/values/hello-world-values.yaml` (`[skip ci]` so it doesn't loop).
4. **Argo CD**, running in the cluster, notices the git change and reconciles: it
   renders the Helm chart with the new digest and applies it.
5. Kubernetes rolls the Deployment; the **AWS Load Balancer Controller** keeps the
   **NLB** pointed at healthy pods; **Prometheus** scrapes `/metrics`; **Grafana**
   shows the RED dashboard.

CI's authority ends at "an image in ECR and a commit in git." It never holds cluster
credentials. This is the single most important boundary in the design.

## The microservice (`app/`)

Node.js + Express, chosen for familiarity; `prom-client` for metrics.

- **Endpoints:** `/` (Hello World), `/healthz` (liveness), `/readyz` (readiness),
  `/metrics` (Prometheus).
- **Liveness vs readiness are different on purpose.** Liveness checks nothing external
  — if it depended on a database, a database blip would fail the probe on every pod at
  once and the kubelet would restart the whole fleet, turning a degraded dependency
  into an outage. Readiness is what gets flipped during shutdown.
- **Graceful shutdown drops zero requests.** On SIGTERM the app fails `/readyz` first,
  waits `DRAIN_DELAY_MS`, *then* closes the listener. Endpoint removal is eventually
  consistent across kube-proxy and the load balancer; closing the socket immediately
  is the most common cause of 5xx spikes on deploy. The chart derives
  `terminationGracePeriodSeconds` to always exceed drain + shutdown time.
- **Bounded metric cardinality.** The `route` label uses the matched Express route
  pattern, never the raw URL, so a client can't mint unbounded label values and blow
  up Prometheus. Probe/scrape traffic is excluded from the RED metrics so the SLO error
  ratio reflects real traffic.
- **Image:** multi-stage Dockerfile → distroless non-root (uid 65532), no shell or
  package manager. The `test` stage runs lint + tests inside the build, so a broken
  image is never produced.

## The Helm chart (`charts/hello-world/`)

- **Hardened pod spec:** `runAsNonRoot`, read-only root filesystem, all capabilities
  dropped, seccomp `RuntimeDefault`, no service-account token mounted (the app never
  calls the API server).
- **Stays responsive under load:** HPA (CPU target, min 2 / max 10) with a slow
  scale-down to avoid thrashing; topology spread across zones and nodes; rolling
  update with `maxUnavailable: 0` for zero-downtime deploys.
- **Survives disruption:** PodDisruptionBudget keeps ≥50% of pods during node drains
  and upgrades.
- **Least-privilege networking:** a default-deny NetworkPolicy with explicit allows —
  the app port from within the cluster, the scrape port from the monitoring namespace,
  and DNS egress. Everything else is dropped.
- **Observability ships with the app:** a ServiceMonitor (scrape config), a
  PrometheusRule (alerts), and a Grafana dashboard ConfigMap — all versioned with the
  code they describe.
- **Digest-pinned image:** the chart prefers `image.digest` over `image.tag`, so
  deploys are immutable and "what is running" is unambiguous.

## Infrastructure (`infra/`)

Composable modules with a thin per-environment root. Adding `prod` is a sibling
directory reusing the same modules with different sizing — not a rewrite.

- **`network`** — wraps the community VPC module: 3 AZs, public + private subnets, a
  single NAT gateway (cost trade-off), and the Kubernetes subnet-discovery tags the
  load balancer controller depends on.
- **`eks`** — wraps the community EKS module: managed spot node group in private
  subnets, OIDC provider for IRSA, control-plane logging to CloudWatch, and
  KMS-encrypted secrets. Also defines IRSA roles for the LB controller and cluster
  autoscaler, each scoped to exactly one service account.
- **`ecr`** — immutable tags, scan-on-push, a lifecycle policy retaining the last 20
  images.
- **`argocd`** — installs Argo CD via Helm and applies the root app-of-apps
  Application. This is the *one* piece of in-cluster software Terraform installs
  directly, because something has to install the tool that installs everything else.
- **`github-oidc`** — the GitHub OIDC provider and a role scoped by `sub` claim to this
  repository, with permission only to push to the one ECR repository. No static AWS
  keys exist anywhere.

## GitOps (`gitops/` + Argo CD)

- **App-of-apps:** a root Application watches `gitops/bootstrap`, which contains an
  `AppProject` and one child Application per platform component and the app.
- **Sync waves order dependencies:** wave 0 = metrics-server + AWS Load Balancer
  Controller; wave 1 = kube-prometheus-stack (installs the ServiceMonitor/PrometheusRule
  CRDs); wave 2 = hello-world (which needs those CRDs).
- **Multi-source app:** the hello-world Application reads the chart from
  `charts/hello-world` and its values from `gitops/apps/values/` via a `$values` ref —
  so CI only ever edits a small values file, never the chart.
- **Self-heal + prune on:** manual drift is reverted automatically. Deleting the
  Deployment by hand and watching Argo restore it is the proof this is real.

## CI (`.github/workflows/`)

- **`ci-pr`** — runs on pull requests with no cloud credentials (safe on forks): app
  lint + tests, a Docker build, `helm lint`/`template`, and `terraform fmt`/`validate`.
- **`ci-main`** — runs on push to `main`: OIDC → build → Trivy scan → push to ECR by
  digest → commit the digest to `gitops/`. Path filters and `[skip ci]` keep the
  gitops commit from retriggering the workflow.

## Observability

- **kube-prometheus-stack** provides Prometheus, Grafana, Alertmanager, node-exporter,
  and kube-state-metrics, with selectors configured to discover the app's
  ServiceMonitor and PrometheusRule across namespaces.
- **Dashboard as code:** the RED dashboard (rate, errors, latency percentiles,
  in-flight, HPA replicas, restarts) is a ConfigMap the Grafana sidecar auto-loads.
- **Alerts that catch problems before customers do:** SLO error-budget burn-rate (fast
  14.4× pages, slow 6× warns) rather than only "it's down"; p99 latency; zero ready
  replicas; crash-looping; HPA pinned at max. The stack's always-firing `Watchdog`
  alert is the dead-man's-switch that detects monitoring itself going dark.

## Security boundaries, summarized

| Direction | Control |
|---|---|
| Inbound to the app | NLB → app port only; default-deny NetworkPolicy |
| CI → AWS | GitHub OIDC, short-lived role, scoped to this repo; no static keys |
| Workloads → AWS | IRSA per controller; nodes carry no workload credentials |
| Anything → cluster | Argo CD is the sole writer; scoped AppProject |
| Pod → host | non-root, read-only rootfs, caps dropped, seccomp, no SA token |
| Nodes | private subnets, no public IPs |
| Secrets at rest | KMS-encrypted in etcd |
| API endpoint | public access locked to a specified CIDR |
