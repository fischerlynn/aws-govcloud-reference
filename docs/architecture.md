# Serverless AWS Reference Architecture — Compliance-Aware Design

> **Maintained by:** FischerLynn LLC
> **Status:** Capability-demonstration reference. Built and validated on **commercial AWS** (`us-east-1`). The design is **GovCloud-aware** and maps to NIST SP 800-53 / FedRAMP controls, but this reference has **not undergone a FedRAMP assessment and holds no prior ATO**. See [Honest Framing](#honest-framing).

## Overview

This reference implements a fully serverless, scale-to-zero web/API workload on AWS using **API Gateway** (HTTPS edge + request routing), **AWS Lambda** (stateless compute), **DynamoDB** (managed NoSQL state), and **S3** (object storage), provisioned entirely as infrastructure-as-code and deployed through a CI/CD pipeline that authenticates to AWS via **GitHub OIDC** — no long-lived access keys are ever stored. The architecture is deliberately constructed around controls that recur in federal authorization packages: identity-federated deployment, least-privilege IAM, encryption at rest and in transit, comprehensive audit logging (CloudWatch + CloudTrail), and S3 public-access blocking. The intent is to demonstrate that a low-cost, commercially hosted serverless stack can be **engineered from day one to satisfy a recognizable subset of NIST 800-53 controls**, easing a future lift into AWS GovCloud (US) under a real FedRAMP authorization boundary.

## Architecture Diagram

```
                       ┌──────────────────────────────────────────────┐
                       │              CI/CD (GitHub Actions)            │
                       │   repo: fischerlynn/aws-govcloud-reference                        │
                       │                                                │
                       │   build ─▶ test ─▶ IaC plan ─▶ deploy          │
                       └───────────────────┬────────────────────────────┘
                                           │  OIDC token (no static keys)
                                           ▼
                            ┌───────────────────────────────┐
                            │  AWS IAM OIDC Identity Provider │
                            │  sts:AssumeRoleWithWebIdentity  │
                            │  ▶ scoped deploy role (sub/aud  │
                            │    + branch condition)          │
                            └───────────────┬─────────────────┘
                                            │ short-lived creds
   Internet ──HTTPS/TLS──┐                  ▼
                         │     ┌─────────────────────────────────────────┐
                         │     │  AWS Account 981257813928          │
                         ▼     │  Region: us-east-1                  │
              ┌──────────────────────┐                                   │
              │   Amazon API Gateway │  TLS 1.2+, throttling, WAF-ready  │
              │   (REST/HTTP API)    │                                   │
              └──────────┬───────────┘                                   │
                         │ invoke (IAM-scoped)                           │
                         ▼                                               │
              ┌──────────────────────┐     ┌──────────────────────────┐ │
              │     AWS Lambda       │────▶│  Amazon DynamoDB         │ │
              │  (least-priv exec    │     │  KMS-encrypted at rest   │ │
              │   role, env in KMS)  │────▶│  point-in-time recovery  │ │
              └──────────┬───────────┘     └──────────────────────────┘ │
                         │                                               │
                         ▼                                               │
              ┌──────────────────────┐                                  │
              │     Amazon S3        │  SSE-KMS, Block Public Access ON, │
              │  (objects/artifacts) │  versioning, TLS-only policy      │
              └──────────────────────┘                                  │
                         │                                               │
   ┌─────────────────────┴───────────────────────────────────────────┐ │
   │  Observability & Audit                                           │ │
   │  • CloudWatch Logs  (Lambda + API GW access logs, KMS-encrypted) │ │
   │  • CloudWatch Metrics/Alarms                                     │ │
   │  • AWS CloudTrail   (management + data events ▶ dedicated S3)    │ │
   └─────────────────────────────────────────────────────────────────┘ │
                            └──────────────────────────────────────────────┘
```

## Security Posture

| Area | Implementation |
|------|----------------|
| **Deployment identity** | GitHub Actions assumes an IAM role via **OIDC federation** (`sts:AssumeRoleWithWebIdentity`). The trust policy pins the OIDC `aud` and `sub` claims to `fischerlynn/aws-govcloud-reference` and a specific branch/environment. **No static `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` exist** in the repo, CI secrets, or developer machines. Credentials are minted just-in-time and expire in minutes. |
| **Least-privilege IAM** | Distinct roles for (a) the CI deploy role and (b) each Lambda execution role. Lambda roles grant only the specific DynamoDB table actions and S3 prefix actions they need (resource-scoped ARNs, no `*`). The deploy role is scoped to the resource types the IaC manages. |
| **Encryption at rest** | DynamoDB encrypted with AWS KMS (customer-managed key). S3 buckets use SSE-KMS. CloudWatch Log groups encrypted with KMS. Lambda environment variables encrypted with KMS. |
| **Encryption in transit** | API Gateway enforces **TLS 1.2+**. S3 bucket policy denies any request where `aws:SecureTransport = false`. All AWS service-to-service traffic uses TLS endpoints. |
| **Audit & logging** | **CloudWatch Logs** capture Lambda execution logs and API Gateway access logs; **CloudTrail** records management events and selected S3/DynamoDB data events to a dedicated, access-restricted log bucket. Log retention and KMS encryption are configured in IaC. |
| **S3 public-access** | **S3 Block Public Access** is enabled at the account and bucket level (all four switches ON). Bucket policies are explicit-deny by default; no ACL-based or policy-based public exposure. |
| **Secrets handling** | No secrets in source. Runtime configuration that is sensitive is sourced from SSM Parameter Store (SecureString) / Secrets Manager with KMS, not from plaintext env files. |
| **Network/edge readiness** | API Gateway is WAF-attachable; throttling and usage plans are configured to blunt abuse. (Private VPC integration is an optional hardening step noted under GovCloud Considerations.) |

## NIST 800-53 / FedRAMP Control Mapping

The table maps a representative subset of controls (Moderate-baseline-relevant) to concrete elements of this reference. This is a **design mapping**, not an assessed/audited control set.

| Control | Title | How this reference addresses it |
|---------|-------|---------------------------------|
| **AC-2** | Account Management | Machine identities are managed as IAM roles, not users; the CI deploy identity is a federated OIDC role with no standing credentials. No shared/static keys to provision, rotate, or deprovision. |
| **AC-3** | Access Enforcement | IAM policies enforce resource-scoped access; API Gateway + Lambda authorizers gate request access. Default posture is deny; access is granted explicitly per ARN/action. |
| **AC-6** | Least Privilege | Separate, narrowly-scoped roles for CI deploy and each Lambda. No wildcard resource ARNs on data-plane permissions; deploy role limited to managed resource types. |
| **AU-2** | Event Logging | CloudTrail logs management events; API Gateway access logging and Lambda logging are enabled to CloudWatch. Auditable event set is defined in IaC. |
| **AU-12** | Audit Record Generation | CloudTrail + CloudWatch generate audit records across API, compute, and storage planes; CloudTrail data events capture S3/DynamoDB object/item access where enabled. |
| **AU-9** | Protection of Audit Information | CloudTrail delivers to a dedicated S3 bucket with Block Public Access, KMS encryption, and restrictive bucket policy; log groups are KMS-encrypted to limit tampering/disclosure. |
| **IA-5** | Authenticator Management | Eliminates long-lived authenticators for CI by using OIDC short-lived tokens; sensitive runtime secrets live in Secrets Manager / SSM SecureString with KMS, not in code. |
| **SC-7** | Boundary Protection | API Gateway is the single managed ingress (TLS-terminated, throttled, WAF-attachable); S3 Block Public Access removes inadvertent public boundaries. |
| **SC-8** | Transmission Confidentiality & Integrity | TLS 1.2+ enforced at API Gateway; S3 policy denies non-TLS requests; all inter-service calls use TLS endpoints. |
| **SC-12** | Cryptographic Key Establishment & Management | AWS KMS manages keys for DynamoDB, S3 (SSE-KMS), CloudWatch Logs, and Lambda env vars; customer-managed keys enable rotation and access policy control. |
| **SC-13** | Cryptographic Protection | FIPS-validated cryptographic modules are available via AWS KMS and FIPS service endpoints (FIPS endpoints are the default expectation in GovCloud). |
| **SC-28** | Protection of Information at Rest | All persistent stores (DynamoDB, S3, logs) are encrypted at rest with KMS; S3 versioning and DynamoDB PITR support integrity/recovery. |
| **CM-2** | Baseline Configuration | The entire stack is defined as version-controlled infrastructure-as-code; the deployed baseline is reproducible and diffable from `fischerlynn/aws-govcloud-reference`. |
| **CM-3** | Configuration Change Control | Changes flow through pull requests + CI plan/apply gates; OIDC-scoped deploy role ties changes to reviewed, branch-pinned pipeline runs. |

## GovCloud Considerations

This reference runs on **commercial AWS**. Moving it toward a real **AWS GovCloud (US)** / FedRAMP authorization would require the following changes, none of which alter the core application code but all of which affect the authorization boundary:

- **Region isolation:** GovCloud regions (`us-gov-west-1`, `us-gov-east-1`) are physically and logically isolated from commercial regions, operated by screened US persons, and require a separate AWS GovCloud account linked to a commercial payer account. `us-east-1` would be replaced by a GovCloud region, and all ARNs shift to the `aws-us-gov` partition.
- **FIPS endpoints:** GovCloud mandates FIPS 140-2/140-3 validated endpoints by default. The SDK/CLI endpoint configuration and KMS usage already assume TLS; in GovCloud they resolve to FIPS endpoints (SC-13).
- **Authorized services only:** Only services in scope for the relevant authorization (FedRAMP High / DoD IL2–IL5 as applicable) may be used. Lambda, API Gateway, DynamoDB, S3, KMS, CloudWatch, and CloudTrail are GovCloud-available; any auxiliary service must be confirmed in-boundary before adoption.
- **ITAR / export control:** GovCloud supports workloads subject to **ITAR/EAR**. Data classified as export-controlled must remain within GovCloud and be handled by US persons; the commercial reference makes **no ITAR claims**.
- **Account & personnel constraints:** GovCloud requires US-person root account holders and additional onboarding/vetting; CI/CD federation (OIDC) is supported but the IAM trust and identity provider are configured in the GovCloud partition.
- **Authorization boundary documentation:** A real ATO requires an SSP, control implementation statements, a 3PAO assessment, and a P-ATO/agency ATO — out of scope here. This reference provides the *technical* substrate those documents would describe.

## Cost Model

The architecture is **scale-to-zero** and sits largely within the AWS Free Tier for demonstration-level traffic:

| Service | Cost behavior |
|---------|---------------|
| **Lambda** | Per-invocation + GB-second; no idle cost. Free tier: 1M requests + 400k GB-s/month. |
| **API Gateway** | Per-request (HTTP API cheaper than REST). No fixed hourly cost. |
| **DynamoDB** | On-demand (pay-per-request) — no provisioned capacity; 25 GB storage free-tier. Zero cost at rest with no traffic beyond storage. |
| **S3** | Per-GB storage + requests; small footprint stays near-free. |
| **CloudWatch / CloudTrail** | First trail (management events) is free; log ingestion/storage is the main variable cost — controlled via retention policies. |
| **KMS** | ~$1/month per customer-managed key + per-request; minimal. |

At demonstration scale, expected steady-state cost is effectively **$0–$2/month** (dominated by KMS keys and minor log storage). There are no always-on compute or NAT/EC2 charges by design.

### Teardown

Because everything is infrastructure-as-code, the environment is fully reversible. Destroy in this order (or via a single IaC destroy command):

```bash
# 1. Empty + remove S3 buckets (app + CloudTrail log bucket; versioned objects must be purged)
aws s3 rm s3://<app-bucket> --recursive
aws s3 rm s3://<cloudtrail-bucket> --recursive

# 2. Tear down the managed stack (Lambda, API GW, DynamoDB, roles, log groups)
#    e.g. terraform destroy   |   sam delete   |   cdk destroy   |   aws cloudformation delete-stack

# 3. Schedule deletion of customer-managed KMS keys (7–30 day window)
aws kms schedule-key-deletion --key-id <key-id> --pending-window-in-days 7

# 4. (Optional) Remove the GitHub OIDC IAM identity provider + deploy role if no longer needed
```

After teardown, recurring cost returns to **$0** (pending KMS key deletion window). No orphaned always-on resources remain.

## Honest Framing

- **Commercial, not GovCloud:** This reference is built and run on **commercial AWS** in `us-east-1`. It is **not deployed in AWS GovCloud** and carries **no FedRAMP authorization or prior ATO**.
- **GovCloud-aware by design:** Control choices (OIDC, least-privilege IAM, KMS everywhere, full audit logging, S3 BPA, IaC baselines) were selected because they are the same primitives a GovCloud/FedRAMP package depends on, so the path to a real authorization boundary is short and well-understood.
- **Capability demonstration:** The NIST 800-53 mapping is a **design-time mapping**, not an assessed control implementation. It demonstrates the ability to architect to federal expectations — it does not assert that an independent assessor has validated these controls.
