# Demo 22b — Cost Governance: Notify-Only Automation + Static Analysis

---

## Overview

22a gave the persistent build a durable state backend, split into two
independent state files — `platform/terraform.tfstate` (created once,
never torn down) and `workloads/terraform.tfstate` (torn down and
re-applied every session). This demo is the first one to actually
write real resources into that backend, and everything it builds
belongs in `platform/`: cost governance is meant to protect every
future session, not get destroyed and recreated alongside the VPC and
EKS cluster that `workloads/` will hold from 22d onward.

Everything this demo builds is about catching a cost problem *after*
it happens (detection), not preventing it from happening at all
(prevention). That distinction matters and gets stated explicitly, not
left implied.

**Real-world scenario — CloudNova:**
Once 22d stands up the EKS cluster, the environment starts accruing a
flat, continuous fee whether or not you remember to tear it down at
the end of a session. Leadership's only real ask before compute goes
live: know quickly if a session runs long or spend crosses a
threshold — don't find out from the bill. That's a detection
requirement, not an auto-remediation one — nobody asked for
infrastructure that can delete itself, and this project doesn't build
that even though it was considered.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — EventBridge + SNS: session-length notify                     │
│  Scheduled rule checks tagged resources → SNS notification only        │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — AWS Budgets: two-threshold spend alarm                       │
│  50% early warning, 80% escalated notification                         │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Static analysis: tflint + checkov, local and interim         │
│  Runs before every real apply from this demo onward                    │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- Detection versus prevention as a real, distinct design choice — not
  just a caveat, an explicit trade-off with a stated reason
- `aws_cloudwatch_event_rule` on a schedule expression, paired with an
  SNS target — publish/subscribe mechanics applied to infrastructure
  monitoring instead of application events
- `aws_sns_topic_policy` as a standalone resource-based policy, which
  is a different shape from the inline `policy` argument Demo 06 used
- Encrypting an SNS topic at rest with an AWS managed KMS key, at no
  additional cost
- `aws_budgets_budget` with multiple notification thresholds
- Why this project deliberately does **not** pair either mechanism
  with an auto-remediation Lambda
- `tflint` and `checkov` as CLI tools that run *outside* Terraform
  entirely — not Terraform resources, not provisioners — and the real
  configuration each one requires to actually run
- Writing into 22a's `platform/` state as the second config to use it,
  and what that state boundary does and doesn't protect

**What this demo does NOT cover:**
- The idle-check's actual filter condition against real, tagged
  workload resources — those don't exist until 22d. This demo builds
  the notification plumbing and the `Tier` tag those resources will
  carry.
- Pipeline-integrated scanning (Demo 32) or Policy as Code (Demo 33) —
  this demo's `tflint`/`checkov` run is local and interim.

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** a scheduled EventBridge rule that
checks tagged Phase 3+ resources against a session-length threshold and
publishes to an SNS topic if exceeded; a two-threshold AWS Budgets
alarm watching total account spend; and a local `tflint`/`checkov`
workflow that isn't AWS infrastructure at all, but governs every real
apply from here forward.

**Why three unrelated-looking mechanisms sit in one demo:** all three
answer the same underlying question — how to know if something's gone
wrong with cost or configuration before it becomes expensive or
dangerous — from three different angles (idle-time detection,
spend-threshold detection, and pre-apply configuration review). None
of the three requires compute to exist first, which is why this demo
runs before 22d's cluster, not after. None of them touches
`retail-store-sample-app` at all.

**Where the state lives, and what that boundary actually protects.**
This demo writes into `src/platform/` — the same directory and the
same `platform/terraform.tfstate` key 22a's `backend.tf` already
points at. It adds no backend of its own; it reuses the file 22a
created, unchanged. 22c (ECR/ACM re-creation) and Demo 24 (IAM
identity) will later add their own files into this same directory and
state. **This is deliberately not the same state `workloads/` uses.**
22d's VPC and EKS cluster live in `workloads/terraform.tfstate`, a
separate key in the same bucket — a `terraform destroy` run inside
`src/workloads/` structurally cannot reach anything this demo builds,
and a destroy run inside `src/platform/` structurally cannot reach the
VPC or cluster. What a `platform/` destroy *can* reach is every other
resource sharing that same state — this demo's own resources, plus
whatever 22c and Demo 24 add later. That's exactly why this demo's
Cleanup is a verification step, not a teardown.

**Why this demo has no Cleanup that tears anything down:** these are
free or near-free governance resources meant to protect every session
from here forward, not artifacts of a single teaching rep. Destroying
and recreating them every session would defeat their purpose for no
cost benefit — the same reasoning 22a used for the state bucket
itself.

---

## Prerequisites

### Knowledge
- 22a completed — the persistent, platform/workloads-split S3 backend
  this demo's state is written into
- Demo 03 completed — SNS topic → subscription mechanics
- Demo 06 completed — `aws_sns_topic` and the `jsonencode()` policy
  pattern this demo's topic policy reuses

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | `~> 1.15.0` | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version --region us-east-2` |
| `tflint` | `>= 0.46.0` — ⚠️ [VERIFY: the exact minimum required by the pinned `0.48.0` ruleset release hasn't been independently re-confirmed against that release's own changelog; check before treating this floor as final] | `tflint --version` |
| `checkov` | Latest stable | `checkov --version` |

### Verify AWS Account and Permissions

**Step 1 — Confirm your profile works:**

```bash
aws sts get-caller-identity --profile default --region us-east-2
```

**Step 2 — A cheap, harmless dry-run of this demo's actual service:**

```bash
aws budgets describe-budgets --account-id <YOUR_ACCOUNT_ID> --profile default --region us-east-2
# Expected: JSON with Budgets array (may be empty)
```

**Step 3 — Verify IAM permissions in Console:**

```
Console → IAM → Users → <your user> → Permissions tab
  → Confirm access to EventBridge, Budgets, and SNS (or an equivalent
    broad policy) is attached ✅
```

> 📷 [Screenshot placeholder: AWS Console → IAM → Users → your user →
> Permissions tab, showing the attached EventBridge/Budgets/SNS policies]

**Required permissions beyond what prior demos established:**

```
events:PutRule, events:PutTargets, events:DescribeRule, events:DeleteRule
budgets:CreateBudget, budgets:DescribeBudget, budgets:ModifyBudget, budgets:DeleteBudget
sns:CreateTopic, sns:Subscribe, sns:Publish, sns:SetTopicAttributes
kms:DescribeKey, kms:GetKeyPolicy   # for the AWS managed KMS key used in Part A
```

### Versions used in this demo

| Tool | Version |
|---|---|
| Terraform | `~> 1.15.0` |
| AWS Provider | `~> 6.47.0` |
| AWS CLI | `>= 2.x` |
| `tflint-ruleset-aws` | `0.48.0` — current release as of this writing; check the plugin's own GitHub releases page for anything newer before setup |

> **Versions pinned as of September 2026.** These two Terraform/AWS
> Provider pins come from `Solution-Architecture.md`, not from this
> demo — they are the project-wide versions every demo in the series
> uses. `tflint` itself and the `tflint-ruleset-aws` plugin **are**
> pinned in this demo (Part C), and `version` is not optional once
> `source` is set: omitting it makes `tflint --init` fail outright.
> `checkov` is left unpinned in this table since it isn't a
> Terraform-adjacent dependency in the same way — pin whatever is
> current stable when you set this up.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain the difference between detection and prevention as cost
   controls, and why this project deliberately chose detection-only
2. ✅ Write an `aws_cloudwatch_event_rule` on a schedule, targeting an
   SNS topic
3. ✅ Write a standalone `aws_sns_topic_policy` that grants an AWS
   service permission to publish, scoped to one specific source ARN
4. ✅ Encrypt an SNS topic at rest with an AWS managed KMS key, and
   explain why that key carries no additional monthly cost
5. ✅ Write an `aws_budgets_budget` with two independent notification
   thresholds
6. ✅ Explain why `tflint` and `checkov` aren't Terraform resources or
   provisioners, configure both correctly, and know where they
   actually run in the workflow
7. ✅ Explain why an auto-remediation Lambda was considered and
   rejected for this specific project
8. ✅ Explain what a shared `platform/` state does and doesn't
   protect, and why that's different from being shared with
   `workloads/`

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| EventBridge scheduled rule (`aws_cloudwatch_event_rule`) | Rule evaluation and same-account delivery to an SNS target carry no publishing charge — confirmed against AWS's own EventBridge pricing page. The commonly-cited "14M/month free" figure belongs to EventBridge **Scheduler**, a separate, newer service from the classic scheduled rule this demo actually uses | **$0.00** | One rule, checked hourly — the classic rule/target pattern used here has no per-invocation fee to begin with |
| SNS topic + email subscription | 1,000 email notifications/month free | **$0.00** | Notify-only traffic is tiny at lab scale |
| AWS managed KMS key (`alias/aws/sns`), used for SNS encryption at rest | Storage of an AWS managed key is always free; only API requests against it are billed, with 20,000 free requests/month | **$0.00 in practice** | A lab-scale topic with a handful of publishes/month stays far inside the free API-request allowance. This is different from a *customer managed* KMS key, which costs $1/month flat regardless of use — this demo deliberately uses the AWS managed key, not a customer managed one |
| AWS Budgets | Budgets with no `action` block attached are unlimited and free, permanently — confirmed against AWS's own Budgets pricing. (Action-enabled budgets get a separate, smaller free allowance; this project uses neither an `action` block nor needs that allowance) | **$0.00** | Notification-only — no `action` block anywhere in this demo |
| `tflint` / `checkov` | Open-source, local CLI | **$0.00** | No AWS resource at all — runs on your machine |
| **Session total** | | **$0.00** | Created once, left standing — see Cleanup |

---

## Directory Structure

```
22b-cost-governance/
├── README.md
├── 22b-cost-governance-anki.csv
├── 22b-cost-governance-quiz.md
└── src/
    ├── platform/                        # 22a's own directory — created once, never torn down
    │   ├── 01-versions.tf               # terraform block + provider version constraints
    │   ├── 02-provider.tf               # AWS provider: region, profile, default_tags
    │   ├── 03-backend.tf                # points at 22a's S3 backend, key platform/terraform.tfstate
    │   ├── 04-variables.tf              # identity, notification email, budget limit
    │   ├── 05-locals.tf                 # common_tags (incl. Tier = platform) consumed by default_tags
    │   ├── 06-cost-governance.tf        # EventBridge rule + SNS topic/target/policy
    │   ├── 07-budgets.tf                # aws_budgets_budget, two thresholds
    │   ├── 08-outputs.tf                # topic ARN and budget name
    │   ├── terraform.tfvars.example     # committed template — real tfvars stays local
    │   ├── .tflint.hcl                  # tflint ruleset config — not a .tf file
    │   └── .checkov.yaml                # checkov config — not a .tf file
    └── break-fix/
        └── broken.tf
```

> **Reuse note — `01-versions.tf` through `03-backend.tf`:** `01-versions.tf`
> and `03-backend.tf` are identical in content to the files 22a already
> created in `src/platform/`. If you're working in the same checkout
> you already have them — this demo lists them again so it can be run
> and verified independently, and so their numbering fits this demo's
> own file sequence. `02-provider.tf` is new here (22a's bootstrap
> config has its own separate provider file; the `platform/` and
> `workloads/` configs get theirs from whichever demo first writes real
> resources into them — for `platform/`, that's this demo).

> **Why `.tflint.hcl` and `.checkov.yaml` live in the same directory
> but aren't numbered `.tf` files:** neither tool is a Terraform
> provider or resource — they're external CLI programs that read your
> `.tf` files directly from disk and report on them. Their config files
> configure the *tool*, not any AWS infrastructure.

> **Why `terraform.tfvars` itself isn't listed:** both variables this
> demo introduces (`notification_email`, `monthly_budget_limit`) are
> genuinely personal. The committed file is the `.example` template;
> your real `terraform.tfvars` stays local and gitignored, matching
> the repository convention `Solution-Architecture.md` sets.

---

## Recall Check — 22a (State Backend Bootstrap)

Answer from memory before reading further:

1. Why can't a Terraform backend's own storage be created by the
   configuration that uses it as a backend?
2. Can a `backend` block ever reference a variable, local, or output
   value, in any Terraform version?
3. Why isn't this backend torn down between sessions like most Phase
   3+ resources?

<details>
<summary>Answers</summary>

1. Chicken-and-egg problem — `terraform init` needs a working backend
   before Terraform can manage any resource, including one meant to
   create that same backend. Requires a separate bootstrap config.
2. No, never — a `backend` block is resolved before Terraform has an
   evaluation context for variables, locals, or outputs. Every
   argument must be a literal value.
3. Destroying and recreating it every session would destroy the state
   history it exists to preserve, defeating its purpose. Only
   cost-accruing compute/networking resources follow the
   every-session teardown default.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `aws_cloudwatch_event_rule` | Resource | Scheduled rule — fires on a cron-like interval |
| `schedule_expression` | Resource argument | Rate or cron expression controlling how often the rule fires |
| `aws_cloudwatch_event_target` | Resource | Connects the rule to what it notifies — the SNS topic here |
| `aws_sns_topic_subscription` (email protocol) | Resource | Subscribes a real email address to receive the notification |
| `aws_sns_topic_policy` | Resource | Standalone resource-based policy — a different shape from Demo 06's inline `policy` argument |
| `kms_master_key_id` on `aws_sns_topic` | Resource argument | Enables encryption at rest; `"alias/aws/sns"` selects the free, AWS managed key |
| `aws_budgets_budget` | Resource | Account-level spend tracking with configurable notification thresholds |
| `notification` block (nested, repeatable) | Resource sub-block | One per threshold — this demo uses two, at 50% and 80% |
| `backend "s3"` block (consuming, not creating) | `terraform` block setting | Points this config at 22a's already-bootstrapped `platform/` key |
| `tflint` | External CLI tool, not a Terraform construct | Lints `.tf` files for style/correctness issues before they're ever applied |
| `checkov` | External CLI tool, not a Terraform construct | Scans `.tf` files for security/compliance misconfigurations before apply |

**Related constructs worth knowing (not used in full here):**

| Construct | What it is | Where it's covered |
|---|---|---|
| `event_pattern` | Event-driven rule matching, the alternative to `schedule_expression` | Not used in this series yet |
| `aws_scheduler_schedule` | EventBridge **Scheduler** — a separate, newer service from the classic rule used here | Not used in this series |
| Customer managed KMS key (`aws_kms_key`) | A key you create and pay $1/month for, versus the free AWS managed key used here | Not used in this series yet |
| Budgets Actions (`action` block) | Auto-remediation attached to a budget | Deliberately not used — see the detection/prevention section below |
| Policy as Code (Sentinel/OPA) | Enforced, automated policy gates | Demo 33 |
| Pipeline-integrated scanning | `tflint`/`checkov` as a real CI stage, plus image scanning | Demo 32 (formalized), Demo 34 (extended) |

---

### Detailed Explanation of New Constructs

#### Detection vs. Prevention — A Real Design Choice, Not a Caveat

Every mechanism in this demo is a detection control. None of them stop
spend from happening — they tell you about it, at various speeds and
via various signals, after the fact:

```
┌────────────────────────────────────────────────────────────────────┐
│  DETECTION (what this demo builds)                                 │
│  - EventBridge notify: fast, proactive, checks a specific idle-time │
│    condition this project defined                                   │
│  - Budgets alarm: slower (spend-based, lags actual usage), but      │
│    checks the thing that actually matters — total dollars           │
│  Both: tell you something happened. Neither stops it from happening.│
├────────────────────────────────────────────────────────────────────┤
│  PREVENTION (deliberately NOT built here)                           │
│  - A Lambda paired with the EventBridge rule that force-destroys    │
│    tagged resources once the idle threshold is crossed              │
│  - Considered, explicitly rejected                                   │
└────────────────────────────────────────────────────────────────────┘
```

**Why prevention was rejected here, specifically:** this is a
single-learner lab, not shared production infrastructure. An
auto-remediation Lambda that misfires — a false-positive idle
detection destroying real work-in-progress mid-session — is a worse
failure mode than the cost risk it would solve. A notification gets
most of the practical benefit (you find out quickly, before the
Budgets alarm's slower spend-based signal would catch it) without that
downside. This isn't a universal rule for all AWS environments — a
shared team environment with strict cost SLAs might reasonably make
the opposite trade-off. It's the right call for *this* project's
actual shape (one learner, real work sessions, thin cost margin).

---

#### `aws_cloudwatch_event_rule` and `aws_cloudwatch_event_target`

| Argument | Required | Description |
|---|---|---|
| `schedule_expression` | Yes (or `event_pattern`, not used here) | `rate(1 hour)` or a `cron(...)` expression — this demo checks hourly |
| `state` | No (default: `"ENABLED"`) | `ENABLED`/`DISABLED` — whether the rule is actively firing |

`aws_cloudwatch_event_target` connects a rule to what happens when it
fires — in this demo, publishing to the SNS topic that then emails
you. The rule and target are two separate resources because a single
rule can fan out to multiple targets; this demo only needs one.

> **On `state` versus `is_enabled`:** older examples you'll find online
> set `is_enabled = true` on this resource. That argument is deprecated
> in favour of `state`, which takes a string rather than a boolean and
> can express more than two conditions. Use `state`; don't copy
> `is_enabled` forward from an older sample.
>
> **✅ Verified against a live run:** `terraform plan` against this
> demo's own configuration reports `state = "ENABLED"` as the argument
> the provider actually returns.

---

#### `aws_sns_topic_policy` — A Different Shape from Demo 06's Inline Policy

Demo 06 set an SNS access policy using the `policy` argument *inside*
the `aws_sns_topic` resource itself. This demo uses
`aws_sns_topic_policy`, a separate resource that attaches a policy to
a topic by ARN. Both produce a resource-based policy on the topic; the
standalone resource is the shape to reach for when the policy needs to
reference something (here, the EventBridge rule's ARN) that doesn't
exist yet at the point the topic is declared.

The `jsonencode()` + `Principal` + `Condition` composition inside it is
the same pattern Demo 06 taught — what's new is the resource wrapper
around it, and the `Service` principal form rather than an account ARN.

> **What the `Condition` block is actually doing:** `Principal =
> { Service = "events.amazonaws.com" }` on its own would trust *any*
> EventBridge rule in the account. The `ArnEquals` condition on
> `aws:SourceArn` narrows that to this one specific rule. Dropping the
> condition wouldn't produce an error — it would silently widen the
> policy, which is exactly the kind of thing Part C's static analysis
> exists to flag.

---

#### Encrypting the SNS Topic — a Real, Free-Tier-Confirmed Fix

Running `checkov` against this demo's `aws_sns_topic` (Part C)
surfaces a genuine, applicable finding: `CKV_AWS_26`, "Ensure all data
stored in the SNS topic is encrypted." This finding is real and cheap
to fix, so it's fixed directly rather than skipped:

```hcl
resource "aws_sns_topic" "cost_alerts" {
  name              = "cloudnova-cost-alerts"
  kms_master_key_id = "alias/aws/sns" # AWS managed key — no monthly fee
}
```

`"alias/aws/sns"` is the AWS managed KMS key AWS creates automatically
the first time an SNS topic in the account requests it. Storage of an
AWS managed key is always free; only the API calls made against it are
billed, and those come with 20,000 free requests/month — far more than
a low-volume cost-alerts topic will ever use. A *customer managed* KMS
key (`aws_kms_key`), by contrast, costs a flat $1/month whether or not
it's ever used. This demo uses the AWS managed key specifically because
there's no requirement here for custom key policies, rotation control,
or cross-account key sharing — the reasons you'd reach for a customer
managed key instead.

---

#### `aws_budgets_budget` — Two Independent Thresholds

| Argument | Required | Description |
|---|---|---|
| `budget_type` | Yes | `"COST"` — tracks spend, not usage quantity |
| `limit_amount` / `limit_unit` | Yes | Your available AWS credit/budget figure, in `USD`. `limit_amount` is a **string** in the provider schema, not a number |
| `time_unit` | Yes | `"MONTHLY"` — resets each month |
| `notification` (block, repeatable) | Yes, one per threshold | Each defines its own `threshold` percentage and `subscriber_email_addresses` |

This demo's `notification` blocks: one at `threshold = 50` (early
warning), one at `threshold = 80` (escalated notification) — matching
the two-threshold design decided at the project level. Both notify the
same email; a real team setup might route the 80% threshold to a
different, more urgent channel.

---

#### Writing Into a Shared `platform/` State — What the Boundary Does and Doesn't Protect

22a's platform/workloads split means a `terraform destroy` run inside
`src/workloads/` can never reach anything this demo builds, and one
run inside `src/platform/` can never reach the VPC or EKS cluster.
That's a real, structural guarantee — not a convention someone has to
remember.

What it does **not** give you is isolation *within* `platform/`
itself. 22c and Demo 24 will add their own files into this same
directory and state. From that point forward, a `terraform destroy`
run in `src/platform/` reaches this demo's resources *and* theirs — a
different kind of shared blast radius than the one the platform/
workloads split solves. This is exactly why this demo, and every other
`platform/`-tier demo, ends with a verification step instead of a
teardown: the state is shared within the tier by design, since
everything in it is meant to be created once and left standing
together.

---

## Lab Step-by-Step Guide

---

## Part A — EventBridge + SNS Notify

Part A builds the EventBridge rule and the SNS topic that notifies you
if a Phase 3+ session runs long, along with the foundation files the
rest of this demo's configuration sits on.

### Step 1 — Navigate to the project config

```bash
cd terraform-aws-mastery/phase-3-real-aws-infrastructure/22b-cost-governance/src/platform
```

### Step 2 — Create the foundation files

This step establishes the version pins, provider configuration,
backend wiring and baseline inputs this demo's resources depend on.
None of these files create AWS infrastructure on their own.

---

#### `01-versions.tf` — Terraform and provider version pins

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

#### `03-backend.tf` — Pointing at 22a's `platform/` state

This is 22a's own `backend.tf`, reused unchanged (see the reuse note
in Directory Structure above). It's what makes this demo the first
config to actually write real resources into the persistent backend
22a created. Every argument here is a literal — backend blocks are
resolved before Terraform has variables or locals available, which is
the point Recall Check question 2 covers.

**03-backend.tf:**

```hcl
terraform {
  backend "s3" {
    bucket = "<YOUR_22A_STATE_BUCKET_NAME>"
    # ↑ output from 22a, pasted in as a literal string — identical to
    # 22a's own src/platform/backend.tf. A backend block cannot
    # reference var.*/local.*/module outputs, at any Terraform version.

    key    = "platform/terraform.tfstate"
    # ↑ everything created once and left standing — this demo's
    # governance resources, plus ECR/ACM (22c) and IAM identity
    # (Demo 24) once built. The workloads config uses a different key
    # in the same bucket, and is never reachable from here.

    region  = "us-east-2"
    profile = "default"
    encrypt = true

    use_lockfile = true
  }
}
```

> Replace `<YOUR_22A_STATE_BUCKET_NAME>` with the bucket 22a actually
> created — don't guess at it. `terraform init` fails immediately and
> harmlessly if the name is wrong, which is the cheapest possible way
> to find out.

---

#### `04-variables.tf` — Identity and notification inputs

This file declares the project identity values that feed tagging, plus
the one input every notification in this demo depends on: the real
email address that receives both the session-length and budget alerts.
`notification_email` deliberately has no default, since a real email
address shouldn't be hardcoded into a file that might get committed.

**Only declare `notification_email` here for now** — `monthly_budget_limit`
belongs to Part B, and is added to this same file in Step 2 of Part B,
once the budget resource that actually needs it exists. Declaring a
variable before anything uses it is harmless, but setting a *value*
for a variable that isn't declared yet produces a real, visible
warning — Step 3's tfvars file is deliberately scoped to avoid that.

**04-variables.tf:**

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
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "dev"
  nullable    = false
}

variable "demo" {
  type        = string
  description = "Demo identifier — used in tags for traceability"
  default     = "22b-cost-governance"
}

# ── Notification ───────────────────────────────────────────────────────────

variable "notification_email" {
  type        = string
  description = "Email address to receive cost and budget notifications"
  # No default — set this in terraform.tfvars, don't hardcode a real
  # email into a file that might get committed
}
```

---

#### `05-locals.tf` — The tag set every resource inherits

These tags are what the session-length check is eventually meant to
filter on, so they aren't decoration — they're the mechanism by which
a Phase 3+ resource becomes visible to this demo's detection logic.
`Tier = "platform"` is the tag that later distinguishes this demo's
resources (and 22c's, and Demo 24's) from anything in `workloads/`.

**05-locals.tf:**

```hcl
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Demo        = var.demo
    ManagedBy   = "Terraform"
    Tier        = "platform"
  }
}
```

### Step 3 — Create the tfvars template

This step creates the committed template with only the one variable
declared so far. Copy it to `terraform.tfvars` and fill in your real
email; leave that copy gitignored.

**terraform.tfvars.example:**

```hcl
notification_email = "you@example.com"
```

### Step 4 — Create the SNS topic, subscription, schedule and policy

This step creates the SNS topic, its email subscription, the scheduled
EventBridge rule, its target, and the resource policy that lets
EventBridge actually publish to the topic — five new resources, none
of which exist yet. The topic is also encrypted at rest using the
free, AWS managed KMS key — see Concepts above for why.

**06-cost-governance.tf:**

```hcl
resource "aws_sns_topic" "cost_alerts" {
  name              = "cloudnova-cost-alerts"
  kms_master_key_id = "alias/aws/sns" # AWS managed key — no monthly fee
}

resource "aws_sns_topic_subscription" "cost_alerts_email" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_cloudwatch_event_rule" "session_length_check" {
  name                = "cloudnova-session-length-check"
  description         = "Checks tagged Phase 3+ resources against a session-length threshold"
  schedule_expression = "rate(1 hour)" # hourly — deliberately low-frequency, see Interview Prep Q2
  state               = "ENABLED"      # not is_enabled — that argument is deprecated
}

resource "aws_cloudwatch_event_target" "notify_sns" {
  rule      = aws_cloudwatch_event_rule.session_length_check.name
  target_id = "cost-alerts-sns"
  arn       = aws_sns_topic.cost_alerts.arn
}

# EventBridge needs explicit permission to publish to this SNS topic —
# this is a resource-based policy on the SNS topic, not an IAM role
resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.cost_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.cost_alerts.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.session_length_check.arn
        }
      }
    }]
  })
}
```

> ⚠️ [VERIFY — open item, not a defect in this file] This rule's
> target publishes on a schedule; the actual idle-resource-check
> *logic* it's meant to gate on (which resources, what threshold
> counts as "too long") depends on real, `Tier = "workloads"`-tagged
> resources that don't exist until 22d onward. This demo builds the
> notification *plumbing* and the tag set those resources will carry;
> the specific check condition should be revisited once 22d's actual
> resource tags are applied.

### Step 5 — Apply and confirm the email subscription

This step creates all five resources above for the first time and
confirms the email subscription is genuinely active, not merely
created. Nothing existing is being modified — this is a first apply
into an empty `platform/` state.

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

> ✅ Verified against a live run. `terraform init` downloads the
> pinned AWS provider and configures the S3 backend; `terraform
> validate` passes cleanly; `terraform plan` reports exactly 5
> resources to add. The provider also reports a `region` argument on
> every resource (defaulting to the provider's own region) — this is a
> per-resource region-override capability added in a recent AWS
> provider major version, not something this demo configures
> explicitly.

```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

> **Bolded takeaway:** expect exactly 5 resources here — the topic, its
> subscription, the EventBridge rule, its target, and the topic
> policy.

SNS email subscriptions require manual confirmation. Check your inbox
for an "AWS Notification - Subscription Confirmation" email and click
the confirmation link. Until you do, the subscription shows
`PendingConfirmation` in Console and won't receive anything — and
because the pending state lives in AWS rather than in your
configuration, `terraform plan` will keep reporting no changes while
the subscription sits unusable.

**Verify:**

```
Console → SNS → Topics → cloudnova-cost-alerts → Subscriptions
  → Status: Confirmed (after clicking the email link) ✅
Console → SNS → Topics → cloudnova-cost-alerts → Encryption
  → SSE enabled, using alias/aws/sns ✅
```

> 📷 [Screenshot placeholder: AWS Console → SNS → Topics →
> cloudnova-cost-alerts, Subscriptions tab showing Status: Confirmed,
> and the Encryption tab showing SSE enabled with alias/aws/sns]

---

## Part B — AWS Budgets Alarm

Part B adds a second, independent detection layer — an AWS Budgets
alarm watching total account spend rather than any single resource's
runtime.

### Step 1 — Add the budget limit variable and its tfvars value

This step adds the one remaining input this demo needs — your own real
budget figure, again with no default since it's genuinely personal to
your account. It's typed `string` because the provider's
`limit_amount` argument is a string, not a number.

Add to **04-variables.tf**:

```hcl
variable "monthly_budget_limit" {
  type        = string
  description = "Your available AWS credit/budget for this project, in USD"
  # No default — this is genuinely personal to your account; set it
  # in terraform.tfvars
}
```

Now that the variable exists, add its value to `terraform.tfvars.example`:

```hcl
notification_email   = "you@example.com"
monthly_budget_limit = "50"
```

> **Why this is added now, not back in Part A:** a value in
> `terraform.tfvars` for a variable that hasn't been declared yet
> produces a real Terraform warning — "Value for undeclared variable"
> — at every `init`, `validate`, and `plan`. It's harmless to the
> apply itself, but it's a distracting, avoidable warning. Declaring
> the variable and setting its value in the same step keeps the two in
> sync.

### Step 2 — Create the budget resource

This step adds the one budget resource this demo builds, with two
`notification` blocks and no `action` block, since this is deliberately
a notify-only design. This creates one new resource; nothing existing
is modified.

Create a file **07-budgets.tf** and add the below content:

```hcl
resource "aws_budgets_budget" "monthly_cost" {
  name         = "cloudnova-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }
}
```

### Step 3 — Create outputs

This step exposes the two values worth having on hand after an apply:
the topic ARN, which later demos and any manual publish test need, and
the budget's name for Console lookups.

Create a file **08-outputs.tf** and add the below content:

```hcl
output "cost_alerts_topic_arn" {
  description = "ARN of the cost-alerts SNS topic"
  value       = aws_sns_topic.cost_alerts.arn
}

output "monthly_budget_name" {
  description = "Name of the monthly cost budget"
  value       = aws_budgets_budget.monthly_cost.name
}
```

### Step 4 — Apply

This step applies the budget and outputs on top of Part A's already-
applied resources, and is a good moment to practise checking the
reported resource count against what actually changed — this apply
creates one new resource and modifies nothing else.

```bash
terraform plan
terraform apply
```

> ✅ Verified against a live run.

```
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

cost_alerts_topic_arn = "arn:aws:sns:us-east-2:<ACCOUNT_ID>:cloudnova-cost-alerts"
monthly_budget_name = "cloudnova-monthly-budget"
```

> **Bolded takeaway:** this apply adds exactly **one** new resource
> (`aws_budgets_budget.monthly_cost`) — outputs aren't counted, and the
> five resources Part A already applied are untouched, so the correct
> count here is 1, not a restatement of the project's running total. If
> an apply against already-existing state ever reports a much larger
> "added" count than the number of genuinely new resource blocks you
> just wrote, stop and read the plan before confirming — that mismatch
> is exactly the kind of signal worth catching before typing `yes`.

**Verify:**

```
Console → Billing and Cost Management → Budgets → cloudnova-monthly-budget
  → Alert thresholds: 50%, 80% ✅
  → Alert subscribers: your email ✅
```

> 📷 [Screenshot placeholder: AWS Console → Billing and Cost
> Management → Budgets → cloudnova-monthly-budget, showing both alert
> thresholds and subscriber email]

`notification_type = "ACTUAL"` alerts on money already spent. AWS
Budgets also supports `"FORECASTED"`, which alerts on a projected
trend before you actually cross the threshold — worth knowing it
exists, even though this demo uses `ACTUAL` for a simpler, more
literal first pass.

---

## Part C — Static Analysis: `tflint` and `checkov`

Part C installs and configures two static-analysis tools that run
outside Terraform entirely, checking configuration quality before any
real apply from here forward.

### Step 1 — Install both tools

This step installs both tools for the first time in this series.
Neither is a Terraform construct, so neither requires `terraform init`
or any provider.

```bash
# tflint — download the current release for your platform from
# https://github.com/terraform-linters/tflint/releases, then:
tflint --version

# checkov
pip install checkov --break-system-packages
checkov --version
```

<details>
<summary>Additional flags (reference, not required)</summary>

If your platform doesn't have a package-manager install available,
`tflint`'s releases page publishes a checksums file alongside each
platform archive — `sha256sum --ignore-missing -c checksums.txt` after
downloading both files is a quick way to confirm the archive wasn't
corrupted in transit, before unzipping and installing it to somewhere
on your `PATH` (e.g. `/usr/local/bin`).

</details>

### Step 2 — Add each tool's config file

This step adds each tool's own configuration file. Both configure the
*tool*, not any AWS infrastructure.

Create a file **.tflint.hcl** and add the below content — it enables
the AWS-specific ruleset with a real, pinned version:

```hcl
plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
```

> **`version` is not optional here.** With `source` set and `version`
> omitted, `tflint --init` fails outright with `"version" attribute
> cannot be omitted when specifying "source"`. `0.48.0` is the current
> release as of this writing — check the plugin's own GitHub releases
> page for anything newer before you set this up, and update the pin
> here rather than leaving it stale.

Create a file **.checkov.yaml** and add the below content — it scopes
checkov to Terraform:

```yaml
framework:
  - terraform
```

> **No `skip-check` list in this configuration.** Running `checkov`
> against this demo's resources surfaces one applicable finding —
> `CKV_AWS_26` ("Ensure all data stored in the SNS topic is
> encrypted"), against `aws_sns_topic.cost_alerts`. Rather than adding
> a skip for it, Step 4 of Part A already fixes it directly with
> `kms_master_key_id = "alias/aws/sns"` — a free, one-line change — so
> there's nothing left here that needs skipping. If a `checkov` run
> against your own extended configuration ever reports a finding
> that's a genuine, cheap fix like this one, fix it before reaching
> for `skip-check`; save the skip list for findings that are actually
> out of scope.

> **If `checkov` errors with `The config file doesn't appear to
> contain 'key: value' pairs`:** this means `.checkov.yaml` was read
> as empty or as something other than a YAML mapping — usually because
> the file only contains a comment, is genuinely empty, or has
> whitespace that isn't valid YAML indentation (tabs instead of
> spaces, for example). Open the file and confirm it actually contains
> the `framework:` mapping above, saved with spaces, not tabs.

### Step 3 — Run both against this demo's own config

This step runs both tools against the configuration you just wrote,
confirming neither touches AWS or Terraform state at all.

```bash
tflint --init
tflint
checkov -d .
```

> ✅ Verified against a live run, with the plugin version pinned and
> the encryption fix from Part A Step 4 in place.

```
tflint: 0 issues found.

checkov: Passed checks: 4, Failed checks: 0, Skipped checks: 0
```

<details>
<summary>Additional flags (reference, not required)</summary>

| Flag | What it does |
|---|---|
| `tflint --format=json` | Machine-readable output — useful once this moves into a pipeline at Demo 32 |
| `tflint --recursive` | Walks subdirectories instead of only the current one |
| `checkov -d . --compact` | Suppresses the per-check code snippets, printing results only |
| `checkov -d . --quiet` | Prints failed checks only, hiding passes |
| `checkov --skip-check <ID>` | Skips a check inline instead of via `.checkov.yaml` |

</details>

Neither command touched AWS or Terraform state — both read your `.tf`
files directly off disk and report findings. That's why they aren't
Terraform resources or provisioners: they run *around* the Terraform
workflow, not inside it. From this demo forward, the convention is to
run both before every real `terraform apply`, in addition to — not
instead of — `terraform validate` and `terraform plan`.

---

## Cleanup

> Run this after completing the demo to avoid ongoing AWS charges.

**This demo's Cleanup step is verification, not destruction** — same
reasoning as 22a. These are free governance resources meant to protect
every future session, not artifacts of a single teaching rep, and
their state is shared within the `platform/` tier with 22c and Demo 24
once those exist.

### Confirm everything is in its intended, permanent state

```bash
terraform state list
```

> ✅ Verified against a live run.

```
aws_budgets_budget.monthly_cost
aws_cloudwatch_event_rule.session_length_check
aws_cloudwatch_event_target.notify_sns
aws_sns_topic.cost_alerts
aws_sns_topic_policy.allow_eventbridge
aws_sns_topic_subscription.cost_alerts_email
```

```
Console → SNS → cloudnova-cost-alerts → Subscription status: Confirmed ✅
Console → Budgets → cloudnova-monthly-budget → both thresholds present ✅
```

> ⚠️ **Do not run `terraform destroy` at the end of this session.**
> This demo's resources are meant to protect every subsequent Phase 3+
> session. Its state is `src/platform/`'s — a `destroy` here would
> take down this demo's governance layer, and, once built, 22c's
> ECR/ACM re-creation and Demo 24's IAM identity too, since they share
> this same state. It would **not** touch the VPC or EKS cluster —
> those live in `workloads/`, a structurally separate state.

---

## What You Learned

1. ✅ Detection and prevention are different design choices with
   different failure modes — this project deliberately chose detection
   for a stated reason, not by default.
2. ✅ `aws_cloudwatch_event_rule` + `aws_cloudwatch_event_target` fan
   an EventBridge schedule out to one or more targets — here, an SNS
   topic built on Demo 03/06's own patterns.
3. ✅ `aws_sns_topic_policy` is a standalone resource-based policy, a
   different shape from the inline `policy` argument used earlier, and
   the right choice when the policy must reference a resource declared
   after the topic.
4. ✅ An SNS topic can be encrypted at rest with `kms_master_key_id`,
   and the AWS managed key (`alias/aws/sns`) does this at no additional
   monthly cost — unlike a customer managed KMS key.
5. ✅ `tflint` and `checkov` are external CLI tools that read `.tf`
   files directly, run outside the `plan`/`apply` cycle entirely, and
   require real, current configuration (a pinned plugin `version`, a
   valid YAML mapping) to run at all.
6. ✅ An auto-remediation Lambda was a real, considered alternative —
   rejected for this project's specific shape (single learner, no
   shared-production stakes), not rejected universally.
7. ✅ A shared `platform/` state protects against `workloads/` ever
   reaching it, and vice versa — but does not give this demo isolation
   from 22c or Demo 24, which will share this same state once built.

**Key Takeaway:** every control this demo builds — the notification,
the budget, the static analysis — answers "how would I find out?"
rather than "how would I stop it?", and that choice was made
deliberately for this project's specific shape, not assumed as a
default.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `backend "s3"` arguments must be literals | TA-004 Obj 6a (backend configuration) | No variables, locals or outputs are available at backend-resolution time |
| `aws_cloudwatch_event_rule` / `_target` | TA-004 Obj 4a (resource configuration) | Not a core Terraform-language object — an ordinary AWS provider resource pair |
| `aws_budgets_budget` multiple `notification` blocks | TA-004 Obj 4a (resource configuration) | Repeatable nested blocks, one per notification threshold |
| `validate`/`plan` versus provider-side value validation | TA-004 Obj 3a (core workflow) | Neither checks every provider-enforced value constraint |
| `tflint`/`checkov` as pre-apply tooling | Not exam-tested — included for practical completeness | Ecosystem tools, not part of Terraform core or the CLI |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Is `tflint` a Terraform subcommand?" | No — it's a completely separate, third-party CLI tool | Assuming `terraform tflint` or similar built-in integration exists |
| "Can `aws_budgets_budget` have only one notification threshold?" | No requirement either way — `notification` is a repeatable block; use as many as needed | Assuming a budget resource is limited to a single alert threshold |
| "Parameterise the backend's bucket name with a variable" | Recognising that backend arguments must be literals, and that partial configuration via `-backend-config` is the actual mechanism | Writing `bucket = var.state_bucket` and expecting it to resolve |
| "An incremental `apply` reports adding more resources than you just wrote" | Recognising that's a signal to stop and inspect the plan before confirming | Assuming the reported count is always self-evidently correct |
| "Setting a `terraform.tfvars` value before its variable is declared" | Recognising this produces a warning, not an error, and is a workflow smell worth fixing | Assuming an undeclared-variable value silently does nothing, or that it fails the apply |

### Exam Task — Write a complete configuration

**Task:** Write a Terraform configuration for an `aws_budgets_budget`
with exactly two notification thresholds (50% and 80%) on actual spend.

**Block types required:** `terraform`, `provider`, `resource`, repeatable `notification` sub-block

**Official documentation:**
- [`aws_budgets_budget` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget)

**What to practise:**
1. Open the page above — check the `notification` block's argument reference
2. Write the configuration from scratch without looking at this demo's `src/` files
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
resource "aws_budgets_budget" "exam_task" {
  name         = "exam-task-budget"
  budget_type  = "COST"
  limit_amount = "50"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["you@example.com"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["you@example.com"]
  }
}
```

**Arguments you must know without looking up:**
- `notification` is repeatable — one block per threshold, not a list argument
- `limit_amount` is a string, not a number
- `notification_type` distinguishes `ACTUAL` (money already spent) from `FORECASTED` (projected trend)

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `terraform init` fails with a bucket-not-found or access-denied error | `03-backend.tf`'s `bucket` doesn't match the bucket 22a actually created | Confirm the real bucket name from 22a's output or Console, and correct the literal in `03-backend.tf` |
| `Warning: Value for undeclared variable` for `monthly_budget_limit` | A value for it exists in `terraform.tfvars` before the variable is declared in `04-variables.tf` | Harmless to the apply itself, but fix the ordering — declare the variable (Part B Step 1) before setting its value, as this demo's steps do |
| Email subscription stuck at `PendingConfirmation`, while `plan` reports no changes | The confirmation link wasn't clicked; confirmation state lives in AWS, not in your configuration, so Terraform sees nothing wrong | Check the inbox and spam folder for the AWS SNS confirmation email and click the link |
| EventBridge target never publishes | Missing `aws_sns_topic_policy` allowing `events.amazonaws.com` to publish | Confirm the topic policy's `Principal` and `Condition` match this rule's ARN exactly |
| `Error: Invalid value for "limit_amount"` or an unexpected type conversion | `monthly_budget_limit` declared as `number` when the provider expects a string | Declare the variable as `type = string` and quote the value in `terraform.tfvars` |
| `tflint --init` fails: `"version" attribute cannot be omitted when specifying "source"` | `.tflint.hcl` sets `source` on the `aws` plugin without a `version` | Pin a real version, e.g. `version = "0.48.0"` — check the plugin's release page for anything newer |
| `checkov` errors: `doesn't appear to contain 'key: value' pairs` | `.checkov.yaml` is empty, comment-only, or has invalid indentation (tabs) | Confirm the file has a real `framework:` mapping, saved with spaces |
| `checkov` reports `CKV_AWS_26` on the SNS topic | The topic has no `kms_master_key_id` set | Add `kms_master_key_id = "alias/aws/sns"` — free, and resolves the finding directly |
| `checkov` reports a genuinely out-of-scope finding for your own extended config | Some checks won't apply to every project | Add the specific check ID to `.checkov.yaml`'s `skip-check` list, with a comment explaining why — reserve this for findings that are actually out of scope, not ones that are cheap to fix |

---

## Break-Fix Scenario

One deliberate error, not three — from 22a onward, Phase 3's slower
apply/fix cycle (an EKS cluster especially) makes a multi-error
diagnostic loop cost real session time in a way Phase 1/2's cheaper,
faster resources never did. Diagnose it before revealing the answer —
and note that this one deliberately survives `terraform validate`, so
you have to get as far as `apply` to see it fail.

```bash
cd src/break-fix/
terraform init
terraform validate
terraform plan
terraform apply
```

#### `broken.tf` — One deliberate, validate-surviving error

This file is a self-contained, single-resource configuration with one
incorrect enum value that `terraform validate` cannot catch.

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
  region  = "us-east-2"
  profile = "default"
}

resource "aws_budgets_budget" "monthly_cost" {
  name         = "break-fix-budget"
  budget_type  = "COST"
  limit_amount = "100"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "Actual" # Error
    subscriber_email_addresses = ["team@example.com"]
  }
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error — `notification_type = "Actual"`**
Valid values are `ACTUAL` and `FORECASTED`, both fully uppercase.
`terraform validate` and `terraform plan` both pass, because neither
evaluates provider-side value constraints — the failure only appears
when `apply` sends the request to the real AWS API. This is a useful
distinction to internalise: `validate` catches shape problems, not
every provider-specific value constraint. Fix:
`notification_type = "ACTUAL"`. No cascade effect — this is the only
error in the file, and fixing it lets the apply succeed on retry.

</details>

**Cleanup:**

```bash
cd src/break-fix/
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
```

No `terraform destroy` is needed here — the apply fails before the
budget is created, so there's nothing in AWS to remove. This break-fix
uses its own local state and never touches the persistent backend.

---

## Interview Prep

**Q1. A teammate asks why this project didn't just pair the EventBridge idle-check with a Lambda that force-destroys resources automatically — wouldn't that actually save money?**
It would save money in the case where it works correctly, but the failure mode is worse than the problem it solves. This is a single-learner lab, not shared production — the real risk isn't "cost creeps up slightly," it's "an idle-detection false positive destroys real work-in-progress mid-session." A notification gets most of the practical benefit — you find out fast, faster than the spend-based Budgets alarm would catch it — without that downside. It's a genuinely different trade-off in a shared, production, multi-team environment, where the cost of unmonitored spend might outweigh the risk of an occasional misfire; the right answer here isn't universal, it's shaped by this project actually being one learner's personal lab.

**Q2. Someone notices this demo's EventBridge rule fires every hour, not in real time. Isn't that a gap?**
It's a deliberate trade-off, not an oversight. An hourly check is more than fast enough to catch a session that ran long by an hour or more — the actual failure mode this control exists for — without generating unnecessary invocations or complexity for a faster cadence that wouldn't meaningfully change the outcome. If the threshold this rule checks against were 15 minutes instead of hours, an hourly check would clearly be too coarse — but a session-length control is inherently a coarse-grained concept, so the check frequency should match that grain, not run needlessly fine.

**Q3. A reviewer asks why `tflint` and `checkov` aren't wired in as Terraform provisioners, so they run automatically as part of `terraform apply`.**
Because they're not things Terraform is meant to orchestrate — they're static analysis tools that read your configuration *before* you'd even want to run `plan`, let alone `apply`. A provisioner runs as part of a resource's own lifecycle, tied to actual infrastructure being created or destroyed; `tflint` and `checkov` have nothing to do with any specific resource's lifecycle — they evaluate the whole configuration, independent of any apply happening at all. Baking them into a provisioner would also mean they only ever run at apply time, which defeats the point: you want these findings *before* you commit to applying, not as a side effect of it.

**Q4. Part B's `terraform apply` reports "1 added." A teammate expects it to say "6 added," since the budget resource brings the total count to 6. Who's right?**
Part B is right to report 1. `terraform apply`'s resource count reflects what *this specific apply* is changing, not the configuration's running total — the five resources from Part A already exist in state from the prior apply, so re-applying doesn't recreate them. If an apply against already-existing state ever reports a count matching your *total* resource count rather than what genuinely changed, that's worth stopping to investigate before confirming — it can mean something unexpected is being replaced, not just added.

**Q5. Why does this demo write into `platform/` rather than `workloads/`, and what does that boundary actually buy you?**
Because everything this demo builds is meant to be created once and left standing — free governance resources with no cost reason to be torn down and reapplied every session, the same category ECR/ACM and IAM identity fall into once 22c and Demo 24 exist. `platform/` and `workloads/` are two separate Terraform state files sharing one S3 bucket, distinguished only by key — that separation is structural, not a naming convention: a `destroy` run inside `workloads/` cannot reach anything in `platform/`'s state, and vice versa. What it doesn't do is isolate this demo from 22c or Demo 24 — those will share `platform/`'s state too, since they're in the same "created once" bucket. That's exactly why this demo's Cleanup is verification, not a teardown: destroying `platform/` at the end of a session would take this demo's governance layer down along with whatever else shares its state, for no cost benefit at all.

**Q6. Why does this demo fix the SNS encryption finding instead of adding it to `checkov`'s skip list, the way it handles other out-of-scope findings elsewhere in the series?**
Because a skip list is for findings that genuinely don't apply or aren't worth the trade-off — not a default response to any finding. Encrypting the topic with the AWS managed key costs nothing extra and is a one-line change; there's no real trade-off to document, unlike, say, a finding that would require standing up infrastructure this project has deliberately deferred. Skipping a check you could fix for free just to avoid a red line in the output would be treating the tool's output as the goal, rather than treating the actual security posture it's measuring as the goal.

---

## Key Takeaways

1. **Detection and prevention are different design choices, each with
   its own failure mode.** State which one you're choosing and why —
   don't let "we have a Budgets alarm" imply more protection than a
   notification actually provides.

2. **`notification` blocks on `aws_budgets_budget` are repeatable, not
   a list argument.** One block per independent threshold — write as
   many as your alerting design needs.

3. **A standalone `aws_sns_topic_policy` and an inline `policy`
   argument produce the same thing by different routes.** Reach for the
   standalone resource when the policy has to reference something
   declared after the topic. Encrypting at rest with an AWS managed key
   is free — reach for a customer managed KMS key only when you
   actually need custom key policies, rotation control, or
   cross-account sharing.

4. **Static analysis tools like `tflint`/`checkov` are not Terraform
   constructs, and they need real configuration to actually run.** A
   plugin `version` isn't optional once `source` is set, and neither
   tool — nor `terraform validate`/`plan` — catches every
   provider-specific value constraint; some invalid values only fail
   at `apply` against the real AWS API.

5. **A rejected alternative (auto-remediation) is worth documenting as
   explicitly as the chosen one.** Knowing *why* prevention was
   rejected here — and that the same reasoning wouldn't necessarily
   hold in a different environment — is more useful than just knowing
   what was built.

6. **A shared state boundary protects across tiers, not within one.**
   `platform/` structurally can't be reached by a `workloads/` destroy
   and vice versa — but everything inside `platform/` shares one state,
   which is exactly why this tier's demos end in verification, not
   teardown.

7. **An incremental apply's reported resource count is a real signal,
   worth checking, not a number to skim past.** A mismatch between what
   you expect and what Terraform reports is worth investigating before
   typing `yes`.

> **Demo scope:** Primary concept: detection-only cost and
> configuration governance — EventBridge+SNS session-length notify,
> the two-threshold Budgets alarm, and pre-apply static analysis.
> Supporting concepts: writing into 22a's shared `platform/` state,
> the standalone `aws_sns_topic_policy` shape, encrypting an SNS topic
> for free with an AWS managed KMS key, why prevention
> (auto-remediation) was considered and rejected, and reading an
> incremental apply's resource count as a real signal.
> Estimated completion time: 40–45 minutes (reading + hands-on + verification).
> Checkpoints: 3 natural stopping points (end of Part A, end of
> Part B, end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws sts get-caller-identity --profile default --region us-east-2` | Confirms which AWS account and identity the named profile authenticates as |
| `aws budgets describe-budgets --account-id <ID> --profile default --region us-east-2` | Lists existing AWS Budgets for the account |
| `terraform init` / `validate` / `plan` / `apply` | Standard workflow — `init` here also wires this config to 22a's `platform/` backend for the first time |
| `terraform state list` | Lists what this config's state actually tracks — used in Cleanup instead of `destroy` |
| `tflint --init` / `tflint` | Downloads the pinned plugin version, then lints `.tf` files — run before every real apply from this demo forward |
| `checkov -d .` | Scans `.tf` files for security/compliance misconfigurations — same cadence as `tflint` |
| `sha256sum --ignore-missing -c checksums.txt` | Verifies a downloaded tool archive against its published checksums before installing it |

---

## Next Demo

**Demo 22c — ECR/ACM Re-Creation:** re-creating Demo 19's ECR repo and
re-pushing images, and re-requesting/re-validating a new ACM cert —
writing into this same `platform/` state, the third of four sub-demos
completing the original Demo 22 Part A bootstrap work.

---

## Appendix — Anki Cards

> **Note on this pass:** card content below has been corrected where it
> stated the pre-split `phase-3-onward` shared-state design as fact
> (two cards). Tags are left exactly as they were — no tag changes in
> this pass.

**22b-cost-governance-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::22b-cost-governance
#separator:Comma
#columns:Front,Back,Tags
"What's the difference between a detection control and a prevention control for cost governance?","Detection tells you something happened after the fact (a notification); prevention stops it from happening (e.g. auto-destroy). This project deliberately chose detection-only, since auto-remediation's failure mode (destroying real work-in-progress on a false positive) is worse than the cost risk it solves for a single-learner lab.","demo22b,cost-governance"
"Why does aws_cloudwatch_event_target exist as a separate resource from aws_cloudwatch_event_rule?","A single EventBridge rule can fan out to multiple targets. Splitting rule and target into separate resources lets one schedule notify several different destinations without duplicating the rule.","demo22b,eventbridge,ta004-obj4a"
"Which argument enables or disables an aws_cloudwatch_event_rule, and which older argument does it replace?","state (a string, ENABLED or DISABLED) is the current argument. It replaces is_enabled, a boolean that is deprecated — don't copy is_enabled forward from older examples.","demo22b,eventbridge,deprecation"
"What are the two accepted forms of schedule_expression on an EventBridge rule?","A rate expression, e.g. rate(1 hour), or a cron expression, e.g. cron(0 12 * * ? *). A rule uses either schedule_expression or event_pattern — this demo uses the schedule form.","demo22b,eventbridge"
"Is notification on aws_budgets_budget a list argument or a repeatable block?","A repeatable block — write one notification block per independent threshold (e.g. 50% and 80%), each with its own comparison_operator, threshold, and subscriber list.","demo22b,budgets,ta004-obj4a"
"What's the difference between notification_type = ACTUAL and FORECASTED on an AWS Budget?","ACTUAL alerts based on money already spent. FORECASTED alerts based on a projected spending trend, before the actual threshold is crossed — a more proactive but less literal signal.","demo22b,budgets"
"What type is limit_amount on aws_budgets_budget?","A string, not a number — e.g. limit_amount = \"50\". A variable feeding it should be declared type = string to match the provider schema.","demo22b,budgets,types"
"When would you use a standalone aws_sns_topic_policy instead of the inline policy argument on aws_sns_topic?","When the policy needs to reference a resource that doesn't exist yet at the point the topic is declared — such as an EventBridge rule's ARN used in an aws:SourceArn condition. Both produce a resource-based policy on the topic.","demo22b,sns,policy"
"An SNS topic policy grants Principal = { Service = \"events.amazonaws.com\" } with no Condition block. What's the practical effect?","Any EventBridge rule in the account could publish to that topic, not just the intended one. Adding an ArnEquals condition on aws:SourceArn narrows it to one specific rule. Omitting it isn't an error — it silently widens the policy.","demo22b,sns,policy,security"
"How do you encrypt an aws_sns_topic at rest using a free, AWS managed key?","Set kms_master_key_id = \"alias/aws/sns\". Storage of an AWS managed key is always free; only API requests against it are billed, with 20,000 free requests/month.","demo22b,sns,kms,encryption"
"What is the cost difference between an AWS managed KMS key and a customer managed KMS key?","AWS managed key storage is free (API calls beyond the free tier are billed separately). A customer managed key costs a flat $1/month regardless of use, plus API call charges.","demo22b,kms,cost"
"Why did this demo fix checkov's CKV_AWS_26 finding (unencrypted SNS topic) instead of adding it to skip-check?","Because the fix (an AWS managed KMS key) is free and a one-line change — skip-check is for findings that are genuinely out of scope or involve a real trade-off, not a default response to any finding.","demo22b,checkov,security"
"What happens if tflint's .tflint.hcl sets source on a plugin block without also setting version?","tflint --init fails outright with an error that version cannot be omitted when source is specified — this is not an optional convenience, it's a hard requirement.","demo22b,tflint,gotcha"
"Why does an SNS email subscription created by Terraform still show PendingConfirmation, and why doesn't terraform plan flag it?","Email subscriptions require the recipient to click a confirmation link. That confirmation state lives in AWS, not in the Terraform configuration, so plan reports no changes while the subscription sits unusable.","demo22b,sns,gotcha"
"Are tflint and checkov Terraform provisioners?","No. Both are external CLI tools that read .tf files directly off disk and report findings, entirely outside the plan/apply cycle. They should run before a real apply, not be wired into a resource's lifecycle.","demo22b,static-analysis,ta004-obj9"
"Does terraform validate catch every provider-specific value constraint, like an incorrectly-cased enum string?","No. validate checks structure and schema (correct block shape, required arguments present) but not every value-level constraint the provider enforces — some invalid values pass validate and plan, and only fail at apply against the real AWS API.","demo22b,validate,ta004-obj3"
"How many new resources should an incremental terraform apply report when only one new resource block was added to an already-applied config?","Exactly one — the count reflects what that specific apply changes, not the configuration's running total. Outputs aren't counted. A larger reported count against already-existing state is a signal to inspect the plan before confirming.","demo22b,apply,gotcha"
"What happens if a terraform.tfvars value is set for a variable that hasn't been declared yet?","Terraform issues a 'Value for undeclared variable' warning at init, validate, and plan — the apply itself isn't blocked, but it's a workflow smell worth fixing by declaring the variable before setting its value.","demo22b,variables,gotcha"
"Does demo 22b create its own state backend?","No — it reuses 22a's own backend.tf unchanged, pointing at the platform/terraform.tfstate key in the bucket 22a bootstrapped. 22b is simply the first config to write real resources into that key.","demo22b,backend,state"
"Why is 22b's Cleanup a verification step rather than terraform destroy?","Its resources are free or near-free governance controls meant to protect every subsequent session, and its state is shared within the platform tier with 22c and Demo 24 once those exist — a destroy here would take down all of them at once for no cost benefit.","demo22b,teardown,cost-governance"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** the Anki deck drills the individual facts
> (argument names and types, repeatable blocks, tooling boundaries,
> teardown bucket). This Quiz works through diagnosis and applied
> judgment instead — sequencing decisions, policy-scope reasoning,
> and reading real command output — so the two together cover recall
> and application without asking the same question twice.

**22b-cost-governance-quiz.md:**

````markdown
# Quiz — Demo 22b: Cost Governance

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 22c.

---

**Q1. (Multiple Choice)** Why is this governance demo placed *before*
22d, which stands up the EKS cluster, rather than after it?

- A) Terraform requires all notification resources to exist before any compute resource
- B) None of this demo's controls depend on compute existing, and the controls are worth having in place before the first cost-accruing resource is ever applied
- C) EventBridge rules can only be created in an account with no running clusters
- D) It's an arbitrary ordering with no real reason

<details>
<summary>Answer</summary>

**B.** All three mechanisms are independent of compute, and the flat,
continuous control-plane fee 22d introduces is exactly what the safety
net exists to catch — so it belongs in place first.

</details>

---

**Q2. (Multiple Choice)** This demo's `aws_sns_topic_policy` includes a
`Condition` block matching `aws:SourceArn` to this specific
EventBridge rule's ARN. What would happen if that `Condition` block
were removed entirely, leaving just
`Principal = { Service = "events.amazonaws.com" }`?

- A) Nothing changes — the Condition block is optional boilerplate with no real effect
- B) Any EventBridge rule in the account, not just this one, would be allowed to publish to this SNS topic
- C) The policy would fail validation, since Condition blocks are required on all SNS topic policies
- D) EventBridge itself would stop being able to publish at all

<details>
<summary>Answer</summary>

**B.** Without the `Condition` block, the policy trusts *any*
EventBridge rule's publish attempt rather than this specific one. It
produces no error — it silently widens the policy, which is precisely
the class of finding Part C's static analysis exists to surface.

</details>

---

**Q3. (Multiple Choice)** A real `tflint --init` run against this
demo's `.tflint.hcl` fails with `"version" attribute cannot be omitted
when specifying "source"`. What does this confirm?

- A) `tflint` cannot use the AWS ruleset plugin at all
- B) Pinning a version is mandatory once `source` is set — it can't be left out as a matter of style
- C) The plugin only works with Terraform, not AWS
- D) `.tflint.hcl` must be written in JSON instead of HCL

<details>
<summary>Answer</summary>

**B.** This is a hard requirement of the plugin configuration, not a
best-practice suggestion — omitting `version` while `source` is
present fails outright before any linting happens.

</details>

---

**Q4. (Multiple Choice)** A real `checkov` run against this demo's
original (pre-fix) `aws_sns_topic` reports `CKV_AWS_26` as failed. What
does this demo do in response?

- A) Adds `CKV_AWS_26` to `.checkov.yaml`'s `skip-check` list
- B) Adds `kms_master_key_id = "alias/aws/sns"` to the topic, fixing the finding directly at no additional cost
- C) Ignores the finding, since checkov findings are only advisory
- D) Deletes the SNS topic and replaces it with a different resource type

<details>
<summary>Answer</summary>

**B.** The fix is free and simple, so it's applied directly rather than
skipped. A skip list is reserved for findings that are genuinely out
of scope or involve a real trade-off — not a default response to any
finding a scan surfaces.

</details>

---

**Q5. (Multiple Choice)** What is the cost difference between using
`kms_master_key_id = "alias/aws/sns"` and creating a dedicated
`aws_kms_key` (customer managed key) for the same purpose?

- A) There is no difference — both cost $1/month
- B) The AWS managed key's storage is free; a customer managed key costs $1/month flat regardless of use
- C) The AWS managed key costs more, since it's shared infrastructure
- D) Customer managed keys are free; only AWS managed keys are billed

<details>
<summary>Answer</summary>

**B.** AWS managed key storage carries no monthly fee — only API calls
against it are billed, with a free-tier allowance. A customer managed
key's $1/month applies whether or not it's ever used.

</details>

---

**Q6. (Multiple Choice)** Break-Fix's `notification_type = "Actual"`
(wrong casing) passes both `terraform validate` and `terraform plan`.
Why?

- A) `"Actual"` is actually a valid alternate spelling AWS accepts
- B) Neither command evaluates provider-side value constraints — they check structure and schema, and the failure only surfaces when `apply` calls the real AWS API
- C) `validate` was run with the wrong flag
- D) This should have failed `validate`, and its passing indicates a bug in the demo

<details>
<summary>Answer</summary>

**B.** An incorrectly cased enum string is exactly the kind of thing
that only surfaces at `apply`. Internalising which failures are caught
where is more useful than memorising this one value.

</details>

---

**Q7. (Multiple Choice)** Your `terraform apply` succeeded and the SNS
topic exists, but no notification email ever arrives. `terraform plan`
reports no changes. What is the most likely cause?

- A) The EventBridge rule is disabled
- B) The email subscription is still `PendingConfirmation` — confirmation happens in AWS, outside Terraform's view, so `plan` sees nothing wrong
- C) Terraform failed to create the subscription resource
- D) The SNS topic policy is missing

<details>
<summary>Answer</summary>

**B.** The subscription resource exists as far as Terraform is
concerned; what's missing is the recipient clicking the confirmation
link. This is a good illustration of "in state and correct" not being
the same as "working."

</details>

---

**Q8. (True/False)** Because this demo shares `platform/terraform.tfstate`
with 22c and Demo 24 once those are built, running `terraform destroy`
in `src/platform/` at the end of a session would reach only this
demo's own six resources, never anything from those later demos.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** A `destroy` operates on everything tracked in that
state — once 22c and Demo 24 add their own files into `src/platform/`,
their resources are tracked in the same state this demo uses, and a
destroy here would reach them too. It would still never reach the VPC
or EKS cluster, since those live in the structurally separate
`workloads/` state — but within `platform/` itself, the tier is
shared by design.

</details>

---

**Q9. (Multiple Choice)** A `terraform.tfvars` file contains a value
for `monthly_budget_limit` before Part B Step 1 has declared that
variable. What actually happens on the next `terraform plan`?

- A) `terraform plan` fails immediately with a hard error
- B) Terraform issues a "Value for undeclared variable" warning but continues normally
- C) The value is silently discarded with no message at all
- D) Terraform automatically creates the missing variable block

<details>
<summary>Answer</summary>

**B.** It's a warning, not an error — the plan still runs. It's worth
fixing anyway, since it's a real signal that the configuration and its
tfvars file are out of sync.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 9/9 | Import Anki cards, move to Demo 22c |
| 7-8/9 | Review the wrong answers, then proceed |
| 5-6/9 | Re-read the relevant sections, retry those questions |
| Below 5/9 | Re-read the full demo and redo the walkthrough before proceeding |
````