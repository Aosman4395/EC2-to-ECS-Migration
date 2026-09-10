output "security_group_id" { value = aws_security_group.alb.id }
output "arn" { value = aws_lb.this.arn }
output "dns_name" { value = aws_lb.this.dns_name }
output "listener_arn" { value = aws_lb_listener.http.arn }
output "legacy_target_group_arn" { value = aws_lb_target_group.legacy.arn }
output "ecs_target_group_arn" { value = aws_lb_target_group.ecs.arn }
