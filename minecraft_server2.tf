# VPC and Network Configuration
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "minecraft-vpc"
  }
}

# Public Subnet for ELB
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

# Private Subnet for EC2
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "private-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "minecraft-igw"
  }
}

# NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "minecraft-nat"
  }
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "private-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "elb" {
  name        = "minecraft-elb-sg"
  description = "Security group for Minecraft ELB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Minecraft server port"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "minecraft-elb-sg"
  }
}

resource "aws_security_group" "ec2" {
  name        = "minecraft-ec2-sg"
  description = "Security group for Minecraft EC2 instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 25565
    to_port         = 25565
    protocol        = "tcp"
    security_groups = [aws_security_group.elb.id]
    description     = "Minecraft server port from ELB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "minecraft-ec2-sg"
  }
}

# Classic Elastic Load Balancer
resource "aws_elb" "minecraft" {
  name            = "minecraft-elb"
  subnets         = aws_subnet.public[*].id
  security_groups = [aws_security_group.elb.id]

  listener {
    instance_port     = 25565
    instance_protocol = "tcp"
    lb_port          = 25565
    lb_protocol      = "tcp"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 10
    target             = "TCP:25565"
    interval           = 30
  }

  instances                 = [aws_instance.minecraft.id]
  cross_zone_load_balancing = true
  idle_timeout             = 400

  tags = {
    Name = "minecraft-elb"
  }
}

# EC2 Instance
resource "aws_instance" "minecraft" {
  ami           = "ami-0c55b159cbfafe1f0" # Replace with your desired AMI
  instance_type = "t2.medium" # Increased instance size for Minecraft server

  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = false

  root_block_device {
    volume_size = 30 # Increased volume size for Minecraft world data
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y java-17-amazon-corretto
              mkdir -p /opt/minecraft
              cd /opt/minecraft
              wget https://launcher.mojang.com/v1/objects/e00c4052dac1d59a1188b2aa9d5a87113aaf1122/server.jar
              java -Xmx2048M -Xms2048M -jar server.jar nogui
              echo "eula=true" > eula.txt
              EOF

  tags = {
    Name = "minecraft-server"
  }
}

# Data source for AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Output the ELB DNS name
output "minecraft_server_address" {
  value       = aws_elb.minecraft.dns_name
  description = "The DNS name of the Minecraft server"
}
