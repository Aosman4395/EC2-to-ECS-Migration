variable "aws_region" {
  description = "AWS region for the staging environment"
  type        = string
  default     = "eu-west-2"
}

variable "certificate_arn" {
  description = "ACM certificate ARN used by the staging ALB HTTPS listener"
  type        = string
}

variable "container_image" {
  description = "ECR image URI and tag to deploy to ECS"
  type        = string
}

variable "container_name" {
  description = "Name of the application container"
  type        = string
  default     = "legacy-api"
}

variable "container_port" {
  description = "Port exposed by the Flask/Gunicorn container"
  type        = number
  default     = 5000
}
