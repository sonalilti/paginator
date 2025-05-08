# HA Deploy scripts 

Unlike `standalone` version, these scripts are not meant to be used as is out of the box. The reason is that conditions vary. For `standalone` scripts It is assumed that firewall rules (Security Groups) are enough to provide reasonable security, no IAM roles used, and network share access is only restricted by ip. This simplicity allows to set up a working environment with just modification of a couple of variables. For HA environment, these assumptions will not meet security regulations, so this set of Terraform scripts should be treated as a draft for adaptation. 

## Subjects for modifications 

You may want to adapt many aspects to suit your needs, but the following three are worth considering first. 

#### The most important topic is Active Directory. 

According to our internal tests the most powerful, versatile and solid (in terms of reformance) solution for storing files is Amazon FSx for NetApp ONTAP. It requires Active Directory in order to provide SMB/CIFS access to Indesign Server nodes. The requirement is strict, and AD cannot be substituted with AWS Directory Service's Simple AD, Samba 4 or anything else. It is either AWS Managed Microsoft AD or Microsoft Active Directory. 

Thus, available options are: 

* access an existing Microsoft Active Directory accessed via a Transit Gateway, 
* set up a pair of ec2 instances within HA VPC, 
* set up AWS Managed Microsoft AD. 

The first option has a significant drawback as AD is accessed remotely. If Transit Gateway fails for some reason, operation of HA environment would be interrupted. That's a single point of failure and it is best avoided. 

The second option is the most versatile and reliable. AD Controllers run within HA environment VPC, directly available and allow for full control. 

The third option has been tested and proved to work very well. But it also has its drawbacks. AWS Managed Microsoft AD has some restrictions as its operation is controlled by AWS and to ensure uninterrupted operation AWS keeps some permissions for itself. It is not cost-effective to set up a dedicated AWS Managed Microsoft AD just for single environment to govern access to FSx for a couple of service users. 

These draft Terraform scripts assume that the second option is chosen. It builds two ec2 Instances for Domain Controllers within HA environment VPC. If you wish to integrate with an existing Active Directory, you have an option to establish an inter-domain relationship over Transit Gateway with the existing domain. Any kind of relationship as these ec2 instances are two Windows Server nodes which provide all AD features. In this case loss of connectivity between domains won't severe HA environment operation as these two controllers will stay accessible. Of course, it means that Domain Controllers would have to be properly configured manually, but in most possible scenarios you would like to have full control over AD anyway. 

#### Secrets 

These draft scripts require usernames and passwords to be passed as variables. This approach is not safe as Terraform state file would keep secrets in open text. 

This problem can be somewhat leveraged by storing state file on an encrypted s3 bucket. See `providers.tf` file. But you would still have to carefully secure the `terraform.tfvars` file. This is a risk. 

The best way to address this problem is to review and edit scripts so that Terraform pulls all the secrets from a secure data source of your choice. There are numerous data sources supported by Terraform. We can't tell which one might suit your needs best, so you must implement this part as you wish. See `rds.tf` and `ontap.tf` files. Review other files and see if you would like to secure anything else. 

#### IAM Roles 

This is a powerful tool that can help automate lots of ec2 instance management tasks with the help of STS. It can also govern access to services and instances. Unfortunately, there is no way for us to tell how exactly you would like to utilize IAM Roles. Scenarios vary greatly. Please review the basic `sd-ec2-generic-role` definition in `ec2.tf` file and modify it to fit your requirements. 

## Files 

Read each file. All variable definitions have descriptions with explanations of their purpose, tips, and hints. 

#### providers.tf 

Main Terraform Provider config file. Controls Region, Availability Zone list and other high-level parameters. Review carefully. Most of the parameters can be controlled with variables but storage backend definition can only be configured directly. Edit to meet your requirements. 

#### VPC entities 

Everything is confined within a dedicated VPC: subnets, Security Groups etc. Four files control this "framework".  Consider these files as prerequisites for building everything else. 

vpc.tf 

VPC is subdivided into three sets of subnets. Each set is distributed over the assigned Availability Zones. It is recommended to assign three or four AZs for HA environment. Three is enough and the HA environment from which this draft has been assembled runs over three AZs. Four AZs should also work. 

Three subnet sets are: 

* "public" - only Load Balancer facing Internet claims addresses in this set of subnets 
* "services" - private subnets, AWS-managed services (RDS, ElastiCache, FSx etc) create their endpoints within this set 
* "private" - private subnets where ec2 instances reside 

This file also controls gateways, route tables, ACL rules and EIPs for gateways. 

sg.tf 

Security Group definitions. 

kms_key.tf 

KMS key for data encryption. 

route53.tf 

Route 53 Zone serves two purposes. 
It holds ACM certificate definition for use with ALBs, and its validation DNS records for automated certificate renewals. 
Another purpose is to publish AWS-managed service endpoint and ec2 instance addresses. 

The latter is not strictly required. For autodiscovery to work you would have to transfer DNS records to AD DNS anyway. You may wish to review service endpoint DNS record definitions for information purposes and disable those resources so that addresses are not exposed to the Internet. You can store these values in some data source for internal use instead. Modify as you see fit. However, it is recommended to keep "www" and "cert_validation" resources and delegate DNS resolutions for this subnet to Route 53. This way, you can check whether AWS requires updating these DNS records using Terraform and update them automatically if necessary. 

#### ad.tf 

Builds Active Directory instances. These instances are the only ones that reside in "services" subnets. Modify subnet indexes if required but make sure to use different indexes so that AD DCs reside in different AZs. 

#### AWS-managed services 

ontap.tf 
elasticache.tf 
rds.tf 

These scripts are straightforward and just place corresponding services into VPC. 

#### EC2 Instances 

ec2.tf 

Builds ec2 instances. Lots of instance parameters are controlled with variables. 

ids-agent.userdata 

A minimalistic userdata script for initial IDS Instance configuration. You can extend it to meet your requirements. 

> For automated AD joins you may wish to utilize either this script (probably unsafe as it would require username and password of a user with appropriate rights) or SSM. 

chrome-agent.userdata 

A userdata cloud-init tool config for initial Chrome Instance configuration. 

> Please note that Chrome instances have not yet been tested in an HA environment. This configuration is known good, but it does not consider the specifics of AD authorization, it will require tuning. 

#### alb.tf 

Installs Load Balancers 

#### terraform.tfvars 

An example set of customized variables with comments. 

## Deploy procedure 

The procedure for deploying a high availability environment must be performed in stages. There are dependencies and manual staps which should be taken at the right time. 
The procedure looks roughly like shown below. Depending on the changes you make to scripts, some steps in the sequence may differ. 

Prepare an empty directory for running Terraform. To keep track of the changes you make you may wish to use git and commit your successful changes from time to time. 

Copy the following files: 

providers.tf 
vpc.tf 
sg.tf 
kms_key.tf 
terraform.tfvars 

Edit the `terraform.tfvars` and `providers.tf` files to suit your needs. 

Make sure to edit backend definition in `providers.tf` file to point at an existing s3 bucket. 
Also set all "instance_count" variables in `terraform.tfvars` to zero for now. 

Initialize providers: 

``` 
terraform init 
``` 

If Terraform detects any problems with s3 backend configuration, this procedure will fail. Please make sure that s3 bucket exists and you have access. Rerun this command. 

After successful initialization, perform the following command: 

``` 
terraform plan 
``` 

It should be completed successfully. There will be some "Value for undeclared variable" warnings. This is OK: `terraform.tfvars` file mentions some variables declared in `tf` files that we will add later. Review the plan. As this is the initial build, it should only plan to add new resources. There should be no plans to change or destroy anything. 

Build resources: 

``` 
terraform apply 
``` 

Next, we'll start adding more resources. 

First build AD DCs. Copy the following files: 

ec2.tf 
ad.tf 
chrome-agent.userdata 
ids-agent.userdata 

The `ec2.tf` is a requirement for `ad.tf` but we only want AD DCs to be built for now. This is why we've previously set all "instance_count" variables in `terraform.tfvars` to zero. 

Rerun `terraform plan` and `terraform apply`. AD DCs should be built. 

This is where you must start adding your modifications. There is no way to connect to AD DC as it is only available within VPC. 

One way to gain access is to set up a Transit Gateway elsewhere, allow Terraform to add this TGW to HA environment with `vpn_transit_gw` and `vpn_networks` variables and apply. Make sure routing is configured appropriately on the "other side". 

Another way is to update `sd-ec2-generic-role` so that it allows RDP access via SSM. See https://docs.aws.amazon.com/systems-manager/latest/userguide/fleet-rdp.html for hints. If you take this route, you may also wish to do the same for ssh. You will need ssh access over SSM later. 

As soon as you gain RDP access, initialize Active Directory on DC instances. You must add at least a service account for ONTAP. See https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/self-manage-prereqs.html#ontap-ad-service-account-prereqs for instructions. 

Next copy `ontap.tf` file. Review this file, set up variables (and optionally data sources for secrets). 

Rerun `terraform plan` and `terraform apply`. 

If build fails, check error messages and ONTAP component statuses on AWS Console. There should be hints on why build failed. Most often it is due to missing service account permissions. Fix permissions, remove misconfigured ONTAP components with AWS Console, rerun Terraform. 

When done, add other missing files: `elasticache.tf`, `rds.tf` and `alb.tf`. Finalize build with `terraform apply`. These components do not depend on each other and should build all at once. But if something goes wrong, or if you edit these files to comply with your internal regulations, build them one by one, in any order you see fit. 

Add and build `route53.tf` at the last step. 

Once all components get built, we can add ec2 instances. Modify `terraform.tfvars`, update "instance_count" variables to the desired values. 

Rerun `terraform plan` and `terraform apply` for the last time. 

## Setting up Autodiscovery 

All ec2 instances receive DHCP options which instruct Operating systems to use DCs as DNS servers. We should add Autodiscovery DNS records to AD DNS zone. 

You need at least the following pair: 

* `NUCLEUS` - CNAME that points to *internal* load balancer's endpoint 
* `admin` - TXT record with the following content: `http://admin.<svm_ad_fqdn>` 

Where `<svm_ad_fqdn>` is the fully qualified domain name of the self-managed AD directory. I.e., with example `terraform.tfvars` values it would be `dc.companyname.com`. And full TXT record content would be `http://admin.dc.companyname.com`. 

For internal load balancer's endpoint you can check output of the following command: 

``` 
terraform state show aws_lb.alb-int 
``` 

`dns_name` property will show the endpoint. 

## ONTAP user mapping 

In a mixed environment Windows nodes access ONTAP with Windows user accounts and Linux nodes have two options to access storage. 

One option is to mount shared folder with `mount.cifs` helper available as part of `cifs-utils` package. Recent Linux kernels have full SMB v3.1.1 support and show perfect performance. This approach is easier as it allows to use the same credentials and avoid user mapping complications. There are barely any drawbacks to this method. 

Another option is to set up user mapping on ONTAP side and mount Linux instances over NFS. We can provide support if you choose this method. 

## Ansible 

There is no dedicated Ansible Playbook for HA environments. The same playbook  `playbooks/standalone.yml` can be used. 
Ansible Inventory also has the same structure. The "Ansible Inventory" instructions in the User Guide apply. 

The only difference is group assignment of inventory hosts. 

See the `examples/inventory.yml.example` file: 

``` 
  children: 
    standalone: 
      vars: 
	      ... excluded for brevity 
      hosts: 
        admin: 
          ansible_user: ec2-user 
          ansible_ssh_host: dev.mycompany.tld # Admin instance address, DNS or IP 
``` 

In this example the only Linux host goes into `standalone` group. This instructs Ansible to apply all the Roles to this single host. 

In an HA environment inventory should place available nodes into specialized groups: 

* `admin` for Admin nodes 
* `ims` for IMS nodes 
* `artisan` for Artisan scheduler nodes 
* `chromeagents` for Chrome Agent nodes 

This ensures that only relevant Roles get applied to the nodes. 

You can request assistance in preparing the inventory. We'll be glad to help.

