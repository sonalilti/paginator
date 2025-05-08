## Variables

variable "ec_node_type" {
  description = "The instance class to be used"
  type        = string
  default     = "cache.t2.small"
}

variable "ec_automatic_failover" {
  description = "Specifies whether a read-only replica will be automatically promoted to read/write primary if the existing primary fails"
  type        = bool
  default     = true
}

variable "ec_num_node_groups" {
  description = "Number of node groups (shards) for this Redis replication group"
  default     = 2
}

variable "ec_replicas_per_node_group" {
  description = "Number of replica nodes in each node group"
  default     = 1
}

variable "ec_at_rest_encryption" {
  description = "Whether to enable encryption at rest"
  type        = bool
  default     = true
}

variable "ec_engine_version" {
  description = "The version number of the cache engine to be used for the cache clusters in this replication group"
  type        = string
  default     = "6.x"
}

variable "ec_port" {
  description = "The port number on which each of the cache nodes will accept connections"
  default     = 6379
}


## Implementation

resource "aws_elasticache_subnet_group" "redis" {
  name        = replace(var.vpc_name, ".", "-")
  description = "${var.vpc_name}-redis"
  subnet_ids  = tolist(aws_subnet.services.*.id)
}

resource "aws_elasticache_replication_group" "redis" {
  automatic_failover_enabled = var.ec_automatic_failover
  replication_group_id       = replace(var.vpc_name, ".", "-")
  description                = "${var.vpc_name}-redis"
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis.id]
  at_rest_encryption_enabled = var.ec_at_rest_encryption
  node_type                  = var.ec_node_type
  engine_version             = var.ec_engine_version
  port                       = var.ec_port
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  num_node_groups            = var.ec_num_node_groups
  replicas_per_node_group    = var.ec_replicas_per_node_group

  tags = merge(
    { Name = "${var.vpc_name}-redis", },
    var.extra_tags
  )
}
