Here are the prerequisites to run this Terraform script:

## AWS Account Prerequisites

**1. AWS Organizations Management Account**
- You MUST run this from the **management account** (root account) of your AWS Organization
- If you don't have an organization yet, you'll need to create one first
- Cannot be run from a member account

**2. Account Requirements**
- Unique email addresses for each account you want to create
- Access to those email addresses (you'll receive verification emails)
- No existing Control Tower setup (this creates a new one)

## AWS Permissions Prerequisites

**3. Required IAM Permissions**
Your AWS credentials need extensive permissions including:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "organizations:*",
        "controltower:*",
        "sso:*",
        "cloudformation:*",
        "iam:*",
        "kms:*",
        "config:*",
        "cloudtrail:*",
        "s3:*",
        "sns:*"
      ],
      "Resource": "*"
    }
  ]
}
```

**4. Service-Linked Roles**
AWS will automatically create these, but your account needs permission to do so.

## Technical Prerequisites

**5. Terraform Installation**
```bash
# Install Terraform (version 1.0+)
# On macOS:
brew install terraform

# On Linux:
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Verify installation:
terraform version
```

**6. AWS CLI Configuration**
```bash
# Install AWS CLI
pip install awscli
# OR
brew install awscli

# Configure credentials
aws configure
# Enter your Access Key ID, Secret Access Key, Region, and Output format

# Verify you're using the management account:
aws sts get-caller-identity
aws organizations describe-organization
```

## Regional Prerequisites

**7. Supported Regions**
- Control Tower must be deployed in a supported home region
- Common choices: `us-east-1`, `us-west-2`, `eu-west-1`
- Check AWS documentation for the latest supported regions

## Configuration Prerequisites

**8. Create terraform.tfvars File**
```hcl
# terraform.tfvars
organization_name = "MyCompany"
control_tower_home_region = "us-east-1"
logging_account_email = "aws-logs+unique123@mycompany.com"
audit_account_email = "aws-audit+unique123@mycompany.com"
workload_account_emails = [
  "aws-dev+unique123@mycompany.com",
  "aws-staging+unique123@mycompany.com"
]
```

**Important Email Notes:**
- Each email must be globally unique across ALL AWS accounts
- Use email aliases (like `+unique123`) to create unique addresses
- You'll receive verification emails at these addresses

## Time and Resource Prerequisites

**9. Execution Time**
- Control Tower deployment takes **60-90 minutes**
- Don't interrupt the process once started
- Plan for a long coffee break!

**10. AWS Service Limits**
- Check your account limits for Organizations (default: 10 accounts)
- Request limit increases if needed

## Pre-Execution Checklist

Before running `terraform apply`, verify:

```bash
# 1. Check you're in the management account
aws sts get-caller-identity

# 2. Verify organization exists or will be created
aws organizations describe-organization

# 3. Check region is supported for Control Tower
aws controltower list-enabled-controls --region us-east-1

# 4. Validate Terraform configuration
terraform init
terraform validate
terraform plan
```

## Common Gotchas

**Email Issues:**
- Gmail users: Use `yourname+aws-log@gmail.com` format
- Corporate emails: Ensure IT allows AWS emails
- Typos in emails will cause account creation to fail

**Permissions Issues:**
- If you get permission errors, you're likely not in the management account
- Or your IAM user/role lacks required permissions

**Region Issues:**
- Some regions don't support Control Tower
- Stick to major regions like us-east-1 or us-west-2 for safety

**Existing Resources:**
- If you already have Control Tower set up, this script will conflict
- If you have existing Organizations structure, review carefully

## Quick Start Command Sequence

```bash
# 1. Clone/create the terraform files
# 2. Create terraform.tfvars with your email addresses
# 3. Initialize and run:

terraform init
terraform validate
terraform plan  # Review the plan carefully!
terraform apply  # This will take 60-90 minutes
```

The most critical prerequisite is having access to the AWS Organizations management account with sufficient permissions. Everything else can be installed or configured relatively quickly.

## Key Components

**Core Infrastructure:**
- AWS Organizations setup with required service access principals
- Control Tower Landing Zone with centralized logging and governance
- KMS encryption key for Control Tower services

**Account Structure:**
- Log Archive account for centralized logging
- Audit account for security monitoring
- Configurable workload accounts for different environments

**Organizational Units:**
- Security OU for core accounts
- Sandbox OU for development/testing
- Production OU for production workloads

**Governance & Compliance:**
- Service Control Policies (SCPs) for root access denial and MFA requirements
- Control Tower Controls (guardrails) for CloudTrail, Config, and IAM
- CloudFormation StackSets for baseline security configurations

## Usage Instructions

1. **Set up your variables** by creating a `terraform.tfvars` file:
```hcl
organization_name = "MyCompany"
control_tower_home_region = "us-east-1"
logging_account_email = "aws-logs@mycompany.com"
audit_account_email = "aws-audit@mycompany.com"
workload_account_emails = [
  "aws-dev@mycompany.com",
  "aws-staging@mycompany.com"
]
```

2. **Initialize and apply:**
```bash
terraform init
terraform plan
terraform apply
```

## Important Notes

- **Prerequisites:** You need to be using the management account of an AWS Organization
- **Email Requirements:** Each account needs a unique email address
- **Permissions:** Ensure your AWS credentials have sufficient permissions for Organizations and Control Tower
- **Time:** Control Tower deployment can take 60+ minutes
- **Regions:** The script sets up governance in us-east-1 and us-west-2 by default

The script follows AWS best practices and implements the multi-account governance structure that's central to the Control Tower workshop experience.
