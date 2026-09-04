output "autoscaling_target_resource_id" {
  description = "Resource ID of the ECS autoscaling target"
  value       = aws_appautoscaling_target.ecs.resource_id
}