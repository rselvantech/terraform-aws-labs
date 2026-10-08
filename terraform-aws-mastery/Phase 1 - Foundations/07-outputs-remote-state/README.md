# Demo 07 — Outputs, Sensitivity, and Remote State

---

## Overview

Demo 05 and Demo 06 both used outputs already — a couple of quick
`role_name`/`role_arn`/`sns_topic_arn` values, just enough to confirm
`apply` worked. Neither demo explained what an output actually *is* as
an interface: who else can read it, what happens when it's marked
`sensitive`, why `ephemeral` outputs come with a restriction variables
don't have, or how a completely separate Terraform configuration reads
these values back without ever touching this one's `.tf` files.

**Real-world scenario — CloudNova:** a second team owns the
notification-consumer service and needs the SNS topic's ARN — but they
work in a separate Terraform configuration with its own state, and
they shouldn't need write access to this one. This demo builds two
different ways to hand that value across: `terraform_remote_state`,
and AWS Systems Manager Parameter Store.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Rebuilding the Baseline & Marking Outputs                     │
│  Recreate the IAM role + SNS topic from Demo 06   |   full output       │
│  argument depth: sensitive, ephemeral restriction, depends_on           │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Output Variants & Remote State                                │
│  terraform output in all its forms   |   a second Terraform config     │
│  reads role_arn back via terraform_remote_state, with zero write access│
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — SSM Parameter Store as a Second Sharing Pattern               │
│  Write the SNS topic ARN to Parameter Store as SecureString   |         │
│  compare remote state vs. SSM vs. env vars vs. hardcoding                │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- `output` block full argument depth: `description`, `sensitive`,
  `ephemeral` (and its child-module-only restriction), `depends_on`
- All `terraform output` variants: default, named, `-json`, `-raw`
- `data.terraform_remote_state` — reading another configuration's
  outputs from its state, without any write access to that state
- `aws_ssm_parameter` — `String` vs. `SecureString`, as a second,
  decoupled sharing pattern
- The sharing-pattern decision: remote state vs. SSM vs. environment
  variables vs. hardcoding

**What this demo does NOT cover:** this is the last demo in the
"variables → locals → outputs" trilogy — Demo 08 onward moves to data
sources, expressions, and resource multiplicity, all building on the
IAM role and SNS topic this trilogy has been maintaining.

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** the same IAM role and SNS topic from
Demos 05–06 (unchanged — this demo adds no new IAM/SNS resources), plus
one new object: an SSM Parameter Store entry holding the SNS topic's
ARN. A second, entirely separate Terraform root configuration
(`consumer/`) is also built, whose only job is to read values back out
of the first configuration's state.

**How the pieces connect:**
- The role's trust policy, permission policy, and the SNS topic's
  resource policy are all **unchanged from Demo 06** — this demo
  doesn't touch policy logic at all; it's entirely about *exposing*
  values these resources already produce, not changing what the
  resources do
- `role_arn`, `role_name`, and `sns_topic_arn` (Part A's outputs) are
  the three values every other Part in this demo revolves around —
  nothing new is computed, only exposed
- `external_secret_label_out` deliberately echoes a `sensitive`
  variable from Demo 05 with no resource behind it — it exists purely
  to demonstrate output redaction rules against something guaranteed
  to be sensitive, not because CloudNova's solution needs it
- The **consumer/ configuration is its own separate Terraform root** —
  own state, own `terraform init`, own provider block. It contains
  **zero AWS resources of its own**; its only content is a
  `data.terraform_remote_state` block plus two outputs that echo
  values read from the main configuration's state file
- The **SSM parameter** (Part C) is written by the *main* configuration
  (`aws_ssm_parameter.sns_topic_arn`, using `aws_sns_topic.deploy_notifications.arn`
  directly) — it is a genuinely new AWS resource, independent of
  `consumer/`, existing purely as a second way to deliver the same ARN

**Progression across the three Parts — one value, three delivery
mechanisms, chosen by audience:**

| Consumer | Mechanism | Why this one |
|---|---|---|
| A human checking a value, or debugging | `terraform output` (Part A) | Fastest, no setup — but only works with this config's state open locally |
| Another **Terraform** configuration, same team | `terraform_remote_state` (Part B, via `consumer/`) | No new AWS resource — just read access to this config's state backend |
| A **non-Terraform** consumer (Lambda, ECS task, script), or a different team entirely | SSM Parameter Store (Part C) | Doesn't require knowing Terraform exists, or granting state-backend access |

**What each Part actually touches, concretely:**
- **Part A** adds no new AWS resources — only `07-outputs.tf`, exposing
  what Demo 06 already built
- **Part B** adds no new AWS resources to the *main* config either —
  it stands up a second, independent Terraform root (`consumer/`) that
  only reads state, never writes anything
- **Part C** adds exactly one new AWS resource — the SSM parameter —
  and is the only Part that changes what exists in AWS

By the end, the SNS topic's ARN is reachable three separate ways —
CLI output, a second Terraform config's remote-state read, and an
independently-readable SSM parameter — while the underlying AWS
resource producing that ARN (the SNS topic itself) was built once, in
Demo 06, and never touched again in this demo.

---

## Prerequisites

### Knowledge
- Demo 06 completed — the distinction test, `try()`/`coalesce()`/
  `merge()`, and the SNS topic this demo continues building on

### Required Tools

Same as Demo 05/06 — Terraform `>= 1.15.0`, AWS CLI `>= 2.x`, `jq`.

### Verify AWS Account and Permissions

```bash
aws sts get-caller-identity --profile default
aws configure get region --profile default
```

**Required permissions for this demo** (adds SSM to Demo 06's list):

```
iam:CreateRole, iam:DeleteRole, iam:GetRole, iam:ListRoles
iam:PutRolePolicy, iam:DeleteRolePolicy, iam:GetRolePolicy
iam:TagRole, iam:UntagRole, iam:ListRoleTags
iam:PassRole
sts:GetCallerIdentity
sns:CreateTopic, sns:DeleteTopic, sns:GetTopicAttributes
sns:SetTopicAttributes, sns:Publish, sns:TagResource
ssm:PutParameter, ssm:GetParameter, ssm:DeleteParameter
ssm:AddTagsToResource, ssm:ListTagsForResource
```

> For a learning account, `IAMFullAccess`, `AmazonSNSFullAccess`, and
> `AmazonSSMFullAccess` managed policies cover the permissions above.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Mark outputs `sensitive`, and explain why `ephemeral` outputs are
   restricted to child modules
2. ✅ Use `depends_on` on an output block
3. ✅ Use every `terraform output` variant: default, named, `-json`, `-raw`
4. ✅ Read another configuration's outputs via `terraform_remote_state`,
   with zero write access to that configuration's state
5. ✅ Use SSM Parameter Store as a second, decoupled sharing pattern,
   and choose between it and remote state for a given scenario

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| `aws_iam_role` / `aws_iam_role_policy` | Always free | **$0.00** | Continued from Demo 05 |
| `aws_sns_topic` | Always free — 1M publishes/month | **$0.00** | Continued from Demo 06 |
| `aws_ssm_parameter` (Standard tier) | Always free | **$0.00** | New this demo |
| **Session total** | | **$0.00** | |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
07-outputs-remote-state/
├── README.md
├── 07-outputs-remote-state-anki.csv
├── 07-outputs-remote-state-quiz.md
└── src/
    ├── 01-versions.tf       # terraform block + provider version constraints
    ├── 02-provider.tf       # AWS provider: region, profile, default_tags
    ├── 03-variables.tf      # Demo 06's finished variable set, recreated
    ├── 04-locals.tf         # Demo 06's finished locals, recreated (IAM + SNS)
    ├── 05-main.tf           # aws_iam_role + aws_iam_role_policy
    ├── 06-sns.tf            # aws_sns_topic (continued from Demo 06)
    ├── 07-outputs.tf        # NEW — full output argument depth this demo teaches
    ├── 08-ssm.tf            # NEW — aws_ssm_parameter, SecureString
    ├── consumer/
    │   └── main.tf           # NEW — separate config, reads role_arn via terraform_remote_state
    └── break-fix/
        └── broken.tf
```

---

## Recall Check — Demo 06

Answer from memory before reading further:

1. What is the distinction test for choosing a `local` over a `variable`?
2. `merge(local.caller_tags, local.base_tags)` was written when the
   intent was "caller overrides base." What actually happens, and why?
3. Two locals reference each other: `a = "prefix-${local.b}"` and
   `b = "suffix-${local.a}"`. What happens, and when is it detected?

<details>
<summary>Answers</summary>

1. If the value would ever need to be overridden from outside the
   configuration (different per environment, engineer, or run), it's a
   variable. If it's always derived from other values in the
   configuration and never needs external input, it's a local.
2. `base_tags`'s values win instead of `caller_tags`'s — `merge()` uses
   right-most-wins for key conflicts, and `base_tags` was listed last.
   There's no error; it silently applies the opposite of the intended
   precedence. Fix: reverse the argument order.
3. `terraform plan` errors with "Cycle in local values" — detected at
   plan time, before any value is evaluated, not silently resolved or
   left to an arbitrary evaluation order.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `output` block (full depth) | Exposing values | `description`, `sensitive`, `ephemeral`, `depends_on` |
| `sensitive = true` on output | Output argument | Redacts from `terraform output` display — visible via `-json` |
| `ephemeral = true` on output | Output argument | Only valid in a **child module** — errors in the root module |
| `depends_on` on output | Output argument | Forces an explicit dependency an output wouldn't otherwise have |
| `terraform output` variants | CLI | Default (all), named (one), `-json`, `-raw` |
| `data.terraform_remote_state` | Data source | Reads another configuration's outputs from its state file |
| `aws_ssm_parameter` | Resource | `String` vs. `SecureString` — a second sharing pattern |

**Related constructs worth knowing (not used in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| `variable` block | External input | Demo 05 |
| `locals` block | Internally computed values | Demo 06 |
| Child modules | Reusable configuration units | Not built in this series yet — referenced here only for the ephemeral-output restriction |
| `for` expression (full) | Collection transformation | Demo 09 |

---

### Detailed Explanation of New Constructs

#### `output` — Complete Argument Syntax

```hcl
output "role_arn" {
  description = "ARN of the IAM deploy role"
  value       = aws_iam_role.deploy.arn
  sensitive   = false
  depends_on  = [aws_iam_role_policy.deploy]
}
```

| Argument | Required | Description |
|---|---|---|
| `value` | Yes | The expression to expose |
| `description` | No | Human-readable description — shown by `terraform output` tooling |
| `sensitive` | No | Redacts from `terraform output` display (not from `-json`) |
| `ephemeral` | No | Never written to state — **root-module restriction applies, see below** |
| `depends_on` | No | Forces an explicit dependency the `value` expression doesn't already imply |

---

#### `sensitive = true` on an Output — Redacted Display, Not Redacted Data

When `sensitive = true`: `terraform apply`'s final output list shows
`(sensitive value)`; `terraform output` (default, no args) shows
`(sensitive value)`; `terraform output -json` shows the actual value in
plaintext; `terraform output <name>` alone still shows `(sensitive
value)` unless `-raw` or `-json` is used.

```hcl
output "external_secret_label" {
  value     = var.external_secret_label
  sensitive = true
}
```

> **Marking an output `sensitive` doesn't change what flows through
> it — only how it displays.** If the underlying value is already
> `sensitive` (like `var.external_secret_label` from Demo 05),
> Terraform requires the output to also be marked `sensitive` — this
> is enforced, not optional, and is exactly the check that catches
> Break-Fix Error 1 below.

---

#### `ephemeral = true` on an Output — Child-Module-Only Restriction

Demo 05 introduced the two valid ephemeral contexts: a child-module
ephemeral output, and a write-only resource argument. `ephemeral = true` on an output only works in a **child module** — not a root module. Every demo in this series so far has been a root module, so this restriction is explained conceptually here rather than demonstrated working; child modules aren't built until later in this series.

```hcl
output "session_token_echo" {
  value     = var.session_token
  ephemeral = true
}
```

```
Error: Ephemeral outputs not allowed in root module
  Ephemeral output values are only supported in child modules — the
  root module's outputs are the module's boundary of stability.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

**Why the restriction exists:** an ephemeral value's entire point is that nothing persists it. A root module's outputs are the final result of `apply` — there's no
"downstream" consumer left to hand an ephemeral value to safely. A child module's outputs, by contrast, flow into whatever called that module, which might itself be another ephemeral context. This series doesn't build child modules until later, so this restriction is explained here conceptually rather than demonstrated working.



---

#### `depends_on` on an Output

```hcl
output "role_arn" {
  value      = aws_iam_role.deploy.arn
  depends_on = [aws_iam_role_policy.deploy]
}
```

**When this is needed:** normally, an output's `value` expression
already creates an implicit dependency — referencing
`aws_iam_role.deploy.arn` means Terraform waits for that resource.
`depends_on` on an output is for the rarer case where the *value*
doesn't reference a resource directly, but you still need Terraform to
wait for it — for example, an output describing a side effect of a
resource rather than one of its attributes.

> **Most outputs never need `depends_on`.** If your `value` expression
> already references the resource, the dependency is implicit and
> automatic — only add `depends_on` when the value genuinely doesn't
> reference what it logically depends on.

---

#### `terraform output` — All Variants

| Command | Shows |
|---|---|
| `terraform output` (no argument) | Every output; `sensitive` ones shown as `<sensitive>` |
| `terraform output NAME` | That one output's value — **in plaintext, even if `sensitive`** |
| `terraform output -json` | Every output as JSON, plaintext for all, including sensitive |
| `terraform output -json NAME` | That one output as JSON, plaintext |
| `terraform output -raw NAME` | That one output's raw value, no quotes, plaintext |

> **Only the bare, no-argument `terraform output` actually redacts
> anything.** The instant you name a specific output — `terraform
> output NAME` — Terraform prints its plaintext value, with no flag
> required at all. Verified directly:
> ```
> $ terraform output
> external_secret_label_out = <sensitive>
> $ terraform output external_secret_label_out
> "demo-secret-label"
> ```
> This is the sharpest illustration yet that `sensitive` redacts a
> specific *display mode* (the summary list), not the value itself —
> naming the output by itself is enough to see it in plaintext.

> **`terraform output` accepts at most one output name.** `terraform
> output role_arn external_secret_label_out` errors: "The output
> command expects exactly one argument... or no arguments to show all
> outputs."

```bash
terraform output
terraform output role_arn
terraform output -json
terraform output -json role_arn
terraform output -raw role_arn
```

> **`-json` and `-raw` both bypass `sensitive` redaction.** This isn't
> a bug — it's why `sensitive` was never encryption to begin with (a
> point already made about variables in Demo 05, and equally true for
> outputs): the flag hides display, not access. Anyone who can run
> `terraform output -json` already has access to state.

---

#### `data.terraform_remote_state` — Reading Another Configuration's Outputs

```hcl
data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = "tfstate-cloudnova-<account-id>-us-east-2"
    key    = "phase-1/07-outputs-remote-state/terraform.tfstate"
    region = "us-east-2"
  }
}

# Referenced as:
data.terraform_remote_state.iam.outputs.role_arn
```

**What it does:** reads the *entire state file* of another
configuration (identified by backend + key) and exposes its outputs
under `.outputs`. Requires only read access to that state's backend —
no write access, no access to the other configuration's `.tf` files at
all.

**What it does NOT do:** it does not give the reading configuration any
ability to modify the source configuration's resources — it's
read-only by construction, since it's reading a state *file*, not
invoking Terraform against that configuration.

> **A `sensitive` output is still readable via remote state.** Per the
> `sensitive`-vs-`ephemeral` distinction from Demo 05: `sensitive`
> values persist in state, so `terraform_remote_state` can read them
> (they'd display as `(sensitive value)` if you tried to output them
> further downstream, following the same redaction rule). `ephemeral`
> values are never in state at all — there's nothing for
> `terraform_remote_state` to read.

---

#### `aws_ssm_parameter` — A Second Sharing Pattern

```hcl
resource "aws_ssm_parameter" "sns_topic_arn" {
  name  = "/cloudnova/${var.environment}/sns-deploy-notifications-arn"
  type  = "SecureString"
  value = aws_sns_topic.deploy_notifications.arn
  tags  = local.sns_tags
}
```

| Argument | Description |
|---|---|
| `name` | Parameter path — hierarchical, `/`-separated by convention |
| `type` | `String` (plaintext) or `SecureString` (KMS-encrypted at rest) |
| `value` | The value to store |

**`String` vs. `SecureString`:** `String` stores the value in plaintext
in Parameter Store. `SecureString` encrypts it with a KMS key (the
default AWS-managed key unless `key_id` is specified) — decrypted only
on read, by callers with `kms:Decrypt` permission. For any value that
was `sensitive` upstream (like an ARN derived from a sensitive
context, or literally any credential), `SecureString` is the correct
choice — writing it as `String` is exactly Break-Fix Error 3 below.

---

#### Sharing Patterns — Remote State vs. SSM vs. Env Vars vs. Hardcoding

| Pattern | Read access needed | Write coupling | Best for |
|---|---|---|---|
| `terraform_remote_state` | Read access to the source state backend | None — fully decoupled reads | Terraform-to-Terraform sharing, same team/org |
| SSM Parameter Store | `ssm:GetParameter` IAM permission | None — fully decoupled reads | Cross-team, cross-tool (non-Terraform consumers too), sensitive values via `SecureString` |
| Environment variables (`TF_VAR_`) | N/A — set at runtime | Manual, per-run | CI/CD pipeline injection, not persistent sharing |
| Hardcoding the value | N/A | Full — breaks the moment the source changes | Never, for anything that can change |

> **When to choose SSM over remote state:** when the consumer isn't
> Terraform at all (an application reading its own config at runtime),
> or when you don't want to grant state-backend read access just to
> share one value. Remote state is the better choice for
> Terraform-to-Terraform sharing on the same team, since it doesn't
> require provisioning a new resource just to pass a value along.

---

## Lab Step-by-Step Guide

---

## Part A — Rebuilding the Baseline & Marking Outputs

**What you accomplish in Part A:** recreate the IAM role and SNS topic
exactly as Demo 06 left them, then write this demo's actual focus —
`07-outputs.tf` with full argument depth: `sensitive`, the ephemeral
restriction (explained, not demonstrated working), and `depends_on`.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/07-outputs-remote-state/src
```

### Step 1.5 — Create the S3 state bucket (one-time)

This demo's entire Part B depends on state genuinely living in S3 —
`terraform_remote_state` reads a state *file*; there's nothing to read
if state stays local. Create the bucket once, before `terraform init`:


```bash
aws s3api create-bucket \
  --bucket tfstate-cloudnova-163125980376-us-east-2 \
  --profile default \
  --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2

aws s3api put-bucket-versioning \
  --bucket tfstate-cloudnova-163125980376-us-east-2 \
  --profile default \
  --region us-east-2 \
  --versioning-configuration Status=Enabled
```

Versioning is optional but recommended for state files — it gives a rollback path if
state is ever accidentally corrupted or overwritten.

> **Backend blocks cannot reference variables or locals.** The bucket
> name above is a literal string, not `var.aws_region`-driven — this
> is a real Terraform constraint: backend configuration is evaluated
> before the rest of the configuration even loads, so nothing dynamic
> is available to it yet.

### Step 2 — Create the source files

---

#### `01-versions.tf` — Provider and Terraform version pins


**01-versions.tf:**

```hcl
terraform {
  required_version = "~> 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47.0"
    }
  }

  backend "s3" {
    bucket       = "tfstate-cloudnova-163125980376-us-east-2"
    # ↑ replace <account-id> with your own account ID — bucket names
    # must be globally unique, and including the account ID is the
    # usual convention for that
    key          = "phase-1/07-outputs-remote-state/terraform.tfstate"
    # ↑ path within the bucket — keeps every demo's state organized
    # under one bucket, one subfolder per demo
    region       = "us-east-2"
    profile      = "default"
    encrypt      = true
    use_lockfile = true
    # ↑ S3-native locking (Terraform 1.11+) — no DynamoDB table needed
  }
}
```

---

#### `02-provider.tf` — AWS provider configuration

**02-provider.tf:**

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = local.common_tags
  }
}
```

---

#### `03-variables.tf` — Demo 06's finished variable set, recreated

**What this file does in this demo:** provides the same inputs Demo 06
finished with — `role_config` and `extra_tags` included — no new
variables are needed for output/remote-state teaching itself. Copy
this file verbatim from Demo 06's finished `03-variables.tf`, plus the
two additions Demo 06 made in its own Part B (`role_config`,
`extra_tags`) — reproduced here in full so it can be created directly
from this README.

**03-variables.tf:**

```hcl
# ── Provider configuration ─────────────────────────────────────────────────

variable "aws_region" {
  type        = string
  description = "AWS region for all resources"
  default     = "us-east-2"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI named profile for authentication"
  default     = "default"
}

# ── Project identity ───────────────────────────────────────────────────────

variable "project" {
  type        = string
  description = "Project name — used in resource names and tags"
  default     = "cloudnova"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.project))
    error_message = "project must be 3–20 lowercase alphanumeric characters or hyphens, starting with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "dev"
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "demo" {
  type        = string
  description = "Demo identifier — used in tags for traceability"
  default     = "07-outputs-remote-state"
}

# ── Role configuration ─────────────────────────────────────────────────────

variable "role_purpose" {
  type        = string
  description = "Short purpose label for the IAM role — becomes part of the role name"
  default     = "deploy"

  validation {
    condition     = length(var.role_purpose) <= 20 && can(regex("^[a-z][a-z0-9-]*$", var.role_purpose))
    error_message = "role_purpose must be lowercase alphanumeric or hyphens, max 20 characters."
  }
}

variable "trusted_account_ids" {
  type        = list(string)
  description = "List of AWS account IDs allowed to assume this role. Empty list = self-trust (current account only)."
  default     = []

  validation {
    condition     = alltrue([for id in var.trusted_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "All trusted_account_ids must be 12-digit AWS account IDs."
  }
}

variable "allowed_actions" {
  type        = list(string)
  description = "IAM actions this role is permitted to perform"
  default     = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
}

variable "custom_role_name" {
  type        = string
  description = "Optional: override the computed role name. If null, a name is computed from project+environment+purpose."
  default     = null
  nullable    = true
}

# ── Sensitive and ephemeral demonstration ──────────────────────────────────

variable "external_secret_label" {
  type        = string
  description = "A label for an external secret — sensitive, stored in state but redacted from output"
  default     = "demo-secret-label"
  sensitive   = true
}

variable "session_token" {
  type        = string
  description = "A short-lived token — ephemeral, never written to state"
  default     = "demo-session-token"
  ephemeral   = true
}

# ── Role instance configuration ────────────────────────────────────────────

variable "max_session_duration" {
  type        = number
  description = "Maximum session duration in seconds (3600–43200)"
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 (1 hour) and 43200 (12 hours)."
  }
}

# ── Demo 06 additions — role_config and extra_tags ─────────────────────────

variable "role_config" {
  type = object({
    description      = optional(string)
    path             = optional(string, "/")
    max_session_secs = optional(number, 3600)
  })
  description = "Optional structured role configuration. All fields are optional."
  default     = {}
  nullable    = false
}

variable "extra_tags" {
  type        = map(string)
  description = "Additional tags to merge onto all resources — caller-provided tags override defaults"
  default     = {}
}
```

---

#### `04-locals.tf` — Demo 06's finished locals, recreated

**What this file does in this demo:** recreates Demo 06's complete
locals block — role locals (including `try()`/`coalesce()`) and SNS
locals (`sns_topic_name`, `sns_topic_policy`, `sns_tags`) — unchanged.
This demo adds no new locals; it exposes what's already computed.

**04-locals.tf:**

```hcl
data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  role_name   = var.custom_role_name != null ? var.custom_role_name : "${local.name_prefix}-${var.role_purpose}-role"
  policy_name = "${local.name_prefix}-${var.role_purpose}-policy"

  trusted_principals = length(var.trusted_account_ids) > 0 ? [
    for id in var.trusted_account_ids : "arn:aws:iam::${id}:root"
  ] : ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]

  trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAssumeRole"
        Effect    = "Allow"
        Principal = { AWS = local.trusted_principals }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  permission_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowedActions"
        Effect   = "Allow"
        Action   = var.allowed_actions
        Resource = "*"
      }
    ]
  })

  # try() safely reads the optional description field — see Demo 06 Part B
  role_description = try(
    var.role_config.description,
    "CI/CD deploy role for ${var.project} ${var.environment}"
  )

  # coalesce(): falls through to var.max_session_duration if unset
  effective_max_session = coalesce(
    try(var.role_config.max_session_secs, null),
    var.max_session_duration
  )

  # merge() — caller-supplied extra_tags win on any key conflict
  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      Demo        = var.demo
      ManagedBy   = "Terraform"
      Owner       = "platform-team"
    },
    var.extra_tags
  )

  # SNS locals — reuse name_prefix, trusted_principals, common_tags from above
  sns_topic_name = "${local.name_prefix}-deploy-notifications"

  sns_topic_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountPublish"
        Effect    = "Allow"
        Principal = { AWS = local.trusted_principals }
        Action    = "sns:Publish"
        Resource  = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sns_topic_name}"
      }
    ]
  })

  sns_tags = merge(local.common_tags, {
    Purpose = "deploy-notifications"
  })
}
```

---

#### `05-main.tf` — The IAM role and its inline policy

**What this file does in this demo:** unchanged from Demo 06 — the
same `aws_iam_role.deploy`/`aws_iam_role_policy.deploy` this whole
trilogy (Demos 05–07) has been building toward.

**05-main.tf:**

```hcl
resource "aws_iam_role" "deploy" {
  name                 = local.role_name
  description          = local.role_description
  path                 = var.role_config.path
  assume_role_policy   = local.trust_policy
  max_session_duration = local.effective_max_session
  tags                 = local.common_tags
}

resource "aws_iam_role_policy" "deploy" {
  name   = local.policy_name
  role   = aws_iam_role.deploy.name
  policy = local.permission_policy
}
```

---

#### `06-sns.tf` — The SNS topic

**What this file does in this demo:** unchanged from Demo 06 — the
same `aws_sns_topic.deploy_notifications` proving locals generalize
beyond IAM.

**06-sns.tf:**

```hcl
resource "aws_sns_topic" "deploy_notifications" {
  name   = local.sns_topic_name
  policy = local.sns_topic_policy
  tags   = local.sns_tags
}
```

---

#### `07-outputs.tf` — Full output argument depth

**What this file does in this demo:** this is the file this entire
demo is about. `role_arn` demonstrates `depends_on` explicitly (even
though it's not strictly required here, to show the syntax);
`external_secret_label_out` demonstrates a `sensitive` output required
because its source variable is sensitive; `sns_topic_arn` is what
Part B and Part C both consume.

**07-outputs.tf:**

```hcl
output "role_name" {
  description = "Name of the IAM deploy role"
  value       = aws_iam_role.deploy.name
}

output "role_arn" {
  description = "ARN of the IAM deploy role"
  value       = aws_iam_role.deploy.arn
  depends_on  = [aws_iam_role_policy.deploy]
}

# Required to be sensitive — the source variable is sensitive, and
# Terraform enforces that the output must be too (Break-Fix Error 1
# shows what happens if you don't).
output "external_secret_label_out" {
  description = "Echoes the sensitive demo variable from Demo 05"
  value       = var.external_secret_label
  sensitive   = true
}

output "sns_topic_arn" {
  description = "ARN of the deploy-notifications SNS topic"
  value       = aws_sns_topic.deploy_notifications.arn
}
```

---

### Step 3 — Apply and confirm sensitive redaction

```bash
terraform init
terraform validate
terraform apply
```

Type `yes`. Expected output:

```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

external_secret_label_out = <sensitive>
role_arn = "arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role"
role_name = "cloudnova-dev-deploy-role"
sns_topic_arn = "arn:aws:sns:us-east-2:163125980376:cloudnova-dev-deploy-notifications"
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **`external_secret_label_out` shows `<sensitive>` right in the apply
> summary** — this is the same redaction `terraform output` applies
> afterward, visible immediately at apply time.

**Verify:**

```
Console → IAM → Roles → cloudnova-dev-deploy-role
  → Description, path, tags all present as expected ✅
Console → SNS → Topics → cloudnova-dev-deploy-notifications
  → Confirms the SNS topic from Demo 06 is intact ✅
```

---

## Part B — Output Variants & Remote State

**What you accomplish in Part B:** exercise every `terraform output`
variant against the outputs from Part A, then stand up a completely
separate Terraform configuration that reads `role_arn` back via
`terraform_remote_state` — with no write access to this configuration
at all.

### Step 1 — Exercise every `terraform output` variant

```bash
terraform output
```

Expected:

```
external_secret_label_out = <sensitive>
role_arn = "arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role"
role_name = "cloudnova-dev-deploy-role"
sns_topic_arn = "arn:aws:sns:us-east-2:163125980376:cloudnova-dev-deploy-notifications"
```

```bash
terraform output role_arn
```

Expected: `"arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role"`

```bash
terraform output external_secret_label_out
```

Expected: `"demo-secret-label"`

> **This is the surprising one.** No `-json`, no `-raw` — just naming
> the output directly bypasses redaction entirely.

```bash
terraform output -json external_secret_label_out
```

Expected: `"demo-secret-label"` — plaintext, `-json` bypasses redaction.

```bash
terraform output -raw role_arn
```

Expected: `arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role`
(no quotes — `-raw` is meant for shell scripting, e.g. `$(terraform
output -raw role_arn)`).

> ✅ Verified against a live run.

### Step 2 — Create the remote-state consumer configuration

Create a file **consumer/main.tf** and add the below content:


```hcl
terraform {
  required_version = "~> 1.15.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# Reads the main configuration's ENTIRE state file, read-only — this
# consuming configuration never touches the main config's .tf files
# or its ability to apply, only the outputs already recorded in state.
data "terraform_remote_state" "outputs_demo" {
  backend = "s3"
  config = {
    bucket = "tfstate-cloudnova-163125980376-us-east-2"
    key    = "phase-1/07-outputs-remote-state/terraform.tfstate"
    region = "us-east-2"
  }
}

output "consumed_role_arn" {
  description = "role_arn read back from the main configuration's state"
  value       = data.terraform_remote_state.outputs_demo.outputs.role_arn
}

output "consumed_sns_arn" {
  description = "sns_topic_arn read back from the main configuration's state"
  value       = data.terraform_remote_state.outputs_demo.outputs.sns_topic_arn
}
```

### Step 3 — Apply the consumer configuration and verify

```bash
cd consumer/
terraform init
terraform apply
```

Type `yes`. Expected output:

```
Outputs:

consumed_role_arn = "arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role"
consumed_sns_arn = "arn:aws:sns:us-east-2:163125980376:cloudnova-dev-deploy-notifications"
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **This `consumer/` configuration has never opened `05-main.tf` or
> `06-sns.tf`.** It only knows the S3 bucket/key where the main
> configuration's state lives, and its IAM permissions only need
> `s3:GetObject` on that one state file — no IAM, SNS, or any other
> service permission from the main configuration's own permission set.

### Step 4 — Confirm `sensitive` outputs remain redacted through remote state

```bash
cd ../
terraform output
```

If you were to add `data.terraform_remote_state.outputs_demo.outputs.external_secret_label_out`
to an output in `consumer/main.tf` without marking that new output
`sensitive`, Terraform would require the `sensitive` flag there too —
the redaction requirement propagates through remote state the same way
it propagates through any other reference to a sensitive value.

```bash
cd consumer/
terraform destroy
cd ../
```

Clean up the consumer configuration now — it was for demonstration only
and isn't part of this demo's Cleanup section below.

---

## Part C — SSM Parameter Store as a Second Sharing Pattern

**Why a second sharing pattern, when Part B already solved this?**
`terraform_remote_state` (Part B) only works when the consumer is
*also* Terraform, with read access to the state backend. AWS Systems
Manager Parameter Store solves the same underlying problem — "let
something else read a value this config produced" — for a broader
audience: a Lambda function, an ECS task, a script, anyone with the
right IAM permission, none of whom need to know or care that
Terraform was involved at all. It's a real AWS service (not a
Terraform-specific mechanism) built for exactly this: a simple,
hierarchical key-value store, with optional KMS encryption
(`SecureString`) for anything sensitive.

**What you accomplish in Part C:** write the SNS topic ARN into
Parameter Store as a `SecureString`, then read it back — independently
of Terraform state entirely — confirming the same ARN Part B read via
remote state is now also readable through a completely different
mechanism.

### Step 1 — Create `08-ssm.tf`

**What this file does in this demo:** writes the SNS topic ARN
(already an output as of Part A) into Parameter Store as a
`SecureString` — a second, independent way to read the same value,
without requiring `terraform_remote_state`'s state-backend access at
all.

Create a file **08-ssm.tf** and add the below content:

```hcl
resource "aws_ssm_parameter" "sns_topic_arn" {
  name  = "/cloudnova/${var.environment}/sns-deploy-notifications-arn"
  type  = "SecureString"          # encrypted at rest — this value is an ARN, not itself sensitive, but demonstrates the pattern for values that would be
  value = aws_sns_topic.deploy_notifications.arn
  tags  = local.sns_tags
}
```

### Step 2 — Apply

```bash
terraform apply
```

### Step 3 — Read the parameter back and verify against the real topic ARN

```bash
aws ssm get-parameter \
  --name "/cloudnova/dev/sns-deploy-notifications-arn" \
  --with-decryption \
  --profile default \
  --region us-east-2 \
  --query "Parameter.Value" --output text
```

Expected: matches `terraform output -raw sns_topic_arn` exactly.

> **Explicit `--profile`/`--region` flags are worth keeping even if
> your CLI has defaults configured.** Verified directly: omitting them
> here can produce `ParameterNotFound` even though the parameter
> exists — the CLI silently falls back to whatever profile/region
> environment variables or config files resolve to, which may not
> match where Terraform actually created the resource.

> **`--with-decryption` is required for `SecureString`.** Without it,
> `get-parameter` returns the KMS-encrypted ciphertext, not the
> plaintext ARN — a real, common mistake when reading `SecureString`
> parameters from the CLI for the first time.

**Verify:**

```
Console → Systems Manager → Parameter Store →
  /cloudnova/dev/sns-deploy-notifications-arn
  → Type: SecureString ✅
  → Value: (hidden by default — click "Show" to reveal, confirming
    it decrypts to the same ARN the CLI call returned) ✅
```

---

## Cleanup

```bash
terraform destroy
```

Type `yes`. Expected: `Destroy complete! Resources: 4 destroyed.`
(IAM role, inline policy, SNS topic, SSM parameter).

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

Confirm the `consumer/` configuration was already destroyed in Part B
Step 3 — if not:

```bash
cd consumer/
terraform destroy
cd ../
```

```
Console → IAM → Roles → cloudnova-dev-deploy-role: GONE ✅
Console → SNS → Topics → cloudnova-dev-deploy-notifications: GONE ✅
Console → Systems Manager → Parameter Store → /cloudnova/dev/sns-deploy-notifications-arn: GONE ✅
```

---

## What You Learned

1. ✅ `sensitive` on an output redacts `terraform output`'s default
   display but not `-json`/`-raw` — and is *required* if the
   underlying value is itself sensitive
2. ✅ `ephemeral` outputs are restricted to child modules — a root
   module's outputs are the final, stable result of `apply`, with
   nothing downstream left to consume an ephemeral value safely
3. ✅ `depends_on` on an output is for the rare case where `value`
   doesn't already imply the dependency you need
4. ✅ `terraform output`, `-json`, and `-raw` each serve a different
   consumer — human display, scripted JSON parsing, and shell
   variable capture respectively
5. ✅ `terraform_remote_state` reads another configuration's outputs
   with zero write access — and zero access to its `.tf` files at all
6. ✅ SSM Parameter Store (`String` vs. `SecureString`) is a second
   sharing pattern, better suited to non-Terraform consumers or
   cross-team boundaries than remote state

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `sensitive` on output vs. `-json`/`-raw` | TA-004 Obj 4h (sensitive data) | Common trap: assuming `-json` also redacts |
| Ephemeral output root-module restriction | TA-004 Obj 4h | Frequently tested against child modules specifically |
| `terraform_remote_state` | TA-004 Obj 6c (remote state storage — this is a state-management objective, not a domain-4 one) | Read-only by construction — no write access to the source config |
| `aws_ssm_parameter` `String` vs `SecureString` | N/A (useful AWS knowledge but isn't part of any official TA-004 objective) | `SecureString` requires `--with-decryption` on read |
### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam asks whether `terraform output -json` redacts a sensitive output | Recognizing `-json` shows the plaintext value regardless of `sensitive` | Assuming `sensitive` redacts everywhere, including `-json`/`-raw` |
| Exam shows an `ephemeral = true` output in a root module | Recognizing this errors — ephemeral outputs are child-module only | Assuming `ephemeral` works identically on variables and outputs everywhere |
| Exam reads an `SecureString` parameter without `--with-decryption` | Recognizing the returned value is still KMS ciphertext | Assuming `get-parameter` always returns plaintext regardless of type |
| Exam asks what access `terraform_remote_state` grants to the source configuration | Recognizing it's read-only — state file access, not `.tf` file or apply access | Assuming remote state read access implies some ability to modify the source |

### Exam Task — Write a complete configuration

**Task:** CloudNova needs to expose two outputs from an existing
`aws_db_instance.primary` resource: a `db_endpoint` output (not
sensitive), and a `db_password_out` output that echoes a `sensitive =
true` variable `var.db_password` used to create the instance. Write
both outputs from scratch, and write the `terraform_remote_state` data
source another configuration would use to read `db_endpoint` back.

**Block types required:** `output` (×2, one requiring `sensitive`),
`data "terraform_remote_state"` (×1)

**Official documentation:**
- [Output Values](https://developer.hashicorp.com/terraform/language/values/outputs)
- [`terraform_remote_state` Data Source](https://developer.hashicorp.com/terraform/language/state/remote-state-data)

**What to practise:**
1. Open the Output Values page — confirm which display commands bypass
   `sensitive` redaction and which don't
2. Write the configuration from scratch without looking at this
   demo's `07-outputs.tf`
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
output "db_endpoint" {
  description = "Connection endpoint for the primary database"
  value       = aws_db_instance.primary.endpoint
}

output "db_password_out" {
  description = "Echoes the sensitive DB password variable"
  value       = var.db_password
  sensitive   = true
}

# In the consuming configuration:
data "terraform_remote_state" "db" {
  backend = "s3"
  config = {
    bucket = "tfstate-example-bucket"
    key    = "path/to/this/config/terraform.tfstate"
    region = "us-east-2"
  }
}

# Referenced as: data.terraform_remote_state.db.outputs.db_endpoint
```

**Arguments you must know without looking up:**
- An output referencing a `sensitive` variable/value must itself be
  marked `sensitive` — Terraform enforces this, it isn't optional
- `terraform_remote_state`'s `config` block needs `bucket`, `key`, and
  `region` for an S3 backend — matching the source configuration's own
  backend configuration exactly

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Error: Output refers to sensitive values` | An output's `value` references a `sensitive` variable/resource attribute without `sensitive = true` on the output itself | Add `sensitive = true` to the output |
| `Error: Ephemeral outputs not allowed in root module` | An `ephemeral = true` output declared in the root module | Ephemeral outputs are child-module only — remove the flag, or move the output into a child module |
| `get-parameter` returns garbled/encrypted text instead of the expected value | Missing `--with-decryption` on a `SecureString` parameter | Add `--with-decryption` to the `aws ssm get-parameter` call |
| `terraform_remote_state` returns an error about the backend/key | `bucket`/`key`/`region` in the `config` block don't match the source configuration's actual backend | Confirm the exact bucket name and state key path from the source configuration's own `01-versions.tf` |

---

## Break-Fix Scenario

Three deliberate errors. Diagnose using `terraform validate` and
`terraform plan`/`apply` — do not look at answers first.

```bash
cd src/break-fix/
terraform init
terraform validate
terraform plan
```

#### `broken.tf` — Three deliberate output/sharing-pattern errors

**What this file does in this demo:** a self-contained configuration
with a sensitive value exposed through a non-sensitive output, an
`ephemeral` output declared in the root module, and a sensitive ARN
written to Parameter Store as plaintext `String` instead of
`SecureString` — diagnose all three.

**broken.tf:**

```hcl
terraform {
  required_version = "~> 1.15.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

variable "db_password" {
  type      = string
  sensitive = true
  default   = "demo-password-value"
}

variable "session_token" {
  type      = string
  ephemeral = true
  default   = "demo-token"
}

# Error 1: exposes a sensitive variable through a non-sensitive output
output "db_password_leak" {
  value = var.db_password
}

# Error 2: ephemeral output in the root module
output "session_token_echo" {
  value     = var.session_token
  ephemeral = true
}

resource "aws_ssm_parameter" "leaked_arn" {
  name  = "/cloudnova/demo/leaked-value"
  type  = "String" # Error 3 — should be SecureString
  value = var.db_password
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — sensitive value exposed through a non-sensitive output**
`terraform plan` errors: "Output refers to sensitive values." Any
output whose `value` references a `sensitive` variable or resource
attribute must itself be marked `sensitive = true` — Terraform enforces
this rather than leaving it to convention. Fix: add `sensitive = true`
to `db_password_leak`.

**Error 2 — ephemeral output in the root module**
`terraform plan` errors: "Ephemeral outputs not allowed in root
module." Ephemeral outputs are restricted to child modules — this
configuration has no module structure at all, so the flag is invalid
here regardless of what it's applied to. Fix: remove `ephemeral = true`
(and accept the value will be in state, since it's the root module), or
restructure so this output lives in a child module if the ephemeral
guarantee is actually required.

**Error 3 — sensitive value written to Parameter Store as plaintext**
Not a `validate`/`plan`-time error — this applies successfully and
silently stores `var.db_password` in plaintext in Parameter Store.
Diagnosed by inspecting the parameter's actual type:
`aws ssm get-parameter --name /cloudnova/demo/leaked-value --query
"Parameter.Type"` returns `"String"`, not `"SecureString"` — a real
security misconfiguration a `validate`/`plan` pass alone wouldn't catch.
Fix: change `type = "String"` to `type = "SecureString"`.

</details>

**Cleanup:**
```bash
cd src/break-fix/
terraform destroy -auto-approve
rm -f terraform.tfstate terraform.tfstate.backup
cd ../..
```

---

## Interview Prep

**Q1. A teammate says "I marked this output `sensitive`, so it's safe to reference from another configuration via remote state." What's the nuance?**
`sensitive` controls display, not access. `terraform_remote_state` can still read the value — it's in state, and remote state reads state directly. If the downstream configuration re-exposes that value in one of its own outputs, Terraform will require that new output to also be marked `sensitive` — the redaction requirement propagates, but the underlying value was never inaccessible to begin with. The real access boundary is who can read the state backend at all, not the `sensitive` flag.

**Q2. Why are ephemeral outputs restricted to child modules — what's actually different about a root module's outputs?**
A root module's outputs are the final, top-level result of `apply` — there's no "downstream Terraform consumer" left to hand an ephemeral value to safely once you're at the root. A child module's outputs, by contrast, flow into the calling module, which might itself pass them into another ephemeral context (a write-only resource argument, for instance). The restriction isn't arbitrary — it reflects that ephemeral guarantees only make sense when something further down the chain can still honor them.

**Q3. When would you choose SSM Parameter Store over `terraform_remote_state` for sharing a value between two Terraform configurations owned by the same team?**
If both configurations are Terraform, on the same team, and you're comfortable granting read access to the source state backend, `terraform_remote_state` is simpler — no extra resource to provision, no extra IAM permission to design beyond state-backend read access. SSM becomes the better choice the moment a non-Terraform consumer needs the value too (an application reading its config at runtime), or when you specifically don't want to grant state-backend access just to share one value — SSM's IAM permissions are scoped to that one parameter, not the entire state file.

**Q4. A DB password variable is `sensitive = true`. A teammate writes an SSM parameter with `type = "String"` and `value = var.db_password`. Does `terraform plan`/`apply` catch this?**
No — this is exactly Break-Fix Error 3. Marking a variable `sensitive` only affects Terraform's own terminal/plan output; it does not enforce anything about what resource arguments that value flows into afterward. Writing a sensitive value into a plaintext `String` parameter succeeds silently. This has to be caught by review or by inspecting the parameter's actual `Type` after the fact — `sensitive` gives you no automatic protection once the value leaves Terraform's own display layer.

---

## Key Takeaways

1. **`sensitive` on an output redacts default display — `-json` and
   `-raw` both bypass it.** This is consistent with `sensitive` never
   being encryption in the first place (true for variables in Demo 05,
   equally true for outputs here).

2. **An output is *required* to be `sensitive` if its value references
   anything already sensitive.** Terraform enforces this — Break-Fix
   Error 1 shows the exact failure when it's skipped.

3. **Ephemeral outputs are child-module only.** A root module's
   outputs are the final result of `apply`, with nothing downstream
   left to honor an ephemeral guarantee.

4. **`terraform_remote_state` is read-only by construction.** It reads
   a state *file*, not the source configuration's `.tf` files or its
   ability to `apply` — there is no write path through it at all.

5. **SSM Parameter Store and remote state solve the same problem for
   different audiences.** Remote state: Terraform-to-Terraform, same
   team, no extra resource. SSM: cross-team or non-Terraform consumers,
   `SecureString` for anything sensitive.

6. **A `SecureString` parameter written as plain `String` isn't caught
   by `validate` or `plan`.** It applies successfully and silently
   stores the value in plaintext — a review-time or inspection-time
   catch, not a Terraform-enforced one.

> **Demo scope:** Primary concept: outputs as an interface — full
> argument depth (`sensitive`, `ephemeral`, `depends_on`) and every
> `terraform output` display variant. Supporting concepts:
> `terraform_remote_state` as a read-only cross-configuration sharing
> mechanism, and SSM Parameter Store (`String` vs. `SecureString`) as a
> second, decoupled sharing pattern.
> Estimated completion time: 40 minutes (reading + hands-on + verification).
> Checkpoints: 3 natural stopping points (end of Part A, end of Part B,
> end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform output` | Shows all outputs; `sensitive` ones redacted |
| `terraform output -json` | Shows all outputs as JSON, including sensitive values in plaintext |
| `terraform output -raw NAME` | Shows one output's raw value, no quotes — for shell scripting |
| `aws ssm get-parameter --name PATH --with-decryption` | Reads an SSM parameter, decrypting if `SecureString` |
| `aws ssm get-parameter --query "Parameter.Type"` | Confirms whether a parameter is `String` or `SecureString` |
| `terraform destroy` (inside `consumer/`) | Tears down the remote-state consumer configuration independently |

---

## Next Demo

**Demo 08 — Data Sources:** `data` vs. `resource`, `aws_iam_policy`,
`aws_s3_bucket`, filtering, `count` on a data source, and a new
`data.aws_ami` lookup — the last purely read-only demo before Demo 09
moves into `for` expressions and collection functions in full.

---

## Appendix — Trust Policy, Permission Policy, and SNS Policy, End-to-End

**Reference values used throughout this section** (fixed, fictional —
same across every demo in this series):

| Item | Value |
|---|---|
| AWS account ID | `163125980376` |
| AWS CLI profile | `default` |
| AWS region | `us-east-2` |
| IAM role name | `cloudnova-dev-deploy-role` |
| IAM role's inline policy name | `cloudnova-dev-deploy-policy` |
| SNS topic name | `cloudnova-dev-deploy-notifications` |
| SSM parameter name | `/cloudnova/dev/sns-deploy-notifications-arn` |
| SSM parameter value | `arn:aws:sns:us-east-2:163125980376:cloudnova-dev-deploy-notifications` |

### The IAM role's two policies

- **Trust policy** (`assume_role_policy`, attached directly to
  `cloudnova-dev-deploy-role`) — answers "**who** is allowed to assume
  this role?" Its actual statement:
```json
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "AllowAssumeRole",
      "Effect": "Allow",
      "Principal": { "AWS": ["arn:aws:iam::163125980376:root"] },
      "Action": "sts:AssumeRole"
    }]
  }
```
- **Permission policy** (`cloudnova-dev-deploy-policy`, an inline
  policy attached to the same role) — answers "once assumed, **what**
  can this role's temporary credentials do?" Its actual statement:
```json
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "AllowedActions",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
      "Resource": "*"
    }]
  }
```

These are two separate documents attached to two separate parts of the
role — mixing them up is a common source of confusion.

### "Why is the trust policy's Principal `arn:aws:iam::163125980376:root`? Does that mean only the root user can assume this role?"

No. `arn:aws:iam::163125980376:root` in a **trust policy's Principal**
is AWS shorthand for **"this entire AWS account,"** not literally the
root login. It delegates trust at the account level.

Two independent checks must BOTH pass before anyone can actually
assume the role:
1. **The role's trust policy** allows the calling account (satisfied
   above, via the `:root` shorthand)
2. **The calling identity's own IAM policy** must separately grant it
   `sts:AssumeRole` permission on this specific role's ARN
   (`arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role`)

`:root` is a common, deliberately broad starting point when you don't
yet know exactly which roles/users need access. Tightening it later
means replacing `:root` with specific role/user ARNs, not the whole
account.

### "Does assuming the role grant access to any resource in the account?"

No — only to what the **permission policy**'s `Action` list allows,
scoped to `Resource = "*"` **within that same statement**. Here,
`Action` is `["s3:GetObject", "s3:PutObject", "s3:ListBucket"]`, so
`Resource = "*"` means "any S3 bucket/object" — not "any AWS resource."
IAM evaluates `Action` and `Resource` together, per statement. Granting
this role EC2 or IAM access would require an entirely separate
statement naming those actions explicitly — nothing in this demo does
that; the role genuinely can only touch S3.

### "Does that mean only the root user can publish to the SNS topic?"

Same clarification as above — the SNS topic's own resource policy also
uses `arn:aws:iam::163125980376:root` as its Principal:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowAccountPublish",
    "Effect": "Allow",
    "Principal": { "AWS": ["arn:aws:iam::163125980376:root"] },
    "Action": "sns:Publish",
    "Resource": "arn:aws:sns:us-east-2:163125980376:cloudnova-dev-deploy-notifications"
  }]
}
```
This again delegates trust to the **whole account**, not the literal
root login. Any identity in that account with its own `sns:Publish`
permission can publish — which is exactly why publishing worked in
this demo using a regular IAM user, not the account's actual root
login.

### "How does the `consumer/` configuration access the S3 bucket?"

`consumer/main.tf`'s `provider "aws"` block specifies only `region =
"us-east-2"` — no `profile`. With no profile set, Terraform falls back
to the AWS SDK's standard credential resolution chain: environment
variables first, then the `default` profile in
`~/.aws/credentials`/`~/.aws/config`, then (on EC2/ECS) an instance or
task role. In this series' setup, that resolves to the same `default`
profile used everywhere else — the same identity that ran every other
`terraform apply` in this demo.

**What permission is actually required:** reading a state file via
`data.terraform_remote_state` needs `s3:GetObject` on the exact state
object (`s3://tfstate-cloudnova-163125980376-us-east-2/phase-1/07-outputs-remote-state/terraform.tfstate`),
and typically `s3:ListBucket` on the bucket itself (some IAM policy
designs scope this more tightly per-prefix). **Locking permissions
are NOT required for this read** — `use_lockfile` locking exists to
protect a configuration's own state during its own `plan`/`apply`;
reading a *different* configuration's state via `terraform_remote_state`
is a plain read, not a write, so it never acquires or needs a lock at
all. This demo doesn't test the *boundary* of that read permission
(see point 4 below) — it only demonstrates that the read succeeds when
using an identity that already has full S3 access.

---

## Appendix — Anki Cards

**07-outputs-remote-state-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::07-outputs-remote-state
#separator:Comma
#columns:Front,Back,Tags
"An output is marked sensitive = true. Which terraform output command actually redacts it?","Only the bare, no-argument terraform output (listing all outputs) redacts to <sensitive>. Naming the output directly — terraform output NAME — prints the plaintext value immediately, with no -json or -raw flag needed at all.","demo07,outputs,sensitive,ta004-obj4h"
"An output's value references a variable marked sensitive = true, but the output itself has no sensitive argument. What happens?","terraform plan errors: 'Output refers to sensitive values.' Terraform requires the output itself to be marked sensitive = true if its value references anything already sensitive — this is enforced, not just a convention.","demo07,outputs,sensitive,break-fix"
"Can an ephemeral = true output be declared in a root module?","No. Ephemeral outputs are restricted to child modules only. Declaring one in the root module errors: 'Ephemeral outputs not allowed in root module.' A root module's outputs are the final result of apply, with nothing downstream to honor an ephemeral guarantee.","demo07,outputs,ephemeral,ta004-obj4h"
"When is depends_on actually needed on an output block?","Only when the value expression doesn't already imply the dependency you need. Normally referencing a resource attribute (e.g. aws_iam_role.deploy.arn) creates an implicit dependency automatically — depends_on is for the rarer case where the value doesn't reference what it logically depends on.","demo07,outputs,depends_on"
"What access does data.terraform_remote_state grant to the source configuration's resources?","None beyond read access to that configuration's state file. It's read-only by construction — there is no path through terraform_remote_state to modify the source configuration's resources or even access its .tf files.","demo07,remote-state,ta004-obj6c"
"A sensitive output's value is read via terraform_remote_state in a second configuration. Is it still protected there?","Only if the second configuration also marks its own output sensitive when re-exposing that value — the redaction requirement propagates through remote state the same way it propagates through any other reference. The underlying value itself was always readable by anyone with state-backend read access.","demo07,remote-state,sensitive"
"What is the difference between an SSM aws_ssm_parameter type of String vs SecureString?","String stores the value in plaintext in Parameter Store. SecureString encrypts it with a KMS key, decrypted only on read by callers with kms:Decrypt permission. Any value that was sensitive upstream should use SecureString.","demo07,ssm"
"You read a SecureString SSM parameter with aws ssm get-parameter but forget --with-decryption. What do you get back?","The KMS-encrypted ciphertext, not the plaintext value. --with-decryption is required to get the actual decrypted value back for a SecureString parameter.","demo07,ssm,break-fix"
"A sensitive Terraform variable is written into an aws_ssm_parameter with type = String. Does terraform plan or apply catch this?","No — this succeeds silently. sensitive only affects Terraform's own terminal/plan display; it does not enforce anything about what resource arguments that value flows into afterward. This has to be caught by review or by inspecting the parameter's actual Type after the fact.","demo07,ssm,sensitive,break-fix"
"When would you choose SSM Parameter Store over terraform_remote_state for sharing a value between two Terraform configs on the same team?","When a non-Terraform consumer also needs the value (an application reading config at runtime), or when you don't want to grant state-backend read access just to share one value. Remote state is simpler when both sides are Terraform and state-backend read access is acceptable.","demo07,ssm,remote-state,decision"
"List the four terraform output display variants and what each is for.","terraform output (all, sensitive redacted) — for humans. terraform output NAME (one, sensitive redacted) — for humans, one value. terraform output -json (all, plaintext even if sensitive) — for scripted JSON parsing. terraform output -raw NAME (one, no quotes, plaintext even if sensitive) — for shell variable capture.","demo07,outputs,cli,ta004-obj4h"
"Rank the four value-sharing patterns (remote state, SSM, env vars, hardcoding) by write coupling — from none to full.","No coupling (fully decoupled reads): terraform_remote_state and SSM Parameter Store — both read independently, no write-side coordination needed. Manual per-run coupling: environment variables (TF_VAR_) — set at runtime, not persistent. Full coupling: hardcoding a value — breaks immediately the moment the source changes. Hardcoding is appropriate for nothing that can ever change.","demo07,sharing-patterns,comparison"
```

---

## Appendix — Quiz

**07-outputs-remote-state-quiz.md:**

````markdown
# Quiz — Demo 07: Outputs, Sensitivity, and Remote State

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 08.

---

**Q1. (True/False)** `terraform output -json` redacts a `sensitive =
true` output the same way the default `terraform output` display does.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `-json` (and `-raw`) both bypass sensitive redaction and
show the plaintext value. Only the default `terraform output` display
(and `terraform output NAME` without a flag) redact to `(sensitive
value)`.

</details>

---

**Q2. (Multiple Choice)** An output's `value` references a variable
marked `sensitive = true`, but the output has no `sensitive` argument
of its own. What happens?

- A) It works fine — sensitivity is a variable-only concern
- B) `terraform plan` errors — the output must also be marked `sensitive`
- C) It's silently redacted with no error
- D) Terraform prompts to confirm

<details>
<summary>Answer</summary>

**B.** This is an enforced requirement, not a suggestion — any output
referencing something already sensitive must itself carry `sensitive =
true`, or `plan` errors immediately.

</details>

---

**Q3. (True/False)** An `ephemeral = true` output works identically
whether declared in a root module or a child module.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Ephemeral outputs are restricted to child modules only —
declaring one in a root module errors with "Ephemeral outputs not
allowed in root module." A root module's outputs are the final result
of `apply`, with nothing downstream left to honor the guarantee.

</details>

---

**Q4. (Multiple Choice)** What is the most accurate description of what
`data.terraform_remote_state` grants access to?

- A) Full read/write access to the source configuration's resources
- B) The source configuration's `.tf` files directly
- C) Read-only access to the source configuration's outputs, via its state file
- D) The ability to trigger `terraform apply` remotely on the source configuration

<details>
<summary>Answer</summary>

**C.** It's read-only by construction — it reads a state *file*, never
the source configuration's `.tf` files, and grants no ability to modify
or apply the source configuration.

</details>

---

**Q5. (Multiple Choice)** Why is `sensitive = true` on a Terraform
variable insufficient to prevent that value from being written into an
`aws_ssm_parameter` as plaintext `type = "String"`?

- A) `sensitive` isn't a real Terraform argument
- B) `sensitive` only affects Terraform's own terminal/plan display — it enforces nothing about what resource arguments the value flows into
- C) `plan` catches this, but `apply` doesn't
- D) SSM parameters are always encrypted regardless of `type`

<details>
<summary>Answer</summary>

**B.** This applies successfully and silently — neither `plan` nor
`apply` validates what downstream arguments a sensitive value ends up
in. Catching this requires review or inspecting the parameter's actual
`Type` after the fact.

</details>

---

**Q6. (Multiple Choice)** You run `aws ssm get-parameter --name
/path/to/param` on a `SecureString` parameter, without
`--with-decryption`. What do you get back?

- A) The plaintext value, same as always
- B) An error refusing to run
- C) The KMS-encrypted ciphertext
- D) An empty string

<details>
<summary>Answer</summary>

**C.** The command succeeds but returns the raw encrypted value.
`--with-decryption` is required to get the actual plaintext back for a
`SecureString` parameter — a genuinely common first-time mistake.

</details>

---

**Q7. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about `depends_on` on an output block are correct?

- A) It's required on every output that references a resource attribute
- B) Most outputs never need it — referencing a resource attribute already creates an implicit dependency
- C) It's needed only when the `value` expression doesn't already reference what it logically depends on
- D) It marks the output as sensitive
- E) It changes the order outputs are displayed in `terraform output`

<details>
<summary>Answer</summary>

**B and C.** The vast majority of outputs get their dependency for free
through the `value` expression's own resource reference. `depends_on`
exists for the rarer case where the value doesn't reference what it
actually depends on. `sensitive` (D) is a separate, unrelated argument,
and display order (E) isn't affected by `depends_on` at all.

</details>

---

**Q8. (Multiple Choice)** Two Terraform configurations are owned by the
same team. Configuration B needs one value from Configuration A. Which
factor would push you toward SSM Parameter Store instead of
`terraform_remote_state`?

- A) Configuration B is also Terraform
- B) Configuration B's team is comfortable with state-backend read access
- C) A non-Terraform application also needs to read that same value at runtime
- D) The value is a string, not a number

<details>
<summary>Answer</summary>

**C.** This is the clearest signal to prefer SSM — `terraform_remote_state`
only works for a Terraform-to-Terraform read; a non-Terraform runtime
consumer needs something like SSM instead. A and B actually favor
remote state (simpler, no extra resource); the value's type (D) is
irrelevant to this decision.

</details>

---

**Q9. (Multiple Choice)** `data.terraform_remote_state.iam.outputs.role_arn`
is referenced in a new output in the consuming configuration, without
marking that new output `sensitive`, even though `role_arn` was
sensitive in the source configuration. What happens?

- A) Nothing — sensitivity doesn't propagate across configurations
- B) `terraform plan` errors — the redaction requirement propagates through remote state exactly as it would through any other reference
- C) The value is automatically encrypted
- D) Only the source configuration's output stays redacted; the new one displays it in plaintext with no error

<details>
<summary>Answer</summary>

**B.** Sensitivity requirements follow the reference chain — reading a
sensitive value through `terraform_remote_state` and re-exposing it in
a new output still triggers the same enforcement as any other sensitive
reference.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8-9/9 | Import Anki cards, move to Demo 08 |
| 6-7/9 | Review the wrong answers, then proceed |
| 5/9 | Re-read the relevant sections, retry those questions |
| Below 5/9 | Re-read the full demo and redo the walkthrough before proceeding |
````