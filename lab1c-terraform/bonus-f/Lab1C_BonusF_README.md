# SEIR FOUNDATIONS
# LAB 1C BONUS F: CloudWatch Logs Insights Query Pack

*Enhanced Socratic Q&A Guide with Detailed Step-by-Step Instructions*

---

> [!warning] **PREREQUISITE**
> Lab 1C Bonus E (WAF Logging) must be completed and verified before starting Bonus F.
> You must have:
> - WAF logs flowing to CloudWatch Logs
> - Application logs in CloudWatch
> - Working ALB + TLS + WAF infrastructure from Bonus B

---

## Lab Overview

Bonus F transforms your logs from "data we have" into "intelligence we use." You'll build a **query pack**—a collection of pre-written Logs Insights queries that form the backbone of your incident runbook.

**What You'll Build:**
- WAF analysis queries (who's attacking, what's blocked, why)
- Application diagnostic queries (errors, patterns, root cause hints)
- Correlation workflow (connect the dots between WAF and app failures)

**Time Estimate:** 45-60 minutes

---

## Why This Lab Exists (Industry Context)

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** I already have logs. Why do I need pre-written queries?*
> 
> **A (Explain Like I'm 10):** Imagine you're a detective, and there's been a crime. Would you rather: (A) Start from scratch figuring out what questions to ask, or (B) Have a checklist of "The 10 Questions Every Detective Asks First"? During an incident, you're stressed, it's probably 3 AM, and your brain is mush. Pre-written queries are like that detective checklist—you run them immediately instead of trying to remember what to look for.
> 
> **Evaluator Question:** *Why do SRE teams maintain query packs as part of their runbooks?*
> 
> **Model Answer:** Query packs reduce Mean Time To Diagnose (MTTD) by eliminating the cognitive overhead of writing queries during incidents. They encode institutional knowledge—what patterns matter, what fields to extract, what thresholds indicate problems. New team members can run the same queries as veterans. They also ensure consistency: every incident is analyzed the same way, making post-incident comparison possible.

---

## STEP 0: Discover Your Log Group Names

Before running any queries, you need to find your **actual log group names**. These may differ from placeholder names in documentation.

### Step 0.1: List All Log Groups (CLI)

**Run this command:**
```bash
aws logs describe-log-groups --query 'logGroups[*].logGroupName' --output table
```

**Expected Output (example):**
```
---------------------------------------------------
|              DescribeLogGroups                  |
+-------------------------------------------------+
|  /aws/ec2/lab-rds-app                           |
|  /aws/rds/instance/lab-mysql/error              |
|  RDSOSMetrics                                   |
|  aws-waf-logs-chewbacca-webacl01                |
+-------------------------------------------------+
```

### Step 0.2: Identify Your Log Groups

**Record your actual log group names:**

| Log Type | Placeholder Name | Your Actual Name |
|----------|------------------|------------------|
| WAF Logs | `aws-waf-logs-<project>-webacl01` | `aws-waf-logs-chewbacca-webacl01` |
| App Logs | `/aws/ec2/<project>-rds-app` | `/aws/ec2/lab-rds-app` |

> [!warning] **CRITICAL: Use Your Actual Names**
> The app log group may be `/aws/ec2/lab-rds-app` (not `/aws/ec2/chewbacca-rds-app`). Using the wrong name will return zero results!

### Step 0.3: Verify Logs Exist in Each Group

**Check WAF logs exist:**
```bash
aws logs filter-log-events \
  --log-group-name aws-waf-logs-chewbacca-webacl01 \
  --limit 3
```

**Check App logs exist:**
```bash
aws logs filter-log-events \
  --log-group-name /aws/ec2/lab-rds-app \
  --limit 3
```

**Expected:** JSON output showing log events. If you see `"events": []`, either:
- Wrong log group name
- No recent logs (expand time range)
- Logs not configured correctly (go back to Bonus E)

---

## STEP 1: Access CloudWatch Logs Insights Console

### Step 1.1: Navigate to Logs Insights

1. Open AWS Console: https://console.aws.amazon.com
2. Search for "CloudWatch" in the search bar
3. Click **CloudWatch**
4. In the left sidebar, expand **Logs**
5. Click **Logs Insights**

```
┌─────────────────────────────────────────────────────────────────┐
│  AWS Console                                                    │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐                                           │
│  │ CloudWatch      │                                           │
│  │ ├─ Dashboards   │                                           │
│  │ ├─ Alarms       │                                           │
│  │ ├─ Logs         │  ◄── Expand this                          │
│  │ │  ├─ Log groups│                                           │
│  │ │  ├─ Logs      │                                           │
│  │ │  │  Insights  │  ◄── Click this                           │
│  │ │  └─ Query     │                                           │
│  │ │     definitions│                                          │
│  │ └─ Metrics      │                                           │
│  └─────────────────┘                                           │
└─────────────────────────────────────────────────────────────────┘
```

> [!tip] **Bookmark This URL**
> Replace `us-west-2` with your region:
> ```
> https://us-west-2.console.aws.amazon.com/cloudwatch/home?region=us-west-2#logsV2:logs-insights
> ```

---

## PART 1: WAF Query Pack (Queries A1-A8)

These queries analyze your WAF logs to understand traffic patterns, attacks, and blocking behavior.

---

### Query A1: Traffic Overview ("What's Happening Right Now?")

**Purpose:** First query to run—gives you immediate situational awareness.

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why is this the first query we run?*
> 
> **A (Explain Like I'm 10):** When you wake up to a fire alarm, your first question isn't "what color is the smoke?" It's "IS THERE ACTUALLY A FIRE?" This query answers the big picture first: Are requests flowing? Is WAF blocking a lot? Is everything being allowed?
> 
> **Evaluator Question:** *What would a healthy vs. unhealthy output look like?*
> 
> **Model Answer:** Healthy = Mostly ALLOW with occasional BLOCK (95%/5%). Under attack = High BLOCK count, possibly exceeding ALLOW. Misconfigured = Almost 100% BLOCK (rules too aggressive).

#### Step-by-Step Instructions:

**Step A1.1: Select the WAF Log Group**
1. In Logs Insights, click the **"Select log group(s)"** dropdown
2. Type: `aws-waf-logs`
3. Check the box next to your WAF log group (e.g., `aws-waf-logs-chewbacca-webacl01`)

**Step A1.2: Set Time Range**
1. Click the time range dropdown (default: "1 hour")
2. Select **"1 hour"** for initial testing
3. For incidents: Match your alarm's trigger time

**Step A1.3: Enter and Run the Query**
1. Delete any existing text in the query editor
2. Paste this query:
```sql
fields @timestamp, action
| stats count() as hits by action
| sort hits desc
```
3. Press **Ctrl+Enter** (Windows/Linux) or **Cmd+Enter** (Mac) to run

**Step A1.4: Interpret Results**
Expected output:
| action | hits |
|--------|------|
| ALLOW  | 1,234 |
| BLOCK  | 45    |

**Step A1.5: Save the Query**
1. Click the **"Save"** button (above the query editor)
2. Query name: `WAF-A1-TrafficOverview`
3. Folder: `incident-runbook` (create if needed)
4. Ensure your WAF log group is checked
5. Click **"Save"**

**✅ Screenshot:** Take a screenshot of the results showing ALLOW/BLOCK counts.

---

### Query A2: Top Client IPs

**Purpose:** Identify who is hitting your application the most.

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why do we care about client IPs?*
> 
> **A (Explain Like I'm 10):** Imagine your lemonade stand gets 100 visitors. If 95 are different neighbors, that's normal! But if ONE person came back 95 times in 5 minutes, that's suspicious. Checking who visits most helps you spot bots or attackers.
> 
> **Evaluator Question:** *How would you use this during an incident?*
> 
> **Model Answer:** Look for single IP with disproportionate traffic (scanner/bot), multiple IPs from same /24 subnet (coordinated attack), or IPs you recognize as internal vs. external.

#### Step-by-Step Instructions:

**Step A2.1:** Keep the same WAF log group selected

**Step A2.2:** Clear the query editor and paste:
```sql
fields @timestamp, httpRequest.clientIp as clientIp
| stats count() as hits by clientIp
| sort hits desc
| limit 25
```

**Step A2.3:** Press **Ctrl+Enter** to run

**Step A2.4:** Review results - look for IPs with unusually high hit counts

**Step A2.5:** Save as `WAF-A2-TopClientIPs`

---

### Query A3: Top Requested URIs

**Purpose:** Understand what paths attackers or users are targeting.

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why does the requested path matter?*
> 
> **A (Explain Like I'm 10):** If someone keeps knocking on your front door, that's normal. If they keep trying the back window, basement door, and checking if the garage is unlocked—that's a burglar! Attackers probe specific paths like `/admin`, `/wp-login.php`, `/.env`.
> 
> **Evaluator Question:** *What URI patterns indicate attack activity?*
> 
> **Model Answer:** CMS probes (`/wp-login.php`, `/phpmyadmin`), config file hunting (`/.env`, `/.git/config`), injection attempts (URIs with `'`, `"`, `<script>`), path traversal (`/../../../etc/passwd`).

#### Step-by-Step Instructions:

**Step A3.1:** Clear the query editor and paste:
```sql
fields @timestamp, httpRequest.uri as uri
| stats count() as hits by uri
| sort hits desc
| limit 25
```

**Step A3.2:** Press **Ctrl+Enter** to run

**Step A3.3:** Save as `WAF-A3-TopURIs`

---

### Query A4: Blocked Requests Only

**Purpose:** Focus specifically on what WAF is stopping—your threat landscape.

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** If requests are blocked, why do we care?*
> 
> **A (Explain Like I'm 10):** Your guard dog stopped a burglar at the fence. Great! But wouldn't you want to know: Was it the same burglar every night? Were they trying the same window? Blocked requests tell you what threats are actively targeting you—even if they failed.
> 
> **Evaluator Question:** *How would you escalate findings from this query?*
> 
> **Model Answer:** Same IP repeatedly blocked → add to permanent block list. Same URI pattern across many IPs → botnet/coordinated scan. Blocks for paths that shouldn't exist → possible vulnerability being probed.

#### Step-by-Step Instructions:

**Step A4.1:** Clear the query editor and paste:
```sql
fields @timestamp, action, httpRequest.clientIp as clientIp, httpRequest.uri as uri
| filter action = "BLOCK"
| stats count() as blocks by clientIp, uri
| sort blocks desc
| limit 25
```

**Step A4.2:** Press **Ctrl+Enter** to run

**Step A4.3:** Save as `WAF-A4-BlockedRequests`

**✅ Screenshot:** Take a screenshot showing blocked IPs and URIs.

---

### Query A5: Which WAF Rule Is Blocking?

**Purpose:** Identify which specific WAF rule is doing the work.

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why know which RULE blocked the request?*
> 
> **A (Explain Like I'm 10):** If you have 5 security guards and hear "we stopped 100 intruders," wouldn't you want to know which guard caught most? If Guard #3 caught 95 people, maybe the others aren't positioned right—or maybe Guard #3 is too aggressive!
> 
> **Evaluator Question:** *What does the distribution of blocks across rules tell you?*
> 
> **Model Answer:** Most from AWSManagedRulesCommonRuleSet = normal. Many from SQLi/XSS rules = targeted injection attempts. All from rate-based = DDoS. One rule with zero blocks = possibly misconfigured.

#### Step-by-Step Instructions:

**Step A5.1:** Clear the query editor and paste:
```sql
fields @timestamp, action, terminatingRuleId, terminatingRuleType
| filter action = "BLOCK"
| stats count() as blocks by terminatingRuleId, terminatingRuleType
| sort blocks desc
| limit 25
```

**Step A5.2:** Press **Ctrl+Enter** to run

**Step A5.3:** Save as `WAF-A5-BlockingRules`

---

### Query A6: Rate of Blocks Over Time

**Purpose:** Visualize when blocks spiked—correlate with incident timeline.

> [!warning] **KNOWN ISSUE: Original Query Has Syntax Error**
> The query `sort bin(1m)` does NOT work in CloudWatch Logs Insights. You must use an alias.

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why see blocks over TIME instead of just totals?*
> 
> **A (Explain Like I'm 10):** If I told you "100 people tried to break into houses this month," that's scary. But if I told you "95 of them tried on October 31st"—oh, that's just Halloween pranksters! Time patterns reveal WHEN something happened.
> 
> **Evaluator Question:** *How would you correlate this with your CloudWatch alarm?*
> 
> **Model Answer:** If blocks spiked 2 minutes BEFORE the alarm → attack may have caused backend failure. If blocks spiked AFTER → unrelated. If blocks are flat but app errors spiked → internal failure, not attack.

#### Step-by-Step Instructions:

**Step A6.1:** Clear the query editor and paste the **CORRECTED** query:
```sql
fields @timestamp, action
| filter action = "BLOCK"
| stats count() as blocks by bin(1m) as minute
| sort minute asc
```

> [!danger] **DO NOT USE THIS (BROKEN):**
> ```sql
> | stats count() as blocks by bin(1m)
> | sort bin(1m) asc
> ```
> Error: `unexpected symbol found ( at line 4`
> 
> **FIX:** Add alias `as minute` then sort by the alias.

**Step A6.2:** Press **Ctrl+Enter** to run

**Step A6.3:** Switch to Visualization
1. Click the **"Visualization"** tab (above results)
2. Select **"Line"** chart type
3. You should see blocks over time

**Step A6.4:** Save as `WAF-A6-BlockRateOverTime`

**✅ Screenshot:** Take a screenshot of the line chart showing block rate over time.

---

### Query A7: Suspicious Scanner Detection

**Purpose:** Catch automated scanners probing for common vulnerabilities.

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why are paths like wp-login, .env, .git suspicious?*
> 
> **A (Explain Like I'm 10):** These paths are like a burglar's checklist: "First, check if they left a key under the mat (.env file). Then try the WordPress door (wp-login). Then look for the secret tunnel (.git folder)." If someone hits `/wp-login.php` on your Flask app, they're not a real user—they're a robot.
> 
> **Evaluator Question:** *What's the difference between a scanner and a targeted attack?*
> 
> **Model Answer:** Scanners hit generic paths across thousands of IPs—low effort, high volume, automated tools. Targeted attacks know YOUR specific application, probe YOUR actual endpoints—lower volume, higher sophistication.

#### Step-by-Step Instructions:

**Step A7.1:** Clear the query editor and paste:
```sql
fields @timestamp, httpRequest.clientIp as clientIp, httpRequest.uri as uri
| filter uri =~ /wp-login|xmlrpc|\.env|admin|phpmyadmin|\.git|login/
| stats count() as hits by clientIp, uri
| sort hits desc
| limit 50
```

**Step A7.2:** Press **Ctrl+Enter** to run

**Step A7.3:** Review results - these are automated scanners/attackers

**Example Real Results:**
| clientIp | uri | hits |
|----------|-----|------|
| 216.81.248.xxx | /.git/config | 3 |
| 216.81.248.xxx | /.gitlab-ci.yml | 1 |
| 20.24.66.xxx | /wp-admin/admin.php | 2 |
| 20.24.66.xxx | /wp-content/plugins/admin.php | 1 |

**Interpretation:** This is normal internet scanner noise. WAF is blocking successfully.

**Step A7.4:** Save as `WAF-A7-SuspiciousScanners`

**✅ Screenshot:** Take a screenshot showing scanner activity.

---

### Query A8: Geographic Distribution

**Purpose:** See where traffic originates geographically.

> [!note] **Availability**
> The `country` field is only available if your WAF logs include geo-location data (depends on WAF configuration).

#### Step-by-Step Instructions:

**Step A8.1:** Clear the query editor and paste:
```sql
fields @timestamp, httpRequest.country as country
| stats count() as hits by country
| sort hits desc
| limit 25
```

**Step A8.2:** Press **Ctrl+Enter** to run

**Step A8.3:** If you get results, save as `WAF-A8-GeoDistribution`

> [!note] If `country` field is empty, this query will return no useful data. Skip and continue.

---

## PART 2: Application Query Pack (Queries B1-B4)

These queries analyze your application logs to diagnose errors, DB issues, and failures.

> [!warning] **CRITICAL: Switch Log Groups**
> Before running B queries, you MUST select your **App log group** (e.g., `/aws/ec2/lab-rds-app`), NOT the WAF log group.

---

### Query B1: Error Rate Over Time

**Purpose:** See when application errors started—establishes incident timeline.

> [!warning] **KNOWN ISSUE: Regex Flag `/i` Not Supported**
> CloudWatch Logs Insights does NOT support case-insensitive regex flags like `/ERROR/i`. You must match exact case.

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why track errors over TIME?*
> 
> **A (Explain Like I'm 10):** If your tummy hurts, the doctor asks "when did it start?" Not "does it hurt now?" Knowing WHEN errors started helps you find what changed—a deploy, an attack, a config change.
> 
> **Evaluator Question:** *How do you use this to establish incident timeline?*
> 
> **Model Answer:** Correlate error spike with: deployment times, WAF block spikes, config changes, or external events. If errors jumped at 3:07 AM and you deployed at 3:05 AM, you found your root cause.

#### Step-by-Step Instructions:

**Step B1.1: Switch to App Log Group**
1. Click the log group dropdown
2. **UNCHECK** the WAF log group
3. **CHECK** your App log group: `/aws/ec2/lab-rds-app`

**Step B1.2:** Set time range to **1 week** (logs may not be recent)

**Step B1.3:** Clear the query editor and paste the **CORRECTED** query:
```sql
fields @timestamp, @message
| filter @message like /ERROR|Exception|Traceback|DB|timeout|refused/
| stats count() as errors by bin(1m) as minute
| sort minute desc
```

> [!danger] **DO NOT USE THIS (BROKEN):**
> ```sql
> | filter @message like /ERROR/i
> ```
> Error: `unexpected symbol found i at line 2`
> 
> **FIX:** Remove the `/i` flag. CloudWatch doesn't support case-insensitive regex.

**Step B1.4:** Press **Ctrl+Enter** to run

**Step B1.5:** If no results in 1 hour, expand time range to **1 week**

**Step B1.6:** Save as `App-B1-ErrorRateOverTime`

---

### Query B2: Recent DB Failures

**Purpose:** Find specific database connection errors for triage.

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why focus specifically on DB errors?*
> 
> **A (Explain Like I'm 10):** Your app is like a restaurant. The database is the kitchen. If customers complain about no food, check the kitchen first! DB errors are often the root cause of "app not working."
> 
> **Evaluator Question:** *What DB error patterns indicate different root causes?*
> 
> **Model Answer:** "Access denied" = wrong credentials (Secrets Manager). "Connection refused" = DB not running or wrong port. "No route to host" = network/security group issue. "Timeout" = overloaded or network latency.

#### Step-by-Step Instructions:

**Step B2.1:** Ensure App log group is selected

**Step B2.2:** Set time range to **1 week** (to find historical incidents)

**Step B2.3:** Clear the query editor and paste:
```sql
fields @timestamp, @message
| filter @message like /DB|mysql|timeout|refused|Access denied|could not connect|No route/
| sort @timestamp desc
| limit 50
```

**Step B2.4:** Press **Ctrl+Enter** to run

**Step B2.5:** Review results - look for patterns

**Example Real Results (Historical Incident Found):**
```
2026-02-02 04:26:22 - DB connection failed: (2003, "Can't connect to MySQL server on lab-mysql.cl02ec282asu.us-west-2.rds.amazonaws.com" ([Errno 113] No route to host))
2026-02-02 04:49:17 - DB connection successful
```

**Interpretation:** 
- Errno 113 = "No route to host" = Network/Security Group issue OR RDS stopped
- Incident duration: ~23 minutes (04:26 to 04:49)

**Step B2.6:** Save as `App-B2-RecentDBFailures`

**✅ Screenshot:** Take a screenshot showing any DB errors found.

---

### Query B3: Failure Classification

**Purpose:** Categorize errors to guide troubleshooting.

> [!danger] **KNOWN ISSUE: `case()` Function Does NOT Exist**
> CloudWatch Logs Insights does NOT have a `case()` function. The original query in documentation is **WRONG**.
> 
> **Original (BROKEN):**
> ```sql
> | fields case(
>     @message like /Access denied|authentication/ as "Creds/Auth",
>     @message like /timeout|No route/ as "Network/Route",
>     ...
>   ) as failure_type
> ```
> Error: `Unrecognized function name: case`
> 
> **SOLUTION:** Split into 3 separate queries (B3a, B3b, B3c).

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why classify errors instead of just reading them?*
> 
> **A (Explain Like I'm 10):** If 100 customers complain, you could read all 100 complaints... OR you could sort them: "78 say the food was cold, 15 say the waiter was rude, 7 say parking was bad." Now you know: FIX THE KITCHEN FIRST. Classification tells you where to focus.
> 
> **Evaluator Question:** *How does classification accelerate incident response?*
> 
> **Model Answer:** "78% of errors are Creds/Auth" immediately tells you: check Secrets Manager, don't waste time on network debugging. It's the difference between "something is broken" and "the password is wrong."

#### Step-by-Step Instructions:

Since `case()` doesn't exist, run THREE separate queries:

---

**Query B3a: Creds/Auth Failures**

**Step B3a.1:** Clear the query editor and paste:
```sql
fields @timestamp, @message
| filter @message like /Access denied|authentication failed|invalid credentials|password/
| stats count() as hits
```

**Step B3a.2:** Press **Ctrl+Enter** to run

**Step B3a.3:** Record the hit count: `Creds/Auth failures: ____`

**Step B3a.4:** Save as `App-B3a-CredsAuth`

---

**Query B3b: Network/Route Failures**

> [!warning] **KNOWN ISSUE: Case Sensitivity**
> CloudWatch regex is CASE SENSITIVE. Log may say "No route to host" (capital N), not "no route".

**Step B3b.1:** Clear the query editor and paste:
```sql
fields @timestamp, @message
| filter @message like /timeout|No route|route to host|Errno 113/
| stats count() as hits
```

> [!danger] **DO NOT USE (may miss results):**
> ```sql
> | filter @message like /timeout|no route/
> ```
> If log says "No route to host" (capital N), lowercase "no route" won't match!

**Step B3b.2:** Press **Ctrl+Enter** to run

**Step B3b.3:** Record the hit count: `Network/Route failures: ____`

**Step B3b.4:** Save as `App-B3b-NetworkRoute`

---

**Query B3c: Port/Connection Refused**

**Step B3c.1:** Clear the query editor and paste:
```sql
fields @timestamp, @message
| filter @message like /refused|could not connect|Connection refused|port/
| stats count() as hits
```

**Step B3c.2:** Press **Ctrl+Enter** to run

**Step B3c.3:** Record the hit count: `Port/Refused failures: ____`

**Step B3c.4:** Save as `App-B3c-PortRefused`

---

**Interpreting B3 Results:**

| Category | High Count Means | Action |
|----------|------------------|--------|
| Creds/Auth | Wrong password/username | Check Secrets Manager, verify secret rotation |
| Network/Route | Can't reach DB | Check security groups, route tables, RDS status |
| Port/Refused | DB not listening | Check RDS instance state, port configuration |

---

### Query B4: JSON Log Analysis (CONDITIONAL)

**Purpose:** Parse structured JSON logs for detailed analysis.

> [!warning] **PREREQUISITE CHECK**
> This query ONLY works if your app logs in JSON format. Many apps log plain text.

#### Step-by-Step Instructions:

**Step B4.1: Check Your Log Format First**

Run this test query:
```sql
fields @timestamp, @message
| limit 10
```

**Look at the results:**
- **JSON logs look like:** `{"timestamp": "2026-02-02T04:26:22", "level": "ERROR", "message": "DB failed"}`
- **Plain text logs look like:** `2026-02-02 04:26:22 - ERROR - DB connection failed`

**Step B4.2: If JSON Format, Run:**
```sql
fields @timestamp, level, message, error_code
| filter level = "ERROR"
| stats count() as errors by error_code
| sort errors desc
```

**Step B4.3: If Plain Text Format:**
Skip this query. Your logs don't support JSON field extraction.

**Step B4.4:** If applicable, save as `App-B4-JSONErrors`

---

## STEP 3: Verify All Queries Are Saved

### Step 3.1: View Saved Queries in Console

1. In Logs Insights, click **"Saved and sample queries"** button
2. OR navigate to **CloudWatch → Logs → Query definitions**
3. You should see your saved queries in the `incident-runbook` folder

**Expected Saved Queries:**
- `WAF-A1-TrafficOverview`
- `WAF-A2-TopClientIPs`
- `WAF-A3-TopURIs`
- `WAF-A4-BlockedRequests`
- `WAF-A5-BlockingRules`
- `WAF-A6-BlockRateOverTime`
- `WAF-A7-SuspiciousScanners`
- `WAF-A8-GeoDistribution` (if applicable)
- `App-B1-ErrorRateOverTime`
- `App-B2-RecentDBFailures`
- `App-B3a-CredsAuth`
- `App-B3b-NetworkRoute`
- `App-B3c-PortRefused`
- `App-B4-JSONErrors` (if applicable)

**✅ Screenshot:** Take a screenshot of your saved queries list.

---

## STEP 4: CLI Verification Commands

Run these commands to generate CLI evidence for deliverables.

> [!warning] **macOS vs Linux Date Commands**
> The `date` command syntax differs between macOS and Linux. Use the correct version for your system.

### 4.1: Verify WAF Log Group Exists

```bash
aws logs describe-log-groups \
  --log-group-name-prefix aws-waf-logs-chewbacca

aws logs filter-log-events \
  --log-group-name aws-waf-logs-chewbacca-webacl01 \
  --limit 5
```

### 4.2: Verify App Log Group Exists

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /aws/ec2/lab-rds-app

aws logs filter-log-events \
  --log-group-name /aws/ec2/lab-rds-app \
  --limit 5
```

### 4.3: Run Sample Query via CLI

**macOS (BSD date):**
```bash
QUERY_ID=$(aws logs start-query \
  --log-group-name aws-waf-logs-chewbacca-webacl01 \
  --start-time $(date -v-1H +%s) \
  --end-time $(date +%s) \
  --query-string 'stats count() by action' \
  --query 'queryId' --output text)

echo "Query ID: $QUERY_ID"

sleep 5

aws logs get-query-results --query-id $QUERY_ID
```

**Linux (GNU date):**
```bash
QUERY_ID=$(aws logs start-query \
  --log-group-name aws-waf-logs-chewbacca-webacl01 \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'stats count() by action' \
  --query 'queryId' --output text)

echo "Query ID: $QUERY_ID"

sleep 5

aws logs get-query-results --query-id $QUERY_ID
```

**Quick Reference: Date Command Differences**

| What You Want | macOS (BSD) | Linux (GNU) |
|---------------|-------------|-------------|
| 1 hour ago | `date -v-1H +%s` | `date -d '1 hour ago' +%s` |
| 1 day ago | `date -v-1d +%s` | `date -d '1 day ago' +%s` |
| 1 week ago | `date -v-1w +%s` | `date -d '1 week ago' +%s` |
| Now | `date +%s` | `date +%s` |

### 4.4: List Saved Query Definitions (Optional)

```bash
aws logs describe-query-definitions \
  --query-definition-name-prefix WAF

aws logs describe-query-definitions \
  --query-definition-name-prefix App
```

---

## Troubleshooting Guide

### Issue 1: Query Returns 0 Results

**Symptoms:** Query runs but shows "0 records matched"

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Wrong log group selected | Verify correct log group (WAF vs App) |
| Time range too narrow | Expand from 1 hour to 1 week |
| No matching log entries | Run `fields @timestamp, @message \| limit 10` to see actual log format |
| Case sensitivity mismatch | Check exact capitalization in logs (e.g., "No route" vs "no route") |

**Diagnostic Query:**
```sql
fields @timestamp, @message
| limit 10
```
This shows you what's actually in the logs.

---

### Issue 2: `unexpected symbol found ( at line X`

**Symptom:** Error when using `sort bin(1m)`

**Cause:** Cannot use `bin()` directly in sort clause

**Fix:** Add alias, then sort by alias:
```sql
# WRONG
| stats count() by bin(1m)
| sort bin(1m) asc

# CORRECT
| stats count() by bin(1m) as minute
| sort minute asc
```

---

### Issue 3: `unexpected symbol found i at line X`

**Symptom:** Error when using regex flag `/pattern/i`

**Cause:** CloudWatch Logs Insights doesn't support regex flags

**Fix:** Remove the flag and add explicit case variations if needed:
```sql
# WRONG
| filter @message like /ERROR/i

# CORRECT
| filter @message like /ERROR|Error|error/
```

---

### Issue 4: `Unrecognized function name: case`

**Symptom:** Error when using `case()` function

**Cause:** CloudWatch Logs Insights has no `case()` function

**Fix:** Split into multiple separate queries (see B3a, B3b, B3c approach)

---

### Issue 5: macOS `date: illegal option -- d`

**Symptom:** Error running CLI commands with `date -d`

**Cause:** macOS uses BSD date, not GNU date

**Fix:** Use macOS syntax:
```bash
# WRONG (Linux only)
date -d '1 hour ago' +%s

# CORRECT (macOS)
date -v-1H +%s
```

---

### Issue 6: Query Runs But Misses Known Errors

**Symptom:** You KNOW errors exist but query returns 0

**Cause:** Case sensitivity or exact string mismatch

**Solution:** 
1. First, view raw logs:
```sql
fields @timestamp, @message
| filter @message like /error/
| limit 20
```

2. Copy the EXACT error text from results
3. Update your filter to match exactly

**Example:**
- Log contains: `[Errno 113] No route to host`
- Query `filter @message like /no route/` → 0 results (wrong case)
- Query `filter @message like /No route/` → ✅ matches

---

## Deliverables Checklist

| # | Requirement | Evidence | Status |
|---|-------------|----------|--------|
| 1 | WAF queries work (A1-A7) | Screenshots of query results | ⬜ |
| 2 | App queries work (B1-B3) | Screenshots of query results | ⬜ |
| 3 | Queries saved in CloudWatch | Screenshot of saved queries list | ⬜ |
| 4 | CLI verification commands run | Terminal output | ⬜ |
| 5 | Can explain attack vs internal failure | Written explanation | ⬜ |

---

## Reflection Questions

### A) Why are pre-written queries valuable during incidents?

**Model Answer:** They eliminate cognitive load during high-stress situations. Engineers don't have to remember query syntax or what fields to examine—they just run the pre-built queries. This reduces Mean Time To Diagnose (MTTD) and ensures consistent analysis across incidents and team members.

### B) What's the difference between logs in CloudWatch Logs vs. S3?

**Model Answer:** CloudWatch Logs: Real-time, indexed, searchable with Logs Insights, retention costs more at scale, ideal for operational queries. S3: Batch storage, much cheaper at scale, requires Athena or external tools to query, ideal for long-term archive and compliance.

### C) How does failure classification (Query B3) accelerate incident response?

**Model Answer:** Instead of reading hundreds of error messages, classification groups them into actionable categories. "78% of errors are Creds/Auth" immediately tells you: check Secrets Manager, don't waste time on network debugging.

### D) What did the Errno 113 error in Query B2 results indicate?

**Model Answer:** Errno 113 means "No route to host"—a network-level failure. The EC2 instance couldn't reach the RDS instance. Root causes include: security group blocking traffic, route table misconfiguration, RDS instance stopped, or network ACL issues. This is a Network/Route category failure, not a credentials issue.

---

## What This Lab Proves About You

*If you complete this lab, you can confidently say:*

> **"I can build and operate incident response tooling using CloudWatch Logs Insights. I understand how to correlate signals across security and application logs to diagnose production issues, and I can troubleshoot query syntax issues when they arise."**

*This is SRE/DevOps engineer capability. You're not just deploying infrastructure—you're building the observability layer that keeps it running.*

---

## Quick Reference: All Working Queries

### WAF Queries (Log group: `aws-waf-logs-chewbacca-webacl01`)

| ID | Query |
|----|-------|
| A1 | `fields @timestamp, action \| stats count() as hits by action \| sort hits desc` |
| A2 | `fields @timestamp, httpRequest.clientIp as clientIp \| stats count() as hits by clientIp \| sort hits desc \| limit 25` |
| A3 | `fields @timestamp, httpRequest.uri as uri \| stats count() as hits by uri \| sort hits desc \| limit 25` |
| A4 | `fields @timestamp, action, httpRequest.clientIp as clientIp, httpRequest.uri as uri \| filter action = "BLOCK" \| stats count() as blocks by clientIp, uri \| sort blocks desc \| limit 25` |
| A5 | `fields @timestamp, action, terminatingRuleId, terminatingRuleType \| filter action = "BLOCK" \| stats count() as blocks by terminatingRuleId, terminatingRuleType \| sort blocks desc` |
| A6 | `fields @timestamp, action \| filter action = "BLOCK" \| stats count() as blocks by bin(1m) as minute \| sort minute asc` |
| A7 | `fields @timestamp, httpRequest.clientIp as clientIp, httpRequest.uri as uri \| filter uri =~ /wp-login\|xmlrpc\|\.env\|admin\|phpmyadmin\|\.git\|login/ \| stats count() as hits by clientIp, uri \| sort hits desc \| limit 50` |
| A8 | `fields @timestamp, httpRequest.country as country \| stats count() as hits by country \| sort hits desc \| limit 25` |

### App Queries (Log group: `/aws/ec2/lab-rds-app`)

| ID | Query |
|----|-------|
| B1 | `fields @timestamp, @message \| filter @message like /ERROR\|Exception\|Traceback\|DB\|timeout\|refused/ \| stats count() as errors by bin(1m) as minute \| sort minute desc` |
| B2 | `fields @timestamp, @message \| filter @message like /DB\|mysql\|timeout\|refused\|Access denied\|could not connect\|No route/ \| sort @timestamp desc \| limit 50` |
| B3a | `fields @timestamp, @message \| filter @message like /Access denied\|authentication failed\|invalid credentials\|password/ \| stats count() as hits` |
| B3b | `fields @timestamp, @message \| filter @message like /timeout\|No route\|route to host\|Errno 113/ \| stats count() as hits` |
| B3c | `fields @timestamp, @message \| filter @message like /refused\|could not connect\|Connection refused\|port/ \| stats count() as hits` |

---

## Next Steps

After completing Bonus F, you have a complete observability stack:

- **Bonus A:** VPC Endpoints + Private EC2 (enterprise security)
- **Bonus B:** ALB + TLS + WAF (production ingress)
- **Bonus C:** Route53 DNS + ACM (domain management)
- **Bonus D:** Zone apex + ALB logs to S3 (access logging)
- **Bonus E:** WAF logging (security visibility)
- **Bonus F:** Logs Insights queries (operational intelligence)

**You've built the full stack that real companies use.**

*Proceed to Lab 2 when you're ready to add CloudFront and origin cloaking.*
