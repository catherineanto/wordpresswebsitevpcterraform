# vpc
#####
module "vpc" {
  source      = "/var/terraform/modules/vpc/"
  vpc_cidr    = var.project_vpc_cidr
  subnets     = var.project_subnets
  project     = var.project_name
  environment = var.project_environment
}

# bastion security group
#######################

module "sg-bastion"

  source         = "/var/terraform/modules/sgroup"
  project        = var.project_name
  environment    = var.project_environment
  sg_name        = "bastion"
  sg_description = "bastion security group"
  sg_vpc         = module.vpc.vpc_id
}

# bastion security group (production)
#####################################

resource "aws_security_group_rule" "bastion-production" {

  count             = var.project_environment == "prod" ? 1 : 0
  type              = "ingress"
  from_port         = "22"
  to_port           = "22"
  protocol          = "tcp"
  cidr_blocks       = ["202.170.207.220/32"]
  security_group_id = module.sg-bastion.sg_id


}

# bastion security group (development)
######################################

resource "aws_security_group_rule" "bastion-development" {

  count             = var.project_environment == "dev" ? 1 : 0
  type              = "ingress"
  from_port         = "22"
  to_port           = "22"
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = module.sg-bastion.sg_id
}


# frontend security group
#########################

module "sg-frontend" {

  source         = "/var/terraform/modules/sgroup"
  project        = var.project_name
  environment    = var.project_environment
  sg_name        = "frontend"
  sg_description = "frondend security group"
  sg_vpc         = module.vpc.vpc_id
}

# Frontend Security Group Rules (web-access)
############################################

resource "aws_security_group_rule" "frontend-web-access" {

  for_each          = var.frontend-webaccess-ports
  type              = "ingress"
  from_port         = each.key
  to_port           = each.key
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = module.sg-frontend.sg_id
}

# Frontend Security-Group Rules (remote-access)
###############################################

resource "aws_security_group_rule" "frontend-remote-access" {

  type                     = "ingress"
  from_port                = "22"
  to_port                  = "22"
  protocol                 = "tcp"
  source_security_group_id = module.sg-bastion.sg_id
  security_group_id        = module.sg-frontend.sg_id

}

# backend security group
########################

module "sg-backend" {

  source         = "/var/terraform/modules/sgroup"
  project        = var.project_name
  environment    = var.project_environment
  sg_name        = "backend"
  sg_description = "backend security group"
  sg_vpc         = module.vpc.vpc_id
}

# backend Security Group rule for ssh access
############################################

resource "aws_security_group_rule" "backend-ssh-access" {

  type                     = "ingress"
  from_port                = "22"
  to_port                  = "22"
  protocol                 = "tcp"
  source_security_group_id = module.sg-bastion.sg_id
  security_group_id        = module.sg-backend.sg_id

}

# backend Security-Group rule for db access
###########################################

resource "aws_security_group_rule" "backend-db-access" {

  type                     = "ingress"
  from_port                = "3306"
  to_port                  = "3306"
  protocol                 = "tcp"
  source_security_group_id = module.sg-frontend.sg_id
  security_group_id        = module.sg-backend.sg_id

}
# key pair creation
###################

#create key pair in the name "key" in the project directory.
resource "aws_key_pair" "mykey" {
  key_name   = "${var.project_name}-${var.project_environment}"
  public_key = file("key.pub")
  tags = {
    Name        = "${var.project_name}-${var.project_environment}",
    project     = var.project_name
    environment = var.project_environment
  }
}

# MySql
#####

variable "mysql_root_password" {}
variable "mysql_extra_username" {}
variable "mysql_extra_password" {}
variable "mysql_extra_dbname" {}
variable "mysql_extra_host" {}

# mariadb-installation userdata script
######################################

data "template_file" "mariadb_installation_userdata" {

  template = file("mariadb-userdata.tmpl")
  vars = {
    ROOT_PASSWORD     = var.mysql_root_password
    DATABASE_NAME     = var.mysql_extra_dbname
    DATABASE_USER     = var.mysql_extra_username
    DATABASE_PASSWORD = var.mysql_extra_password
    DATABASE_HOST     = var.mysql_extra_host
  }
}

# bastion instance
##################

resource "aws_instance" "bastion" {

  ami                    = var.instance_ami
  instance_type          = var.instance_type
  key_name               = aws_key_pair.mykey.id
  subnet_id              = module.vpc.subnet_public2_id
  vpc_security_group_ids = [module.sg-bastion.sg_id]
  tags = {
    Name        = "${var.project_name}-${var.project_environment}-bastion"
    project     = var.project_name,
    environment = var.project_environment
  }

}
# Backend Instance
##################

resource "aws_instance" "backend" {
  ami                    = var.instance_ami
  instance_type          = var.instance_type
  key_name               = aws_key_pair.mykey.id
  subnet_id              = module.vpc.subnet_private1_id
  vpc_security_group_ids = [module.sg-backend.sg_id]
  user_data              = data.template_file.mariadb_installation_userdata.rendered
  tags = {
    Name        = "${var.project_name}-${var.project_environment}-backend",
    project     = var.project_name,
    environment = var.project_environment
  }
  depends_on = [module.vpc.nat, module.vpc.rt_private, module.vpc.rt_association_private]
}

# frontend instance
###################

resource "aws_instance" "frontend" {
  ami                    = var.instance_ami
  instance_type          = var.instance_type
  key_name               = aws_key_pair.mykey.id
  subnet_id              = module.vpc.subnet_public1_id
  vpc_security_group_ids = [module.sg-frontend.sg_id]
  user_data              = data.template_file.frontend.rendered
  tags = {
    Name        = "${var.project_name}-${var.project_environment}-frontend",
    project     = var.project_name,
    environment = var.project_environment
  }
  depends_on = [aws_instance.backend]
}
#Template
##########

data "template_file" "frontend" {
  template = file("${path.module}/userdata.sh")
  vars = {
    localaddress = "${aws_instance.backend.private_ip}"
  }
}
# Zone record
#############

data "aws_route53_zone" "web" {
  name         = "catherineanto.tech"
  private_zone = false
}
resource "aws_route53_record" "wordpress" {
  zone_id = var.hosted_zone
  name    = "wordpress.catherineanto.tech"
  type    = "CNAME"
  ttl     = "5"
  records = [aws_instance.frontend.public_dns]
}
