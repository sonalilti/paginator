## Variables

variable "admin_instance_ami" {
  description = "For Linux nodes only Oracle 9 currently supported. You can search public images on AWS EC2 Console for newer images. Oracle's owner id is 131827586825."
  type        = string
  default     = "ami-0dd239e274077553a"
}

variable "admin_instance_type" {
  description = "Recommended minimum instance count is 3. Can be scaled both in size and in number. Balanced approach is recommended as higher instance numbers are beneficial for redundancy. The best start when balancing is to increase the number of instances."
  type        = string
  default     = "c5.large"
}

variable "admin_instance_disk_size" {
  description = "Root volume size. In HA environment Admin nodes only serve WEB application. Large volume is not required."
  default     = 32
}

variable "admin_instance_count" {
  description = "Number of Admin instances. It is recommended to have at least one Admin node in each Zone. Maximum value is 27*zone count, i.e 81 for three zones, 108 for four zones, etc."
  default     = 3
}

variable "artisan_instance_ami" {
  description = "Oracle Linux 9 update 3 for x86_64 HVM"
  type        = string
  default     = "ami-0dd239e274077553a"
}

variable "artisan_instance_type" {
  description = "Artisan Scheduler does not require a lot of CPU power but launches numerous PHP workers. It requires at least 2 GiB of RAM."
  type        = string
  default     = "t2.medium"
}

variable "artisan_instance_disk_size" {
  description = "Scheduler does not require any disk space other than for storing it's source code."
  default     = 8
}

variable "artisan_instance_count" {
  description = "Recommended minimum instance count is 2. There is no need to keep lots of Schedulers and there is no need to scale resources. Add the third Scheduler instance for full Muti-AZ redundancy if you wish. Maximum value is 4*zone count, i.e 12 for three zones, 16 for four zones, etc."
  default     = 2
}

variable "ims_instance_ami" {
  description = "Oracle Linux 9 update 3 for x86_64 HVM"
  type        = string
  default     = "ami-0dd239e274077553a"
}

variable "ims_instance_type" {
  description = "IMS can be very CPU and disk-intensive when processing hi-res images. Make sure to use powerfull nodes."
  type        = string
  default     = "c5.large"
}

variable "ims_instance_disk_size" {
  description = "When processing hi-res images, Image Magick can create large temp files."
  default     = 120
}

variable "ims_instance_count" {
  description = "Recommended minimum instance count is 2. Add the third IMS instance for full Muti-AZ redundancy if you wish. Can be scaled both in size and in number. Balanced approach is recommended as higher instance numbers are beneficial for redundancy. The best start when balancing is to increase the number of instances. When it reaches 6, it is the right moment to start increasing instance sizes. Maximum value is 36*zone count, i.e 108 for three zones, 144 for four zones, etc."
  default     = 2
}

variable "agent_instance_ami" {
  description = "Microsoft Windows Server 2022 Full Locale English AMI provided by Amazon"
  type        = string
  default     = "ami-0069eac59d05ae12b"
}

variable "agent_instance_type" {
  description = "Agent instances require IDS license. This limits the possibility to add more instances. Scale by increasing instance sizes but please suggest installing at least one instance in each Zone."
  type        = string
  default     = "c5.xlarge"
}

variable "agent_instance_disk_size" {
  description = "IDS Agent caches Templates and performs render Jobs locally prior to sending results to the shared storage. Make sure to have enough disk space to avoid preliminarry cache purges."
  default     = 300
}

variable "agent_instance_count" {
  description = "Recommended minimum instance count is 2. Scale by increasing instance sizes but please suggest installing at least one instance in each Zone as soon as possible. Maximum value is 36*zone count, i.e 108 for three zones, 144 for four zones, etc."
  default     = 0
}

variable "chrome_instance_ami" {
  description = "Oracle Linux 9 update 3 for x86_64 HVM"
  type        = string
  default     = "ami-0dd239e274077553a"
}

variable "chrome_instance_type" {
  description = "Chrome instances can be CPU and disk-intensive. Make sure to use powerfull nodes."
  type        = string
  default     = "c5.xlarge"
}

variable "chrome_instance_disk_size" {
  description = "Chrome Agent caches Templates and performs render Jobs locally prior to sending results to the shared storage. Make sure to have enough disk space to avoid preliminarry cache purges."
  default     = 200
}

variable "chrome_instance_count" {
  description = "Recommended minimum instance count is 2. Add the third IMS instance for full Muti-AZ redundancy if you wish. Can be scaled both in size and in number. Balanced approach is recommended as higher instance numbers are beneficial for redundancy. The best start when balancing is to increase the number of instances. When it reaches 6, it is the right moment to start increasing instance sizes. Maximum value is 144*zone count, i.e 432 for three zones, 576 for four zones, etc. But maximum value is subject to change in the future if new agent type or auto-scaling groups are introduced."
  default     = 0
}

variable "ec2_extra_tags" {
  description = "Tags to add to every EC2 instance"
  type        = map(any)
  default = {
    "ssm" = "auto"
  }
}

variable "ec2_admin_extra_tags" {
  description = "Tags to add to every Admin EC2 instance"
  type        = map(any)
  default = {
    "role" = "admin"
  }
}

variable "ec2_ims_extra_tags" {
  description = "Tags to add to every IMS EC2 instance"
  type        = map(any)
  default = {
    "role" = "ims"
  }
}

variable "ec2_artisan_extra_tags" {
  description = "Tags to add to every Artisan EC2 instance"
  type        = map(any)
  default = {
    "role" = "artisan"
  }
}

variable "ec2_agent_extra_tags" {
  description = "Tags to add to every Agent EC2 instance"
  type        = map(any)
  default = {
    "role" = "agent"
  }
}

variable "ec2_chrome_extra_tags" {
  description = "Tags to add to every Chrome EC2 instance"
  type        = map(any)
  default = {
    "role" = "agent"
  }
}

variable "idsbootscript" {
  description = "Userdata script for use with SSM to set up IDS Agent nodes."
  type        = string
  default     = "ids-agent.userdata"
}

variable "chromebootscript" {
  description = "Userdata script for use with cloud-init to set up IDS Agent nodes."
  type        = string
  default     = "chrome-agent.userdata"
}

## Implementation

resource "aws_instance" "admin" {
  count         = var.admin_instance_count
  ami           = var.admin_instance_ami
  key_name      = "${var.vpc_name}-key"
  subnet_id     = aws_subnet.private[count.index % length(var.zone_names)].id
  instance_type = var.admin_instance_type

  credit_specification { cpu_credits = "unlimited" }

  iam_instance_profile = aws_iam_instance_profile.sd-ec2-generic.name
  depends_on           = [aws_iam_instance_profile.sd-ec2-generic]

  vpc_security_group_ids = [aws_security_group.linux.id, aws_security_group.admin.id, aws_security_group.tgs.id, aws_security_group.sg_exceptions.id]

  private_ip = cidrhost(aws_subnet.private[count.index % length(var.zone_names)].cidr_block, 5 + floor((count.index) / length(var.zone_names)))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.admin_instance_disk_size
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = data.aws_kms_key.current.arn
  }

  volume_tags = {
    Name = "admin${count.index}.in.${var.vpc_name}"
  }

  tags = merge(
    { Name = "admin${count.index}.in.${var.vpc_name}", },
    { DLMBackupTarget = var.vpc_name },
    var.ec2_extra_tags,
    var.ec2_admin_extra_tags,
    var.extra_tags
  )

  lifecycle {
    ignore_changes = [instance_type]
  }
}

resource "aws_instance" "artisan" {
  count         = var.artisan_instance_count
  ami           = var.artisan_instance_ami
  key_name      = "${var.vpc_name}-key"
  subnet_id     = aws_subnet.private[count.index % length(var.zone_names)].id
  instance_type = var.artisan_instance_type

  credit_specification { cpu_credits = "unlimited" }

  iam_instance_profile = aws_iam_instance_profile.sd-ec2-generic.name
  depends_on           = [aws_iam_instance_profile.sd-ec2-generic]

  vpc_security_group_ids = [aws_security_group.linux.id, aws_security_group.service.id, aws_security_group.sg_exceptions.id]

  private_ip = cidrhost(aws_subnet.private[count.index % length(var.zone_names)].cidr_block, 32 + floor((count.index) / length(var.zone_names)))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.artisan_instance_disk_size
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = data.aws_kms_key.current.arn
  }

  volume_tags = {
    Name = "artisan${count.index}.in.${var.vpc_name}"
  }

  tags = merge(
    { Name = "artisan${count.index}.in.${var.vpc_name}", },
    { DLMBackupTarget = var.vpc_name },
    var.ec2_extra_tags,
    var.ec2_artisan_extra_tags,
    var.extra_tags
  )
}

resource "aws_instance" "ims" {
  count         = var.ims_instance_count
  ami           = var.ims_instance_ami
  key_name      = "${var.vpc_name}-key"
  subnet_id     = aws_subnet.private[count.index % length(var.zone_names)].id
  instance_type = var.ims_instance_type

  credit_specification { cpu_credits = "unlimited" }

  iam_instance_profile = aws_iam_instance_profile.sd-ec2-generic.name
  depends_on           = [aws_iam_instance_profile.sd-ec2-generic]

  vpc_security_group_ids = [aws_security_group.linux.id, aws_security_group.service.id, aws_security_group.sg_exceptions.id]

  private_ip = cidrhost(aws_subnet.private[count.index % length(var.zone_names)].cidr_block, 36 + floor((count.index) / length(var.zone_names)))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.ims_instance_disk_size
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = data.aws_kms_key.current.arn
  }

  volume_tags = {
    Name = "ims${count.index}.in.${var.vpc_name}"
  }

  tags = merge(
    { Name = "ims${count.index}.in.${var.vpc_name}", },
    { DLMBackupTarget = var.vpc_name },
    var.ec2_extra_tags,
    var.ec2_ims_extra_tags,
    var.extra_tags
  )
}

resource "aws_instance" "agent" {
  count         = var.agent_instance_count
  ami           = var.agent_instance_ami
  key_name      = "${var.vpc_name}-key"
  subnet_id     = aws_subnet.private[count.index % length(var.zone_names)].id
  instance_type = var.agent_instance_type

  user_data = templatefile(var.idsbootscript, { number = count.index, vpcname = var.vpc_name })

  credit_specification { cpu_credits = "unlimited" }

  iam_instance_profile = aws_iam_instance_profile.sd-ec2-generic.name
  depends_on           = [aws_iam_instance_profile.sd-ec2-generic]

  vpc_security_group_ids = [aws_security_group.windows.id, aws_security_group.service.id, aws_security_group.sg_exceptions.id]

  private_ip = cidrhost(aws_subnet.private[count.index % length(var.zone_names)].cidr_block, 72 + floor((count.index) / length(var.zone_names)))

  get_password_data = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.agent_instance_disk_size
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = data.aws_kms_key.current.arn
  }

  lifecycle {
    ignore_changes = [user_data]
  }

  volume_tags = {
    Name = "agent${count.index}.in.${var.vpc_name}"
  }

  tags = merge(
    { Name = "agent${count.index}.in.${var.vpc_name}", },
    { DLMBackupTarget = var.vpc_name },
    var.ec2_extra_tags,
    var.ec2_agent_extra_tags,
    var.extra_tags
  )
}

resource "aws_instance" "chrome" {
  count         = var.chrome_instance_count
  ami           = var.chrome_instance_ami
  key_name      = "${var.vpc_name}-key"
  subnet_id     = aws_subnet.private[count.index % length(var.zone_names)].id
  instance_type = var.chrome_instance_type

  user_data = templatefile(var.chromebootscript, { number = count.index, local_zone = var.vpc_name })

  credit_specification { cpu_credits = "unlimited" }

  iam_instance_profile = aws_iam_instance_profile.sd-ec2-generic.name
  depends_on           = [aws_iam_instance_profile.sd-ec2-generic]

  vpc_security_group_ids = [aws_security_group.linux.id, aws_security_group.service.id, aws_security_group.sg_exceptions.id]

  private_ip = cidrhost(aws_subnet.private[count.index % length(var.zone_names)].cidr_block, 108 + floor((count.index) / length(var.zone_names)))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.chrome_instance_disk_size
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = data.aws_kms_key.current.arn
  }

  lifecycle {
    ignore_changes = [user_data]
  }

  volume_tags = {
    Name = "chrome${count.index}.in.${var.vpc_name}"
  }

  tags = merge(
    { Name = "chrome${count.index}.in.${var.vpc_name}", },
    { DLMBackupTarget = var.vpc_name },
    var.ec2_extra_tags,
    var.ec2_chrome_extra_tags,
    var.extra_tags
  )
}

resource "aws_iam_role" "sd-ec2-generic-role" {
  name        = "sd-${var.vpc_name}-ec2-generic-role"
  description = "Allows EC2 instances to call AWS services on your behalf"

  assume_role_policy = jsonencode(
    {
      Statement = [
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "ssm.amazonaws.com"
          }
        },
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "ec2.amazonaws.com"
          }
        },
      ]
      Version = "2012-10-17"
    }
  )

  tags = {
    Name = "sd-ec2-generic-role by Terraform"
  }
}

resource "aws_iam_instance_profile" "sd-ec2-generic" {
  name = "sd-${var.vpc_name}-ec2-generic"
  role = aws_iam_role.sd-ec2-generic-role.name
}

resource "aws_iam_role_policy_attachment" "ssm-managed-instance" {
  role       = aws_iam_role.sd-ec2-generic-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ssm-patch-assoc" {
  role       = aws_iam_role.sd-ec2-generic-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMPatchAssociation"
}
