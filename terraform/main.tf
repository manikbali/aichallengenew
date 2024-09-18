# Specify the AWS provider
provider "aws" {
  region = "us-west-2"  # Ensure this matches your resource region
}

# CloudWatch Log Group for Backend
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/backend"
  retention_in_days = 7 # Optional: Adjust as needed
}

# CloudWatch Log Group for Frontend
resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/frontend"
  retention_in_days = 7 # Optional: Adjust as needed
}

# Declare the VPC resource
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"  # Adjust as needed
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main_vpc"
  }
}

# First Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"  # Adjust as needed
  availability_zone       = "us-west-2a"   # Ensure it matches your region
  map_public_ip_on_launch = true

  tags = {
    Name = "public_subnet"
  }
}

# Second Subnet
resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"  # Adjust as needed
  availability_zone       = "us-west-2b"   # Different AZ
  map_public_ip_on_launch = true

  tags = {
    Name = "public_subnet_2"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main_igw"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public_route_table"
  }
}

# Associate first subnet
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public.id
}

# Associate second subnet
resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public.id
}

# Security Group for Load Balancer
resource "aws_security_group" "lb_sg" {
  name        = "load_balancer_sg"
  description = "Security group for the load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lb_sg"
  }
}

# Application Load Balancer
resource "aws_lb" "ecs_alb" {
  name               = "ecs-alb"
  load_balancer_type = "application"
  subnets            = [
    aws_subnet.public_subnet.id,
    aws_subnet.public_subnet_2.id
  ]
  security_groups    = [aws_security_group.lb_sg.id]

  tags = {
    Name = "ecs_alb"
  }
}

# Load Balancer Target Group for Frontend
resource "aws_lb_target_group" "frontend_tg" {
  name        = "frontend-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"  # Changed to 'ip' to support Fargate with awsvpc

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "frontend_tg"
  }
}

# Load Balancer Target Group for Backend
resource "aws_lb_target_group" "backend_tg" {
  name        = "backend-tg"
  port        = 5000  # Changed from 80 to 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"  # Changed to 'ip' to support Fargate with awsvpc

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "backend_tg"
  }
}

# Load Balancer Listener for Frontend
resource "aws_lb_listener" "frontend_listener" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_tg.arn
  }
}

# Load Balancer Listener for Backend
resource "aws_lb_listener" "backend_listener" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 5000  # Ensure this is correct
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_tg.arn
  }
}

# Add a Listener for WebSocket traffic on port 3000
resource "aws_lb_listener" "websocket_listener" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 3000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_tg.arn
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "perplexity_cluster" {
  name = "perplexity-cluster"
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs_task_execution_role"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ecs-tasks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "ecs_task_execution_role"
  }
}

# Attach the necessary policy to the ECS execution role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition for Frontend
resource "aws_ecs_task_definition" "frontend_task" {
  family                   = "perplexity-frontend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"    # Adjust as needed
  memory                   = "512"    # Adjust as needed
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "frontend",
    image     = "664418982972.dkr.ecr.us-west-2.amazonaws.com/frontend:latest",
    essential = true,

    portMappings = [{
      containerPort = 3000,
      hostPort      = 3000,
      protocol      = "tcp"
    }],
    
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        awslogs-group         = "/ecs/frontend",
        awslogs-region        = "us-west-2",
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# ECS Task Definition for Backend
resource "aws_ecs_task_definition" "backend_task" {
  family                   = "perplexity-backend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "backend",
    image     = "664418982972.dkr.ecr.us-west-2.amazonaws.com/backend:latest",
    essential = true,

    portMappings = [{
      containerPort = 5000,  # Changed from 8000 to 5000
      hostPort      = 5000,  # Changed from 8000 to 5000
      protocol      = "tcp"
    }],

    logConfiguration = {
      logDriver = "awslogs",
      options = {
        awslogs-group         = "/ecs/backend",
        awslogs-region        = "us-west-2",
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}



# Security Group for ECS Tasks
resource "aws_security_group" "ecs_task_sg" {
  name        = "ecs_task_sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
    description     = "Allow ALB to access frontend task on port 3000"
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
    description     = "Allow ALB to access backend task on port 8000"
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow WebSocket connections on port 3000"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs_task_sg"
  }
}

# ECS Service for Frontend
resource "aws_ecs_service" "frontend_service" {
  name            = "frontend-service"
  cluster         = aws_ecs_cluster.perplexity_cluster.id
  task_definition = aws_ecs_task_definition.frontend_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id]
    security_groups = [aws_security_group.ecs_task_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend_tg.arn
    container_name   = "frontend"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.frontend_listener, aws_lb_listener.websocket_listener]
}

# ECS Service for Backend
resource "aws_ecs_service" "backend_service" {
  name            = "backend-service"
  cluster         = aws_ecs_cluster.perplexity_cluster.id
  task_definition = aws_ecs_task_definition.backend_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id]
    security_groups = [aws_security_group.ecs_task_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend_tg.arn
    container_name   = "backend"
    container_port   = 5000  # Changed from 8000 to 5000
  }

  depends_on = [aws_lb_listener.backend_listener]
}

# Output DNS name of the Load Balancer
output "alb_dns_name" {
  value = aws_lb.ecs_alb.dns_name
}

