variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "legacy_weight" {
  description = "Legacy traffic percentage, owned by the prod state."
  type        = number
  default     = 100
  validation {
    condition     = var.legacy_weight >= 0 && var.legacy_weight <= 100 && floor(var.legacy_weight) == var.legacy_weight
    error_message = "legacy_weight must be an integer from 0 to 100."
  }
}

variable "ecs_weight" {
  description = "ECS traffic percentage. Leave at zero until targets are verified."
  type        = number
  default     = 0
  validation {
    condition     = var.ecs_weight >= 0 && var.ecs_weight <= 100 && floor(var.ecs_weight) == var.ecs_weight && var.legacy_weight + var.ecs_weight == 100
    error_message = "Weights must be integers from 0 to 100 and total 100."
  }
}

variable "legacy_instance_type" {
  type    = string
  default = "t3.micro"
}
