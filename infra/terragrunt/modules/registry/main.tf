# The container registry for the dbt runner's image, shared by both environments. Each deploy
# pushes one image with an immutable tag (the commit) and points dev, then prod, at it; older
# images are deleted, keeping the one before to roll back to.

resource "aws_ecr_repository" "runner" {
  #checkov:skip=CKV_AWS_136:AWS-managed encryption (AES-256) is enough; a customer-managed KMS key adds cost and key management
  name                 = "${var.name}-runner"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # Images can always be rebuilt from the repo, so destroying the stack may delete them.
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "runner" {
  repository = aws_ecr_repository.runner.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the current image and the one before it"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 2
      }
      action = { type = "expire" }
    }]
  })
}
