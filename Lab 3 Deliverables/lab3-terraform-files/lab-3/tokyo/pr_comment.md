### SEIR Lab 2 (ALB Origin) Gate Result: **RED** (FAIL)

**Domain:** `wheresjack.com`  
**CloudFront:** `EGSYE9Z9V58UT` → `dilw2rrp8jl8g.cloudfront.net`  
**ALB:** `arn:aws:elasticloadbalancing:us-west-2:262164343754:loadbalancer/app/chewbacca-alb01/70d5b3ab0d97d281` (scheme=`internet-facing`)  
**ALB SG:** `sg-02bddb7d9e79f7d02`  

**Failures (fix in order)**
- FAIL: WAF WebACL not associated with CloudFront.
- FAIL: Route53 A alias target mismatch (expected=dilw2rrp8jl8g.cloudfront.net actual=dilw2rrp8jl8g.cloudfront.net.).
- FAIL: Route53 AAAA alias target mismatch (expected=dilw2rrp8jl8g.cloudfront.net actual=dilw2rrp8jl8g.cloudfront.net.).

**Warnings**
- WARN: ALB internal requirement disabled; public ALB weakens 'CloudFront-only' guarantee.

> Reminder: If the ALB is public or world-open, CloudFront is decorative, not protective.
