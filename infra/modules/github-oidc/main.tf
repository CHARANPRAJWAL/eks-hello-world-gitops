# -----------------------------------------------------------------------------
# GitHub OIDC role for CI.
#
# Lets the ci-main workflow assume a short-lived AWS role via GitHub's OIDC
# provider — no long-lived access keys anywhere. The trust policy is scoped by
# the `sub` claim to exactly this repository (and optionally a ref), so no
# other repo or fork can assume it. Permissions are limited to pushing to the
# one ECR repository.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# The GitHub OIDC provider. Created once per account; if it already exists,
# import it or set create_oidc_provider = false and pass the ARN.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scope to this repo. The value looks like repo:OWNER/REPO:ref:refs/heads/main
    # or repo:OWNER/REPO:* — narrow it as tight as your workflow allows.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [var.github_sub_claim]
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "${var.name_prefix}-github-ci"
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = var.tags
}

# Least-privilege ECR push: auth + push/pull to the one repository only.
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
