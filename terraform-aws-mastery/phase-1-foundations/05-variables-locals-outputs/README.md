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
- Operators: arithmetic, relational, logical, conditional (`? :`)
- String interpolation, `null` literal, index operator
- Built-in functions: `can()`, `regex()`, `contains()`, `length()`,
  `alltrue()`, `toset()`, `tostring()`, `try()`, `coalesce()`, `merge()`
- When to use a local vs. a variable — the distinction test
- Locals type inference, chaining, and circular reference rules
- Policy document as a `jsonencode()` local
- `sensitive = true` and `ephemeral = true` on outputs
- `depends_on` on outputs and when it's needed
- `terraform output` variants: `-raw`, `-json`, `-no-color`
- `data.terraform_remote_state` — reading another config's outputs
- `aws_iam_role`, `aws_iam_role_policy`, `aws_caller_identity` (new)

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
sts:GetCallerIdentity
s3:GetObject (on state bucket — for terraform_remote_state)
```

> For a learning account, `IAMFullAccess` managed policy covers the IAM
> permissions above.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Declare variables with all type constraints, validation blocks,
   `sensitive`, `ephemeral`, and `nullable` arguments
2. ✅ Explain the variable value precedence order and apply it correctly
3. ✅ Use Terraform's operators and language constructs: arithmetic,
   relational, logical, conditional, string interpolation, index operator
4. ✅ Use `can()`, `regex()`, `contains()`, `length()`, `alltrue()`,
   `toset()`, and type conversion functions correctly
5. ✅ Distinguish between a `variable` (external input) and a `local`
   (internal computed value) using the distinction test
6. ✅ Use `try()`, `coalesce()`, and `merge()` inside locals
7. ✅ Build a policy document as a `jsonencode()` local
8. ✅ Mark outputs as `sensitive` or `ephemeral` and explain what each
   does differently
9. ✅ Use `depends_on` on outputs and explain when it is necessary
10. ✅ Use all `terraform output` command variants
11. ✅ Read another configuration's outputs using
    `data.terraform_remote_state`

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| `aws_iam_role` | Always free — IAM has no cost | **$0.00** | |
| `aws_iam_role_policy` | Always free | **$0.00** | |
| `data.aws_caller_identity` | Always free | **$0.00** | STS read call |
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
3. What does `terraform state push -force` do to the current remote
   state — and why is `-force` sometimes required?

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
3. Overwrites entirely — it does not merge. `-force` is required when
   the file being pushed has a lower serial number than what the backend
   currently holds (e.g. restoring an older backup version). Without
   `-force`, Terraform refuses with "cannot import state with serial N
   over newer state with serial M."

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `variable` block (full depth) | Input declaration | All type constraints, validation, sensitive, ephemeral, nullable |
| `sensitive = true` on variable | Variable argument | Redacts value from plan/apply output — still stored in state |
| `ephemeral = true` on variable | Variable argument | Value never written to state, logs, or plan output — memory-only |
| `nullable = false` on variable | Variable argument | Prevents `null` from being passed as a value even when a default exists |
| `validation` block | Variable sub-block | Enforces a custom condition on the input value before any API call |
| Arithmetic operators | Language construct | `+` `-` `*` `/` `%` — used in validation conditions and locals |
| Relational operators | Language construct | `==` `!=` `<` `>` `<=` `>=` — used in validation conditions |
| Logical operators | Language construct | `&&` `\|\|` `!` — combine multiple conditions |
| Conditional operator | Language construct | `condition ? true_val : false_val` — inline if/else |
| String interpolation | Language construct | `"${expression}"` — embed expressions inside strings |
| Index operator | Language construct | `list[0]`, `map["key"]` — access collection elements |
| `null` literal | Language construct | Explicit absence of a value |
| `for` expression (preview) | Language construct | Transform lists/maps — preview here, full coverage in Demo 06 |
| `can()` | Built-in function | Returns true if an expression evaluates without error |
| `regex()` | Built-in function | Tests a string against a pattern; errors if no match |
| `contains()` | Built-in function | Tests whether a list contains a specific value |
| `length()` | Built-in function | Returns the number of elements in a list, set, map, or string |
| `alltrue()` | Built-in function | Returns true if all elements of a list are true |
| `toset()` `tolist()` `tostring()` `tonumber()` | Built-in functions | Type conversion functions |
| `locals` block (full depth) | Computed values | try(), coalesce(), merge(), chained locals, jsonencode() policy doc |
| `try()` | Built-in function | Returns first argument that evaluates without error |
| `coalesce()` | Built-in function | Returns first argument that is not null and not empty string |
| `merge()` | Built-in function | Combines two or more maps; right-most value wins on key conflicts |
| `sensitive = true` on output | Output argument | Redacts value from `terraform output` display — still stored in state |
| `ephemeral = true` on output | Output argument | Available during apply only, never written to state; root module restriction applies |
| `depends_on` on output | Output meta-argument | Delays output resolution until a dependency fully completes |
| `terraform output -no-color` | CLI flag | Strips ANSI colour codes — use in CI logs |
| `data.terraform_remote_state` | Data source | Reads outputs from another Terraform configuration's state file |
| `data.aws_caller_identity` | Data source | Returns the AWS account ID, ARN, and user ID of the caller |
| `aws_iam_role` | Resource | An IAM role CI/CD pipelines assume to deploy infrastructure |
| `aws_iam_role_policy` | Resource | Inline IAM policy attached directly to a role |

**Related constructs worth knowing (not used in this demo):**

| Construct | What it does |
|---|---|
| `aws_iam_policy` | Standalone (managed) IAM policy — attachable to multiple roles |
| `aws_iam_role_policy_attachment` | Attaches a managed policy to a role (vs. inline `aws_iam_role_policy`) |
| `write_only` argument (Terraform 1.10+) | Resource argument that is never stored in state — covered in Demo 08 |
| `var.x == null ? "default" : var.x` | Inline null-check — alternative to `coalesce()` for simple cases |
| `%{if}` / `%{for}` template directives | Conditional/loop logic inside string templates — covered in Demo 06 |
| `format()`, `join()`, `split()` | String manipulation functions — covered in Demo 06 |
| `flatten()`, `distinct()`, `concat()` | Advanced collection functions — covered in Demo 06 |

---

### Detailed Explanation of New Constructs

---

### Operators and Language Constructs

HCL has no `if` statement, no `while` loop, and no variable assignment
outside of `variable` and `locals` blocks. Logic in Terraform is
expressed through expressions — operators, the conditional operator, and
`for` expressions. Understanding these is required before you can read
validation conditions, locals, and resource arguments confidently.

---

#### Arithmetic Operators

```hcl
var.instance_count + 1
var.max_size - var.min_size
var.disk_gb * 1024          # GB to MB
var.total / var.shards
var.port % 2 == 0           # even port check
```

| Operator | Meaning | Example |
|---|---|---|
| `+` | Addition | `var.min + 1` |
| `-` | Subtraction | `var.max - var.min` |
| `*` | Multiplication | `var.size * 1024` |
| `/` | Division (float result) | `var.total / var.count` |
| `%` | Modulo (remainder) | `var.port % 2` |

> **All Terraform numbers are 64-bit floats internally.** Integer
> division like `5 / 2` returns `2.5`, not `2`. Use `floor(5 / 2)` if
> you need integer division.

---

#### Relational Operators

```hcl
var.instance_count >= 1    # true if count is 1 or more
var.environment == "prod"  # true if environment is exactly "prod"
var.port != 22             # true if port is not 22
```

| Operator | Meaning |
|---|---|
| `==` | Equal |
| `!=` | Not equal |
| `<` | Less than |
| `>` | Greater than |
| `<=` | Less than or equal |
| `>=` | Greater than or equal |

> **String comparison is case-sensitive.** `"Dev" == "dev"` is `false`.
> Use `lower(var.environment) == "dev"` if you need case-insensitive
> comparison.

---

#### Logical Operators

```hcl
var.count >= 1 && var.count <= 10         # AND: both must be true
var.env == "dev" || var.env == "staging"  # OR: either must be true
!var.enable_deletion_protection           # NOT: invert a bool
```

| Operator | Meaning | Short-circuits? |
|---|---|---|
| `&&` | AND — true only if both sides are true | Yes — right side not evaluated if left is false |
| `\|\|` | OR — true if either side is true | Yes — right side not evaluated if left is true |
| `!` | NOT — inverts a boolean | N/A |

---

#### Conditional Operator (`? :`)

The conditional operator is Terraform's only "if/else" mechanism. There
are no `if` statements in HCL.

```hcl
# Syntax: condition ? value_if_true : value_if_false
var.environment == "prod" ? "m5.large" : "t3.micro"

# In a local:
locals {
  instance_type = var.environment == "prod" ? "m5.large" : "t3.micro"
}

# For conditional resource creation (Demo 07):
count = var.create_role ? 1 : 0
```

> **No `if` statements exist in HCL.** If you find yourself wanting
> `if var.env == "prod" { ... }`, the Terraform equivalent is always
> a conditional expression. For conditional resource creation, use
> `count = var.create ? 1 : 0` (covered in Demo 07).

---

#### String Interpolation

String interpolation embeds any Terraform expression inside a string
using `${...}`. Used in every demo since Demo 01 — here it gets its
formal introduction.

```hcl
# Basic — embed variables
"${var.project}-${var.environment}-deploy-role"
# Result: "cloudnova-dev-deploy-role"

# Embed a data source attribute
"arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
# Result: "arn:aws:iam::163125980376:root"

# Embed a conditional
"${var.environment == "prod" ? "PRODUCTION" : "non-prod"} deployment"
```

> **When interpolation is unnecessary:** if the entire string IS the
> expression and that value is already a string, skip the interpolation:
> ```hcl
> # Unnecessary:
> bucket = "${var.bucket_name}"
> # Correct:
> bucket = var.bucket_name
> ```

---

#### Index Operator

Access elements of lists and maps using bracket notation.

```hcl
var.trusted_account_ids[0]   # first element of a list (zero-based)
var.allowed_actions[2]       # third element
local.common_tags["Project"] # map value by key
var.config["network"]["cidr"] # nested map
```

> **Out-of-bounds list access errors at plan time.** Guard with
> `length()`: `length(var.list) > 0 ? var.list[0] : null`

---

#### `null` Literal

`null` is Terraform's explicit "no value" — distinct from `""`, `0`,
`false`, or `[]`.

```hcl
variable "custom_role_name" {
  type    = string
  default = null   # null = "not provided — use the computed name"
}

# Test for null:
var.custom_role_name != null ? var.custom_role_name : local.computed_name
# Or use coalesce() — see coalesce() section below
```

When a resource argument receives `null`, Terraform omits it from the
API call — the AWS service's own default applies.

---

#### `for` Expression — Preview

A `for` expression transforms a list or map into a new list or map.
Used in this demo's `trusted_principals` local — full coverage in
Demo 06.

```hcl
# Basic form: [for item in list : transformation]
[for id in var.trusted_account_ids : "arn:aws:iam::${id}:root"]
# Input:  ["123456789012", "987654321098"]
# Output: ["arn:aws:iam::123456789012:root", "arn:aws:iam::987654321098:root"]
```

Full `for` expression coverage — map transformation, filtering with
`if`, `for` in map context — is in Demo 06.

---

### Built-in Functions Used in This Demo

Terraform has ~120 built-in functions across 9 categories. This section
introduces those used in Demo 05. Functions first used in later demos
are introduced there.

**Function category overview — coverage plan:**

| Category | Demo 05 | Demo 06 | Later |
|---|---|---|---|
| Logic | `can()`, `try()`, `coalesce()`, `alltrue()` | — | — |
| Collection | `contains()`, `length()`, `merge()`, `toset()`, `tolist()` | `flatten()`, `distinct()`, `concat()`, `keys()`, `values()`, `lookup()` | — |
| Encoding | `jsonencode()` | `jsondecode()`, `base64encode()` | — |
| Type conversion | `tostring()`, `tonumber()`, `tobool()` | — | — |
| String | — | `format()`, `join()`, `split()`, `replace()`, `upper()`, `lower()` | — |
| Numeric | — | `abs()`, `ceil()`, `floor()`, `min()`, `max()` | — |
| Filesystem | — | `file()`, `templatefile()` | — |
| Date/time | — | — | Demo 08+ |
| Hash/crypto | — | — | Demo 08+ |

---

#### `can(expression)` — Safe Expression Evaluation

```
Syntax:   can(expression)
Input:    any expression
Returns:  bool — true if expression evaluates without error;
          false if it produces any error
```

```hcl
can(regex("^[a-z]+$", var.name))  # true if matches, false if errors
can(var.config.region)             # true if attribute exists, false if null-access errors
```

`can()` is most commonly paired with `regex()` in validation conditions
— `regex()` errors when there is no match, so `can(regex(...))` converts
that error into `false`, which is what a validation `condition` needs.

```hcl
# Without can() — regex() errors on no match (not a bool):
condition = regex("^[a-z]+$", var.name)        # WRONG

# With can() — safely returns false on no match:
condition = can(regex("^[a-z]+$", var.name))   # CORRECT
```

---

#### `regex(pattern, string)` — Pattern Matching

```
Syntax:   regex(pattern, string)
Input:    pattern (string — RE2 syntax), string to test
Returns:  the matched string (or captured groups if groups used)
Errors:   if the pattern does not match — use can(regex(...)) to handle
```

**Regex patterns used in this demo — explained:**

```
^[a-z][a-z0-9-]{1,18}[a-z0-9]$

^          start of string
[a-z]      must start with a lowercase letter
[a-z0-9-]  middle characters: lowercase letter, digit, or hyphen
{1,18}     between 1 and 18 of the middle characters
[a-z0-9]   must end with a lowercase letter or digit
$          end of string
Total length: 3–20 characters (1 start + 1–18 middle + 1 end)

^[0-9]{12}$

^          start of string
[0-9]      any digit 0–9
{12}       exactly 12 repetitions
$          end of string
Matches:   exactly 12-digit strings (AWS account IDs)
```

> **Terraform uses RE2 regex syntax** — not PCRE. Lookahead/lookbehind
> (`(?=...)`, `(?!...)`) are not supported. For most validation patterns
> the difference doesn't matter.

---

#### `contains(list, value)` — Membership Test

```
Syntax:   contains(list, value)
Input:    list (list or set), value (any)
Returns:  bool — true if the value appears in the list
```

```hcl
contains(["dev", "staging", "prod"], var.environment)
# true if var.environment is one of those three values

contains(["t3.micro", "t3.small"], var.instance_type)
```

The idiomatic way to check whether a variable's value is in an allowed
set inside a validation `condition`.

---

#### `length(collection)` — Element Count

```
Syntax:   length(value)
Input:    list, set, map, or string
Returns:  number — count of elements (or characters for strings)
```

```hcl
length(var.trusted_account_ids)        # number of account IDs
length("cloudnova")                    # 9 — character count
length({a = 1, b = 2})                # 2 — key count
length(var.trusted_account_ids) > 0   # true if at least one ID
```

---

#### `alltrue(list)` — All Elements True

```
Syntax:   alltrue(list)
Input:    list of bool values
Returns:  bool — true if ALL elements are true (or list is empty)
```

```hcl
alltrue([for id in var.trusted_account_ids : can(regex("^[0-9]{12}$", id))])
# Transforms each account ID into a bool (does it match the 12-digit pattern?)
# Then checks that ALL those bools are true
```

> `alltrue([])` returns `true` — an empty list satisfies "all elements
> are true" vacuously. This is why the `trusted_account_ids` validation
> works correctly when the list is empty: no error is raised.

**Related:** `anytrue(list)` — returns `true` if ANY element is true.

---

#### Type Conversion Functions

| Function | Input | Returns | Example |
|---|---|---|---|
| `tostring(value)` | number or bool | string | `tostring(42)` → `"42"` |
| `tonumber(value)` | string | number | `tonumber("42")` → `42` |
| `tobool(value)` | string | bool | `tobool("true")` → `true` |
| `tolist(value)` | set or tuple | list | `tolist(toset(["b","a"]))` → ordered list |
| `toset(value)` | list or tuple | set | `toset(["a","b","a"])` → `{"a","b"}` (deduped) |
| `tomap(value)` | object | map | converts object to map (all values must be same type) |

> **`toset()` deduplicates and loses order.** If you need to deduplicate
> while preserving order, use `distinct(list)` (covered in Demo 06).

---

### Variable Types — Full Reference

#### Primitive Types

| Type | Example value | Notes |
|---|---|---|
| `string` | `"us-east-2"` | Always double-quoted. Supports interpolation. |
| `number` | `8` or `3.14` | Integer or float — all numbers are 64-bit floats internally |
| `bool` | `true` / `false` | Lowercase only — `True` and `TRUE` are invalid |

#### Collection Types

All three require all elements to be the same type. For mixed types,
use `object` or `tuple`.

| Type | Syntax | Example default | Ordered? | Duplicates? |
|---|---|---|---|---|
| `list(type)` | `list(string)` | `["a", "b", "c"]` | Yes | Yes |
| `set(type)` | `set(string)` | `toset(["a", "b"])` | No | No — auto-removed |
| `map(type)` | `map(string)` | `{ key = "val" }` | No | N/A — keys unique |

> **Sets have no literal syntax in HCL.** You cannot write
> `default = {"a", "b"}`. Write a list and convert:
> `default = toset(["a", "b"])`. Via CLI: `-var='my_set=["a","b"]'`
> (Terraform converts automatically).

> **`list` vs `set`:** use `list` when order matters or duplicates are
> meaningful. Use `set` when you need uniqueness and don't care about
> order.

> **`map` vs `object`:** use `map` when keys are dynamic or
> user-defined and all values share the same type. Use `object` when
> the set of keys is fixed and known in advance and values can have
> different types.

#### Structural Types

| Type | Syntax | Notes |
|---|---|---|
| `object({...})` | `object({ name = string, count = number })` | Fixed named fields, each typed independently. Fields are required unless marked `optional()`. |
| `tuple([...])` | `tuple([string, number, bool])` | Fixed-length, positional, mixed-type. Rarely used — `object` is more readable. |
| `any` | `any` | Disables type checking. Use as a last resort. |

**`optional()` inside `object()` — marking fields as optional:**

```hcl
variable "role_config" {
  type = object({
    description      = optional(string)         # optional, defaults to null
    path             = optional(string, "/")    # optional, defaults to "/"
    max_session_secs = optional(number, 3600)  # optional, defaults to 3600
  })
  default = {}   # caller can pass {} — all fields use their defaults
}
```

Without `optional()`, every field in an `object` type is required.
With `optional(type, default)`, the field can be omitted and the
specified default applies.

---

### Variables — Arguments in Full

**Complete variable block syntax:**

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

#### `sensitive = true` — Redacts from Output, Not from State

```hcl
variable "deploy_token" {
  type      = string
  sensitive = true
}
```

When `sensitive = true`:
- Plan/apply output shows `(sensitive value)` instead of the actual value
- `terraform output` shows `(sensitive value)`
- `terraform output -json` shows the actual value in plaintext
- The value IS still written to `terraform.tfstate` in plaintext

> **The most common misconception:** `sensitive = true` is NOT encryption
> — it is redaction from terminal output only. The value still exists in
> state in plaintext. State security requires a secure backend
> (encrypted S3, IAM access control), independent of the `sensitive`
> flag.

---

#### `ephemeral = true` — Never Written to State (Terraform 1.10+)

```hcl
variable "deploy_token" {
  type      = string
  ephemeral = true
}
```

When `ephemeral = true`:
- Value exists only in memory during plan/apply
- Never written to `terraform.tfstate`
- Never written to saved plan files (`-out`)
- Cannot be used in regular resource arguments — only in ephemeral
  contexts

**What is an ephemeral context?**
An ephemeral context is a location where Terraform explicitly guarantees
the value will not be persisted to state. Currently two exist:

1. An `ephemeral = true` output block in a **child module** (not a root
   module — see output section below)
2. A `write_only` resource argument (Terraform 1.10+, covered in Demo 08)

A regular resource argument is NOT an ephemeral context — Terraform must
store it in state for drift detection. Attempting to pass an ephemeral
variable to a regular resource argument errors:

```
Error: Ephemeral value not allowed
  An ephemeral value cannot be used here — the value must be stored in
  the Terraform state for use in future operations.
```

**`sensitive` vs `ephemeral` — the key distinction:**

| | `sensitive = true` | `ephemeral = true` |
|---|---|---|
| Appears in plan/apply terminal output | No (redacted) | No (redacted) |
| Written to `terraform.tfstate` | **Yes — plaintext** | **No — never** |
| Written to saved plan file (`-out`) | **Yes** | **No** |
| Can be used in regular resource arguments | Yes | **No** |
| Can be read by `terraform_remote_state` | Yes (in state) | **No** (never in state) |
| Purpose | Hide from logs/terminal | Truly never persisted anywhere |

> **When to use which:** `sensitive = true` for confidential values that
> need to persist in state. `ephemeral = true` for values that must never
> be stored anywhere — credentials, tokens, passwords passed at apply
> time and never needed again.

---

#### `nullable` — Controlling Whether `null` Is a Valid Input

```hcl
# nullable = true (default) — null is a valid input, overrides default
variable "custom_role_name" {
  type     = string
  default  = null
  nullable = true   # caller passing null → null is used (not the default)
}

# nullable = false — if null is passed, the default is used instead
variable "environment" {
  type     = string
  default  = "dev"
  nullable = false   # caller passing null → "dev" is used
}
```

By default (`nullable = true`) a caller can explicitly pass `null` and
`null` will be used as the value — even if a `default` exists. This is
useful when `null` has a deliberate meaning: "use the resource's own
default for this argument" (passing `null` to a resource argument causes
Terraform to omit it from the API call, letting AWS's own default apply).

Setting `nullable = false` changes this: **if null is passed, the
default is used instead.**

---

#### `validation` Blocks — Custom Conditions

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
| `condition` | A boolean expression. The ONLY reference allowed is `var.<this_variable>`. Must return `true` or `false` — a string or number condition is itself a validation error. |
| `error_message` | Shown when condition is false. Must be a non-empty string ending with a period. |

**What validation can and cannot check:**

```hcl
# VALID — tests this variable's own value
condition = can(regex("^[a-z][a-z0-9-]+$", var.project))

# VALID — arithmetic on this variable
condition = var.max_session_duration >= 3600 && var.max_session_duration <= 43200

# INVALID — references another variable (not in scope)
condition = var.max_size > var.min_size        # ERROR: var.min_size not in scope

# INVALID — references a resource (not in scope)
condition = var.name != aws_s3_bucket.main.bucket  # ERROR: resources not in scope
```

> **Validation fires before any API call** — invalid inputs are rejected
> during variable resolution, before Terraform contacts AWS.

---

### Variable Value Precedence

When the same variable can receive a value from multiple sources,
Terraform uses this precedence order — highest wins:

```
1 (highest)  CLI flag:          terraform apply -var="environment=staging"
2            CLI var-file:      terraform apply -var-file="staging.tfvars"
3            *.auto.tfvars:     loaded automatically, alphabetical order
4            terraform.tfvars:  loaded automatically if present
5            TF_VAR_ env vars:  export TF_VAR_environment=staging
6            Default value:     default = "dev" in the variable block
7 (lowest)   Interactive prompt (no default — avoided in CI)
```

**How each mechanism looks in practice:**

```bash
# Level 1 — CLI flag (highest precedence)
terraform apply -var="environment=prod"
terraform plan  -var="environment=staging" -var="project=myapp"

# Level 2 — CLI var-file
terraform apply -var-file="prod.tfvars"
# prod.tfvars:
# environment = "prod"
# project     = "myapp"

# Level 3 — auto.tfvars (loaded automatically — no flag needed)
# File: prod.auto.tfvars
# environment = "prod"

# Level 4 — terraform.tfvars (loaded automatically)
# File: terraform.tfvars
# environment = "dev"

# Level 5 — environment variable
export TF_VAR_environment=staging
terraform plan   # uses staging
unset TF_VAR_environment

# Level 6 — default value (used when nothing else provides a value)
variable "environment" { default = "dev" }
```

**When to use each mechanism:**

| Mechanism | When to use |
|---|---|
| `default` | Safe fallback for values that rarely change |
| `terraform.tfvars` | Local developer overrides — add to `.gitignore`, never commit |
| `*.auto.tfvars` | Environment-specific value sets checked into Git (non-sensitive only) |
| `TF_VAR_` env vars | CI/CD pipelines — values injected by the pipeline system at runtime |
| `-var-file` | One-off override for a specific deployment |
| `-var` flag | Highest-precedence override — human-initiated one-off, not automated pipelines |

---

### `data.aws_caller_identity` — Current Account Identity

```hcl
data "aws_caller_identity" "current" {}
```

The body is intentionally empty — no arguments are required. Makes a
single `sts:GetCallerIdentity` API call and returns:

| Attribute | Example value | Description |
|---|---|---|
| `account_id` | `"163125980376"` | AWS account ID of the caller |
| `arn` | `"arn:aws:iam::163125980376:user/wadmin"` | ARN of the caller |
| `user_id` | `"AIDAXXXXXXXXXXXXXXXXX"` | Unique ID of the caller |

**Why it's in `04-locals.tf`:** the data source is used inside the
`trusted_principals` local — placing it in `04-locals.tf` keeps all
inputs to the locals block (variables and data sources) in one file,
making the dependency clear without jumping files.

---

### `aws_iam_role` and `aws_iam_role_policy`

**`aws_iam_role`:** an IAM role is an AWS identity that can be assumed
by services, users, or other accounts. Unlike an IAM user (which has
long-term credentials), a role issues temporary credentials when assumed.

| Argument | Required | Description |
|---|---|---|
| `name` | No — but always set | Role name. Must be unique within the account. Max 64 characters. |
| `assume_role_policy` | **Yes** | JSON trust policy — who is allowed to assume this role |
| `description` | No | Human-readable description |
| `max_session_duration` | No | Seconds. Range: 3600–43200. Default: 3600. |
| `path` | No | IAM path for organisational grouping. Default: `"/"`. |
| `tags` | No | Resource tags |

**`aws_iam_role_policy`:** an inline policy attached to one specific
role. Cannot be reused — exists only as part of the role it's attached
to.

| Argument | Required | Description |
|---|---|---|
| `name` | Yes | Policy name — unique within the role |
| `role` | Yes | The role's name or ID — `aws_iam_role.deploy.name` |
| `policy` | Yes | JSON permission policy document |

**Inline vs. managed policies:**
- **Inline:** specific to one role, destroyed with the role — use for
  role-specific permissions
- **Managed (`aws_iam_policy` + `aws_iam_role_policy_attachment`):**
  attachable to multiple roles — use for shared permissions

---

### Locals — Full Depth

---

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

**What type is `default_tags` — `object` or `map`?**

```hcl
locals {
  default_tags = {
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

### Built-in Functions — `try()`, `coalesce()`, `merge()`

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

### Outputs — Full Depth

---

#### `sensitive = true` on Outputs

```hcl
output "role_unique_id" {
  description = "AWS-assigned unique ID for the role"
  value       = aws_iam_role.deploy.unique_id
  sensitive   = true
}
```

- `terraform output role_unique_id` shows `(sensitive value)`
- `terraform output -json` shows the actual value — JSON is for
  programmatic consumption and always includes sensitive values
- The value IS written to state in plaintext
- Consumer configurations reading via `terraform_remote_state` can
  access the value — sensitivity is not inherited

---

#### `ephemeral = true` on Outputs (Terraform 1.10+)

```hcl
# CHILD MODULE ONLY — see restriction note below
output "session_hint" {
  value     = var.session_token
  ephemeral = true
}
```

> **Root module restriction:** `ephemeral = true` on an output is NOT
> supported in root modules — only in child modules. Attempting to use
> it in a root module errors at `terraform validate`:
> ```
> Error: Ephemeral output not allowed
>   Ephemeral outputs are not allowed in context of a root module
> ```
> Ephemeral outputs in child modules allow a module to return a value
> that the calling module can use within the same apply without the
> value being written to state. In root modules, there is no caller to
> receive the ephemeral value — hence the restriction.

---

#### `depends_on` on Outputs

```hcl
output "role_arn" {
  value      = aws_iam_role.deploy.arn
  depends_on = [aws_iam_role_policy.deploy]
}
```

By default, an output is computed as soon as the resource it references
has completed. `depends_on` delays output resolution until the listed
resources have also fully completed.

**When outputs are computed:** Terraform computes each output as soon as
all resources in its value expression AND its `depends_on` list have
completed — not necessarily at the very end of `apply`. In a large
configuration, some outputs may resolve mid-apply while others are still
running. In a small configuration like this demo it effectively feels
like "all at the end."

**The real use case for `depends_on` on outputs:** it matters when
another configuration (a child module or concurrent consumer) can start
reading outputs before the current apply finishes. `depends_on =
[aws_iam_role_policy.deploy]` signals "do not consume the role ARN until
the policy is also attached — the role is not fully configured until
both resources complete." For sequential apply-then-consume workflows
where the consumer runs after the producer finishes, `depends_on` on
outputs has no practical effect — all resources are already done by the
time the consumer starts.

---

#### `terraform output` Variants

```bash
terraform output                         # all outputs, human-readable
terraform output role_name               # single output
terraform output -raw role_name          # no surrounding quotes — use in shell scripts
terraform output -json                   # all outputs as JSON, including sensitive values
terraform output -json | jq -r '.role_arn.value'   # extract with jq
terraform output -no-color               # strip ANSI colour codes — use in CI logs
```

> **`-no-color`:** without this flag, CI log systems that don't
> interpret ANSI codes display literal escape sequences (e.g.
> `\033[32m"cloudnova-dev-deploy-role"\033[0m`) instead of formatted
> colour. Use `-no-color` whenever output is captured as plain text or
> logged to a system that doesn't render ANSI formatting.

---

### `data.terraform_remote_state` — Reading Another Config's Outputs

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

**How it works:** calls the S3 `GetObject` API under the consumer's own
AWS credentials to download the state file directly. No Terraform API,
no provider call to IAM.

**IAM permissions required:** the AWS credentials in the consumer's
provider block must have `s3:GetObject` on the state bucket and key
path. No special Terraform permissions are needed — it is a standard
S3 read.

**What if the state file doesn't exist?**

If the producer has never been applied, `terraform plan` on the consumer
fails immediately:

```
Error: Error loading state error
  error loading the remote state: NoSuchKey
```

Real-world handling options:

1. **Sequential dependency:** always apply the producer before the
   consumer. Enforce in CI by making the consumer pipeline depend on
   the producer pipeline.
2. **Conditional fallback with `try()`:**
   ```hcl
   role_arn = try(data.terraform_remote_state.iam.outputs.role_arn, "")
   ```
   Allows the consumer's plan to succeed during initial bootstrap.

**Which outputs are accessible:**

ALL non-ephemeral outputs are accessible via `terraform_remote_state` —
including `sensitive = true` outputs (the state file contains them in
plaintext). Ephemeral outputs are NOT accessible because they were never
written to state.

> **Common misconception:** "only non-sensitive outputs are accessible."
> This is wrong. Sensitive outputs ARE in the state file and ARE readable
> via `terraform_remote_state`. Any consumer with `s3:GetObject` access
> to the state bucket can read your sensitive output values.

**Supported backends:**

| Backend | Notes |
|---|---|
| `s3` | Used in this series — most common for AWS teams |
| `gcs` | Google Cloud Storage |
| `azurerm` | Azure Blob Storage |
| `remote` | HCP Terraform / Terraform Cloud |
| `local` | Local filesystem — development/testing only |
| `http` | Generic HTTP backend |
| `kubernetes` | Kubernetes Secret as backend |
| `consul` | HashiCorp Consul |
| `pg` | PostgreSQL |

The `config {}` block arguments differ per backend — refer to each
backend's documentation for the correct keys.

---

### `terraform_remote_state` vs. Other Sharing Patterns

| Pattern | How it works | Coupling | Failure mode | Best for |
|---|---|---|---|---|
| `terraform_remote_state` | Consumer reads producer's state file from S3 | **Tight** — depends on state location AND output names | Consumer `plan` fails if producer state doesn't exist | Same team, tightly-related infrastructure |
| SSM Parameter Store | Producer writes values to SSM; consumer reads via `data.aws_ssm_parameter` | **Loose** — only needs the parameter name | Consumer `plan` fails if parameter doesn't exist | Cross-team, cross-account, independently-changing infra |
| CLI flags / env vars | Shell script passes values between Terraform runs | **None** — no Terraform-level coupling | Fails at the shell script level | Simple pipelines, passing values between CI steps |
| Hardcoded values | ARN/ID written directly into `.tf` files | **Maximum** | No runtime failure — but stale values if producer changes | Never in practice |

**CLI flags / env vars as a sharing pattern — concrete example:**

```bash
# CI pipeline — Step 1: apply producer, capture output
cd producer/
terraform apply -auto-approve
ROLE_ARN=$(terraform output -raw role_arn)

# CI pipeline — Step 2: pass to consumer via env var
cd ../consumer/
export TF_VAR_role_arn="$ROLE_ARN"
terraform apply -auto-approve
```

This pattern requires no shared state access — the consumer receives
the value as a variable. The downside: the pipeline must run in the
correct order and the value is not version-controlled.

> **SSM Parameter Store as a Terraform-native decoupled sharing
> mechanism** is planned for a future demo. Pattern: producer writes
> `aws_ssm_parameter.role_arn` → consumer reads
> `data.aws_ssm_parameter.role_arn`. The parameter name is the contract
> between teams, not the state file location.

---

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

---

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
  nullable    = false

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

# NOTE: ephemeral variables cannot be used in regular resource arguments.
# var.session_token is demonstrated in Step 11 but NOT referenced in any
# resource argument — it can only flow to an ephemeral output (child module
# only) or a write-only resource argument (Demo 08).
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
# Data source — current AWS account ID, used in trust policy self-trust fallback
data "aws_caller_identity" "current" {}

locals {
  # ── Step 1: name prefix ───────────────────────────────────────────────────
  name_prefix = "${var.project}-${var.environment}"

  # ── Step 2: role and policy names ────────────────────────────────────────
  # coalesce(): if var.custom_role_name is null (default), use the computed name
  role_name   = coalesce(var.custom_role_name, "${local.name_prefix}-${var.role_purpose}-role")
  policy_name = "${local.name_prefix}-${var.role_purpose}-policy"

  # ── Step 3: trust policy — who can assume this role ──────────────────────
  # Expression breakdown:
  #   length(var.trusted_account_ids) > 0
  #     → conditional operator: if the list has at least one element...
  #   ? [for id in var.trusted_account_ids : "arn:aws:iam::${id}:root"]
  #     → for expression: transform each account ID into a principal ARN
  #   : ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
  #     → fallback: self-trust using the current account's ID
  #
  # Result when trusted_account_ids = ["123456789012"]:
  #   ["arn:aws:iam::123456789012:root"]
  # Result when trusted_account_ids = [] (default — self-trust):
  #   ["arn:aws:iam::163125980376:root"]
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

  # ── Step 6: role-specific tags — merge() adds Purpose on top of common ─────
  role_tags = merge(local.common_tags, {
    Purpose = var.role_purpose
  })
}
```

> **Chaining in action:** `name_prefix` → `role_name` / `policy_name`
> → `trusted_principals` (uses `data.aws_caller_identity`) →
> `trust_policy` / `permission_policy`. Terraform resolves this
> automatically — write them in any order.

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
```

Expected:

```
Success! The configuration is valid.
```

```bash
terraform fmt -recursive
terraform apply
```

Type `yes`. Expected output:

```
data.aws_caller_identity.current: Reading...
data.aws_caller_identity.current: Read complete after 0s [id=163125980376]

aws_iam_role.deploy: Creating...
aws_iam_role.deploy: Creation complete after 1s [id=cloudnova-dev-deploy-role]
aws_iam_role_policy.deploy: Creating...
aws_iam_role_policy.deploy: Creation complete after 1s [id=cloudnova-dev-deploy-role:cloudnova-dev-deploy-policy]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

> ⚠️ Simulated expected output — not from a live terminal run. Role name
> and policy name are derived from default variable values and should
> match if defaults are unchanged.

---

### Step 8 — Verify in Console

```
Console → IAM → Roles → cloudnova-dev-deploy-role

Trust relationships tab:
  → Trusted entities: arn:aws:iam::<your-account-id>:root ✅

Permissions tab:
  → cloudnova-dev-deploy-policy (inline) ✅
  → JSON: AllowedActions: s3:GetObject, s3:PutObject, s3:ListBucket ✅

Tags tab:
  → Environment: dev, Purpose: deploy, ManagedBy: Terraform ✅
```

---

### Step 9 — Test variable precedence (all six levels)

**Level 6 — default (baseline):**

```bash
terraform plan | grep "cloudnova"
```

Expected: `cloudnova-dev-deploy-role` — from `default = "dev"`.

**Level 5 — TF_VAR_ environment variable:**

```bash
export TF_VAR_environment=staging
terraform plan | grep "cloudnova"
```

Expected: `cloudnova-staging-deploy-role` — env var overrides default.

**Level 4 — terraform.tfvars overrides TF_VAR_:**

```bash
echo 'environment = "prod"' > terraform.tfvars
terraform plan | grep "cloudnova"
```

Expected: `cloudnova-prod-deploy-role` — `terraform.tfvars` overrides
the `TF_VAR_environment=staging` env var.

**Level 3 — *.auto.tfvars overrides terraform.tfvars:**

```bash
echo 'environment = "staging"' > override.auto.tfvars
terraform plan | grep "cloudnova"
```

Expected: `cloudnova-staging-deploy-role` — `.auto.tfvars` overrides
`terraform.tfvars`.

**Level 1 — CLI `-var` flag overrides everything:**

```bash
terraform plan -var="environment=dev" | grep "cloudnova"
```

Expected: `cloudnova-dev-deploy-role` — CLI flag wins over all files
and env vars.

**Clean up:**

```bash
unset TF_VAR_environment
rm -f terraform.tfvars override.auto.tfvars
```

---

### Step 10 — Test validation

```bash
terraform plan -var="environment=qa"
```

Expected:

```
╷
│ Error: Invalid value for variable
│   environment must be dev, staging, or prod.
╵
```

```bash
terraform plan -var="max_session_duration=999"
```

Expected:

```
╷
│ Error: Invalid value for variable
│   max_session_duration must be between 3600 (1 hour) and 43200 (12 hours).
╵
```

```bash
terraform plan -var='trusted_account_ids=["not-an-id"]'
```

Expected:

```
╷
│ Error: Invalid value for variable
│   All trusted_account_ids must be 12-digit AWS account IDs.
╵
```

> **All errors appear before Terraform contacts AWS** — validation fires
> during variable resolution.

---

### Step 11 — Observe sensitive and ephemeral variable behaviour

```bash
terraform plan -var="external_secret_label=my-real-secret"
```

Any reference to `var.external_secret_label` in plan output shows
`(sensitive value)`. Check that it IS in state in plaintext:

```bash
terraform state pull | jq '.resources[] | select(.type=="aws_iam_role") | .instances[0].attributes.tags'
```

```bash
terraform apply -var="session_token=my-real-token"
```

Confirm `session_token` is NOT in state:

```bash
terraform state pull | jq '.' | grep -i "session"
```

Expected: no output — `session_token` was in memory during apply and
discarded immediately after. It was never written to state.

---

## Part B — Locals in Depth: Refactor and Extend

**What you accomplish in Part B:** extend the configuration to
demonstrate `try()` for safe access, `coalesce()` for conditional
naming, `merge()` for tag composition, and chained locals.

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

---

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

---

### Step 3 — Update `05-main.tf`

```hcl
resource "aws_iam_role" "deploy" {
  name                 = local.role_name
  description          = local.role_description
  path                 = try(var.role_config.path, "/")
  assume_role_policy   = local.trust_policy
  max_session_duration = local.effective_max_session
  tags                 = local.role_tags
}
```

---

### Step 4 — Test with and without the optional config

```bash
# Without role_config — uses all defaults
terraform apply
# description = "CI/CD deploy role for cloudnova dev", max_session_duration = 3600

# With partial role_config — only description overridden
terraform apply -var='role_config={"description":"Platform deploy role"}'
# description = "Platform deploy role", max_session_duration = 3600 (unchanged)
```

---

### Step 5 — Demonstrate `merge()` tag composition

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

---

## Part C — Outputs in Depth and Remote State

**What you accomplish in Part C:** expose the IAM role's attributes as
outputs with different sensitivity levels, practise all `terraform output`
variants, then consume those outputs using `terraform_remote_state`.

### Step 1 — Confirm prerequisites

Before creating `07-consumer.tf`, confirm:

1. **The state bucket exists.** Confirm the bucket from Demo 01 is
   still present:

```bash
aws s3 ls s3://tfstate-cloudnova-<your-account-id>-us-east-2 --profile default
```

2. **The state file exists at the key.** The `apply` in Part A wrote
   the state file — confirm it exists:

```bash
aws s3 ls s3://tfstate-cloudnova-<your-account-id>-us-east-2/phase-1/05-variables-locals-outputs/ --profile default
```

Expected: shows `terraform.tfstate` with a timestamp.

---

### Step 2 — Create `06-outputs.tf`

```hcl
# Standard output — visible in all terraform output variants
output "role_name" {
  description = "Name of the IAM deploy role"
  value       = aws_iam_role.deploy.name
}

# Standard output with depends_on — only resolves after policy is attached
output "role_arn" {
  description = "ARN of the IAM deploy role (available after policy is fully attached)"
  value       = aws_iam_role.deploy.arn
  depends_on  = [aws_iam_role_policy.deploy]
}

# Sensitive output — redacted in human-readable display, visible in -json
output "role_unique_id" {
  description = "AWS-assigned unique ID for the role (sensitive — internal identifier)"
  value       = aws_iam_role.deploy.unique_id
  sensitive   = true
}

# NOTE: ephemeral = true on outputs is NOT supported in root modules.
# Attempting it errors at terraform validate:
#   Error: Ephemeral output not allowed
#   Ephemeral outputs are not allowed in context of a root module
# The session_token variable is demonstrated in Step 11 (Part A) instead.
```

---

### Step 3 — Apply and observe output behaviour

```bash
terraform apply
terraform output
```

Expected:

```
role_arn       = "arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role"
role_name      = "cloudnova-dev-deploy-role"
role_unique_id = <sensitive>
```

```bash
terraform output -raw role_name
# cloudnova-dev-deploy-role   (no surrounding quotes)

terraform output -json
```

Expected (abbreviated):

```json
{
  "role_arn": { "sensitive": false, "type": "string", "value": "arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role" },
  "role_name": { "sensitive": false, "type": "string", "value": "cloudnova-dev-deploy-role" },
  "role_unique_id": { "sensitive": true, "type": "string", "value": "AROAXXXXXXXXXXXXXXXXX" }
}
```

> **Key observation:** `role_unique_id` marked `sensitive = true` shows
> its actual value in `-json` — sensitivity only redacts from
> human-readable display.

```bash
terraform output -json | jq -r '.role_arn.value'
# arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role

terraform output -no-color
# Same as terraform output — without ANSI colour escape codes
```

---

### Step 4 — Create `07-consumer.tf`

Replace `<your-account-id>` with your actual AWS account ID before
saving.

```hcl
# In a real multi-configuration setup, this data source lives in a SEPARATE
# configuration directory pointing at the producer's state. Here it's in the
# same configuration to demonstrate the syntax without requiring a second project.
data "terraform_remote_state" "this" {
  backend = "s3"

  config = {
    bucket  = "tfstate-cloudnova-<your-account-id>-us-east-2"
    key     = "phase-1/05-variables-locals-outputs/terraform.tfstate"
    region  = "us-east-2"
    profile = "default"
  }
}

output "consumed_role_arn" {
  description = "Role ARN read back from remote state — demonstrates terraform_remote_state"
  value       = data.terraform_remote_state.this.outputs.role_arn
}
```

```bash
terraform apply
```

Expected — new output appears:

```
consumed_role_arn = "arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role"
```

> **What to observe:** `consumed_role_arn` equals `role_arn` in value —
> both ultimately describe the same IAM role. The mechanism differs:
> `role_arn` reads from Terraform's in-memory resource graph during
> apply. `consumed_role_arn` reads from the S3 state file via a
> `GetObject` API call. In a real multi-config setup, the consumer
> would live in a separate directory with no knowledge of how the role
> was created.

---

### Step 5 — Test remote state failure behaviour

Temporarily edit `07-consumer.tf` to use a wrong key:

```hcl
key = "phase-1/05-variables-locals-outputs/nonexistent.tfstate"
```

```bash
terraform plan
```

Expected:

```
Error: Error loading state error
  error loading the remote state: NoSuchKey: The specified key does not exist.
```

Revert `07-consumer.tf` to the correct key after observing the error.

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
rm -f terraform.tfvars override.auto.tfvars
```

---

## What You Learned

1. ✅ Variables have a complete argument set: `sensitive` redacts from
   terminal output (still in state), `ephemeral` prevents the value
   ever being written anywhere persistent, `nullable = false` means if
   null is passed the default is used, and `validation` blocks enforce
   custom conditions before any API call
2. ✅ Variable value precedence: CLI `-var` > `-var-file` >
   `*.auto.tfvars` > `terraform.tfvars` > `TF_VAR_` env > `default`
3. ✅ HCL has no `if` statement — the conditional operator (`? :`) is
   the only conditional mechanism; arithmetic (`+` `-` `*` `/` `%`),
   relational (`==` `!=` `<` `>` `<=` `>=`), and logical (`&&` `||`
   `!`) operators work as in other languages
4. ✅ `can(regex(...))` is the idiomatic validation pattern — `regex()`
   errors on no match, `can()` converts that error to `false`
5. ✅ `contains()` tests membership; `length()` counts elements;
   `alltrue()` tests every element — `alltrue([])` returns `true`
6. ✅ Collection types (`list`, `set`, `map`) require homogeneous
   elements; `object` allows mixed types with fixed named fields. Sets
   have no literal syntax — use `toset([...])`. Locals have no `type`
   argument — type is inferred from the expression
7. ✅ The distinction test: if the value needs external input, it's a
   variable; if always derived from other values, it's a local. Locals
   type is inferred; you cannot declare a type constraint on a local
8. ✅ `try()` returns the first non-erroring expression; `coalesce()`
   returns the first non-null non-empty value; `merge()` combines maps
   with right-most-wins on key conflicts
9. ✅ `sensitive = true` on outputs redacts from terminal but NOT from
   `-json`; `ephemeral = true` outputs are child-module-only (root
   module errors at validate) and never written to state
10. ✅ `terraform_remote_state` reads ALL non-ephemeral outputs — including
    sensitive ones. Output names are a public interface; renaming is a
    breaking change for all consumers

---

## Cert Tips — TA-004 Objectives Covered

This demo covers **TA-004 Objective 4: Use Terraform outside of core
workflow** (variables and outputs) and parts of **Objective 2**:

- Variable value precedence is frequently exam-tested — know the full
  order from CLI flag (highest) to default (lowest)
- `sensitive = true` on a variable **still stores in state in plaintext**
  — a common wrong-answer trap says "sensitive variables are encrypted"
- `terraform output -json` includes sensitive values — designed for
  programmatic use, not display
- A `validation` block's `condition` must be a **boolean expression**
- `alltrue([])` returns `true` — empty list satisfies vacuously
- `coalesce()` skips both `null` AND `""` (empty string)
- `ephemeral = true` on an output is **only valid in child modules**
- `terraform_remote_state` reads from the backend's state file directly
  — the referenced configuration must already be applied; sensitive
  outputs ARE accessible (they are in the state file in plaintext)

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Error: Invalid value for variable` | A validation block's condition evaluated to false | Check the value against the condition in the `validation` block |
| `Error: Invalid condition expression` | The `condition` returned a non-bool (e.g. a string literal) | Ensure `condition` evaluates to `true` or `false` — use `can()`, `contains()`, or comparison operators |
| `Error: Output refers to sensitive values` | A non-sensitive output references a sensitive variable | Mark the output `sensitive = true` |
| `Error: Ephemeral value not allowed` | An ephemeral variable used in a regular resource argument | Ephemeral values can only flow into ephemeral outputs (child modules) or write-only resource arguments (Demo 08) |
| `Error: Ephemeral output not allowed — not allowed in context of a root module` | `ephemeral = true` on an output in a root module | Remove `ephemeral = true` from root module outputs — child modules only |
| `Error: Error loading state error — S3 bucket does not exist` | Wrong bucket name in `terraform_remote_state` config, or state bucket not created | Verify bucket name; confirm bucket exists in Console |
| `Error: NoSuchKey` on `terraform_remote_state` | Producer never applied — state file doesn't exist at the key | Apply producer first; or use `try(data.terraform_remote_state.x.outputs.role_arn, "")` for bootstrap |
| `terraform output role_unique_id` shows `(sensitive value)` | Expected — `sensitive = true` | Use `terraform output -json \| jq -r '.role_unique_id.value'` |
| `coalesce()` ignores a value you expected it to use | `coalesce()` skips null AND `""` | Use a conditional expression if you need to distinguish null from empty string |
| `Error: Cycle in local values` | Two or more locals reference each other circularly | Break the cycle — extract the shared value into a third local |
| `Error: Unsupported attribute` on `terraform_remote_state` reference | Output name typo or producer renamed an output | Run `terraform output -json` on the producer to see exact output names |

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
    condition     = "dev"                             # Error 1
    error_message = "Must be dev, staging, or prod."
  }
}

variable "secret_token" {
  type      = string
  default   = "my-token"
  sensitive = true
}

output "token_display" {
  description = "The token value for display"
  value       = var.secret_token                     # Error 2
}

data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket  = "tfstate-cloudnova-163125980376-us-east-2"
    key     = "phase-1/05-variables-locals-outputs/terraform.tfstate"
    region  = "us-east-2"
    profile = "default"
  }
}

output "remote_role" {
  value = data.terraform_remote_state.iam.outputs.role_nam   # Error 3
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — `condition = "dev"` (string, not bool)**
A `validation` block's `condition` must evaluate to `true` or `false`.
`terraform validate` errors: "A condition expression must return either
true or false." Fix:
```hcl
condition = contains(["dev", "staging", "prod"], var.environment)
```

**Error 2 — non-sensitive output exposes a sensitive variable**
`var.secret_token` is `sensitive = true`. Referencing it in an output
without also marking the output `sensitive = true` causes: "Output
refers to sensitive values." Fix:
```hcl
output "token_display" {
  value     = var.secret_token
  sensitive = true
}
```

**Error 3 — typo in remote state output name**
`role_nam` is a typo for `role_name`. `terraform validate` won't catch
this (it can't fetch the state file to check), but `terraform plan`
fails: "Unsupported attribute: This object does not have an attribute
named 'role_nam'." Fix:
```hcl
value = data.terraform_remote_state.iam.outputs.role_name
```

</details>

---

## Interview Prep

**Q1. A teammate marks a variable `sensitive = true` and says "now this value is secure — it's encrypted in state." What's wrong?**
`sensitive = true` only redacts from terminal output. The value is written to `terraform.tfstate` in plaintext. Security comes from how state is stored — encrypted S3 backend with IAM access control — not the `sensitive` flag. For values that must never be stored anywhere, `ephemeral = true` is correct, but it carries significant constraints: ephemeral values can't flow into regular resource arguments, and ephemeral outputs are only valid in child modules.

**Q2. When would you use `ephemeral = true` vs. `sensitive = true` on a variable, and what is the practical limitation of ephemeral?**
`sensitive = true`: value persists in state (downstream configs can read it; future plans can compare against it for drift detection) but is hidden from terminal output. `ephemeral = true`: value must never be stored anywhere — credentials, one-time tokens passed at apply time and never needed again. Practical limitations: ephemeral values can only flow into ephemeral outputs (child modules only — not root modules) or write-only resource arguments. They cannot be used in regular resource arguments that Terraform tracks in state.

**Q3. You have a locals block with `name_prefix`, `role_name`, and `trust_policy` chained together. If you write them in reverse order in the file, does this affect the result?**
No. Local declaration order has no effect — Terraform resolves dependency order automatically from the references within each expression, exactly as it does for resources. `trust_policy` referencing `local.role_name` creates an implicit dependency; Terraform always evaluates `name_prefix` → `role_name` → `trust_policy` regardless of file order.

**Q4. A consumer uses `terraform_remote_state` to read `role_arn`. The producer renames it to `deploy_role_arn`. What breaks and what is the safe migration path?**
The consumer's reference to `outputs.role_arn` errors with "Unsupported attribute" on the next plan. Output names are a public interface — renaming is a breaking change. Safe migration: add `deploy_role_arn` as a new output while keeping `role_arn` temporarily, update all consumers to the new name, then remove `role_arn` in a follow-up change.

**Q5. What is the difference between `merge(map_a, map_b)` and `merge(map_b, map_a)`?**
`merge()` uses right-most-wins for key conflicts. `merge(map_a, map_b)` means `map_b` wins; `merge(map_b, map_a)` means `map_a` wins. In the tag pattern, `merge(local.common_tags, var.extra_tags)` means caller-provided tags win over defaults — the intended behaviour. Reversing it would mean common tags always override caller input.

---

## Key Takeaways

1. **`sensitive = true` redacts, it does not encrypt or protect.** State
   security comes from where you store state — not from the flag.

2. **`ephemeral = true` is genuinely never stored — but has real
   constraints.** Can't flow into regular resource arguments. Ephemeral
   outputs are child-module-only; root module errors at validate.

3. **When `nullable = false`, if null is passed the default is used.**
   When `nullable = true` (default), passing null overrides to null
   even if a default exists.

4. **`validation` blocks fire before any API call — and can only see
   `var.<this_variable>`.** No other variables, locals, or resources
   are in scope. The `condition` must be a boolean expression.

5. **Variable precedence: CLI flag wins, default loses.** Full order:
   CLI `-var` > `-var-file` > `*.auto.tfvars` > `terraform.tfvars` >
   `TF_VAR_` env > `default`.

6. **HCL has no `if` statement.** The conditional operator (`? :`) is
   the only conditional mechanism. `can()`, `contains()`, `alltrue()`,
   and logical operators are the tools for conditional logic.

7. **The distinction test: would you ever override this from outside?**
   Yes = variable. No = local. Locals have no `type` argument — type is
   inferred from the expression.

8. **`try()` handles errors; `coalesce()` handles null and empty
   string.** Combine them: `coalesce(try(var.config.name, null), local.default)`.

9. **`sensitive = true` on an output hides from terminal, not from
   `-json`.** All non-ephemeral outputs — sensitive or not — are
   accessible via `terraform_remote_state`.

10. **Output names are a public interface.** Any consumer breaks if you
    rename one. Add the new name first, migrate consumers, then remove
    the old name.

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform init` | Downloads provider plugins and initialises the backend |
| `terraform validate` | Checks configuration syntax and schema — no API calls |
| `terraform fmt -recursive` | Auto-formats all `.tf` files in the current directory and subdirectories |
| `terraform plan -var="<NAME>=<VALUE>"` | Overrides one variable for this plan (highest precedence) |
| `terraform plan -var-file="<FILE>.tfvars"` | Loads variable overrides from a file |
| `terraform apply` | Applies pending changes after confirmation |
| `terraform output` | Prints all output values in human-readable format |
| `terraform output <NAME>` | Prints a single output value |
| `terraform output -raw <NAME>` | Prints a single output with no surrounding quotes — use in shell scripts |
| `terraform output -json` | Prints all outputs as JSON, including sensitive values |
| `terraform output -json \| jq -r '.<NAME>.value'` | Extracts a specific output value using jq |
| `terraform output -no-color` | Strips ANSI colour codes — use in CI log systems |
| `export TF_VAR_<NAME>=<VALUE>` | Sets a variable via environment variable (level 5 precedence) |
| `unset TF_VAR_<NAME>` | Removes a TF_VAR_ environment variable override |
| `terraform destroy` | Destroys all resources managed by this configuration |

---

## Next Demo

**Demo 06 — Data Sources, Expressions, and Functions:** `data` sources
for reading existing AWS infrastructure without managing it, `for`
expressions in full (list and map transformation, filtering), `dynamic`
blocks for conditionally-generated nested blocks, string functions
(`format()`, `join()`, `split()`), advanced collection functions
(`flatten()`, `distinct()`, `concat()`), and template directives
(`%{if}` / `%{for}`).

---

## Appendix — Anki Cards

**05-variables-locals-outputs-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::05-variables-locals-outputs
#separator:Comma
#columns:Front,Back,Tags
"A variable is marked sensitive = true. Is its value encrypted or protected in terraform.tfstate?","No. sensitive = true ONLY redacts the value from terminal output (plan/apply logs, terraform output display). The value is written to terraform.tfstate in plaintext, exactly like any other value. State security requires storing state securely (encrypted S3 backend, IAM access control) — not the sensitive flag.","demo05,variables,sensitive,ta004"
"What is the difference between sensitive = true and ephemeral = true on a variable?","sensitive = true: value is redacted from terminal output but IS written to state and plan files. ephemeral = true: value exists only in memory during plan/apply — NEVER written to state, plan files, or logs. Ephemeral values can only flow into ephemeral outputs (child modules only) or write-only resource arguments.","demo05,variables,sensitive,ephemeral,ta004"
"What are the two valid ephemeral contexts for an ephemeral variable value?","(1) An ephemeral = true output block in a child module (NOT a root module — ephemeral outputs are invalid in root modules and error at validate). (2) A write_only resource argument (Terraform 1.10+, covered in Demo 08). Regular resource arguments are NOT ephemeral contexts.","demo05,variables,ephemeral"
"What does nullable = false on a variable do?","If null is passed as the variable value, the default is used instead. By default (nullable = true), explicitly passing null overrides the variable to null — even if a default exists. nullable = false prevents this: null input → default is used.","demo05,variables,nullable"
"A validation block's condition returns the string 'dev' instead of a boolean. What happens?","terraform validate errors: 'A condition expression must return either true or false.' The condition must be a boolean expression — use contains(), can(), regex(), or comparison operators. A string is not valid.","demo05,validation,ta004"
"Inside a validation block, what is the ONLY variable reference allowed in the condition?","Only var.<this_variable> — the variable being validated. You cannot reference other variables, locals, resources, or data sources. Attempting to do so errors with 'Invalid reference.'","demo05,validation"
"State the variable value precedence order from highest to lowest.","1. CLI -var flag, 2. CLI -var-file flag, 3. *.auto.tfvars files (alphabetical), 4. terraform.tfvars, 5. TF_VAR_ environment variables, 6. default value in the variable block, 7. interactive prompt (avoided in CI).","demo05,variables,precedence,ta004"
"What is the distinction test for variable vs. local?","If you would ever want to override this value from outside the configuration (different per environment, engineer, or run) — it is a variable. If it is always derived from other values in the configuration and never needs external input — it is a local. Locals earn their place through transformation, not pass-through.","demo05,locals,variables,distinction"
"What are three key differences between variables and locals?","(1) Variables can be set from outside (CLI, env, tfvars); locals cannot. (2) Variables have type/description/sensitive/nullable/validation arguments; locals have none of these. (3) Locals can reference resources and data sources; variables cannot (only var.<this_variable> in validation).","demo05,variables,locals,comparison"
"Do locals have a type argument? How is a local's type determined?","No type argument exists for locals. Terraform infers the type from the assigned expression. A locals block with all string values is inferred as map(string). Mixed value types produce object({...}). You cannot declare a type constraint on a local.","demo05,locals,types"
"What type does Terraform infer for a local defined as { Project = var.project, Environment = var.environment } when both variables are type = string?","map(string) — all values are strings. If any value were a different type (e.g. a number), Terraform would infer object({...}) instead.","demo05,locals,types"
"What is the difference between list(string), set(string), and map(string)?","list: ordered, allows duplicates, indexed by position [0]. set: unordered, no duplicates, no positional index — sets have no literal syntax, use toset([...]). map: key-value pairs, keys are strings, no guaranteed order. All three require all elements to be the same type.","demo05,variables,types,ta004"
"What does can(regex('pattern', var.x)) return when the pattern does not match?","false — regex() errors when there is no match, and can() converts any error into false. This is the idiomatic pattern for regex-based validation: can(regex(...)) returns true on match, false on no match.","demo05,validation,can,regex"
"What does alltrue([]) return?","true — alltrue() returns true if ALL elements are true. An empty list satisfies this vacuously (no false elements). This is why validation conditions using alltrue([for item in var.list : ...]) pass when the list is empty.","demo05,functions,alltrue"
"What does coalesce(null, '', 'first-real', 'second') return?","'first-real' — coalesce() skips both null AND empty string (''), returning the first value that is neither. Empty string is treated the same as null.","demo05,locals,coalesce,ta004"
"What is the difference between try() and coalesce()?","try(expr, fallback) catches ERRORS — returns the first argument that evaluates without error. coalesce(val1, val2) skips null and empty string — returns the first non-null, non-empty value. Use try() for optional object attributes or failing type conversions. Use coalesce() for 'use this value if set, otherwise fall back.'","demo05,locals,try,coalesce"
"You call merge(local.common_tags, var.extra_tags). Both have key 'Owner'. Which value appears?","var.extra_tags's value — merge() uses right-most-wins for key conflicts. merge(common, extra) means extra wins. merge(extra, common) would mean common wins.","demo05,locals,merge"
"Can locals reference other locals? Does the order they are written in matter?","Yes, locals can reference other locals. No, order does not matter — Terraform resolves the dependency order automatically from references within each expression, exactly as it does for resources.","demo05,locals,ordering"
"What happens if two locals reference each other circularly?","terraform plan errors: 'Cycle in local values: local.a -> local.b -> local.a'. Detected at plan time before evaluating any value. Fix: break the cycle by extracting the shared value into a third local that neither side references back.","demo05,locals,circular"
"What does data.aws_caller_identity return and what arguments does it require?","No arguments — body is empty ({}). Makes a single sts:GetCallerIdentity API call. Returns: account_id (AWS account ID), arn (ARN of the caller), user_id (unique caller ID).","demo05,data-sources,aws-caller-identity"
"What is the difference between aws_iam_role_policy (inline) and aws_iam_policy (managed)?","Inline: attached to exactly one role, destroyed with the role, cannot be reused. Managed: standalone resource attachable to multiple roles via aws_iam_role_policy_attachment. Use inline for role-specific permissions, managed for shared permissions.","demo05,iam,policy"
"terraform output role_unique_id shows (sensitive value). Does terraform output -json also redact it?","No — terraform output -json always shows the actual value even for sensitive outputs. -json is for programmatic consumption. Treat -json output with the same care as the state file.","demo05,outputs,sensitive,ta004"
"Can terraform_remote_state read sensitive = true outputs from the producer?","Yes — sensitive = true only redacts from terminal display. The value is in the state file in plaintext and any consumer with s3:GetObject access can read it via terraform_remote_state. All non-ephemeral outputs are accessible regardless of sensitivity.","demo05,remote-state,sensitive,ta004"
"Can terraform_remote_state read ephemeral = true outputs from the producer?","No — ephemeral outputs are never written to state. Since terraform_remote_state reads the state file, ephemeral outputs simply do not exist there.","demo05,remote-state,ephemeral,ta004"
"What IAM permissions does the consumer need for terraform_remote_state with S3 backend?","s3:GetObject on the state bucket and key path, using the consumer's own AWS credentials from the consumer's provider block. No special Terraform permissions — it is a standard S3 read.","demo05,remote-state,iam"
"A producer has never been applied. What happens when the consumer runs terraform plan with terraform_remote_state?","plan fails immediately: 'Error loading state error: NoSuchKey — the specified key does not exist.' Handle by applying the producer first, or wrapping the reference in try() with a fallback for bootstrap scenarios.","demo05,remote-state,error"
"You run terraform plan -var='environment=prod' with TF_VAR_environment=staging also set. Which value wins?","prod — CLI -var flag has higher precedence than TF_VAR_ environment variables. Full order: CLI -var > CLI -var-file > *.auto.tfvars > terraform.tfvars > TF_VAR_ > default.","demo05,variables,precedence,ta004"
"What does terraform output -raw do differently from terraform output <NAME>?","terraform output <NAME> prints the value with surrounding quotes and formatting. terraform output -raw <NAME> prints the raw value with no quotes or extra characters — suitable for capturing in a shell variable: ROLE_ARN=$(terraform output -raw role_arn).","demo05,outputs,commands"
"What does terraform output -no-color do and when is it needed?","Strips ANSI colour escape codes from output. Without it, CI log systems that do not interpret ANSI display literal escape sequences (e.g. ESC[32m) instead of colour formatting. Use in any CI environment where output is captured as plain text.","demo05,outputs,commands"
"Is ephemeral = true on an output valid in a root module?","No. Ephemeral outputs are only valid in child modules. terraform validate errors in a root module: 'Ephemeral output not allowed — Ephemeral outputs are not allowed in context of a root module.' Root modules have no caller to receive the ephemeral value.","demo05,outputs,ephemeral,ta004"
"What is the conditional operator syntax in Terraform, and why is it the only conditional mechanism?","Syntax: condition ? value_if_true : value_if_false. HCL has no if statement — the conditional expression IS the if/else mechanism. For conditional resource creation: count = var.create ? 1 : 0.","demo05,language,conditional"
"What does coalesce() return when called with coalesce('', 'fallback')?","'fallback' — coalesce() treats empty string the same as null, skipping both. Only non-null, non-empty string values satisfy coalesce.","demo05,functions,coalesce,ta004"
```

---

## Appendix — Quiz

**05-variables-locals-outputs-quiz.md:**

````markdown
# Quiz — Demo 05: Variables, Locals, and Outputs: Value Flow Through a Configuration

> One correct answer per question unless stated otherwise.
> Target: 80% or above before moving to Demo 06.
> TA-004 exam style.

---

**Q1.** A variable is marked `sensitive = true`. Which statement is
accurate?

A. The value is encrypted in `terraform.tfstate`
B. The value is redacted from plan/apply terminal output but is still
   written to `terraform.tfstate` in plaintext
C. The value is never written to state or any file
D. The value cannot be used in regular resource arguments

<details>
<summary>Answer</summary>

**B.** `sensitive = true` only redacts from terminal output. State
storage is plaintext regardless. For never-written-to-state behaviour,
use `ephemeral = true`. State security requires a secure backend
(encrypted S3, IAM access control), not the `sensitive` flag.

</details>

---

**Q2.** What is the variable value precedence order? Rank from highest
to lowest: `TF_VAR_` environment variable, CLI `-var` flag, `default`
value, `terraform.tfvars` file.

A. `-var` > `TF_VAR_` > `terraform.tfvars` > `default`
B. `terraform.tfvars` > `-var` > `TF_VAR_` > `default`
C. `TF_VAR_` > `terraform.tfvars` > `-var` > `default`
D. `default` > `terraform.tfvars` > `TF_VAR_` > `-var`

<details>
<summary>Answer</summary>

**A.** CLI `-var` flag is highest. `TF_VAR_` environment variables
override `terraform.tfvars`. `default` is the lowest fallback. Full
order: CLI `-var` > `-var-file` > `*.auto.tfvars` > `terraform.tfvars`
> `TF_VAR_` > `default`.

</details>

---

**Q3.** A `validation` block has `condition = "prod"` (a string literal).
What happens?

A. Passes — non-empty strings are truthy in Terraform
B. Errors at `terraform validate` — condition must return a boolean
C. The validation is silently ignored
D. Errors only at `apply` time, not `validate`

<details>
<summary>Answer</summary>

**B.** A `validation` block's `condition` must evaluate to `true` or
`false`. `terraform validate` errors immediately: "A condition expression
must return either true or false."

</details>

---

**Q4.** What does `coalesce(var.custom_name, local.computed_name)`
return when `var.custom_name` is set to `""`?

A. `""` — coalesce returns the first non-null value, and `""` is not null
B. `local.computed_name` — coalesce skips both null AND empty string
C. An error — coalesce requires at least one non-null argument
D. `null`

<details>
<summary>Answer</summary>

**B.** `coalesce()` skips both `null` AND `""` — empty string is treated
the same as null. Only a non-null, non-empty string satisfies coalesce.

</details>

---

**Q5.** You call `merge(local.common_tags, var.extra_tags)`. Both have
key `"Owner"`. Which value appears in the result?

A. `local.common_tags`'s value — the left-most map wins
B. `var.extra_tags`'s value — the right-most map wins
C. Both values are combined into a list
D. An error — duplicate keys are not allowed in merge()

<details>
<summary>Answer</summary>

**B.** `merge()` uses right-most-wins for key conflicts. `var.extra_tags`
is rightmost, so its `"Owner"` value overrides `local.common_tags`'s.

</details>

---

**Q6.** A teammate runs `terraform output -json` and sees the actual
value of an output marked `sensitive = true`. Is this expected?

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
reads the state file, ephemeral outputs simply are not there.

</details>

---

**Q8.** You add `ephemeral = true` to an output block in your root module
and run `terraform validate`. What happens?

A. Validates successfully — ephemeral outputs are supported everywhere
B. Validates successfully but warns that ephemeral outputs are experimental
C. Errors: "Ephemeral output not allowed — Ephemeral outputs are not
   allowed in context of a root module"
D. Errors only at apply time, not validate time

<details>
<summary>Answer</summary>

**C.** `ephemeral = true` on outputs is only valid in child modules.
Root modules have no caller to receive the ephemeral value. `terraform
validate` catches this immediately.

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