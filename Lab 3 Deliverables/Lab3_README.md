# SEIR FOUNDATIONS

## LAB 3: Japan Medical Cross-Region Architecture

*Enhanced Socratic Q&A Guide with Step-by-Step Instructions*

> **⚠️ PREREQUISITE**
>
> Lab 2 must be completed and verified before starting Lab 3. You must have: CloudFront distribution, WAF with CLOUDFRONT scope, Route53 hosted zone, working EC2→RDS application with origin cloaking.

---

## Lab Overview

Lab 3 implements a cross-region medical architecture that complies with Japan's APPI (Act on the Protection of Personal Information) data residency requirements. A Japanese medical organization operates a primary system in Tokyo and a satellite office in São Paulo, with strict legal requirements that all patient data remains physically stored in Japan.

> **🔑 THE KEY PRINCIPLE**
>
> Global access does not require global storage. Access is allowed. Storage is not. This single sentence is the heart of modern regulated cloud architecture.

---

## Target Architecture

```
🇯🇵 Tokyo (ap-northeast-1)                    🇧🇷 São Paulo (sa-east-1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━               ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[RDS MySQL - PHI Storage]                      [EC2 - Stateless Compute Only]

[EC2 - App Tier]                               [ALB - Load Balancer]

[Transit Gateway Hub] ←──────────────────────→ [Transit Gateway Spoke]
         ↑                                              ↑
         └──────────────── TGW Peering ─────────────────┘

         ↓
    [CloudFront]
         ↓
  chewbacca-growls.com
```

---

## Legal Reality → Architectural Consequence

| Component | Allowed Location | Why? |
|-----------|-----------------|------|
| RDS (Medical Records) | Tokyo ONLY (ap-northeast-1) | PHI must remain in Japan |
| Backups / Snapshots | Tokyo ONLY | Data at rest = Japan only |
| Read Replicas | ❌ NOT ALLOWED outside Japan | Replication = storage violation |
| App Access | ✅ Allowed globally | Access ≠ storage |
| CloudFront | ✅ Allowed (edge, no PHI) | No persistence of medical data |
| EC2 in São Paulo | ✅ Allowed (stateless only) | Compute only, no local DB |

> **SOCRATIC Q&A**
>
> ***Q:** Why can't we just put an RDS read replica in São Paulo to make the app faster for doctors there?*
>
> **A (Explain Like I'm 10):** Imagine you have a secret diary (medical records). Your mom says "you can SHOW pages to your friends anywhere, but the diary STAYS in your room." If you photocopied the diary and left copies at your friend's house in another country, you'd be breaking the rule — even if the copies are "just for reading." A read replica IS a copy of the data. Japan's law says the data itself cannot leave Japan, period.
>
> **Evaluator Question:** *What's the difference between 'data access' and 'data storage' in the context of APPI compliance?*
>
> **Model Answer:** Data access means a user or system can READ/WRITE data that remains stored in Japan. The request travels to Japan, touches the data there, and returns. Data storage means the data physically exists on disk in that location. APPI restricts storage, not access. A doctor in São Paulo accessing Tokyo RDS = legal. A read replica storing data in São Paulo = compliance violation.

---

## What Changes from Lab 2

| Action | Tokyo (ap-northeast-1) | São Paulo (sa-east-1) |
|--------|----------------------|---------------------|
| ✅ Keep | RDS, VPC, EC2, ALB, WAF, CloudFront | N/A (new region) |
| 🆕 Add | Transit Gateway Hub | Transit Gateway Spoke |
| 🆕 Add | TGW VPC Attachment | TGW VPC Attachment |
| 🆕 Add | TGW Peering Request | TGW Peering Accept |
| 🆕 Add | Routes to São Paulo CIDR | Routes to Tokyo CIDR |
| 🆕 Add | RDS SG allows São Paulo CIDR | New VPC (Lab 2 structure, NO DB) |

---

## PART 1: LAB 3A — Transit Gateway Between Tokyo + São Paulo

Transit Gateway creates a controlled data corridor between regions. Tokyo is the hub (data authority), São Paulo is the spoke (stateless compute).

> **⚠️ KEY REALITY CHECK**
>
> Transit Gateway is REGIONAL. You don't "attach São Paulo VPC to Tokyo TGW" directly. You create: (1) TGW in Tokyo, (2) TGW in São Paulo, (3) TGW Peering between them. Each VPC attaches to its LOCAL TGW. Routes propagate across the peering.

> **SOCRATIC Q&A**
>
> ***Q:** Why can't we just use VPC Peering instead of Transit Gateway?*
>
> **A (Explain Like I'm 10):** VPC Peering is like connecting two tin cans with a string — it works for 2 cans, but if you add 10 more friends, you need a string between EVERY pair (that's 66 strings!). Transit Gateway is like a telephone switchboard — everyone connects to ONE central hub, and the hub routes calls between them. For 2 regions it works either way, but TGW gives you: centralized route management, route tables you can audit, and the ability to add more regions without re-wiring everything.
>
> **Evaluator Question:** *When would VPC Peering be the better choice over Transit Gateway?*
>
> **Model Answer:** VPC Peering is simpler and cheaper for connecting just 2 VPCs that need direct communication. It has lower latency (no hub hop) and no hourly TGW charge. Choose VPC Peering for simple 2-VPC setups. Choose TGW when you need centralized routing, multiple VPCs, route table control, or auditability — which is exactly what regulated architectures require.

---

### Step 1: Create Tokyo Transit Gateway (Hub)

Tokyo TGW is the hub — it owns the data authority and initiates the peering request.

**Action:** Create `tokyo_tgw.tf`:

```hcl
# Shinjuku is Tokyo's transit hub — all data corridors originate here.
resource "aws_ec2_transit_gateway" "shinjuku_tgw01" {
  description = "shinjuku-tgw01 (Tokyo hub)"

  tags = {
    Name = "shinjuku-tgw01"
  }
}

# Shinjuku connects to Tokyo's VPC — the vault door opens inward.
resource "aws_ec2_transit_gateway_vpc_attachment" "shinjuku_attach_tokyo_vpc01" {
  transit_gateway_id = aws_ec2_transit_gateway.shinjuku_tgw01.id
  vpc_id             = aws_vpc.main.id

  subnet_ids = [
    aws_subnet.chewbacca_private_subnet01.id,
    aws_subnet.chewbacca_private_subnet02.id
  ]

  tags = {
    Name = "shinjuku-attach-tokyo-vpc01"
  }
}

# Shinjuku opens a corridor request to Liberdade — compute may travel, data may not.
resource "aws_ec2_transit_gateway_peering_attachment" "shinjuku_to_liberdade_peer01" {
  transit_gateway_id      = aws_ec2_transit_gateway.shinjuku_tgw01.id
  peer_region             = "sa-east-1"
  peer_transit_gateway_id = aws_ec2_transit_gateway.liberdade_tgw01.id

  tags = {
    Name = "shinjuku-to-liberdade-peer01"
  }
}
```

> **SOCRATIC Q&A**
>
> ***Q:** Why do we attach the TGW to private subnets specifically?*
>
> **A (Explain Like I'm 10):** Your medical records vault (RDS) is in a private room with no windows to the street. The Transit Gateway is like a secure internal hallway — it connects rooms INSIDE the building, not to the outside world. Attaching to private subnets means the TGW traffic stays internal. Public subnets are for things that need street-facing doors (like the ALB).
>
> **Evaluator Question:** *What does the peering attachment represent architecturally?*
>
> **Model Answer:** The peering attachment creates a "request to connect" from Tokyo TGW to São Paulo TGW. It's like sending a formal invitation: "Tokyo data authority invites São Paulo compute to connect via controlled corridor." São Paulo must explicitly ACCEPT this invitation (next step). This two-way handshake ensures both sides consent to the connection.

---

### Step 2: Create São Paulo Transit Gateway (Spoke)

São Paulo TGW is the spoke — it accepts the peering from Tokyo and provides the local endpoint for compute resources.

**Action:** Create `sao_paulo_tgw.tf`:

```hcl
# Liberdade is São Paulo's Japanese town — local doctors, local compute, remote data.
resource "aws_ec2_transit_gateway" "liberdade_tgw01" {
  provider    = aws.saopaulo
  description = "liberdade-tgw01 (Sao Paulo spoke)"

  tags = {
    Name = "liberdade-tgw01"
  }
}

# Liberdade accepts the corridor from Shinjuku — permissions are explicit, not assumed.
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "liberdade_accept_peer01" {
  provider                      = aws.saopaulo
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.shinjuku_to_liberdade_peer01.id

  tags = {
    Name = "liberdade-accept-peer01"
  }
}

# Liberdade attaches to its VPC — compute can now reach Tokyo legally.
resource "aws_ec2_transit_gateway_vpc_attachment" "liberdade_attach_sp_vpc01" {
  provider           = aws.saopaulo
  transit_gateway_id = aws_ec2_transit_gateway.liberdade_tgw01.id
  vpc_id             = aws_vpc.liberdade_vpc01.id

  subnet_ids = [
    aws_subnet.liberdade_private_subnet01.id,
    aws_subnet.liberdade_private_subnet02.id
  ]

  tags = {
    Name = "liberdade-attach-sp-vpc01"
  }
}
```

> **SOCRATIC Q&A**
>
> ***Q:** Why does São Paulo need to "accept" the peering? Why can't Tokyo just connect?*
>
> **A (Explain Like I'm 10):** Imagine someone wants to build a door from their house to yours. Even if they build their half of the door, it doesn't work until YOU agree and build your half! The accepter resource is São Paulo saying "Yes, I agree to this connection." Without acceptance, there's no connection — this prevents unauthorized regions from forcing their way into your network.
>
> **Evaluator Question:** *Notice that every São Paulo resource has `provider = aws.saopaulo`. What happens if you forget this?*
>
> **Model Answer:** If you forget the provider, Terraform uses the default (Tokyo). You'd accidentally create the resource in Tokyo instead of São Paulo! This would break the architecture and potentially create compliance issues. The explicit provider requirement is a safety mechanism — it forces you to consciously decide where each resource belongs.

---

### Step 3: Configure Cross-Region Routes

Routes tell each VPC how to reach the other region. Without routes, traffic doesn't know where to go.

> **⚠️ CRITICAL**
>
> Routes are the "it works or it doesn't" part. If routes are wrong, São Paulo can't reach Tokyo RDS. Both regions need routes pointing to each other through the TGW.

**Action:** Create `tokyo_routes.tf`:

```hcl
# Shinjuku returns traffic to Liberdade — doctors need answers, not one-way tunnels.
resource "aws_route" "shinjuku_to_sp_route01" {
  route_table_id         = aws_route_table.chewbacca_private_rt01.id
  destination_cidr_block = "10.1.0.0/16"  # São Paulo VPC CIDR
  transit_gateway_id     = aws_ec2_transit_gateway.shinjuku_tgw01.id
}
```

**Action:** Create `sao_paulo_routes.tf`:

```hcl
# Liberdade knows the way to Shinjuku — Tokyo CIDR routes through TGW corridor.
resource "aws_route" "liberdade_to_tokyo_route01" {
  provider               = aws.saopaulo
  route_table_id         = aws_route_table.liberdade_private_rt01.id
  destination_cidr_block = "10.0.0.0/16"  # Tokyo VPC CIDR
  transit_gateway_id     = aws_ec2_transit_gateway.liberdade_tgw01.id
}
```

> **SOCRATIC Q&A**
>
> ***Q:** Why do we need routes in BOTH directions? Can't we just route São Paulo → Tokyo?*
>
> **A (Explain Like I'm 10):** If you send a letter to your friend but they don't know your address, they can't write back! The São Paulo → Tokyo route says "send database requests this way." The Tokyo → São Paulo route says "send the answers back this way." Without both, the request arrives but the response has nowhere to go — it's a one-way street.
>
> **Evaluator Question:** *What's the difference between VPC route tables and TGW route tables?*
>
> **Model Answer:** VPC route tables tell traffic WHERE to go — "send 10.0.0.0/16 to the TGW." TGW route tables tell the TGW HOW to forward that traffic once it arrives — "traffic for 10.0.0.0/16 goes across the peering attachment." You need both. VPC routes are the on-ramp. TGW routes are the highway map. Missing either one = blackholed traffic.

---

### Step 4: Add TGW Route Table Static Routes

> **⚠️ THIS IS THE STEP MOST PEOPLE MISS**
>
> VPC route tables point traffic TO the TGW. But the TGW itself needs routes to know where to FORWARD that traffic. VPC attachments auto-propagate. **Peering attachments do NOT.** You must add static routes manually.

**Action:** Get TGW route table IDs for both regions:

```bash
# Tokyo TGW route table
aws ec2 describe-transit-gateway-route-tables --region us-west-2 \
  --filters "Name=transit-gateway-id,Values=<TOKYO_TGW_ID>" \
  --query "TransitGatewayRouteTables[0].TransitGatewayRouteTableId" \
  --output text

# São Paulo TGW route table
aws ec2 describe-transit-gateway-route-tables --region sa-east-1 \
  --filters "Name=transit-gateway-id,Values=<SP_TGW_ID>" \
  --query "TransitGatewayRouteTables[0].TransitGatewayRouteTableId" \
  --output text
```

**Action:** Add static routes in both TGW route tables:

```bash
# Tokyo TGW: "traffic for São Paulo goes across the peering"
aws ec2 create-transit-gateway-route --region us-west-2 \
  --transit-gateway-route-table-id <TOKYO_TGW_RTB_ID> \
  --destination-cidr-block "10.1.0.0/16" \
  --transit-gateway-attachment-id <PEERING_ATTACHMENT_ID>

# São Paulo TGW: "traffic for Tokyo goes across the peering"
aws ec2 create-transit-gateway-route --region sa-east-1 \
  --transit-gateway-route-table-id <SP_TGW_RTB_ID> \
  --destination-cidr-block "10.0.0.0/16" \
  --transit-gateway-attachment-id <PEERING_ATTACHMENT_ID>
```

> **SOCRATIC Q&A**
>
> ***Q:** Why don't TGW peering attachments propagate routes automatically like VPC attachments do?*
>
> **A (Explain Like I'm 10):** When you connect two train stations with a new rail line, the trains don't automatically know to use it. Someone has to update the schedule board at each station: "Trains to Tokyo → use Track 5 (the peering line)." VPC attachments propagate routes by default, but peering attachments don't — AWS forces you to explicitly say what traffic should cross. This is a security feature: you control exactly which CIDRs can traverse the corridor.
>
> **Evaluator Question:** *What happens if TGW route table entries are missing?*
>
> **Model Answer:** The VPC sends traffic to the TGW, but the TGW has no forwarding rule for the destination CIDR. The packet gets blackholed — silently dropped. From the user's perspective, `nc -vz` hangs indefinitely. This is the second most common TGW debugging issue after missing VPC routes.

---

### Step 5: Update Tokyo RDS Security Group

The RDS security group must allow inbound MySQL traffic from São Paulo's CIDR range.

> **⚠️ CRITICAL: Use inline rules ONLY**
>
> Do NOT create a separate `aws_security_group_rule` resource for the same security group that uses inline `ingress` blocks. Mixing inline and standalone rules causes Terraform to silently strip rules during drift reconciliation. See Troubleshooting Issue #3 for the full story.

**Action:** Update `security_groups.tf` — add the São Paulo CIDR as an inline ingress rule:

```hcl
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg01"
  description = "Security group for RDS MySQL"
  vpc_id      = aws_vpc.main.id

  # MySQL from EC2 security group ONLY
  ingress {
    description     = "MySQL from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  # Lab 3: MySQL from São Paulo via TGW
  ingress {
    description = "MySQL from Sao Paulo via TGW"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg01"
  })
}
```

> **SOCRATIC Q&A**
>
> ***Q:** Why do we allow the entire 10.1.0.0/16 CIDR instead of just the São Paulo EC2's specific IP?*
>
> **A (Explain Like I'm 10):** EC2 instances come and go — if you rebuild the server, it gets a new IP address. If you locked the security group to one specific IP, you'd have to update it every time the server changes. Using the whole VPC CIDR (10.1.0.0/16) means "any machine in São Paulo's private network can connect." Since the VPC itself is private and controlled, this is safe AND resilient.
>
> **Evaluator Question:** *Why use a CIDR block here instead of a security group reference like you did for the EC2 → RDS rule?*
>
> **Model Answer:** Security group references only work within the same VPC (or peered VPCs in the same region). São Paulo is in a completely different region with its own security groups. Cross-region security group references don't exist in AWS. CIDR blocks are the only option for cross-region ingress rules.

---

### Step 6: Verify End-to-End Connectivity

This is the moment of truth — can São Paulo actually reach Tokyo's database through the TGW corridor?

**Action:** SSM into São Paulo EC2 and test:

```bash
# Connect to São Paulo EC2
aws ssm start-session --region sa-east-1 --target <SP_EC2_INSTANCE_ID>

# Install ncat (not included by default on Amazon Linux 2023)
sudo dnf install -y nmap-ncat

# Test TGW connectivity to Tokyo RDS
nc -vz <tokyo-rds-endpoint> 3306
```

**Expected output:**
```
Ncat: Version 7.93 ( https://nmap.org/ncat )
Ncat: Connected to 10.0.101.67:3306.
Ncat: 0 bytes sent, 0 bytes received in 0.20 seconds.
```

> **SOCRATIC Q&A**
>
> ***Q:** What does `nc -vz` actually do, and why is it the right tool here?*
>
> **A (Explain Like I'm 10):** `nc` (netcat) is like knocking on a door to see if anyone's home. The `-v` flag means "tell me what happened" (verbose), and `-z` means "just knock, don't go inside" (zero I/O — no data transfer). We're not trying to log into the database — we're just checking: "Can a packet from São Paulo reach Tokyo's database port?" If the knock succeeds, the entire network path works: VPC routes → TGW → peering → TGW → security group → RDS.
>
> **Evaluator Question:** *If `nc -vz` succeeds but the application still can't connect to the database, what would you check next?*
>
> **Model Answer:** `nc -vz` proves Layer 4 (TCP) connectivity. If the app still fails, the issue is Layer 7 (application): wrong database credentials, missing database user grants for the São Paulo IP range, incorrect connection string in the app config, or the app not resolving the RDS endpoint correctly. The network path is confirmed working — the problem is authentication or application configuration.

---

### Verification Checklist for Lab 3A

```bash
# VERIFICATION 1: TGW Peering Attachment Status
aws ec2 describe-transit-gateway-peering-attachments --region us-west-2 \
  --query "TransitGatewayPeeringAttachments[].{Id:TransitGatewayAttachmentId,State:State}" \
  --output table
# Expected: State = 'available'

# VERIFICATION 2: TGW Route Table Associations
aws ec2 get-transit-gateway-route-table-associations --region us-west-2 \
  --transit-gateway-route-table-id <TOKYO_TGW_RTB_ID> \
  --query "Associations[].{AttachmentId:TransitGatewayAttachmentId,ResourceType:ResourceType,State:State}" \
  --output table
# Expected: State = 'associated' for both VPC and peering attachments

# VERIFICATION 3: Routes Point Cross-Region CIDRs to TGW
aws ec2 describe-route-tables --region us-west-2 \
  --filters "Name=vpc-id,Values=<TOKYO_VPC_ID>" \
  --query "RouteTables[].Routes[]"
# Look for: DestinationCidrBlock = São Paulo CIDR, TransitGatewayId = present

# VERIFICATION 4: Test Network Reachability from São Paulo to Tokyo RDS
# SSM Session into São Paulo EC2, then:
nc -vz <tokyo-rds-endpoint> 3306
# Expected: Connection to <endpoint> 3306 port [tcp/mysql] succeeded!
```

---

## PART 2: LAB 3B — Audit Evidence & Regulator-Ready Logging

In regulated industries, "it works" isn't enough — you must PROVE it works correctly. Lab 3B creates an audit evidence pack that demonstrates compliance to regulators.

> **SOCRATIC Q&A**
>
> ***Q:** Why do we need evidence files? Can't we just show the auditor the AWS console?*
>
> **A (Explain Like I'm 10):** Imagine your teacher asks "did you do your homework?" You can say "yes" (that's Lab 3A — it works). Or you can show them the completed worksheet, your scratch paper, and the textbook page you referenced (that's Lab 3B — proof). Auditors don't accept "trust me" or live demos. They need timestamped, reproducible CLI output they can verify independently. Evidence files are your receipts.
>
> **Evaluator Question:** *Why use CLI output instead of console screenshots for compliance evidence?*
>
> **Model Answer:** CLI output is machine-verifiable, timestamped, and reproducible. Screenshots can be edited, don't include timestamps, and can't be re-run for verification. An auditor can take your CLI command, run it themselves, and confirm the output matches. That's the gold standard for compliance evidence.

---

### Evidence Pack Structure

```
Lab3/evidence/
├── 00_architecture-summary.md   # High-level design explanation
├── 01_data-residency-proof.txt  # RDS only in Tokyo
├── 02_edge-proof-cloudfront.txt # CloudFront access logs
├── 03_waf-proof.txt             # WAF Allow/Block summary
├── 04_cloudtrail-change-proof.txt # Who changed what
├── 05_network-corridor-proof.txt  # TGW attachments + routes
└── evidence.json                # Malgus scripts output
```

---

### Malgus Evidence Scripts

These Python scripts automate evidence collection. Run them from the Lab3/python/ folder:

| Script | Purpose | Command |
|--------|---------|---------|
| `malgus_residency_proof.py` | Creates "DB only in Tokyo" proof | `python3 malgus_residency_proof.py` |
| `malgus_tgw_corridor_proof.py` | Shows TGW attachments + routes | `python3 malgus_tgw_corridor_proof.py` |
| `malgus_cloudtrail_last_changes.py` | Pulls recent CloudTrail events | `python3 malgus_cloudtrail_last_changes.py` |
| `malgus_waf_summary.py` | Summarizes WAF Allow/Block | `python3 malgus_waf_summary.py` |
| `malgus_cloudfront_log_explainer.py` | Counts Hit/Miss/RefreshHit | `python3 malgus_cloudfront_log_explainer.py --latest 5` |

---

### Deliverable: Auditor Narrative

Write an 8-12 line paragraph explaining why this design is APPI-compliant. This is what you'd say to an auditor:

> **Example Auditor Narrative**
>
> This architecture ensures APPI compliance by maintaining strict data residency in Japan while enabling global access for medical staff.
>
> All patient health information (PHI) is stored exclusively in Tokyo (ap-northeast-1) within a private RDS MySQL instance. No database replicas, backups, or persistent storage exist outside Japan.
>
> São Paulo (sa-east-1) operates as a stateless compute extension, connected to Tokyo via AWS Transit Gateway peering. This creates a controlled, auditable data corridor where compute requests travel to Japan, but data never leaves.
>
> CloudFront provides global access through a single URL (chewbacca-growls.com) with WAF protection at the edge. The ALB is cloaked — direct access returns 403, ensuring all traffic flows through the secured perimeter.
>
> CloudTrail records all infrastructure changes. Evidence shows: RDS exists only in Tokyo, TGW forms the exclusive cross-region path, and edge security blocks bypass attempts. This design intentionally trades latency for legal certainty — the correct tradeoff for regulated healthcare.

---

## Deliverables Checklist

| Lab | Requirement | Proof |
|-----|-------------|-------|
| 3A | TGW exists in both regions | `aws ec2 describe-transit-gateways` |
| 3A | Peering attachment is 'available' | `aws ec2 describe-transit-gateway-peering-attachments` |
| 3A | Routes point cross-region CIDRs to TGW | `aws ec2 describe-route-tables` |
| 3A | RDS SG allows São Paulo CIDR | `aws ec2 describe-security-groups` |
| 3A | nc -vz from São Paulo to Tokyo RDS succeeds | SSM Session + nc command |
| 3B | Data residency proof (RDS only in Tokyo) | `01_data-residency-proof.txt` |
| 3B | Network corridor proof (TGW path) | `05_network-corridor-proof.txt` |
| 3B | CloudTrail change proof | `04_cloudtrail-change-proof.txt` |
| 3B | Auditor narrative (8-12 lines) | `00_architecture-summary.md` |

---

## Common Issues and Troubleshooting

*These are real issues encountered during actual lab completion — not theoretical problems. Each one cost real debugging time and teaches a lesson you'll carry into production.*

> **SOCRATIC Q&A**
>
> ***Q:** Why is a troubleshooting section important in a lab guide?*
>
> **A (Explain Like I'm 10):** When you build a LEGO set and a piece doesn't fit, the instruction booklet just shows the happy path — step 1, step 2, done! But real building has wrong pieces, missing pieces, and steps where you realize you did step 5 wrong and have to go back. This section is like a "common mistakes" page that experienced builders wish they'd had. In interviews, being able to talk about problems you solved is MORE impressive than saying "everything worked first try."
>
> **Evaluator Question:** *Describe your systematic debugging approach for cross-region connectivity issues.*
>
> **Model Answer:** I follow an OSI-inspired elimination process: (1) DNS — is the hostname resolving to the correct private IP? (2) Routing — do VPC route tables point cross-region CIDRs to the TGW? (3) TGW routing — do TGW route tables have static routes for peering? (4) TGW associations — are peering attachments associated with route tables? (5) Security groups — does the target SG allow the source CIDR on the required port? (6) NACLs — are default NACLs still allowing all? I eliminate each layer before moving to the next, starting with the cheapest check (DNS) and ending with the most common culprit (security groups).

---

### Issue #1: CIDR Overlap Between Regions

| | Detail |
|---|--------|
| **Symptom** | TGW routes show "blackhole" status, or traffic routes to wrong VPC |
| **Root Cause** | Both Tokyo and São Paulo VPCs configured with the same CIDR (e.g., both using `10.0.0.0/16`) |
| **Resolution** | Change one region to a non-overlapping CIDR. São Paulo → `10.1.0.0/16` with subnets: `10.1.1.0/24`, `10.1.2.0/24`, `10.1.101.0/24`, `10.1.102.0/24` |
| **Prevention** | Plan CIDR allocation BEFORE deployment. Document in architecture diagram. Use a CIDR registry spreadsheet for multi-region deployments. |

**Verification:**
```bash
# Confirm Tokyo CIDR
aws ec2 describe-vpcs --region us-west-2 \
  --query "Vpcs[].CidrBlock" --output text
# Expected: 10.0.0.0/16

# Confirm São Paulo CIDR (must be DIFFERENT)
aws ec2 describe-vpcs --region sa-east-1 \
  --query "Vpcs[].CidrBlock" --output text
# Expected: 10.1.0.0/16
```

> **SOCRATIC Q&A**
>
> ***Q:** Why can't two VPCs connected by TGW use the same CIDR?*
>
> **A (Explain Like I'm 10):** Imagine two houses on the same street both have the address "123 Main Street." When the mailman has a letter for "123 Main Street," which house does he deliver it to? He can't tell! That's exactly what happens with overlapping CIDRs — the TGW gets a packet for `10.0.5.20` and doesn't know if it should go to Tokyo or São Paulo. The packet gets "blackholed" (dropped) because the TGW can't make a decision.
>
> **Evaluator Question:** *How would you design a CIDR allocation strategy for an organization with 20+ VPCs across 5 regions?*
>
> **Model Answer:** Use a hierarchical CIDR scheme: allocate a /8 supernet (e.g., 10.0.0.0/8) and subdivide by region. Region 1 gets 10.0.0.0/12, Region 2 gets 10.16.0.0/12, etc. Within each region, further subdivide for production, staging, and dev environments. Maintain a central CIDR registry (even a spreadsheet works). This prevents overlap, enables route aggregation at TGW, and makes troubleshooting intuitive — "10.1.x.x is always São Paulo."

---

### Issue #2: TGW Peering Routes Missing (The Silent Killer)

| | Detail |
|---|--------|
| **Symptom** | `nc -vz` hangs indefinitely (timeout). VPC route tables look correct. |
| **Root Cause** | TGW route tables don't have static routes for the peering attachment. VPC attachments auto-propagate routes to TGW route tables. **Peering attachments do NOT.** |
| **Resolution** | Add static routes in BOTH TGW route tables: Tokyo TGW → `10.1.0.0/16` via peering attachment. São Paulo TGW → `10.0.0.0/16` via peering attachment. |
| **Prevention** | Remember the rule: **VPC attachments auto-propagate. Peering attachments require static routes.** Add TGW static route creation to your deployment checklist immediately after peering acceptance. |

**Verification:**
```bash
# Check Tokyo TGW route table for São Paulo route
aws ec2 search-transit-gateway-routes --region us-west-2 \
  --transit-gateway-route-table-id <TOKYO_TGW_RTB_ID> \
  --filters "Name=type,Values=static" \
  --query "Routes[].{CIDR:DestinationCidrBlock,State:State,AttachmentId:TransitGatewayAttachments[0].TransitGatewayAttachmentId}"

# Check São Paulo TGW route table for Tokyo route
aws ec2 search-transit-gateway-routes --region sa-east-1 \
  --transit-gateway-route-table-id <SP_TGW_RTB_ID> \
  --filters "Name=type,Values=static" \
  --query "Routes[].{CIDR:DestinationCidrBlock,State:State,AttachmentId:TransitGatewayAttachments[0].TransitGatewayAttachmentId}"
```

> **SOCRATIC Q&A**
>
> ***Q:** What's the difference between a TGW route and a TGW association?*
>
> **A (Explain Like I'm 10):** A route is like a sign that says "traffic for Tokyo, go through Door 5." An association is like giving someone a map when they walk IN through Door 5. Without the association, traffic arrives via peering but the TGW doesn't know which map (route table) to check for where to deliver it next. The packet just stands in the hallway confused and gets dropped. You need BOTH: routes (signs saying where to go) AND associations (maps for incoming traffic).
>
> **Evaluator Question:** *A colleague tells you "I added TGW routes but connectivity still times out." What's your first follow-up question?*
>
> **Model Answer:** "Are the peering attachments associated with the TGW route tables?" Routes tell the TGW where to forward outbound traffic, but associations tell the TGW which route table to consult for traffic arriving via a specific attachment. VPC attachments auto-associate; peering attachments don't. This is the most commonly missed step in TGW peering deployments.

---

### Issue #3: RDS Security Group Rule Silently Disappears (Terraform Inline vs. Standalone Conflict)

| | Detail |
|---|--------|
| **Symptom** | `nc -vz` times out AFTER a `terraform apply`. Previously working connectivity breaks. Security group appears to be missing the São Paulo CIDR rule. |
| **Root Cause** | The RDS security group had inline `ingress {}` blocks in `security_groups.tf` AND a separate `aws_security_group_rule` resource in another file managing the same security group. Terraform sees the inline block as "source of truth" and removes anything not defined inline — including your standalone rule. |
| **Resolution** | Move ALL rules inline into the security group resource. Delete the standalone `aws_security_group_rule` file entirely. Never mix the two patterns on the same security group. |
| **Prevention** | **Pick ONE pattern per security group and stick with it.** If the base SG uses inline rules, add new rules inline too. If you use standalone `aws_security_group_rule` resources, remove ALL inline ingress/egress blocks. |

**How it happened step by step:**

1. `security_groups.tf` defined the RDS SG with an inline `ingress` block for EC2 → RDS
2. A separate file `tokyo_rds_ingress_sp.tf` created an `aws_security_group_rule` for São Paulo CIDR → RDS port 3306
3. On `terraform apply`, Terraform reconciled the inline block — saw a CIDR rule it didn't define inline, treated it as "drift," and removed it
4. The standalone resource was destroyed separately, leaving NO São Paulo rule on the security group
5. `nc -vz` started timing out — the firewall was silently blocking traffic

**Quick CLI fix (for immediate testing):**
```bash
# Re-add the rule manually to unblock testing
aws ec2 authorize-security-group-ingress --region us-west-2 \
  --group-id <RDS_SG_ID> \
  --protocol tcp --port 3306 --cidr 10.1.0.0/16
```

**Permanent Terraform fix:**
```hcl
# In security_groups.tf — add São Paulo CIDR as INLINE rule
ingress {
  description = "MySQL from Sao Paulo via TGW"
  from_port   = 3306
  to_port     = 3306
  protocol    = "tcp"
  cidr_blocks = ["10.1.0.0/16"]
}
```

Then delete the standalone file:
```bash
rm tokyo_rds_ingress_sp.tf
terraform plan  # Should show: 1 to destroy (standalone rule), 0-1 to change
terraform apply
```

**Verification:**
```bash
aws ec2 describe-security-groups --region us-west-2 \
  --group-ids <RDS_SG_ID> \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`3306\`]" \
  --output table
# Must show BOTH: security group reference (EC2) AND CIDR 10.1.0.0/16
```

> **SOCRATIC Q&A**
>
> ***Q:** Why does Terraform silently remove security group rules instead of showing an error?*
>
> **A (Explain Like I'm 10):** Imagine two people editing the same whiteboard. One writes a rule with a marker (inline), the other sticks a Post-it note on the same board (standalone). When the marker person erases and redraws the board, the Post-it falls off — and nobody notices. Terraform sees the inline block as "this is everything that should exist." Anything else is "drift" that needs to be cleaned up. It's not a bug — it's Terraform being strict about what "source of truth" means. The problem is that humans didn't expect two managers fighting over the same resource.
>
> **Evaluator Question:** *How would you prevent inline vs. standalone security group rule conflicts in a team environment?*
>
> **Model Answer:** Implement multiple guardrails: (1) Use `terraform validate` and `terraform plan` review as mandatory PR checks. (2) Implement pre-commit hooks or `tflint` custom rules that scan for mixed inline/standalone patterns on the same security group. (3) Document team standards: "All security group rules must be inline" or "All rules must be standalone resources." (4) Use code review checklists that specifically flag new `aws_security_group_rule` resources and verify they don't target SGs with inline blocks. This is one of Terraform's most dangerous footguns — silent state reconciliation that removes working rules.

---

### Issue #4: `nc: command not found` on Amazon Linux 2023

| | Detail |
|---|--------|
| **Symptom** | `bash: nc: command not found` when testing connectivity from São Paulo EC2 |
| **Root Cause** | Amazon Linux 2023 doesn't include netcat/ncat by default (unlike Amazon Linux 2) |
| **Resolution** | `sudo dnf install -y nmap-ncat` |
| **Prevention** | Include in EC2 `user_data` script for future deployments so it's always available |

```bash
# Fix
sudo dnf install -y nmap-ncat

# Verify
nc -vz <tokyo-rds-endpoint> 3306
```

> **SOCRATIC Q&A**
>
> ***Q:** Why does Amazon Linux 2023 not include nc by default when it's such a common debugging tool?*
>
> **A (Explain Like I'm 10):** Think of it like a new phone — it comes with the basics (phone, camera, messages) but not every app you might want. Amazon Linux 2023 ships with a minimal footprint for security and speed. Every extra package is a potential attack surface. Network tools like `nc` are powerful — they can probe ports, transfer files, even create reverse shells. For a hardened production server, you WANT minimal packages. For a lab/debug environment, you install what you need.
>
> **Evaluator Question:** *What's the difference between `nc`, `ncat`, and `nmap-ncat`?*
>
> **Model Answer:** `nc` (netcat) is the original networking Swiss Army knife. `ncat` is Nmap's modern rewrite with SSL support, IPv6, and better security. `nmap-ncat` is the RPM package name that provides the `ncat` binary, which is also aliased as `nc` on Amazon Linux 2023. When you `dnf install nmap-ncat`, you get both the `ncat` and `nc` commands. For basic port testing (`nc -vz`), they're functionally identical.

---

### Issue #5: DNS Resolution — `nslookup` Not Available

| | Detail |
|---|--------|
| **Symptom** | `bash: nslookup: command not found` when trying to verify DNS resolution of RDS endpoint from São Paulo |
| **Root Cause** | Amazon Linux 2023 minimal install doesn't include `bind-utils` (which provides `nslookup`, `dig`, `host`) |
| **Resolution** | Use Python's built-in socket module as an alternative, or install `bind-utils` |
| **Prevention** | Know multiple DNS resolution methods — not every server has the same tools |

**Python DNS workaround (always available):**
```bash
python3 -c "import socket; print(socket.gethostbyname('chewbacca-rds01.cl02ec282asu.us-west-2.rds.amazonaws.com'))"
# Expected: 10.0.101.67 (Tokyo private subnet IP)
```

**Alternative — install proper DNS tools:**
```bash
sudo dnf install -y bind-utils
nslookup chewbacca-rds01.cl02ec282asu.us-west-2.rds.amazonaws.com
```

> **SOCRATIC Q&A**
>
> ***Q:** Why is DNS the FIRST thing to check when debugging cross-region connectivity?*
>
> **A (Explain Like I'm 10):** When you call someone and the phone just rings forever, the first question is: "Did I dial the right number?" DNS is the phone book — it translates the RDS hostname into an IP address. If São Paulo's EC2 looks up the wrong number (a public IP instead of the `10.0.x.x` private IP), the TGW route never matches and the packet goes out through NAT to the internet instead of through the tunnel. Always check the phone book first — it's the cheapest, fastest diagnostic.
>
> **Evaluator Question:** *The RDS endpoint resolves to `10.0.101.67` from São Paulo. Is that expected, and what does it tell you?*
>
> **Model Answer:** Yes — `10.0.101.67` is in Tokyo's VPC CIDR (`10.0.0.0/16`), specifically in a private subnet (`10.0.101.0/24`). This tells me: (1) DNS resolution is working correctly across regions, (2) the RDS is in a private subnet (good — no public access), and (3) traffic will match the VPC route table entry for `10.0.0.0/16 → TGW`. If it had resolved to a public IP (e.g., `54.x.x.x`), it would mean DNS is returning the public endpoint, and traffic would bypass the TGW entirely.

---

### Issue #6: Terraform `terraform.tfvars.tf` Naming Error

| | Detail |
|---|--------|
| **Symptom** | `Error: Unsupported argument` for valid variable definitions |
| **Root Cause** | File named `terraform.tfvars.tf` — the extra `.tf` extension causes Terraform to parse it as HCL code instead of variable values |
| **Resolution** | Rename to `terraform.tfvars` (no `.tf` extension) |
| **Prevention** | Remember: `.tf` = Terraform code (HCL). `.tfvars` = Variable values (key-value pairs). They use different syntax. |

```bash
# Fix
mv terraform.tfvars.tf terraform.tfvars

# Verify
terraform validate
# Expected: Success! The configuration is valid.
```

> **SOCRATIC Q&A**
>
> ***Q:** What's the difference between `.tf` files and `.tfvars` files?*
>
> **A (Explain Like I'm 10):** Think of `.tf` files as the recipe — "you need 2 cups of flour, 1 cup of sugar" (variable declarations, resource definitions, logic). `.tfvars` files are the shopping list — "flour = King Arthur brand, sugar = organic cane" (actual values). The recipe says WHAT you need. The shopping list says WHICH SPECIFIC ONES. If you accidentally put your shopping list in the recipe format, the chef gets confused because "flour = King Arthur" isn't a valid recipe instruction.
>
> **Evaluator Question:** *Why should `terraform.tfvars` never be committed to Git?*
>
> **Model Answer:** `terraform.tfvars` typically contains environment-specific values including sensitive data like database passwords, API keys, and AWS account IDs. Committing it to Git exposes secrets in version history permanently — even if you delete the file later, it's in the Git log forever. Use `.gitignore` to exclude it, and use `terraform.tfvars.example` (with placeholder values) to document what variables are needed. In CI/CD, inject values via environment variables or a secrets manager.

---

### Issue #7: Missing TGW Peering Attachment ID in Terraform Outputs

| | Detail |
|---|--------|
| **Symptom** | São Paulo's Terraform config needs the peering attachment ID from Tokyo, but `terraform output` doesn't include it |
| **Root Cause** | Tokyo's `outputs.tf` didn't define an output for the peering attachment ID |
| **Resolution** | Retrieve via CLI, or add the output to Tokyo's Terraform config |
| **Prevention** | Always add outputs for cross-region resource IDs that other configurations need to reference |

**CLI retrieval:**
```bash
aws ec2 describe-transit-gateway-peering-attachments --region us-west-2 \
  --query "TransitGatewayPeeringAttachments[].{Id:TransitGatewayAttachmentId,State:State,PeerRegion:RequesterTgwInfo.Region}" \
  --output table
```

**Terraform output to add:**
```hcl
output "tgw_peering_attachment_id" {
  value       = aws_ec2_transit_gateway_peering_attachment.shinjuku_to_liberdade_peer01.id
  description = "TGW Peering Attachment ID (needed by São Paulo accepter)"
}
```

> **SOCRATIC Q&A**
>
> ***Q:** Why are Terraform outputs important in multi-region architectures?*
>
> **A (Explain Like I'm 10):** When you're building a LEGO spaceship with a friend and they're building the cockpit while you build the engines, you need to tell them "the engine connector piece is the blue 4x2 block." Terraform outputs are how one configuration tells another "here's the ID you need to connect to my stuff." Without outputs, you're hunting through the AWS console or CLI for IDs — which is slow, error-prone, and doesn't scale. Good outputs are like labeled ports on the back of a TV — "HDMI 1," "USB 2" — you know exactly what plugs in where.

---

### Systematic Debugging Workflow: "nc -vz Times Out"

When `nc -vz <rds-endpoint> 3306` times out, work through this checklist in order. Stop at the first failure — that's your problem.

```
┌─────────────────────────────────────────────────────────────────┐
│         SYSTEMATIC DEBUG CHECKLIST: "nc -vz Times Out"         │
├────┬────────────────────────────────────────────────────────────┤
│ #  │ Check                                                     │
├────┼────────────────────────────────────────────────────────────┤
│ 1  │ DNS RESOLUTION                                            │
│    │ Does the RDS endpoint resolve to a private IP              │
│    │ in Tokyo's CIDR (10.0.x.x)?                               │
│    │                                                            │
│    │ python3 -c "import socket;                                 │
│    │   print(socket.gethostbyname('<rds-endpoint>'))"           │
│    │                                                            │
│    │ ✅ 10.0.x.x → Continue to #2                              │
│    │ ❌ Public IP or failure → Fix DNS/VPC settings             │
├────┼────────────────────────────────────────────────────────────┤
│ 2  │ VPC ROUTE TABLES                                          │
│    │ Does São Paulo's private route table have                  │
│    │ 10.0.0.0/16 → TGW?                                       │
│    │                                                            │
│    │ aws ec2 describe-route-tables --region sa-east-1           │
│    │   --filters "Name=vpc-id,Values=<SP_VPC_ID>"              │
│    │                                                            │
│    │ ✅ Route exists → Continue to #3                           │
│    │ ❌ Missing → Add aws_route for Tokyo CIDR                 │
├────┼────────────────────────────────────────────────────────────┤
│ 3  │ TGW ROUTE TABLES                                          │
│    │ Do both TGW route tables have static routes for           │
│    │ the peering attachment?                                    │
│    │                                                            │
│    │ aws ec2 search-transit-gateway-routes                      │
│    │   --transit-gateway-route-table-id <TGW_RTB_ID>           │
│    │   --filters "Name=type,Values=static"                     │
│    │                                                            │
│    │ ✅ Static routes present → Continue to #4                  │
│    │ ❌ Missing → Add static routes (see Issue #2)             │
├────┼────────────────────────────────────────────────────────────┤
│ 4  │ TGW ASSOCIATIONS                                          │
│    │ Are BOTH VPC and peering attachments associated            │
│    │ with TGW route tables?                                     │
│    │                                                            │
│    │ aws ec2 get-transit-gateway-route-table-associations       │
│    │   --transit-gateway-route-table-id <TGW_RTB_ID>           │
│    │                                                            │
│    │ ✅ Both "associated" → Continue to #5                      │
│    │ ❌ Peering not associated → Associate it                  │
├────┼────────────────────────────────────────────────────────────┤
│ 5  │ SECURITY GROUPS                                           │
│    │ Does Tokyo RDS SG allow 10.1.0.0/16 on port 3306?        │
│    │                                                            │
│    │ aws ec2 describe-security-groups --region us-west-2        │
│    │   --group-ids <RDS_SG_ID>                                 │
│    │   --query "SecurityGroups[0].IpPermissions                 │
│    │           [?FromPort==\`3306\`]"                           │
│    │                                                            │
│    │ ✅ CIDR present → Continue to #6                           │
│    │ ❌ Missing → Check for inline/standalone conflict          │
│    │   (see Issue #3)                                           │
├────┼────────────────────────────────────────────────────────────┤
│ 6  │ NETWORK ACLs                                              │
│    │ Are default NACLs still allowing all traffic?              │
│    │ (Only relevant if custom NACLs were configured)            │
│    │                                                            │
│    │ aws ec2 describe-network-acls --region us-west-2           │
│    │   --filters "Name=vpc-id,Values=<TOKYO_VPC_ID>"           │
│    │                                                            │
│    │ ✅ Default allow-all → Problem is elsewhere               │
│    │ ❌ Custom deny rules → Adjust NACLs                       │
└────┴────────────────────────────────────────────────────────────┘
```

> **SOCRATIC Q&A**
>
> ***Q:** Why do we debug in THIS specific order?*
>
> **A (Explain Like I'm 10):** Imagine you're trying to mail a birthday card. You'd check in this order: (1) Do I have the right address? (DNS) (2) Does my mailbox connect to the post office? (VPC routes) (3) Does the post office know which truck to put it on? (TGW routes) (4) Is the truck actually assigned to my route? (TGW associations) (5) Will the recipient's mailbox accept it? (Security groups) (6) Is there a gate blocking the driveway? (NACLs). Each step is cheaper and faster to check than the next. DNS takes 2 seconds. Tracing NACLs takes 10 minutes. Start cheap, stop at the first failure.
>
> **Evaluator Question:** *Walk me through how you debugged a cross-region connectivity timeout in this lab.*
>
> **Model Answer (Interview Talk Track):** "During cross-region TGW deployment, `nc -vz` from São Paulo to Tokyo RDS timed out. I followed a systematic elimination process: DNS resolved correctly to `10.0.101.67` — a Tokyo private subnet IP. VPC route tables had the correct cross-region CIDR pointing to TGW. TGW route tables had static routes in both directions. TGW peering associations were confirmed. Then I checked the RDS security group and found the São Paulo CIDR rule was missing. Root cause: a Terraform state conflict between inline `ingress` blocks and a standalone `aws_security_group_rule` resource — Terraform's reconciliation loop silently stripped the standalone rule. I fixed it by consolidating to inline rules, verified with `nc -vz`, and documented the pattern to prevent recurrence. That debugging narrative alone demonstrates production-level troubleshooting methodology."

---

## How to Talk About This in an Interview

***"I designed a multi-region medical application where all PHI remained in Japan to comply with APPI. CloudFront provided global access, São Paulo ran stateless compute only, and all reads/writes traversed a Transit Gateway to Tokyo RDS. The design intentionally traded some latency for legal certainty and auditability."***

**That answer will stop the room.**

---

## What This Lab Proves About You

*If you complete this lab, you can confidently say:*

**"I can translate legal requirements into cloud architecture and prove compliance to auditors."**

*This is senior-level cloud architecture knowledge. Most engineers learn "multi-region for availability" and "replicate everything everywhere." You learned that regulated reality is different — and how to design for it.*
