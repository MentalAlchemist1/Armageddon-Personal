# Lab 1C — Bonus G: Bedrock Auto-IR Pipeline

## SEIR FOUNDATIONS — Socratic Q&A Guide

**What You're Building:** An event-driven pipeline where a CloudWatch Alarm automatically triggers a Lambda function that collects evidence from your entire stack, sends it to Amazon Bedrock (an AI model), and produces a professional incident report — stored in S3 and delivered via SNS.

**The Real-World Pattern:** Alarm → Evidence Collection → LLM Summarization → Report Artifact → Notify

**Why This Matters:** This is what real SRE teams at companies like Netflix, Uber, and AWS themselves are moving toward. You're not just playing with AI — you're building an automated incident response pipeline.

---

## Big Picture: How the Pieces Fit Together

```
CloudWatch Alarm (ALARM state)
        │
        ▼
   SNS Topic (you already have this from core lab)
        │
        ▼
   Lambda "IncidentReporter" (NEW — the brain)
        │
        ├──→ CloudWatch Logs Insights (queries app + WAF logs)
        ├──→ SSM Parameter Store (pulls config)
        ├──→ Secrets Manager (pulls DB metadata — NOT passwords)
        ├──→ Bedrock Runtime (AI generates the report)
        ├──→ S3 Bucket (stores JSON evidence + Markdown report)
        └──→ SNS (notifies "Report Ready" with S3 link)
```

> **SOCRATIC Q&A — The Big "Why"**
>
> **Q:** Why would a company want an AI to write incident reports instead of a human?
>
> **A (ELI10):** Imagine your house fire alarm goes off at 3 AM. You're half asleep, panicking, trying to figure out what's burning. Now imagine a robot assistant that — the moment the alarm rings — instantly checks every room, writes down what it sees, and hands you a report saying "smoke is coming from the kitchen toaster." You're still the one who decides what to do, but the robot did the boring evidence-gathering so you can focus on *fixing the problem* instead of *finding the problem.*
>
> **Evaluator Question:** *"What's the difference between automated evidence collection and automated remediation? Why would a company trust AI for one but not the other?"*
>
> **Model Answer:** Automated evidence collection is *read-only* — it observes and reports. Automated remediation *takes action* (restarting servers, rolling back deploys). Companies trust AI for collection because the worst case is a bad report you throw away. The worst case for bad remediation is the AI making things *worse*. The principle is: **AI summarizes. Humans interpret and act.**

---

## Prerequisites Checklist

Before starting Bonus-G, confirm you have these from your core lab and previous bonuses:

- [ ] **SNS Topic** (`chewbacca_sns_topic01`) — already deployed from core lab
- [ ] **CloudWatch Alarm** — fires on `DBConnectionErrors >= 3` per 5 min
- [ ] **CloudWatch Log Group** — app logs at `/aws/ec2/${project_name}-rds-app`
- [ ] **Parameter Store entries** — at `/lab/db/*`
- [ ] **Secrets Manager secret** — at `${project_name}/rds/mysql`
- [ ] **WAF Log Group** (from Bonus E) — at `aws-waf-logs-${project_name}-webacl01`
- [ ] **Bedrock model access** — enabled in your AWS region (check in the Bedrock console)

---

## Phase 1: Enable Bedrock Model Access

### Step 1.1 — Choose Your Model

The instructor intentionally left the model choice open — `BEDROCK_MODEL_ID = "REPLACE_ME"` in the Terraform skeleton. Model selection is part of the exercise.

**Our choice: `anthropic.claude-3-5-haiku-20241022` (Claude 3.5 Haiku)**

Why Claude 3.5 Haiku over other options in the Bedrock catalog:

| Model | Why It Does / Doesn't Fit |
|-------|--------------------------|
| **Claude 3.5 Haiku** ✅ | Fast, cost-efficient, excellent at structured summarization and multi-constraint prompt following. Right-sized for "fill this template from this evidence" tasks. |
| Amazon Nova Micro | Would work, but weaker at following complex prompts with multiple rules (evidence-only, cite sources, confidence levels). |
| Amazon Nova Lite/Pro | More capable than Micro but still not as strong as Claude for structured report generation. |
| Claude 3.5 Sonnet / Opus | Overkill — more expensive, and Haiku's quality is sufficient for this task. Cost-conscious model selection matters. |
| Amazon Titan models | These are embeddings, image generation, and reranking — **not text generation**. They won't work for this lab. |
| Nova 2 Sonic / Nova 2 Lite | Speech-to-speech and image/video models — wrong modality entirely. |

> **SOCRATIC Q&A — Why Model Selection Matters**
>
> **Q:** Why not just pick the most powerful (and expensive) model available?
>
> **A (ELI10):** Imagine you need to hammer a nail. You *could* rent a giant construction crane to do it — it would definitely work! But it costs $10,000/hour and takes an hour to set up. Or you could use a $15 hammer that does the job in 2 seconds. Choosing the right model for the task is the same principle. Claude 3.5 Haiku is the hammer — fast, cheap, and perfect for structured summarization. Using Opus for this would be like renting the crane.
>
> **Evaluator Question:** *"Why did you choose Claude 3.5 Haiku over a larger model or a cheaper Amazon model for your incident report pipeline?"*
>
> **Model Answer:** The task is structured summarization — converting JSON evidence into a templated Markdown report with specific constraints. Haiku excels at instruction-following and structured output at a fraction of Opus/Sonnet's cost. A larger model adds latency and cost without meaningfully improving report quality for this use case. Amazon Nova models were considered but are weaker at following multi-constraint prompts (evidence-only, cite sources, include confidence levels). The decision demonstrates **cost-conscious architectural thinking** — matching model capability to task complexity.

### Step 1.2 — Submit Anthropic Use Case Details (One-Time Setup)

**Important:** AWS has retired the old "Model access" page. Serverless models are now auto-enabled on first invocation. However, **Anthropic models require a one-time use case submission** before first use.

1. Navigate to **Bedrock console → Model catalog** (left sidebar under Discover)
2. Filter by **Providers = Anthropic**
3. You'll see a **yellow banner** at the top: *"Anthropic requires first-time customers to submit use case details..."*
4. Click **"Submit use case details"** and paste your use case (500 character max)
5. Approval is typically instant for educational use cases

> **SOCRATIC Q&A — Why Anthropic Requires a Use Case**
>
> **Q:** Amazon models just work. Why does Anthropic make me submit a use case first?
>
> **A (ELI10):** Think of Bedrock like a mall food court. AWS owns the building, but each restaurant (Anthropic, Meta, Amazon) has their own rules. Some restaurants are open to everyone who walks in. Others — like a fancy sushi bar — want to know who you are and what you're ordering before they seat you. Anthropic's use case requirement is their way of knowing what their models are being used for. It's a responsible AI governance practice, not a barrier.
>
> **Evaluator Question:** *"Why do some Bedrock model providers require use case submissions while others don't? What does this tell you about the shared responsibility model in managed AI services?"*
>
> **Model Answer:** Each model provider sets their own access policies on top of AWS's platform. Anthropic's use case requirement reflects their responsible AI practices — they want visibility into how their models are used. This is an extension of the **shared responsibility model**: AWS secures the infrastructure (networking, billing, IAM), but model providers retain governance over their models' usage policies. Account administrators can further restrict access via IAM policies and Service Control Policies (SCPs). It's three layers: AWS platform → model provider policy → customer IAM.

### Step 1.3 — Verify Model Access in the Playground

1. Navigate to **Bedrock console → Playground** (left sidebar under Test)
2. Select **Claude 3.5 Haiku** from the model dropdown
3. Send a test message: `"Hello, respond with one sentence."`
4. If you get a response, you're good. If you get an access error, the use case submission may still be processing.

**Your Model ID for Terraform:** `anthropic.claude-3-5-haiku-20241022-v1:0`

⚠️ **Important:** The model ID has a version suffix (`-v1:0`) that is NOT visible in the console UI. Always verify with the CLI command below.

**CLI Verification:**
```bash
aws bedrock list-foundation-models --by-provider anthropic --region us-west-2 \
  --query "modelSummaries[?contains(modelId,'claude-3-5-haiku')].modelId" \
  --output text
```

---

## Phase 2: Understand the Instructor-Provided Files

You received four files from the instructor. Before writing any code, understand what each one does.

| File | Purpose | Your Action |
|------|---------|-------------|
| `bonus_G_bedrock_autoreport.tf` | Terraform skeleton — S3 bucket, IAM role/policy, Lambda function, SNS subscription, permissions | Add to your Terraform project, fill in TODOs |
| `handler.py` | Lambda Python code — evidence collection + Bedrock call + S3 storage + SNS notify | Customize for your Bedrock model, zip for deployment |
| `1c_bonus-G_Bedrock_template.md` | Incident report template — the exact headings Bedrock must output | Reference only (already embedded in handler.py) |
| `1c_bonus-G_Bedrock.md` | Instructor overview — architecture, grading rubric, advanced criteria | Your roadmap |

> **SOCRATIC Q&A — Why a Template for AI Output?**
>
> **Q:** Why do we force the AI to follow an exact template instead of letting it write whatever it wants?
>
> **A (ELI10):** Imagine you're a teacher grading 30 book reports. If every student used a different format — one wrote a poem, one drew a picture, one wrote a song — it would take forever to grade. But if everyone used the same template (Title, Summary, Characters, Theme), you can compare them instantly. In incident response, *consistency is everything.* When you're reading your 50th incident report at 2 AM, you need to know exactly where to look for the root cause.
>
> **Evaluator Question:** *"Why is a structured incident report template critical for operational teams?"*
>
> **Model Answer:** Structured templates enable three things: (1) **Speed during triage** — responders know exactly where to find critical info; (2) **Pattern detection over time** — you can compare incidents across weeks/months to spot systemic issues; (3) **Auditability** — compliance teams can verify that every incident was investigated consistently. This is why frameworks like NIST and SOC2 require standardized incident documentation.

---

## Phase 3: Deploy the S3 Reports Bucket + IAM Foundation

### Step 3.1 — Add the Terraform File

Copy `bonus_G_bedrock_autoreport.tf` into your Terraform project directory alongside your other `.tf` files.

### Step 3.2 — Review the S3 Bucket Resource

```hcl
resource "aws_s3_bucket" "chewbacca_ir_reports_bucket01" {
  bucket = "${var.project_name}-ir-reports-${data.aws_caller_identity.chewbacca_self01.account_id}"
}
```

> **SOCRATIC Q&A — Why a Dedicated Bucket?**
>
> **Q:** Why not just write the reports to the same S3 bucket I already have (like ALB logs)?
>
> **A (ELI10):** Imagine you have one big toy box where you throw everything — LEGOs, crayons, homework, snacks. When Mom asks "where's your math homework?", you're digging through a mess. Now imagine you have a special folder *just* for homework. You can find any assignment instantly, and Mom can check it without seeing your snack wrappers. In cloud engineering, **separation of concerns** means each type of data gets its own home with its own access rules.
>
> **Evaluator Question:** *"What are the security and operational benefits of isolating incident report artifacts in a dedicated S3 bucket?"*
>
> **Model Answer:** (1) **Least-privilege access** — the Lambda only needs write access to this one bucket, not your entire S3 estate; (2) **Lifecycle management** — you can set retention policies specific to incident reports (e.g., keep for 1 year for compliance) without affecting other data; (3) **Blast radius containment** — if the bucket policy is misconfigured, only IR reports are exposed, not application data or credentials; (4) **Audit trail** — S3 access logs for this bucket give you a clean record of who accessed incident reports.

### Step 3.3 — Review the Public Access Block

```hcl
resource "aws_s3_bucket_public_access_block" "chewbacca_ir_reports_pab01" {
  bucket                  = aws_s3_bucket.chewbacca_ir_reports_bucket01.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

> **SOCRATIC Q&A — The Four Locks**
>
> **Q:** Why are there FOUR separate "block public" settings? Isn't one enough?
>
> **A (ELI10):** Think of your house. You have a front door lock, a deadbolt, a chain lock, and a security system. Any ONE of them might fail — maybe you forget to lock the deadbolt, or the chain breaks. But with all four? Someone would have to defeat every single one. Each of these four settings blocks a *different way* someone could accidentally make your bucket public. It's defense in depth — the same reason your car has seatbelts AND airbags AND crumple zones.
>
> **Evaluator Question:** *"Explain what each of the four S3 public access block settings prevents."*
>
> **Model Answer:** `block_public_acls` prevents *new* public ACLs from being applied; `ignore_public_acls` makes existing public ACLs have no effect; `block_public_policy` prevents bucket policies that grant public access; `restrict_public_buckets` prevents public and cross-account access granted through any public bucket policy. Together they form a complete defense against accidental public exposure regardless of how access might be granted.

---

## Phase 4: Deploy the Lambda IAM Role and Policy

### Step 4.1 — Review the IAM Role (Trust Policy)

The Lambda needs an IAM role to assume. The trust policy says "only the Lambda service can use this role."

```hcl
resource "aws_iam_role" "chewbacca_ir_lambda_role01" {
  name = "${var.project_name}-ir-lambda-role01"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
```

> **SOCRATIC Q&A — Trust Policy vs. Permission Policy**
>
> **Q:** What's the difference between the trust policy (who can *become* this role) and the permission policy (what this role can *do*)?
>
> **A (ELI10):** Imagine a VIP backstage pass at a concert. The **trust policy** is the bouncer at the door — it checks "are you on the list?" (only `lambda.amazonaws.com` is on the list). The **permission policy** is the list of rooms you can enter once you're backstage — "you can go to the green room and the sound booth, but NOT the artist's dressing room." Both are needed: you can't do anything without getting in the door, and getting in the door doesn't automatically let you go everywhere.
>
> **Evaluator Question:** *"Why does the Lambda role's trust policy specify `lambda.amazonaws.com` as the principal, and what would happen if you accidentally set it to `*`?"*
>
> **Model Answer:** The trust policy restricts which AWS service can assume this role. Setting the principal to `lambda.amazonaws.com` ensures only the Lambda service can use these permissions. If set to `*`, any AWS principal (any user, role, or service in any account) could assume this role and gain access to your CloudWatch logs, Secrets Manager, S3 bucket, and Bedrock — a critical privilege escalation vulnerability.

### Step 4.2 — Review the Permission Policy (What Lambda Can Do)

The policy grants access to exactly six services. Study each block:

| Permission Block | Why Lambda Needs It |
|-----------------|-------------------|
| `logs:StartQuery`, `GetQueryResults` | Run CloudWatch Logs Insights queries against app + WAF logs |
| `cloudwatch:DescribeAlarms`, `GetMetricData` | Read alarm state and metric data for the report |
| `ssm:GetParameter*` | Pull `/lab/db/*` config values (endpoint, port, DB name) |
| `secretsmanager:GetSecretValue` | Pull DB connection metadata (NOT the password — the code filters it) |
| `s3:PutObject`, `GetObject` | Write the report + evidence bundle to the IR bucket |
| `bedrock:InvokeModel` | Call the AI model to generate the report |

> **SOCRATIC Q&A — Least Privilege in Action**
>
> **Q:** The SSM permission uses a specific resource ARN (`arn:aws:ssm:*:ACCOUNT:parameter/lab/db/*`) but the Bedrock permission uses `Resource = "*"`. Why the inconsistency?
>
> **A (ELI10):** Think about giving someone a library card. For the school library, you can say exactly which shelves they're allowed to visit — "only the science section on floor 2." But for the public internet, you can't list every website in advance. SSM parameters have predictable paths (`/lab/db/*`), so we can lock it down precisely. Bedrock model ARNs are harder to predict and may change, so `*` is acceptable here — but in production, you'd narrow it to the specific model ARN.
>
> **Evaluator Question:** *"How would you tighten the Bedrock IAM permission for a production environment?"*
>
> **Model Answer:** Replace `Resource: "*"` with the specific model ARN: `arn:aws:bedrock:REGION::foundation-model/amazon.titan-text-express-v1`. This ensures the Lambda can only invoke the approved model, preventing cost surprises if someone changes the `BEDROCK_MODEL_ID` environment variable to a more expensive model. In an organization, you'd also add a service control policy (SCP) or permissions boundary to restrict which Bedrock models any role can invoke.

### Step 4.3 — Note the Bug in the Skeleton

Look at line 120 of the Terraform file:

```hcl
policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
```

**This has a missing account ID field.** The correct ARN should be:

```hcl
policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
```

Wait — actually, AWS-managed policies use an **empty account field**, which means the format `arn:aws:iam::aws:policy/...` is correct in some contexts but Terraform expects `arn:aws:iam::aws:policy/...`. Double-check this works in your `terraform plan`. If it fails, the correct format for AWS-managed policies is:

```hcl
policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
```

> **SOCRATIC Q&A — Why a Separate Logging Permission?**
>
> **Q:** Lambda already has `logs:StartQuery` permission. Why does it ALSO need `AWSLambdaBasicExecutionRole`?
>
> **A (ELI10):** The `logs:StartQuery` permission lets Lambda *read other people's diaries* (app logs, WAF logs). But `AWSLambdaBasicExecutionRole` lets Lambda *write its own diary* (its own execution logs in CloudWatch). Without it, when your Lambda crashes, you'd have ZERO visibility into what went wrong — no logs, no errors, nothing. It's like a security camera that can watch every room but has no way to record what it sees.
>
> **Evaluator Question:** *"What happens if a Lambda function doesn't have AWSLambdaBasicExecutionRole or equivalent logging permissions?"*
>
> **Model Answer:** The function will still execute, but it cannot write logs to CloudWatch. This means `print()` statements, error tracebacks, and execution metadata are all silently lost. You'd be debugging blind — the function could be failing on every invocation and you'd never know unless you specifically checked the invocation error metrics.

---

## Phase 5: Prepare and Deploy the Lambda Function

### Step 5.1 — Adapt handler.py for Claude 3.5 Haiku

The instructor's `handler.py` uses a generic request body format based on Amazon Titan's `inputText` API. **This will NOT work with Claude.** You must replace the `bedrock_generate()` function with the Claude Messages API format.

**⚠️ Instructor skeleton (won't work with Claude — replace this):**
```python
# ❌ OLD — Titan format from instructor skeleton
def bedrock_generate(report_prompt: str):
    body = json.dumps({
        "inputText": report_prompt,           # ← Titan-specific key
        "textGenerationConfig": {             # ← Titan-specific config
            "maxTokenCount": 2000,
            "temperature": 0.2,
            "topP": 0.9
        }
    })
```

**✅ Replace with — Claude 3.5 Haiku Messages API format:**
```python
def bedrock_generate(report_prompt: str):
    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 4096,
        "temperature": 0.2,
        "messages": [{"role": "user", "content": report_prompt}]
    })
    resp = bedrock.invoke_model(
        modelId=MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=body
    )
    payload = json.loads(resp["body"].read())
    # Claude returns text in content[0].text
    return payload.get("content", [{}])[0].get("text", json.dumps(payload, indent=2))
```

**Key differences from the Titan skeleton:**

| Parameter | Titan (Instructor Skeleton) | Claude 3.5 Haiku (Your Code) |
|-----------|-----------------------------|-------------------------------|
| Prompt field | `inputText` (string) | `messages` (array of role/content objects) |
| Token limit | `maxTokenCount` inside `textGenerationConfig` | `max_tokens` at top level |
| Version header | Not required | `anthropic_version: "bedrock-2023-05-31"` (required) |
| Response path | `results[0].outputText` | `content[0].text` |
| Max tokens | 2000 (Titan default) | 4096 (increased — incident reports can be long) |

> **SOCRATIC Q&A — Why Different Request Bodies?**
>
> **Q:** Why can't I just send the same JSON to every Bedrock model?
>
> **A (ELI10):** Imagine ordering food at different restaurants. At McDonald's, you say "I'll have a #3 combo." At a Japanese restaurant, you might say "omakase, please." At a taco truck, you say "two al pastor, extra lime." They're all food orders, but each place has its own language. Bedrock is a "food court" for AI models — each model family (Titan, Claude, Llama) was built by a different company with their own API format. AWS provides the building (Bedrock), but each model speaks its own dialect.
>
> **Evaluator Question:** *"The instructor's skeleton used Amazon Titan's request format. You deployed Claude instead. What did you have to change and why?"*
>
> **Model Answer:** Bedrock follows a **model marketplace / gateway pattern** — AWS provides a unified endpoint (`bedrock-runtime`) with consistent authentication, billing, and networking, but preserves each model provider's native API format. Titan uses `inputText` as a flat string with a `textGenerationConfig` block. Claude uses the Messages API with a `messages` array of role/content objects and requires an `anthropic_version` header. The response parsing also differs: Titan returns `results[0].outputText`, Claude returns `content[0].text`. This is the real-world challenge of working with multi-provider AI platforms — you must read each model's documentation and adapt your integration code accordingly. AWS documents this at the Bedrock InvokeModel API reference.

### Step 5.2 — Review the Prompt Engineering (Non-Negotiable Rules)

Look at the prompt in `handler.py`:

```python
prompt = f"""
You are an SRE generating a concise, high-signal incident report in MARKDOWN.

Use ONLY the provided evidence. Do not invent facts.
If evidence is missing, write "Unknown" and recommend what to collect next.
...
"""
```

> **SOCRATIC Q&A — Why "Use ONLY the Provided Evidence"?**
>
> **Q:** The AI model knows a lot about AWS. Why can't it just fill in gaps with its general knowledge?
>
> **A (ELI10):** Imagine you're a detective investigating a burglary. You walk into the house and see a broken window and muddy footprints. Your report should say "broken window, muddy footprints." But if you *also* write "the burglar was probably named Steve because most burglars are named Steve" — that's made up! In incident response, **invented claims are worse than saying "Unknown"** because someone might act on them. If the AI says "root cause: database credential rotation" but that's actually wrong, the team wastes hours investigating the wrong thing while the real problem gets worse.
>
> **Evaluator Question:** *"What is 'hallucination' in the context of LLM-generated incident reports, and what guardrails does this pipeline implement to prevent it?"*
>
> **Model Answer:** Hallucination is when an LLM generates plausible-sounding but factually incorrect information. This pipeline implements four guardrails: (1) **Evidence-only constraint** — the prompt explicitly says "Use ONLY the provided evidence"; (2) **Unknown acknowledgment** — the prompt instructs "If evidence is missing, write Unknown"; (3) **Confidence levels** — the prompt requires confidence ratings so reviewers know what to trust; (4) **Citation requirement** — "Report must cite which query/field supports each key claim." The human reviewer is the final guardrail — **AI summarizes, humans interpret.**

### Step 5.3 — Review the Secret Handling (Critical Security Pattern)

Look at line 116 of `handler.py`:

```python
"secret_meta": {k: secret.get(k) for k in ("host","port","dbname","username")},  # avoid dumping password
```

> **SOCRATIC Q&A — Why Filter the Secret?**
>
> **Q:** The Lambda retrieves the full secret from Secrets Manager, including the password. Why does it only pass metadata (host, port, dbname, username) to the evidence bundle?
>
> **A (ELI10):** Imagine you're writing a report about your house for insurance. You'd write "I have a front door with a Schlage lock." You would NOT write "I have a front door with a Schlage lock and the combination is 1-2-3-4." The incident report goes to S3, gets sent via SNS, maybe gets emailed around, maybe gets pasted into Slack. If the password is in the report, it's now in 15 different places. The Lambda needs to *check* if the credential is valid, but it should never *record* the credential in the output.
>
> **Evaluator Question:** *"What would the blast radius be if the Lambda included the database password in the evidence bundle stored in S3?"*
>
> **Model Answer:** The password would be exposed in the JSON evidence file in S3, in the Bedrock-generated Markdown report (since the evidence is passed to the model), in the SNS notification if any content is included, and in CloudWatch logs if the Lambda logs the evidence. Anyone with read access to any of those locations gains database credentials. This is why the code explicitly filters to metadata only — it's applying the principle of **minimum necessary data exposure**, even for internal tooling.

### Step 5.4 — Package the Lambda

```bash
# From your project directory
cd lambda_ir_reporter/    # or wherever you placed handler.py
zip lambda_ir_reporter.zip handler.py
# Move the zip to where Terraform expects it
mv lambda_ir_reporter.zip ../
```

### Step 5.5 — Update the Terraform TODO

In `bonus_G_bedrock_autoreport.tf`, update the `BEDROCK_MODEL_ID`:

```hcl
environment {
  variables = {
    ...
    BEDROCK_MODEL_ID = "anthropic.claude-3-5-haiku-20241022-v1:0"  # ← Full model ID (verify with: aws bedrock list-foundation-models --region YOUR_REGION --query "modelSummaries[?contains(modelId,'claude-3-5-haiku')].modelId" --output text)
    ...
  }
}
```

⚠️ **The model ID includes a version suffix (`-v1:0`) that is NOT obvious from the Bedrock console UI.** Always verify with the CLI in your target region. See Bug #5 in the debugging narrative.

---

## Phase 6: Deploy with Terraform

### Step 6.1 — Plan and Apply

```bash
terraform plan
terraform apply
```

**What Terraform Creates (6 new resources):**
1. S3 bucket for incident reports
2. S3 public access block
3. IAM role for Lambda
4. IAM policy with 6 service permission blocks
5. Lambda function with environment variables
6. SNS → Lambda subscription + invocation permission

> **SOCRATIC Q&A — Why SNS → Lambda (Not Alarm → Lambda Directly)?**
>
> **Q:** The CloudWatch Alarm could invoke the Lambda directly. Why route through SNS first?
>
> **A (ELI10):** Imagine your school fire alarm. It could be wired directly to the fire truck (alarm → response). But instead, it calls a dispatcher first (alarm → dispatcher → fire truck + ambulance + police). The dispatcher (SNS) can notify *multiple* responders: your email gets an alert AND the Lambda generates a report AND maybe a PagerDuty integration fires. If you wired the alarm directly to Lambda, you'd lose the email notification you already had working. **SNS is the fan-out layer** — one event, many subscribers.
>
> **Evaluator Question:** *"What's the architectural advantage of using SNS as an intermediary between CloudWatch Alarms and downstream processors like Lambda?"*
>
> **Model Answer:** SNS provides **fan-out** (one alarm triggers multiple subscribers without modifying the alarm), **decoupling** (adding/removing subscribers doesn't require alarm changes), **protocol flexibility** (email, Lambda, SQS, HTTP all from one topic), and **retry/dead-letter handling** (failed Lambda invocations can be retried or sent to DLQ). It follows the pub/sub pattern — the alarm publishes and doesn't need to know who's listening.

### Step 6.2 — Verify Deployment

```bash
# Verify Lambda exists
aws lambda get-function --function-name chewbacca-ir-reporter01 \
  --query "Configuration.{Name:FunctionName,Runtime:Runtime,Role:Role,Timeout:Timeout}" \
  --output table

# Verify S3 bucket
aws s3 ls | grep ir-reports

# Verify SNS subscription
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw chewbacca_sns_topic_arn) \
  --query "Subscriptions[?Protocol=='lambda'].{Endpoint:Endpoint,Protocol:Protocol}" \
  --output table

# Verify Lambda environment variables
aws lambda get-function-configuration \
  --function-name chewbacca-ir-reporter01 \
  --query "Environment.Variables" \
  --output table
```

---

## Phase 7: Test the Pipeline

### Step 7.1 — Test Lambda Manually (Before Wiring to Real Alarm)

Create a test event that simulates an SNS message from a CloudWatch Alarm:

```bash
# Create test event file
cat > /tmp/test_event.json << 'EOF'
{
  "Records": [{
    "Sns": {
      "Message": "{\"AlarmName\":\"chewbacca-db-error-alarm01\",\"NewStateValue\":\"ALARM\",\"NewStateReason\":\"Threshold Crossed: 3 datapoints were greater than or equal to the threshold (3.0)\"}"
    }
  }]
}
EOF

# Invoke Lambda
aws lambda invoke \
  --function-name chewbacca-ir-reporter01 \
  --payload file:///tmp/test_event.json \
  --cli-binary-format raw-in-base64-out \
  /tmp/lambda_output.json

cat /tmp/lambda_output.json
```

> **SOCRATIC Q&A — Why Test with a Fake Event First?**
>
> **Q:** Why not just break the database and let the real alarm trigger the Lambda?
>
> **A (ELI10):** Imagine you're testing a parachute. Would you rather test it by: (A) jumping out of a plane and hoping it works, or (B) pulling the cord while standing on the ground to see if it opens? Testing with a fake event lets you check if the Lambda code works *before* you're in a real emergency. If the Lambda has a bug (wrong model ID, bad IAM permissions, broken code), you want to find out in a calm test, not during a real incident when you're already stressed.
>
> **Evaluator Question:** *"What's the testing strategy for an event-driven serverless pipeline, and why is unit testing alone insufficient?"*
>
> **Model Answer:** The testing strategy has three layers: (1) **Local testing** — verify the Python logic with mocked AWS clients; (2) **Integration testing** — invoke the Lambda with a simulated event (what we're doing here) to verify IAM permissions, environment variables, and real AWS API calls work; (3) **End-to-end testing** — trigger the actual alarm to verify the SNS → Lambda subscription, event payload format, and complete pipeline flow. Unit tests can't catch IAM permission errors or environment variable misconfigurations, which is why integration testing with a real deployed Lambda is essential.

### Step 7.2 — Check Lambda Logs for Errors

```bash
aws logs tail /aws/lambda/chewbacca-ir-reporter01 --since 5m --format short
```

Common errors you might see:

| Error | Root Cause | Fix |
|-------|-----------|-----|
| `AccessDeniedException` on Bedrock | Anthropic use case not submitted, or IAM missing `bedrock:InvokeModel` | Submit use case in Model catalog yellow banner; check IAM policy |
| `ValidationException` on Bedrock | Using Titan `inputText` format instead of Claude Messages API | Replace `bedrock_generate()` with the Claude version from Step 5.1 |
| `ResourceNotFoundException` on Logs | Log group name doesn't match | Check `APP_LOG_GROUP` env var matches your actual log group |
| `ModelNotReadyException` | Model access still processing | Wait a few minutes and retry, or test in Playground first |
| `NoSuchBucket` | Terraform hasn't created the bucket yet | Re-run `terraform apply` |

### Step 7.2a — Real Debugging Narrative: Bugs We Hit and How We Fixed Them

**This section documents the actual sequence of failures encountered during deployment.** This is the real learning — not the clean "it worked on the first try" story, but the iterative investigation process that real engineers go through. Capture this in your deliverables.

> **SOCRATIC Q&A — Why Document Debugging?**
>
> **Q:** Why would I include my mistakes in my deliverables? Shouldn't I only show the clean final result?
>
> **A (ELI10):** Imagine two kids showing their math homework. Kid A shows a perfect answer sheet. Kid B shows the same correct answers, but also wrote "I tried X first and it didn't work because Y, so I changed to Z." The teacher knows Kid B actually *understands* the math. Kid A might have just copied someone. In engineering interviews, showing your debugging process proves you can solve problems you've never seen before — that's worth more than a clean demo.
>
> **Evaluator Question:** *"Walk me through a time you debugged a multi-service AWS pipeline. What was your approach?"*
>
> **Model Answer:** Use the narrative below — it shows methodical isolation of failures across six different services (CloudWatch Logs, Bedrock, IAM, SNS, Lambda, Terraform) using a consistent pattern: invoke → read error → identify root cause → fix → re-invoke.

---

#### Bug #1: SNS Topic Name Mismatch (Terraform)

**Error:** `A managed resource "aws_sns_topic" "chewbacca_sns_topic01" has not been declared in the root module.`

**Root Cause:** The instructor's skeleton referenced `aws_sns_topic.chewbacca_sns_topic01`, but our actual SNS topic was named `aws_sns_topic.alerts` (defined in `cloudwatch.tf` from the core lab). The instructor used Chewbacca naming conventions; we used a simpler name.

**How We Found It:** `grep -r "aws_sns_topic" *.tf` showed the mismatch instantly.

**Fix:** Replaced all three references in `bonus_G_bedrock_autoreport.tf`:
```bash
sed -i '' 's/chewbacca_sns_topic01/alerts/g' bonus_G_bedrock_autoreport.tf
```

**Lesson:** Instructor skeleton code assumes their naming conventions. Always verify resource names against YOUR existing Terraform state before applying.

---

#### Bug #2: Regex `/i` Flag Not Supported (CloudWatch Logs Insights)

**Error:** `MalformedQueryException: unexpected symbol found i at line 1 and position 167`

**Root Cause:** The instructor's Logs Insights queries used `/i` (case-insensitive regex flag), which CloudWatch Logs Insights does not support. This syntax works in many programming languages but NOT in the Insights query language.

**How We Found It:** Lambda logs showed the exact query and position of the error. The stack trace pointed to `run_insights_query()` on the `app_errors` query.

**Fix:** Removed `/i` from both app log queries in `handler.py`:
```python
# Before (broken)
"filter @message like /ERROR|DB|timeout|refused|Access denied/i"

# After (fixed)
"filter @message like /ERROR|DB|timeout|refused|Access denied/"
```

**Lesson:** Regex syntax varies across services. Always validate queries in the CloudWatch console or CLI before embedding them in Lambda code.

---

#### Bug #3: `sort bin(1m)` Syntax Error (CloudWatch Logs Insights)

**Error:** `MalformedQueryException: unexpected symbol found ( at line 1 and position 211`

**Root Cause:** The `app_rate` query used `sort bin(1m) asc`, but `bin(1m)` is a function call that Logs Insights doesn't recognize in the `sort` clause without backtick escaping.

**How We Found It:** After fixing Bug #2, the first query (`app_errors`) passed but the second query (`app_rate`) failed. We isolated it by testing the query directly via CLI, progressively simplifying until we found that removing `| sort bin(1m) asc` made it work.

**Debugging commands used:**
```bash
# Failed
aws logs start-query --log-group-name "/aws/ec2/chewbacca-app" \
  --query-string 'fields @timestamp | filter @message like /ERROR/ | stats count() as errors by bin(1m) | sort bin(1m) asc'

# Passed (removed sort)
aws logs start-query --log-group-name "/aws/ec2/chewbacca-app" \
  --query-string 'fields @timestamp | filter @message like /ERROR/ | stats count() as errors by bin(1m)'
```

**Fix:** Added backticks around `bin(1m)` in the sort clause:
```python
# Before (broken)
"sort bin(1m) asc"

# After (fixed)
"sort `bin(1m)` asc"
```

**Lesson:** In CloudWatch Logs Insights, field names that are function expressions must be backtick-escaped in `sort` and `display` clauses. This is poorly documented.

---

#### Bug #4: Log Group Name Mismatch (Lambda Environment Variable)

**Error:** `ResourceNotFoundException: Log group '/aws/ec2/chewbacca-rds-app' does not exist`

**Root Cause:** The Terraform skeleton hardcoded `APP_LOG_GROUP = "/aws/ec2/${var.project_name}-rds-app"` but our actual log group was `/aws/ec2/chewbacca-app` (without the `-rds-` infix).

**How We Found It:** The error message told us exactly which log group it was looking for. We confirmed with:
```bash
aws logs describe-log-groups \
  --query "logGroups[?contains(logGroupName,'chewbacca')].logGroupName" --output table
```

**Fix:** Updated the Lambda environment variable via CLI (and updated `bonus_G_bedrock_autoreport.tf` for Terraform sync):
```bash
# CLI fix (immediate)
aws lambda update-function-configuration \
  --function-name chewbacca-ir-reporter01 \
  --environment "Variables={...,APP_LOG_GROUP=/aws/ec2/chewbacca-app,...}"

# Terraform fix (permanent)
APP_LOG_GROUP = "/aws/ec2/chewbacca-app"
```

**Lesson:** Instructor skeletons use assumed naming patterns. Always verify actual resource names in your account before deploying.

---

#### Bug #5: Bedrock Model ID Wrong (Lambda Environment Variable)

**Error:** `ValidationException: The provided model identifier is invalid.`

**Root Cause:** We set `BEDROCK_MODEL_ID` to `anthropic.claude-3-5-haiku-20241022`, but the actual model ID in `us-west-2` is `anthropic.claude-3-5-haiku-20241022-v1:0` (includes the version suffix).

**How We Found It:** The Playground worked (different region/context), but the Lambda failed. We discovered the exact ID with:
```bash
aws bedrock list-foundation-models --region us-west-2 \
  --query "modelSummaries[?contains(modelId,'claude-3-5-haiku')].modelId" --output text
```

**Fix:** Updated the Lambda environment variable to the exact model ID:
```bash
aws lambda update-function-configuration \
  --function-name chewbacca-ir-reporter01 \
  --environment "Variables={...,BEDROCK_MODEL_ID=anthropic.claude-3-5-haiku-20241022-v1:0,...}"
```

**Lesson:** Never assume model IDs — always query the Bedrock API in your target region. Model IDs can have version suffixes that aren't obvious from the console UI.

---

#### Bug #6: Missing SNS:Publish Permission (IAM)

**Error:** `AuthorizationError: User arn:aws:sts::262164343754:assumed-role/chewbacca-ir-lambda-role01/chewbacca-ir-reporter01 is not authorized to perform: SNS:Publish`

**Root Cause:** The instructor's Terraform skeleton IAM policy included permissions for CloudWatch, SSM, Secrets Manager, S3, and Bedrock — but forgot `sns:Publish`. The Lambda needs to publish the "Report Ready" notification after generating the report.

**How We Found It:** This was the LAST error — everything else worked (evidence collection, Bedrock generation, S3 upload). The Lambda only failed at the final SNS publish step. The error message was explicit about the missing action.

**Fix:** Added an inline IAM policy via CLI (immediate), then updated `bonus_G_bedrock_autoreport.tf` (permanent):
```bash
# CLI fix (immediate)
aws iam put-role-policy \
  --role-name chewbacca-ir-lambda-role01 \
  --policy-name sns-publish \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "arn:aws:sns:us-west-2:262164343754:chewbacca-alerts"
    }]
  }'

# Terraform fix (permanent) — add to policy statements in bonus_G_bedrock_autoreport.tf:
{
  Effect = "Allow",
  Action = ["sns:Publish"],
  Resource = aws_sns_topic.alerts.arn
}
```

**Lesson:** Always audit IAM policies against every AWS API call your code makes. The instructor's skeleton had a gap — this is common in real skeleton/template code. The pattern: read the Lambda code → list every `boto3` client call → verify each action exists in the IAM policy.

> **SOCRATIC Q&A — The Debugging Pattern**
>
> **Q:** We hit six bugs. That seems like a lot. Is this normal?
>
> **A (ELI10):** Imagine building a LEGO set where the instructions were written for a slightly different version of the set. The pieces are mostly the same, but some pieces have different names, some steps assume you have a piece you don't have, and some diagrams have small errors. You don't throw away the instructions — you use them as a guide and adapt as you go. That's exactly what happened here: the instructor provided a skeleton, but it was designed for *their* environment. Adapting it to *your* environment IS the engineering work.
>
> **Evaluator Question:** *"You deployed an instructor-provided Lambda skeleton and hit six different errors. Walk me through your debugging methodology."*
>
> **Model Answer:** I used an iterative **invoke → read error → isolate → fix → re-invoke** cycle. Each error was in a different service (Terraform naming, CloudWatch query syntax, Lambda env vars, Bedrock model ID, IAM permissions), which demonstrates the challenge of multi-service pipelines — a single Lambda touches 6+ AWS services, and each one can fail independently. Key techniques: (1) tested queries in CLI before embedding in Lambda; (2) used `aws logs tail` for Lambda execution logs; (3) used `grep` to find resource name mismatches across Terraform files; (4) used `aws bedrock list-foundation-models` to discover exact model IDs; (5) applied CLI fixes for immediate unblocking, then synced Terraform for long-term state. The six bugs were typical of adapting skeleton code to a real environment — not a sign of broken code, but of the normal integration work that skeleton code requires.

---

**Summary of All Fixes Applied:**

| # | Bug | Service | Fix | Applied Via |
|---|-----|---------|-----|-------------|
| 1 | SNS topic name mismatch | Terraform | `chewbacca_sns_topic01` → `alerts` | `sed` on `.tf` file |
| 2 | Regex `/i` flag unsupported | CloudWatch Logs Insights | Removed `/i` from queries | `handler.py` edit + re-zip |
| 3 | `sort bin(1m)` syntax | CloudWatch Logs Insights | Added backticks: `` sort `bin(1m)` `` | `handler.py` edit + re-zip |
| 4 | Log group name wrong | Lambda env var | `/aws/ec2/chewbacca-rds-app` → `/aws/ec2/chewbacca-app` | CLI `update-function-configuration` |
| 5 | Model ID incomplete | Lambda env var | Added `-v1:0` suffix | CLI `update-function-configuration` |
| 6 | Missing `sns:Publish` | IAM | Added SNS publish permission | CLI `put-role-policy` + `.tf` update |

### Step 7.3 — Verify Report in S3

```bash
# List reports
aws s3 ls s3://$(terraform output -raw chewbacca_ir_reports_bucket)/reports/

# Download and read the Markdown report
aws s3 cp s3://$(terraform output -raw chewbacca_ir_reports_bucket)/reports/chewbacca-YYYYMMDD-HHMMSS.md /tmp/report.md
cat /tmp/report.md

# Download the JSON evidence
aws s3 cp s3://$(terraform output -raw chewbacca_ir_reports_bucket)/reports/chewbacca-YYYYMMDD-HHMMSS.json /tmp/evidence.json
cat /tmp/evidence.json | python3 -m json.tool
```

### Step 7.4 — Trigger a Real Incident (End-to-End Test)

Now trigger your real alarm by breaking database connectivity (same technique from core lab):

```bash
# Rotate the secret to invalid credentials (triggers DB errors)
aws secretsmanager update-secret \
  --secret-id chewbacca/rds/mysql \
  --secret-string '{"host":"YOUR_RDS_ENDPOINT","port":"3306","dbname":"chewbaccadb","username":"admin","password":"WRONG_PASSWORD"}'

# Wait for alarm to fire (5 min window with 3 errors)
watch -n 30 "aws cloudwatch describe-alarms --alarm-names chewbacca-db-error-alarm01 --query 'MetricAlarms[0].StateValue' --output text"
```

Once the alarm fires → SNS triggers → Lambda runs → Report appears in S3.

> **SOCRATIC Q&A — The Full Circle**
>
> **Q:** We just broke the database on purpose, and a machine automatically investigated it and wrote a report. Why is this powerful?
>
> **A (ELI10):** Before this: alarm fires → you get an email → you log into AWS console → you click through CloudWatch → you manually run queries → you copy-paste into a Google Doc → you spend 30 minutes writing a report. **After this:** alarm fires → you get an email with a link to a finished report. You went from 30 minutes of evidence gathering to *seconds.* That's 30 minutes you can spend actually *fixing* the problem instead of documenting it. And the report is consistent every time — no more "oh I forgot to check WAF logs."
>
> **Evaluator Question:** *"Walk me through the end-to-end data flow from alarm to finished report."*
>
> **Model Answer:** (1) CloudWatch Alarm transitions to `ALARM` state when `DBConnectionErrors >= 3` per 5 min; (2) Alarm publishes to the SNS topic; (3) SNS invokes the Lambda function with the alarm payload as the event; (4) Lambda pulls configuration from SSM Parameter Store and metadata from Secrets Manager; (5) Lambda runs four Logs Insights queries against app and WAF log groups; (6) Lambda assembles a JSON evidence bundle; (7) Lambda sends the evidence + template to Bedrock, which generates a Markdown report; (8) Lambda writes both the JSON evidence and Markdown report to S3; (9) Lambda publishes a "Report Ready" SNS notification with S3 links; (10) The human reviewer validates the report against evidence before accepting any claims.

---

## Phase 8: Human Review (Required — Not Optional)

### Step 8.1 — Validate the Report

**Download and read the Bedrock-generated report.** Check each claim against the JSON evidence:

- [ ] Does the Executive Summary match what the evidence shows?
- [ ] Does the Timeline have UTC timestamps that match the alarm state changes?
- [ ] Are the "Top Error Signatures" actually present in the evidence?
- [ ] Does the Root Cause Analysis match the failure you injected?
- [ ] Are there ANY invented claims? (If yes, flag them)
- [ ] Is the password redacted? (It should NEVER appear)
- [ ] Does the report say "Unknown" for evidence it doesn't have? (Good sign)

> **SOCRATIC Q&A — Why Human Review Is Mandatory**
>
> **Q:** If the AI reviewed all the evidence, why do *I* still need to check the report?
>
> **A (ELI10):** Imagine a robot vacuum cleaned your whole house. Would you walk around afterward to check? Of course! Maybe it missed under the couch, or it vacuumed up your LEGO set, or it pushed dirt into a corner instead of actually picking it up. The AI is good at gathering and organizing, but it can make mistakes — it might misinterpret an error message, or confidently state something that isn't actually supported by the evidence. **The human is the last line of defense.** In a real company, the on-call engineer who signs the incident report is personally accountable for its accuracy.
>
> **Evaluator Question:** *"Why is human validation of AI-generated incident reports a non-negotiable step in an enterprise IR pipeline?"*
>
> **Model Answer:** Three reasons: (1) **Accountability** — someone must own the accuracy of the report; AI can't be held accountable; (2) **Context** — AI lacks institutional knowledge about recent changes, planned maintenance, or known issues that might explain the behavior; (3) **Hallucination risk** — even with evidence-only constraints, LLMs can misinterpret data, conflate unrelated signals, or state correlations as causation. The principle is: **AI accelerates the investigation, but the human owns the conclusion.**

### Step 8.2 — Restore Normal Operations

```bash
# Restore the correct secret
aws secretsmanager update-secret \
  --secret-id chewbacca/rds/mysql \
  --secret-string '{"host":"YOUR_RDS_ENDPOINT","port":"3306","dbname":"chewbaccadb","username":"admin","password":"CORRECT_PASSWORD"}'

# Wait for alarm to return to OK
watch -n 30 "aws cloudwatch describe-alarms --alarm-names chewbacca-db-error-alarm01 --query 'MetricAlarms[0].StateValue' --output text"
```

---

## Deliverables Checklist

| # | Deliverable | Evidence |
|---|------------|----------|
| 1 | `bonus_G_bedrock_autoreport.tf` in your Terraform project | `terraform plan` showing 6+ new resources |
| 2 | `handler.py` customized for Claude 3.5 Haiku | Zip deployed successfully with Messages API format |
| 3 | Lambda deployed and configured | `aws lambda get-function` output |
| 4 | S3 bucket with public access blocked | `aws s3api get-public-access-block` output |
| 5 | Successful manual Lambda invocation | Lambda output JSON showing `"ok": true` |
| 6 | JSON evidence bundle in S3 | Downloaded `.json` file with no passwords |
| 7 | Markdown report in S3 | Downloaded `.md` file matching template headings, "Unknown" where evidence was missing |
| 8 | End-to-end test (real alarm → report) | SNS notification received + report in S3 |
| 9 | Human review notes | Written validation that claims match evidence |
| 10 | Debugging narrative | Document the bugs hit and fixes applied (Step 7.2a) — this is interview gold |

---

## Advanced Grading Criteria (Top Students)

You pass **"advanced"** if:

1. **Both artifacts produced** — JSON evidence bundle AND Markdown report in S3
2. **No invented claims** — every statement in the report traces back to evidence
3. **Root cause matches** — the classification matches the failure you injected
4. **Secrets redacted** — password NEVER appears in evidence or report
5. **Preventive actions tied to evidence** — e.g., "implement automatic credential rotation because credential drift was the root cause"

---

## Interview Nuclear Option

> *"I built an event-driven incident response pipeline where CloudWatch Alarms trigger a Lambda function via SNS. The Lambda automatically collects evidence from CloudWatch Logs Insights, SSM Parameter Store, and Secrets Manager, then feeds that evidence to Amazon Bedrock to generate a structured incident report. The report and raw evidence are stored in S3, and the team gets notified via SNS. I explicitly designed the pipeline so that AI summarizes evidence but humans validate every claim — because in incident response, invented claims are worse than unknowns."*

That statement covers: **event-driven architecture, serverless, observability, secrets management, AI/ML integration, security principles, and operational maturity.** It puts you ahead of 95% of candidates.

---

## Optional Extra Credit: Mode B (Deep Report) ✅ COMPLETED

The instructor mentions two modes:

- **Mode A (what you just built):** 15-minute window, 4 queries, fast triage report
- **Mode B:** 60-minute window + WAF URI correlation + error clustering = deep investigation report

### Step EC.1 — Three Changes to `handler.py`

**Change 1: Expand the time window (line ~77)**

```python
# Before (Mode A)
start_ts = now - 15 * 60  # 15 min "fast report" window

# After (Mode B)
start_ts = now - 60 * 60  # 60 min "deep report" window
```

**Change 2: Add two new queries after `waf_blocks` (after line ~103)**

```python
    # Mode B: WAF URI correlation — which paths are being hit hardest?
    waf_top_uris = run_insights_query(
        WAF_LOG_GROUP,
        "fields httpRequest.uri | stats count() as hits by httpRequest.uri | sort hits desc | limit 10",
        start_ts, end_ts
    )

    # Mode B: Error clustering — are errors repeating with the same message?
    error_clusters = run_insights_query(
        APP_LOG_GROUP,
        "fields @message | filter @message like /ERROR/ | stats count() as cnt by @message | sort cnt desc | limit 10",
        start_ts, end_ts
    )
```

⚠️ **Do NOT use `/ERROR/i`** — the case-insensitive `/i` flag is not supported in CloudWatch Logs Insights (we learned this the hard way in Bug #2).

**Change 3: Add new queries to the evidence bundle**

Find the `"queries"` dict inside the `evidence` object and add two lines:

```python
        "queries": {
            "app_errors": app_errors,
            "app_rate": app_rate,
            "waf_actions": waf_actions,
            "waf_blocks": waf_blocks,
            "waf_top_uris": waf_top_uris,       # ← NEW
            "error_clusters": error_clusters      # ← NEW
        }
```

⚠️ **Common mistake:** Adding the queries but forgetting to add them to the evidence bundle. If you skip this step, the queries run but Bedrock never sees the results (they're not in the JSON it receives).

### Step EC.2 — Deploy and Test

```bash
cd lambda_ir_reporter
zip ../lambda_ir_reporter.zip handler.py
cd ..
aws lambda update-function-code \
  --function-name chewbacca-ir-reporter01 \
  --zip-file fileb://lambda_ir_reporter.zip
```

Press `q` to exit the output, then invoke:

```bash
aws lambda invoke \
  --function-name chewbacca-ir-reporter01 \
  --payload file:///tmp/test_event.json \
  --cli-binary-format raw-in-base64-out \
  /tmp/lambda_output.json

cat /tmp/lambda_output.json
```

Expected: `{"ok": true, "incident_id": "chewbacca-...", "report_s3": "s3://..."}`

### Step EC.3 — Verify Mode B Evidence

```bash
aws s3 cp s3://chewbacca-ir-reports-262164343754/reports/chewbacca-YYYYMMDD-HHMMSS.json /tmp/evidence_b.json
cat /tmp/evidence_b.json | python3 -m json.tool | grep -E "waf_top_uris|error_clusters"
```

Both keys should appear in the output. If they don't, you forgot Change 3 (adding them to the evidence bundle).

### Step EC.4 — Compare Mode A vs. Mode B Results

Download the Mode B report:

```bash
aws s3 cp s3://chewbacca-ir-reports-262164343754/reports/chewbacca-YYYYMMDD-HHMMSS.md /tmp/report_b.md
cat /tmp/report_b.md
```

**Actual results from our deployment:**

| Metric | Mode A (15 min) | Mode B (60 min) |
|--------|----------------|-----------------|
| WAF ALLOW hits | 2 | 7 |
| WAF BLOCK hits | 1 | 2 |
| Unique blocked IPs | 1 (`176.65.134.20`) | 2 (`176.65.134.20`, `84.66.211.226`) |
| URI breakdown | Not collected | `/` (8 hits), `/config/.env` (1 hit) |
| Error clusters | Not collected | No app errors (simulated event) |

**Key finding Mode B caught that Mode A missed:** IP `84.66.211.226` was probing `/config/.env` — a classic attacker technique scanning for exposed environment files containing database credentials, API keys, and secrets. The 15-minute Mode A window didn't capture this because the probe happened earlier. The 60-minute Mode B window caught the full attack pattern.

> **SOCRATIC Q&A — Mode A vs. Mode B**
>
> **Q:** When would you use a 15-minute window versus a 60-minute window?
>
> **A (ELI10):** A 15-minute window is like checking the security camera footage from the last few minutes — quick, focused, tells you what just happened. A 60-minute window is like reviewing the full hour of footage — you might see the burglar walk past the door three times before actually breaking in. **Mode A** is for fast triage: "what just broke?" **Mode B** is for deep investigation: "what led up to this and how widespread is the damage?" In a real incident, you'd run Mode A first for a quick picture, then Mode B for the full postmortem.
>
> **Q:** Why did Mode B catch the `/config/.env` probe but Mode A didn't?
>
> **A (ELI10):** Imagine you're a detective reviewing store security footage after a robbery. If you only look at the last 15 minutes, you see the robber grab the cash register and run. But if you look at the last hour, you see the same robber casing the store 45 minutes earlier — checking the exits, testing the locks, looking for cameras. That `/config/.env` probe was the attacker "casing the store." Mode A only saw the alarm. Mode B saw the reconnaissance that preceded it.
>
> **Evaluator Question:** *"Your Mode B report revealed an attacker probing `/config/.env`. What does this tell you about the threat, and what would you recommend?"*
>
> **Model Answer:** The `/config/.env` probe is a common automated scanner technique looking for accidentally exposed environment files — these often contain database credentials, API keys, and cloud secrets in plaintext. The fact that WAF blocked it (status: BLOCK) means our WAF rules are working. However, the probe itself indicates our infrastructure is being actively scanned. Recommendations: (1) Verify no `.env` files are accessible on the origin; (2) Check WAF rules cover other common scanner paths (`/.git/config`, `/wp-admin`, `/phpinfo.php`); (3) Consider rate limiting or IP reputation blocking for known scanner IPs; (4) The correlation between the `/config/.env` probe and the DB alarm is likely coincidental, but in a real investigation you'd verify the probe IP didn't also attempt SQL injection or credential stuffing.

### Mode B Troubleshooting

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| New queries run but don't appear in report | Forgot to add `waf_top_uris` and `error_clusters` to the `"queries"` dict in the evidence bundle | Add both keys to the evidence dict (Change 3) |
| `MalformedQueryException` on `error_clusters` | Used `/ERROR/i` flag (copied from instructor sketch) | Remove `/i` — CloudWatch Logs Insights doesn't support it (Bug #2) |
| Mode B report looks identical to Mode A | Time window wasn't changed | Verify `start_ts = now - 60 * 60` (not `15 * 60`) |
| Lambda timeout | 6 queries × polling time exceeds 60s timeout | Increase Lambda timeout to 120s in Terraform or CLI |

### Mode B Interview Answer

> "I extended the pipeline from Mode A (15-minute fast triage) to Mode B (60-minute deep investigation) by adding WAF URI correlation and error clustering queries. The wider window immediately revealed an attacker probing `/config/.env` that the 15-minute window missed entirely. This demonstrates why incident investigation needs multiple time horizons — fast triage tells you *what broke*, deep analysis tells you *what led up to it*. The `/config/.env` finding also triggered a follow-up security review of our WAF ruleset coverage."
