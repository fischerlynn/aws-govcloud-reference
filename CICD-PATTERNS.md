# CI/CD Patterns -- `terraform.yml`

This directory holds the GitHub Actions pipeline for the FischerLynn LLC AWS
gov-cloud reference. The single workflow (`terraform.yml`) demonstrates four
patterns that are table-stakes for regulated / gov-cloud-aware AWS work.

## Patterns

### 1. OIDC keyless authentication
GitHub's built-in OIDC identity provider issues a short-lived JWT to each job
that requests `permissions: id-token: write`. The step
`aws-actions/configure-aws-credentials@v4` exchanges that token with AWS STS for
**temporary** credentials by assuming an IAM role (`role-to-assume`). There are
**no static AWS access keys** anywhere in the repo or in GitHub secrets. The IAM
role's trust policy is scoped to `token.actions.githubusercontent.com` and to
this specific `fischerlynn/aws-govcloud-reference`.

### 2. Policy-as-code gates
Every pull request runs two independent IaC scanners before any plan is trusted:
- **tfsec** -- Terraform-focused static analysis.
- **checkov** -- broad misconfiguration scanning across IaC frameworks.

Both run with `soft_fail: false`, so a finding **fails the build** and blocks the
merge. This keeps insecure infrastructure out of `main`.

### 3. Plan-before-apply
Pull requests run `terraform plan` only -- never `apply`. The rendered plan is
posted back as a PR comment so a human reviews the exact resource diff before it
can reach `main`. The PR job assumes the role only to read remote state and the
provider; it makes no infrastructure writes.

### 4. Environment promotion (approval gate)
`terraform apply` runs **only** on push to `main` and is bound to the
`production` GitHub Environment. Configure that Environment in
**Settings > Environments > production** with **required reviewers** so the apply
job pauses for an explicit human approval before mutating real AWS resources.

## Hardening notes
- Action versions are **pinned** to release tags (supply-chain stability).
- Top-level `permissions` default to `contents: read`; each job opts into the
  minimum extra scopes it needs (`id-token`, `pull-requests`, `security-events`).
- `concurrency` cancels superseded runs to conserve free-tier CI minutes.

## Tokens to fill before use
| Token | Where | Meaning |
| --- | --- | --- |
| `fischerlynn/aws-govcloud-reference` | IAM trust policy (in your AWS setup) | `org/repo` allowed to assume the deploy role |
| `981257813928` | `terraform.yml` env | AWS account hosting the deploy role |
| `us-east-1` | `terraform.yml` env | Deploy region (default `us-east-1`) |

See `../../README.md` for bootstrap, run, security, and teardown instructions.
