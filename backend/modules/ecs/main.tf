resource "aws_ecs_cluster" "cluster_uat" {
  name               = "${var.ecs_cluster_name}-uat"
  capacity_providers = ["FARGATE"]
    setting {
      name = "containerInsights"
      value = "enabled"
    }
}

resource "aws_cloudwatch_log_group" "log_group_uat" {
  name = "${var.cloudwatch_log_group_name}-uat"
}
data "aws_iam_role" "ecsExecutionRole" {
  name = "ecsTaskExecutionRole"
}

resource "aws_ecs_task_definition" "task_uat" {
  family                   = "${var.ecs_task_definition_family}-uat"
  network_mode             = "awsvpc"
  cpu                      = "1024" # equivalent to 1 vCPU
  memory                   = "3072" # equivalent to 3GB
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = data.aws_iam_role.ecsExecutionRole.arn
  task_role_arn            = data.aws_iam_role.ecsExecutionRole.arn

  container_definitions = jsonencode([
    {
      name      = "mytechscrum-container",
      image     = "${var.repository_url}:latest",
      cpu       = 0,
      memory    = 300,
      essential = true,
      portMappings = [
        {
          containerPort = 8000,
          hostPort      = 8000,
          protocol      = "tcp"
        }
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.log_group_uat.name
          "awslogs-region"        = "ap-southeast-2",
          "awslogs-stream-prefix" = "ecs-uat"
        }
      },
      environmentFiles = [
        {
          value = "arn:aws:s3:::techscrum-backend-bucket/config/.env"
          type  = "s3"
        }
      ]
    }
  ])
}


///create ecs servcie
resource "aws_ecs_service" "service_uat" {
  name            = "${var.ecs_service_name}-uat"
  cluster         = aws_ecs_cluster.cluster_uat.id
  task_definition = aws_ecs_task_definition.task_uat.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [var.public_subnets_a_id, var.public_subnets_b_id]
    assign_public_ip = true
    security_groups  = [var.service_sg_id]
  }

  load_balancer {
    target_group_arn = var.tg_uat_arn
    container_name   = "mytechscrum-container"
    container_port   = 8000
  }

  depends_on = [var.listener_arn]
}

#######################################################################################################################
///PROD stage
resource "aws_ecs_cluster" "cluster_prod" {
  name               = "${var.ecs_cluster_name}-prod"
  capacity_providers = ["FARGATE"]
    setting {
      name = "containerInsights"
      value = "enabled"
    }
}

resource "aws_cloudwatch_log_group" "log_group_prod" {
  name = "${var.cloudwatch_log_group_name}-prod"
}

resource "aws_ecs_task_definition" "task_prod" {
  family                   = "${var.ecs_task_definition_family}-prod"
  network_mode             = "awsvpc"
  cpu                      = "1024" # equivalent to 1 vCPU
  memory                   = "3072" # equivalent to 3GB
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = data.aws_iam_role.ecsExecutionRole.arn
  task_role_arn            = data.aws_iam_role.ecsExecutionRole.arn

  container_definitions = jsonencode([
    {
      name      = "mytechscrum-container",
      image     = "${var.repository_url}:latest",
      cpu       = 0,
      memory    = 300,
      essential = true,
      portMappings = [
        {
          containerPort = 8000,
          hostPort      = 8000,
          protocol      = "tcp"
        }
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.log_group_prod.name
          "awslogs-region"        = "ap-southeast-2",
          "awslogs-stream-prefix" = "ecs-prod"
        }
      },
      environmentFiles = [
        {
          value = "arn:aws:s3:::techscrum-backend-bucket/config/.env"
          type  = "s3"
        }
      ]
    }
  ])
}

///create ecs servcie
resource "aws_ecs_service" "service_prod" {
  name            = "${var.ecs_service_name}-prod"
  cluster         = aws_ecs_cluster.cluster_prod.id
  task_definition = aws_ecs_task_definition.task_prod.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [var.private_subnets_a_id, var.private_subnets_b_id]
    assign_public_ip = true
    security_groups  = [var.service_sg_id]
  }

  load_balancer {
    target_group_arn = var.tg_prod_arn
    container_name   = "mytechscrum-container"
    container_port   = 8000
  }
  depends_on = [var.listener_arn]

}



///iam policy for ecsTaskExecutionRole
resource "aws_iam_policy" "s3_access_policy" {
  name        = "s3_access_policy"
  path        = "/"
  description = "Policy for ECS task to access S3"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::techscrum-backend-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:GetBucketLocation",
      "Resource": "arn:aws:s3:::techscrum-backend-bucket"
    }
  ]
}
EOF
}

data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

resource "aws_iam_role_policy_attachment" "ecs_s3_access" {
  role       = data.aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}


///
///Auto scale for UAT 
resource "aws_appautoscaling_target" "scale_target_uat" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster_uat.name}/${aws_ecs_service.service_uat.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 2
  max_capacity       = 4
}

resource "aws_appautoscaling_policy" "scale_up_policy_uat" {
  name               = "${aws_ecs_service.service_uat.name}-scale-up-policy-uat"
  service_namespace  = aws_appautoscaling_target.scale_target_uat.service_namespace
  resource_id        = aws_appautoscaling_target.scale_target_uat.resource_id
  scalable_dimension = aws_appautoscaling_target.scale_target_uat.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_appautoscaling_policy" "scale_down_policy_uat" {
  name               = "${aws_ecs_service.service_uat.name}-scale-down-policy-uat"
  service_namespace  = aws_appautoscaling_target.scale_target_uat.service_namespace
  resource_id        = aws_appautoscaling_target.scale_target_uat.resource_id
  scalable_dimension = aws_appautoscaling_target.scale_target_uat.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high_uat" {
  alarm_name          = "${aws_ecs_service.service_uat.name}-cpu-high-uat"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "5"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "80"
  alarm_actions       = [aws_appautoscaling_policy.scale_up_policy_uat.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.cluster_uat.name
    ServiceName = aws_ecs_service.service_uat.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low_uat" {
  alarm_name          = "${aws_ecs_service.service_uat.name}-cpu-low-uat"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "5"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "20"
  alarm_actions       = [aws_appautoscaling_policy.scale_down_policy_uat.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.cluster_uat.name
    ServiceName = aws_ecs_service.service_uat.name
  }
}
#######################################################################################################################
///Auto scale for PROD

resource "aws_appautoscaling_target" "scale_target_prod" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster_prod.name}/${aws_ecs_service.service_prod.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 2
  max_capacity       = 4
}

resource "aws_appautoscaling_policy" "scale_up_policy_prod" {
  name               = "${aws_ecs_service.service_prod.name}-scale-up-policy-prod"
  service_namespace  = aws_appautoscaling_target.scale_target_prod.service_namespace
  resource_id        = aws_appautoscaling_target.scale_target_prod.resource_id
  scalable_dimension = aws_appautoscaling_target.scale_target_prod.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_appautoscaling_policy" "scale_down_policy_prod" {
  name               = "${aws_ecs_service.service_prod.name}-scale-down-policy-prod"
  service_namespace  = aws_appautoscaling_target.scale_target_prod.service_namespace
  resource_id        = aws_appautoscaling_target.scale_target_prod.resource_id
  scalable_dimension = aws_appautoscaling_target.scale_target_prod.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high_prod" {
  alarm_name          = "${aws_ecs_service.service_prod.name}-cpu-high-prod"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "5"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "80"
  alarm_actions       = [aws_appautoscaling_policy.scale_up_policy_prod.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.cluster_prod.name
    ServiceName = aws_ecs_service.service_prod.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low_prod" {
  alarm_name          = "${aws_ecs_service.service_prod.name}-cpu-low-prod"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "5"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "20"
  alarm_actions       = [aws_appautoscaling_policy.scale_down_policy_prod.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.cluster_prod.name
    ServiceName = aws_ecs_service.service_prod.name
  }
}