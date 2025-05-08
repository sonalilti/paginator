variable "ssh_pub" {}
variable "vpc_name" { default = "bridge" }
variable "vpc_subnet" { default = "172.32." }
variable "vpc_region" { default = "us-east-1" }
variable "vpc_zone" { default = "us-east-1a" }
variable "vpc_bridge_ami" { default = "ami-02eac2c0129f6376b" }
variable "vpn_peer" { default = "" }
variable "vpn_subnets" { default = [] }
variable "neighbours" { type = list }

provider "aws" {
  region  = var.vpc_region
}

resource "aws_vpc" "main" {
  cidr_block           = "${var.vpc_subnet}0.0/16"
  instance_tenancy     = "default"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"

  tags = {
    Name = "${var.vpc_name}"
  }
}

resource "aws_subnet" "bridge" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "${var.vpc_subnet}0.0/20"
  availability_zone       = var.vpc_zone
  map_public_ip_on_launch = "true"

  tags = {
    Name = "${var.vpc_name}-${var.vpc_zone}"
  }
}

resource "aws_security_group" "bridge" {
  name        = var.vpc_name
  description = "A trivial ruleset"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "ICMP"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Secure SHell"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_key_pair" "ansible" {
  key_name   = "${var.vpc_name}-ansible-key"
  public_key = var.ssh_pub
}

resource "aws_instance" "bridge" {
  ami           = var.vpc_bridge_ami
  key_name      = "${var.vpc_name}-ansible-key"
  instance_type = "t2.micro"

  subnet_id       = aws_subnet.bridge.id
  private_ip      = "${var.vpc_subnet}0.5"
  vpc_security_group_ids = [ aws_security_group.bridge.id ]

  root_block_device {
    volume_type = "standard"
    volume_size = "16"
    delete_on_termination = "true"
  }

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_vpn_gateway" "vpn_gateway" {
  vpc_id = aws_vpc.main.id
}

resource "aws_customer_gateway" "customer_gateway" {
  bgp_asn    = 65000
  ip_address = var.vpn_peer
  type       = "ipsec.1"
}

resource "aws_vpn_connection" "main" {
  type                = aws_customer_gateway.customer_gateway.type
  customer_gateway_id = aws_customer_gateway.customer_gateway.id
  transit_gateway_id  = aws_ec2_transit_gateway.bridge.id
  static_routes_only  = false

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_ec2_transit_gateway" "bridge" {
  description = "bridge"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_route_table" "bridge" {
  vpc_id     = aws_vpc.main.id
  depends_on = [aws_internet_gateway.gw]

  tags = {
    Name = "${var.vpc_name}-${var.vpc_zone}"
  }
}

resource "aws_route_table_association" "bridge" {
  subnet_id      = aws_subnet.bridge.id
  route_table_id = aws_route_table.bridge.id
}

resource "aws_vpn_gateway_route_propagation" "customer_subnets" {
  vpn_gateway_id  = aws_vpn_gateway.vpn_gateway.id
#  route_table_id = aws_ec2_transit_gateway_route.customer_subnets.id
  route_table_id  = aws_route_table.bridge.id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "bridge" {
  subnet_ids         = [aws_subnet.bridge.id]
  transit_gateway_id = aws_ec2_transit_gateway.bridge.id
  vpc_id             = aws_vpc.main.id

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_route" "default_gw" {
  route_table_id            = aws_route_table.bridge.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.gw.id
  depends_on                = [aws_route_table.bridge]
}

resource "aws_route" "vpn" {
  count                   = length(var.vpn_subnets)
  route_table_id          = aws_route_table.bridge.id
  destination_cidr_block  = var.vpn_subnets[count.index]
  transit_gateway_id      = aws_ec2_transit_gateway.bridge.id
  depends_on              = [aws_route_table.bridge]
}

resource "aws_ec2_transit_gateway_vpc_attachment" "neighbours" {
  count              = length(var.neighbours)
  subnet_ids         = lookup(var.neighbours[count.index], "net_ids")
  transit_gateway_id = aws_ec2_transit_gateway.bridge.id
  vpc_id             = lookup(var.neighbours[count.index], "vpc_id")

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_route" "neighbours" {
  count                   = length(var.neighbours)
  route_table_id          = aws_route_table.bridge.id
  destination_cidr_block  = lookup(var.neighbours[count.index], "prefix")
  transit_gateway_id      = aws_ec2_transit_gateway.bridge.id
  depends_on              = [aws_route_table.bridge]
}

  output "ipsec-secrets" {
    value = data.template_file.strongswan_secrets.rendered
    sensitive = true
}

  output "ipsec-conf" {
    value = data.template_file.strongswan_connections.rendered
    sensitive = true
}

  output "ipsec-bgp" { value = data.template_file.ipsec_bgp_peer.rendered }
  output "ipsec-csf" { value = data.template_file.ipsec_csf_allow.rendered }

  data "template_file" "strongswan_secrets" {
  template = <<IPSECSECRETS
|

${var.vpn_peer} ${aws_vpn_connection.main.tunnel1_address} : PSK "${aws_vpn_connection.main.tunnel1_preshared_key}"
${var.vpn_peer} ${aws_vpn_connection.main.tunnel2_address} : PSK "${aws_vpn_connection.main.tunnel2_preshared_key}"
  IPSECSECRETS
}

  data "template_file" "strongswan_connections" {
  template = <<IPSECCONF
|

conn tun-${var.vpc_name}-1
	auto=start
	left=%defaultroute
	leftid=${var.vpn_peer}
	right=${aws_vpn_connection.main.tunnel1_address}
	type=tunnel
	leftauth=psk
	rightauth=psk
	keyexchange=ikev1
	ike=aes256-sha256-modp2048
	ikelifetime=8h
	esp=aes256-sha256-modp2048
	lifetime=1h
	keyingtries=%forever
	leftsubnet=0.0.0.0/0
	rightsubnet=0.0.0.0/0
	dpddelay=10s
	dpdtimeout=30s
	dpdaction=restart
	mark=${replace(var.vpc_subnet, ".", "")}1
	leftupdown="/usr/libexec/strongswan/aws-updown.sh -ln tun-${var.vpc_name}-1 -ll ${aws_vpn_connection.main.tunnel1_cgw_inside_address}/30 -lr ${aws_vpn_connection.main.tunnel1_vgw_inside_address}/30 -m ${replace(var.vpc_subnet, ".", "")}1 -r ${aws_vpc.main.cidr_block}" # modify netmask to meet your requirements

conn tun-${var.vpc_name}-2
	auto=start
	left=%defaultroute
	leftid=${var.vpn_peer}
	right=${aws_vpn_connection.main.tunnel2_address}
	type=tunnel
	leftauth=psk
	rightauth=psk
	keyexchange=ikev1
	ike=aes256-sha256-modp2048
	ikelifetime=8h
	esp=aes256-sha256-modp2048
	lifetime=1h
	keyingtries=%forever
	leftsubnet=0.0.0.0/0
	rightsubnet=0.0.0.0/0
	dpddelay=10s
	dpdtimeout=30s
	dpdaction=restart
	mark=${replace(var.vpc_subnet, ".", "")}2
	leftupdown="/usr/libexec/strongswan/aws-updown.sh -ln tun-${var.vpc_name}-2 -ll ${aws_vpn_connection.main.tunnel2_cgw_inside_address}/30 -lr ${aws_vpn_connection.main.tunnel2_vgw_inside_address}/30 -m ${replace(var.vpc_subnet, ".", "")}2 -r ${aws_vpc.main.cidr_block}" # modify netmask to meet your requirements
  IPSECCONF
}

  data "template_file" "ipsec_bgp_peer" {
  template = <<IPSECBGP
!
router bgp 65000
 bgp router-id ${aws_vpn_connection.main.tunnel1_cgw_inside_address}
 neighbor ${aws_vpn_connection.main.tunnel1_vgw_inside_address} remote-as ${aws_vpn_connection.main.tunnel1_bgp_asn}
 neighbor ${aws_vpn_connection.main.tunnel1_vgw_inside_address} weight 1
 neighbor ${aws_vpn_connection.main.tunnel2_vgw_inside_address} remote-as ${aws_vpn_connection.main.tunnel2_bgp_asn}
 neighbor ${aws_vpn_connection.main.tunnel2_vgw_inside_address} weight 2
 !
 address-family ipv4 unicast
  redistribute connected
  redistribute static
  redistribute ospf
 exit-address-family
!
  IPSECBGP
}

  data "template_file" "ipsec_csf_allow" {
  template = <<IPSECCSF
|
csf.conf:
UDP_OUT = "20,21,53,113,123,500,4500"

csf.allow:
udp|in|d=4500|s=${aws_vpn_connection.main.tunnel1_address}	# AWS IPSEC peer
udp|in|d=4500|s=${aws_vpn_connection.main.tunnel2_address}	# AWS IPSEC peer
tcp|in|d=179|s=${aws_vpn_connection.main.tunnel1_vgw_inside_address}	# AWS BGP neighbour
tcp|in|d=179|s=${aws_vpn_connection.main.tunnel2_vgw_inside_address}	# AWS BGP neighbour

csfpost.sh:
/usr/sbin/iptables -t nat -A POSTROUTING -m comment --comment "Do not expose tunnel via BGP, SNAT source address instead" \
 	-s ${aws_vpn_connection.main.tunnel1_cgw_inside_address} ! -d ${aws_vpn_connection.main.tunnel1_vgw_inside_address} -j SNAT --to ${var.vpn_peer}
/usr/sbin/iptables -t nat -A POSTROUTING -m comment --comment "Do not expose tunnel via BGP, SNAT source address instead" \
 	-s ${aws_vpn_connection.main.tunnel2_cgw_inside_address} ! -d ${aws_vpn_connection.main.tunnel2_vgw_inside_address} -j SNAT --to ${var.vpn_peer}
  IPSECCSF
}
