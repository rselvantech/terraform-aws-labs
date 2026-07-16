# Demo 06 — Locals in Depth: Computing Internal Values

---

## Overview

Demo 05 already used a `locals {}` block — it had to, in order to build
the IAM role's trust policy and tags — but treated it as a black box:
"just enough locals to make the lab work." That's fine for a demo whose
actual focus is variables, but it leaves real questions unanswered: when
should you reach for a local instead of a variable? How do locals chain?
What happens when two locals reference each other in a cycle? And is
everything about locals actually specific to the IAM role we've been
building, or does it generalize?

**Real-world scenario — CloudNova:** the platform team now needs a
second thing built from scratch: an SNS topic that CI/CD pipelines
publish deploy notifications to. The topic's name and access policy
should be composed the exact same way the IAM role's trust policy was
— which is exactly the proof this demo needs that locals aren't an
IAM-specific trick.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Recreate the Baseline (Demo 05's Role)                        │
│  Same IAM role and inline policy from Demo 05, brought back up as a     │
│  known-good starting point — no new teaching                            │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — try(), coalesce(), and merge() in Practice                    │
│  An optional role_config object   |   try() reads its optional fields   │
│  |   coalesce() falls through to a default   |   merge() composes tags  │
│  with right-most-wins                                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Applying Locals to a New Resource — SNS Topic                 │
│  local.name_prefix, local.common_tags, and local.trusted_principals     │
│  reused, unchanged, to name/tag/policy-secure an aws_sns_topic — proof  │
│  the pattern isn't IAM-specific                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- The distinction test — when to use a `local` instead of a `variable`
- Full `variable` vs. `local` comparison
- Locals type inference (locals have no `type` argument)
- Chaining locals and how Terraform resolves their dependency order
- Circular reference detection
- `try()`, `coalesce()`, `merge()`
- A policy document as a `jsonencode()` local
- **New:** applying all of the above to a second, unrelated resource —
  `aws_sns_topic` — to prove locals generalize beyond one example

---

## Prerequisites

### Knowledge
- Demo 05 completed — full variable argument set, operators, precedence,
  `can()`/`regex()`/`contains()`/`length()`/`alltrue()`, and the IAM
  role this demo continues building on

### Required Tools

Same as Demo 05 — Terraform `>= 1.15.0`, AWS CLI `>= 2.x`, `jq`.

**Required permissions for this demo** (adds SNS to Demo 05's IAM list):

```
iam:CreateRole, iam:DeleteRole, iam:GetRole, iam:ListRoles
iam:PutRolePolicy, iam:DeleteRolePolicy, iam:GetRolePolicy
iam:TagRole, iam:UntagRole, iam:ListRoleTags
iam:PassRole
sts:GetCallerIdentity
sns:CreateTopic, sns:DeleteTopic, sns:GetTopicAttributes
sns:SetTopicAttributes, sns:Publish, sns:TagResource
```

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Distinguish between a `variable` (external input) and a `local`
   (internal computed value) using the distinction test
2. ✅ Use `try()`, `coalesce()`, and `merge()` inside locals
3. ✅ Build a policy document as a `jsonencode()` local
4. ✅ Apply the same locals-composition pattern to a second, unrelated
   resource (`aws_sns_topic`), confirming locals aren't tied to one
   resource type

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| `aws_iam_role` / `aws_iam_role_policy` | Always free | **$0.00** | Continued from Demo 05 |
| `aws_sns_topic` | Always free — 1M publishes/month free forever | **$0.00** | New this demo |
| **Session total** | | **$0.00** | |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
06-locals-in-depth/
└── README.md   — all source files, Anki cards, and quiz embedded below
```

Source layout referenced throughout this README:

```
src/
├── 01-versions.tf
├── 02-provider.tf
├── 03-variables.tf     # Demo 05's full set + role_config + extra_tags (this demo's additions)
├── 04-locals.tf         # full locals depth — chaining, try/coalesce/merge, jsonencode
├── 05-main.tf           # aws_iam_role + aws_iam_role_policy (continued from Demo 05)
├── 06-sns.tf            # NEW — aws_sns_topic, locals-composed name + policy
├── 07-outputs.tf        # minimal outputs — full depth is Demo 07
└── break-fix/
    └── broken.tf
```

---

## Recall Check — Demo 05

Answer from memory before reading further:

1. A variable has `nullable = false` and a `default` set. A caller
   passes `null` explicitly. What value is actually used, and why?
2. What's the idiomatic pattern for validating a string against a regex
   inside a `validation` block, and why is it written that way instead
   of using `regex()` alone?
3. State the variable value precedence order from highest to lowest.

**Answers**

1. The `default` value is used, not `null`. With `nullable = false`,
   if `null` is passed, Terraform substitutes the default instead of
   letting `null` through — this is the opposite of the `nullable =
   true` (default) behavior, where passing `null` overrides to `null`
   even with a default present.
2. `can(regex(pattern, var.x))`. `regex()` alone errors when there's no
   match rather than returning `false` — `can()` converts that error
   into a boolean `false`, which is what a `validation` block's
   `condition` requires.
3. CLI `-var` flag (highest) > CLI `-var-file` > `*.auto.tfvars` >
   `terraform.tfvars` > `TF_VAR_` environment variables > `default`
   value (lowest).

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `locals` block (full depth) | Computed values | The distinction test, chaining, type inference |
| `try()` | Built-in function | Returns first argument that evaluates without error |
| `coalesce()` | Built-in function | Returns first argument that is not null and not empty string |
| `merge()` | Built-in function | Combines two or more maps; right-most value wins on key conflicts |
| Circular reference detection | Locals behavior | Terraform detects and errors on `local.a` ↔ `local.b` cycles at plan time |
| `jsonencode()` policy pattern | Locals pattern | Building an AWS policy document as a composed local |
| `aws_sns_topic` | Resource | New resource proving locals composition generalizes beyond IAM |

**Related constructs worth knowing (not used in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| `variable` block | External input | Demo 05 |
| `output` block (full depth) | Exposing values | Demo 07 |
| `for` expression (full) | Collection transformation | Demo 09 |
| `format()`, `join()`, `split()` | String functions | Demo 09 |
| `aws_iam_policy` (managed policy) | Standalone, reusable IAM policy | Not used in this series yet |

---

### Detailed Explanation of New Constructs

#### The Distinction Test — Variable vs. Local

> If you would ever want to override this value from outside the
> configuration (different per engineer, per environment, per run),
> it's a **variable**. If it's always derived from other values in
> the configuration and never needs external input, it's a **local**.

Locals earn their place when they compute something — a composed name,
a filtered list, a merged map. If you're tempted to write
`local.x = var.x` with no transformation, it should be a variable.

---

#### Variables vs. Locals — Full Comparison

| | `variable` | `local` |
|---|---|---|
| Set from outside? | Yes — CLI, env, tfvars, default | No — always internal |
| Type constraint | Declared explicitly with `type = ...` | None — **type is inferred** from the assigned expression |
| `description` argument | Yes | No |
| `sensitive` argument | Yes | No |
| `nullable` argument | Yes | No |
| `validation` block | Yes | No |
| Can reference resources? | No | Yes |
| Can reference data sources? | No | Yes |
| Can reference other locals? | No | Yes |
| Can reference other variables? | Only `var.<this variable>` in validation | Yes — `var.x` freely |
| Overridable per-run? | Yes | No |

> **Locals have no `type` argument.** Terraform infers the type from
> the assigned expression. A `{}` block where all values are strings
> is inferred as `map(string)`. Mixed value types produce
> `object({...})`. You cannot declare a type constraint on a local.

**What type is `common_tags` — `object` or `map`?**

```hcl
locals {
  common_tags = {
    ManagedBy   = "Terraform"       # string
    Project     = var.project       # string (var.project is type = string)
    Environment = var.environment   # string (var.environment is type = string)
  }
}
```

All three values are strings → Terraform infers `map(string)`. If one
value were a number (e.g. `Count = 3`), Terraform would infer
`object({ ManagedBy = string, Project = string, Environment = string, Count = number })`.
The `{}` literal produces a `map` when all values are the same type,
and an `object` when they differ.

---

#### Chaining Locals — Dependency Order

Locals can reference other locals. Terraform resolves the dependency
order automatically by building a DAG from the references in each
expression — the same mechanism it uses for resources.

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"    # Step 1
  role_name   = "${local.name_prefix}-deploy-role"    # Step 2 — depends on Step 1
  trust_policy = jsonencode({                          # Step 3 — depends on Step 2
    Statement = [{ Resource = "arn:aws:iam::*:role/${local.role_name}" }]
  })
}
```

`local.role_name` referencing `local.name_prefix` creates an implicit
dependency. Terraform always evaluates `name_prefix` → `role_name` →
`trust_policy`, regardless of the order they are written in the file.

**Circular references — what they look like and the error:**

```hcl
# BROKEN — circular reference
locals {
  a = "prefix-${local.b}"   # a depends on b
  b = "suffix-${local.a}"   # b depends on a — CIRCULAR
}
```

```
Error: Cycle in local values
  local.a -> local.b -> local.a
```

Terraform detects cycles at plan time and errors before evaluating any
value. The fix: break the cycle by identifying the shared value and
extracting it into a third local that neither side references back.

---

#### `try(expr1, expr2, ...)` — First Non-Erroring Expression

```
Syntax:   try(expression, fallback, ...)
Input:    one or more expressions
Returns:  the first expression that evaluates without error
Errors:   only if ALL arguments error
```

```hcl
# Safe attribute access — if var.config is null, .region errors;
# try() catches that and returns the fallback
try(var.config.region, "us-east-2")

# Multiple fallbacks
try(var.config.name, var.config.label, "default-name")

# Safe type conversion
try(tonumber(var.port_string), 8080)
```

**`try()` vs `can()` — when to use which:**

| | `try(expr, fallback)` | `can(expr)` |
|---|---|---|
| Returns | The value of the first non-erroring expression | `true` or `false` |
| Use when | You want the value with a fallback | You want to know IF it works (for a condition) |
| Example | `try(var.config.region, "us-east-2")` | `can(regex("^[a-z]+$", var.name))` |

---

#### `coalesce(val1, val2, ...)` — First Non-Null, Non-Empty Value

```
Syntax:   coalesce(value, value, ...)
Input:    any number of values of the same type
Returns:  the first value that is not null AND not empty string ("")
Errors:   if all arguments are null or empty string
```

```hcl
coalesce(var.custom_role_name, "${local.name_prefix}-deploy-role")
# If var.custom_role_name is null (default) → returns the computed name
# If var.custom_role_name is "" (empty)     → also returns the computed name
# If var.custom_role_name is "my-role"      → returns "my-role"

coalesce(null, "fallback")   # "fallback"
coalesce("", "fallback")     # "fallback" — empty string is also skipped
coalesce("real", "fallback") # "real"
```

> **`coalesce()` skips both `null` AND `""`** — empty string is treated
> the same as null. If you need to distinguish null from empty string,
> use a conditional: `var.x != null ? var.x : local.default`

**`try()` vs `coalesce()` — when to use which:**

| | `try(expr, fallback)` | `coalesce(val1, val2)` |
|---|---|---|
| Handles | Expression evaluation errors | null and empty string values |
| Use for | Optional object attributes, failing type conversions | "use this if set, otherwise this default" |
| Combined pattern | `coalesce(try(var.config.name, null), local.default)` | — |

---

#### `merge(map1, map2, ...)` — Combine Maps

```
Syntax:   merge(map, map, ...)
Input:    two or more maps of the same value type
Returns:  a single map; right-most value wins on key conflicts
```

```hcl
# Key conflict — right-most wins
merge(
  { Owner = "platform-team" },   # left
  { Owner = "devops-team" }      # right — wins
)
# Result: { Owner = "devops-team" }

# Practical pattern: base defaults + caller overrides
common_tags = merge(
  local.base_tags,
  var.extra_tags   # caller overrides any base tag by providing the same key
)
```

> **`merge()` order matters.** `merge(base, overrides)` means overrides
> win. `merge(overrides, base)` means base wins. Always put the
> "higher authority" map last.

---

#### Locals for a Second, Unrelated Resource — Proving the Concept Generalizes

Every example so far — `name_prefix`, `role_name`, `trust_policy`,
`common_tags` — feeds the same IAM role. That's a legitimate gap: it's
easy to walk away thinking these patterns are IAM-specific. They're
not. The SNS topic below reuses `local.name_prefix` and
`local.common_tags` (already built for the IAM role) and applies the
exact same `jsonencode()` + `merge()` pattern to a completely different
resource type and a completely different kind of policy (a resource
policy, not a trust policy):

```hcl
locals {
  # Reused from the IAM role's locals — proves name_prefix isn't role-specific
  sns_topic_name = "${local.name_prefix}-deploy-notifications"

  # A resource policy (who can publish/subscribe to this topic) — same
  # jsonencode() pattern as the IAM trust policy, different statement shape
  sns_topic_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountPublish"
        Effect    = "Allow"
        Principal = { AWS = local.trusted_principals } # reused — same list as the IAM trust policy
        Action    = "sns:Publish"
        Resource  = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sns_topic_name}"
      }
    ]
  })

  # merge() again — same pattern as the IAM role's tags, different resource
  sns_tags = merge(local.common_tags, {
    Purpose = "deploy-notifications"
  })
}
```

**What this demonstrates:** `local.name_prefix`, `local.common_tags`,
and `local.trusted_principals` were computed once and are now driving
two entirely unrelated resources. Nothing about `jsonencode()` or
`merge()` needed to change for a different resource type — the pattern
is general-purpose, not an IAM trick.

---

## Lab Step-by-Step Guide

---

## Part A — Recreate the Baseline (Demo 05's Role)

**What you accomplish in Part A:** bring Demo 05's finished IAM role
back up exactly as it was left — same provider, same variables, same
locals, same resources. Nothing here is new teaching; it exists purely
to give Part B and Part C a known-good starting point to extend.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/06-locals-in-depth/src
```

### Step 2 — Create the source files

All six files below recreate Demo 05's finished configuration verbatim
— copy them exactly, no changes yet.

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

  default_tags {
    tags = local.common_tags
  }
}
```

---

#### `03-variables.tf` — Demo 05's finished variable set, recreated

**What this file does in this demo:** provides the baseline inputs
(role/environment/project identity, sensitive/ephemeral demonstration
variables) this demo's locals work builds on top of — no new variables
until Part B adds `role_config` and `extra_tags`.

**03-variables.tf:** *(identical to Demo 05's `03-variables.tf` —
`aws_region`, `aws_profile`, `project`, `environment`, `demo`,
`role_purpose`, `trusted_account_ids`, `allowed_actions`,
`custom_role_name`, `external_secret_label`, `session_token`,
`max_session_duration`)*

---

#### `04-locals.tf` — Baseline locals, before this demo's additions

**What this file does in this demo:** recreates exactly what Demo 05
had before `try()`/`coalesce()`/`merge()` were introduced — Part B
extends this same block.

**04-locals.tf (baseline):**

```hcl
data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  role_name   = var.custom_role_name != null ? var.custom_role_name : "${local.name_prefix}-${var.role_purpose}-role"
  policy_name = "${local.name_prefix}-${var.role_purpose}-policy"

  trusted_principals = length(var.trusted_account_ids) > 0 ? [
    for id in var.trusted_account_ids : "arn:aws:iam::${id}:root"
  ] : ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]

  trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAssumeRole"
        Effect    = "Allow"
        Principal = { AWS = local.trusted_principals }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  permission_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowedActions"
        Effect   = "Allow"
        Action   = var.allowed_actions
        Resource = "*"
      }
    ]
  })

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Demo        = var.demo
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
  }
}
```

---

#### `05-main.tf` — The IAM role and its inline policy (baseline)

**What this file does in this demo:** recreates the same two resources
from Demo 05 unchanged — Part B is what actually modifies this file
with `local.role_description` and `local.effective_max_session`.

**05-main.tf:**

```hcl
resource "aws_iam_role" "deploy" {
  name                 = local.role_name
  description          = "CI/CD deploy role for ${var.project} ${var.environment}"
  assume_role_policy   = local.trust_policy
  max_session_duration = var.max_session_duration
  tags                 = local.common_tags
}

resource "aws_iam_role_policy" "deploy" {
  name   = local.policy_name
  role   = aws_iam_role.deploy.name
  policy = local.permission_policy
}
```

---

#### `07-outputs.tf` — Quick confirmation outputs

**What this file does in this demo:** identical purpose to Demo 05's
outputs file — Part C extends it with an SNS topic ARN output.

**07-outputs.tf:**

```hcl
output "role_name" {
  description = "Name of the IAM deploy role"
  value       = aws_iam_role.deploy.name
}

output "role_arn" {
  description = "ARN of the IAM deploy role"
  value       = aws_iam_role.deploy.arn
}
```

---

### Step 3 — Initialize and apply the baseline

```bash
terraform init
terraform validate
terraform apply
```

Expected: `Apply complete! Resources: 2 added, 0 changed, 0 destroyed.`
— same shape of output as Demo 05's apply.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## Part B — `try()`, `coalesce()`, and `merge()` in Practice

**What you accomplish in Part B:** this is where the demo's real
content starts. Add an optional structured config object, read it
safely with `try()` and `coalesce()`, and demonstrate `merge()`'s
right-most-wins tag composition — confirming each function's behavior
against a live `apply`.

### Step 1 — Add an optional config object variable

Add to `03-variables.tf`:

```hcl
variable "role_config" {
  type = object({
    description      = optional(string)
    path             = optional(string, "/")
    max_session_secs = optional(number, 3600)
  })
  description = "Optional structured role configuration. All fields are optional."
  default     = {}
  nullable    = false
}
```

### Step 2 — Add `try()` and `coalesce()` locals to `04-locals.tf`

Add inside the `locals {}` block:

```hcl
  # try() safely reads the optional description field — if null, returns fallback
  role_description = try(
    var.role_config.description,
    "CI/CD deploy role for ${var.project} ${var.environment}"
  )

  # coalesce(): try() extracts max_session_secs (null if omitted);
  # coalesce() falls through to var.max_session_duration if null
  effective_max_session = coalesce(
    try(var.role_config.max_session_secs, null),
    var.max_session_duration
  )
```

### Step 3 — Update `05-main.tf` and test

```hcl
resource "aws_iam_role" "deploy" {
  name                 = local.role_name
  description          = local.role_description
  path                 = try(var.role_config.path, "/")
  assume_role_policy   = local.trust_policy
  max_session_duration = local.effective_max_session
  tags                 = local.common_tags
}
```

```bash
# Without role_config — uses all defaults
terraform apply
# description = "CI/CD deploy role for cloudnova dev", max_session_duration = 3600

# With partial role_config — only description overridden
terraform apply -var='role_config={"description":"Platform deploy role"}'
# description = "Platform deploy role", max_session_duration = 3600 (unchanged)
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **Only `description` changed in the second apply.** The in-place
> update confirms `try()` correctly fell through to the default for
> `max_session_secs` since it wasn't provided in the partial object.

### Step 4 — Demonstrate `merge()` tag composition

Add to `03-variables.tf`:

```hcl
variable "extra_tags" {
  type        = map(string)
  description = "Additional tags to merge onto all resources — caller-provided tags override defaults"
  default     = {}
}
```

Update `common_tags` in `04-locals.tf`:

```hcl
  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      Demo        = var.demo
      ManagedBy   = "Terraform"
      Owner       = "platform-team"
    },
    var.extra_tags   # rightmost — caller overrides win
  )
```

```bash
terraform apply -var='extra_tags={"CostCenter":"platform","Owner":"devops-team"}'
```

Expected — "Owner" in `extra_tags` wins (right-most-wins):

```
Console → IAM → cloudnova-dev-deploy-role → Tags
  → Owner: devops-team   (overridden — right-most wins) ✅
  → CostCenter: platform (added by extra_tags) ✅
```

```bash
terraform apply   # no extra_tags — reverts to defaults
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **This `merge()` change affects every resource, not just the IAM
> role.** `local.common_tags` is applied via `default_tags` in the
> provider block (Part A, Step 2), so this ripples everywhere — worth
> noting before Part C creates the SNS topic, which inherits these same
> tags.

---

## Part C — Applying Locals to a New Resource — SNS Topic

**What you accomplish in Part C:** the same `jsonencode()`/`merge()`
pattern applied to a resource that has nothing to do with IAM, reusing
`local.name_prefix`, `local.common_tags`, and `local.trusted_principals`
computed in Part A and B — the concrete proof that this demo's
patterns aren't IAM-specific.

### Step 1 — Create `06-sns.tf`

#### `06-sns.tf` — The SNS topic, proving locals generalize

**What this file does in this demo:** declares `aws_sns_topic.deploy_notifications`,
named and policy-secured entirely from locals already built for the
IAM role — the concrete proof that this demo's patterns aren't
IAM-specific.

**06-sns.tf:**

```hcl
locals {
  sns_topic_name = "${local.name_prefix}-deploy-notifications"

  sns_topic_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountPublish"
        Effect    = "Allow"
        Principal = { AWS = local.trusted_principals }
        Action    = "sns:Publish"
        Resource  = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sns_topic_name}"
      }
    ]
  })

  sns_tags = merge(local.common_tags, {
    Purpose = "deploy-notifications"
  })
}

resource "aws_sns_topic" "deploy_notifications" {
  name   = local.sns_topic_name
  policy = local.sns_topic_policy
  tags   = local.sns_tags
}
```

### Step 2 — Apply and verify with a real published message

Add a quick output to `07-outputs.tf` to get the ARN:

```hcl
output "sns_topic_arn" {
  description = "ARN of the deploy-notifications SNS topic"
  value       = aws_sns_topic.deploy_notifications.arn
}
```

```bash
terraform apply
aws sns publish \
  --topic-arn "$(terraform output -raw sns_topic_arn)" \
  --message "Demo 06 locals verification — $(date -u +%FT%TZ)"
```

Expected:

```json
{
    "MessageId": "a1b2c3d4-5678-90ab-cdef-1234567890ab"
}
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **A real `MessageId` confirms the topic is actually functional, not
> just present in state** — it accepted and processed a real publish
> request. No subscriber is configured (avoiding overlap with Demo 10's
> SQS introduction), so the `MessageId` itself is the verifiable proof.

### Step 3 — Confirm the naming and tags reused the IAM role's locals

```bash
aws sns list-tags-for-resource --resource-arn "$(terraform output -raw sns_topic_arn)"
```

Expected: tags include `Environment: dev`, `ManagedBy: Terraform`, and
`Purpose: deploy-notifications` — the first three inherited unchanged
from `local.common_tags`, the last one added specifically for this
resource via `merge()`.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## Cleanup

```bash
terraform destroy
```

Type `yes`. Expected: `Destroy complete! Resources: 3 destroyed.`
(IAM role, inline policy, SNS topic).

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

```
Console → IAM → Roles → cloudnova-dev-deploy-role: GONE ✅
Console → SNS → Topics → cloudnova-dev-deploy-notifications: GONE ✅
```

---

## What You Learned

1. ✅ The distinction test: if the value needs external input, it's a
   variable; if always derived from other values, it's a local. Locals
   type is inferred; you cannot declare a type constraint on a local
2. ✅ `try()` returns the first non-erroring expression; `coalesce()`
   returns the first non-null non-empty value; `merge()` combines maps
   with right-most-wins on key conflicts
3. ✅ Building a policy document as a composed `jsonencode()` local
4. ✅ The same locals-composition pattern (`name_prefix`,
   `common_tags`, `trusted_principals`, `jsonencode()`, `merge()`)
   applied cleanly to an unrelated `aws_sns_topic` resource — proof
   locals aren't an IAM-specific trick

---

## Cert Tips — TA-004 Objectives Covered

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `coalesce()` skipping null AND `""` | TA-004 Obj 2 (Terraform basics / core concepts) | Common exam trap assumes it only skips `null` |
| Locals have no `type` argument | TA-004 Obj 2 | Type is always inferred from the assigned expression |
| `try()` vs `coalesce()` | TA-004 Obj 2 | Different problems — evaluation errors vs. null/empty values — frequently confused |
| Circular local reference detection | TA-004 Obj 2 | Caught at plan time with "Cycle in local values," not silently resolved |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam asks what `coalesce(var.x, "fallback")` returns when `var.x = ""` | Recognizing `coalesce()` skips both `null` and `""`, returning `"fallback"` | Assuming `""` counts as "set" since it isn't `null`, expecting `""` to be returned |
| Exam shows `merge(map_a, map_b)` with a shared key and asks the result | Identifying that the right-most map (`map_b`) wins on key conflicts | Assuming the first-listed map wins, or that `merge()` errors on duplicate keys |
| Exam gives two locals referencing each other | Recognizing this is a plan-time cycle error, not a runtime issue | Assuming Terraform picks an arbitrary evaluation order and one side "just gets an empty value" |

### Exam Task — Write a complete configuration

**Task:** CloudNova needs a locals-driven naming and tagging setup for
a new CloudWatch Log Group: a `local.log_group_name` composed from
`var.project`/`var.environment`, a `local.retention_days` using
`coalesce()` to fall back to `14` if an optional variable is unset, and
a `local.log_tags` using `merge()` so caller-supplied tags override a
base set. Write all three locals plus the variable declarations from
scratch.

**Block types required:** `locals`, `variable` (×2 — an optional
retention override and a caller tags map)

**Official documentation:**
- [Local Values](https://developer.hashicorp.com/terraform/language/values/locals)
- [`coalesce` Function](https://developer.hashicorp.com/terraform/language/functions/coalesce)

**What to practise:**
1. Open the Local Values page — confirm there is no `type` argument
   documented anywhere in the block reference
2. Write the configuration from scratch without looking at this demo's
   `04-locals.tf`
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
variable "retention_days_override" {
  type        = number
  description = "Optional override for log retention in days"
  default     = null
}

variable "extra_log_tags" {
  type        = map(string)
  description = "Additional tags — caller-provided tags override defaults"
  default     = {}
}

locals {
  log_group_name  = "${var.project}-${var.environment}-app-logs"
  retention_days  = coalesce(var.retention_days_override, 14)
  log_tags = merge(
    { ManagedBy = "Terraform", Project = var.project },
    var.extra_log_tags
  )
}
```

**Arguments you must know without looking up:**
- `coalesce(var.x, default)` — skips both `null` and `""`, not just `null`
- `merge(base, overrides)` — right-most map wins on key conflicts

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `coalesce()` ignores a value you expected it to use | `coalesce()` skips null AND `""` | Use a conditional expression if you need to distinguish null from empty string |
| `Error: Cycle in local values` | Two or more locals reference each other circularly | Break the cycle — extract the shared value into a third local |
| `try()` always falls through to the fallback, even when the attribute should exist | The object type doesn't actually have that field, or a typo in the attribute name | Check the variable's `object({...})` type definition for the exact field name |
| SNS topic policy `Resource` ARN doesn't match the topic's actual ARN | Region, account ID, or topic name mismatch in the manually-constructed ARN string | Prefer referencing `aws_sns_topic.x.arn` directly where possible instead of reconstructing the ARN string, to avoid drift between the two |

---

## Break-Fix Scenario

Three deliberate errors — all locals-specific, none inherited from
Demo 05. Diagnose using `terraform validate` and `terraform plan`.

```bash
cd src/break-fix/
terraform init
terraform validate
terraform plan
```

#### `broken.tf` — Three deliberate locals-specific errors

**What this file does in this demo:** a self-contained configuration
with a circular local reference, a misleading map key named `type`,
and a reversed `merge()` argument order — diagnose all three without
looking at the answers first.

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

locals {
  # Error 1: circular reference
  a = "prefix-${local.b}"
  b = "suffix-${local.a}"

  # Error 2: attempting a type argument on a local (not valid HCL for locals)
  c = {
    type  = string   # locals have no type argument — this is just a map key
    value = "test"
  }

  base_tags = {
    Owner = "platform-team"
  }
  caller_tags = {
    Owner = "devops-team"
  }
  # Error 3: merge() argument order reversed — base wins instead of caller
  common_tags = merge(local.caller_tags, local.base_tags)
}

output "common_tags_result" {
  value = local.common_tags
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — circular local reference**
`local.a` references `local.b`, and `local.b` references `local.a`.
`terraform plan` errors: `Error: Cycle in local values: local.a ->
local.b -> local.a`. Fix: identify what value both sides actually need
and extract it into a third local neither references back to — e.g.
`base = "shared"`, then `a = "prefix-${local.base}"` and `b =
"suffix-${local.base}"`.

**Error 2 — this isn't actually an error, and that's the point**
`local.c`'s `type` key is not a Terraform keyword here — locals have no
`type` argument at the block level, but nothing stops you from naming
an ordinary map key `type`. This block is valid HCL: `local.c` is
simply a map `{ type = "string", value = "test" }`. The "bug" is
conceptual, not syntactic — a learner might expect this to declare a
type constraint the way `variable` blocks do, and it silently does not.
Diagnosed by checking `terraform console` and confirming
`local.c.type` returns the literal string `"string"`, not a type
constraint being enforced anywhere.

**Error 3 — `merge()` argument order reversed**
`merge(local.caller_tags, local.base_tags)` puts `base_tags` last, so
`base_tags`'s `Owner = "platform-team"` wins over `caller_tags`'s
`Owner = "devops-team"` — the reverse of the intended "caller
overrides base" behavior. Not a `validate`-time error — diagnosed by
comparing expected vs. actual: `terraform plan` shows
`common_tags_result` as `{ Owner = "platform-team" }` when
`devops-team` was expected. Fix: reverse the argument order —
`merge(local.base_tags, local.caller_tags)`.

</details>

**Cleanup:**
```bash
cd src/break-fix/
rm -f terraform.tfstate terraform.tfstate.backup
cd ../..
```
No resources were created (all three issues are caught or observed
before any `apply`).

---

## Interview Prep

**Q1. You have a locals block with `name_prefix`, `role_name`, and `trust_policy` chained together. If you write them in reverse order in the file, does this affect the result?**
No. Local declaration order has no effect — Terraform resolves dependency order automatically from the references within each expression, exactly as it does for resources. `trust_policy` referencing `local.role_name` creates an implicit dependency; Terraform always evaluates `name_prefix` → `role_name` → `trust_policy` regardless of file order.

**Q2. What is the difference between `merge(map_a, map_b)` and `merge(map_b, map_a)`?**
`merge()` uses right-most-wins for key conflicts. `merge(map_a, map_b)` means `map_b` wins; `merge(map_b, map_a)` means `map_a` wins. In the tag pattern, `merge(local.common_tags, var.extra_tags)` means caller-provided tags win over defaults — the intended behavior. Reversing it would mean common tags always override caller input.

**Q3. A teammate asks why the SNS topic's policy uses `jsonencode()` and `local.trusted_principals` — the same values used for the IAM role's trust policy. Isn't that IAM-specific machinery?**
No — `jsonencode()` is a general-purpose function for producing any JSON document, and `local.trusted_principals` is just a list of ARN strings computed once. The IAM trust policy and the SNS resource policy both happen to need "which principals are allowed to do X," so reusing the same computed list avoids re-deriving it twice. Nothing about either construct is IAM-specific — the same pattern would apply to an S3 bucket policy or a KMS key policy just as easily.

---

## Key Takeaways

1. **The distinction test: would you ever override this from outside?**
   Yes = variable. No = local. Locals have no `type` argument — type is
   inferred from the expression.

2. **`try()` handles errors; `coalesce()` handles null and empty
   string.** Combine them: `coalesce(try(var.config.name, null), local.default)`.

3. **`merge()` order matters — put the "higher authority" map last.**
   `merge(base, overrides)` means overrides win; reversing it silently
   flips that.

4. **Circular local references are caught at plan time, not silently
   resolved.** `local.a` ↔ `local.b` produces a clear "Cycle in local
   values" error.

5. **Locals composed once can drive multiple, unrelated resources.**
   `name_prefix`, `common_tags`, and `trusted_principals` — all built
   for the IAM role — fed the SNS topic's name, tags, and policy
   without any IAM-specific logic anywhere in that reuse.
> **Demo scope:** Primary concept: Terraform locals — the distinction
> test, chaining, type inference, and `try()`/`coalesce()`/`merge()`.
> Supporting concepts: circular-reference detection, `jsonencode()`
> policy composition, and reusing locals across unrelated resource
> types.
> Estimated completion time: 40 minutes (reading + hands-on + verification).
> Checkpoints: 3 natural stopping points (end of Part A, end of Part B,
> end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `try(expr, fallback, ...)` | Returns the first expression that evaluates without error |
| `coalesce(val1, val2, ...)` | Returns the first value that is not null and not empty string |
| `merge(map1, map2, ...)` | Combines maps; right-most value wins on key conflicts |
| `jsonencode(value)` | Converts an HCL value into a JSON-encoded string — used for policy documents |
| `terraform console` | Opens an interactive expression evaluator — useful for checking a local's inferred type or value directly |
| `terraform plan -var='extra_tags={"K":"V"}'` | Overrides a map-typed variable from the CLI |
| `aws sns publish --topic-arn ARN --message MSG` | Publishes a real message to an SNS topic — used here to verify the topic is functional |

---

## Next Demo

**Demo 07 — Outputs, Sensitivity, and Remote State:** `sensitive` and
`ephemeral` on outputs, `depends_on` on outputs, all `terraform output`
variants, `terraform_remote_state`, and writing the SNS topic ARN
(built in this demo) to SSM Parameter Store as a second, decoupled
sharing pattern.

---

## Appendix — Anki Cards

**06-locals-in-depth-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::06-locals-in-depth
#separator:Comma
#columns:Front,Back,Tags
"What is the distinction test for variable vs. local?","If you would ever want to override this value from outside the configuration (different per environment, engineer, or run) — it is a variable. If it is always derived from other values in the configuration and never needs external input — it is a local. Locals earn their place through transformation, not pass-through.","demo06,locals,variables,distinction"
"What are three key differences between variables and locals?","(1) Variables can be set from outside (CLI, env, tfvars); locals cannot. (2) Variables have type/description/sensitive/nullable/validation arguments; locals have none of these. (3) Locals can reference resources and data sources; variables cannot (only var.<this_variable> in validation).","demo06,variables,locals,comparison"
"Do locals have a type argument? How is a local's type determined?","No type argument exists for locals. Terraform infers the type from the assigned expression. A locals block with all string values is inferred as map(string). Mixed value types produce object({...}). You cannot declare a type constraint on a local.","demo06,locals,types"
"What type does Terraform infer for a local defined as { Project = var.project, Environment = var.environment } when both variables are type = string?","map(string) — all values are strings. If any value were a different type (e.g. a number), Terraform would infer object({...}) instead.","demo06,locals,types"
"What does coalesce(null, '', 'first-real', 'second') return?","'first-real' — coalesce() skips both null AND empty string (''), returning the first value that is neither. Empty string is treated the same as null.","demo06,locals,coalesce,ta004"
"What is the difference between try() and coalesce()?","try(expr, fallback) catches ERRORS — returns the first argument that evaluates without error. coalesce(val1, val2) skips null and empty string — returns the first non-null, non-empty value. Use try() for optional object attributes or failing type conversions. Use coalesce() for 'use this value if set, otherwise fall back.'","demo06,locals,try,coalesce"
"You call merge(local.common_tags, var.extra_tags). Both have key 'Owner'. Which value appears?","var.extra_tags's value — merge() uses right-most-wins for key conflicts. merge(common, extra) means extra wins. merge(extra, common) would mean common wins.","demo06,locals,merge"
"Can locals reference other locals? Does the order they are written in matter?","Yes, locals can reference other locals. No, order does not matter — Terraform resolves the dependency order automatically from references within each expression, exactly as it does for resources.","demo06,locals,ordering"
"What happens if two locals reference each other circularly?","terraform plan errors: 'Cycle in local values: local.a -> local.b -> local.a'. Detected at plan time before evaluating any value. Fix: break the cycle by extracting the shared value into a third local that neither side references back.","demo06,locals,circular"
"A locals block has a map value with a key literally named 'type', e.g. local.c = { type = string, value = 'test' }. Does this declare a type constraint on local.c?","No — locals have no type-constraint mechanism at all. 'type' here is just an ordinary map key holding the string value 'string' (or whatever expression follows it). It looks like it might be enforcing something the way variable blocks do, but it is not — local.c.type just returns that literal value.","demo06,locals,break-fix"
"The same jsonencode()+merge() pattern used for an IAM trust policy is applied to an SNS topic's resource policy. Does this mean the pattern is IAM-specific?","No — jsonencode() and merge() are general-purpose functions with no awareness of which AWS resource consumes their output. The same locals (name_prefix, common_tags, trusted_principals) can drive any number of unrelated resources without any IAM-specific logic in that reuse.","demo06,locals,jsonencode,generalization"
"Why does merge(local.caller_tags, local.base_tags) silently produce the wrong result if the intent was 'caller overrides base'?","Because merge() is right-most-wins, and base_tags is listed last here — so base_tags's values win over caller_tags's, the opposite of the intended behavior. There's no error; it just silently applies the wrong precedence. Fix: reverse the argument order.","demo06,locals,merge,break-fix"
```

---

## Appendix — Quiz

**06-locals-in-depth-quiz.md:**
````markdown
# Quiz — Demo 06: Locals in Depth

> One correct answer per question unless stated otherwise.
> Target: 80% or above before moving to Demo 07.
> TA-004 exam style.

---

**Q1.** What is the distinction test for choosing a `local` over a
`variable`?

A. Locals are for strings; variables are for everything else
B. If the value would ever need to be overridden from outside the
   configuration, it's a variable; if it's always derived internally,
   it's a local
C. Locals are faster to evaluate than variables
D. There is no meaningful distinction — they're interchangeable

<details>
<summary>Answer</summary>

**B.** The distinction is about external overridability, not type or
performance. A local that's just `local.x = var.x` with no
transformation should be a variable instead. **A** is wrong — locals
can hold any type (maps, lists, objects, numbers), not just strings.
**C** is wrong — there is no meaningful performance difference between
a local and a variable; that's not the basis for the distinction at
all. **D** is wrong — locals cannot be overridden from outside the
configuration the way variables can, which is precisely the point of
the distinction test.

</details>

---

**Q2.** Do `locals` blocks support a `type` argument like `variable`
blocks do?

A. Yes — locals require an explicit `type`
B. No — Terraform infers the type from the assigned expression
C. Only for collection types (list, set, map)
D. Only if `strict_types = true` is set on the block

<details>
<summary>Answer</summary>

**B.** Locals have no `type` argument at all. Terraform infers the type
from whatever expression is assigned — a `{}` of all-string values
infers as `map(string)`; mixed types infer as `object({...})`. **A** is
wrong — this is exactly the trap; there is no `type` argument to
require. **C** is wrong — the lack of a `type` argument applies to
every kind of local, not just collections. **D** is wrong —
`strict_types` isn't a real Terraform argument for `locals` blocks at all.

</details>

---

**Q3.** What does `coalesce(var.custom_name, local.computed_name)`
return when `var.custom_name` is set to `""`?

A. `""` — coalesce returns the first non-null value, and `""` is not null
B. `local.computed_name` — coalesce skips both null AND empty string
C. An error — coalesce requires at least one non-null argument
D. `null`

<details>
<summary>Answer</summary>

**B.** `coalesce()` skips both `null` and `""` — empty string is
treated the same as null. Only a non-null, non-empty string satisfies
coalesce. **A** is wrong — this is exactly the misconception the
question is testing; `""` not being `null` doesn't stop `coalesce()`
from skipping it. **C** is wrong — `coalesce()` only errors if *every*
argument is null or empty; here `local.computed_name` provides a
fallback. **D** is wrong — `coalesce()` never returns `null` when a
valid fallback is available.

</details>

---

**Q4.** You call `merge(local.common_tags, var.extra_tags)`. Both have
key `"Owner"`. Which value appears in the result?

A. `local.common_tags`'s value — the left-most map wins
B. `var.extra_tags`'s value — the right-most map wins
C. Both values are combined into a list
D. An error — duplicate keys are not allowed in merge()

<details>
<summary>Answer</summary>

**B.** `merge()` uses right-most-wins for key conflicts. `var.extra_tags`
is rightmost, so its `"Owner"` value overrides `local.common_tags`'s.
**A** is wrong — it reverses `merge()`'s actual precedence rule. **C**
is wrong — `merge()` produces a single flat map, never a list of
conflicting values. **D** is wrong — `merge()` is specifically designed
to handle key conflicts via right-most-wins; it never errors on them.

</details>

---

**Q5.** Two locals are written as `a = "prefix-${local.b}"` and
`b = "suffix-${local.a}"`. What happens?

A. Terraform resolves them in file order, using whichever is empty
   first as a seed
B. `terraform plan` errors with "Cycle in local values"
C. Both resolve to empty strings silently
D. Only the first-declared local (`a`) is evaluated; `b` is ignored

<details>
<summary>Answer</summary>

**B.** Circular local references are detected at plan time and produce
a clear cycle error, not a silent or partial resolution. Fix by
extracting the shared value into a third local neither side references
back to. **A** is wrong — there's no "empty seed" mechanism; Terraform
doesn't guess an evaluation order for a genuine cycle. **C** is wrong —
nothing resolves silently; the cycle is caught before any value is
computed. **D** is wrong — declaration order in the file has no bearing
on which local Terraform attempts to evaluate first; both sides of a
real cycle are equally blocked.

</details>

---

**Q6.** What is the key difference between `try(expr, fallback)` and
`coalesce(val1, val2)`?

A. They are functionally identical
B. `try()` catches evaluation errors; `coalesce()` catches null and
   empty-string values — different problems entirely
C. `coalesce()` only works on numbers; `try()` only works on strings
D. `try()` requires exactly two arguments; `coalesce()` allows any number

<details>
<summary>Answer</summary>

**B.** `try()` is for expressions that might error (e.g. accessing an
optional object attribute that might not exist). `coalesce()` is for
values that might be null or empty string. They solve different
problems and are often combined: `coalesce(try(var.config.name, null),
local.default)`. **A** is wrong — this is the misconception the
question tests directly; the two functions solve distinct problems.
**C** is wrong — neither function is restricted to a single type;
both work across strings, numbers, and other value types. **D** is
wrong — `try()` actually accepts any number of fallback expressions,
and `coalesce()` requires at least one non-null argument to succeed,
not an unlimited count with no constraint.

</details>

---

**Q7.** A locals block reuses `local.name_prefix` and `local.common_tags`
(already built for an IAM role) to name and tag a new, unrelated SNS
topic. What does this demonstrate?

A. That SNS topics require IAM-specific configuration
B. That `jsonencode()` and `merge()` are general-purpose and not tied
   to any one resource type
C. That locals must always be reused across at least two resources
D. Nothing — this is considered an anti-pattern

<details>
<summary>Answer</summary>

**B.** Locals composed once (`name_prefix`, `common_tags`,
`trusted_principals`) can drive any number of resources. Nothing about
`jsonencode()` or `merge()` is IAM-specific — the pattern generalizes.
**A** is wrong — it reverses the demonstration's actual point; nothing
about SNS required IAM-specific setup. **C** is wrong — reuse across
multiple resources is a nice outcome, not a requirement locals must
satisfy to be valid. **D** is wrong — reusing already-computed values
across unrelated resources is standard, encouraged practice, not an
anti-pattern.

</details>

---

**Q8.** A `locals` block is:
```hcl
locals {
  common_tags = {
    ManagedBy   = "Terraform"
    Project     = var.project
    Environment = var.environment
  }
}
```
Assuming `var.project` and `var.environment` are both `type = string`,
what type does Terraform infer for `local.common_tags`?

A. `object({ ManagedBy = string, Project = string, Environment = string })`
B. `map(string)`
C. `tuple([string, string, string])`
D. `any` — locals are always untyped

<details>
<summary>Answer</summary>

**B.** All three values are strings, so Terraform infers `map(string)`
— a map, not an object. **A** is wrong — `object({...})` is inferred
only when the values have *different* types; here they're
homogeneous. **C** is wrong — `tuple` is for ordered, positional
values, not a `{}` key-value literal like this one. **D** is wrong —
"no `type` argument" (Q2) doesn't mean "no type at all"; Terraform
still infers a concrete type, it's just not user-declared.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 07 |
| 7/8 | Review the wrong answer, then proceed |
| 5–6/8 | Re-read the relevant section, retry those questions |
| Below 5/8 | Re-read the full demo and redo the walkthrough before proceeding |
````