output "legacy_application_url" {
  description = "Existing legacy EC2 application URL from the dev environment"
  value       = data.terraform_remote_state.legacy_dev.outputs.application_url
}

output "legacy_ec2_public_ip" {
  description = "Existing legacy EC2 Elastic IP from the dev environment"
  value       = data.terraform_remote_state.legacy_dev.outputs.ec2_instance_public_ip
}

output "staging_vpc_id" {
  description = "VPC ID for the new ECS staging platform"
  value       = module.vpc.vpc_id
}

output "staging_alb_arn" {
  description = "ARN of the staging Application Load Balancer"
  value       = module.alb.load_balancer_arn
}

output "staging_target_group_arn" {
  description = "ARN of the ECS staging target group"
  value       = module.alb.target_group_arn
}
