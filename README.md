# FischerLynn LLC -- AWS Gov-Cloud Reference (Serverless)

A small, self-contained Terraform reference that stands up a **serverless** AWS
stack -- **Lambda + API Gateway + DynamoDB + S3** -- with a secure, OIDC-based
GitHub Actions CI/CD pipeline.

This repository is a **capability demonstration** by FischerLynn LLC. It is
**GovCloud-AWARE but runs on commercial AWS**: the architecture, IAM trust model,
policy-as-code gates, and approval-gated promotion mirror the controls expected
in AWS GovCloud (US) and FedRAMP-style environments, while the actual deployment
target is a standard commercial AWS account so it stays inside the free tier and
costs effectively nothing to run and tear down. The patterns
(OIDC keyless auth, least-privilege IAM, encrypted state, policy-as-code,
plan-before-apply, environment promotion) port directly to a GovCloud partition.

> This repo intentionally contains **no static credentials**. Authentication to
> AWS happens through GitHub OIDC + IAM role assumption only.

---

## What's in here

```
aws-govcloud-reference/
├── .github/
│   └── workflows/
│       ├── terraform.yml     # OIDC CI/CD: fmt/validate/tfsec/checkov/plan -> gated apply
│       └── README.md         # named CI/CD patterns
├── README.md                 # you are here
└── (your Terraform: *.tf for Lambda / APIGW / DynamoDB / S3)
```

The Terraform modules themselves (Lambda function, HTTP API Gateway, DynamoDB
table, S3 bucket, backing IAM) are the deployable payload that the pipeline
formats, scans, plans, and applies.

---

## Why serverless: the cost rationale

The whole point of this reference is that a reviewer can clone it, deploy it,
look at it, and destroy it for **near-zero cost**:

- **Scale-to-zero.** Lambda and API Gateway HTTP APIs bill per request. With no
  traffic there is no compute charge -- idle cost is essentially $0.
- **Free-tier friendly.** Lambda (1M requests/mo), API Gateway HTTP API (1M
  calls/mo for the first year), DynamoDB on-demand (25 GB + 25 WCU/RCU), and S3
  (5 GB) all sit comfortably inside the AWS Free Tier for a demo-sized stack.
- **No always-on infrastructure.** There are no VPCs, NAT gateways, load
  balancers, or EC2 instances accruing hourly charges.
- **Destroy after.** The stack is designed to be ephemeral: spin it up to
  demonstrate, then `terraform destroy` to return to a zero-resource, zero-cost
  state (see **Teardown** below).

---

## Bootstrap (one-time AWS setup)

These steps create the keyless trust relationship the pipeline relies on. Do
them once in your AWS account, then never store an access key again.

1. **Create the GitHub OIDC identity provider** in IAM (if not already present):
   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`

2. **Create the deploy IAM role** `github-oidc-terraform-deploy` with a trust
   policy that allows **only** this repository to assume it via OIDC:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::981257813928:oidc-provider/token.actions.githubusercontent.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
           },
           "StringLike": {
             "token.actions.githubusercontent.com:sub": "repo:fischerlynn/aws-govcloud-reference:*"
           }
         }
       }
     ]
   }
   ```

   Attach a **least-privilege** permissions policy scoped to the Lambda / API
   Gateway / DynamoDB / S3 resources this stack manages (plus access to the
   Terraform remote-state backend).

3. **Create the Terraform remote-state backend** (recommended): an S3 bucket
   with versioning + SSE enabled and a DynamoDB table for state locking. Wire it
   into a `backend "s3"` block in your Terraform.

4. **Configure the `production` GitHub Environment**:
   - Repo **Settings > Environments > New environment > `production`**.
   - Add **required reviewers** so `terraform apply` waits for human approval.

5. **Set the tokens** in `.github/workflows/terraform.yml`:
   - `us-east-1` (default `us-east-1`)
   - `981257813928`
   - and confirm the role name / `fischerlynn/aws-govcloud-reference` match your trust policy.

---

## Run

### Locally (optional, for development)
```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan
```

### Via CI/CD (the intended path)
1. Open a **pull request**. The pipeline runs `fmt -check`, `validate`, `tfsec`,
   `checkov`, and `terraform plan`, then comments the plan on the PR.
2. **Merge to `main`.** The `apply` job starts but pauses on the `production`
   Environment gate.
3. **Approve** the deployment in the GitHub UI. Terraform applies.

---

## Security patterns

- **OIDC keyless auth** -- GitHub Actions assumes an IAM role via short-lived STS
  credentials; no long-lived AWS keys exist anywhere.
- **Least-privilege IAM** -- the deploy role is scoped to only the services this
  stack manages; per-job GitHub `permissions` default to read-only.
- **Policy-as-code gates** -- `tfsec` and `checkov` fail the build on insecure
  configuration before anything merges.
- **Plan-before-apply** -- PRs only plan; the diff is reviewed as a PR comment.
- **Environment promotion** -- applies are gated behind an approval-required
  `production` Environment.
- **Encrypted, locked remote state** -- S3 (versioned + SSE) with DynamoDB
  locking keeps state confidential and prevents concurrent corruption.
- **Pinned action versions** -- supply-chain stability for the CI toolchain.

(See `.github/workflows/README.md` for the same patterns mapped to workflow
steps.)

---

## Teardown

This stack is meant to be ephemeral. To return to a zero-cost, zero-resource
state:

```bash
terraform destroy
```

`terraform destroy` removes the Lambda function, API Gateway, DynamoDB table, and
S3 bucket created by this reference.

**Also remember to clean up the bootstrap resources** if you no longer need them:
- Empty and delete the Terraform remote-state S3 bucket, and delete the
  state-lock DynamoDB table.
- Delete the `github-oidc-terraform-deploy` IAM role (and the OIDC provider if it
  is not used by any other repo).

> Note: S3 buckets must be **empty** before they can be destroyed. If `destroy`
> fails on a non-empty bucket, empty it first (or enable `force_destroy` in the
> bucket resource for demo environments only).

---

## Tokens

| Token | Meaning |
| --- | --- |
| `fischerlynn/aws-govcloud-reference` | `org/repo` allowed to assume the deploy role (OIDC trust) |
| `981257813928` | AWS account id hosting the role and resources |
| `us-east-1` | Deploy region (default `us-east-1`) |

All placeholders use the double-brace UPPER_SNAKE convention. `FischerLynn LLC`
is the hard-coded company name (not a token).
