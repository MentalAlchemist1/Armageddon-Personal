# SEIR FOUNDATIONS
# LAB 1B: Operations, Secrets & Incident Response
*Step-by-Step Implementation Guide*

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

### What You'll Build

1. Store DB configuration values in Parameter Store
2. Store DB credentials in Secrets Manager (if not done in 1a)
3. Create CloudWatch Log Group for application logs
4. Create SNS Topic for incident alerts
5. Create CloudWatch Alarm that triggers on DB connection failures
6. Deploy updated application with observability features
7. Simulate and recover from a database outage

---

## PART 1: Create Parameter Store Entries

Parameter Store holds non-sensitive configuration values. These are the "where to connect" values, not the "how to authenticate" values.

### Parameters to Create

| Parameter Name | Type | Value |
|----------------|------|-------|
| `/lab/db/endpoint` | String | Your RDS endpoint (e.g., lab-mysql.xxx.us-east-1.rds.amazonaws.com) |
| `/lab/db/port` | String | 3306 |
| `/lab/db/name` | String | labdb |

### Step 1.1: Get Your RDS Endpoint

```bash
# Get your RDS endpoint
aws rds describe-db-instances \
  --db-instance-identifier lab-mysql \
  --query "DBInstances[0].Endpoint.Address" \
  --output text
```

### Step 1.2: Create the Parameters

```bash
# Create endpoint parameter (replace <RDS_ENDPOINT> with your actual endpoint)
aws ssm put-parameter \
  --name "/lab/db/endpoint" \
  --value "<RDS_ENDPOINT>" \
  --type String

# Create port parameter
aws ssm put-parameter \
  --name "/lab/db/port" \
  --value "3306" \
  --type String

# Create database name parameter
aws ssm put-parameter \
  --name "/lab/db/name" \
  --value "labdb" \
  --type String
```

### Step 1.3: Verify Parameters

```bash
aws ssm get-parameters \
  --names /lab/db/endpoint /lab/db/port /lab/db/name \
  --with-decryption
```

> ✅ **VERIFICATION**
> 
> Expected output: All three parameters returned with correct values.
> The `InvalidParameters` array should be empty.

---

## PART 2: Create CloudWatch Log Group

The application will send DB connection failure logs to CloudWatch. This allows you to investigate incidents without SSH access to the server.

### Step 2.1: Create the Log Group

```bash
aws logs create-log-group \
  --log-group-name /aws/ec2/lab-rds-app
```

### Step 2.2: Set Retention Policy

```bash
# Set 7-day retention (sufficient for lab purposes)
aws logs put-retention-policy \
  --log-group-name /aws/ec2/lab-rds-app \
  --retention-in-days 7
```

### Step 2.3: Verify Log Group

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /aws/ec2/lab-rds-app
```

> ✅ **VERIFICATION**
> 
> Expected: Log group `/aws/ec2/lab-rds-app` exists with 7-day retention.

---

## PART 3: Create SNS Topic for Alerts

SNS (Simple Notification Service) will send you email alerts when the CloudWatch alarm triggers. This simulates PagerDuty or other alerting systems.

### Step 3.1: Create the SNS Topic

```bash
aws sns create-topic --name lab-db-incidents
```

**Save the TopicArn from the output.** You'll need it for the alarm and subscription.

### Step 3.2: Subscribe Your Email

```bash
# Replace <ACCOUNT_ID> with your AWS account ID
# Replace <YOUR_EMAIL> with your actual email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:<ACCOUNT_ID>:lab-db-incidents \
  --protocol email \
  --notification-endpoint <YOUR_EMAIL>
```

> ⚠️ **IMPORTANT**
> 
> Check your email inbox and **CONFIRM the subscription!**
> You will not receive alerts until you click the confirmation link.

### Step 3.3: Verify Subscription

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:us-east-1:<ACCOUNT_ID>:lab-db-incidents
```

> ✅ **VERIFICATION**
> 
> Expected: `SubscriptionArn` shows your email (not `PendingConfirmation`).

---

## PART 4: Create CloudWatch Alarm

The alarm monitors the `DBConnectionErrors` metric. When errors exceed the threshold, it triggers SNS notification.

### Alarm Configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| Metric | DBConnectionErrors | Custom metric pushed by app |
| Namespace | Lab/RDSApp | Custom namespace for our app |
| Threshold | ≥ 3 errors | Triggers after 3 failures |
| Period | 300 seconds (5 min) | Evaluation window |
| Evaluation Periods | 1 | Triggers after first breach |

### Step 4.1: Create the Alarm

```bash
# Replace <ACCOUNT_ID> with your AWS account ID
aws cloudwatch put-metric-alarm \
  --alarm-name lab-db-connection-failure \
  --alarm-description "Alarm when the app fails to connect to RDS" \
  --metric-name DBConnectionErrors \
  --namespace Lab/RDSApp \
  --statistic Sum \
  --period 300 \
  --threshold 3 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 1 \
  --treat-missing-data notBreaching \
  --alarm-actions arn:aws:sns:us-east-1:<ACCOUNT_ID>:lab-db-incidents
```

### Step 4.2: Verify the Alarm

```bash
aws cloudwatch describe-alarms \
  --alarm-names lab-db-connection-failure
```

> ✅ **VERIFICATION**
> 
> Expected: Alarm exists with `StateValue` of `OK` or `INSUFFICIENT_DATA`.
> The `AlarmActions` should contain your SNS topic ARN.

---

## PART 5: Update IAM Role Permissions

The EC2 instance role needs additional permissions to write logs to CloudWatch and push metrics.

### Step 5.1: Add CloudWatch Permissions

Navigate to: **IAM → Roles → lab-ec2-app-role → Add permissions → Attach policies**

Add these managed policies:
- `CloudWatchAgentServerPolicy`
- `AmazonSSMReadOnlyAccess` (for Parameter Store)

### Step 5.2: Verify Role Policies

```bash
aws iam list-attached-role-policies \
  --role-name lab-ec2-app-role
```

> ✅ **VERIFICATION**
> 
> Expected: Role has `SecretsManagerReadWrite` (or custom policy), `CloudWatchAgentServerPolicy`, and `AmazonSSMReadOnlyAccess` attached.

---

## PART 6: Deploy Updated Application

Deploy the Flask application that integrates with Parameter Store, Secrets Manager, and CloudWatch.

### Step 6.1: SSH into EC2

```bash
ssh -i your-key.pem ec2-user@<EC2_PUBLIC_IP>
```

### Step 6.2: Install Dependencies

```bash
sudo dnf update -y
sudo dnf install -y python3-pip mariadb105
sudo pip3 install flask pymysql boto3 watchtower
```

### Step 6.3: Create Application Directory

```bash
sudo mkdir -p /opt/rdsapp
```

### Step 6.4: Create the Application

Create the file `/opt/rdsapp/app.py`:

```bash
sudo nano /opt/rdsapp/app.py
```

Paste the following code:

```python
import json
import os
import boto3
import pymysql
import logging
from flask import Flask, request
from watchtower import CloudWatchLogHandler

REGION = os.environ.get("AWS_REGION", "us-east-1")
LOG_GROUP = "/aws/ec2/lab-rds-app"
METRIC_NAMESPACE = "Lab/RDSApp"

ssm = boto3.client("ssm", region_name=REGION)
sm = boto3.client("secretsmanager", region_name=REGION)
cw = boto3.client("cloudwatch", region_name=REGION)

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

def record_failure(error_msg):
    logger.error(f"DB_CONNECTION_FAILURE: {error_msg}")
    try:
        cw.put_metric_data(
            Namespace=METRIC_NAMESPACE,
            MetricData=[{'MetricName': 'DBConnectionErrors', 'Value': 1.0, 'Unit': 'Count'}]
        )
    except Exception as e:
        logger.warning(f"Failed to push metric: {e}")

def get_config():
    try:
        p_resp = ssm.get_parameters(
            Names=['/lab/db/endpoint', '/lab/db/port', '/lab/db/name'],
            WithDecryption=False
        )
        p_map = {p['Name']: p['Value'] for p in p_resp['Parameters']}
        s_resp = sm.get_secret_value(SecretId='lab/rds/mysql2')
        secret = json.loads(s_resp['SecretString'])
        return {
            'host': p_map.get('/lab/db/endpoint'),
            'port': int(p_map.get('/lab/db/port', 3306)),
            'dbname': p_map.get('/lab/db/name', 'labdb'),
            'user': secret.get('username'),
            'password': secret.get('password')
        }
    except Exception as e:
        record_failure(str(e))
        raise e

def get_conn():
    c = get_config()
    return pymysql.connect(
        host=c['host'], user=c['user'], password=c['password'], 
        port=c['port'], database=c['dbname'], autocommit=True
    )

@app.route("/")
def home():
    return """
    <h1>Lab 1b: Simple RDS App</h1>
    <ul>
        <li><a href='/init'>1. Init DB</a></li>
        <li><a href='/add?text=LabEntry'>2. Add Note (?text=...)</a></li>
        <li><a href='/list'>3. List Notes</a></li>
    </ul>
    """

@app.route("/add")
def add_note():
    note_text = request.args.get('text', 'Manual Entry')
    try:
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("INSERT INTO notes (note) VALUES (%s)", (note_text,))
        cur.close()
        conn.close()
        return f"Added: {note_text} | <a href='/list'>View List</a>"
    except Exception as e:
        record_failure(str(e))
        return f"Add Failed: {e}", 500

@app.route("/list")
def list_notes():
    try:
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("SELECT id, note FROM notes ORDER BY id DESC;")
        rows = cur.fetchall()
        cur.close()
        conn.close()
        return "<h3>Notes:</h3>" + "".join([f"<li>{r[1]}</li>" for r in rows]) + "<br><a href='/'>Back</a>"
    except Exception as e:
        record_failure(str(e))
        return f"List Failed: {e}", 500

@app.route("/init")
def init_db():
    try:
        c = get_config()
        conn = pymysql.connect(host=c['host'], user=c['user'], password=c['password'], port=c['port'])
        cur = conn.cursor()
        cur.execute(f"CREATE DATABASE IF NOT EXISTS {c['dbname']};")
        cur.execute(f"USE {c['dbname']};")
        cur.execute("CREATE TABLE IF NOT EXISTS notes (id INT AUTO_INCREMENT PRIMARY KEY, note VARCHAR(255));")
        cur.close()
        conn.close()
        return "Init Success! <a href='/'>Back</a>"
    except Exception as e:
        record_failure(str(e))
        return f"Init Failed: {e}", 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
```

> 💡 **NOTE**
> 
> The secret ID used is `lab/rds/mysql2` - ensure your Secrets Manager secret matches this name, or update the code to match your secret name.

### Step 6.5: Create systemd Service

```bash
sudo nano /etc/systemd/system/rdsapp.service
```

Add the following content:

```ini
[Unit]
Description=Lab 1b RDS App
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/opt/rdsapp
ExecStartPre=/usr/bin/sleep 20
ExecStart=/usr/bin/python3 /opt/rdsapp/app.py
Restart=always
RestartSec=10s
Environment=AWS_REGION=us-east-1

[Install]
WantedBy=multi-user.target
```

### Step 6.6: Start the Application

```bash
sudo systemctl daemon-reload
sudo systemctl enable rdsapp
sudo systemctl start rdsapp

# Check status
sudo systemctl status rdsapp
```

### Step 6.7: Test the Application

From your local machine (not EC2):

```bash
# Initialize the database
curl http://<EC2_PUBLIC_IP>/init

# Add a note
curl "http://<EC2_PUBLIC_IP>/add?text=Lab1bTest"

# List notes
curl http://<EC2_PUBLIC_IP>/list
```

> ✅ **VERIFICATION**
> 
> - `/init` returns `Init Success!`
> - `/add` returns `Added: Lab1bTest`
> - `/list` returns your notes

---

## PART 7: Incident Response Simulation

Now you'll simulate a database outage and follow the incident response runbook to recover.

> ⚠️ **SCENARIO: You Are Now On-Call**
> 
> The system was working. No infrastructure changes were announced.
> Users are reporting failures. Your job is to:
> - **OBSERVE** using logs and metrics
> - **DIAGNOSE** the root cause
> - **RECOVER** without redeploying infrastructure

### Step 7.1: Inject the Failure

Stop the RDS instance to simulate a database outage:

```bash
aws rds stop-db-instance \
  --db-instance-identifier lab-mysql
```

Now access the application multiple times to generate errors:

```bash
# Hit the application several times to generate connection errors
curl http://<EC2_PUBLIC_IP>/list
curl http://<EC2_PUBLIC_IP>/list
curl http://<EC2_PUBLIC_IP>/list
curl http://<EC2_PUBLIC_IP>/list
```

**Wait 5-10 minutes** for the alarm to trigger and send you an email.

---

## RUNBOOK SECTION 1: Acknowledge

### 1.1 Confirm the Alert

```bash
aws cloudwatch describe-alarms \
  --alarm-names lab-db-connection-failure \
  --query "MetricAlarms[].StateValue"
```

> ✅ **EXPECTED:** `["ALARM"]`

---

## RUNBOOK SECTION 2: Observe

### 2.1 Check Application Logs

```bash
aws logs filter-log-events \
  --log-group-name /aws/ec2/lab-rds-app \
  --filter-pattern "DB_CONNECTION_FAILURE"
```

### 2.2 Classify the Failure Type

| Failure Type | Log Signature | Likely Cause |
|--------------|---------------|--------------|
| Credential failure | Access denied (1045) | Password mismatch |
| Network failure | Connection refused (2003) | SG or routing issue |
| Database unavailable | Can't connect / timed out | RDS stopped or endpoint changed |

---

## RUNBOOK SECTION 3: Validate Configuration

### 3.1 Check Parameter Store Values

```bash
aws ssm get-parameters \
  --names /lab/db/endpoint /lab/db/port /lab/db/name \
  --with-decryption
```

### 3.2 Check Secrets Manager

```bash
aws secretsmanager get-secret-value \
  --secret-id lab/rds/mysql2
```

> ✅ **EXPECTED:** Both commands return valid configuration. This rules out credential drift.

---

## RUNBOOK SECTION 4: Containment

**Do NOT:**
- Restart EC2 blindly
- Rotate secrets without diagnosis
- Redeploy infrastructure

**State explicitly:** *"System state preserved for recovery."*

---

## RUNBOOK SECTION 5: Recovery

### 5.1 Check RDS Status

```bash
aws rds describe-db-instances \
  --db-instance-identifier lab-mysql \
  --query "DBInstances[0].DBInstanceStatus"
```

### 5.2 Start the RDS Instance

```bash
aws rds start-db-instance \
  --db-instance-identifier lab-mysql
```

Wait for RDS to become `available` (5-10 minutes):

```bash
# Poll until status is 'available'
aws rds describe-db-instances \
  --db-instance-identifier lab-mysql \
  --query "DBInstances[0].DBInstanceStatus"
```

---

## RUNBOOK SECTION 6: Post-Incident Validation

### 6.1 Verify Application Recovery

```bash
curl http://<EC2_PUBLIC_IP>/list
```

> ✅ **EXPECTED:** Application returns data successfully.

### 6.2 Verify Alarm Clears

```bash
aws cloudwatch describe-alarms \
  --alarm-names lab-db-connection-failure \
  --query "MetricAlarms[].StateValue"
```

> ✅ **EXPECTED:** `["OK"]`

---

## Deliverables Checklist

| Item | Evidence Required | Points |
|------|-------------------|--------|
| Parameter Store entries | CLI output showing all 3 parameters | 10 |
| CloudWatch Log Group | CLI output showing log group exists | 10 |
| SNS Topic + Subscription | CLI output + email confirmation | 10 |
| CloudWatch Alarm | CLI output showing alarm config | 15 |
| Application working | Screenshot of /list returning data | 15 |
| Alarm triggered (ALARM state) | CLI output or email screenshot | 10 |
| Correct failure classification | Written explanation | 10 |
| Recovery without redeploy | Documentation of steps taken | 10 |
| Alarm cleared (OK state) | CLI output after recovery | 10 |

---

## Incident Report Template

**Incident Title:** Production Database Connectivity Timeout

**Incident Summary:**
- **What failed:** _______________
- **How detected:** _______________
- **Root cause:** _______________
- **Time to detection:** _______________
- **Time to recovery:** _______________

**Preventive Action:**
- One improvement to reduce MTTR: _______________
- One improvement to prevent recurrence: _______________

---

## Final Verification Script

```bash
# Run all verification commands

# 1. Parameters exist
aws ssm get-parameters --names /lab/db/endpoint /lab/db/port /lab/db/name

# 2. Log group exists
aws logs describe-log-groups --log-group-name-prefix /aws/ec2/lab-rds-app

# 3. SNS topic exists
aws sns list-topics | grep lab-db-incidents

# 4. Alarm exists and is OK
aws cloudwatch describe-alarms --alarm-names lab-db-connection-failure

# 5. Application responds
curl http://<EC2_PUBLIC_IP>/list
```

---

## What This Lab Proves About You

*If you complete this lab correctly, you can say:*

**"I can operate, monitor, and recover AWS workloads using proper secret management and observability."**

*That is mid-level engineer capability, not entry-level.*
