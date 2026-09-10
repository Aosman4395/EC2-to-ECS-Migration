resource "aws_security_group" "alb" {
  name        = "${var.name}-sg"
  description = "Production HTTP entry point"
  vpc_id      = var.vpc_id
}
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.alb.id
  description       = "Public HTTP entry point"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "targets" {
  for_each          = toset(["80", "5000"])
  security_group_id = aws_security_group.alb.id
  description       = "Target traffic and health checks"
  cidr_ipv4         = data.aws_vpc.platform.cidr_block
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
}
data "aws_vpc" "platform" { id = var.vpc_id }

resource "aws_lb" "this" {
  name                       = var.name
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = true
}

resource "aws_lb_target_group" "legacy" {
  name                 = "${var.name}-legacy"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  port                 = 80
  protocol             = "HTTP"
  deregistration_delay = 30
  health_check {
    path                = "/ready"
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}
resource "aws_lb_target_group" "ecs" {
  name                 = "${var.name}-ecs"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  port                 = 5000
  protocol             = "HTTP"
  deregistration_delay = 30
  health_check {
    path                = "/ready"
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# The listener and weights have one owner: environments/prod/terraform.tfstate.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.legacy.arn
        weight = var.legacy_weight
      }
      target_group {
        arn    = aws_lb_target_group.ecs.arn
        weight = var.ecs_weight
      }
      stickiness {
        enabled  = false
        duration = 1
      }
    }
  }
}
