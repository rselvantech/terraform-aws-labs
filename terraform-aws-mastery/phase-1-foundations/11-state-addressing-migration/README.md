# Demo 11 — State Addressing and Multiplicity Migration

---

## Overview

Demo 10 built three SQS dead-letter queues with `count` and warned that
index-based addressing has a real cost: `count` has no concept of a
queue's *identity*, only its *position*. This demo makes that cost
concrete. CloudNova's platform team wants to remove one queue from the
middle of a three-queue list — a completely routine change — and
discovers that Terraform proposes replacing not just the removed
queue, but every queue after it too. This demo shows exactly why that
happens, then fixes it permanently by migrating the same resource from
`count` to `for_each` without destroying a single queue in the process.

**Real-world scenario — CloudNova:** three named dead-letter queues
(`orders`, `payments`, `shipping`), built with `count` because that's
what Demo 10 taught first. The platform team needs to remove
`payments` — a queue in the *middle* of the list — and needs to
understand, live, what Terraform proposes to do about it before
running `apply` on a plan they don't understand.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — State Addressing Mechanics                                    │
│  resource[0] vs. resource["key"] compared directly against the same     │
│  underlying resources   |   terraform state list / state show           │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — The count Reordering Trap, Live                               │
│  Remove the middle item from a name-driven count list   |   read the    │
│  destructive plan Terraform proposes, and understand exactly why        │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Migrating count to for_each Without Destroy/Recreate          │
│  The moved block   |   terraform state list index/key filtering   |     │
│  confirm zero destroys after migration                                  │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- State addressing: `resource[0]` (index) vs. `resource["key"]` (key) —
  what each actually looks like in `terraform state list`/`state show`
- The `count` mid-list-removal replacement trap — reproduced live, not
  just described
- The `moved` block — migrating a resource from `count` to `for_each`
  so Terraform recognizes existing instances as the same objects,
  instead of planning destroy + create
- `terraform state list` with index/key filtering

**What this demo does NOT cover:** `dynamic` blocks were already
merged into Demo 10 alongside `count`/`for_each`, so there's no
separate `dynamic` comparison here — this demo is entirely about state
mechanics for resources that already use `count` or `for_each`, not
about choosing between the multiplicity mechanisms in the first place
(that decision framework is Demo 10's territory).

---

## How This Demo's Pieces Fit Together

**This demo builds no new AWS solution** — it takes the exact SQS
queues and S3 buckets Demo 10 already taught `count`/`for_each` with,
and puts them through a state-mechanics exercise. There's no new
resource graph to trace; the "solution" here is a *technique*
(migrating addressing schemes safely), not an architecture.

**The one deliberate connective thread across all three Parts:**
the same three queues (`orders`, `payments`, `shipping`) are the
subject of Part A's addressing comparison, Part B's reordering trap,
and Part C's migration — watched through one continuous state
lifecycle rather than three separate examples:
- **Part A** creates them and shows what their addresses look like
  right now (`dlq[0]`, `dlq[1]`, `dlq[2]`)
- **Part B** breaks something by removing `payments` from the middle
  of the list — read carefully, not applied
- **Part C** fixes the underlying cause permanently by migrating the
  same three queues to `for_each`, using `moved` blocks to prove to
  Terraform they're the same real objects under new addresses

By the end, the same three real SQS queues that existed at the start
of Part A still exist, unchanged, at the end of Part C — only their
addressing scheme changed. That continuity (same resources, evolving
address scheme) is the thing to track across this demo, not a growing
resource inventory.

---

## Prerequisites

### Knowledge
- Demo 10 completed — `count`, `count.index`, `for_each`, `each.key`/
  `each.value`, `toset()`, and splat expressions

### Required Tools

Same as Demos 05–10 — Terraform `>= 1.15.0`, AWS CLI `>= 2.x`, `jq`.

### Verify AWS Account and Permissions

```bash
aws sts get-caller-identity --profile default
aws configure get region --profile default
```

**Required permissions for this demo:**

```
sqs:CreateQueue, sqs:DeleteQueue, sqs:GetQueueAttributes, sqs:ListQueues
s3:CreateBucket, s3:DeleteBucket, s3:PutBucketTagging, s3:ListBucket
```

> For a learning account, `AmazonSQSFullAccess` and `AmazonS3FullAccess`
> managed policies cover the permissions above.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Read and compare `resource[0]` (index-based) and
   `resource["key"]` (key-based) addressing directly in
   `terraform state list`/`state show`
2. ✅ Reproduce the `count` mid-list-removal replacement trap live, and
   explain precisely why removing a middle item forces replacement of
   every subsequent instance
3. ✅ Use a `moved` block to migrate a resource from `count` to
   `for_each` with zero destroys — Terraform recognizes existing
   instances as the same objects under their new addresses
4. ✅ Use `terraform state list` with index/key filtering to target
   individual instances from the CLI

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| SQS queues (×3, standard) | Free forever — 1M requests/month | **$0.00** | |
| S3 buckets (×2, empty) | Free for the buckets themselves | **$0.00** | Rebuilt minimally, for index-vs-key comparison only |
| **Session total** | | **$0.00** | |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
11-state-addressing-migration/
├── README.md
├── 11-state-addressing-migration-anki.csv
├── 11-state-addressing-migration-quiz.md
└── src/
    ├── 01-versions.tf         # terraform block + provider version constraints
    ├── 02-provider.tf         # AWS provider: region, profile
    ├── 03-variables.tf        # dlq_names list, environments map
    ├── 04-count-queues.tf     # count-driven queues, name-list-indexed — this demo's focus
    ├── 05-foreach-buckets.tf  # for_each-driven buckets — minimal, for index/key comparison
    ├── 06-outputs.tf          # exposes what was built
    └── break-fix/
        └── broken.tf
```

---

## Recall Check — Demo 10

Answer from memory before reading further:

1. What is the key structural difference between `for_each` on a
   resource block and a `dynamic` block inside a resource?
2. A resource block has both `count = 2` and
   `for_each = toset(["a","b"])`. What happens?
3. Why is `count` the wrong choice for something with a real, stable
   per-instance identity?

<details>
<summary>Answers</summary>

1. `for_each` on a resource creates multiple independent state
   entries — you can destroy one without touching the others. A
   `dynamic` block repeats a nested configuration block *inside a
   single resource* — there's still exactly one resource in state,
   regardless of how many nested blocks it generates.
2. `terraform validate` fails — the two meta-arguments are mutually
   exclusive. Terraform cannot reconcile integer-index addressing with
   key-based addressing on the same resource block at the same time.
3. `count` addresses instances by position, not identity. Removing an
   item from the middle of a `count`-driven list shifts every
   subsequent index, and Terraform plans to destroy and recreate every
   instance after the removed one — even though their actual
   configuration didn't change. This demo makes that trap concrete.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `resource[0]` state address | Addressing syntax | Index-based — position in the `count` list |
| `resource["key"]` state address | Addressing syntax | Key-based — the map key or set value from `for_each` |
| `terraform state list` | CLI command | Lists every resource address currently tracked in state |
| `terraform state show ADDRESS` | CLI command | Shows the full recorded attributes of one specific instance |
| `moved` block | Configuration block | Tells Terraform an address changed, without destroying/recreating the underlying object |
| `count` mid-list-removal trap | Terraform behavior | Removing a middle list item shifts every subsequent index, forcing replacement |

**Related constructs worth knowing (not re-taught in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| `count`, `for_each`, `dynamic` fundamentals | Resource/block multiplicity | Demo 10 |
| Splat expressions | Collecting one attribute across instances | Demo 10 |
| `terraform import` | Bringing an existing, unmanaged resource under Terraform | Not covered in this series yet |

---

### Detailed Explanation of New Constructs

#### State Addressing — `resource[0]` vs. `resource["key"]`, Directly Compared

Every `count`-driven resource instance is addressed by its integer
index; every `for_each`-driven instance is addressed by its map key or
set value. This demo puts both side by side against real, currently
existing resources so the difference is visible in actual `state`
output, not just described.

```bash
terraform state list
```

```
aws_sqs_queue.dlq[0]
aws_sqs_queue.dlq[1]
aws_sqs_queue.dlq[2]
aws_s3_bucket.env["dev"]
aws_s3_bucket.env["staging"]
```

> **The bracket contents are the entire difference.** `dlq[0]` is a
> bare integer — Terraform has no idea what that queue is *for*,
> only that it's "the first one." `env["dev"]` is a string key chosen
> by the map — Terraform (and anyone reading `state list`) can tell
> immediately what that bucket is for, without cross-referencing
> anything else.

```bash
terraform state show 'aws_sqs_queue.dlq[0]'
terraform state show 'aws_s3_bucket.env["dev"]'
```

> **Quoting matters on the command line.** `aws_s3_bucket.env["dev"]`
> contains characters your shell may try to interpret (`[`, `]`, `"`)
> — always wrap the full address in single quotes when passing it to
> `state show`/`state list -id`/etc., or your shell may mangle it
> before Terraform ever sees it.

---

#### The `count` Mid-List-Removal Replacement Trap

Consider a `count`-driven resource whose name is built from a *list*,
indexed by `count.index`:

```hcl
variable "dlq_names" {
  type    = list(string)
  default = ["orders", "payments", "shipping"]
}

resource "aws_sqs_queue" "dlq" {
  count = length(var.dlq_names)
  name  = "cloudnova-${var.dlq_names[count.index]}-dlq"
}
```

This creates three queues: `dlq[0]` = `cloudnova-orders-dlq`, `dlq[1]`
= `cloudnova-payments-dlq`, `dlq[2]` = `cloudnova-shipping-dlq`.

**Now remove `"payments"` from the middle of the list:**

```hcl
variable "dlq_names" {
  type    = list(string)
  default = ["orders", "shipping"]   # "payments" removed
}
```

What Terraform sees is **not** "delete `dlq[1]`, leave `dlq[0]` and
what was `dlq[2]` alone." It sees:

- `dlq[0]`: `var.dlq_names[0]` is still `"orders"` — unchanged
- `dlq[1]`: `var.dlq_names[1]` is now `"shipping"` (it used to be
  `"payments"`) — the **name changes**, which forces replacement
- `dlq[2]`: `var.dlq_names[2]` no longer exists (the list only has 2
  elements now) — this instance is **destroyed**

The queue that should have simply been removed (`payments`) is
"replaced" by relabeling `shipping` into its old slot, and the actual
`shipping` queue is destroyed outright. Nothing about `shipping`'s own
configuration changed — it got caught entirely by its neighbor's
removal, purely because of its position in the list.

> **This is exactly the trap `for_each` avoids.** With `for_each`
> keyed by name instead of position, removing `"payments"` from the
> source map/set would destroy exactly `dlq["payments"]` and leave
> `dlq["orders"]`/`dlq["shipping"]` completely untouched — because
> their addresses were never tied to position in the first place.

---

#### The `moved` Block — Migrating Without Destroy/Recreate

A `moved` block tells Terraform "the object at this old address is
the same object as this new address" — so instead of planning a
destroy (old address gone) + create (new address appears), Terraform
just updates its own bookkeeping.

```hcl
moved {
  from = aws_sqs_queue.dlq[0]
  to   = aws_sqs_queue.dlq["orders"]
}
moved {
  from = aws_sqs_queue.dlq[1]
  to   = aws_sqs_queue.dlq["payments"]
}
moved {
  from = aws_sqs_queue.dlq[2]
  to   = aws_sqs_queue.dlq["shipping"]
}
```

Paired with actually changing the resource block itself from `count`
to `for_each`, this tells Terraform: "the queue that used to be
`dlq[0]` is now addressed as `dlq["orders"]` — same real SQS queue,
just a new address." `terraform plan` should show **zero** changes to
the underlying queues — no destroy, no create, no modify — only
Terraform's internal state bookkeeping updates.

> **`moved` blocks are typically temporary.** Once everyone who might
> apply this configuration has done so at least once (so their local
> state reflects the new addresses), the `moved` blocks can usually be
> removed — they exist to smooth the transition, not to remain forever.

---

#### `terraform state list` — Index/Key Filtering

```bash
# All instances of one resource
terraform state list | grep 'aws_sqs_queue\.dlq'

# One specific indexed instance
terraform state list | grep 'aws_sqs_queue\.dlq\[0\]'

# One specific keyed instance
terraform state list | grep 'aws_s3_bucket\.env\["dev"\]'
```

> **`grep` here is filtering CLI text output, not a Terraform
> feature.** `terraform state list` always prints every address; the
> "filtering" is standard shell text processing on top of that full
> list — worth knowing the distinction if you ever script against this
> output.

---

## Lab Step-by-Step Guide

---

## Part A — State Addressing Mechanics

**What you accomplish in Part A:** rebuild a small, self-contained set
of `count`- and `for_each`-driven resources, then compare their state
addresses directly using `terraform state list`/`state show`.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/11-state-addressing-migration/src
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

#### `03-variables.tf` — Inputs for both Parts

**What this file does in this demo:** `dlq_names` drives Part B's
reordering trap directly; `environments` is a minimal `for_each`
comparison point, not a full rebuild of Demo 10's bucket scenario.

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

variable "dlq_names" {
  type        = list(string)
  description = "Names for the count-driven dead-letter queues — order matters, this is the point"
  default     = ["orders", "payments", "shipping"]
}

variable "environments" {
  type        = map(string)
  description = "Minimal for_each comparison point — not a full Demo 10 rebuild"
  default = {
    dev     = "us-east-2"
    staging = "us-east-2"
  }
}
```

---

#### `04-count-queues.tf` — count-driven, name-list-indexed queues

**What this file does in this demo:** this is the resource Part B's
reordering trap and Part C's migration both operate on. Naming each
queue from `var.dlq_names[count.index]` (rather than just
`"dlq-${count.index}"`, as Demo 10 did) is what makes the trap visible
— the name itself now depends on list position, not just the index
number.

**04-count-queues.tf:**

```hcl
resource "aws_sqs_queue" "dlq" {
  count = length(var.dlq_names)
  name  = "cloudnova-${var.dlq_names[count.index]}-dlq"

  tags = {
    ManagedBy = "terraform-demo-11"
  }
}
```

---

#### `05-foreach-buckets.tf` — for_each-driven buckets, for comparison

**What this file does in this demo:** exists purely so Part A has a
real `for_each`-keyed resource to compare against `04-count-queues.tf`'s
index-addressed one — this file is not itself the subject of the
reordering trap or the migration in Parts B/C.

**05-foreach-buckets.tf:**

```hcl
resource "aws_s3_bucket" "env" {
  for_each = var.environments
  bucket   = "cloudnova-demo11-${each.key}"

  tags = {
    Environment = each.key
    ManagedBy   = "terraform-demo-11"
  }
}
```

---

### Step 3 — Apply and compare addressing directly

```bash
terraform init
terraform validate
terraform apply
```

```bash
terraform state list
```

Expected:

```
aws_s3_bucket.env["dev"]
aws_s3_bucket.env["staging"]
aws_sqs_queue.dlq[0]
aws_sqs_queue.dlq[1]
aws_sqs_queue.dlq[2]
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

```bash
terraform state show 'aws_sqs_queue.dlq[1]'
```

Expected (abbreviated): shows `name = "cloudnova-payments-dlq"` among
the recorded attributes — confirming index `1` currently corresponds
to the `payments` queue.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

**Verify:**

```
Console → SQS → Queues → cloudnova-payments-dlq
  → confirm this queue exists and matches state's dlq[1] ✅
Console → S3 → Buckets → cloudnova-demo11-dev, cloudnova-demo11-staging
  → confirm both exist, matching env["dev"]/env["staging"] ✅
```

---

## Part B — The count Reordering Trap, Live

**What you accomplish in Part B:** remove `"payments"` from the middle
of `dlq_names`, then read the resulting plan carefully to understand
exactly what Terraform proposes — and why.

### Step 1 — Remove the middle item

Update `03-variables.tf`'s default:

```hcl
variable "dlq_names" {
  type        = list(string)
  description = "Names for the count-driven dead-letter queues — order matters, this is the point"
  default     = ["orders", "shipping"]   # "payments" removed
}
```

### Step 2 — Plan, and read the destructive result carefully

```bash
terraform plan
```

Expected:

```
  # aws_sqs_queue.dlq[1] must be replaced
-/+ resource "aws_sqs_queue" "dlq" {
      ~ name = "cloudnova-payments-dlq" -> "cloudnova-shipping-dlq" # forces replacement
      # ...
    }

  # aws_sqs_queue.dlq[2] will be destroyed
  - resource "aws_sqs_queue" "dlq" {
      - name = "cloudnova-shipping-dlq" -> null
      # ...
    }

Plan: 1 to add, 0 to change, 2 to destroy.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **Read this plan slowly — it's not what most people expect.**
> `dlq[1]` isn't destroyed and left gone; it's **replaced**, taking on
> `shipping`'s name. The *actual* `shipping` queue (`dlq[2]`) is
> destroyed outright. If `payments` had real messages in flight or
> downstream consumers configured against its ARN, this plan would
> silently break them — the queue "renamed" into `dlq[1]`'s slot has a
> brand-new ARN, since it's a genuinely new AWS resource, not the old
> `shipping` queue renamed in place.

**Do not `apply` this plan** — Part C will fix the underlying cause
instead of accepting this destructive outcome.

### Step 3 — Restore the original list before continuing

```hcl
variable "dlq_names" {
  type        = list(string)
  description = "Names for the count-driven dead-letter queues — order matters, this is the point"
  default     = ["orders", "payments", "shipping"]
}
```

```bash
terraform plan
```

Expected: `No changes.` — confirms all three original queues are still
intact, since Step 2's destructive plan was never applied.

---

## Part C — Migrating count to for_each Without Destroy/Recreate

**What you accomplish in Part C:** convert `04-count-queues.tf` from
`count` to `for_each`, add `moved` blocks mapping every old index
address to its new key address, and confirm the migration itself
produces zero destroys.

### Step 1 — Change the resource from count to for_each

Update `04-count-queues.tf`'s resource block itself (not a new file —
this edits the existing resource in place):

```hcl
resource "aws_sqs_queue" "dlq" {
  for_each = toset(var.dlq_names)
  name     = "cloudnova-${each.key}-dlq"

  tags = {
    ManagedBy = "terraform-demo-11"
  }
}
```

### Step 2 — Add moved blocks mapping every old index to its new key

Add to `04-count-queues.tf`, alongside the resource block:

```hcl
moved {
  from = aws_sqs_queue.dlq[0]
  to   = aws_sqs_queue.dlq["orders"]
}
moved {
  from = aws_sqs_queue.dlq[1]
  to   = aws_sqs_queue.dlq["payments"]
}
moved {
  from = aws_sqs_queue.dlq[2]
  to   = aws_sqs_queue.dlq["shipping"]
}
```

> **The index-to-name mapping here must match what Part A actually
> had.** `dlq[0]` was `orders`, `dlq[1]` was `payments`, `dlq[2]` was
> `shipping` — confirmed directly back in Part A's `terraform state
> show 'aws_sqs_queue.dlq[1]'` output. Getting this mapping wrong
> would tell Terraform the wrong old-to-new correspondence, and it
> would fall back to destroy + create for whichever instance was
> mismapped.

### Step 3 — Plan and confirm zero destroys

```bash
terraform plan
```

Expected:

```
Terraform will perform the following actions:

  # aws_sqs_queue.dlq[0] has moved to aws_sqs_queue.dlq["orders"]
    resource "aws_sqs_queue" "dlq" {
        name = "cloudnova-orders-dlq"
    }
  # aws_sqs_queue.dlq[1] has moved to aws_sqs_queue.dlq["payments"]
    resource "aws_sqs_queue" "dlq" {
        name = "cloudnova-payments-dlq"
    }
  # aws_sqs_queue.dlq[2] has moved to aws_sqs_queue.dlq["shipping"]
    resource "aws_sqs_queue" "dlq" {
        name = "cloudnova-shipping-dlq"
    }

Plan: 0 to add, 0 to change, 0 to destroy.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **`Plan: 0 to add, 0 to change, 0 to destroy` is the entire point of
> this Part.** Compare this directly against Part B Step 2's `1 to
> add, 0 to change, 2 to destroy` for the *same underlying change in
> intent* (removing positional dependence) — the difference is
> entirely due to the `moved` blocks telling Terraform these are the
> same real objects, just re-addressed.

```bash
terraform apply
```

### Step 4 — Confirm with state list and index/key filtering

```bash
terraform state list | grep 'aws_sqs_queue\.dlq'
```

Expected:

```
aws_sqs_queue.dlq["orders"]
aws_sqs_queue.dlq["payments"]
aws_sqs_queue.dlq["shipping"]
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **No more `dlq[0]`/`dlq[1]`/`dlq[2]` anywhere in state.** The
> migration is complete — every queue is now addressed by name, and
> removing `payments` from `var.dlq_names` (as a set, via `toset()`)
> would from this point forward destroy exactly `dlq["payments"]` and
> nothing else.

**Verify:**

```
Console → SQS → Queues → cloudnova-orders-dlq, cloudnova-payments-dlq,
  cloudnova-shipping-dlq
  → all three still exist, same ARNs as before the migration ✅
```

---

## Cleanup

```bash
terraform destroy
```

Type `yes`. Expected: `Destroy complete! Resources: 5 destroyed.` (3
queues, 2 buckets).

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

```bash
aws sqs list-queues --queue-name-prefix cloudnova --profile default --region us-east-2
aws s3 ls --profile default --region us-east-2 | grep cloudnova-demo11
```

Expected: both commands return empty results.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## What You Learned

1. ✅ `resource[0]` (index) and `resource["key"]` (key) are visibly
   different in `terraform state list`/`state show` — the bracket
   contents carry all the meaning
2. ✅ Removing a middle item from a `count`-driven, list-indexed
   resource forces replacement of every subsequent instance, because
   `count.index` addressing is purely positional
3. ✅ A `moved` block tells Terraform an object's address changed
   without destroying/recreating it — confirmed by `Plan: 0 to add, 0
   to change, 0 to destroy` after migrating `count` to `for_each`
4. ✅ `terraform state list` always prints every address; index/key
   "filtering" is standard shell `grep`, not a separate Terraform feature

---

## Cert Tips — TA-004 Objectives Covered

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `resource[0]` vs `resource["key"]` | TA-004 Obj (state management) | Frequently tested — know which addressing syntax goes with `count` vs `for_each` |
| `count` mid-list-removal replacement | TA-004 Obj (state management) | Common trap — expects recognition of the cascading replacement, not just "one item is removed" |
| `moved` block | TA-004 Obj (state management) | Tests whether you know this avoids destroy/recreate during a refactor |
| `terraform state list` | TA-004 Obj (state management) | Know this always lists everything; filtering is a shell operation on top |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam shows a name removed from the middle of a `count`-driven list | Recognizing this forces replacement of every subsequent index, not just the removed one | Assuming only the specific removed name's queue is affected |
| Exam asks what a `moved` block accomplishes | Recognizing it avoids destroy/recreate by telling Terraform an object's address changed | Assuming `moved` performs some data migration on the resource itself |
| Exam asks how to see only `for_each`-driven instances of a resource in `state list` | Recognizing this requires piping to `grep`/similar — Terraform's own output always lists everything | Assuming `terraform state list` has a built-in filter flag for this |

### Exam Task — Write a complete configuration

**Task:** CloudNova has three `count`-driven CloudWatch log groups
named from a list variable `service_names` (`["auth", "billing",
"notifications"]`). Migrate this resource from `count` to `for_each`
using `moved` blocks, preserving the existing log groups without
destroy/recreate.

**Block types required:** `resource` (the migrated log group block),
`moved` (×3)

**Official documentation:**
- [Refactoring — `moved` Blocks](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring)

**What to practise:**
1. Open the `moved` block documentation — confirm the exact `from`/`to`
   argument syntax
2. Write the migrated resource block and all three `moved` blocks from
   scratch, without looking at this demo's `04-count-queues.tf`
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
variable "service_names" {
  type    = list(string)
  default = ["auth", "billing", "notifications"]
}

resource "aws_cloudwatch_log_group" "app" {
  for_each = toset(var.service_names)
  name     = "/cloudnova/${each.key}"
}

moved {
  from = aws_cloudwatch_log_group.app[0]
  to   = aws_cloudwatch_log_group.app["auth"]
}
moved {
  from = aws_cloudwatch_log_group.app[1]
  to   = aws_cloudwatch_log_group.app["billing"]
}
moved {
  from = aws_cloudwatch_log_group.app[2]
  to   = aws_cloudwatch_log_group.app["notifications"]
}
```

**Arguments you must know without looking up:**
- `moved` block syntax: `from = OLD_ADDRESS`, `to = NEW_ADDRESS` — no
  quotes around the addresses themselves, since they're resource
  references, not strings
- The old-to-new index-to-key mapping must match the actual current
  state exactly, or Terraform falls back to destroy + create for the
  mismapped instance

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `terraform plan` still shows destroy/create after adding `moved` blocks | The `from` address doesn't match what's actually in state (wrong index-to-key mapping) | Run `terraform state list` first to confirm the exact current addresses before writing `moved` blocks |
| Shell mangles a `state show`/`state list` command targeting a `for_each` address | Unquoted `["key"]` interpreted by the shell | Always wrap the full resource address in single quotes: `'aws_s3_bucket.env["dev"]'` |
| Removing a list item still triggers cascading replacement even after "fixing" the list | The resource is still `count`-driven — only migrating to `for_each` (Part C) actually resolves this, not just being more careful with the list | Confirm the resource block itself uses `for_each`, not `count`, before expecting position-independent removal |

---

## Break-Fix Scenario

Three deliberate errors, all state-addressing/migration-specific.
Diagnose using `terraform validate`/`plan` — do not look at answers
first.

```bash
cd src/break-fix/
terraform init
terraform validate
terraform plan
```

#### `broken.tf` — Three deliberate state-addressing errors

**What this file does in this demo:** a self-contained configuration
with a `moved` block pointing to the wrong old index, a `for_each`
resource still referenced with bracket-index syntax in an output, and
a `moved` block whose `to` address doesn't match the resource's actual
current configuration — diagnose all three.

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

variable "dlq_names" {
  type    = list(string)
  default = ["orders", "payments", "shipping"]
}

resource "aws_sqs_queue" "dlq" {
  for_each = toset(var.dlq_names)
  name     = "cloudnova-${each.key}-dlq"
}

# Error 1: wrong old index mapped to "payments" (should be index 1, not 2)
moved {
  from = aws_sqs_queue.dlq[2]
  to   = aws_sqs_queue.dlq["payments"]
}
moved {
  from = aws_sqs_queue.dlq[0]
  to   = aws_sqs_queue.dlq["orders"]
}
moved {
  from = aws_sqs_queue.dlq[1]
  to   = aws_sqs_queue.dlq["shipping"]
}

# Error 2: bracket-index reference to a resource that is now for_each-driven
output "first_queue_arn" {
  value = aws_sqs_queue.dlq[0].arn
}

# Error 3: moved block references a resource address that was never
# for_each — this key never existed under count in the first place
moved {
  from = aws_sqs_queue.dlq[5]
  to   = aws_sqs_queue.dlq["archive"]
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — wrong old index mapped to the wrong new key**
The actual Part A state had `dlq[1]` = `payments`, not `dlq[2]`. If
this mismapping is applied against real existing state, Terraform
would treat the *actual* `dlq[1]` (payments) as having no `moved`
block matching it at all, and `dlq[2]` (shipping) as if it were meant
to become `payments` — producing destroy/create for whichever
instances don't actually correspond. Fix: confirm the real mapping via
`terraform state list`/`state show` before writing any `moved` block,
never assume or guess it.

**Error 2 — bracket-index reference on a now-`for_each` resource**
`aws_sqs_queue.dlq[0]` was valid when the resource used `count`; now
that it's `for_each`, valid addresses are `dlq["orders"]`,
`dlq["payments"]`, `dlq["shipping"]` — `dlq[0]` no longer refers to
anything. Terraform errors that the given key doesn't identify an
instance. Fix: update the reference to the correct key,
`aws_sqs_queue.dlq["orders"].arn`.

**Error 3 — `moved` block referencing an index that was never real**
`dlq[5]` never existed — Part A only ever had `dlq[0]` through
`dlq[2]`. A `moved` block for a `from` address that was never a real
prior instance is simply inert — it doesn't error, but it also does
nothing useful, and its presence is misleading to anyone reading the
config later, suggesting a migration step happened that never
actually applied to anything. Fix: remove `moved` blocks for addresses
that were never genuinely present in prior state.

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

**Q1. A teammate removes an item from the middle of a `count`-driven list and is confused why `terraform plan` proposes replacing resources they didn't touch. What's your explanation?**
`count` addresses instances purely by position — `count.index` has no concept of what a given instance represents, only where it sits in the list. When an item is removed from the middle, every subsequent index shifts down by one, and Terraform sees each shifted index as "this instance's configuration changed" (since the name/attributes derived from that index now reflect a different list entry) — which for most arguments (like `name`) forces a destroy+create rather than an in-place update. The fix isn't to be more careful about list order; it's to migrate the resource to `for_each`, which addresses instances by a stable key instead of position.

**Q2. What does a `moved` block actually do — does it change anything about the real AWS resource?**
No — a `moved` block only updates Terraform's own internal bookkeeping about which configuration address corresponds to which tracked object in state. It tells Terraform "the object previously known as X is the same real-world object as Y" so that a refactor (like changing `count` to `for_each`) doesn't get misread as "X was deleted and Y was newly created." The underlying AWS resource is completely untouched — same ARN, same creation date, same everything — only Terraform's record of its address changes.

**Q3. How would you verify, before running `apply`, that a migration involving `moved` blocks won't accidentally destroy anything?**
Run `terraform plan` and check the summary line — specifically that it shows `0 to add, 0 to change, 0 to destroy` (or only genuinely intended changes, with no destroys tied to the migration itself). The plan output for a correctly-configured `moved` block shows a `has moved to` message for each affected instance, not a destroy/create pair — if you see any destroy/create activity on resources you expected to just get new addresses, that's the signal something in the `from`/`to` mapping doesn't match reality, and it's worth re-checking against `terraform state list`'s actual current addresses before proceeding.

---

## Key Takeaways

1. **The bracket contents in a state address carry all the meaning.**
   `resource[0]` tells you nothing about what that instance represents;
   `resource["key"]` does, by construction.

2. **Removing a middle item from a `count`-driven, list-indexed
   resource cascades.** Every instance after the removed one shifts
   index, and Terraform reads that shift as a configuration change,
   forcing replacement — not just for the removed item.

3. **A `moved` block changes Terraform's bookkeeping, not the real
   resource.** Same ARN, same creation date — only the tracked address
   changes, which is exactly why it avoids destroy/recreate.

4. **A correct migration plan shows zero destroys.** `Plan: 0 to add,
   0 to change, 0 to destroy` (with `has moved to` messages) is the
   confirmation a `count`-to-`for_each` migration was mapped correctly.

5. **`terraform state list` always lists everything.** Any
   index/key-specific "filtering" you see in practice is shell `grep`
   applied afterward, not a Terraform feature.

> **Demo scope:** Primary concept: state addressing mechanics for
> `count`- and `for_each`-driven resources, and migrating between them
> without destroy/recreate. Supporting concepts: the mid-list-removal
> replacement trap (reproduced live), the `moved` block, and
> `terraform state list`/`state show` as the tools for confirming
> exactly what's tracked and how.
> Estimated completion time: 35 minutes (reading + hands-on + verification).
> Checkpoints: 3 natural stopping points (end of Part A, end of Part B,
> end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform state list` | Lists every resource address currently tracked in state |
| `terraform state show 'ADDRESS'` | Shows the full recorded attributes of one specific instance — quote addresses containing brackets |
| `terraform state list \| grep PATTERN` | Filters the full address list via shell `grep` — not a separate Terraform feature |
| `moved { from = X, to = Y }` | Tells Terraform an object's address changed, without destroy/recreate |
| `terraform plan` (post-migration) | Should show `0 to add, 0 to change, 0 to destroy` with `has moved to` messages if the migration is correct |

---

## Next Demo

**Demo 12 — The `lifecycle` Meta-Argument:** `create_before_destroy`,
`prevent_destroy`, `ignore_changes`, and `replace_triggered_by` — the
last topic in Phase 1 - Foundations before Phase 2 moves into modules.

---

## Appendix — Anki Cards

**11-state-addressing-migration-anki.csv:**

````
#deck:Terraform AWS Mastery::Phase 1 - Foundations::11-state-addressing-migration
#separator:Comma
#columns:Front,Back,Tags
"What is the structural difference between a resource[0] address and a resource['key'] address in terraform state list?","resource[0] is an integer index — purely positional, carries no meaning about what the instance represents. resource['key'] is a string key from for_each — carries real identity, visible directly in state output without cross-referencing anything else.","demo11,state-addressing,ta004"
"A count-driven resource is named from a list, indexed by count.index. The middle item is removed from the list. What does terraform plan propose?","Not just removing the middle item — every index after it shifts down by one, and each shifted index's changed name forces replacement. The last instance in the original list is destroyed outright, and the middle-removed item's slot is effectively taken over by relabeling the next instance into it.","demo11,count,replacement-trap,ta004"
"What does a moved block actually change — the real AWS resource, or something else?","Only Terraform's own state bookkeeping. It tells Terraform 'the object at this old address is the same real object as this new address' so a refactor isn't misread as destroy+create. The underlying AWS resource (same ARN, same creation date) is completely untouched.","demo11,moved-block,ta004"
"After migrating a resource from count to for_each with moved blocks, what does a correct terraform plan show?","Plan: 0 to add, 0 to change, 0 to destroy — with 'has moved to' messages for each migrated instance. Any destroy/create activity signals the from/to mapping in a moved block doesn't match the resource's actual prior state.","demo11,moved-block,verification"
"Does terraform state list have a built-in way to show only for_each-driven instances of one resource?","No — terraform state list always prints every tracked address. Any index/key-specific filtering seen in practice (e.g. piping to grep) is standard shell text processing applied afterward, not a Terraform feature.","demo11,state-list,ta004"
"Why must a resource address containing for_each's bracket syntax be quoted on the command line, e.g. terraform state show 'aws_s3_bucket.env[\"dev\"]'?","Because the shell would otherwise try to interpret the brackets and quotation marks itself before Terraform ever receives the argument — wrapping the whole address in single quotes passes it through to Terraform intact.","demo11,state-addressing,cli"
"A moved block's from address references an index that never actually existed in prior state (e.g. dlq[5] when only dlq[0]-dlq[2] ever existed). What happens?","Nothing harmful — it's simply inert. Terraform finds no matching prior object at that address, so the moved block has no effect. It doesn't error, but its presence is misleading to future readers, suggesting a migration step that never actually applied to anything real.","demo11,moved-block,break-fix"
"A resource migrated from count to for_each is still referenced elsewhere in the config using bracket-index syntax, e.g. aws_sqs_queue.dlq[0].arn. What happens?","An error — dlq[0] is no longer a valid address once the resource is for_each-driven; valid addresses are now string keys like dlq[\"orders\"]. Every reference to the resource elsewhere in the configuration must be updated to match the new addressing scheme.","demo11,for_each,break-fix"
"Why is 'be more careful about list order' not a real fix for the count mid-list-removal trap?","Because the trap is inherent to positional addressing itself, not a mistake in how the list happens to be ordered on any given day — any future removal from any position other than the very end will reproduce the same cascading replacement. The actual fix is migrating the resource to for_each, which removes position from the addressing scheme entirely.","demo11,count,replacement-trap,decision"
"What are the exact two arguments a moved block requires, and are they quoted?","from and to — both are resource address references, not string literals, so neither is quoted. e.g. moved { from = aws_sqs_queue.dlq[0], to = aws_sqs_queue.dlq[\"orders\"] }.","demo11,moved-block,syntax"
"What does terraform state show 'aws_sqs_queue.dlq[1]' return, compared to terraform state list?","state show returns one instance's full recorded attributes (name, arn, tags, every exported value) — state list only returns the bare address strings for every tracked resource, with no attribute detail at all.","demo11,state-list,state-show,ta004"
"Do count-driven and for_each-driven addresses require the same quoting on the command line?","No — count[0] (bare integer, no double quotes) typically survives unquoted in most shells, though quoting is still good practice. for_each[\"key\"] (containing literal double quotes) almost always needs the whole address wrapped in single quotes, or the shell will mangle it.","demo11,state-addressing,cli"
"After migrating dlq from count to for_each, is dlq[0] still a valid way to reference the first queue?","No. Once a resource is for_each-driven, every count-style bracket-index address becomes permanently invalid — valid addresses are now the map keys (e.g. dlq[\"orders\"]), regardless of what index that same queue used to occupy under count.","demo11,for_each,state-addressing"
"Are moved blocks meant to stay in a configuration permanently?","Typically no — they exist to smooth a one-time transition. Once everyone who applies the configuration has done so at least once (so their local state reflects the new addresses), the moved blocks are usually safe to remove.","demo11,moved-block,best-practice"
"What AWS CLI commands confirm a specific, indexed SQS queue instance actually round-trips a real message, rather than just existing?","aws sqs get-queue-url --queue-name NAME to resolve the URL, then aws sqs send-message --queue-url URL --message-body TEXT, then aws sqs receive-message --queue-url URL to confirm the exact message comes back from that specific queue.","demo11,sqs,verification,commands"
"In this demo's mid-list-removal scenario, which specific queue gets destroyed outright, and which gets replaced under a new name?","Removing the middle item ('payments') from a 3-item list: dlq[2] (originally 'shipping') is destroyed outright, since index 2 no longer has any corresponding list entry. dlq[1] (originally 'payments') is replaced — its name changes to 'shipping', since var.dlq_names[1] now points to what used to be at index 2.","demo11,count,replacement-trap,mechanics"
````

---

## Appendix — Quiz

**11-state-addressing-migration-quiz.md:**

````markdown
# Quiz — Demo 11: State Addressing and Multiplicity Migration

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 12.

---

**Q1. (Multiple Choice)** A `count`-driven resource has 3 instances.
Which state address correctly refers to the second one?

- A) `resource_type.name[2]`
- B) `resource_type.name[1]`
- C) `resource_type.name["1"]`
- D) `resource_type.name.1`

<details>
<summary>Answer</summary>

**B.** `count` addressing is zero-based — the second instance is
index `1`, not `2`. **A** is the classic off-by-one error, treating it
as one-based. **C** uses `for_each`-style string-key syntax, invalid
for a `count` resource. **D** isn't valid Terraform address syntax at
all.

</details>

---

**Q2. (True/False)** Removing an item from the exact END of a
`count`-driven, list-indexed resource's source list produces the same
cascading replacement as removing an item from the middle.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Removing the last item only destroys that one instance
— no other index shifts, since nothing after it exists to shift into
its place. The cascading replacement trap is specifically about
removing from the middle (or anywhere other than the very end), where
subsequent indices do shift.

</details>

---

**Q3. (Multiple Choice)** What does a `moved` block change about the
underlying AWS resource?

- A) Its ARN
- B) Its tags, to reflect the new address
- C) Nothing — only Terraform's own state bookkeeping changes
- D) Its creation timestamp, to mark the migration

<details>
<summary>Answer</summary>

**C.** A `moved` block only tells Terraform two addresses refer to the
same real object — the AWS resource itself (ARN, tags, creation date,
everything) is completely untouched. **A**, **B**, and **D** are all
wrong — none of these ever change as a result of a `moved` block.

</details>

---

**Q4. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about `terraform state list` are correct?

- A) It supports a `--filter` flag to show only `for_each` instances
- B) It always prints every tracked address, with no built-in filtering
- C) Piping its output to `grep` is standard shell processing, not a Terraform feature
- D) It requires resource addresses to be quoted as arguments
- E) It shows full attribute detail for each instance, like `state show` does

<details>
<summary>Answer</summary>

**B and C.** `state list` always prints everything; narrowing it to a
pattern is plain shell `grep` on top, not anything Terraform provides.
**A** is wrong — no such flag exists. **D** is wrong — `state list`
takes no address argument at all; quoting only matters for commands
like `state show` that target one specific address. **E** is wrong —
that's what `state show` does; `state list` only prints bare address
strings.

</details>

---

**Q5. (Multiple Choice)** Why must `terraform state show
'aws_s3_bucket.env["dev"]'` be wrapped in single quotes on the command
line?

- A) Terraform requires quotes on every address, with no exceptions
- B) The shell would otherwise interpret the brackets/quotes itself before Terraform receives the argument
- C) Quoting encrypts the address for the current session
- D) Only `for_each` resources exist in state; quoting marks this distinction

<details>
<summary>Answer</summary>

**B.** The shell's own special-character handling can mangle an
unquoted address containing `[`, `]`, and `"` — wrapping it in single
quotes passes it through intact. **A** is wrong — simple `count`
addresses like `dlq[0]` (no embedded double quotes) often survive
unquoted, though quoting is still good practice. **C** is wrong —
quoting has nothing to do with security. **D** is wrong — quoting
isn't a marker of resource type.

</details>

---

**Q6. (Multiple Choice)** After adding correctly-mapped `moved` blocks
for a `count`-to-`for_each` migration, what should `terraform plan`
report?

- A) `Plan: 3 to add, 0 to change, 3 to destroy`
- B) `Plan: 0 to add, 0 to change, 0 to destroy`, with "has moved to" messages
- C) `Plan: 0 to add, 3 to change, 0 to destroy`
- D) An error, since `count`-to-`for_each` migrations always require manual state surgery

<details>
<summary>Answer</summary>

**B.** Zero destroys, zero adds — only address bookkeeping changes,
shown as "has moved to" messages. **A** would mean the `moved` blocks
aren't working at all. **C** is wrong — nothing about the resources'
actual configuration changed, only their addresses. **D** is wrong —
`moved` blocks exist specifically to avoid manual state surgery.

</details>

---

**Q7. (Multiple Choice)** A `moved` block's `from` address references
an index that never existed in prior state (e.g. `dlq[5]` when only
`dlq[0]`–`dlq[2]` ever existed). What happens?

- A) `terraform plan` errors immediately
- B) Terraform fabricates a placeholder instance to satisfy the block
- C) The block is inert — no matching prior object exists, so it has no effect
- D) Every other `moved` block in the same file is invalidated

<details>
<summary>Answer</summary>

**C.** A `moved` block referencing a never-real address simply does
nothing — not harmful, but misleading to future readers. **A** is
wrong — this doesn't error. **B** is wrong — Terraform never fabricates
instances to satisfy a `moved` block. **D** is wrong — each `moved`
block is independent.

</details>

---

**Q8. (True/False)** Once a resource has been migrated from `count` to
`for_each`, its old bracket-index addresses (e.g. `dlq[0]`) remain
valid as a secondary way to reference the same instance.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Once a resource is `for_each`-driven, `count`-style
bracket-index addresses are permanently invalid — every reference
elsewhere in the configuration (outputs, other resources) must be
updated to the new string-key addresses, or it errors.

</details>

---

**Q9. (Multiple Choice)** CloudNova needs to remove one queue from the
middle of a 3-item, `count`-driven, list-indexed set of queues, without
triggering replacement of the other queues. What should they do first?

- A) Reorder the list so the item to remove is last, then remove it
- B) Migrate the resource to `for_each`, keyed by name, before removing anything
- C) Add a `moved` block pointing the removed item to itself
- D) Increase `count` temporarily, then decrease it after removal

<details>
<summary>Answer</summary>

**B.** Migrating to `for_each` removes position from the addressing
scheme entirely — after that, removing one named entry only affects
that one instance. **A** technically avoids the cascade for *this one*
removal, but doesn't fix the underlying problem — the very next
non-last removal reproduces it. **C** and **D** don't address the root
cause at all.

</details>

---

**Q10. (Multiple Answer — Pick the 2 correct responses)** Which TWO of
the following are true about the relationship between `moved` blocks
and the real AWS resources they reference?

- A) `moved` blocks are typically temporary and can usually be removed after everyone has applied the migration once
- B) `moved` blocks must remain in the configuration permanently once added
- C) A `moved` block never triggers any AWS API call — it only affects Terraform's own state file
- D) A `moved` block causes AWS to rename the underlying resource
- E) `moved` blocks can be safely written before confirming the actual prior addresses via `state list`/`state show`

<details>
<summary>Answer</summary>

**A and C.** `moved` blocks smooth a one-time transition and are
usually removable afterward; they never touch AWS itself, only
Terraform's bookkeeping. **B** is wrong — permanence isn't required.
**D** is wrong — AWS resources have no concept of a Terraform address
at all; nothing about them changes. **E** is wrong — guessing the
mapping instead of confirming it against real state risks exactly the
kind of destroy/create Break-Fix Error 1 demonstrates.

</details>

---

**Q11. (Multiple Choice)** What is the most reliable way to confirm a
specific, indexed SQS queue instance (not just "one of three queues
exists") is genuinely functional?

- A) Check that `terraform apply` completed without error
- B) Resolve its exact queue URL, then send and receive a real message from that specific queue
- C) Confirm the queue's ARN appears in `terraform state list`
- D) Check the AWS Console's queue count matches `count`'s value

<details>
<summary>Answer</summary>

**B.** A real send/receive round trip against the resolved queue URL
is the only one of these that verifies actual functionality, not just
existence. **A**, **C**, and **D** all confirm the resource *exists*
in some form, but none of them confirm it can actually send and
receive a message.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 10-11/11 | Import Anki cards, move to Demo 12 |
| 8-9/11 | Review the wrong answers, then proceed |
| 6-7/11 | Re-read the relevant sections, retry those questions |
| Below 6/11 | Re-read the full demo and redo the walkthrough before proceeding |
````