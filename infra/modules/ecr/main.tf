# -----------------------------------------------------------------------------
# ECR module: one private repository for the app image.
#
# Hand-rolled (not a wrapper) because it is small and we want explicit control
# over immutability, scan-on-push, and the lifecycle policy.
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  name = var.repository_name

  # Immutable tags: a tag, once pushed, can never be moved to a different
  # digest. Combined with digest-pinned deploys this makes "what is running"
  # unambiguous and defeats tag-mutation supply-chain attacks.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

# Keep the registry from growing without bound: retain the last N images,
# expire the rest. Cheap hygiene that also bounds the blast radius of a
# compromised old image lingering around.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.max_image_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = { type = "expire" }
      }
    ]
  })
}
