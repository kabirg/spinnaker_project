provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

variable "resource_name_prefix" {
  type = string
  default = "kag-jenkins"
}

variable "vpc_cidr" {
  type = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type = string
  default = "10.0.0.0/19"
}


variable "ec2_keypair" {
  type = string
  default = "kabirg"
}

# Amaazon Linux AMI in us-east-1
variable "ami" {
  type = string
  default = "ami-0aeeebd8d2ab47354"
}


resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "${var.resource_name_prefix}_vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.resource_name_prefix}_public_subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.resource_name_prefix}_igw"
  }
}

resource "aws_security_group" "webserver_sg" {
  name   = "webserver_sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.resource_name_prefix}_sg"
  }
}

resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.resource_name_prefix}_public_rt"
  }
}

resource "aws_route_table_association" "public-rt-association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public-rt.id
}

# Webserver
resource "aws_instance" "jenkins" {
  ami                         = var.ami
  instance_type               = "t2.medium"
  key_name                    = var.ec2_keypair
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.webserver_sg.id]

  tags = {
    Name = "${var.resource_name_prefix}_jenkins"
  }

  # Src:
  # https://github.com/jenkinsci/docker
  # https://www.lewuathe.com/how-to-install-docker-in-amazon-linux.html
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install docker -y
              service docker start
              usermod -aG docker ec2-user
              docker image pull jenkins/jenkins:lts
              docker container run -d -p 8082:8080 -v jenkins_home:/var/jenkins_home --name jenkins jenkins/jenkins:lts              
              EOF
}

resource "aws_eip" "eip" {
  vpc = true
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.jenkins.id
  allocation_id = aws_eip.eip.id
}
