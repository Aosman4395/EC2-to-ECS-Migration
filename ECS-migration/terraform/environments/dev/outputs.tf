output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = aws_subnet.private.id
}

output "ec2_instance_id" {
  description = "Legacy EC2 instance ID"
  value       = aws_instance.app.id
}

output "ec2_instance_private_ip" {
  description = "Legacy EC2 private IP"
  value       = aws_instance.app.private_ip
}

output "ec2_instance_public_ip" {
  description = "Legacy EC2 public Elastic IP"
  value       = aws_eip.app.public_ip
}

output "application_url" {
  description = "Legacy application URL"
  value       = var.domain_name != "" ? "http://${var.domain_name}" : "http://${aws_eip.app.public_ip}"
}

output "security_group_id" {
  description = "Legacy EC2 security group ID"
  value       = aws_security_group.ec2.id
}

output "s3_bucket_name" {
  description = "S3 bucket containing the legacy application package"
  value       = aws_s3_bucket.app.id
}

output "route53_record" {
  description = "Route53 record if configured"
  value       = var.domain_name != "" && var.route53_zone_id != "" ? aws_route53_record.app[0].fqdn : null
}
