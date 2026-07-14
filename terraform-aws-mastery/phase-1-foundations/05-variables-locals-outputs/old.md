# Demo 05 — Variables, Locals, and Outputs: Value Flow Through a Configuration

---

## Overview

In Demos 01–04 the configuration has been largely hardcoded — region,
project name, environment, and resource names all baked directly into
`.tf` files. A second CloudNova engineer is joining and needs to run the
same configuration against a staging AWS account. Right now that means
editing `.tf` files directly, which is exactly what Terraform's input
system exists to prevent.

**Real-world scenario — CloudNova:**
The platform team needs an IAM role that CI/CD pipelines use to deploy
infrastructure. The role needs to exist in both dev and staging, with
identical configuration but different names and in different accounts.
Rather than maintaining two separate copies of the configuration, you
parameterise it: values that change per environment enter as variables,
values derived from those inputs are composed as locals, and the resulting
role ARN is exposed as an output that downstream configurations consume
via `terraform_remote_state`.

This is the complete value-flow pattern: **in** (variables), **computed**
(locals), **out** (outputs + remote state).

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Variables in depth                                            │
│  Types, sensitive, ephemeral, nullable, validation, precedence          │
│  IAM role + inline policy driven entirely by variable inputs            │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Locals in depth                                               │
│  When to use local vs variable   |   try(), coalesce(), merge()         │
│  Composed naming locals   |   policy document as a jsonencode() local   │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Outputs in depth                                              │
│  sensitive, ephemeral, depends_on on outputs                            │
│  terraform output variants   |   terraform_remote_state                 │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- Variable types: primitives, collection types, `object({})`, `any`
- `sensitive = true` and `ephemeral = true` on variables — what each
  does and how they differ
- `nullable = false` on variables
- `validation` blocks — `condition` and `error_message`
- Variable value precedence: CLI > env > tfvars > default
- When to use a local vs. a variable — the distinction test
- `try()`, `coalesce()`, `merge()` functions in locals
- Locals referencing other locals (chaining)
- Policy document as a `jsonencode()` local
- `sensitive = true` and `ephemeral = true` on outputs
- `depends_on` on outputs and when it's needed
- `terraform output` variants: `-raw`, `-json`, `-no-color`
- `data.terraform_remote_state` — reading another config's outputs
- `aws_iam_role` and `aws_iam_role_policy` (new AWS resources)

---

## Prerequisites

### Knowledge
- Demos 01–04 completed — provider configuration, resource patterns,
  `depends_on`, state management, basic variables/locals/outputs used
  in every prior demo but never explained in depth

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
iam:CreateRole, iam:DeleteRole, iam:GetRole, iam:ListRoles
iam:PutRolePolicy, iam:DeleteRolePolicy, iam:GetRolePolicy
iam:TagRole, iam:UntagRole, iam:ListRoleTags
iam:PassRole
```

> For a learning account, `IAMFullAccess` managed policy covers all of
> the above.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Declare variables with all type constraints, validation blocks,
   `sensitive`, `ephemeral`, and `nullable` arguments
2. ✅ Explain the variable value precedence order and apply it correctly
3. ✅ Distinguish between a `variable` (external input) and a `local`
   (internal computed value) using the distinction test
4. ✅ Use `try()`, `coalesce()`, and `merge()` inside locals
5. ✅ Build a policy document as a `jsonencode()` local
6. ✅ Mark outputs as `sensitive` or `ephemeral` and explain what each
   does differently
7. ✅ Use `depends_on` on outputs and explain when it is necessary
8. ✅ Use all `terraform output` command variants
9. ✅ Read another configuration's outputs using
   `data.terraform_remote_state`

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| `aws_iam_role` | Always free — IAM has no cost | **$0.00** | |
| `aws_iam_role_policy` | Always free | **$0.00** | |
| `data.terraform_remote_state` | Read-only S3 API call | **<$0.001** | |
| **Session total** | | **~$0.00** | |

---

## Directory Structure

```
05-variables-locals-outputs/
├── README.md
├── 05-variables-locals-outputs-anki.csv
├── 05-variables-locals-outputs-quiz.md
└── src/
    ├── 01-versions.tf      # terraform block + provider version constraints
    ├── 02-provider.tf      # AWS provider: region, profile, default_tags
    ├── 03-variables.tf     # all input variables
    ├── 04-locals.tf        # computed values + policy document
    ├── 05-main.tf          # aws_iam_role + aws_iam_role_policy
    ├── 06-outputs.tf       # role ARN, policy name, sensitive outputs
    ├── 07-consumer.tf      # data.terraform_remote_state (Part C)
    └── break-fix/
        └── broken.tf
```

---

## Recall Check — Demo 04

Answer from memory before reading anything new:

1. What is the difference between `terraform state mv` and simply
   renaming a resource block in a `.tf` file — what does each affect?
2. After `terraform state rm` on a resource whose `.tf` block still
   exists, what does the next `terraform plan` propose, and what is the
   correct recovery step?
3. What does `terraform state push` do to the current remote state —
   does it merge or overwrite?

<details>
<summary>Answers</summary>

1. Renaming a resource block in `.tf` only changes the code — Terraform
   sees this as "delete the old resource, create a new one" and plans
   a destroy + create. `terraform state mv` updates state's record of
   the resource's address to match the renamed block, so Terraform
   recognises them as the same resource — no destroy/create happens.
   Both changes (`.tf` rename + `state mv`) are required together.
2. `plan` proposes to CREATE the resource — state no longer knows it
   exists, but the `.tf` block still declares it. The correct recovery
   is `terraform import`, not `terraform apply` — `apply` would attempt
   to create a new resource that already exists in AWS.
3. Overwrites entirely — it does not merge. The current remote state is
   replaced completely with the local file's contents. Always follow
   with `terraform plan -refresh-only` to check whether the restored
   state matches actual AWS infrastructure.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `variable` block (full depth) | Input declaration | All type constraints, validation, sensitive, ephemeral, nullable |
| `sensitive = true` on variable | Variable argument | Redacts value from plan/apply output — still stored in state |
| `ephemeral = true` on variable | Variable argument | Value never written to state, logs, or plan output — memory-only |
| `nullable = false` on variable | Variable argument | Prevents `null` from being passed as a value even if a default is set |
| `validation` block | Variable sub-block | Enforces a custom condition on the input value |
| `locals` block (full depth) | Computed values | try(), coalesce(), merge(), chained locals, jsonencode() policy doc |
| `sensitive = true` on output | Output argument | Redacts value from `terraform output` and plan — still stored in state |
| `ephemeral = true` on output | Output argument | Value available during apply but never written to state |
| `depends_on` on output | Output meta-argument | Delays output resolution until a dependency fully completes |
| `data.terraform_remote_state` | Data source | Reads outputs from another Terraform configuration's state file |
| `aws_iam_role` | Resource | An IAM role CI/CD pipelines assume to deploy infrastructure |
| `aws_iam_role_policy` | Resource | Inline IAM policy attached directly to a role |

**Related constructs worth knowing (not used in this demo):**

| Construct | What it does |
|---|---|
| `aws_iam_policy` | Standalone (managed) IAM policy — attachable to multiple roles |
| `aws_iam_role_policy_attachment` | Attaches a managed policy to a role (vs. inline `aws_iam_role_policy`) |
| `write_only` argument (Terraform 1.10+) | Resource argument that is never stored in state — covered in Demo 08 |
| `var.x == null ? "default" : var.x` | Inline null-check — alternative to `coalesce()` for simple cases |

---

### Detailed Explanation of New Constructs

#### Variables — Full Depth

You've declared variables in every demo since Demo 01, always with
`type`, `description`, and `default`. Here's the complete picture.

**Full variable block syntax:**

```hcl
variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "dev"
  sensitive   = false
  ephemeral   = false
  nullable    = true

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}
```

---

**Type constraints — the full set:**

| Type | Example value | Notes |
|---|---|---|
| `string` | `"us-east-2"` | Always double-quoted |
| `number` | `8` or `3.14` | Integer or float |
| `bool` | `true` / `false` | Lowercase only |
| `list(type)` | `["a", "b"]` | Ordered, allows duplicates |
| `set(type)` | `toset(["a", "b"])` | Unordered, no duplicates |
| `map(type)` | `{ key = "val" }` | All values same type |
| `object({...})` | `{ name = string, count = number }` | Fixed named fields, each typed independently |
| `tuple([...])` | `tuple([string, number])` | Fixed-length, mixed-type sequence |
| `any` | Accepts anything | Loses type-checking — use sparingly |

**When to use `object` vs `map`:** use `object` when the set of keys is
fixed and known in advance (e.g. a config struct with `name`, `region`,
`count`). Use `map` when keys are dynamic or user-defined and all values
share the same type (e.g. a tag set where keys vary).

---

**`sensitive = true` — redacts from output, not from state:**

```hcl
variable "deploy_token" {
  type      = string
  sensitive = true
}
```

When `sensitive = true`:
- Plan/apply output shows `(sensitive value)` instead of the actual value
- `terraform output deploy_token` shows `(sensitive value)`
- The value IS still written to `terraform.tfstate` in plaintext

> **The most common misconception:** `sensitive = true` is NOT encryption
> and NOT a security boundary — it's redaction from terminal output only.
> The value still exists in state. This is why state must be stored
> securely (encrypted S3 backend, not Git) independently of whether
> variables are marked sensitive.

---

**`ephemeral = true` — never written to state (Terraform 1.10+):**

```hcl
variable "deploy_token" {
  type      = string
  ephemeral = true
}
```

When `ephemeral = true`:
- Value exists only in memory during plan/apply
- Never written to `terraform.tfstate`
- Never written to plan files
- Cannot be used in non-ephemeral resource arguments — only in
  ephemeral contexts (ephemeral outputs, write-only resource arguments)

**`sensitive` vs `ephemeral` — the key distinction:**

| | `sensitive = true` | `ephemeral = true` |
|---|---|---|
| Appears in plan/apply terminal output | No (redacted) | No (redacted) |
| Written to `terraform.tfstate` | **Yes** | **No** |
| Written to saved plan file (`-out`) | **Yes** | **No** |
| Can be used in regular resource arguments | Yes | No — ephemeral-only contexts |
| Purpose | Hides from logs/terminal | Truly never persisted anywhere |

> **When to use which:** `sensitive = true` for values that are
> confidential but need to persist in state (e.g. a database name that
> downstream configs read from state). `ephemeral = true` for values
> that must never be stored anywhere — credentials, tokens, passwords
> that are passed to a resource at apply time and never needed again.

---

**`nullable = false` — prevents null even with a default:**

```hcl
variable "environment" {
  type     = string
  default  = "dev"
  nullable = false
}
```

By default (`nullable = true`), a caller can explicitly pass `null` to
override a variable — even if a default exists. This is useful when you
want `null` to mean "use the resource's own default" for a resource
argument. Setting `nullable = false` rejects `null` as an input — the
default is always used if no explicit non-null value is provided.

---

**`validation` blocks — custom conditions:**

```hcl
variable "instance_count" {
  type    = number
  default = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "instance_count must be between 1 and 10 inclusive."
  }
}
```

| Argument | Description |
|---|---|
| `condition` | A Terraform expression that must evaluate to `true`. Must be a bool — returning a string or number is a validation error in itself. |
| `error_message` | The message shown when condition is false. Must be a non-empty string ending with a period. |

> **What validation catches vs. what it doesn't:** `validation` blocks
> are evaluated when the variable value is resolved — before `plan`
> calls any provider API. They can test the value's content
> (`contains()`, regex, arithmetic) but cannot reference other variables
> or resources (only `var.<this variable>` is in scope).

---

**Variable value precedence — highest to lowest:**

```
1. CLI flag:          terraform apply -var="environment=staging"
2. CLI var file:      terraform apply -var-file="staging.tfvars"
3. *.auto.tfvars      (loaded automatically, alphabetical order)
4. terraform.tfvars   (loaded automatically if present)
5. TF_VAR_ env vars:  export TF_VAR_environment=staging
6. Default value:     default = "dev" in the variable block
7. Interactive prompt (if no default and not provided — avoided in CI)
```

> **The practical rule:** earlier in the list = harder to accidentally
> override. Use `default` for safe fallbacks, `terraform.tfvars` for
> local developer overrides (add to `.gitignore`), environment variables
> for CI/CD pipelines, and `-var` flags for one-off overrides.

---

#### Locals — Full Depth

You've used `locals` in every demo since Demo 01 for `bucket_name` and
`common_tags`. Here's the full picture of what locals are and what
they're for.

**The distinction test — variable vs. local:**

> If you would ever want to override this value from outside the
> configuration (different per engineer, per environment, per run),
> it's a **variable**. If it's always derived from other values in
> the configuration and never needs external input, it's a **local**.

```hcl
# Variable — needs external input (different per environment)
variable "environment" {
  type    = string
  default = "dev"
}

# Local — derived from the variable, never needs external input
locals {
  role_name = "${var.project}-${var.environment}-deploy-role"
}
```

The signal: if you're tempted to write `local.x = var.x` with no
transformation, it should probably be a variable, not a local. Locals
earn their place when they compute something — a composed name, a
filtered list, a merged map.

---

**`try()` — safe attribute access:**

```hcl
locals {
  # If var.config is null or doesn't have a .region attribute,
  # return "us-east-2" instead of erroring
  region = try(var.config.region, "us-east-2")
}
```

`try()` evaluates each argument in order and returns the first one that
doesn't produce an error. Essential for optional object attributes —
without it, accessing a null object's attribute errors immediately.

---

**`coalesce()` — first non-null, non-empty value:**

```hcl
locals {
  # Use var.custom_name if set, otherwise compute a default name
  role_name = coalesce(var.custom_name, "${var.project}-${var.environment}-deploy-role")
}
```

`coalesce()` returns the first argument that is not `null` and not an
empty string. Useful for "use the provided value if given, otherwise
fall back to a computed default" patterns without verbose conditionals.

---

**`merge()` — combining maps:**

```hcl
locals {
  # Default tags applied everywhere
  default_tags = {
    ManagedBy   = "Terraform"
    Project     = var.project
    Environment = var.environment
  }

  # Resource-specific extra tags merged on top
  # In conflicts, the right-most map wins
  role_tags = merge(local.default_tags, {
    Purpose = "ci-cd-deploy"
    Team    = "platform"
  })
}
```

`merge()` takes two or more maps and combines them. Later maps win on
key conflicts. The typical pattern: a base tag map as a local, then each
resource gets `merge(local.default_tags, { resource-specific tags })`.

---

**Chaining locals — locals referencing other locals:**

```hcl
locals {
  # Step 1: base name components
  name_prefix = "${var.project}-${var.environment}"

  # Step 2: full resource names derived from Step 1
  role_name   = "${local.name_prefix}-deploy-role"
  policy_name = "${local.name_prefix}-deploy-policy"

  # Step 3: policy document built from Step 2's names
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowAssumeRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::*:role/${local.name_prefix}-*"
      }
    ]
  })
}
```

Locals can reference each other — Terraform resolves the dependency
order automatically. The same rule applies as for resources: no circular
references allowed.

---

#### `aws_iam_role` and `aws_iam_role_policy`

**`aws_iam_role`:** an IAM role is an AWS identity that can be assumed
by services, users, or other accounts. Unlike an IAM user (which has
long-term credentials), a role issues temporary credentials when assumed.
CI/CD pipelines typically assume a role to deploy infrastructure —
avoiding the need to store long-term access keys.

| Argument | Required | Description |
|---|---|---|
| `name` | No — but always set | Role name. Must be unique within the account. Max 64 characters. |
| `assume_role_policy` | **Yes** | JSON trust policy — who is allowed to assume this role. Must use `jsonencode()` or `data.aws_iam_policy_document`. |
| `description` | No | Human-readable description |
| `tags` | No | Resource tags |

**`aws_iam_role_policy`:** an inline policy attached directly to one
specific role. Unlike a managed policy (`aws_iam_policy`), inline
policies cannot be reused — they exist only as part of the role they're
attached to.

| Argument | Required | Description |
|---|---|---|
| `name` | Yes | Policy name — unique within the role |
| `role` | Yes | The role's name or ID — `aws_iam_role.deploy.name` |
| `policy` | Yes | JSON permission policy document — what this role is allowed to do |

**Inline vs. managed policies — when to use which:**
- **Inline:** when the policy is specific to exactly one role and should
  be destroyed when the role is destroyed. Simpler lifecycle, tighter
  coupling by design.
- **Managed (`aws_iam_policy` + `aws_iam_role_policy_attachment`):**
  when the same policy needs to be attached to multiple roles, or when
  you want to track the policy independently of any specific role.

---

#### Outputs — Full Depth

**`sensitive = true` on outputs:**

```hcl
output "role_arn" {
  description = "ARN of the deploy role"
  value       = aws_iam_role.deploy.arn
  sensitive   = true
}
```

- `terraform output role_arn` shows `(sensitive value)`
- `terraform output -json` shows the value in plaintext (JSON encoding
  includes it — this is intentional for programmatic consumption)
- The value IS written to state
- Other Terraform configurations reading via `terraform_remote_state`
  can access the value — sensitivity is not inherited

---

**`ephemeral = true` on outputs (Terraform 1.10+):**

```hcl
output "deploy_token" {
  description = "Short-lived deploy token"
  value       = var.deploy_token   # var.deploy_token must also be ephemeral
  ephemeral   = true
}
```

- Value is available during the current plan/apply session
- Never written to state — subsequent plans cannot read it from state
- Cannot be read via `terraform_remote_state` (never persisted)
- Primarily useful for passing ephemeral values between module calls
  within a single apply

---

**`depends_on` on outputs:**

```hcl
output "role_arn" {
  value      = aws_iam_role.deploy.arn
  depends_on = [aws_iam_role_policy.deploy]
}
```

By default, an output is computed as soon as the value it references
is available. `depends_on` delays output resolution until the listed
resources have fully completed — useful when downstream consumers of
the output need to know that a related resource (not directly referenced
in the output's value) has also been applied.

In this demo's case: the role ARN is the output, but the consumer needs
to know the *role is fully configured with its policy* before assuming
it. The policy isn't referenced in the ARN — so `depends_on` ensures
the output only resolves after the policy is attached.

---

**`terraform output` variants:**

```bash
terraform output                      # all outputs, human-readable
terraform output role_arn             # single output value
terraform output -raw role_arn        # no quotes — use in shell scripts
terraform output -json                # all outputs as JSON (sensitive values included)
terraform output -json | jq '.role_arn.value'   # parse with jq
terraform output -no-color            # strip ANSI color codes — useful in CI logs
```

---

#### `data.terraform_remote_state` — Reading Another Config's Outputs

```hcl
data "terraform_remote_state" "iam" {
  backend = "s3"

  config = {
    bucket  = "tfstate-cloudnova-163125980376-us-east-2"
    key     = "phase-1/05-variables-locals-outputs/terraform.tfstate"
    region  = "us-east-2"
    profile = "default"
  }
}
```

After declaring this data source, any output from the referenced
configuration is available as:

```hcl
data.terraform_remote_state.iam.outputs.role_arn
```

**How it works:** reads the remote state file directly from the S3
backend — no Terraform API, no provider call to IAM. It calls the S3
`GetObject` API, downloads the state JSON, and makes the `outputs` map
available. This means:

- Read-only — it cannot modify the referenced state
- The referenced configuration must already be applied (the state file
  must exist)
- Only non-sensitive, non-ephemeral outputs are accessible this way —
  sensitive outputs are included (the state file contains them in
  plaintext); ephemeral outputs are not (they were never written to state)

> **`terraform_remote_state` vs. other sharing patterns:** this data
> source couples two configurations tightly — Consumer B reads Producer
> A's state file directly, meaning B's plan fails if A's state doesn't
> exist. An alternative is passing values explicitly (CLI flags,
> environment variables, a shared parameter store like SSM). For
> tightly-coupled infrastructure owned by the same team,
> `terraform_remote_state` is the most ergonomic. For loosely-coupled
> or cross-team infrastructure, explicit passing or SSM Parameter Store
> is often preferable.

## Lab Step-by-Step Guide

---

## Part A — Variables in Depth: Build the IAM Role

**What you accomplish in Part A:** write a fully-parameterised
configuration for an IAM deploy role, exercising all variable arguments
— type constraints, validation, `sensitive`, `ephemeral`, `nullable`,
and precedence. At the end of Part A, the role exists in AWS and every
value that should be configurable is externally injectable.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/05-variables-locals-outputs/src
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

This file demonstrates the full variable argument set. Read each
variable's arguments before writing them — they're intentionally varied
to exercise different combinations.

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

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "demo" {
  type        = string
  description = "Demo identifier — used in tags for traceability"
  default     = "05-variables-locals-outputs"
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
  description = "List of AWS account IDs allowed to assume this role"
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
  nullable    = true   # null = "use the computed name" — an intentional nullable pattern
}

# ── Sensitive and ephemeral demonstration ──────────────────────────────────

variable "external_secret_label" {
  type        = string
  description = "A label for an external secret — sensitive, stored in state but redacted from output"
  default     = "demo-secret-label"
  sensitive   = true
}

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

### Step 5 — Create `04-locals.tf`

**What this file does:** computes all derived values. Nothing here is
user-configurable — every local is derived from variables or other
locals.

**04-locals.tf:**

```hcl
locals {
  # ── Step 1: name prefix — foundation for all resource names ──────────────
  name_prefix = "${var.project}-${var.environment}"

  # ── Step 2: role name — use custom override if provided, else compute ────
  # coalesce() returns the first non-null, non-empty value:
  # if var.custom_role_name is null, falls through to the computed name
  role_name   = coalesce(var.custom_role_name, "${local.name_prefix}-${var.role_purpose}-role")
  policy_name = "${local.name_prefix}-${var.role_purpose}-policy"

  # ── Step 3: trust policy — who can assume this role ──────────────────────
  # try() prevents errors if trusted_account_ids is empty:
  # if the list is empty, the fallback builds a self-trust policy
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

  # ── Step 4: permission policy — what this role can do ────────────────────
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

  # ── Step 5: common tags — merged with resource-specific tags ─────────────
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Demo        = var.demo
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
  }

  # ── Step 6: role-specific tags — merge adds Purpose on top of common ─────
  role_tags = merge(local.common_tags, {
    Purpose = var.role_purpose
  })
}

# Data source for current account ID — used in trust policy
data "aws_caller_identity" "current" {}
```

> **Notice the chaining:** `name_prefix` → `role_name` / `policy_name`
> → `trusted_principals` (depends on an external data source) →
> `trust_policy` / `permission_policy`. Terraform resolves this
> dependency order automatically — you write them in any order you like.

---

### Step 6 — Create `05-main.tf`

**05-main.tf:**

```hcl
resource "aws_iam_role" "deploy" {
  name                 = local.role_name
  description          = "CI/CD deploy role for ${var.project} ${var.environment}"
  assume_role_policy   = local.trust_policy
  max_session_duration = var.max_session_duration
  tags                 = local.role_tags
}

resource "aws_iam_role_policy" "deploy" {
  name   = local.policy_name
  role   = aws_iam_role.deploy.name
  policy = local.permission_policy
}
```

---

### Step 7 — Initialise and apply

```bash
terraform init
terraform validate
terraform fmt -recursive
terraform apply
```

Type `yes`. Expected output:

```
data.aws_caller_identity.current: Reading...
data.aws_caller_identity.current: Read complete after 0s

aws_iam_role.deploy: Creating...
aws_iam_role.deploy: Creation complete after 1s [id=cloudnova-dev-deploy-role]

aws_iam_role_policy.deploy: Creating...
aws_iam_role_policy.deploy: Creation complete after 1s [id=cloudnova-dev-deploy-role:cloudnova-dev-deploy-policy]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

### Step 8 — Verify in Console

```
Console → IAM → Roles → cloudnova-dev-deploy-role

Trust relationships tab:
  → Trusted entities: arn:aws:iam::<your-account-id>:root ✅

Permissions tab:
  → cloudnova-dev-deploy-policy (inline) ✅
  → Click policy → JSON:
    → AllowedActions: s3:GetObject, s3:PutObject, s3:ListBucket ✅

Tags tab:
  → Environment: dev ✅
  → Purpose: deploy ✅
  → ManagedBy: Terraform ✅
```

---

### Step 9 — Test variable precedence

Override `environment` at each precedence level and observe the result:

```bash
# Level 5 — environment variable (TF_VAR_ prefix)
export TF_VAR_environment=staging
terraform plan
# Notice: role_name in plan would be cloudnova-staging-deploy-role
# (different from what's applied — plan shows a pending change)

# Level 1 — CLI flag overrides TF_VAR_
terraform plan -var="environment=prod"
# role_name would be cloudnova-prod-deploy-role

# Clean up override
unset TF_VAR_environment
```

> **The precedence rule in action:** CLI `-var` flag produces
> `cloudnova-prod-deploy-role` even with `TF_VAR_environment=staging`
> set — the CLI flag wins. Remove both and the `default = "dev"` applies.

---

### Step 10 — Test validation

```bash
terraform plan -var="environment=qa"
```

Expected output:

```
╷
│ Error: Invalid value for variable
│
│   on 03-variables.tf line 27, in variable "environment":
│   27:   default     = "dev"
│
│ environment must be dev, staging, or prod.
│
│ This was checked by the validation rule at 03-variables.tf:30,3-13.
╵
```

```bash
terraform plan -var="max_session_duration=999"
```

Expected:

```
│ Error: Invalid value for variable
│   max_session_duration must be between 3600 (1 hour) and 43200 (12 hours).
```

> **Validation fires before any API call** — these errors appear during
> variable resolution, before `terraform plan` even contacts AWS. This
> is intentional: invalid inputs are caught as early as possible.

---

### Step 11 — Observe sensitive and ephemeral variable behavior

```bash
# sensitive variable — redacted in output
terraform plan -var="external_secret_label=my-real-secret"
```

Expected — in the plan output, any reference to `var.external_secret_label`
shows `(sensitive value)`:

```
  # aws_iam_role.deploy will be updated in-place
  ~ resource "aws_iam_role" "deploy" {
      ~ tags = {
          ~ "SecretLabel" = (sensitive value)
        }
    }
```

```bash
# ephemeral variable — never written to state
terraform apply -var="session_token=my-real-token"
```

Expected — apply succeeds. Check state:

```bash
terraform state pull | jq '.resources[] | select(.type=="aws_iam_role") | .instances[0].attributes.tags'
```

The `session_token` value does **not** appear anywhere in state — it was
available during apply and discarded immediately after. Compare with
`external_secret_label` (if you used it in a tag): that value IS in
state in plaintext, just redacted from terminal output.

---

## Part B — Locals in Depth: Refactor and Extend

**What you accomplish in Part B:** extend the configuration to
demonstrate the full range of local techniques — `try()` for safe
access, `coalesce()` for conditional naming, `merge()` for tag
composition, and chained locals.

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

> **`optional()` inside `object()`:** marks individual object fields as
> optional with their own defaults. If a caller omits `path`, it
> defaults to `"/"`. If a caller passes `{}`, all fields use their
> defaults. This is the idiomatic pattern for structured optional
> configuration objects.

### Step 2 — Update `04-locals.tf` to use `try()` and the new variable

Add to the `locals` block in `04-locals.tf`:

```hcl
  # try() safely reads the optional description field
  # If var.role_config.description is null or doesn't exist, falls back
  role_description = try(
    var.role_config.description,
    "CI/CD deploy role for ${var.project} ${var.environment}"
  )

  # try() safely reads the optional max_session_secs field
  # coalesce() picks the first non-null from variable override or config object
  effective_max_session = coalesce(
    try(var.role_config.max_session_secs, null),
    var.max_session_duration
  )
```

### Step 3 — Update `05-main.tf` to use the new locals

```hcl
resource "aws_iam_role" "deploy" {
  name                 = local.role_name
  description          = local.role_description      # ← now uses try()
  path                 = try(var.role_config.path, "/")
  assume_role_policy   = local.trust_policy
  max_session_duration = local.effective_max_session # ← now uses coalesce()
  tags                 = local.role_tags
}
```

### Step 4 — Test with and without the optional config

```bash
# Without role_config — uses all defaults
terraform plan
# description = "CI/CD deploy role for cloudnova dev"
# max_session_duration = 3600

# With partial role_config — only some fields overridden
terraform plan -var='role_config={"description":"Platform deploy role"}'
# description = "Platform deploy role"
# max_session_duration = 3600 (still from max_session_duration variable default)
```

### Step 5 — Demonstrate merge() tag composition

Add a variable for extra tags:

```hcl
variable "extra_tags" {
  type        = map(string)
  description = "Additional tags to merge onto all resources"
  default     = {}
}
```

Update `common_tags` local:

```hcl
  # merge() — later map wins on key conflicts
  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      Demo        = var.demo
      ManagedBy   = "Terraform"
      Owner       = "platform-team"
    },
    var.extra_tags   # caller can add/override any tag
  )
```

```bash
terraform apply -var='extra_tags={"CostCenter":"platform","Owner":"devops-team"}'
```

Expected — "Owner" in `extra_tags` wins over the hardcoded "platform-team"
value, demonstrating right-most-wins merge behavior:

```
Console → IAM → cloudnova-dev-deploy-role → Tags
  → Owner: devops-team   (overridden by extra_tags) ✅
  → CostCenter: platform (added by extra_tags) ✅
```

```bash
terraform apply   # with no extra_tags — reverts to defaults
```

---

## Part C — Outputs in Depth and Remote State

**What you accomplish in Part C:** expose the IAM role's attributes as
outputs with different sensitivity levels, practise all `terraform output`
variants, then consume those outputs from a second minimal configuration
using `terraform_remote_state`.

### Step 1 — Create `06-outputs.tf`

**06-outputs.tf:**

```hcl
# Standard output — visible everywhere
output "role_name" {
  description = "Name of the IAM deploy role"
  value       = aws_iam_role.deploy.name
}

# Standard output with depends_on — role_arn only resolves after policy is attached
output "role_arn" {
  description = "ARN of the IAM deploy role (available after policy is fully attached)"
  value       = aws_iam_role.deploy.arn
  depends_on  = [aws_iam_role_policy.deploy]
}

# Sensitive output — redacted in terminal, visible in JSON and state
output "role_unique_id" {
  description = "AWS-assigned unique ID for the role (sensitive — internal identifier)"
  value       = aws_iam_role.deploy.unique_id
  sensitive   = true
}

# Ephemeral output — available during apply only, never written to state
output "session_hint" {
  description = "Ephemeral hint derived from the ephemeral session_token variable"
  value       = "session configured: ${var.session_token != "" ? "yes" : "no"}"
  ephemeral   = true
}
```

> **Why `depends_on` on `role_arn`:** the role ARN is technically
> available as soon as `aws_iam_role.deploy` completes — before the
> policy is attached. But a consumer using this ARN to assume the role
> needs the policy to be in place first. `depends_on` delays the output
> resolution until `aws_iam_role_policy.deploy` has also completed,
> giving the consumer a signal that the role is *fully configured*, not
> just created.

### Step 2 — Apply and observe output behavior

```bash
terraform apply
```

```bash
# All outputs — human readable
terraform output
```

Expected:

```
role_arn       = "arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role"
role_name      = "cloudnova-dev-deploy-role"
role_unique_id = <sensitive>
session_hint   = <ephemeral>
```

```bash
# Single output
terraform output role_name
# "cloudnova-dev-deploy-role"

# Raw — no quotes, for shell scripts
terraform output -raw role_name
# cloudnova-dev-deploy-role

# JSON — sensitive values included
terraform output -json
```

Expected JSON output (abbreviated):

```json
{
  "role_arn": {
    "sensitive": false,
    "type": "string",
    "value": "arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role"
  },
  "role_name": {
    "sensitive": false,
    "type": "string",
    "value": "cloudnova-dev-deploy-role"
  },
  "role_unique_id": {
    "sensitive": true,
    "type": "string",
    "value": "AROAXXXXXXXXXXXXXXXXX"
  }
}
```

> **Key observation:** `role_unique_id` marked as `sensitive = true` in
> the output block shows its actual value in `-json` output — sensitivity
> only redacts from human-readable terminal display, not from JSON. The
> `session_hint` output marked `ephemeral = true` doesn't appear in
> `-json` at all — it was never written to state.

```bash
# Use jq to extract a specific value from JSON output
terraform output -json | jq -r '.role_arn.value'
# arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role
```

### Step 3 — Create `07-consumer.tf` (remote state consumer)

**07-consumer.tf:**

```hcl
# Reads the outputs from this same configuration's state
# (In a real multi-config setup, this would be in a SEPARATE configuration
# directory. Here we demonstrate the syntax within the same config for
# simplicity — the data source reads from the same state file it's part of.)
data "terraform_remote_state" "this" {
  backend = "s3"

  config = {
    bucket  = "tfstate-cloudnova-163125980376-us-east-2"
    key     = "phase-1/05-variables-locals-outputs/terraform.tfstate"
    region  = "us-east-2"
    profile = "default"
  }
}

# Output derived from the remote state read
output "consumed_role_arn" {
  description = "Role ARN read back from remote state — demonstrates terraform_remote_state"
  value       = data.terraform_remote_state.this.outputs.role_arn
}
```

> **Note:** using `terraform_remote_state` to read the same config's
> own state is technically valid but circular in a real workflow —
> in practice, this data source lives in a *separate* consumer
> configuration (e.g. an application deployment config that needs the
> platform team's IAM role ARN). Here it's in the same config to
> demonstrate the syntax without needing a second project directory.

```bash
terraform apply
```

Expected — the new output appears:

```
consumed_role_arn = "arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role"
```

> **What to observe:** `consumed_role_arn` is derived from
> `data.terraform_remote_state.this.outputs.role_arn` — it reads the
> value from the S3 state file, not from the live AWS resource. This
> is how a separate consumer configuration would reference the platform
> team's role without knowing anything about how it was created.

---

## Cleanup

```bash
terraform destroy
```

Type `yes`. Expected:

```
aws_iam_role_policy.deploy: Destroying...
aws_iam_role_policy.deploy: Destruction complete after 1s
aws_iam_role.deploy: Destroying...
aws_iam_role.deploy: Destruction complete after 2s

Destroy complete! Resources: 2 destroyed.
```

```
Console → IAM → Roles → cloudnova-dev-deploy-role: GONE ✅
```

```bash
unset TF_VAR_environment
```

## What You Learned

1. ✅ Variables have a complete argument set beyond `type`/`default`:
   `sensitive` redacts from terminal output (still in state), `ephemeral`
   prevents the value ever being written anywhere persistent, `nullable`
   controls whether `null` is a valid input even when a default exists,
   and `validation` blocks enforce custom conditions before any API call
2. ✅ Variable value precedence: CLI `-var` > `-var-file` >
   `*.auto.tfvars` > `terraform.tfvars` > `TF_VAR_` env > `default`
3. ✅ The distinction test for variable vs. local: if the value needs
   external input, it's a variable; if it's always derived from other
   values in the configuration, it's a local
4. ✅ `try()` safely accesses attributes that might not exist;
   `coalesce()` returns the first non-null non-empty value; `merge()`
   combines maps with right-most-wins for conflicts
5. ✅ Locals can reference other locals — Terraform resolves dependency
   order automatically
6. ✅ `jsonencode()` inside a local is the idiomatic way to build policy
   documents — keeps the policy as structured HCL data rather than a
   raw string
7. ✅ `sensitive = true` on outputs redacts from human-readable terminal
   output but not from `-json`; `ephemeral = true` outputs are never
   written to state and don't appear in `-json` at all
8. ✅ `depends_on` on outputs delays resolution until a dependency
   completes — useful when consumers need to know a related resource is
   fully configured, not just that the output's source resource exists
9. ✅ `terraform_remote_state` reads another configuration's outputs
   directly from its S3 state file — tightly coupling the consumer to
   the producer's state location and output names

---

## Cert Tips — TA-004 Objectives Covered

This demo covers **TA-004 Objective 4: Use Terraform outside of core
workflow** (variables and outputs) and parts of **Objective 2**:

- Variable value precedence is frequently exam-tested — know the full
  order from CLI flag (highest) to default (lowest)
- `sensitive = true` on a variable **redacts from plan/apply output but
  still stores in state** — this is a common wrong-answer trap that says
  "sensitive variables are encrypted in state"
- `terraform output -json` includes sensitive values — `-json` is
  designed for programmatic consumption, not display
- A `validation` block's `condition` must be a **boolean expression** —
  a string or number condition is itself a validation error
- `terraform_remote_state` reads from the backend's state file
  directly — the referenced configuration must already be applied

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Error: Invalid value for variable` with your own error message | A validation block's condition evaluated to false | Check the value you passed against the condition in the `validation` block |
| `Error: Invalid condition expression` | The `condition` in a `validation` block returned a non-bool (e.g. a string) | Ensure `condition` evaluates to `true` or `false` — use `can()`, `contains()`, or comparison operators |
| `Error: Output refers to sensitive values` | A non-sensitive output references a sensitive variable directly | Either mark the output `sensitive = true` or redesign so the sensitive value isn't exposed as-is |
| `Error: Ephemeral value not allowed` | An ephemeral variable used in a non-ephemeral context (e.g. a regular resource argument or non-ephemeral output) | Ephemeral values can only flow into ephemeral outputs or write-only resource arguments |
| `Error: Failed to read state file` on `terraform_remote_state` | Wrong bucket/key in the `config` block, or the referenced state doesn't exist yet | Verify the S3 key path exactly matches the producer config's backend `key`, and confirm the producer has been applied |
| `terraform output role_unique_id` shows `(sensitive value)` | Expected — `sensitive = true` on the output | Use `terraform output -json | jq -r '.role_unique_id.value'` to extract the value programmatically |
| `coalesce()` ignores a value you expected it to use | `coalesce()` skips null AND empty string — if the value is `""`, it's treated the same as null | Use `try(var.x, null)` inside coalesce, or a conditional expression if you need to distinguish null from empty string |

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

variable "environment" {
  type    = string
  default = "dev"

  validation {
    condition     = "dev"                           # Error 1
    error_message = "Must be dev, staging, or prod"
  }
}

variable "secret_token" {
  type      = string
  default   = "my-token"
  sensitive = true
}

output "token_display" {
  description = "The token value for display"
  value       = var.secret_token                   # Error 2
}

data "terraform_remote_state" "iam" {
  backend = "s3"

  config = {
    bucket = "tfstate-cloudnova-163125980376-us-east-2"
    key    = "phase-1/05-variables-locals-outputs/terraform.tfstate"
    region = "us-east-2"
  }
}

output "remote_role" {
  value = data.terraform_remote_state.iam.outputs.role_nam   # Error 3
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — `condition = "dev"` (string, not bool)**
A `validation` block's `condition` must evaluate to a boolean (`true`
or `false`). The string `"dev"` is not a boolean — Terraform errors:
`Invalid expression: A condition expression must return either true or
false`. Fix: use a proper boolean expression:
```hcl
condition = contains(["dev", "staging", "prod"], var.environment)
```

**Error 2 — non-sensitive output exposes a sensitive variable**
`var.secret_token` is marked `sensitive = true`. Referencing it in an
output without also marking the output `sensitive = true` causes an
error: `Output refers to sensitive values`. Terraform won't let sensitive
values flow into a non-sensitive output implicitly.
Fix: add `sensitive = true` to the output block:
```hcl
output "token_display" {
  value     = var.secret_token
  sensitive = true
}
```

**Error 3 — typo in remote state output name**
`data.terraform_remote_state.iam.outputs.role_nam` — `role_nam` is a
typo of `role_name`. `terraform validate` won't catch this (it can't
know what outputs the referenced state file contains without fetching
it), but `terraform plan` will fail with: `Unsupported attribute: This
object does not have an attribute named "role_nam"`.
Fix: `data.terraform_remote_state.iam.outputs.role_name`

</details>

---

## Interview Prep

**Q1. A teammate marks a variable `sensitive = true` and says "now this value is secure — it's encrypted in state." What's wrong with this statement, and what does `sensitive = true` actually do?**
`sensitive = true` on a variable only redacts the value from terminal output — plan/apply logs, `terraform output` display, and error messages will show `(sensitive value)` instead of the actual value. It has no effect on how the value is stored: it's written to `terraform.tfstate` in plaintext, exactly like any other value. The security guarantee comes from where and how state is stored (encrypted S3 backend with IAM access control, not Git), not from the `sensitive` flag itself. For values that must never be written anywhere persistently, `ephemeral = true` is the correct argument — but ephemeral values have significant constraints (they can't flow into regular resource arguments or non-ephemeral outputs).

**Q2. When would you use `ephemeral = true` on a variable vs `sensitive = true`, and what's the practical limitation of ephemeral?**
Use `sensitive = true` when the value should be available in state (so downstream configurations can read it via `terraform_remote_state`, or so future plans can compare against it), but should be hidden from terminal output. Use `ephemeral = true` when the value must never be stored anywhere — typically short-lived credentials, one-time tokens, or passwords that are passed to a resource at apply time and never needed again. The practical limitation: ephemeral values can only flow into ephemeral outputs or write-only resource arguments — they cannot be used in regular resource arguments that Terraform needs to track in state for drift detection. This means you can't use an ephemeral variable for a resource argument that Terraform manages normally.

**Q3. You have a locals block with `name_prefix`, `role_name` (which references `name_prefix`), and `trust_policy` (which references `role_name`). If you write them in reverse order in the file — `trust_policy` first, then `role_name`, then `name_prefix` — does this affect the result?**
No — local declaration order within a `locals` block (or across multiple `locals` blocks) has no effect on the result. Terraform resolves locals' dependency order automatically from the references within each expression, exactly as it does for resources. `trust_policy` referencing `local.role_name` creates an implicit dependency that Terraform detects — it always computes `name_prefix` before `role_name` before `trust_policy`, regardless of the order they're written in the file. This is the same DAG behavior introduced in Demo 00a.

**Q4. A consumer configuration uses `data.terraform_remote_state` to read the role ARN from this demo's state. The producer configuration renames the output from `role_arn` to `deploy_role_arn`. What breaks, and how do you manage this change safely?**
The consumer's `data.terraform_remote_state.iam.outputs.role_arn` reference becomes invalid — Terraform errors with "Unsupported attribute" on the consumer's next plan. This is the tight-coupling risk of `terraform_remote_state` — output names are part of the interface between configurations, and renaming them is a breaking change for all consumers. Managing it safely: add the new name (`deploy_role_arn`) as an additional output while keeping `role_arn` temporarily, update all consumers to use the new name, then remove the old output in a follow-up change. For frequently-consumed outputs, treat the output name as a public API and version changes carefully.

**Q5. What is the difference between `merge(map_a, map_b)` and `merge(map_b, map_a)` — when does it matter?**
`merge()` uses right-most-wins for key conflicts — the rightmost map's value is used when the same key appears in multiple maps. `merge(map_a, map_b)` means `map_b` wins on conflicts; `merge(map_b, map_a)` means `map_a` wins. This matters specifically when you want one source to be authoritative for specific keys. In the tag-merging pattern from this demo, `merge(local.common_tags, var.extra_tags)` means caller-provided extra tags win over the defaults — a conscious design choice. Reversing it (`merge(var.extra_tags, local.common_tags)`) would mean common tags always win over caller overrides, which is usually not what you want for a "customisable defaults" pattern.

---

## Key Takeaways

1. **`sensitive = true` redacts, it does not encrypt or protect.** State
   security comes from where you store state, not from the `sensitive`
   flag. The flag only prevents accidental logging.

2. **`ephemeral = true` is genuinely never stored — but comes with real
   constraints.** Ephemeral values can't flow into regular resource
   arguments or non-ephemeral outputs. Use only for values that truly
   must not persist.

3. **The distinction test for variable vs. local is simple:** would
   you ever want to override this value externally? Yes = variable.
   No = local. Locals earn their place through transformation, not
   pass-through.

4. **`validation` blocks fire before any API call** — invalid inputs
   are rejected during variable resolution. The `condition` must be a
   boolean expression, not a string or number.

5. **Variable precedence: CLI flag wins, default loses.** The order
   matters for CI/CD design — if you want a value to be overridable
   per-run, make it a variable with a sensible default and pass it via
   `-var` or `TF_VAR_`.

6. **`sensitive = true` on an output hides from terminal, not from
   `-json`.** `-json` is for programmatic consumption and always
   includes sensitive values. Treat `-json` output with the same
   care as state.

7. **`depends_on` on outputs is for consumer guarantees, not producer
   correctness.** The role ARN is correct as soon as the role is
   created — `depends_on` delays the output to tell consumers "the
   role is fully configured," not because the ARN itself needs to wait.

8. **`terraform_remote_state` output names are a public interface.**
   Renaming an output is a breaking change for all consumers. Plan
   output name changes with the same care as a public API change.

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform init` | Downloads provider plugins and initialises the backend |
| `terraform validate` | Checks configuration syntax and schema with zero API calls |
| `terraform fmt -recursive` | Auto-formats `.tf` files in the current directory and all subdirectories |
| `terraform plan -var="<NAME>=<VALUE>"` | Overrides one variable value for this plan (highest precedence) |
| `terraform plan -var-file="<FILE>.tfvars"` | Loads variable overrides from a file |
| `terraform apply` | Applies pending changes after confirmation |
| `terraform output` | Prints all output values in human-readable format |
| `terraform output <NAME>` | Prints a single output value |
| `terraform output -raw <NAME>` | Prints a single output value with no surrounding quotes |
| `terraform output -json` | Prints all outputs as JSON, including sensitive values |
| `terraform output -json \| jq -r '.<NAME>.value'` | Extracts a specific output value using jq |
| `export TF_VAR_<NAME>=<VALUE>` | Sets a variable via environment variable |
| `unset TF_VAR_<NAME>` | Removes a TF_VAR_ environment variable override |
| `terraform destroy` | Destroys all resources managed by this configuration |

---

## Next Demo

**Demo 06 — Data Sources and Expressions:** `data` sources for reading
existing AWS infrastructure without managing it, `for` expressions for
transforming lists and maps, `dynamic` blocks for conditionally-generated
nested blocks, and `count` vs `for_each` for creating multiple instances
of a resource.

---

## Appendix — Anki Cards

**05-variables-locals-outputs-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::05-variables-locals-outputs
#separator:Comma
#columns:Front,Back,Tags
"A variable is marked sensitive = true. Is its value encrypted or protected in terraform.tfstate?","No. sensitive = true ONLY redacts the value from terminal output (plan/apply logs, terraform output display). The value is written to terraform.tfstate in plaintext, exactly like any other value. State security requires storing state securely (encrypted S3 backend, IAM access control) — not the sensitive flag.","demo05,variables,sensitive,ta004"
"What is the difference between sensitive = true and ephemeral = true on a variable?","sensitive = true: value is redacted from terminal output but IS written to state and plan files. ephemeral = true: value exists only in memory during plan/apply — NEVER written to state, plan files, or logs. Ephemeral values can only flow into ephemeral outputs or write-only resource arguments.","demo05,variables,sensitive,ephemeral,ta004"
"A validation block's condition returns the string 'dev' instead of a boolean. What happens?","terraform validate errors: 'A condition expression must return either true or false.' The condition must be a boolean expression — use contains(), can(), regex(), or comparison operators. A string, even a truthy one, is not valid.","demo05,validation,ta004"
"What does nullable = false on a variable do?","Prevents the caller from passing null as a value even when a default exists. By default (nullable = true), a caller can explicitly pass null to override a variable, which causes Terraform to use null instead of the default. nullable = false rejects null — the default is always used if no explicit non-null value is provided.","demo05,variables,nullable"
"State the variable value precedence order from highest to lowest.","1. CLI -var flag, 2. CLI -var-file flag, 3. *.auto.tfvars files (alphabetical), 4. terraform.tfvars, 5. TF_VAR_ environment variables, 6. default value in the variable block, 7. interactive prompt (avoided in CI).","demo05,variables,precedence,ta004"
"What is the distinction test for deciding whether a value should be a variable or a local?","If you would ever want to override this value from outside the configuration (different per environment, per engineer, per run) — it's a variable. If it's always derived from other values in the configuration and never needs external input — it's a local. Locals earn their place through transformation, not pass-through.","demo05,locals,variables,distinction"
"What does try(expr1, expr2) do in Terraform?","try() evaluates each argument in order and returns the first one that doesn't produce an error. Essential for safely accessing attributes that might not exist (e.g. a field on a null object). If all arguments error, try() itself errors.","demo05,locals,try"
"What does coalesce(val1, val2, ...) return?","The first argument that is not null AND not an empty string. Common use: coalesce(var.custom_name, local.computed_default) — uses the custom name if provided, otherwise falls back to the computed default.","demo05,locals,coalesce"
"You call merge(map_a, map_b). Both maps have key 'Owner'. Which value appears in the result?","map_b's value — merge() uses right-most-wins for key conflicts. merge(map_a, map_b) means map_b wins. merge(map_b, map_a) would mean map_a wins.","demo05,locals,merge"
"Can locals reference other locals? Does the order they're written in matter?","Yes, locals can reference other locals. No, the order they're written does not matter — Terraform resolves the dependency order automatically from the references within each expression, exactly as it does for resources.","demo05,locals,ordering"
"What is the difference between aws_iam_role_policy (inline) and aws_iam_policy (managed)?","aws_iam_role_policy is an inline policy attached to exactly one role — it exists only as part of that role and is destroyed with it. aws_iam_policy is a standalone managed policy that can be attached to multiple roles via aws_iam_role_policy_attachment. Use inline for role-specific permissions, managed for shared permissions.","demo05,iam,policy"
"terraform output role_arn shows the value. terraform output role_unique_id shows (sensitive value). A teammate runs terraform output -json. Does role_unique_id's actual value appear in the JSON output?","Yes. terraform output -json is designed for programmatic consumption and always includes sensitive values — sensitivity only redacts from human-readable terminal display. Treat -json output with the same care as the state file itself.","demo05,outputs,sensitive,ta004"
"What does ephemeral = true on an output mean — where is the value available and where is it not?","The value is available during the current plan/apply session and can be used within the same apply (e.g. passed to a module). It is NEVER written to terraform.tfstate and does NOT appear in terraform output -json. Subsequent plans cannot read it from state, and terraform_remote_state cannot access it.","demo05,outputs,ephemeral"
"Why would you put depends_on on an output block, not just on the resource whose attribute the output exposes?","depends_on on an output delays resolution until a dependency fully completes — useful when consumers need to know a RELATED resource (not directly referenced in the output's value) has also been applied. Example: an output exposes the role ARN, but consumers need the inline policy to be attached before assuming the role — depends_on = [aws_iam_role_policy.deploy] signals that the role is fully configured.","demo05,outputs,depends_on"
"What does data.terraform_remote_state actually read from — does it call an AWS API or Terraform's own API?","It calls the S3 GetObject API to download the referenced state file directly from the S3 backend. It does not contact Terraform's own API or require the producer's Terraform CLI to be running. The state file must already exist (the producer must have been applied).","demo05,remote-state,ta004"
"A producer configuration renames its output from role_arn to deploy_role_arn. What breaks for consumers using terraform_remote_state, and what's the safe migration path?","All consumers referencing data.terraform_remote_state.x.outputs.role_arn fail with 'Unsupported attribute'. Safe migration: add deploy_role_arn as a NEW output (keeping role_arn temporarily), update all consumers to use the new name, then remove role_arn in a follow-up change. Output names are a public interface — treat renames as breaking changes.","demo05,remote-state,outputs"
"Can sensitive outputs be read by terraform_remote_state in a consumer configuration?","Yes — sensitive = true on an output only redacts from terminal display. The value is still written to state in plaintext, so a consumer reading the state file via terraform_remote_state can access it. Ephemeral outputs CANNOT be read via terraform_remote_state because they are never written to state.","demo05,remote-state,sensitive,ephemeral"
"What does optional(string, '/') inside an object({}) type constraint do?","Marks that field as optional — callers don't need to provide it. The second argument ('/' in this case) is the default value used when the field is omitted. Without optional(), every field in an object type constraint is required.","demo05,variables,object,optional"
"You call terraform plan -var='environment=prod' with TF_VAR_environment=staging also set. Which value does Terraform use?","prod — CLI -var flag has higher precedence than TF_VAR_ environment variables. The full order from highest to lowest: CLI -var > CLI -var-file > *.auto.tfvars > terraform.tfvars > TF_VAR_ > default.","demo05,variables,precedence,ta004"
"What is the difference between jsonencode() inside a local vs. writing a raw JSON string as a heredoc?","jsonencode() takes HCL data structures (maps, lists, strings) and produces valid JSON — the policy is structured HCL data that Terraform can validate and display in plan diffs as structured changes. A heredoc raw JSON string is opaque to Terraform — it shows as a single string change in plan output, with no indication of what inside the JSON changed. jsonencode() is the idiomatic and more readable approach.","demo05,locals,jsonencode"
```

---

## Appendix — Quiz

**05-variables-locals-outputs-quiz.md:**

````markdown
# Quiz — Demo 05: Variables, Locals, and Outputs: Value Flow Through a Configuration

---

**Q1.** A variable is marked `sensitive = true`. Which statement is
accurate?

A. The value is encrypted in `terraform.tfstate`
B. The value is redacted from plan/apply terminal output but is still
   written to `terraform.tfstate` in plaintext
C. The value is never written to state or any file
D. The value cannot be used in resource arguments

<details>
<summary>Answer</summary>

**B.** `sensitive = true` only redacts from terminal output — state
storage is plaintext regardless. For never-written-to-state behavior,
use `ephemeral = true`. State security requires a secure backend
(encrypted S3, IAM access control), not the `sensitive` flag.

</details>

---

**Q2.** What is the variable value precedence order? Rank these from
highest to lowest: `TF_VAR_` environment variable, CLI `-var` flag,
`default` value, `terraform.tfvars` file.

A. `-var` > `TF_VAR_` > `terraform.tfvars` > `default`
B. `terraform.tfvars` > `-var` > `TF_VAR_` > `default`
C. `TF_VAR_` > `terraform.tfvars` > `-var` > `default`
D. `default` > `terraform.tfvars` > `TF_VAR_` > `-var`

<details>
<summary>Answer</summary>

**A.** CLI `-var` flag has the highest precedence, `TF_VAR_` environment
variables override `terraform.tfvars`, and `default` is the lowest
fallback. Full order: CLI `-var` > `-var-file` > `*.auto.tfvars` >
`terraform.tfvars` > `TF_VAR_` > `default`.

</details>

---

**Q3.** A `validation` block has `condition = "prod"` (a string literal,
not a boolean). What happens?

A. Passes — non-empty strings are truthy in Terraform
B. Errors at `terraform validate` — condition must return a boolean
C. The validation is silently ignored
D. Errors only at `apply` time, not `validate`

<details>
<summary>Answer</summary>

**B.** A `validation` block's `condition` must evaluate to `true` or
`false`. A string literal is not a boolean — `terraform validate` errors
immediately with "A condition expression must return either true or
false."

</details>

---

**Q4.** What does `coalesce(var.custom_name, local.computed_name)`
return when `var.custom_name` is set to an empty string `""`?

A. `""` — coalesce returns the first non-null value, and `""` is not null
B. `local.computed_name` — coalesce skips both null AND empty string
C. An error — coalesce requires at least one non-null argument
D. `null`

<details>
<summary>Answer</summary>

**B.** `coalesce()` skips values that are either `null` OR empty string
`""`. An empty string is treated the same as null — both are skipped.
Only a non-null, non-empty string satisfies coalesce.

</details>

---

**Q5.** You call `merge(local.common_tags, var.extra_tags)`. Both have
a key `"Owner"`. Which value appears in the result?

A. `local.common_tags`'s value — the left-most map wins
B. `var.extra_tags`'s value — the right-most map wins
C. Both values are combined into a list
D. An error — duplicate keys are not allowed

<details>
<summary>Answer</summary>

**B.** `merge()` uses right-most-wins for key conflicts. `var.extra_tags`
is rightmost, so its `"Owner"` value overrides `local.common_tags`'s.

</details>

---

**Q6.** A teammate runs `terraform output -json` and sees the actual
value of an output marked `sensitive = true`. Is this expected behavior?

A. No — this is a bug; sensitive outputs should be redacted everywhere
B. Yes — `sensitive = true` only redacts from human-readable terminal
   display; `-json` always includes the actual value for programmatic use
C. Only if the user has special IAM permissions
D. No — the output should show `null` in JSON format

<details>
<summary>Answer</summary>

**B.** `sensitive = true` redacts from human-readable output only.
`terraform output -json` is designed for programmatic consumption and
always includes sensitive values. Treat `-json` output with the same
care as the state file.

</details>

---

**Q7.** A producer configuration's output is marked `ephemeral = true`.
Can a consumer read it via `data.terraform_remote_state`?

A. Yes — all outputs are available via remote state regardless of
   ephemeral status
B. No — ephemeral outputs are never written to state, so remote state
   has nothing to read
C. Yes — but only if the consumer runs in the same Terraform session
D. Only if the consumer also marks its output `ephemeral = true`

<details>
<summary>Answer</summary>

**B.** Ephemeral outputs are never written to `terraform.tfstate` —
they exist only during the apply session. Since `terraform_remote_state`
reads the state file, ephemeral outputs are simply not there to read.

</details>

---

**Q8.** A producer configuration renames an output from `role_arn` to
`deploy_role_arn`. What is the immediate effect on consumers using
`terraform_remote_state`?

A. No effect — Terraform handles output renames automatically
B. Consumers fail on next `plan` with "Unsupported attribute" for
   `outputs.role_arn`
C. Consumers silently get `null` for the renamed output
D. Consumers must re-run `terraform init` to pick up the new name

<details>
<summary>Answer</summary>

**B.** `terraform_remote_state` references output names directly —
`data.terraform_remote_state.x.outputs.role_arn`. If that output no
longer exists in the producer's state (because it was renamed), the
consumer's plan fails immediately with an unsupported attribute error.
Output names are a public interface.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 06 |
| 7/8 | Review the wrong answer, then proceed |
| 6/8 | Re-read the relevant section, retry those questions |
| Below 6/8 | Re-read the full demo and redo the walkthrough before proceeding |
````