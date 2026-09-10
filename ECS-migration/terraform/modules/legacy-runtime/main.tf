resource "aws_security_group" "legacy" {
  name        = "${var.name}-sg"
  description = "Legacy application behind production ALB"
  vpc_id      = var.vpc_id
}
resource "aws_vpc_security_group_ingress_rule" "alb" {
  security_group_id            = aws_security_group.legacy.id
  referenced_security_group_id = var.alb_security_group_id
  description                  = "HTTP only from production ALB"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.legacy.id
  description       = "Package installation and AWS APIs through existing NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
resource "aws_iam_role" "legacy" {
  name = "${var.name}-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}
resource "aws_iam_instance_profile" "legacy" {
  name = var.name
  role = aws_iam_role.legacy.name
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.legacy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "archive_file" "app" {
  type        = "zip"
  source_dir  = var.app_source_dir
  output_path = var.archive_path
  excludes    = ["terraform", "tests", ".git", ".terraform", "app/__pycache__", "app/storage/__pycache__"]
}
resource "aws_s3_bucket" "app" { bucket_prefix = "${var.name}-app-" }
resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration { status = "Enabled" }
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
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_object" "app" {
  bucket     = aws_s3_bucket.app.id
  key        = "releases/${data.archive_file.app.output_sha256}.zip"
  source     = data.archive_file.app.output_path
  etag       = data.archive_file.app.output_md5
  depends_on = [aws_s3_bucket_server_side_encryption_configuration.app, aws_s3_bucket_public_access_block.app]
}
resource "aws_iam_role_policy" "app" {
  name = "download-application"
  role = aws_iam_role.legacy.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.app.arn}/releases/*" }]
  })
}
resource "aws_instance" "legacy" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.legacy.id]
  iam_instance_profile        = aws_iam_instance_profile.legacy.name
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    bucket = aws_s3_bucket.app.id
    key    = aws_s3_object.app.key
    region = var.aws_region
  })
  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  tags       = { Name = var.name }
  depends_on = [aws_iam_role_policy.app, aws_iam_role_policy_attachment.ssm]
}
resource "aws_lb_target_group_attachment" "legacy" {
  target_group_arn = var.target_group_arn
  target_id        = aws_instance.legacy.id
  port             = 80
}
