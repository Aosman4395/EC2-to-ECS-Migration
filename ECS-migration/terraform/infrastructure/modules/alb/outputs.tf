output "load_balancer_arn" {
  value = aws_lb.ecs_alb.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.ecs_tg.arn
}

output "alb_sg_id" {
  description = "Security group ID of the ALB"
  value       = aws_security_group.alb_sg.id
}