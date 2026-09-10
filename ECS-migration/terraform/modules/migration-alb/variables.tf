variable "name" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" {
  type = list(string)
  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "The production ALB needs at least two public subnets."
  }
}
variable "legacy_weight" { type = number }
variable "ecs_weight" { type = number }
