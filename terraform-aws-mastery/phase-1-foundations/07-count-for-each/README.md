# Demo 07: Count, For-Each, and the Multiplicity Decision

## Overview

CloudNova has been writing one `resource` block per S3 bucket, per SQS queue, per IAM user — and it's starting to hurt. The platform team just asked for three near-identical dead-letter queues and three near-identical S3 buckets (dev/staging/prod), and copy-pasting six resource blocks with only the name changed is exactly the kind of repetition Terraform is supposed to eliminate.

This demo covers the two mechanisms Terraform provides for creating multiple instances of a resource from a single block — `count` and `for_each` — plus the expression type you need to read data back out of them (splat expressions), and the decision framework for choosing between them.

- `count` — index-based multiplicity (`count.index`, `resource[0]`)
- `for_each` — key-based multiplicity over a map or set (`each.key`, `each.value`, `resource["key"]`)
- Converting a list to a set with `toset()` so `for_each` can consume it
- Splat expressions (`[*]`) for collecting one attribute across every instance
- Why `count` and `for_each` cannot be used on the same resource block
- When to reach for `count`, when to reach for `for_each`, and when to just write a single resource

**What this demo does NOT cover:** how state addressing changes when you reorder a `count` list or migrate a resource from `count` to `for_each`, and the specific "removing item 2 of 5" replacement trap. That's a state-mechanics topic in its own right — full coverage is in Demo 08 (State Addressing and Multiplicity Migration).

---

## Prerequisites

**Knowledge:** This demo assumes Demo 06 (Data Sources and Expressions) — specifically `for` expressions, `toset()`/`keys()`/`values()`, and `dynamic` blocks. If `dynamic` blocks and `for_each` on a *resource* sound like the same thing, that's addressed directly in Concepts below — they are not.

**Required Tools:**

| Tool | Min version | Install | Verify |
|---|---|---|---|
| Terraform | `>= 1.9.0` | Same as Demo 00 — [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install) | `terraform version` |
| AWS CLI | `>= 2.15` | Same as Demo 01 | `aws --version` |
| AWS credentials configured | — | Same profile used since Demo 01 | `aws sts get-caller-identity` |

**IAM permissions required for this demo:**
```
sqs:CreateQueue
sqs:DeleteQueue
sqs:GetQueueAttributes
sqs:ListQueues
s3:CreateBucket
s3:DeleteBucket
s3:PutBucketTagging
s3:ListBucket
iam:CreateUser
iam:DeleteUser
iam:GetUser
```
Console verify: IAM → Users → confirm your user/role has these actions (or `AdministratorAccess` in a sandbox account, consistent with Demos 00–06).
CLI verify: `aws sts get-caller-identity` (confirms which identity you're using before running `apply`).

---

## Demo Objectives

1. ✅ Create three or more identical resource instances using `count` and reference each one via `count.index`
2. ✅ Create resource instances keyed by name using `for_each` over a map, and reference `each.key`/`each.value`
3. ✅ Convert a list variable to a set with `toset()` to satisfy `for_each`'s type requirement
4. ✅ Collect one attribute across every instance of a `count` or `for_each` resource using a splat expression (`[*]`)
5. ✅ Correctly address individual resource instances in CLI output and code (`resource[0]` vs `resource["key"]`)
6. ✅ Apply CloudNova's decision framework to choose `count`, `for_each`, or a single resource for a given scenario
7. ✅ Diagnose and fix the three most common `count`/`for_each` authoring errors from Terraform's own error output
8. ✅ Explain why Terraform rejects `count` and `for_each` on the same resource block, and what to do instead

---

## Cost & Free Tier

| Resource | Free tier status | Notes |
|---|---|---|
| SQS queues (3x, standard) | Free forever — 1M requests/month | Well under free tier for a lab |
| S3 buckets (3x, empty) | Free forever for the buckets themselves; storage billed per GB after 5GB/12mo | No objects uploaded in this demo — negligible |
| IAM users (2x) | Always free | IAM has no usage-based cost |

**Total expected cost for this demo: $0.00**, provided Cleanup is run at the end of the session (bucket/queue/user existence itself is free, but don't leave the account cluttered).

---

## Directory Structure

```
07-count-for-each/
├── README.md                          # this file
├── 07-count-for-each-anki.csv         # Anki flashcard deck
├── 07-count-for-each-quiz.md          # standalone quiz
└── src/
    ├── 01-providers.tf                 # terraform {} + provider block, versions pinned
    ├── 02-variables.tf                 # environment map, queue count, user list
    ├── 03-count-queues.tf              # count example: SQS dead-letter queues
    ├── 04-foreach-buckets.tf           # for_each example: per-environment S3 buckets + toset() IAM users
    ├── 05-outputs.tf                   # splat expression outputs
    └── break-fix/
        └── broken.tf                   # 3 deliberate count/for_each errors, self-contained
```

---

## Recall Check — Demo 06

Answer from memory before reading further. These questions come from Demo 06 (Data Sources and Expressions) only.

1. You need to reference an AWS account ID inside a resource block without hardcoding it. Which data source do you use, and what does it return?
2. You have a list of subnet IDs and need a map instead, keyed by availability zone. Which Terraform expression type builds that transformation, and what's the general shape of its syntax?
3. You want to attach a variable number of ingress rules to a security group depending on an input variable, without repeating the `ingress {}` block by hand. What Terraform construct handles this, and what does its `iterator` argument do?

<details>
<summary>Answers</summary>

1. `data "aws_caller_identity" "current"` — it returns the calling identity's `account_id`, `arn`, and `user_id`, resolved via the `sts:GetCallerIdentity` API call, without requiring you to hardcode the account number.
2. A `for` expression, specifically the map-producing form: `{ for s in var.subnets : s.az => s.id }` — the part before `=>` becomes the key, the part after becomes the value.
3. A `dynamic` block — it repeats a nested block *within* a single resource based on a collection. The `iterator` argument lets you rename the loop variable (default is the block's own label, e.g. `ingress`) to avoid collisions when nesting dynamic blocks.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Purpose |
|---|---|
| `count` | Create N identical instances of a resource, indexed 0 to N-1 |
| `count.index` | The current instance's index inside a `count`-driven resource |
| `for_each` | Create one instance of a resource per key in a map, or per value in a set |
| `each.key` / `each.value` | The current instance's key/value inside a `for_each`-driven resource |
| `toset()` | Converts a list to a set — required when you have a list but need `for_each`'s set/map input |
| Splat expression `[*]` | Collects one attribute across every instance of a `count` or `for_each` resource into a single list |
| `resource[0]` / `resource["key"]` | State/code addressing syntax for one instance of a multi-instance resource |

### Related constructs worth knowing (not used in this demo)

| Construct | Why it's related | Where it's covered |
|---|---|---|
| `dynamic` block | Also loop-driven, but repeats a *nested block inside one resource* — not the whole resource. Contrasted directly below so the two aren't conflated. | Introduced in Demo 06; contrasted here |
| `moved` block | Lets you rename a resource address (e.g. after switching `count` → `for_each`) without Terraform planning a destroy/recreate | Full coverage in Demo 08 |
| `terraform state list` index/key filtering | Reading and targeting individual instances of a multi-instance resource from the CLI | Full coverage in Demo 08 |

---

#### `count` — index-based resource multiplicity

**What:** Setting `count = N` on a resource block tells Terraform to create N instances of that resource instead of one. Each instance is addressed by a zero-based integer index: `aws_sqs_queue.dlq[0]`, `aws_sqs_queue.dlq[1]`, `aws_sqs_queue.dlq[2]`.

**Why:** Without `count`, creating three near-identical queues means writing three separate `resource` blocks that differ only in name — a maintenance and consistency risk (a config change has to be made in three places).

**How:** Inside the resource block, `count.index` is available as the current iteration's index (0, 1, 2, ...). It's commonly used to build a unique name: `name = "cloudnova-notifications-dlq-${count.index}"`.

```hcl
resource "aws_sqs_queue" "dlq" {
  count = 3
  name  = "cloudnova-notifications-dlq-${count.index}"
}
```

This Queue resource block is what Step 2 in Part A below applies — the `count = 3` argument is the only thing distinguishing this from three hand-written blocks, and `count.index` is what keeps the three resulting queue names from colliding.

**What it does NOT do:** `count` gives you an *integer-indexed list* of instances. It has no concept of a meaningful name per instance beyond the index itself — if CloudNova later needs to remove queue index 1 specifically, Terraform doesn't know "queue 1" was semantically the staging queue; it only knows index 1. This index-only addressing is exactly what causes the reordering trap covered in Demo 08.

---

#### `for_each` — key-based resource multiplicity (map form)

**What:** Setting `for_each = <map or set>` on a resource block creates one instance per entry. Unlike `count`, each instance is addressed by a **key you chose**, not a position: `aws_s3_bucket.env["dev"]`, `aws_s3_bucket.env["staging"]`.

**Why:** CloudNova's per-environment buckets have real semantic identity — "dev," "staging," "prod" — not just a position in a list. `for_each` lets the *name itself* be the address, which survives reordering the input map (map keys have no order to begin with) and makes "add prod, remove dev" a targeted, unambiguous change.

**How:** Inside the resource block, `each.key` is the map key (or the set value, if using a set) and `each.value` is the map value (or, for a set, identical to `each.key` since a set has no separate value).

```hcl
variable "environments" {
  type = map(string)
  default = {
    dev     = "us-east-2"
    staging = "us-east-2"
    prod    = "us-east-2"
  }
}

resource "aws_s3_bucket" "env" {
  for_each = var.environments
  bucket   = "cloudnova-${each.key}-assets"

  tags = {
    Environment = each.key
    Region      = each.value
  }
}
```

This is the exact configuration Step 6 in Part B builds — `each.key` becomes both the bucket name suffix and the `Environment` tag value, and `each.value` (the region string in the map) becomes the `Region` tag, demonstrating that `each.value` doesn't have to be used for the resource's primary identity at all.

---

#### `for_each` over a set — the `toset()` conversion

**What:** `for_each` accepts a map or a set of strings — **not a list**. If your input is a list (which is common — most variables default to lists), you must convert it with `toset()` first.

**Why:** Terraform needs each `for_each` key to be stable and independent of position, so that adding/removing one element doesn't shift the identity of the others. A list is ordered and can contain duplicates; a set is unordered and inherently free of duplicates — which is what "each key is a stable identity" actually requires.

**How:**

```hcl
variable "cloudnova_iam_users" {
  type    = list(string)
  default = ["dev-readonly", "billing-auditor"]
}

resource "aws_iam_user" "svc" {
  for_each = toset(var.cloudnova_iam_users)
  name     = each.key
}
```

**What it does NOT do:** `toset()` does not silently drop or reorder anything you'd notice for uniqueness purposes — it removes exact duplicates (if the list had `["dev-readonly", "dev-readonly"]`, the set has one `"dev-readonly"`), which is a real behavior a learner should expect, not a bug.

---

#### Splat expressions (`[*]`) — collecting one attribute across every instance

**What:** A splat expression, `resource.name[*].attribute`, returns a list containing that attribute from every instance of a `count`- or `for_each`-driven resource — without writing a `for` expression.

**Why:** After creating 3 SQS queues via `count`, CloudNova's application needs all three ARNs to configure a fan-out subscription. Writing `[aws_sqs_queue.dlq[0].arn, aws_sqs_queue.dlq[1].arn, aws_sqs_queue.dlq[2].arn]` by hand doesn't scale if the count changes; the splat expression does.

**How:**

```hcl
output "dlq_arns" {
  value = aws_sqs_queue.dlq[*].arn
}
```

**Splat vs. `for` expression — why this approach, not that one:** A `for` expression (`[for q in aws_sqs_queue.dlq : q.arn]`) produces the identical result here and is strictly more powerful (it supports filtering and transforming). Splat is the terser choice specifically for the common case of "give me one unmodified attribute from every instance, no filtering" — use `for` the moment you need a condition or a transformation on the result.

**`for_each` splat note:** on a `for_each` resource, `resource.name[*].attribute` returns the values in an **unspecified but consistent-within-a-plan order** (map iteration order) — not keyed. If you need the key alongside the value, use a `for` expression over `resource.name` instead: `{ for k, v in aws_s3_bucket.env : k => v.arn }`.

---

#### `count` vs `for_each` vs `dynamic` — concept comparison

These three are easy to conflate because all three are "loop over something in Terraform." They operate at different scopes:

| | Repeats | Addressed by | Typical use |
|---|---|---|---|
| `count` | The entire resource block | Integer index (`[0]`) | N identical/near-identical resources, position doesn't carry meaning |
| `for_each` | The entire resource block | Map key or set value (`["prod"]`) | N resources with a meaningful, stable identity per instance |
| `dynamic` | One nested block *inside* a single resource | N/A — it's not a separate resource instance at all | A variable number of repeated sub-blocks (e.g. `ingress {}`) within one resource |

**Bidirectional distinction:** `for_each` on a resource creates multiple *state entries* (`aws_s3_bucket.env["dev"]`, `aws_s3_bucket.env["prod"]` — two separate objects Terraform tracks independently). A `dynamic "ingress"` block inside one `aws_security_group` resource creates multiple *nested block instances inside one state entry* — there is still only one `aws_security_group.this` in state, just with several `ingress` blocks inside it.

---

#### Why `count` and `for_each` cannot coexist on one resource block

**What:** A single resource block may use `count` **or** `for_each`, never both.

**Why:** Both arguments answer the same underlying question — "how many instances, and how do I address each one?" — with two different, incompatible addressing schemes (integer index vs. arbitrary key). Terraform has no way to reconcile "the third instance" with "the instance named prod" if both were active simultaneously, so it rejects the configuration at the validation stage rather than guessing.

**How this is diagnosed:** covered directly in Break-Fix below — this is one of the three deliberate errors in this demo's scenario.

---

## Lab Step-by-Step Guide

---

### Part A — Count Fundamentals: CloudNova Notification Dead-Letter Queues

**What you accomplish in Part A:** CloudNova's notification service needs three SQS dead-letter queues, identical except for name, to shard failed-message retries across. You'll build them with `count`, verify the addressing, and collect their ARNs with a splat expression.

#### Step 1 — Initialize the working directory

This step establishes a clean Terraform working directory before any `count`/`for_each` code is written, so `init` failures are ruled out before we introduce new syntax.

```bash
cd src/
terraform init
```

Expected output:
```
Terraform has been successfully initialized!
```
> ⚠️ Simulated expected output — not from a live terminal run. Verify before following.

**# Observation:** A clean `init` here confirms the provider block and version constraints (Step 1's `01-providers.tf`) are valid before we add any `count`/`for_each` resources — isolating any later error to the new syntax, not to setup.

#### Step 2 — Write the `count`-based queue resource

This step creates the three dead-letter queues. `count = var.dlq_count` (defaulting to 3) is the only thing distinguishing this from three separate hand-written resource blocks.

**`03-count-queues.tf`:**
```hcl
resource "aws_sqs_queue" "dlq" {
  count = var.dlq_count
  name  = "cloudnova-notifications-dlq-${count.index}"

  tags = {
    Environment = "shared"
    ManagedBy   = "terraform-demo-07"
  }
}
```

#### Step 3 — Plan, apply, and verify addressing

```bash
terraform plan -out=demo07.tfplan
terraform apply demo07.tfplan
aws sqs list-queues --queue-name-prefix cloudnova-notifications-dlq
```

Expected output (`list-queues`):
```json
{
    "QueueUrls": [
        "https://sqs.us-east-2.amazonaws.com/<account-id>/cloudnova-notifications-dlq-0",
        "https://sqs.us-east-2.amazonaws.com/<account-id>/cloudnova-notifications-dlq-1",
        "https://sqs.us-east-2.amazonaws.com/<account-id>/cloudnova-notifications-dlq-2"
    ]
}
```
> ⚠️ Simulated expected output — not from a live terminal run. Verify before following.

**# Observation:** Three queues exist, named `-0` through `-2` — confirming `count.index` produced the expected 0-based sequence. Note the account ID is redacted here since it differs per user; never hardcode a value like this when documenting your own run.

#### Step 4 — Collect ARNs with a splat expression

This step demonstrates why splat expressions matter: without one, referencing all three queue ARNs elsewhere would mean hardcoding three separate index references.

**`05-outputs.tf`** (partial — DLQ portion):
```hcl
output "dlq_arns" {
  description = "ARNs of all CloudNova notification DLQs, collected via splat expression"
  value       = aws_sqs_queue.dlq[*].arn
}
```

```bash
terraform output dlq_arns
```

Expected output:
```
dlq_arns = [
  "arn:aws:sqs:us-east-2:<account-id>:cloudnova-notifications-dlq-0",
  "arn:aws:sqs:us-east-2:<account-id>:cloudnova-notifications-dlq-1",
  "arn:aws:sqs:us-east-2:<account-id>:cloudnova-notifications-dlq-2",
]
```
> ⚠️ Simulated expected output — not from a live terminal run. Verify before following.

**# Observation:** All three ARNs appear in a single list in index order — this is the value a downstream fan-out subscription resource would consume, without the config needing to know how many queues exist ahead of time.

---

### Part B — For-Each Fundamentals: Per-Environment Buckets and a `toset()` Example

**What you accomplish in Part B:** CloudNova needs one S3 bucket per environment (dev/staging/prod) with environment-specific tags, and two read-only IAM users defined from a plain list variable. You'll build both with `for_each`, contrasting map-based and set-based input.

#### Step 5 — Declare the environment map and user list

This step adds the input variables `for_each` will consume — a map for the buckets (key = environment name, value = region) and a list for the IAM users (converted to a set at the point of use).

**`02-variables.tf`** (relevant portion):
```hcl
variable "environments" {
  description = "CloudNova environments to provision a bucket for, keyed by name"
  type        = map(string)
  default = {
    dev     = "us-east-2"
    staging = "us-east-2"
    prod    = "us-east-2"
  }
}

variable "cloudnova_iam_users" {
  description = "Read-only IAM users to create — a list, converted to a set for for_each"
  type        = list(string)
  default     = ["dev-readonly", "billing-auditor"]
}

variable "dlq_count" {
  description = "Number of dead-letter queues to create via count"
  type        = number
  default     = 3
}
```

#### Step 6 — Write the `for_each` bucket resource

This step creates one bucket per map entry, keyed by environment name rather than by position — so "add a fourth environment" or "remove staging" is a one-line map change with no risk of touching the wrong bucket.

**`04-foreach-buckets.tf`:**
```hcl
resource "aws_s3_bucket" "env" {
  for_each = var.environments
  bucket   = "cloudnova-${each.key}-assets"

  tags = {
    Environment = each.key
    Region      = each.value
    ManagedBy   = "terraform-demo-07"
  }
}
```

#### Step 7 — Plan, apply, and verify key-based addressing

```bash
terraform plan -out=demo07-buckets.tfplan
terraform apply demo07-buckets.tfplan
aws s3 ls | grep cloudnova
```

Expected output:
```
2026-07-15 09:14:02 cloudnova-dev-assets
2026-07-15 09:14:03 cloudnova-prod-assets
2026-07-15 09:14:03 cloudnova-staging-assets
```
> ⚠️ Simulated expected output — not from a live terminal run. Verify before following.

**# Observation:** Bucket names carry the environment name directly — there's no need to cross-reference an index to know which bucket is which, unlike the DLQ queues in Part A. `aws s3 ls` sorts alphabetically, which is why `prod` appears before `staging` here — that ordering is a CLI display artifact, not the order Terraform created them in.

#### Step 8 — Add the `toset()`-based IAM users

This step demonstrates converting a `list(string)` variable into the set `for_each` requires, using the same `for_each` mechanism as Step 6 but over a converted list instead of a native map.

**`04-foreach-buckets.tf`** (append):
```hcl
resource "aws_iam_user" "svc" {
  for_each = toset(var.cloudnova_iam_users)
  name     = each.key

  tags = {
    ManagedBy = "terraform-demo-07"
  }
}
```

Note `each.value` is available here too, but on a set it's always identical to `each.key` — there's no separate "value" concept for a set, only a converted-list-of-keys.

#### Step 9 — Verify the IAM users

```bash
terraform apply -auto-approve
aws iam list-users --query "Users[?starts_with(UserName, 'dev-') || starts_with(UserName, 'billing-')].UserName"
```

Expected output:
```
[
    "billing-auditor",
    "dev-readonly"
]
```
> ⚠️ Simulated expected output — not from a live terminal run. Verify before following.

**# Observation:** Both users from the `cloudnova_iam_users` list variable now exist as individually addressable resources (`aws_iam_user.svc["dev-readonly"]`, `aws_iam_user.svc["billing-auditor"]`) — the `toset()` conversion didn't lose any list entries, since the two values were already unique.

---

### Part C — The Decision Framework

**What you accomplish in Part C:** With both mechanisms built, you'll apply CloudNova's decision framework to classify new scenarios, then deliberately trigger and read the error Terraform gives when both mechanisms are combined on one resource.

#### Step 10 — Apply the decision framework to three new scenarios

This step is a reasoning exercise, not a code change — it checks that the concept, not just the syntax, transferred.

| Scenario | `count`, `for_each`, or single resource? | Why |
|---|---|---|
| 5 identical CloudWatch log groups for 5 microservices with interchangeable names (`service-log-0` .. `service-log-4`) | `count` | Instances are truly interchangeable; no name carries independent meaning |
| One S3 bucket per AWS region CloudNova operates in (`us-east-2`, `eu-west-1`) | `for_each` (set of region strings) | Each instance has a meaningful, stable identity (the region) that must survive adding a third region later |
| CloudNova's single production VPC | Single resource, no `count`/`for_each` | There is exactly one; multiplicity constructs exist to avoid repetition, not to formalize a singleton |

#### Step 11 — Deliberately trigger the mutual-exclusion error

This step shows the exact validation failure Terraform produces when `count` and `for_each` both appear on one resource block — the same error diagnosed cold in Break-Fix below, seen here for the first time with the cause already known.

```hcl
# Do NOT leave this in the working config — for demonstration only
resource "aws_sqs_queue" "invalid_example" {
  count    = 2
  for_each = toset(["a", "b"])
  name     = "invalid-example"
}
```

```bash
terraform validate
```

Expected output:
```
Error: Invalid combination of "count" and "for_each"

  on 03-count-queues.tf line 14, in resource "aws_sqs_queue" "invalid_example":
  14:   for_each = toset(["a", "b"])

The "count" and "for_each" meta-arguments are mutually-exclusive, only one
should be used to be explicit about the number of resources to be created.
```
> ⚠️ Simulated expected output — not from a live terminal run. Verify before following. The exact wording of this error message has not been confirmed against a live `terraform validate` run in this environment — treat the surrounding cause/fix explanation as reliable, but verify literal wording before quoting it elsewhere.

**# Observation:** Terraform catches this at `validate` time, before any AWS API call — this is a static configuration error, not a runtime one. Remove the block (or the `for_each` line) before continuing; it must not remain in `03-count-queues.tf`.

---

## Cleanup

Destroy every resource created in this demo before moving on, and confirm the account is clean afterward.

```bash
cd src/
terraform destroy
```

Type `yes` when prompted. This removes all 3 SQS queues, all 3 S3 buckets, and both IAM users in one operation, since all are tracked in the same state file.

Verify a clean teardown:

```bash
aws sqs list-queues --queue-name-prefix cloudnova-notifications-dlq
aws s3 ls | grep cloudnova
aws iam list-users --query "Users[?starts_with(UserName, 'dev-') || starts_with(UserName, 'billing-')].UserName"
```

Expected: all three commands return empty results.
> ⚠️ Simulated expected output — not from a live terminal run. Verify before following.

---

## What You Learned

1. ✅ Created three SQS dead-letter queues using `count` and referenced each via `count.index`
2. ✅ Created one S3 bucket per environment using `for_each` over a map, keyed by `each.key`
3. ✅ Converted a `list(string)` variable to a set with `toset()` to satisfy `for_each`
4. ✅ Collected all three queue ARNs into a single output using a splat expression (`[*]`)
5. ✅ Verified individual instance addressing — `aws_sqs_queue.dlq[0]` vs `aws_s3_bucket.env["prod"]`
6. ✅ Applied the `count`/`for_each`/single-resource decision framework to three new scenarios
7. ✅ Diagnosed and fixed three deliberate `count`/`for_each` authoring errors (Break-Fix, below)
8. ✅ Triggered and read Terraform's mutual-exclusion error for `count` + `for_each` on one block, and explained why it exists

---

## Cert Tips — TA-004 Objectives Covered

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `count` and `count.index` | TA-004 Obj (configuration language / resource management) | Common exam pattern: "how many resources does this config create?" |
| `for_each` and `each.key`/`each.value` | TA-004 Obj (configuration language / resource management) | Frequently tested against a map input specifically |
| Splat expression `[*]` | TA-004 Obj 4 (variables/outputs and expressions) | Often tested as "what does this output value evaluate to" |
| `count`/`for_each` mutual exclusion | TA-004 Obj (configuration language) | Common trap question — expects you to identify the invalid config |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam shows a resource with both `count` and a `for_each`-style map reference | Recognize this configuration is invalid and would fail `validate` | Assuming Terraform merges the two or that `for_each` "wins" |
| Exam asks for the resource address of the second instance created by `count = 3` | `resource_type.name[1]` (zero-indexed) | Answering `resource_type.name[2]` (treating it as 1-indexed) |
| Exam shows `for_each` over a `list(string)` variable directly | Recognize this is invalid without `toset()` and would fail | Assuming `for_each` accepts lists natively like `count` accepts a number |

### Exam Task — Write a complete configuration

**Task:** CloudNova needs two things in one configuration: (1) three identical CloudWatch log groups named `app-log-0` through `app-log-2` using `count`, and (2) one S3 bucket per entry in a map variable `environments` (dev, staging, prod) using `for_each`, each tagged with its environment name. Write both from scratch.

**Block types required:** `resource` (x2, one using `count`, one using `for_each`), `variable` (the `environments` map)

**Official documentation:**
- [Count Meta-Argument](https://developer.hashicorp.com/terraform/language/meta-arguments/count)
- [For_Each Meta-Argument](https://developer.hashicorp.com/terraform/language/meta-arguments/for_each)

**What to practise:**
1. Open the `for_each` meta-argument page — navigate to the "Limitations" section covering the map/set requirement
2. Write the configuration from scratch without looking at Part A/B of this demo
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
variable "environments" {
  type = map(string)
  default = {
    dev     = "us-east-2"
    staging = "us-east-2"
    prod    = "us-east-2"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  count = 3                                    # index-based — names are interchangeable
  name  = "app-log-${count.index}"
}

resource "aws_s3_bucket" "env" {
  for_each = var.environments                  # key-based — environment name carries meaning
  bucket   = "cloudnova-${each.key}-assets"

  tags = {
    Environment = each.key
  }
}
```

**Arguments you must know without looking up:**
- `count.index` — zero-based, not one-based; a common exam trap when asked "what is the third instance's address"
- `for_each` requires a map or a set — a bare `list(string)` variable must be wrapped in `toset()` first

</details>

---

## Troubleshooting

| Symptom/Error | Cause | Fix |
|---|---|---|
| `Error: Invalid for_each argument` — value depends on resource attributes that cannot be determined until apply | `for_each` was set to something computed from a resource not yet created (e.g. `for_each = aws_instance.example[*].id`) | Restructure so the `for_each` input is a variable, `local`, or data source value known at plan time — not a downstream resource attribute |
| `for_each` value is a list, not a map or set | A `list(string)`/`list(object(...))` variable passed directly to `for_each` | Wrap in `toset()` for a plain list of strings, or convert to a map keyed by a stable field for a list of objects |
| Splat expression returns an empty list unexpectedly | Referencing `resource.name[*].attribute` on a resource whose `count` evaluated to 0 | Confirm the `count`/`for_each` input isn't empty — check the variable's actual value with `terraform console` |

---

## Break-Fix Scenario

CloudNova's junior engineer was asked to extend the notification-queue and bucket configuration and introduced three separate errors. Diagnose each using only `terraform validate`/`terraform plan` output — do not open the answers first.

```bash
cd src/break-fix/
terraform init
terraform validate
```

**`broken.tf`** (all three errors, self-contained with its own `terraform {}` block):
```hcl
terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# Error 1: for_each given a duplicate-key map — will fail before we even reach the AWS API
resource "aws_s3_bucket" "env" {
  for_each = {
    dev  = "us-east-2"
    dev  = "us-west-2"
  }
  bucket = "cloudnova-${each.key}-broken"
}

# Error 2: count and for_each on the same resource
resource "aws_sqs_queue" "dlq" {
  count    = 2
  for_each = toset(["a", "b"])
  name     = "cloudnova-broken-dlq"
}

# Error 3: count.index referenced inside a for_each resource
resource "aws_iam_user" "svc" {
  for_each = toset(["dev-readonly", "billing-auditor"])
  name     = "svc-user-${count.index}"
}
```

### Error-1

**File reference:** `broken.tf` — `aws_s3_bucket.env`

<details>
<summary>Reveal answer — attempt diagnosis first</summary>

**Cause:** HCL object literals cannot have duplicate keys — `dev` is defined twice in the map. This is a syntax-level error caught during parsing, before Terraform even evaluates `for_each`.

**Fix:** Each key must be unique. Rename one entry (e.g. `dev` and `dev-secondary`) or remove the duplicate.

**Cascade:** Because this fails at parse time, `terraform validate` never reaches Error 2 or Error 3 in the same file until this is fixed — fix errors in the order they're reported.

</details>

### Error-2

**File reference:** `broken.tf` — `aws_sqs_queue.dlq`

<details>
<summary>Reveal answer — attempt diagnosis first</summary>

**Cause:** `count` and `for_each` are both set on the same resource block. Terraform rejects this because the two addressing schemes (integer index vs. arbitrary key) are mutually incompatible — it has no way to reconcile them.

**Fix:** Choose one. Since the two SQS queues here have no meaningful per-instance identity beyond "queue A" and "queue B," `count = 2` with `count.index`-based naming is the better fit — remove the `for_each` line entirely.

**Cascade:** Leaving both in place blocks `terraform plan` from running at all for this resource — no queues get created until this is resolved.

</details>

### Error-3

**File reference:** `broken.tf` — `aws_iam_user.svc`

<details>
<summary>Reveal answer — attempt diagnosis first</summary>

**Cause:** `count.index` is only available inside a resource block that uses `count`. This resource uses `for_each`, where the equivalent references are `each.key`/`each.value` — `count.index` is undefined in this context and Terraform reports it as a reference to a nonexistent object.

**Fix:** Replace `count.index` with `each.key`: `name = "svc-user-${each.key}"` (or drop the numeric suffix entirely, since `each.key` already gives each user a unique, meaningful name).

**Cascade:** None of the two IAM users are created until this reference error is resolved — same effect as Error 2, a plan-blocking validation failure rather than a partial apply.

</details>

**Cleanup:**
```bash
cd src/break-fix/
terraform destroy -auto-approve
rm -f terraform.tfstate terraform.tfstate.backup
cd ../..
```
Verify: `terraform state list` inside `src/break-fix/` should error with "no state file was found" or return empty — confirming no break-fix resources remain before starting the next demo.

---

## Interview Prep

**Q1. When would you choose `count` over `for_each`, and when is that the wrong call?**
`count` fits when instances are truly interchangeable and position carries no meaning — three identical log groups, for example. It's the wrong call the moment an instance has a real identity worth preserving across changes, like "the prod bucket" — because removing an item from the middle of a `count`-driven list shifts every subsequent index, and Terraform will plan to destroy and recreate every instance after the removed one, even though their actual configuration didn't change. `for_each` avoids this entirely because each instance is addressed by its own stable key, independent of the others.

**Q2. A teammate's PR uses `for_each = var.subnet_ids` where `subnet_ids` is `type = list(string)`. What happens, and what's your review comment?**
It fails validation — `for_each` requires a map or a set, not a list, specifically because a set (or map) guarantees each key/value is a stable, order-independent identity, which is the property `for_each`'s per-instance addressing depends on. The review comment: wrap it as `toset(var.subnet_ids)`, and flag that if `subnet_ids` can ever contain duplicates, `toset()` will silently collapse them — worth confirming that's acceptable for this use case.

**Q3. How do you explain the difference between `for_each` on a resource and a `dynamic` block to someone who's only seen one of the two?**
`for_each` on a resource block creates multiple independent state entries — Terraform tracks each instance separately, and you can destroy one without touching the others. A `dynamic` block, by contrast, repeats a *nested configuration block inside a single resource* — there's still exactly one resource in state; you're just avoiding writing out N copies of an `ingress {}` block by hand. If someone says "I used `dynamic` to create three separate S3 buckets," that's actually not possible — `dynamic` can't create separate top-level resources, only repeated nested blocks within one.

**Q4. Your CI pipeline shows a plan with `count.index` used inside a `for_each` resource, and it's failing. Walk through your diagnosis.**
First, I'd read the exact error — Terraform will report a reference to an object that doesn't exist in that context, since `count.index` simply isn't defined inside a `for_each` block. That tells me immediately this is a mismatched meta-argument reference, not a provider or AWS-side issue. The fix is mechanical: swap `count.index` for `each.key` (or `each.value`, depending on what's actually needed), which confirms the resource was always meant to be `for_each`-driven and the reference was just never updated when it was converted.

**Q5. Why does Terraform refuse to let you use `count` and `for_each` together instead of just picking one automatically?**
Because "pick one automatically" would be a silent, implicit decision about addressing semantics — and Terraform's whole design philosophy is explicit, predictable state addressing. If it silently preferred `for_each`, someone debugging why their `count.index` references broke would have no clear signal why; failing validation immediately, with both meta-arguments visible in the error, makes the actual problem obvious at the point of authoring rather than surfacing as confusing behavior later.

---

## Key Takeaways

1. **`count` addresses instances by position, `for_each` addresses them by key.** Choosing `count` for something with real per-instance identity (like an environment name) sets up the reordering-replacement trap covered fully in Demo 08 — choose based on whether position or identity is the meaningful thing here, not on which one is shorter to type.
2. **`for_each` requires a map or a set — never a plain list.** A `list(string)` variable must go through `toset()` first; forgetting this is one of the most common `for_each` authoring errors and fails at `validate`, before any AWS call.
3. **`count.index` only exists inside `count`-driven resources; `each.key`/`each.value` only exist inside `for_each`-driven ones.** Mixing them up — usually after converting a resource from one to the other — produces an "reference to undeclared" error, not a silent wrong value.
4. **`count` and `for_each` can never coexist on one resource block.** Terraform rejects this at validation time specifically because the two addressing schemes are mutually incompatible — there is no "for_each wins" fallback.
5. **Splat expressions (`resource[*].attr`) are the terse form of a `for` expression for the single common case of "one unmodified attribute from every instance."** Reach for a full `for` expression the moment you need filtering or transformation instead.
6. **`for_each` on a resource and a `dynamic` block are not the same tool.** `for_each` creates multiple independent state entries for a whole resource; `dynamic` repeats one nested block inside a single resource, which still has exactly one state entry.
7. **`toset()` silently deduplicates.** If your source list can contain duplicate values, confirm that's actually acceptable before relying on `toset()` to "just handle it" — it will handle it by discarding the duplicate, which may not be what you wanted.
8. **A resource with real, stable per-instance names (environments, regions, named service accounts) is very rarely a good `count` candidate** — if you're naming instances by string in your `count.index` interpolation anyway, that's usually a sign the resource wants `for_each` instead.

---

## Next Demo

**Demo 08 — State Addressing and Multiplicity Migration**

Building directly on this demo's `count` and `for_each` resources, Demo 08 covers:
- The exact state-addressing mechanics behind `resource[0]` vs `resource["key"]`
- The `count` mid-list-removal replacement trap, demonstrated live against this demo's DLQ queues
- Migrating a resource from `count` to `for_each` without a destroy/recreate, using the `moved` block
- Advanced splat usage and `terraform state list` key/index filtering

---

## Appendix — Anki Cards

**`07-count-for-each-anki.csv`:**
```csv
#deck:Terraform AWS Mastery::Phase 1 - Foundations::07-count-for-each
#separator:Comma
#columns:Front,Back,Tags
"You need 3 identical CloudWatch log groups where none of them has a meaningful name beyond being 'one of three.' Which meta-argument do you use, and how do you build a unique name for each?","Use `count = 3`. Build the name with `count.index`, e.g. `name = ""app-log-${count.index}""` — this produces app-log-0, app-log-1, app-log-2 (zero-indexed).","demo07,count,ta-004"
"You write `for_each = var.subnet_ids` where subnet_ids is `type = list(string)`. What happens when you run terraform validate?","It fails. `for_each` requires a map or a set, not a list. Fix: wrap it as `toset(var.subnet_ids)`.","demo07,for_each,ta-004"
"Inside a for_each-driven resource, what are the two expressions used to reference the current instance's key and value?","each.key and each.value. On a set (via toset()), each.value is always identical to each.key since a set has no separate value component.","demo07,for_each,ta-004"
"Inside a count-driven resource, what expression gives you the current instance's position, and is it zero- or one-indexed?","count.index — zero-indexed. The first instance is count.index == 0, not 1.","demo07,count,ta-004"
"You write a resource block with both count = 2 and for_each = toset([""a"",""b""]). What happens?","terraform validate fails with an error that count and for_each are mutually exclusive on a single resource block — Terraform cannot reconcile integer-index addressing with key-based addressing at the same time. [needs-verification]","demo07,count,for_each,break-fix,ta-004"
"You accidentally leave count.index in a resource that was converted to for_each. What error do you get?","A reference-to-undeclared error — count.index only exists inside count-driven resources. The fix is to replace it with each.key or each.value, whichever is appropriate.","demo07,for_each,break-fix"
"How do you collect the ARN of every instance of a count-driven aws_sqs_queue resource into a single list, without a for expression?","A splat expression: aws_sqs_queue.dlq[*].arn — returns a list of every instance's arn attribute in index order.","demo07,splat,ta-004"
"When would you prefer a full for expression over a splat expression for collecting resource attributes?","When you need to filter instances or transform the attribute before collecting it — splat only handles 'give me one unmodified attribute from every instance, unconditionally.'","demo07,splat"
"On a for_each resource, does a splat expression (resource[*].attr) return the results keyed by each.key?","No — splat on a for_each resource returns values in map-iteration order with no keys attached. To keep the key, use a for expression instead: { for k, v in resource : k => v.attr }.","demo07,splat,for_each"
"How is an individual instance of a for_each-driven aws_s3_bucket resource named env, keyed dev, addressed in Terraform code or state?","aws_s3_bucket.env[""dev""] — string key in square brackets, quoted.","demo07,for_each,state-addressing"
"How is the second instance of a count-driven aws_sqs_queue resource named dlq addressed?","aws_sqs_queue.dlq[1] — integer index in square brackets, zero-based, so the second instance is index 1.","demo07,count,state-addressing"
"You have a list variable with a duplicate value and convert it with toset() for a for_each resource. What happens to the duplicate?","toset() silently deduplicates — the resulting set contains only one instance of the duplicated value, so only one resource instance is created for it, not two.","demo07,for_each,toset"
"What is the key structural difference between for_each on a resource block and a dynamic block inside a resource?","for_each on a resource creates multiple independent state entries (separate objects Terraform tracks). A dynamic block repeats a nested configuration block inside a single resource — there is still exactly one state entry.","demo07,for_each,dynamic,ta-004"
"Why does for_each require a map or set instead of accepting a list directly, the way count accepts a plain number?","Because for_each's addressing depends on each key being a stable, order-independent identity — a list is ordered and can contain duplicates, which breaks that guarantee. A map or set enforces uniqueness and doesn't rely on position.","demo07,for_each"
"CloudNova needs one S3 bucket per environment (dev/staging/prod), each with a meaningful, permanent name. Why is for_each the better choice here over count, even though both could technically create 3 buckets?","for_each addresses each bucket by environment name (a stable identity), so adding a 4th environment or removing one doesn't shift any other bucket's address. count addresses buckets by position — removing the middle one out of three would shift indexes and could cause Terraform to plan destroy/recreate on buckets that didn't actually change.","demo07,for_each,count,decision"
"A resource has count = 3 and you reference aws_instance.web[2] in another resource. Is [2] the second or third instance?","The third instance — count.index and the resulting addressing are zero-based, so [0] is first, [1] is second, [2] is third.","demo07,count,state-addressing,ta-004"
"What's the fix for a for_each map literal that has the same key defined twice, e.g. { dev = ""a"", dev = ""b"" }?","This is an HCL syntax error, not a for_each-specific one — object literals cannot have duplicate keys. Rename one of the keys so both are unique.","demo07,for_each,break-fix"
"True or false: a splat expression can be used on a resource that has neither count nor for_each set.","False — without count or for_each, a resource has exactly one instance (no index or key), and splat syntax (resource[*].attr) doesn't apply; you'd just reference resource.attr directly.","demo07,splat"
```

---

## Appendix — Quiz

**`07-count-for-each-quiz.md`:**
````markdown
# Demo 07 Quiz — Count, For-Each, and the Multiplicity Decision

---

**Q1.** You need 4 identical CloudWatch log groups where no instance has meaning beyond "one of four." What's the best construct?

- A) `for_each` over a set of 4 arbitrary strings
- B) `count = 4`
- C) Four separate resource blocks
- D) `dynamic` block

<details>
<summary>Answer</summary>

**B** — `count` is designed exactly for this: N interchangeable instances with no meaningful per-instance identity. `for_each` (A) works too but adds unnecessary indirection (you'd have to invent 4 arbitrary keys). Four separate blocks (C) is the repetition this feature exists to eliminate. `dynamic` (D) repeats a nested block within one resource, not whole resources.

</details>

---

**Q2.** A resource block has `for_each = var.regions` where `regions` is `type = list(string)`. What happens on `terraform validate`?

- A) It works — `for_each` accepts lists directly
- B) It fails — `for_each` requires a map or a set
- C) It works but silently treats the list as a set
- D) It works only if the list has no duplicates

<details>
<summary>Answer</summary>

**B** — `for_each` requires a map or a set, never a plain list, regardless of whether the list has duplicates. Fix: wrap it in `toset()`.

</details>

---

**Q3.** Inside a `for_each`-driven resource, you write `name = "svc-${count.index}"`. What happens?

- A) It works, using the map's iteration position
- B) It fails — `count.index` is undefined in a `for_each` context
- C) It works, treating `count.index` as `each.key`
- D) It silently defaults to 0

<details>
<summary>Answer</summary>

**B** — `count.index` only exists inside `count`-driven resources. In a `for_each` resource, the equivalent references are `each.key`/`each.value`. Terraform reports this as a reference to an undeclared object; it does not fall back to any of A/C/D.

</details>

---

**Q4.** What's the correct way to reference the third instance of `resource "aws_sqs_queue" "dlq"` created with `count = 5`?

- A) `aws_sqs_queue.dlq[3]`
- B) `aws_sqs_queue.dlq[2]`
- C) `aws_sqs_queue.dlq["3"]`
- D) `aws_sqs_queue.dlq.2`

<details>
<summary>Answer</summary>

**B** — indexing is zero-based, so the third instance is index 2. A is a common off-by-one error treating it as one-based. C uses `for_each`-style string-key syntax, which doesn't apply to `count`. D isn't valid Terraform syntax for either mechanism.

</details>

---

**Q5.** A resource block is written with both `count = 2` and `for_each = toset(["a","b"])`. What is the result?

- A) Terraform creates 2 instances, using `for_each`'s values as names
- B) Terraform creates 4 instances (2 × 2)
- C) `terraform validate` fails — the two meta-arguments are mutually exclusive
- D) `for_each` is silently ignored and `count` wins

<details>
<summary>Answer</summary>

**C** — Terraform rejects this configuration at validation time. There is no merge or precedence behavior (ruling out A, B, D) — the two addressing schemes are incompatible and Terraform will not guess which one you meant.

</details>

---

**Q6.** What does `aws_s3_bucket.env[*].arn` return, if `env` is a `for_each`-driven resource over a 3-entry map?

- A) A map of key → arn
- B) A list of the 3 ARNs, in map-iteration order, with no keys attached
- C) A single ARN — the first instance only
- D) An error — splat doesn't work on `for_each` resources

<details>
<summary>Answer</summary>

**B** — splat on a `for_each` resource still returns a list, not a map, and does not carry the keys along. If you need the keys, use a `for` expression instead: `{ for k, v in aws_s3_bucket.env : k => v.arn }`.

</details>

---

**Q7.** Your input list variable has a duplicate value: `["dev-readonly", "dev-readonly"]`. You use `toset()` for a `for_each` resource. How many instances get created?

- A) 2 — one per list element
- B) 1 — `toset()` deduplicates
- C) 0 — duplicates cause a validation error
- D) It depends on provider behavior

<details>
<summary>Answer</summary>

**B** — `toset()` converts the list to a set, and sets cannot contain duplicate values, so the duplicate collapses to one entry and exactly one resource instance is created for it.

</details>

---

**Q8.** What is the key structural difference between using `for_each` on a resource block versus using a `dynamic` block inside a resource?

- A) There is no difference — both create multiple resource instances
- B) `for_each` on a resource creates multiple independent state entries; `dynamic` repeats a nested block within a single resource that remains one state entry
- C) `dynamic` blocks can only be used with `count`, never `for_each`
- D) `for_each` can only be used inside `dynamic` blocks

<details>
<summary>Answer</summary>

**B** — this is the core distinction covered in Concepts. A `for_each`-driven resource has as many independent state entries as there are keys; a `dynamic` block just repeats configuration inside one resource, which still has exactly one state entry.

</details>

---

**Q9.** CloudNova needs a bucket per environment where the environment name itself is meaningful and must be stable if environments are added or removed later. Which is the better choice and why?

- A) `count`, because it's simpler syntax
- B) `for_each`, because each instance's identity (the environment name) doesn't depend on the position of other instances
- C) Either works identically for this case
- D) Neither — this requires a separate resource block per environment

<details>
<summary>Answer</summary>

**B** — this is exactly the scenario `for_each` is designed for: instances with real, stable identity. `count` (A) would work mechanically but risks the reordering-replacement trap the moment a middle environment is removed — full mechanics of that trap are covered in Demo 08.

</details>

---
````