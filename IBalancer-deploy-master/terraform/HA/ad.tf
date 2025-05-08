## Variables

variable "ad_zone" {
  description = "Active Directory DNS zone"
  type        = string
}

variable "dc_instance_ami" {
  description = "Microsoft Windows Server 2022 Full Locale English AMI provided by Amazon in us-east-1"
  type        = string
  default     = "ami-0069eac59d05ae12b"
}

variable "dc_instance_type" {
  description = "DC instance does not have to be large and powerful. Instance can be just large enough to meet the minimum hardware requirements."
  type        = string
  default     = "c5.large"
}

variable "dc_instance_disk_size" {
  description = "Minimum hardware requirements plus some extra space for Windows Update to work."
  default     = 64
}

variable "dc_instance_disk_type" {
  description = "Valid values include standard, gp2, gp3, io1, io2, sc1, or st1"
  type        = string
  default     = "gp3"
}

## Implementation

resource "aws_instance" "dc0" {
  ami               = var.dc_instance_ami
  key_name          = "${var.vpc_name}-key"
  subnet_id         = aws_subnet.services[0].id
  instance_type     = var.dc_instance_type
  get_password_data = true

  credit_specification { cpu_credits = "unlimited" }

  iam_instance_profile = aws_iam_instance_profile.sd-ec2-generic.name
  depends_on           = [aws_iam_instance_profile.sd-ec2-generic]

  vpc_security_group_ids = [
    aws_security_group.windows.id,
    aws_security_group.sg_exceptions.id,
    aws_security_group.services.id
  ]

  private_ip = cidrhost(aws_subnet.services[0].cidr_block, 22)

  root_block_device {
    volume_type           = var.dc_instance_disk_type
    volume_size           = var.dc_instance_disk_size
    delete_on_termination = false
    encrypted             = true
  }

  volume_tags = {
    Name = "dc0.in.${var.vpc_name}"
  }

  tags = merge(
    { Name = "dc0.in.${var.vpc_name}", },
    { DLMBackupTarget = var.vpc_name },
    var.ec2_extra_tags,
    var.extra_tags
  )
}

resource "aws_instance" "dc1" {
  ami               = var.dc_instance_ami
  key_name          = "${var.vpc_name}-key"
  subnet_id         = aws_subnet.services[2].id
  instance_type     = var.dc_instance_type
  get_password_data = true

  credit_specification { cpu_credits = "unlimited" }

  iam_instance_profile = aws_iam_instance_profile.sd-ec2-generic.name
  depends_on           = [aws_iam_instance_profile.sd-ec2-generic]

  vpc_security_group_ids = [
    aws_security_group.windows.id,
    aws_security_group.sg_exceptions.id,
    aws_security_group.services.id
  ]

  private_ip = cidrhost(aws_subnet.services[2].cidr_block, 8)

  root_block_device {
    volume_type           = var.dc_instance_disk_type
    volume_size           = var.dc_instance_disk_size
    delete_on_termination = false
    encrypted             = true
  }

  volume_tags = {
    Name = "dc1.in.${var.vpc_name}"
  }

  tags = merge(
    { Name = "dc1.in.${var.vpc_name}", },
    { DLMBackupTarget = var.vpc_name },
    var.ec2_extra_tags,
    var.extra_tags
  )
}

resource "aws_vpc_dhcp_options" "discovery" {
  domain_name = var.ad_zone
  domain_name_servers = [
    aws_instance.dc0.private_ip,
    aws_instance.dc1.private_ip
  ]

  tags = merge(
    { Name = var.vpc_name, },
    var.extra_tags
  )
}
