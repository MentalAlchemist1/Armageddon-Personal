# SEIR FOUNDATIONS

# Lab 1: EC2 Web App → RDS MySQL

---

## 📋 Lab Overview

**Goal:** Deploy a simple web app on an EC2 instance that can insert a note into RDS MySQL and list notes from the database.

### Why This Lab Exists (Industry Context)

This is one of the most common interview architectures. Employers routinely expect engineers to understand:

- How EC2 communicates with RDS
- How database access is restricted
- Where credentials are stored
- How connectivity is validated
- How failures are debugged

> **If you cannot explain this pattern clearly, you will struggle in real cloud environments.**

⚠️ CLI Note: Multi-line commands in this guide use \ for line continuation (Linux/Mac). If you're on Windows or prefer single-line commands, simply remove the \ characters and put everything on one line. Alternatively, copy-paste each command into a text editor first and join the lines.
---

## PART 1: Create Security Groups

### Step 1.1: Configure Security Group for EC2

**Create Security Group:** `lab-ec2-sg`

| Rule | Type | Port | Source | Purpose |
|------|------|------|--------|---------|
| Inbound | HTTP | 80 | 0.0.0.0/0 | Web app access |
| Inbound | SSH | 22 | Your IP only | Admin access |
| Outbound | All traffic | All | 0.0.0.0/0 | App can reach internet |

**⚠️ Troubleshooting:**
- Make sure your SSH is **NOT** 0.0.0.0/0
- Find your current public IP: `curl checkip.amazonaws.com`
- Use format: `<Your IP>/32`

---

### Step 1.2: Configure Security Group for RDS

**Create Security Group:** `lab-rds-sg`

| Rule | Type | Port | Source | Purpose |
|------|------|------|--------|---------|
| Inbound | MySQL/Aurora | 3306 | lab-ec2-sg | Allow app server to connect |
| Outbound | All traffic | All | 0.0.0.0/0 | Default - allow responses |

---

### 💡 Socratic Q&A: Security Groups

> **Q: Why do we use a security group as the source instead of an IP address?**
>
> **A (Explain Like I'm 10):** Say you want to let "friends from school" into your birthday party. You could write down each friend's home address (IPs), but what if a friend moves? You have to update the list. OR you could just say "anyone wearing a Springfield Elementary shirt can come in." That's like using a security group as the source - anyone who's part of that group gets in automatically.

**Evaluator Question:** *What's the security advantage of SG-to-SG references?*

**Model Answer:** Security group references provide dynamic, self-maintaining firewall rules. When EC2 instances are added or removed from the source security group, access is automatically granted or revoked. This eliminates manual IP management, reduces human error, and scales automatically with infrastructure changes.

---

## PART 2: Create a VPC

1. **VPC Dashboard** → Create VPC (Select "VPC and more")
2. **Custom VPC CIDR:** `10.0.0.0/16`
3. **Availability Zones (AZs):** minimum of 2
4. **NAT Gateway:** none
5. **VPC Endpoints:** none
6. **DNS Options:** ✅ Enable both "DNS hostnames" and "DNS resolution"
7. **Create VPC**

---

## PART 3: Create RDS MySQL Database

### Step 3.1: Navigate to RDS Console

**Action:** AWS Console → RDS → Create database

---

### 💡 Socratic Q&A: Why RDS?

> **Q: Why can't I just install MySQL directly on my EC2 instance? Isn't that simpler?**
>
> **A (Explain Like I'm 10):** Imagine you have a pet goldfish. You could keep it in a bowl in your bedroom and remember to feed it, change the water, check if it's sick, and watch it 24/7. OR you could put it in a fancy aquarium at the pet store where experts do all that for you automatically. RDS is like that fancy aquarium - AWS handles automatic backups, software updates, failover, and monitoring so you can focus on your application.

**Evaluator Question:** *Why did you choose RDS over self-managed MySQL?*

**Model Answer:** RDS provides managed database services including automated backups, patching, failover, and monitoring. This reduces operational overhead and allows us to focus on application development rather than database administration. In production, this also provides better reliability and compliance capabilities.

---

### ✅ Pre-RDS Verification

Before creating the RDS, verify your security group exists:

```bash
# Verify your RDS security group exists and has the right inbound rule
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=lab-rds-sg" \
  --query "SecurityGroups[].{ID:GroupId,Name:GroupName,InboundRules:IpPermissions}" \
  --output json
```

**Expected:** Inbound rule for port 3306 with source = your EC2 security group ID

**⚠️ Troubleshooting:**
- Your CLI command searched for `lab-rds-sg`, but your actual security group name may be different
- Your console may be in another region (e.g., Oregon `us-west-2`), but your CLI may be defaulting to a different region. Set it with: `aws configure set region us-west-2`

---

### Step 3.2: Configure RDS Instance

| Setting | Value | Why This Value? |
|---------|-------|-----------------|
| Engine | MySQL | Industry standard, well-documented |
| Template | Free tier (or Dev/Test) | Cost optimization for learning |
| DB Instance ID | lab-mysql | Descriptive naming convention |
| Master username | admin | Standard admin access |
| Master password | Generate or set | **SAVE THIS SOMEWHERE SAFE** |
| Instance class | db.t3.micro | Sufficient for lab workload |
| Storage | 20 GB gp2 | Minimum for general purpose |

---

### Step 3.3: Configure Connectivity

| Setting | Value | Why? |
|---------|-------|------|
| VPC | Default VPC (or class VPC) | Network isolation |
| Subnet group | Default | Uses multiple AZs |
| Public access | **NO** | Security best practice |
| VPC Security Group | Create new: lab-rds-sg | Firewall rules |

---

### ✅ RDS Verification Commands

```bash
# Check RDS is in the same VPC as your security groups
aws rds describe-db-instances \
  --region us-west-2 \
  --db-instance-identifier lab-mysql \
  --query "DBInstances[].DBSubnetGroup.VpcId" \
  --output text

# List all RDS instances
aws rds describe-db-instances \
  --region us-west-2 \
  --query "DBInstances[].{DB:DBInstanceIdentifier,Status:DBInstanceStatus}" \
  --output table

# Verify NOT publicly accessible
aws rds describe-db-instances \
  --region us-west-2 \
  --db-instance-identifier lab-mysql \
  --query "DBInstances[].PubliclyAccessible" \
  --output text
# Expected: False

# Verify correct security group attached
aws rds describe-db-instances \
  --region us-west-2 \
  --db-instance-identifier lab-mysql \
  --query "DBInstances[].VpcSecurityGroups[].VpcSecurityGroupId" \
  --output text

# Get endpoint (you'll need this later)
aws rds describe-db-instances \
  --region us-west-2 \
  --db-instance-identifier lab-mysql \
  --query "DBInstances[].Endpoint.Address" \
  --output text
# Expected: lab-mysql.<random>.us-west-2.rds.amazonaws.com
```

---

### 💡 Socratic Q&A: Public Access & Connectivity

> **Q: If I set public access to No, how will my EC2 connect to it?**
>
> **A (Explain Like I'm 10):** Imagine your database is a treasure chest. "Public access = Yes" is like putting that chest in the middle of Times Square with a sign saying "Try to open me!" Even with a lock, people will try to break in. "Public access = No" means the chest is locked inside your house (the VPC), and only people who are already inside your house (like your EC2 instance) can even see it exists.

**Evaluator Question:** *Walk me through the network path from EC2 to RDS.*

**Model Answer:** The EC2 instance and RDS are in the same VPC. EC2 connects to RDS using the private DNS endpoint. This resolves to a private IP within the VPC. Traffic flows through the VPC's internal routing - never touching the internet. The RDS security group must allow inbound traffic on port 3306 from the EC2's security group.

> **Q: Why couldn't I create the secret before RDS?**
>
> **A (Explain Like I'm 10):** The secret is like a treasure map with directions to the treasure chest (RDS). If the chest doesn't exist yet, what would the map point to? When you select "Credentials for RDS database," AWS asks "which database?" and auto-fills the endpoint. No database = nothing to point to.

---

## PART 4: Store Credentials in Secrets Manager

### Step 4.1: Navigate to Secrets Manager

**Action:** AWS Console → Secrets Manager → Store a new secret

---

### 💡 Socratic Q&A: Why Secrets Manager?

> **Q: Why can't I just put the password in the code or an environment variable?**
>
> **A (Explain Like I'm 10):** Imagine writing your house key's code on a sticky note on your backpack. Everyone at school can see it! That's like putting passwords in code - anyone who sees the code sees the password. Secrets Manager is like a super-secure vault at a bank. You don't carry the actual treasure; you carry a card that lets you access the vault when you need it.

**Evaluator Question:** *Compare Secrets Manager vs. storing credentials in environment variables.*

**Model Answer:** Environment variables are better than hardcoded credentials but have limitations: they appear in process listings, can be logged accidentally, require manual rotation, and offer no audit trail. Secrets Manager provides encryption at rest and in transit, automatic rotation, CloudTrail auditing, fine-grained IAM access control, and versioning.

> **Q: Why does the secret name in my code have to match exactly?**
>
> **A (Explain Like I'm 10):** Imagine you're at a hotel front desk asking for a package. You say "I'm here to pick up the box for Room 101." If the package is labeled "Room 102," the clerk won't give it to you - even if it's YOUR package! The secret name is like that room number. Your app asks AWS for `lab/rds/mysql`, and AWS looks for EXACTLY that name. `Lab/RDS/MySQL` or `lab-rds-mysql` would fail.

---

### Step 4.2: Configure the Secret

| Setting | Value |
|---------|-------|
| Secret type | Credentials for RDS database |
| Username | admin |
| Password | The password you set for RDS |
| Database | lab-mysql (select from dropdown) |
| Secret name | lab/rds/mysql |

---

### ✅ Secrets Manager Verification

```bash
# List secrets (doesn't expose values)
aws secretsmanager list-secrets \
  --region us-west-2 \
  --query "SecretList[].{Name:Name,ARN:ARN}" \
  --output table

# Describe your specific secret (no value exposed)
aws secretsmanager describe-secret \
  --region us-west-2 \
  --secret-id lab/rds/mysql \
  --output json
```

---

## PART 5: Create IAM Role for EC2

### Step 5.1: Navigate to IAM

**Action:** AWS Console → IAM → Roles → Create role

**Steps:**
1. **IAM Console** → **Policies** → **Create policy**
   - **JSON Tab:** Paste the secretsmanager:GetSecretValue JSON
   - **Name:** `SecretsManagerReadPolicy`
2. **IAM Console** → **Roles** → **Create role**
   - **Select trusted entity:** AWS service → EC2
   - **Permissions:** Add the new policy you just created
   - **Name:** `lab-ec2-app-role`

---

### 💡 Socratic Q&A: IAM Roles vs Access Keys

> **Q: Why can't I just create an IAM user with access keys and use those in the app?**
>
> **A (Explain Like I'm 10):** Access keys are like giving your friend a permanent copy of your house key. Even after they move to another country, they still have that key forever. IAM roles are like a hotel key card. It only works for your specific room (your EC2), during your stay (temporary credentials), and the hotel knows exactly who used it when (CloudTrail).

**Evaluator Question:** *Explain how EC2 instance profiles work with IAM roles.*

**Model Answer:** An instance profile is a container for an IAM role attached to an EC2 instance. When an application calls AWS APIs, the SDK automatically retrieves temporary credentials from the Instance Metadata Service (IMDS) at 169.254.169.254. These credentials are rotated automatically before expiration. The application never sees long-term credentials.

---

### Step 5.2: Configure the IAM Role

| Setting | Value |
|---------|-------|
| Trusted entity type | AWS service |
| Use case | EC2 |
| Role name | lab-ec2-app-role |

---

### Step 5.3: Create Inline Policy (Least Privilege)

**Policy Name:** `SecretsManagerReadPolicy`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadSpecificSecret",
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:<REGION>:<ACCOUNT_ID>:secret:lab/rds/mysql*"
    }
  ]
}
```

> ⚠️ **Replace `<REGION>` and `<ACCOUNT_ID>` with your actual values!**

---

### ✅ IAM Role Verification

```bash
# 1. Verify the role exists
aws iam get-role \
  --role-name lab-ec2-app-role \
  --query "Role.{Name:RoleName,Arn:Arn}" \
  --output table

# 2. Verify EC2 can assume this role (trusted entity)
aws iam get-role \
  --role-name lab-ec2-app-role \
  --query "Role.AssumeRolePolicyDocument.Statement[].Principal"
# Expected: {"Service": "ec2.amazonaws.com"}

# 3. Verify the policy is attached
aws iam list-attached-role-policies \
  --role-name lab-ec2-app-role \
  --output table
```

---

### 💡 Socratic Q&A: Least Privilege

> **Q: AWS has a managed policy called SecretsManagerReadWrite. Why not just use that?**
>
> **A (Explain Like I'm 10):** The managed policy is like giving someone a master key to EVERY room in a building. Our inline policy is like giving them a key to just one room - the room they actually need. This is "least privilege" - give only the exact permissions needed, nothing more.

**Evaluator Question:** *How would you audit this role's permissions?*

**Model Answer:** I'd use IAM Access Analyzer to check for overly permissive policies, review the role's attached policies via CLI, and use CloudTrail to see which API calls the role actually makes. If the role never calls certain allowed actions, I'd tighten the policy further.

---

## PART 6: Launch EC2 Instance

### Step 6.1: Configure EC2 Instance

**Action:** AWS Console → EC2 → Launch instance

| Setting | Value | Why? |
|---------|-------|------|
| Name | lab-ec2-app | Descriptive |
| AMI | Amazon Linux 2023 | Modern, well-supported |
| Instance type | t3.micro | Free tier eligible |
| Key pair | Create new or select existing | For SSH access |
| Network | Same VPC as RDS | Must be able to reach DB |
| Subnet | Choose public | For web access |
| Security group | lab-ec2-sg | Firewall rules |
| IAM Instance Profile | lab-ec2-app-role | Access to secrets |
| Auto-assign public IP | Enabled | Auto-creation of public URL |

---

### 💡 Socratic Q&A: SSH Security

> **Q: Why do we restrict SSH to 'My IP' instead of allowing from anywhere?**
>
> **A (Explain Like I'm 10):** SSH is like the master key to your entire house. Would you leave copies at every store in town? No! You keep the master key only where you need it. '0.0.0.0/0' means EVERY computer in the world can try your lock. 'My IP' means only your current location can even attempt to connect.

**Evaluator Question:** *How would you secure SSH access in production?*

**Model Answer:** In production, I would not expose SSH directly. Instead, I'd use AWS Systems Manager Session Manager for shell access - it requires IAM authentication, logs all sessions to CloudWatch, and doesn't require open security group ports. For environments requiring SSH, a bastion host with strict IP allowlisting provides defense in depth.

---

### Step 6.2: Attach Role to EC2 Instance

**Action:** EC2 Console → Select instance → Actions → Security → Modify IAM role → Select your role

---

### ✅ EC2 Verification

```bash
# Check which role is attached to the EC2
aws ec2 describe-instances \
  --region us-west-2 \
  --filters "Name=tag:Name,Values=lab-ec2-app" \
  --query "Reservations[].Instances[].IamInstanceProfile.Arn" \
  --output text
# Expected: Contains 'lab-ec2-app-role'

# Get more instance details
aws ec2 describe-instances \
  --region us-west-2 \
  --filters "Name=tag:Name,Values=lab-ec2-app" \
  --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,PublicIP:PublicIpAddress,IAMRole:IamInstanceProfile.Arn}" \
  --output table
```

---

### Step 6.3: Verify RDS and SGs in Same VPC

This creates the trust relationship: "RDS accepts traffic from anything in the EC2 security group"

```bash
# RDS VPC
aws rds describe-db-instances \
  --region us-west-2 \
  --db-instance-identifier lab-mysql \
  --query "DBInstances[].DBSubnetGroup.VpcId" \
  --output text

# EC2 VPC
aws ec2 describe-instances \
  --region us-west-2 \
  --filters "Name=tag:Name,Values=lab-ec2-app" \
  --query "Reservations[].Instances[].VpcId" \
  --output text

# Both should return the SAME VPC ID!
```

---

## PART 7: Deploy the Flask Application

> ⚠️ **Note:** Make sure you haven't broken any infrastructure that affects the lab. For example, destroying a previously-connected Internet Gateway will result in a cascade of failures (no internet access = dependencies won't install).

### Step 7.1: SSH into EC2

```bash
ssh -i <your-key>.pem ec2-user@<EC2_PUBLIC_IP>
```

---

### Step 7.2: Install Dependencies

```bash
# Update system
sudo dnf update -y

# Install Python and pip
sudo dnf install -y python3-pip

# Install Flask, MySQL connector, and boto3
sudo pip3 install flask pymysql boto3
```

---

### 💡 Socratic Q&A: Why boto3?

> **Q: Why are we using boto3 instead of just hardcoding the database connection string?**
>
> **A (Explain Like I'm 10):** Imagine you have a secret decoder ring that only works when you're wearing your special watch (the IAM role). boto3 is like that decoder ring - it automatically uses your EC2's special permissions to decode secrets from the vault. If someone steals your code, they still can't decode anything because they don't have the special watch.

**Evaluator Question:** *What happens if the EC2 instance doesn't have the IAM role attached when the app tries to read from Secrets Manager?*

**Model Answer:** The boto3 call will fail with an AccessDeniedException. The SDK looks for credentials in a specific order: environment variables, shared credentials file, EC2 instance metadata. Without the role, there are no valid credentials, and the API call is rejected. This is defense in depth - even if code is compromised, credentials aren't exposed.

---

### Step 7.3: Create the Application (User Data Script)

The application is deployed via User Data script. Key components:

- **`/init` endpoint:** Creates the database and notes table
- **`/add` endpoint:** Inserts a note into the database
- **`/list` endpoint:** Retrieves all notes from the database

---

### Step 7.4: Test the Application

```bash
# Initialize the database
http://<EC2_PUBLIC_IP>/init

# Add a note
http://<EC2_PUBLIC_IP>/add?note=first_note

# List all notes
http://<EC2_PUBLIC_IP>/list
```

---

## 🔧 Common Failure Modes & Troubleshooting

**If /init hangs or errors, it's almost always one of these:**

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Can't connect to RDS / Timeout | Security group misconfigured | Verify SG source is lab-ec2-sg on port 3306 |
| Timeout connecting to RDS | Different VPCs | Verify both resources in same VPC |
| Access Denied from Secrets Manager | IAM role not attached | Check instance profile and policy ARN |
| No module named flask | Not installed globally | Use `sudo pip3 install` |
| Port 80 connection refused | App not running as root | Use `sudo python3` |

---

### ✅ Troubleshooting Script (Run from EC2)

```bash
# 1. Verify EC2 identity
aws sts get-caller-identity
# Expected: Contains 'lab-ec2-app-role'

# 2. Test Secrets Manager access
aws secretsmanager describe-secret \
  --secret-id lab/rds/mysql \
  --region us-west-2
# Expected: Secret metadata (no AccessDenied)

# 3. Test secret value retrieval
aws secretsmanager get-secret-value \
  --secret-id lab/rds/mysql \
  --region us-west-2 \
  --query "SecretString" \
  --output text
# Expected: JSON with username, password, host, port
```

---

## ✅ Final Verification Checklist

```bash
# 1. RDS is private
aws rds describe-db-instances \
  --db-instance-identifier lab-mysql \
  --query "DBInstances[].PubliclyAccessible" \
  --output text
# Expected: False

# 2. EC2 and RDS in same VPC (compare outputs)
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=lab-ec2-app" \
  --query "Reservations[].Instances[].VpcId" \
  --output text

aws rds describe-db-instances \
  --db-instance-identifier lab-mysql \
  --query "DBInstances[].DBSubnetGroup.VpcId" \
  --output text

# 3. EC2 has IAM role attached
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=lab-ec2-app" \
  --query "Reservations[].Instances[].IamInstanceProfile.Arn" \
  --output text
# Expected: Contains 'lab-ec2-app-role'

# 4. RDS security group allows EC2 security group
aws ec2 describe-security-groups \
  --group-names lab-rds-sg \
  --query "SecurityGroups[].IpPermissions[].UserIdGroupPairs[].GroupId" \
  --output text
# Expected: The security group ID of lab-ec2-sg
```

---

## 📝 Student Deliverables

### 1. Screenshots
- RDS SG inbound rule using source = lab-ec2-sg
- EC2 role attached
- `/list` output showing at least 3 notes

### 2. Short Answers

#### A) Why is DB inbound source restricted to the EC2 security group?

**Answer:**

Restricting the RDS inbound source to the EC2 security group implements the **principle of least privilege** - only the specific resources that need database access can reach it.

Using security-group-to-security-group referencing (instead of IP addresses) provides three key benefits:

1. **Dynamic membership** - If we add more EC2 instances to the app security group, they automatically gain database access without modifying RDS rules
2. **No IP management** - EC2 IPs can change on stop/start; security group references don't break
3. **Defense in depth** - Even if an attacker knows the RDS endpoint, they can't connect unless they're inside a resource belonging to the trusted security group

This is how production environments restrict database access to only the application tier.

#### B) What port does MySQL use?

**Answer:**

MySQL uses **port 3306** by default.

This is why our RDS security group inbound rule specifically allows TCP traffic on port 3306 from the EC2 security group. If this port is blocked, the Flask application's pymysql connection will timeout or be refused.

#### C) Why is Secrets Manager better than storing creds in code/user-data?

**Answer:**

| Concern | Hardcoded Creds | Secrets Manager |
|---------|-----------------|-----------------|
| **Git exposure** | Credentials committed = leaked forever | Only secret ID in code |
| **Rotation** | Must redeploy app to change passwords | Rotate without touching app |
| **Access control** | Anyone with code access sees creds | IAM policies control access |
| **Audit trail** | No record of who accessed credentials | CloudTrail logs every access |
| **Encryption** | Plaintext in files | Encrypted at rest and in transit |

In our lab, the EC2 instance uses its IAM role to call `secretsmanager:GetSecretValue` at runtime. The credentials never exist in the code or user-data script - only a reference to the secret name (`lab/rds/mysql`). If the password is compromised, we update Secrets Manager once rather than redeploying every server.

### 3. Evidence Files (Exported as JSON)

```bash
aws ec2 describe-security-groups --group-ids sg-xxx > sg.json
aws rds describe-db-instances --db-instance-identifier lab-mysql > rds.json
aws secretsmanager describe-secret --secret-id lab/rds/mysql > secret.json
aws ec2 describe-instances --instance-ids i-xxx > instance.json
aws iam list-attached-role-policies --role-name lab-ec2-app-role > role-policies.json
```

---

## 🤔 Reflection Questions

*Answer all of these to solidify your understanding:*

**1. Why is 'defense in depth' important?**
> Even if one layer fails, other layers still protect you.

**2. What's the principle of least privilege?**
> Give only the minimum permissions needed.

**3. How do you verify 'as built' vs 'as designed'?**
> Use CLI commands to check actual state.

**4. What's the difference between authentication and authorization?**
> Authentication = who you are; Authorization = what you can do.

---

## 🎯 What This Lab Proves About You

*If you complete this lab correctly, you can say:*

> **"I understand how real AWS applications securely connect compute to managed databases."**

That is a non-trivial claim in the job market.

---

## ⏭️ What's Next: Lab 1B & 1C

### Lab 1B: Operations, Secrets & Incident Response
- Dual secret storage (Parameter Store + Secrets Manager)
- CloudWatch Logs for application monitoring
- Automated alarms when database connectivity fails
- Incident-response and recovery procedures

### Lab 1C: Terraform Infrastructure as Code
- Recreate entire infrastructure with Terraform
- Bonus: ALB, TLS with ACM, WAF, CloudWatch Dashboard
- Enterprise-grade deployment pattern

---

## 📚 Resources

- [AWS RDS Documentation](https://docs.aws.amazon.com/rds/)
- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [EC2 Security Groups](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)
