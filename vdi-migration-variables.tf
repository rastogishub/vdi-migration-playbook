# =============================================================
# VDI Migration Playbook - Variables
# =============================================================

variable "aws_region" {
  description = "AWS region for EUC resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment: dev | uat | prod"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
}

variable "team_owner" {
  description = "Team responsible for this infrastructure"
  type        = string
  default     = "EUC-VDI-Team"
}

# Networking
variable "vpc_cidr" {
  description = "CIDR for the EUC VPC"
  type        = string
  default     = "172.16.0.0/16"
}

variable "workspaces_subnet_a_cidr" {
  description = "WorkSpaces subnet - AZ A"
  type        = string
  default     = "172.16.1.0/24"
}

variable "workspaces_subnet_b_cidr" {
  description = "WorkSpaces subnet - AZ B"
  type        = string
  default     = "172.16.2.0/24"
}

variable "appstream_subnet_cidr" {
  description = "AppStream 2.0 fleet subnet"
  type        = string
  default     = "172.16.3.0/24"
}

variable "corporate_cidr_ranges" {
  description = "Corporate IP ranges allowed to connect to WorkSpaces"
  type        = list(string)
}

# Directory
variable "directory_id" {
  description = "AWS Managed AD or AD Connector directory ID"
  type        = string
  sensitive   = true
}

variable "ad_domain_name" {
  description = "Active Directory domain name (e.g. corp.contoso.com)"
  type        = string
}

variable "appstream_ou_dn" {
  description = "OU distinguished name for AppStream fleet computers"
  type        = string
}

# AppStream
variable "appstream_instance_type" {
  description = "EC2 instance type for AppStream fleet"
  type        = string
  default     = "stream.standard.medium"
}

variable "appstream_desired_instances" {
  description = "Number of streaming instances to keep running"
  type        = number
  default     = 2
}

variable "appstream_image_name" {
  description = "Name of the AppStream image containing published applications"
  type        = string
}
