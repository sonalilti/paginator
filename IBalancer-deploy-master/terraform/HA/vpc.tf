## Variables

variable "vpc_subnet" {
  description = "Subnet you wish to use within VPC. Make sure it is big enough."
  type        = string
}

variable "vpc_extra_tags" {
  type    = map(any)
  default = {}
}

# If this list is empty no VPN-related resources get built
variable "vpn_networks" {
  type    = list(string)
  default = []
}

# Only gets built if `vpn_networks` list is not empty
variable "vpn_transit_gw" {
  type    = string
  default = ""
}

## Implementation

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_subnet
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = false

  tags = merge(
    { Name = var.vpc_name, },
    var.extra_tags
  )
}

resource "aws_subnet" "public" {
  count      = length(var.zone_names)
  vpc_id     = aws_vpc.main.id
  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 5, count.index)

  availability_zone       = var.zone_names[count.index]
  map_public_ip_on_launch = "false"

  tags = merge(
    { Name = "${var.vpc_name}-public-${var.zone_names[count.index]}", },
    var.extra_tags
  )
}

resource "aws_subnet" "services" {
  count      = length(var.zone_names)
  vpc_id     = aws_vpc.main.id
  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 5, count.index + 4)

  availability_zone       = var.zone_names[count.index]
  map_public_ip_on_launch = "false"

  tags = merge(
    { Name = "${var.vpc_name}-services-${var.zone_names[count.index]}", },
    var.extra_tags
  )
}

resource "aws_subnet" "private" {
  count      = length(var.zone_names)
  vpc_id     = aws_vpc.main.id
  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 2, count.index + 1)

  availability_zone       = var.zone_names[count.index]
  map_public_ip_on_launch = "false"

  tags = merge(
    { Name = "${var.vpc_name}-private-${var.zone_names[count.index]}", },
    var.extra_tags
  )
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    { Name = var.vpc_name, },
    var.extra_tags
  )
}

resource "aws_eip" "nat" {
  count = length(var.zone_names)

  tags = merge(
    { Name = "${var.vpc_name}-${var.zone_names[count.index]}", },
    var.extra_tags
  )
}

resource "aws_nat_gateway" "private" {
  count         = length(var.zone_names)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.gw]

  tags = merge(
    { Name = "${var.vpc_name}-${var.zone_names[count.index]}", },
    var.extra_tags
  )
}

resource "aws_route_table" "public" {
  vpc_id     = aws_vpc.main.id
  depends_on = [aws_internet_gateway.gw]

  tags = merge(
    { Name = "${var.vpc_name}-public", },
    var.extra_tags
  )
}

resource "aws_route" "public-default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_route_table" "nat" {
  count  = length(var.zone_names)
  vpc_id = aws_vpc.main.id

  tags = merge(
    { Name = "${var.vpc_name}-private-${var.zone_names[count.index]}", },
    var.extra_tags
  )
}

resource "aws_route" "nat-default" {
  count                  = length(var.zone_names)
  route_table_id         = aws_route_table.nat[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.private[count.index].id
}

resource "aws_route_table" "services" {
  count  = length(var.zone_names)
  vpc_id = aws_vpc.main.id

  tags = merge(
    { Name = "${var.vpc_name}-services-${var.zone_names[count.index]}", },
    var.extra_tags
  )
}

resource "aws_route" "services-default" {
  count                  = length(var.zone_names)
  route_table_id         = aws_route_table.services[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.private[count.index].id
}

resource "aws_route_table_association" "public" {
  count          = length(var.zone_names)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.zone_names)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.nat[count.index].id
}

resource "aws_route_table_association" "services" {
  count          = length(var.zone_names)
  subnet_id      = aws_subnet.services[count.index].id
  route_table_id = aws_route_table.services[count.index].id
}

# Default network ACL is permissive and applies to Public subnets only
# Hosts running within Public subnets are secured with Security Groups
resource "aws_default_network_acl" "main_vpc" {
  default_network_acl_id = aws_vpc.main.default_network_acl_id

  subnet_ids = concat(aws_subnet.public.*.id)

  egress {
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    icmp_code  = 0
    icmp_type  = 0
    protocol   = "-1"
    rule_no    = 100
    to_port    = 0
  }

  ingress {
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    icmp_code  = 0
    icmp_type  = 0
    protocol   = "-1"
    rule_no    = 100
    to_port    = 0
  }

  tags = merge(
    { Name = var.vpc_name, },
    var.extra_tags
  )
}

# Network ACL for internal subnets. It is designed to serve as additional
# security level to mitigate situations when Security Groups get too open
# and route tables allow  external  traffic in or out  by  mistake
# Explicit use of Network ACL Rule resources allows to extend rule set if
# required, e.g. it allows to control VPN traffic, see `vpn.tf`
resource "aws_network_acl" "internal" {
  vpc_id = aws_vpc.main.id

  subnet_ids = concat(aws_subnet.private.*.id, aws_subnet.services.*.id)

  tags = merge(
    { Name = "${var.vpc_name}-internal-subnets", },
    var.extra_tags
  )
}

resource "aws_network_acl_rule" "egress_vpn" {
  network_acl_id = aws_network_acl.internal.id
  rule_number    = 100
  egress         = true
  protocol       = "all"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "ingress_vpn_vpc" {
  network_acl_id = aws_network_acl.internal.id
  rule_number    = 100
  protocol       = "all"
  rule_action    = "allow"
  cidr_block     = aws_vpc.main.cidr_block
}

resource "aws_network_acl_rule" "ingress_vpn_nat_tcp" {
  network_acl_id = aws_network_acl.internal.id
  rule_number    = 32010
  from_port      = 1025
  to_port        = 65535
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "ingress_vpn_nat_udp" {
  network_acl_id = aws_network_acl.internal.id
  rule_number    = 32020
  from_port      = 1025
  to_port        = 65535
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

## Optional resources

resource "aws_route" "peers_public" {
  count                  = length(var.vpn_networks)
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = var.vpn_networks[count.index]
  transit_gateway_id     = var.vpn_transit_gw
  depends_on             = [aws_route_table.public]
}

resource "aws_route" "peers_private" {
  count                  = length(var.vpn_networks) * length(aws_route_table.nat.*.id)
  route_table_id         = aws_route_table.nat[count.index % length(aws_route_table.nat.*.id)].id
  destination_cidr_block = var.vpn_networks[floor(count.index / length(aws_route_table.nat.*.id))]
  transit_gateway_id     = var.vpn_transit_gw
  depends_on             = [aws_route_table.nat[0]]
}

resource "aws_route" "peers_services" {
  count                  = length(aws_route_table.services) * length(var.vpn_networks)
  route_table_id         = aws_route_table.services[floor(count.index / 3)].id
  destination_cidr_block = var.vpn_networks[count.index % 3]
  transit_gateway_id     = var.vpn_transit_gw
  depends_on             = [aws_route_table.services]
}

resource "aws_network_acl_rule" "ingress_vpn" {
  count          = length(var.vpn_networks)
  network_acl_id = aws_network_acl.internal.id
  rule_number    = 1000 + 10 * count.index
  protocol       = "all"
  rule_action    = "allow"
  cidr_block     = var.vpn_networks[count.index]
}
