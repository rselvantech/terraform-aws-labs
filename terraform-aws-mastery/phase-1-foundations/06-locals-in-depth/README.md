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

Same as Demo 05 — Terraform `>= 1.15.0`, AWS CLI `>= 2.x`.

### Verify AWS Account and Permissions

```bash
aws sts get-caller-identity --profile default
aws configure get region --profile default
```

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

> For a learning account, `IAMFullAccess` and `AmazonSNSFullAccess`
> managed policies cover the permissions above.

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
├── README.md
├── 06-locals-in-depth-anki.csv
├── 06-locals-in-depth-quiz.md
└── src/
    ├── 01-versions.tf       # terraform block + provider version constraints
    ├── 02-provider.tf       # AWS provider: region, profile, default_tags
    ├── 03-variables.tf      # Demo 05's finished variable set, recreated
    ├── 04-locals.tf         # full locals depth — chaining, try/coalesce/merge, jsonencode
    ├── 05-main.tf           # aws_iam_role + aws_iam_role_policy (continued)
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

<details>
<summary>Answers</summary>

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

</details>

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

**Why this asymmetry exists — locals can reference almost anything,
variables can barely reference themselves:** it comes down to *when*
each one is resolved, in Terraform's evaluation order (the same order
introduced in Demo 05's validation section):

1. Variables are resolved first — before locals exist, before the
   provider is configured, before any data source has been read, and
   before any resource has been planned
2. Locals are computed after that — so a local can safely reference
   any variable (already resolved), any resource or data source
   (already part of the dependency graph by the time locals run), and
   any other local (Terraform builds a dependency order among locals
   automatically)

A `variable`'s `validation` block runs at step 1, before step 2 even
begins — there's nothing for it to reference yet except the variable's
own value. A `local`, by definition, only ever gets evaluated at
step 2 or later, so everything from step 1 is already available to it.
This is the same reasoning Demo 05 used to explain why `validation`
can't see other variables or resources — locals simply run at a later
point where those things already exist.

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

**Why is `merge()` map-specific — is there no equivalent for `list`,
`set`, or `tuple`?** `merge()` solves one specific problem: what to do
when two collections have *conflicting keys*. That problem only exists
for maps/objects, since only they have keys at all — a list is just
positions, and a set has no positions or keys, only membership. So
`merge()` genuinely has no reason to exist for the other three types;
the *concept* of "combine two collections" still applies to them, just
solved by different functions suited to what each type actually is:

| Type | "Combine two of them" function | What it does |
|---|---|---|
| `map`/`object` | `merge(map1, map2)` | Combines keys; right-most wins on conflicts |
| `list`/`tuple` | `concat(list1, list2)` | Appends one list after another — no "conflict" concept, just concatenation |
| `set` | `setunion(set1, set2)` | Combines elements; duplicates are automatically removed (a set's defining property) |

None of these three functions are interchangeable with `merge()` —
each is shaped by what its collection type actually guarantees.
`concat()` and `setunion()` aren't used in this series yet, but exist
in Terraform for exactly the list/set version of this same "combine
two collections" need.

---

#### Locals for a Second, Unrelated Resource — Proving the Concept Generalizes

Every example so far — `name_prefix`, `role_name`, `trust_policy`,
`common_tags` — feeds the same IAM role. That's a legitimate gap: it's
easy to walk away thinking these patterns are IAM-specific. They're
not. Part C below builds a brand-new `aws_sns_topic` that reuses
`local.name_prefix`, `local.common_tags`, and `local.trusted_principals`
— all already built for the IAM role — applying the exact same
`jsonencode()` + `merge()` pattern to a completely different resource
type and a completely different kind of policy (a resource policy, not
a trust policy).

> **This is a preview of the pattern, not the actual file to create
> yet.** The complete `06-sns.tf` — the real, applyable resource block
> — is written in Part C, Step 1, below. Creating it now, before Part
> B's `try()`/`coalesce()`/`merge()` work is done, would apply an SNS
> topic ahead of where this demo's narrative actually needs it.

The shape of what's coming, illustrating just the reuse (not the full
file):

```hcl
# Illustrative only — see Part C Step 1 for the complete, real file
sns_topic_name = "${local.name_prefix}-deploy-notifications"  # reused prefix
sns_tags       = merge(local.common_tags, { Purpose = "deploy-notifications" })
```

**What this demonstrates:** `local.name_prefix`, `local.common_tags`,
and `local.trusted_principals` were computed once and will drive two
entirely unrelated resources once Part C builds the SNS topic.
Nothing about `jsonencode()` or `merge()` needs to change for a
different resource type — the pattern is general-purpose, not an IAM
trick.

---

## Lab Step-by-Step Guide

---

## Part A — Rebuilding the Baseline

**What you accomplish in Part A:** recreate Demo 05's finished IAM role
exactly, as a working starting point for this demo — no new teaching
here, the variables/precedence concepts were already covered in Demo 05.

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

**03-variables.tf:**

```hcl
# ── Provider configuration ─────────────────────────────────────────────────

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

# ── Project identity ───────────────────────────────────────────────────────

variable "project" {
  type        = string
  description = "Project name — used in resource names and tags"
  default     = "cloudnova"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.project))
    error_message = "project must be 3–20 lowercase alphanumeric characters or hyphens, starting with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "dev"
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "demo" {
  type        = string
  description = "Demo identifier — used in tags for traceability"
  default     = "06-locals-in-depth"
}

# ── Role configuration ─────────────────────────────────────────────────────

variable "role_purpose" {
  type        = string
  description = "Short purpose label for the IAM role — becomes part of the role name"
  default     = "deploy"

  validation {
    condition     = length(var.role_purpose) <= 20 && can(regex("^[a-z][a-z0-9-]*$", var.role_purpose))
    error_message = "role_purpose must be lowercase alphanumeric or hyphens, max 20 characters."
  }
}

variable "trusted_account_ids" {
  type        = list(string)
  description = "List of AWS account IDs allowed to assume this role. Empty list = self-trust (current account only)."
  default     = []

  validation {
    condition     = alltrue([for id in var.trusted_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "All trusted_account_ids must be 12-digit AWS account IDs."
  }
}

variable "allowed_actions" {
  type        = list(string)
  description = "IAM actions this role is permitted to perform"
  default     = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
}

variable "custom_role_name" {
  type        = string
  description = "Optional: override the computed role name. If null, a name is computed from project+environment+purpose."
  default     = null
  nullable    = true
}

# ── Sensitive and ephemeral demonstration ──────────────────────────────────

variable "external_secret_label" {
  type        = string
  description = "A label for an external secret — sensitive, stored in state but redacted from output"
  default     = "demo-secret-label"
  sensitive   = true
}

# NOTE: ephemeral variables cannot be used in regular resource arguments —
# carried over from Demo 05 for consistency; not otherwise used in this demo.
variable "session_token" {
  type        = string
  description = "A short-lived token — ephemeral, never written to state"
  default     = "demo-session-token"
  ephemeral   = true
}

# ── Role instance configuration ────────────────────────────────────────────

variable "max_session_duration" {
  type        = number
  description = "Maximum session duration in seconds (3600–43200)"
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 (1 hour) and 43200 (12 hours)."
  }
}
```

---

#### `04-locals.tf` — Baseline locals, before this demo's additions

**What this file does in this demo:** recreates exactly what Demo 05
had before `try()`/`coalesce()`/`merge()` were introduced — Part B
extends this same block.

**04-locals.tf:**

```hcl
data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  role_name   = var.custom_role_name != null ? var.custom_role_name : "${local.name_prefix}-${var.role_purpose}-role"
  policy_name = "${local.name_prefix}-${var.role_purpose}-policy"

  # for expression (preview — full coverage Demo 09): builds one principal
  # ARN per trusted account ID, or falls back to self-trust if the list is empty
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

### Step 3 — Initialise and apply the baseline

```bash
terraform init
terraform validate
terraform apply
```

Type `yes`. Expected output:

```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```
> **Expect exactly 2 resources here** (`aws_iam_role.deploy` and
> `aws_iam_role_policy.deploy`) 

**Verify:**

```
Console → IAM → Roles → cloudnova-dev-deploy-role
  → Trust relationships tab: your account ARN ✅
  → Permissions tab: cloudnova-dev-deploy-policy (inline) ✅
```

---

## Part B — try(), coalesce(), and merge() in Practice

**What you accomplish in Part B:** extend the baseline locals with an
optional `role_config` object read safely via `try()`, a `coalesce()`
fallback for session duration, and `merge()`-based tag composition
where caller-supplied tags override defaults. **Every change in this
Part updates the same `aws_iam_role.deploy` and
`aws_iam_role_policy.deploy` created in Part A — this is intentional.**
Nothing here creates new resources; Terraform will show each `apply`
as an in-place update (`~`), not a new resource, because we're
refining the same role's configuration incrementally, the way a real
role's config evolves over time in practice rather than being
recreated from scratch.

### Step 1 — Add an optional config object variable

#### `03-variables.tf` — Add `role_config`

**What this change does in this demo:** adds one new variable,
`role_config`, whose fields are all individually optional — this is
what `try()` in Step 2 will read from safely.

Add to `03-variables.tf`:

```hcl
variable "role_config" {
  type = object({
    description      = optional(string)         # no default → null if omitted
    path             = optional(string, "/")    # explicit default "/" if omitted
    max_session_secs = optional(number, 3600)  # explicit default 3600 if omitted
  })
  description = "Optional structured role configuration. All fields are optional."
  default     = {}
  nullable    = false
}
```

> **Two different kinds of "optional" here, and it matters for Step
> 2.** `description = optional(string)` has no second argument, so an
> omitted `description` becomes `null`. `path` and `max_session_secs`
> both supply an explicit default as the second argument to
> `optional()`, so they can never be `null` — they're always at least
> `"/"` and `3600` respectively, even if the caller never mentions
> them at all.

### Step 2 — Add `try()` and `coalesce()` locals

#### `04-locals.tf` — Add `role_description` and `effective_max_session`

**What this change does in this demo:** `role_description` uses
`try()` because `var.role_config.description` can genuinely be `null`
(it has no default — see Step 1's note). `effective_max_session` layers
`try()` inside `coalesce()` for the same reason. Neither pattern is
needed for `path`, which is why Step 3's `05-main.tf` update references
`var.role_config.path` directly, with no `try()` at all.

Add inside the `locals {}` block in `04-locals.tf`:

```hcl
  # try() safely reads the optional description field — var.role_config.description
  # can genuinely be null (no default was given for it in 03-variables.tf),
  # so try() catches that and falls through to a computed default
  role_description = try(
    var.role_config.description,
    "CI/CD deploy role for ${var.project} ${var.environment}"
  )

  # coalesce(): try() extracts max_session_secs (which, unlike description,
  # already has its own default of 3600 from optional() — so this try()
  # is a defensive no-op here, and coalesce() falls through to
  # var.max_session_duration only if try() itself somehow returned null)
  effective_max_session = coalesce(
    try(var.role_config.max_session_secs, null),
    var.max_session_duration
  )
```

### Step 3 — Update `05-main.tf` and test

#### `05-main.tf` — Read `role_description` and `role_config.path`

**What this change does in this demo:** updates the **same**
`aws_iam_role.deploy` resource from Part A — not a new resource. Three
arguments change: `description` now reads `local.role_description`
instead of a hardcoded string; `path` now reads `var.role_config.path`
directly (no `try()` — see the note below); `max_session_duration` now
reads `local.effective_max_session` instead of `var.max_session_duration`
directly.

```hcl
resource "aws_iam_role" "deploy" {
  name                 = local.role_name
  description          = local.role_description
  path                 = var.role_config.path                # no try() needed — see note below
  assume_role_policy   = local.trust_policy
  max_session_duration = local.effective_max_session
  tags                 = local.common_tags
}
```

> **Why `path` doesn't need `try()`, unlike `description`:**
> `var.role_config.path` has an explicit default (`"/"`) built into its
> own `optional(string, "/")` declaration in Step 1 — it can **never**
> be `null`, so there's nothing for `try()` to catch. Wrapping it in
> `try(var.role_config.path, "/")` would be redundant: the fallback
> would never actually trigger, since the value is already guaranteed
> non-null before `try()` ever gets involved. `description`, by
> contrast, has no built-in default (`optional(string)` alone), so it
> genuinely can be `null` — that's the real difference that decides
> whether `try()` earns its place.

```bash
# Without role_config — uses all defaults
terraform plan
# description = null , max_session_duration = 3600 (unchanged)
```

Expected — Terraform shows this as an **update in-place** (`~`) on the
existing role with a change in `description`


```
  # aws_iam_role.deploy will be updated in-place
  ~ resource "aws_iam_role" "deploy" {
      - description           = "CI/CD deploy role for cloudnova dev" -> null
        id                    = "cloudnova-dev-deploy-role"
        name                  = "cloudnova-dev-deploy-role"
        # (11 unchanged attributes hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

```bash
# With partial role_config — only description overridden
terraform apply -var='role_config={"description":"Platform deploy role"}'
# description = "Platform deploy role", max_session_duration = 3600 (unchanged)
```

Expected — Terraform shows this as an **update in-place** (`~`) on the
existing role, not a new resource:

```
  # aws_iam_role.deploy will be updated in-place
  ~ resource "aws_iam_role" "deploy" {
      ~ description = "CI/CD deploy role for cloudnova dev" -> "Platform deploy role"
        id          = "cloudnova-dev-deploy-role"
        name        = "cloudnova-dev-deploy-role"
        # (11 unchanged attributes hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

> ✅ Verified against a live run.

**Verify:**

```
Console → IAM → Roles → cloudnova-dev-deploy-role
  → Description: "Platform deploy role" ✅ (updated, same role — same
    ARN and creation date as Part A, only description changed)
```

> **Only `description` changed in the second apply.** The in-place
> update confirms `try()` correctly fell through to the default for
> `max_session_secs` since it wasn't provided in the partial object.

### Step 4 — Add `merge()` tag composition

#### `03-variables.tf` — Add `extra_tags`

Add to `03-variables.tf`:

```hcl
variable "extra_tags" {
  type        = map(string)
  description = "Additional tags to merge onto all resources — caller-provided tags override defaults"
  default     = {}
}
```

#### `04-locals.tf` — Update `common_tags` to use `merge()`

**What this change does in this demo:** replaces the plain `{}` map
literal `common_tags` had in the baseline with a `merge()` call —
`var.extra_tags` is listed last, so caller-supplied tags win over the
defaults on any key conflict.

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

Expected — `"Owner"` in `extra_tags` wins (right-most-wins), and **both**
the IAM role and (once Part C creates it) the SNS topic pick this up,
since both consume `local.common_tags`:

```
  # aws_iam_role.deploy will be updated in-place
  ~ resource "aws_iam_role" "deploy" {
      ~ tags = {
          + "CostCenter" = "platform"
            ~ "Owner"    = "platform-team" -> "devops-team"
        }
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

> ✅ Verified against a live run.

**Verify:**

```
Console → IAM → Roles → cloudnova-dev-deploy-role → Tags
  → Owner: devops-team   (overridden — right-most wins) ✅
  → CostCenter: platform (added by extra_tags) ✅
```

> **If the Console still shows the old tag values right after
> `apply`,** this is almost always a Console refresh lag, not a
> Terraform problem — `terraform apply`'s own plan output (`~ "Owner" =
> "platform-team" -> "devops-team"`) is the authoritative confirmation
> that the update happened; refresh the Console page or wait a few
> seconds if it looks stale.

```bash
terraform apply   # no extra_tags — reverts to defaults
```

> ✅ Verified against a live run.

> **This `merge()` change affects every resource using
> `local.common_tags`, not just the IAM role.** `local.common_tags` is
> applied via `default_tags` in the provider block (Step 2 of Part A),
> so this ripples everywhere — worth noting before Part C creates the
> SNS topic, which inherits these same tags (plus one more, added
> specifically for it — explained there).

---

## Part C — Locals for a Second, Unrelated Resource

**What you accomplish in Part C:** build a brand-new `aws_sns_topic`
whose name, tags, and access policy are composed entirely from locals
already built for the IAM role — the concrete proof that none of this
demo's patterns are IAM-specific. `06-sns.tf` exists as an empty file
from the start of this demo; this Part is where it gets its real
content.

### Step 1 — Create `06-sns.tf` with locals-composed name and policy

#### `06-sns.tf` — The SNS topic, proving locals generalize

**What this file does in this demo:** declares
`aws_sns_topic.deploy_notifications`, named and policy-secured entirely
from locals already built for the IAM role (`local.name_prefix`,
`local.trusted_principals`, `local.common_tags`). `sns_tags` adds one
SNS-specific tag (`Purpose = "deploy-notifications"`) on top of
`local.common_tags` via `merge()` — this is why the SNS topic ends up
with one more tag than the IAM role: the IAM role's `tags` argument
uses `local.common_tags` directly (Part A), while the SNS topic uses
`local.sns_tags`, a `merge()`-extended version defined right here.

Create a file **06-sns.tf** and add the below content:

```hcl
locals {
  # Reused from the IAM role's locals — proves name_prefix isn't role-specific
  sns_topic_name = "${local.name_prefix}-deploy-notifications"

  # A resource policy (who can publish to this topic) — same jsonencode()
  # pattern as the IAM trust policy, different statement shape
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

  # merge() again — same pattern as the IAM role's tags (Part B, Step 4),
  # but this resource gets ONE EXTRA tag (Purpose) that the IAM role does
  # not — this is why the two resources' tag sets differ by one entry
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

#### `07-outputs.tf` — Add the SNS topic ARN output

**What this change does in this demo:** exposes `sns_topic_arn` so the
`aws sns publish`/`list-tags-for-resource` calls below have something
to target — without this output, you'd need to read the ARN from state
directly instead of via `terraform output -raw`.

Add to `07-outputs.tf`:

```hcl
output "sns_topic_arn" {
  description = "ARN of the deploy-notifications SNS topic"
  value       = aws_sns_topic.deploy_notifications.arn
}
```

```bash
terraform apply
```

**Verify:**

```
Console → SNS → Topics → cloudnova-dev-deploy-notifications
  → Access policy tab → Sid: AllowAccountPublish, Principal: your account ARN ✅
  → Tags tab → Purpose: deploy-notifications ✅
```

Now publish a real message:

```bash
aws sns publish \
  --profile default \
  --region us-east-2 \
  --topic-arn "$(terraform output -raw sns_topic_arn)" \
  --message "Demo 06 locals verification — $(date -u +%FT%TZ)"
```

> **If this errors with `Invalid parameter: TopicArn`,** the most
> common cause is a stale or empty value captured into `--topic-arn` —
> confirm `terraform output -raw sns_topic_arn` actually prints the
> full ARN by itself first (`echo "$(terraform output -raw
> sns_topic_arn)"`) before using it inside the `aws sns publish`
> command, and make sure `terraform apply` has been re-run since the
> output was added — `terraform output` only shows values that exist
> in the current state, which requires the output to have been through
> at least one `apply` after being added.

Expected:

```json
{
    "MessageId": "a1b2c3d4-5678-90ab-cdef-1234567890ab"
}
```


> **A real `MessageId` confirms the topic is actually functional, not
> just present in state** — it accepted and processed a real publish
> request. No subscriber is configured (avoiding overlap with Demo 10's
> SQS introduction), so the `MessageId` itself is the verifiable proof.

### Step 3 — Confirm the naming and tags reused the IAM role's locals

```bash
aws sns list-tags-for-resource --profile default --region us-east-2 --resource-arn "$(terraform output -raw sns_topic_arn)"
```

Expected: tags include `Environment: dev`, `ManagedBy: Terraform`, and
`Purpose: deploy-notifications` — the first two inherited unchanged
from `local.common_tags`, the last one added specifically for this
resource via `local.sns_tags`'s `merge()` in Step 1.

```
{
    "Tags": [
        {
            "Key": "Project",
            "Value": "cloudnova"
        },
        {
            "Key": "Environment",
            "Value": "dev"
        },
        {
            "Key": "Owner",
            "Value": "platform-team"
        },
        {
            "Key": "Purpose",
            "Value": "deploy-notifications"
        },
        {
            "Key": "Demo",
            "Value": "06-locals-in-depth"
        },
        {
            "Key": "ManagedBy",
            "Value": "Terraform"
        }
    ]
}

```

**Verify:**

```
Console → SNS → Topics → cloudnova-dev-deploy-notifications → Tags
  → Environment: dev, ManagedBy: Terraform, Purpose: deploy-notifications ✅
Console → IAM → Roles → cloudnova-dev-deploy-role → Tags
  → Environment: dev, ManagedBy: Terraform (no Purpose tag — confirms
    the IAM role uses local.common_tags directly, not local.sns_tags) ✅
```

---

## Cleanup

```bash
terraform destroy
```

Type `yes`. Expected: `Destroy complete! Resources: 3 destroyed.`
(IAM role, inline policy, SNS topic).


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

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `coalesce()` skipping null AND `""` | TA-004 Obj 4e (functions) | Common exam trap assumes it only skips `null` |
| Locals have no `type` argument | TA-004 Obj 4d (complex types) | Type is always inferred from the assigned expression |
| `try()` vs `coalesce()` | TA-004 Obj 4e (functions)  | Different problems — evaluation errors vs. null/empty values — frequently confused |
| Circular local reference detection | TA-004 Obj 4f (resource/value dependencies) | Caught at plan time with "Cycle in local values," not silently resolved |

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

> **Demo scope:** Primary concept: locals — the distinction test, type
> inference, chaining, and circular-reference detection. Supporting
> concepts: `try()`/`coalesce()`/`merge()`, a `jsonencode()` policy
> pattern, and applying the same composition pattern to a second,
> unrelated resource (`aws_sns_topic`).
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
"Can locals reference resources and data sources? Can variables?","Locals: yes — a local can reference data.aws_caller_identity.current.account_id, a resource attribute, another local, or a variable. Variables: no — a variable can only reference var.<itself>, and only inside its own validation block.","demo06,locals,variables"
"An SNS topic policy manually constructs its own ARN using region + account_id + name. What is the safer alternative when the topic is managed by the same configuration?","Reference the resource's own .arn attribute directly (e.g. aws_sns_topic.x.arn) instead of reconstructing it from parts. Manual construction risks drift if any component doesn't match the resource's actual ARN.","demo06,troubleshooting,arn"
```

---

## Appendix — Quiz

**06-locals-in-depth-quiz.md:**

````markdown
# Quiz — Demo 06: Locals in Depth

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 07.

---

**Q1. (Multiple Choice)** What is the correct distinction test for
choosing a `local` over a `variable`?

- A) Locals hold complex types; variables hold only primitives
- B) If the value would ever need external override, it's a variable; if it's always derived internally, it's a local
- C) Locals are evaluated faster
- D) There's no real distinction — use whichever is shorter to type

<details>
<summary>Answer</summary>

**B.** The test is about external overridability, not type or
performance. A local that's just `local.x = var.x` with no
transformation should be a variable instead.

</details>

---

**Q2. (True/False)** A `locals` block supports a `type` argument, just
like a `variable` block does.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Locals have no `type` argument at all — Terraform infers
the type entirely from the assigned expression.

</details>

---

**Q3. (Multiple Choice)** A local is defined as `{ Project = var.project,
Count = 3 }`, where `var.project` is `type = string`. What type does
Terraform infer?

- A) `map(string)`
- B) `map(number)`
- C) `object({ Project = string, Count = number })`
- D) `tuple([string, number])`

<details>
<summary>Answer</summary>

**C.** The two values have different types (string and number), so
Terraform infers `object({...})`, not `map(...)`. A `map` is only
inferred when every value shares the same type.

</details>

---

**Q4. (True/False)** If `local.b` is declared before `local.a` in a
file, but `local.a` references `local.b`, Terraform will error because
`local.b` isn't defined yet when `local.a` is evaluated.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Declaration order in the file has zero effect. Terraform
builds a dependency graph from the references inside each expression
and resolves evaluation order automatically — the same mechanism used
for resources.

</details>

---

**Q5. (Multiple Choice)** `local.a = "prefix-${local.b}"` and
`local.b = "suffix-${local.a}"`. What happens at `terraform plan`?

- A) Terraform picks an arbitrary order and one side gets an empty value
- B) A clear "Cycle in local values" error, before any value is evaluated
- C) Both resolve successfully using empty-string placeholders
- D) Only `local.a` (declared first) is evaluated

<details>
<summary>Answer</summary>

**B.** Circular references are detected at plan time with an explicit
cycle error — never silently resolved or partially evaluated. Fix by
extracting the shared value into a third local neither side references.

</details>

---

**Q6. (Multiple Choice)** What does `coalesce(var.name, "fallback")`
return when `var.name` is set to `""` (empty string)?

- A) `""` — empty string is not null, so it's returned
- B) `"fallback"` — `coalesce()` skips both null and empty string
- C) An error
- D) `null`

<details>
<summary>Answer</summary>

**B.** `coalesce()` treats `""` the same as `null` — both are skipped.
This is a common exam trap: empty string "not technically being null"
doesn't stop `coalesce()` from skipping it.

</details>

---

**Q7. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about `try(expr1, expr2, ...)` are correct?

- A) It returns `true` or `false`
- B) It returns the value of the first argument that evaluates without error
- C) It only errors if every single argument errors
- D) It is functionally identical to `coalesce()`
- E) It requires exactly two arguments

<details>
<summary>Answer</summary>

**B and C.** `try()` returns an actual value (not a boolean — that's
`can()`), and only fails if all provided expressions error. It accepts
any number of arguments (not exactly two), and solves a different
problem than `coalesce()` (errors vs. null/empty values).

</details>

---

**Q8. (Multiple Choice)** What is the key functional difference between
`try()` and `coalesce()`?

- A) They solve the same problem with different syntax
- B) `try()` catches expression evaluation errors; `coalesce()` catches null/empty-string values
- C) `try()` is for numbers only; `coalesce()` is for strings only
- D) `coalesce()` is deprecated in favor of `try()`

<details>
<summary>Answer</summary>

**B.** `try()` is for expressions that might error (e.g. an optional
object attribute that may not exist). `coalesce()` is for values that
might be `null` or `""`. They're often combined:
`coalesce(try(var.config.name, null), local.default)`.

</details>

---

**Q9. (Multiple Choice)** `merge(local.common_tags, var.extra_tags)` —
both have key `"Owner"`. Which value wins?

- A) `local.common_tags`'s value
- B) `var.extra_tags`'s value
- C) Both are kept as a list
- D) An error — duplicate keys aren't allowed

<details>
<summary>Answer</summary>

**B.** `merge()` is right-most-wins on key conflicts. Since
`var.extra_tags` is listed last, its value overrides
`local.common_tags`'s for any shared key.

</details>

---

**Q10. (Multiple Choice)** You want caller-supplied tags to override a
set of base defaults. Which argument order to `merge()` achieves this?

- A) `merge(caller_tags, base_tags)`
- B) `merge(base_tags, caller_tags)`
- C) Either order — `merge()` is commutative
- D) Neither — `merge()` cannot express "caller overrides base"

<details>
<summary>Answer</summary>

**B.** Base defaults go first, caller overrides go last — the
"higher authority" map always goes last in `merge()`. Reversing the
order (A) silently flips precedence with no error, which is exactly
the kind of mistake that's hard to spot without knowing this rule.

</details>

---

**Q11. (Multiple Choice)** Why can `jsonencode()` and `merge()`,
originally used to build an IAM trust policy, be reused unchanged to
build an SNS topic's resource policy?

- A) They can't — each AWS service requires its own policy-building functions
- B) They are general-purpose functions with no awareness of which resource consumes their output
- C) SNS and IAM share the same underlying API
- D) Only because both policies happen to have identical structure

<details>
<summary>Answer</summary>

**B.** `jsonencode()` converts any HCL value to a JSON string; `merge()`
combines any maps. Neither function knows or cares what AWS resource
the result is eventually assigned to — the same composition pattern
applies to any policy document, for any service.

</details>

---

**Q12. (Multiple Choice)** A local is defined as `local.c = { type =
string, value = "test" }`. Does this declare a type constraint on
`local.c`?

- A) Yes — `type` inside any block enforces a constraint
- B) No — `type` here is just an ordinary map key; locals have no type-constraint mechanism at all
- C) Yes, but only for the `value` field
- D) It causes a `terraform validate` error

<details>
<summary>Answer</summary>

**B.** Nothing about `locals` blocks treats `type` as special — it's an
ordinary key in an ordinary map literal here. This is valid HCL that
does nothing resembling a `variable` block's `type` argument, which is
exactly what makes this a subtle trap rather than an obvious syntax error.

</details>

---

**Q13. (True/False)** Unlike `variable` blocks, `locals` blocks can
reference resources and data sources directly.

- A) True
- B) False

<details>
<summary>Answer</summary>

**A) True.** A `local` can reference `data.aws_caller_identity.current.account_id`,
a resource attribute, another local, or a variable — variables can only
reference `var.<themselves>`, and only inside a `validation` block.

</details>

---

**Q14. (Multiple Choice)** Two locals reference `data.aws_caller_identity.current.account_id`
in constructing an ARN string manually. What is a safer alternative
where the target resource is also managed by this same configuration?

- A) There is no safer alternative — manual ARN construction is required
- B) Reference the resource's own `.arn` attribute directly (e.g. `aws_sns_topic.x.arn`) instead of reconstructing it
- C) Hardcode the ARN as a literal string
- D) Use `jsonencode()` to generate the ARN automatically

<details>
<summary>Answer</summary>

**B.** Manually reconstructing an ARN from region/account ID/name risks
drift if any component doesn't match the resource's actual ARN.
Referencing the resource's own `.arn` attribute is always authoritative
and avoids that class of bug entirely.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 13-14/14 | Import Anki cards, move to Demo 07 |
| 11-12/14 | Review the wrong answers, then proceed |
| 9-10/14 | Re-read the relevant sections, retry those questions |
| Below 9/14 | Re-read the full demo and redo the walkthrough before proceeding |
````