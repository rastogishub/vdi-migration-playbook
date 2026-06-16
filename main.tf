# =============================================================
# VDI Migration Playbook - AWS EUC Infrastructure
# Author : Shubham Rastogi
# Covers AWS WorkSpaces & AWS WorkSpaces Applications (formerly AWS AppStream 2.0)
# Based on Citrix → AWS migration (100+ apps migrated)
# =============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "tfstate-vdi-migration"
    key            = "vdi/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "tfstate-lock"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

# ------------------------------------------------------------------
# VPC for AWS EUC workloads
# ------------------------------------------------------------------
resource "aws_vpc" "euc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "vpc-euc-${var.environment}" }
}

resource "aws_subnet" "workspaces_a" {
  vpc_id            = aws_vpc.euc.id
  cidr_block        = var.workspaces_subnet_a_cidr
  availability_zone = "${var.aws_region}a"
  tags              = { Name = "snet-workspaces-${var.environment}-a" }
}

resource "aws_subnet" "workspaces_b" {
  vpc_id            = aws_vpc.euc.id
  cidr_block        = var.workspaces_subnet_b_cidr
  availability_zone = "${var.aws_region}b"
  tags              = { Name = "snet-workspaces-${var.environment}-b" }
}

resource "aws_subnet" "appstream" {
  vpc_id            = aws_vpc.euc.id
  cidr_block        = var.appstream_subnet_cidr
  availability_zone = "${var.aws_region}a"
  tags              = { Name = "snet-appstream-${var.environment}-a" }
}

# ------------------------------------------------------------------
# Internet Gateway & NAT Gateway (AppStream needs outbound internet)
# ------------------------------------------------------------------
resource "aws_internet_gateway" "euc" {
  vpc_id = aws_vpc.euc.id
  tags   = { Name = "igw-euc-${var.environment}" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "eip-nat-euc-${var.environment}" }
}

resource "aws_nat_gateway" "euc" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.workspaces_a.id
  tags          = { Name = "nat-euc-${var.environment}" }
  depends_on    = [aws_internet_gateway.euc]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.euc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.euc.id
  }
  tags = { Name = "rt-private-euc-${var.environment}" }
}

resource "aws_route_table_association" "appstream" {
  subnet_id      = aws_subnet.appstream.id
  route_table_id = aws_route_table.private.id
}

# ------------------------------------------------------------------
# Security Groups
# ------------------------------------------------------------------
resource "aws_security_group" "workspaces" {
  name        = "sg-workspaces-${var.environment}"
  description = "Security group for AWS WorkSpaces"
  vpc_id      = aws_vpc.euc.id

  ingress {
    description = "PCoIP from corporate"
    from_port   = 4172
    to_port     = 4172
    protocol    = "tcp"
    cidr_blocks = var.corporate_cidr_ranges
  }

  ingress {
    description = "PCoIP UDP from corporate"
    from_port   = 4172
    to_port     = 4172
    protocol    = "udp"
    cidr_blocks = var.corporate_cidr_ranges
  }

  ingress {
    description = "WSP from corporate"
    from_port   = 4195
    to_port     = 4195
    protocol    = "tcp"
    cidr_blocks = var.corporate_cidr_ranges
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-workspaces-${var.environment}" }
}

resource "aws_security_group" "appstream" {
  name        = "sg-appstream-${var.environment}"
  description = "Security group for AppStream 2.0 fleet"
  vpc_id      = aws_vpc.euc.id

  egress {
    description = "HTTPS outbound for AppStream service"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-appstream-${var.environment}" }
}

# ------------------------------------------------------------------
# AWS WorkSpaces Directory (AD-joined)
# ------------------------------------------------------------------
resource "aws_workspaces_directory" "main" {
  directory_id = var.directory_id
  subnet_ids   = [aws_subnet.workspaces_a.id, aws_subnet.workspaces_b.id]

  self_service_permissions {
    change_compute_type  = false
    increase_volume_size = false
    rebuild_workspace    = true
    restart_workspace    = true
    switch_running_mode  = false
  }

  workspace_access_properties {
    device_type_android    = "ALLOW"
    device_type_chromeos   = "ALLOW"
    device_type_ios        = "ALLOW"
    device_type_linux      = "DENY"
    device_type_osx        = "ALLOW"
    device_type_web        = "ALLOW"
    device_type_windows    = "ALLOW"
    device_type_zeroclient = "DENY"
  }

  workspace_creation_properties {
    enable_internet_access              = false
    enable_maintenance_mode             = true
    user_enabled_as_local_administrator = false
  }

  tags = local.common_tags
}

# ------------------------------------------------------------------
# AppStream 2.0 Fleet (replaces Citrix published apps)
# ------------------------------------------------------------------
resource "aws_appstream_fleet" "published_apps" {
  name          = "fleet-published-apps-${var.environment}"
  instance_type = var.appstream_instance_type

  compute_capacity {
    desired_instances = var.appstream_desired_instances
  }

  vpc_config {
    subnet_ids         = [aws_subnet.appstream.id]
    security_group_ids = [aws_security_group.appstream.id]
  }

  image_name                         = var.appstream_image_name
  fleet_type                         = "ON_DEMAND"
  max_user_duration_in_seconds       = 57600   # 16 hours
  disconnect_timeout_in_seconds      = 900     # 15 minutes
  idle_disconnect_timeout_in_seconds = 900

  enable_default_internet_access = false

  domain_join_info {
    directory_name                         = var.ad_domain_name
    organizational_unit_distinguished_name = var.appstream_ou_dn
  }

  tags = merge(local.common_tags, {
    Purpose = "CitrixAppsMigration"
  })
}

resource "aws_appstream_stack" "published_apps" {
  name         = "stack-published-apps-${var.environment}"
  display_name = "Published Applications"
  description  = "Migrated Citrix published applications"

  storage_connectors {
    connector_type = "HOMEFOLDERS"
  }

  user_settings {
    action     = "CLIPBOARD_COPY_FROM_LOCAL_DEVICE"
    permission = "ENABLED"
  }

  user_settings {
    action     = "CLIPBOARD_COPY_TO_LOCAL_DEVICE"
    permission = "ENABLED"
  }

  user_settings {
    action     = "FILE_UPLOAD"
    permission = "ENABLED"
  }

  user_settings {
    action     = "FILE_DOWNLOAD"
    permission = "ENABLED"
  }

  application_settings {
    enabled        = true
    settings_group = "published-apps-${var.environment}"
  }

  tags = local.common_tags
}

resource "aws_appstream_fleet_stack_association" "main" {
  fleet_name = aws_appstream_fleet.published_apps.name
  stack_name = aws_appstream_stack.published_apps.name
}

# ------------------------------------------------------------------
# Locals
# ------------------------------------------------------------------
locals {
  common_tags = {
    Environment = var.environment
    Project     = "VDI-Migration"
    ManagedBy   = "Terraform"
    Owner       = var.team_owner
    CostCenter  = var.cost_center
  }
}
