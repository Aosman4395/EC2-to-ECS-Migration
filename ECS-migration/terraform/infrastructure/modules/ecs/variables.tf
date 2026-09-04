variable "target_group_arn" {
  description = "ALB target group ARN to attach the ECS service to"
  type        = string
}

variable "container_name" {
  description = "Name of the container in the task definition"
  type        = string
}

variable "container_port" {
  description = "Port the application listens on"
  type        = number
  default     = 5000
}

variable "ecs_sg_name" {
  description = "Security group for ECS tasks"
  type        = string
  default     = "ecs_sg"

}

variable "vpc_id" {
  description = "VPC ID where ECS resources are created"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB"
  type        = string
}

variable "execution_role_arn" {
  description = "IAM role ARN used by ECS to pull images and write logs"
  type        = string
}

variable "task_role_arn" {
  description = "IAM role ARN assumed by the application container"
  type        = string
}

variable "container_image" {
  description = "Container image to deploy"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name for ECS task logs"
  type        = string
}

variable "aws_region" {
  description = "AWS region where resources are deployed"
  type        = string
  default     = "us-east-2"
}

variable "subnet_ids" {
  description = "List of subnet IDs for the ECS service"
  type        = list(string)

}
