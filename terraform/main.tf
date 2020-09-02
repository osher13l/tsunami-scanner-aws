provider "aws" {
  region  = var.aws-region
  access_key = var.aws-access-key
  secret_key = var.aws-secret-key
}

resource "aws_sqs_queue" "tsunami_queue" {
  name                        = "tsunami-queue.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}

resource "aws_ecs_cluster" "tsunami_cluster" {
  name = "tsunami-cluster"
}
# Providing a reference to our default VPC
resource "aws_default_vpc" "default_vpc" {
}

# Providing a reference to our default subnets
resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = var.default_subnet_a
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = var.default_subnet_b
}

resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = var.default_subnet_c
}

resource "aws_ecs_task_definition" "tsunami_app_task" {
  family                   = "tsunami_app_task" # Naming our first task
  container_definitions    = <<DEFINITION
  [
    {
      "name": "tsunami_app_task",
      "image": "osher13levi/tsunami-app:1.0",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 5000,
          "hostPort": 5000
        }
      ],
      "memory": 512,
      "cpu": 256,
      "environment": [
        {
          "name":"AWS_ACCESS_KEY",
          "value": "${var.aws-access-key}"
        },
        {
          "name":"AWS_SECRET_KEY", 
          "value": "${var.aws-secret-key}"
        },
        {
         "name": "REGION_NAME",
         "value": "${var.aws-region}"
        },
        {
         "name": "AWS_SQS_QUEUE",
         "value": "${aws_sqs_queue.tsunami_queue.id}"
        },
        {
         "name": "BUCKET_NAME",
         "value": "tsunami-results-bucket"
        }
       ]
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # Stating that we are using ECS Fargate
  network_mode             = "awsvpc"    # Using awsvpc as our network mode as this is required for Fargate
  memory                   = 512         # Specifying the memory our container requires
  cpu                      = 256         # Specifying the CPU our container requires
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_alb" "application_load_balancer" {
  name               = "tsunami-lb-tf" # Naming our load balancer
  load_balancer_type = "application"
  subnets = [ # Referencing the default subnets
    aws_default_subnet.default_subnet_a.id,
    aws_default_subnet.default_subnet_b.id,
    aws_default_subnet.default_subnet_c.id
  ]
  # Referencing the security group
  security_groups = [aws_security_group.load_balancer_security_group.id]
}

# Creating a security group for the load balancer:
resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_target_group" "target_group" {
  name        = "target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_default_vpc.default_vpc.id # Referencing the default VPC
  depends_on = ["aws_alb.application_load_balancer"]
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_alb.application_load_balancer.arn # Referencing our load balancer
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn # Referencing our tagrte group
  }
}

data "aws_lb" "alb_data" {
  arn  = aws_alb.application_load_balancer.arn
}

resource "aws_ecs_service" "tsunami_app_service" {
  name            = "tsunami_app_service"                             # Naming our first service
  cluster         = aws_ecs_cluster.tsunami_cluster.id             # Referencing our created Cluster
  task_definition = aws_ecs_task_definition.tsunami_app_task.arn # Referencing the task our service will spin up
  launch_type     = "FARGATE"
  desired_count   = 3 # Setting the number of containers we want deployed to 3
  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn # Referencing our target group
    container_name   = aws_ecs_task_definition.tsunami_app_task.family
    container_port   = 5000 # Specifying the container port
  }
  network_configuration {
    subnets          = [aws_default_subnet.default_subnet_a.id, aws_default_subnet.default_subnet_b.id, aws_default_subnet.default_subnet_c.id]
    assign_public_ip = true # Providing our containers with public IPs
    security_groups  = [aws_security_group.service_security_group.id] # Setting the security group
  }
}

resource "aws_security_group" "service_security_group" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = [aws_security_group.load_balancer_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_s3_bucket" "tsunami_results" {
  bucket = "tsunami-results-bucket"
  acl    = "private"
}

resource "aws_lambda_function" "lambda_tsunami_function" {
  role             = "${aws_iam_role.lambda_exec_role.arn}"
  handler          = "lambda-tsunami.handler"
  runtime          = "python2.7"
  filename         = "lambda-tsunami.zip"
  function_name    = "lambda-tsunami-function"
  depends_on = ["aws_alb.application_load_balancer"]
  environment {
    variables = {
      alb_dns = data.aws_lb.alb_data.dns_name,
      bucket_name = aws_s3_bucket.tsunami_results.bucket
    }
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name        = "lambda_exec"
  path        = "/"
  description = "Allows Lambda Function to call AWS services on your behalf."

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": 
            "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_lambda_event_source_mapping" "event_source_mapping" {
  event_source_arn = aws_sqs_queue.tsunami_queue.arn
  enabled          = true
  function_name    = aws_lambda_function.lambda_tsunami_function.arn
  batch_size       = 1
}

resource "aws_lambda_permission" "allows_sqs_to_trigger_lambda" {
  statement_id  = "AllowExecutionFromSQS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_tsunami_function.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = aws_sqs_queue.tsunami_queue.arn
}

resource "aws_iam_role_policy_attachment" "tsunami_lambda" {
  policy_arn = aws_iam_policy.tsunami_lambda.arn
  role = aws_iam_role.lambda_exec_role.name
}

resource "aws_iam_policy" "tsunami_lambda" {
  policy = "${data.aws_iam_policy_document.tsunami_lambda.json}"
}

data "aws_iam_policy_document" "tsunami_lambda" {
  statement {
    sid       = "AllowSQSPermissions"
    effect    = "Allow"
    resources = ["arn:aws:sqs:*"]

    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ReceiveMessage",
    ]
  }

  statement {
    sid       = "AllowInvokingLambdas"
    effect    = "Allow"
    resources = ["arn:aws:lambda:${var.aws-region}:*:function:*"]
    actions   = ["lambda:InvokeFunction"]
  }

  statement {
    sid       = "AllowCreatingLogGroups"
    effect    = "Allow"
    resources = ["arn:aws:logs:${var.aws-region}:*:*"]
    actions   = ["logs:CreateLogGroup"]
  }
  statement {
    sid       = "AllowWritingLogs"
    effect    = "Allow"
    resources = ["arn:aws:logs:${var.aws-region}:*:log-group:/aws/lambda/*:*"]

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
  }
}
