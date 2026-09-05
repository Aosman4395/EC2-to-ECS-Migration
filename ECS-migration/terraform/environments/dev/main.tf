# Development environment
#
# Reproduces the original legacy EC2 architecture so the application can be
# baselined and validated before comparison with the ECS migration target.

# Data source for latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Public subnet for the legacy EC2 instance
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
    Type = "Public"
  }
}

# Retained from the original legacy Terraform as the private migration subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-private-subnet"
    Type = "Private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security group for the legacy EC2 application
resource "aws_security_group" "ec2" {
  name_prefix = "${var.project_name}-ec2-"
  description = "Security group for EC2 instance running Flask app"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from allowed CIDR"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "HTTPS from allowed CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# IAM role and instance profile for EC2
resource "aws_iam_role" "ec2" {
  name_prefix = "${var.project_name}-ec2-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

resource "aws_iam_instance_profile" "ec2" {
  name_prefix = "${var.project_name}-ec2-"
  role        = aws_iam_role.ec2.name
}

# Package the original legacy application from the repository.
data "archive_file" "app" {
  type        = "zip"
  output_path = "${path.module}/app.zip"
  source_dir  = "${path.module}/../../../../legacy-app"
  excludes    = ["terraform", ".git", ".terraform", "*.tfstate", "*.tfstate.backup"]
}

resource "aws_s3_bucket" "app" {
  bucket_prefix = "${var.project_name}-app-"

  tags = {
    Name = "${var.project_name}-app-bucket"
  }
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "app" {
  bucket = aws_s3_bucket.app.id
  key    = "app.zip"
  source = data.archive_file.app.output_path
  etag   = filemd5(data.archive_file.app.output_path)
}

resource "aws_iam_role_policy" "ec2_s3_access" {
  name_prefix = "${var.project_name}-ec2-s3-"
  role        = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.app.arn}/*"
      }
    ]
  })
}

locals {
  user_data = <<-EOF
#!/bin/bash
set -euo pipefail

APP_DIR="/opt/flask-app"
S3_BUCKET="${aws_s3_bucket.app.id}"
S3_KEY="app.zip"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq awscli python3 python3-venv python3-pip nginx git curl wget unzip

mkdir -p $APP_DIR
mkdir -p /var/log/flask-app
chown ubuntu:ubuntu $APP_DIR
chown ubuntu:ubuntu /var/log/flask-app

aws s3 cp s3://$S3_BUCKET/$S3_KEY /tmp/app.zip
cd /tmp
unzip -q app.zip -d $APP_DIR/
rm app.zip

chown -R ubuntu:ubuntu $APP_DIR

cd $APP_DIR
chmod +x scripts/setup.sh
bash $APP_DIR/scripts/setup.sh

echo "Application setup completed at $(date)" >> /var/log/user-data.log
  EOF
}

# Legacy EC2 instance
resource "aws_instance" "app" {
  ami                    = "ami-0224ce6f9504665ee"
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null
  user_data              = base64encode(local.user_data)

  depends_on = [aws_s3_object.app]

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "${var.project_name}-ec2-instance"
  }
}

resource "aws_eip" "app" {
  domain   = "vpc"
  instance = aws_instance.app.id

  tags = {
    Name = "${var.project_name}-eip"
  }
}

resource "aws_route53_record" "app" {
  count   = var.domain_name != "" && var.route53_zone_id != "" ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  records = [aws_eip.app.public_ip]
  ttl     = 300
}
