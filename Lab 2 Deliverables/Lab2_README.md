# SEIR FOUNDATIONS
# LAB 2: CloudFront, Origin Cloaking & Cache Correctness
*Enhanced Socratic Q&A Guide with Step-by-Step Instructions*

---

> **⚠️ PREREQUISITE**
>
> Labs 1, 1B, and 1C (including all Bonus modules A–F) must be completed and verified before starting Lab 2. You must have: VPC with public/private subnets, ALB with TLS (ACM), WAF (regional), Route53 hosted zone, working EC2→RDS application, Parameter Store, Secrets Manager, CloudWatch alarms, and SNS alerting.

---

## Lab Overview

Lab 2 transforms your Lab 1 architecture from "working application" to "production-grade edge security." You will place CloudFront in front of your ALB, lock down the ALB so only CloudFront can reach it (origin cloaking), move WAF enforcement to the edge, and configure intelligent caching policies that protect against cache poisoning while maximizing performance.

**The Architecture:**

```
Internet → CloudFront (+ WAF) → ALB (locked to CloudFront) → Private EC2 → RDS
```

**Key Constraints:**
- No one can hit ALB directly (even if they know ALB DNS)
- WAF enforcement happens at CloudFront edge
- DNS points to CloudFront, not ALB

---

## Why This Lab Exists (Real-World Context)

> **SOCRATIC Q&A**
>
> ***Q:** I already have an ALB with TLS and WAF from Lab 1C. Why add CloudFront on top?*
>
> **A (Explain Like I'm 10):** Imagine your house (ALB) has a great security system. But it's right on a busy street where anyone can walk up and knock. CloudFront is like moving your house behind a gated community with a guard at the entrance. The guard (WAF at the edge) stops bad visitors before they even reach your street. Your house still has its own locks (ALB rules), but now there are TWO layers of protection, and visitors are served from a nearby guardhouse (edge cache) instead of making them walk all the way to your door every time.
>
> **Evaluator Question:** *Why not just use the ALB with WAF directly? What does CloudFront add?*
>
> **Model Answer:** Three things: (1) **Performance** — CloudFront has 400+ edge locations worldwide, serving cached content closer to users. (2) **DDoS protection** — CloudFront absorbs volumetric attacks at the edge before they reach your ALB/VPC. AWS Shield Standard is automatically included. (3) **Origin protection** — with origin cloaking, attackers can't bypass WAF by hitting the ALB directly. Without CloudFront, anyone who discovers your ALB DNS name can skip your WAF entirely. This is a common real-world attack vector.

---

## What Changes from Lab 1C

| Action | Component | Detail |
|--------|-----------|--------|
| ✅ Keep | Private EC2, RDS, SSM, Secrets, incident automation, dashboards, alarms | All Lab 1 infrastructure stays |
| 🔄 Modify | WAF | Moves from ALB (REGIONAL) → CloudFront (CLOUDFRONT scope) |
| 🔄 Modify | DNS | Route53 aliases move from ALB → CloudFront distribution |
| 🔄 Modify | ALB SG | Replaces `0.0.0.0/0` with CloudFront prefix list only |
| 🆕 Add | CloudFront distribution | CDN in front of ALB origin |
| 🆕 Add | ACM cert in us-east-1 | CloudFront requires certs in N. Virginia |
| 🆕 Add | Secret origin header | Defense-in-depth: ALB requires header only CloudFront sends |
| 🆕 Add | Cache + ORP policies | Separate static (aggressive) vs API (safe) caching |

---

## Terraform File Structure

| File | Purpose |
|------|---------|
| `lab2_cloudfront_alb.tf` | CloudFront distribution, origin config, WAF association |
| `lab2_cloudfront_origin_cloaking.tf` | ALB SG prefix list rule, secret header, listener rules |
| `lab2_cloudfront_r53.tf` | Route53 A + AAAA records → CloudFront |
| `lab2_cloudfront_shield_waf.tf` | WAFv2 WebACL with CLOUDFRONT scope |
| `lab2b_cache_correctness.tf` | Cache policies, ORPs, response headers policy |
| `lab2b_honors_origin_driven.tf` | Honors: origin-driven cache behavior for `/api/public-feed` |
| `lab2b_honors_plus_invalidation_action.tf` | Honors: cache invalidation automation |

---

# PART 1: LAB 2A — Origin Cloaking

Origin cloaking ensures CloudFront is the **only** way to reach your application. Even though the ALB is technically "internet-facing" (CloudFront needs to reach it), direct access is blocked via two mechanisms.

---

## Step 1: ACM Certificate in us-east-1

CloudFront requires TLS certificates in the `us-east-1` (N. Virginia) region, regardless of where your origin lives.

> **SOCRATIC Q&A**
>
> ***Q:** Why does CloudFront require certificates in us-east-1 specifically? My ALB is in us-west-2.*
>
> **A (Explain Like I'm 10):** CloudFront is a *global* service — it doesn't live in any one region. But it needs to pick up its TLS certificate from somewhere, and AWS chose us-east-1 as the "global config home" for CloudFront. Think of it like a passport office — no matter where you travel in the world, you got your passport from one specific office. CloudFront's "passport office" is us-east-1.
>
> **Evaluator Question:** *What happens if you try to attach a us-west-2 ACM certificate to CloudFront?*
>
> **Model Answer:** CloudFront will reject it with a validation error. CloudFront is a global service that reads its configuration (including certificates) from us-east-1. This is why you either create a second `aws` provider alias for us-east-1 in Terraform, or create the cert manually. This catches many engineers off-guard in production because their existing certs are in their primary region.

**Terraform:** Uses a provider alias for us-east-1:

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

resource "aws_acm_certificate" "cloudfront" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method = "DNS"
}
```

**Verification:**
```bash
# Confirm cert is in us-east-1 and ISSUED
aws acm list-certificates --region us-east-1 \
  --query "CertificateSummaryList[?DomainName=='wheresjack.com'].Status" --output text
# Expected: ISSUED
```

---

## Step 2: ALB Security Group — CloudFront Prefix List Only

Replace the `0.0.0.0/0` ingress rules on the ALB security group with the AWS-managed CloudFront prefix list. This means only CloudFront edge IPs can reach the ALB.

> **SOCRATIC Q&A**
>
> ***Q:** What is a prefix list and why is it better than individual IP ranges?*
>
> **A (Explain Like I'm 10):** Imagine you're a bouncer at a club. You could memorize every single face of every VIP (individual IP ranges) — but the list changes every week and has thousands of people. Or you could just check for a special VIP wristband (prefix list). AWS maintains the wristband list for you, automatically updating it when CloudFront adds or removes edge IPs. You reference one prefix list ID (`pl-82a045eb` in us-west-2) instead of hundreds of CIDR ranges.
>
> **Evaluator Question:** *Why can't you rely on the prefix list alone for origin cloaking?*
>
> **Model Answer:** Because anyone can create their own CloudFront distribution and point it at your ALB. CloudFront IP ranges are shared across all AWS customers. The prefix list blocks non-CloudFront traffic, but doesn't distinguish YOUR CloudFront distribution from an attacker's. That's why you need the secret header as a second layer (defense-in-depth).

**Terraform:**
```hcl
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group_rule" "alb_ingress_cloudfront" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS from CloudFront only"
}
```

**Verification:**
```bash
# Confirm no 0.0.0.0/0 rules, only prefix list
aws ec2 describe-security-groups --group-ids sg-02bddb7d9e79f7d02 \
  --query "SecurityGroups[0].IpPermissions[].[IpRanges[].CidrIp, PrefixListIds[].PrefixListId]" --output text
# Expected: No CIDRs, only pl-82a045eb
```

---

## Step 3: Secret Origin Header (Defense-in-Depth)

CloudFront adds a secret custom header to every request it sends to the ALB. The ALB listener rules check for this header — requests without it get a 403.

> **SOCRATIC Q&A**
>
> ***Q:** If the prefix list already blocks non-CloudFront traffic, why do we need a secret header too?*
>
> **A (Explain Like I'm 10):** Remember, the prefix list is like checking for a VIP wristband — but ALL VIPs from ALL clubs wear the same wristband (all CloudFront distributions share the same IP ranges). The secret header is like a secret password that only YOUR club's VIPs know. An attacker could spin up their own CloudFront distribution pointing at your ALB (passing the prefix list check), but they won't know your secret password.
>
> **Evaluator Question:** *How is the secret header value managed securely?*
>
> **Model Answer:** Using `random_password` in Terraform to generate a high-entropy string, stored in Terraform state. CloudFront adds it as a custom origin header. The ALB listener rule checks for it. The value never appears in application code, logs, or URLs. If compromised, you rotate by changing the Terraform random seed and re-applying. AWS also documents this pattern in their CloudFront best practices.

**Terraform:**
```hcl
resource "random_password" "origin_header_secret" {
  length  = 32
  special = false
}

# In CloudFront distribution origin config:
custom_header {
  name  = "X-Chewbacca-Growl"
  value = random_password.origin_header_secret.result
}

# ALB listener rules:
resource "aws_lb_listener_rule" "require_origin_header" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1
  condition {
    http_header {
      http_header_name = "X-Chewbacca-Growl"
      values           = [random_password.origin_header_secret.result]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

resource "aws_lb_listener_rule" "default_block" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 99
  condition {
    path_pattern { values = ["/*"] }
  }
  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}
```

**Verification:**
```bash
# Direct ALB access should TIMEOUT (SG blocks it before header check)
curl -I --max-time 10 https://chewbacca-alb01-1094761683.us-west-2.elb.amazonaws.com
# Expected: Connection timed out (PASS — blocked at network layer)

# CloudFront access should succeed
curl -I https://wheresjack.com/list
# Expected: HTTP/2 200
```

---

## Step 4: WAF Moves to CloudFront (CLOUDFRONT Scope)

The WAF WebACL changes from REGIONAL (attached to ALB) to CLOUDFRONT scope (attached to the distribution). This means malicious traffic is blocked at the edge before it ever reaches your VPC.

> **SOCRATIC Q&A**
>
> ***Q:** Why move WAF from ALB to CloudFront? Can't I have WAF on both?*
>
> **A (Explain Like I'm 10):** You CAN have both, but the best strategy is to stop bad guys as far away from your house as possible. WAF on the ALB is like having a guard inside your living room — the bad guy already got through your front gate, walked across your yard, and is at your door. WAF on CloudFront is like having the guard at the neighborhood entrance — bad traffic never even reaches your VPC. You still keep the ALB listener rules as a backup, but the heavy lifting moves to the edge.
>
> **Evaluator Question:** *What's the difference between WAFv2 scope REGIONAL vs CLOUDFRONT?*
>
> **Model Answer:** REGIONAL WAFs attach to regional resources (ALB, API Gateway, AppSync) and are created in the same region as the resource. CLOUDFRONT WAFs attach only to CloudFront distributions and must be created in us-east-1 (same "global config home" as ACM certificates). They use the same WAFv2 API but different scope parameters. A common mistake is creating a CLOUDFRONT-scope WAF in us-west-2 — it will fail because CloudFront only reads global config from us-east-1.

**Verification:**
```bash
# Confirm WAF is attached to CloudFront distribution
aws cloudfront get-distribution --id EGSYE9Z9V58UT \
  --query "Distribution.DistributionConfig.WebACLId" --output text
# Expected: arn:aws:wafv2:us-east-1:262164343754:global/webacl/chewbacca-cf-waf/...
```

---

## Step 5: CloudFront Distribution

The CloudFront distribution sits in front of the ALB, serving as the single public entry point.

> **SOCRATIC Q&A**
>
> ***Q:** What is a "custom origin" vs an "S3 origin" in CloudFront?*
>
> **A (Explain Like I'm 10):** An S3 origin is like a vending machine — CloudFront just grabs static files from a bucket. A custom origin is like a restaurant kitchen — CloudFront sends the order to your ALB/EC2, which cooks up a dynamic response. Your ALB is a custom origin because it runs application code, not just serves files. Custom origins require more configuration (protocol policy, ports, custom headers) because you're talking to a live server, not a file store.
>
> **Evaluator Question:** *Why set `origin_protocol_policy = "https-only"` for the ALB origin?*
>
> **Model Answer:** This ensures CloudFront-to-ALB traffic is encrypted in transit. Even though both are within AWS's network, "https-only" prevents accidental plaintext communication if someone misconfigures the origin. It's defense-in-depth: the viewer-to-CloudFront connection uses your ACM cert, and the CloudFront-to-origin connection uses the ALB's cert. End-to-end encryption with no plaintext hops.

---

## Step 6: Route53 DNS → CloudFront

Route53 alias records point your domain at the CloudFront distribution instead of the ALB.

> **SOCRATIC Q&A**
>
> ***Q:** Why do we need both A and AAAA records?*
>
> **A (Explain Like I'm 10):** A records are like phone numbers for the old phone system (IPv4). AAAA records are phone numbers for the new system (IPv6). Some people only have the new phone. If you don't have an AAAA record, those people can't reach you. CloudFront supports both, so you should too.
>
> **Evaluator Question:** *What's the difference between an alias record and a CNAME?*
>
> **Model Answer:** An alias record is an AWS-specific extension that maps a domain to an AWS resource (CloudFront, ALB, S3) at the DNS protocol level — it resolves directly to the resource's IP addresses without an extra DNS hop. A CNAME creates a redirect that requires a second lookup. Critically, CNAMEs cannot be used at the zone apex (naked domain like `wheresjack.com`) — only alias records can. Alias records to AWS resources are also free (no Route53 query charges), while CNAMEs cost per query.

**Terraform:**
```hcl
resource "aws_route53_record" "apex_to_cloudfront" {
  zone_id = local.chewbacca_zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apex_to_cloudfront_ipv6" {
  zone_id = local.chewbacca_zone_id
  name    = var.domain_name
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
```

**Verification:**
```bash
dig wheresjack.com A +short
# Expected: CloudFront anycast IPs (54.240.x.x range)

dig wheresjack.com AAAA +short
# Expected: CloudFront IPv6 addresses (2600:9000:... range)
```

---

## Step 7: CloudFront Access Logging

Enable CloudFront access logging to an S3 bucket for operational visibility and audit compliance.

> **SOCRATIC Q&A**
>
> ***Q:** Why does CloudFront logging need a special S3 bucket ACL?*
>
> **A (Explain Like I'm 10):** CloudFront is like a mail carrier that needs to put packages (log files) in your mailbox (S3 bucket). But the mailbox is locked! You need to give the mail carrier a key. CloudFront uses a specific AWS canonical user ID (`c4c1ede6...`) as its identity — you grant that identity FULL_CONTROL permission on your bucket. Without this, CloudFront gets "AccessDenied" when trying to write logs.
>
> **Evaluator Question:** *Why not use the standard `log-delivery-write` ACL?*
>
> **Model Answer:** The generic `log-delivery-write` ACL grants permission to the S3 log delivery group, which handles ALB and S3 access logging. CloudFront uses a different delivery mechanism with its own canonical user ID. CloudFront requires an explicit ACL grant to `c4c1ede66af53448b93c283ce9448c4ba468c9432aa01d700d3878632f77d2d0` with FULL_CONTROL. This is a common gotcha — using the wrong ACL results in a 403 error during `terraform apply`.

**Terraform:**
```hcl
resource "aws_s3_bucket" "cf_logs" {
  bucket = "${var.project_name}-cf-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_ownership_controls" "cf_logs" {
  bucket = aws_s3_bucket.cf_logs.id
  rule { object_ownership = "BucketOwnerPreferred" }
}

data "aws_canonical_user_id" "current" {}

resource "aws_s3_bucket_acl" "cf_logs" {
  depends_on = [aws_s3_bucket_ownership_controls.cf_logs]
  bucket     = aws_s3_bucket.cf_logs.id
  access_control_policy {
    owner {
      id = data.aws_canonical_user_id.current.id
    }
    grant {
      grantee {
        id   = data.aws_canonical_user_id.current.id
        type = "CanonicalUser"
      }
      permission = "FULL_CONTROL"
    }
    grant {
      grantee {
        id   = "c4c1ede66af53448b93c283ce9448c4ba468c9432aa01d700d3878632f77d2d0"
        type = "CanonicalUser"
      }
      permission = "FULL_CONTROL"
    }
  }
}
```

---

# PART 2: LAB 2B — Cache Correctness

Lab 2B configures CloudFront cache behaviors so static content is cached aggressively while API responses are never accidentally cached.

*"Most CDN outages aren't 'CloudFront is down.' They're misconfigured caching: auth/session mixups (catastrophic), stale reads after writes, and 'works in dev, breaks in prod' because headers/cookies/query strings weren't forwarded."*

---

## Step 8: Cache Policies — Static vs API

You create two cache policies with fundamentally different philosophies:

| Policy | TTL | Cookies | Headers | Query Strings | Purpose |
|--------|-----|---------|---------|---------------|---------|
| Static (aggressive) | 86400s (24h) | None | None | None | Maximum cache hits, minimum origin load |
| API (disabled) | 0 | None | None | None | Every request goes to origin, zero caching risk |

> **SOCRATIC Q&A**
>
> ***Q:** What is a "cache key" and why does it matter?*
>
> **A (Explain Like I'm 10):** A cache key is like a label on a storage box. When someone requests a file, CloudFront looks at the label to see if it already has that exact box. If the label says "GET /static/logo.png" — simple, one box fits all. But if the label says "GET /static/logo.png + Cookie:session=abc123 + User-Agent:Chrome/120" — now you need a DIFFERENT box for every user and every browser. That's called **cache fragmentation** and it destroys your hit ratio. The cache policy controls what goes on the label.
>
> **Evaluator Question:** *What happens if you accidentally include high-cardinality headers (like User-Agent) in the cache key?*
>
> **Model Answer:** Cache fragmentation explodes. There are thousands of unique User-Agent strings, so CloudFront would create thousands of separate cache entries for the same file. Your hit ratio drops to near zero, every request goes to origin, and you're paying for CloudFront without getting any caching benefit. AWS explicitly warns against this in their documentation. The fix is to whitelist only the specific headers your origin actually varies responses on.

> **SOCRATIC Q&A**
>
> ***Q:** Why is the API cache policy set to TTL=0 instead of just "don't use a cache policy"?*
>
> **A (Explain Like I'm 10):** CloudFront REQUIRES a cache policy on every behavior — you can't skip it. Setting TTL=0 is the "off switch." It means CloudFront forwards every request to origin immediately. This is the safe default for APIs because you never risk serving User A's private data to User B. It's like having a "no parking" sign — the road still exists, but nobody stops there.
>
> **Evaluator Question:** *When all TTLs are set to 0, what happens to the cache key configuration?*
>
> **Model Answer:** AWS enforces that cache key parameters must be minimal when caching is disabled. You can't set `cookie_behavior = "all"` or whitelist headers because there's no cache to key — it would be meaningless configuration. If you try, AWS returns `InvalidArgument: The parameter CookieBehavior is invalid for policy with caching disabled.` This is a built-in guardrail that prevents accidental misconfiguration.

---

## Step 9: Origin Request Policies — What Gets Forwarded

Cache policies control what CloudFront uses to identify cached objects. Origin Request Policies (ORPs) control what gets sent to the origin. **These are independent knobs.**

> **SOCRATIC Q&A**
>
> ***Q:** Wait — if I don't include a header in the cache policy, does the origin still receive it?*
>
> **A (Explain Like I'm 10):** Not automatically! That's the whole point of having TWO separate policies. The cache policy says "use these things to decide if I already have the answer." The ORP says "send these things to the kitchen when I need a fresh answer." You might want to forward `Accept` and `Content-Type` to the origin (so it knows what format to respond in) WITHOUT including them in the cache key (because the response is the same regardless). Getting this wrong is the #1 cause of CDN incidents: either the origin doesn't get headers it needs (502 errors) or the cache key includes things it shouldn't (fragmentation).
>
> **Evaluator Question:** *What breaks if the ORP doesn't forward the `Host` header to an ALB origin?*
>
> **Model Answer:** The ALB can't route the request properly — it receives a request with CloudFront's internal hostname instead of your domain name. If your ALB has host-based routing rules, they won't match. Even without explicit host rules, the ALB needs `Host` for its default routing logic. This results in a 502 Bad Gateway from CloudFront. We discovered this exact issue during Lab 2 troubleshooting — the static ORP had `header_behavior = "none"` which stripped the Host header, causing 502s on `/static/*` while `/list` worked fine (because the API ORP forwarded Host).

---

## Step 10: Response Headers Policy

The response headers policy adds headers to responses CloudFront sends back to viewers, without requiring origin changes.

> **SOCRATIC Q&A**
>
> ***Q:** Why add a response headers policy for Cache-Control instead of setting it in the Flask app?*
>
> **A (Explain Like I'm 10):** Imagine you're a movie studio sending DVDs to stores. You could stamp "Keep for 1 year" on every DVD at the factory (origin). Or you could have the shipping company stamp it during delivery (response headers policy). The second approach is better because: (1) you don't have to change the factory for different stores, (2) you can change the stamp centrally without redeploying the factory, and (3) some factories (like Flask's default) stamp "Don't keep this!" (`no-cache`) on everything. The response headers policy overrides that stamp at the edge.
>
> **Evaluator Question:** *What does `immutable` mean in `Cache-Control: public, max-age=86400, immutable`?*
>
> **Model Answer:** `immutable` tells browsers "this file will NEVER change during its max-age lifetime — don't even bother revalidating." Without `immutable`, browsers may still send conditional requests (If-None-Match/If-Modified-Since) during the TTL period, especially on page reload. With `immutable`, the browser serves from its local cache without any network request at all. Best used with fingerprinted filenames (e.g., `style.abc123.css`) where the URL changes when content changes.

---

## Step 11: Honors — Origin-Driven Caching

For the `/api/public-feed` behavior, use the AWS-managed `UseOriginCacheControlHeaders` policy instead of the custom disabled policy.

> **SOCRATIC Q&A**
>
> ***Q:** Why is origin-driven caching safer for APIs than CDN-side caching?*
>
> **A (Explain Like I'm 10):** Imagine a school cafeteria. Origin-driven caching is like letting the chef put a sticky note on each dish: "This salad is good for 4 hours" or "This sushi — eat NOW, don't save it." CDN-side caching is like the cafeteria manager saying "keep everything for 24 hours" without asking the chef. The chef knows which food spoils fast. Always trust the chef. With `UseOriginCacheControlHeaders`, your Flask app controls caching per-route: `Cache-Control: public, max-age=30` on public feeds, `no-store` on private endpoints.
>
> **Evaluator Question:** *When would you still disable caching entirely instead of using origin-driven?*
>
> **Model Answer:** (1) When the origin application doesn't set proper Cache-Control headers yet — the safe default is "don't cache" rather than "cache unpredictably." (2) During development when you need to see changes immediately. (3) When dealing with authenticated endpoints where even a few seconds of caching could leak User A's data to User B. (4) When the API response changes on every request (real-time data, personalized content).

---

# PART 3: VERIFICATION & EVIDENCE

## Lab 2A — Infrastructure Verification

```bash
# 1. CloudFront serves the application
curl -I https://wheresjack.com/list
# Expected: HTTP/2 200

# 2. Direct ALB access blocked (origin cloaking)
curl -I --max-time 10 https://chewbacca-alb01-1094761683.us-west-2.elb.amazonaws.com
# Expected: Connection timed out (PASS — SG blocks at network layer)

# 3. WAF attached to CloudFront
aws cloudfront get-distribution --id EGSYE9Z9V58UT \
  --query "Distribution.DistributionConfig.WebACLId" --output text
# Expected: arn:aws:wafv2:us-east-1:...:global/webacl/chewbacca-cf-waf/...

# 4. ALB SG has no 0.0.0.0/0, only CloudFront prefix list
aws ec2 describe-security-groups --group-ids sg-02bddb7d9e79f7d02 \
  --query "SecurityGroups[0].IpPermissions[].[IpRanges[].CidrIp, PrefixListIds[].PrefixListId]" --output text
# Expected: No CIDRs, only pl-82a045eb

# 5. DNS resolves to CloudFront
dig wheresjack.com A +short
dig wheresjack.com AAAA +short
# Expected: CloudFront IPs, not ALB IPs
```

## Lab 2B — Cache Correctness Verification

```bash
# 6. Static caching — response headers policy applies
curl -I https://wheresjack.com/static/example.txt
# Expected: HTTP/2 200, cache-control: public, max-age=86400, immutable

# 7. API no-cache — dynamic routes never cached
curl -I https://wheresjack.com/list
sleep 2
curl -I https://wheresjack.com/list
# Expected: Both show x-cache: Miss from cloudfront, no Age header

# 8. Query string sanity — static ignores query params
curl -I "https://wheresjack.com/static/example.txt?v=1"
curl -I "https://wheresjack.com/static/example.txt?v=2"
# Expected: Same etag, same content-length (same cached object)

# 9. Managed origin-driven policy on /api/public-feed
aws cloudfront get-distribution --id EGSYE9Z9V58UT \
  --query "Distribution.DistributionConfig.CacheBehaviors.Items[?PathPattern=='/api/public-feed'].CachePolicyId" --output text
# Expected: 83da9c7e-98b4-4e11-a168-04f0df8e2c65 (UseOriginCacheControlHeaders)
```

---

# PART 4: WRITTEN DELIVERABLES

## Q1: "What is my cache key for /api/* and why?"

**For the default `/api/*` behavior**, the cache key is essentially nothing — caching is disabled (all TTLs = 0). Every request goes straight to the origin.

**For `/api/public-feed`**, the cache key is determined by the AWS-managed `UseOriginCacheControlHeaders` policy. The origin (Flask) decides what's cacheable via its `Cache-Control` response header. The cache key includes only the URL path — no cookies, no query strings, no extra headers.

**Why:** Cache keys should include the *minimum* needed to uniquely identify a response. Too many things = cache fragmentation (thousands of boxes holding the same content). Too few things = cache poisoning (User A sees User B's data). For APIs, the safest default is: don't cache, or let the origin decide.

## Q2: "What am I forwarding to origin and why?"

**API ORP** forwards: `Host` (ALB routing), `Origin` (CORS), `Accept` + `Content-Type` (content negotiation), all cookies (session/auth), all query strings (pagination, filtering).

**Static ORP** forwards: `Host` only (ALB routing). Nothing else — a CSS file is the same for everyone regardless of cookies or query params.

**Key insight:** The ORP controls what reaches your server. The cache policy controls what CloudFront uses to decide "is this the same request?" They're independent knobs, and confusing them causes real production incidents.

## Q3: "Why is origin-driven caching safer for APIs?" (Honors)

The application developer knows which responses are safe to share. With origin-driven caching, Flask sends `Cache-Control: public, max-age=30` on public feeds and `no-store` on private endpoints. CloudFront obeys. With CDN-side caching, CloudFront applies the same rules to everything — it can't distinguish a public feed from a private profile page.

## Deliverable C: Haiku (漢字で、英語なし)

> 毛深き勇者
> 吠えれば星も震える
> 忠義の心

---

# PART 5: GATE SCRIPT VALIDATION

## Running the Gate Script

```bash
ORIGIN_REGION=us-west-2 \
CF_DISTRIBUTION_ID=EGSYE9Z9V58UT \
DOMAIN_NAME=wheresjack.com \
ROUTE53_ZONE_ID=Z08529463796GXWJTC93E \
ALB_ARN=arn:aws:elasticloadbalancing:us-west-2:262164343754:loadbalancer/app/chewbacca-alb01/70d5b3ab0d97d281 \
ALB_SG_ID=sg-02bddb7d9e79f7d02 \
REQUIRE_ALB_INTERNAL=false \
LOG_BUCKET=chewbacca-cf-logs-262164343754 \
./run_all_gates_lab2_alb.sh
```

## Gate Script Bug Report

The gate script returns RED with 3 failures, but **all 3 are script bugs**, not infrastructure issues:

| Gate Failure | Root Cause | CLI Proof |
|---|---|---|
| WAF WebACL not associated | Script's WAF ARN lookup is broken — uses wrong ARN format | `aws cloudfront get-distribution --id EGSYE9Z9V58UT --query "Distribution.DistributionConfig.WebACLId"` returns valid ARN |
| Route53 A alias mismatch (`cloudfront.net` vs `cloudfront.net.`) | Script does string comparison without normalizing DNS trailing dot | Trailing dot is standard DNS — all FQDNs end with `.` |
| Route53 AAAA alias mismatch | Same trailing dot issue | Same as above |

> **SOCRATIC Q&A**
>
> ***Q:** The gate script says RED/FAIL. Shouldn't I fix my infrastructure to make it pass?*
>
> **A (Explain Like I'm 10):** Imagine your teacher gives you a math test, but the answer key has a typo — it says 2+2=5. You wrote 4. Are you wrong? No! The answer key is wrong. The same thing happens in real life with monitoring tools, CI/CD pipelines, and compliance checks. Senior engineers investigate WHETHER the test is correct before changing working infrastructure. Junior engineers panic at RED and break things trying to make a bad test pass.
>
> **Evaluator Question:** *How do you handle false positives in automated validation?*
>
> **Model Answer:** First, independently verify the finding using CLI commands. If the CLI proves your infrastructure is correct, document the false positive with evidence, report the bug in the validation tool, and proceed. Never change working infrastructure to satisfy a broken test. In production, this skill is critical during incident response — dashboards and alerts have false positives too, and chasing them wastes precious time during real outages.

---

# PART 6: TROUBLESHOOTING LOG

Real issues encountered and resolved during Lab 2. Every one of these is a learning opportunity and potential interview question.

---

## Issue 1: Wrong Managed Cache Policy (CRITICAL)

**Symptom:** `/api/public-feed` behavior was using `Managed-CachingOptimized` instead of `UseOriginCacheControlHeaders`.

**The Investigation (blow-by-blow):**

1. **Found during code review.** We uploaded all `.tf` files and audited the CloudFront distribution config. The `lab2b_honors_origin_driven.tf` file referenced a data source for the managed policy, but the policy *name* was wrong — it said `Managed-CachingOptimized` where it should have said `UseOriginCacheControlHeaders`.

2. **Why is this critical and not just "cosmetic"?** `Managed-CachingOptimized` aggressively caches with a 24-hour TTL. For an API endpoint, this is a ticking time bomb: responses get cached regardless of what the origin wants, if auth is added later User A could see User B's data, and write-then-read shows stale data.

3. **Applied the fix and verified post-apply:**
   ```bash
   aws cloudfront get-distribution --id EGSYE9Z9V58UT \
     --query "Distribution.DistributionConfig.CacheBehaviors.Items[?PathPattern=='/api/public-feed'].CachePolicyId" --output text
   # Returned: 83da9c7e-98b4-4e11-a168-04f0df8e2c65 ← Correct!
   ```

**Fix:**
```hcl
data "aws_cloudfront_cache_policy" "use_origin_cache_headers" {
  name = "Managed-CachingOptimized"            # ← WRONG
  name = "UseOriginCacheControlHeaders"        # ← CORRECT
}
```

> **SOCRATIC Q&A**
>
> ***Q:** Why can't you just set TTL=0 on CachingOptimized instead of switching policies?*
>
> **A (ELI10):** CachingOptimized is like a pre-printed form — you can't change what's on it. It's an AWS *managed* policy, meaning AWS controls the settings. You can only choose which form to use, not edit the form itself. `UseOriginCacheControlHeaders` is the form that says "let the origin (your app) decide."
>
> **Evaluator Question:** *What's the difference between a cache policy and an origin request policy?*
>
> **Model Answer:** A cache policy controls what CloudFront uses to build the cache key (what makes two requests "the same" vs "different") and how long to cache. An origin request policy controls what CloudFront forwards to the origin — headers, cookies, query strings. They're independent knobs. You can cache based on zero headers while still forwarding Host and Authorization to the origin.

**Interview takeaway:** *"I discovered a cache policy misconfiguration where API responses were being aggressively cached with a 24-hour TTL. This could have caused auth token leakage between users. I replaced it with the origin-driven managed policy so the application controls caching behavior per-route."*

---

## Issue 2: ALB Security Group Open to 0.0.0.0/0 (HIGH)

**Symptom:** ALB security group had `0.0.0.0/0` ingress rules on ports 80 and 443 alongside the CloudFront prefix list rule.

**The Investigation (blow-by-blow):**

1. **We ran `terraform apply` for Fix 1 (cache policy).** The plan showed NO ALB SG changes, so we assumed Fix 2 (ALB SG lockdown) was already in place from the code review.

2. **Post-apply verification told a different story:**
   ```bash
   aws ec2 describe-security-groups --group-ids sg-02bddb7d9e79f7d02 \
     --query "SecurityGroups[0].IpPermissions[].IpRanges[].CidrIp"
   # Expected: [] (empty)
   # Actual: ["0.0.0.0/0", "0.0.0.0/0"]   ← TWO wide-open rules still in AWS!
   ```

3. **Wait — why didn't `terraform plan` catch this?** This was the real "aha" moment. We had already removed the inline `ingress` blocks from the `.tf` file. Terraform showed "no changes" because it no longer *tracked* those rules. But the rules still existed in AWS. Terraform's state and AWS reality had diverged.

4. **Root cause identified: inline vs standalone rule conflict.** The original code had `ingress {}` blocks inside `aws_security_group.alb`, AND separate `aws_security_group_rule` resources for the CloudFront prefix list. When we removed the inline blocks, Terraform stopped tracking them — but it never deleted them from AWS. They became "orphaned" rules: invisible to Terraform, visible to attackers.

5. **Manual CLI cleanup was the only option:**
   ```bash
   aws ec2 revoke-security-group-ingress --group-id sg-02bddb7d9e79f7d02 \
     --protocol tcp --port 443 --cidr 0.0.0.0/0

   aws ec2 revoke-security-group-ingress --group-id sg-02bddb7d9e79f7d02 \
     --protocol tcp --port 80 --cidr 0.0.0.0/0
   ```

6. **Collateral damage discovered:** The inline cleanup also broke the EC2 SG → ALB rule. We had to run `terraform apply -target=aws_security_group_rule.ec2_from_alb` to restore it. One fix created a second problem — this is the reality of cascading dependency chains in production infrastructure.

**Verification:**
```bash
aws ec2 describe-security-groups --group-ids sg-02bddb7d9e79f7d02 \
  --query "SecurityGroups[0].IpPermissions[].IpRanges[].CidrIp"
# Must return: [] (empty)
```

> **SOCRATIC Q&A**
>
> ***Q:** Why didn't `terraform plan` show us the `0.0.0.0/0` rules needed to be removed?*
>
> **A (ELI10):** Imagine you have a to-do list (Terraform state) and a messy room (AWS). You cross items off the list — but crossing something off doesn't clean the room. Terraform only manages what it *thinks* it owns. When you use two different methods (inline blocks + standalone rules) to manage the same security group, Terraform gets confused about what belongs to whom. The inline rules get "disowned" and become invisible orphans — still in AWS, but not on Terraform's list.
>
> **Evaluator Question:** *How do you prevent this from happening in a real production environment?*
>
> **Model Answer:** Three rules: (1) Never mix inline `ingress`/`egress` blocks with standalone `aws_security_group_rule` resources for the same security group — pick one pattern. (2) Run `terraform plan` AND independently verify with `aws ec2 describe-security-groups` before declaring a change complete. Terraform's plan is necessary but not sufficient. (3) Use `terraform import` to bring orphaned resources back under management, or clean them via CLI and document the drift.

**Interview takeaway:** *"I found that our ALB security group had 0.0.0.0/0 rules that Terraform wasn't managing due to inline vs standalone rule conflicts. This effectively made origin cloaking decorative — anyone could bypass CloudFront and hit the ALB directly, skipping WAF entirely. I revoked the rules via CLI, restored a broken EC2→ALB rule that was collateral damage, and standardized on standalone rules to prevent recurrence."*

---

## Issue 3: AWS Cache Policy Guardrails (MEDIUM → Resolved by AWS)

**Symptom:** Attempted to harden the API disabled cache policy (TTL=0) by adding cookies, headers, and encoding — AWS rejected with `InvalidArgument`.

**The Investigation (blow-by-blow):**

1. **We identified the API cache policy (`api_disabled`) as too permissive** during the code review. With `cookie_behavior = "none"`, `header_behavior = "none"`, and encoding disabled, it was leaving attack surface on the table. Plan: add `cookie_behavior = "all"`, whitelist `Authorization` and `Host` headers, enable encoding.

2. **First attempt — edited the wrong resource block.** During the apply, `terraform plan` revealed we'd accidentally changed `cookie_behavior` on the *static* cache policy too. Caught before apply — lesson: when a .tf file has multiple similar-looking resource blocks, double-check which one you edited.

3. **Second attempt — AWS rejected the header whitelist:**
   ```
   InvalidArgument: The parameter HeaderBehavior is invalid for policy with caching disabled.
   ```
   When all TTLs = 0, AWS won't let you configure cache key parameters because there IS no cache. A cache key is meaningless if nothing gets cached.

4. **Pivoted: move `Authorization` to the Origin Request Policy instead.** This achieves the same goal (auth headers reach the origin) via a different mechanism.

5. **Third attempt — AWS rejected Authorization in the ORP too:**
   ```
   InvalidArgument: The Authorization header is not supported in origin request policies.
   ```
   CloudFront treats `Authorization` specially — it always forwards it when present in the viewer request. You don't need to (and can't) add it to an ORP.

6. **Final resolution: No fix needed.** AWS's built-in guardrails prevent exactly the misconfiguration we were concerned about. If caching gets enabled later, AWS forces you to reconfigure these settings. And `Authorization` is handled automatically.

> **SOCRATIC Q&A**
>
> ***Q:** If TTL=0 means "don't cache," why does CloudFront even allow a cache policy on that behavior?*
>
> **A (ELI10):** Think of it like a thermostat set to "OFF" — you can still see the thermostat on the wall, and you still need it there in case you turn heating on later. The cache policy is the configuration that's *ready* for when someone enables caching. AWS just won't let you set contradictory values (like "don't cache, but use these cache keys").
>
> **Evaluator Question:** *Why does CloudFront handle the Authorization header differently from other headers?*
>
> **Model Answer:** Authorization headers contain credentials (tokens, API keys). CloudFront has special logic: if the viewer sends an `Authorization` header, CloudFront always forwards it to origin and never caches that response (unless the origin explicitly says it's OK via `Cache-Control: public`). This prevents credential leakage through the cache. You can't add it to an ORP because CloudFront manages its forwarding internally.

**Interview takeaway:** *"I learned that AWS enforces immutable cache key parameters when caching is disabled, which is actually a smart guardrail. I also discovered that the Authorization header has special handling in CloudFront — it can't be added to Origin Request Policies because CloudFront manages its forwarding behavior internally to prevent credential leakage."*

---

## Issue 4: Static ORP Missing Host Header — 502 Errors (HIGH)

**Symptom:** `/list` worked through CloudFront, but `/static/example.txt` returned 502 Bad Gateway.

**The Investigation (blow-by-blow):**

1. **We created a test file on EC2** via SSM (`echo "Hello from static" > /opt/app/static/example.txt`) to test static caching behavior. First curl to CloudFront: 502.

2. **Isolated the problem layer.** SSM'd into the EC2 and tested locally:
   ```bash
   curl -I http://localhost:80/static/example.txt
   # HTTP/1.1 200 OK ← Flask serves it fine!
   ```
   So the app works, the file exists. The problem is between CloudFront and the ALB.

3. **Compared the working path vs broken path.** `/list` works (hits default behavior) but `/static/*` doesn't (hits static behavior). Both point to the same ALB origin (`chewbacca-alb-origin`). What's different?

4. **Pulled the cache behavior configs:**
   ```bash
   aws cloudfront get-distribution --id EGSYE9Z9V58UT \
     --query "Distribution.DistributionConfig.CacheBehaviors.Items[*].[PathPattern,OriginRequestPolicyId]" --output table
   ```
   Static behavior uses ORP `b2c62266...` (chewbacca-orp-static), default uses `45ed12fc...` (chewbacca-orp-api).

5. **Inspected both ORPs — found the smoking gun:**
   ```bash
   # Static ORP:
   aws cloudfront get-origin-request-policy --id b2c62266... --query "...HeadersConfig"
   # Result: HeaderBehavior: "none"   ← Forwards NOTHING

   # API ORP:
   aws cloudfront get-origin-request-policy --id 45ed12fc... --query "...HeadersConfig"
   # Result: HeaderBehavior: "whitelist", Items: ["Content-Type", "Origin", "Host", "Accept"]
   ```
   The API ORP forwards `Host`. The static ORP forwards **nothing**. Without `Host`, the ALB can't route the request.

6. **Tried direct ALB test to confirm theory — but origin cloaking blocked us:**
   ```bash
   curl -I https://chewbacca-alb01-....elb.amazonaws.com/static/example.txt -k
   # Connection timeout ← SG correctly blocks direct access
   ```
   Good news: origin cloaking works! Bad news: can't test the ALB in isolation.

7. **Applied the fix — added Host to static ORP:**
   ```hcl
   headers_config {
     header_behavior = "whitelist"
     headers {
       items = ["Host"]
     }
   }
   ```

8. **Post-apply test: 200!** But then a new problem surfaced — see Issue 7.

> **SOCRATIC Q&A**
>
> ***Q:** CloudFront adds the secret origin header (`X-Chewbacca-Growl`) automatically via the origin config. Why didn't the ALB just accept the request based on that header alone?*
>
> **A (ELI10):** The secret header is like a password to get INTO the building. But once inside, you still need to tell the receptionist (ALB) which floor (Host) you want. The password got you past the door, but the receptionist can't route you without knowing the destination. Without `Host`, the ALB returns a 502 because it literally doesn't know which target group to forward to.
>
> **Evaluator Question:** *If the static ORP forwards no headers, what does CloudFront use as the Host header when connecting to the ALB?*
>
> **Model Answer:** CloudFront sends the origin domain name (the ALB's DNS name) as the Host header. But the ALB listener rules may be expecting the viewer's Host header (`wheresjack.com`), not the ALB's DNS name. The mismatch causes routing failures. The ORP's `whitelist` with `Host` tells CloudFront to forward the viewer's original Host header instead.

**Interview takeaway:** *"I debugged a 502 error on our static content path that was caused by the Origin Request Policy stripping the Host header. The API path worked because its ORP forwarded Host, but the static ORP was set to forward nothing. I isolated the issue by testing locally on EC2 (200), comparing ORP configs side-by-side, and identifying that the Host header was the only meaningful difference. This taught me that cache policies and origin request policies are independent — you can have zero headers in the cache key while still forwarding Host to the origin."*

---

## Issue 5: CloudFront Logging ACL Mismatch (403)

**Symptom:** `terraform apply` failed with `AccessDenied: You don't have permission to access the S3 bucket for CloudFront logs`.

**The Investigation (blow-by-blow):**

1. **Gate script flagged "CloudFront logging not enabled."** This was a real finding (unlike the WAF false positive), so we added logging config to the CloudFront distribution.

2. **Created the S3 bucket with `acl = "log-delivery-write"`** — the same ACL pattern that works for ALB access logs. Seemed logical.

3. **Apply failed with AccessDenied.** The error message said CloudFront couldn't deliver logs to the bucket. We checked bucket policies, IAM — nothing wrong there.

4. **Root cause: CloudFront uses a DIFFERENT delivery mechanism than ALB.** ALB logs use the ELB service account (an AWS-managed IAM role). CloudFront logs use a *canonical user ID* — a legacy S3 identity system predating IAM. The generic `log-delivery-write` ACL only covers the S3 log delivery group, not CloudFront's canonical user.

5. **Fix: Explicit ACL with CloudFront's canonical user ID:**
   ```hcl
   grant {
     grantee {
       id   = "c4c1ede66af53448b93c283ce9448c4ba468c9432aa01d700d3878632f77d2d0"
       type = "CanonicalUser"
     }
     permission = "FULL_CONTROL"
   }
   ```

> **SOCRATIC Q&A**
>
> ***Q:** Why does CloudFront use a canonical user ID instead of an IAM role like every other AWS service?*
>
> **A (ELI10):** CloudFront is one of the oldest AWS services — it existed before IAM was fully mature. The canonical user ID system is like a library card number from the old days before everyone got digital IDs. AWS kept it for backward compatibility. This is a "legacy artifact" pattern you'll see throughout AWS — newer services use IAM roles, older ones have quirks.
>
> **Evaluator Question:** *You used `log-delivery-write` for ALB logs in Lab 1. Why did it work there but not here?*
>
> **Model Answer:** ALB access logs are delivered by the Elastic Load Balancing service principal, which has its own pre-defined S3 bucket policy pattern using the ELB account ID for your region. CloudFront standard logs are delivered via an S3 ACL grant to CloudFront's canonical user ID. They're completely different delivery pipelines that happen to both write to S3.

**Interview takeaway:** *"CloudFront logging uses a different S3 delivery mechanism than ALB access logs. ALB uses the ELB service account, CloudFront uses a canonical user ID. The generic log-delivery-write ACL doesn't cover CloudFront. This is a common production gotcha when enabling logging across multiple AWS services."*

---

## Issue 6: Terraform State Lock — Ctrl+Z vs Ctrl+C

**Symptom:** `terraform apply` failed with `resource temporarily unavailable` — state file locked.

**What went wrong:** Hit `Ctrl+Z` during `terraform apply`, which suspends the process without releasing the state lock. The lock file (`.terraform.tfstate.lock.info`) remained orphaned.

**Fix:**
```bash
ps aux | grep terraform     # Find suspended PID
kill -9 <PID>               # Kill the process
rm -f .terraform.tfstate.lock.info  # Remove orphaned lock
```

> **SOCRATIC Q&A**
>
> ***Q:** Why does Terraform even have a state lock?*
>
> **A (ELI10):** Imagine two kids trying to rearrange the same Lego set at the same time — one adds a piece, the other removes a piece, and the whole thing falls apart. The state lock is like a "building in progress" sign that says "only one builder at a time." In production, multiple CI/CD pipelines or team members might run `terraform apply` simultaneously. The lock prevents them from corrupting the state file with overlapping changes.
>
> **Evaluator Question:** *What's the difference between SIGINT (Ctrl+C) and SIGTSTP (Ctrl+Z), and why does it matter for Terraform?*
>
> **Model Answer:** `Ctrl+C` sends SIGINT — a graceful termination signal. Terraform catches it, releases the state lock, and rolls back cleanly. `Ctrl+Z` sends SIGTSTP — a suspend signal that pauses the process in place. The process is still alive (just sleeping), so it never releases the lock. When you later try to run Terraform again, it sees the lock held by a zombie process. The fix is `kill -9` (force kill) then remove the orphaned `.terraform.tfstate.lock.info` file.

---

## Issue 7: Flask Origin Sends `Cache-Control: no-cache` — Persistent Misses

**Symptom:** After fixing the 502 (Issue 4), static files returned 200 but `x-cache: Miss from cloudfront` on EVERY request — even after waiting between requests.

**The Investigation (blow-by-blow):**

1. **ORP fix confirmed working — 200 instead of 502.** But both requests showed `Miss from cloudfront` with no `Age` header. Caching wasn't happening at all.

2. **First hypothesis: min_ttl too low.** The static cache policy had `min_ttl = 0`. Changed it to `min_ttl = 1`. Applied, waited for `Deployed` status. Tested again — still all Misses.

3. **Second hypothesis: hitting different edge nodes.** The `via` header showed different CloudFront edge IDs on each request (e.g., `032e70899d...` vs `80ea9b66f...`), all within the same POP (`MIA50-P7`). Ran 5 requests in a loop:
   ```bash
   for i in 1 2 3 4 5; do
     curl -sI https://wheresjack.com/static/example.txt | grep -i "x-cache\|age:"
     sleep 2
   done
   # All 5: Miss from cloudfront
   ```
   Even with `min_ttl = 1`, with 2-second sleep, the 1-second cache had already expired. Bumped to `min_ttl = 60`. Applied, waited for Deployed. Tested again — **still all Misses.**

4. **Third hypothesis (correct): Flask sends `Cache-Control: no-cache`.** We'd seen this earlier when testing locally on EC2:
   ```
   cache-control: no-cache
   ```
   The key insight: `min_ttl` only overrides `max-age` values. It does NOT override `no-cache` or `no-store` directives. `no-cache` means "you may store this, but MUST revalidate with origin before serving." So CloudFront stores it but contacts the origin on every request — which always shows as a `Miss`.

5. **Two options presented:**
   - **Option A:** SSM into EC2 and configure Flask to send proper headers (`app.config['SEND_FILE_MAX_AGE_DEFAULT'] = 86400`)
   - **Option B:** Accept as-is. The *response headers policy* correctly adds `Cache-Control: public, max-age=86400, immutable` to what the **viewer** sees. So browsers still cache for 24 hours.

6. **Chose Option B.** The CloudFront-to-origin Misses don't affect viewers — browsers see the response headers policy override and cache locally. Lab 3 doesn't depend on this, so no need to modify the Flask app.

> **SOCRATIC Q&A**
>
> ***Q:** If `min_ttl` doesn't override `no-cache`, what's it actually for?*
>
> **A (ELI10):** Imagine a restaurant where the kitchen (origin) puts an expiration sticker on each dish. `min_ttl` is like the restaurant manager saying "even if the kitchen says this dish expires in 5 minutes, keep it for at least 60 minutes." That works when the kitchen says `max-age=300` (5 minutes) — the manager overrides it to 60 minutes. But `no-cache` is different — it's the kitchen saying "ALWAYS check with me before serving, even if the dish looks fine." The manager can't override a direct "always check" order.
>
> ***Q:** What's the difference between edge caching and browser caching?*
>
> **A (ELI10):** Think of a library system. The **central library** (origin/EC2) has the original book. The **branch library** (CloudFront edge) keeps copies so people don't have to drive downtown every time. The **bookshelf at home** (browser cache) is your personal copy. In our case, the branch library (CloudFront) goes back to the central library on every request (`no-cache`), but it still tells you (the browser) "keep this copy for 24 hours" (response headers policy). So your home bookshelf works even though the branch library is inefficient.
>
> **Evaluator Question:** *You said the response headers policy adds `max-age=86400` for the viewer. Doesn't that contradict the origin's `no-cache`?*
>
> **Model Answer:** No contradiction — they operate at different layers. The response headers policy overrides what CloudFront sends *to the viewer*. The origin's `no-cache` controls what CloudFront does *internally* (always revalidate). CloudFront is effectively saying: "I'm going to check with the origin every time (honoring no-cache), but I'm telling the browser to keep its copy for 24 hours (response headers policy)." The viewer benefits from browser caching even though the edge doesn't cache.

**Interview takeaway:** *"I discovered that CloudFront's min_ttl doesn't override origin no-cache directives — a common misconception. The solution is either fixing the origin's Cache-Control headers or using a response headers policy for viewer-side caching. Understanding the difference between edge caching (CloudFront stores) and browser caching (viewer stores) is critical for CDN architecture."*

---

## Issue 8: Gate Script Bugs — Trailing Dot & WAF ARN

**Symptom:** Gate script returned RED with 4 failures despite correct infrastructure.

**The Investigation (blow-by-blow):**

1. **Ran the gate script.** RED badge, 4 failures. Initial reaction: "What did we break?"

2. **Triaged each failure independently with AWS CLI:**

   - **"WAF not associated"** — We verified it WAS associated:
     ```bash
     aws cloudfront get-distribution --id EGSYE9Z9V58UT \
       --query "Distribution.DistributionConfig.WebACLId" --output text
     # Returns: arn:aws:wafv2:us-east-1:262164343754:global/webacl/chewbacca-cf-waf/...
     ```
     **Script bug:** The WAF check used `wafv2 get-web-acl-for-resource`, which requires a specific ARN format for CloudFront distributions. The script constructed the ARN incorrectly.

   - **"Route53 A alias mismatch"** — We verified the alias was correct:
     ```bash
     aws route53 list-resource-record-sets --hosted-zone-id Z08529463796GXWJTC93E \
       --query "ResourceRecordSets[?Type=='A'].AliasTarget.DNSName" --output text
     # Returns: dilw2rrp8jl8g.cloudfront.net.   ← Note the trailing dot!
     ```
     **Script bug:** The script expected `dilw2rrp8jl8g.cloudfront.net` but Route53 returns `dilw2rrp8jl8g.cloudfront.net.` with a trailing dot (per DNS RFC 1035, all FQDNs end with a dot representing the root zone). The script did no normalization before string comparison.

   - **"AAAA record missing"** and **"Logging not enabled"** — These were **real** findings. We fixed both (see earlier sections).

3. **Pedagogical insight:** The instructor DELIBERATELY included these bugs to teach "debug the debugger." In production, monitoring dashboards, alerting systems, and CI/CD gates all have bugs. An engineer who blindly trusts a RED badge wastes time "fixing" working infrastructure. An engineer who independently verifies understands the difference between infrastructure problems and tooling problems.

> **SOCRATIC Q&A**
>
> ***Q:** Why does Route53 return FQDNs with a trailing dot?*
>
> **A (ELI10):** In the phone book of the internet (DNS), every name has a "last name" — the root zone, represented by a dot. `wheresjack.com.` is the full name. `wheresjack.com` without the dot is a shortcut that your computer adds the dot to automatically. Route53 always gives the full formal name. It's like how your birth certificate says "John Michael Smith" but everyone calls you "John." Both are correct — the script just didn't know how to handle the formal version.
>
> **Evaluator Question:** *A CI/CD gate reports FAIL on your infrastructure deployment. How do you determine if it's a real failure or a false positive?*
>
> **Model Answer:** Three-step process: (1) Read the failure message carefully — what exactly is it checking and what did it expect vs what it found? (2) Independently verify the claim using the AWS CLI or console — don't trust the gate's interpretation, verify the underlying data yourself. (3) If your independent check contradicts the gate, read the gate's source code to find the bug. Document both the false positive and the CLI evidence that proves your infrastructure is correct. This skill transfers directly to production incident response where dashboards and alerts have false positives too.

**Interview takeaway:** *"The automated validation tool returned RED, but I independently verified each failure with AWS CLI and found that 2 of 4 were script bugs — a DNS trailing dot normalization issue and an incorrect WAF ARN construction. I fixed the 2 real issues (AAAA record, logging) and documented the false positives with CLI proof. This taught me to always verify automated findings independently before acting on them."*

---

# Evidence Summary

| Test | Result | Status |
|------|--------|--------|
| CloudFront serves application (`/list`) | HTTP/2 200 | ✅ |
| Direct ALB access blocked | Connection timeout | ✅ |
| WAF attached to CloudFront | ARN returned | ✅ |
| ALB SG locked to CloudFront prefix list | No `0.0.0.0/0` | ✅ |
| Static response headers policy | `cache-control: public, max-age=86400, immutable` | ✅ |
| API no-cache (dynamic routes) | `Miss from cloudfront`, no `Age` header | ✅ |
| Query string sanity | Same etag for `?v=1` and `?v=2` | ✅ |
| Managed origin-driven policy | `83da9c7e-98b4-4e11-a168-04f0df8e2c65` | ✅ |
| Route53 A record → CloudFront | CloudFront IPs | ✅ |
| Route53 AAAA record → CloudFront | CloudFront IPv6 | ✅ |
| CloudFront logging enabled | S3 bucket `chewbacca-cf-logs-262164343754` | ✅ |

---

## How to Talk About This in an Interview

*"I built a production-grade edge security architecture with CloudFront origin cloaking, defense-in-depth header validation, and intelligent cache policies that prevent auth token leakage. During the process, I identified and fixed a critical cache policy misconfiguration, debugged a 502 caused by missing Host header forwarding, discovered AWS's built-in guardrails for disabled cache policies, and learned that CloudFront's min_ttl doesn't override no-cache directives. I also found and documented bugs in the automated validation tooling, proving that independent CLI verification skills are essential."*

**That answer demonstrates:** troubleshooting depth, security awareness, caching expertise, and the maturity to question automated tools.

---

## What This Lab Proves About You

*If you completed this lab, you can confidently say:*

**"I can design and debug CDN architectures that protect origins, enforce WAF at the edge, and prevent cache-related security incidents."**

*Most engineers "add CloudFront" and call it done. You understand cache key composition, origin request policy separation, defense-in-depth origin cloaking, and why automated tests aren't always right.*
