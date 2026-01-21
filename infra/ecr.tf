resource "aws_ecr_repository" "app" {
  name                 = "${local.name}-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "${local.name}-app"
    Project = var.project
    Env     = var.env
  }
}

output "ecr_repo_url" {
  value = aws_ecr_repository.app.repository_url
}
