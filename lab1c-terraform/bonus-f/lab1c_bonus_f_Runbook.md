
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