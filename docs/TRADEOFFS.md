# Trade-offs and known limitations

Every shortcut taken for this demo, why it was acceptable here, and what production
would do instead. The assignment explicitly asks for this honesty, and naming a
limitation deliberately is different from missing it.

## Infrastructure

### Local Terraform state (not S3 + DynamoDB)
- **Choice:** state lives in a local `terraform.tfstate` file.
- **Why here:** a single operator, provision → demo → destroy. Remote state's value is
  team locking and shared state, neither of which applies. A remote backend also needs
  a chicken-and-egg bootstrap (a bucket must exist before `init`), which is exactly the
  kind of over-engineering to avoid for a one-person demo.
- **Production:** S3 backend with DynamoDB state locking and versioning, bootstrapped
  once per account.

### Single NAT gateway
- **Choice:** one NAT gateway shared across all AZs.
- **Why here:** a NAT gateway per AZ roughly triples NAT cost for no demo benefit.
- **Risk:** if that AZ fails, private-subnet egress (image pulls, AWS API) stops
  cluster-wide.
- **Production:** `one_nat_gateway_per_az = true` — the module already supports it via
  the `single_nat_gateway` variable.

### Spot instances
- **Choice:** the node group runs on spot capacity.
- **Why here:** ~60–70% cheaper; interruptions are tolerable for a demo.
- **Risk:** nodes can be reclaimed with two minutes' notice.
- **Production:** on-demand or a mixed on-demand/spot strategy with capacity rebalancing.

### t3.small nodes and the pod-density ceiling
- **What happened:** t3.small allows ~11 pods per node (ENI limit). With the monitoring
  stack, Argo CD, and system pods, two nodes couldn't fit the second app replica —
  it stayed Pending. Fixed by running three nodes.
- **Production:** larger instances (more pods per node), and the **Cluster Autoscaler**
  (its IRSA role is already provisioned here) would add capacity automatically instead
  of a manual bump.

### EKS version
- **Note:** the default was originally 1.30, which AWS now marks end-of-support. Bumped
  to **1.34** (a currently supported version). Keep this current — EKS versions age out.

## Delivery and CI

### Single repository (app + gitops config together)
- **Choice:** one repo with a `gitops/` subdirectory.
- **Why here:** one link to submit; simpler to reason about.
- **Risk:** CI committing a digest back to the same repo could retrigger CI.
- **Mitigation:** workflow path filters (only `app/**`, `charts/**`, the workflow file)
  plus `[skip ci]` on the digest commit.
- **Production:** separate app and config repos, so a config commit can never trigger an
  app build.

### Image scan is report-only
- **Choice:** Trivy runs on every build but does not fail it (`exit-code: 0`).
- **Why:** the app's own dependencies scan clean (the one finding, `path-to-regexp`,
  was fixed via an npm override). The remaining HIGH/CRITICAL findings are openssl
  (`libssl3`) CVEs in the distroless Debian base, for which no patched distroless base
  is published yet — and distroless has no package manager to patch in place.
- **Production:** keep the gate hard (`exit-code: 1`); rebuild on a patched base as soon
  as one ships; use a `.trivyignore` with justifications and expiry for anything
  knowingly accepted. Re-arming the gate is a one-line change.

### OIDC trust policy
- **Note:** the trust policy scopes assumption by the `sub` claim (this repo) and relies
  on the OIDC provider's `client_id_list` to enforce the audience, rather than a
  duplicate `aud` condition in the policy. Empirically, adding the `aud` StringEquals
  alongside the `sub` condition caused `AssumeRoleWithWebIdentity` to be denied with the
  action version used. The effective security boundary — "only this repo can assume the
  role" — is intact.

## Networking and access

### No TLS, no custom domain
- **Choice:** the app is served over plain HTTP via an NLB hostname.
- **Why here:** no domain was assumed for the demo.
- **Production:** an ALB Ingress + ACM certificate + a real hostname (external-dns), or
  TLS terminated at the app.

### Argo CD and Grafana are not exposed
- **Choice:** both are ClusterIP, reached via `kubectl port-forward`, with demo
  credentials.
- **Why here:** exposing dashboards publicly without TLS and hardened auth would be a
  security regression.
- **Production:** private ingress behind SSO/OIDC, TLS, and rotated secrets.

### Public API endpoint locked to one CIDR
- **Choice:** the EKS API is public but restricted to a specified CIDR (the operator's
  IP), with the private endpoint also enabled.
- **Production:** disable public access entirely; reach the API over a bastion or VPN.

## Observability

### Prometheus is not highly available and retention is short
- **Choice:** single Prometheus replica, 6h retention, no long-term storage.
- **Why here:** enough to demonstrate scraping, dashboards, and alerts cheaply.
- **Production:** HA Prometheus (or Thanos/Mimir) with remote-write to durable storage
  and multi-week retention.

### Alertmanager routes nowhere real
- **Choice:** alerts fire but aren't delivered to Slack/PagerDuty.
- **Production:** wire Alertmanager receivers and test the delivery path, not just the
  rule.

## Scope decisions

- **Cluster Autoscaler authored but not deployed.** Its IRSA role exists; deploying the
  controller is a one-file addition to `gitops/bootstrap/apps/`. It was left out to keep
  the demo footprint predictable.
- **`dev` environment only.** The module structure supports adding `prod` as a sibling
  root; it was out of scope to actually stand one up.
