---
title: "Lab 1C: Terraform Infrastructure as Code"
subtitle: "Enhanced Socratic Q&A Guide"
course: "SEIR Foundations"
tags:
  - aws
  - terraform
  - infrastructure-as-code
  - ec2
  - rds
  - secrets-manager
  - cloudwatch
  - iam
created: 2024-01-01
status: complete
---

# Lab 1C: Terraform Infrastructure as Code

## Enhanced Step-by-Step Guide with Embedded Socratic Q&A

---

## 🎯 Lab Overview

You've built this infrastructure by clicking through the AWS Console in Labs 1a and 1b. Now you're going to **recreate the entire thing using Terraform code**.

### What You'll Terraform

- VPC with public and private subnets
- Internet Gateway + NAT Gateway
- Security Groups (EC2 + RDS)
- RDS MySQL in private subnet
- EC2 instance with IAM role
- Parameter Store entries
- Secrets Manager secret
- CloudWatch Log Group + Alarm
- SNS Topic for alerts

---

## PART 1: Setting Up Your Terraform Environment

### Step 1.1: Create Your Project Directory Structure

**Action:** Create the following folder structure on your local machine:

```bash
mkdir -p lab1c-terraform
cd lab1c-terraform
```

> [!question] SOCRATIC Q&A: Why a Dedicated Directory?
> 
> ***Q:** Can't I just put all my Terraform files anywhere on my computer?*
> 
> **A (Explain Like I'm 10):** Imagine you're building a LEGO spaceship. Would you dump all the pieces on the floor mixed with your sister's dollhouse parts and your brother's dinosaurs? No! You'd use a separate box just for spaceship pieces. A dedicated directory is your "LEGO box" for this specific infrastructure. Terraform looks at ALL `.tf` files in the current directory and treats them as one project. If you mix projects, chaos ensues!
> 
> **Evaluator Question:** *What happens if you run `terraform apply` in a directory with `.tf` files from multiple unrelated projects?*
> 
> **Model Answer:** Terraform will attempt to create ALL resources defined in ALL `.tf` files in that directory as a single state. This leads to: (1) Unintended resource creation, (2) State file corruption when resources don't belong together, (3) Deletion of resources when you later try to separate them. Always isolate projects in separate directories.

---

### Step 1.2: Create the Provider Configuration

**Action:** Create `providers.tf`:

```hcl
# providers.tf
# This tells Terraform which cloud provider to use and where to deploy

provider "aws" {
  region = var.aws_region
}
```

**Action:** Create `versions.tf`:

```hcl
# versions.tf
# Pin versions to prevent breaking changes

terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
```

> [!question] SOCRATIC Q&A: Why Pin Versions?
> 
> ***Q:** Why do we specify exact versions? Can't Terraform just use the latest?*
> 
> **A (Explain Like I'm 10):** Imagine you have a recipe for chocolate chip cookies. It says "use flour." But what if one day the store changes their flour formula and your cookies taste weird? Version pinning is like writing "use Gold Medal All-Purpose Flour from 2024." Now your cookies taste the same EVERY time, even if you bake them next year. In Terraform, provider updates can change how resources behave—pinning prevents surprise breakages.
> 
> **Evaluator Question:** *What does `~> 5.0` mean in version constraints?*
> 
> **Model Answer:** The `~>` operator is the "pessimistic constraint operator." `~> 5.0` means "any version >= 5.0 and < 6.0" (allows 5.1, 5.2, 5.99, but blocks 6.0). This allows minor updates and patches while preventing major version changes that might break your code. It's the recommended approach for most production use cases.

---

### Step 1.3: Create Your Variables File

**Action:** Create `variables.tf`:

```hcl
# variables.tf
# All configurable inputs for your infrastructure

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "chewbacca"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "labdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
  # NO DEFAULT - must be provided at runtime!
}

variable "alert_email" {
  description = "Email address for SNS alerts"
  type        = string
}
```

> [!question] SOCRATIC Q&A: Why Variables Instead of Hardcoding?
> 
> ***Q:** Why not just write "us-east-1" directly in the code? Variables seem like extra work.*
> 
> **A (Explain Like I'm 10):** Imagine you're making birthday invitations. You could write "Come to 123 Main Street" on every single card. But what if you move next year? You'd have to rewrite ALL the cards! Instead, you write "Come to MY HOUSE" and keep your address on a separate sticky note. When you move, you just update the sticky note. Variables are that sticky note—change one place, everything updates.
> 
> **Evaluator Question:** *What does `sensitive = true` do for a variable?*
> 
> **Model Answer:** The `sensitive` flag tells Terraform to: (1) Hide the value in CLI output and logs, (2) Mark it in the state file as sensitive, (3) Prevent it from appearing in `terraform plan` output. This is critical for passwords, API keys, and secrets. Note: it does NOT encrypt the value in the state file—you still need state encryption for full protection.


NOTE: if your lab 1a and 1b infrastructure was built in a different region than us-east-1, change the region on line 7 in the variables.tf file.

Since Lab 1c **recreates** your previous infrastructure from scratch using Terraform, you have two choices:

|Approach|What Happens|
|---|---|
|**Same region (us-west-2)**|You'll have duplicate resources alongside your manually-created Lab 1a/1b resources. You can compare them!|
|**Different region**|Clean slate, no conflicts with existing resources|
**My recommendation:** Use `us-west-2` so you can verify your Terraform output matches what you built manually. Just be aware you'll have two sets of resources temporarily (and two sets of costs). After Lab 1c, you can `terraform destroy` the Terraform-managed resources.

---

## PART 2: Building the Network Foundation

### Step 2.1: Create the VPC

**Action:** Create `vpc.tf`:

```hcl
# vpc.tf
# The virtual private cloud - your isolated network in AWS

# Local values for consistent naming
locals {
  name_prefix = var.project_name
  
  common_tags = {
    Project     = var.project_name
    ManagedBy   = "terraform"
    Environment = "lab"
  }
}

# The VPC itself
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc01"
  })
}

# Internet Gateway - the door to the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw01"
  })
}
```

> [!question] SOCRATIC Q&A: What IS a VPC, Really?
> 
> ***Q:** I keep hearing "VPC" but what is it actually doing for me?*
> 
> **A (Explain Like I'm 10):** Imagine AWS is a GIANT apartment building with millions of tenants. Without a VPC, everyone's stuff is just... out there. A VPC is like getting your own private apartment with walls, a lock, and your own address. Nobody else can see inside unless you specifically invite them. Your EC2 is your TV, your RDS is your refrigerator—they're inside YOUR apartment, talking to each other privately.
> 
> **Evaluator Question:** *Why do we set both `enable_dns_support` and `enable_dns_hostnames` to true?*
> 
> **Model Answer:** 
> - `enable_dns_support = true`: Allows instances to use AWS-provided DNS server (at VPC CIDR + 2)
> - `enable_dns_hostnames = true`: Assigns public DNS hostnames to instances with public IPs
> 
> Without BOTH enabled: RDS endpoints won't resolve, VPC endpoints won't work, Session Manager fails, and private hosted zones break. This is a top-5 interview question because it's a top-5 production issue.

---

### Step 2.2: Create Subnets

**Action:** Add to `vpc.tf`:

```hcl
# Get available AZs in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Public Subnets (for ALB, NAT Gateway, bastion if needed)
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
    Type = "public"
  })
}

# Private Subnets (for EC2 app servers, RDS)
resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
    Type = "private"
  })
}
```

> [!question] SOCRATIC Q&A: Public vs Private Subnets
> 
> ***Q:** What makes a subnet "public" or "private"? Is it just a label?*
> 
> **A (Explain Like I'm 10):** Imagine your school. The LOBBY is public—anyone can walk in from the street. The CLASSROOM is private—you need to go through the lobby and hallways first; there's no direct door from outside. A public subnet has a direct route to the Internet Gateway (the front door). A private subnet has NO direct route out—it must go through a NAT Gateway in the public subnet (like going through the lobby). The label "public" or "private" is just a reminder; the ROUTES make it true.
> 
> **Evaluator Question:** *We use `count` here. When would you use `for_each` instead?*
> 
> **Model Answer:** Use `count` when resources are interchangeable and identified by index (0, 1, 2). Use `for_each` when resources have meaningful keys (like subnet names or AZ names). Problem with `count`: if you remove item 0 from the list, items 1 and 2 shift to 0 and 1, causing Terraform to destroy and recreate them. `for_each` uses stable keys, so removing one doesn't affect others. For production, `for_each` is often safer.

---

### Step 2.3: Create Route Tables and NAT Gateway

**Action:** Add to `vpc.tf`:

```hcl
# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip01"
  })
  
  depends_on = [aws_internet_gateway.main]
}

# NAT Gateway - allows private subnet to reach internet
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id  # NAT lives in public subnet
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat01"
  })
  
  depends_on = [aws_internet_gateway.main]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt01"
  })
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt01"
  })
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate private subnets with private route table
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

> [!question] SOCRATIC Q&A: Why Does NAT Gateway Live in Public Subnet?
> 
> ***Q:** If NAT Gateway helps private resources reach the internet, why is it in the PUBLIC subnet?*
> 
> **A (Explain Like I'm 10):** Think of NAT Gateway as a DELIVERY PERSON. Your private subnet is like a gated community—no outsiders allowed in directly. But residents (EC2s) still want to order pizza! The NAT Gateway stands at the community gate (public subnet), takes orders from residents, walks outside to get the pizza, and brings it back. The delivery person needs access to BOTH the outside world AND the gated community. That's why NAT lives in public subnet but serves private subnet.
> 
> **Evaluator Question:** *What's the `depends_on` doing for the NAT Gateway and EIP?*
> 
> **Model Answer:** `depends_on` creates an explicit dependency ordering. The EIP and NAT Gateway require the Internet Gateway to exist first—even though there's no direct resource reference. Without this, Terraform might try to create the NAT Gateway before the IGW is ready, causing a failure. Terraform usually infers dependencies from references, but when there's an implicit AWS-level dependency (like "NAT needs IGW for internet routing"), you must declare it explicitly.

---

## PART 3: Security Groups

### Step 3.1: Create Security Groups

**Action:** Create `security_groups.tf`:

```hcl
# security_groups.tf
# Firewall rules for EC2 and RDS

# EC2 Security Group
resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-ec2-sg01"
  description = "Security group for EC2 application server"
  vpc_id      = aws_vpc.main.id
  
  # HTTP from anywhere (for the web app)
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # SSH from anywhere (TIGHTEN THIS IN PRODUCTION!)
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # TODO: Replace with your IP
  }
  
  # Allow all outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec2-sg01"
  })
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg01"
  description = "Security group for RDS MySQL"
  vpc_id      = aws_vpc.main.id
  
  # MySQL from EC2 security group ONLY
  ingress {
    description     = "MySQL from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]  # SG-to-SG reference!
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg01"
  })
}
```

> [!question] SOCRATIC Q&A: The Magic of SG-to-SG References
> 
> ***Q:** Why do we use `security_groups = [aws_security_group.ec2.id]` instead of an IP address or CIDR?*
> 
> **A (Explain Like I'm 10):** Imagine a club with a rule: "Only people wearing a GREEN wristband can enter the VIP room." You don't need to know everyone's NAME—just check their wristband! The EC2 security group is like a green wristband. When you reference `security_groups = [aws_security_group.ec2.id]`, you're saying "anyone wearing this security group can connect." If you add 10 more EC2s with that security group, they ALL automatically get access. No IP address management needed!
> 
> **Evaluator Question:** *What's the security benefit of SG-to-SG over CIDR blocks?*
> 
> **Model Answer:** SG-to-SG references are:
> 1. **Dynamic** - When EC2 IPs change (scaling, replacement), access automatically follows
> 2. **Self-maintaining** - No manual IP list updates
> 3. **Auditable** - Clear intent: "EC2 can talk to RDS" vs. "10.0.1.50 can talk to RDS"
> 4. **Scalable** - Works with Auto Scaling Groups automatically
> 
> CIDR blocks require constant maintenance and create security drift when IPs change but rules don't.

> [!question] SOCRATIC Q&A: Why No Egress Rule on RDS Security Group?
> 
> ***Q:** The RDS security group has no `egress` block. Is that a mistake?*
> 
> **A (Explain Like I'm 10):** Great catch! When you don't specify egress rules, AWS creates a DEFAULT rule that allows ALL outbound traffic. For RDS, this is usually fine—the database only responds to queries, it doesn't initiate connections to random places. But here's the learning: ALWAYS be intentional. In production, you might explicitly define egress rules to be clear about your intentions, even if they match the default.
> 
> **Evaluator Question:** *When would you explicitly restrict RDS egress?*
> 
> **Model Answer:** You'd restrict RDS egress when: (1) Compliance requires explicit "deny by default" posture, (2) You want to prevent data exfiltration via database features like `SELECT INTO OUTFILE` to external locations, (3) You're using RDS features that make outbound calls (like Lambda triggers) and want to control where they can reach. Most labs leave it default; production should be intentional.

---

## PART 4: Database Layer

### Step 4.1: Create RDS Subnet Group and Instance

**Action:** Create `rds.tf`:

```hcl
# rds.tf
# RDS MySQL database in private subnet

# Subnet group tells RDS which subnets it can use
resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-db-subnet-group"
  description = "Subnet group for RDS"
  subnet_ids  = aws_subnet.private[*].id  # All private subnets
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

# The RDS MySQL instance
resource "aws_db_instance" "main" {
  identifier     = "${local.name_prefix}-rds01"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"
  
  allocated_storage     = 20
  max_allocated_storage = 100  # Enable storage autoscaling
  storage_type          = "gp2"
  
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  
  # CRITICAL: Keep it private!
  publicly_accessible = false
  
  # For lab - skip final snapshot on destroy
  skip_final_snapshot = true
  
  # Enable enhanced monitoring (optional but recommended)
  monitoring_interval = 0  # Set to 60 for production
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds01"
  })
}
```

> [!question] SOCRATIC Q&A: Why `publicly_accessible = false`?
> 
> ***Q:** Wouldn't it be easier to set `publicly_accessible = true` so I can connect from my laptop to debug?*
> 
> **A (Explain Like I'm 10):** Imagine your piggy bank. Would you put it on your front porch where anyone walking by could try to open it? Or would you keep it in your bedroom where only people INSIDE your house can reach it? `publicly_accessible = true` puts your database on the front porch of the internet. Even with a password, hackers will try MILLIONS of password combinations. `publicly_accessible = false` means attackers can't even SEE your database exists—they'd have to break into your VPC first.
> 
> **Evaluator Question:** *If RDS is not publicly accessible, how do you connect to it for debugging?*
> 
> **Model Answer:** Several secure options:
> 1. **SSM Session Manager** - Shell into EC2, then use mysql client to connect to RDS
> 2. **Bastion Host** - A small EC2 in public subnet that you SSH through (jump box)
> 3. **VPN** - Connect your laptop to the VPC via Site-to-Site or Client VPN
> 4. **EC2 Instance Connect Endpoint** - AWS's newer service for private instance access
> 
> All options keep RDS private while allowing controlled access. SSM Session Manager is the modern preferred approach.

> [!question] SOCRATIC Q&A: What's the Subnet Group For?
> 
> ***Q:** Why do we need a separate "subnet group"? Why can't RDS just use the subnet directly?*
> 
> **A (Explain Like I'm 10):** RDS is like a really important guest who needs a backup plan. The subnet group says "You can stay in bedroom A or bedroom B" (multiple subnets across availability zones). If bedroom A floods (AZ failure), the guest moves to bedroom B automatically. Without multiple subnets in the group, RDS can't do Multi-AZ failover. The subnet group is RDS's list of backup bedrooms.
> 
> **Evaluator Question:** *Why do we use `aws_subnet.private[*].id` with the splat operator?*
> 
> **Model Answer:** The `[*]` splat operator collects all elements from a list and extracts a specific attribute from each. `aws_subnet.private[*].id` means "get the `id` attribute from every subnet in the `aws_subnet.private` list." It's equivalent to `[for s in aws_subnet.private : s.id]`. This is cleaner than manually listing each subnet ID and automatically scales if you add more private subnets.

---

## PART 5: Secrets Management (From Lab 1b)

### Step 5.1: Create Parameter Store Entries

**Action:** Create `parameters.tf`:

```hcl
# parameters.tf
# Store non-sensitive configuration in Parameter Store

resource "aws_ssm_parameter" "db_endpoint" {
  name        = "/lab/db/endpoint"
  description = "RDS endpoint"
  type        = "String"
  value       = aws_db_instance.main.endpoint
  
  tags = local.common_tags
}

resource "aws_ssm_parameter" "db_port" {
  name        = "/lab/db/port"
  description = "RDS port"
  type        = "String"
  value       = tostring(aws_db_instance.main.port)
  
  tags = local.common_tags
}

resource "aws_ssm_parameter" "db_name" {
  name        = "/lab/db/name"
  description = "Database name"
  type        = "String"
  value       = var.db_name
  
  tags = local.common_tags
}
```

### Step 5.2: Create Secrets Manager Secret

**Action:** Create `secrets.tf`:

```hcl
# secrets.tf
# Store sensitive credentials in Secrets Manager

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${local.name_prefix}/rds/mysql"
  description = "RDS MySQL credentials for ${local.name_prefix}"
  
  # For lab - allow immediate deletion
  recovery_window_in_days = 0
  
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = var.db_name
  })
}
```

> [!question] SOCRATIC Q&A: Parameter Store vs Secrets Manager
> 
> ***Q:** We're storing the endpoint in Parameter Store and password in Secrets Manager. Why not put everything in Secrets Manager?*
> 
> **A (Explain Like I'm 10):** Think of it like your locker at school. Your notebook and pencils (endpoint, port, db name) can go in any locker—they're not secret. But your diary with embarrassing stories (password)? That needs a LOCKED locker with a combination! Parameter Store is the regular locker—free, fast, good for non-secrets. Secrets Manager is the locked locker—costs money, has special features like automatic password rotation. Use the right tool for the job!
> 
> **Evaluator Question:** *What does `recovery_window_in_days = 0` do and why is it dangerous in production?*
> 
> **Model Answer:** The recovery window is how long AWS keeps a deleted secret before permanently destroying it (default: 30 days). Setting it to 0 means immediate permanent deletion—great for labs where you want clean terraform destroy, but DANGEROUS in production. In production, that 30-day window has saved many teams who accidentally deleted secrets. Always use the default or longer in production.

> [!question] SOCRATIC Q&A: The Password-in-Code Problem
> 
> ***Q:** Wait—`var.db_password` means the password will be in my Terraform code or state file. Isn't that bad?*
> 
> **A (Explain Like I'm 10):** EXCELLENT catch! Yes, this is a real concern. The password will appear in: (1) terraform.tfvars if you put it there, (2) terraform.tfstate after apply. For labs, this is acceptable. For production, you would: (1) Use `random_password` resource to generate it, (2) Use environment variables `TF_VAR_db_password`, (3) Use a secrets backend like HashiCorp Vault, (4) Enable state encryption with S3 backend. The template shows the PATTERN—you secure the VALUE separately.
> 
> **Evaluator Question:** *How would you modify this to generate a random password that never appears in code?*
> 
> **Model Answer:**
> ```hcl
> resource "random_password" "db_password" {
>   length  = 32
>   special = true
> }
> 
> # Then use random_password.db_password.result instead of var.db_password
> ```
> The password is still in the state file, so you'd also enable state encryption:
> ```hcl
> terraform {
>   backend "s3" {
>     bucket  = "my-terraform-state"
>     key     = "lab1c/terraform.tfstate"
>     encrypt = true
>   }
> }
> ```

---

## PART 6: IAM Role for EC2

### Step 6.1: Create IAM Role and Instance Profile

**Action:** Create `iam.tf`:

```hcl
# iam.tf
# IAM Role for EC2 to access Secrets Manager and Parameter Store

# Trust policy - who can assume this role
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# The IAM Role
resource "aws_iam_role" "ec2_app" {
  name               = "${local.name_prefix}-ec2-role01"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  
  tags = local.common_tags
}

# Permission policy - what the role can do (LEAST PRIVILEGE!)
data "aws_iam_policy_document" "ec2_permissions" {
  # Read specific secret only
  statement {
    sid    = "ReadSpecificSecret"
    effect = "Allow"
    
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    
    resources = [
      aws_secretsmanager_secret.db_credentials.arn
    ]
  }
  
  # Read parameters under /lab/db/*
  statement {
    sid    = "ReadDBParameters"
    effect = "Allow"
    
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    
    resources = [
      "arn:aws:ssm:${var.aws_region}:*:parameter/lab/db/*"
    ]
  }
  
  # CloudWatch Logs permissions
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    
    resources = [
      "${aws_cloudwatch_log_group.app.arn}:*"
    ]
  }
}

# Attach the permissions to the role
resource "aws_iam_role_policy" "ec2_permissions" {
  name   = "${local.name_prefix}-ec2-permissions"
  role   = aws_iam_role.ec2_app.id
  policy = data.aws_iam_policy_document.ec2_permissions.json
}

# Instance profile - the "container" that attaches role to EC2
resource "aws_iam_instance_profile" "ec2_app" {
  name = "${local.name_prefix}-instance-profile01"
  role = aws_iam_role.ec2_app.name
  
  tags = local.common_tags
}
```

> [!question] SOCRATIC Q&A: Why Not Use AWS Managed Policies?
> 
> ***Q:** AWS has a managed policy called `SecretsManagerReadWrite`. Why write our own policy?*
> 
> **A (Explain Like I'm 10):** The managed policy is like getting a master key to EVERY locker in the school. Sure, it opens your locker... but it also opens everyone else's! Our custom policy is like getting a key that ONLY opens YOUR locker. This is "least privilege"—give exactly what's needed, nothing more. If this EC2 gets hacked, the attacker can only read ONE secret, not all 500 secrets in your account.
> 
> **Evaluator Question:** *Walk me through how an EC2 instance uses this IAM role without any access keys.*
> 
> **Model Answer:** This is the Instance Metadata Service (IMDS) flow:
> 1. EC2 launches with instance profile attached
> 2. Application calls AWS SDK (boto3, etc.)
> 3. SDK automatically queries `http://169.254.169.254/latest/meta-data/iam/security-credentials/<role-name>`
> 4. IMDS returns temporary credentials (access key, secret key, session token)
> 5. Credentials auto-rotate before expiration
> 6. Application never sees long-term credentials
> 
> This is why IAM roles are more secure than access keys—no credentials to leak, automatic rotation, and CloudTrail shows exactly what the role did.

> [!question] SOCRATIC Q&A: Role vs Instance Profile
> 
> ***Q:** What's the difference between the IAM Role and the Instance Profile? They seem redundant.*
> 
> **A (Explain Like I'm 10):** The IAM Role is like your PERMISSION SLIP—it says what you're allowed to do. The Instance Profile is like a BADGE HOLDER that clips to your shirt. EC2 can't read a piece of paper floating around; it needs something to WEAR. The instance profile is that wearable container that holds the permission slip. You create the role (permissions), put it in a profile (container), and attach the profile to EC2 (wearing it).
> 
> **Evaluator Question:** *Can one instance profile contain multiple roles?*
> 
> **Model Answer:** No. An instance profile can contain exactly ONE IAM role (or zero roles, though that's useless). If you need permissions from multiple sources, you combine them into a single role with multiple policies attached. This is a common misconception—people think they can attach multiple profiles or multiple roles, but it's always one profile with one role.

---

## PART 7: Observability (From Lab 1b)

### Step 7.1: Create CloudWatch Log Group

**Action:** Create `cloudwatch.tf`:

```hcl
# cloudwatch.tf
# Observability: Logs, Alarms, and Dashboards

# Log group for application logs
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/ec2/${local.name_prefix}-app"
  retention_in_days = 7
  
  tags = local.common_tags
}

# SNS Topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
  
  tags = local.common_tags
}

# Email subscription (requires manual confirmation!)
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Metric filter to extract DB connection errors from logs
resource "aws_cloudwatch_log_metric_filter" "db_errors" {
  name           = "${local.name_prefix}-db-connection-errors"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "?ERROR ?\"DB connection\" ?timeout ?refused ?\"Access denied\""
  
  metric_transformation {
    name          = "DBConnectionErrors"
    namespace     = "Lab/RDSApp"
    value         = "1"
    default_value = "0"
  }
}

# Alarm when DB errors exceed threshold
resource "aws_cloudwatch_metric_alarm" "db_connection_failure" {
  alarm_name          = "${local.name_prefix}-db-connection-failure"
  alarm_description   = "Triggers when DB connection errors exceed 3 in 5 minutes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DBConnectionErrors"
  namespace           = "Lab/RDSApp"
  period              = 300  # 5 minutes
  statistic           = "Sum"
  threshold           = 3
  
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  
  tags = local.common_tags
}
```

> [!question] SOCRATIC Q&A: Why a Metric Filter + Alarm Instead of Just Reading Logs?
> 
> ***Q:** Can't I just check CloudWatch Logs when something breaks? Why create metrics and alarms?*
> 
> **A (Explain Like I'm 10):** Imagine you're sleeping and your house catches fire. Would you rather: (A) Hope you wake up, smell smoke, run to the fire alarm panel, and read what's happening, OR (B) Have the smoke detector SCREAM at you the moment there's smoke? Logs are like the fire alarm panel—useful for investigation AFTER you know there's a problem. The metric + alarm is the smoke detector—it TELLS you there's a problem at 3 AM before your users notice.
> 
> **Evaluator Question:** *What does the pattern `?ERROR ?\"DB connection\"` mean in the metric filter?*
> 
> **Model Answer:** CloudWatch Logs filter patterns use a specific syntax:
> - `?` means "optional" or "OR" between terms
> - `"DB connection"` (quoted) matches that exact phrase
> - `?ERROR ?timeout ?refused` means "match if ANY of these appear"
> 
> This pattern catches: "ERROR: DB connection failed", "Connection timeout", "Connection refused", etc. The `?` makes it flexible to catch different error formats from your application.

> [!question] SOCRATIC Q&A: Symptom-Based vs Cause-Based Alarms
> 
> ***Q:** Why alarm on "DB connection errors" instead of "RDS CPU high"?*
> 
> **A (Explain Like I'm 10):** Imagine your bike won't move. Cause-based alarm: "Check if the chain is broken." But what if the tire is flat? The chain alarm doesn't help! Symptom-based alarm: "The bike isn't moving." This catches ALL problems—chain, tire, brakes, whatever. "DB connection errors" is a SYMPTOM (what users experience). It catches everything: credential drift, network issues, DB down, security group changes. CPU high is just ONE possible cause.
> 
> **Evaluator Question:** *What's the difference between `alarm_actions` and `ok_actions`?*
> 
> **Model Answer:** 
> - `alarm_actions`: Triggered when alarm goes from OK → ALARM
> - `ok_actions`: Triggered when alarm goes from ALARM → OK (recovery!)
> 
> Both should notify the same SNS topic so you know: (1) When the problem started, (2) When it was resolved. Without `ok_actions`, you'd never know if the issue self-healed. In production, you might send ALARM to PagerDuty and OK to Slack.

---

## PART 8: EC2 Application Server

### Step 8.1: Create EC2 Instance with User Data

**Action:** Create `ec2.tf`:

```hcl
# ec2.tf
# EC2 Application Server

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# User data script to bootstrap the application
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -ex
    
    # Update system
    dnf update -y
    
    # Install Python and dependencies
    dnf install -y python3-pip mysql
    pip3 install flask pymysql boto3
    
    # Create application directory
    mkdir -p /opt/app
    cd /opt/app
    
    # Create the Flask application
    cat > app.py << 'APPEOF'
    import os
    import json
    import boto3
    import pymysql
    from flask import Flask, request
    
    app = Flask(__name__)
    region = "${var.aws_region}"
    secret_name = "${local.name_prefix}/rds/mysql"
    
    def get_db_creds():
        client = boto3.client('secretsmanager', region_name=region)
        response = client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    
    def get_connection():
        creds = get_db_creds()
        return pymysql.connect(
            host=creds['host'],
            user=creds['username'],
            password=creds['password'],
            database=creds['dbname'],
            port=int(creds['port'])
        )
    
    @app.route('/health')
    def health():
        return 'OK', 200
    
    @app.route('/init')
    def init_db():
        try:
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS notes (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    content VARCHAR(255),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            conn.commit()
            conn.close()
            return 'Database initialized!', 200
        except Exception as e:
            print(f'ERROR: DB connection failed: {e}')
            return f'Error: {e}', 500
    
    @app.route('/add')
    def add_note():
        note = request.args.get('note', 'default note')
        try:
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute('INSERT INTO notes (content) VALUES (%s)', (note,))
            conn.commit()
            conn.close()
            return f'Added: {note}', 200
        except Exception as e:
            print(f'ERROR: DB connection failed: {e}')
            return f'Error: {e}', 500
    
    @app.route('/list')
    def list_notes():
        try:
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute('SELECT id, content, created_at FROM notes ORDER BY created_at DESC')
            rows = cursor.fetchall()
            conn.close()
            return '<br>'.join([f'{r[0]}: {r[1]} ({r[2]})' for r in rows]), 200
        except Exception as e:
            print(f'ERROR: DB connection failed: {e}')
            return f'Error: {e}', 500
    
    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=80)
    APPEOF
    
    # Run the application
    python3 /opt/app/app.py &
    EOF
}

# The EC2 instance
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_app.name
  
  user_data = local.user_data
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec201"
  })
  
  depends_on = [
    aws_db_instance.main,
    aws_secretsmanager_secret_version.db_credentials
  ]
}
```

> [!question] SOCRATIC Q&A: Why Use User Data Instead of a Pre-Built AMI?
> 
> ***Q:** This user data script is long. Why not just create an AMI with everything pre-installed?*
> 
> **A (Explain Like I'm 10):** Good question! There are tradeoffs:
> 
> **User Data (current approach):**
> - ✅ Always gets latest packages on launch
> - ✅ Easy to modify—just change the script
> - ✅ No AMI management overhead
> - ❌ Slower instance startup (installs packages)
> - ❌ Dependent on internet access during boot
> 
> **Custom AMI ("Golden Image"):**
> - ✅ Fast startup—everything pre-installed
> - ✅ No internet dependency during boot
> - ❌ Must rebuild AMI when packages update
> - ❌ AMI management pipeline needed
> 
> For labs, user data is simpler. For production with Auto Scaling, custom AMIs are faster and more reliable.
> 
> **Evaluator Question:** *What does the `depends_on` block ensure?*
> 
> **Model Answer:** `depends_on` ensures EC2 only launches AFTER RDS and the secret are fully created. Without it, Terraform might launch EC2 in parallel, and the application would fail to connect because RDS isn't ready yet. Terraform usually infers dependencies from references, but user data embeds values as strings—Terraform doesn't "see" those dependencies. Explicit `depends_on` makes the ordering certain.

---

## PART 9: Outputs

### Step 9.1: Create Outputs

**Action:** Create `outputs.tf`:

```hcl
# outputs.tf
# Values displayed after terraform apply

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.app.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS of the EC2 instance"
  value       = aws_instance.app.public_dns
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.main.endpoint
}

output "app_url" {
  description = "URL to access the application"
  value       = "http://${aws_instance.app.public_ip}"
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS alert topic"
  value       = aws_sns_topic.alerts.arn
}

output "init_url" {
  description = "URL to initialize the database"
  value       = "http://${aws_instance.app.public_ip}/init"
}

output "list_url" {
  description = "URL to list all notes"
  value       = "http://${aws_instance.app.public_ip}/list"
}
```

> [!question] SOCRATIC Q&A: Why Are Outputs Important?
> 
> ***Q:** I can just look up these values in the AWS Console. Why bother with outputs?*
> 
> **A (Explain Like I'm 10):** Imagine you bake cookies and they turn out AMAZING. Would you rather: (A) Try to remember exactly how they tasted, or (B) Write down "These were 10/10, used mom's chocolate chips"? Outputs are your notes! After `terraform apply`, you immediately see the EC2 IP, RDS endpoint, and URLs to test. No console hunting. Plus, other Terraform projects can READ your outputs using `terraform_remote_state`—your cookie recipe becomes shareable!
> 
> **Evaluator Question:** *How would another Terraform project consume these outputs?*
> 
> **Model Answer:** Using the `terraform_remote_state` data source:
> ```hcl
> data "terraform_remote_state" "lab1c" {
>   backend = "s3"
>   config = {
>     bucket = "my-terraform-state"
>     key    = "lab1c/terraform.tfstate"
>     region = "us-east-1"
>   }
> }
> 
> # Then reference like: data.terraform_remote_state.lab1c.outputs.vpc_id
> ```
> This enables modular infrastructure where networks, databases, and applications are managed separately but can reference each other.

---

## PART 10: Deploy and Verify

### Step 10.1: Create terraform.tfvars (Local Only - NEVER COMMIT!)

**Action:** Create `terraform.tfvars`:

```hcl
# terraform.tfvars
# NEVER COMMIT THIS FILE TO GIT!

aws_region   = "<your region>"
project_name = "chewbacca"
db_password  = "YourSecurePassword123!"  # Change this!
alert_email  = "your-email@example.com"
```

> [!warning] Security Warning
> Add `terraform.tfvars` to your `.gitignore` file immediately!

**Action:** Add to `.gitignore`:

```
terraform.tfvars
*.tfstate
*.tfstate.*
.terraform/
```

---
### Step 10.2: Initialize and Apply

**Action:** Run Terraform commands:

```bash
# Initialize - downloads providers
terraform init

# Validate syntax
terraform validate

# Format code (makes it pretty)
terraform fmt

# Preview changes - ALWAYS DO THIS!
terraform plan

# Apply (creates resources)
terraform apply
```

Fixes
- The plan shows 1 change because I fixed a package naming bug in the user_data script (mysql → mariadb105 for Amazon Linux 2023 compatibility). The infrastructure is fully deployed and functional. This demonstrated **real-world Terraform workflow** — finding issues, fixing code, and seeing Terraform detect the drift.

> [!question] SOCRATIC Q&A: Why `terraform plan` Before `terraform apply`?
> 
> ***Q:** Can't I just run `terraform apply` directly? The plan seems like extra work.*
> 
> **A (Explain Like I'm 10):** Imagine you're about to send a text message to your ENTIRE contact list. Would you rather: (A) Just hit SEND and hope for the best, or (B) Preview the message first to make sure you're not accidentally sending "I HATE MONDAYS" to your grandma? `terraform plan` is that preview. It shows EXACTLY what will be created (+), changed (~), or DESTROYED (-). That red (-) is especially important—you don't want surprise deletions!
> 
> **Evaluator Question:** *How do you ensure the plan you reviewed is exactly what gets applied?*
> 
> **Model Answer:** Save the plan to a file, then apply that specific plan:
> ```bash
> terraform plan -out=plan.tfplan
> # Review the plan...
> terraform apply plan.tfplan
> ```
> This guarantees the applied changes match what was reviewed—critical for production deployments and change management processes. The plan file is binary and can't be modified.

Troubleshooting

- Invalid resource type anywhere? To clean up and reinitialize:
	- *rm -rf .terraform rm -f .terraform.lock.hcl
	- *terraform init

---

### Step 10.3: Verify Deployment

**Action:** Run verification commands:

```bash
# From outputs, test the application
# Wait 2-3 minutes for EC2 user data to complete!

# Initialize the database
curl http://<EC2_PUBLIC_IP>/init

# Add some notes
curl "http://<EC2_PUBLIC_IP>/add?note=terraform_rocks"
curl "http://<EC2_PUBLIC_IP>/add?note=infrastructure_as_code"
curl "http://<EC2_PUBLIC_IP>/add?note=lab1c_complete"

# List all notes
curl http://<EC2_PUBLIC_IP>/list
```

---

## 📋 Verification Checklist

> [!success] CLI Verification Commands
> Run these commands to prove your infrastructure is correctly deployed:
> 
> ```bash
> # 1. VPC exists
> aws ec2 describe-vpcs -filters "Name=tag:Name,Values=chewbacca-vpc01" --query "Vpcs[].VpcId"
> 
> # 2. RDS is private
> aws rds describe-db-instances --db-instance-identifier chewbacca-rds01 --query "DBInstances[].{Status:DBInstanceStatus,Public:PubliclyAccessible}"
> 
> # 3. EC2 has role attached
> aws ec2 describe-instances -filters "Name=tag:Name,Values=chewbacca-ec201" --query "Reservations[].Instances[].IamInstanceProfile.Arn"
> 
> # 4. Secret exists
> aws secretsmanager describe-secret -secret-id chewbacca/rds/mysql
> 
> # 5. Parameters exist
> aws ssm get-parameters --names /lab/db/endpoint /lab/db/port /lab/db/name
> 
> # 6. Alarm exists
> aws cloudwatch describe-alarms --alarm-name-prefix chewbacca
> ```

---

## 🎯 Summary: What Lab 1C Proves About You

If you can Terraform this entire stack, you've demonstrated:

| Skill | Evidence |
|-------|----------|
| **Infrastructure as Code** | You wrote declarative code, not clicked buttons |
| **AWS Networking** | VPC, subnets, route tables, NAT Gateway |
| **Security Best Practices** | SG-to-SG rules, private RDS, IAM least privilege |
| **Secrets Management** | Parameter Store + Secrets Manager separation |
| **Observability** | CloudWatch Logs, Metrics, Alarms, SNS |
| **Reproducibility** | Anyone can run your code and get identical infrastructure |

---

> [!tip] Interview Statement
> **The sentence you can now say in an interview:**
> 
> *"I can design, deploy, and operate AWS infrastructure using Terraform with proper security, secrets management, and observability patterns."*
> 
> That is junior-to-mid-level cloud engineer capability. You're no longer "someone who clicked around"—you're someone who ships infrastructure like a professional.

---

## 🔜 What's Next?

- **[[Lab 2 - CloudFront Origin Cloaking and Caching]]**: Add CloudFront, origin cloaking, and caching in front of this infrastructure
- **[[Lab 3 - Japan Medical Cross-Region Architecture]]**: Extend to multi-region with Transit Gateway for compliance requirements

---

## Quick Reference: Terraform File Structure

| File | Purpose |
|------|---------|
| `providers.tf` | AWS provider configuration, region |
| `versions.tf` | Terraform and provider version constraints |
| `variables.tf` | Input variables (customizable values) |
| `vpc.tf` | VPC, subnets, route tables, gateways |
| `security_groups.tf` | Firewall rules for EC2 and RDS |
| `rds.tf` | RDS MySQL database |
| `parameters.tf` | Parameter Store entries |
| `secrets.tf` | Secrets Manager secret |
| `iam.tf` | IAM role and instance profile |
| `cloudwatch.tf` | Log groups, alarms, SNS topics |
| `ec2.tf` | EC2 application server |
| `outputs.tf` | Values displayed after apply |
| `terraform.tfvars` | Variable values (NEVER COMMIT!) |

---

## Common Terraform Commands

```bash
# Initialize project (run first!)
terraform init

# Format code
terraform fmt

# Validate syntax
terraform validate

# Preview changes
terraform plan

# Apply changes
terraform apply

# Destroy everything (careful!)
terraform destroy

# Show current state
terraform show

# List resources in state
terraform state list
```
