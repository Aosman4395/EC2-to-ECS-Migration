variable "alb_name" {
  description = "The name of the Application Load Balancer"
  type        = string
  default     = "memos-alb"
}

variable "public_subnet_ids" {
  description = "The public subnet IDs for the ALB"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID where ALB resources are created"
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
