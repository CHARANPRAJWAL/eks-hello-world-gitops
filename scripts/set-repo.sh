#!/usr/bin/env bash
# Fill repository-specific placeholders across the repo.
#
# Usage:
#   scripts/set-repo.sh <github-owner> <repo-name> [account-id]
#
# Example:
#   scripts/set-repo.sh CHARANPRAJWAL eks-hello-world-gitops 123456789012
#
# - <owner>/<repo> fills the Argo CD repoURL, the runbook URLs, and the OIDC
#   sub claim.
# - [account-id] (optional) fills the ECR repository URL in the gitops values.
#   Pass it once `terraform apply` has created the account/ECR, or set the ECR
#   URL later from `terraform output ecr_repository_url`.
set -euo pipefail

OWNER="${1:?owner required}"
REPO="${2:?repo name required}"
ACCOUNT_ID="${3:-}"
REGION="${AWS_REGION:-ap-south-1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_URL="https://github.com/${OWNER}/${REPO}.git"

echo "Setting repo to ${OWNER}/${REPO}"

# Argo CD Application repoURL (app-of-apps + multi-source refs).
sed -i.bak "s|REPO_URL_PLACEHOLDER|${REPO_URL}|g" \
  "${ROOT}/gitops/bootstrap/apps/hello-world.yaml"

# Runbook URLs (PrometheusRule) and Terraform defaults reference OWNER/repo.
find "${ROOT}/charts" "${ROOT}/infra" -type f \( -name '*.yaml' -o -name '*.tf' \) \
  -not -path '*/.terraform/*' -print0 \
  | xargs -0 sed -i.bak "s|OWNER/devops-assignment|${OWNER}/${REPO}|g"

if [[ -n "${ACCOUNT_ID}" ]]; then
  echo "Setting ECR account ${ACCOUNT_ID} (${REGION})"
  sed -i.bak "s|ACCOUNT_ID\.dkr\.ecr\.[a-z0-9-]*\.amazonaws\.com|${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com|g" \
    "${ROOT}/gitops/apps/values/hello-world-values.yaml"
fi

# Clean up sed backups.
find "${ROOT}" -name '*.bak' -not -path '*/node_modules/*' -not -path '*/.terraform/*' -delete

echo "Done. Review with: git diff"
