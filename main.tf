# --- TERRAFORM BLOCK ---
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
# Define the AWS region
provider "aws" {
  region = "us-east-1" 
}

# --- DATA SOURCES (Gathering necessary info) ---

# 1. Fetch ALL available Availability Zones 
data "aws_availability_zones" "all" {
  state    = "available"
}

# Find the latest Ubuntu 22.04 LTS AMI 
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  owners = ["099720109477"] # Canonical
}

# --- LOCALS BLOCK (Filter the AZs) ---
# Create a local variable that limits us to the first two AZs 
locals {
  # We use slice() on the fetched data source output to safely grab only the first two AZ names.
  az_names = slice(data.aws_availability_zones.all.names, 0, 2)
}

# --- VPC NETWORK RESOURCES ---

# 1. Create the VPC (The private network container)
resource "aws_vpc" "main" {
  cidr_block           = "10.100.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "HA-Flask-VPC"
  }
}

# 2. Create Public Subnets (using count based on our filtered AZ list)
resource "aws_subnet" "public" {
  count                   = length(local.az_names)
  vpc_id                  = aws_vpc.main.id
  # Dynamically calculate CIDR blocks: 10.100.0.0/24, 10.100.1.0/24, etc.
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index) 
  availability_zone       = local.az_names[count.index]
  map_public_ip_on_launch = true # Instances get public IP
  tags = {
    Name = "Public-Subnet-${count.index + 1}"
    AZ   = local.az_names[count.index]
  }
}

# 3. Create Internet Gateway (IGW)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "HA-Flask-IGW"
  }
}

# 4. Create Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0" # Traffic destination to the Internet
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "Public-RT"
  }
}

# 5. Associate Route Table with Public Subnets (Count for Multi-AZ)
resource "aws_route_table_association" "public_assoc" {
  count          = length(local.az_names)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- SECURITY GROUP ---

resource "aws_security_group" "web_sg" {
  name        = "ha_web_server_sg"
  description = "Allow SSH and HTTP traffic"
  vpc_id      = aws_vpc.main.id

  # Ingress rule for SSH (Port 22)
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress rule for HTTP (Port 8000) for the Flask app
  ingress {
    description = "Flask HTTP from anywhere"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress rule (Allow all outbound traffic)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "HA-Flask-SG"
  }
}

# --- EC2 INSTANCES ---

# 6. Create two EC2 Instances (one in each Public Subnet)
resource "aws_instance" "web_server" {
  count                  = length(local.az_names)
  key_name               = "my-ha-key" 
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public[count.index].id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "HA-Web-Server-${count.index + 1}"
    AZ   = local.az_names[count.index]
  }
}

# --- TERRAFORM OUTPUTS & INVENTORY GENERATION ---

output "server_public_ips" {
  value = aws_instance.web_server[*].public_ip
}

# Generates the Ansible inventory file dynamically
resource "local_file" "inventory" {
  content = templatefile("${path.module}/ansible/inventory.tmpl", {
    # Joins the list of IPs with a newline for the inventory file
    ip_list = join("\n", aws_instance.web_server[*].public_ip)
  })
  filename = "ansible/inventory.ini"
}
