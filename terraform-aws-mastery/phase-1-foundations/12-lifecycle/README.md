# Demo 12 — The `lifecycle` Meta-Argument

---

## Overview

Every resource so far has followed Terraform's default lifecycle:
change an argument that can't be updated in place, and Terraform
destroys the old instance, then creates the new one. Most of the time
that's fine. Sometimes it isn't — CloudNova needs a queue replaced
without a gap where neither the old nor the new queue exists, a
critical bucket that should never be destroyed even by an honest
mistake, a tag that changes outside Terraform and shouldn't get
reverted every `apply`, and a queue that should be replaced whenever an
unrelated resource it depends on changes. The `lifecycle` block is
Terraform's mechanism for overriding the default create/update/destroy
behavior for exactly these four situations.

**Real-world scenario — CloudNova:** the platform team needs a
notification queue replaced without downtime, a data bucket protected
from accidental `terraform destroy`, a role's tags left alone once
someone adjusts them by hand in the Console, and a fallback queue that
should be rebuilt whenever the primary queue's configuration changes.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — create_before_destroy: Zero-Downtime Replacement              │
│  An SQS queue whose name change would normally destroy-then-create —    │
│  create_before_destroy flips that order                                 │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — prevent_destroy: Guarding Against Accidental Deletion          │
│  An S3 bucket that refuses to be destroyed while the guard is in place  │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — ignore_changes and replace_triggered_by                       │
│  Tolerating out-of-band tag drift   |   forcing replacement of one      │
│  resource when an unrelated resource changes                            │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- `create_before_destroy` — reversing the default destroy-then-create
  order for resources that can't update in place
- `prevent_destroy` — a hard guard against `terraform destroy` and
  block-removal, at the Terraform level (not an AWS-level protection)
- `ignore_changes` — telling Terraform to stop reverting drift on
  specific arguments after the resource is created
- `replace_triggered_by` — forcing a resource to be replaced whenever
  a *different* resource or value changes, even if nothing about the
  first resource's own arguments changed

**What this demo does NOT cover:** provisioners (`local-exec`,
`remote-exec`) are a related but separate mechanism — covered in
Demo 13, the last demo in Phase 1 - Foundations.

---

## How This Demo's Pieces Fit Together

**This demo builds no single connected AWS solution** — like Demo 11,
each Part is a self-contained demonstration of one `lifecycle`
argument, applied to a different, unrelated resource. There's no
shared resource graph to trace across Parts.

**What ties the four arguments together conceptually:** each one
overrides a different piece of Terraform's *default* lifecycle
behavior — not by changing what a resource block does, but by changing
*when* or *whether* Terraform acts on the plan it would otherwise make:

| Argument | What it overrides |
|---|---|
| `create_before_destroy` | The *order* of a replacement (new-then-old, instead of old-then-new) |
| `prevent_destroy` | *Whether* a destroy is allowed to happen at all |
| `ignore_changes` | *Whether* specific drifted arguments get corrected on the next `apply` |
| `replace_triggered_by` | *Whether* a replacement happens, driven by something outside the resource's own arguments |

None of these change what a resource *is* — they change how Terraform
manages the transition between resource states, which is why this demo
sits here, right before Provisioners (Demo 13) closes out
Phase 1 - Foundations.

---

## Prerequisites

### Knowledge
- Demo 11 completed — state addressing, the `count` reordering trap,
  and `moved` blocks

### Required Tools

Same as Demos 05–11 — Terraform `>= 1.15.0`, AWS CLI `>= 2.x`, `jq`.

### Verify AWS Account and Permissions

```bash
aws sts get-caller-identity --profile default
aws configure get region --profile default
```

**Required permissions for this demo:**

```
sqs:CreateQueue, sqs:DeleteQueue, sqs:GetQueueAttributes, sqs:ListQueues
s3:CreateBucket, s3:DeleteBucket, s3:PutBucketTagging, s3:ListBucket
iam:CreateRole, iam:DeleteRole, iam:GetRole, iam:TagRole
```

> For a learning account, `AmazonSQSFullAccess`, `AmazonS3FullAccess`,
> and `IAMFullAccess` managed policies cover the permissions above.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Use `create_before_destroy` to reverse the default replacement
   order for a resource that must be replaced
2. ✅ Use `prevent_destroy` to block both `terraform destroy` and
   accidental block-removal, and correctly remove the guard when a
   destroy is genuinely intended
3. ✅ Use `ignore_changes` to stop Terraform from reverting drift on
   specific arguments after creation
4. ✅ Use `replace_triggered_by` to force one resource's replacement
   based on a change to a completely different resource or value

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| SQS queues (×2) | Free forever — 1M requests/month | **$0.00** | |
| S3 bucket (×1, empty) | Free for the bucket itself | **$0.00** | |
| IAM role (×1) | Always free | **$0.00** | |
| **Session total** | | **$0.00** | |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
12-lifecycle/
├── README.md
├── 12-lifecycle-anki.csv
├── 12-lifecycle-quiz.md
└── src/
    ├── 01-versions.tf       # terraform block + provider version constraints
    ├── 02-provider.tf       # AWS provider: region, profile
    ├── 03-variables.tf      # queue name variable, bucket name
    ├── 04-queue-cbd.tf      # create_before_destroy SQS queue
    ├── 05-bucket-pd.tf      # prevent_destroy S3 bucket
    ├── 06-role-ignore.tf    # ignore_changes IAM role + replace_triggered_by fallback queue
    ├── 07-outputs.tf        # exposes what was built
    └── break-fix/
        └── broken.tf
```

---

## Recall Check — Demo 11

Answer from memory before reading further:

1. What does a `moved` block actually change — the real AWS resource,
   or something else?
2. A `count`-driven resource's middle list item is removed. What does
   `terraform plan` propose, and why?
3. After a correct `count`-to-`for_each` migration using `moved`
   blocks, what should `terraform plan` report?

<details>
<summary>Answers</summary>

1. Only Terraform's own state bookkeeping — which address maps to
   which tracked object. The real AWS resource (same ARN, same
   creation date) is completely untouched.
2. Every index after the removed item shifts down by one, and each
   shifted index's changed name forces replacement — not just the
   removed item. The last instance in the original list is destroyed
   outright.
3. `Plan: 0 to add, 0 to change, 0 to destroy`, with "has moved to"
   messages for each migrated instance — confirming the migration was
   mapped correctly, with zero actual resource lifecycle events.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `lifecycle` block | Resource meta-argument block | Overrides default create/update/destroy behavior |
| `create_before_destroy` | `lifecycle` argument | Creates the replacement before destroying the original |
| `prevent_destroy` | `lifecycle` argument | Blocks `terraform destroy` and block-removal for this resource |
| `ignore_changes` | `lifecycle` argument | Stops Terraform from correcting drift on named arguments |
| `replace_triggered_by` | `lifecycle` argument | Forces replacement when a referenced resource/value changes |

**Related constructs worth knowing (not covered in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| Provisioners (`local-exec`, `remote-exec`) | Imperative script execution tied to a resource's lifecycle | Demo 13 |
| `precondition`/`postcondition` blocks | Custom validation tied to a resource's lifecycle | Not covered in this series yet |

---

### Detailed Explanation of New Constructs

#### `create_before_destroy` — Reversing the Default Replacement Order

By default, when an argument change forces replacement, Terraform
destroys the old instance **first**, then creates the new one —
meaning there's a window where neither exists.

```hcl
resource "aws_sqs_queue" "notifications" {
  name = var.queue_name

  lifecycle {
    create_before_destroy = true
  }
}
```

With `create_before_destroy = true`, Terraform creates the **new**
instance first, waits for it to succeed, and only then destroys the
old one. There is no window where the queue doesn't exist at all.

> **This doesn't make replacement free.** For a short window, *both*
> the old and new queues exist simultaneously — for SQS this is
> harmless (queue names just need to be unique), but for resources
> with hard uniqueness constraints (like a fixed DNS name), this can
> itself cause a conflict. `create_before_destroy` trades "gap" for
> "brief overlap" — it doesn't eliminate the tradeoff, it picks the
> side that's usually safer.

---

#### `prevent_destroy` — Blocking Destruction at the Terraform Level

```hcl
resource "aws_s3_bucket" "critical_data" {
  bucket = var.critical_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}
```

With `prevent_destroy = true`, **both** `terraform destroy` and simply
removing the resource block from the configuration error instead of
proceeding:

```
Error: Instance cannot be destroyed

Resource aws_s3_bucket.critical_data has lifecycle.prevent_destroy
set, but the plan calls for this resource to be destroyed. To avoid
this error and continue with the plan, either disable
lifecycle.prevent_destroy or reduce the scope of the plan using the
-target flag.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **This is a Terraform-level guard, not an AWS-level one.** It has no
> effect on anyone deleting the bucket directly via the AWS Console or
> CLI — `prevent_destroy` only blocks Terraform's own destroy path. To
> genuinely destroy a `prevent_destroy` resource on purpose, you must
> first remove or set `prevent_destroy = false`, `apply` that change
> (which itself does nothing destructive), and only then run
> `destroy`.

---

#### `ignore_changes` — Tolerating Specific Drift

```hcl
resource "aws_iam_role" "deploy" {
  name = "cloudnova-dev-deploy-role"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}
```

Normally, if something outside Terraform modifies `tags` (someone adds
a tag via the Console), the next `plan`/`apply` proposes reverting it
back to match the `.tf` file — Terraform always treats its own
configuration as the source of truth by default. `ignore_changes =
[tags]` tells Terraform to stop checking that specific argument for
drift entirely; whatever value currently exists in AWS is left alone,
indefinitely, regardless of what the `.tf` file says.

> **`ignore_changes` takes a list of argument names, or the special
> value `all`.** `ignore_changes = [tags]` ignores drift on `tags`
> only; `ignore_changes = all` ignores drift on every argument — rarely
> what you actually want, since it also stops Terraform from applying
> *your own* intentional future changes to those arguments.

---

#### `replace_triggered_by` — Forcing Replacement from an Unrelated Change

```hcl
resource "aws_sqs_queue" "fallback" {
  name = "cloudnova-fallback-queue"

  lifecycle {
    replace_triggered_by = [aws_iam_role.deploy.arn]
  }
}
```

Normally, a resource is only replaced when *its own* arguments change
in a replacement-forcing way. `replace_triggered_by` adds an extra
trigger: whenever the **referenced** resource's attribute changes
(here, `aws_iam_role.deploy.arn`), this resource is replaced too — even
though nothing about the fallback queue's own configuration changed at
all.

> **Why this is useful:** some resources need to be rebuilt whenever
> something they conceptually depend on changes, even without a direct
> Terraform argument reference creating that dependency. This is the
> mechanism for expressing "replace this whenever that changes," when
> "that" isn't naturally part of this resource's own arguments.

---

## Lab Step-by-Step Guide

---

## Part A — create_before_destroy: Zero-Downtime Replacement

**What you accomplish in Part A:** create an SQS queue, then force a
name change that would normally destroy-then-create — with
`create_before_destroy` in place, observe the new queue being created
before the old one is destroyed.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/12-lifecycle/src
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
}
```

---

#### `03-variables.tf` — Inputs for all three Parts

**What this file does in this demo:** `queue_name` drives Part A's
replacement demonstration directly — changing its value is what forces
the queue to be replaced.

**03-variables.tf:**

```hcl
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

variable "queue_name" {
  type        = string
  description = "Name of the notifications queue — changing this forces replacement"
  default     = "cloudnova-notifications-v1"
}

variable "critical_bucket_name" {
  type        = string
  description = "Name of the protected critical-data bucket"
  default     = "cloudnova-critical-data-163125980376"
}
```

---

#### `04-queue-cbd.tf` — create_before_destroy queue

**What this file does in this demo:** `name = var.queue_name` means
changing `queue_name` forces replacement (SQS queue names can't be
renamed in place) — `create_before_destroy` controls the *order* of
that replacement.

**04-queue-cbd.tf:**

```hcl
resource "aws_sqs_queue" "notifications" {
  name = var.queue_name

  tags = {
    ManagedBy = "terraform-demo-12"
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

---

### Step 3 — Apply the baseline

```bash
terraform init
terraform validate
terraform apply
```

**Verify:**

```
Console → SQS → Queues → cloudnova-notifications-v1
  → exists, tagged ManagedBy=terraform-demo-12 ✅
```

### Step 4 — Force replacement and observe the create-before-destroy order

```bash
terraform apply -var="queue_name=cloudnova-notifications-v2"
```

Expected — note the **order** of the two lifecycle events:

```
Terraform will perform the following actions:

  # aws_sqs_queue.notifications must be replaced
+/- resource "aws_sqs_queue" "notifications" {
      ~ name = "cloudnova-notifications-v1" -> "cloudnova-notifications-v2" # forces replacement
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```
```
aws_sqs_queue.notifications: Creating...
aws_sqs_queue.notifications: Creation complete after 1s [id=...v2]
aws_sqs_queue.notifications: Destroying... [id=...v1]
aws_sqs_queue.notifications: Destruction complete after 0s
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **The plan symbol is `+/-` (create then destroy), not `-/+`
> (destroy then create).** This ordering flip is exactly what
> `create_before_destroy` controls — compare this against Demo 05
> Part B, where a forced replacement (changing `environment`) showed
> `-/+` because no `lifecycle` block was present there at all.

**Verify:**

```
Console → SQS → Queues
  → cloudnova-notifications-v2 exists; cloudnova-notifications-v1 is gone ✅
```

```bash
terraform apply -var="queue_name=cloudnova-notifications-v1"
```

---

## Part B — prevent_destroy: Guarding Against Accidental Deletion

**What you accomplish in Part B:** create an S3 bucket guarded by
`prevent_destroy`, confirm both `terraform destroy` and block-removal
are blocked, then correctly remove the guard when destruction is
genuinely intended.

### Step 1 — Create `05-bucket-pd.tf`

**What this file does in this demo:** a single S3 bucket with
`prevent_destroy = true` — this is the entire subject of Part B.

Create a file **05-bucket-pd.tf** and add the below content:

```hcl
resource "aws_s3_bucket" "critical_data" {
  bucket = var.critical_bucket_name

  tags = {
    ManagedBy = "terraform-demo-12"
  }

  lifecycle {
    prevent_destroy = true
  }
}
```

### Step 2 — Apply, then attempt to destroy

```bash
terraform apply
terraform destroy -target=aws_s3_bucket.critical_data
```

Expected:

```
Error: Instance cannot be destroyed

Resource aws_s3_bucket.critical_data has lifecycle.prevent_destroy
set, but the plan calls for this resource to be destroyed. To avoid
this error and continue with the plan, either disable
lifecycle.prevent_destroy or reduce the scope of the plan using the
-target flag.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

**Verify:**

```
Console → S3 → Buckets → cloudnova-critical-data-163125980376
  → still exists — the destroy attempt above never reached AWS at all,
    it was rejected by Terraform before any API call ✅
```

### Step 3 — Correctly remove the guard, then destroy on purpose

This is the deliberate, correct sequence for destroying a
`prevent_destroy` resource — never remove the resource block directly
while the guard is still in place.

Update `05-bucket-pd.tf`'s `lifecycle` block:

```hcl
  lifecycle {
    prevent_destroy = false
  }
```

```bash
terraform apply
terraform destroy -target=aws_s3_bucket.critical_data
```

> **This two-step sequence is intentional, not extra caution for its
> own sake.** Setting `prevent_destroy = false` and applying it first
> means Terraform's own state now agrees the guard is off, before any
> destroy is attempted — never remove the guard and destroy in what
> you assume is "one step," since a stale plan could still reflect the
> old guard.

---

## Part C — ignore_changes and replace_triggered_by

**What you accomplish in Part C:** create an IAM role whose `tags`
tolerate out-of-band drift, and a fallback SQS queue that's replaced
whenever the role's ARN changes — even though nothing about the queue
itself changes.

### Step 1 — Create `06-role-ignore.tf`

**What this file does in this demo:** the IAM role's `ignore_changes =
[tags]` is this Part's first subject; the fallback queue's
`replace_triggered_by` referencing the role's `arn` is the second —
both demonstrated together since the fallback queue needs the role to
already exist.

Create a file **06-role-ignore.tf** and add the below content:

```hcl
resource "aws_iam_role" "deploy" {
  name = "cloudnova-dev-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAssumeRole"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::163125980376:root" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_sqs_queue" "fallback" {
  name = "cloudnova-fallback-queue"

  tags = {
    ManagedBy = "terraform-demo-12"
  }

  lifecycle {
    replace_triggered_by = [aws_iam_role.deploy.arn]
  }
}
```

### Step 2 — Apply, then drift a tag out-of-band

```bash
terraform apply
aws iam tag-role \
  --role-name cloudnova-dev-deploy-role \
  --tags Key=AddedManually,Value=true \
  --profile default --region us-east-2
```

```bash
terraform plan
```

Expected: `No changes.` — the manually-added tag is **not** proposed
for removal, because `ignore_changes = [tags]` tells Terraform to stop
checking `tags` for drift entirely.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

**Verify:**

```
Console → IAM → Roles → cloudnova-dev-deploy-role → Tags
  → AddedManually=true is present and untouched by terraform plan ✅
```

### Step 3 — Force the role's replacement and observe the fallback queue follow

```bash
terraform apply -replace="aws_iam_role.deploy"
```

Expected: the role is replaced (new ARN), and — with no change to
`aws_sqs_queue.fallback`'s own arguments at all — the fallback queue is
**also** replaced, because `replace_triggered_by` is watching the
role's `arn`:

```
Plan: 2 to add, 0 to change, 2 to destroy.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **`terraform apply -replace=ADDRESS` forces a specific resource's
> replacement manually** — a convenient way to demonstrate
> `replace_triggered_by` without needing a real argument change on the
> role itself.

**Verify:**

```
Console → SQS → Queues → cloudnova-fallback-queue
  → new creation timestamp, different from Step 2's apply — confirms
    it was genuinely replaced, not left alone ✅
```

---

## Cleanup

```bash
terraform destroy
```

Type `yes`. Expected: `Destroy complete! Resources: 4 destroyed.` (2
queues, 1 bucket, 1 role).

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment. Confirm `05-bucket-pd.tf`'s `prevent_destroy` is set to
> `false` (from Part B, Step 3) before running this — otherwise the
> bucket blocks the whole destroy.

```bash
aws sqs list-queues --queue-name-prefix cloudnova --profile default --region us-east-2
aws s3 ls --profile default --region us-east-2 | grep cloudnova-critical
aws iam get-role --role-name cloudnova-dev-deploy-role --profile default --region us-east-2
```

Expected: all three commands return empty or a "not found" error.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## What You Learned

1. ✅ `create_before_destroy` reverses the default replacement order —
   the plan symbol changes from `-/+` to `+/-`, and there's a brief
   overlap instead of a gap
2. ✅ `prevent_destroy` blocks both `terraform destroy` and
   block-removal at the Terraform level — it has no effect on
   deletions made outside Terraform entirely
3. ✅ `ignore_changes = [tags]` (or any argument list) stops Terraform
   from reverting drift on those specific arguments indefinitely
4. ✅ `replace_triggered_by` forces a resource's replacement based on a
   *different* resource's change — even when nothing about the first
   resource's own configuration changed

---

## Cert Tips — TA-004 Objectives Covered

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `create_before_destroy` | TA-004 Obj (resource management) | Know the plan symbol changes from `-/+` to `+/-` |
| `prevent_destroy` | TA-004 Obj (resource management) | Common trap: assuming it's an AWS-level protection |
| `ignore_changes` | TA-004 Obj (resource management) | `all` vs. a specific argument list — know the difference |
| `replace_triggered_by` | TA-004 Obj (resource management) | Tests understanding that a resource can be replaced with zero changes to its own arguments |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam asks whether `prevent_destroy` stops someone from deleting the resource in the AWS Console | Recognizing this is a Terraform-only guard — it has zero effect outside Terraform's own destroy path | Assuming `prevent_destroy` is an AWS-level deletion protection |
| Exam shows a resource with `replace_triggered_by` referencing another resource, and asks what forces this resource's replacement | Recognizing the *referenced* resource's change is what triggers it, not this resource's own arguments | Assuming replacement only ever comes from a resource's own argument changes |
| Exam asks how to destroy a `prevent_destroy` resource on purpose | Recognizing the guard must be removed/disabled and applied *first*, as a separate step, before `destroy` | Assuming `-target` or `-force` alone bypasses `prevent_destroy` |

### Exam Task — Write a complete configuration

**Task:** CloudNova needs an SQS queue that replaces without downtime
when its name changes, and a second queue that must be replaced
whenever the first queue's ARN changes. Write both from scratch.

**Block types required:** `resource` (×2), `lifecycle` (×2)

**Official documentation:**
- [Meta-Arguments: `lifecycle`](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle)

**What to practise:**
1. Open the `lifecycle` documentation — confirm `replace_triggered_by`
   accepts resource attribute references, not just resource addresses
2. Write both resources from scratch without looking at this demo's
   `.tf` files
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
resource "aws_sqs_queue" "primary" {
  name = var.primary_queue_name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_sqs_queue" "secondary" {
  name = "cloudnova-secondary-queue"

  lifecycle {
    replace_triggered_by = [aws_sqs_queue.primary.arn]
  }
}
```

**Arguments you must know without looking up:**
- `replace_triggered_by` takes a list of **attribute references**
  (`aws_sqs_queue.primary.arn`), not bare resource addresses
- `create_before_destroy` and `replace_triggered_by` can coexist on the
  same resource if both behaviors are needed together

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Error: Instance cannot be destroyed` | `prevent_destroy = true` is still set on a resource being destroyed | Set `prevent_destroy = false`, `apply` that change first, then destroy |
| `terraform destroy` blocks the whole run over one resource | A `prevent_destroy` resource is part of a full `terraform destroy` | Use `-target` to destroy other resources individually, or disable the guard first |
| A manually-added tag keeps disappearing on every `apply` | `ignore_changes` doesn't include that argument | Add the argument's name to the `ignore_changes` list |
| A resource replaces unexpectedly with no argument change of its own | `replace_triggered_by` is watching a resource that changed | Check what's referenced in `replace_triggered_by` — the trigger is intentional, not a bug, if configured correctly |

---

## Break-Fix Scenario

Three deliberate errors, all `lifecycle`-specific. Diagnose using
`terraform validate`/`plan` — do not look at answers first.

```bash
cd src/break-fix/
terraform init
terraform validate
terraform plan
```

#### `broken.tf` — Three deliberate lifecycle errors

**What this file does in this demo:** a self-contained configuration
with `prevent_destroy` set on a resource then immediately removed from
the config, `ignore_changes` given a non-existent argument name, and
`replace_triggered_by` referencing a resource address instead of an
attribute — diagnose all three.

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

resource "aws_sqs_queue" "primary" {
  name = "cloudnova-broken-primary"

  lifecycle {
    ignore_changes = [nonexistent_argument] # Error 1
  }
}

resource "aws_sqs_queue" "secondary" {
  name = "cloudnova-broken-secondary"

  lifecycle {
    replace_triggered_by = [aws_sqs_queue.primary] # Error 2 — bare resource, not an attribute
  }
}

resource "aws_s3_bucket" "guarded" {
  bucket = "cloudnova-broken-guarded-163125980376"

  lifecycle {
    prevent_destroy = true
  }
}
```

```bash
# Error 3 demonstrated separately — remove the aws_s3_bucket.guarded
# block entirely from this file, then:
terraform plan
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — `ignore_changes` referencing a nonexistent argument**
`nonexistent_argument` isn't a real argument on `aws_sqs_queue`.
`terraform validate` errors that this isn't a valid attribute
reference for this resource type. Fix: use a real argument name, e.g.
`tags`.

**Error 2 — `replace_triggered_by` given a bare resource, not an
attribute reference**
`[aws_sqs_queue.primary]` references the whole resource, not one of
its attributes. `terraform validate` errors that `replace_triggered_by`
requires a specific attribute reference. Fix: reference a real
attribute, e.g. `aws_sqs_queue.primary.arn`.

**Error 3 — removing a `prevent_destroy` resource's block entirely**
Deleting the `aws_s3_bucket.guarded` block from the configuration
(rather than destroying it properly) still counts as "this resource
should be destroyed" from Terraform's perspective — `prevent_destroy`
blocks this exactly the same way it blocks `terraform destroy`.
`terraform plan` errors: "Instance cannot be destroyed." Fix: restore
the block, set `prevent_destroy = false`, `apply`, *then* remove the
block.

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

**Q1. A teammate says `prevent_destroy` protects a resource from being deleted, full stop. What's the nuance?**
It only protects against Terraform's own destroy path — `terraform destroy`, or removing the resource block from the configuration. It has zero effect on anyone deleting the resource directly via the AWS Console, CLI, or another tool entirely. `prevent_destroy` is a guard against Terraform-driven deletion, not a general AWS-level protection.

**Q2. Why would you ever need `replace_triggered_by` instead of just adding a direct argument reference between the two resources?**
Sometimes there's no natural argument that should reference the other resource — forcing an artificial reference just to create a dependency would be misleading about what the resource actually needs to function. `replace_triggered_by` expresses "rebuild this whenever that changes" as an explicit lifecycle relationship, without requiring an argument-level dependency that doesn't otherwise make sense.

**Q3. What's the correct sequence to intentionally destroy a resource that has `prevent_destroy = true`?**
First, change `prevent_destroy` to `false` in the configuration and run `apply` — this updates Terraform's own understanding that the guard is now off, without destroying anything yet. Only after that succeeds should you run `terraform destroy` (or remove the resource block and apply). Attempting to remove the guard and destroy in what feels like one step risks a stale plan still reflecting the old guard.

---

## Key Takeaways

1. **`create_before_destroy` flips the plan symbol from `-/+` to
   `+/-`.** There's a brief overlap instead of a gap — not free, but
   usually the safer tradeoff for stateless resources.

2. **`prevent_destroy` is a Terraform-only guard.** It stops
   `terraform destroy` and block-removal — nothing about it reaches
   AWS or prevents deletion through any other path.

3. **`ignore_changes` takes a list of argument names, or `all`.**
   Prefer naming specific arguments — `all` also blocks your own
   future intentional changes to everything it covers.

4. **`replace_triggered_by` forces replacement from an unrelated
   resource's change** — the referenced resource's attribute, not this
   resource's own arguments, is what triggers it.

> **Demo scope:** Primary concept: the `lifecycle` meta-argument block
> — `create_before_destroy`, `prevent_destroy`, `ignore_changes`,
> `replace_triggered_by`. Supporting concepts: the Terraform-only
> nature of `prevent_destroy`, and the correct two-step sequence for
> intentionally destroying a guarded resource.
> Estimated completion time: 35 minutes (reading + hands-on + verification).
> Checkpoints: 3 natural stopping points (end of Part A, end of Part B,
> end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform apply -replace="ADDRESS"` | Forces a specific resource's replacement manually — useful for demonstrating `replace_triggered_by` |
| `terraform destroy -target=ADDRESS` | Destroys one specific resource rather than everything in state |
| `aws iam tag-role --role-name NAME --tags Key=K,Value=V` | Adds a tag out-of-band, to test `ignore_changes` |

---

## Next Demo

**Demo 13 — Provisioners:** `local-exec` and `remote-exec`, the
`when = destroy` provisioner variant, and the decision framework for
when a provisioner is genuinely the right tool versus a last resort —
the final demo in Phase 1 - Foundations.

---

## Appendix — Anki Cards

**12-lifecycle-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::12-lifecycle
#separator:Comma
#columns:Front,Back,Tags
"What plan symbol does create_before_destroy produce for a forced replacement, instead of the default -/+?","+/- — create first, then destroy. The default (no lifecycle block) is -/+, destroy first then create, which leaves a gap where neither instance exists.","demo12,create-before-destroy,ta004"
"Does prevent_destroy stop someone from deleting a resource directly in the AWS Console?","No — prevent_destroy only blocks Terraform's own destroy path (terraform destroy, or removing the resource block). It has zero effect on deletions made outside Terraform entirely.","demo12,prevent-destroy,ta004"
"What is the correct sequence to intentionally destroy a resource with prevent_destroy = true?","Set prevent_destroy = false in the config, run apply first (this alone destroys nothing), then run terraform destroy. Removing the guard and destroying in what feels like one step risks a stale plan still reflecting the old guard.","demo12,prevent-destroy,sequence"
"What does ignore_changes = [tags] do if someone adds a tag to a resource outside Terraform?","Terraform stops checking the tags argument for drift entirely — the manually-added tag is never proposed for removal on subsequent plans, regardless of what the .tf file's tags block says.","demo12,ignore-changes,ta004"
"What is the difference between ignore_changes = [tags] and ignore_changes = all?","[tags] ignores drift only on the tags argument. all ignores drift on every argument — which also blocks your own future intentional changes to all of them, not just externally-caused drift.","demo12,ignore-changes"
"What does replace_triggered_by = [aws_iam_role.deploy.arn] actually watch?","A specific attribute (arn) of a different resource (aws_iam_role.deploy). Whenever that attribute's value changes, this resource is replaced too — even if nothing about this resource's own arguments changed at all.","demo12,replace-triggered-by,ta004"
"Can replace_triggered_by reference a bare resource address, e.g. [aws_sqs_queue.primary], instead of one of its attributes?","No — terraform validate errors. replace_triggered_by requires a specific attribute reference, e.g. aws_sqs_queue.primary.arn, not the resource as a whole.","demo12,replace-triggered-by,break-fix"
"What command forces a specific resource's replacement manually, without changing any of its arguments?","terraform apply -replace=\"ADDRESS\" — useful for demonstrating replace_triggered_by's effect on a dependent resource without needing a real argument change.","demo12,commands,replace"
"Can create_before_destroy and replace_triggered_by be used together on the same resource?","Yes — they solve different problems (ordering vs. triggering) and can coexist whenever a resource needs both zero-downtime replacement AND to be replaced in response to another resource's change.","demo12,lifecycle,combination"
```

---

## Appendix — Quiz

**12-lifecycle-quiz.md:**

````markdown
# Quiz — Demo 12: The lifecycle Meta-Argument

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 13.

---

**Q1. (Multiple Choice)** What plan symbol does
`create_before_destroy = true` produce for a forced replacement?

- A) `-/+` (destroy then create)
- B) `+/-` (create then destroy)
- C) `~` (update in place)
- D) No symbol — the plan shows no action at all

<details>
<summary>Answer</summary>

**B.** The new instance is created first, then the old one is
destroyed — reversing the default `-/+` order. **A** is the *default*
behavior without `create_before_destroy`. **C** is wrong — this is
still a full replacement, never an in-place update. **D** is wrong —
a replacement is always a visible plan action.

</details>

---

**Q2. (True/False)** `prevent_destroy = true` prevents the resource
from being deleted through the AWS Console or CLI, in addition to
blocking `terraform destroy`.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `prevent_destroy` is a Terraform-only guard — it has
zero effect on deletions made outside Terraform's own destroy path
entirely.

</details>

---

**Q3. (Multiple Choice)** What is the correct sequence to intentionally
destroy a resource with `prevent_destroy = true`?

- A) Run `terraform destroy -force`
- B) Remove the resource block directly, then run `apply`
- C) Set `prevent_destroy = false`, `apply` that change, then destroy
- D) `prevent_destroy` cannot ever be removed once set

<details>
<summary>Answer</summary>

**C.** The guard must be disabled and applied as its own step first,
before any destroy is attempted. **A** is wrong — there's no
`-force` flag that bypasses `prevent_destroy`. **B** is wrong — this
still triggers the guard, since Terraform sees the resource "should be
destroyed" either way. **D** is wrong — the guard is just a
configuration value; it can always be changed.

</details>

---

**Q4. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about `ignore_changes` are correct?

- A) `ignore_changes = [tags]` only stops drift-checking on the `tags` argument
- B) `ignore_changes = all` is generally preferable since it's more thorough
- C) `ignore_changes = all` also blocks your own intentional future changes to every argument it covers
- D) `ignore_changes` can only be used on `tags`, never other arguments
- E) `ignore_changes` requires a `moved` block to take effect

<details>
<summary>Answer</summary>

**A and C.** A specific argument list is scoped narrowly; `all` is
broad and has the real downside of blocking your own future
intentional edits, not just external drift. **B** is wrong — `all`
being "thorough" is exactly the problem, not a benefit. **D** is
wrong — `ignore_changes` works on any argument name. **E** is wrong —
`moved` blocks are unrelated to `ignore_changes` entirely.

</details>

---

**Q5. (Multiple Choice)** `replace_triggered_by = [aws_iam_role.deploy]`
(the bare resource, not an attribute) is written on a different
resource. What happens?

- A) It works — Terraform infers a default attribute to watch
- B) `terraform validate` errors — a specific attribute reference is required
- C) It silently does nothing
- D) It triggers replacement on every `apply`, regardless of change

<details>
<summary>Answer</summary>

**B.** `replace_triggered_by` requires an attribute reference (e.g.
`aws_iam_role.deploy.arn`), not a bare resource. **A** is wrong — there
is no inferred default attribute. **C** is wrong — this is a real
validation error, not silent. **D** is wrong — this never gets far
enough to run at all, since it fails validation first.

</details>

---

**Q6. (Multiple Choice)** A resource is replaced even though none of
its own arguments changed in the `.tf` file. What's the most likely
explanation?

- A) Terraform has a bug
- B) `replace_triggered_by` is watching a different resource that changed
- C) `ignore_changes` was misconfigured
- D) `create_before_destroy` forces periodic replacement automatically

<details>
<summary>Answer</summary>

**B.** This is exactly what `replace_triggered_by` is for — forcing
replacement based on something outside the resource's own arguments.
**A** is wrong — this is expected, documented behavior, not a bug.
**C** is wrong — `ignore_changes` only suppresses drift-correction, it
never forces a replacement. **D** is wrong — `create_before_destroy`
only affects the *order* of a replacement that's already happening for
another reason; it never triggers one on its own.

</details>

---

**Q7. (True/False)** `create_before_destroy` and `replace_triggered_by`
can both be set in the same `lifecycle` block on one resource.

- A) True
- B) False

<details>
<summary>Answer</summary>

**A) True.** They solve different problems — ordering vs. triggering
— and commonly coexist when a resource needs zero-downtime replacement
AND needs to respond to another resource's changes.

</details>

---

**Q8. (Multiple Choice)** What command manually forces a specific
resource's replacement, without changing any of its actual
configuration?

- A) `terraform taint ADDRESS` only
- B) `terraform apply -replace="ADDRESS"`
- C) `terraform destroy -target=ADDRESS` followed by nothing else
- D) Editing the resource's `id` directly in the state file

<details>
<summary>Answer</summary>

**B.** `-replace` is the modern, direct way to force one resource's
replacement on the next `apply`. **A** references an older, deprecated
mechanism (`taint`) not covered as this demo's primary approach. **C**
is wrong — that destroys without recreating, which isn't "replacement."
**D** is wrong — manually editing state directly is never the correct
way to force anything; it risks corrupting state.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 7-8/8 | Import Anki cards, move to Demo 13 |
| 6/8 | Review the wrong answers, then proceed |
| 4-5/8 | Re-read the relevant sections, retry those questions |
| Below 4/8 | Re-read the full demo and redo the walkthrough before proceeding |
````