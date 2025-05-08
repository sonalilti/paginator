## Variables

variable "rds_allocated_storage" {
  description = "Unless it is expected to store millions of complex variables Admin won't require a lot of disk space for database"
  default     = 64
}

variable "rds_maximum_storage" {
  description = "Most likely database will stay within 64GB but for high loads there must be some room to scale"
  default     = 256
}

variable "rds_engine_version" {
  description = "Minimum supported since Admin 0.8.0"
  default     = "10.6"
}

variable "rds_instance_class" {
  description = "For testing environments can be scaled down to db.t2.micro"
  default     = "db.t3.medium"
}

variable "rds_username" {
  description = "RDS Admin user, implement a call to data source of your choice instead of plain variable for added security"
  default     = "sdadmin"
}

variable "rds_password" {
  description = "RDS Admin password. Required. Please provide the password via terraform.tfvars or implement a call to data source of your choice instead of plain variable for added security."
}

variable "rds_db_name" {
  description = "The name of the database to create when the DB instance is created."
  default     = "nucleus"
}

## Implementation

resource "aws_db_subnet_group" "rds" {
  name       = "${var.vpc_name}-rds"
  subnet_ids = tolist(aws_subnet.services.*.id)

  tags = merge(
    { Name = "${var.vpc_name}-rds", },
    var.extra_tags
  )
}

# You may wish to edit this resource.

resource "aws_db_parameter_group" "main" {
  name        = "${replace(var.vpc_name, ".", "")}-mariadb106"
  description = "Parameter group for hmklabs-sp-stage-nucleus-db"
  family      = "mariadb10.6"

  parameter {
    apply_method = "immediate"
    name         = "long_query_time"
    value        = "5"
  }
  parameter {
    apply_method = "immediate"
    name         = "slow_query_log"
    value        = "1"
  }
  parameter {
    apply_method = "immediate"
    name         = "log_output"
    value        = "FILE"
  }
  parameter {
    apply_method = "immediate"
    name         = "innodb_flush_log_at_trx_commit"
    value        = "2"
  }
}

resource "aws_db_instance" "main" {
  identifier = replace(var.vpc_name, ".", "")

  engine         = "mariadb"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class
  multi_az       = true

  storage_type          = "gp3"
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_maximum_storage
  parameter_group_name  = "${replace(var.vpc_name, ".", "")}-mariadb106"
  storage_encrypted     = true
  kms_key_id            = data.aws_kms_key.current.arn

  apply_immediately           = var.apply_immediately
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = var.allow_major_version_upgrade

  db_name  = var.rds_db_name
  username = var.rds_username
  password = var.rds_password

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  depends_on             = [aws_db_parameter_group.main]
  vpc_security_group_ids = [aws_security_group.rds.id]

  tags = merge(
    { Name = "${var.vpc_name}-nucleus", },
    var.extra_tags
  )

  lifecycle {
    ignore_changes = [engine_version]
  }
}
