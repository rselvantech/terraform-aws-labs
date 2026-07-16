# Demo 05 — Variables in Depth: Declaring and Constraining External Input

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
parameterise it: values that change per environment enter as variables.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Declaring & Building the Role                                 │
│  Full variable argument set: type, validation, sensitive, ephemeral,    │
│  nullable   |   locals compose a trust policy   |   aws_iam_role +      │
│  aws_iam_role_policy applied against real AWS                           │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Precedence in Practice                                        │
│  All six precedence levels exercised in order: CLI -var > *.auto.tfvars │
│  > terraform.tfvars > TF_VAR_ env > default                             │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Validation, Sensitive & Ephemeral Behavior                    │
│  Trigger all three validation blocks   |   confirm sensitive value in   │
│  state (plaintext)   |   confirm ephemeral value absent from state      │
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
  `alltrue()`, `toset()`, `tostring()`, and other type conversion functions
- `aws_iam_role`, `aws_iam_role_policy`, `data.aws_caller_identity` (preview)

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
| `jq` | Any recent | `apt install jq` / `brew install jq` | `jq --version` |
| Git | Any recent | Pre-installed on most systems | `git --version` |

> **Carried over from Demo 04:** `jq` — used in Part C to confirm a
> `sensitive` value's plaintext presence in state, and a `session_token`
> value's absence from state. Not new to this demo, but required to
> complete the lab.

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

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| `aws_iam_role` | Always free — IAM has no cost | **$0.00** | |
| `aws_iam_role_policy` | Always free | **$0.00** | |
| `data.aws_caller_identity` | Always free | **$0.00** | STS read call |
| **Session total** | | **$0.00** | |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
05-variables-in-depth/
├── README.md
├── 05-variables-in-depth-anki.csv
├── 05-variables-in-depth-quiz.md
└── src/
    ├── 01-versions.tf      # terraform block + provider version constraints
    ├── 02-provider.tf      # AWS provider: region, profile, default_tags
    ├── 03-variables.tf     # all input variables — this demo's focus
    ├── 04-locals.tf        # minimal locals to build the role — full Locals depth is Demo 06
    ├── 05-main.tf           # aws_iam_role + aws_iam_role_policy
    ├── 06-outputs.tf       # a couple of quick outputs — full Outputs depth is Demo 07
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
| `for` expression (preview) | Language construct | Transform lists/maps — preview here, full coverage in Demo 09 |
| `can()` | Built-in function | Returns true if an expression evaluates without error |
| `regex()` | Built-in function | Tests a string against a pattern; errors if no match |
| `contains()` | Built-in function | Tests whether a list contains a specific value |
| `length()` | Built-in function | Returns the number of elements in a list, set, map, or string |
| `alltrue()` | Built-in function | Returns true if all elements of a list are true |
| `toset()` `tolist()` `tostring()` `tonumber()` | Built-in functions | Type conversion functions |

**Related constructs worth knowing (not taught in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| `locals` block | Internally computed values | Demo 06 — this demo uses a few, undecorated, just to build the role |
| `output` block | Exposing values | Demo 07 — this demo has a couple of quick outputs, minimally explained |
| `for` expression (full) | Collection transformation | Demo 09 |
| `data.aws_caller_identity` (full depth) | Reading the current AWS identity | Demo 08 — used here already as a light preview |
| `try()`, `coalesce()`, `merge()` | Value-fallback and composition functions | Demo 06 |

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

# For conditional resource creation (Demo 10):
count = var.create_role ? 1 : 0
```

> **No `if` statements exist in HCL.** If you find yourself wanting
> `if var.env == "prod" { ... }`, the Terraform equivalent is always
> a conditional expression. For conditional resource creation, use
> `count = var.create ? 1 : 0` (covered in Demo 10).

**What `count = var.create_role ? 1 : 0` actually does:** `count` on a
resource block tells Terraform how many instances to create. Instead of
a fixed number, this feeds it the *result* of a conditional expression
— `1` if `var.create_role` is `true`, `0` if it's `false`. A resource
with `count = 0` is not created at all (Terraform sees zero instances
to manage); `count = 1` creates exactly one, addressed as
`resource_type.name[0]`. This is how Terraform expresses "create this
resource, but only if X is true" — there's no other mechanism for
conditional resource creation. The full mechanics of `count` (indexing,
addressing, the reordering trap) are Demo 10's focus; this is only the
`?:` piece that makes the condition itself possible.

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
```

When a resource argument receives `null`, Terraform omits it from the
API call — the AWS service's own default applies.

---

#### `for` Expression — Preview

A `for` expression transforms a list or map into a new list or map.
Used in this demo's `trusted_principals` local — full coverage is in
Demo 09.

```hcl
# Basic form: [for item in list : transformation]
[for id in var.trusted_account_ids : "arn:aws:iam::${id}:root"]
# Input:  ["123456789012", "987654321098"]
# Output: ["arn:aws:iam::123456789012:root", "arn:aws:iam::987654321098:root"]
```

Full `for` expression coverage — map transformation, filtering with
`if`, `for` in map context — is in Demo 09.

---

### Built-in Functions Used in This Demo

Terraform has ~120 built-in functions across 9 categories. This section
introduces those used in Demo 05. Functions first used in later demos
are introduced there.

**Function category overview — coverage plan:**

| Category | Demo 05 | Demo 06 | Demo 09 |
|---|---|---|---|
| Logic | `can()`, `alltrue()` | `try()`, `coalesce()` | — |
| Collection | `contains()`, `length()`, `toset()`, `tolist()` | `merge()` | `flatten()`, `distinct()`, `concat()`, `keys()`, `values()`, `lookup()` |
| Encoding | — | `jsonencode()` | `jsondecode()`, `base64encode()` |
| Type conversion | `tostring()`, `tonumber()`, `tobool()` | — | — |
| String | — | — | `format()`, `join()`, `split()`, `replace()`, `upper()`, `lower()` |

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
> while preserving order, use `distinct(list)` (covered in Demo 09).

**What happens when a type conversion fails:**

```hcl
tonumber("abc")   # ERROR — "abc" cannot be converted to a number
tobool("yes")     # ERROR — only exact "true"/"false" convert; "yes" does not
tonumber("42")    # 42 — succeeds, "42" is a valid numeric string
```

```
Error: Invalid function argument
  Invalid value for "v" parameter: cannot convert "abc" to number:
  a number is required.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

Type conversion functions **error immediately**, the same way `regex()`
does on no match — they never silently return `0`, `false`, or `null`
on a failed conversion. If you need to attempt a conversion that might
fail and fall back to a default instead of erroring, wrap it in
`try()`: `try(tonumber(var.port_string), 8080)` — covered in full in
Demo 06, since `try()` is a Demo 06 construct, not a Demo 05 one.

---

### Variable Types — Full Reference

#### Primitive Types

| Type | Example value | Notes |
|---|---|---|
| `string` | `"us-east-2"` | Always double-quoted. Supports interpolation. |
| `number` | `8` or `3.14` | Integer or float — all numbers are 64-bit floats internally |
| `bool` | `true` / `false` | Lowercase only — `True` and `TRUE` are invalid |

#### Collection Types

All three require all elements to be the same type (homogeneous). For
mixed types, use `object` or `tuple`.

| Type | Syntax | Example default | Ordered? | Duplicates allowed? |
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

**Tuple vs. list vs. set — and why tuple needs no conversion function:**

Unlike `set` (which has no literal syntax at all — you must write a
list and convert with `toset()`), a **tuple has ordinary list literal
syntax**. Write a list literal with mixed types, and Terraform infers
it as a tuple automatically — there's no `totuple()` function because
none is needed:

```hcl
["us-east-2", 3, true]
# Terraform infers this as tuple([string, number, bool]) automatically
# — mixed types in a single [...] literal always produce a tuple,
# never a list, because list requires homogeneous elements.

["us-east-2", "us-west-2"]
# All elements the same type (string) — Terraform infers list(string)
# here instead, since nothing forces tuple inference when types match.
```

| | `list(type)` | `set(type)` | `tuple([...])` |
|---|---|---|---|
| Element types | All the same | All the same | Can differ per position |
| Literal syntax | `["a", "b"]` | None — must `toset([...])` | `["a", 1, true]` — ordinary list literal, inferred automatically |
| Access by index | Yes | No | Yes |
| Duplicates allowed | Yes | No | Yes |
| Typical use | Ordered, uniform values | Deduplicated, unordered values | A small, fixed-shape group of mixed-type values (rare — `object` is usually clearer) |

> **In practice, you rarely write `tuple([...])` as an explicit type
> constraint.** Terraform infers it automatically the moment a list
> literal has mixed element types — the explicit `tuple([string,
> number, bool])` syntax mainly shows up when you need to *constrain*
> a variable's input to a specific tuple shape, not when just writing
> an inline value.

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

#### Variables — Complete Argument Syntax

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

When `sensitive = true`: plan/apply output shows `(sensitive value)`
instead of the actual value; `terraform output` shows `(sensitive
value)`; `terraform output -json` shows the actual value in plaintext;
the value IS still written to `terraform.tfstate` in plaintext.

When `sensitive = false` (the default): the value appears in plan/apply
output, terminal display, and `terraform output` exactly as provided —
no redaction anywhere.

```hcl
variable "deploy_token" {
  type      = string
  sensitive = true
}
```

> **The most common misconception:** `sensitive = true` is NOT encryption
> — it is redaction from terminal output only. The value still exists in
> state in plaintext. State security requires a secure backend
> (encrypted S3, IAM access control), independent of the `sensitive`
> flag.

---

#### `ephemeral = true` — Never Written to State (Terraform 1.10+)

`ephemeral = true` marks a variable's value as something Terraform
should never write down anywhere — not in `terraform.tfstate`, not in
a saved plan file, not anywhere persistent. It only ever exists in
memory, for the duration of the current `plan`/`apply`, then it's gone.

```hcl
variable "deploy_token" {
  type      = string
  ephemeral = true
}
```

When `ephemeral = true`: the value exists only in memory during
plan/apply; it is never written to `terraform.tfstate`; it is never
written to saved plan files (`-out`); it **cannot** be used in a
regular resource argument (the error this produces is shown below).

When `ephemeral = false` (the default): the value flows normally into
resource arguments and is stored in state like any other value.

**Can you output an ephemeral variable?** Yes — but only through an
`ephemeral = true` output, and only in a **child module**, not a root
module (every demo in this series so far has been a root module). This
is one of exactly two valid destinations for an ephemeral value — the
other is a `write_only` resource argument (Terraform 1.10+, covered in
a later demo). A regular resource argument is neither. This series
doesn't build child modules until later, so the output side isn't
demonstrated working here — Demo 07 covers the restriction directly,
including what error you get if you try it in a root module. For now,
the practical takeaway is narrower: **in this demo, an ephemeral
variable has nowhere valid to go except staying unused, or being
consumed by something that doesn't persist it** — which is why
`session_token` in this demo's lab is declared but deliberately never
referenced in a resource argument.

**Concrete example of the error** — this is what happens if you try to
use `var.deploy_token` (ephemeral) directly on a resource:

```hcl
variable "deploy_token" {
  type      = string
  ephemeral = true
}

resource "aws_ssm_parameter" "example" {
  name  = "/example/token"
  type  = "SecureString"
  value = var.deploy_token   # ERROR — see below
}
```

```
Error: Ephemeral value not allowed
  on 05-main.tf line 12, in resource "aws_ssm_parameter" "example":
  12:   value = var.deploy_token
  This argument does not allow ephemeral values, and the given value
  is derived from an ephemeral value.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

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

When `nullable = true` (the default): a caller can explicitly pass
`null` and `null` is used as the value — even if a `default` exists.
This is useful when `null` has a deliberate meaning ("use the
resource's own default for this argument" — passing `null` to a
resource argument causes Terraform to omit it from the API call).

When `nullable = false`: if `null` is passed, the `default` is used
instead.

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

**Can a `condition` reference another variable, or a `local`?** No to
both. The *only* reference a `condition` may contain is
`var.<this_variable>` — not any other variable, and not any `local`,
even one that doesn't itself depend on a resource. This surprises
people, since locals often feel like "just another value" — but
locals are computed later in the evaluation order than variable
validation (see the scopes list below), so they can't be referenced
here regardless of what they depend on.

**Can a `condition` reference a `resource` or `data` attribute?** No.
Resources may not exist yet on a first `apply`, and `data` blocks
require the provider to already be configured and an API call made —
neither of those has happened yet at the point variable validation
runs. Referencing either is out of scope for the same underlying
reason as locals: validation happens too early in the evaluation order.

**What happens when `condition` evaluates to `false`?** Terraform halts
`plan` (or `apply`) immediately and displays `error_message` as a hard
error — not a warning. No API call is made, no resource is touched.
The `plan`/`apply` simply fails, and must be re-run with a valid value
before anything proceeds.

**What validation can and cannot check — worked examples:**

```hcl
# VALID — tests this variable's own value
condition = can(regex("^[a-z][a-z0-9-]+$", var.project))

# VALID — arithmetic on this variable
condition = var.max_session_duration >= 3600 && var.max_session_duration <= 43200

# INVALID — references another variable (not in scope)
condition = var.max_size > var.min_size        # ERROR: var.min_size not in scope

# INVALID — references a local (not in scope, even though it looks harmless)
condition = var.name == local.expected_name    # ERROR: local.expected_name not in scope

# INVALID — references a resource (not in scope)
condition = var.name != aws_s3_bucket.main.bucket  # ERROR: resources not in scope
```

---

**Terraform's evaluation order — "scopes," and where each is covered:**

The reason validation's `condition` can only see `var.<this_variable>`
makes more sense once you see the order Terraform actually resolves
things in. Roughly, top to bottom:

1. **Variable resolution + validation** (this demo) — every `variable`
   block's value is determined (precedence order) and every
   `validation` block runs, using only that one variable's own value
2. **Provider configuration** — the `provider` block is configured,
   using resolved variables
3. **Locals** (Demo 06) — computed in dependency order, can reference
   variables and (once computed) other locals
4. **Data source reads** (Demo 08) — require the provider to be
   configured; can reference variables and locals
5. **Resource graph — plan, then apply** (ongoing since Demo 01; `count`/
   `for_each` multiplicity in Demo 10) — resources are created/updated/
   destroyed in dependency order, can reference variables, locals, and
   data sources
6. **Outputs** (Demo 07) — resolved last, can reference anything above

A `validation` block's `condition` runs at step 1 — before steps 2–6
exist in any form. That's the literal reason it can't see a resource
(step 5, doesn't exist yet) or a local (step 3, hasn't run yet) — not
a convention or a stylistic restriction, but a consequence of what
information actually exists at that point in the evaluation order.

**Concrete example — why `var.min_size`/`var.max_size` genuinely isn't
available yet:** imagine Terraform tried to allow
`condition = var.max_size > var.min_size` inside `min_size`'s own
validation block. For this to work, Terraform would need `max_size`
already resolved before it can validate `min_size` — but `max_size`'s
own validation (if it had one referencing `min_size`) would have the
identical problem in reverse. There's no guaranteed order to resolve
this in, unlike locals or resources, which form an explicit dependency
graph (DAG) precisely so Terraform *can* determine an order. Variables
don't form a DAG with each other at all — each one's validation is
self-contained by design, which sidesteps the ordering problem entirely
rather than trying to solve it.

> **Validation fires before any API call** — invalid inputs are rejected
> during variable resolution, before Terraform contacts AWS. This is why
> the `condition` can only see `var.<this_variable>`: resources and other
> variables may not exist yet at the point validation runs, so referencing
> them is out of scope by design, not merely by convention.

---

#### Variable Value Precedence

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

# Level 2 — CLI var-file
terraform apply -var-file="prod.tfvars"

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

#### `data.aws_caller_identity` — Current Account Identity (Preview)

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

This is a light preview — full coverage of `data` blocks (what they are,
how they differ from `resource`, other data sources) is Demo 08. Here
it's used only for its `account_id`, inside the `trusted_principals`
local, to build a self-trust fallback when no external accounts are
listed.

---

#### `aws_iam_role` and `aws_iam_role_policy`

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

**Closing the loop — how this role and policy actually get used:**

Everything above defines the role and its permissions, but not *who
uses it or when*. Here's the complete real-world sequence for
CloudNova's CI/CD deploy role:

1. **Trust policy decides *who can ask to become this role*.** The
   `assume_role_policy` (built from `local.trust_policy` in this
   demo's lab) lists the trusted principals — in this demo, the
   current AWS account itself (self-trust, since no external accounts
   were provided). In a real CI/CD setup, this is typically the CI/CD
   platform's own AWS account or an OIDC identity provider (e.g.
   GitHub Actions' OIDC provider), not a human user.

2. **A CI/CD pipeline run calls `sts:AssumeRole`** against this role's
   ARN (`role_arn`, this demo's output). AWS checks the trust policy —
   is the calling identity one of the trusted principals? If yes, AWS
   issues **temporary credentials** (access key, secret key, session
   token) valid for up to `max_session_duration` seconds (this demo's
   `3600`–`43200` range).

3. **The pipeline uses those temporary credentials** — not the role
   itself directly, and not any human's long-term credentials — to run
   `terraform apply` (or any AWS CLI/SDK call). Every API call made
   with those credentials is authorized against the role's **inline
   permission policy** (`aws_iam_role_policy.deploy`, built from
   `local.permission_policy`) — in this demo, `s3:GetObject`,
   `s3:PutObject`, `s3:ListBucket` (`var.allowed_actions`).

4. **When the session expires** (at `max_session_duration`), the
   temporary credentials stop working — the pipeline must call
   `sts:AssumeRole` again for the next run. Nothing about the role
   itself needs to change; this is exactly why roles use temporary
   credentials instead of an IAM user's permanent access keys — there's
   no long-lived secret sitting in the pipeline's configuration to leak
   or rotate.

**Why two separate resources (role + inline policy) instead of one?**
The trust policy (who can assume) and the permission policy (what they
can do once assumed) are answering two entirely different questions.
Keeping them as two Terraform resources mirrors how AWS itself treats
them — `assume_role_policy` lives directly on the role; permissions
are attached separately (inline here; via `aws_iam_policy` +
`aws_iam_role_policy_attachment` if you needed the same permission set
reused across multiple roles).

---

## Lab Step-by-Step Guide

---

## Part A — Declaring & Building the Role

**What you accomplish in Part A:** write the complete variable set with
its full argument surface (type constraints, validation, `sensitive`,
`ephemeral`, `nullable`), a minimal `locals` block to compose the trust
policy, and the two real AWS resources those variables ultimately
parameterise. At the end of Part A, the role exists in AWS.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/05-variables-in-depth/src
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

  default_tags {
    tags = local.common_tags
  }
}
```

---

#### `03-variables.tf` — Every variable argument this demo teaches

**What this file does in this demo:** declares every input this
configuration accepts — provider settings, project identity (with
`validation` blocks), role configuration, the `sensitive` and
`ephemeral` demonstration variables, and the `max_session_duration`
numeric validation. Read each variable's arguments as you go — they're
intentionally varied to exercise different combinations.

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
  default     = "05-variables-in-depth"
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
# var.session_token is demonstrated in Part C but NOT referenced in any
# resource argument — it can only flow to an ephemeral output (child module
# only, Demo 07) or a write-only resource argument (a later demo).
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

#### `04-locals.tf` — Minimal computed values for the role

**What this file does in this demo:** builds the role name, the trust
policy, the permission policy, and the common tags — all derived from
the variables in `03-variables.tf`, none of it independently
configurable. The deep explanation of *why* these are locals and not
variables, and the functions used to compose them well, is Demo 06's
focus — this file uses only what's needed to build the role.

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

#### `05-main.tf` — The IAM role and its inline policy

**What this file does in this demo:** declares `aws_iam_role.deploy`
and `aws_iam_role_policy.deploy` — the two real AWS resources this
entire demo has been parameterising. `assume_role_policy` and `tags`
consume the `local.trust_policy` and `local.common_tags` values from
`04-locals.tf`; `max_session_duration` and `description` are populated
directly from variables — this one file shows the complete path from
raw input (variables) through computed values (locals) to a real AWS
resource.

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

#### `06-outputs.tf` — Quick confirmation outputs

**What this file does in this demo:** exposes the role's name and ARN
so Step 3's `apply` has something to display — full output argument
depth (sensitivity, `depends_on`) is Demo 07.

**06-outputs.tf:**

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

### Step 3 — Initialise and apply

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

Outputs:

role_arn  = "arn:aws:iam::163125980376:role/cloudnova-dev-deploy-role"
role_name = "cloudnova-dev-deploy-role"
```

> ✅ Verified against a live run. `terraform fmt -recursive` reported
> `break-fix/broken.tf` as reformatted (expected — that file is
> intentionally malformed for Break-Fix below). Account ID shown here
> is a placeholder — yours will differ, and `role_arn`/`role_name`
> will match if defaults are unchanged.

**Verify in Console:**

```
Console → IAM → Roles → cloudnova-dev-deploy-role

Trust relationships tab:
  → Trusted entities: arn:aws:iam::<your-account-id>:root ✅

Permissions tab:
  → cloudnova-dev-deploy-policy (inline) ✅
  → JSON: AllowedActions: s3:GetObject, s3:PutObject, s3:ListBucket ✅
```

---

## Part B — Precedence in Practice

**What you accomplish in Part B:** exercise all six variable value
precedence levels against the live `environment` variable, confirming
each override behaves exactly as the precedence order predicts before
returning the configuration to its default state.

### Step 1 — Level 6: default (baseline)

```bash
terraform plan | grep "cloudnova"
```

Expected: `cloudnova-dev-deploy-role` — from `default = "dev"`.

✅ Verified against a live run:
```
aws_iam_role.deploy: Refreshing state... [id=cloudnova-dev-deploy-role]
aws_iam_role_policy.deploy: Refreshing state... [id=cloudnova-dev-deploy-role:cloudnova-dev-deploy-policy]

No changes. Your infrastructure matches the configuration.
```

### Step 2 — Level 5: `TF_VAR_` environment variable

```bash
export TF_VAR_environment=staging
terraform plan | grep "cloudnova"
```

Expected: `cloudnova-staging-deploy-role` — env var overrides default.

✅ Verified against a live run — the plan proposes replacing the role,
since changing `environment` changes the computed `name` (a
`name`-changing update forces replacement, not an in-place update):
```
  # aws_iam_role.deploy must be replaced
-/+ resource "aws_iam_role" "deploy" {
      ~ name = "cloudnova-dev-deploy-role" -> "cloudnova-staging-deploy-role" # forces replacement
      ~ description = "CI/CD deploy role for cloudnova dev" -> "CI/CD deploy role for cloudnova staging"
        # ...
    }
Plan: 2 to add, 0 to change, 2 to destroy.
```

> **`# forces replacement` is worth noticing here.** Changing the
> `name` argument (derived from `environment`) can't be applied
> in-place — AWS doesn't support renaming an IAM role via update, so
> Terraform plans a destroy-then-create instead. This is a real,
> general Terraform behavior (some argument changes update in place,
> others force replacement), not something specific to precedence
> testing — it just happens to be visible here because `environment`
> feeds directly into `name`.

### Step 3 — Level 4: `terraform.tfvars` overrides `TF_VAR_`

```bash
echo 'environment = "prod"' > terraform.tfvars
terraform plan | grep "cloudnova"
```

Expected: `cloudnova-prod-deploy-role` — `terraform.tfvars` overrides
the `TF_VAR_environment=staging` env var.

✅ Verified against a live run:
```
      ~ name = "cloudnova-dev-deploy-role" -> "cloudnova-prod-deploy-role" # forces replacement
      ~ description = "CI/CD deploy role for cloudnova dev" -> "CI/CD deploy role for cloudnova prod"
  ~ role_arn  = "arn:aws:iam::<account-id>:role/cloudnova-dev-deploy-role" -> (known after apply)
  ~ role_name = "cloudnova-dev-deploy-role" -> "cloudnova-prod-deploy-role"
```

### Step 4 — Level 3: `*.auto.tfvars` overrides `terraform.tfvars`

```bash
echo 'environment = "staging"' > override.auto.tfvars
terraform plan | grep "cloudnova"
```

Expected: `cloudnova-staging-deploy-role` — `.auto.tfvars` overrides
`terraform.tfvars`.

> **A wrong value here fails loudly, not silently.** If you type an
> `environment` value outside `dev`/`staging`/`prod` into any of these
> files, the `validation` block from `03-variables.tf` catches it
> immediately: `terraform plan` fails with `Error: Invalid value for
> variable` and the exact `error_message` you wrote — the same
> validation Part C exercises deliberately, encountered here as a
> genuine typo would trigger it.

### Step 5 — Level 2: CLI `-var-file` overrides `*.auto.tfvars`

This level is easy to overlook since `*.auto.tfvars` loads
automatically and `-var-file` requires an explicit flag — but
`-var-file` outranks it precisely because it's an explicit, deliberate
CLI choice rather than something loaded by convention.

```bash
echo 'environment = "prod"' > env.tfvars
terraform plan -var-file="env.tfvars" | grep "cloudnova"
```

Expected: `cloudnova-prod-deploy-role` — the explicit `-var-file` flag
overrides `override.auto.tfvars`'s `"staging"`, even though both files
are present simultaneously.

### Step 6 — Level 1: CLI `-var` flag overrides everything

```bash
terraform plan -var="environment=dev" | grep "cloudnova"
```

Expected: `cloudnova-dev-deploy-role` — CLI flag wins over all files
and env vars.

✅ Verified against a live run — the full precedence chain in this
walkthrough was demonstrated end-to-end: default (`dev`) → `TF_VAR_`
(`staging`) → `terraform.tfvars` (`prod`) → `.auto.tfvars` (`staging`)
→ `-var-file` (`prod`) → `-var` (`dev`) — each override winning over
everything beneath it, exactly matching the documented order.

### Step 7 — Clean up precedence artifacts

```bash
unset TF_VAR_environment
rm -f terraform.tfvars override.auto.tfvars env.tfvars
```

---

## Part C — Validation, Sensitive & Ephemeral Behavior

**What you accomplish in Part C:** deliberately trigger all three
`validation` blocks to confirm they fire before any AWS API call, then
confirm the practical difference between `sensitive` (redacted from
output, still in state) and `ephemeral` (never in state at all).

### Step 1 — Trigger the `environment` validation

```bash
terraform plan -var="environment=qa"
```

✅ Verified against a live run:

```
Planning failed. Terraform encountered an error while generating this plan.

╷
│ Error: Invalid value for variable
│
│   on 03-variables.tf line 28:
│   28: variable "environment" {
│     ├────────────────
│     │ var.environment is "qa"
│
│ environment must be dev, staging, or prod.
│
│ This was checked by the validation rule at 03-variables.tf:34,3-13.
╵
```

### Step 2 — Trigger the `max_session_duration` validation

```bash
terraform plan -var="max_session_duration=999"
```

✅ Verified against a live run:

```
Planning failed. Terraform encountered an error while generating this plan.

╷
│ Error: Invalid value for variable
│
│   on 03-variables.tf line 105:
│  105: variable "max_session_duration" {
│     ├────────────────
│     │ var.max_session_duration is 999
│
│ max_session_duration must be between 3600 (1 hour) and 43200 (12 hours).
│
│ This was checked by the validation rule at 03-variables.tf:110,3-13.
╵
```

### Step 3 — Trigger the `trusted_account_ids` validation

```bash
terraform plan -var='trusted_account_ids=["not-an-id"]'
```

✅ Verified against a live run:

```
Planning failed. Terraform encountered an error while generating this plan.

╷
│ Error: Invalid value for variable
│
│   on 03-variables.tf line 59:
│   59: variable "trusted_account_ids" {
│     ├────────────────
│     │ var.trusted_account_ids is list of string with 1 element
│
│ All trusted_account_ids must be 12-digit AWS account IDs.
│
│ This was checked by the validation rule at 03-variables.tf:64,3-13.
╵
```

> **Notice each error names the exact line and the actual value that
> failed** (`var.environment is "qa"`, `var.max_session_duration is
> 999`) — this is genuine `terraform plan` output, not a generic
> message; Terraform always tells you specifically what it evaluated.

> **All three errors appear before Terraform contacts AWS** — validation
> fires during variable resolution.

---

### Step 4 — Observe `sensitive` variable behaviour

```bash
terraform plan -var="external_secret_label=my-real-secret"
```

✅ Verified against a live run:

```
No changes. Your infrastructure matches the configuration.
```

> **"No changes" is correct here, not a bug.** `external_secret_label`
> is declared purely to demonstrate `sensitive` behavior — it isn't
> actually wired into any resource argument in this demo's `.tf` files,
> so changing its value has nothing downstream to affect. The
> `sensitive` redaction behavior itself is confirmed by inspecting
> state directly, not by watching a plan diff.

Confirm the role's tags (a genuinely-used value) ARE in state in
plaintext, as a general confirmation state stores actual values:

```bash
terraform state pull | jq '.resources[] | select(.type=="aws_iam_role") | .instances[0].attributes.tags'
```

✅ Verified against a live run:

```json
{
  "Demo": "05-variables-in-depth",
  "Environment": "dev",
  "ManagedBy": "Terraform",
  "Owner": "platform-team",
  "Project": "cloudnova"
}
```

---

### Step 5 — Observe `ephemeral` variable behaviour

```bash
terraform apply -var="session_token=my-real-token"
```

✅ Verified against a live run:

```
No changes. Your infrastructure matches the configuration.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

> **`0 added, 0 changed` is expected here too** — `session_token`, like
> `external_secret_label`, is declared to demonstrate `ephemeral`
> behavior but isn't referenced in any resource argument (it can't be —
> that's exactly what `ephemeral` restricts). Nothing about applying it
> should change any real resource.

Confirm `session_token` is NOT in state:

```bash
terraform state pull | jq '.' | grep -i "session"
```

✅ Verified against a live run:

```
            "max_session_duration": 3600,
      "config_addr": "var.max_session_duration",
          "object_addr": "var.max_session_duration",
```

> **This is NOT a failed check — read the matches carefully.** Every
> line matched is `max_session_duration` (a real, stored variable) —
> the substring `"session"` inside it is what `grep -i session` picked
> up. `session_token` itself appears **nowhere** in this output. If
> `session_token` had been written to state, you'd see a line
> containing that exact name — its total absence, even as a substring
> match, is the actual confirmation that `ephemeral = true` worked.

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

> ✅ Verified against a live run.

```
Console → IAM → Roles → cloudnova-dev-deploy-role: GONE ✅
```

```bash
unset TF_VAR_environment
rm -f terraform.tfvars override.auto.tfvars env.tfvars
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
4. ✅ `can(regex(...))` is the idiomatic validation pattern (`regex()`
   errors on no match, `can()` converts that to `false`); `contains()`,
   `length()`, and `alltrue()` (vacuously `true` on an empty list) round
   out the function set — and `toset()`/`tolist()`/`tostring()`/`tonumber()`
   convert between collection types (`list`/`set`/`map` require
   homogeneous elements, `object` allows mixed types)

---

## Cert Tips — TA-004 Objectives Covered

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| Variable value precedence | TA-004 Obj 2 (Terraform basics / core concepts) | Frequently tested — know the full order, CLI flag highest to default lowest |
| `sensitive = true` on a variable | TA-004 Obj 4 (Terraform outside core workflow) | Common wrong-answer trap: "sensitive variables are encrypted" |
| `validation` block `condition` | TA-004 Obj 2 | Must be a boolean expression — a string/number condition is itself invalid |
| `alltrue()` on an empty list | TA-004 Obj 4 | Returns `true` — vacuous truth is a common trap |
| `ephemeral = true` constraints | TA-004 Obj 4 | Cannot be used in a regular resource argument — child-module output or write-only argument only |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam states a variable is `sensitive = true` and asks whether its value is protected in state | Recognizing `sensitive` only redacts terminal/log output — the value is still in `terraform.tfstate` in plaintext | Assuming `sensitive = true` means the value is encrypted or otherwise secured at rest |
| Exam gives a `validation` block with `condition = "prod"` (a string literal) | Recognizing this fails `terraform validate` — the condition must evaluate to a boolean | Assuming a non-empty string is "truthy" the way some other languages treat it |
| Exam asks what `alltrue([])` returns | Answering `true` — an empty list vacuously satisfies "all elements are true" | Assuming an empty list returns `false` or errors |
| Exam shows an ephemeral variable referenced directly in a `resource` argument | Recognizing this is invalid — ephemeral values are restricted to child-module outputs or write-only resource arguments | Assuming any variable can flow into any resource argument regardless of `ephemeral` status |

### Exam Task — Write a complete configuration

**Task:** CloudNova needs a variable set for a new S3 artifact bucket:
a `bucket_suffix` variable (3–20 lowercase alphanumeric/hyphen
characters, validated), an `upload_token` variable (a placeholder
access token, marked `sensitive = true`), and an `environment` variable
(`nullable = false`, defaulting to `"dev"`, restricted to
`dev`/`staging`/`prod` via `validation`). Write all three from scratch.

**Block types required:** `variable` (×3, exercising `validation`,
`sensitive`, and `nullable`)

**Official documentation:**
- [Input Variables](https://developer.hashicorp.com/terraform/language/values/variables)
- [Variable Validation](https://developer.hashicorp.com/terraform/language/values/variables#custom-validation-rules)

**What to practise:**
1. Open the Input Variables page — navigate to the Custom Validation
   Rules section, not just the overview
2. Write all three variables from scratch without looking at this
   demo's `03-variables.tf`
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
variable "bucket_suffix" {
  type        = string
  description = "Suffix appended to the artifact bucket name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,18}[a-z0-9]$", var.bucket_suffix))
    error_message = "bucket_suffix must be 3–20 lowercase alphanumeric characters or hyphens."
  }
}

variable "upload_token" {
  type        = string
  description = "Placeholder access token for artifact uploads"
  sensitive   = true
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
```

**Arguments you must know without looking up:**
- `nullable = false` — if `null` is explicitly passed, the `default` is
  used instead, not `null` itself
- `sensitive = true` — redacts from terminal/plan output only; the
  value is still written to state in plaintext

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Error: Invalid value for variable` | A validation block's condition evaluated to false | Check the value against the condition in the `validation` block |
| `Error: Invalid condition expression` | The `condition` returned a non-bool (e.g. a string literal) | Ensure `condition` evaluates to `true` or `false` — use `can()`, `contains()`, or comparison operators |
| `Error: Ephemeral value not allowed` | An ephemeral variable used in a regular resource argument | Ephemeral values can only flow into ephemeral outputs (child modules) or write-only resource arguments |
| Regex validation always fails even for valid-looking input | Forgot `can()` around `regex()` | `regex()` itself errors on no match rather than returning `false` — always wrap it: `can(regex(pattern, var.x))` |

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

#### `broken.tf` — Three deliberate variable-argument errors

**What this file does in this demo:** a self-contained configuration
(own `terraform {}`/`provider` block) with a non-boolean `validation`
condition, a `nullable = false` misunderstanding, and a number+string
arithmetic error — diagnose all three from `terraform validate`/`plan`
output alone.

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

variable "retry_count" {
  type    = number
  default = 3
}

variable "custom_role_name" {
  type     = string
  default  = "cloudnova-fallback-role"
  nullable = false                                     # Error 2 setup — see below
}

output "retry_as_string" {
  value = var.retry_count + "extra"                     # Error 3
}

output "custom_role_name" {
  value = var.custom_role_name                          # needed to observe Error 2
}
```

```bash
# Step A — the CLI -var attempt (what most learners try first)
terraform plan -var="custom_role_name=null"

# Step B — the actual nullable=false repro, via a tfvars file
cat > null.tfvars <<'EOF'
custom_role_name = null
EOF

terraform plan -var-file="null.tfvars"
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

**Error 2 — two separate gotchas stacked on top of each other**

Step A (`-var="custom_role_name=null"`) does **not** demonstrate
`nullable = false`. Per Terraform's docs, `-var` values are interpreted
as **literal strings** for scalar-typed variables like `string` — HCL
keywords such as `null` are only parsed for complex types (list, map,
object, etc.). So `-var="custom_role_name=null"` assigns the literal
4-character string `"null"`, not the HCL `null` value. The plan output
proves it:
```
* custom_role_name = "null"
```
That's a real string, not a fallback default and not an actual null —
`nullable = false` never even gets a chance to act, because no `null`
ever reached the variable.

Step B (`-var-file="null.tfvars"`) is the correct repro. `.tfvars`
files are parsed with full HCL syntax, so `custom_role_name = null` is
a genuine null. *Now* `nullable = false` kicks in: since the variable
can't be null and has a `default`, Terraform silently substitutes it.
The plan output confirms this:
```
* custom_role_name = "cloudnova-fallback-role"
```

The lesson: a learner expecting to check `var.custom_role_name == null`
downstream and branch to a computed fallback will never see `null` —
Terraform substitutes the `default` before the value is ever used in
the module. Fix: either remove `nullable = false` (allowing real `null`
through so it can be checked explicitly) if `null` is meant to be a
meaningful override signal, or accept the default as the intended
safety net and stop treating `null` as special. Separately: always pass
`null` via a `.tfvars` file (or `-var-file`) rather than `-var` on the
CLI, since `-var` won't parse it as HCL for scalar types.

**Error 3 — arithmetic operator applied to mismatched types**
`var.retry_count + "extra"` attempts to add a `number` and a `string`.
Terraform errors at `plan`/`validate`: "Invalid operand type — Unsuitable
value type; a number is required." The `+` operator requires both
sides to be numbers. Fix: use string interpolation instead if the goal
was a descriptive string: `"${var.retry_count} extra"`.

</details>

**Cleanup:**
```bash
cd src/break-fix/
rm -f terraform.tfstate terraform.tfstate.backup null.tfvars
cd ../..
```
No resources were created in this scenario (all three errors are caught
before any `apply`), so cleanup is just removing any local state files.

---

## Interview Prep

**Q1. A teammate marks a variable `sensitive = true` and says "now this value is secure — it's encrypted in state." What's wrong?**
`sensitive = true` only redacts from terminal output. The value is written to `terraform.tfstate` in plaintext. Security comes from how state is stored — encrypted S3 backend with IAM access control — not the `sensitive` flag. For values that must never be stored anywhere, `ephemeral = true` is correct, but it carries significant constraints: ephemeral values can't flow into regular resource arguments, and ephemeral outputs are only valid in child modules.

**Q2. When would you use `ephemeral = true` vs. `sensitive = true` on a variable, and what is the practical limitation of ephemeral?**
`sensitive = true`: value persists in state (downstream configs can read it; future plans can compare against it for drift detection) but is hidden from terminal output. `ephemeral = true`: value must never be stored anywhere — credentials, one-time tokens passed at apply time and never needed again. Practical limitations: ephemeral values can only flow into ephemeral outputs (child modules only) or write-only resource arguments. They cannot be used in regular resource arguments that Terraform tracks in state.

**Q3. Why can a `validation` block's `condition` only reference `var.<this_variable>`, and not another variable or a resource?**
Validation runs during variable resolution, before Terraform has necessarily resolved every other variable or built its resource graph. Allowing a condition to reference another variable would require Terraform to guarantee an evaluation order across variables that doesn't otherwise exist — variables aren't a DAG the way resources and locals are. Referencing a resource is out of scope for a stronger reason: resources may not exist yet (first apply) or may be about to change, so validating against their current state would validate against a moving target. If you need cross-variable validation, the alternative is a `precondition` on a resource or a `check` block, both of which run later in the plan/apply lifecycle when more context is available.

**Q4. A teammate writes `tostring(var.count) == "3"` instead of `var.count == 3` in a validation condition. Does this matter?**
Functionally both work here, but it signals a design smell worth raising in review: converting a `number` to a `string` just to compare it against a string literal adds an unnecessary conversion step and a conversion that could itself fail on unexpected input (though `tostring()` on a number rarely fails). The direct comparison `var.count == 3` is clearer, doesn't require understanding why a conversion function appears in a simple condition, and matches the variable's actual declared type. Type conversion functions are for genuine type mismatches — a string coming from a CLI flag that needs to become a number, for example — not for making two same-type values "match" more explicitly.

---

## Key Takeaways

1. **`sensitive = true` redacts, it does not encrypt or protect.** State
   security comes from where you store state — not from the flag.

2. **`ephemeral = true` is genuinely never stored — but has real
   constraints.** Can't flow into regular resource arguments. Ephemeral
   outputs are child-module-only (Demo 07 covers the root-module
   restriction in full).

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

7. **`can()` converts an erroring expression into a boolean.** This is
   why `can(regex(...))` is the idiomatic validation pattern — `regex()`
   alone errors on no match rather than returning `false`.

8. **Type conversion functions solve real type mismatches, not
   stylistic preferences.** Converting a same-type comparison just to
   "make it more explicit" (e.g. `tostring(var.n) == "3"`) is a design
   smell, not a best practice.

> **Demo scope:** Primary concept: Terraform input variables — the full
> argument set (`type`, `validation`, `sensitive`, `ephemeral`,
> `nullable`) and value precedence. Supporting concepts: operators and
> the conditional operator, `can()`/`regex()`/`contains()`/`alltrue()`
> and type-conversion functions, a `for` expression preview, and a
> `data.aws_caller_identity` preview.
> Estimated completion time: 40 minutes (reading + hands-on + verification).
> Checkpoints: 3 natural stopping points (end of Part A, end of Part B,
> end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform validate` | Checks configuration syntax and internal consistency, including `validation` block conditions |
| `terraform plan -var="KEY=VALUE"` | Overrides a variable's value for this plan only (highest precedence) |
| `terraform plan -var-file="FILE"` | Loads variable values from a specific file for this plan only |
| `terraform apply -var="KEY=VALUE"` | Same override, applied |
| `export TF_VAR_name=value` | Sets a variable's value via environment variable (precedence level 5) |
| `terraform state pull \| jq '...'` | Inspects the current remote state's raw JSON — used here to confirm a `sensitive` value is still stored in plaintext |
| `can(expression)` | Returns `true`/`false` — safely evaluates an expression that might error |
| `regex(pattern, string)` | Tests a string against a pattern — errors on no match (pair with `can()`) |
| `alltrue([...])` | Returns `true` if every element in a list is `true` (vacuously `true` on an empty list) |

---

## Next Demo

**Demo 06 — Locals in Depth:** the distinction test for choosing a
`local` over a `variable`, the full comparison table between the two,
type inference and chaining, circular-reference detection, `try()`,
`coalesce()`, `merge()`, building a JSON policy document as a
`jsonencode()` local — using this demo's IAM role as the continuing
example, plus a new `aws_sns_topic` to prove locals aren't tied to one
resource.

---

## Appendix — Anki Cards

**`05-variables-in-depth-anki.csv`:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::05-variables-in-depth
#separator:Comma
#columns:Front,Back,Tags
"A variable is marked sensitive = true. Is its value encrypted or protected in terraform.tfstate?","No. sensitive = true ONLY redacts the value from terminal output (plan/apply logs, terraform output display). The value is written to terraform.tfstate in plaintext, exactly like any other value. State security requires storing state securely (encrypted S3 backend, IAM access control) — not the sensitive flag.","demo05,variables,sensitive,ta004"
"What is the difference between sensitive = true and ephemeral = true on a variable?","sensitive = true: value is redacted from terminal output but IS written to state and plan files. ephemeral = true: value exists only in memory during plan/apply — NEVER written to state, plan files, or logs. Ephemeral values can only flow into ephemeral outputs (child modules only) or write-only resource arguments.","demo05,variables,sensitive,ephemeral,ta004"
"What are the two valid ephemeral contexts for an ephemeral variable value?","(1) An ephemeral = true output block in a child module (NOT a root module). (2) A write_only resource argument (Terraform 1.10+). Regular resource arguments are NOT ephemeral contexts.","demo05,variables,ephemeral"
"What does nullable = false on a variable do?","If null is passed as the variable value, the default is used instead. By default (nullable = true), explicitly passing null overrides the variable to null — even if a default exists. nullable = false prevents this: null input → default is used.","demo05,variables,nullable"
"A validation block's condition returns the string 'dev' instead of a boolean. What happens?","terraform validate errors: 'A condition expression must return either true or false.' The condition must be a boolean expression — use contains(), can(), regex(), or comparison operators. A string is not valid.","demo05,validation,ta004"
"Inside a validation block, what is the ONLY variable reference allowed in the condition, and why?","Only var.<this_variable>. Validation runs during variable resolution, before other variables are guaranteed resolved and before resources exist — referencing anything else would validate against a moving or nonexistent target.","demo05,validation"
"State the variable value precedence order from highest to lowest.","1. CLI -var flag, 2. CLI -var-file flag, 3. *.auto.tfvars files (alphabetical), 4. terraform.tfvars, 5. TF_VAR_ environment variables, 6. default value in the variable block, 7. interactive prompt (avoided in CI).","demo05,variables,precedence,ta004"
"What does can(regex('pattern', var.x)) return when the pattern does not match?","false — regex() errors when there is no match, and can() converts any error into false. This is the idiomatic pattern for regex-based validation: can(regex(...)) returns true on match, false on no match.","demo05,validation,can,regex"
"What does alltrue([]) return?","true — alltrue() returns true if ALL elements are true. An empty list satisfies this vacuously (no false elements). This is why validation conditions using alltrue([for item in var.list : ...]) pass when the list is empty.","demo05,functions,alltrue"
"What is the difference between list(string), set(string), and map(string)?","list: ordered, allows duplicates, indexed by position [0]. set: unordered, no duplicates, no positional index — sets have no literal syntax, use toset([...]). map: key-value pairs, keys are strings, no guaranteed order. All three require all elements to be the same type.","demo05,variables,types,ta004"
"Does var.retry_count + 'extra' work if retry_count is type = number?","No — Terraform errors with an invalid operand type. The + operator requires both sides to be numbers. To combine a number into a descriptive string, use string interpolation instead: ${var.retry_count} extra wrapped in quotes.","demo05,operators,break-fix"
"Why is converting a number to a string just to compare it to a string literal (e.g. tostring(var.n) == '3') considered a design smell?","It adds an unnecessary conversion step for no functional benefit — the direct comparison var.n == 3 is clearer and matches the variable's actual declared type. Type conversion functions exist for genuine type mismatches (e.g. a CLI-provided string that needs to become a number), not for making same-type comparisons feel more explicit.","demo05,functions,type-conversion"
"HCL has no if statement. What is the only conditional mechanism, and what is its syntax?","The conditional operator: condition ? value_if_true : value_if_false. There is no if statement equivalent in HCL — all conditional logic goes through this operator (or, for resource creation, count = var.create ? 1 : 0).","demo05,language,conditional"
"What does contains(['dev','staging','prod'], var.environment) check, and where is it commonly used?","Whether var.environment's value is one of the three listed strings — returns true/false. Commonly used inside a validation block's condition to restrict a variable to an allowed set of values.","demo05,functions,contains,ta004"
"A caller passes -var='custom_role_name=null' to a variable with nullable = false and a default set. What actually happens?","Terraform silently substitutes the default value — null never gets through. There is no error; this is a design behavior, not a bug, and is a common source of confusion when someone expects null to flow through as a meaningful signal.","demo05,variables,nullable,break-fix"
"What is an 'ephemeral context' in Terraform, defined precisely?","A location where Terraform explicitly guarantees a value will never be persisted to state. Exactly two currently qualify: an ephemeral = true output in a child module, and a write_only resource argument (1.10+). A regular resource argument is NOT an ephemeral context.","demo05,ephemeral,terms-of-art"
```

---

## Appendix — Quiz

**`05-variables-in-depth-quiz.md`:**

````markdown
# Quiz — Demo 05: Variables in Depth

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
storage is plaintext regardless. **A** is wrong — nothing about
`sensitive` triggers encryption; that requires a separately-encrypted
backend. **C** is wrong — that's `ephemeral = true`'s behavior, not
`sensitive`'s. **D** is wrong — sensitive values flow into regular
resource arguments exactly like any other value; only `ephemeral`
values have that restriction.

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

**A.** Full order: CLI `-var` > `-var-file` > `*.auto.tfvars` >
`terraform.tfvars` > `TF_VAR_` > `default`. So `-var` is highest and
`terraform.tfvars` actually outranks `TF_VAR_` (not the reverse). **B**
is wrong — it puts `terraform.tfvars` above `-var`, but no file-based
mechanism outranks the CLI flag. **C** is wrong — it places `TF_VAR_`
above `terraform.tfvars`, reversing their actual order. **D** is wrong
— it inverts the entire order, putting the lowest-precedence source
first.

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
`false`. `terraform validate` errors immediately. **A** is wrong —
Terraform has no "truthy string" concept; a condition must be an
actual boolean expression, not a non-empty string. **C** is wrong —
validation is never silently skipped; an invalid condition type is
itself an error. **D** is wrong — this is a `validate`-time error,
before any API call, not something that waits until `apply`.

</details>

---

**Q4.** A variable has `nullable = false` and `default = "dev"`. A
caller passes `-var="environment=null"`. What value is actually used?

A. `null`
B. `"dev"` — the default, since nullable = false substitutes it for null input
C. An empty string
D. An error is raised

<details>
<summary>Answer</summary>

**B.** With `nullable = false`, passing `null` causes Terraform to
substitute the `default` value instead — no error, no `null` value
used. **A** is wrong — that's the `nullable = true` (default) behavior,
where an explicit `null` does override. **C** is wrong — Terraform
never silently converts `null` to an empty string; it either becomes
`null` (`nullable = true`) or falls back to `default` (`nullable =
false`). **D** is wrong — this is a deliberate, documented substitution
behavior, not an error condition.

</details>

---

**Q5.** What does `alltrue([])` (an empty list) return?

A. `false` — an empty list has no true elements
B. `true` — vacuously true, no false elements exist to fail the check
C. An error — `alltrue()` requires at least one element
D. `null`

<details>
<summary>Answer</summary>

**B.** `alltrue([])` returns `true`. This is why validation conditions
using `alltrue([for x in var.list : ...])` pass when the list is empty
— there's nothing to violate the condition. **A** is wrong — it
reflects an intuitive but incorrect assumption; "all elements are true"
is vacuously satisfied by an empty set, the same logical principle as
an empty list satisfying a universally-quantified statement. **C** is
wrong — `alltrue()` doesn't require any minimum element count. **D** is
wrong — the function always returns a boolean, never `null`.

</details>

---

**Q6.** `var.retry_count` is `type = number`. What happens when you
write `var.retry_count + "extra"`?

A. Terraform coerces `"extra"` to `0` and adds it
B. Terraform concatenates them into a string
C. Terraform errors — `+` requires both operands to be numbers
D. Terraform silently drops the string

<details>
<summary>Answer</summary>

**C.** The `+` operator requires both sides to be numbers. Combining a
number into a descriptive string requires interpolation instead:
`"${var.retry_count} extra"`. **A** is wrong — Terraform never coerces
a non-numeric string to `0`; it errors instead of silently guessing.
**B** is wrong — that's what string interpolation does, not the `+`
operator, which is strictly arithmetic. **D** is wrong — there's no
silent-drop behavior anywhere in Terraform's type system; type
mismatches are errors, not warnings.

</details>

---

**Q7.** Which is the correct idiomatic pattern for validating a string
against a regex pattern inside a `validation` block?

A. `condition = regex("^[a-z]+$", var.name)`
B. `condition = can(regex("^[a-z]+$", var.name))`
C. `condition = var.name == regex("^[a-z]+$", var.name)`
D. Both A and B work identically

<details>
<summary>Answer</summary>

**B.** `regex()` alone errors when there's no match (it doesn't return
`false`) — `can()` converts that error into a boolean `false`, which is
what a `condition` requires. **A** is wrong — this is exactly the trap:
`regex()` without `can()` would cause `terraform validate` to error on
any non-matching input instead of cleanly failing the validation with
the custom `error_message`. **C** is wrong — comparing a string to
whatever `regex()` returns (which errors on no match, or a substring on
match) is not a meaningful boolean condition. **D** is wrong precisely
because A does not work identically to B — A errors uncontrolled, B
fails validation cleanly.

</details>

---

**Q8.** A variable is `ephemeral = true`. Which of the following is a
valid use of its value?

A. Passing it directly to a regular `resource` argument
B. Passing it to a `write_only` resource argument (1.10+)
C. Storing it in a `local` for later reuse across the config
D. Referencing it in a non-ephemeral output

<details>
<summary>Answer</summary>

**B.** `write_only` resource arguments are one of exactly two valid
ephemeral contexts (the other being a child-module ephemeral output).
**A** is wrong — regular resource arguments require Terraform to store
the value in state for drift detection, which is exactly what
`ephemeral` forbids. **C** is wrong — locals aren't an ephemeral
context; assigning an ephemeral value to a local doesn't make it safe
to store. **D** is wrong — a non-ephemeral output would itself write
the value to state, defeating the entire purpose of marking the
variable ephemeral.

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