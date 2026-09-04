variable "alb_name" {
  description = "The name of the Application Load Balancer"
  type        = string
  default     = "memos-alb"

}

variable "alb_security_group_ids" {
  description = "The security group IDs to associate with the ALB"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "The public subnet IDs for the ALB"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID where ECS resources are created"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate for the ALB"
  type        = string
}

variable "alb_sg_name" {
  description = "Security group for Application Load Balancer"
  type        = string
  default     = "alb-security-group"

}

variable "vpc_id" {
  description = "VPC ID where ECS resources are created"
  type        = string
}