output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.vpc.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "ecs_private_subnet_ids" {
  description = "IDs of the ECS private subnets"
  value       = aws_subnet.ecs_private[*].id
}

output "rds_private_subnet_ids" {
  description = "IDs of the RDS private subnets"
  value       = aws_subnet.rds_private[*].id
}