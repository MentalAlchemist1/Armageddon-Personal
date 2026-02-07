# Architecture Summary: APPI-Compliant Cross-Region Medical System

## Auditor Narrative

This architecture ensures compliance with Japan's Act on the Protection of Personal Information (APPI) by enforcing strict data residency while enabling global access for medical staff. All patient health information (PHI) is stored exclusively in a private RDS MySQL instance in Tokyo (us-west-2), with no database replicas, backups, or persistent storage existing outside Japan. A region-wide scan across eight AWS regions confirms zero database resources beyond Tokyo — this is documented in `01_data-residency-proof.txt`.

São Paulo (sa-east-1) operates as a stateless compute extension only. Its EC2 instance runs application logic but stores nothing locally. The IAM role attached to São Paulo's EC2 has no permissions to create databases, read secrets, or write to S3 — even an application bug cannot accidentally persist PHI outside Japan. The Terraform state file for São Paulo contains zero `aws_db_instance` resources, serving as infrastructure-as-code proof of statelessness.

The two regions connect exclusively through an AWS Transit Gateway peering corridor. Tokyo's Shinjuku TGW (tgw-0cd60163b3569e69e) peers with São Paulo's Liberdade TGW (tgw-0f01d1f9dc23b25cf) via attachment tgw-attach-088f83c0824af2304, verified as `available`. Static routes on both TGW route tables restrict cross-region traffic to their respective VPC CIDRs (10.0.0.0/16 for Tokyo, 10.1.0.0/16 for São Paulo). No VPC peering, VPN, or public internet path exists between these environments — the TGW corridor is the sole data channel, documented in `05_network-corridor-proof.txt`.

Tokyo's RDS security group permits inbound MySQL (port 3306) only from São Paulo's VPC CIDR (10.1.0.0/16) and Tokyo's own EC2 security group. All infrastructure changes — security group modifications, TGW creation, peering acceptance — are recorded in AWS CloudTrail with timestamps and user identity, documented in `04_cloudtrail-change-proof.txt`.

This design intentionally trades cross-region latency for legal certainty and auditability — the correct tradeoff for regulated healthcare data under APPI.

---

## Evidence Index

| File | What It Proves |
|---|---|
| `01_data-residency-proof.txt` | RDS exists only in Tokyo; zero databases in 7 other regions |
| `04_cloudtrail-change-proof.txt` | Who changed security controls, when, with what identity |
| `05_network-corridor-proof.txt` | TGW is the sole cross-region path; routes, peering, VPC routing documented |
| `00_architecture-summary.md` | This file — plain-language compliance explanation for auditors |
