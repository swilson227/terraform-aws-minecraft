provider "aws" {
  region  = "eu-west-1"
}

# VPC and Network Configuration
resource "aws_vpc" "minecraft" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "minecraft-vpc"
  }
}

# Public Subnet for ELB
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.minecraft.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "public-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.minecraft.id

  tags = {
    Name = "minecraft-igw"
  }
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.minecraft.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ec2" {
  name        = "minecraft-ec2-sg"
  description = "Security group for Minecraft EC2 instance"
  vpc_id      = aws_vpc.minecraft.id

  ingress {
    from_port       = 25565
    to_port         = 25565
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
    description     = "Minecraft server port from Internet"
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

# EC2 Instance
resource "aws_instance" "minecraft" {
  ami           = "ami-0ef0975ebdd78b77b" # Replace with your desired AMI
  instance_type = "t3.medium" # Increased instance size for Minecraft server

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30 # Increased volume size for Minecraft world data
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y java-23-amazon-corretto java-23-amazon-corretto-devel
              mkdir -p /opt/minecraft
              cd /opt/minecraft
              #groupadd minecraft
              #adduser -r -d /opt/minecraft -g minecraft -G minecraft minecraft
              #wget https://piston-data.mojang.com/v1/objects/4707d00eb834b446575d89a61a11b5d548d8c001/server.jar
              curl -OJ https://meta.fabricmc.net/v2/versions/loader/1.21.4/0.16.10/1.0.1/server/jar
              echo "eula=true" > eula.txt
              sleep 10
              #java -Xmx2048M -Xms2048M -jar server.jar nogui
              java -Xmx2G -jar fabric-server-mc.1.21.4-loader.0.16.10-launcher.1.0.1.jar nogui
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
  value       = aws_instance.minecraft.public_ip
  description = "The DNS name of the Minecraft server"
}
