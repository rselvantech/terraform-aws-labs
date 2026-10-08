# Demo 22b — Cost Governance: Notify-Only Automation + Static Analysis

---

## Overview

22a gave the persistent build a durable state backend. Before any
actual cost-accruing resource exists — before the EKS cluster, before
the NAT Gateway — this demo puts the safety net in place. Everything
here is about catching a cost problem *after* it happens (detection),
not preventing it from happening at all (prevention). That distinction
matters and gets stated explicitly, not left implied.

**Real-world scenario — CloudNova:**
Once 22d stands up the EKS cluster, the environment starts accruing a
flat, continuous fee whether or not you remember to tear it down at
the end of a session. Leadership's only real ask before compute goes
live: "if I forget, or if something runs longer than expected, I want
to know — I don't want to find out from the bill." That's a detection
requirement, not an auto-remediation one — nobody asked for infrastructure
that can delete itself, and you shouldn't build that even if they had.

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
  SNS target — the same SNS-topic pattern's actual publish/subscribe
  mechanics, applied to infrastructure monitoring instead of app events
- `aws_budgets_budget` with multiple notification thresholds
- Why this project deliberately does **not** pair either mechanism
  with an auto-remediation Lambda
- `tflint` and `checkov` as CLI tools that run *outside* Terraform
  entirely — not Terraform resources, not provisioners

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** a scheduled EventBridge rule that
checks tagged Phase 3+ resources against a session-length threshold and
publishes to an SNS topic if exceeded; a two-threshold AWS Budgets
alarm watching total account spend; and a local `tflint`/`checkov`
workflow that isn't AWS infrastructure at all, but governs every real
apply from here forward.

**Why three unrelated-looking mechanisms sit in one demo:** all three
answer the same underlying question — "how do I know if something's
gone wrong with cost or configuration before it becomes expensive or
dangerous?" — from three different angles (idle-time detection,
spend-threshold detection, and pre-apply configuration review). None
of the three requires compute to exist first, which is why this demo
runs before 22d's cluster, not after. None of them touches
`retail-store-sample-app` at all.

**Why this demo has no Cleanup that tears anything down:** same
reasoning as 22a — these are free or near-free governance resources
meant to protect every session from here forward, not artifacts of a
single teaching rep. Destroying and recreating them every session would
defeat their purpose for no cost benefit.

---

## Prerequisites

### Knowledge
- 22a completed — the persistent backend this demo's state will live in
- Demo 03/06 completed — SNS topic + subscription mechanics (this demo
  reuses that pattern, doesn't reteach it)
- Demo 21 completed — most recent demo in the series

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | `>= 1.15.0` | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version` |
| `tflint` | Latest (see Part C for why no exact version is pinned here) | `tflint --version` |
| `checkov` | Latest | `checkov --version` |

### Verify AWS Account and Permissions

**Step 1 — Confirm your profile works:**

```bash
aws sts get-caller-identity --profile default
```

**Step 2 — A cheap, harmless dry-run of this demo's actual service:**

```bash
aws budgets describe-budgets --account-id <YOUR_ACCOUNT_ID> --profile default
# Expected: JSON with Budgets array (may be empty)
```

**Step 3 — Verify IAM permissions in Console:**

```
Console → IAM → Users → test → Permissions tab
  → Confirm access to EventBridge, Budgets, and SNS (or an equivalent
    broad policy) is attached ✅
```

**Required permissions beyond what prior demos established:**
```
events:PutRule, events:PutTargets, events:DescribeRule, events:DeleteRule
budgets:CreateBudget, budgets:DescribeBudget, budgets:ModifyBudget, budgets:DeleteBudget
sns:CreateTopic, sns:Subscribe, sns:Publish (already covered from Demo 06)
```

### Versions used in this demo

| Tool | Version |
|---|---|
| Terraform | `~> 1.15.0` |
| AWS Provider | `~> 6.47.0` |

> **Versions pinned as of September 2026** — same dating convention as
> the rest of this series. `tflint`/`checkov` themselves are
> intentionally *not* version-pinned in this table — see Part C for
> why a concrete version number for the `tflint-ruleset-aws` plugin
> specifically is deliberately avoided in this demo's example config.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain the difference between detection and prevention as cost
   controls, and why this project deliberately chose detection-only
2. ✅ Write an `aws_cloudwatch_event_rule` on a schedule, targeting an
   SNS topic
3. ✅ Write an `aws_budgets_budget` with two independent notification
   thresholds
4. ✅ Explain why `tflint` and `checkov` aren't Terraform resources or
   provisioners, and where they actually run in the workflow
5. ✅ Explain why an auto-remediation Lambda was considered and
   rejected for this specific project

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| EventBridge scheduled rule | Same-account rule-to-SNS invocations on the default event bus have historically carried no separate publishing charge — ⚠️ [VERIFY: the commonly-cited "14M/month free" figure belongs to EventBridge **Scheduler**, a separate, newer product from the classic `aws_cloudwatch_event_rule` this demo actually uses; confirm the correct free-tier line for classic scheduled rules before citing a specific number as authoritative] | **$0.00** | One rule, checked hourly — far under any plausible threshold either way |
| SNS topic + email subscription | 1,000 email notifications/month free | **$0.00** | Notify-only traffic is tiny at lab scale |
| AWS Budgets (notification-only, no Actions) | Unconditionally free — the "first 2 free" cap applies only to budgets with AWS Budgets Actions (auto-remediation) attached; this demo's budget has no `action` block at all, only `notification` blocks | **$0.00** | This project uses exactly one budget |
| `tflint` / `checkov` | Open-source, local CLI | **$0.00** | No AWS resource at all — runs on your machine |
| **Session total** | | **~$0.00** | Created once, left standing — see Cleanup |

---

## Directory Structure

```
22b-cost-governance/
├── README.md
├── 22b-cost-governance-anki.csv
├── 22b-cost-governance-quiz.md
└── src/
    └── phase-3-onward/                     # same config 22a's backend serves
        ├── cost_governance.tf              # EventBridge rule + SNS topic/target
        ├── budgets.tf                      # aws_budgets_budget, two thresholds
        ├── variables.tf                    # notification email, threshold values
        ├── outputs.tf
        ├── .tflint.hcl                      # tflint ruleset config — not a .tf file
        └── .checkov.yaml                    # checkov config — not a .tf file
```

> **Why `.tflint.hcl` and `.checkov.yaml` live in the same directory
> but aren't `.tf` files:** neither tool is a Terraform provider or
> resource — they're external CLI programs that read your `.tf` files
> directly from disk and report on them. Their config files configure
> the *tool*, not any AWS infrastructure.

---

## Recall Check — 22a (State Backend Bootstrap)

> **Correction:** this section previously (incorrectly) pointed at
> Demo 21. Demo 21 isn't the immediately preceding demo for 22b — 22a
> is. Fixed to trace to 22a's actual Key Takeaways instead.

Answer from memory before reading anything new:

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
| `aws_cloudwatch_event_rule` | Resource | Scheduled rule — checks tagged resources on a cron-like interval |
| `schedule_expression` | Resource argument | Rate or cron expression controlling how often the rule fires |
| `aws_cloudwatch_event_target` | Resource | Connects the rule to what it notifies — the SNS topic here |
| `aws_sns_topic_subscription` (email) | Resource | Subscribes a real email address to receive the notification |
| `aws_budgets_budget` | Resource | Account-level spend tracking with configurable notification thresholds |
| `notification` block (nested, repeatable) | Resource sub-block | One per threshold — this demo uses two, at 50% and 80% |
| `tflint` | External CLI tool, not a Terraform construct | Lints `.tf` files for style/correctness issues before they're ever applied |
| `checkov` | External CLI tool, not a Terraform construct | Scans `.tf` files for security/compliance misconfigurations before apply |

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

> **Same-as-Demo-06 note, restated rather than assumed:** the SNS
> topic and email subscription here use the identical resource shapes
> Demo 06 taught for `aws_sns_topic_subscription`. What's new in *this*
> demo is what triggers the publish — a scheduled EventBridge rule
> instead of an application event — not the SNS mechanics themselves.

---

#### `aws_budgets_budget` — Two Independent Thresholds

| Argument | Required | Description |
|---|---|---|
| `budget_type` | Yes | `"COST"` — tracks spend, not usage quantity |
| `limit_amount` / `limit_unit` | Yes | Your available AWS credit/budget figure, in `USD` |
| `time_unit` | Yes | `"MONTHLY"` — resets each month |
| `notification` (block, repeatable) | Yes, one per threshold | Each defines its own `threshold` percentage and `subscriber_email_addresses` |

This demo's `notification` blocks: one at `threshold = 50` (early
warning), one at `threshold = 80` (escalated notification) — matching
the two-threshold design decided at the project level. Both notify the
same email; a real team setup might route the 80% threshold to a
different, more urgent channel.

---

## Lab Step-by-Step Guide

---

## Part A — EventBridge + SNS Notify

Part A builds the EventBridge rule and SNS topic that will notify you
if a Phase 3+ session runs long.

### Step 1 — Navigate to the project config

```bash
cd terraform-aws-mastery/phase-3-real-aws-infrastructure/22b-cost-governance/src/phase-3-onward
```

### Step 2 — Add cost_governance.tf

This step creates the SNS topic, its email subscription, the scheduled
EventBridge rule, its target, and the resource policy letting
EventBridge actually publish to the topic.

Create a file **cost_governance.tf** and add the below content:

This file contains every resource this demo's notify-only detection
mechanism needs — the topic, the schedule, the connection between
them, and the permission that makes the connection actually work.

```hcl
resource "aws_sns_topic" "cost_alerts" {
  name = "cloudnova-cost-alerts"
}

resource "aws_sns_topic_subscription" "cost_alerts_email" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_cloudwatch_event_rule" "session_length_check" {
  name                = "cloudnova-session-length-check"
  description         = "Checks tagged Phase 3+ resources against a session-length threshold"
  schedule_expression = "rate(1 hour)"   # checks hourly — not real-time, deliberately low-frequency
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

> ⚠️ [VERIFY — timing claim, docs only] The actual idle-resource-check
> *logic* this rule's target would evaluate (which tags, what
> threshold counts as "too long") is a detail for whoever finalizes
> this demo's Lab against real, tagged Phase 3+ resources — those
> resources don't exist until 22d onward. This demo builds the
> notification *plumbing*; the specific check condition should be
> revisited once 22d's actual resource tags are defined.

### Step 3 — Add variables.tf

This step declares the one variable every notification in this demo
depends on — the real email address that will receive both the
session-length and budget alerts.

This file declares `notification_email`, deliberately with no
default, since a real email address shouldn't be hardcoded into a
file that might get committed.

**variables.tf:**

```hcl
variable "notification_email" {
  type        = string
  description = "Email address to receive cost and budget notifications"
  # No default — set this in terraform.tfvars, don't hardcode a real
  # email into a file that might get committed
}
```

### Step 4 — Apply and confirm the email subscription

This step applies the notification plumbing for the first time and
confirms the email subscription is genuinely active, not just created.

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

```
⚠️ Simulated expected output

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

> **Bolded takeaway:** SNS email subscriptions require manual
> confirmation — check your inbox for a "AWS Notification -
> Subscription Confirmation" email and click the confirmation link.
> Until confirmed, the subscription shows `PendingConfirmation` in
> Console and won't actually receive notifications.

```
Console → SNS → Topics → cloudnova-cost-alerts → Subscriptions
  → Status: Confirmed (after clicking the email link) ✅
```

> 📷 [Screenshot placeholder: AWS Console → SNS → Topics →
> cloudnova-cost-alerts → Subscriptions tab, showing Status: Confirmed]

---

## Part B — AWS Budgets Alarm

Part B adds a second, independent detection layer — an AWS Budgets
alarm watching total account spend rather than any single resource's
runtime.

### Step 5 — Add budgets.tf

This step adds the second, independent detection mechanism — a
Budgets alarm tracking total account spend against two thresholds.

Create a file **budgets.tf** and add the below content:

This file contains the one budget resource this demo builds, with two
`notification` blocks — no `action` block, since this is deliberately
a notify-only design.

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

### Step 6 — Add the budget limit variable

This step adds the one remaining variable this demo needs — your own
real budget figure, again with no default since it's genuinely
personal to your account.

**Add to variables.tf:**

```hcl
variable "monthly_budget_limit" {
  type        = number
  description = "Your available AWS credit/budget for this project, in USD"
  # No default — this is genuinely personal to your account; set it
  # in terraform.tfvars
}
```

### Step 7 — Apply

This step applies the budget resource on top of Part A's already-
applied resources, and is a good moment to practice checking the
reported resource count against what actually changed.

```bash
terraform plan
terraform apply
```

```
⚠️ Simulated expected output

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

> **Bolded takeaway, and a self-check worth doing on every incremental
> apply in this series:** this apply adds exactly **one** new resource
> (`aws_budgets_budget.monthly_cost`) — the five resources Part A
> already applied (`aws_sns_topic`, its subscription, the EventBridge
> rule and target, and the SNS topic policy) are untouched, so the
> correct count here is 1, not a re-statement of the project's running
> total. If your own `apply` output ever shows a much larger "added"
> count than the number of genuinely new resource blocks you just
> wrote, stop and check what Terraform thinks it's about to do before
> confirming — that mismatch is exactly the kind of signal worth
> catching before typing `yes`.

```
Console → Billing and Cost Management → Budgets → cloudnova-monthly-budget
  → Alert thresholds: 50%, 80% ✅
  → Alert subscribers: your email ✅
```

> 📷 [Screenshot placeholder: AWS Console → Billing and Cost
> Management → Budgets → cloudnova-monthly-budget, showing both the
> 50% and 80% alert thresholds and the subscribed email]

> **Bolded takeaway:** `notification_type = "ACTUAL"` alerts on money
> already spent. AWS Budgets also supports `"FORECASTED"`, which alerts
> based on a projected trend before you actually cross the threshold —
> a real option worth knowing exists, even though this demo uses
> `ACTUAL` for a simpler, more literal first pass.

---

## Part C — Static Analysis: `tflint` and `checkov`

Part C installs and configures two static-analysis tools that run
outside Terraform entirely, checking configuration quality before any
real apply from here forward.

### Step 8 — Install both tools (if not already present)

This step installs both static-analysis tools for the first time in
this series — neither is a Terraform construct, so neither requires
`terraform init` or any provider.

```bash
# tflint — see https://github.com/terraform-linters/tflint for your platform's install method
tflint --version

# checkov
pip install checkov --break-system-packages
checkov --version
```

### Step 9 — Add minimal config files

This step adds each tool's own configuration file, controlling what
each one checks rather than anything about AWS infrastructure.

This file enables the AWS-specific tflint ruleset, deliberately
without pinning an exact plugin version.

**`.tflint.hcl`:**

```hcl
plugin "aws" {
  enabled = true
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
  # No `version` pinned here deliberately — this plugin releases
  # frequently (it was already several versions past 0.31.0 by early
  # 2026), so any specific number written into this demo would go
  # stale quickly. Run `tflint --init` and check the plugin's own
  # GitHub releases page for whatever is actually current when you
  # set this up, and pin that real number in your own project.
}
```

This file scopes checkov to Terraform and explicitly skips one check
this lab-scale project has consciously decided not to satisfy.

**`.checkov.yaml`:**

```yaml
framework:
  - terraform
skip-check:
  - CKV_AWS_18   # S3 access logging — deliberately out of scope for this lab-scale project
```

### Step 10 — Run both against this demo's own config

This step runs both tools against this demo's own configuration,
confirming neither touches AWS or Terraform state at all.

```bash
tflint --init
tflint
checkov -d .
```

```
⚠️ Simulated expected output

tflint: 0 issues found.

checkov: Passed checks: 14, Failed checks: 0, Skipped checks: 1
```

> **Bolded takeaway:** neither command touched AWS or Terraform state
> at all — both read your `.tf` files directly off disk and report
> findings. This is why they're not Terraform resources or
> provisioners: they run *around* the Terraform workflow, not inside
> it. From this demo forward, the convention is: run both before every
> real `terraform apply`, not instead of `terraform plan`/`validate`.

---

## Cleanup

**This demo's Cleanup step is verification, not destruction** — same
reasoning as 22a. These are free governance resources meant to protect
every future session, not artifacts of a single teaching rep.

### Step 11 — Confirm everything is in its intended, permanent state

```bash
terraform state list
# aws_sns_topic.cost_alerts
# aws_sns_topic_subscription.cost_alerts_email
# aws_cloudwatch_event_rule.session_length_check
# aws_cloudwatch_event_target.notify_sns
# aws_sns_topic_policy.allow_eventbridge
# aws_budgets_budget.monthly_cost
```

```
Console → SNS → cloudnova-cost-alerts → confirm subscription is Confirmed ✅
Console → Budgets → cloudnova-monthly-budget → confirm both thresholds ✅
```

> ⚠️ **Do not run `terraform destroy` at the end of this session.**
> These resources protect every subsequent Phase 3+ session.

---

## What You Learned

1. ✅ Detection and prevention are different design choices with
   different failure modes — this project deliberately chose detection
   for a stated reason, not by default.
2. ✅ `aws_cloudwatch_event_rule` + `aws_cloudwatch_event_target` fan
   an EventBridge schedule out to one or more targets — here, an SNS
   topic reused from Demo 06's own pattern.
3. ✅ `aws_budgets_budget` supports multiple independent `notification`
   blocks, each with its own threshold and comparison operator.
4. ✅ `tflint` and `checkov` are external CLI tools that read `.tf`
   files directly — they are not Terraform resources or provisioners,
   and run outside the `plan`/`apply` cycle entirely.
5. ✅ An auto-remediation Lambda was a real, considered alternative —
   rejected for this project's specific shape (single learner, no
   shared-production stakes), not rejected universally.
6. ✅ Checking an incremental apply's reported resource count against
   what you actually expect to change is a real, useful habit — not
   just a formality.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `aws_cloudwatch_event_rule` / `_target` | TA-004 Obj 4a — Resource configuration (provider-specific resource types) | Not itself a core Terraform-language object — an ordinary AWS provider resource pair |
| `aws_budgets_budget` multiple `notification` blocks | TA-004 Obj 4a | Repeatable nested blocks, one per notification threshold |
| `tflint`/`checkov` as pre-apply tooling | TA-004 Obj 9 — Testing and validation ecosystem | Know these are ecosystem tools, not part of Terraform core or the CLI itself |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Is `tflint` a Terraform subcommand?" | No — it's a completely separate, third-party CLI tool | Assuming `terraform tflint` or similar built-in integration exists |
| "Can `aws_budgets_budget` have only one notification threshold?" | No requirement either way — `notification` is a repeatable block; use as many as needed | Assuming a budget resource is limited to a single alert threshold |
| "An incremental `apply` reports adding more resources than you just wrote" | Recognizing that's a signal to stop and inspect the plan before confirming, not something to click through | Assuming the reported count is always self-evidently correct |

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
- `notification_type` distinguishes `ACTUAL` (money already spent) from `FORECASTED` (projected trend)

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| Email subscription stuck at `PendingConfirmation` | Confirmation link in the subscription email wasn't clicked | Check the inbox (and spam folder) for the AWS SNS confirmation email, click the link |
| EventBridge target never publishes | Missing `aws_sns_topic_policy` allowing `events.amazonaws.com` to publish | Confirm the topic policy's `Principal`/`Condition` match this rule's ARN exactly |
| `checkov` reports a finding you've deliberately accepted | A real, known limitation, not a bug | Add the specific check ID to `.checkov.yaml`'s `skip-check` list, with a comment explaining why |
| `tflint` fails to download the `aws` plugin | No `version` pinned and no network access, or a genuinely broken release | Pin the plugin's current real version explicitly once you've checked its release page, rather than leaving `version` unset indefinitely |

---

## Break-Fix Scenario

One deliberate error. Diagnose using `terraform validate` and
`terraform plan` — do not look at the answer first.

```bash
cd src/break-fix/
terraform init
terraform validate
terraform plan
```

This file is a single-resource configuration with one deliberately
incorrect enum value that `terraform validate` cannot catch — diagnose
it before revealing the answer.

**broken.tf:**

```hcl
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
    notification_type          = "Actual"          # Error
    subscriber_email_addresses = ["team@example.com"]
  }
}
```

<details>
<summary>Reveal answer — attempt diagnosis first</summary>

**Error — `notification_type = "Actual"`**
Valid values are `ACTUAL` and `FORECASTED`, both fully uppercase.
`terraform apply` will fail against the AWS API with a validation
error, since `terraform validate` alone doesn't catch invalid enum
*values* — only structural/syntax issues. This is a useful distinction
to internalize: `validate` catches shape problems, not every
provider-specific value constraint. Fix: `notification_type = "ACTUAL"`.

</details>

**Cleanup:**

```bash
cd src/break-fix/
terraform destroy -auto-approve
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
```

---

## Interview Prep

**Q1. A teammate asks why this project didn't just pair the EventBridge idle-check with a Lambda that force-destroys resources automatically — wouldn't that actually save money?**
It would save money in the case where it works correctly, but the failure mode is worse than the problem it solves. This is a single-learner lab, not shared production — the real risk isn't "cost creeps up slightly," it's "an idle-detection false positive destroys real work-in-progress mid-session." A notification gets most of the practical benefit — you find out fast, faster than the spend-based Budgets alarm would catch it — without that downside. It's a genuinely different trade-off in a shared, production, multi-team environment, where the cost of unmonitored spend might outweigh the risk of an occasional misfire; the right answer here isn't universal, it's shaped by this project actually being one learner's personal lab.

**Q2. Someone notices this demo's EventBridge rule fires every hour, not in real time. Isn't that a gap?**
It's a deliberate trade-off, not an oversight. An hourly check is more than fast enough to catch a session that ran long by an hour or more — the actual failure mode this control exists for — without generating unnecessary EventBridge invocations or complexity for a faster cadence that wouldn't meaningfully change the outcome. If the threshold this rule checks against were, say, 15 minutes instead of hours, an hourly check would clearly be too coarse — but a session-length control is inherently a coarse-grained concept, so the check frequency should match that grain, not run needlessly fine.

**Q3. A reviewer asks why `tflint` and `checkov` aren't wired in as Terraform provisioners, so they run automatically as part of `terraform apply`.**
Because they're not things Terraform is meant to orchestrate — they're static analysis tools that read your configuration *before* you'd even want to run `plan`, let alone `apply`. A provisioner runs as part of a resource's own lifecycle, tied to actual infrastructure being created or destroyed; `tflint` and `checkov` have nothing to do with any specific resource's lifecycle; they evaluate the whole configuration, independent of any apply happening at all. Baking them into a provisioner would also mean they only ever run at apply-time, which defeats the actual point — you want these findings *before* you commit to running `apply`, not as a side effect of it.

**Q4. Part B's `terraform apply` reports "1 added." A teammate expects it to say "6 added," since the budget resource brings the total count to 6. Who's right?**
Part B is right to report 1. `terraform apply`'s resource count reflects what *this specific apply* is changing, not the configuration's running total — the 5 resources from Part A already exist in state from the prior apply, so re-applying doesn't recreate them. If an apply against already-existing state ever reports a count matching your *total* resource count rather than what genuinely changed, that's worth stopping to investigate before confirming — it can mean something unexpected is being replaced, not just added.

---

## Key Takeaways

1. **Detection and prevention are different design choices, each with
   its own failure mode.** State which one you're choosing and why —
   don't let "we have a Budgets alarm" imply more protection than a
   notification actually provides.

2. **`notification` blocks on `aws_budgets_budget` are repeatable, not
   a list argument.** One block per independent threshold — write as
   many as your alerting design needs.

3. **Static analysis tools like `tflint`/`checkov` are not Terraform
   constructs.** They read `.tf` files directly, run entirely outside
   the `plan`/`apply` cycle, and should run *before* you'd even
   consider applying, not as a provisioner tied to a resource's lifecycle.

4. **`terraform validate` doesn't catch every provider-specific value
   constraint.** It checks structure and schema — an invalid enum
   value like a wrongly-cased string can still pass `validate` and
   only fail at `apply` against the real AWS API.

5. **A rejected alternative (auto-remediation) is worth documenting as
   explicitly as the chosen one.** Knowing *why* prevention was
   rejected here — and that the same reasoning wouldn't necessarily
   hold in a different environment — is more useful than just knowing
   what was built.

6. **An incremental apply's reported resource count is a real signal,
   worth checking, not a number to skim past.** A mismatch between what
   you expect and what Terraform reports is worth investigating before
   typing `yes`.

> **Demo scope:** Primary concept: detection-only cost and
> configuration governance — EventBridge+SNS session-length notify,
> the two-threshold Budgets alarm, and pre-apply static analysis.
> Supporting concepts: why prevention (auto-remediation) was
> considered and rejected, the reusable SNS pattern from Demo 06,
> reading an incremental apply's resource count as a real signal.
> Estimated completion time: 35–40 minutes.
> Checkpoints: 3 natural stopping points (end of Part A, end of
> Part B, end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws sts get-caller-identity --profile <PROFILE>` | Confirms which AWS account and identity the named profile authenticates as |
| `aws budgets describe-budgets --account-id <ID> --profile <PROFILE>` | Lists existing AWS Budgets for the account |
| `terraform init` / `validate` / `plan` / `apply` | Standard workflow, unchanged from prior demos |
| `tflint --init` / `tflint` | Downloads configured plugins, then lints `.tf` files for style/correctness — run before every real apply from this demo forward |
| `checkov -d .` | Scans `.tf` files for security/compliance misconfigurations — same cadence as `tflint` |

---

## Next Demo

**Demo 22c — ECR/ACM Re-Creation:** re-creating Demo 19's ECR repo and
re-pushing images, and re-requesting/re-validating a new ACM cert —
the third of four sub-demos completing the original Demo 22 Part A
bootstrap work.

---

## Appendix — Anki Cards

**22b-cost-governance-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::22b-cost-governance
#separator:Comma
#columns:Front,Back,Tags
"What's the difference between a detection control and a prevention control for cost governance?","Detection tells you something happened after the fact (a notification); prevention stops it from happening (e.g. auto-destroy). This project deliberately chose detection-only, since auto-remediation's failure mode (destroying real work-in-progress on a false positive) is worse than the cost risk it solves for a single-learner lab.","demo22b,cost-governance,ta004-obj"
"Why does aws_cloudwatch_event_target exist as a separate resource from aws_cloudwatch_event_rule?","A single EventBridge rule can fan out to multiple targets. Splitting rule and target into separate resources lets one schedule notify several different destinations without duplicating the rule.","demo22b,eventbridge,ta004-obj4a"
"Is notification on aws_budgets_budget a list argument or a repeatable block?","A repeatable block — write one notification block per independent threshold (e.g. 50% and 80%), each with its own comparison_operator, threshold, and subscriber list.","demo22b,budgets,ta004-obj4a"
"What's the difference between notification_type = ACTUAL and FORECASTED on an AWS Budget?","ACTUAL alerts based on money already spent. FORECASTED alerts based on a projected spending trend, before the actual threshold is crossed — a more proactive but less literal signal.","demo22b,budgets"
"Are tflint and checkov Terraform provisioners?","No. Both are external CLI tools that read .tf files directly off disk and report findings, entirely outside the plan/apply cycle. They should run before a real apply, not be wired in as part of a resource's lifecycle.","demo22b,static-analysis,ta004-obj9"
"Does terraform validate catch every provider-specific value constraint, like an incorrectly-cased enum string?","No. validate checks structure and schema (correct block shape, required arguments present) but not every value-level constraint the provider itself enforces — some invalid values only fail at apply, against the real AWS API.","demo22b,validate,ta004-obj3"
"How many new resources should an incremental terraform apply report when only one new resource block was added to an already-applied config?","Exactly one — the count reflects what that specific apply changes, not the configuration's running total. A larger reported count against already-existing state is a signal to inspect the plan before confirming.","demo22b,apply,gotcha"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the individual facts
> (detection vs. prevention, repeatable `notification` blocks,
> tooling boundaries). This Quiz instead works through Break-Fix-style
> diagnosis and realistic apply-output-reading scenarios, so the two
> together cover recall and applied judgment without restating the
> same question twice.

**22b-cost-governance-quiz.md:**

````markdown
# Quiz — Demo 22b: Cost Governance

> Question types: True/False, Multiple Choice, Multiple Answer —
> matching the real TA-004 exam format.
> Target: 80% or above before moving to Demo 22c.

---

**Q1. (Multiple Choice)** Why did this project choose a notify-only
EventBridge+SNS design instead of pairing it with an auto-destroy Lambda?

- A) Auto-destroy Lambdas aren't technically possible with EventBridge
- B) A misfiring auto-destroy could destroy real work-in-progress mid-session — worse than the cost risk it solves, for a single-learner lab
- C) Lambda functions cost too much to justify this use case
- D) SNS doesn't support triggering Lambda functions

<details>
<summary>Answer</summary>

**B.** This is a deliberate trade-off specific to a single-learner lab
— the failure mode of destructive automation misfiring outweighs the
cost risk a notification-only approach leaves unaddressed.

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

**B.** Without the `Condition` block, the policy would trust *any*
EventBridge rule's publish attempt, not just this specific one — the
same restriction pattern this series has used before for SQS queue
policies, just applied to SNS here.

</details>

---

**Q3. (Multiple Choice)** Break-Fix's `notification_type = "Actual"`
(wrong casing) passes `terraform validate`. Why?

- A) `"Actual"` is actually a valid alternate spelling AWS accepts
- B) `validate` checks structure and schema, not every provider-enforced value constraint like enum casing
- C) `validate` was run with the wrong flag
- D) This should have failed `validate`, and its passing indicates a bug in the demo

<details>
<summary>Answer</summary>

**B.** `validate` catches shape and syntax problems, not every
value-level constraint the AWS API itself enforces — an incorrectly
cased enum string is exactly the kind of thing that only surfaces at
`apply`.

</details>

---

**Q4. (Multiple Choice)** This demo states its detection-only (no
auto-remediation) choice explicitly isn't a universal rule for all AWS
environments. Under what circumstance does the demo suggest the
opposite trade-off might actually make sense?

- A) Never — detection-only is always the correct choice regardless of environment
- B) A shared, production, multi-team environment with strict cost SLAs, where unmonitored spend risk might outweigh the risk of an occasional auto-remediation misfire
- C) Any environment where the AWS bill exceeds $100/month
- D) Only when Lambda functions are unavailable in the target region

<details>
<summary>Answer</summary>

**B.** The demo is explicit that this reasoning is shaped by this
project's own shape (single learner, no shared-production stakes) —
a genuinely different environment could reasonably reach the opposite
conclusion.

</details>

---

**Q5. (Multiple Choice)** This demo's `.checkov.yaml` skips
`CKV_AWS_18` (S3 access logging). What does this demo say about why?

- A) Checkov doesn't actually support this check reliably
- B) It's deliberately out of scope for this lab-scale project — not a mistake or a universal recommendation to skip it elsewhere
- C) S3 access logging is enabled by default now, making the check redundant
- D) This check only applies to buckets created before 2024

<details>
<summary>Answer</summary>

**B.** The skip is a scoped, stated decision for this specific
lab-scale project — not a general claim that the check is wrong or
unnecessary in every context.

</details>

---

**Q6. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about this demo's `.tflint.hcl` example are correct?

- A) It pins an exact plugin version so every reader gets identical linting behavior
- B) It deliberately omits a `version` argument, since the plugin releases too frequently for a hardcoded number to stay current
- C) A reader is expected to check the plugin's own release page and pin a real, current version in their own project
- D) `tflint` requires no configuration file at all to function

<details>
<summary>Answer</summary>

**B and C.** This demo's example deliberately leaves `version` unset
rather than repeat the mistake of hardcoding a number that will go
stale — the reader is expected to pin whatever is actually current
when they set this up.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 5-6/6 | Import Anki cards, move to Demo 22c |
| 4/6 | Review the wrong answers, then proceed |
| 3/6 | Re-read the relevant sections, retry those questions |
| Below 3/6 | Re-read the full demo before proceeding |
````