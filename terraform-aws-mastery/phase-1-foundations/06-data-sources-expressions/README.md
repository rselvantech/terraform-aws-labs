# Demo 06 — Data Sources and Expressions: Read and Transform

---

## Overview

Every demo so far has created resources from scratch. In practice, most
real Terraform configurations work alongside infrastructure that already
exists — a VPC created by the network team, the latest AMI published by
AWS, an S3 bucket created before Terraform adoption. `data` sources are
how Terraform reads that existing infrastructure without managing it.

Alongside data sources, this demo covers HCL's expression and
transformation primitives: `for` expressions that transform lists and
maps, and `dynamic` blocks that generate nested configuration blocks
programmatically.

**Real-world scenario — CloudNova:**
The security team has defined a set of S3 bucket policies that all
application buckets must use. Rather than hardcoding policy ARNs, the
configuration reads them from IAM using a data source. The platform team
also needs to create log groups for multiple services from a single
variable — a perfect case for `for` expressions and `for_each` at the
data-source level.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Data Sources                                                  │
│  data.aws_caller_identity   |   data.aws_iam_policy                    │
│  data.aws_s3_bucket   |   filtering with argument blocks               │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — for Expressions                                               │
│  List → list   |   List → map   |   Map → map                          │
│  Filtering with if   |   toset(), keys(), values(), zipmap()            │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — dynamic Blocks                                                │
│  Conditionally generating nested blocks   |   iterator argument        │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- `data` block — purpose, when to use vs. `resource`, how it differs
  from `resource` in the dependency graph
- `data.aws_caller_identity` — current account ID and ARN
- `data.aws_iam_policy` — reading an existing managed IAM policy by ARN
- `data.aws_s3_bucket` — reading an existing S3 bucket's attributes
- Filtering data sources with argument blocks
- `for` expressions: list → list, list → map, map → map
- Filtering with `if` inside `for`
- Built-in functions used with expressions: `toset()`, `keys()`,
  `values()`, `zipmap()`, `lookup()`, `flatten()`
- `dynamic` blocks: generating repeated nested blocks programmatically
- The `iterator` argument on `dynamic` blocks

---

## Prerequisites

### Knowledge
- Demo 05 completed — variables, locals, outputs, `jsonencode()`,
  `try()`, `coalesce()`, `merge()`

### Required Tools

| Tool | Minimum version | Install | Verify |
|---|---|---|---|
| Terraform CLI | `>= 1.15.0` | [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install) | `terraform version` |
| AWS CLI | `>= 2.x` | [docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | `aws --version` |
| Git | Any recent | Pre-installed on most systems | `git --version` |

### Verify AWS Account and Permissions

```bash
aws sts get-caller-identity --profile default
aws configure get region --profile default
```

**Required permissions for this demo:**

```
iam:GetPolicy, iam:GetPolicyVersion, iam:ListPolicies
s3:GetBucketLocation, s3:GetBucketVersioning, s3:GetEncryptionConfiguration
s3:GetBucketPublicAccessBlock, s3:ListBucket
logs:CreateLogGroup, logs:DeleteLogGroup, logs:DescribeLogGroups
logs:PutRetentionPolicy, logs:ListTagsForResource
```

> For a learning account, `IAMReadOnlyAccess`, `AmazonS3ReadOnlyAccess`,
> and `CloudWatchLogsFullAccess` managed policies cover the above.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain when to use a `data` block vs. a `resource` block
2. ✅ Read existing AWS infrastructure using `data` sources with and
   without filtering argument blocks
3. ✅ Write `for` expressions that transform lists to lists, lists to
   maps, and maps to maps
4. ✅ Filter collections inside `for` expressions using `if`
5. ✅ Use `toset()`, `keys()`, `values()`, `zipmap()`, `lookup()`, and
   `flatten()` in expression contexts
6. ✅ Generate repeated nested configuration blocks using `dynamic`
7. ✅ Use the `iterator` argument to rename the `dynamic` block's
   iteration variable

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| `data` sources | Read-only API calls | **~$0.00** | S3/IAM reads are effectively free |
| CloudWatch Log Groups | First 5GB/month ingest free | **$0.00** | No logs ingested in this demo |
| `aws_cloudwatch_log_group` | Free to create | **$0.00** | Only retention metadata set |
| **Session total** | | **~$0.00** | |

---

## Directory Structure

```
06-data-sources-expressions/
├── README.md
├── 06-data-sources-expressions-anki.csv
├── 06-data-sources-expressions-quiz.md
└── src/
    ├── 01-versions.tf      # terraform block + provider version constraints
    ├── 02-provider.tf      # AWS provider: region, profile, default_tags
    ├── 03-variables.tf     # input variables
    ├── 04-locals.tf        # for expressions + computed values
    ├── 05-data.tf          # all data sources
    ├── 06-main.tf          # CloudWatch log groups + dynamic blocks
    └── 07-outputs.tf       # outputs exposing data source and expression results
```

---

## Recall Check — Demo 05

Answer from memory before reading anything new:

1. What is the distinction test for deciding whether a value should be
   a `variable` or a `local`?
2. `sensitive = true` on a variable redacts it from terminal output.
   Does it also prevent the value from being written to
   `terraform.tfstate`?
3. A `for` expression (not yet formally taught) looks like
   `[for s in var.services : upper(s)]`. Based on the syntax alone,
   what do you think it produces?

<details>
<summary>Answers</summary>

1. If you would ever want to override the value from outside the
   configuration (per environment, per engineer, per run) — it's a
   variable. If it's always derived from other values in the
   configuration and never needs external input — it's a local.
2. No. `sensitive = true` only redacts from terminal/log output. The
   value is still written to `terraform.tfstate` in plaintext. For
   never-written-to-state behavior, use `ephemeral = true`.
3. A list of uppercase strings — one for each element of
   `var.services`, with `upper()` applied to each. (Demo 06 teaches
   `for` expressions formally — if you got the general shape right,
   that's the goal of this recall question.)

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `data` block | Configuration block | Reads existing infrastructure without managing it |
| `data.aws_caller_identity` | Data source | Current AWS account ID, ARN, and user ID |
| `data.aws_iam_policy` | Data source | Reads an existing managed IAM policy by ARN or name |
| `data.aws_s3_bucket` | Data source | Reads an existing S3 bucket's attributes |
| `for` expression (list output) | HCL expression | Transforms a list into a new list |
| `for` expression (map output) | HCL expression | Transforms a collection into a map |
| `if` filter inside `for` | HCL expression | Filters collection elements during transformation |
| `toset()` | Built-in function | Converts a list to a set (removes duplicates, unordered) |
| `keys()` / `values()` | Built-in functions | Extracts keys or values from a map as a list |
| `zipmap()` | Built-in function | Combines two lists into a map (first = keys, second = values) |
| `lookup()` | Built-in function | Reads a map value by key with a fallback default |
| `flatten()` | Built-in function | Collapses a list of lists into a single flat list |
| `dynamic` block | Configuration construct | Generates repeated nested blocks from a collection |
| `iterator` argument | `dynamic` argument | Renames the iteration variable inside a `dynamic` block |
| `aws_cloudwatch_log_group` | Resource | CloudWatch Log Group for centralised logging |

---

### Detailed Explanation of New Constructs

#### `data` Blocks — Purpose and Behavior

A `data` block reads existing infrastructure that Terraform did not
create and does not manage. It makes zero changes to that infrastructure
— it only reads.

```hcl
# resource block — Terraform creates, manages, and can destroy this
resource "aws_s3_bucket" "app" {
  bucket = "cloudnova-dev-app-a1b2c3d4"
}

# data block — Terraform reads this; it was created elsewhere and
# Terraform cannot destroy it via normal workflow
data "aws_s3_bucket" "existing" {
  bucket = "cloudnova-legacy-uploads-xxxxxxxx"
}
```

**When to use `data` vs `resource`:**

| Use `resource` when... | Use `data` when... |
|---|---|
| Terraform should own the full lifecycle (create/update/destroy) | The resource exists outside this configuration |
| The resource doesn't exist yet | You only need to read attributes (ARN, ID, region) |
| You need to track it in state for drift detection | The resource is managed by another team or config |
| Recreating it from scratch is acceptable | Recreating it would be destructive or disruptive |

**How `data` sources appear in the dependency graph:**

Data sources are read during the `refresh` step of `plan` — the same
phase where Terraform reads managed resource state. They produce values
that other resources can reference, creating implicit dependencies just
like resource-to-resource references. If a resource references
`data.aws_s3_bucket.existing.arn`, Terraform reads that data source
before computing the resource's plan.

> **`data` sources and state:** data source results are stored in state
> (under `"mode": "data"`) but are never managed — Terraform refreshes
> them on every `plan` because their attributes might have changed
> externally. They are never destroyed by `terraform destroy`.

---

#### Commonly Used Data Sources in This Demo

**`data.aws_caller_identity`** — reads the currently authenticated AWS
identity. No arguments required.

```hcl
data "aws_caller_identity" "current" {}
```

Available attributes:
- `.account_id` — the 12-digit AWS account ID
- `.arn` — the ARN of the authenticated identity
- `.user_id` — the unique ID of the authenticated identity

**`data.aws_iam_policy`** — reads an existing managed IAM policy.

```hcl
data "aws_iam_policy" "readonly" {
  arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
```

Available attributes: `.arn`, `.name`, `.id`, `.policy` (the full
JSON policy document), `.policy_id`, `.tags`.

**`data.aws_s3_bucket`** — reads an existing S3 bucket's metadata.

```hcl
data "aws_s3_bucket" "existing" {
  bucket = "cloudnova-legacy-uploads-xxxxxxxx"
}
```

Available attributes: `.arn`, `.bucket`, `.bucket_domain_name`,
`.bucket_regional_domain_name`, `.hosted_zone_id`, `.region`.

> **Important distinction:** `data.aws_s3_bucket` only reads bucket
> metadata — it does NOT read object contents, versioning status,
> encryption config, or public access block settings. Those settings
> each have their own separate data sources
> (`aws_s3_bucket_versioning`, etc.).

---

#### `for` Expressions — Full Syntax

A `for` expression transforms one collection into another. The output
type depends on the surrounding brackets:

- `[for ... : ...]` — produces a **list**
- `{for ... : ... => ...}` — produces a **map**

---

**List → list transformation:**

```hcl
# Input:  ["api", "worker", "scheduler"]
# Output: ["cloudnova-dev-api", "cloudnova-dev-worker", "cloudnova-dev-scheduler"]

locals {
  prefixed_services = [
    for service in var.services : "${var.project}-${var.environment}-${service}"
  ]
}
```

Syntax breakdown:
```
[for <element_var> in <collection> : <expression>]
      ↑                ↑               ↑
  loop variable    input list      output value per element
```

---

**List → map transformation:**

```hcl
# Input:  ["api", "worker", "scheduler"]
# Output: { "api" = "/cloudnova/dev/api", "worker" = "/cloudnova/dev/worker", ... }

locals {
  log_group_paths = {
    for service in var.services :
    service => "/cloudnova/${var.environment}/${service}"
  }
}
```

Syntax breakdown:
```
{for <element_var> in <collection> : <key_expr> => <value_expr>}
```

---

**Map → map transformation:**

```hcl
# Input:  { "api" = 7, "worker" = 14, "scheduler" = 30 }
# Output: { "api" = 7, "scheduler" = 30 }   (filtered to <= 14)

locals {
  short_retention = {
    for name, days in var.service_retention :
    name => days
    if days <= 14
  }
}
```

When iterating a map, use two variables:
```
{for <key_var>, <value_var> in <map> : <key_expr> => <value_expr> [if <condition>]}
```

---

**Filtering with `if`:**

The `if` clause filters elements — only elements where the condition is
`true` are included in the output:

```hcl
# Only include services that are "production-grade"
locals {
  prod_services = [
    for service in var.services : service
    if contains(var.prod_services, service)
  ]
}
```

---

#### Built-in Functions Used With Expressions

These functions are used naturally inside `for` expressions and locals
throughout this demo.

| Function | What it does | Example |
|---|---|---|
| `toset(list)` | Converts a list to a set — removes duplicates, loses ordering | `toset(["a","b","a"])` → `toset(["a","b"])` |
| `keys(map)` | Returns all keys of a map as a list | `keys({a=1, b=2})` → `["a","b"]` |
| `values(map)` | Returns all values of a map as a list | `values({a=1, b=2})` → `[1,2]` |
| `zipmap(keys, values)` | Combines two lists into a map | `zipmap(["a","b"],[1,2])` → `{a=1, b=2}` |
| `lookup(map, key, default)` | Reads a map value by key; returns default if key absent | `lookup({a=1}, "b", 0)` → `0` |
| `flatten(list_of_lists)` | Collapses nested lists into one flat list | `flatten([[1,2],[3]])` → `[1,2,3]` |

> **`toset()` vs list — when it matters:** `for_each` (covered in
> Demo 07) requires a set or map, not a list. `toset()` converts a
> list of strings to a set, removing duplicates — a common pre-step
> before `for_each`. Sets are unordered, so if order matters, keep a
> list.

---

#### `dynamic` Blocks — Generating Nested Blocks Programmatically

Some Terraform resources have optional nested blocks that can appear
zero or more times — for example, `ingress` rules in a security group,
or `metric_transformation` in a CloudWatch metric filter. Writing each
block by hand is verbose and repetitive. `dynamic` generates them from
a collection.

```hcl
# Without dynamic — repetitive, hardcoded
resource "aws_cloudwatch_log_group" "services" {
  name = "/cloudnova/dev/api"

  # If you needed per-tag-key blocks (hypothetical example to show dynamic):
  tag_block { key = "Service" value = "api" }
  tag_block { key = "Env"     value = "dev" }
}

# With dynamic — generated from a map variable
resource "aws_security_group" "app" {
  name = "cloudnova-dev-app-sg"

  dynamic "ingress" {
    for_each = var.ingress_rules   # map or set to iterate
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }
}
```

**`dynamic` block syntax:**

```hcl
dynamic "<block_type>" {
  for_each = <collection>        # required — map, set, or list
  iterator = <optional_alias>    # optional — renames the iteration variable
  content {
    # block body — uses <block_type>.<attribute> or <alias>.<attribute>
    # to reference the current element
  }
}
```

**The `iterator` argument:**

By default, inside `content {}`, the current element is referenced as
`<block_type>.key` and `<block_type>.value`. When the block type is
long or conflicts with another name, `iterator` renames it:

```hcl
dynamic "ingress" {
  for_each = var.ingress_rules
  iterator = rule              # now use rule.key and rule.value instead of ingress.key
  content {
    from_port   = rule.value.from_port
    to_port     = rule.value.to_port
    protocol    = rule.value.protocol
    cidr_blocks = rule.value.cidr_blocks
  }
}
```

**When NOT to use `dynamic`:** dynamic blocks make configuration harder
to read and harder to review in plan output — the generated blocks don't
show up as distinct named resources. Use `dynamic` when the number of
nested blocks is genuinely variable (driven by a variable or data
source), not just because you have three ingress rules and want to save
a few lines. For a fixed set of nested blocks, write them explicitly.

---

#### `aws_cloudwatch_log_group`

CloudWatch Log Groups are containers for log streams — application logs,
Lambda function output, ECS container logs, and VPC flow logs all land
in log groups.

| Argument | Required | Description |
|---|---|---|
| `name` | Yes | Log group name. Convention: `/project/environment/service` |
| `retention_in_days` | No (default: never expire) | How long to retain log entries. Common values: 7, 14, 30, 60, 90, 180, 365 |
| `tags` | No | Resource tags |

> **Cost note:** CloudWatch Logs charges for ingested data ($0.50/GB
> in us-east-2) and storage ($0.03/GB/month beyond the free tier). In
> this demo, no logs are ingested — the group is created but empty, so
> the cost is $0.00.

## Lab Step-by-Step Guide

---

## Part A — Data Sources: Read Existing Infrastructure

**What you accomplish in Part A:** read current account identity, an
existing managed IAM policy, and the legacy S3 bucket from Demo 04 using
data sources — without creating or modifying anything in AWS.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/06-data-sources-expressions/src
```

### Step 2 — Create `01-versions.tf`

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

### Step 3 — Create `02-provider.tf`

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

### Step 4 — Create `03-variables.tf`

**03-variables.tf:**

```hcl
variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "aws_profile" {
  type    = string
  default = "default"
}

variable "project" {
  type    = string
  default = "cloudnova"
}

variable "environment" {
  type    = string
  default = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "demo" {
  type    = string
  default = "06-data-sources-expressions"
}

variable "services" {
  type        = list(string)
  description = "List of service names to create log groups for"
  default     = ["api", "worker", "scheduler"]
}

variable "service_retention" {
  type        = map(number)
  description = "Retention in days per service — any service not listed uses the default"
  default = {
    api       = 30
    worker    = 14
    scheduler = 7
  }
}

variable "default_retention_days" {
  type        = number
  description = "Default log retention in days for services not in service_retention"
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.default_retention_days)
    error_message = "default_retention_days must be a valid CloudWatch Logs retention value."
  }
}

variable "legacy_bucket_name" {
  type        = string
  description = "Name of the existing legacy S3 bucket to read (from Demo 04)"
  default     = ""   # empty = skip the s3 data source
}
```

---

### Step 5 — Create `05-data.tf`

**What this file does:** declares all data sources used in this demo.
Data sources are conventionally separated into their own file since they
represent reads of existing infrastructure, not new resources.

**05-data.tf:**

```hcl
# ── Current AWS identity ───────────────────────────────────────────────────
# No arguments — reads whoever is currently authenticated
data "aws_caller_identity" "current" {}

# ── AWS-managed IAM policies ───────────────────────────────────────────────
# Reading the AWS-managed ReadOnlyAccess policy
# arn:aws:iam::aws:policy/ prefix = AWS-managed (not account-specific)
data "aws_iam_policy" "readonly" {
  arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Reading the CloudWatchReadOnlyAccess policy — used later in outputs
data "aws_iam_policy" "cloudwatch_readonly" {
  arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# ── Existing S3 bucket (optional — only if legacy_bucket_name is set) ─────
# count = 0 means the data source is not read when legacy_bucket_name is ""
# count with data sources works the same as with resources
data "aws_s3_bucket" "legacy" {
  count  = var.legacy_bucket_name != "" ? 1 : 0
  bucket = var.legacy_bucket_name
}
```

> **`count` on a data source:** data sources support the same
> `count` and `for_each` meta-arguments as resources. `count = 0`
> means the data source is never read — useful for making optional data
> lookups conditional. When `count = 1`, the data source is referenced
> as `data.aws_s3_bucket.legacy[0]`. Demo 07 covers `count` and
> `for_each` in full depth.

---

### Step 6 — Create `04-locals.tf`

**What this file does:** builds all computed values using `for`
expressions, built-in functions, and the data source attributes read
in `05-data.tf`.

**04-locals.tf:**

```hcl
locals {
  # ── Common tags ──────────────────────────────────────────────────────────
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Demo        = var.demo
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
    AccountId   = data.aws_caller_identity.current.account_id
  }

  # ── for expressions: list → list ─────────────────────────────────────────
  # Produces: ["/cloudnova/dev/api", "/cloudnova/dev/worker", ...]
  log_group_names = [
    for service in var.services :
    "/${var.project}/${var.environment}/${service}"
  ]

  # ── for expressions: list → map ──────────────────────────────────────────
  # Produces: { "api" = "/cloudnova/dev/api", "worker" = "...", ... }
  # Keys: service names   Values: log group paths
  log_group_map = {
    for service in var.services :
    service => "/${var.project}/${var.environment}/${service}"
  }

  # ── for expressions: map → map with lookup() ─────────────────────────────
  # For each service, look up its retention days from var.service_retention
  # If not found, fall back to var.default_retention_days
  service_retention_resolved = {
    for service in var.services :
    service => lookup(var.service_retention, service, var.default_retention_days)
  }

  # ── for expressions: filtering with if ───────────────────────────────────
  # Only services with retention > 14 days (longer-lived logs)
  long_retention_services = [
    for service, days in local.service_retention_resolved :
    service
    if days > 14
  ]

  # ── flatten() — collapse list of lists ───────────────────────────────────
  # Produces a flat list of all policy ARNs being read in this demo
  policy_arns = flatten([
    [data.aws_iam_policy.readonly.arn],
    [data.aws_iam_policy.cloudwatch_readonly.arn],
  ])

  # ── zipmap() — combine two lists into a map ───────────────────────────────
  # Pairs service names with their log group paths
  service_to_log_group = zipmap(
    var.services,
    local.log_group_names
  )

  # ── keys() and values() ───────────────────────────────────────────────────
  service_names      = keys(local.service_retention_resolved)
  retention_values   = values(local.service_retention_resolved)
}
```

---

### Step 7 — Create `06-main.tf`

**06-main.tf:**

```hcl
# Creates one CloudWatch Log Group per service
# Uses for_each with the log_group_map local (map[service → path])
# Demo 07 covers for_each in full depth — this is a preview
resource "aws_cloudwatch_log_group" "services" {
  for_each = local.log_group_map

  name              = each.value
  retention_in_days = local.service_retention_resolved[each.key]

  tags = {
    Service = each.key
  }
}
```

---

### Step 8 — Create `07-outputs.tf`

**07-outputs.tf:**

```hcl
# Data source results
output "current_account_id" {
  description = "AWS account ID of the currently authenticated identity"
  value       = data.aws_caller_identity.current.account_id
}

output "current_caller_arn" {
  description = "ARN of the currently authenticated identity"
  value       = data.aws_caller_identity.current.arn
}

output "readonly_policy_arn" {
  description = "ARN of the AWS-managed ReadOnlyAccess policy"
  value       = data.aws_iam_policy.readonly.arn
}

# for expression results
output "log_group_names" {
  description = "List of log group names (list → list for expression)"
  value       = local.log_group_names
}

output "log_group_map" {
  description = "Map of service → log group path (list → map for expression)"
  value       = local.log_group_map
}

output "service_retention_resolved" {
  description = "Resolved retention days per service (map → map with lookup)"
  value       = local.service_retention_resolved
}

output "long_retention_services" {
  description = "Services with retention > 14 days (filtered for expression)"
  value       = local.long_retention_services
}

output "service_to_log_group" {
  description = "Service name → log group path (zipmap result)"
  value       = local.service_to_log_group
}

output "policy_arns" {
  description = "Flat list of all policy ARNs (flatten result)"
  value       = local.policy_arns
}

output "legacy_bucket_region" {
  description = "Region of the legacy S3 bucket (empty if not provided)"
  value       = var.legacy_bucket_name != "" ? data.aws_s3_bucket.legacy[0].region : "not read"
}
```

---

### Step 9 — Initialise and apply

```bash
terraform init
terraform validate
terraform fmt -recursive
terraform apply
```

Type `yes`. Expected output (abbreviated):

```
data.aws_caller_identity.current: Reading...
data.aws_iam_policy.readonly: Reading...
data.aws_iam_policy.cloudwatch_readonly: Reading...
data.aws_caller_identity.current: Read complete after 0s
data.aws_iam_policy.readonly: Read complete after 1s
data.aws_iam_policy.cloudwatch_readonly: Read complete after 1s

aws_cloudwatch_log_group.services["api"]: Creating...
aws_cloudwatch_log_group.services["scheduler"]: Creating...
aws_cloudwatch_log_group.services["worker"]: Creating...
aws_cloudwatch_log_group.services["api"]: Creation complete after 1s
aws_cloudwatch_log_group.services["scheduler"]: Creation complete after 1s
aws_cloudwatch_log_group.services["worker"]: Creation complete after 1s

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

current_account_id         = "163125980376"
current_caller_arn         = "arn:aws:iam::163125980376:user/test"
log_group_map              = {
  "api"       = "/cloudnova/dev/api"
  "scheduler" = "/cloudnova/dev/scheduler"
  "worker"    = "/cloudnova/dev/worker"
}
log_group_names            = [
  "/cloudnova/dev/api",
  "/cloudnova/dev/scheduler",
  "/cloudnova/dev/worker",
]
long_retention_services    = ["api"]
policy_arns                = [
  "arn:aws:iam::aws:policy/ReadOnlyAccess",
  "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess",
]
service_retention_resolved = {
  "api"       = 30
  "scheduler" = 7
  "worker"    = 14
}
service_to_log_group       = {
  "api"       = "/cloudnova/dev/api"
  "scheduler" = "/cloudnova/dev/scheduler"
  "worker"    = "/cloudnova/dev/worker"
}
```

### Step 10 — Verify in Console

```
Console → CloudWatch → Log groups
  → /cloudnova/dev/api       — Retention: 30 days ✅
  → /cloudnova/dev/worker    — Retention: 14 days ✅
  → /cloudnova/dev/scheduler — Retention: 7 days ✅
```

### Step 11 — Test with optional legacy bucket

If you have the bucket from Demo 04 still in your account:

```bash
terraform apply -var="legacy_bucket_name=cloudnova-legacy-uploads-xxxxxxxx"
```

Expected additional output:

```
data.aws_s3_bucket.legacy[0]: Reading...
data.aws_s3_bucket.legacy[0]: Read complete after 0s

legacy_bucket_region = "us-east-2"
```

> **`data.aws_s3_bucket.legacy[0]`:** the `[0]` index is because this
> data source uses `count` — when `count = 1`, it's addressed with
> `[0]`. When `count = 0`, it doesn't exist in state at all.

### Step 12 — Explore `for` expressions interactively

```bash
terraform console
```

```
> [for s in ["api", "worker", "scheduler"] : upper(s)]
[
  "API",
  "WORKER",
  "SCHEDULER",
]

> {for s in ["api", "worker"] : s => length(s)}
{
  "api" = 3
  "worker" = 6
}

> [for k, v in {api = 30, worker = 14} : k if v > 14]
[
  "api",
]

> zipmap(["api", "worker"], [30, 14])
{
  "api" = 30
  "worker" = 14
}

> flatten([["/cloudnova/dev/api"], ["/cloudnova/dev/worker"]])
[
  "/cloudnova/dev/api",
  "/cloudnova/dev/worker",
]

> lookup({api = 30, worker = 14}, "scheduler", 7)
7
```

> **`terraform console` for expression development:** the console is the
> best place to test `for` expressions before adding them to `.tf`
> files — you can iterate quickly without running a full plan.

---

## Part B — `for` Expressions: Advanced Patterns

**What you accomplish in Part B:** extend the locals to demonstrate
less-obvious `for` expression patterns — nested iteration, grouping, and
combining multiple functions.

### Step 1 — Add advanced expression locals to `04-locals.tf`

Add the following to the existing `locals` block:

```hcl
  # ── Invert a map (swap keys and values) ──────────────────────────────────
  # Original: { "api" = 30, "worker" = 14, "scheduler" = 7 }
  # Inverted: { 30 = "api", 14 = "worker", 7 = "scheduler" }
  # Note: only works when values are unique — duplicate values would
  # cause a map key collision error
  retention_to_service = {
    for service, days in local.service_retention_resolved :
    days => service
  }

  # ── Group services by retention tier ─────────────────────────────────────
  # Produces: { "short" = ["scheduler"], "medium" = ["worker"], "long" = ["api"] }
  services_by_tier = {
    short  = [for s, d in local.service_retention_resolved : s if d <= 7]
    medium = [for s, d in local.service_retention_resolved : s if d > 7 && d <= 14]
    long   = [for s, d in local.service_retention_resolved : s if d > 14]
  }

  # ── toset() — deduplicate and prepare for for_each ────────────────────────
  # If var.services accidentally contained duplicates, toset() removes them
  # for_each (Demo 07) requires a set or map, never a list with duplicates
  services_set = toset(var.services)
```

### Step 2 — Add outputs for the new locals

Add to `07-outputs.tf`:

```hcl
output "retention_to_service" {
  description = "Inverted map: retention days → service name"
  value       = local.retention_to_service
}

output "services_by_tier" {
  description = "Services grouped by retention tier"
  value       = local.services_by_tier
}

output "services_set" {
  description = "Services as a set (deduped, unordered)"
  value       = local.services_set
}
```

### Step 3 — Apply and observe

```bash
terraform apply
```

Expected new outputs:

```
retention_to_service = {
  "7"  = "scheduler"
  "14" = "worker"
  "30" = "api"
}
services_by_tier = {
  "long"   = ["api"]
  "medium" = ["worker"]
  "short"  = ["scheduler"]
}
services_set = toset([
  "api",
  "scheduler",
  "worker",
])
```

> **`services_set` is unordered:** the output may show elements in a
> different order each time — sets have no guaranteed ordering. This is
> expected and correct. If order matters, keep a list. If uniqueness
> matters and order doesn't, use a set.

---

## Part C — `dynamic` Blocks

**What you accomplish in Part C:** add a security group resource with
dynamically-generated `ingress` rules — a realistic case where the
number of nested blocks is driven by a variable.

### Step 1 — Add ingress rules variable to `03-variables.tf`

```hcl
variable "ingress_rules" {
  type = map(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = optional(string, "")
  }))
  description = "Map of ingress rule name → rule config for the app security group"
  default = {
    https = {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTPS from anywhere"
    }
    http = {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTP from anywhere"
    }
    internal = {
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
      description = "Internal traffic"
    }
  }
}
```

### Step 2 — Add a data source for the default VPC

Add to `05-data.tf`:

```hcl
# Reads the default VPC — exists in all AWS accounts by default
data "aws_vpc" "default" {
  default = true
}
```

### Step 3 — Add the security group to `06-main.tf`

```hcl
resource "aws_security_group" "app" {
  name        = "${var.project}-${var.environment}-app-sg"
  description = "Security group for ${var.project} ${var.environment} application tier"
  vpc_id      = data.aws_vpc.default.id

  # dynamic generates one ingress block per entry in var.ingress_rules
  dynamic "ingress" {
    for_each = var.ingress_rules
    iterator = rule   # rename from default "ingress" to "rule" for clarity

    content {
      from_port   = rule.value.from_port
      to_port     = rule.value.to_port
      protocol    = rule.value.protocol
      cidr_blocks = rule.value.cidr_blocks
      description = rule.value.description
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.project}-${var.environment}-app-sg"
  }
}
```

> **Notice:** the `egress` block is written statically — it's always
> the same (allow all outbound). Only the `ingress` blocks are dynamic
> because their count varies by variable. This is the correct pattern:
> use `dynamic` only where the number of blocks genuinely varies.

### Step 4 — Add required permission and apply

The security group resource requires the `ec2` provider permission.
Add to `01-versions.tf`'s `required_providers`:

```hcl
# (ec2 is part of the aws provider — no separate entry needed)
# Add to the required permissions note for your account:
# ec2:CreateSecurityGroup, ec2:DeleteSecurityGroup, ec2:DescribeSecurityGroups
# ec2:AuthorizeSecurityGroupIngress, ec2:RevokeSecurityGroupIngress
# ec2:DescribeVpcs
```

```bash
terraform apply
```

Expected additional output:

```
data.aws_vpc.default: Reading...
data.aws_vpc.default: Read complete after 0s [id=vpc-xxxxxxxx]

aws_security_group.app: Creating...
aws_security_group.app: Creation complete after 2s [id=sg-xxxxxxxx]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

**Verify in Console:**

```
Console → EC2 → Security Groups → cloudnova-dev-app-sg
  → Inbound rules:
    → Port 443 TCP 0.0.0.0/0  HTTPS from anywhere ✅
    → Port 80  TCP 0.0.0.0/0  HTTP from anywhere ✅
    → Port 8080 TCP 10.0.0.0/8 Internal traffic ✅
```

### Step 5 — Add an ingress rule dynamically

```bash
terraform apply -var='ingress_rules={
  "https": {"from_port": 443, "to_port": 443, "protocol": "tcp", "cidr_blocks": ["0.0.0.0/0"], "description": "HTTPS"},
  "http":  {"from_port": 80,  "to_port": 80,  "protocol": "tcp", "cidr_blocks": ["0.0.0.0/0"], "description": "HTTP"},
  "internal": {"from_port": 8080, "to_port": 8080, "protocol": "tcp", "cidr_blocks": ["10.0.0.0/8"], "description": "Internal"},
  "monitoring": {"from_port": 9090, "to_port": 9090, "protocol": "tcp", "cidr_blocks": ["10.0.0.0/8"], "description": "Prometheus"}
}'
```

Expected plan:

```
  # aws_security_group.app will be updated in-place
  ~ resource "aws_security_group" "app" {
      ~ ingress = [
          + {
              + from_port   = 9090
              + to_port     = 9090
              + protocol    = "tcp"
              + cidr_blocks = ["10.0.0.0/8"]
              + description = "Prometheus"
            },
            # (3 unchanged elements hidden)
        ]
    }
```

> **The `dynamic` block in action:** adding one entry to `var.ingress_rules`
> generates exactly one new `ingress` block — you didn't touch the
> resource block definition at all. Remove an entry and the corresponding
> ingress rule is removed from the security group on next apply.

---

## Cleanup

```bash
terraform destroy
```

Type `yes`. Expected:

```
aws_security_group.app: Destroying...
aws_security_group.app: Destruction complete after 2s
aws_cloudwatch_log_group.services["api"]: Destroying...
aws_cloudwatch_log_group.services["scheduler"]: Destroying...
aws_cloudwatch_log_group.services["worker"]: Destroying...
aws_cloudwatch_log_group.services["api"]: Destruction complete after 1s
aws_cloudwatch_log_group.services["scheduler"]: Destruction complete after 1s
aws_cloudwatch_log_group.services["worker"]: Destruction complete after 1s

Destroy complete! Resources: 4 destroyed.
```

> **Data sources are not destroyed** — they were never managed by
> Terraform, only read. `terraform destroy` has no effect on
> `data.aws_caller_identity.current`, `data.aws_iam_policy.readonly`,
> or `data.aws_s3_bucket.legacy`.

## What You Learned

1. ✅ A `data` block reads existing infrastructure without managing it —
   no creates, updates, or destroys. Data sources appear in the
   dependency graph and their results flow into resources exactly like
   resource attribute references do
2. ✅ Data sources are refreshed on every `plan` (not just first apply)
   because their attributes might change externally. They are never
   destroyed by `terraform destroy`
3. ✅ `[for x in collection : expression]` produces a list;
   `{for x in collection : key => value}` produces a map. The
   surrounding bracket type determines the output type
4. ✅ `if` inside a `for` expression filters elements — only elements
   where the condition is `true` appear in the output
5. ✅ When iterating a map with `for`, use two variables:
   `for key, value in map : ...`
6. ✅ `toset()` removes duplicates and loses ordering — required before
   `for_each` (Demo 07) when your input is a list that might have
   duplicates
7. ✅ `lookup(map, key, default)` safely reads a map key with a fallback
   — avoids errors when a key might be absent
8. ✅ `flatten()` collapses a list of lists into a single flat list —
   useful when combining multiple collections
9. ✅ `zipmap(keys_list, values_list)` combines two parallel lists into
   a map — the lists must be the same length
10. ✅ `dynamic` blocks generate repeated nested blocks from a collection
    — use only when the number of blocks genuinely varies. The
    `iterator` argument renames the loop variable when `dynamic`'s
    block type name is inconvenient or ambiguous

---

## Cert Tips — TA-004 Objectives Covered

This demo covers **TA-004 Objective 4: Use Terraform outside of core
workflow** (data sources and expressions):

- Data sources are never destroyed by `terraform destroy` — a common
  exam trap presenting a scenario where someone tries to "delete" a data
  source and expecting it to affect real infrastructure
- `terraform_remote_state` (from Demo 05) is itself a data source —
  the same "read-only, not managed" rule applies
- A `for` expression outputting a list uses `[...]`; outputting a map
  uses `{... : ... => ...}` — the surrounding bracket determines output
  type
- `data` source results are stored in state under `"mode": "data"` —
  they appear in `terraform state list` output but cannot be targeted
  by `terraform state rm` in any meaningful way (they'd just be re-read
  on the next plan)
- `toset()` is commonly tested in context of `for_each` — know that
  `for_each` requires a set or map, and `toset()` converts a list

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Error: No matching policy found` | The ARN passed to `data.aws_iam_policy` doesn't exist or is misspelled | Verify the ARN with `aws iam get-policy --policy-arn <ARN> --profile default` |
| `Error: duplicate map key` in a `for` expression | Two elements produced the same key | Add `if` filtering to deduplicate, or redesign the key expression — map keys must be unique |
| `Error: Invalid for_each argument` | Passing a list to `for_each` instead of a set or map | Wrap in `toset()` for a list of strings, or use a `{for ...}` map expression |
| `Error: Unsupported block type` inside `dynamic` | Misspelled the block type name in `dynamic "<block_type>"` | The block type must exactly match the nested block the parent resource supports |
| `data.aws_s3_bucket.legacy[0]` — index error | Referencing index `[0]` when `count = 0` | Add a conditional: `var.legacy_bucket_name != "" ? data.aws_s3_bucket.legacy[0].region : "not configured"` |
| `lookup()` returns wrong value | Second argument (key) doesn't match any key in the map | Check the key's exact spelling — `lookup()` is case-sensitive. The third argument (default) is returned silently when the key is absent. |
| Security group `ingress` rule not appearing | Variable override not passed correctly | For complex object variables in `-var`, use a `.tfvars` file instead of CLI flag |

---

## Break-Fix Scenario

Three deliberate errors. Diagnose using `terraform validate` and
`terraform plan` — do not look at answers first.

```bash
cd src/break-fix/
terraform init
terraform validate
terraform plan
```

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

variable "services" {
  type    = list(string)
  default = ["api", "worker"]
}

variable "retention" {
  type    = map(number)
  default = { api = 30, worker = 14 }
}

data "aws_caller_identity" "current" {}

locals {
  # Error 1 — wrong bracket type for intended output
  service_map = [                           # Error 1
    for s in var.services :
    s => "/${s}/logs"
  ]

  # Error 2 — iterating a map with one variable instead of two
  retention_doubled = {
    for k in var.retention :               # Error 2
    k => k * 2
  }

  # Error 3 — using lookup without a default on a key that may not exist
  api_retention = lookup(var.retention, "database")   # Error 3
}

output "identity" {
  value = data.aws_caller_identity.current.account_id
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — `[for s in var.services : s => "/${s}/logs"]`**
The `key => value` syntax (`s => "/${s}/logs"`) is map output syntax
and requires curly braces `{...}`. Using square brackets `[...]`
produces a list, but `key => value` pairs are not valid list element
syntax. Terraform errors: `Invalid 'for' expression`.
Fix: change `[` to `{` and `]` to `}`:
```hcl
service_map = {
  for s in var.services :
  s => "/${s}/logs"
}
```

**Error 2 — `for k in var.retention`**
`var.retention` is a `map(number)`. When iterating a map with `for`,
you must use two variables to capture both key and value:
`for k, v in var.retention`. Using a single variable `k` tries to
iterate the map as if it were a list, which is not supported. Terraform
errors: `Invalid 'for' expression`.
Fix:
```hcl
retention_doubled = {
  for k, v in var.retention :
  k => v * 2
}
```

**Error 3 — `lookup(var.retention, "database")` with no default**
`lookup()` requires exactly three arguments: the map, the key, and the
default value to return when the key is absent. Calling it with two
arguments is a function call error. Additionally, `"database"` doesn't
exist in `var.retention` — without a default, this would return an
error at runtime even if the function call were syntactically correct.
Fix:
```hcl
api_retention = lookup(var.retention, "database", 0)
```

</details>

---

## Interview Prep

**Q1. A teammate says "I'll use a `data` source to read an S3 bucket so I can manage it in Terraform without running `terraform import`." Is this a valid approach?**
No — a `data` source reads infrastructure but does not bring it under Terraform management. Terraform cannot update or destroy infrastructure that exists only as a `data` block. If the goal is to manage the bucket (versioning, encryption, public access block), `terraform import` is required to bring it into state as a managed resource. The `data` source is appropriate when you only need to *read* the bucket's attributes (its ARN, region, domain name) to reference them in other resources — for example, configuring a CloudFront distribution to use an existing origin bucket that another team owns. Using a `data` source instead of `import` when management is the goal is a common misunderstanding.

**Q2. You write `{for s in var.services : s => s}`. A colleague says this is the same as `zipmap(var.services, var.services)`. Are they equivalent?**
Functionally yes — both produce a map where each key equals its value (e.g. `{api = "api", worker = "worker"}`). The `for` expression approach is more flexible — you can transform keys and values independently, add `if` filtering, and reference other locals. `zipmap()` is more concise when you have two already-computed parallel lists you want to combine. One important difference: `for` expressions guarantee uniqueness of keys (duplicate keys are a validation error), while `zipmap()` with duplicate keys in the first list also produces an error but potentially later. In practice, choose whichever reads more clearly for your specific case.

**Q3. You need to generate a security group with a variable number of ingress rules. A colleague suggests writing the resource once per rule with `count`. You suggest `dynamic`. Walk through why `dynamic` is the correct tool here.**
`count` creates multiple *resource instances* — separate security groups, each counted `[0]`, `[1]`, `[2]`. That's the wrong model: you want one security group with multiple *ingress blocks inside it*. `dynamic` generates repeated nested configuration blocks within a single resource, which is exactly what `ingress` rules are. Using `count` would create N separate security groups, which is not what's needed and would produce a fundamentally different infrastructure topology. The distinction: `count`/`for_each` controls how many resource instances exist; `dynamic` controls how many nested blocks appear inside one resource instance.

**Q4. When iterating a map with a `for` expression, what happens if you use only one variable (`for k in some_map`) instead of two (`for k, v in some_map`)?**
Using one variable when iterating a map produces an error: Terraform expects you to handle both the key and value when the input is a map. With a single variable `k`, Terraform doesn't know whether `k` should receive the key, the value, or some combination — it's ambiguous, so it errors. The two-variable form (`for key, value in map`) is required when the input is a map. If you genuinely only need the keys, you can use `for k, _ in map` (discarding the value) or simply use `keys(map)` to get a list of keys directly without a `for` expression.

**Q5. `terraform destroy` completes successfully. You check `terraform state list` afterward and notice the data sources are gone from the list. Does this mean the real IAM policies and caller identity were deleted from AWS?**
No — `terraform state list` shows what's currently in state, and `terraform destroy` removes all state entries after successfully destroying managed resources. Data source entries are also removed from state on destroy, but this only means Terraform's record of having read them is cleared — it has no effect on the actual IAM policies or AWS identity, which Terraform never managed. The IAM policies continue to exist exactly as before. On the next `terraform apply`, the data sources would be re-read and their state entries recreated. Data sources are never destroyed by `terraform destroy` — they are read-only lookups.

---

## Key Takeaways

1. **`data` blocks read existing infrastructure without managing it.**
   They appear in the dependency graph, produce attributes other
   resources can reference, and are re-read on every `plan` — but are
   never created, updated, or destroyed by Terraform.

2. **The output type of a `for` expression is determined by the
   surrounding bracket:** `[...]` produces a list, `{...}` with
   `key => value` produces a map.

3. **When iterating a map with `for`, use two variables.** A single
   variable is valid only for lists and sets — maps require
   `for key, value in map`.

4. **`if` inside a `for` expression filters, not transforms.** Only
   elements where the condition is `true` appear in the output —
   elements where it's `false` are dropped entirely.

5. **`toset()` removes duplicates and loses ordering** — a list of
   strings becomes a set before `for_each` (Demo 07), which requires
   a set or map, never a plain list.

6. **Use `dynamic` for genuinely variable nested block counts, not
   to avoid repetition.** A fixed three-rule security group written
   explicitly is more readable than a `dynamic` block over a
   three-element map. `dynamic` earns its place when the block count
   is driven by a variable or data source.

7. **`lookup(map, key, default)` requires all three arguments.** The
   default is not optional — calling `lookup()` with two arguments
   is a function call error.

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform init` | Downloads provider plugins and initialises the backend |
| `terraform validate` | Checks configuration syntax and schema with zero API calls |
| `terraform fmt -recursive` | Auto-formats `.tf` files including subdirectories |
| `terraform plan` | Previews changes — data sources are read during this step |
| `terraform apply` | Applies pending changes after confirmation |
| `terraform console` | Opens interactive REPL — best tool for testing `for` expressions |
| `terraform output` | Prints all output values including `for` expression results |
| `terraform output -json` | Prints all outputs as JSON — useful for inspecting complex maps/lists |
| `terraform state list` | Lists managed resources — data sources appear here prefixed with `data.` |
| `terraform destroy` | Destroys managed resources — data sources are not affected |

---

## Next Demo

**Demo 07 — Count, For-Each, and Resource Multiplicity:** `count` for
numbered resource instances, `for_each` for named instances with
`each.key`/`each.value`, why `count` is fragile for ordered collections,
splat expressions (`aws_instance.web[*].id`), and how each approach
appears differently in state and plan output.

---
## Appendix — Anki Cards

**06-data-sources-expressions-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::06-data-sources-expressions
#separator:Comma
#columns:Front,Back,Tags
"What is the key behavioral difference between a resource block and a data block?","resource: Terraform creates, manages full lifecycle (create/update/destroy), tracks in state as mode=managed. data: Terraform reads only — makes no changes to real infrastructure, never destroyed by terraform destroy, stored in state as mode=data and re-read on every plan.","demo06,data-sources,ta004"
"Does terraform destroy affect data sources?","No. Data sources are read-only — terraform destroy only destroys managed resources (resource blocks). Data source entries are removed from state entries on destroy (Terraform clears its record of having read them), but the actual AWS resources they represent are completely unaffected.","demo06,data-sources,ta004"
"When does Terraform read a data source — only on first apply, or on every plan?","On every plan (during the refresh step). Data source results can change externally between runs, so Terraform always re-reads them to get current values. This is different from managed resources, where Terraform compares state against current reality rather than always re-fetching.","demo06,data-sources"
"What does [for x in collection : expression] produce vs {for x in collection : key => value}?","Square brackets [for ...] produce a LIST. Curly braces {for ... : key => value} produce a MAP. The surrounding bracket type determines the output type — this is the most common source of for expression errors.","demo06,for-expressions,ta004"
"You write a for expression iterating a map with one variable: for k in some_map. What happens?","Error — when iterating a map, two variables are required to capture both key and value: for k, v in some_map. Using a single variable is valid only for lists and sets. If you only need keys, use keys(some_map) directly instead of a for expression.","demo06,for-expressions"
"How do you filter elements inside a for expression?","Add an if clause after the output expression: [for s in var.services : s if contains(var.prod_services, s)]. Only elements where the condition evaluates to true are included in the output — elements where it's false are dropped entirely.","demo06,for-expressions,filtering"
"What does toset(list) do, and why is it needed before for_each?","toset() converts a list to a set — removing duplicates and losing ordering. for_each (Demo 07) requires a set or map as input, never a plain list. toset() is the standard pre-step when you have a list of strings you want to use with for_each.","demo06,toset,for-each,ta004"
"What does lookup(map, key, default) do when the key is absent?","Returns the default value — the third argument. lookup() requires all three arguments (two-argument call is a function error). When the key exists, its value is returned. When absent, the default is returned silently with no error.","demo06,lookup,functions"
"What does flatten([[1, 2], [3, 4], [5]]) produce?","[1, 2, 3, 4, 5] — a single flat list. flatten() collapses a list of lists into one level. Commonly used when combining multiple for expressions or data source result lists that each return a list.","demo06,flatten,functions"
"What does zipmap(['a','b'], [1, 2]) produce?","{ a = 1, b = 2 } — a map combining the first list as keys and the second as values. Both lists must be the same length. Useful for combining two parallel computed lists into a map for use with for_each or lookup.","demo06,zipmap,functions"
"When should you use a dynamic block vs writing nested blocks explicitly?","Use dynamic when the number of nested blocks genuinely varies based on a variable or data source — the block count is unknown at configuration-write time. Write nested blocks explicitly when the count is fixed — a static three-rule security group is more readable as three explicit ingress blocks than as a dynamic block over a three-element map.","demo06,dynamic,ta004"
"Inside a dynamic block, how do you reference the current iteration's key and value by default?","Using <block_type>.key and <block_type>.value — e.g. inside dynamic \"ingress\" {}, the current element is ingress.key and ingress.value. The iterator argument renames this: iterator = rule makes it rule.key and rule.value instead.","demo06,dynamic,iterator"
"What does data.aws_s3_bucket.existing read, and what does it NOT read?","It reads bucket metadata: ARN, bucket name, domain names, hosted_zone_id, region. It does NOT read versioning status, encryption configuration, public access block settings, or object contents — each of those has its own separate data source.","demo06,data-sources,s3"
"You use count = 0 on a data source: data.aws_s3_bucket.legacy { count = 0 ... }. How do you reference it when count = 1?","With the index: data.aws_s3_bucket.legacy[0]. When count = 0, the data source doesn't exist in state at all and cannot be referenced — use a conditional: var.x != '' ? data.aws_s3_bucket.legacy[0].region : 'not configured'.","demo06,data-sources,count"
"What is the difference between using dynamic for security group ingress rules vs count?","count creates multiple resource INSTANCES (separate security groups). dynamic generates multiple nested BLOCKS within one resource instance. Security group ingress rules are nested blocks inside a single security group — dynamic is correct. count would create N separate security groups, which is wrong topology.","demo06,dynamic,count"
"How do you invert a map (swap keys and values) using a for expression?","{ for k, v in some_map : v => k } — swap the key and value positions. Only works when values are unique — duplicate values produce duplicate keys, which is a map key collision error in Terraform.","demo06,for-expressions,map"
"data.aws_caller_identity.current provides what three attributes?","account_id (the 12-digit AWS account ID), arn (ARN of the authenticated identity), user_id (unique ID of the authenticated identity). Requires no arguments — reads whoever is currently authenticated via the provider configuration.","demo06,data-sources,caller-identity"
```

---

## Appendix — Quiz

**06-data-sources-expressions-quiz.md:**

````markdown
# Quiz — Demo 06: Data Sources and Expressions: Read and Transform

---

**Q1.** What happens to `data.aws_iam_policy.readonly` when you run
`terraform destroy`?

A. The IAM policy is deleted from AWS
B. The data source entry is removed from state but the real IAM policy
   is completely unaffected — data sources are never destroyed
C. Terraform errors because data sources cannot be destroyed
D. The data source is converted to a managed resource

<details>
<summary>Answer</summary>

**B.** Data sources are read-only — `terraform destroy` only destroys
managed resources. The IAM policy keeps existing in AWS exactly as
before. Terraform's state entry for the data source is removed (cleared
with the rest of state), but this has no effect on AWS.

</details>

---

**Q2.** What does this `for` expression produce?

```hcl
[for k, v in {api = 30, worker = 14} : "${k}: ${v} days"]
```

A. `{ "api: 30 days" = ..., "worker: 14 days" = ... }` — a map
B. `["api: 30 days", "worker: 14 days"]` — a list
C. An error — maps cannot be iterated with `for`
D. `{ api = "api: 30 days", worker = "worker: 14 days" }` — a map

<details>
<summary>Answer</summary>

**B.** The surrounding `[...]` produces a list. The two-variable form
`for k, v in map` is correct for iterating a map. Each element becomes
a formatted string. The result is a list of strings.

</details>

---

**Q3.** You call `lookup(var.retention, "scheduler")` with only two
arguments. What happens?

A. Returns `null` when the key is absent
B. Returns `0` as the default for a `map(number)`
C. Function call error — `lookup()` requires exactly three arguments
D. Returns the first value in the map

<details>
<summary>Answer</summary>

**C.** `lookup()` requires three arguments: map, key, and default.
Calling it with two arguments is a function call error — Terraform
won't even reach the question of whether the key exists.

</details>

---

**Q4.** A security group needs a variable number of ingress rules
based on a `map` variable. Should you use `count` or `dynamic`?

A. `count` — creates one security group per ingress rule
B. `dynamic` — generates multiple nested `ingress` blocks inside one
   security group resource
C. Neither — you must write each ingress block explicitly
D. `for_each` on the security group resource

<details>
<summary>Answer</summary>

**B.** `dynamic` generates repeated nested blocks within a single
resource instance. `count` would create multiple separate security
group resources — one per rule — which is the wrong topology. Ingress
rules are nested blocks inside one security group, not separate
resources.

</details>

---

**Q5.** Inside `dynamic "ingress" { iterator = rule ... }`, how do you
reference the current element's value?

A. `ingress.value`
B. `rule.value`
C. `dynamic.value`
D. `iterator.value`

<details>
<summary>Answer</summary>

**B.** The `iterator = rule` argument renames the loop variable from
the default (`ingress`) to `rule`. After this, `rule.key` and
`rule.value` are used inside `content {}`. Without `iterator`, the
default is `ingress.key` and `ingress.value`.

</details>

---

**Q6.** What does `toset(["api", "worker", "api"])` produce?

A. `["api", "worker", "api"]` — unchanged list
B. `["api", "worker"]` — list with duplicates removed
C. `toset(["api", "worker"])` — a set with duplicates removed,
   unordered
D. An error — `toset()` does not accept lists with duplicates

<details>
<summary>Answer</summary>

**C.** `toset()` converts a list to a set, removing duplicates and
losing ordering. The result is `toset(["api", "worker"])` — the
duplicate `"api"` is removed. Sets are unordered, so the display
order may vary.

</details>

---

**Q7.** Which `for` expression correctly filters a map to only entries
where the value is greater than 14?

A. `[for k, v in var.retention : k => v if v > 14]`
B. `{for k, v in var.retention : k => v if v > 14}`
C. `{for k in var.retention : k if k > 14}`
D. `[for k, v in var.retention : {k = v} if v > 14]`

<details>
<summary>Answer</summary>

**B.** Curly braces `{...}` produce a map. Two variables `k, v` are
required for map iteration. `k => v` is the key/value pair syntax.
`if v > 14` filters to only elements where value exceeds 14. Option A
uses `[...]` which would produce a list (and `key => value` syntax
isn't valid in a list for-expression). Option C uses one variable for
a map, which errors.

</details>

---

**Q8.** `data.aws_s3_bucket.existing` successfully reads a bucket.
Which attribute is NOT available from this data source?

A. `.arn`
B. `.region`
C. `.versioning_status`
D. `.bucket_regional_domain_name`

<details>
<summary>Answer</summary>

**C.** `data.aws_s3_bucket` only reads bucket metadata — ARN, name,
domain names, hosted zone ID, region. Versioning status, encryption
configuration, and public access block settings each have their own
separate data sources (`aws_s3_bucket_versioning`, etc.).

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 07 |
| 7/8 | Review the wrong answer, then proceed |
| 6/8 | Re-read the relevant section, retry those questions |
| Below 6/8 | Re-read the full demo and redo the walkthrough before proceeding |
````