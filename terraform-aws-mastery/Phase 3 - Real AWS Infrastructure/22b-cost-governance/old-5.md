# Demo 22b — Cost Governance: Notify-Only Automation + Static Analysis

> **Revision note (this version) — per ADR-023, pending Track 2 final
> sign-off.** This demo now builds into `src/terraform/platform/`,
> state key `platform/terraform.tfstate` — not `phase-3-onward/`. Two
> substantive changes beyond the path: (1) every resource here now
> carries an explicit `Tier = "platform"` tag, so that once workloads
> exist (starting the EKS demo), the session-length idle-check has a
> concrete, tag-based way to distinguish "should never be flagged
> idle" (platform) from "should be flagged if left running" (workloads)
> — this closes a real scoping gap Track 3's governance review
> surfaced: without this tag, a future idle-check risks either
> flagging permanent resources as stale or missing the actual
> cost-accruing tier entirely. (2) `prevent_destroy` was evaluated for
> this demo's own resources (SNS topic, EventBridge rule, Budget) and
> **deliberately not applied** — see the callout in Part A below for
> why, flagged here for Track 2 to confirm or override.

---

## Overview

22a gave the persistent build its two state keys. This demo is the
first to actually write into one of them — `platform/terraform.tfstate`
— before any cost-accruing resource exists in the other
(`workloads/terraform.tfstate`). Everything here is about catching a
cost problem *after* it happens (detection), not preventing it from
happening at all (prevention). That distinction matters and gets
stated explicitly, not left implied.

**Real-world scenario — CloudNova:**
Once the workloads-tier EKS cluster stands up, the environment starts
accruing a flat, continuous fee whether or not you remember to tear it
down at the end of a session. Leadership's only real ask before compute
goes live: "if I forget, or if something runs longer than expected, I
want to know — I don't want to find out from the bill." That's a
detection requirement, not an auto-remediation one.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — EventBridge + SNS: session-length notify                     │
│  Scheduled rule checks WORKLOADS-tagged resources → SNS notification   │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — AWS Budgets: two-threshold spend alarm                       │
│  50% early warning, 80% escalated notification                         │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Static analysis: tflint + checkov, local and interim         │
│  Runs before every real apply from this demo onward, in BOTH           │
│  platform/ and workloads/                                               │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- Detection versus prevention as a real, distinct design choice
- `aws_cloudwatch_event_rule` on a schedule expression, paired with an
  SNS target
- `aws_sns_topic_policy` as a standalone resource-based policy
- Encrypting an SNS topic at rest with an AWS managed KMS key
- `aws_budgets_budget` with multiple notification thresholds
- Why this project does **not** pair either mechanism with an
  auto-remediation Lambda
- `tflint` and `checkov` as CLI tools that run *outside* Terraform
  entirely
- **New in this revision:** why the session-length check's tag
  matching must target the **workloads** tier specifically, and why
  tagging every resource with its tier explicitly (rather than relying
  on which state file it happens to live in) is the correct way to
  make that filterable

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** a scheduled EventBridge rule that
checks **workloads-tagged** Phase 3+ resources against a session-length
threshold and publishes to an SNS topic if exceeded; a two-threshold
AWS Budgets alarm watching total account spend; and a local
`tflint`/`checkov` workflow governing every real apply in both
`platform/` and `workloads/` from here forward.

**Why the idle-check must not fire on platform-tier resources.** This
demo's own SNS topic, EventBridge rule, ACM cert (22c), ECR repos
(22c), and IAM roles (Demo 24) are all *meant* to run indefinitely —
flagging any of them as "this session ran long" would be a false
positive by design, not a real signal. Before this revision, tagging
didn't distinguish tier at all (`Project`/`Environment`/`Demo`/
`ManagedBy` only) — that was fine when everything lived in one shared
bucket, but is actively wrong now that platform and workloads have
different idle-worthiness. **Fix: add `Tier = "platform"` to this
demo's `locals.tf`.** The workloads config (built starting the EKS
demo) will carry `Tier = "workloads"` on its own resources instead.
Whenever the idle-check's actual filter logic is built out (still an
open item independent of this revision — see the original demo's own
VERIFY callout, unchanged), it should filter on `Tier = "workloads"`
specifically, never on `Tier = "platform"` or on tag absence.

**Where the state lives:** `platform/terraform.tfstate`, via the
`backend.tf` 22a's Part B created for this specific key.

**Why this demo has no Cleanup that tears anything down:** same
reasoning as before — these are free or near-free governance resources
meant to protect every session from here forward.

---

## Prerequisites

### Knowledge
- 22a completed — both state keys (`platform/`, `workloads/`)
  bootstrapped
- Demo 03 completed — SNS topic → subscription mechanics
- Demo 06 completed — `aws_sns_topic` and the `jsonencode()` policy
  pattern this demo's topic policy reuses

### Required Tools

(unchanged — Terraform CLI `~> 1.15.0`, AWS CLI `>= 2.x`, `tflint`
`>= 0.46.0`, `checkov` latest stable)

### Versions used in this demo

| Tool | Version |
|---|---|
| Terraform | `~> 1.15.0` |
| AWS Provider | `~> 6.47.0` |

---

## Demo Objectives

1. ✅ Explain the difference between detection and prevention
2. ✅ Write an `aws_cloudwatch_event_rule` on a schedule, targeting an
   SNS topic
3. ✅ Write a standalone `aws_sns_topic_policy`
4. ✅ Encrypt an SNS topic at rest with an AWS managed KMS key
5. ✅ Write an `aws_budgets_budget` with two independent thresholds
6. ✅ Explain why `tflint`/`checkov` aren't Terraform resources
7. ✅ Explain why an auto-remediation Lambda was rejected
8. ✅ **New:** explain why every resource in this project now needs an
   explicit `Tier` tag, and why that tag — not "which state file it
   happens to be tracked in" — is what a future automated check should
   actually filter on

---

## Cost & Free Tier

(unchanged from the original — EventBridge rule, SNS topic/subscription,
AWS managed KMS key, and the one Budgets resource all remain effectively
free at this project's scale. See the original demo's cost table and
its two VERIFY callouts on EventBridge Scheduler vs. classic rules, and
Budgets' free-tier scope, both still open and unaffected by this
revision.)

---

## Directory Structure

```
22b-cost-governance/
├── README.md
├── 22b-cost-governance-anki.csv
├── 22b-cost-governance-quiz.md
└── src/
    ├── platform/                        # CHANGED from phase-3-onward/
    │   ├── versions.tf
    │   ├── provider.tf
    │   ├── backend.tf                   # key = "platform/terraform.tfstate"
    │   ├── variables.tf
    │   ├── locals.tf                     # CHANGED — adds Tier = "platform"
    │   ├── cost_governance.tf
    │   ├── budgets.tf
    │   ├── outputs.tf
    │   ├── terraform.tfvars.example
    │   ├── .tflint.hcl
    │   └── .checkov.yaml
    └── break-fix/
        └── broken.tf
```

---

## Recall Check — 22a (State Backend Bootstrap)

1. Why can't a Terraform backend's own storage be created by the
   configuration that uses it as a backend?
2. Can a `backend` block ever reference a variable, local, or output
   value, in any Terraform version?
3. **New:** why does this project use one S3 bucket with two different
   `key` values, rather than two separate buckets, for platform vs.
   workloads state?

<details>
<summary>Answers</summary>

1. Chicken-and-egg problem — requires a separate bootstrap config.
2. No, never — resolved before any evaluation context exists.
3. The bucket's job (safe, locked storage) doesn't change based on how
   many state files it holds. The `key` argument is what Terraform
   actually uses to keep two state files from ever being reconciled
   against each other — a second bucket would duplicate the bucket's
   own settings for no additional isolation benefit.

</details>

---

## Concepts

### What's New in This Demo

(Table unchanged from the original — `aws_cloudwatch_event_rule`,
`schedule_expression`, `aws_cloudwatch_event_target`,
`aws_sns_topic_subscription`, `aws_sns_topic_policy`,
`kms_master_key_id`, `aws_budgets_budget`, repeatable `notification`
blocks, `tflint`/`checkov` — see original demo text for the full
per-construct explanations, all unaffected by this revision.)

**One addition:**

| Construct | Type | Purpose in this demo |
|---|---|---|
| `Tier` tag in `locals.common_tags` | Applied tagging convention | Distinguishes platform-tier resources (never idle-flagged) from workloads-tier resources (should be idle-flagged) — the concrete mechanism a future session-length check filters on |

---

### Detection vs. Prevention — A Real Design Choice, Not a Caveat

(Unchanged from the original demo — see prior version for the full
detection-vs-prevention framing and the rationale for rejecting
auto-remediation. Still fully applicable; the platform/workloads split
doesn't change this reasoning.)

---

## Lab Step-by-Step Guide

## Part A — EventBridge + SNS Notify

### Step 1 — Navigate to the project config

```bash
cd terraform-aws-mastery/phase-3-real-aws-infrastructure/22b-cost-governance/src/platform
```

### Step 2 — Create the foundation files

**versions.tf** and **provider.tf** — unchanged from the original demo.

**backend.tf** — **changed key**:

```hcl
terraform {
  backend "s3" {
    bucket       = "<YOUR_22A_STATE_BUCKET_NAME>"
    key          = "platform/terraform.tfstate"   # ← was "phase-3-onward/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
  }
}
```

**variables.tf** — unchanged (`aws_region`, `aws_profile`, `project`,
`environment`, `demo`, `notification_email`).

**locals.tf** — **changed, adds the `Tier` tag**:

```hcl
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Demo        = var.demo
    ManagedBy   = "Terraform"
    Tier        = "platform"   # ← NEW — see the Revision Note above
  }
}
```

> **Why this is a `locals.tf` change and not a `variables.tf` change:**
> `Tier` isn't something that should vary per apply the way
> `notification_email` does — it's a structural fact about which
> directory/config this is, fixed for the life of this config. Hardcoding
> it in `locals.tf` (rather than exposing it as a variable someone could
> accidentally override) is the same reasoning already applied to other
> fixed structural facts in this project.

### Step 3 — Create the tfvars template

(unchanged from the original demo)

### Step 4 — Create cost_governance.tf

(unchanged from the original demo — the SNS topic, subscription,
EventBridge rule/target, and topic policy are identical. The `Tier`
tag reaches these resources automatically via `default_tags` on the
provider block, the same mechanism that already applies
`Project`/`Environment`/`Demo`/`ManagedBy` — no per-resource edit
needed.)

> **Open item, unchanged from the original demo, now sharper:** the
> actual idle-resource-check *logic* this rule's target would evaluate
> still doesn't exist — this demo builds the notification *plumbing*
> only. What's new in this revision is that the plumbing now has a
> concrete tag to filter on (`Tier = "workloads"`) once that logic is
> written, rather than an open question of what to filter on at all.

### Step 5 — Apply and confirm the email subscription

(unchanged — expect exactly 5 resources added, confirm the SNS
subscription via the confirmation email, verify encryption in Console)

---

## Part B — AWS Budgets Alarm

(Steps 6–9 unchanged from the original demo — `monthly_budget_limit`
variable, `budgets.tf`, `outputs.tf`, apply, verify in Console. The
`Tier = "platform"` tag reaches the Budget resource the same way, via
`default_tags`.)

---

## Part C — Static Analysis: `tflint` and `checkov`

(Steps 10–12 unchanged from the original demo — install, configure
`.tflint.hcl`/`.checkov.yaml`, run both, confirm 0 issues / all checks
passed. This convention now applies in **both** `platform/` and
`workloads/` going forward — run both tools in whichever directory
you're about to apply.)

---

## Cleanup

**This demo's Cleanup step is verification, not destruction** — same
reasoning as 22a.

```bash
terraform state list
```

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
Console → any resource above → Tags → Tier: platform ✅  (NEW — confirm the tag actually landed)
```

> ⚠️ **Do not run `terraform destroy` in `platform/` at the end of
> this session.** Since this state is separate from `workloads/` as of
> this revision, a `destroy` here would take down only this tier's own
> resources — but they're still meant to persist for the life of the
> project, so don't run it regardless.

> **On `prevent_destroy` — deliberately not applied here, flagged for
> Track 2 to confirm.** ADR-023 calls for `lifecycle { prevent_destroy
> = true }` on platform-tier resources that would **break something
> else** if silently destroyed (ECR repos, ACM cert, IAM roles — see
> 22c and Demo 24). This demo's own resources (SNS topic, EventBridge
> rule, Budget) have no such downstream dependents — losing and
> recreating any of them is cheap and consequence-free, so
> `prevent_destroy` was evaluated and intentionally left off, rather
> than applied uniformly to every platform-tier resource regardless of
> whether it needs it. If Track 2 disagrees with this scoping, add
> the lifecycle block to `cost_governance.tf`'s and `budgets.tf`'s
> resources — no other change is needed.

---

## What You Learned

(items 1–9 unchanged from the original demo)

10. ✅ **New:** a resource's tier (platform vs. workloads) needs to be
    an explicit, queryable tag — not something inferred from which
    directory or state file it happens to live in — because the
    session-length check (and any future automation) can only filter
    on what's actually attached to the resource itself.

---

## Next Demo

**Demo 22c — ECR/ACM Re-Creation**, also built in
`src/terraform/platform/` — re-creating Demo 19's ECR repo (now with
`repository_force_delete = true` added, closing a real destroy-blocking
bug found during this project's own teardown) and re-requesting a new
ACM cert, both tagged `Tier = "platform"` and both protected with
`prevent_destroy`, unlike this demo's own resources.