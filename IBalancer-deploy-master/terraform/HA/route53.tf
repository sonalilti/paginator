## Variables

variable "route53_san" {
  description = "Set of domains that should be SANs in the issued certificate"
  type        = list(string)
  default     = []
}

## Implementation

resource "aws_route53_zone" "main" {
  name          = var.vpc_name
  comment       = "Nucleus VPC for ${var.vpc_name} environment"
  force_destroy = false
}

resource "aws_route53_record" "discovery" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "admin.in.${aws_route53_zone.main.name}"
  type    = "TXT"
  ttl     = "300"
  records = ["http://admin.in.${aws_route53_zone.main.name}"]
}

resource "aws_route53_record" "admin" {
  count   = var.agent_instance_count
  zone_id = aws_route53_zone.main.zone_id
  name    = "admin${count.index}.in.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = "300"
  records = [element(aws_instance.admin.*.private_ip, count.index)]
}

resource "aws_route53_record" "agent" {
  count   = var.agent_instance_count
  zone_id = aws_route53_zone.main.zone_id
  name    = "agent${count.index}.in.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = "300"
  records = [element(aws_instance.agent.*.private_ip, count.index)]
}

resource "aws_route53_record" "artisan" {
  count   = var.artisan_instance_count
  zone_id = aws_route53_zone.main.zone_id
  name    = "artisan${count.index}.in.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = "300"
  records = [element(aws_instance.artisan.*.private_ip, count.index)]
}

resource "aws_route53_record" "ims" {
  count   = var.ims_instance_count
  zone_id = aws_route53_zone.main.zone_id
  name    = "ims${count.index}.in.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = "300"
  records = [element(aws_instance.ims.*.private_ip, count.index)]
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = aws_route53_zone.main.name
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "admin-int" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "admin.in.${aws_route53_zone.main.name}"
  type    = "A"

  alias {
    name                   = aws_lb.alb-int.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "nfs" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "nfs.in.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = "300"
  records = tolist(aws_fsx_ontap_storage_virtual_machine.nucleus.endpoints[0].nfs[0].ip_addresses)
}

resource "aws_route53_record" "smb" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "smb.in.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = "300"
  records = tolist(aws_fsx_ontap_storage_virtual_machine.nucleus.endpoints[0].smb[0].ip_addresses)
}

resource "aws_route53_record" "redis" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "redis.in.${aws_route53_zone.main.name}"
  type    = "CNAME"
  ttl     = "300"
  records = [aws_elasticache_replication_group.redis.configuration_endpoint_address]
}

resource "aws_route53_record" "mysql" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "mysql.in.${aws_route53_zone.main.name}"
  type    = "CNAME"
  ttl     = "300"
  records = [aws_db_instance.main.address]
}

resource "aws_acm_certificate" "www" {
  domain_name               = var.vpc_name
  subject_alternative_names = var.route53_san
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    { Name = var.vpc_name, },
    var.extra_tags
  )
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.www.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.id
}

resource "aws_acm_certificate_validation" "www" {
  certificate_arn         = aws_acm_certificate.www.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
  depends_on              = [aws_route53_record.cert_validation]
}

resource "aws_vpc_dhcp_options_association" "discovery" {
  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.discovery.id
}
