## Variables

variable "firewall_trusted" {
  description = "Remote prefixes that are absolutely trusted, keep narrow!"
  type        = list(string)
  default     = []
}

## Implementation

resource "aws_security_group" "www" {
  name        = "WWW"
  description = "Public WWW traffic to Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress = [
    {
      cidr_blocks      = ["0.0.0.0/0"]
      description      = "HTTP for ALB"
      from_port        = 80
      to_port          = 80
      protocol         = "TCP"
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    },
    {
      cidr_blocks      = ["0.0.0.0/0"]
      description      = "HTTPS for ALB"
      from_port        = 443
      to_port          = 443
      protocol         = "TCP"
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "tgs" {
  name        = "TargetGroups"
  description = "Allow traffic between LB target groups and Admin instances"
  vpc_id      = aws_vpc.main.id

  ingress = [
    {
      cidr_blocks      = []
      description      = ""
      from_port        = 443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = true
      to_port          = 443
    },
    {
      cidr_blocks      = []
      description      = ""
      from_port        = 80
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = true
      to_port          = 80
    }
  ]

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "admin" {
  name        = "Admin"
  description = "Nucleus Admin"
  vpc_id      = aws_vpc.main.id

  ingress = [
    {
      cidr_blocks      = aws_subnet.private.*.cidr_block
      description      = "HTTP for Agents and LB Target Groups"
      from_port        = 80
      to_port          = 80
      protocol         = "TCP"
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    },
    {
      cidr_blocks      = aws_subnet.private.*.cidr_block
      description      = "HTTPS for Agents and LB Target Groups"
      from_port        = 443
      to_port          = 443
      protocol         = "TCP"
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "service" {
  name        = "NucleusService"
  description = "Nucleus Service"
  vpc_id      = aws_vpc.main.id

  ingress = [
    {
      cidr_blocks      = aws_subnet.private.*.cidr_block
      description      = "Listen for Admin polls"
      from_port        = 33300
      to_port          = 33499
      protocol         = "TCP"
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "windows" {
  name        = "Windows"
  description = "Windows access rules"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group_rule" "windows_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.windows.id
}

resource "aws_security_group_rule" "rdp_internal" {
  cidr_blocks       = [aws_vpc.main.cidr_block]
  description       = "RDP access within VPC"
  type              = "ingress"
  from_port         = 3389
  to_port           = 3389
  protocol          = "tcp"
  security_group_id = aws_security_group.windows.id
}

resource "aws_security_group" "linux" {
  name        = "Linux"
  description = "Linux access rules"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group_rule" "linux_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.linux.id
}

resource "aws_security_group_rule" "ssh_internal" {
  cidr_blocks       = [aws_vpc.main.cidr_block]
  description       = "SSH access within VPC"
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.linux.id
}

resource "aws_security_group" "rds" {
  name        = "RDS"
  description = "RDS access rules"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group_rule" "rds_internal" {
  cidr_blocks       = aws_subnet.private.*.cidr_block
  description       = "RDS access within VPC"
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  security_group_id = aws_security_group.rds.id
}

resource "aws_security_group" "redis" {
  name        = "redis"
  description = "ElastiCache Redis access rules"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group_rule" "redis_internal" {
  cidr_blocks       = aws_subnet.private.*.cidr_block
  description       = "Redis access within VPC"
  type              = "ingress"
  from_port         = 6379
  to_port           = 6379
  protocol          = "tcp"
  security_group_id = aws_security_group.redis.id
}

## Optional rules

resource "aws_security_group_rule" "icmp_vpn_linux" {
  count             = length(var.vpn_networks)
  cidr_blocks       = [var.vpn_networks[count.index]]
  description       = "ICMP access from VPN"
  type              = "ingress"
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
  ipv6_cidr_blocks  = []
  prefix_list_ids   = []
  security_group_id = aws_security_group.linux.id
}

resource "aws_security_group_rule" "rdp_vpn" {
  count             = length(var.vpn_networks)
  cidr_blocks       = [var.vpn_networks[count.index]]
  description       = "RDP access from VPN"
  type              = "ingress"
  from_port         = 3389
  to_port           = 3389
  protocol          = "tcp"
  ipv6_cidr_blocks  = []
  prefix_list_ids   = []
  security_group_id = aws_security_group.windows.id
}

resource "aws_security_group_rule" "ssh_vpn" {
  count             = length(var.vpn_networks)
  cidr_blocks       = [var.vpn_networks[count.index]]
  description       = "SSH access from VPN"
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  ipv6_cidr_blocks  = []
  prefix_list_ids   = []
  security_group_id = aws_security_group.linux.id
}

resource "aws_security_group_rule" "www_vpn" {
  count             = length(var.vpn_networks)
  cidr_blocks       = [var.vpn_networks[count.index]]
  description       = "http access from VPN"
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  ipv6_cidr_blocks  = []
  prefix_list_ids   = []
  security_group_id = aws_security_group.linux.id
}

resource "aws_security_group_rule" "rds_vpn" {
  count             = length(var.vpn_networks)
  cidr_blocks       = [var.vpn_networks[count.index]]
  description       = "RDS access from VPN"
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  ipv6_cidr_blocks  = []
  prefix_list_ids   = []
  security_group_id = aws_security_group.rds.id
}

resource "aws_security_group_rule" "redis_vpn" {
  count             = length(var.vpn_networks)
  cidr_blocks       = [var.vpn_networks[count.index]]
  description       = "Redis access from VPN"
  type              = "ingress"
  from_port         = 6379
  to_port           = 6379
  protocol          = "tcp"
  ipv6_cidr_blocks  = []
  prefix_list_ids   = []
  security_group_id = aws_security_group.redis.id
}

resource "aws_security_group_rule" "winrm_vpn" {
  count             = length(var.vpn_networks)
  cidr_blocks       = [var.vpn_networks[count.index]]
  description       = "WinRM access from VPN"
  type              = "ingress"
  from_port         = 5986
  to_port           = 5986
  protocol          = "tcp"
  ipv6_cidr_blocks  = []
  prefix_list_ids   = []
  security_group_id = aws_security_group.windows.id
}

resource "aws_security_group" "sg_exceptions" {
  name        = "Trusted"
  description = "Security Groups exceptions, trusted addresses"
  vpc_id      = aws_vpc.main.id

  ingress = [
    {
      description      = "Trusted hosts can access any ports"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = var.firewall_trusted
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]
}

resource "aws_security_group" "services" {
  name        = "Services"
  description = "Allow full traffic access from service subnets"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group_rule" "services_subnets" {
  cidr_blocks       = aws_subnet.services.*.cidr_block
  description       = "Allow access from service subnets"
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.services.id
}
