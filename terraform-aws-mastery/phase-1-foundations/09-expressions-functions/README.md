# Demo 09 — Expressions and Collection Functions

---

## Overview

Every demo since Demo 05 has used a `for` expression as a "preview" —
`trusted_principals` transforming a list of account IDs into a list of
ARNs — always with a note pointing here. This is that demo. `for`
expressions are Terraform's only mechanism for transforming a
collection into another collection, and they're everywhere once you
start looking: turning a list into a map, filtering elements, reshaping
one map's keys into another map's values.

**Real-world scenario — CloudNova:** the platform team needs one
CloudWatch Log Group per service (auth, billing, notifications) — built
from a single map, not three copy-pasted resource blocks — plus a
metric filter on each one that actually counts `ERROR`-level log lines
in real time. This demo builds both, and proves the metric filter works
by injecting real log events and watching a real metric count them.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — for Expressions: List and Map Transformations                 │
│  list→list, list→map, map→map   |   filtering elements with `if`        │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Collection Functions                                          │
│  keys(), values(), zipmap(), lookup(), flatten()   |   inverting a map, │
│  grouping by a computed key                                             │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — for_each-Driven Log Groups and a Tangible, Verifiable Result   │
│  One aws_cloudwatch_log_group per service   |   a metric filter per     │
│  group   |   inject real log events, confirm a real metric counts them  │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- `for` expression full syntax: list→list, list→map, map→map
- Filtering with `if` inside a `for` expression
- `toset()`, `keys()`, `values()`, `zipmap()`, `lookup()`, `flatten()`
- `for_each` over a `for`-expression-derived map (preview of Demo 10's
  full multiplicity coverage — used here, not yet explained in depth)
- `aws_cloudwatch_log_group` and `aws_cloudwatch_log_metric_filter`

**What this demo does NOT cover:** `for_each`'s own mechanics — the
distinction from `count`, splat expressions, the decision framework for
choosing between them — are Demo 10's focus. This demo uses `for_each`
as a consumer of the maps built here, without explaining `for_each`
itself in depth.

---

## Prerequisites

### Knowledge
- Demo 08 completed — `data` blocks, `data.aws_iam_policy`, `count` on
  a data source, `data.aws_ami`

### Required Tools

Same as Demos 05–08 — Terraform `>= 1.15.0`, AWS CLI `>= 2.x`, `jq`.

### Verify AWS Account and Permissions

```bash
aws sts get-caller-identity --profile default
aws configure get region --profile default
```

**Required permissions for this demo:**

```
logs:CreateLogGroup, logs:DeleteLogGroup, logs:DescribeLogGroups
logs:CreateLogStream, logs:PutLogEvents
logs:PutMetricFilter, logs:DeleteMetricFilter, logs:DescribeMetricFilters
cloudwatch:GetMetricStatistics, cloudwatch:ListMetrics
```

> For a learning account, `CloudWatchLogsFullAccess` and
> `CloudWatchFullAccess` managed policies cover the permissions above.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Write `for` expressions transforming a list into a list, a list
   into a map, and a map into a map
2. ✅ Filter elements inside a `for` expression using the `if` clause
3. ✅ Use `keys()`, `values()`, `zipmap()`, `lookup()`, and `flatten()`
   to reshape and combine collections
4. ✅ Use `for_each` over a `for`-expression-derived map to create one
   `aws_cloudwatch_log_group` per service
5. ✅ Create a `for_each`-driven `aws_cloudwatch_log_metric_filter` per
   log group, and confirm it counts real, injected log events

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| `aws_cloudwatch_log_group` (×3) | 5 GB ingestion + 5 GB storage free/month | **$0.00** | Well under free tier for a lab |
| `aws_cloudwatch_log_metric_filter` (×3) | First 10 custom metrics free/month | **$0.00** | |
| **Session total** | | **$0.00** | |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
09-expressions-functions/
├── README.md
├── 09-expressions-functions-anki.csv
├── 09-expressions-functions-quiz.md
└── src/
    ├── 01-versions.tf       # terraform block + provider version constraints
    ├── 02-provider.tf       # AWS provider: region, profile
    ├── 03-variables.tf      # service map, log retention, error pattern
    ├── 04-locals.tf         # for expressions + collection functions — this demo's focus
    ├── 05-log-groups.tf     # for_each-driven aws_cloudwatch_log_group
    ├── 06-metric-filters.tf # for_each-driven aws_cloudwatch_log_metric_filter
    ├── 07-outputs.tf        # exposes what was built
    └── break-fix/
        └── broken.tf
```

---

## Recall Check — Demo 08

Answer from memory before reading further:

1. What is the simplest test for whether something belongs in a `data`
   block instead of a `resource` block?
2. A `count`-gated `data` block has `count` evaluate to `0`. What does
   referencing `data.x.y[0]` produce?
3. Why does `data.aws_ami` require `most_recent = true` when multiple
   images could match the filters?

<details>
<summary>Answers</summary>

1. Ask: does removing this block from the configuration destroy
   anything real? If no, it's `data`. If yes, it's `resource`.
2. An "Invalid index" error — "the collection has no elements." A
   `count`-gated data source with `count = 0` becomes an empty list;
   indexing `[0]` on an empty list errors, the same as any other
   out-of-bounds list access.
3. Without it, Terraform errors if more than one AMI matches the
   filters — it never silently picks one for you. `most_recent = true`
   makes the tie-breaking rule explicit rather than leaving ambiguous
   resolution to chance.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `for` expression (full) | Language construct | list→list, list→map, map→map transformations |
| `if` filter in a `for` expression | Language construct | Excludes elements that don't match a condition |
| `keys(map)` | Built-in function | Returns a map's keys as a list |
| `values(map)` | Built-in function | Returns a map's values as a list |
| `zipmap(keys, values)` | Built-in function | Combines a list of keys and a list of values into a map |
| `lookup(map, key, default)` | Built-in function | Safely reads a map key, with a fallback if missing |
| `flatten(list)` | Built-in function | Flattens a nested list of lists into a single list |
| `for_each` (preview) | Resource argument | Consumes a `for`-derived map — full coverage Demo 10 |
| `aws_cloudwatch_log_group` | Resource | One per service, `for_each`-driven |
| `aws_cloudwatch_log_metric_filter` | Resource | Counts matching log lines as a real CloudWatch metric |

**Related constructs worth knowing (not used in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| `count` / `for_each` decision framework | Choosing between multiplicity mechanisms | Demo 10 |
| Splat expressions | Collecting one attribute across instances | Demo 10 |
| `distinct()`, `concat()` | Additional collection functions | Not used in this series yet |
| `format()`, `join()`, `split()` | String functions | Not used in this series yet |

---

### Detailed Explanation of New Constructs

#### `for` Expression — List to List

```hcl
# Syntax: [for item in list : transformation]
[for name in ["auth", "billing", "notifications"] : "cloudnova-${name}-service"]
# Result: ["cloudnova-auth-service", "cloudnova-billing-service", "cloudnova-notifications-service"]
```

Transforms every element of a list, producing a new list of the same
length. This is the same form `trusted_principals` used back in
Demo 05 — building one ARN string per account ID.

---

#### `for` Expression — List to Map

```hcl
# Syntax: {for item in list : key_expr => value_expr}
{for name in ["auth", "billing", "notifications"] : name => "cloudnova-${name}-service"}
# Result: {
#   auth          = "cloudnova-auth-service"
#   billing       = "cloudnova-billing-service"
#   notifications = "cloudnova-notifications-service"
# }
```

The `{}` braces (instead of `[]`) and the `=>` (instead of a bare
transformation) are what make this a map-producing `for` expression.
Each list element becomes a map value, keyed by whatever expression
precedes `=>` — here, the service name itself.

---

#### `for` Expression — Map to Map

```hcl
locals {
  service_config = {
    auth          = { retention_days = 30 }
    billing       = { retention_days = 90 }
    notifications = { retention_days = 14 }
  }
}

# Syntax: {for key, value in map : new_key => new_value}
{for name, config in local.service_config : name => config.retention_days}
# Result: { auth = 30, billing = 90, notifications = 14 }
```

Iterating a map gives you both the key and the value at each step —
`for name, config in ...` destructures them, letting you build a new
map derived from the original's values.

---

#### Filtering with `if`

```hcl
# Syntax: [for item in list : transformation if condition]
[for name, config in local.service_config : name if config.retention_days >= 30]
# Result: ["auth", "billing"] — notifications excluded (retention_days = 14)
```

The `if` clause excludes elements from the result entirely — it
doesn't just skip transforming them, it removes them from the output
list/map altogether. This is the only filtering mechanism `for`
expressions have; there's no separate "filter" function.

> **`if` in a `for` expression filters; it doesn't branch.** This is
> different from the conditional operator (`? :`, Demo 05), which
> picks between two values for every element. `if` here removes
> elements outright — there's no "else" branch to provide an
> alternative value for excluded elements.

---

#### Advanced Pattern — Inverting a Map

```hcl
locals {
  name_to_id = { auth = "svc-001", billing = "svc-002" }
}

{for name, id in local.name_to_id : id => name}
# Result: { "svc-001" = "auth", "svc-002" = "billing" }
```

Swapping keys and values is just a map-to-map `for` expression where
the key and value expressions are reversed from the source. Useful
when you have a lookup in one direction but need it in the other.

---

#### Advanced Pattern — Grouping by a Computed Key

```hcl
locals {
  services_by_tier = {
    auth          = "critical"
    billing       = "critical"
    notifications = "standard"
  }
}

{for name, tier in local.services_by_tier : tier => name...}
# Result: { critical = ["auth", "billing"], standard = ["notifications"] }
```

The trailing `...` after the value expression is the **grouping mode**
of a map-producing `for` expression — instead of the last-write-wins
behavior a plain `for` would have if two elements produced the same
key, `...` collects every value that maps to the same key into a list.
Without `...`, `tier => name` would silently keep only the *last*
service seen for each tier and discard the rest.

---

#### `keys(map)` and `values(map)`

```hcl
keys({ auth = 30, billing = 90 })    # ["auth", "billing"]
values({ auth = 30, billing = 90 })  # [30, 90]
```

Both return elements in the same corresponding order — `keys(m)[0]`
and `values(m)[0]` always refer to the same map entry.

---

#### `zipmap(keys, values)` — Combining Two Lists into a Map

```hcl
zipmap(["auth", "billing"], [30, 90])
# Result: { auth = 30, billing = 90 }
```

The inverse of `keys()`/`values()` — takes a list of keys and a
parallel list of values (same length, same order) and combines them
into a map. Useful when a data source or variable gives you two
correlated lists that need to become one map.

---

#### `lookup(map, key, default)` — Safe Map Reads

```hcl
lookup({ auth = 30, billing = 90 }, "notifications", 14)
# Result: 14 — "notifications" isn't a key, so the default is returned

lookup({ auth = 30, billing = 90 }, "auth", 14)
# Result: 30 — "auth" IS a key, so its actual value is returned
```

> **`lookup()` vs. index syntax (`map["key"]`):** `map["key"]` errors
> if the key doesn't exist. `lookup(map, "key", default)` returns the
> default instead of erroring. Use `lookup()` whenever a key might
> legitimately be absent; use index syntax when its absence should be
> a hard error.

---

#### `flatten(list)` — Collapsing Nested Lists

```hcl
flatten([["a", "b"], ["c"], ["d", "e", "f"]])
# Result: ["a", "b", "c", "d", "e", "f"]
```

Common after a `for` expression that itself produces a list per
element — e.g., building one list of log stream names per service,
then flattening the list-of-lists into a single flat list.

---

## Lab Step-by-Step Guide

---

## Part A — for Expressions: List and Map Transformations

**What you accomplish in Part A:** declare CloudNova's service
configuration as a map, then use `for` expressions to derive every
other shape needed from it — a list of names, a filtered subset, and
an inverted lookup.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/09-expressions-functions/src
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

#### `03-variables.tf` — Service configuration inputs

**What this file does in this demo:** `service_config` is the single
source of truth this entire demo transforms in different shapes —
every `for` expression and collection function in Part A and Part B
derives something from this one map.

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

variable "service_config" {
  type = map(object({
    retention_days = number
    tier           = string
  }))
  description = "Per-service configuration — retention and criticality tier"
  default = {
    auth = {
      retention_days = 30
      tier           = "critical"
    }
    billing = {
      retention_days = 90
      tier           = "critical"
    }
    notifications = {
      retention_days = 14
      tier           = "standard"
    }
  }
}

variable "error_pattern" {
  type        = string
  description = "CloudWatch Logs filter pattern for the metric filter"
  default     = "ERROR"
}
```

---

### Step 3 — Create `04-locals.tf` with Part A's `for` expressions

**What this file does in this demo:** every local here derives from
`var.service_config` alone, in a different shape — this is the file
Part B extends with collection functions, and Part C's `for_each`
resources both consume.

**04-locals.tf:**

```hcl
locals {
  # list→list: just the service names
  service_names = [for name, config in var.service_config : name]

  # list→map: service name to full log group name
  log_group_names = {for name, config in var.service_config : name => "cloudnova-${name}-logs"}

  # map→map: just retention days per service
  retention_by_service = {for name, config in var.service_config : name => config.retention_days}

  # filtering with if: only critical-tier services
  critical_services = [for name, config in var.service_config : name if config.tier == "critical"]

  # inverting: retention days back to service name (assumes unique retention values)
  service_by_retention = {for name, config in var.service_config : config.retention_days => name}

  # grouping by computed key: services grouped by tier
  services_by_tier = {for name, config in var.service_config : config.tier => name...}
}
```

### Step 4 — Apply and inspect via `terraform console`

```bash
terraform init
terraform validate
terraform apply
```

```bash
terraform console
```

```hcl
> local.service_names
["auth", "billing", "notifications"]
> local.critical_services
["auth", "billing"]
> local.services_by_tier
{
  "critical" = ["auth", "billing"]
  "standard" = ["notifications"]
}
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## Part B — Collection Functions

**What you accomplish in Part B:** extend `04-locals.tf` with
`keys()`/`values()`/`zipmap()`/`lookup()`/`flatten()`, all operating on
the same `service_config` map from Part A.

### Step 1 — Add collection-function locals

Add to the `locals {}` block in `04-locals.tf`:

```hcl
  # keys() / values() — same order, corresponding entries
  service_name_list       = keys(var.service_config)
  retention_days_list      = values(local.retention_by_service)

  # zipmap() — rebuild a map from two parallel lists
  rebuilt_retention_map = zipmap(local.service_name_list, [for n in local.service_name_list : local.retention_by_service[n]])

  # lookup() — safe read with a fallback for a service that might not exist
  archive_service_retention = lookup(local.retention_by_service, "archive", 7)

  # flatten() — one list of log stream name per service, flattened to a single list
  all_log_streams = flatten([
    for name, config in var.service_config : [
      "${name}-stream-primary",
      "${name}-stream-secondary"
    ]
  ])
```

### Step 2 — Apply and verify

```bash
terraform apply
terraform console
```

```hcl
> local.archive_service_retention
7
> local.all_log_streams
[
  "auth-stream-primary", "auth-stream-secondary",
  "billing-stream-primary", "billing-stream-secondary",
  "notifications-stream-primary", "notifications-stream-secondary",
]
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **`archive_service_retention` returns `7`, the fallback — not an
> error.** `"archive"` isn't a key in `retention_by_service`;
> `lookup()`'s third argument is exactly for this case. The same
> lookup written as `local.retention_by_service["archive"]` would have
> errored instead.

---

## Part C — for_each-Driven Log Groups and a Tangible, Verifiable Result

**What you accomplish in Part C:** create one `aws_cloudwatch_log_group`
per service using `for_each` over `local.log_group_names`, add a metric
filter per group, then inject real log events and confirm a real
CloudWatch metric actually counts them.

### Step 1 — Create `05-log-groups.tf`

**What this file does in this demo:** one `aws_cloudwatch_log_group`
per service, `for_each`-driven directly over `var.service_config` —
`each.key` becomes the log group's name suffix, `each.value` supplies
its retention period and tier tag.

Create a file **05-log-groups.tf** and add the below content:

```hcl
resource "aws_cloudwatch_log_group" "service" {
  for_each          = var.service_config
  name              = "/cloudnova/${each.key}"
  retention_in_days = each.value.retention_days

  tags = {
    Service = each.key
    Tier    = each.value.tier
  }
}
```

### Step 2 — Create `06-metric-filters.tf`

**What this file does in this demo:** one metric filter per log group,
`for_each`-driven over the same `var.service_config` map — this is
what makes the demo's result tangible: without this, the log groups
would sit empty and unverifiable.

Create a file **06-metric-filters.tf** and add the below content:

```hcl
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  for_each       = var.service_config
  name           = "${each.key}-error-count"
  log_group_name = aws_cloudwatch_log_group.service[each.key].name
  pattern        = var.error_pattern

  metric_transformation {
    name      = "${each.key}ErrorCount"
    namespace = "CloudNova/Application"
    value     = "1"
  }
}
```

### Step 3 — Create `07-outputs.tf` and apply

**What this file does in this demo:** exposes every created log
group's real name, keyed by service — confirming `for_each` produced
one log group per `service_config` entry, addressable by name.

Create a file **07-outputs.tf** and add the below content:

```hcl
output "log_group_names" {
  description = "Names of all created log groups"
  value       = { for k, v in aws_cloudwatch_log_group.service : k => v.name }
}
```

```bash
terraform apply
```

Expected: `Apply complete! Resources: 6 added` (3 log groups + 3
metric filters).

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

**Verify:**

```
Console → CloudWatch → Log groups → /cloudnova/auth, /cloudnova/billing,
  /cloudnova/notifications
  → all three exist, retention periods match service_config ✅
Console → CloudWatch → Metrics → CloudNova/Application
  → authErrorCount, billingErrorCount, notificationsErrorCount all
    listed (may show "no data" until Step 4 injects real events) ✅
```

### Step 4 — Inject real log events

```bash
STREAM_NAME="auth-stream-primary"
aws logs create-log-stream --log-group-name "/cloudnova/auth" --log-stream-name "$STREAM_NAME"

TS=$(date +%s000)
aws logs put-log-events \
  --log-group-name "/cloudnova/auth" \
  --log-stream-name "$STREAM_NAME" \
  --log-events \
    "timestamp=${TS},message=\"INFO user login succeeded\"" \
    "timestamp=${TS},message=\"ERROR failed to validate token\"" \
    "timestamp=${TS},message=\"ERROR database connection timeout\""
```

### Step 5 — Confirm the metric filter actually counted them

Wait a few seconds for CloudWatch to process the filter, then:

```bash
aws logs filter-log-events \
  --log-group-name "/cloudnova/auth" \
  --filter-pattern "ERROR"
```

Expected: two matching log events returned — the two `ERROR` lines,
not the `INFO` line.

```bash
aws cloudwatch get-metric-statistics \
  --namespace "CloudNova/Application" \
  --metric-name "authErrorCount" \
  --start-time "$(date -u -d '10 minutes ago' +%FT%TZ)" \
  --end-time "$(date -u +%FT%TZ)" \
  --period 300 \
  --statistics Sum
```

Expected: a datapoint with `Sum: 2.0` — the metric filter counted
exactly the two injected `ERROR` lines, nothing more, nothing less.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

**Verify:**

```
Console → CloudWatch → Metrics → CloudNova/Application → authErrorCount
  → graph shows a real datapoint of 2 at the time events were injected ✅
Console → CloudWatch → Log groups → /cloudnova/auth → auth-stream-primary
  → the three injected log lines (1 INFO, 2 ERROR) are visible directly ✅
```

> **This is the tangible, verifiable result this demo promised.** The
> log group, the metric filter, and the pattern match are all real —
> two `ERROR` lines went in, and a real CloudWatch metric shows `Sum:
> 2.0` back out. Nothing here is asserted from documentation alone;
> it's an end-to-end check against live AWS behavior.

---

## Cleanup

```bash
terraform destroy
```

Expected: `Destroy complete! Resources: 6 destroyed.`

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

```
Console → CloudWatch → Log groups → /cloudnova/auth, /cloudnova/billing, /cloudnova/notifications: GONE ✅
Console → CloudWatch → Metrics → CloudNova/Application: GONE ✅
```

---

## What You Learned

1. ✅ `for` expressions transform lists into lists (`[for x in list :
   expr]`), lists into maps (`{for x in list : k => v}`), and maps
   into maps (`{for k, v in map : new_k => new_v}`)
2. ✅ `if` inside a `for` expression filters elements out entirely —
   it doesn't provide a branch or alternative value
3. ✅ The `...` suffix on a map-producing `for` expression's value
   groups multiple matches into a list, instead of last-write-wins
4. ✅ `keys()`/`values()` return corresponding-order lists;
   `zipmap()` does the reverse — combining two parallel lists into a map
5. ✅ `lookup(map, key, default)` returns a fallback instead of
   erroring when a key is missing — unlike `map["key"]`
6. ✅ `flatten()` collapses a list of lists into one flat list —
   common after a `for` expression that itself produces a list per element
7. ✅ A `for_each`-driven `aws_cloudwatch_log_metric_filter` counts
   real log events as a real CloudWatch metric, verified end-to-end

---

## Cert Tips — TA-004 Objectives Covered

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `for` expression list→map form | TA-004 Obj 4 (variables/outputs and expressions) | Frequently tested — know the `{}`/`=>` syntax distinction from list→list |
| `if` filter in a `for` expression | TA-004 Obj 4 | Common trap: assuming it transforms rather than excludes |
| `...` grouping mode | TA-004 Obj 4 | Tests whether you know last-write-wins is the default without it |
| `lookup()` vs. index syntax | TA-004 Obj 4 | Tests knowing which one errors on a missing key |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam shows `{for k, v in map : k => v if condition}` | Recognizing `if` excludes non-matching entries from the result entirely | Assuming excluded entries appear with a null/default value instead of being removed |
| Exam shows two services mapping to the same tier without `...` | Recognizing only the last-processed entry survives (last-write-wins) | Assuming Terraform automatically collects all matches into a list without `...` |
| Exam asks the difference between `lookup(map, "x", default)` and `map["x"]` | Recognizing `lookup()` returns the default on a missing key; index syntax errors | Assuming both behave identically on a missing key |

### Exam Task — Write a complete configuration

**Task:** CloudNova needs a `for` expression that takes a map of
regions to instance counts and produces (1) a list of region names
with more than 2 instances, and (2) a map inverting region-to-count
into count-to-region. Write both `for` expressions plus the source
variable from scratch.

**Block types required:** `variable` (×1), `locals` (×1, two `for`
expressions)

**Official documentation:**
- [`for` Expressions](https://developer.hashicorp.com/terraform/language/expressions/for)

**What to practise:**
1. Open the `for` Expressions page — confirm the exact syntax
   difference between the list-producing and map-producing forms
2. Write both expressions from scratch without looking at this demo's
   `04-locals.tf`
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
variable "region_instance_counts" {
  type = map(number)
  default = {
    "us-east-2" = 5
    "us-west-2" = 2
    "eu-west-1" = 8
  }
}

locals {
  high_usage_regions = [
    for region, count in var.region_instance_counts : region if count > 2
  ]

  count_to_region = {
    for region, count in var.region_instance_counts : count => region
  }
}
```

**Arguments you must know without looking up:**
- List-producing form: `[for x in collection : expr]`
- Map-producing form: `{for x in collection : key_expr => value_expr}`
  — braces and `=>`, not brackets

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `for` expression produces fewer entries than expected | An `if` filter is excluding more than intended | Check the filter condition — remember `if` removes, it doesn't provide a fallback |
| A map-producing `for` expression silently drops entries | Two source elements produced the same key, and `...` wasn't used | Add `...` after the value expression to collect all matches into a list instead |
| `lookup()` still errors | Passed only 2 arguments (`lookup(map, key)`) instead of 3 | Always supply the third `default` argument for safe reads |
| Metric filter shows `Sum: 0` or no datapoints | Log events were injected before the metric filter was created, or the pattern doesn't match | Confirm filter creation preceded event injection; verify the pattern with `aws logs filter-log-events` directly |

---

## Break-Fix Scenario

Three deliberate errors, all expression/function-specific. Diagnose
using `terraform validate`/`plan` — do not look at answers first.

```bash
cd src/break-fix/
terraform init
terraform validate
terraform plan
```

#### `broken.tf` — Three deliberate expression/function errors

**What this file does in this demo:** a self-contained configuration
with a bracket-type mismatch in a `for` expression, a single-variable
map iteration, and a `lookup()` call missing its default argument —
diagnose all three.

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

variable "service_config" {
  type = map(object({
    retention_days = number
  }))
  default = {
    auth    = { retention_days = 30 }
    billing = { retention_days = 90 }
  }
}

locals {
  # Error 1: [] brackets used, but => makes this a map-producing expression
  wrong_brackets = [for name, config in var.service_config : name => config.retention_days]

  # Error 2: single loop variable on a map — only gets the key, not the value
  service_names_only = [for name in var.service_config : name]

  # Error 3: lookup() missing the required default argument
  missing_service = lookup(local.wrong_brackets, "archive")
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — bracket/syntax mismatch**
`[for ... : name => config.retention_days]` mixes list-producing
brackets (`[]`) with map-producing syntax (`=>`). `terraform validate`
errors on the syntax — `=>` is only valid inside `{}`. Fix: change `[`
to `{` and `]` to `}` to match the map-producing form actually intended.

**Error 2 — single loop variable on a map**
`for name in var.service_config` with only one loop variable, when
iterating a map, binds `name` to each **key** only — the config value
is silently unavailable, not an error but a design mistake if the
value was needed. Fix: use two loop variables — `for name, config in
var.service_config` — to get both key and value.

**Error 3 — `lookup()` missing the default argument**
`lookup(local.wrong_brackets, "archive")` supplies only 2 arguments.
`terraform validate` errors that `lookup()` requires 3 arguments (or a
2-argument form exists in older behavior, but the safe pattern always
supplies a default explicitly). Fix: add a third argument —
`lookup(local.wrong_brackets, "archive", null)`.

</details>

**Cleanup:**
```bash
cd src/break-fix/
rm -f terraform.tfstate terraform.tfstate.backup
cd ../..
```
No resources were created in this scenario (all three errors are caught
before any `apply`).

---

## Interview Prep

**Q1. A teammate writes `[for k, v in map : k => v]` and gets a syntax error. What's wrong, and what's the fix?**
The brackets (`[]`) signal a list-producing `for` expression, but `=>` is map-producing syntax — the two are incompatible. Terraform can't reconcile "give me a list" with "here's a key-value pair for each element." The fix is to match the syntax to the intent: `{for k, v in map : k => v}` if a map result is wanted (braces), or drop the `=>` entirely for a list result (`[for k, v in map : v]`, just the values as a list).

**Q2. Why does `{for name, tier in services : tier => name}` silently produce fewer entries than expected when two services share a tier?**
Without the `...` grouping suffix, a map-producing `for` expression follows last-write-wins: if two elements produce the same key, only the last one processed survives in the result — the earlier one is silently overwritten, not combined. This is easy to miss because there's no error; the map is just smaller than the source had entries. Adding `...` after the value expression (`tier => name...`) changes the behavior to collect every match into a list under that key instead.

**Q3. When would you use `lookup()` instead of just writing `map["key"]`?**
`map["key"]` is the right choice when the key's absence should be a hard error — you want to know immediately if something expected is missing. `lookup(map, "key", default)` is the right choice when a missing key is a normal, expected case that should degrade gracefully to some sensible fallback, rather than halting the plan. The decision is about whether a missing key represents a bug to surface loudly or a legitimate, anticipated situation.

**Q4. A `for_each`-driven metric filter shows `Sum: 0` even though you've confirmed matching log lines exist in the log group. What's your diagnosis process?**
First, I'd check the timing — if log events were written before the metric filter existed, the filter only processes events going forward, not retroactively; it wouldn't count anything from before its own creation. Second, I'd verify the filter pattern actually matches by running `aws logs filter-log-events` directly with the same pattern against the log group, confirming the pattern itself is correct independent of the metric. Third, I'd check the metric namespace and name in the `get-metric-statistics` call match exactly what the `metric_transformation` block declared — a namespace or name typo there would query the wrong (empty) metric entirely.

---

## Key Takeaways

1. **List-producing `for` uses `[]`; map-producing `for` uses `{}` and
   `=>`.** Mixing them is a syntax error, not a style choice.

2. **`if` filters elements out entirely — it doesn't branch or provide
   an alternative.** That's what the conditional operator (`? :`) is
   for; `if` in a `for` expression only excludes.

3. **Without `...`, colliding keys in a map-producing `for` expression
   silently keep only the last match.** `...` changes this to collect
   all matches into a list — no error either way, just different
   results.

4. **`lookup()` returns a default on a missing key; `map["key"]`
   errors.** Choose based on whether a missing key is expected
   (degrade gracefully) or a bug (fail loudly).

5. **A metric filter only counts events written after its own
   creation.** `Sum: 0` on genuinely matching log lines often means a
   timing issue, not a broken pattern.

> **Demo scope:** Primary concept: `for` expressions — list-to-list,
> list-to-map, map-to-map transformations, and filtering with `if`.
> Supporting concepts: `keys()`/`values()`/`zipmap()`/`lookup()`/
> `flatten()`, and a `for_each`-driven log group + metric filter pair
> proving the transformations feed real, verifiable infrastructure.
> Estimated completion time: 40 minutes (reading + hands-on + verification).
> Checkpoints: 3 natural stopping points (end of Part A, end of Part B,
> end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform console` | Interactively evaluate a `for` expression or collection function |
| `keys(map)` / `values(map)` | Corresponding-order key/value lists from a map |
| `zipmap(keys, values)` | Combines two parallel lists into a map |
| `lookup(map, key, default)` | Safe map read — returns default instead of erroring on a missing key |
| `flatten(list_of_lists)` | Collapses nested lists into one flat list |
| `aws logs put-log-events` | Injects real log events into a log group for testing |
| `aws logs filter-log-events --filter-pattern PATTERN` | Confirms a filter pattern's matches directly, independent of the metric |
| `aws cloudwatch get-metric-statistics` | Confirms a metric filter is actually counting events |

---

## Next Demo

**Demo 10 — Multiplicity: `count`, `for_each`, and `dynamic`:** the
three ways Terraform repeats configuration, taught together — `count`
fundamentals, `for_each` fundamentals (building on this demo's
`for`-expression-derived maps), splat expressions, the decision
framework for choosing between them, and `dynamic` blocks contrasted
directly against both.

---

## Appendix — Anki Cards

**09-expressions-functions-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::09-expressions-functions
#separator:Comma
#columns:Front,Back,Tags
"What is the syntax difference between a list-producing and a map-producing for expression?","List-producing: [for x in collection : expr] — square brackets. Map-producing: {for x in collection : key_expr => value_expr} — curly braces and =>. Mixing them (e.g. brackets with =>) is a syntax error.","demo09,for-expression,ta004"
"Does if inside a for expression transform an element or exclude it?","Exclude it entirely. if in a for expression filters — non-matching elements are removed from the result completely, not transformed into a null/default value. There is no else branch.","demo09,for-expression,if,ta004"
"Two services map to the same tier in {for name, tier in services : tier => name}, written without the ... suffix. What happens?","Last-write-wins silently — only the last-processed service for that tier survives in the result; the earlier one is overwritten with no error. Adding ... after the value expression (tier => name...) collects all matches into a list instead.","demo09,for-expression,grouping,ta004"
"What is the difference between lookup(map, 'key', default) and map['key']?","map['key'] errors if the key doesn't exist. lookup(map, 'key', default) returns the default value instead of erroring. Use lookup() when a missing key is expected and should degrade gracefully; use index syntax when it should be a hard error.","demo09,functions,lookup,ta004"
"What does zipmap(['a','b'], [1,2]) return?","{ a = 1, b = 2 } — zipmap combines a list of keys and a parallel list of values (same length, same order) into a single map. It's the inverse of using keys()/values() to split a map into two lists.","demo09,functions,zipmap"
"What does flatten([['a','b'], ['c']]) return?","['a', 'b', 'c'] — flatten collapses a list of lists into a single flat list. Commonly needed after a for expression that itself produces a list per source element.","demo09,functions,flatten"
"A for_each-driven metric filter shows Sum: 0 even though matching log lines clearly exist in the log group. What's the most likely cause?","The log events were written before the metric filter was created — filters only process events going forward from their own creation, not retroactively. Confirm by checking event timestamps against the filter's creation time.","demo09,metric-filter,troubleshooting"
"Why does a for expression's if clause matter more than it might seem for validation-style filtering?","Because it's the ONLY filtering mechanism for expressions have — there's no separate filter() function. Any collection filtering in Terraform HCL goes through a for expression's if clause.","demo09,for-expression,if"
"What loop variable(s) do you get iterating a map with a single variable, e.g. for name in var.service_config?","Only the key (name) — the value is not accessible with a single loop variable on a map. Use two loop variables (for name, config in var.service_config) to access both key and value.","demo09,for-expression,break-fix"
```

---

## Appendix — Quiz

**09-expressions-functions-quiz.md:**

```markdown
# Quiz — Demo 09: Expressions and Collection Functions

> One correct answer per question unless stated otherwise.
> Target: 80% or above before moving to Demo 10.
> TA-004 exam style.

---

**Q1.** What syntax distinguishes a map-producing `for` expression from
a list-producing one?

A. Map-producing uses `()`, list-producing uses `[]`
B. Map-producing uses `{}` and `=>`; list-producing uses `[]` with no `=>`
C. There is no syntactic difference — Terraform infers it from context
D. Map-producing requires a `map()` type wrapper around the whole expression

<details>
<summary>Answer</summary>

**B.** `{for x in collection : key => value}` (braces + `=>`) produces
a map; `[for x in collection : value]` (brackets, no `=>`) produces a
list. **A** is wrong — `()` isn't valid `for` expression delimiter
syntax at all. **C** is wrong — the syntax is explicit and required,
not inferred. **D** is wrong — no such wrapper exists or is needed.

</details>

---

**Q2.** `{for k, v in map : k => v if v > 10}` — what happens to entries
where `v <= 10`?

A. They appear in the result with a `null` value
B. They are excluded from the result entirely
C. They cause a validation error
D. They're included but flagged as invalid

<details>
<summary>Answer</summary>

**B.** `if` in a `for` expression filters — non-matching entries are
removed from the output entirely. **A** is wrong — there's no
null-value fallback; excluded means absent, not null. **C** is wrong —
this is normal, valid filtering behavior, not an error. **D** is wrong
— there's no "flagged as invalid" concept; excluded entries simply
don't appear.

</details>

---

**Q3.** Two source elements produce the same key in a map-producing
`for` expression **without** the `...` suffix. What happens?

A. Terraform errors on the duplicate key
B. Both values are combined into a list automatically
C. Only the last-processed element's value survives — silently
D. The map ends up with a duplicate-keys warning but both are kept

<details>
<summary>Answer</summary>

**C.** Without `...`, it's last-write-wins with no error — earlier
matches for the same key are silently overwritten. **A** is wrong —
this doesn't error; it's valid, if surprising, behavior. **B** is
wrong — that's exactly what adding `...` does; without it, there's no
automatic list collection. **D** is wrong — there's no warning
mechanism here at all.

</details>

---

**Q4.** What does `lookup(local.retention_map, "archive", 7)` return if
`"archive"` is not a key in `local.retention_map`?

A. An error
B. `null`
C. `7` — the supplied default
D. `0`

<details>
<summary>Answer</summary>

**C.** `lookup()`'s third argument is exactly for this case — a
fallback returned when the key is missing, instead of erroring. **A**
is wrong — that's `map["key"]`'s behavior, not `lookup()`'s. **B** and
**D** are wrong — `lookup()` returns the explicit default supplied,
not `null` or `0` unless those were the default passed in.

</details>

---

**Q5.** What does `flatten([["a","b"], ["c","d"]])` return?

A. `[["a","b"], ["c","d"]]` — unchanged
B. `["a","b","c","d"]`
C. `"a,b,c,d"` — a single string
D. An error — `flatten()` requires uniform nesting depth

<details>
<summary>Answer</summary>

**B.** `flatten()` collapses one level of list nesting, producing a
single flat list. **A** is wrong — that would mean `flatten()` did
nothing, which defeats its purpose. **C** is wrong — the result is
still a list of strings, not a concatenated single string (that would
be `join()`). **D** is wrong — `flatten()` doesn't require uniform
nesting depth to function.

</details>

---

**Q6.** `for name in var.service_config` (a map), with only one loop
variable. What does `name` refer to on each iteration?

A. Both the key and the value, as a combined object
B. Only the key
C. Only the value
D. An error — maps require two loop variables

<details>
<summary>Answer</summary>

**B.** A single loop variable iterating a map binds to the key only —
the value is simply not accessible in that iteration. **A** is wrong —
there's no combined key+value object with one variable. **C** is
wrong — that's a common but incorrect assumption; single-variable
iteration always gets the key on a map. **D** is wrong — this is valid
syntax, just not necessarily what the author intended if they needed
the value too.

</details>

---

**Q7.** A `for_each`-driven `aws_cloudwatch_log_metric_filter` shows
`Sum: 0` in `get-metric-statistics`, despite confirmed matching log
lines in the log group. What's the most likely cause?

A. The metric filter pattern syntax is always wrong in this situation
B. The log events were written before the metric filter existed —
   filters don't process retroactively
C. CloudWatch metrics take 24 hours to populate
D. `for_each` doesn't support metric filters

<details>
<summary>Answer</summary>

**B.** Metric filters only count matching events from their own
creation forward — anything logged earlier is never retroactively
counted. **A** is wrong — the pattern could be entirely correct; timing
is the more likely culprit given "confirmed matching log lines." **C**
is wrong — CloudWatch metrics from log filters populate within
minutes, not 24 hours. **D** is wrong — `for_each` works fine with
metric filters; this demo uses exactly that combination successfully.

</details>

---

**Q8.** Which function combination is the inverse of using
`keys(map)`/`values(map)` to split a map into two lists?

A. `flatten(list)`
B. `lookup(map, key, default)`
C. `zipmap(keys, values)`
D. `merge(map1, map2)`

<details>
<summary>Answer</summary>

**C.** `zipmap()` takes a list of keys and a parallel list of values
and recombines them into a single map — the exact inverse operation.
**A** is wrong — `flatten()` deals with nested lists, unrelated to
map/list conversion. **B** is wrong — `lookup()` reads a single value
from an existing map, it doesn't reconstruct one. **D** is wrong —
`merge()` combines two existing maps; it doesn't build one from
separate key/value lists.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 10 |
| 7/8 | Review the wrong answer, then proceed |
| 6/8 | Re-read the relevant section, retry those questions |
| Below 6/8 | Re-read the full demo and redo the walkthrough before proceeding |
```