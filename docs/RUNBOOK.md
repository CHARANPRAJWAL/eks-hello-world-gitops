# Runbook

What to do when each alert fires, plus operational procedures. Alert names match the
`PrometheusRule` in `charts/hello-world/templates/prometheusrule.yaml`; the
`runbook_url` on each alert links back to the matching section here.

## Conventions

- App namespace: `hello-world`. Monitoring: `monitoring`. Argo CD: `argocd`.
- Quick triage commands:
  ```bash
  kubectl -n hello-world get pods -o wide
  kubectl -n hello-world logs -l app.kubernetes.io/name=hello-world --tail=100
  kubectl -n hello-world describe deploy hello-world
  kubectl -n argocd get applications
  ```
- The Watchdog alert (from kube-prometheus-stack) should **always** be firing. If it
  is *not*, monitoring itself is broken — investigate Prometheus/Alertmanager before
  trusting the absence of other alerts.

---

## HelloWorldErrorBudgetFastBurn
**Severity: critical (page).** 5m and 1h error ratios both exceed 14.4× the SLO budget
— at this rate the 30-day error budget is gone in ~2 days.

1. Confirm real user impact: `curl http://<nlb>/` and check the error-ratio panel in
   the RED dashboard.
2. Correlate with a recent deploy: `kubectl -n hello-world rollout history deploy/hello-world`.
   If a bad digest just rolled out, roll back by reverting the digest commit in
   `gitops/apps/values/hello-world-values.yaml` (Argo re-syncs) or
   `kubectl -n hello-world rollout undo deploy/hello-world` for immediate relief.
3. Check pod logs for 5xx causes; check dependencies if any were added.
4. If caused by load, see *HelloWorldHPAMaxedOut*.

## HelloWorldErrorBudgetSlowBurn
**Severity: warning.** 1h error ratio exceeds 6× the budget for 15m — a slow leak, not
yet an outage. Investigate before it accelerates.

1. Same triage as fast burn, but you have time. Identify the failing route from the
   RED dashboard's per-route breakdown.
2. Check whether it correlates with a specific pod (a bad node/spot reclaim) vs all
   pods (a code/config issue).

## HelloWorldHighLatencyP99
**Severity: warning.** p99 latency exceeded the SLO objective (0.25s) for 10m.

1. RED dashboard → latency panel: is it all routes or one? p99 only, or p50 too?
2. Check CPU throttling and whether the HPA is scaling (`kubectl -n hello-world get hpa`).
3. Check node pressure: `kubectl top nodes` (needs metrics-server, which is deployed).
4. If sustained under real load, raise `autoscaling.maxReplicas` or node capacity.

## HelloWorldNoReadyReplicas
**Severity: critical (page).** Zero pods are Ready — the service is down.

1. `kubectl -n hello-world get pods` — what state? (CrashLoopBackOff, Pending,
   ImagePullBackOff, Terminating?)
2. `Pending` → scheduling: node capacity or the t3.small pod-density ceiling (see
   TRADEOFFS). Add a node or scale the group.
3. `ImagePullBackOff` → verify the digest in the gitops values exists in ECR and the
   nodes can reach ECR (NAT/egress).
4. `CrashLoopBackOff` → see *HelloWorldPodCrashLooping*.
5. Fast mitigation: `kubectl -n hello-world rollout undo deploy/hello-world`.

## HelloWorldPodCrashLooping
**Severity: warning.** A container restarted more than 3× in 5 minutes.

1. `kubectl -n hello-world logs <pod> --previous` — the crash reason is in the prior
   container's logs.
2. Common causes: bad config (the app fails fast on invalid env — check the
   ConfigMap/env), a failing liveness probe, or OOMKill (`kubectl describe pod` →
   check for OOMKilled; raise `resources.limits.memory` if legitimate).
3. If a bad release, revert the digest commit in gitops.

## HelloWorldHPAMaxedOut
**Severity: warning.** The HPA has been pinned at `maxReplicas` for 15m — headroom is
exhausted.

1. Confirm it's real demand (RED request-rate panel) vs a hot loop / retry storm.
2. If real: raise `autoscaling.maxReplicas` in the chart values and ensure the node
   group / Cluster Autoscaler can supply capacity.
3. If artificial: find the source of the traffic (a client retry bug, a scraper).

---

## Operational procedures

### Deploy a new version
Push to `main` → CI builds, scans, pushes by digest, and commits the digest to
`gitops/apps/values/hello-world-values.yaml` → Argo CD syncs. No `kubectl` required.

### Roll back
Revert the digest-bump commit in git (or `git revert`). Argo CD reconciles back to the
previous image. For an emergency, `kubectl -n hello-world rollout undo deploy/hello-world`
gives immediate relief, but push a matching git revert afterward or Argo self-heal will
re-apply the bad version.

### Access dashboards
```bash
kubectl -n argocd     port-forward svc/argocd-server 8090:80
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

---

## Teardown gotchas

`terraform destroy` can stall in two known spots on this stack. Both were hit and
resolved during the live run.

### 1. Argo CD Applications block on their finalizer
The Applications carry `resources-finalizer.argocd.argoproj.io`, which makes deletion
cascade to children. If a child is stuck, the delete hangs and Terraform waits forever
on the root Application. Clear the finalizers so they can be removed:
```bash
for app in hello-world kube-prometheus-stack metrics-server aws-load-balancer-controller root; do
  kubectl patch application "$app" -n argocd --type merge -p '{"metadata":{"finalizers":null}}'
done
# If the helm/kubernetes providers then error (cluster unreachable mid-destroy), drop
# the now-gone Argo resources from state and continue:
terraform state rm 'module.argocd[0].helm_release.argocd' 'module.argocd[0].kubernetes_manifest.root_app'
```

### 2. VPC won't delete — orphaned security groups
The AWS Load Balancer Controller creates security groups Terraform doesn't own (for the
NLB). If the app's Service isn't deleted before the controller, these linger and block
the VPC delete. Prevent it by deleting the Service first (so the NLB and its SGs are
cleaned up); if it still happens, delete the leftover SGs directly:
```bash
VPC=<vpc-id>
for sg in $(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC \
    --query "SecurityGroups[?GroupName!='default'].GroupId" --output text); do
  aws ec2 delete-security-group --group-id "$sg"
done
```

### 3. ECR won't delete — not empty
ECR refuses to delete a repository containing images. Force it:
```bash
aws ecr delete-repository --repository-name hello-world --force
```

After teardown, verify nothing bills:
```bash
aws eks list-clusters                                                   # []
aws ec2 describe-nat-gateways --query 'NatGateways[?State==`available`]' # []
aws elbv2 describe-load-balancers                                       # no k8s-* LBs
```
