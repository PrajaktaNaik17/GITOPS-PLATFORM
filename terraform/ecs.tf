#############################################
# ECR Repository for Container Images
#############################################

resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-ecr-repo"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

#############################################
# ECS Task Definition
#############################################

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "app"
      image = "${aws_ecr_repository.app.repository_url}:latest"
      
      essential = true
      
      portMappings = [
        {
          containerPort = var.app_port
          protocol      = "tcp"
        }
      ]

      # Environment variables
      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "PORT"
          value = tostring(var.app_port)
        },
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "DB_HOST"
          value = aws_db_instance.main.endpoint
        },
        {
          name  = "DB_PORT"
          value = tostring(aws_db_instance.main.port)
        },
        {
          name  = "DB_NAME"
          value = aws_db_instance.main.db_name
        },
        {
          name  = "S3_BACKUP_BUCKET"
          value = aws_s3_bucket.backups.bucket
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ]

      # Secrets from AWS Secrets Manager
      secrets = [
        {
          name      = "DB_USER"
          valueFrom = "${aws_secretsmanager_secret.db_password.arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.db_password.arn}:password::"
        }
      ]

      # Health check
      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:${var.app_port}/health || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      # Logging configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # Resource limits
      cpu    = 512
      memory = 1024

      # Security
      readonlyRootFilesystem = false
      
      # For debugging
      command = null
    }
  ])

  tags = {
    Name = "${var.project_name}-task-definition"
  }
}

#############################################
# Blue ECS Service
#############################################

resource "aws_ecs_service" "blue" {
  name            = "${var.project_name}-blue"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"


  # Network configuration
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  # Load balancer configuration
  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "app"
    container_port   = var.app_port
  }

  # Health check grace period
  health_check_grace_period_seconds = 60

    
    

  # Service discovery
  service_registries {
    registry_arn = aws_service_discovery_service.blue.arn
  }

  # Ensure target group is created first
  depends_on = [
    aws_lb_listener.main,
    aws_iam_role_policy_attachment.ecs_task_execution
  ]

  tags = {
    Name  = "${var.project_name}-blue-service"
    Color = "blue"
  }

  # Ignore changes to desired count for auto-scaling
  lifecycle {
    ignore_changes = [desired_count]
  }
}

#############################################
# Green ECS Service - Fixed Configuration
#############################################

resource "aws_ecs_service" "green" {
  name            = "${var.project_name}-green"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 0  # Start with 0, scale up during deployments
  launch_type     = "FARGATE"

  # Network configuration
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  # Service discovery only (no load balancer initially)
  service_registries {
    registry_arn = aws_service_discovery_service.green.arn
  }

  # Health check grace period (even without LB)
  health_check_grace_period_seconds = 60

  # Ensure dependencies are met
  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution
  ]

  tags = {
    Name  = "${var.project_name}-green-service"
    Color = "green"
  }

  # Ignore changes to desired count for auto-scaling
  lifecycle {
    ignore_changes = [desired_count, load_balancer]
  }
}
#############################################
# Service Discovery
#############################################

resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.project_name}.local"
  description = "Private DNS namespace for ${var.project_name}"
  vpc         = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-namespace"
  }
}

resource "aws_service_discovery_service" "blue" {
  name = "blue"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }


  tags = {
    Name  = "${var.project_name}-blue-discovery"
    Color = "blue"
  }
}

resource "aws_service_discovery_service" "green" {
  name = "green"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }


  tags = {
    Name  = "${var.project_name}-green-discovery"
    Color = "green"
  }
}

#############################################
# Auto Scaling
#############################################

# Auto Scaling Target for Blue Service
resource "aws_appautoscaling_target" "blue" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.blue.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto Scaling Policy for Blue Service
resource "aws_appautoscaling_policy" "blue_cpu" {
  name               = "${var.project_name}-blue-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.blue.resource_id
  scalable_dimension = aws_appautoscaling_target.blue.scalable_dimension
  service_namespace  = aws_appautoscaling_target.blue.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# Auto Scaling Target for Green Service
resource "aws_appautoscaling_target" "green" {
  max_capacity       = 10
  min_capacity       = 0
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.green.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto Scaling Policy for Green Service
resource "aws_appautoscaling_policy" "green_cpu" {
  name               = "${var.project_name}-green-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.green.resource_id
  scalable_dimension = aws_appautoscaling_target.green.scalable_dimension
  service_namespace  = aws_appautoscaling_target.green.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

#############################################
# CloudWatch Alarms
#############################################

# Blue service health alarm
resource "aws_cloudwatch_metric_alarm" "blue_service_health" {
  alarm_name          = "${var.project_name}-blue-service-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors blue service health"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.blue.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = {
    Name = "${var.project_name}-blue-health-alarm"
  }
}

# Green service health alarm
resource "aws_cloudwatch_metric_alarm" "green_service_health" {
  alarm_name          = "${var.project_name}-green-service-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors green service health"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.green.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = {
    Name = "${var.project_name}-green-health-alarm"
  }
}

# SNS topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"

  tags = {
    Name = "${var.project_name}-alerts-topic"
  }
}
