# Hello World on EKS — GitOps, IaC, and Observability

A production-shaped path from source code to a running, observable, self-healing
microservice on managed Kubernetes, provisioned entirely as code.

```
 developer push
       │
       ▼
┌──────────────────┐   build → test → scan → push     ┌──────────────┐
│  GitHub Actions  │ ───────────────────────────────► │  ECR (image) │
│      (CI)        │                                   └──────────────┘
└──────────────────┘
       │ commit new image DIGEST into gitops/  (no cluster credentials)
       ▼
┌──────────────────┐   Argo CD watches git, reconciles cluster
│  Git (gitops/)   │ ◄──────────────────────────────────┐
└──────────────────┘                                     │
                                              ┌────────────────────┐
                                              │      Argo CD       │  (CD)
                                              │    in-cluster      │
                                              └─────────┬──────────┘
                                                        │ applies Helm chart + platform
   ┌───────────────────────── EKS (Terraform) ─────────▼─────────────────────┐
   │  hello-world Deployment  (HPA · PDB · NetworkPolicy · non-root)          │
   │  kube-prometheus-stack   (Prometheus · Grafana · Alertmanager)           │
   │  metrics-server · AWS Load Balancer Controller                          │
   └──────────────────────────────────────────────────────────────────────────┘
```

**The core design point:** CI and CD never overlap. GitHub Actions builds, scans,
pushes the image to ECR, and commits a digest to `gitops/`. It has **no** cluster
credentials. Argo CD is the only thing that writes to Kubernetes. That separation is
what makes "access scoped in every direction" answerable rather than hand-waved.

This was built and verified end-to-end on real AWS (EKS, `ap-south-1`): the app
served "Hello World" over a public NLB, Prometheus scraped it, Grafana rendered the
dashboard, and deleting the Deployment by hand triggered Argo CD to restore it in
~20s. It was then torn down with `terraform destroy`.

---

## Repository layout

```
├── app/                    Node.js (Express) service, tests, multi-stage Dockerfile
├── charts/hello-world/     Helm chart (Deployment, Service, HPA, PDB, NetworkPolicy,
│                           ServiceMonitor, PrometheusRule, Grafana dashboard)
├── infra/
│   ├── modules/            network · eks · ecr · argocd · github-oidc
│   └── envs/dev/           thin root module wiring the above
├── gitops/
│   ├── bootstrap/          Argo CD AppProject + app-of-apps children (sync waves)
│   └── apps/values/        per-app values (CI writes the image digest here)
├── .github/workflows/      ci-pr.yaml (checks) · ci-main.yaml (build→push→gitops)
├── monitoring/dashboards/  Grafana dashboard as code (RED metrics)
├── scripts/                set-repo.sh (fills repo/account placeholders)
└── docs/                   ARCHITECTURE · TRADEOFFS · RUNBOOK
```

## What each piece does

| Concern | Where | Notes |
|---|---|---|
| Microservice | `app/` | `/` → Hello World, `/healthz`, `/readyz`, `/metrics`. Graceful shutdown, structured logs, distroless non-root image. |
| Packaging | `charts/hello-world/` | Hardened pod spec, autoscaling, disruption budget, default-deny network policy, Prometheus integration. |
| Infrastructure | `infra/` | VPC (3 AZ), EKS (spot nodes, private subnets, IRSA, KMS, control-plane logging), ECR, the Argo CD bootstrap, and the GitHub OIDC role. |
| Continuous delivery | `gitops/` + Argo CD | App-of-apps; sync waves order platform before the app. |
| Continuous integration | `.github/workflows/` | Build, scan, push by digest, commit digest to `gitops/`. OIDC auth, no static keys. |
| Observability | kube-prometheus-stack + `monitoring/` | RED dashboard + SLO burn-rate and operational alerts. |

---

## Prerequisites

- An AWS account with permissions to create VPC/EKS/IAM/ECR. **Cost warning:** an EKS
  control plane, nodes, a NAT gateway and an NLB all bill by the hour. This is a
  provision → demo → `terraform destroy` workflow. Check the AWS Pricing Calculator
  for your own numbers.
- A GitHub repository you own (the app and gitops config live together here).
- Local tools: `terraform >= 1.9`, `aws` CLI (v2), `kubectl`, `helm`, `docker`,
  and `git`. For CI: nothing extra — GitHub-hosted runners provide it.

---

## Run it end to end

### 0. Point the repo at your GitHub repo and account

```bash
# Fills the Argo CD repoURL, runbook links, and the OIDC sub claim.
scripts/set-repo.sh <github-owner> <repo-name>
git add -A && git commit -m "chore: set repo" && git push
```

### 1. Provision base infrastructure

```bash
cd infra/envs/dev
terraform init
terraform apply \
  -var 'enable_github_oidc=true' \
  -var 'github_sub_claim=repo:<owner>/<repo>:*' \
  -var 'public_access_cidrs=["<YOUR_IP>/32"]'    # lock the API endpoint to you
```

This creates the VPC, EKS cluster (Kubernetes 1.34), managed spot node group, ECR
repository, and the GitHub OIDC role. Note the outputs — you'll need
`ecr_repository_url` and `ci_role_arn`.

```bash
aws eks update-kubeconfig --region ap-south-1 --name hello-world-dev
kubectl get nodes          # Ready nodes across 3 AZs
```

### 2. Wire CI to the account

```bash
# Pin the ECR URL (account id) into the gitops values, then push.
scripts/set-repo.sh <owner> <repo> <aws-account-id>
git add -A && git commit -m "chore: set ECR account" && git push

# Tell GitHub Actions which role to assume (from terraform output ci_role_arn).
gh variable set AWS_CI_ROLE_ARN --body "<ci_role_arn>"
```

A push to `main` now builds the image, scans it, pushes it to ECR by digest, and
commits that digest into `gitops/apps/values/hello-world-values.yaml`.

### 3. Bootstrap Argo CD (it deploys everything else)

Argo CD's root Application is a Kubernetes CRD, so the CRDs must exist before the
manifest is applied. That means a two-step apply the first time:

```bash
# Step 1: install Argo CD (creates the CRDs).
terraform apply -var 'bootstrap_argocd=true' \
  -var 'enable_github_oidc=true' \
  -var 'github_sub_claim=repo:<owner>/<repo>:*' \
  -var 'public_access_cidrs=["<YOUR_IP>/32"]' \
  -target='module.argocd[0].helm_release.argocd'

# Step 2: full apply (creates the root app-of-apps).
terraform apply -var 'bootstrap_argocd=true' \
  -var 'enable_github_oidc=true' \
  -var 'github_sub_claim=repo:<owner>/<repo>:*' \
  -var 'public_access_cidrs=["<YOUR_IP>/32"]'
```

Argo CD then syncs, in wave order:
`metrics-server` + `aws-load-balancer-controller` (wave 0) →
`kube-prometheus-stack` (wave 1) → `hello-world` (wave 2).

```bash
kubectl get applications -n argocd     # all Synced / Healthy
```

### 4. Reach it

```bash
# The app is public via an NLB:
kubectl get svc hello-world -n hello-world     # EXTERNAL-IP is the NLB hostname
curl http://<nlb-hostname>/                    # -> Hello World

# Argo CD, Grafana, Prometheus are internal (ClusterIP) — reach via port-forward:
kubectl -n argocd     port-forward svc/argocd-server 8090:80          # http://localhost:8090
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80   # http://localhost:3000
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

Credentials:
- Argo CD: user `admin`, password `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`
- Grafana: user `admin`, password `kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d` (default `prom-operator`)

In Grafana, open the **"hello-world · RED metrics"** dashboard.

### 5. Prove GitOps is real

```bash
kubectl delete deploy hello-world -n hello-world
kubectl get deploy -n hello-world -w         # Argo CD recreates it within ~20s
```

### 6. Tear down

```bash
# Delete the app's Service first so the LB controller de-provisions the NLB cleanly.
kubectl delete svc hello-world -n hello-world
terraform destroy -var 'bootstrap_argocd=true' \
  -var 'enable_github_oidc=true' \
  -var 'github_sub_claim=repo:<owner>/<repo>:*'
```

See `docs/RUNBOOK.md` → *Teardown* for the two known gotchas (Argo finalizers and
LB-controller security groups) and how to clear them if destroy stalls.

---

## Verifying without the cloud

Everything except the live EKS run is checkable locally:

```bash
# App: lint + 28 unit tests run inside the Docker build's `test` stage.
docker build --target test app/

# Chart: lint + render.
helm lint charts/hello-world
helm template hw charts/hello-world -f gitops/apps/values/hello-world-values.yaml

# Infra: format + validate (no cloud creds needed).
terraform -chdir=infra/envs/dev init -backend=false
terraform -chdir=infra/envs/dev validate
```

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — components and data flow, decision by decision.
- [`docs/TRADEOFFS.md`](docs/TRADEOFFS.md) — every shortcut taken and its production alternative.
- [`docs/RUNBOOK.md`](docs/RUNBOOK.md) — what to do when each alert fires, and teardown gotchas.

## Known limitations

Summarized here, detailed in `docs/TRADEOFFS.md`:

- **No TLS / custom domain** — the app is served over plain HTTP via an NLB. Production would add ACM + an ALB/Ingress + a real hostname.
- **Local Terraform state** — fine for a single operator; production uses S3 + DynamoDB locking.
- **Single NAT gateway, spot nodes** — cost choices; production trades money for AZ-resilient egress and on-demand capacity.
- **Single repo** — app and gitops config share one repo; path filters + `[skip ci]` prevent CI loops. Production often splits them.
- **Image scan is report-only** — the distroless base ships a few openssl CVEs with no patched base published yet; the app's own dependencies are clean. The gate re-arms with a one-line change once a fixed base exists.
- **Argo CD / Grafana served insecurely (port-forward only)** — no public exposure, no TLS, demo credentials.
