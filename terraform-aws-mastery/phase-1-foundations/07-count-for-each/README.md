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

**Answers**

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
ephemeral output, and a write-only resource argument. This demo is
where the child-module restriction actually matters — attempting an
`ephemeral = true` output in a **root module** (which is what every
demo in this series has been so far) errors:

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

**Why the restriction exists:** an ephemeral value's entire point is
that it's never persisted. A root-module output is the final,
top-level result of `apply` — there's nothing "downstream" left to
consume an ephemeral value safely at that point, so Terraform doesn't
allow the combination at all. This series doesn't build child modules
until later, so this restriction is explained here conceptually rather
than demonstrated working.

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
| `terraform output` | Every output, `sensitive` ones redacted |
| `terraform output role_arn` | Just that one output, redacted if `sensitive` |
| `terraform output -json` | Every output as JSON, **including sensitive values in plaintext** |
| `terraform output -json role_arn` | Just that one, as JSON, plaintext even if `sensitive` |
| `terraform output -raw role_arn` | Just the raw value, no quotes — plaintext even if `sensitive` |

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
variables are needed for output/remote-state teaching itself.

**03-variables.tf:** *(identical to Demo 06's finished `03-variables.tf`
— all of Demo 05's variables plus `role_config` and `extra_tags`)*

---

#### `04-locals.tf` — Demo 06's finished locals, recreated

**What this file does in this demo:** recreates Demo 06's complete
locals block — role locals (including `try()`/`coalesce()`) and SNS
locals (`sns_topic_name`, `sns_topic_policy`, `sns_tags`) — unchanged.
This demo adds no new locals; it exposes what's already computed.

**04-locals.tf:** *(identical to Demo 06's finished `04-locals.tf`)*

---

#### `05-main.tf` — The IAM role and its inline policy

**What this file does in this demo:** unchanged from Demo 06.

**05-main.tf:** *(identical to Demo 06's `05-main.tf`)*

---

#### `06-sns.tf` — The SNS topic

**What this file does in this demo:** unchanged from Demo 06.

**06-sns.tf:** *(identical to Demo 06's `06-sns.tf`)*

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

Expected: `<sensitive>`

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

> ⚠️ Simulated expected output for all five commands above — not from
> a live terminal run in this environment.

### Step 2 — Create the remote-state consumer configuration

**`consumer/main.tf`:**

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

data "terraform_remote_state" "outputs_demo" {
  backend = "s3"
  config = {
    bucket = "tfstate-cloudnova-<account-id>-us-east-2"
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

Replace `<account-id>` with your own account ID before applying.

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
terraform output -raw external_secret_label_out
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

**What you accomplish in Part C:** write the SNS topic ARN to Parameter
Store as a `SecureString`, read it back independently of Terraform
state entirely, and confirm it matches the real topic ARN.

### Step 1 — Create `08-ssm.tf`

**08-ssm.tf:**

```hcl
resource "aws_ssm_parameter" "sns_topic_arn" {
  name  = "/cloudnova/${var.environment}/sns-deploy-notifications-arn"
  type  = "SecureString"
  value = aws_sns_topic.deploy_notifications.arn
  tags  = local.sns_tags
}
```

### Step 2 — Apply and verify against the real topic ARN

```bash
terraform apply
aws ssm get-parameter \
  --name "/cloudnova/dev/sns-deploy-notifications-arn" \
  --with-decryption \
  --query "Parameter.Value" --output text
```

Expected: matches `terraform output -raw sns_topic_arn` exactly —
`arn:aws:sns:us-east-2:163125980376:cloudnova-dev-deploy-notifications`.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **`--with-decryption` is required for `SecureString`.** Without it,
> `get-parameter` returns the KMS-encrypted ciphertext, not the
> plaintext ARN — a real, common mistake when reading `SecureString`
> parameters from the CLI for the first time.

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

## Cert Tips — TA-004 Objectives Covered

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `sensitive` on output vs. `-json`/`-raw` | TA-004 Obj 4 (Terraform outside core workflow) | Common trap: assuming `-json` also redacts |
| Ephemeral output root-module restriction | TA-004 Obj 4 | Frequently tested against child modules specifically |
| `terraform_remote_state` | TA-004 Obj 4 | Read-only by construction — no write access to the source config |
| `aws_ssm_parameter` `String` vs `SecureString` | TA-004 Obj (AWS resource management) | `SecureString` requires `--with-decryption` on read |

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

## Appendix — Anki Cards

**07-outputs-remote-state-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::07-outputs-remote-state
#separator:Comma
#columns:Front,Back,Tags
"An output is marked sensitive = true. Does terraform output -json still redact it?","No. -json (and -raw) show the actual plaintext value regardless of the sensitive flag. Only the default terraform output display (and terraform output NAME without -json/-raw) redacts to (sensitive value). sensitive controls display, not access.","demo07,outputs,sensitive,ta004"
"An output's value references a variable marked sensitive = true, but the output itself has no sensitive argument. What happens?","terraform plan errors: 'Output refers to sensitive values.' Terraform requires the output itself to be marked sensitive = true if its value references anything already sensitive — this is enforced, not just a convention.","demo07,outputs,sensitive,break-fix"
"Can an ephemeral = true output be declared in a root module?","No. Ephemeral outputs are restricted to child modules only. Declaring one in the root module errors: 'Ephemeral outputs not allowed in root module.' A root module's outputs are the final result of apply, with nothing downstream to honor an ephemeral guarantee.","demo07,outputs,ephemeral,ta004"
"When is depends_on actually needed on an output block?","Only when the value expression doesn't already imply the dependency you need. Normally referencing a resource attribute (e.g. aws_iam_role.deploy.arn) creates an implicit dependency automatically — depends_on is for the rarer case where the value doesn't reference what it logically depends on.","demo07,outputs,depends_on"
"What access does data.terraform_remote_state grant to the source configuration's resources?","None beyond read access to that configuration's state file. It's read-only by construction — there is no path through terraform_remote_state to modify the source configuration's resources or even access its .tf files.","demo07,remote-state,ta004"
"A sensitive output's value is read via terraform_remote_state in a second configuration. Is it still protected there?","Only if the second configuration also marks its own output sensitive when re-exposing that value — the redaction requirement propagates through remote state the same way it propagates through any other reference. The underlying value itself was always readable by anyone with state-backend read access.","demo07,remote-state,sensitive"
"What is the difference between an SSM aws_ssm_parameter type of String vs SecureString?","String stores the value in plaintext in Parameter Store. SecureString encrypts it with a KMS key, decrypted only on read by callers with kms:Decrypt permission. Any value that was sensitive upstream should use SecureString.","demo07,ssm,ta004"
"You read a SecureString SSM parameter with aws ssm get-parameter but forget --with-decryption. What do you get back?","The KMS-encrypted ciphertext, not the plaintext value. --with-decryption is required to get the actual decrypted value back for a SecureString parameter.","demo07,ssm,break-fix"
"A sensitive Terraform variable is written into an aws_ssm_parameter with type = String. Does terraform plan or apply catch this?","No — this succeeds silently. sensitive only affects Terraform's own terminal/plan display; it does not enforce anything about what resource arguments that value flows into afterward. This has to be caught by review or by inspecting the parameter's actual Type after the fact.","demo07,ssm,sensitive,break-fix"
"When would you choose SSM Parameter Store over terraform_remote_state for sharing a value between two Terraform configs on the same team?","When a non-Terraform consumer also needs the value (an application reading config at runtime), or when you don't want to grant state-backend read access just to share one value. Remote state is simpler when both sides are Terraform and state-backend read access is acceptable.","demo07,ssm,remote-state,decision"
"List the four terraform output display variants and what each is for.","terraform output (all, sensitive redacted) — for humans. terraform output NAME (one, sensitive redacted) — for humans, one value. terraform output -json (all, plaintext even if sensitive) — for scripted JSON parsing. terraform output -raw NAME (one, no quotes, plaintext even if sensitive) — for shell variable capture.","demo07,outputs,cli,ta004"
```

---

## Appendix — Quiz

**07-outputs-remote-state-quiz.md:**

```markdown
# Quiz — Demo 07: Outputs, Sensitivity, and Remote State

> One correct answer per question unless stated otherwise.
> Target: 80% or above before moving to Demo 08.
> TA-004 exam style.

---

**Q1.** An output is marked `sensitive = true`. Which command shows its
actual plaintext value?

A. `terraform output`
B. `terraform output NAME`
C. `terraform output -json`
D. None — sensitive values are never displayed by any command

<details>
<summary>Answer</summary>

**C.** `-json` (and `-raw`) bypass sensitive redaction and show the
plaintext value. **A** and **B** are wrong — both show `(sensitive
value)` for a sensitive output. **D** is wrong — `-json`/`-raw` do show
it in plaintext; redaction is display-only, not universal.

</details>

---

**Q2.** An output's `value` references a `sensitive = true` variable,
but the output itself has no `sensitive` argument. What happens?

A. It works fine — sensitivity only applies to variables, not outputs
B. `terraform plan` errors — the output must also be marked `sensitive`
C. The output is silently redacted without needing the flag
D. Terraform prompts interactively to confirm

<details>
<summary>Answer</summary>

**B.** Terraform enforces that an output referencing a sensitive value
must itself be marked `sensitive = true` — this is a `plan`-time error,
not a suggestion. **A** is wrong — sensitivity requirements propagate
from variables/resources into outputs that reference them. **C** is
wrong — there's no automatic silent redaction; the flag is required
explicitly. **D** is wrong — Terraform never resolves this
interactively; it's a hard error.

</details>

---

**Q3.** Can an `ephemeral = true` output be declared in a root module?

A. Yes, identically to a child module
B. No — ephemeral outputs are restricted to child modules
C. Yes, but only if `sensitive = true` is also set
D. Yes, but only for outputs referencing data sources

<details>
<summary>Answer</summary>

**B.** Ephemeral outputs are restricted to child modules — a root
module's outputs are the final result of `apply`, with nothing
downstream to honor an ephemeral guarantee. **A** is wrong — this is
exactly the restriction being tested. **C** and **D** are wrong —
there's no combination of other arguments that makes an ephemeral
root-module output valid; the restriction is absolute.

</details>

---

**Q4.** What access does `data.terraform_remote_state` grant to the
source configuration it reads from?

A. Full read/write access to the source configuration's resources
B. Read-only access to that configuration's outputs, via its state file
C. The ability to trigger `terraform apply` on the source configuration
D. Access to the source configuration's `.tf` files directly

<details>
<summary>Answer</summary>

**B.** It reads the source configuration's state file and exposes its
outputs — read-only, by construction. **A** is wrong — there is no
write path through remote state at all. **C** is wrong — remote state
reads a file; it never invokes Terraform against the source
configuration. **D** is wrong — it never touches `.tf` files, only the
state file's recorded outputs.

</details>

---

**Q5.** You read a `SecureString` SSM parameter with `aws ssm
get-parameter` but forget `--with-decryption`. What do you get back?

A. The plaintext value, same as always
B. An error — the command refuses to run without the flag
C. The KMS-encrypted ciphertext, not the plaintext value
D. An empty string

<details>
<summary>Answer</summary>

**C.** Without `--with-decryption`, `get-parameter` returns the raw
encrypted value for a `SecureString` parameter. **A** is wrong — that's
only true for `String` type parameters, or `SecureString` *with* the
flag. **B** is wrong — the command runs successfully; it just returns
ciphertext, not an error. **D** is wrong — a value is returned, just not
a usable plaintext one.

</details>

---

**Q6.** A `sensitive = true` Terraform variable is written into an
`aws_ssm_parameter` with `type = "String"`. Does `terraform plan` or
`apply` catch this as an error?

A. Yes, `terraform plan` refuses to proceed
B. Yes, but only `terraform apply` catches it
C. No — it applies successfully and stores the value in plaintext
D. No — Terraform automatically upgrades it to `SecureString`

<details>
<summary>Answer</summary>

**C.** This succeeds silently. `sensitive` only affects Terraform's own
terminal/plan display — it enforces nothing about what resource
arguments that value subsequently flows into. **A** and **B** are wrong
— neither `plan` nor `apply` validates this. **D** is wrong — Terraform
never silently changes a resource argument's value; `type` stays
exactly as written.

</details>

---

**Q7.** When would SSM Parameter Store be the better choice over
`terraform_remote_state` for sharing a value between two Terraform
configurations on the same team?

A. Never — remote state is always superior for Terraform-to-Terraform sharing
B. When a non-Terraform consumer also needs the value, or you don't want to grant state-backend read access
C. Only when the value is a number, not a string
D. Only when both configurations use the same S3 backend bucket

<details>
<summary>Answer</summary>

**B.** SSM's IAM permissions are scoped to one parameter, useful when
you want to avoid granting broader state-backend access, or when a
non-Terraform consumer (an application at runtime) needs the value
too. **A** is wrong — SSM has genuine advantages in specific scenarios.
**C** is wrong — the value's type has no bearing on this decision. **D**
is wrong — using the same bucket has nothing to do with which sharing
pattern is more appropriate.

</details>

---

**Q8.** What is `depends_on` on an output block actually for?

A. It's required on every output that references a resource
B. It's for the rare case where the `value` expression doesn't already imply a needed dependency
C. It marks the output as sensitive
D. It controls the order outputs are displayed in `terraform output`

<details>
<summary>Answer</summary>

**B.** Most outputs never need `depends_on` — referencing a resource
attribute in `value` already creates an implicit dependency. It's only
needed when the value doesn't reference what it logically depends on.
**A** is wrong — the vast majority of outputs work fine without it. **C**
is wrong — that's the unrelated `sensitive` argument. **D** is wrong —
display order isn't something `depends_on` affects at all.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 08 |
| 7/8 | Review the wrong answer, then proceed |
| 6/8 | Re-read the relevant section, retry those questions |
| Below 6/8 | Re-read the full demo and redo the walkthrough before proceeding |
```