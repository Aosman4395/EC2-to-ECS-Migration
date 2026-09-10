output "application_url" {
  value = "http://${module.alb.dns_name}"
}
output "alb_arn" {
  value = module.alb.arn
}
output "listener_arn" {
  value = module.alb.listener_arn
}
output "legacy_target_group_arn" {
  value = module.alb.legacy_target_group_arn
}
output "ecs_target_group_arn" {
  value = module.alb.ecs_target_group_arn
}
output "legacy_instance_id" {
  value = module.legacy.instance_id
}
output "routing_weights" {
  value = { legacy = var.legacy_weight, ecs = var.ecs_weight }
}
