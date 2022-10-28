variable "aws_region" {}
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "project_vpc_cidr" {}
variable "project_subnets" {}
variable "project_name" {}
variable "project_environment" {}
variable "instance_type" {}
variable "instance_ami" {}
variable "hosted_zone" {}

variable "frontend-webaccess-ports" {
  description = "port for frontend security groups"
  type        = set(string)
}

locals {
  common_tags = {
    project     = var.project_name,
    environment = var.project_environment
  }
}
