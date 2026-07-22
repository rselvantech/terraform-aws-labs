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

## How This Demo's Pieces Fit Together

**The AWS solution being built:** one CloudWatch Log Group per service
(`aws_cloudwatch_log_group.service`), each paired with its own metric
filter (`aws_cloudwatch_log_metric_filter.error_count`) — both
`for_each`-driven over the exact same source map, `var.service_config`.

**How the pieces connect, concretely:**
- `var.service_config` (one map: `auth`, `billing`, `notifications`,
  each with a `retention_days` and `tier`) is the single source every
  `for` expression in Parts A and B derives something from —
  `service_names`, `log_group_names`, `retention_by_service`,
  `critical_services`, `services_by_tier` are all different *shapes*
  of the same underlying data, never independently defined
- Part C's `aws_cloudwatch_log_group.service` is `for_each`-driven
  directly over `var.service_config` — `each.key` becomes the log
  group's name suffix (`/cloudnova/auth`), `each.value.retention_days`
  sets its retention
- **The metric filter is not independently `for_each`-driven in
  parallel — it's wired directly to the log group it belongs to:**
  `log_group_name = aws_cloudwatch_log_group.service[each.key].name`
  references the *actual created log group*, not just a
  reconstructed name string. If the log group's naming logic ever
  changed, the metric filter would follow automatically, because it
  reads the real resource's `.name` attribute rather than rebuilding
  `"/cloudnova/${each.key}"` a second time
- The result: one map key (e.g. `"auth"`) produces exactly one log
  group and exactly one metric filter, permanently linked by that
  same key — verified end-to-end in Part C by injecting real `ERROR`
  log lines and confirming the metric counts exactly them, nothing
  more

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
3. data.aws_ami is a data source that must resolve to a single AMI. 
   If the filters  match multiple AMIs, Terraform doesn't arbitrarily 
   choose one and instead raises an error. Setting most_recent = true 
   explicitly tells Terraform how to break the tie by selecting the 
   newest matching AMI. If you need all matching AMIs, use the aws_ami_ids 
   data source instead.

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

The trailing `...` after the value expression enables **grouping
mode** for a map-producing `for` expression. Normally, each generated
key must be unique; if two or more elements produce the same key,
Terraform raises a **duplicate object key error** — it does not
silently pick one and discard the rest. With `...`, Terraform instead
groups all values associated with the same key into a list, producing
a map whose values are lists (e.g. `map(list(string))`).

Confirmed directly — without `...`:
```
Error: Duplicate object key

Two different items produced the key "critical" in this 'for'
expression. If duplicates are expected, use the ellipsis (...) after
the value expression to enable grouping by key.
```

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

#### Map index access, briefly: 

`map["key"]` reads a map's value at a given key, the same way `list[0]` reads a list's value at a given
position — `{ auth = 30 }["auth"]` returns `30`. 
The difference from `lookup()` is what happens when the key is **missing**.

#### `lookup(map, key, default)` — Safe Map Reads

```hcl
lookup({ auth = 30, billing = 90 }, "notifications", 14)
# Result: 14 — "notifications" isn't a key, so the default is returned

lookup({ auth = 30, billing = 90 }, "auth", 14)
# Result: 30 — "auth" IS a key, so its actual value is returned
```

| | `map["key"]` | `lookup(map, "key", default)` |
|---|---|---|
| If the key exists | Returns its value | Returns its value |
| If the key is missing | **Errors** | Returns `default` |
| Use when | A missing key is a bug you want surfaced immediately | A missing key is expected and should degrade gracefully |

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

#### `for_each` — Brief Preview

`for_each = var.service_config` creates one resource instance per map
entry, addressed by key rather than position — `each.key` is the map
key (`"auth"`, `"billing"`, `"notifications"`), `each.value` is that
key's full object (`{ retention_days = 30, tier = "critical" }`, etc).
This demo uses `for_each` purely as a *consumer* of the maps built in
Parts A/B — full mechanics (`count` vs. `for_each`, splat expressions,
the decision framework for choosing between them) are Demo 10's
dedicated focus.

---

#### `aws_cloudwatch_log_group` — Parameters and the CloudWatch Concept

A **log group** is CloudWatch Logs' top-level container for a related
stream of log data — typically one per application or service. Nothing
is written to it directly; applications write to a **log stream**
inside a log group (Part C, Step 4, creates one manually via CLI to
simulate an application doing so).

| Argument | Required | Description |
|---|---|---|
| `name` | No — but always set | Log group name. Convention: `/` -separated, e.g. `/cloudnova/auth` |
| `retention_in_days` | No | How long CloudWatch keeps log events before automatic deletion. Must be one of a fixed set of AWS-allowed values (see Step 1's note above) |
| `tags` | No | Resource tags |

---

#### `aws_cloudwatch_log_metric_filter` — Parameters and the CloudWatch Concept

A **metric filter** is a pattern continuously applied to a log group's
incoming lines — every matching line increments a real CloudWatch
metric. This turns unstructured log text into a queryable, graphable
number, which is what makes Part C's result verifiable rather than
just "some log lines exist somewhere."

| Argument | Required | Description |
|---|---|---|
| `name` | Yes | Filter's own name — unique within the log group |
| `log_group_name` | Yes | Which log group this filter watches |
| `pattern` | Yes | CloudWatch Logs filter pattern syntax — `"ERROR"` matches any line containing that substring |
| `metric_transformation` | Yes (block) | Defines the metric this filter produces: `name`, `namespace`, and `value` (how much to increment per match — `"1"` here means "count occurrences") |

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

**What's new here: Amazon CloudWatch Logs.** CloudWatch Logs is AWS's
centralized log storage and search service — applications write log
lines to a **log group**, and CloudWatch retains, indexes, and lets you
search them without you managing any storage infrastructure yourself.
A **metric filter** is a pattern applied continuously to a log group's
incoming lines — every time a line matches, it increments a real
CloudWatch metric, turning unstructured log text into a queryable,
graphable number. This demo needs both: log groups so each service has
somewhere to write to, and metric filters so an `ERROR` line actually
produces a countable signal, not just text sitting in storage.

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

> **Note on `retention_in_days`:** this argument only accepts specific
> AWS-allowed values (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365,
> 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653, or 0 for
> "never expire") — not an arbitrary integer. `var.service_config`'s
> retention values (14, 30, 90) were chosen because they're all valid;
> an arbitrary number like `45` would fail at `apply` with an AWS-side
> validation error, not a Terraform-side one.

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
> **`log_group_name` references the *actual created resource*, not a
> reconstructed string.** `aws_cloudwatch_log_group.service[each.key].name`
> reads the real log group's `name` attribute — if `05-log-groups.tf`'s
> naming logic ever changed, this reference follows automatically. This
> also creates an implicit dependency: Terraform creates every log
> group before creating any metric filter, since each filter's
> `log_group_name` depends on its corresponding log group already
> existing.

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

> **What `for k, v in aws_cloudwatch_log_group.service` actually
> iterates over:** since `aws_cloudwatch_log_group.service` is
> `for_each`-driven, it isn't a single resource — it's a map of
> instances, one per key. Iterating it with a `for` expression gives
> you `k` = each instance's key (`"auth"`, `"billing"`,
> `"notifications"` — the same keys from `var.service_config`) and `v`
> = that **entire instance's full object** — every exported attribute
> the resource has (`arn`, `id`, `name`, `retention_in_days`, `tags`,
> etc.), not just the one you asked for. `v.name` then picks out just
> the `name` attribute from that full object. The result,
> `{ for k, v in ... : k => v.name }`, is a plain map — same shape as
> any other map-producing `for` expression, just built from a
> resource's instances instead of a variable or local.

### Step 4 — Apply & Verify

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

### Step 5 — Inject real log events

```bash
STREAM_NAME="auth-stream-primary"
aws logs create-log-stream --log-group-name "/cloudnova/auth" --log-stream-name "$STREAM_NAME" --profile default --region us-east-2

TS=$(date +%s000)
aws logs put-log-events \
  --log-group-name "/cloudnova/auth" \
  --log-stream-name "$STREAM_NAME" \
  --log-events \
    "timestamp=${TS},message=\"INFO user login succeeded\"" \
    "timestamp=${TS},message=\"ERROR failed to validate token\"" \
    "timestamp=${TS},message=\"ERROR database connection timeout\"" \
  --profile default \
  --region us-east-2
```

### Step 6 — Confirm the metric filter actually counted them

Wait a few seconds for CloudWatch to process the filter, then:

```bash
aws logs filter-log-events \
  --log-group-name "/cloudnova/auth" \
  --filter-pattern "ERROR" \
  --profile default \
  --region us-east-2
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
  --statistics Sum \
  --profile default \
  --region us-east-2
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
   expr]`), lists into maps (`{for x in list : k => v}`), and maps into
   maps (`{for k, v in map : new_k => new_v}`) — and the `...` suffix on
   a map-producing `for` expression groups colliding keys into a list
   instead of the hard `Duplicate object key` error that occurs without it
2. ✅ `if` inside a `for` expression filters elements out entirely —
   it doesn't provide a branch or alternative value
3. ✅ `keys()`/`values()` return corresponding-order lists; `zipmap()`
   reverses that (two parallel lists → one map); `lookup(map, key,
   default)` returns a fallback instead of erroring on a missing key,
   unlike `map[key]`; `flatten()` collapses a list of lists into one
4. ✅ `for_each` over a `for`-expression-derived map created one
   `aws_cloudwatch_log_group` per service, addressed via `each.key`/`each.value`
5. ✅ A `for_each`-driven `aws_cloudwatch_log_metric_filter` counted
   real, injected log events as a real CloudWatch metric, verified end-to-end

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `for` expression list→map form | TA-004 Obj 4e (variables/outputs and expressions) | Frequently tested — know the `{}`/`=>` syntax distinction from list→list |
| `if` filter in a `for` expression | TA-004 Obj 4e | Common trap: assuming it transforms rather than excludes |
| `...` grouping mode | TA-004 Obj 4 | Tests whether you know a genuine key collision errors without it — there is no silent default |
| `lookup()` vs. index syntax | TA-004 Obj 4e | Tests knowing which one errors on a missing key |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam shows `{for k, v in map : k => v if condition}` | Recognizing `if` excludes non-matching entries from the result entirely | Assuming excluded entries appear with a null/default value instead of being removed |
| Exam shows two services mapping to the same tier without `...` | Recognizing this is a hard `Duplicate object key` error, not a silent overwrite | Assuming Terraform silently keeps one value (last-write-wins) instead of erroring |
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
| A map-producing `for` expression errors with `Duplicate object key` | Two source elements produced the same key, and `...` wasn't used | Add `...` after the value expression to collect all matches into a list instead |
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

**Error 3 — `lookup()` on a genuinely missing key, no default supplied**
`lookup(local.wrong_brackets, "archive")` supplies only 2 arguments —
no default. Confirmed directly, the actual error is:
```
Error: Invalid function argument

Invalid value for "inputMap" parameter: the given object has no
attribute "archive".
```
This only surfaces at `terraform plan`, not `validate` — see the
timing note below. Fix: add a third argument —
`lookup(local.wrong_brackets, "archive", null)`

</details>

**Cleanup:**
```bash
cd src/break-fix/
rm -f terraform.tfstate terraform.tfstate.backup
cd ../..
```
No resources were created in this scenario (all three errors are caught
before any `apply`).


> **Why these errors surface at different stages — confirmed directly
> by running this exact scenario:**
> - **Error 1** (bracket/`=>` mismatch) is a genuine **HCL syntax**
>   error — Terraform's parser rejects it as invalid at the earliest
>   possible point. Confirmed: it surfaced during `terraform init`
>   itself, before `validate` was even run separately — `init` parses
>   every `.tf` file as part of its own processing, so a severe syntax
>   error blocks it immediately.
> - **Error 2** (single loop variable) never produces any error at any
>   stage — confirmed: `terraform validate` returned `Success!` even
>   with this line present. It's completely valid HCL; the "bug" is
>   purely a mismatch between what the code does and what the author
>   probably intended, discoverable only by inspecting the actual
>   value (e.g. via `terraform console`), never through `validate` or
>   `plan` output.
> - **Error 3** (`lookup()` on a missing key) requires actually
>   *evaluating* `local.wrong_brackets`'s real contents to discover
>   `"archive"` isn't present — that evaluation only happens at `plan`
>   (or `apply`), which is why `validate` succeeds first and the error
>   only appears one command later.

---

## Interview Prep

**Q1. A teammate writes `[for k, v in map : k => v]` and gets a syntax error. What's wrong, and what's the fix?**
The brackets (`[]`) signal a list-producing `for` expression, but `=>` is map-producing syntax — the two are incompatible. Terraform can't reconcile "give me a list" with "here's a key-value pair for each element." The fix is to match the syntax to the intent: `{for k, v in map : k => v}` if a map result is wanted (braces), or drop the `=>` entirely for a list result (`[for k, v in map : v]`, just the values as a list).

**Q2. What happens when `{for name, tier in services : tier => name}` (no `...`) is used and two services share a tier?**
It errors immediately — `Error: Duplicate object key`. Without the `...` grouping suffix, a map-producing `for` expression requires every generated key to be unique; Terraform refuses to guess which of two colliding values you meant, so it fails the `plan`/`validate` rather than silently picking one. Adding `...` after the value expression (`tier => name...`) changes the behavior to collect every match into a list under that key instead, resolving the collision by grouping rather than erroring.

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
   error immediately** — `Duplicate object key`, confirmed directly.
   `...` changes this to collect all matches into a list instead of
   erroring.

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
| `aws logs filter-log-events --filter-pattern PATTERN --profile default --region us-east-2` | Confirms a filter pattern's matches directly, independent of the metric |
| `aws cloudwatch get-metric-statistics --profile default --region us-east-2` | Confirms a metric filter is actually counting events |

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
"What is the syntax difference between a list-producing and a map-producing for expression?","List-producing: [for x in collection : expr] — square brackets. Map-producing: {for x in collection : key_expr => value_expr} — curly braces and =>. Mixing them (e.g. brackets with =>) is a syntax error.","demo09,for-expression,ta004-obj4e"
"Does if inside a for expression transform an element or exclude it?","Exclude it entirely. if in a for expression filters — non-matching elements are removed from the result completely, not transformed into a null/default value. There is no else branch.","demo09,for-expression,if,ta004-obj4e"
"Two services map to the same tier in {for name, tier in services : tier => name}, written without the ... suffix. What happens?","Last-write-wins silently — only the last-processed service for that tier survives in the result; the earlier one is overwritten with no error. Adding ... after the value expression (tier => name...) collects all matches into a list instead.","demo09,for-expression,grouping,ta004-obj4e"
"What is the difference between lookup(map, 'key', default) and map['key']?","map['key'] errors if the key doesn't exist. lookup(map, 'key', default) returns the default value instead of erroring. Use lookup() when a missing key is expected and should degrade gracefully; use index syntax when it should be a hard error.","demo09,functions,lookup,ta004-obj4e"
"What does zipmap(['a','b'], [1,2]) return?","{ a = 1, b = 2 } — zipmap combines a list of keys and a parallel list of values (same length, same order) into a single map. It's the inverse of using keys()/values() to split a map into two lists.","demo09,functions,zipmap"
"What does flatten([['a','b'], ['c']]) return?","['a', 'b', 'c'] — flatten collapses a list of lists into a single flat list. Commonly needed after a for expression that itself produces a list per source element.","demo09,functions,flatten"
"A for_each-driven metric filter shows Sum: 0 even though matching log lines clearly exist in the log group. What's the most likely cause?","The log events were written before the metric filter was created — filters only process events going forward from their own creation, not retroactively. Confirm by checking event timestamps against the filter's creation time.","demo09,metric-filter,troubleshooting"
"Why does a for expression's if clause matter more than it might seem for validation-style filtering?","Because it's the ONLY filtering mechanism for expressions have — there's no separate filter() function. Any collection filtering in Terraform HCL goes through a for expression's if clause.","demo09,for-expression,if"
"What loop variable(s) do you get iterating a map with a single variable, e.g. for name in var.service_config?","Only the key (name) — the value is not accessible with a single loop variable on a map. Use two loop variables (for name, config in var.service_config) to access both key and value.","demo09,for-expression,break-fix"
"Why does inverting a map ({for k,v in m : v => k}) risk silently losing entries?","If two original values are identical, they'd collide as the same new key. Without the ... grouping suffix, this is last-write-wins — one of the two entries silently disappears from the result, with no error.","demo09,for-expression,inversion,ta004-obj4e"
"In a for_each-driven resource where for_each = var.service_config (a map), what does each.key refer to for a given instance?","The map key for that instance — e.g. the string 'billing'. each.value is that key's corresponding map value (e.g. the object { retention_days = 90, tier = 'critical' }). Both are available inside the resource block for that specific instance.","demo09,for-each,ta004-obj4e"
"After applying 3 for_each-driven log groups and 3 for_each-driven metric filters for the first time, what does terraform apply report?","Resources: 6 added — each for_each instance counts individually toward the tally, regardless of how few resource blocks produced them (2 resource blocks, 6 total instances).","demo09,for-each,apply"
```

---

## Appendix — Quiz

**09-expressions-functions-quiz.md:**

````markdown
# Quiz — Demo 09: Expressions and Collection Functions

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 10.

---

**Q1. (Multiple Choice)** What syntax distinguishes a map-producing
`for` expression from a list-producing one?

- A) Map-producing uses `()`; list-producing uses `[]`
- B) Map-producing uses `{}` and `=>`; list-producing uses `[]` with no `=>`
- C) There's no syntactic difference — Terraform infers it from context
- D) Map-producing requires wrapping the whole expression in `map()`

<details>
<summary>Answer</summary>

**B.** `{for x in collection : key => value}` produces a map;
`[for x in collection : value]` produces a list. Mixing brackets with
`=>` is a genuine syntax error, not a style variation.

</details>

---

**Q2. (True/False)** A map-producing `for` expression that both reads
the key and computes a new value requires two loop variables — one
variable alone can't access both.

- A) True
- B) False

<details>
<summary>Answer</summary>

**A) True.** `{for name, config in map : name => config.field}` needs
both `name` and `config` bound — a single loop variable iterating a
map only binds to the key.

</details>

---

**Q3. (Multiple Choice)** `{for k, v in map : k => v if v > 10}` — what
happens to entries where `v <= 10`?

- A) They appear with a `null` value
- B) They are excluded from the result entirely
- C) They cause a validation error
- D) They're kept but marked invalid

<details>
<summary>Answer</summary>

**B.** `if` filters — non-matching entries are removed completely, not
transformed into a placeholder value. There's no error and no "else"
branch; this is the only filtering mechanism `for` expressions have.

</details>

---

**Q4. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about the `...` suffix on a map-producing `for` expression
are correct?

- A) Without it, colliding keys cause a hard `Duplicate object key` error
- B) With it, colliding keys are collected into a list under that key
- C) It's required syntax on every map-producing `for` expression
- D) It only works on list-producing `for` expressions
- E) Terraform silently keeps the last-processed value when keys collide, regardless of `...`

<details>
<summary>Answer</summary>

**A and B.** Confirmed directly: omitting `...` when two elements
produce the same key errors immediately —
`Error: Duplicate object key — Two different items produced the key
"critical" in this 'for' expression.` With `...`, every value that
maps to the same key is collected into a list instead of erroring.
It's optional (C is wrong), only meaningful on map-producing
expressions (D is wrong, backwards), and there is no silent
last-write-wins behavior at all, with or without `...` (E is wrong —
this is the key misconception the question tests).

</details>

---

**Q5. (Multiple Choice)** What is the difference between
`lookup(map, "key", default)` and `map["key"]` when `"key"` doesn't
exist?

- A) Both error identically
- B) `map["key"]` errors; `lookup()` returns the supplied default
- C) `lookup()` errors; `map["key"]` returns `null`
- D) Both silently return `null`

<details>
<summary>Answer</summary>

**B.** `lookup()` exists specifically to make a missing key a
non-error, graceful case. Index syntax (`map["key"]`) always errors on
a genuinely missing key — no silent `null` fallback either way.

</details>

---

**Q6. (Multiple Choice)** What does `zipmap(["a","b"], [1,2])` return?

- A) `[["a",1], ["b",2]]`
- B) `{ a = 1, b = 2 }`
- C) `["a","b",1,2]`
- D) An error — `zipmap()` requires matching types

<details>
<summary>Answer</summary>

**B.** `zipmap()` combines a list of keys and a parallel list of values
(same length, same order) into a single map — the inverse of splitting
a map with `keys()`/`values()`.

</details>

---

**Q7. (Multiple Choice)** What does `flatten([["a","b"], ["c"]])` return?

- A) `[["a","b"], ["c"]]` — unchanged
- B) `["a","b","c"]`
- C) `"a,b,c"` as a single string
- D) An error — nesting depths must match

<details>
<summary>Answer</summary>

**B.** `flatten()` collapses one level of list nesting into a single
flat list — commonly needed right after a `for` expression that itself
produces a list per source element.

</details>

---

**Q8. (Multiple Choice)** `for name in var.service_config` — a map —
using only one loop variable. What does `name` refer to?

- A) Both the key and value, combined
- B) Only the key
- C) Only the value
- D) An error — maps always require two loop variables

<details>
<summary>Answer</summary>

**B.** A single loop variable iterating a map always binds to the key
— the value simply isn't accessible without a second loop variable.
This is valid syntax, just possibly not what was intended if the value
was actually needed.

</details>

---

**Q9. (Multiple Choice)** A map-producing `for` expression attempts to
invert `{ auth = 30, billing = 90 }` into `{30 = "auth", 90 = "billing"}`,
written without the `...` suffix. What does this inversion silently
depend on?

- A) That the map has at least two entries
- B) That the original values are unique — if two services shared the same retention value, the inversion would error with a duplicate-key conflict
- C) That the values are strings, not numbers
- D) Nothing — inversion is always safe regardless of duplicate values

<details>
<summary>Answer</summary>

**B.** Inverting a map turns values into keys — if two original values
are identical, they'd collide as the same new key. Without `...`, this
errors immediately (`Duplicate object key`), the same way any other
key collision does — it does not silently drop or overwrite anything.
**D** is wrong for exactly that reason: inversion is only safe when
the original values are genuinely unique.

</details>

---

**Q10. (Multiple Choice)** `resource "aws_cloudwatch_log_group" "service"
{ for_each = var.service_config, name = "/cloudnova/${each.key}", ... }`
— what does `each.key` refer to for the `"billing"` entry?

- A) The entire `service_config` map
- B) The object `{ retention_days = 90, tier = "critical" }`
- C) The string `"billing"`
- D) The number `90`

<details>
<summary>Answer</summary>

**C.** With `for_each` over a map, `each.key` is the map key (the
service name string), and `each.value` is that key's corresponding
value (the object with `retention_days`/`tier`). `each.value.retention_days`
would be `90` — the number in D is accessible, but not via `each.key`.

</details>

---

**Q11. (Multiple Choice)** After applying 3 `for_each`-driven log
groups and 3 `for_each`-driven metric filters together for the first
time, what does `terraform apply` report?

- A) `Resources: 3 added` — only the log groups count
- B) `Resources: 6 added` — both resource types count individually
- C) `Resources: 1 added` — `for_each` collapses into one resource
- D) An error — two `for_each` resources can't reference each other

<details>
<summary>Answer</summary>

**B.** Each `for_each` instance counts individually toward the
resource tally — 3 log groups + 3 metric filters = 6 total, regardless
of how few `resource` blocks were written to produce them. `for_each` fully supports one resource referencing another's instances (D is wrong) — that's exactly how the metric filter's `log_group_name` gets each group's name.

</details>

---

**Q12. (Multiple Choice)** A `for_each`-driven metric filter shows
`Sum: 0` in `get-metric-statistics`, despite confirmed matching log
lines existing in the log group. What's the most likely cause?

- A) The metric filter pattern is always wrong in this scenario
- B) The log events were written before the metric filter existed — filters don't process retroactively
- C) CloudWatch metrics take 24 hours to populate
- D) `for_each` doesn't support metric filters

<details>
<summary>Answer</summary>

**B.** Metric filters only count matching events from their own
creation forward. Given the log lines are confirmed to match, timing
(events written before the filter existed) is the most likely
explanation, not a broken pattern.

</details>

---

**Q13. (True/False)** Terraform provides a dedicated `filter()`
function separate from the `for` expression's `if` clause.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** There is no standalone `filter()` function in HCL — the
`if` clause inside a `for` expression is the *only* collection
filtering mechanism the language provides.

</details>

---

**Q14. (Multiple Choice)** Why might a team choose `for_each` over
`var.service_config` directly (a map) rather than first converting it
with a `for` expression into a differently-shaped map?

- A) `for_each` cannot accept a map at all — it always requires a `for` expression first
- B) When the map's existing keys and values already have exactly the shape needed, no transformation is required before using it
- C) `for_each` only works with lists, never maps
- D) A `for` expression is always mandatory before `for_each`

<details>
<summary>Answer</summary>

**B.** `for_each` accepts a map or set directly — a `for` expression is
only needed when the *existing* shape doesn't already match what's
needed (e.g. deriving `log_group_names` for Part A's purposes). This
demo uses `var.service_config` directly in Part C precisely because
its existing shape (service name → config object) was already exactly
what `for_each` needed.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 13-14/14 | Import Anki cards, move to Demo 10 |
| 11-12/14 | Review the wrong answers, then proceed |
| 9-10/14 | Re-read the relevant sections, retry those questions |
| Below 9/14 | Re-read the full demo and redo the walkthrough before proceeding |
````