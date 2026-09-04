variable "ecr_repository_name" {
  description = "The name of the ECR repository."
  type        = string
  default     = "migration-repository"
}

variable "ecr_repository_tags" {
  description = "A map of tags to assign to the ECR repository."
  type        = map(string)
  default     = {
    Name        = "migration-repository"
    Environment = "ECR"
  }
}