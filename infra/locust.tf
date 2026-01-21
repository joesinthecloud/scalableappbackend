resource "aws_security_group" "locust" {
  name        = "${local.name}-locust-sg"
  description = "Locust task egress only"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${local.name}-locust-sg"
    Project = var.project
    Env     = var.env
  }
}

resource "aws_ecs_task_definition" "locust" {
  family                   = "${local.name}-locust"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "locust"
      image     = "${aws_ecr_repository.locust.repository_url}:dev"
      essential = true
      environment = [
        { name = "TARGET_HOST", value = "http://${aws_lb.app.dns_name}" }
      ]
      command = [
        "--headless",
        "-u", "50",
        "-r", "5",
        "--run-time", "3m",
        "--stop-timeout", "30",
        "--only-summary"
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "locust"
        }
      }
    }
  ])

  tags = {
    Name    = "${local.name}-locust-taskdef"
    Project = var.project
    Env     = var.env
  }
}
