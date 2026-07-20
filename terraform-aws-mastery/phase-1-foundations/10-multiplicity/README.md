# Demo 10 — Multiplicity: `count`, `for_each`, and `dynamic`

---

## Overview

CloudNova has been writing one `resource` block per S3 bucket, per SQS
queue, per IAM user — and it's starting to hurt. The platform team just
asked for three near-identical dead-letter queues, three near-identical
S3 buckets (dev/staging/prod), and a security group with a variable
number of ingress rules. Copy-pasting resource blocks with only the
name changed is exactly the kind of repetition Terraform exists to
eliminate — and this demo covers all three ways Terraform repeats
configuration, taught together so the contrast between them is
immediate rather than spread across separate demos.

**Real-world scenario — CloudNova:** three dead-letter queues (position
doesn't matter — `count`), three per-environment buckets and two IAM
users (identity matters — `for_each`), and a security group with a
caller-supplied number of ingress rules (repeating a *nested block*
inside one resource — `dynamic`).

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — count Fundamentals: Notification Dead-Letter Queues           │
│  count.index   |   splat expressions collecting ARNs across instances  │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — for_each Fundamentals: Buckets, Users, and toset()             │
│  for_each over a map (buckets)   |   for_each over a converted set     │
│  (IAM users)   |   each.key / each.value                                 │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — dynamic Blocks and the Decision Framework                     │
│  A security group with a variable number of ingress rules   |   count  │
│  vs. for_each vs. dynamic vs. a single resource — and the mutual-       │
│  exclusion error diagnosed live                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- `count` and `count.index` — index-based resource multiplicity
- `for_each` and `each.key`/`each.value` — key-based resource multiplicity
- `toset()` — converting a list to the set `for_each` requires
- Splat expressions (`[*]`) — collecting one attribute across instances
- `dynamic` blocks — repeating a *nested block inside one resource*,
  contrasted directly against `for_each` on a whole resource
- `data.aws_vpc` — supplying the security group's `vpc_id`
- The `count`/`for_each`/`dynamic`/single-resource decision framework
- Why `count` and `for_each` cannot coexist on one resource block

**What this demo does NOT cover:** the exact state-addressing mechanics
behind `resource[0]` vs. `resource["key"]`, the `count` mid-list-removal
replacement trap, and migrating a resource from `count` to `for_each`
without destroy/recreate are Demo 11's focus (State Addressing and
Multiplicity Migration).

---

## Prerequisites

### Knowledge
- Demo 09 completed — `for` expressions and collection functions,
  since `for_each`'s map inputs in this demo build directly on that

### Required Tools

Same as Demos 05–09 — Terraform `>= 1.15.0`, AWS CLI `>= 2.x`, `jq`.

### Verify AWS Account and Permissions

```bash
aws sts get-caller-identity --profile default
aws configure get region --profile default
```

**Required permissions for this demo:**

```
sqs:CreateQueue, sqs:DeleteQueue, sqs:GetQueueAttributes, sqs:ListQueues
sqs:SendMessage, sqs:ReceiveMessage, sqs:DeleteMessage
s3:CreateBucket, s3:DeleteBucket, s3:PutBucketTagging, s3:ListBucket
iam:CreateUser, iam:DeleteUser, iam:GetUser, iam:TagUser
ec2:CreateSecurityGroup, ec2:DeleteSecurityGroup, ec2:DescribeSecurityGroups
ec2:AuthorizeSecurityGroupIngress, ec2:RevokeSecurityGroupIngress
ec2:DescribeVpcs
```

> For a learning account, `AmazonSQSFullAccess`, `AmazonS3FullAccess`,
> `IAMFullAccess`, and `AmazonEC2FullAccess` managed policies cover the
> permissions above.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Create multiple identical resource instances using `count` and
   reference each via `count.index`
2. ✅ Create resource instances keyed by name using `for_each` over a
   map, converting a list to a set with `toset()` where needed
3. ✅ Collect one attribute across every instance of a `count`- or
   `for_each`-driven resource using a splat expression (`[*]`)
4. ✅ Use a `dynamic` block to repeat a nested block within one
   resource, and explain how this differs from `for_each` on a whole
   resource
5. ✅ Apply the `count`/`for_each`/`dynamic`/single-resource decision
   framework, and diagnose the `count`+`for_each` mutual-exclusion error

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| SQS queues (×3, standard) | Free forever — 1M requests/month | **$0.00** | Well under free tier for a lab |
| S3 buckets (×3, empty) | Free for the buckets themselves | **$0.00** | No objects uploaded |
| IAM users (×2) | Always free | **$0.00** | |
| Security group | Always free | **$0.00** | |
| **Session total** | | **$0.00** | |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
10-multiplicity/
├── README.md
├── 10-multiplicity-anki.csv
├── 10-multiplicity-quiz.md
└── src/
    ├── 01-versions.tf         # terraform block + provider version constraints
    ├── 02-provider.tf         # AWS provider: region, profile
    ├── 03-variables.tf        # dlq_count, environments map, iam_users list, ingress_rules
    ├── 04-count-queues.tf     # count-driven aws_sqs_queue
    ├── 05-foreach-buckets.tf  # for_each-driven aws_s3_bucket + aws_iam_user
    ├── 06-dynamic-sg.tf       # dynamic-block security group + data.aws_vpc
    ├── 07-outputs.tf          # splat-expression outputs
    └── break-fix/
        └── broken.tf
```

---

## Recall Check — Demo 09

Answer from memory before reading further:

1. What is the syntax difference between a list-producing and a
   map-producing `for` expression?
2. Two source elements produce the same key in a map-producing `for`
   expression, written without the `...` suffix. What happens?
3. What is the difference between `lookup(map, "key", default)` and
   `map["key"]`?

<details>
<summary>Answers</summary>

1. List-producing uses square brackets with no `=>`:
   `[for x in collection : value]`. Map-producing uses curly braces
   and `=>`: `{for x in collection : key => value}`. Mixing the two
   (brackets with `=>`) is a syntax error.
2. Last-write-wins, silently — only the last-processed element's value
   survives for that key; the earlier one is overwritten with no
   error. Adding `...` after the value expression collects all matches
   into a list instead.
3. `map["key"]` errors if the key doesn't exist. `lookup(map, "key",
   default)` returns the default instead of erroring — use it when a
   missing key is expected and should degrade gracefully.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `count` | Resource meta-argument | Create N identical instances, indexed 0 to N-1 |
| `count.index` | Expression | The current instance's index inside a `count`-driven resource |
| `for_each` | Resource meta-argument | Create one instance per key in a map, or per value in a set |
| `each.key` / `each.value` | Expression | The current instance's key/value inside a `for_each`-driven resource |
| `toset()` | Built-in function | Converts a list to a set — required when `for_each` needs a set but you have a list |
| Splat expression `[*]` | Expression | Collects one attribute across every instance into a single list |
| `dynamic` block | Language construct | Repeats a nested block *within one resource*, based on a collection |
| `data.aws_vpc` | Data source | Reads the default (or specified) VPC, supplying `vpc_id` to the security group |

**Related constructs worth knowing (not used in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| `resource[0]` / `resource["key"]` state addressing | Instance addressing syntax | Demo 11 |
| `moved` block | Migrating between `count`/`for_each` without destroy/recreate | Demo 11 |
| `terraform state list` index/key filtering | Targeting individual instances from the CLI | Demo 11 |

---

### Detailed Explanation of New Constructs

#### `count` — Index-Based Resource Multiplicity

Setting `count = N` on a resource block tells Terraform to create N
instances instead of one. Each instance is addressed by a zero-based
integer index: `aws_sqs_queue.dlq[0]`, `aws_sqs_queue.dlq[1]`,
`aws_sqs_queue.dlq[2]`.

```hcl
resource "aws_sqs_queue" "dlq" {
  count = 3
  name  = "cloudnova-notifications-dlq-${count.index}"
}
```

`count.index` is available inside the block as the current iteration's
index (0, 1, 2, ...) — commonly used to build a unique name.

> **`count` gives you an integer-indexed list of instances, nothing
> more.** It has no concept of a meaningful name per instance beyond
> the index itself. If you later need to remove "the staging queue"
> specifically, `count` doesn't know any queue was semantically
> staging — it only knows indexes. This index-only addressing is
> exactly what causes the reordering trap covered in Demo 11.

---

#### `for_each` — Key-Based Resource Multiplicity

Setting `for_each = <map or set>` creates one instance per entry,
addressed by a **key you chose**, not a position:
`aws_s3_bucket.env["dev"]`, `aws_s3_bucket.env["staging"]`.

```hcl
resource "aws_s3_bucket" "env" {
  for_each = var.environments
  bucket   = "cloudnova-${each.key}-assets"

  tags = {
    Environment = each.key
    Region      = each.value
  }
}
```

`each.key` is the map key (or set value); `each.value` is the map value
(or, for a set, identical to `each.key`, since a set has no separate
value).

---

#### `for_each` over a Set — the `toset()` Conversion

`for_each` accepts a map or a set of strings — **not a list**. A list
variable must be converted first:

```hcl
resource "aws_iam_user" "svc" {
  for_each = toset(var.cloudnova_iam_users)
  name     = each.key
}
```

> **`toset()` silently deduplicates.** If the source list has a
> duplicate value, the resulting set collapses it to one — exactly one
> resource instance is created for it, not two.

---

#### Splat Expressions (`[*]`) — Collecting One Attribute Across Instances

```hcl
output "dlq_arns" {
  value = aws_sqs_queue.dlq[*].arn
}
```

Returns a list containing that attribute from every instance of a
`count`- or `for_each`-driven resource, without writing a `for`
expression.

> **Splat vs. `for` expression:** a `for` expression
> (`[for q in aws_sqs_queue.dlq : q.arn]`) produces the identical
> result here and is strictly more powerful (filtering, transforming).
> Splat is the terser choice specifically for "give me one unmodified
> attribute from every instance, no filtering."

> **On a `for_each` resource, splat returns values in map-iteration
> order with no keys attached** — not keyed by `each.key`. If you need
> the key alongside the value, use a `for` expression instead:
> `{for k, v in aws_s3_bucket.env : k => v.arn}`.

---

#### `dynamic` Blocks — Repeating a Nested Block Within One Resource

Every construct so far in this demo repeats a *whole resource*. A
`dynamic` block is different: it repeats a **nested block inside a
single resource**, based on a collection.

```hcl
resource "aws_security_group" "app" {
  name   = "cloudnova-app-sg"
  vpc_id = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }
}
```

The `dynamic "ingress"` block's `for_each` drives how many `ingress {}`
blocks get generated — but there is still exactly **one**
`aws_security_group.app` in state, regardless of how many `ingress`
blocks it ends up containing. Inside `content {}`, the iterator
variable defaults to the block's own label (`ingress` here) — `.value`
accesses the current element, same as `each.value` would.

**Renaming the iterator** (useful to avoid collisions when nesting
`dynamic` blocks inside other `dynamic` blocks):

```hcl
dynamic "ingress" {
  for_each = var.ingress_rules
  iterator = rule
  content {
    from_port = rule.value.from_port
    to_port   = rule.value.to_port
  }
}
```

---

#### `count` vs. `for_each` vs. `dynamic` — Concept Comparison

These three are easy to conflate because all three are "loop over
something in Terraform." They operate at different scopes:

| | Repeats | Addressed by | Typical use |
|---|---|---|---|
| `count` | The entire resource block | Integer index (`[0]`) | N identical/near-identical resources, position doesn't carry meaning |
| `for_each` | The entire resource block | Map key or set value (`["prod"]`) | N resources with a meaningful, stable identity per instance |
| `dynamic` | One nested block *inside* a single resource | N/A — not a separate resource instance | A variable number of repeated sub-blocks (e.g. `ingress {}`) within one resource |

**Bidirectional distinction:** `for_each` on a resource creates
multiple *state entries* — `aws_s3_bucket.env["dev"]` and
`aws_s3_bucket.env["prod"]` are two separate objects Terraform tracks
independently. A `dynamic "ingress"` block inside one
`aws_security_group` resource creates multiple *nested block instances
inside one state entry* — there is still only one
`aws_security_group.app` in state, just with several `ingress` blocks
inside it.

---

#### `data.aws_vpc` — Supplying the Security Group's `vpc_id`

```hcl
data "aws_vpc" "default" {
  default = true
}
```

Reads the account's default VPC (or a specific one, via `filter`
blocks) without creating or managing it — the same `data` vs.
`resource` distinction from Demo 08, arriving here because this
security group genuinely needs a real `vpc_id` to attach to.

---

#### Why `count` and `for_each` Cannot Coexist on One Resource Block

A single resource block may use `count` **or** `for_each`, never both
— both arguments answer the same question ("how many instances, and
how do I address each one?") with incompatible addressing schemes.
Terraform rejects this at validation time rather than guessing which
one you meant. Diagnosed live in Break-Fix below.

---

## Lab Step-by-Step Guide

---

## Part A — count Fundamentals: Notification Dead-Letter Queues

**What you accomplish in Part A:** build three SQS dead-letter queues
with `count`, verify index-based addressing, and collect all three
ARNs with a splat expression.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/10-multiplicity/src
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

**What this file does in this demo:** `dlq_count` drives Part A;
`environments` and `cloudnova_iam_users` drive Part B; `ingress_rules`
drives Part C's `dynamic` block.

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

variable "dlq_count" {
  type        = number
  description = "Number of dead-letter queues to create via count"
  default     = 3
}

variable "environments" {
  type        = map(string)
  description = "CloudNova environments to provision a bucket for, keyed by name"
  default = {
    dev     = "us-east-2"
    staging = "us-east-2"
    prod    = "us-east-2"
  }
}

variable "cloudnova_iam_users" {
  type        = list(string)
  description = "Read-only IAM users to create — a list, converted to a set for for_each"
  default     = ["dev-readonly", "billing-auditor"]
}

variable "ingress_rules" {
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  description = "Ingress rules for the app security group — variable count, drives the dynamic block"
  default = [
    {
      description = "HTTPS from anywhere"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "SSH from CloudNova office"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["203.0.113.0/24"]
    }
  ]
}
```

---

#### `04-count-queues.tf` — count-driven dead-letter queues

**What this file does in this demo:** `count.index` drives the naming
— no meaningful identity beyond position, which is why `count` (not
`for_each`) is the right choice for these queues.

**04-count-queues.tf:**

```hcl
resource "aws_sqs_queue" "dlq" {
  count = var.dlq_count
  name  = "cloudnova-notifications-dlq-${count.index}"

  tags = {
    Environment = "shared"
    ManagedBy   = "terraform-demo-10"
  }
}
```

---

### Step 3 — Apply, verify addressing, and collect ARNs with splat

```bash
terraform init
terraform validate
terraform apply
```

```bash
aws sqs list-queues --queue-name-prefix cloudnova-notifications-dlq
```

Expected:

```json
{
    "QueueUrls": [
        "https://sqs.us-east-2.amazonaws.com/<account-id>/cloudnova-notifications-dlq-0",
        "https://sqs.us-east-2.amazonaws.com/<account-id>/cloudnova-notifications-dlq-1",
        "https://sqs.us-east-2.amazonaws.com/<account-id>/cloudnova-notifications-dlq-2"
    ]
}
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

**Verify:**

```
Console → SQS → Queues → cloudnova-notifications-dlq-0, -1, -2
  → all three exist, tagged Environment=shared ✅
```

Create a file **07-outputs.tf** and add the below content — this is
its first content in the demo, and Part B/C will add more outputs to
it as they go:

```hcl
output "dlq_arns" {
  description = "ARNs of all CloudNova notification DLQs, collected via splat expression"
  value       = aws_sqs_queue.dlq[*].arn
}
```

```bash
terraform apply
terraform output dlq_arns
```

> **Three queues, named `-0` through `-2`, confirm `count.index`
> produced the expected 0-based sequence** — and the splat output
> collects all three ARNs without knowing in advance how many queues
> exist.

---

## Part B — for_each Fundamentals: Buckets, Users, and toset()

**What you accomplish in Part B:** create one S3 bucket per
environment using `for_each` over a map, and two IAM users using
`for_each` over a `toset()`-converted list — then verify a specific,
index/key-addressed instance with a real send/receive round trip.

### Step 1 — Create `05-foreach-buckets.tf`

**What this file does in this demo:** `each.key` carries the
environment's real identity here, which is why `for_each` (not
`count`) is the right choice — bucket names must stay stable if an
environment is added or removed later.

Create a file **05-foreach-buckets.tf** and add the below content:

```hcl
resource "aws_s3_bucket" "env" {
  for_each = var.environments
  bucket   = "cloudnova-${each.key}-assets"

  tags = {
    Environment = each.key
    Region      = each.value
    ManagedBy   = "terraform-demo-10"
  }
}

resource "aws_iam_user" "svc" {
  for_each = toset(var.cloudnova_iam_users)
  name     = each.key

  tags = {
    ManagedBy = "terraform-demo-10"
  }
}
```

### Step 2 — Apply and verify key-based addressing

```bash
terraform apply
aws s3 ls | grep cloudnova
```

Expected:

```
2026-07-15 09:14:02 cloudnova-dev-assets
2026-07-15 09:14:03 cloudnova-prod-assets
2026-07-15 09:14:03 cloudnova-staging-assets
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **Bucket names carry the environment name directly** — no index
> cross-reference needed, unlike the DLQ queues in Part A.
> `aws s3 ls` sorts alphabetically, which is why `prod` appears before
> `staging` here — a CLI display artifact, not creation order.

**Verify:**

```
Console → S3 → Buckets → cloudnova-dev-assets, cloudnova-staging-assets,
  cloudnova-prod-assets
  → all three exist, tagged Environment=<matching key> ✅
```

### Step 3 — Verify the IAM users

```bash
aws iam list-users --query "Users[?starts_with(UserName, 'dev-') || starts_with(UserName, 'billing-')].UserName"
```

Expected: `["billing-auditor", "dev-readonly"]`

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

**Verify:**

```
Console → IAM → Users → dev-readonly, billing-auditor
  → both exist, tagged ManagedBy=terraform-demo-10 ✅
```

### Step 4 — Verify a specific indexed queue with a real round trip

This step strengthens Part A's verification — proving `count` index
addressing works by sending to *one specific* queue, not just
confirming three queues exist.

```bash
QUEUE_URL=$(aws sqs get-queue-url --queue-name cloudnova-notifications-dlq-1 --query QueueUrl --output text)

aws sqs send-message --queue-url "$QUEUE_URL" --message-body "test-message-for-index-1"

aws sqs receive-message --queue-url "$QUEUE_URL" --query "Messages[0].Body" --output text
```

Expected: `test-message-for-index-1` — confirming the message was sent
to, and received from, `aws_sqs_queue.dlq[1]` specifically, not just
"one of the three queues."

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

```bash
RECEIPT_HANDLE=$(aws sqs receive-message --queue-url "$QUEUE_URL" --query "Messages[0].ReceiptHandle" --output text)
aws sqs delete-message --queue-url "$QUEUE_URL" --receipt-handle "$RECEIPT_HANDLE"
```

---

## Part C — dynamic Blocks and the Decision Framework

**What you accomplish in Part C:** build a security group whose
ingress rules are generated by a `dynamic` block, then apply the
decision framework to new scenarios and trigger the `count`/`for_each`
mutual-exclusion error live.

### Step 1 — Create `06-dynamic-sg.tf`

**What this file does in this demo:** a single resource whose ingress
rules come entirely from the `dynamic "ingress"` block — no ingress
rule is hand-written as a separate `ingress {}` block, and there is
still exactly one `aws_security_group` in state regardless of how many
rules `var.ingress_rules` contains.

Create a file **06-dynamic-sg.tf** and add the below content:

```hcl
data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "app" {
  name        = "cloudnova-app-sg"
  description = "CloudNova application security group"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  tags = {
    ManagedBy = "terraform-demo-10"
  }
}
```

### Step 2 — Apply and verify the generated ingress rules

```bash
terraform apply
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=cloudnova-app-sg" \
  --query "SecurityGroups[0].IpPermissions"
```

Expected: two ingress rule entries — port 443 (HTTPS) and port 22
(SSH) — matching `var.ingress_rules` exactly, generated from the
`dynamic` block rather than written as two separate `ingress {}`
blocks by hand.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **Confirm there's still exactly one security group in state**, not
> two: `terraform state list | grep security_group` shows a single
> `aws_security_group.app` — the `dynamic` block generated two nested
> `ingress` blocks *inside* that one resource, not two resources.

**Verify:**

```
Console → EC2 → Security Groups → cloudnova-app-sg → Inbound rules tab
  → HTTPS (443) from 0.0.0.0/0, SSH (22) from 203.0.113.0/24 — both
    listed as inbound rules on the SAME security group ✅
```

### Step 3 — Apply the decision framework to three new scenarios

| Scenario | `count`, `for_each`, `dynamic`, or single resource? | Why |
|---|---|---|
| 5 identical CloudWatch log groups for 5 microservices with interchangeable names | `count` | Instances are interchangeable; no name carries independent meaning |
| One S3 bucket per AWS region CloudNova operates in | `for_each` (set of region strings) | Each instance has a meaningful, stable identity (the region) |
| A security group needing a caller-supplied number of egress rules, in addition to the ingress rules already built | `dynamic` (a second `dynamic "egress"` block) | Still one resource; the variability is in nested blocks, not whole resources |
| CloudNova's single production VPC | Single resource, no `count`/`for_each`/`dynamic` | There is exactly one; multiplicity constructs exist to avoid repetition, not formalize a singleton |

### Step 4 — Deliberately trigger the mutual-exclusion error

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

Expected:

```
Error: Invalid combination of "count" and "for_each"

  on 04-count-queues.tf line 14, in resource "aws_sqs_queue" "invalid_example":
  14:   for_each = toset(["a", "b"])

The "count" and "for_each" meta-arguments are mutually-exclusive, only
one should be used to be explicit about the number of resources to be
created.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment. The exact wording of this error message has not been
> confirmed against a live `terraform validate` run in this
> environment — treat the surrounding cause/fix explanation as
> reliable, but verify literal wording before quoting it elsewhere.

> **Terraform catches this at `validate` time, before any AWS API
> call** — a static configuration error, not a runtime one. Remove the
> block before continuing; it must not remain in `04-count-queues.tf`.

---

## Cleanup

```bash
terraform destroy
```

Type `yes`. Expected: `Destroy complete! Resources: 9 destroyed.` (3
queues, 3 buckets, 2 IAM users, 1 security group).

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

```bash
aws sqs list-queues --queue-name-prefix cloudnova-notifications-dlq
aws s3 ls | grep cloudnova
aws iam list-users --query "Users[?starts_with(UserName, 'dev-') || starts_with(UserName, 'billing-')].UserName"
aws ec2 describe-security-groups --filters "Name=group-name,Values=cloudnova-app-sg"
```

Expected: all four commands return empty results.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## What You Learned

1. ✅ Created three SQS dead-letter queues using `count` and
   referenced each via `count.index`
2. ✅ Created one S3 bucket per environment and two IAM users using
   `for_each`, converting a list to a set with `toset()` where needed
3. ✅ Collected all three queue ARNs into a single output using a
   splat expression, and verified one specific indexed queue with a
   real send/receive round trip
4. ✅ Built a security group with a `dynamic "ingress"` block,
   confirming it generates multiple nested blocks inside one resource
   — not multiple resources
5. ✅ Applied the `count`/`for_each`/`dynamic`/single-resource decision
   framework to new scenarios, and triggered the `count`+`for_each`
   mutual-exclusion error live

---

## Cert Tips — TA-004 Objectives Covered

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `count` and `count.index` | TA-004 Obj (resource management) | Common exam pattern: "how many resources does this config create?" |
| `for_each` and `each.key`/`each.value` | TA-004 Obj (resource management) | Frequently tested against a map input specifically |
| Splat expression `[*]` | TA-004 Obj 4 (expressions) | Often tested as "what does this output value evaluate to" |
| `dynamic` blocks vs. `for_each` on a resource | TA-004 Obj (resource management) | Common trap — conflating "repeats a block" with "repeats a resource" |
| `count`/`for_each` mutual exclusion | TA-004 Obj (resource management) | Common trap question — expects you to identify the invalid config |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam shows a resource with both `count` and a `for_each`-style map reference | Recognizing this configuration is invalid and would fail `validate` | Assuming Terraform merges the two or that `for_each` "wins" |
| Exam asks for the resource address of the second instance created by `count = 3` | `resource_type.name[1]` (zero-indexed) | Answering `resource_type.name[2]` (treating it as 1-indexed) |
| Exam shows `for_each` over a `list(string)` variable directly | Recognizing this is invalid without `toset()` | Assuming `for_each` accepts lists natively like `count` accepts a number |
| Exam shows a `dynamic` block and asks how many resources exist in state | Recognizing there's still exactly ONE resource — `dynamic` repeats nested blocks, not resources | Assuming a `dynamic` block with `for_each = list of 3` creates 3 resources |

### Exam Task — Write a complete configuration

**Task:** CloudNova needs three things in one configuration: (1) three
identical CloudWatch log groups named `app-log-0` through `app-log-2`
using `count`; (2) one S3 bucket per entry in a map variable
`environments` using `for_each`; (3) a security group with a
`dynamic "ingress"` block driven by a list variable `ingress_rules`.
Write all three from scratch.

**Block types required:** `resource` (×3 — one `count`, one `for_each`,
one with a `dynamic` block), `variable` (×2 — `environments` map,
`ingress_rules` list)

**Official documentation:**
- [Count Meta-Argument](https://developer.hashicorp.com/terraform/language/meta-arguments/count)
- [For_Each Meta-Argument](https://developer.hashicorp.com/terraform/language/meta-arguments/for_each)
- [`dynamic` Blocks](https://developer.hashicorp.com/terraform/language/expressions/dynamic-blocks)

**What to practise:**
1. Open the `dynamic` Blocks page — confirm what the default iterator
   name is when not explicitly renamed via `iterator`
2. Write the configuration from scratch without looking at this
   demo's `.tf` files
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
variable "environments" {
  type = map(string)
  default = {
    dev  = "us-east-2"
    prod = "us-east-2"
  }
}

variable "ingress_rules" {
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = [
    { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  ]
}

resource "aws_cloudwatch_log_group" "app" {
  count = 3                                    # index-based — names are interchangeable
  name  = "app-log-${count.index}"
}

resource "aws_s3_bucket" "env" {
  for_each = var.environments                  # key-based — environment name carries meaning
  bucket   = "cloudnova-${each.key}-assets"
}

resource "aws_security_group" "app" {
  name = "cloudnova-app-sg"

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }
}
```

**Arguments you must know without looking up:**
- `count.index` — zero-based, a common exam trap when asked "what is
  the third instance's address"
- The default `dynamic` block iterator name matches the block's own
  label (`ingress` here) unless renamed via `iterator`

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Error: Invalid for_each argument` | `for_each` value depends on attributes not known until apply | Restructure so `for_each`'s input is a variable, `local`, or data source value known at plan time |
| `for_each` value is a list, not a map or set | A `list(string)`/`list(object(...))` passed directly to `for_each` | Wrap in `toset()` for a plain string list, or convert to a map keyed by a stable field |
| Splat expression returns an empty list unexpectedly | `count`/`for_each` input evaluated to empty | Check the actual value with `terraform console` |
| `dynamic` block generates zero nested blocks | Its `for_each` input is an empty list/map | Confirm the source variable actually has entries — the resource itself still exists even with zero nested blocks |

---

## Break-Fix Scenario

CloudNova's junior engineer introduced four errors while extending this
demo's configuration — one more than the series' usual three, since
this scenario spans both the `count`/`for_each` fundamentals and the
`dynamic` block content merged into this demo. Diagnose using
`terraform validate`/`plan` output alone.

```bash
cd src/break-fix/
terraform init
terraform validate
```

#### `broken.tf` — Four deliberate multiplicity errors

**What this file does in this demo:** a self-contained configuration
with a duplicate-key `for_each` map, `count`+`for_each` on one
resource, `count.index` referenced inside a `for_each` resource, and a
wrong `dynamic` iterator reference — diagnose all four.

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

# Error 1: for_each given a duplicate-key map
resource "aws_s3_bucket" "env" {
  for_each = {
    dev = "us-east-2"
    dev = "us-west-2"
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

# Error 4: wrong dynamic iterator reference after renaming it
resource "aws_security_group" "broken" {
  name = "cloudnova-broken-sg"

  dynamic "ingress" {
    for_each = ["443", "22"]
    iterator = rule
    content {
      from_port = ingress.value # should be rule.value — iterator was renamed
      to_port   = ingress.value
      protocol  = "tcp"
    }
  }
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — duplicate-key map literal**
HCL object literals cannot have duplicate keys — `dev` appears twice.
Caught at parse time, before `for_each` is even evaluated. Fix: rename
one entry to make both keys unique.

**Error 2 — `count` and `for_each` on the same resource**
Terraform rejects this because the two addressing schemes (integer
index vs. arbitrary key) are mutually incompatible. Fix: choose one —
`count = 2` fits here since the queues have no meaningful per-instance
identity.

**Error 3 — `count.index` referenced inside a `for_each` resource**
`count.index` is only defined inside `count`-driven resources; this
resource uses `for_each`, where the equivalent is `each.key`/
`each.value`. Fix: replace `count.index` with `each.key`.

**Error 4 — wrong `dynamic` iterator reference**
The `dynamic "ingress"` block renamed its iterator to `rule` via
`iterator = rule`, but `content {}` still references `ingress.value` —
the default iterator name, which no longer applies once renamed. Fix:
change both `ingress.value` references to `rule.value`.

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

**Q1. When would you choose `count` over `for_each`, and when is that the wrong call?**
`count` fits when instances are truly interchangeable and position carries no meaning. It's the wrong call the moment an instance has a real identity worth preserving, because removing an item from the middle of a `count`-driven list shifts every subsequent index, and Terraform plans to destroy and recreate every instance after the removed one — even though their actual configuration didn't change. `for_each` avoids this since each instance is addressed by its own stable key.

**Q2. How do you explain the difference between `for_each` on a resource and a `dynamic` block to someone who's only seen one of the two?**
`for_each` on a resource block creates multiple independent state entries — you can destroy one without touching the others. A `dynamic` block repeats a *nested configuration block inside a single resource* — there's still exactly one resource in state; you're just avoiding writing out N copies of a nested block (like `ingress {}`) by hand. If someone says "I used `dynamic` to create three separate S3 buckets," that's not possible — `dynamic` can't create separate top-level resources, only repeated nested blocks within one.

**Q3. A teammate's PR uses `for_each = var.subnet_ids` where `subnet_ids` is `type = list(string)`. What's your review comment?**
It fails validation — `for_each` requires a map or a set, not a list. The review comment: wrap it as `toset(var.subnet_ids)`, and flag that if `subnet_ids` can ever contain duplicates, `toset()` will silently collapse them — worth confirming that's acceptable.

**Q4. Why does Terraform refuse to let you use `count` and `for_each` together instead of just picking one automatically?**
Because "pick one automatically" would be a silent, implicit decision about addressing semantics — and Terraform's design philosophy favors explicit, predictable state addressing. If it silently preferred `for_each`, someone debugging why their `count.index` references broke would have no clear signal why; failing validation immediately, with both meta-arguments visible in the error, surfaces the actual problem at the point of authoring.

---

## Key Takeaways

1. **`count` addresses instances by position, `for_each` addresses
   them by key.** Choosing `count` for something with real per-instance
   identity sets up the reordering-replacement trap covered fully in
   Demo 11.

2. **`for_each` requires a map or a set — never a plain list.** A
   `list(string)` variable must go through `toset()` first.

3. **`count.index` only exists inside `count`-driven resources;
   `each.key`/`each.value` only exist inside `for_each`-driven ones.**
   Mixing them up produces an "undeclared reference" error.

4. **`count` and `for_each` can never coexist on one resource block.**
   Terraform rejects this at validation time — there is no
   "for_each wins" fallback.

5. **`for_each` on a resource and a `dynamic` block are not the same
   tool.** `for_each` creates multiple independent state entries for a
   whole resource; `dynamic` repeats one nested block inside a single
   resource, which still has exactly one state entry.

6. **Splat expressions are the terse form of a `for` expression for
   "one unmodified attribute from every instance."** Reach for a full
   `for` expression the moment you need filtering or transformation.

> **Demo scope:** Primary concept: resource and block multiplicity —
> `count`, `for_each`, and `dynamic`, taught together so their
> contrast is immediate. Supporting concepts: `toset()`, splat
> expressions, `data.aws_vpc`, and the decision framework for choosing
> between all three (plus a single resource).
> Estimated completion time: 45 minutes (reading + hands-on + verification).
> Checkpoints: 3 natural stopping points (end of Part A, end of Part B,
> end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `count.index` | Zero-based index of the current instance in a `count`-driven resource |
| `each.key` / `each.value` | Current key/value of the current instance in a `for_each`-driven resource |
| `toset(list)` | Converts a list to a set — required for `for_each` on a plain list |
| `resource[*].attr` | Splat expression — collects one attribute across every instance |
| `terraform state list \| grep TYPE` | Confirms how many actual resources exist vs. how many nested blocks a `dynamic` block generated |
| `aws sqs send-message` / `receive-message` | Verifies a specific, indexed queue round-trips a real message |

---

## Next Demo

**Demo 11 — State Addressing and Multiplicity Migration:** the exact
mechanics behind `resource[0]` vs. `resource["key"]` in state, the
`count` mid-list-removal replacement trap demonstrated live against
this demo's DLQ queues, migrating a resource from `count` to `for_each`
using the `moved` block without destroy/recreate, and
`terraform state list` index/key filtering.

---

## Appendix — Anki Cards

**10-multiplicity-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::10-multiplicity
#separator:Comma
#columns:Front,Back,Tags
"You need 3 identical CloudWatch log groups where none has a meaningful name beyond being 'one of three.' Which meta-argument, and how do you build a unique name?","Use count = 3. Build the name with count.index, e.g. name = 'app-log-${count.index}' — produces app-log-0, app-log-1, app-log-2 (zero-indexed).","demo10,count,ta004"
"You write for_each = var.subnet_ids where subnet_ids is list(string). What happens on terraform validate?","It fails. for_each requires a map or a set, not a list. Fix: wrap it as toset(var.subnet_ids).","demo10,for_each,ta004"
"Inside a for_each-driven resource, what are the two expressions for the current instance's key and value?","each.key and each.value. On a set (via toset()), each.value is always identical to each.key since a set has no separate value component.","demo10,for_each,ta004"
"Inside a count-driven resource, what expression gives the current instance's position, and is it zero- or one-indexed?","count.index — zero-indexed. The first instance is count.index == 0.","demo10,count,ta004"
"A resource block has both count = 2 and for_each = toset(['a','b']). What happens?","terraform validate fails — count and for_each are mutually exclusive on a single resource block. Terraform cannot reconcile integer-index addressing with key-based addressing at the same time.","demo10,count,for_each,break-fix,ta004"
"What is the key structural difference between for_each on a resource block and a dynamic block inside a resource?","for_each on a resource creates multiple independent state entries. A dynamic block repeats a nested configuration block inside a single resource — there is still exactly one state entry, regardless of how many nested blocks are generated.","demo10,dynamic,for_each,ta004"
"A dynamic block's iterator is renamed via iterator = rule, but content {} still references ingress.value. What happens?","An error — once the iterator is renamed, the default name (matching the block's own label, e.g. ingress) no longer applies. All references inside content {} must use the new iterator name (rule.value), not the old default.","demo10,dynamic,break-fix"
"How do you collect the ARN of every instance of a count-driven aws_sqs_queue into a single list, without a for expression?","A splat expression: aws_sqs_queue.dlq[*].arn — returns a list of every instance's arn attribute in index order.","demo10,splat,ta004"
"On a for_each resource, does a splat expression (resource[*].attr) return results keyed by each.key?","No — splat on a for_each resource returns values in map-iteration order with no keys attached. Use a for expression instead if you need the key: { for k, v in resource : k => v.attr }.","demo10,splat,for_each"
"CloudNova needs one S3 bucket per environment with a meaningful, permanent name. Why is for_each better than count here?","for_each addresses each bucket by environment name (a stable identity), so adding/removing an environment doesn't shift any other bucket's address. count addresses by position — removing the middle one out of three would shift indexes and could cause destroy/recreate on buckets that didn't actually change.","demo10,for_each,count,decision"
"What's the fix for a for_each map literal with the same key defined twice, e.g. { dev = 'a', dev = 'b' }?","This is an HCL syntax error, not for_each-specific — object literals cannot have duplicate keys. Rename one of the keys so both are unique.","demo10,for_each,break-fix"
```

---

## Appendix — Quiz

**10-multiplicity-quiz.md:**

```markdown
# Quiz — Demo 10: Multiplicity — count, for_each, and dynamic

> One correct answer per question unless stated otherwise.
> Target: 80% or above before moving to Demo 11.
> TA-004 exam style.

---

**Q1.** You need 4 identical CloudWatch log groups where no instance
has meaning beyond "one of four." What's the best construct?

A. `for_each` over a set of 4 arbitrary strings
B. `count = 4`
C. Four separate resource blocks
D. A `dynamic` block

<details>
<summary>Answer</summary>

**B.** `count` fits exactly this case — N interchangeable instances,
no meaningful per-instance identity. **A** works too but adds
unnecessary indirection (inventing 4 arbitrary keys). **C** is the
repetition this feature exists to eliminate. **D** is wrong — `dynamic`
repeats nested blocks within one resource, not whole resources.

</details>

---

**Q2.** A resource block has `for_each = var.regions` where `regions`
is `type = list(string)`. What happens on `terraform validate`?

A. It works — `for_each` accepts lists directly
B. It fails — `for_each` requires a map or a set
C. It works but silently treats the list as a set
D. It works only if the list has no duplicates

<details>
<summary>Answer</summary>

**B.** `for_each` requires a map or a set, never a plain list,
regardless of duplicates. Fix: wrap in `toset()`. **A**, **C**, and
**D** are all wrong — there's no automatic list acceptance under any
condition.

</details>

---

**Q3.** What is the key structural difference between `for_each` on a
resource block and a `dynamic` block inside a resource?

A. There is no difference — both create multiple resource instances
B. `for_each` on a resource creates multiple independent state
   entries; `dynamic` repeats a nested block within one resource that
   remains one state entry
C. `dynamic` blocks can only be used with `count`, never `for_each`
D. `for_each` can only be used inside `dynamic` blocks

<details>
<summary>Answer</summary>

**B.** This is the core distinction this demo teaches. **A** is
wrong — this is precisely the distinction being tested. **C** is
wrong — `dynamic` blocks use their own `for_each` argument, unrelated
to a resource's `count`. **D** is wrong — they're independent
constructs; neither requires the other.

</details>

---

**Q4.** A resource block is written with both `count = 2` and
`for_each = toset(["a","b"])`. What is the result?

A. Terraform creates 2 instances, using `for_each`'s values as names
B. Terraform creates 4 instances (2 × 2)
C. `terraform validate` fails — the two meta-arguments are mutually exclusive
D. `for_each` is silently ignored and `count` wins

<details>
<summary>Answer</summary>

**C.** Terraform rejects this at validation time — no merge or
precedence behavior exists. **A**, **B**, and **D** are all wrong —
there is no combination or fallback logic; the configuration is simply
invalid.

</details>

---

**Q5.** What does `aws_s3_bucket.env[*].arn` return, if `env` is a
`for_each`-driven resource over a 3-entry map?

A. A map of key → arn
B. A list of the 3 ARNs, in map-iteration order, with no keys attached
C. A single ARN — the first instance only
D. An error — splat doesn't work on `for_each` resources

<details>
<summary>Answer</summary>

**B.** Splat on a `for_each` resource still returns a list, not keyed
by `each.key`. If you need the keys, use a `for` expression instead.
**A** is wrong — splat never returns a map. **C** is wrong — splat
returns every instance's value, not just one. **D** is wrong — splat
works fine on `for_each` resources, just without keys attached.

</details>

---

**Q6.** A `dynamic "ingress"` block's iterator is renamed via `iterator
= rule`. Which reference is correct inside `content {}`?

A. `ingress.value` — the default name always still works
B. `rule.value` — the renamed iterator must be used
C. Either works interchangeably
D. `dynamic.value`

<details>
<summary>Answer</summary>

**B.** Once renamed via `iterator = rule`, the default name (`ingress`)
no longer applies — all references inside `content {}` must use the
new name. **A** is wrong — this is exactly Break-Fix Error 4; using
the old default after renaming produces an error. **C** is wrong —
only the renamed iterator works after `iterator` is set. **D** is
wrong — `dynamic` itself is never a valid reference name.

</details>

---

**Q7.** CloudNova needs a bucket per environment where the environment
name itself is meaningful and must be stable if environments are added
or removed later. Which is the better choice?

A. `count`, because it's simpler syntax
B. `for_each`, because each instance's identity doesn't depend on the
   position of other instances
C. Either works identically for this case
D. A `dynamic` block

<details>
<summary>Answer</summary>

**B.** This is exactly the scenario `for_each` is designed for.
**A** would work mechanically but risks the reordering-replacement
trap the moment a middle environment is removed (full mechanics in
Demo 11). **C** is wrong — `count` risks unnecessary
destroy/recreate on unrelated instances. **D** is wrong — `dynamic`
repeats nested blocks, not whole resources; it doesn't apply to
creating multiple S3 buckets at all.

</details>

---

**Q8.** How many `aws_security_group` resources exist in state after
applying a security group with a `dynamic "ingress"` block whose
`for_each` has 5 entries?

A. 5 — one per ingress rule
B. 1 — the `dynamic` block only generates nested blocks, not resources
C. 6 — the security group plus 5 ingress resources
D. 0 until the ingress rules are individually approved

<details>
<summary>Answer</summary>

**B.** Exactly one security group exists in state, regardless of how
many nested `ingress` blocks the `dynamic` block generates inside it.
**A** and **C** are wrong — `dynamic` never creates separate top-level
resources. **D** is wrong — there's no such approval mechanism; the
security group (with all its generated ingress blocks) is created in
one `apply`.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 11 |
| 7/8 | Review the wrong answer, then proceed |
| 6/8 | Re-read the relevant section, retry those questions |
| Below 6/8 | Re-read the full demo and redo the walkthrough before proceeding |
```