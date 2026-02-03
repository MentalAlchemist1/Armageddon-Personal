# SEIR FOUNDATIONS
# LAB 1C BONUS A: Private EC2 + VPC Endpoints
## *Enhanced Socratic Q&A Guide*

---

> [!warning] **PREREQUISITE**
> Lab 1C core must be completed and verified before starting Bonus A. Your Terraform-deployed EC2 → RDS application must be working.

---

## Lab Overview

In Lab 1C core, your EC2 instance had a **public IP** and used the **internet** to reach AWS services. In Bonus A, you'll **remove the public IP entirely** and replace internet-dependent AWS API calls with **VPC Endpoints** — private tunnels that keep traffic inside AWS's network.

*"If your EC2 can be pinged from the internet, it can be attacked from the internet. Remove the attack surface."*

---

## Design Goals (What You're Building)

| Goal | What It Means |
|------|---------------|
| EC2 is private | No public IP assigned — invisible to internet scanners |
| No SSH required | Access via SSM Session Manager (auditable, no key pairs) |
| No NAT for AWS APIs | VPC Interface Endpoints replace internet path |
| Least privilege IAM | Only the exact permissions needed, nothing more |

---

## VPC Endpoints You'll Create

| Endpoint Type | Service | Why You Need It |
|---------------|---------|-----------------|
| Interface | SSM | Session Manager core |
| Interface | EC2Messages | SSM message delivery |
| Interface | SSMMessages | SSM session communication |
| Interface | CloudWatch Logs | Ship logs without internet |
| Interface | Secrets Manager | Read DB credentials privately |
| Interface | KMS | (Optional) Decrypt secrets |
| Gateway | S3 | Package repos, golden AMIs |

---

## Why This Lab Exists (Industry Context)

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** My EC2 worked fine with a public IP. Why make it private?*
> 
> **A (Explain Like I'm 10):** Imagine your house has two doors — a front door facing the street (public IP) and a secret tunnel that only connects to trusted friends' houses (VPC Endpoints). If you use the front door, anyone walking by can see your house, try the doorknob, peek in the windows. Burglars especially love houses with front doors! But if you brick up the front door and ONLY use secret tunnels to approved places, burglars can't even find your house. That's what "private EC2" does — it removes the front door entirely.
> 
> **Evaluator Question:** *What's the security benefit of removing the public IP from EC2?*
> 
> **Model Answer:** A public IP creates an attack surface — port scanners, brute force attempts, and zero-day exploits all require network reachability. Without a public IP, the instance is invisible to the internet. Even if vulnerabilities exist, attackers can't reach them. This is "defense in depth" — reducing exposure layers, not just relying on security groups.

---

## PART 1: Understanding VPC Endpoints

### Interface Endpoints vs Gateway Endpoints

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why are there two types of endpoints (Interface vs Gateway)? Can't AWS just have one type?*
> 
> **A (Explain Like I'm 10):** Think of it like two kinds of delivery services. A **Gateway Endpoint** is like having a dedicated highway exit ramp that goes straight to one mega-store (S3 or DynamoDB) — it's free and super fast because it's built into the road system. An **Interface Endpoint** is like hiring a personal courier who can deliver to ANY store (Secrets Manager, CloudWatch, SSM, etc.) — it costs money per hour and per package, but it's flexible. AWS built the highway ramps first for their busiest stores, then created the courier service for everything else.
> 
> **Evaluator Question:** *When would you choose an Interface Endpoint vs a Gateway Endpoint?*
> 
> **Model Answer:** Gateway Endpoints support only S3 and DynamoDB, are free, and route via the VPC route table. Interface Endpoints support 100+ AWS services, cost ~$0.01/hour per AZ plus data transfer, and create an ENI in your subnet with a private IP. Use Gateway for S3/DynamoDB (cost savings). Use Interface for everything else or when you need DNS resolution to a private IP (e.g., hybrid cloud with on-prem DNS).

---

## PART 2: Remove Public IP from EC2

### Step 2.1: Modify EC2 Resource to Private Subnet

Your EC2 must now launch in a **private subnet** (no internet gateway route) with no public IP.

**Action:** Update your EC2 resource in Terraform:

```hcl
resource "aws_instance" "chewbacca_ec201" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.chewbacca_private_subnet01.id  # PRIVATE subnet
  associate_public_ip_address = false                                      # NO public IP
  iam_instance_profile        = aws_iam_instance_profile.chewbacca_instance_profile01.name
  vpc_security_group_ids      = [aws_security_group.chewbacca_ec2_sg01.id]

  tags = {
    Name = "${local.name_prefix}-ec201"
  }
}
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** If EC2 has no public IP, how do I access it? SSH is dead now, right?*
> 
> **A (Explain Like I'm 10):** Remember how you used to call your friend by shouting across the street (SSH over the internet)? Now imagine you have walkie-talkies that only work inside your house (VPC). SSM Session Manager is like those walkie-talkies — AWS provides a private channel where you can talk to your EC2 without ever going outside. Plus, mom (CloudTrail) automatically records every conversation, so there's an audit trail. No more lost house keys (SSH key pairs)!
> 
> **Evaluator Question:** *What are the advantages of SSM Session Manager over SSH?*
> 
> **Model Answer:** SSM advantages: (1) No inbound ports required — SSH needs port 22 open, SSM needs zero inbound rules. (2) IAM-based access control — granular permissions, no key pairs to manage. (3) Automatic session logging to CloudWatch/S3 — full audit trail of commands. (4) No bastion host needed — direct private access. (5) Cross-platform — works on Windows and Linux. (6) Session recording for compliance.

---

## PART 3: Create VPC Interface Endpoints

### Step 3.1: Create SSM Endpoints (Required for Session Manager)

Session Manager requires **three endpoints** to function. This is a common interview question!

```hcl
# === SSM Endpoint (core) ===
resource "aws_vpc_endpoint" "chewbacca_ssm_endpoint01" {
  vpc_id              = aws_vpc.chewbacca_vpc01.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.chewbacca_private_subnet01.id, aws_subnet.chewbacca_private_subnet02.id]
  security_group_ids  = [aws_security_group.chewbacca_endpoint_sg01.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-ssm-endpoint01"
  }
}

# === EC2Messages Endpoint ===
resource "aws_vpc_endpoint" "chewbacca_ec2messages_endpoint01" {
  vpc_id              = aws_vpc.chewbacca_vpc01.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.chewbacca_private_subnet01.id, aws_subnet.chewbacca_private_subnet02.id]
  security_group_ids  = [aws_security_group.chewbacca_endpoint_sg01.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-ec2messages-endpoint01"
  }
}

# === SSMMessages Endpoint ===
resource "aws_vpc_endpoint" "chewbacca_ssmmessages_endpoint01" {
  vpc_id              = aws_vpc.chewbacca_vpc01.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.chewbacca_private_subnet01.id, aws_subnet.chewbacca_private_subnet02.id]
  security_group_ids  = [aws_security_group.chewbacca_endpoint_sg01.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-ssmmessages-endpoint01"
  }
}
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why do I need THREE endpoints just for Session Manager? Isn't that overkill?*
> 
> **A (Explain Like I'm 10):** Think of Session Manager like a video call. You need three things: (1) A phone book to find who you're calling (SSM endpoint), (2) A way to send your voice to them (EC2Messages), and (3) A way for them to send their voice back to you (SSMMessages). If any one of these is missing, the call doesn't work — you might find them but can't talk, or you can talk but can't hear. All three together make a complete conversation.
> 
> **Evaluator Question:** *What happens if you forget the ec2messages endpoint?*
> 
> **Model Answer:** The SSM agent on EC2 uses ec2messages to poll for commands and ssmmessages for interactive sessions. Without ec2messages, the agent can't receive commands — `aws ssm describe-instance-information` will show the instance as "not connected" even though the SSM endpoint exists. This is a common troubleshooting scenario: "I have the SSM endpoint but Session Manager doesn't work." Check all three endpoints.

---

### Step 3.2: Create Security Group for Endpoints

Interface Endpoints create ENIs (Elastic Network Interfaces) in your subnet. Those ENIs need a security group allowing HTTPS traffic from your VPC.

```hcl
resource "aws_security_group" "chewbacca_endpoint_sg01" {
  name        = "${local.name_prefix}-endpoint-sg01"
  description = "Security group for VPC Interface Endpoints"
  vpc_id      = aws_vpc.chewbacca_vpc01.id

  # Inbound: Allow HTTPS from VPC CIDR (endpoints use HTTPS/443)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.chewbacca_vpc01.cidr_block]
    description = "HTTPS from VPC"
  }

  # Outbound: Allow all (endpoints respond to requests)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-endpoint-sg01"
  }
}
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why do Interface Endpoints need their own security group?*
> 
> **A (Explain Like I'm 10):** Interface Endpoints are like installing private ATMs inside your office building. Even though they're inside YOUR building, you still need security rules about who in the building can use them. The security group says "only people with company badges (VPC CIDR) can use these ATMs (endpoints)." Without the security group, the ATMs would be locked and nobody could withdraw cash (make API calls).
> 
> **Evaluator Question:** *What's the minimum security group rule needed for VPC endpoints to function?*
> 
> **Model Answer:** Inbound HTTPS (port 443) from the VPC CIDR block. All AWS API calls use HTTPS. The source can be narrowed to specific subnets or security groups for tighter control. Some teams create separate endpoint security groups per service for granular logging and audit.

---

### Step 3.3: Create CloudWatch Logs Endpoint

Your application ships logs to CloudWatch. Without this endpoint, logs can't leave the private subnet.

```hcl
resource "aws_vpc_endpoint" "chewbacca_logs_endpoint01" {
  vpc_id              = aws_vpc.chewbacca_vpc01.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.chewbacca_private_subnet01.id, aws_subnet.chewbacca_private_subnet02.id]
  security_group_ids  = [aws_security_group.chewbacca_endpoint_sg01.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-logs-endpoint01"
  }
}
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** My EC2 was already sending logs to CloudWatch. Why didn't it need an endpoint before?*
> 
> **A (Explain Like I'm 10):** Before, your EC2 had a public IP, which meant it could shout over the internet to CloudWatch's public address. It's like mailing a letter — you drop it in the public mailbox, and it eventually reaches CloudWatch. Now that your EC2 has no public address, there's no mailbox to use! The VPC Endpoint is like installing a private mail slot that goes directly to CloudWatch's office — no need for the public postal system.
> 
> **Evaluator Question:** *If logs can't reach CloudWatch, how would you detect this failure?*
> 
> **Model Answer:** You wouldn't see log events in CloudWatch Logs Insights — but you might not notice immediately because queries return empty rather than errors. On the instance, check the CloudWatch agent log: `/var/log/amazon/amazon-cloudwatch-agent/amazon-cloudwatch-agent.log`. Look for "connection refused" or "timeout" errors. In production, create a CloudWatch alarm on `NumberOfMessagesReceived` metric to detect log delivery failures.

---

### Step 3.4: Create Secrets Manager Endpoint

Your application retrieves database credentials from Secrets Manager. This needs an endpoint too.

```hcl
resource "aws_vpc_endpoint" "chewbacca_secretsmanager_endpoint01" {
  vpc_id              = aws_vpc.chewbacca_vpc01.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.chewbacca_private_subnet01.id, aws_subnet.chewbacca_private_subnet02.id]
  security_group_ids  = [aws_security_group.chewbacca_endpoint_sg01.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-secretsmanager-endpoint01"
  }
}
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** The secret is just a small JSON blob. Why do we need a whole endpoint for that?*
> 
> **A (Explain Like I'm 10):** Size doesn't matter — location does! Your secret is stored in a vault (Secrets Manager) that lives OUTSIDE your private house (VPC). Before, you walked out the front door (public IP) to get to the vault. Now there's no front door! The endpoint is like building a private tunnel from your basement directly into the vault's basement. The tunnel exists whether you're moving a small envelope or a big box.
> 
> **Evaluator Question:** *What happens to your application if the Secrets Manager endpoint is missing?*
> 
> **Model Answer:** The application's `boto3.client('secretsmanager').get_secret_value()` call will timeout and fail. The Flask app can't retrieve database credentials, so it can't connect to RDS. Users see "Database connection error" or the app crashes on startup. This is why configuration retrieval is often in the critical path — test endpoint connectivity before assuming the app works.

---

### Step 3.5: Create S3 Gateway Endpoint

S3 Gateway Endpoints are **free** and critical for package installations and AWS service integrations.

```hcl
resource "aws_vpc_endpoint" "chewbacca_s3_endpoint01" {
  vpc_id            = aws_vpc.chewbacca_vpc01.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # Gateway endpoints attach to route tables, not subnets
  route_table_ids = [
    aws_route_table.chewbacca_private_rt01.id
  ]

  tags = {
    Name = "${local.name_prefix}-s3-endpoint01"
  }
}
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why is S3 a Gateway Endpoint but everything else is Interface?*
> 
> **A (Explain Like I'm 10):** S3 is AWS's most popular service — everyone uses it constantly. Imagine if every single person in a city needed to use the same store. Building a private door for each person (Interface Endpoint) would be crazy expensive! Instead, AWS built a free highway exit ramp (Gateway Endpoint) that goes directly to S3's mega-warehouse. The highway exit is built into the road system (route tables), so it handles millions of cars without creating traffic jams (ENI bottlenecks).
> 
> **Evaluator Question:** *What breaks in a private subnet if you forget the S3 Gateway Endpoint?*
> 
> **Model Answer:** Many things rely on S3 silently: (1) `yum`/`dnf` repos for Amazon Linux are hosted on S3 — no package installs. (2) CloudWatch agent installer is on S3. (3) SSM agent updates come from S3. (4) Many AWS services store artifacts in S3. Without the S3 endpoint, a private instance can't update itself, install packages, or use services that fetch from S3. This is the most common "gotcha" in private subnet designs.

---

## PART 4: Tighten IAM to Least Privilege

### Step 4.1: Restrict Secrets Manager Access

Replace the broad `SecretsManagerReadWrite` with a policy that allows reading **only your specific secret**.

```hcl
resource "aws_iam_role_policy" "chewbacca_secrets_policy01" {
  name = "${local.name_prefix}-secrets-policy01"
  role = aws_iam_role.chewbacca_ec2_role01.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSpecificSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "${aws_secretsmanager_secret.chewbacca_db_secret01.arn}"
      }
    ]
  })
}
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** The managed policy worked fine. Why write a custom policy?*
> 
> **A (Explain Like I'm 10):** Imagine you're the building manager, and you give a janitor a master key that opens EVERY room (managed policy). That janitor can now access the CEO's office, the server room, the safe — everything! But the janitor only needs to clean the bathrooms. A custom policy is like giving them a key that ONLY opens bathroom doors. If the janitor turns evil, they can only mess up bathrooms, not steal from the safe. That's "least privilege" — give exactly what's needed, nothing more.
> 
> **Evaluator Question:** *How would you audit if an IAM role has overly permissive policies?*
> 
> **Model Answer:** Use IAM Access Analyzer to identify overly permissive policies and external access. Review attached policies with `aws iam list-attached-role-policies` and inline policies with `aws iam list-role-policies`. Check CloudTrail for actual API calls — if a role never calls certain allowed actions, the policy should be tightened. AWS also provides policy simulators and access advisor for unused permissions.

---

### Step 4.2: Restrict Parameter Store Access

Allow reading parameters **only from your specific path**.

```hcl
resource "aws_iam_role_policy" "chewbacca_ssm_params_policy01" {
  name = "${local.name_prefix}-ssm-params-policy01"
  role = aws_iam_role.chewbacca_ec2_role01.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadLabParameters"
        Effect   = "Allow"
        Action   = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/lab/*"
      }
    ]
  })
}

# Data source to get account ID
data "aws_caller_identity" "current" {}
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** What's the wildcard `/lab/*` doing in the Resource ARN?*
> 
> **A (Explain Like I'm 10):** The wildcard is like saying "you can open any drawer in the `/lab/` filing cabinet, but NOT drawers in other cabinets." Your app needs `/lab/db/endpoint`, `/lab/db/port`, and `/lab/db/name`. Instead of listing all three, the wildcard says "anything starting with `/lab/`" is fair game. But it can't touch `/production/*` or `/admin/*` — those cabinets are locked for this role.
> 
> **Evaluator Question:** *Why use path-based parameter naming and IAM restrictions?*
> 
> **Model Answer:** Path-based naming creates natural IAM boundaries. Parameters like `/production/db/password` and `/staging/db/password` can have different access policies by path. Applications only get access to their environment. This prevents cross-environment data leaks (staging app reading production creds) and supports team boundaries (team A can't read team B's parameters).

---

### Step 4.3: Add SSM Session Manager Permissions

The EC2 needs permissions to participate in SSM sessions.

```hcl
resource "aws_iam_role_policy_attachment" "chewbacca_ssm_managed_policy01" {
  role       = aws_iam_role.chewbacca_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** We just talked about avoiding managed policies. Why use one here?*
> 
> **A (Explain Like I'm 10):** Some managed policies are like official uniforms — everyone needs the same thing, and AWS updates them when the rules change. `AmazonSSMManagedInstanceCore` is AWS's official "what an EC2 needs to talk to SSM" uniform. If AWS adds a new SSM feature tomorrow, they update the uniform automatically. Writing your own custom policy means you have to keep updating it yourself. For SSM specifically, the managed policy is the pragmatic choice because SSM's requirements are complex and AWS-maintained.
> 
> **Evaluator Question:** *What's in `AmazonSSMManagedInstanceCore` that makes it necessary?*
> 
> **Model Answer:** It includes: (1) `ssm:UpdateInstanceInformation` — heartbeat to SSM, (2) `ssmmessages:*` — session communication, (3) `ec2messages:*` — command delivery, (4) `s3:GetObject` for SSM document storage. These permissions interact across multiple services. A custom policy would need to track AWS's changes. The managed policy is acceptable for SSM because it's scoped to SSM's own functionality, not your data.

---

## PART 5: (Optional) Remove NAT Gateway

> [!warning] **ADVANCED CONSIDERATION**
> Removing NAT entirely means your EC2 cannot reach ANY internet resource. This is ideal for maximum security but requires careful planning.

### What Breaks Without NAT?

| Dependency | What Happens | Solution |
|------------|--------------|----------|
| OS package updates | `yum install` fails | Use golden AMIs or S3-hosted repos |
| Third-party APIs | External webhooks fail | Use Lambda with VPC config or API Gateway |
| Time sync (NTP) | Clock drift | Amazon Time Sync Service (169.254.169.123) works without NAT |
| AWS public endpoints | API calls fail | VPC Endpoints (already done!) |

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Should I remove NAT in a real production environment?*
> 
> **A (Explain Like I'm 10):** It depends on whether your application needs to call ANYONE outside your house. If it only talks to AWS services (which you've covered with endpoints), removing NAT is like sealing all the windows — maximum security. But if your app needs to call a weather API, a payment processor, or any external service, you need NAT (or a different egress solution like a proxy). Most companies keep NAT for flexibility but tightly control what can use it via security groups and NACLs.
> 
> **Evaluator Question:** *What are alternatives to NAT Gateway for controlled egress?*
> 
> **Model Answer:** Options include: (1) NAT Gateway — simple, managed, but allows any outbound. (2) NAT Instance — cheaper, customizable, but self-managed. (3) Forward proxy (Squid) — URL filtering, logging, policy enforcement. (4) AWS Network Firewall — deep packet inspection, managed rules. (5) PrivateLink to third parties — some SaaS providers support PrivateLink for private access. The right choice depends on compliance needs, budget, and operational capacity.

---

## Verification Commands

> [!success] **VERIFICATION: 1. Prove EC2 is Private (No Public IP)**
> ```bash
> aws ec2 describe-instances \
>   --instance-ids <INSTANCE_ID> \
>   --query "Reservations[].Instances[].PublicIpAddress"
> ```
> **Expected:** `null` or empty array `[]`

> [!success] **VERIFICATION: 2. Prove VPC Endpoints Exist**
> ```bash
> aws ec2 describe-vpc-endpoints \
>   --filters "Name=vpc-id,Values=<VPC_ID>" \
>   --query "VpcEndpoints[].ServiceName"
> ```
> **Expected:** List includes: `ssm`, `ec2messages`, `ssmmessages`, `logs`, `secretsmanager`, `s3`

> [!success] **VERIFICATION: 3. Prove Session Manager Works (No SSH)**
> ```bash
> aws ssm describe-instance-information \
>   --query "InstanceInformationList[].InstanceId"
> ```
> **Expected:** Your private EC2 instance ID appears in the list

> [!success] **VERIFICATION: 4. Prove Instance Can Read Config Stores**
> Run **from SSM session** (not your laptop):
> ```bash
> # Start SSM session
> aws ssm start-session --target <INSTANCE_ID>
> 
> # Inside the session:
> aws ssm get-parameter --name /lab/db/endpoint
> aws secretsmanager get-secret-value --secret-id <your-secret-name>
> ```
> **Expected:** Both return values without timeout errors

> [!success] **VERIFICATION: 5. Prove CloudWatch Logs Endpoint Works**
> ```bash
> aws logs describe-log-streams \
>   --log-group-name /aws/ec2/<prefix>-rds-app
> ```
> **Expected:** Log streams appear (proves logs are being delivered)

NOTE: on verification #5, I ran into an IAM permission issue, not an endpoint issue. I didn't add CloudWatch Logs or Streams permissions to the role — which is actually fine for this lab.

## Terraform File Structure for Bonus A

```
lab1c/
├── main.tf              # Core resources (VPC, subnets, RDS, EC2)
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── providers.tf         # AWS provider config
├── versions.tf          # Terraform/provider versions
└── bonus_a.tf           # 👈 NEW: All Bonus A resources
    ├── VPC Endpoints (SSM, EC2Messages, SSMMessages, Logs, Secrets, S3)
    ├── Endpoint Security Group
    └── Updated IAM policies (least privilege)
```

---

## Deliverables Checklist

| Requirement                | Proof Command                       | Expected Result                                         |
| -------------------------- | ----------------------------------- | ------------------------------------------------------- |
| EC2 has no public IP       | `describe-instances` query          | `null`                                                  |
| 6 VPC endpoints exist      | `describe-vpc-endpoints`            | ssm, ec2messages, ssmmessages, logs, secretsmanager, s3 |
| SSM Session Manager works  | `describe-instance-information`     | Instance ID appears                                     |
| Secrets Manager accessible | `get-secret-value` from SSM session | Returns secret (no timeout)                             |
| Parameter Store accessible | `get-parameter` from SSM session    | Returns parameter (no timeout)                          |
| CloudWatch Logs flowing    | `describe-log-streams`              | Log streams exist                                       |

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

## How This Maps to "Real Company" Practice

> [!quote] **Employer-Credible Sound Bite**
> *"I implemented VPC endpoints to enable private EC2 instances to access AWS APIs without internet exposure, reducing attack surface while maintaining SSM Session Manager for auditable administrative access. I also tightened IAM to least privilege with resource-specific policies rather than broad managed policies."*

| Practice | Why It Matters |
|----------|----------------|
| Private compute + SSM | Standard in regulated industries (healthcare, finance, government) |
| VPC Endpoints | Reduces NAT costs and eliminates internet dependency for AWS APIs |
| Least privilege IAM | Non-negotiable in security interviews and compliance audits |
| Terraform submission | Mirrors real workflow: PR → plan → review → apply → monitor |

---

## What This Lab Proves About You

*If you complete this lab, you can confidently say:*

> **"I understand how to design secure, private AWS architectures using VPC endpoints and least privilege IAM — patterns required in regulated and enterprise environments."**

*This is senior engineer territory. Most cloud practitioners never go beyond "give it a public IP and call it a day." You now know the alternative.*

---

## What's Next: Bonus B

**Bonus B: ALB + TLS + WAF + Dashboard**
- Public ALB (internet-facing) protects private EC2
- TLS termination with ACM certificates
- WAF for web application security
- CloudWatch Dashboard for operational visibility

*The combination of Bonus A (private compute) + Bonus B (public ingress) is how production applications are actually deployed.*
