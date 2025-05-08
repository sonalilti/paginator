## Variales

variable "fsx_storage_size" {
  description = "Storage capacity of the file system in Gigabytes"
  default     = 1024
}

variable "fsx_storage_throughput" {
  description = "Storage throughput in Megabytes per second"
  default     = 128
}

variable "svm_ad_fqdn" {
  description = "Fully qualified domain name of the self-managed AD directory"
  type        = string
}

variable "svm_ad_username" {
  description = "User name for the service account"
  type        = string
}

variable "svm_ad_password" {
  description = "Service account password"
  type        = string
}

variable "fsx_admin_password" {
  description = "The ONTAP administrative password for the fsxadmin user"
  type        = string
}

variable "fsx_vol_share_name" {
  description = "Share and Junction Path Name"
  type        = string
  default     = "Shared"
}

variable "fsx_vol_size" {
  description = "Volume size in Megabytes"
  default     = 1047552
}

variable "fsx_vol_storage_efficiency" {
  description = "Set to true to enable deduplication, compression, and compaction storage efficiency features on the volume"
  type        = bool
  default     = true
}

variable "fsx_vol_tiering_policy_name" {
  description = "Tiering policy for moving data to the capacity pool storage"
  type        = string
  default     = "AUTO"
}

variable "fsx_vol_tiering_policy_cooldown" {
  description = "Days that user data in a volume must remain inactive before being moved to the capacity pool"
  default     = 2
}

variable "fsx_automatic_backup_retention_days" {
  description = "The number of days to retain automatic backups. Minimum of 0 and maximum of 35."
  default     = 5
}

## Implementation

resource "aws_fsx_ontap_file_system" "main" {
  storage_capacity    = var.fsx_storage_size
  subnet_ids          = [aws_subnet.services[0].id, aws_subnet.services[1].id]
  deployment_type     = "MULTI_AZ_1"
  throughput_capacity = var.fsx_storage_throughput
  preferred_subnet_id = aws_subnet.services[0].id
  fsx_admin_password  = var.fsx_admin_password

  automatic_backup_retention_days = var.fsx_automatic_backup_retention_days

  security_group_ids = [
    aws_security_group.ontap_fsx_tcp.id,
    aws_security_group.ontap_fsx_udp.id
  ]

  route_table_ids = concat(aws_route_table.services.*.id, aws_route_table.nat.*.id)

  tags = merge(
    { Name = var.svm_ad_fqdn, },
    var.extra_tags
  )
}

resource "aws_fsx_ontap_storage_virtual_machine" "nucleus" {
  file_system_id = aws_fsx_ontap_file_system.main.id
  name           = "netapp.${var.svm_ad_fqdn}"

  active_directory_configuration {
    netbios_name = "netapp"
    self_managed_active_directory_configuration {
      domain_name = var.svm_ad_fqdn
      password    = var.svm_ad_password
      username    = var.svm_ad_username
      dns_ips = [
        aws_instance.dc0.private_ip,
        aws_instance.dc1.private_ip
      ]
    }
  }

  tags = merge(
    { Name = var.vpc_name, },
    var.extra_tags
  )

  # AWS API reports domain name in upper case and confuses Terraform. Ignore.
  lifecycle {
    ignore_changes = [active_directory_configuration]
  }
}

resource "aws_fsx_ontap_volume" "shared" {
  name                       = var.fsx_vol_share_name
  junction_path              = "/${var.fsx_vol_share_name}"
  security_style             = "MIXED"
  size_in_megabytes          = var.fsx_vol_size
  storage_efficiency_enabled = var.fsx_vol_storage_efficiency
  storage_virtual_machine_id = aws_fsx_ontap_storage_virtual_machine.nucleus.id

  tiering_policy {
    name           = var.fsx_vol_tiering_policy_name
    cooling_period = var.fsx_vol_tiering_policy_cooldown
  }

  tags = merge(
    { Name = var.vpc_name, },
    var.extra_tags
  )
}

resource "aws_network_acl_rule" "ingress_ontap_fsx" {
  network_acl_id = aws_network_acl.internal.id
  rule_number    = 2000
  protocol       = "all"
  rule_action    = "allow"
  cidr_block     = aws_fsx_ontap_file_system.main.endpoint_ip_address_range
}

resource "aws_security_group" "ontap_fsx_tcp" {
  name        = "ONTAP FSx TCP"
  description = "ONTAP FSx file system access, TCP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Domain Controllers"
    cidr_blocks = formatlist("%s/32", [aws_instance.dc0.private_ip, aws_instance.dc1.private_ip])
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "ICMP"
    description = "Internet Control Message Protocol"
    cidr_blocks = concat(aws_subnet.private.*.cidr_block, aws_subnet.services.*.cidr_block)
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    description = "SSH access to the IP address of the cluster management LIF or a node management LIF"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 111
    to_port     = 111
    protocol    = "TCP"
    description = "Remote procedure call for NFS"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 135
    to_port     = 135
    protocol    = "TCP"
    description = "Remote procedure call for CIFS"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 139
    to_port     = 139
    protocol    = "TCP"
    description = "NetBIOS service session for CIFS"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 161
    to_port     = 162
    protocol    = "TCP"
    description = "Simple network management protocol (SNMP)"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    description = "ONTAP REST API access to the IP address of the cluster management LIF or an SVM management LIF"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 445
    to_port     = 445
    protocol    = "TCP"
    description = "Microsoft SMB/CIFS over TCP with NetBIOS framing"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 635
    to_port     = 635
    protocol    = "TCP"
    description = "NFS mount"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 749
    to_port     = 749
    protocol    = "TCP"
    description = "Kerberos"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "TCP"
    description = "NFS server daemon"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 3260
    to_port     = 3260
    protocol    = "TCP"
    description = "iSCSI access through the iSCSI data LIF"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 4045
    to_port     = 4045
    protocol    = "TCP"
    description = "NFS lock daemon"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 4046
    to_port     = 4046
    protocol    = "TCP"
    description = "Network status monitor for NFS"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 11104
    to_port     = 11104
    protocol    = "TCP"
    description = "Management of intercluster communication sessions for SnapMirror"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 11105
    to_port     = 11105
    protocol    = "TCP"
    description = "SnapMirror data transfer using intercluster LIFs"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ontap_fsx_udp" {
  name        = "ONTAP FSx UDP"
  description = "ONTAP FSx file system access, UDP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 111
    to_port     = 111
    protocol    = "UDP"
    description = "Remote procedure call for NFS"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 135
    to_port     = 135
    protocol    = "UDP"
    description = "Remote procedure call for CIFS"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 137
    to_port     = 137
    protocol    = "UDP"
    description = "NetBIOS name resolution for CIFS"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 139
    to_port     = 139
    protocol    = "UDP"
    description = "NetBIOS service session for CIFS"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 161
    to_port     = 162
    protocol    = "UDP"
    description = "Simple network management protocol (SNMP)"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 635
    to_port     = 635
    protocol    = "UDP"
    description = "NFS mount"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "UDP"
    description = "NFS server daemon"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 4045
    to_port     = 4045
    protocol    = "UDP"
    description = "NFS lock daemon"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 4046
    to_port     = 4046
    protocol    = "UDP"
    description = "Network status monitor for NFS"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  ingress {
    from_port   = 4049
    to_port     = 4049
    protocol    = "UDP"
    description = "NFS quota protocol"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "services_ontap" {
  cidr_blocks       = [aws_fsx_ontap_file_system.main.endpoint_ip_address_range]
  description       = "Allow access from ONTAP Endpoint IP address range"
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.services.id
}
