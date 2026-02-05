# SEIR FOUNDATIONS
# LAB 1C BONUS F: CloudWatch Logs Insights Query Pack

*Enhanced Socratic Q&A Guide for Incident Response*

---

> [!warning] **PREREQUISITE**
> Lab 1C Bonus E (WAF Logging) must be completed and verified before starting Bonus F.
> You must have:
> - WAF logs flowing to CloudWatch Logs (`aws-waf-logs-<project>-webacl01`)
> - Application logs in CloudWatch (`/aws/ec2/<project>-rds-app`)
> - Working ALB + TLS + WAF infrastructure from Bonus B

---

## Lab Overview

Bonus F transforms your logs from "data we have" into "intelligence we use." You'll build a **query pack**—a collection of pre-written Logs Insights queries that form the backbone of your incident runbook.

**What You'll Build:**
- WAF analysis queries (who's attacking, what's blocked, why)
- Application diagnostic queries (errors, patterns, root cause hints)
- Correlation workflow (connect the dots between WAF and app failures)

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

## Understanding CloudWatch Logs Insights

### What Logs Insights Actually Does

```
Your Logs (millions of lines) → Logs Insights Query → Actionable Summary
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why can't I just grep through logs like I do on Linux?*
> 
> **A (Explain Like I'm 10):** Imagine searching for your friend's photo in a pile of 10 million photos. You COULD flip through each one... or you could use a smart album app that organizes photos by date, face, and location, then searches in seconds. Logs Insights is that smart album—it indexes your logs and runs queries across terabytes in seconds. Grep works great for small files on one server; Logs Insights works for millions of log entries across dozens of servers.
> 
> **Evaluator Question:** *What are the key differences between Logs Insights and traditional log analysis (grep/awk)?*
> 
> **Model Answer:** Logs Insights provides: (1) Distributed query execution across multiple log streams simultaneously, (2) Automatic field discovery from JSON logs, (3) Time-range filtering at the storage layer (not scanning everything), (4) Aggregation functions (stats, count, avg) that would require complex awk pipelines, (5) Visualization integration with CloudWatch dashboards. Traditional tools require logs on local disk and scale poorly beyond single machines.

---

### Log Sources in This Lab

| Log Source | Location | What It Contains |
|------------|----------|------------------|
| WAF Logs | `aws-waf-logs-<project>-webacl01` | Every HTTP request, ALLOW/BLOCK decisions, client IPs, URIs |
| App Logs | `/aws/ec2/<project>-rds-app` | Application errors, DB connection attempts, business logic logs |
| ALB Access Logs | **S3 bucket** (not CloudWatch) | Full request/response details, latency, status codes |

> [!warning] **CRITICAL NOTE**
> ALB access logs are in **S3**, not CloudWatch Logs. You cannot query them with Logs Insights directly. For ALB analysis, use:
> - CloudWatch **metrics** (HTTPCode_Target_5XX_Count, etc.)
> - **Athena** for S3 log querying (advanced)
> - Third-party tools (Splunk, Datadog, etc.)

---

## Console Walkthrough: Running Logs Insights Queries

This section walks you through using the AWS Console to run Logs Insights queries. **This is the recommended approach** for learning and incident triage.

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why use the Console instead of CLI for running queries?*
> 
> **A (Explain Like I'm 10):** Imagine debugging a mystery. Would you rather: (A) Get clues written on index cards one at a time, or (B) Have a giant whiteboard where you can see everything at once, draw connections, and move things around? The Console is that whiteboard—you see results visually, adjust time ranges with sliders, and click on entries to expand details. CLI is great for automation, but Console is where humans solve problems.
> 
> **Evaluator Question:** *When would you choose CLI over Console for log analysis?*
> 
> **Model Answer:** CLI for: (1) Automation/scripting (scheduled evidence collection), (2) CI/CD pipelines (automated health checks), (3) When Console is inaccessible (network issues, IAM restrictions), (4) Bulk operations across multiple log groups. Console for: (1) Active incident triage, (2) Exploratory analysis, (3) Learning/experimentation, (4) Creating visualizations, (5) Sharing screens with teammates during incidents.

---

### Step-by-Step: Accessing Logs Insights

#### Step 1: Navigate to CloudWatch Logs Insights

**Path:** AWS Console → CloudWatch → Logs → Logs Insights

```
┌─────────────────────────────────────────────────────────────────┐
│  AWS Console Header                                    [Region] │
├─────────────────────────────────────────────────────────────────┤
│  Services ▼   CloudWatch                                        │
│                                                                 │
│  ┌─────────────────┐                                           │
│  │ CloudWatch      │                                           │
│  │ ├─ Dashboards   │                                           │
│  │ ├─ Alarms       │                                           │
│  │ ├─ Logs         │  ◄── Click this                           │
│  │ │  ├─ Log groups│                                           │
│  │ │  ├─ Logs      │                                           │
│  │ │  │  Insights  │  ◄── Then click this                      │
│  │ │  └─ ...       │                                           │
│  │ └─ Metrics      │                                           │
│  └─────────────────┘                                           │
└─────────────────────────────────────────────────────────────────┘
```

**What You'll See:**
- Left sidebar with CloudWatch navigation
- "Logs Insights" appears under the "Logs" section
- Click it to open the query editor

> [!tip] **Quick Access URL**
> Bookmark this direct link (replace `us-east-1` with your region):
> ```
> https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:logs-insights
> ```

---

#### Step 2: Select Your Log Group(s)

**What You'll See:**

```
┌─────────────────────────────────────────────────────────────────┐
│  CloudWatch > Logs > Logs Insights                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Select log group(s)                                            │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ 🔍 Search log groups...                              [▼]  │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Recently selected:                                             │
│  ☐ aws-waf-logs-chewbacca-webacl01                             │
│  ☐ /aws/ec2/chewbacca-rds-app                                  │
│  ☐ /aws/lambda/my-function                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Actions:**
1. Click the dropdown or search box
2. Type your log group name (e.g., `aws-waf-logs-chewbacca`)
3. Check the checkbox next to your log group
4. You can select **multiple log groups** to query across them simultaneously

> [!note] **Pro Tip: Multi-Log Group Queries**
> Select both your WAF log group AND app log group to correlate events in a single query. Use `@logStream` or `@log` fields to distinguish which log group an entry came from.

---

#### Step 3: Set the Time Range

**What You'll See:**

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  Time range:  [ 15 minutes ▼ ]                                  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Relative                    │  Absolute                │   │
│  │  ○ 5 minutes                 │                          │   │
│  │  ○ 15 minutes   ◄── Default │  Start: [____________]   │   │
│  │  ○ 30 minutes                │  End:   [____________]   │   │
│  │  ○ 1 hour                    │                          │   │
│  │  ○ 3 hours                   │  [Apply]                 │   │
│  │  ○ 12 hours                  │                          │   │
│  │  ○ 1 day                     │                          │   │
│  │  ○ Custom                    │                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Actions:**
1. Click the time range dropdown (default: "15 minutes")
2. For incidents: Match your alarm's trigger time
3. For exploration: Start with "1 hour" then narrow down
4. Use "Absolute" tab to specify exact start/end times (useful for post-incident analysis)

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why does time range selection matter so much?*
> 
> **A (Explain Like I'm 10):** Imagine searching for "when did the dog bark?" If you check the last 5 minutes but the dog barked 20 minutes ago, you'll find nothing and think "the dog never barked!" Time range is like setting the search window on your security camera footage. Too narrow = miss the event. Too wide = drown in irrelevant data and slow queries.
> 
> **Evaluator Question:** *How do you determine the right time range during an incident?*
> 
> **Model Answer:** Start with the alarm trigger time and work backward. If alarm fired at 3:07 AM: (1) First query: 3:00-3:15 AM (capture the incident), (2) If you need more context: expand to 2:45-3:30 AM, (3) For root cause: look at 24h trend to see if this was gradual or sudden. Avoid querying "last 7 days" unless necessary—it's slow and expensive.

---

#### Step 4: Enter Your Query

**What You'll See:**

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  Query editor:                                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ fields @timestamp, @message                               │ │
│  │ | sort @timestamp desc                                    │ │
│  │ | limit 20                                                │ │
│  │                                                           │ │
│  │                                                           │ │
│  │                                                           │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  [Run query]  [Save]  [History ▼]  [▶ Sample queries]          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Actions:**
1. Delete the default query
2. Paste your query from this guide (e.g., Query A1)
3. Click **Run query** (or press Ctrl+Enter / Cmd+Enter)

**Example - Paste Query A1:**
```sql
fields @timestamp, action
| stats count() as hits by action
| sort hits desc
```

> [!tip] **Keyboard Shortcut**
> Press `Ctrl+Enter` (Windows/Linux) or `Cmd+Enter` (Mac) to run the query without clicking the button.

---

#### Step 5: View Results

**What You'll See (Table View):**

```
┌─────────────────────────────────────────────────────────────────┐
│  Results (2 records matched)                     [📊] [📋] [⬇] │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────┬────────┐                                         │
│  │ action   │ hits   │                                         │
│  ├──────────┼────────┤                                         │
│  │ ALLOW    │ 1,247  │                                         │
│  │ BLOCK    │ 53     │                                         │
│  └──────────┴────────┘                                         │
│                                                                 │
│  Query runtime: 0.8 seconds                                     │
│  Records scanned: 1,300                                         │
│  Bytes scanned: 2.1 MB                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Key Elements:**
- **Records matched:** How many log entries matched your query
- **Table view:** Results displayed in columns (default)
- **Icons in header:**
  - 📊 = Switch to visualization (bar chart, line graph)
  - 📋 = Copy results
  - ⬇ = Export to CSV

---

#### Step 6: Switch to Visualization (For Time-Series Queries)

For queries with `bin()` (like Query A6), you can visualize as a chart.

**What You'll See:**

```
┌─────────────────────────────────────────────────────────────────┐
│  Results                                    [Table] [📊 Line]   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  blocks                                                         │
│  │                                                             │
│  │      ┌──┐                                                   │
│  │      │  │                                                   │
│  │  ┌───┤  │                         ┌──┐                      │
│  │  │   │  │    ┌──┐                 │  │                      │
│  │  │   │  │    │  │  ┌──┐           │  │                      │
│  │──┴───┴──┴────┴──┴──┴──┴───────────┴──┴──────────────        │
│  3:00  3:01  3:02  3:03  3:04  3:05  3:06  3:07  3:08          │
│                                                                 │
│  ▲ Spike at 3:01 - matches alarm trigger time                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**When to Use Visualization:**
- Time-binned queries (using `bin(1m)`, `bin(5m)`, etc.)
- Spotting trends and spikes
- Correlating multiple metrics
- Screenshots for incident reports

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why bother with visualizations when I can see the numbers in a table?*
> 
> **A (Explain Like I'm 10):** What's easier—looking at a list of 100 numbers to find the biggest one, or looking at a chart where one bar is obviously taller? Your brain processes pictures WAY faster than numbers. A spike in a chart screams "LOOK HERE!" A spike buried in a table of numbers is easy to miss, especially at 3 AM when you're tired.
> 
> **Evaluator Question:** *What visualization type would you use for different query types?*
> 
> **Model Answer:**
> - **Line chart:** Time-series data with `bin()` (error rate over time)
> - **Bar chart:** Categorical counts (ALLOW vs BLOCK, top IPs)
> - **Stacked area:** Multiple metrics over time (errors by category over time)
> - **Table:** Detailed drill-down, exact values needed, or non-numeric data

---

#### Step 7: Expand Log Entry Details

For queries that return raw log entries (like Query B2), click a row to see full details.

**What You'll See:**

```
┌─────────────────────────────────────────────────────────────────┐
│  @timestamp              @message                               │
├─────────────────────────────────────────────────────────────────┤
│  2024-01-15 03:07:22    ERROR: DB connection timeout to...     │
│  ├─────────────────────────────────────────────────────────────┤
│  │  ▼ Expanded View (click row to see)                         │
│  │                                                             │
│  │  @timestamp:  2024-01-15T03:07:22.451Z                      │
│  │  @message:    ERROR: DB connection timeout to               │
│  │               chewbacca-rds01.abc123.us-east-1.rds.amazo... │
│  │  @logStream:  i-0abc123def456/application.log               │
│  │  @log:        123456789012:/aws/ec2/chewbacca-rds-app       │
│  │                                                             │
│  │  [Copy @message]  [View in context]                         │
│  │                                                             │
│  └─────────────────────────────────────────────────────────────┘
│  2024-01-15 03:07:21    ERROR: Access denied for user 'admin'  │
│  2024-01-15 03:07:19    WARN: Retry attempt 3 of 5...          │
└─────────────────────────────────────────────────────────────────┘
```

**Key Features:**
- **Click any row** to expand and see full message (not truncated)
- **"View in context"** shows surrounding log entries (before/after)
- **Copy button** for sharing in Slack/tickets

---

#### Step 8: Save Query for Reuse

**What You'll See:**

```
┌─────────────────────────────────────────────────────────────────┐
│  Save query                                              [X]    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Query name:                                                    │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ WAF-A1-TrafficOverview                                    │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Folder (optional):                                             │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ incident-runbook                                          │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Log groups to include with this query:                         │
│  ☑ aws-waf-logs-chewbacca-webacl01                             │
│                                                                 │
│                                    [Cancel]  [Save]             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Actions:**
1. Click **Save** button above the query editor
2. Enter a descriptive name (use naming convention!)
3. Optionally create a folder to organize queries
4. Check the log group to save with the query
5. Click **Save**

**Recommended Naming Convention:**
```
<LogType>-<QueryID>-<Description>
```
Examples:
- `WAF-A1-TrafficOverview`
- `WAF-A4-BlockedRequests`
- `App-B1-ErrorRateOverTime`
- `App-B3-FailureClassification`

---

#### Step 9: Load a Saved Query

**What You'll See:**

```
┌─────────────────────────────────────────────────────────────────┐
│  Query editor:                                                  │
│                                                                 │
│  [Run query]  [Save]  [History ▼]  [▶ Saved queries]           │
│                                     └──────────────────────┐   │
│                                        │ incident-runbook  │   │
│                                        │ ├─ WAF-A1-Traffic │   │
│                                        │ ├─ WAF-A4-Blocked │   │
│                                        │ ├─ App-B1-ErrorR  │   │
│                                        │ └─ App-B3-Failure │   │
│                                        │ Recently used     │   │
│                                        │ └─ ...            │   │
│                                        └──────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

**Actions:**
1. Click **Saved queries** dropdown (or the ▶ arrow)
2. Navigate to your folder
3. Click the query name
4. Query and log group are automatically loaded
5. Click **Run query**

---

### Console vs. CLI: Quick Comparison

| Task | Console | CLI |
|------|---------|-----|
| **Run a query** | Click "Run query" | `aws logs start-query` + `get-query-results` |
| **See results** | Instant table/chart | Parse JSON output |
| **Adjust time range** | Click dropdown/slider | Calculate epoch timestamps |
| **Save queries** | Click Save button | Store in scripts/files |
| **Share with team** | Share screen or screenshot | Share script |
| **3 AM incident** | ✅ Preferred | Only if Console down |

---

### Console Workflow During an Incident

```
┌─────────────────────────────────────────────────────────────────┐
│  INCIDENT STARTS: Alarm fires at 3:07 AM                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Open Logs Insights                                          │
│     └─→ Bookmark: https://console.aws.amazon.com/cloudwatch/... │
│                                                                 │
│  2. Load saved query: WAF-A1-TrafficOverview                    │
│     └─→ Time range: 3:00 AM - 3:15 AM                          │
│     └─→ Result: ALLOW=247, BLOCK=1,853  ⚠️ HIGH BLOCKS         │
│                                                                 │
│  3. Load saved query: WAF-A6-BlockRateOverTime                  │
│     └─→ Switch to Line visualization                            │
│     └─→ Result: Spike at 3:04 AM, peaked at 3:07 AM            │
│                                                                 │
│  4. Load saved query: App-B1-ErrorRateOverTime                  │
│     └─→ Result: Errors flat until 3:06, then spiked            │
│                                                                 │
│  5. DECISION: Attack overwhelmed backend                        │
│     └─→ Block attacking IPs via WAF                             │
│     └─→ Verify recovery with App-B1                             │
│                                                                 │
│  6. Screenshot results for incident report                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

> [!success] **This is how SREs actually work during incidents.**
> Pre-saved queries + Console visualization = Fast diagnosis.

---

## PART 1: WAF Query Pack

These queries analyze your WAF logs to understand traffic patterns, attacks, and blocking behavior.

### Variables to Fill In (Your Environment)

```
WAF_LOG_GROUP="aws-waf-logs-<project>-webacl01"
APP_LOG_GROUP="/aws/ec2/<project>-rds-app"
TIME_RANGE="Last 15 minutes"  # Or match your incident window
```

---

### Query A1: "What's Happening Right Now?" (Traffic Overview)

**Purpose:** First query to run—gives you immediate situational awareness.

```sql
fields @timestamp, action
| stats count() as hits by action
| sort hits desc
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why is this the first query we run?*
> 
> **A (Explain Like I'm 10):** When you wake up to a fire alarm, your first question isn't "what color is the smoke?" It's "IS THERE ACTUALLY A FIRE?" This query answers the big picture first: Are requests flowing? Is WAF blocking a lot? Is everything being allowed? Once you know the situation, you can dig deeper.
> 
> **Evaluator Question:** *What would a healthy vs. unhealthy output from this query look like?*
> 
> **Model Answer:** 
> - **Healthy:** Mostly `ALLOW` with occasional `BLOCK` (normal scanner noise). Ratio like 95% ALLOW, 5% BLOCK.
> - **Unhealthy (under attack):** High `BLOCK` count, possibly exceeding `ALLOW`. Ratio like 40% ALLOW, 60% BLOCK.
> - **Unhealthy (misconfigured):** Almost 100% `BLOCK`—your WAF rules are too aggressive and blocking legitimate traffic.

**Expected Output:**
| action | hits |
|--------|------|
| ALLOW  | 1,234 |
| BLOCK  | 45    |

---

### Query A2: Top Client IPs

**Purpose:** Identify who is hitting your application the most—normal users or attackers?

```sql
fields @timestamp, httpRequest.clientIp as clientIp
| stats count() as hits by clientIp
| sort hits desc
| limit 25
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why do we care about client IPs? Aren't they all just "users"?*
> 
> **A (Explain Like I'm 10):** Imagine your lemonade stand gets 100 visitors. If 95 of them are different neighbors, that's normal! But if ONE person came back 95 times in 5 minutes, that's suspicious—are they casing the stand? Checking who visits most often helps you spot bots, scanners, or attackers who generate way more traffic than normal humans.
> 
> **Evaluator Question:** *How would you use this query output during an incident?*
> 
> **Model Answer:** Look for anomalies: (1) Single IP with disproportionate traffic (potential scanner or bot), (2) Multiple IPs from same /24 subnet (coordinated attack), (3) IPs you recognize as internal vs. external. During incidents, if one IP dominates BLOCK counts, consider adding it to a WAF IP block list. Cross-reference suspicious IPs with threat intelligence services.

---

### Query A3: Top Requested URIs

**Purpose:** Understand what paths attackers or users are targeting.

```sql
fields @timestamp, httpRequest.uri as uri
| stats count() as hits by uri
| sort hits desc
| limit 25
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why does it matter WHAT path they're requesting?*
> 
> **A (Explain Like I'm 10):** If someone keeps knocking on your front door, that's normal. If they keep trying the back window, the basement door, and checking if the garage is unlocked—that's a burglar! Attackers probe specific paths: `/admin`, `/wp-login.php`, `/.env`. Normal users hit your actual application routes. The URI pattern tells you "curious user" vs. "active scanning."
> 
> **Evaluator Question:** *What URI patterns indicate reconnaissance or attack activity?*
> 
> **Model Answer:** Red flags include:
> - CMS probes: `/wp-login.php`, `/wp-admin`, `/administrator`, `/phpmyadmin`
> - Config file hunting: `/.env`, `/.git/config`, `/config.php`, `/web.config`
> - Injection attempts: URIs with `'`, `"`, `<script>`, `UNION SELECT`
> - Path traversal: `/../../../etc/passwd`
> - API enumeration: Sequential IDs like `/api/user/1`, `/api/user/2`, etc.

---

### Query A4: Blocked Requests Only

**Purpose:** Focus specifically on what WAF is stopping—this is your threat landscape.

```sql
fields @timestamp, action, httpRequest.clientIp as clientIp, httpRequest.uri as uri
| filter action = "BLOCK"
| stats count() as blocks by clientIp, uri
| sort blocks desc
| limit 25
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** If requests are already blocked, why do we care about them?*
> 
> **A (Explain Like I'm 10):** Your guard dog stopped a burglar at the fence. Great! But wouldn't you want to know: Was it the same burglar every night? Were they trying the same window? Are there patterns that suggest a bigger plan? Blocked requests tell you what threats are actively targeting you—even if they failed. That intelligence helps you prepare for smarter attacks.
> 
> **Evaluator Question:** *How would you escalate findings from this query?*
> 
> **Model Answer:** If you see: (1) Same IP repeatedly blocked → add to permanent block list and investigate source, (2) Same URI pattern blocked across many IPs → botnet or coordinated scan, consider adding rate limiting, (3) Blocks for paths that shouldn't exist but do → possible application vulnerability being probed, audit your code. Document patterns for threat intelligence sharing with your security team.

---

### Query A5: Which WAF Rule Is Blocking?

**Purpose:** Identify which specific WAF rule is doing the work—validates your rule configuration.

```sql
fields @timestamp, action, terminatingRuleId, terminatingRuleType
| filter action = "BLOCK"
| stats count() as blocks by terminatingRuleId, terminatingRuleType
| sort blocks desc
| limit 25
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why do we need to know which RULE blocked the request?*
> 
> **A (Explain Like I'm 10):** Imagine you have 5 security guards, and you hear "we stopped 100 intruders today!" Wouldn't you want to know which guard caught most of them? If Guard #3 caught 95 people, maybe the others aren't positioned right—or maybe Guard #3 is too aggressive and stopping delivery drivers too! Knowing which rule blocks helps you tune your security.
> 
> **Evaluator Question:** *What does the distribution of blocks across rules tell you?*
> 
> **Model Answer:** 
> - **Most blocks from AWSManagedRulesCommonRuleSet:** Normal, expected baseline protection
> - **Many blocks from SQLi/XSS rules:** Targeted injection attempts, investigate the sources
> - **All blocks from rate-based rule:** DDoS or aggressive scraping, may need to adjust thresholds
> - **Custom rule catching everything:** Review rule logic—it may be overly broad
> - **One rule with zero blocks:** Rule may be misconfigured or redundant, consider removing

---

### Query A6: Rate of Blocks Over Time

**Purpose:** Visualize when blocks spiked—correlate with incident timeline.

WARNING: The following query given in the lab was INCORRECT and should be changed...
```sql
fields @timestamp, action
| filter action = "BLOCK"
| stats count() as blocks by bin(1m)
| sort bin(1m) asc
```

...to this:
```sql
fields @timestamp, action
| filter action = "BLOCK"
| stats count() as blocks by bin(1m) as minute
| sort minute asc
```
The `bin(1m)` function creates a time bucket, but you can't reference it directly in `sort` with parentheses. You need to either:

1. **Give it an alias** with `as minute` — then sort by the alias
2. **Skip the sort** — `stats ... by bin()` results are already chronological

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why do we need to see blocks over TIME instead of just totals?*
> 
> **A (Explain Like I'm 10):** If I told you "100 people tried to break into houses this month," that's scary. But if I told you "95 of them tried on October 31st"—oh, that's just Halloween pranksters! Time patterns reveal WHEN something happened, which helps you find the cause. A spike at 3:07 AM that matches when your alarm fired? Now you've connected the dots.
> 
> **Evaluator Question:** *How would you correlate this query's output with your CloudWatch alarm?*
> 
> **Model Answer:** Overlay this query's timeline with your alarm's state change timestamp. If blocks spiked 2 minutes BEFORE the alarm → attack may have caused backend failure. If blocks spiked AFTER the alarm → unrelated or attackers noticed your service was down. If blocks are flat but app errors spiked → it's not an attack, it's an internal failure (creds, network, DB).

---

### Query A7: Suspicious Scanner Detection

**Purpose:** Catch automated scanners probing for common vulnerabilities.

```sql
fields @timestamp, httpRequest.clientIp as clientIp, httpRequest.uri as uri
| filter uri =~ /wp-login|xmlrpc|\.env|admin|phpmyadmin|\.git|login/
| stats count() as hits by clientIp, uri
| sort hits desc
| limit 50
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why are these specific paths (wp-login, .env, etc.) suspicious?*
> 
> **A (Explain Like I'm 10):** These paths are like a burglar's checklist: "First, check if they left a key under the mat (.env file). Then try the WordPress door (wp-login). Then look for the secret tunnel (.git folder)." Automated scanners try EVERY common vulnerability path on EVERY website. If someone hits `/wp-login.php` on your Flask app, they're not a real user—they're a robot running a script.
> 
> **Evaluator Question:** *What's the difference between a scanner and a targeted attack?*
> 
> **Model Answer:** 
> - **Scanners:** Hit generic paths across thousands of IPs, looking for any vulnerable site. Low effort, high volume. Usually automated tools like Nikto, Nmap, or botnets.
> - **Targeted attacks:** Know YOUR specific application, probe YOUR actual endpoints, may have done reconnaissance first. Lower volume, higher sophistication, more dangerous.
> 
> Both matter, but scanners are "noise" while targeted attacks are "signal." This query catches the noise; Query A4 + A5 help identify targeted activity.

---

### Query A8: Geographic Distribution (If Available)

**Purpose:** See where traffic originates—useful for geo-blocking decisions.

```sql
fields @timestamp, httpRequest.country as country
| stats count() as hits by country
| sort hits desc
| limit 25
```

> [!note] **Note**
> This query only works if your WAF logs include `httpRequest.country`. Not all configurations capture this field.

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why does the country of origin matter for security?*
> 
> **A (Explain Like I'm 10):** If your lemonade stand only serves your neighborhood, but suddenly you're getting 1,000 visitors from Antarctica, something's weird! Geographic data helps you spot: (1) Traffic from countries where you have no customers, (2) Attack infrastructure often hosted in specific regions, (3) Compliance requirements that restrict certain countries.
> 
> **Evaluator Question:** *When is geo-blocking appropriate, and when is it problematic?*
> 
> **Model Answer:** Appropriate: Regulatory compliance (GDPR data residency), business decision (no customers in region X), active attack from specific country. Problematic: Blocking legitimate customers, VPN users appear from unexpected countries, attackers use proxies in "trusted" countries. Geo-data is a hint, not proof—always correlate with other signals before blocking entire countries.

---

## PART 2: Application Query Pack

These queries analyze your application logs to diagnose backend issues.

> [!warning] **PREREQUISITE**
> Your application must log meaningful strings like `ERROR`, `DB`, `timeout`, `refused`, etc. If your app logs only "something went wrong," these queries won't help. **Structured logging is an investment that pays off during incidents.**

---

### Query B1: Error Rate Over Time

**Purpose:** Visualize when errors spiked—this should align with your alarm window.

WARNING: The following query given in the lab was INCORRECT and should be changed...
```sql
fields @timestamp, @message
| filter @message like /ERROR|Exception|Traceback|DB|timeout|refused/i
| stats count() as errors by bin(1m)
| sort bin(1m) asc
```

...to this:
```sql
fields @timestamp, @message
| filter @message like /ERROR|Exception|Traceback|DB|timeout|refused|error|Error/
| stats count() as errors by bin(1m) as minute
| sort minute asc
```
CloudWatch Logs Insights **doesn't support the `/i` flag** for case-insensitive regex. Same fix applies to **B2, B3, and A7** if they have `/i` flags — just remove them.

- ✅ `/pattern/` — supported
- ❌ `/pattern/i` — **NOT supported** (no flags)

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why do we bin errors by 1-minute intervals?*
> 
> **A (Explain Like I'm 10):** If you just count "100 errors today," you don't know if it was a gradual trickle or a sudden explosion. Binning by minute is like a heart monitor—you see the exact moment things went bad. "Errors jumped from 2 to 50 at 3:07 AM" is actionable. "100 errors today" is just sad.
> 
> **Evaluator Question:** *How does this query relate to your CloudWatch alarm configuration?*
> 
> **Model Answer:** Your alarm is configured with a period (e.g., 5 minutes) and threshold (e.g., ≥3 errors). This query shows the raw data feeding that alarm. If the query shows 50 errors/minute and your alarm has threshold=3, the alarm definitely should have fired. If query shows 2 errors/minute, maybe the alarm is misconfigured or you're looking at the wrong time window.

---

### Query B2: Recent DB Failures (Triage View)

**Purpose:** See the actual error messages—this is your diagnostic goldmine.

```sql
fields @timestamp, @message
| filter @message like /DB|mysql|timeout|refused|Access denied|could not connect/
| sort @timestamp desc
| limit 50
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why do we sort by timestamp descending (newest first)?*
> 
> **A (Explain Like I'm 10):** When the doctor asks "when did the pain start?", you don't describe your childhood first! You start with "it hurts NOW" then work backward. Newest errors show the current state; older errors might already be resolved. Start with NOW, then trace back to find the first occurrence (that's when the problem actually started).
> 
> **Evaluator Question:** *What information should you extract from these error messages?*
> 
> **Model Answer:** Look for: (1) Error TYPE: timeout vs. access denied vs. connection refused—each has different causes, (2) Timestamp pattern: continuous errors or intermittent?, (3) Specific details: endpoint names, port numbers, error codes, (4) Stack traces: which code path failed?, (5) Correlation IDs: if your app uses request IDs, find the full request journey.

---

### Query B3: Failure Classification ("Is it Creds or Network?")

**Purpose:** Automatically categorize errors to accelerate root cause analysis.

WARNING: the following code threw an error: Unrecognized function name: case ([224,430]). **CloudWatch Logs Insights doesn't have a `case()` function**. The original source document had pseudocode that doesn't actually work.

```sql
fields @timestamp, @message
| filter @message like /Access denied|authentication failed|timeout|refused|no route|could not connect/
| stats count() as hits by
  case(
    @message like /Access denied|authentication failed/i, "Creds/Auth",
    @message like /timeout|no route/i, "Network/Route",
    @message like /refused/i, "Port/SG/ServiceRefused",
    1=1, "Other"
  ) as failure_category
| sort hits desc
```

CloudWatch Logs Insights is **not full SQL**. It doesn't support:

- ❌ `case()` / `case when`
- ❌ `if()` / `iff()`
- ❌ Conditional logic inside `stats`

## Workaround: Run Separate Queries

## Switch Log Groups First

You're likely on `aws-waf-logs-chewbacca-webacl01` (WAF logs) from above.

For B3 queries, switch to your **app log group**.

Instead of one query that classifies everything, run **3-4 targeted queries**:
### B3a: Credential/Auth Failures

```sql
fields @timestamp, @message
| filter @message like /Access denied|authentication failed/
| stats count() as hits
```

### B3b: Network/Route Failures


```sql
fields @timestamp, @message
| filter @message like /timeout|no route/
| stats count() as hits
```

### B3c: Port/Service Refused


```sql
fields @timestamp, @message
| filter @message like /refused|could not connect/
| stats count() as hits
```

### B3d: All Failures (Overview)


```sql
fields @timestamp, @message
| filter @message like /Access denied|authentication failed|timeout|refused|no route|could not connect/
| stats count() as total_failures
```

NOTE: Since B2 showed 0 DB errors, you'll likely see 0s across these too — that's fine. You're validating that the queries **work**, not that you have an active incident.

## How to Use During Incidents

|Query|Result|Interpretation|
|---|---|---|
|B3a|47 hits|→ Check Secrets Manager|
|B3b|3 hits|→ Probably not network|
|B3c|2 hits|→ Probably not SG/port|
|**Winner**|B3a (Creds)|Focus on credentials first|

## Why This Still Works

The goal of B3 was to **quickly classify the failure type**. Running 3 quick queries takes ~10 seconds and gives you the same answer: "Which category has the most hits? That's your root cause direction."

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why do we classify failures into categories?*
> 
> **A (Explain Like I'm 10):** When your car won't start, the mechanic asks: "Does it make a clicking sound (battery), a grinding sound (starter), or no sound at all (ignition)?" Each sound points to a different fix. Error messages are the same—"Access denied" means wrong password, "timeout" means network problem, "refused" means the service isn't listening. Classification tells you WHERE to look.
> 
> **Evaluator Question:** *Map each failure category to a likely root cause and fix.*
> 
> **Model Answer:**
> 
> | Category | Likely Root Cause | Recovery Action |
> |----------|-------------------|-----------------|
> | Creds/Auth | Secrets Manager password doesn't match RDS | Update Secrets Manager OR reset RDS password |
> | Network/Route | Security group blocking, route table missing | Check SG ingress rules, verify VPC routing |
> | Port/SG/ServiceRefused | RDS not running, wrong port, SG denies port | Start RDS, verify endpoint and port 3306 |
> | Other | Application bug, resource exhaustion | Check app code, memory, disk space |

---

### Query B4: Structured JSON Log Analysis

**Purpose:** If your app logs JSON, extract specific fields for analysis. B4 **only works if your app logs JSON**:

> [!note] **Prerequisite**
> Your application must emit logs in JSON format like:
> ```json
> {"level":"ERROR","event":"db_connect_fail","reason":"timeout","timestamp":"2024-01-15T03:07:22Z"}
> ```

If your Flask app logs plain text like: ``` ERROR: DB connection timeout to chewbacca-rds01...

```sql
fields @timestamp, level, event, reason
| filter level = "ERROR"
| stats count() as n by event, reason
| sort n desc
```
...Then B4 will return **nothing useful** — there are no structured fields to extract.

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why is JSON logging better than plain text?*
> 
> **A (Explain Like I'm 10):** Imagine organizing your toys. Plain text is like dumping everything in one big box—finding your red LEGO piece means digging through everything. JSON is like having labeled drawers: "LEGOs here, action figures there, cars over there." When you need to find "all red things," you just look in the "color: red" section. JSON lets you search by any field instantly.
> 
> **Evaluator Question:** *What fields should production applications include in structured logs?*
> 
> **Model Answer:** Essential fields: (1) `timestamp` (ISO 8601 format), (2) `level` (DEBUG, INFO, WARN, ERROR), (3) `event` or `message` (what happened), (4) `request_id` or `correlation_id` (trace across services), (5) `user_id` or `session_id` (who was affected), (6) `component` (which service/module), (7) `duration_ms` (for performance), (8) `error_code` and `error_message` (for failures). Avoid logging PII, passwords, or tokens!

---

## PART 3: Correlation Workflow (Enterprise-Style Runbook)

This section teaches you how to CONNECT THE DOTS between WAF and app failures during an incident.

> [!tip] **THE CORRELATION PRINCIPLE**
> A symptom (alarm firing) can have multiple causes (attack, creds, network). Your job is to systematically eliminate possibilities until you find the true root cause.

---

### Step 1: Confirm Signal Timing

**Goal:** Establish the incident timeline.

1. **Check CloudWatch alarm state change time** (when did it fire?)
2. **Run App Query B1** (error rate over time)
3. **Compare:** Does the error spike align with the alarm?

```sql
-- Run this first to see when errors started
fields @timestamp, @message
| filter @message like /ERROR|DB|timeout|refused|Access denied/i
| stats count() as errors by bin(1m)
| sort bin(1m) asc
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why is establishing the timeline the FIRST step?*
> 
> **A (Explain Like I'm 10):** If someone says "the window was broken," your first question is "WHEN?" If it was broken yesterday but the alarm just went off, maybe the alarm is delayed or broken. If it was broken 2 minutes ago, the intruder might still be inside! Knowing WHEN helps you understand IF the alarm and the problem are related, and HOW URGENT your response needs to be.
> 
> **Evaluator Question:** *What if the alarm fired but query B1 shows no error spike?*
> 
> **Model Answer:** Possible explanations: (1) Wrong log group—you're querying the wrong environment, (2) Wrong time window—adjust to match alarm time, (3) Alarm misconfiguration—threshold too sensitive, (4) Logging gap—app crashed before it could log, (5) Metric vs. log mismatch—alarm uses a metric that doesn't rely on these logs. Investigate each possibility systematically.

---

### Step 2: Decide Attack vs. Backend Failure

**Goal:** Determine if this is external pressure or internal failure.

**Run WAF Query A1 + A6:**

```sql
-- A1: What's happening now?
fields @timestamp, action
| stats count() as hits by action
| sort hits desc
```

```sql
-- A6: Block rate over time
fields @timestamp, action
| filter action = "BLOCK"
| stats count() as blocks by bin(1m)
| sort bin(1m) asc
```

**Decision Matrix:**

| WAF Blocks | App Errors | Likely Cause |
|------------|------------|--------------|
| ⬆️ Spiked  | ⬆️ Spiked  | Attack overwhelmed backend OR attack coincided with unrelated failure |
| ⬆️ Spiked  | ➡️ Flat    | Attack blocked successfully, no backend impact |
| ➡️ Flat    | ⬆️ Spiked  | **Internal failure** (creds, network, DB)—not an attack |
| ➡️ Flat    | ➡️ Flat    | False alarm OR issue already resolved |

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why is it important to distinguish attack from internal failure?*
> 
> **A (Explain Like I'm 10):** If your house alarm goes off, you respond differently if it's a burglar (call police, hide) vs. if your cat knocked over a lamp (turn off alarm, go back to sleep). Attacks need security response (block IPs, notify security team). Internal failures need operational response (fix config, restart service). Wrong response wastes time and might make things worse.
> 
> **Evaluator Question:** *How would your incident response differ for attack vs. internal failure?*
> 
> **Model Answer:**
> 
> **Attack Response:**
> - Identify and block attacking IPs
> - Enable additional WAF rules
> - Consider rate limiting
> - Notify security team
> - Preserve evidence for forensics
> 
> **Internal Failure Response:**
> - Check configuration (secrets, parameters)
> - Verify network path (security groups, routes)
> - Check service health (RDS status)
> - Restore from known-good config
> - Focus on service recovery, not attribution

---

### Step 3: Backend Failure Deep Dive

**Goal:** If WAF is quiet but app errors spiked, diagnose the backend.

**Run App Query B2 and B3:**

```sql
-- B2: Recent failures (raw messages)
fields @timestamp, @message
| filter @message like /DB|mysql|timeout|refused|Access denied|could not connect/i
| sort @timestamp desc
| limit 50
```

```sql
-- B3: Classify the failures
fields @timestamp, @message
| filter @message like /Access denied|authentication failed|timeout|refused|no route|could not connect/i
| stats count() as hits by
  case(
    @message like /Access denied|authentication failed/i, "Creds/Auth",
    @message like /timeout|no route/i, "Network/Route",
    @message like /refused/i, "Port/SG/ServiceRefused",
    1=1, "Other"
  ) as failure_category
| sort hits desc
```

**Then retrieve known-good values:**

```bash
# Parameter Store values
aws ssm get-parameters \
  --names /lab/db/endpoint /lab/db/port /lab/db/name \
  --with-decryption

# Secrets Manager values
aws secretsmanager get-secret-value \
  --secret-id <prefix>/rds/mysql \
  --query "SecretString" --output text
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why do we retrieve Parameter Store and Secrets Manager values during diagnosis?*
> 
> **A (Explain Like I'm 10):** Imagine you're locked out of your house. First you check: "Did I lose my key?" Then: "Did someone change the locks?" Parameter Store has the address (endpoint, port). Secrets Manager has the key (password). If the key doesn't match the lock anymore (secrets drift), you need to either get the right key or change the lock. You can't fix it without knowing what SHOULD work.
> 
> **Evaluator Question:** *What is "secrets drift" and how does it happen?*
> 
> **Model Answer:** Secrets drift occurs when the credential stored in Secrets Manager no longer matches the actual credential on the target system (RDS). Causes: (1) Manual password change in RDS console without updating Secrets Manager, (2) Secrets rotation that updated Secrets Manager but failed to update RDS, (3) Restore from backup with old password, (4) Multiple environments sharing secrets incorrectly. Prevention: Use Secrets Manager automatic rotation, implement drift detection, never manually change passwords without updating all references.

---

### Step 4: Verify Recovery

**Goal:** Confirm the incident is resolved, not just "looks better."

**Verification Checklist:**

| Check | Command/Query | Expected Result |
|-------|---------------|-----------------|
| App errors baseline | Query B1 | Errors return to normal (< 3/min) |
| WAF blocks stable | Query A6 | No unusual spikes |
| Alarm state | `aws cloudwatch describe-alarms --alarm-name-prefix <name>` | State = OK |
| Application works | `curl https://app.chewbacca-growl.com/list` | Returns data, HTTP 200 |

```bash
# Verify alarm returned to OK
aws cloudwatch describe-alarms \
  --alarm-name-prefix chewbacca \
  --query "MetricAlarms[].{Name:AlarmName,State:StateValue}"

# Verify application responds
curl -s -o /dev/null -w "%{http_code}" https://app.chewbacca-growl.com/list
# Expected: 200
```

> [!info] **SOCRATIC Q&A**
> 
> ***Q:** Why isn't "the alarm went away" sufficient proof of recovery?*
> 
> **A (Explain Like I'm 10):** If your smoke alarm stops beeping, is the fire out? Maybe! Or maybe the batteries died. Or maybe the fire is in a different room now. "Alarm stopped" only means the specific sensor stopped detecting. You need to actually check: Is the fire out? Is there smoke? Is the house okay? Multiple verification points prove recovery, not just alarm silence.
> 
> **Evaluator Question:** *What could cause a false "recovery" where the alarm clears but the problem persists?*
> 
> **Model Answer:** (1) Alarm period ended without new data points (evaluation gap), (2) Application crashed completely—no errors because nothing is running, (3) Load balancer health check failing, routing traffic away from broken instance (looks healthy because no traffic = no errors), (4) Caching—CloudFront serving cached responses, hiding backend failure, (5) Intermittent issue—problem comes and goes, currently in "good" phase. Always verify with actual application request, not just metrics.

---

## PART 4: Implementation Steps

### Step 1: Create the Log Groups (If Not Already Existing)

```bash
# WAF log group (should exist from Bonus E)
aws logs describe-log-groups \
  --log-group-name-prefix aws-waf-logs-chewbacca

# App log group (should exist from core Lab 1C)
aws logs describe-log-groups \
  --log-group-name-prefix /aws/ec2/chewbacca
```

---

### Step 2: Save Queries to CloudWatch Insights

You can save queries for reuse directly in the CloudWatch console:

1. Navigate to **CloudWatch → Logs → Logs Insights**
2. Select your log group
3. Enter a query
4. Click **Save** → **Save query**
5. Name it descriptively: `WAF-A1-TrafficOverview`, `App-B3-FailureClassification`, etc.

> [!tip] **Pro Tip**
> Organize saved queries with a naming convention:
> - `WAF-A1-TrafficOverview`
> - `WAF-A4-BlockedRequests`
> - `App-B1-ErrorRate`
> - `App-B3-FailureClassification`

---

### Step 3: Create a Runbook Document

Create a Markdown document (or Wiki page) that your team references during incidents:

```markdown
# Incident Runbook: Application Errors

## Step 1: Confirm Timeline
- [ ] Check alarm trigger time
- [ ] Run App-B1 query
- [ ] Document: Errors started at ________

## Step 2: Attack or Internal?
- [ ] Run WAF-A1 query
- [ ] Run WAF-A6 query
- [ ] Decision: ATTACK / INTERNAL

## Step 3: If Internal...
- [ ] Run App-B2 for raw errors
- [ ] Run App-B3 for classification
- [ ] Retrieve Parameter Store values
- [ ] Retrieve Secrets Manager values
- [ ] Identify root cause: ________

## Step 4: Apply Fix
- [ ] Document fix applied: ________
- [ ] Time fix applied: ________

## Step 5: Verify Recovery
- [ ] App-B1 shows errors at baseline
- [ ] Alarm state = OK
- [ ] curl returns HTTP 200
- [ ] Time service restored: ________
```

---

### Step 4: Test the Query Pack

Run each query against your log groups to verify they work:

```bash
# Test WAF query A1
aws logs start-query \
  --log-group-name aws-waf-logs-chewbacca-webacl01 \
  --start-time $(date -d '15 minutes ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, action | stats count() as hits by action | sort hits desc'

# Get query results (use query ID from above)
aws logs get-query-results --query-id <QUERY_ID>
```

---

## Verification Commands

> [!success] **VERIFICATION: Query Pack Functionality**
> 
> ```bash
> # 1. Verify WAF log group exists and has data
> aws logs describe-log-groups \
>   --log-group-name-prefix aws-waf-logs-chewbacca
> 
> aws logs filter-log-events \
>   --log-group-name aws-waf-logs-chewbacca-webacl01 \
>   --limit 5
> 
> # 2. Verify App log group exists and has data
> aws logs describe-log-groups \
>   --log-group-name-prefix /aws/ec2/chewbacca
> 
> aws logs filter-log-events \
>   --log-group-name /aws/ec2/chewbacca-rds-app \
>   --limit 5
> 
> # 3. Run a sample Logs Insights query
> QUERY_ID=$(aws logs start-query \
>   --log-group-name aws-waf-logs-chewbacca-webacl01 \
>   --start-time $(date -d '1 hour ago' +%s) \
>   --end-time $(date +%s) \
>   --query-string 'stats count() by action' \
>   --query 'queryId' --output text)
> 
> sleep 5
> 
> aws logs get-query-results --query-id $QUERY_ID
> # Expected: Results showing ALLOW/BLOCK counts
> ```

---

## Deliverables Checklist

| Requirement | Evidence |
|-------------|----------|
| WAF queries work (A1-A7) | Screenshots of query results |
| App queries work (B1-B3) | Screenshots of query results |
| Correlation workflow documented | Runbook Markdown file |
| Queries saved in CloudWatch | Screenshot of saved queries list |
| Can distinguish attack vs. internal failure | Written explanation with example output |

---

## Reflection Questions

### A) Why are pre-written queries valuable during incidents?

**Model Answer:** They eliminate cognitive load during high-stress situations. Engineers don't have to remember query syntax or what fields to examine—they just run the pre-built queries. This reduces Mean Time To Diagnose (MTTD) and ensures consistent analysis across incidents and team members.

### B) What's the difference between logs in CloudWatch Logs vs. S3?

**Model Answer:** CloudWatch Logs: Real-time, indexed, searchable with Logs Insights, retention costs more at scale, ideal for operational queries. S3: Batch storage, much cheaper at scale, requires Athena or external tools to query, ideal for long-term archive and compliance. WAF and app logs can go to CloudWatch for real-time analysis; ALB access logs default to S3.

### C) How does failure classification (Query B3) accelerate incident response?

**Model Answer:** Instead of reading hundreds of error messages, classification groups them into actionable categories. "78% of errors are Creds/Auth" immediately tells you: check Secrets Manager, don't waste time on network debugging. It's the difference between "something is broken" and "the password is wrong."

### D) Why is "alarm returned to OK" insufficient verification of recovery?

**Model Answer:** Alarms measure specific metrics with specific thresholds and periods. They can clear due to: evaluation gaps, application crash (no data = no errors), load balancer routing away from broken instances, or intermittent issues. True recovery requires: alarm OK + application responds + errors at baseline + no new symptoms.

---

## What This Lab Proves About You

*If you complete this lab, you can confidently say:*

> **"I can build and operate incident response tooling using CloudWatch Logs Insights, and I understand how to correlate signals across security and application logs to diagnose production issues."**

*This is SRE/DevOps engineer capability. You're not just deploying infrastructure—you're building the observability layer that keeps it running.*

---

## Quick Reference: All Queries

### WAF Queries
| ID | Purpose | Key Filter |
|----|---------|------------|
| A1 | Traffic overview | `stats count() by action` |
| A2 | Top client IPs | `stats count() by clientIp` |
| A3 | Top URIs | `stats count() by uri` |
| A4 | Blocked requests | `filter action = "BLOCK"` |
| A5 | Blocking rules | `stats count() by terminatingRuleId` |
| A6 | Block rate over time | `stats count() by bin(1m)` |
| A7 | Suspicious scanners | `filter uri =~ /wp-login\|.env\|admin/` |
| A8 | Geographic distribution | `stats count() by country` |

### App Queries
| ID | Purpose | Key Filter |
|----|---------|------------|
| B1 | Error rate over time | `filter @message like /ERROR/` + `bin(1m)` |
| B2 | Recent DB failures | `filter @message like /DB\|mysql\|timeout/` |
| B3 | Failure classification | `case()` statement categorizing errors |
| B4 | JSON log analysis | `filter level = "ERROR"` |

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
