variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "service_name" {
  description = "Name of the ECS service"
  type        = string
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks"
  type        = number
  default     = 6
}

variable "cpu_target_value" {
  description = "Target average CPU utilisation percentage"
  type        = number
  default     = 60
}

variable "scale_in_cooldown" {
  description = "Cooldown period in seconds before scaling in again"
  type        = number
  default     = 300
}

variable "scale_out_cooldown" {
  description = "Cooldown period in seconds before scaling out again"
  type        = number
  default     = 60
}