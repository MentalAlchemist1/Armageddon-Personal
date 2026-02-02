# SEIR FOUNDATIONS
# LAB 1B: Operations, Secrets & Incident Response

## *Enhanced Socratic Q&A Guide*

---

> ⚠️ **PREREQUISITE**
> 
> Lab 1a must be completed and verified before starting Lab 1b.
> 
> You must have:
> - Working EC2 instance with IAM role attached
> - RDS MySQL instance (private, in same VPC as EC2)
> - Security groups configured (EC2 → RDS on port 3306)
> - Secrets Manager secret with DB credentials

---

## Lab Overview

In Lab 1a, you built a working system. In Lab 1b, you will **operate, observe, break, and recover** that system.

*"Anyone can deploy. Professionals recover."*

---

## Why This Lab Exists (Real-World Context)

Most cloud failures are **NOT** caused by bad code or wrong instance sizes. They are caused by:

- Credential issues
- Secret rotation failures
- Misconfigured access
- Silent connectivity loss
- Poor observability

**This lab teaches you how to design for failure, detect it early, and recover using stored configuration data.**

**Rule of thumb:** There are a lot of commands to run in this lab. If a command changes something but returns nothing, follow it with a `describe-*` or `get-*` to confirm, if you want.

### CASE PREVIEW: Correct Failure Classification

> Database unavailability caused connection failures. The application could not reach RDS after the instance was stopped. Logs showed connection timeouts, and the DBConnectionErrors metric exceeded the threshold of 3 errors in 5 minutes. 

**Recovery Without Redeploy: Summary**
> 1. Started RDS: `aws rds start-db-instance --db-instance-identifier lab-mysql`
> 2. Waited for status: `available`
> 3. Verified app recovery: `curl http://54.218.85.165/list`
> 4. No EC2 restart or code changes required
---

# PART 1: Create Parameter Store Entries

---

## 🎯 The Big Picture: Why Parameter Store?

> **SOCRATIC Q&A**
>
> ***Q:** Why do we need BOTH Parameter Store AND Secrets Manager? Isn't that redundant?*
>
> **A (Explain Like I'm 10):** Imagine you have a treasure map (Parameter Store) and a locked treasure chest (Secrets Manager). The map tells you WHERE to go - the endpoint, the port, the database name. The chest holds the actual treasure - the password. You need both to complete your quest! The map isn't secret (everyone knows the address), but the key to the chest must be protected.
>
> **Evaluator Question:** *Why might Parameter Store still exist alongside Secrets Manager in enterprise environments?*
>
> **Model Answer:** Parameter Store is optimized for configuration data that changes infrequently and doesn't need rotation - endpoints, ports, feature flags, environment settings. Secrets Manager is designed for credentials requiring rotation, audit trails, and encryption. Using both provides separation of concerns: config data is cheap and fast to retrieve, while secrets have stronger access controls and audit capabilities. Many companies use Parameter Store for non-sensitive config (free tier, simpler) and Secrets Manager for actual credentials.

### Comparison: Parameter Store vs Secrets Manager

| Feature | Parameter Store | Secrets Manager |
|---------|-----------------|-----------------|
| Best for | Configuration values, endpoints, flags | Credentials, passwords, API keys |
| Rotation | Manual | Automatic rotation supported |
| Cost | Free tier available | Per-secret pricing |
| Encryption | Optional (SecureString) | Always encrypted |
| Audit | CloudTrail | CloudTrail + tighter integration |

---

## Step 1.1: Get Your RDS Endpoint

### Why This Step?

Before you can tell your application WHERE to connect, you need to know the address. Think of this like looking up a phone number before making a call.

> **SOCRATIC Q&A**
>
> ***Q:** Why can't I just hardcode the RDS endpoint in my application code?*
>
> **A (Explain Like I'm 10):** Imagine writing your friend's phone number directly on your arm with a permanent marker. Works great until they get a new number! Then you're stuck with wrong info that's hard to change. Parameter Store is like a contact list on your phone - when the number changes, you update ONE place, and everyone who looks it up gets the new number automatically.
>
> **Evaluator Question:** *What happens to your application if the RDS endpoint changes (e.g., during a restore or migration)?*
>
> **Model Answer:** If the endpoint is hardcoded, the application breaks and requires redeployment. If the endpoint is in Parameter Store, you update ONE parameter, and the application picks up the new value on next read (or restart). This reduces Mean Time To Recovery (MTTR) from "redeploy everything" to "change one value."

### The Command

```bash
aws rds describe-db-instances \
  --db-instance-identifier lab-mysql \
  --query "DBInstances[0].Endpoint.Address" \
  --output text
```

**Single-line version** (if you have copy-paste issues):

```bash
aws rds describe-db-instances --db-instance-identifier lab-mysql --query "DBInstances[0].Endpoint.Address" --output text
```

### Expected Output

```
lab-mysql.xxxxxxxxxx.us-west-2.rds.amazonaws.com
```


> 💡 **TIP**
> 
> Save this value! You'll need it in the next step.

---

## Step 1.2: Create the Parameters

### Why Three Separate Parameters?

> **SOCRATIC Q&A**
>
> ***Q:** Why not just store the entire connection string as one parameter?*
>
> **A (Explain Like I'm 10):** Imagine your LEGO instructions came as one giant paragraph instead of separate steps. Harder to read, harder to fix if something's wrong! Three separate parameters means: (1) If the port changes, you update just the port, (2) If you need to point to a different database, you change just the name, (3) Debugging is easier - you can check each piece individually.
>
> **Evaluator Question:** *How does parameter separation support the principle of least privilege?*
>
> **Model Answer:** Different applications might need different parameters. A reporting tool might only need the endpoint and port (read-only access), while an admin tool needs all three. Separating parameters lets you grant access to specific values, not an all-or-nothing connection string.

### Parameters to Create

| Parameter Name | Type | Value | Purpose |
|----------------|------|-------|---------|
| `/lab/db/endpoint` | String | Your RDS endpoint | WHERE to connect |
| `/lab/db/port` | String | 3306 | WHICH door to knock on |
| `/lab/db/name` | String | labdb | WHICH room to enter |

### Why the Naming Convention `/lab/db/...`?

> **SOCRATIC Q&A**
>
> ***Q:** Why use slashes in parameter names like a file path?*
>
> **A (Explain Like I'm 10):** Imagine your toy box. If you just throw everything in, finding your favorite LEGO is chaos! But if you organize: Toys → Building → LEGOs → Star Wars → Millennium Falcon, you can find things fast. The slashes create "folders" for your parameters: `/lab/` is the project, `/db/` is the database stuff, `/endpoint` is the specific value.
>
> **Evaluator Question:** *How does hierarchical naming affect IAM policies?*
>
> **Model Answer:** IAM policies can use wildcards on paths. A policy allowing `ssm:GetParameter` on `/lab/db/*` grants access to all database parameters but nothing else. This enables team-based access control: the database team gets `/lab/db/*`, the cache team gets `/lab/cache/*`, etc.

### The Commands

```bash
# Create endpoint parameter
# Replace <YOUR_RDS_ENDPOINT> with the value from Step 1.1
aws ssm put-parameter \
  --name "/lab/db/endpoint" \
  --value "<YOUR_RDS_ENDPOINT>" \
  --type String
```

```bash
# Create port parameter
aws ssm put-parameter \
  --name "/lab/db/port" \
  --value "3306" \
  --type String
```

```bash
# Create database name parameter
aws ssm put-parameter \
  --name "/lab/db/name" \
  --value "labdb" \
  --type String
```

**Single-line versions:**

```bash
aws ssm put-parameter --name "/lab/db/endpoint" --value "<YOUR_RDS_ENDPOINT>" --type String
```

```bash
aws ssm put-parameter --name "/lab/db/port" --value "3306" --type String
```

```bash
aws ssm put-parameter --name "/lab/db/name" --value "labdb" --type String
```

### Expected Output (for each command)

```json
{
    "Version": 1,
    "Tier": "Standard"
}
```


**What does "Version: 1" mean?**
Parameter Store tracks versions. If you update a parameter, it becomes Version 2. This lets you roll back to previous values if needed - like "undo" for your configuration!

---

## Step 1.3: Verify Parameters

### Why Verify?

> **SOCRATIC Q&A**
>
> ***Q:** I just created them - why do I need to verify?*
>
> **A (Explain Like I'm 10):** When you mail a birthday card, do you just drop it in the mailbox and HOPE it arrives? Or do you ask grandma "Did you get my card?" Verification is asking "Did it arrive?" In cloud engineering, we call this "trust but verify" - don't assume it worked, PROVE it worked.
>
> **Evaluator Question:** *What's the difference between "as designed" and "as built" in infrastructure?*
>
> **Model Answer:** "As designed" is what you INTENDED to create. "As built" is what ACTUALLY exists. They can differ due to typos, permissions issues, regional differences, or silent failures. Professional engineers verify "as built" matches "as designed" using CLI commands, not just trusting the console.

### The Command

```bash
aws ssm get-parameters \
  --names /lab/db/endpoint /lab/db/port /lab/db/name --with-decryption
```

### Expected Output

```json
{
    "Parameters": [
        {
            "Name": "/lab/db/endpoint",
            "Value": "lab-mysql.xxxxxxxxxx.us-west-2.rds.amazonaws.com",
            ...
        },
        {
            "Name": "/lab/db/port",
            "Value": "3306",
            ...
        },
        {
            "Name": "/lab/db/name",
            "Value": "labdb",
            ...
        }
    ],
    "InvalidParameters": []
}
```


> ✅ **VERIFICATION CHECKLIST**
> 
> - [ ] All three parameters returned
> - [ ] `InvalidParameters` array is empty
> - [ ] Values match what you intended

---

# PART 2: Create CloudWatch Log Group

---

## 🎯 The Big Picture: Why CloudWatch Logs?

> **SOCRATIC Q&A**
>
> ***Q:** Why do we need to ship logs to CloudWatch? Can't I just SSH in and check the logs on the server?*
>
> **A (Explain Like I'm 10):** Imagine your house is on fire. Would you run INSIDE to check your security cameras, or would you rather watch the footage from your phone outside? CloudWatch is like having all your cameras feed to your phone. When things go wrong (and they will), you want to see what happened WITHOUT logging into the burning server - which might be crashed, unreachable, or too dangerous to touch.
>
> **Evaluator Question:** *What breaks first during a production incident, and how do CloudWatch logs help?*
>
> **Model Answer:** Usually connectivity or credentials break first, which means you can't SSH in to check logs. CloudWatch provides: (1) Log persistence even if EC2 terminates, (2) Searchable history across time windows, (3) Metric extraction for alerting, (4) Correlation with other AWS services. During incidents, teams query CloudWatch first because it's always accessible and doesn't require touching the potentially broken system.

---

## Step 2.1: Create the Log Group

### Why Create It Manually?

> **SOCRATIC Q&A**
>
> ***Q:** Why create the log group before the application? Can't the app create it automatically?*
>
> **A (Explain Like I'm 10):** Imagine you're moving to a new house. You COULD show up with all your furniture and hope there's a house there... or you could make sure the house exists FIRST. Creating the log group first means: (1) You control the settings (like retention), (2) You know exactly where logs will go, (3) If the app fails to start, you still have somewhere to investigate.
>
> **Evaluator Question:** *What IAM permissions does the application need to write to CloudWatch Logs?*
>
> **Model Answer:** The application needs `logs:CreateLogStream` and `logs:PutLogEvents` on the specific log group. If you pre-create the log group, you don't need `logs:CreateLogGroup`. This follows least privilege - the app can write logs but can't create arbitrary log groups.

### The Command

```bash
aws logs create-log-group --log-group-name /aws/ec2/lab-rds-app
```

The `aws logs create-log-group` command is a **silent success** - it returns **no output** if it works correctly.

Verification wanted?
aws logs describe-log-groups --log-group-name-prefix /aws/ec2/lab-rds-app


### Why This Naming Convention?

| Path Segment | Meaning |
|--------------|---------|
| `/aws/` | AWS-related logs (convention) |
| `ec2/` | Logs from EC2 instances |
| `lab-rds-app` | Our specific application |

---

## Step 2.2: Set Retention Policy

### Why Set Retention?

> **SOCRATIC Q&A**
>
> ***Q:** Why do we set log retention to 7 days? Shouldn't we keep logs forever?*
>
> **A (Explain Like I'm 10):** Logs are like video recordings. If you kept EVERY recording from EVERY camera in your house forever, you'd run out of storage (and money) really fast! 7 days is enough to investigate recent problems. In real jobs, companies keep important logs longer (30-90 days or more), but they archive older logs to cheaper storage - like moving old photos to a backup hard drive instead of keeping them on your phone.
>
> **Evaluator Question:** *How does log retention policy affect incident response and compliance?*
>
> **Model Answer:** Log retention is a balance between cost, compliance, and operational needs. 7 days covers most immediate incident investigations. Production environments typically retain 30-90 days in CloudWatch (hot storage), then archive to S3 (cold storage) for compliance periods (1-7 years depending on regulations). The key is ensuring logs exist when you need them for root cause analysis while managing storage costs.

### The Command

```bash
aws logs put-retention-policy --log-group-name /aws/ec2/lab-rds-app --retention-in-days 7
```

Another **silent success** command. Here's the verification: 
aws logs describe-log-groups --log-group-name-prefix /aws/ec2/lab-rds-app --query "logGroups[*].[logGroupName,retentionInDays]" --output table


```

### Expected Output
```
-----------------------------------------
|          DescribeLogGroups            |
+-------------------------+-------------+
|  /aws/ec2/lab-rds-app   |  7          |
+-------------------------+-------------+

### Common Retention Periods

| Days | Use Case |
|------|----------|
| 1-7 | Development, labs |
| 30 | Production troubleshooting |
| 90 | Standard compliance |
| 365+ | Regulated industries (healthcare, finance) |

---

## Step 2.3: Verify Log Group

### The Command

```bash
aws logs describe-log-groups --log-group-name-prefix /aws/ec2/lab-rds-app
```

### Expected Output

```json
{
    "logGroups": [
        {
            "logGroupName": "/aws/ec2/lab-rds-app",
            "retentionInDays": 7,
            ...
        }
    ]
}
```


> ✅ **VERIFICATION CHECKLIST**
> 
> - [ ] Log group exists
> - [ ] `retentionInDays` is 7


---

# PART 3: Create SNS Topic for Alerts

---

## 🎯 The Big Picture: Why SNS?

> **SOCRATIC Q&A**
>
> ***Q:** Why do we need alerts? Can't I just check the dashboard when something feels wrong?*
>
> **A (Explain Like I'm 10):** Imagine you're sleeping and your house starts flooding. Would you rather: (A) Hope you wake up and notice the water, or (B) Have a water sensor that SCREAMS at you the moment it detects a leak? Alarms are like that screaming sensor. Problems don't wait for you to check dashboards - they happen at 3 AM on holidays. Alarms make sure YOU know before your USERS know.
>
> **Evaluator Question:** *What's the difference between SNS and a direct email notification?*
>
> **Model Answer:** SNS is a pub/sub (publish-subscribe) system. One alarm publishes to a topic; many things can subscribe (email, SMS, Lambda, Slack via Lambda, PagerDuty, etc.). If you hardcoded email, adding SMS later means changing the alarm. With SNS, you just add another subscriber. It's the difference between a mailing list (SNS) and sending individual emails.

---

## Step 3.1: Create the SNS Topic

### Why "Topic"?

Think of a topic like a radio station. The alarm "broadcasts" to the station, and anyone "tuned in" (subscribed) hears the message.

### The Command

```bash
aws sns create-topic --name lab-db-incidents
```

### Expected Output

```json
{
    "TopicArn": "arn:aws:sns:us-west-2:123456789012:lab-db-incidents"
}
```

 *TopicArn: "arn:aws:sns:us-west-2:262164343754:lab-db-incidents

> ⚠️ **IMPORTANT**
> 
> **Save the TopicArn!** You'll need it for the alarm and subscription.
> 
> Your TopicArn will look like: `arn:aws:sns:<REGION>:<ACCOUNT_ID>:lab-db-incidents`

---

## Step 3.2: Subscribe Your Email

### Why Subscribe?

> **SOCRATIC Q&A**
>
> ***Q:** Why do I need to subscribe? Doesn't creating the topic mean I'll get alerts?*
>
> **A (Explain Like I'm 10):** Creating the topic is like setting up a radio station. But you still need to tune your radio to that station! Subscribing is "tuning in." Without subscribers, the alarm screams into the void - no one hears it.
>
> **Evaluator Question:** *In production, why might you subscribe a Lambda function instead of (or in addition to) email?*
>
> **Model Answer:** Lambda enables automated response. Email tells a human; Lambda can automatically: (1) Create a Jira ticket, (2) Post to Slack/Teams, (3) Trigger auto-remediation (restart service, scale up), (4) Page on-call via PagerDuty API. The goal is reducing MTTR - human reads email in minutes; Lambda responds in seconds.

### The Command

Replace `<ACCOUNT_ID>` with your AWS account ID and `<YOUR_EMAIL>` with your actual email:

```bash
aws sns subscribe --topic-arn arn:aws:sns:us-west-2:<ACCOUNT_ID>:lab-db-incidents --protocol email --notification-endpoint <YOUR_EMAIL>
```

### How to Find Your Account ID

```bash
aws sts get-caller-identity --query "Account" --output text
```

> ⚠️ **CRITICAL: CONFIRM YOUR SUBSCRIPTION!**
> 
> 1. Check your email inbox (and spam folder!)
> 2. Click the **Confirm subscription** link
> 3. You will NOT receive alerts until confirmed!

---

## Step 3.3: Verify Subscription

### The Command

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:us-west-2:<ACCOUNT_ID>:lab-db-incidents
```

### Expected Output (AFTER confirming email)

```json
{
    "Subscriptions": [
        {
            "SubscriptionArn": "arn:aws:sns:us-west-2:123456789012:lab-db-incidents:abc123...",
            "Protocol": "email",
            "Endpoint": "your-email@example.com"
        }
    ]
}
```


> ✅ **VERIFICATION CHECKLIST**
> 
> - [ ] `SubscriptionArn` shows a full ARN (not `PendingConfirmation`)
> - [ ] `Endpoint` shows your email

---

# PART 4: Create CloudWatch Alarm

---

## 🎯 The Big Picture: Why Alarms?

> **SOCRATIC Q&A**
>
> ***Q:** Why should alarms be based on symptoms instead of causes?*
>
> **A (Explain Like I'm 10):** Imagine your car has a "check engine" light. That light doesn't tell you exactly what's wrong - it just says "something's wrong with the engine." That's a SYMPTOM alarm. If you only had alarms for specific things like "oil low" or "spark plug bad," you'd miss problems you didn't anticipate. Our "DBConnectionErrors" alarm is a symptom - it catches ALL connection problems, even ones we didn't think of.
>
> **Evaluator Question:** *Why should alarms be based on symptoms instead of causes?*
>
> **Model Answer:** Symptom-based alarms (like 'users can't load data') catch ALL problems, even ones you didn't anticipate. Cause-based alarms (like 'RDS CPU high') only catch specific issues. Example: If credentials drift, RDS CPU looks fine but users still can't connect. A symptom alarm (DB connection errors) catches this; a cause alarm (CPU) doesn't. Alert on what users experience, then investigate the cause.

---

## Step 4.1: Understand the Alarm Configuration

### Why These Settings?

| Setting | Value | Why This Value? |
|---------|-------|-----------------|
| Metric Name | `DBConnectionErrors` | Custom metric our app pushes when DB connections fail |
| Namespace | `Lab/RDSApp` | Groups our metrics separately from AWS default metrics |
| Statistic | `Sum` | We want TOTAL errors, not average |
| Period | `300` (5 min) | Window to evaluate - long enough to catch patterns |
| Threshold | `3` | 1-2 might be transient; 3+ suggests real problem |
| Evaluation Periods | `1` | Trigger immediately after first breach |
| treat-missing-data | `notBreaching` | No data = probably no errors = don't alarm |

> **SOCRATIC Q&A**
>
> ***Q:** Why is the threshold 3 instead of 1? Won't we miss problems?*
>
> **A (Explain Like I'm 10):** Imagine if your smoke detector went off every time you made toast. You'd start ignoring it! That's "alert fatigue." Setting threshold to 3 means: one hiccup? Fine. Two? Hmm. THREE? Okay, something's actually wrong. You want alarms sensitive enough to catch real problems but not so sensitive they cry wolf.
>
> **Evaluator Question:** *What is "alert fatigue" and why is it dangerous?*
>
> **Model Answer:** Alert fatigue occurs when too many false or low-priority alerts cause operators to ignore all alerts. It's like the boy who cried wolf. When a REAL incident occurs, the alert gets lost in the noise. Studies show that teams with >50% false positive rate start ignoring alerts entirely. Proper threshold tuning balances sensitivity (catching real issues) with specificity (avoiding false alarms).

---

## Step 4.2: Create the Alarm

### The Command

Replace `<ACCOUNT_ID>` with your AWS account ID:

```bash
aws cloudwatch put-metric-alarm --alarm-name lab-db-connection-failure --alarm-description "Alarm when the app fails to connect to RDS" --metric-name DBConnectionErrors --namespace Lab/RDSApp --statistic Sum --period 300 --threshold 3 --comparison-operator GreaterThanOrEqualToThreshold --evaluation-periods 1 --treat-missing-data notBreaching --alarm-actions arn:aws:sns:us-west-2:<ACCOUNT_ID>:lab-db-incidents
```

### Expected Output

**Silent success** (no output = it worked)

Also, I chose --treat-missing-data `notBreaching`, so when there's no metric data (because my app isn't deployed yet), CloudWatch says "no news is good news" → **OK**.

### What Happens When This Alarm Fires?

```
App fails to connect to DB
        ↓
App pushes "DBConnectionErrors" metric to CloudWatch
        ↓
CloudWatch evaluates: "Sum of errors in last 5 min >= 3?"
        ↓ YES
Alarm state changes: OK → ALARM
        ↓
CloudWatch publishes to SNS topic
        ↓
SNS sends email to all subscribers
        ↓
YOU get an email at 3 AM 📧🔔
```

---

## Step 4.3: Verify the Alarm

### The Command

```bash
aws cloudwatch describe-alarms --alarm-names lab-db-connection-failure
```


> ✅ **VERIFICATION CHECKLIST**
> 
> - [ ] Alarm exists
> - [ ] `StateValue` is `OK` or `INSUFFICIENT_DATA`
> - [ ] `AlarmActions` contains your SNS topic ARN

---

# PART 5: Update IAM Role Permissions

---

## 🎯 The Big Picture: Why Update Permissions?

> **SOCRATIC Q&A**
>
> ***Q:** We already have an IAM role from Lab 1a. Why do we need to add more permissions?*
>
> **A (Explain Like I'm 10):** In Lab 1a, your EC2 had a key to ONE room: the Secrets Manager room. Now we're asking it to also write to the CloudWatch room and read from the Parameter Store room. You need to give it keys to those rooms too! This is "least privilege" - start with nothing, add only what you need.
>
> **Evaluator Question:** *Why is it better to add permissions incrementally rather than giving broad permissions upfront?*
>
> **Model Answer:** Incremental permissions follow the principle of least privilege. Benefits: (1) Limits blast radius if credentials are compromised, (2) Makes it clear what each component needs, (3) Easier to audit - "why does this need X?" is answerable, (4) Reduces risk of accidental data access. Broad permissions hide dependencies and create security risks.

---

## Step 5.1: Identify Required Permissions

### What the Application Needs

| Action | AWS Permission | Why |
|--------|---------------|-----|
| Read parameters | `ssm:GetParameters` | Get DB endpoint, port, name |
| Write logs | `logs:CreateLogStream`, `logs:PutLogEvents` | Send logs to CloudWatch |
| Push metrics | `cloudwatch:PutMetricData` | Push DBConnectionErrors metric |

### Managed Policies That Provide These

| Policy Name | Provides |
|-------------|----------|
| `CloudWatchAgentServerPolicy` | CloudWatch Logs + Metrics permissions |
| `AmazonSSMReadOnlyAccess` | Parameter Store read access |

---

## Step 5.2: Add the Policies via Console

### Navigation

**IAM Console → Roles → `<your role name>` → Add permissions → Attach policies**

### Policies to Add

1. ✅ `CloudWatchAgentServerPolicy`
2. ✅ `AmazonSSMReadOnlyAccess`

> **SOCRATIC Q&A**
>
> ***Q:** Why use managed policies instead of writing our own?*
>
> **A (Explain Like I'm 10):** Managed policies are like recipes from a professional chef - they're tested, they work, and they're maintained by AWS. Writing your own is like inventing a recipe - might work, might have mistakes, and YOU have to update it when things change. For common use cases, managed policies are safer and easier.
>
> **Evaluator Question:** *When SHOULD you write a custom policy instead of using managed policies?*
>
> **Model Answer:** Write custom policies when: (1) Managed policies are too broad (e.g., you need access to ONE secret, not all), (2) You need to combine permissions not in any managed policy, (3) You need resource-level restrictions (only this S3 bucket, only this DynamoDB table), (4) Compliance requires explicit policy documentation. Always prefer narrower custom policies over broad managed policies for production.

---

## Step 5.3: Verify Role Policies

### The Command

```bash
aws iam list-attached-role-policies --role-name lab-ec2-app-role
```

### Expected Output

```json
{
    "AttachedPolicies": [
        {
            "PolicyName": "SecretsManagerReadWrite (or your custom policy)",
            "PolicyArn": "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
        },
        {
            "PolicyName": "CloudWatchAgentServerPolicy",
            "PolicyArn": "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        },
        {
            "PolicyName": "AmazonSSMReadOnlyAccess",
            "PolicyArn": "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
        }
    ]
}
```


> ✅ **VERIFICATION CHECKLIST**
> 
> - [ ] `SecretsManagerReadWrite` (or custom policy from Lab 1a)
> - [ ] `CloudWatchAgentServerPolicy`
> - [ ] `AmazonSSMReadOnlyAccess`

---

# PART 6: Deploy Updated Application

---

## 🎯 The Big Picture: Why This Application Architecture?

> **SOCRATIC Q&A**
>
> ***Q:** Why does the application read from Parameter Store AND Secrets Manager? Couldn't we put everything in one place?*
>
> **A (Explain Like I'm 10):** Remember the treasure map and treasure chest? The application asks Parameter Store: "Where's the treasure?" (endpoint, port, database). Then it asks Secrets Manager: "What's the combination to the chest?" (username, password). Keeping them separate means you can change the location without changing the password, or rotate the password without changing the location.
>
> **Evaluator Question:** *How does this architecture support zero-downtime secret rotation?*
>
> **Model Answer:** When Secrets Manager rotates a password: (1) It creates a new password in RDS, (2) Updates the secret value, (3) Application reads new password on next connection. Because the application reads credentials dynamically (not hardcoded), it automatically uses the new password. No redeployment, no downtime.

---

## Step 6.1: SSH into EC2

```bash
ssh -i your-key.pem ec2-user@<EC2_PUBLIC_IP>
```

IMPORTANT: If you can't find your .pem file, an alternative is to connect directly through the AWS Console...
### Steps:

1. **Go to EC2 Console** → Instances → Select your `lab-ec2-app` instance
2. **Click "Connect"** button (top right)
3. **Choose "EC2 Instance Connect" tab**
4. **Leave username as `ec2-user`**
5. **Click "Connect"**

> **How to Find Your EC2 Public IP**
> 
> ```bash
> aws ec2 describe-instances \
>   --filters "Name=tag:Name,Values=lab-ec2-app" \
>   --query "Reservations[].Instances[].PublicIpAddress" \
>   --output text
> ```

---

## Step 6.2: Install Dependencies

### The Commands

```bash
sudo dnf update -y
sudo dnf install -y python3-pip mariadb105
sudo pip3 install flask pymysql boto3 watchtower
```

### Why Each Package?

| Package | Purpose |
|---------|---------|
| `flask` | Web framework - handles HTTP requests |
| `pymysql` | MySQL database connector |
| `boto3` | AWS SDK - talks to Parameter Store, Secrets Manager, CloudWatch |
| `watchtower` | Sends Python logs to CloudWatch Logs |
| `mariadb105` | MySQL client tools (for manual testing) |

> **SOCRATIC Q&A**
>
> ***Q:** Why use `watchtower` instead of just writing logs to a file?*
>
> **A (Explain Like I'm 10):** Writing to a file is like keeping a diary under your mattress - only YOU can read it, and if your house burns down, the diary is gone. Watchtower sends your logs to CloudWatch, which is like backing up your diary to the cloud automatically. Even if the server dies, your logs survive!

---

## Step 6.3: Create Application Directory

```bash
sudo mkdir -p /opt/rdsapp
```

### Why `/opt`?

> `/opt` is the standard Linux directory for "optional" software - applications that aren't part of the operating system. It's a convention that keeps your code organized and separate from system files.

---

## Step 6.4: Create the Application

### Create the File

```bash
sudo nano /opt/rdsapp/app.py
```

### The Application Code

```python
import json
import os
import boto3
import pymysql
import logging
from flask import Flask, request
from watchtower import CloudWatchLogHandler

# ===== CONFIGURATION =====
# These match what we created earlier
REGION = os.environ.get("AWS_REGION", "us-west-2")  # Change to your region!
LOG_GROUP = "/aws/ec2/lab-rds-app"
METRIC_NAMESPACE = "Lab/RDSApp"
SECRET_ID = "lab/rds/mysql"  # Change if your secret has a different name!

# ===== AWS CLIENTS =====
ssm = boto3.client("ssm", region_name=REGION)
sm = boto3.client("secretsmanager", region_name=REGION)
cw = boto3.client("cloudwatch", region_name=REGION)

# ===== LOGGING SETUP =====
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
try:
    cw_handler = CloudWatchLogHandler(
        log_group=LOG_GROUP,
        stream_name="app-stream",
        boto3_client=boto3.client("logs", region_name=REGION)
    )
    logger.addHandler(cw_handler)
except Exception as e:
    print(f"CloudWatch Logs Setup Pending: {e}")

app = Flask(__name__)

# ===== HELPER FUNCTIONS =====

def record_failure(error_msg):
    """Log the failure AND push a metric to CloudWatch"""
    logger.error(f"DB_CONNECTION_FAILURE: {error_msg}")
    try:
        cw.put_metric_data(
            Namespace=METRIC_NAMESPACE,
            MetricData=[{
                'MetricName': 'DBConnectionErrors',
                'Value': 1.0,
                'Unit': 'Count'
            }]
        )
    except Exception as e:
        logger.warning(f"Failed to push metric: {e}")

def get_config():
    """Get configuration from Parameter Store + Secrets Manager"""
    try:
        # Get non-sensitive config from Parameter Store
        p_resp = ssm.get_parameters(
            Names=['/lab/db/endpoint', '/lab/db/port', '/lab/db/name'],
            WithDecryption=False
        )
        p_map = {p['Name']: p['Value'] for p in p_resp['Parameters']}
        
        # Get credentials from Secrets Manager
        s_resp = sm.get_secret_value(SecretId=SECRET_ID)
        secret = json.loads(s_resp['SecretString'])
        
        return {
            'host': p_map['/lab/db/endpoint'],
            'port': int(p_map['/lab/db/port']),
            'dbname': p_map['/lab/db/name'],
            'user': secret['username'],
            'password': secret['password']
        }
    except Exception as e:
        record_failure(f"Config retrieval failed: {e}")
        raise

def get_conn():
    """Get a database connection using dynamic configuration"""
    c = get_config()
    return pymysql.connect(
        host=c['host'],
        user=c['user'],
        password=c['password'],
        port=c['port'],
        database=c['dbname'],
        autocommit=True
    )

# ===== ROUTES =====

@app.route("/")
def home():
    return """
    <h2>Lab 1B - RDS App with Observability</h2>
    <ul>
        <li><a href='/init'>Initialize Database</a></li>
        <li><a href='/add?text=TestNote'>Add a Note</a></li>
        <li><a href='/list'>List Notes</a></li>
        <li><a href='/health'>Health Check</a></li>
    </ul>
    """

@app.route("/init")
def init_db():
    """Initialize the database and table"""
    try:
        c = get_config()
        conn = pymysql.connect(
            host=c['host'],
            user=c['user'],
            password=c['password'],
            port=c['port']
        )
        cur = conn.cursor()
        cur.execute(f"CREATE DATABASE IF NOT EXISTS {c['dbname']};")
        cur.execute(f"USE {c['dbname']};")
        cur.execute("""
            CREATE TABLE IF NOT EXISTS notes (
                id INT AUTO_INCREMENT PRIMARY KEY,
                note VARCHAR(255),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        cur.close()
        conn.close()
        logger.info("Database initialized successfully")
        return "✅ Init Success! <a href='/'>Back</a>"
    except Exception as e:
        record_failure(str(e))
        return f"❌ Init Failed: {e}", 500

@app.route("/add")
def add_note():
    """Add a note to the database"""
    note_text = request.args.get('text', 'empty note')
    try:
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("INSERT INTO notes (note) VALUES (%s)", (note_text,))
        cur.close()
        conn.close()
        logger.info(f"Note added: {note_text}")
        return f"✅ Added: {note_text} | <a href='/list'>View List</a>"
    except Exception as e:
        record_failure(str(e))
        return f"❌ Add Failed: {e}", 500

@app.route("/list")
def list_notes():
    """List all notes from the database"""
    try:
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("SELECT id, note, created_at FROM notes ORDER BY id DESC;")
        rows = cur.fetchall()
        cur.close()
        conn.close()
        
        html = "<h3>📝 Notes:</h3><ul>"
        for r in rows:
            html += f"<li>[{r[0]}] {r[1]} <small>({r[2]})</small></li>"
        html += "</ul><br><a href='/'>Back</a>"
        return html
    except Exception as e:
        record_failure(str(e))
        return f"❌ List Failed: {e}", 500

@app.route("/health")
def health():
    """Health check endpoint"""
    try:
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        return "✅ Healthy"
    except Exception as e:
        record_failure(str(e))
        return f"❌ Unhealthy: {e}", 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
```

> ⚠️ **IMPORTANT: Update These Values**
> 
> - `REGION` - Change to your region (e.g., `us-west-2`)
> - `SECRET_ID` - Change to match your Secrets Manager secret name

### Save and Exit

- Press `Ctrl+O` to save
- Press `Enter` to confirm
- Press `Ctrl+X` to exit

---

## Step 6.5: Create systemd Service

### Why systemd?

> **SOCRATIC Q&A**
>
> ***Q:** Why create a systemd service instead of just running `python3 app.py`?*
>
> **A (Explain Like I'm 10):** Running `python3 app.py` is like holding a kite string - as soon as you let go (log out), the kite falls. systemd is like tying the string to a post - the kite keeps flying even when you walk away. Plus, if the wind knocks the kite down (app crashes), systemd picks it back up automatically!
>
> **Evaluator Question:** *What are the benefits of running applications as systemd services?*
>
> **Model Answer:** systemd provides: (1) Automatic start on boot, (2) Automatic restart on crash, (3) Logging integration with journald, (4) Resource management (memory limits, CPU priority), (5) Dependency ordering (wait for network before starting), (6) Status monitoring via `systemctl status`. It's the production standard for Linux services.

### Create the Service File

```bash
sudo nano /etc/systemd/system/rdsapp.service
```

### Service Configuration

```ini
[Unit]
Description=Lab 1b RDS App with Observability
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/opt/rdsapp
ExecStartPre=/usr/bin/sleep 10
ExecStart=/usr/bin/python3 /opt/rdsapp/app.py
Restart=always
RestartSec=10s
Environment=AWS_REGION=us-west-2

[Install]
WantedBy=multi-user.target
```

### What Each Section Means

| Section | Setting | Purpose |
|---------|---------|---------|
| `[Unit]` | `After=network-online.target` | Wait for network before starting |
| `[Service]` | `ExecStartPre=/usr/bin/sleep 10` | Wait 10 sec for IMDS to be ready |
| `[Service]` | `Restart=always` | Auto-restart if it crashes |
| `[Service]` | `RestartSec=10s` | Wait 10 sec before restart |
| `[Service]` | `Environment=AWS_REGION=...` | Set region for boto3 |
| `[Install]` | `WantedBy=multi-user.target` | Start on normal boot |

> ⚠️ **Update `AWS_REGION`** to match your region!

---

## Step 6.6: Start the Application

### The Commands

```bash
# Reload systemd to recognize the new service
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable rdsapp

# Start the service now
sudo systemctl start rdsapp

# Check the status
sudo systemctl status rdsapp
```

### Expected Status Output

```
● rdsapp.service - Lab 1b RDS App with Observability
     Loaded: loaded (/etc/systemd/system/rdsapp.service; enabled; preset: disabled)
     Active: active (running) since ...
```

### If Something Goes Wrong

```bash
# View detailed logs
sudo journalctl -u rdsapp -f

# Restart the service
sudo systemctl restart rdsapp
```

---

## Step 6.7: Test the Application

### From Your Local Machine

```bash
# Initialize the database
curl http://<EC2_PUBLIC_IP>/init

# Add a test note
curl "http://<EC2_PUBLIC_IP>/add?note=Lab1bTest"

## URL Encoding Required for Special Characters!
Spaces, apostrophes, and exclamation marks have special meanings in URLs and shells. If you want complete sentence, use:
curl -G "http://54.218.85.165/add" --data-urlencode "note=Let's go DAWGS!"

# List all notes
curl http://<EC2_PUBLIC_IP>/list

# Health check The `/` endpoint works as a health check
curl "http://<EC2_PUBLIC_IP>/"
```


At this point, everything should work!🔥 **EC2 → Parameter Store → Secrets Manager → RDS → Response** - the entire chain is working!

> ✅ **VERIFICATION CHECKLIST**
> 
> - [ ] `/init` returns `✅ Init Success!`
> - [ ] `/add` returns `✅ Added: Lab1bTest`
> - [ ] `/list` shows your notes
> - [ ] `/health` returns `✅ Healthy`

Note: if you didn't create a `/health` endpoint in the app so I couldn't run a health check. The `/` endpoint works as a health check in the interim. Add 4 lines to app.py to create the health check. Here are the steps:
Step 1: SSH into EC2 (or use Instance Connect)
Step 2: Edit the App - *sudo nano /opt/rdsapp/app.py*
Step 3: Add This Block After the `def home()` Function

Find this section:

python
```python
@app.route('/')
def home():
    return "Lab 1B App Running! Try /init, /add?note=hello, or /list"
```

Add **right below it**:

python
```python
@app.route('/health')
def health():
    return {"status": "healthy", "app": "lab1b-rdsapp"}
```

### Step 4: Save and Exit

- Press `Ctrl + O` → Enter (save)
- Press `Ctrl + X` (exit)

### Step 5: Restart the App

```bash
sudo systemctl restart rdsapp
```
### Step 6: Test It

bash

```bash
curl http://54.218.85.165/health
```

Expected output:

json
```json
{"status": "healthy", "app": "lab1b-rdsapp"}
```

| Signal                                                      | Meaning              |
| ----------------------------------------------------------- | -------------------- |
| **`active (running)`**                                      | App is alive!        |
| **`Found credentials from IAM Role: alex_armageddon_role`** | IAM role working     |
| **`Serving Flask app 'app'`**                               | Flask is ready       |
| **`Running on http://127.0.0.1:80`**                        | Listening on port 80 |
### Test of the Health Endpoint

```bash
curl http://localhost/health
```

Expected output:

json
```json
{"app":"lab1b-rdsapp","status":"healthy"}
```

**Part 6 Complete!**

| Layer              | Status                |
| ------------------ | --------------------- |
| Flask App          | ✅ Running             |
| Parameter Store    | ✅ Reading config      |
| Secrets Manager    | ✅ Reading credentials |
| RDS MySQL          | ✅ Connected           |
| CloudWatch Logs    | ✅ Shipping logs       |
| `/health` endpoint | ✅ Working             |
# PART 7: Incident Response Simulation

---

## 🎯 The Big Picture: Why Simulate Incidents?

> **SOCRATIC Q&A**
>
> ***Q:** Why would we intentionally BREAK something we just built?*
>
> **A (Explain Like I'm 10):** Fire drills! Schools don't wait for real fires to practice evacuating - they do drills so everyone knows what to do. We're doing an "incident drill" so you know how to respond when REAL problems happen. The first time you face a production incident shouldn't be at 3 AM with angry customers.
>
> **Evaluator Question:** *Why is incident simulation important for teams?*
>
> **Model Answer:** Incident simulation: (1) Validates that alerting actually works (many teams discover their alerts are broken during real incidents), (2) Builds muscle memory for runbook execution, (3) Identifies gaps in documentation, (4) Reduces MTTR through practice, (5) Builds confidence - when real incidents happen, you've done this before. Netflix's Chaos Monkey popularized this as "chaos engineering."

---

## Step 7.1: Inject the Failure

> ⚠️ **SCENARIO: You Are Now On-Call**
> 
> The system was working. No infrastructure changes were announced.
> Users are reporting failures. Your job is to:
> - **OBSERVE** using logs and metrics
> - **DIAGNOSE** the root cause
> - **RECOVER** without redeploying infrastructure

### Why Can't You Just Redeploy?

> **SOCRATIC Q&A**
>
> ***Q:** Why can't I just terminate and recreate EC2 to fix the problem?*
>
> **A (Explain Like I'm 10):** Imagine your car won't start. You COULD buy a new car every time... but that's expensive, slow, and you never learn what actually broke! Maybe it was just out of gas. Professional mechanics diagnose FIRST, then fix the specific problem. Redeploying is the 'buy a new car' approach - it might work, but you learned nothing, and the same problem will happen again.
>
> **Evaluator Question:** *What's wrong with 'just redeploying' as an incident response strategy?*
>
> **Model Answer:** Redeployment destroys forensic evidence needed for root cause analysis. It doesn't fix the underlying issue (which will recur). It takes longer than targeted fixes. It signals to employers that you don't understand operational discipline. Professional response: preserve state, diagnose with logs/metrics, apply minimal targeted fix, verify recovery, then document for prevention.

Now the fun part - **we break the database and watch your alarm fire!**
Check Current Alarm State first: 

*aws cloudwatch describe-alarms --alarm-names lab-db-connection-failure --query "MetricAlarms[].StateValue" --output text --region us-west-2

Should return: `OK`
### Stop the RDS Instance

```bash
aws rds stop-db-instance --db-instance-identifier lab-mysql
```

At this point, you can verify RDS is stopping, if you want:
*aws rds describe-db-instances --db-instance-identifier lab-mysql --query "DBInstances[].DBInstanceStatus" --output text --region us-west-2

Should return: `stopping` or `stopped`

### Generate Errors

Hit the application several times to generate connection failures:

```bash
curl http://<EC2_PUBLIC_IP>/list
curl http://<EC2_PUBLIC_IP>/list
curl http://<EC2_PUBLIC_IP>/list
curl http://<EC2_PUBLIC_IP>/list
```

### Wait for Alert

**Wait 5-10 minutes** for:
1. CloudWatch to collect the metrics
2. Alarm to breach threshold
3. SNS to send email

After the curl failures, check alarm state:
*aws cloudwatch describe-alarms --alarm-names lab-db-connection-failure --query "MetricAlarms[].StateValue" --output text --region us-west-2

It should change from `OK` → `ALARM`

## 🎉 INCIDENT SIMULATION SUCCESS!

You just experienced a **real-world incident response scenario**:

|Event|Status|
|---|---|
|Database outage|✅ Simulated (RDS stopped)|
|Connection failures|✅ App couldn't connect|
|Metrics published|✅ DBConnectionErrors fired|
|Alarm triggered|✅ State → ALARM|
|Notification sent|✅ Email received|

# INCIDENT RUNBOOK

---

## SECTION 1: Acknowledge

### Why Acknowledge?

In real incident management (PagerDuty, OpsGenie), "acknowledging" tells the team: "I see this, I'm working on it." It prevents duplicate work.

### 1.1 Confirm the Alert State

```bash
aws cloudwatch describe-alarms --alarm-names lab-db-connection-failure --query "MetricAlarms[].StateValue"
```

**Expected:** `["ALARM"]`

---

## SECTION 2: Observe

### Why Observe Before Acting?

> **SOCRATIC Q&A**
>
> ***Q:** I know the DB is down - why waste time looking at logs?*
>
> **A (Explain Like I'm 10):** A doctor doesn't just give you medicine because you "feel bad" - they check your symptoms first! Logs tell you EXACTLY what's failing. Is it credentials? Network? The database itself? Each problem has a different fix. Looking at logs is like reading the error message before calling tech support.

### 2.1 Check Application Logs

```bash
aws logs filter-log-events --log-group-name /aws/ec2/lab-rds-app --filter-pattern "DB_CONNECTION_FAILURE"
```


### 2.2 Classify the Failure Type

| Log Signature | Failure Type | Likely Cause |
|---------------|--------------|--------------|
| `Access denied (1045)` | Credential failure | Password mismatch |
| `Connection refused (2003)` | Network failure | Security group or routing |
| `Can't connect / timed out` | Database unavailable | RDS stopped or endpoint changed |

---

## SECTION 3: Validate Configuration

### Why Validate Before Fixing?

Ensure the problem isn't a configuration drift - someone might have changed a parameter or secret without telling you.

### 3.1 Check Parameter Store Values

```bash
aws ssm get-parameters --names /lab/db/endpoint /lab/db/port /lab/db/name --with-decryption
```

**Verify:** Values match your RDS instance.
### 3.2 Check Secrets Manager

```bash
aws secretsmanager get-secret-value --secret-id lab/rds/mysql
```

**Verify:** Credentials are present and correct.


> ✅ **This rules out credential drift as the cause.**

---

## SECTION 4: Containment

### Why Containment?

Prevent the problem from getting worse while you diagnose.

### Do NOT:
- ❌ Restart EC2 blindly
- ❌ Rotate secrets without diagnosis
- ❌ Redeploy infrastructure

### Do:
- ✅ Preserve system state for forensics
- ✅ Document current time and observations
- ✅ State explicitly: *"System state preserved for recovery."*

---

## SECTION 5: Recovery

### 5.1 Check RDS Status

```bash
aws rds describe-db-instances --db-instance-identifier lab-mysql --query "DBInstances[0].DBInstanceStatus"
```

**Expected (for our simulation):** `"stopped"`

### 5.2 Start the RDS Instance

```bash
aws rds start-db-instance --db-instance-identifier lab-mysql
```

### 5.3 Wait for Recovery

RDS takes 5-10 minutes to become available. Poll the status:

```bash
# Run this periodically until you see "available"
aws rds describe-db-instances --db-instance-identifier lab-mysql --query "DBInstances[].DBInstanceStatus" --output text --region us-west-2
```

**Status progression:** `stopped` → `starting` → `available`

---

## SECTION 6: Post-Incident Validation

### 6.1 Verify Application Recovery

```bash
curl http://<EC2_PUBLIC_IP>/health
curl http://<EC2_PUBLIC_IP>/list
```

**Expected:** Application returns data successfully.
### 6.2 Verify Alarm Clears

```bash
aws cloudwatch describe-alarms --alarm-names lab-db-connection-failure --query "MetricAlarms[].StateValue"
```

**Expected:** `["OK"]`


> ✅ **INCIDENT RESOLVED**

---

# DELIVERABLES

---

## Checklist

| Item                           | Evidence Required                   | Points  |
| ------------------------------ | ----------------------------------- | ------- |
| Parameter Store entries        | CLI output showing all 3 parameters | 10      |
| CloudWatch Log Group           | CLI output showing log group exists | 10      |
| SNS Topic + Subscription       | CLI output + email confirmation     | 10      |
| CloudWatch Alarm               | CLI output showing alarm config     | 15      |
| Application working            | Screenshot of /list returning data  | 15      |
| Alarm triggered (ALARM state)  | CLI output or email screenshot      | 10      |
| Correct failure classification | Written explanation                 | 10      |
| Recovery without redeploy      | Documentation of steps taken        | 10      |
| Alarm cleared (OK state)       | CLI output after recovery           | 10      |
| **TOTAL**                      |                                     | **100** |

---
# VERIFICATION BONUS: Gate Scripts

---

## 🎯 What Are Gate Scripts?

Gate scripts are **automated verification tools** that check whether your infrastructure is correctly configured. Think of them as a "pre-flight checklist" for your cloud infrastructure.

> **SOCRATIC Q&A**
> 
> _**Q:** Why use scripts instead of just running individual CLI commands?_
> 
> **A (Explain Like I'm 10):** Imagine you're a pilot. Before every flight, you check: fuel? ✓ wings? ✓ engines? ✓ That's a checklist. Now imagine having to REMEMBER every check every time - you'd eventually forget something! A script is like a printed checklist that checks everything automatically and tells you PASS or FAIL. Pilots don't skip checklists, and neither should cloud engineers.
> 
> **Evaluator Question:** _How do gate scripts fit into CI/CD pipelines?_
> 
> **Model Answer:** Gate scripts return exit codes: 0 = PASS, non-zero = FAIL. CI/CD tools (Jenkins, GitHub Actions, GitLab CI) use exit codes to decide whether to proceed. A gate script that returns FAIL stops the pipeline - preventing broken infrastructure from reaching production. This is "shift left" security - catching problems early.

---

## 📁 Available Gate Scripts

|Script|What It Validates|
|---|---|
|`gate_secrets_and_role.sh`|Secrets Manager + IAM role configuration|
|`gate_network_db.sh`|EC2 ↔ RDS network connectivity|
|`run_all_gates.sh`|Runs both scripts, produces combined result|

---

## Prerequisites

### 1. Download the Scripts

If the scripts aren't already in your working directory, download them from the course repository:

```bash
# Create a directory for the scripts
mkdir -p ~/lab-gates
cd ~/lab-gates

# Download the scripts (adjust URL to your repo)
# Or copy them from the course materials
```

### 2. Make Scripts Executable

```bash
chmod +x gate_secrets_and_role.sh gate_network_db.sh run_all_gates.sh
```

### 3. Get Your Resource IDs

```bash
# Get your EC2 Instance ID
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=lab-ec2-app" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text

# Get your RDS Instance ID (should be "lab-mysql")
aws rds describe-db-instances \
  --query "DBInstances[].DBInstanceIdentifier" \
  --output text
```

---

## Gate 1: Secrets and Role Verification

### What It Checks

|Check|Pass Criteria|
|---|---|
|AWS credentials valid|`sts get-caller-identity` succeeds|
|Secret exists|Secret is describable|
|EC2 has instance profile|IAM role attached to EC2|
|Profile resolves to role|Can determine role name|
|Caller is expected role|(If run on EC2) Running as the role|
|Role can read secret|(If run on EC2) Secret access works|

### Run the Script

```bash
REGION=us-west-2 \
INSTANCE_ID=<YOUR_EC2_INSTANCE_ID> \
SECRET_ID=lab/rds/mysql \
./gate_secrets_and_role.sh
```

### Expected Output (PASS)

```
=== SEIR Gate: Secrets + EC2 Role Verification ===
Timestamp (UTC): 2026-02-01T20:30:00Z
Region:          us-west-2
Instance ID:     i-0abc123def456789
Secret ID:       lab/rds/mysql
Resolved Role:   lab-ec2-app-role
-----------------------------------------------
PASS: aws sts get-caller-identity succeeded (credentials OK).
PASS: secret exists and is describable (lab/rds/mysql).
PASS: instance has IAM instance profile attached (i-0abc123def456789).
PASS: resolved instance profile -> role (lab-ec2-app-role).

RESULT: PASS
===============================================

Wrote: gate_secrets_and_role.json
```

### Common Failures and Fixes

|Failure|Cause|Fix|
|---|---|---|
|`cannot describe secret`|Secret doesn't exist or wrong name|Verify secret name in Secrets Manager console|
|`instance has NO IAM instance profile`|Role not attached to EC2|Attach `lab-ec2-app-role` to EC2 instance|
|`could not resolve role name`|Instance profile misconfigured|Check IAM console for instance profile|

---

## Gate 2: Network and Database Verification

### What It Checks

|Check|Pass Criteria|
|---|---|
|RDS instance exists|Can describe the DB instance|
|RDS is NOT public|`PubliclyAccessible = false`|
|DB port discovered|Can determine port (3306 for MySQL)|
|EC2 security groups resolved|Can identify EC2's security groups|
|RDS security groups resolved|Can identify RDS's security groups|
|SG-to-SG ingress rule|RDS SG allows traffic from EC2 SG on DB port|
|No world-open DB port|DB port not open to 0.0.0.0/0|

### Run the Script

```bash
REGION=us-west-2 \
INSTANCE_ID=<YOUR_EC2_INSTANCE_ID> \
DB_ID=lab-mysql \
./gate_network_db.sh
```

### Expected Output (PASS)

```
=== SEIR Gate: Network + RDS Verification ===
Timestamp (UTC): 2026-02-01T20:31:00Z
Region:          us-west-2
EC2 Instance:    i-0abc123def456789
RDS Instance:    lab-mysql
Engine:          mysql
DB Port:         3306
-------------------------------------------
PASS: aws sts get-caller-identity succeeded (credentials OK).
PASS: RDS instance exists (lab-mysql).
PASS: RDS is not publicly accessible (PubliclyAccessible=False).
PASS: discovered DB port = 3306 (engine=mysql).
PASS: EC2 security groups resolved (i-0abc123def456789): sg-0abc123
PASS: RDS security groups resolved (lab-mysql): sg-0def456
PASS: RDS SG allows DB port 3306 from EC2 SG (SG-to-SG ingress present).

RESULT: PASS
===========================================

Wrote: gate_network_db.json
```

### Common Failures and Fixes

|Failure|Cause|Fix|
|---|---|---|
|`RDS is publicly accessible`|Security misconfiguration|Modify RDS to disable public access|
|`no SG-to-SG ingress rule`|Security group misconfigured|Add inbound rule: MySQL (3306) from EC2 SG|
|`allows DB port from the world`|0.0.0.0/0 rule exists|Remove the 0.0.0.0/0 rule, use SG reference|

> **SOCRATIC Q&A**
> 
> _**Q:** Why is "DB port open to 0.0.0.0/0" a failure even if RDS is in a private subnet?_
> 
> **A (Explain Like I'm 10):** Defense in depth! Imagine your bedroom is inside your house (private subnet), but you left the bedroom door wide open (0.0.0.0/0 rule). If someone breaks into your house, they walk right into your room. Multiple locks are better - private subnet AND restricted security group. If one fails, the other still protects you.
> 
> **Evaluator Question:** _What's the difference between network isolation (private subnet) and access control (security groups)?_
> 
> **Model Answer:** Network isolation controls WHERE traffic can physically reach - private subnets have no internet gateway route. Access control (security groups) controls WHAT traffic is allowed - even within a network. Both are needed: isolation prevents external access; security groups prevent unauthorized internal access. A compromised EC2 in the same VPC could still reach an overly-permissive RDS if only relying on subnet isolation.

---

## Combined Gate: Run All Checks

### Run the Script

```bash
REGION=us-west-2 \
INSTANCE_ID=<YOUR_EC2_INSTANCE_ID> \
SECRET_ID=lab/rds/mysql \
DB_ID=lab-mysql \
./run_all_gates.sh
```

### Expected Output

```
=== Running Gate 1/2: secrets_and_role ===
[... gate 1 output ...]

=== Running Gate 2/2: network_db ===
[... gate 2 output ...]

===== SEIR Combined Gate Summary =====
Gate 1 (secrets_and_role) exit: 0  -> gate_secrets_and_role.json
Gate 2 (network_db)       exit: 0  -> gate_network_db.json
--------------------------------------
BADGE:  GREEN
RESULT: PASS
Wrote:  gate_result.json
======================================
```

### Badge Meanings

|Badge|Meaning|Action|
|---|---|---|
|🟢 **GREEN**|All checks passed|You're good!|
|🟡 **YELLOW**|Passed with warnings|Review warnings, usually OK|
|🔴 **RED**|One or more failures|Fix the failures before proceeding|

---

## Understanding the JSON Output

Each gate script produces a JSON file with detailed results:

### `gate_secrets_and_role.json`

```json
{
  "gate": "secrets_and_role",
  "timestamp_utc": "2026-02-01T20:30:00Z",
  "region": "us-west-2",
  "instance_id": "i-0abc123def456789",
  "secret_id": "lab/rds/mysql",
  "resolved_role_name": "lab-ec2-app-role",
  "status": "PASS",
  "exit_code": 0,
  "details": [...],
  "warnings": [],
  "failures": []
}
```

### `gate_network_db.json`

```json
{
  "gate": "network_db",
  "timestamp_utc": "2026-02-01T20:31:00Z",
  "region": "us-west-2",
  "instance_id": "i-0abc123def456789",
  "db_id": "lab-mysql",
  "engine": "mysql",
  "db_port": "3306",
  "publicly_accessible": "False",
  "status": "PASS",
  "exit_code": 0,
  "details": [...],
  "warnings": [],
  "failures": []
}
```

> **Why JSON Output?**
> 
> JSON is machine-readable. These files can be:
> 
> - Stored as evidence for audits
> - Parsed by CI/CD pipelines
> - Aggregated into dashboards
> - Compared over time to detect drift

---

## Quick Reference: One-Liner Validation

After completing Lab 1B, run this to validate everything:

```bash
# Set your variables
export REGION=us-west-2
export INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=lab-ec2-app" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)
export SECRET_ID=lab/rds/mysql
export DB_ID=lab-mysql

# Run combined gates
./run_all_gates.sh
```

**If you see GREEN, your Lab 1B infrastructure is production-ready!** 🎉

---

## Reflection Questions

**1. Why do gate scripts output both human-readable text AND JSON?**

> Humans read the text for quick understanding. Machines (CI/CD, dashboards, audit tools) parse the JSON for automation. Both audiences matter.

**2. What's the difference between a "warning" and a "failure" in gate scripts?**

> Failures block progress - something is definitely wrong. Warnings are "you should know about this" - might be fine, might need attention. Example: "running off-instance" is a warning (you might be testing from your laptop), but "secret doesn't exist" is a failure.

**3. How would you integrate these gates into a CI/CD pipeline?**

> Add a pipeline stage that runs `./run_all_gates.sh`. If exit code is non-zero (FAIL), the pipeline stops. This prevents deploying broken infrastructure. Store the JSON artifacts for audit trails.

---

## What This Proves About You

_If you can run these gate scripts and achieve GREEN:_

**"I can validate infrastructure configuration using automated verification scripts - a core DevOps/SRE skill."**

_Scripts don't lie. GREEN means your infrastructure matches the design._
## Incident Report Template

```
INCIDENT TITLE: Production Database Connectivity Failure

INCIDENT SUMMARY:
- What failed: _______________
- How detected: _______________
- Root cause: _______________
- Time to detection: _______________
- Time to recovery: _______________

PREVENTIVE ACTIONS:
- One improvement to reduce MTTR: _______________
- One improvement to prevent recurrence: _______________
```

---

## Final Verification Script

```bash
echo "=== Parameter Store ==="
aws ssm get-parameters --names /lab/db/endpoint /lab/db/port /lab/db/name --query "Parameters[*].[Name,Value]" --output table

echo "=== Log Group ==="
aws logs describe-log-groups --log-group-name-prefix /aws/ec2/lab-rds-app --query "logGroups[*].[logGroupName,retentionInDays]" --output table

echo "=== SNS Topic ==="
aws sns list-topics --query "Topics[?contains(TopicArn, 'lab-db-incidents')]" --output table

echo "=== CloudWatch Alarm ==="
aws cloudwatch describe-alarms --alarm-names lab-db-connection-failure --query "MetricAlarms[*].[AlarmName,StateValue]" --output table

echo "=== Application Health ==="
curl http://<EC2_PUBLIC_IP>/health
```

---

# REFLECTION QUESTIONS

---

## For Your Own Understanding

**1. Why is 'defense in depth' important?**

> Even if one layer fails, other layers still protect you. In this lab: if Secrets Manager is misconfigured, we'd still see it in logs. If logs fail, alarms still fire. Multiple layers = multiple chances to catch problems.

**2. What's the principle of least privilege?**

> Give only the minimum permissions needed. Our EC2 can read Parameter Store and Secrets Manager for THIS app, write to THIS log group, push metrics to THIS namespace - nothing more.

**3. How do you verify 'as built' vs 'as designed'?**

> Use CLI commands to check actual state. Don't trust the console, don't trust memory - run the verification commands and prove it exists as expected.

**4. How does this lab reduce Mean Time To Recovery (MTTR)?**

> Stored config values enable recovery without redeployment. Logs enable fast diagnosis. Alarms enable early detection. Runbook provides step-by-step recovery.

---

# WHAT THIS LAB PROVES ABOUT YOU

---

*If you complete this lab correctly, you can say:*

**"I can operate, monitor, and recover AWS workloads using proper secret management and observability."**

*That is mid-level engineer capability, not entry-level.*

---

## What's Next: Lab 1C

**Lab 1C: Terraform Infrastructure as Code**

- Recreate entire infrastructure with Terraform
- Bonus: ALB, TLS with ACM, WAF, CloudWatch Dashboard
- Enterprise-grade deployment pattern

*If you can Terraform this, you're no longer 'a student who clicked around' — you're a junior cloud engineer.*
