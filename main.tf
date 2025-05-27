# AWS Control Tower Workshop - Terraform Implementation
# This script implements the components covered in the AWS Control Tower workshop

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Variables
variable "organization_name" {
  description = "Name for the organization"
  type        = string
  default     = "MyOrganization"
}

variable "control_tower_home_region" {
  description = "Home region for Control Tower"
  type        = string
  default     = "us-east-1"
}

variable "logging_account_email" {
  description = "Email for the logging account"
  type        = string
}

variable "audit_account_email" {
  description = "Email for the audit account"
  type        = string
}

variable "workload_account_emails" {
  description = "List of email addresses for workload accounts"
  type        = list(string)
  default     = []
}

# Provider configuration
provider "aws" {
  region = var.control_tower_home_region
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Organizations setup (prerequisite for Control Tower)
resource "aws_organizations_organization" "main" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "sso.amazonaws.com",
    "controltower.amazonaws.com"
  ]
  
  feature_set = "ALL"
  
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY"
  ]
}

# Control Tower Landing Zone
resource "aws_controltower_landing_zone" "main" {
  manifest_json = jsonencode({
    accessManagement = {
      enabled = true
    },
    securityRoles = {
      accountId = data.aws_caller_identity.current.account_id
    },
    centralizedLogging = {
      accountId = aws_organizations_account.log_archive.id,
      configurations = {
        loggingBucket = {
          retentionDays = 365
        },
        accessLoggingBucket = {
          retentionDays = 3653
        },
        kmsKeyId = aws_kms_key.control_tower.arn
      },
      enabled = true
    },
    securityRoles = {
      accountId = aws_organizations_account.audit.id
    },
    governedRegions = [
      var.control_tower_home_region,
      "us-west-2"
    ],
    organizationStructure = {
      sandbox = {
        name = "Sandbox"
      },
      security = {
        name = "Security"
      },
      production = {
        name = "Production"
      }
    }
  })

  version = "3.3"
  
  depends_on = [
    aws_organizations_organization.main,
    aws_organizations_account.log_archive,
    aws_organizations_account.audit
  ]
}

# KMS Key for Control Tower
resource "aws_kms_key" "control_tower" {
  description             = "KMS key for Control Tower"
  deletion_window_in_days = 7
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "cloudtrail.amazonaws.com",
            "config.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "control_tower" {
  name          = "alias/control-tower-key"
  target_key_id = aws_kms_key.control_tower.key_id
}

# Core Accounts
resource "aws_organizations_account" "log_archive" {
  name                       = "Log Archive"
  email                      = var.logging_account_email
  iam_user_access_to_billing = "ALLOW"
  
  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "audit" {
  name                       = "Audit"
  email                      = var.audit_account_email
  iam_user_access_to_billing = "ALLOW"
  
  lifecycle {
    ignore_changes = [role_name]
  }
}

# Organizational Units
resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.main.roots[0].id
}

resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "Sandbox"
  parent_id = aws_organizations_organization.main.roots[0].id
}

resource "aws_organizations_organizational_unit" "production" {
  name      = "Production"
  parent_id = aws_organizations_organization.main.roots[0].id
}

# Move core accounts to Security OU
resource "aws_organizations_account" "log_archive_move" {
  count     = 1
  name      = aws_organizations_account.log_archive.name
  email     = aws_organizations_account.log_archive.email
  parent_id = aws_organizations_organizational_unit.security.id
  
  depends_on = [aws_organizations_account.log_archive]
  
  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "audit_move" {
  count     = 1
  name      = aws_organizations_account.audit.name
  email     = aws_organizations_account.audit.email
  parent_id = aws_organizations_organizational_unit.security.id
  
  depends_on = [aws_organizations_account.audit]
  
  lifecycle {
    ignore_changes = [role_name]
  }
}

# Workload Accounts
resource "aws_organizations_account" "workload" {
  count                      = length(var.workload_account_emails)
  name                       = "Workload-${count.index + 1}"
  email                      = var.workload_account_emails[count.index]
  parent_id                  = aws_organizations_organizational_unit.sandbox.id
  iam_user_access_to_billing = "ALLOW"
  
  lifecycle {
    ignore_changes = [role_name]
  }
}

# Service Control Policies
resource "aws_organizations_policy" "deny_root_access" {
  name        = "DenyRootAccess"
  description = "Deny root user access"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = "*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalType" = "Root"
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy" "require_mfa" {
  name        = "RequireMFA"
  description = "Require MFA for sensitive actions"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Deny"
        Action = [
          "iam:*",
          "organizations:*",
          "account:*"
        ]
        Resource = "*"
        Condition = {
          BoolIfExists = {
            "aws:MultiFactorAuthPresent" = "false"
          }
        }
      }
    ]
  })
}

# Attach SCPs
resource "aws_organizations_policy_attachment" "sandbox_deny_root" {
  policy_id = aws_organizations_policy.deny_root_access.id
  target_id = aws_organizations_organizational_unit.sandbox.id
}

resource "aws_organizations_policy_attachment" "production_require_mfa" {
  policy_id = aws_organizations_policy.require_mfa.id
  target_id = aws_organizations_organizational_unit.production.id
}

# Control Tower Controls (Guardrails)
resource "aws_controltower_control" "cloudtrail_enabled" {
  control_identifier = "arn:aws:controltower:${data.aws_region.current.name}::control/AWS-GR_CLOUDTRAIL_ENABLED"
  target_identifier  = aws_organizations_organizational_unit.production.arn
}

resource "aws_controltower_control" "config_enabled" {
  control_identifier = "arn:aws:controltower:${data.aws_region.current.name}::control/AWS-GR_CONFIG_ENABLED"
  target_identifier  = aws_organizations_organizational_unit.production.arn
}

resource "aws_controltower_control" "iam_user_mfa" {
  control_identifier = "arn:aws:controltower:${data.aws_region.current.name}::control/AWS-GR_IAM_USER_MFA_ENABLED"
  target_identifier  = aws_organizations_organizational_unit.sandbox.arn
}

# CloudFormation StackSets for additional governance
resource "aws_cloudformation_stack_set" "baseline_security" {
  name             = "baseline-security"
  description      = "Baseline security configuration for all accounts"
  permission_model = "SERVICE_MANAGED"
  
  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }
  
  managed_execution {
    active = true
  }
  
  operation_preferences {
    failure_tolerance_count = 0
    max_concurrent_count    = 10
    region_concurrency_type = "PARALLEL"
  }
  
  parameters = {
    NotificationEmail = var.audit_account_email
  }
  
  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description = "Baseline security configuration"
    Parameters = {
      NotificationEmail = {
        Type = "String"
        Description = "Email for security notifications"
      }
    }
    Resources = {
      SecurityTopic = {
        Type = "AWS::SNS::Topic"
        Properties = {
          TopicName = "SecurityAlerts"
          Subscription = [
            {
              Endpoint = { Ref = "NotificationEmail" }
              Protocol = "email"
            }
          ]
        }
      }
      ConfigRule = {
        Type = "AWS::Config::ConfigRule"
        Properties = {
          ConfigRuleName = "root-mfa-enabled"
          Description = "Checks whether MFA is enabled for root user"
          Source = {
            Owner = "AWS"
            SourceIdentifier = "ROOT_MFA_ENABLED"
          }
        }
      }
    }
    Outputs = {
      SecurityTopicArn = {
        Description = "ARN of the security alerts topic"
        Value = { Ref = "SecurityTopic" }
        Export = {
          Name = "SecurityTopicArn"
        }
      }
    }
  })
  
  depends_on = [aws_controltower_landing_zone.main]
}

# Deploy StackSet to all accounts
resource "aws_cloudformation_stack_set_instance" "baseline_security_deployment" {
  account_id         = data.aws_caller_identity.current.account_id
  region             = var.control_tower_home_region
  stack_set_name     = aws_cloudformation_stack_set.baseline_security.name
  operation_id       = "initial-deployment"
  
  deployment_targets {
    organizational_unit_ids = [
      aws_organizations_organizational_unit.sandbox.id,
      aws_organizations_organizational_unit.production.id
    ]
  }
  
  operation_preferences {
    failure_tolerance_count = 0
    max_concurrent_count    = 10
    region_concurrency_type = "PARALLEL"
  }
}

# Outputs
output "organization_id" {
  description = "The ID of the AWS Organization"
  value       = aws_organizations_organization.main.id
}

output "control_tower_home_region" {
  description = "Control Tower home region"
  value       = var.control_tower_home_region
}

output "log_archive_account_id" {
  description = "ID of the Log Archive account"
  value       = aws_organizations_account.log_archive.id
}

output "audit_account_id" {
  description = "ID of the Audit account"
  value       = aws_organizations_account.audit.id
}

output "organizational_units" {
  description = "Organizational Units created"
  value = {
    security    = aws_organizations_organizational_unit.security.id
    sandbox     = aws_organizations_organizational_unit.sandbox.id
    production  = aws_organizations_organizational_unit.production.id
  }
}

output "workload_account_ids" {
  description = "IDs of workload accounts"
  value       = aws_organizations_account.workload[*].id
}

output "kms_key_arn" {
  description = "ARN of the Control Tower KMS key"
  value       = aws_kms_key.control_tower.arn
}

# Example terraform.tfvars file content (commented out)
/*
# terraform.tfvars example
organization_name = "MyCompany"
control_tower_home_region = "us-east-1"
logging_account_email = "aws-logs@mycompany.com"
audit_account_email = "aws-audit@mycompany.com"
workload_account_emails = [
  "aws-dev@mycompany.com",
  "aws-staging@mycompany.com",
  "aws-prod@mycompany.com"
]
*/
