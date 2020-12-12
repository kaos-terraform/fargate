provider "aws" {
  region  = "us-west-1"
  version = "~> 2.44"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>2.70.0"
    }
    hashicorp = {
      source  = "hashicorp/local"
      version = "~> 2.0.0"
    }
  }
}

////////////////////////////////
//                            //
//            ALB             //
//                            //
////////////////////////////////

// Reference: https://github.com/Oxalide/terraform-fargate-example

resource "aws_alb" "main" {
  name            = "${var.domain}.${var.service}.${var.environment}-alb"
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.lb.id]

  tags = {
    Domain      = var.domain
    Environment = var.environment
    Service     = var.service
  }
}

resource "aws_alb_target_group" "app" {
  name        = "${var.domain}.${var.service}.${var.environment}-alb-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  tags = {
    Domain      = var.domain
    Environment = var.environment
    Service     = var.service
  }
}

// Redirect all traffic from the ALB to the target group
resource "aws_alb_listener" "front_end" {
  load_balancer_arn = aws_alb.main.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.app.id
    type             = "forward"
  }
}

////////////////////////////////
//                            //
//            ECR             //
//                            //
////////////////////////////////

// Reference: https://github.com/Oxalide/terraform-fargate-example

resource "aws_ecs_cluster" "main" {
  name = "${var.domain}.${var.service}.${var.environment}-ecs-cluster"

  tags = {
    Domain      = var.domain
    Environment = var.environment
    Service     = var.service
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.domain}.${var.service}.${var.environment}-task-def"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory

  container_definitions = <<TASK_DEFINITION
[
  {
    "cpu": ${var.fargate_cpu},
    "image": "${var.app_image}",
    "memory": ${var.fargate_memory},
    "name": "${var.domain}.${var.service}.${var.environment}-ecs-task",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": ${var.app_port},
        "hostPort": ${var.app_port}
      }
    ]
  }
]
TASK_DEFINITION

  tags = {
    Domain      = var.domain
    Environment = var.environment
    Service     = var.service
  }
}

resource "aws_ecs_service" "main" {
  name            = "${var.domain}.${var.service}.${var.environment}-ecs-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.app_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups = [aws_security_group.ecs_tasks.id]
    subnets         = aws_subnet.private.*.id
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.app.id
    container_name   = "${var.domain}.${var.service}.${var.environment}-ecs-lb"
    container_port   = var.app_port
  }

  depends_on = [
    aws_alb_listener.front_end,
  ]

  tags = {
    Domain      = var.domain
    Environment = var.environment
    Service     = var.service
  }
}

////////////////////////////////
//                            //
//          Network           //
//                            //
////////////////////////////////

// Reference: https://github.com/Oxalide/terraform-fargate-example

// Get availability zones for current region
data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block = "172.17.0.0/16"

  tags = {
    Domain      = var.domain
    Environment = var.environment
    Service     = var.service
  }
}

// Create a private subnet for each availability zone
resource "aws_subnet" "private" {
  count = var.az_count
  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  vpc_id = aws_vpc.main.id

  tags = {
    Domain      = var.domain
    Environment = var.environment
    Service     = var.service
  }
}

// Create a public subnet for each availability zone
resource "aws_subnet" "public" {
  count                   = var.az_count
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, var.az_count + count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  vpc_id                  = aws_vpc.main.id
  map_public_ip_on_launch = true

  tags = {
    Domain      = var.domain
    Environment = var.environment
    Service     = var.service
  }
}

// Create internet gateway for public subnets
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Domain      = var.domain
    Environment = var.environment
    Service     = var.service
  }
}

// Route the public subnet traffic through the internet gateway
resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.main.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

// Create a NAT gateway with an elastic IP for each private subnet to get internet connectivity
resource "aws_eip" "gw" {
  count      = var.az_count
  vpc        = true
  depends_on = [aws_internet_gateway.gw]
}

resource "aws_nat_gateway" "gw" {
  count         = var.az_count
  subnet_id     = element(aws_subnet.public.*.id, count.index)
  allocation_id = element(aws_eip.gw.*.id, count.index)

  tags = {
    Domain      = var.domain
    Environment = var.environment
    Service     = var.service
  }
}

// Create a new route table for the private subnets that routes non-local traffic through the NAT gateway to the internet
resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.gw.*.id, count.index)
  }

  tags = {
    Domain      = var.domain
    Environment = var.environment
    Service     = var.service
  }
}

// Explicitly associate the newly created route tables to the private subnets (so they don't default to the main route table)
resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

////////////////////////////////
//                            //
//          Security          //
//                            //
////////////////////////////////

// Reference: https://github.com/Oxalide/terraform-fargate-example

// ALB (application load balancer) security group
// This is the group you need to edit if you want to restrict access to your application
resource "aws_security_group" "lb" {
  name        = "${var.domain}.${var.service}.${var.environment}-sg-lb"
  description = "Controls access to the ${var.domain}.${var.service} ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Domain      = var.domain
    Environment = var.environment
    Service     = var.service
  }
}

// Traffic to the ECS Cluster should only come from the ALB
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.domain}.${var.service}.${var.environment}-sg-tasks"
  description = "Allow inbound access from the ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol        = "tcp"
    from_port       = var.app_port
    to_port         = var.app_port
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Domain      = var.domain
    Environment = var.environment
    Service     = var.service
  }
}