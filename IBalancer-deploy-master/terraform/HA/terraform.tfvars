ssh_pub = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDgCiQZ15W1x1LE1 ... put your public key here"

vpc_subnet = "172.17.0.0/20"

region     = "us-east-1"
zone_names = ["us-east-1a", "us-east-1c", "us-east-1d"] # us-east-1b: NO c5 instance type in this region!

vpc_name    = "stage.companyname.com"
route53_san = ["stage.companyname.com", "*.stage.companyname.com", "product.companyname.com", "*.product.companyname.com"]

apply_immediately = true

vpn_transit_gw = "" # Transit Gateway ID, only required if you actually plan to connect one
vpn_networks   = [] # Networks behind Transit Gateway ID, routes would get added only if this array is not empty

firewall_trusted = ["11.22.33.44/32", "55.66.77.88/29"] # Trusted hosts or subnets, this list can be empty

ec2_extra_tags = {
  ssm = "auto"
}

extra_tags = {
  env = "Stage"
  SLA = "not applicable"
}

alb_deregistration_delay = 30

dc_instance_ami = "ami-0069eac59d05ae12b" # Microsoft Windows Server 2022 Full Locale English AMI provided by Amazon, as an example
ad_zone         = "dc.companyname.com"

ims_instance_ami   = "ami-0dd239e274077553a" # Oracle Linux 9 update 3 for x86_64 HVM
ims_instance_type  = "c5.large"
ims_instance_count = 2

artisan_instance_ami   = "ami-0dd239e274077553a" # Oracle Linux 9 update 3 for x86_64 HVM
artisan_instance_count = 2
artisan_instance_type  = "t3.medium"

admin_instance_ami   = "ami-0dd239e274077553a" # Oracle Linux 9 update 3 for x86_64 HVM
admin_instance_type  = "c5.large"
admin_instance_count = 3

agent_instance_ami   = "ami-0069eac59d05ae12b" # The same Microsoft Windows Server 2022 Full as above, tested and known to work well
agent_instance_type  = "c5.xlarge"
agent_instance_count = 2

chrome_instance_ami   = "ami-0dd239e274077553a" # Oracle Linux 9 update 3 for x86_64 HVM
chrome_instance_type  = "c5.xlarge"
chrome_instance_count = 2

rds_instance_class         = "db.m5.xlarge"
rds_password               = "12345678" # Set to something secure or pull from a secret store
rds_allocated_storage      = 120
rds_maximum_storage        = 0
auto_minor_version_upgrade = false

ec_node_type = "cache.t2.medium"

# ONTAP FSx
svm_ad_fqdn            = "dc.companyname.com"
svm_ad_username        = "ontap_fsx"
svm_ad_password        = "12345678" # Set to something secure or pull from a secret store
fsx_admin_password     = "12345678" # Set to something secure or pull from a secret store
fsx_storage_throughput = 128
fsx_storage_size       = 1500
fsx_vol_size           = 1571328
