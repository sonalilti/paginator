terraform {
  required_version = ">= 0.15"
}

## Terraform does not support variables in backend definition.
# It is also not recommended to create an s3 bucket for the state file with Terraform scripts.
# Create a bucket, make sure it is encrypted. Enable versioning (recommended).
# Then update the following definition accordingly.

terraform {
  backend "s3" {
    bucket = "tfstates"
    key    = "ha-stage.tfstate"
    region = "us-east-1"
  }
}

variable "ssh_pub" {}

variable "region" {
  description = "AWS region to use"
  type        = string
  default     = "us-east-1"
}

variable "zone_names" {
  description = "At least two Availability Zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1c"]
}

variable "auto_minor_version_upgrade" {
  description = "Enables automatic upgrades to new minor versions of AWS resources"
  type        = bool
  default     = true
}

variable "allow_major_version_upgrade" {
  description = "As above, major upgrades are promised to be transparent but this is for your discretion"
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Whether to reconfigure resources immediately or schedule changes for next maintenance window"
  type        = bool
  default     = false
}

variable "vpc_name" {
  type = string
}

variable "extra_tags" {
  description = "Tags to add to every entity in your environment"
  type        = map(any)
  default     = {}
}

resource "aws_key_pair" "main" {
  key_name   = "${var.vpc_name}-key"
  public_key = var.ssh_pub
}

provider "aws" {
  region = var.region
}
