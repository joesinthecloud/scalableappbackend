resource "aws_ecr_repository" "locust" {
  name                 = "${local.name}-locust"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "${local.name}-locust"
    Project = var.project
    Env     = var.env
  }
}

output "ecr_locust_repo_url" {
  value = aws_ecr_repository.locust.repository_url
}
