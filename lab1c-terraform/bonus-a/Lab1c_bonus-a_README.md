# SEIR FOUNDATIONS

# LAB 1C BONUS A: Private EC2 + VPC Endpoints

## *Enhanced Socratic Q&A Guide with Step-by-Step Instructions*

---

> ⚠️ **CLI Note:** Multi-line commands use `\` for line continuation (Linux/Mac). If you're on Windows or prefer single-line commands, remove the `\` characters and put everything on one line.

> ⚠️ **PREREQUISITE:** Lab 1C core must be completed and verified before starting Bonus A. Your Terraform-deployed EC2 → RDS application must be working.

---

## Lab Overview

In Lab 1C core, your EC2 instance had a **public IP** and used the **internet** to reach AWS services. In Bonus A, you'll **remove the public IP entirely** and replace internet-dependent AWS API calls with **VPC Endpoints** — private tunnels that keep traffic inside AWS's network.

*"If your EC2 can be pinged from the internet, it can be attacked from the internet. Remove the attack surface."*

---

## What You're Building

| Component | Purpose |
|-----------|---------|
| Private EC2 | No public IP — invisible to internet scanners |
| SSM Session Manager | Replaces SSH (auditable, no key pairs, no inbound ports) |
| 6 VPC Endpoints | Private access to AWS APIs without internet |
| Least Privilege IAM | Only exact permissions needed, nothing more |

### VPC Endpoints You'll Create

| Endpoint Type | Service | Why You Need It |
|---------------|---------|-----------------|
| Interface | SSM | Session Manager core |
| Interface | EC2Messages | SSM message delivery |
| Interface | SSMMessages | SSM session communication |
| Interface | CloudWatch Logs | Ship logs without internet |
| Interface | Secrets Manager | Read DB credentials privately |
| Gateway | S3 | Package repos, SSM documents, golden AMIs |

---

## 💡 Socratic Q&A: Why Make EC2 Private?

> **Q: My EC2 worked fine with a public IP. Why make it private?**
>
> **A (Explain Like I'm 10):** Imagine your house has two doors — a front door facing the street (public IP) and a secret tunnel that only connects to trusted friends' houses (VPC Endpoints). If you use the front door, anyone walking by can see your house, try the doorknob, peek in the windows. Burglars especially love houses with front doors! But if you brick up the front door and ONLY use secret tunnels to approved places, burglars can't even find your house. That's what "private EC2" does — it removes the front door entirely.

**Evaluator Question:** *What's the security benefit of removing the public IP from EC2?*

**Model Answer:** A public IP creates an attack surface — port scanners, brute force attempts, and zero-day exploits all require network reachability. Without a public IP, the instance is invisible to the internet. Even if vulnerabilities exist, attackers can't reach them. This is "defense in depth" — reducing exposure layers, not just relying on security groups.

---

## PART 1: Prerequisites Check

Before modifying anything, verify your Lab 1C infrastructure is working.

### Step 1.1: Verify Current Infrastructure

```bash
# Navigate to your Lab 1C Terraform directory
cd ~/path/to/lab1c-terraform

# Check current state
terraform state list
```

**Expected:** You should see resources like:
- `aws_instance.app` (or `aws_instance.chewbacca_ec201`)
- `aws_vpc.main` (or `aws_vpc.chewbacca_vpc01`)
- `aws_subnet.private` (or similar)
- `aws_secretsmanager_secret.db_credentials`

### Step 1.2: Note Your Current Values

```bash
# Get your VPC ID
aws ec2 describe-vpcs \
  --region us-west-2 \
  --filters "Name=tag:Name,Values=*chewbacca*" \
  --query "Vpcs[].{Name:Tags[?Key=='Name'].Value|[0],VpcId:VpcId,CIDR:CidrBlock}" \
  --output table

# Get your private subnet IDs
aws ec2 describe-subnets \
  --region us-west-2 \
  --filters "Name=tag:Name,Values=*chewbacca*private*" \
  --query "Subnets[].{Name:Tags[?Key=='Name'].Value|[0],SubnetId:SubnetId,AZ:AvailabilityZone}" \
  --output table

# Get your current EC2 instance ID
aws ec2 describe-instances \
  --region us-west-2 \
  --filters "Name=tag:Name,Values=*chewbacca*ec2*" \
  --query "Reservations[].Instances[].{Name:Tags[?Key=='Name'].Value|[0],InstanceId:InstanceId,PublicIP:PublicIpAddress}" \
  --output table
```

**Write down these values — you'll need them:**
- VPC ID: `vpc-________________`
- Private Subnet 1: `subnet-________________`
- Private Subnet 2: `subnet-________________`
- Current Instance ID: `i-________________`
- VPC CIDR: `10.0.0.0/16` (or your value)

---

## PART 2: Install Session Manager Plugin (One-Time Setup)

Before you can use SSM Session Manager, you need to install the plugin on your local machine.

### Step 2.1: Check Your Mac Architecture

```bash
uname -m
```

| Output | Your Mac Type | Download URL |
|--------|---------------|--------------|
| `arm64` | Apple Silicon (M1/M2/M3) | Use ARM64 version |
| `x86_64` | Intel | Use Intel version |

### Step 2.2: Install the Plugin

**For Apple Silicon (M1/M2/M3) Macs:**

```bash
# Download the plugin
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/sessionmanager-bundle.zip" -o "sessionmanager-bundle.zip"

# Unzip it
unzip sessionmanager-bundle.zip

# Install it
sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin

# Clean up
rm -rf sessionmanager-bundle sessionmanager-bundle.zip
```

**For Intel Macs:**

```bash
# Download the plugin
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip" -o "sessionmanager-bundle.zip"

# Unzip it
unzip sessionmanager-bundle.zip

# Install it
sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin

# Clean up
rm -rf sessionmanager-bundle sessionmanager-bundle.zip
```

### Step 2.3: Verify Installation

```bash
session-manager-plugin
```

**Expected:** Shows version information

---

### 🔧 Troubleshooting: Session Manager Plugin

| Error | Cause | Fix |
|-------|-------|-----|
| `command not found` | Plugin not installed | Re-run installation steps |
| `bad CPU type in executable` | Wrong architecture (ARM vs Intel) | Remove and reinstall correct version |

**To remove and reinstall:**

```bash
# Remove bad installation
sudo rm -rf /usr/local/sessionmanagerplugin
sudo rm /usr/local/bin/session-manager-plugin

# Then run the correct installation for your Mac type
```

---

## PART 3: Create the Bonus A Terraform File

### Step 3.1: Create bonus_a.tf

**Action:** In your `lab1c-terraform` directory, create a new file called `bonus_a.tf`:

```bash
touch bonus_a.tf
```

**Action:** Open `bonus_a.tf` in your editor and add the following content:

```hcl
# ==============================================================================
# BONUS A: Private EC2 + VPC Endpoints
# ==============================================================================
# This file creates:
# 1. Security Group for VPC Endpoints
# 2. VPC Interface Endpoints (SSM, EC2Messages, SSMMessages, Logs, Secrets Manager)
# 3. VPC Gateway Endpoint (S3)
# 4. Least Privilege IAM Policies
# ==============================================================================

# ------------------------------------------------------------------------------
# SECURITY GROUP FOR VPC ENDPOINTS
# ------------------------------------------------------------------------------
# Interface Endpoints create ENIs that need a security group allowing HTTPS

resource "aws_security_group" "endpoint_sg" {
  name        = "${local.name_prefix}-endpoint-sg01"
  description = "Security group for VPC Interface Endpoints"
  vpc_id      = aws_vpc.main.id

  # Inbound: Allow HTTPS from VPC CIDR (all AWS APIs use HTTPS/443)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS from VPC"
  }

  # Outbound: Allow all (endpoints respond to requests)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-endpoint-sg01"
  })
}

# ------------------------------------------------------------------------------
# SSM ENDPOINTS (Required for Session Manager - ALL THREE ARE MANDATORY)
# ------------------------------------------------------------------------------

# SSM Core Endpoint
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id, aws_subnet.private[1].id]
  security_group_ids  = [aws_security_group.endpoint_sg.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ssm-endpoint01"
  })
}

# EC2Messages Endpoint (SSM command delivery)
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id, aws_subnet.private[1].id]
  security_group_ids  = [aws_security_group.endpoint_sg.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec2messages-endpoint01"
  })
}

# SSMMessages Endpoint (SSM session communication)
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id, aws_subnet.private[1].id]
  security_group_ids  = [aws_security_group.endpoint_sg.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ssmmessages-endpoint01"
  })
}

# ------------------------------------------------------------------------------
# CLOUDWATCH LOGS ENDPOINT
# ------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id, aws_subnet.private[1].id]
  security_group_ids  = [aws_security_group.endpoint_sg.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-logs-endpoint01"
  })
}

# ------------------------------------------------------------------------------
# SECRETS MANAGER ENDPOINT
# ------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id, aws_subnet.private[1].id]
  security_group_ids  = [aws_security_group.endpoint_sg.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secretsmanager-endpoint01"
  })
}

# ------------------------------------------------------------------------------
# S3 GATEWAY ENDPOINT (Free! No hourly charges)
# ------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # Gateway endpoints attach to route tables, not subnets
  route_table_ids = [aws_route_table.private.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-endpoint01"
  })
}

# ------------------------------------------------------------------------------
# LEAST PRIVILEGE IAM POLICIES
# ------------------------------------------------------------------------------

# SSM Session Manager permissions (required for SSM to work)
resource "aws_iam_role_policy_attachment" "ssm_managed_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Secrets Manager - ONLY access to this specific secret
resource "aws_iam_role_policy" "secrets_policy" {
  name = "${local.name_prefix}-secrets-policy01"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSpecificSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

# Parameter Store - ONLY access to /lab/* parameters
resource "aws_iam_role_policy" "ssm_params_policy" {
  name = "${local.name_prefix}-ssm-params-policy01"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLabParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/lab/*"
      }
    ]
  })
}

# Data source to get AWS account ID
data "aws_caller_identity" "current" {}
```

---

### 💡 Socratic Q&A: Why Three SSM Endpoints?

> **Q: Why do I need THREE endpoints just for Session Manager? Isn't that overkill?**
>
> **A (Explain Like I'm 10):** Think of Session Manager like a video call. You need three things: (1) A phone book to find who you're calling (SSM endpoint), (2) A way to send your voice to them (EC2Messages), and (3) A way for them to send their voice back to you (SSMMessages). If any one of these is missing, the call doesn't work — you might find them but can't talk, or you can talk but can't hear. All three together make a complete conversation.

**Evaluator Question:** *What happens if you forget the ec2messages endpoint?*

**Model Answer:** The SSM agent on EC2 uses ec2messages to poll for commands and ssmmessages for interactive sessions. Without ec2messages, the agent can't receive commands — `aws ssm describe-instance-information` will show the instance as "not connected" even though the SSM endpoint exists. This is a common troubleshooting scenario.

---

## PART 4: Modify EC2 to Be Private

### Step 4.1: Update Your EC2 Resource

**Action:** Open your `ec2.tf` file (or wherever your EC2 instance is defined).

**Find this section** (or similar):

```hcl
resource "aws_instance" "app" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id      # <-- CHANGE THIS
  associate_public_ip_address = true                          # <-- CHANGE THIS
  # ... rest of config
}
```

**Replace with:**

```hcl
resource "aws_instance" "app" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private[0].id     # PRIVATE subnet
  associate_public_ip_address = false                         # NO public IP
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    db_host     = aws_db_instance.main.address
    db_name     = var.db_name
    db_user     = var.db_username
    db_password = var.db_password
    aws_region  = var.aws_region
  }))

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec201"
  })

  depends_on = [
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ec2messages,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.secretsmanager,
    aws_vpc_endpoint.s3
  ]
}
```

**Key changes:**
1. `subnet_id` → Changed from public to **private** subnet
2. `associate_public_ip_address` → Changed to **false**
3. Added `depends_on` → Ensures endpoints exist before EC2 launches

---

### 💡 Socratic Q&A: No Public IP, No SSH?

> **Q: If EC2 has no public IP, how do I access it? SSH is dead now, right?**
>
> **A (Explain Like I'm 10):** Remember how you used to call your friend by shouting across the street (SSH over the internet)? Now imagine you have walkie-talkies that only work inside your house (VPC). SSM Session Manager is like those walkie-talkies — AWS provides a private channel where you can talk to your EC2 without ever going outside. Plus, mom (CloudTrail) automatically records every conversation, so there's an audit trail. No more lost house keys (SSH key pairs)!

**Evaluator Question:** *What are the advantages of SSM Session Manager over SSH?*

**Model Answer:** SSM advantages: (1) No inbound ports required — SSH needs port 22 open, SSM needs zero inbound rules. (2) IAM-based access control — granular permissions, no key pairs to manage. (3) Automatic session logging to CloudWatch/S3 — full audit trail of commands. (4) No bastion host needed — direct private access. (5) Cross-platform — works on Windows and Linux. (6) Session recording for compliance.

---

## PART 5: Adapt the Code to Your Infrastructure

### Step 5.1: Match Resource Names

The `bonus_a.tf` file references resources by name. You need to ensure these match YOUR Lab 1C code.

**Check and update these references in `bonus_a.tf`:**

| Reference in bonus_a.tf | Your Lab 1C resource name | Example |
|-------------------------|---------------------------|---------|
| `aws_vpc.main.id` | Your VPC resource name | `aws_vpc.chewbacca_vpc01.id` |
| `aws_subnet.private[0].id` | Your private subnet | `aws_subnet.chewbacca_private_subnet01.id` |
| `aws_subnet.private[1].id` | Your second private subnet | `aws_subnet.chewbacca_private_subnet02.id` |
| `aws_route_table.private.id` | Your private route table | `aws_route_table.chewbacca_private_rt01.id` |
| `aws_iam_role.ec2_role.name` | Your IAM role | `aws_iam_role.chewbacca_ec2_role01.name` |
| `aws_secretsmanager_secret.db_credentials.arn` | Your secret | `aws_secretsmanager_secret.chewbacca_db_secret01.arn` |
| `local.name_prefix` | Your naming prefix | Should already exist |
| `local.common_tags` | Your common tags | Should already exist |
| `var.vpc_cidr` | Your VPC CIDR variable | Should already exist |
| `var.aws_region` | Your region variable | Should already exist |

### Step 5.2: Find Your Resource Names

Run this to see your current resource names:

```bash
terraform state list | grep -E "(vpc|subnet|route_table|iam_role|secret)"
```

### Step 5.3: Update bonus_a.tf

**Example:** If your VPC is named `aws_vpc.chewbacca_vpc01`, change:

```hcl
# FROM:
vpc_id = aws_vpc.main.id

# TO:
vpc_id = aws_vpc.chewbacca_vpc01.id
```

**Do this for ALL resource references** in `bonus_a.tf`.

---

## PART 6: Deploy Bonus A

### Step 6.1: Validate Terraform Configuration

```bash
# Format code (fixes spacing/indentation)
terraform fmt

# Validate syntax
terraform validate
```

**Expected:** `Success! The configuration is valid.`

---

### 🔧 Troubleshooting: Validation Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Reference to undeclared resource` | Resource name doesn't match | Check `terraform state list` and update reference |
| `Invalid reference` | Typo in resource name | Check spelling carefully |
| `Unsupported attribute` | Wrong attribute name | Check Terraform AWS provider docs |

---

### Step 6.2: Preview Changes

```bash
terraform plan
```

**Review the output carefully.** You should see:
- **Create:** ~6-7 new resources (endpoints, security group, IAM policies)
- **Replace:** EC2 instance (will be destroyed and recreated in private subnet)

> ⚠️ **WARNING:** The EC2 will be **replaced**, meaning a new instance with a new Instance ID. Any data on the old instance will be lost.

### Step 6.3: Apply Changes

```bash
terraform apply
```

Type `yes` when prompted.

**Wait for completion** (2-5 minutes for endpoints to become available).

### Step 6.4: Note Your New Instance ID

```bash
terraform output
```

Or:

```bash
aws ec2 describe-instances \
  --region us-west-2 \
  --filters "Name=tag:Name,Values=*chewbacca*ec2*" \
  --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name}" \
  --output table
```

**Write down your new Instance ID:** `i-________________`

---

## PART 7: Verification

### Verification 1: Prove EC2 Has No Public IP

```bash
aws ec2 describe-instances \
  --region us-west-2 \
  --instance-ids <YOUR_INSTANCE_ID> \
  --query "Reservations[].Instances[].PublicIpAddress" \
  --output text
```

> ⚠️ **Replace `<YOUR_INSTANCE_ID>`** with your actual instance ID (e.g., `i-05e9e54886585eaea`)

**Expected:** `None` or empty output

---

### Verification 2: Prove All 6 VPC Endpoints Exist

```bash
# Get your VPC ID first
VPC_ID=$(aws ec2 describe-vpcs \
  --region us-west-2 \
  --filters "Name=tag:Name,Values=*chewbacca*" \
  --query "Vpcs[0].VpcId" \
  --output text)

echo "VPC ID: $VPC_ID"

# List all endpoints
aws ec2 describe-vpc-endpoints \
  --region us-west-2 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "VpcEndpoints[].ServiceName" \
  --output table
```

**Expected:** All 6 services listed:
- `com.amazonaws.us-west-2.ssm`
- `com.amazonaws.us-west-2.ec2messages`
- `com.amazonaws.us-west-2.ssmmessages`
- `com.amazonaws.us-west-2.logs`
- `com.amazonaws.us-west-2.secretsmanager`
- `com.amazonaws.us-west-2.s3`

---

### Verification 3: Prove SSM Agent Is Connected

```bash
aws ssm describe-instance-information \
  --region us-west-2 \
  --query "InstanceInformationList[].{InstanceId:InstanceId,PingStatus:PingStatus}" \
  --output table
```

**Expected:** Your instance ID appears with `PingStatus: Online`

> ⚠️ **If your instance doesn't appear:** Wait 2-3 minutes for the SSM agent to initialize, then retry.

---

### Verification 4: Connect via Session Manager (No SSH!)

```bash
aws ssm start-session \
  --region us-west-2 \
  --target <YOUR_INSTANCE_ID>
```

**Expected:** Shell prompt opens (e.g., `sh-5.2$`)

🎉 **You just connected to a private EC2 without SSH or a public IP!**

---

### Verification 5: Test Secrets Manager Access (From Inside Session)

While inside the SSM session, run:

```bash
aws secretsmanager get-secret-value \
  --secret-id chewbacca/rds/mysql \
  --region us-west-2 \
  --query "SecretString" \
  --output text
```

> ⚠️ **Replace `chewbacca/rds/mysql`** with your actual secret name if different.

**Expected:** Returns your database credentials JSON:
```json
{"dbname":"labdb","host":"...rds.amazonaws.com","password":"...","port":3306,"username":"admin"}
```

---

### 🔧 Troubleshooting: Verification 5 Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Connection timed out` | Secrets Manager endpoint missing/broken | Check endpoint exists and SG allows 443 |
| `AccessDeniedException` | IAM policy doesn't allow access | Check IAM policy has correct secret ARN |
| **Wrong region in command** | Using `us-east-1` instead of `us-west-2` | Use `--region us-west-2` |

**Common mistake:** Using the wrong region in the command. Your secret is in `us-west-2`, so the command MUST include `--region us-west-2`.

---

### Verification 6: Test Parameter Store Access (From Inside Session)

```bash
aws ssm get-parameters-by-path \
  --path "/lab" \
  --region us-west-2 \
  --recursive \
  --query "Parameters[].{Name:Name,Value:Value}" \
  --output table
```

**Expected:** Returns your parameters (or empty if you didn't create any)

---

### Verification 7: Exit the Session

```bash
exit
```

---

## 🔧 Troubleshooting: Common Issues

### Issue 1: SSM Session Won't Start

**Symptoms:**
- `TargetNotConnected` error
- Instance doesn't appear in `describe-instance-information`

**Diagnosis:**

```bash
# Check all three SSM endpoints exist
aws ec2 describe-vpc-endpoints \
  --region us-west-2 \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=service-name,Values=*ssm*" \
  --query "VpcEndpoints[].{Service:ServiceName,State:State}" \
  --output table
```

**Fixes:**
1. Verify all THREE endpoints exist (ssm, ec2messages, ssmmessages)
2. Check endpoint security group allows port 443 from VPC CIDR
3. Check EC2 has the `AmazonSSMManagedInstanceCore` IAM policy
4. Wait 2-3 minutes for SSM agent to connect

---

### Issue 2: "bad CPU type in executable" for Session Manager Plugin

**Cause:** You installed the wrong architecture version.

**Fix:**

```bash
# Remove bad installation
sudo rm -rf /usr/local/sessionmanagerplugin
sudo rm /usr/local/bin/session-manager-plugin

# Check your Mac type
uname -m

# Reinstall correct version (see Part 2)
```

---

### Issue 3: AccessDeniedException for Secrets Manager

**Cause:** IAM policy doesn't match the secret ARN.

**Diagnosis:**

```bash
# Check what ARN the policy allows
aws iam get-role-policy \
  --role-name chewbacca-ec2-role01 \
  --policy-name chewbacca-secrets-policy01

# Check the actual secret ARN
aws secretsmanager list-secrets \
  --region us-west-2 \
  --query "SecretList[].{Name:Name,ARN:ARN}" \
  --output table
```

**Fix:** Update the IAM policy to use the correct secret ARN.

---

### Issue 4: CloudWatch Logs AccessDeniedException

**Example error:**
```
AccessDeniedException: User is not authorized to perform: logs:DescribeLogGroups
```

**This is OK!** The error proves the endpoint **works**. The traffic reached CloudWatch Logs (no timeout), but IAM rejected it.

| Error Type | What It Means |
|------------|---------------|
| `Connection timed out` | Endpoint broken ❌ |
| `AccessDeniedException` | Endpoint works, IAM missing ✅ |

For Bonus A, you only need to prove the endpoint exists — not that you have full IAM permissions.

---

### Issue 5: Stale EBS Volume Error in Console

**Symptom:** AWS Console shows "Volume vol-xxx not found" error.

**Cause:** When Terraform recreated your EC2 (moving from public to private subnet), it deleted the old volume. The Console is caching a stale reference.

**Fix:** Refresh the page or wait a few minutes. **No action needed** — your new instance is fine.

---

## Deliverables Checklist

| Requirement | Verification Command | Expected Result | Status |
|-------------|---------------------|-----------------|--------|
| EC2 has no public IP | `describe-instances` query | `None` | ☐ |
| 6 VPC Endpoints exist | `describe-vpc-endpoints` | All 6 services listed | ☐ |
| SSM Agent connected | `describe-instance-information` | Instance shows `Online` | ☐ |
| Session Manager works | `start-session` | Shell prompt opens | ☐ |
| Secrets Manager accessible | `get-secret-value` from session | Returns credentials | ☐ |

---

## Terraform File Structure After Bonus A

```
lab1c-terraform/
├── providers.tf         # AWS provider config
├── versions.tf          # Terraform/provider versions
├── variables.tf         # Input variables
├── vpc.tf               # VPC, subnets, route tables, gateways
├── security_groups.tf   # Firewall rules for EC2 and RDS
├── rds.tf               # RDS MySQL database
├── parameters.tf        # Parameter Store entries
├── secrets.tf           # Secrets Manager secret
├── iam.tf               # IAM role and instance profile
├── cloudwatch.tf        # Log groups, alarms, SNS topics
├── ec2.tf               # EC2 app server (MODIFIED for private)
├── outputs.tf           # Values displayed after apply
├── terraform.tfvars     # Variable values (NEVER COMMIT!)
└── bonus_a.tf           # ← NEW: VPC Endpoints + Least Privilege IAM
```

---

## Reflection Questions

**A) Why do Interface Endpoints need a security group but Gateway Endpoints don't?**

Interface Endpoints create ENIs (network interfaces) in your subnet — ENIs always need security groups. Gateway Endpoints modify route tables — they're a routing construct, not a network interface.

**B) What's the minimum set of endpoints for SSM Session Manager to work?**

Three: `ssm`, `ec2messages`, and `ssmmessages`. Plus the IAM policy `AmazonSSMManagedInstanceCore`. Missing any one breaks sessions.

**C) Why is the S3 Gateway Endpoint often called a "gotcha" in private subnet designs?**

Many AWS services silently depend on S3: package repos, SSM documents, CloudWatch agent installers, service integrations. Without the S3 endpoint, seemingly unrelated things break with confusing timeout errors.

**D) How does `private_dns_enabled = true` work on Interface Endpoints?**

It creates a Route 53 private hosted zone that overrides the public DNS name (e.g., `secretsmanager.us-east-1.amazonaws.com`) to resolve to the endpoint's private IP. Your application code doesn't change — the same SDK calls now route privately.

---

## What This Lab Proves About You

*If you complete this lab, you can confidently say:*

> **"I understand how to design secure, private AWS architectures using VPC endpoints and least privilege IAM — patterns required in regulated and enterprise environments."**

*This is senior engineer territory. Most cloud practitioners never go beyond "give it a public IP and call it a day." You now know the alternative.*

---

## Interview Sound Bite

> *"I implemented VPC endpoints to enable private EC2 instances to access AWS APIs without internet exposure, reducing attack surface while maintaining SSM Session Manager for auditable administrative access. I also tightened IAM to least privilege with resource-specific policies rather than broad managed policies."*

---

## What's Next: Bonus B

**Bonus B: ALB + TLS + WAF + Dashboard**
- Public ALB (internet-facing) protects private EC2
- TLS termination with ACM certificates
- WAF for web application security
- CloudWatch Dashboard for operational visibility

*The combination of Bonus A (private compute) + Bonus B (public ingress) is how production applications are actually deployed.*
