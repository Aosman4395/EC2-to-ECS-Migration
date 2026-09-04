variable "vpc_name" {
  description = "The VPC for ECS"
  type        = string
  default     = "ecs_vpc"
}

variable "vpc_cidr" {
  description = "Value of cidr"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24"

  ]
}

variable "private_subnet_cidrs_ecs" {
  description = "List of private subnet CIDR blocks for ECS"
  type        = list(string)
  default = [
    "10.0.11.0/24",
    "10.0.12.0/24"
  ]
}

variable "private_subnet_cidrs_rds" {
  description = "List of private subnet CIDR blocks for RDS"
  type        = list(string)
  default = [
    "10.0.21.0/24",
    "10.0.22.0/24"
  ]
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]
}