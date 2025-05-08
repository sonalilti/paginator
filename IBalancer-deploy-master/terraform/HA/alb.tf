## Variables

variable "alb_deregistration_delay" {
  description = "The amount time for Elastic Load Balancing to wait before changing the state of a deregistering target from draining to unused. The range is 0-3600 seconds."
  default     = 300
}


## Implementation

resource "aws_lb" "alb" {
  name               = replace(var.vpc_name, ".", "")
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.www.id, aws_security_group.tgs.id]
  subnets            = aws_subnet.public.*.id

  idle_timeout = 600

  enable_deletion_protection = true

  tags = merge(
    { Name = var.vpc_name, },
    var.extra_tags
  )

  #access_logs {
  #  bucket  = aws_s3_bucket.lb-logs.bucket
  #  prefix  = "www"
  #  enabled = true
  #}
}

resource "aws_lb" "alb-int" {
  name               = "${replace(var.vpc_name, ".", "")}-int"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.admin.id, aws_security_group.tgs.id]
  subnets            = aws_subnet.services.*.id

  idle_timeout = 350

  enable_deletion_protection = true

  tags = merge(
    { Name = "${var.vpc_name}-int", },
    var.extra_tags
  )
  access_logs {
    bucket  = aws_s3_bucket.lb-logs.bucket
    prefix  = "int"
    enabled = true
  }
}

resource "aws_lb_target_group" "alb" {
  name                          = replace(var.vpc_name, ".", "")
  port                          = 80
  protocol                      = "HTTP"
  vpc_id                        = aws_vpc.main.id
  load_balancing_algorithm_type = "least_outstanding_requests"

  deregistration_delay = var.alb_deregistration_delay

  stickiness {
    enabled         = true
    type            = "lb_cookie"
    cookie_duration = 86400
  }

  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 15
    matcher             = "200"
    path                = "/api/v1/monitor/alive?components=admin%2Credis"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 4
    unhealthy_threshold = 3
  }

  tags = merge(
    { Name = var.vpc_name, },
    var.extra_tags
  )
}

resource "aws_lb_target_group" "alb-int" {
  name     = "${replace(var.vpc_name, ".", "")}-int"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  deregistration_delay = var.alb_deregistration_delay

  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 15
    matcher             = "200"
    path                = "/api/v1/monitor/alive?components=admin%2Credis"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 4
    unhealthy_threshold = 3
  }

  tags = merge(
    { Name = "${var.vpc_name}-int", },
    var.extra_tags
  )
}

resource "aws_lb_listener" "alb_https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.www.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb.arn
  }

  tags = merge(
    { Name = "${var.vpc_name}-https", },
    var.extra_tags
  )
}

resource "aws_lb_listener" "alb_http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(
    { Name = "${var.vpc_name}-http", },
    var.extra_tags
  )
}

resource "aws_lb_listener" "alb_int_http" {
  load_balancer_arn = aws_lb.alb-int.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-int.arn
  }

  tags = merge(
    { Name = "${var.vpc_name}-int-http", },
    var.extra_tags
  )
}

resource "aws_lb_target_group_attachment" "alb" {
  count            = var.admin_instance_count
  target_group_arn = aws_lb_target_group.alb.arn
  target_id        = aws_instance.admin[count.index].id
  port             = 80
}

resource "aws_lb_target_group_attachment" "alb-int" {
  count            = var.admin_instance_count
  target_group_arn = aws_lb_target_group.alb-int.arn
  target_id        = aws_instance.admin[count.index].id
  port             = 80
}

data "aws_iam_policy_document" "allow-lb" {
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.default.arn]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.lb-logs.arn}/*"
    ]

  }
}

data "aws_elb_service_account" "default" {}

resource "aws_s3_bucket" "lb-logs" {
  bucket = "${var.vpc_name}-lb-logs"

  tags = merge(
    { Name = "${var.vpc_name}-lb-logs", },
    var.extra_tags
  )
}

resource "aws_s3_bucket_acl" "lb-logs-acl" {
  bucket     = aws_s3_bucket.lb-logs.id
  acl        = "private"
  depends_on = [aws_s3_bucket_ownership_controls.s3_bucket_acl_lb_logs]
}

resource "aws_s3_bucket_ownership_controls" "s3_bucket_acl_lb_logs" {
  bucket = aws_s3_bucket.lb-logs.id
  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_policy" "allow-lb" {
  bucket = aws_s3_bucket.lb-logs.id
  policy = data.aws_iam_policy_document.allow-lb.json
}

