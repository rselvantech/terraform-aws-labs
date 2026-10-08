# Demo 21 — Terraform Testing Basics

---

## Overview

Every module in this series so far has been verified by hand —
`terraform apply`, then a Console check, then `terraform destroy`. That
works, but it doesn't scale: nobody re-verifies Demo 14's `sns-topic`
module by hand every time they touch it months later. This demo
introduces Terraform's native `terraform test` framework, applied to
two modules already built in this series — proving they still behave
correctly without a human re-running every manual check.

**Real-world scenario — CloudNova:** the platform team wants automated
confidence that the `sns-topic` module and the VPC module still work
correctly after any future change — without a human re-running Demo 14
and Demo 16's manual verification steps every time.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Testing sns-topic: apply-mode, real (cheap) resources         │
│  run blocks, assert, expect_failures against a validation block        │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Testing the VPC Module: plan-mode, zero cost                  │
│  Same framework, deliberately plan-only — no NAT Gateway re-created    │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Running Both Test Suites Together                             │
│  terraform test, -verbose, -filter, and the CI angle (Demo 32 ahead)   │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- `.tftest.hcl` files and where Terraform looks for them
- `run` blocks — `command = apply` vs. `command = plan`, and why the
  choice matters for cost as much as correctness
- `assert` blocks — `condition` and `error_message`
- `expect_failures` — deliberately proving a `validation` block
  rejects bad input
- `variables` blocks at the `run` level, supplying test-specific input
- `terraform test`'s CLI flags: `-verbose`, `-filter`

**What this demo does NOT cover:** mock providers (Terraform 1.7+,
simulating provider behavior without any real API calls) — genuinely
useful, but this demo's tests are simple enough not to need them. Not
covered in this series.

---

## ⚠️ A Note on This Demo's One Cross-Demo Dependency

Part A's `main.tf` sources Demo 14's local module directly:
`source = "../../14-modules-basics/src/modules/sns-topic"`. This is
the **only** demo in the entire series whose main lab content reaches
into another demo's own folder rather than staying fully
self-contained — a deliberate choice, since the whole point of this
demo is testing a module the series already built, not a reason to
adopt cross-demo references as a general habit (this demo's own
Break-Fix scenario, by contrast, duplicates its supporting `.tf` files
rather than reaching back into this demo's `src/`, for exactly that
reason).

The tradeoff this creates: **if Demo 14's directory is ever renamed,
restructured, or moved to a different phase number, this demo's Part A
breaks** with a `module not found` error unrelated to anything done
wrong in Demo 21 itself. If you're maintaining this series and ever
renumber or relocate Demo 14, this relative path is the one place
outside Demo 14's own folder that also needs updating — check for it
specifically, the same way a "Next Demo" pointer needs checking after
a renumbering pass.

---

## How This Demo's Pieces Fit Together

**No new AWS solution, deliberately.** This demo's actual subject is a
*testing technique* applied to infrastructure this series already
built — Demo 14's `sns-topic` module and Demo 16's VPC module. There's
no new architecture to trace; the point is verifying two already-built
things behave as expected, automatically.

- Part A's tests genuinely create and destroy a real SNS topic and
  subscription per test run — cheap enough that `command = apply` is
  the right choice, since a real create/destroy cycle actually proves
  the module works, not just that its plan looks right.
- Part B's tests **never** create real infrastructure —
  `command = plan` is a deliberate choice, not a shortcut: Demo 16's
  VPC module includes a real NAT Gateway (~$1.00/session), and
  re-applying it just to test subnet counts would repeat that cost for
  no additional confidence the plan itself can't already provide.
- Part C runs both suites together with one `terraform test` command —
  proving the framework doesn't care whether a given test file
  actually touches AWS or not; it's the same command either way.

---

## Prerequisites

### Knowledge
- Demo 14 completed — the local `sns-topic` module's actual inputs and
  outputs, tested directly in this demo
- Demo 16 completed — the VPC module's actual inputs and outputs,
  tested directly in this demo (in plan mode only)

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | `>= 1.15.0` (pinned `~> 1.15.0` in this demo) | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version` |

### Verify AWS Account and Permissions

**Step 1 — Confirm your profile works:**

```bash
aws sts get-caller-identity --profile default --region us-east-2
```

**Step 2 — A cheap, harmless dry-run of this demo's actual service:**

```bash
aws sns list-topics --profile default --region us-east-2
# Expected: JSON with a Topics array (may be empty — that is fine)
# If you see AccessDenied: fix IAM permissions before proceeding,
# not after you're mid-lab
```

**Step 3 — Verify IAM permissions in Console:**

```
Console → IAM → Users → test → Permissions tab
  → Confirm AmazonSNSFullAccess (or equivalent) is attached ✅
```

**Required permissions for this demo:** same as Demo 14 (SNS) — Part
A's tests create and destroy real SNS resources. Part B's plan-mode
VPC tests require no permissions beyond read access, since nothing is
ever actually created.

```
sns:CreateTopic, sns:DeleteTopic, sns:GetTopicAttributes, sns:TagResource
sns:Subscribe, sns:Unsubscribe, sns:ListSubscriptionsByTopic
```

### Versions used in this demo

| Tool | Version |
|---|---|
| Terraform | `~> 1.15.0` (the test framework itself has been stable since `1.6`) |
| AWS Provider | `~> 6.47.0` |

> **Versions pinned as of September 2026** — same dating convention as
> the rest of this series. The `terraform test` framework's own
> stability baseline (`1.6`) is a fixed historical fact and doesn't
> need re-checking; the provider pin should still be checked against
> its own changelog if you're reading this well after that date.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Write a `.tftest.hcl` file with `run` blocks and `assert`
   conditions
2. ✅ Choose between `command = apply` and `command = plan` based on
   cost and what's actually being verified — not by default
3. ✅ Use `expect_failures` to prove a `variable` validation block
   genuinely rejects bad input
4. ✅ Supply test-specific input values via a `run` block's `variables`
   argument
5. ✅ Run `terraform test` against multiple test files, using
   `-verbose` and `-filter` to control output and scope

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| SNS topic + subscription (Part A, apply-mode tests) | Always free | **$0.00** | Created and destroyed automatically by the test framework itself |
| VPC module (Part B, plan-mode tests) | N/A — nothing created | **$0.00** | `command = plan` never creates real infrastructure, including the NAT Gateway |
| **Session total** | | **$0.00** | |

> No manual cleanup step is required for Part A — `terraform test`
> destroys its own ephemeral resources automatically at the end of
> each `run` block, whether the test passes or fails.

---

## Directory Structure

```
21-terraform-testing-basics/
├── README.md
├── 21-terraform-testing-basics-anki.csv
├── 21-terraform-testing-basics-quiz.md
└── src/
    ├── versions.tf              # terraform block + provider version constraints
    ├── provider.tf               # AWS provider: region, profile
    ├── variables.tf               # root-level test-harness variable, with a validation block
    ├── main.tf                     # calls both sns-topic (local) and vpc (registry) modules
    ├── tests/
    │   ├── sns-topic.tftest.hcl       # apply-mode tests, Part A
    │   └── vpc.tftest.hcl             # plan-mode-only tests, Part B
    └── break-fix/
        ├── versions.tf                 # self-contained copy — see note below
        ├── provider.tf                 # self-contained copy
        ├── variables.tf                # self-contained copy, incl. environment_label validation
        ├── main.tf                     # self-contained copy — calls both modules
        └── broken.tftest.hcl           # the 3 deliberate test-file errors
```

> **Break-fix's supporting `.tf` files are self-contained copies, not
> references to the parent directory.** Consistent with every other
> demo's Break-Fix scenario in this series — the errors this Part
> tests live entirely in `broken.tftest.hcl`, but the surrounding
> config is fully standalone rather than reaching back into this
> demo's own `src/` files. This is the same discipline the ⚠️ note near
> the top of this demo flags as *not* followed by Part A's own main
> lab content — Break-Fix deliberately avoids the cross-demo coupling
> that Part A deliberately accepts.

---

## Recall Check — Demo 20

Answer from memory before reading further:

1. Why is DNS validation preferred over email validation for an
   automated Terraform pipeline?
2. What does `wait_for_validation = true` actually change about
   `terraform apply`?
3. Does destroying Demo 20's resources ever affect the
   `rselvantech.com` hosted zone itself?

<details>
<summary>Answers</summary>

1. DNS validation only requires a DNS record to exist, which Terraform
   can create itself — email validation requires a human to receive a
   message and click a link, which no automated `apply` can do.
2. It blocks `apply` from completing until AWS confirms the
   certificate is genuinely `ISSUED`, not just requested.
3. No — only the certificate and the two records that demo created are
   destroyed. The zone itself is read-only to this series, managed
   entirely outside it.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `.tftest.hcl` file | File type | Holds `run` blocks Terraform executes as tests |
| `run` block | Test construct | One test step — either a `plan` or an `apply` |
| `command = plan` / `command = apply` | `run` argument | Controls whether real infrastructure is actually created |
| `assert` block | Test construct | `condition` + `error_message`, checked after each `run` |
| `expect_failures` | `run` argument | Asserts a `variable` validation block genuinely rejects the given input |
| `terraform test` | CLI command | Discovers and executes every `.tftest.hcl` file |

**Related constructs worth knowing (not used in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| Mock providers (Terraform 1.7+) | Simulating provider responses with no real API calls | Not covered in this series |
| `terraform test -json` | Machine-readable output for CI pipelines | Referenced ahead of Demo 32, not built here |

---

### Detailed Explanation of New Constructs

#### `.tftest.hcl` Files and `run` Blocks

```hcl
# tests/sns-topic.tftest.hcl

run "creates_topic_and_subscription" {
  command = apply

  variables {
    topic_name          = "cloudnova-test-topic"
    subscription_email  = "platform-team@cloudnova.example.com"
  }

  assert {
    condition     = output.topic_arn != ""
    error_message = "Expected a non-empty topic ARN output"
  }
}
```

**What it does:** Terraform automatically discovers `.tftest.hcl`
files in the `tests/` directory (or the config's own root — `tests/`
is the convention this demo follows). Each `run` block is one test
step: `command = apply` genuinely creates real infrastructure (this
module's SNS topic and subscription), evaluated against real state,
then destroys it automatically once the test file finishes — whether
the assertions passed or failed.

> **Each test file's state is entirely separate from any real,
> existing state for this configuration.** Running these tests never
> touches this demo's own `terraform.tfstate` — the test framework
> maintains its own in-memory state per test file, starting empty
> every time.

---

#### `command = plan` — Testing Without Creating Anything

```hcl
# tests/vpc.tftest.hcl

run "creates_correct_subnet_counts" {
  command = plan

  assert {
    condition     = length(module.vpc.public_subnets) == 2
    error_message = "Expected exactly 2 public subnets"
  }
}
```

**What it does:** identical `run`/`assert` syntax, but
`command = plan` means Terraform only computes what *would* happen —
no NAT Gateway, no VPC, nothing is actually created in AWS. The
assertion still checks a real, computed value (the planned
`public_subnets` list's length), just without paying for or waiting on
any of it.

> **This is a deliberate cost/confidence tradeoff, not a lesser
> test.** A plan-mode test can't catch every possible failure (a value
> AWS only determines at actual creation time might behave
> differently) — but for structural questions like "how many subnets
> does this produce," a plan already contains the answer, and there's
> no reason to pay for a NAT Gateway to confirm it.

---

#### `expect_failures` — Proving Bad Input Is Genuinely Rejected

```hcl
# variables.tf (this demo's own root config)
variable "environment_label" {
  type        = string
  description = "Environment label passed through to the sns-topic module's tags"

  validation {
    condition     = can(regex("^[a-z]+$", var.environment_label))
    error_message = "environment_label must be lowercase letters only."
  }
}
```

```hcl
# tests/sns-topic.tftest.hcl
run "rejects_uppercase_environment_label" {
  command = plan

  variables {
    environment_label = "PROD"
  }

  expect_failures = [var.environment_label]
}
```

**What it does:** `expect_failures` inverts the usual pass/fail logic
for the listed value — this test *passes* specifically because
`"PROD"` fails the `validation` block's condition. Without
`expect_failures`, this exact same `run` block would report a failure,
since the underlying `plan` itself errors out.

> **`expect_failures` targets a `validation`/`precondition`/
> `postcondition` failure specifically — not just "any error."** A
> missing required variable with no `validation` block at all isn't
> what this demonstrates; it needs a real condition to deliberately
> trip. This demo adds `environment_label`'s validation to its own
> root config specifically to have something genuine for
> `expect_failures` to exercise, rather than modifying Demo 14's
> already-built module.

---

## Lab Step-by-Step Guide

---

## Part A — Testing `sns-topic`: apply-mode, real (cheap) resources

**What you accomplish in Part A:** write and run apply-mode tests
against Demo 14's module, including a deliberate validation-failure
test.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-2-modules/21-terraform-testing-basics/src
```

### Step 2 — Create the root scaffolding files

#### `versions.tf` — Provider and Terraform version pins

**versions.tf:**

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

#### `provider.tf` — AWS provider configuration

**provider.tf:**

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
```

Create a file **variables.tf** and add the below content:

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

variable "environment_label" {
  type        = string
  description = "Environment label passed through to the sns-topic module's tags — used to demonstrate expect_failures"
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z]+$", var.environment_label))
    error_message = "environment_label must be lowercase letters only."
  }
}
```

### Step 3 — Call both modules from root

Create a file **main.tf** and add the below content:

```hcl
module "sns_topic" {
  source = "../../14-modules-basics/src/modules/sns-topic"

  topic_name         = "cloudnova-test-topic"
  subscription_email = "platform-team@cloudnova.example.com"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "cloudnova-test-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2a", "us-east-2b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway = true
}
```

> **This is the first demo in the series where a `source` path reaches
> into another demo's own folder** — see the ⚠️ note near the top of
> this document for the tradeoff that creates and what to watch for if
> Demo 14 is ever moved or renamed.

> **`enable_nat_gateway = true` is present here but never actually
> triggers a real NAT Gateway.** Every test against this module in
> this demo runs with `command = plan` — the argument reflects Demo
> 16's real configuration accurately (so the plan being tested is
> genuinely representative), but plan mode never applies it.

### Step 4 — Write the sns-topic test file

Create a file **tests/sns-topic.tftest.hcl** and add the below
content:

```hcl
run "creates_topic_and_subscription" {
  command = apply

  assert {
    condition     = module.sns_topic.topic_arn != ""
    error_message = "Expected a non-empty topic ARN output"
  }
}

run "rejects_uppercase_environment_label" {
  command = plan

  variables {
    environment_label = "PROD"
  }

  expect_failures = [var.environment_label]
}
```

### Step 5 — Run the sns-topic tests

```bash
terraform init
terraform test -filter=tests/sns-topic.tftest.hcl
```

Expected:

```
tests/sns-topic.tftest.hcl... in progress
  run "creates_topic_and_subscription"... pass
  run "rejects_uppercase_environment_label"... pass
tests/sns-topic.tftest.hcl... tearing down
tests/sns-topic.tftest.hcl... pass

Success! 2 passed, 0 failed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **Both runs report "pass" — including the one testing a deliberate
> failure.** `rejects_uppercase_environment_label` passes precisely
> *because* the validation genuinely rejected `"PROD"` — if the module
> had silently accepted it instead, this test would report a failure.

---

## Part B — Testing the VPC Module: plan-mode, zero cost

**What you accomplish in Part B:** write and run plan-only tests
against Demo 16's VPC module, verifying structure with zero AWS cost.

### Step 6 — Write the VPC test file

Create a file **tests/vpc.tftest.hcl** and add the below content:

```hcl
run "creates_correct_subnet_counts" {
  command = plan

  assert {
    condition     = length(module.vpc.public_subnets) == 2
    error_message = "Expected exactly 2 public subnets"
  }

  assert {
    condition     = length(module.vpc.private_subnets) == 2
    error_message = "Expected exactly 2 private subnets"
  }
}

run "vpc_cidr_matches_expected_range" {
  command = plan

  assert {
    condition     = module.vpc.vpc_cidr_block == "10.0.0.0/16"
    error_message = "Expected the VPC's CIDR block to be 10.0.0.0/16"
  }
}
```

### Step 7 — Run the VPC tests

```bash
terraform test -filter=tests/vpc.tftest.hcl
```

Expected:

```
tests/vpc.tftest.hcl... in progress
  run "creates_correct_subnet_counts"... pass
  run "vpc_cidr_matches_expected_range"... pass
tests/vpc.tftest.hcl... pass

Success! 2 passed, 0 failed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **Confirm no real AWS resources were created.**
> `aws ec2 describe-vpcs --filters "Name=tag:Name,Values=cloudnova-test-vpc"`
> should return an empty list — `command = plan` never reaches an
> actual `apply`, regardless of how many assertions ran against the
> computed plan.

---

## Part C — Running Both Test Suites Together

**What you accomplish in Part C:** run the full test suite in one
command, and use `-verbose` to inspect exactly what each `run` block
actually did.

### Step 8 — Run everything

```bash
terraform test
```

Expected: both test files' results, combined:

```
tests/sns-topic.tftest.hcl... pass
tests/vpc.tftest.hcl... pass

Success! 4 passed, 0 failed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

### Step 9 — Inspect verbose output

```bash
terraform test -verbose
```

Expected: the full plan or state for every `run` block, not just
pass/fail — useful for understanding *why* a test passed or failed,
not just that it did.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **This same `terraform test` command is exactly what Demo 32's
> GitLab CI pipeline will eventually run automatically**, on every
> change, using `-json` for machine-readable output instead of the
> human-readable format shown here.

---

## Cleanup

### Step 10 — Confirm the test framework's automatic teardown worked

No manual cleanup is required — `terraform test` destroys its own
ephemeral resources automatically as each test file finishes, whether
tests passed or failed.

```bash
aws sns list-topics --profile default --region us-east-2 | grep cloudnova-test-topic
```

Expected: no output — confirming the test framework's automatic
teardown genuinely worked, not just that the test reported success.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## What You Learned

1. ✅ `.tftest.hcl` files with `run`/`assert` blocks let you verify a
   module's behavior without manual `apply`/Console-check/`destroy`
   cycles
2. ✅ `command = plan` vs. `command = apply` is a real cost/confidence
   choice — not a default to accept without thinking about what's
   actually being verified
3. ✅ `expect_failures` proves a `validation` block genuinely rejects
   bad input — the test passes *because* the underlying operation
   failed
4. ✅ A `run` block's `variables` argument supplies test-specific
   input, independent of the configuration's own defaults
5. ✅ `terraform test` maintains entirely separate, in-memory state per
   test file — it never touches a configuration's real, existing state

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `terraform test`, `run` blocks | *Not directly mapped — see note below* | |
| `assert`/`expect_failures` | *Not directly mapped — see note below* | |

> **Honest scope note, not a fabricated mapping:** `terraform test` is
> a relatively recent framework (stable since Terraform 1.6), and the
> TA-004 objective outline verified earlier in this series (for
> Demo 18's workspace content) did not include a dedicated testing
> objective either. This content is included for practical
> completeness — genuinely useful, increasingly common in real
> Terraform workflows — not because it's confirmed exam-tested.

### Common Exam Traps

Given the honest scope note above, this section covers practical traps
rather than exam-specific ones:

| Scenario | What actually happens | Common wrong assumption |
|---|---|---|
| A `run` block with `command = apply` fails partway through | Terraform still attempts to destroy whatever was created, even on failure | Assuming a failed test leaves orphaned real infrastructure behind |
| `expect_failures` is used on a variable with no `validation` block | The test fails — there's no validation failure to "expect" | Assuming `expect_failures` works for any kind of error, including a plain missing-argument error |

### Exam Task — Write a complete configuration

**Task:** CloudNova wants a test proving the `sns-topic` module
rejects a `topic_name` longer than 256 characters (SNS's real naming
limit).

**Block types required:** `run` (×1), a `validation` block added to a
wrapping root variable (same pattern as this demo's
`environment_label`)

**Official documentation:**
- [Terraform Tests](https://developer.hashicorp.com/terraform/language/tests)

**What to practise:**
1. Write the wrapping variable's `validation` block from scratch
2. Write the `run` block using `expect_failures`, without looking at
   this demo's own example

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
variable "topic_name_input" {
  type = string
  validation {
    condition     = length(var.topic_name_input) <= 256
    error_message = "topic_name_input must be 256 characters or fewer."
  }
}
```

```hcl
run "rejects_topic_name_over_256_chars" {
  command = plan

  variables {
    topic_name_input = join("", [for i in range(300) : "a"])
  }

  expect_failures = [var.topic_name_input]
}
```

**Arguments you must know without looking up:**
- `expect_failures` takes a list of variable/resource references, not
  a boolean — even for a single value, it's `[var.x]`, not `var.x`
  alone

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `terraform test` reports "no test files found" | Test files aren't named `*.tftest.hcl`, or aren't in the config's root or `tests/` directory | Confirm the exact filename extension and location |
| A `command = apply` test never tears down | A prior test run was interrupted (e.g. `Ctrl+C`) before cleanup completed | Manually check for and destroy any leftover resources with the test's own tags before re-running |
| `expect_failures` test itself fails | The referenced variable's `validation` block didn't actually reject the given input | Confirm the `validation` condition genuinely fails for the specific value the test supplies |

---

## Break-Fix Scenario

Three deliberate errors — this time, the errors live in the **test
file** itself, not the configuration being tested. Unlike every other
demo's Break-Fix, this one's supporting `.tf` files are a minimal,
self-contained restatement of this demo's own root config — not a
reference to it — so `break-fix/` stays genuinely standalone, same
discipline as every other demo in this series.

```bash
cd src/break-fix/
terraform init
terraform test -filter=broken.tftest.hcl
```

#### Self-contained supporting files

**versions.tf, provider.tf, variables.tf, main.tf:** identical in
substance to this demo's own root files (Parts A/B above) — reproduced
here as their own standalone copies so this Break-Fix scenario doesn't
depend on any other file in this demo's own `src/` directory.

#### `broken.tftest.hcl` — Three deliberate errors

**What this file does in this demo:** a test file with a reference to
a nonexistent output, an `expect_failures` target with no real
validation block, and a `variables` block supplying a value of the
wrong type — diagnose all three.

**broken.tftest.hcl:**

```hcl
run "broken_assertion" {
  command = apply

  assert {
    condition     = module.sns_topic.arn != "" # Error 1: wrong output name, should be topic_arn
    error_message = "Expected a non-empty ARN"
  }
}

run "broken_expect_failures" {
  command = plan

  variables {
    aws_region = "not-a-real-region"
  }

  expect_failures = [var.aws_region] # Error 2: aws_region has no validation block at all
}

run "broken_variable_type" {
  command = plan

  variables {
    environment_label = 12345 # Error 3: environment_label expects a string, not a number
  }
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — wrong output name (`arn` instead of `topic_arn`)**
The `sns_topic` module's actual output is `topic_arn` — there is no
bare `arn`. Reported as an "Unsupported attribute" error before the
test can even run. Fix: correct the reference to
`module.sns_topic.topic_arn`.

**Error 2 — `expect_failures` targeting a variable with no
`validation` block**
`aws_region` has no `validation` block in this demo's configuration —
there's no validation failure for `expect_failures` to expect. The
test fails, reporting that the expected failure never occurred. Fix:
either add a real `validation` block to the targeted variable, or
target a variable that already has one (`environment_label`).

**Error 3 — wrong variable type, and what actually happens**
`environment_label` is typed `string`; `12345` is a number. Terraform
converts the number to its string form, `"12345"`, per its normal
type-conversion rules — this isn't silently accepted as "close
enough." Once converted, `"12345"` is checked against
`environment_label`'s own `validation` block
(`can(regex("^[a-z]+$", var.environment_label))`), which digits fail —
`[a-z]+` matches only lowercase letters. So this `run` block reports a
genuine validation failure, the same class of failure Demo 19's
Break-Fix Error 1 and this demo's own
`rejects_uppercase_environment_label` test both demonstrate — not a
vague "unexpected behavior downstream." Fix: supply a real string
value that actually satisfies the validation, e.g.
`environment_label = "staging"` — or, if the point is deliberately
testing this rejection, add `expect_failures = [var.environment_label]`
to this `run` block so the (correctly occurring) validation failure is
the expected, passing outcome rather than an unhandled test failure.

</details>

**Cleanup:**
```bash
cd src/break-fix/
rm -f terraform.tfstate terraform.tfstate.backup
cd ../..
```

---

## Interview Prep

**Q1. Why does this demo test the VPC module in plan mode but the
sns-topic module in apply mode?**
Cost and what's actually being verified. The VPC module includes a
real NAT Gateway costing roughly $1.00/session — re-applying it just
to confirm subnet counts would repeat that cost for no additional
confidence a plan can't already provide for a purely structural
question. The sns-topic module's resources are free, so an actual
create/destroy cycle is worth the extra confidence of testing real
applied state, not just a plan.

**Q2. What does it mean for `expect_failures` to make a test pass
"because" something failed?**
`expect_failures` inverts the normal pass/fail relationship for the
listed value — the test's actual goal is confirming a `validation`
block correctly rejects bad input. If the underlying `plan` succeeds
despite the intentionally-bad input, that's the test failing, since it
means the validation didn't do its job. The test only passes when the
validation genuinely blocks the input as designed.

**Q3. A teammate asks whether running `terraform test` risks affecting
this demo's real, existing infrastructure. What do you tell them?**
No — every test file maintains its own entirely separate, in-memory
state, starting empty each run, regardless of what real state already
exists for that configuration. `terraform test` genuinely cannot touch
or corrupt a project's real `.tfstate` file; it's an isolated
operation by design.

**Q4. This demo's `main.tf` sources Demo 14's module directly by
relative path — is that a pattern worth reusing elsewhere in this
series?**
No, and this demo is explicit about that: it's the only place in the
entire series a demo's main lab content reaches into another demo's
own folder, done here specifically because the whole point is testing
a module the series already built. It creates a real, if narrow,
fragility — if Demo 14 is ever renamed or moved, this demo's Part A
breaks for reasons that have nothing to do with anything covered in
Demo 21 itself. Every other demo (including this one's own Break-Fix)
stays self-contained specifically to avoid that kind of coupling.

---

## Key Takeaways

1. **`command = apply` vs. `command = plan` is a deliberate cost and
   confidence tradeoff, not a default.** Test cheap resources with
   real applies; test expensive ones structurally, in plan mode.

2. **`expect_failures` proves a `validation` block genuinely rejects
   bad input** — it targets a real validation/precondition/
   postcondition failure specifically, not any error in general.

3. **A `run` block's `variables` argument supplies test-specific
   input**, independent of whatever defaults the configuration itself
   declares.

4. **Test file state is entirely separate from a configuration's real
   state** — `terraform test` cannot touch or corrupt existing,
   real infrastructure's tracked state.

> **Demo scope:** Primary concept: `terraform test` framework basics —
> `run`/`assert` blocks, `command` mode selection, `expect_failures`.
> Supporting concepts: cost-aware mode selection, test-specific
> variable overrides, the one deliberate cross-demo dependency this
> series contains.
> Estimated completion time: 35–40 minutes.
> Checkpoints: 3 natural stopping points (end of Part A, end of
> Part B, end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform test` | Discovers and runs every `.tftest.hcl` file |
| `terraform test -filter=PATH` | Runs only the specified test file |
| `terraform test -verbose` | Shows the full plan/state for each `run` block, not just pass/fail |

---

## Next Demo

**Demo 22a — State Backend Bootstrap.** Phase 3 begins here — the
first of four sub-demos that together make up what was originally
planned as a single Demo 22. Before any persistent compute exists,
22a stands up the project's own durable Terraform state backend; 22b
and 22c add cost/configuration guardrails and re-create the ECR/ACM
objects Demos 19/20 taught as teaching reps; 22d is where the actual
EKS cluster and `retail-store-sample-app` deployment begin, re-applying
Demo 16/17's module code for real and marking the shift from isolated
teaching reps to an ongoing, incrementally-extended system.

---

## Appendix — Anki Cards

**21-terraform-testing-basics-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 2 - Modules::21-terraform-testing-basics
#separator:Comma
#columns:Front,Back,Tags
"What's the actual difference between command = apply and command = plan in a run block?","apply genuinely creates real infrastructure, evaluates it, then destroys it automatically. plan only computes what would happen — nothing is ever actually created. The choice is a real cost/confidence tradeoff, not a default.","demo21,terraform-test"
"What does expect_failures actually prove?","That a variable's validation block (or a precondition/postcondition) genuinely rejects the given bad input — the test passes because the underlying plan/apply failed as expected, not despite it.","demo21,terraform-test,gotcha"
"Can expect_failures be used on a variable with no validation block at all?","No meaningfully — there's no validation failure to expect. The test would fail, reporting the expected failure never occurred, since a plain missing-argument error isn't the same as a validation condition failing.","demo21,terraform-test,break-fix"
"Does running terraform test ever touch a configuration's real, existing state file?","No — every test file maintains its own entirely separate, in-memory state, starting empty each run, regardless of what real state already exists.","demo21,terraform-test,gotcha"
"Why would you test a module in plan mode instead of apply mode, even though apply mode gives more real-world confidence?","Cost. A module with expensive resources (like a NAT Gateway) doesn't need to actually create them just to verify structural facts (subnet counts, CIDR values) that a plan already computes correctly.","demo21,terraform-test,cost"
"What does a run block's variables argument do?","Supplies test-specific input values for that run, independent of whatever defaults the configuration under test declares.","demo21,terraform-test"
"Why is Demo 21's main.tf sourcing Demo 14's module directly considered a deliberate exception, not a pattern to reuse?","It's the only demo in the series whose main lab content reaches into another demo's own folder — done specifically to test an already-built module. It creates a real fragility (breaks if Demo 14 is ever renamed/moved) that every other demo, including this one's own Break-Fix, avoids by staying self-contained.","demo21,terraform-test,gotcha"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the framework facts
> (apply/plan difference, `expect_failures`, state isolation). This
> Quiz instead works through this demo's own Break-Fix scenario and
> realistic "what would this `terraform test` output tell you"
> situations, so the two together cover recall and diagnosis without
> asking the same question twice.

**21-terraform-testing-basics-quiz.md:**

````markdown
# Quiz — Demo 21: Terraform Testing Basics

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before Phase 3 begins.

---

**Q1. (Multiple Choice)** `assert { condition = module.sns_topic.arn
!= "" }` fails with `Unsupported attribute`. What's the fix?

- A) Add `depends_on` to the `run` block
- B) Reference `module.sns_topic.topic_arn` instead — the module has no bare `arn` output
- C) Change `command = apply` to `command = plan`
- D) Re-run `terraform init -upgrade`

<details>
<summary>Answer</summary>

**B.** This module's real output is `topic_arn` (established back in
Demo 14) — a guess-by-analogy mistake, the same class of error this
series' registry-module demos repeatedly warn against.

</details>

---

**Q2. (Multiple Choice)** `expect_failures = [var.aws_region]` is set,
but `aws_region` has no `validation` block anywhere in the
configuration. What happens when this test runs?

- A) The test passes automatically, since `aws_region` is clearly invalid
- B) The test fails — there's no validation failure for `expect_failures` to expect
- C) Terraform silently adds a default validation block
- D) `aws_region` is skipped for this run only

<details>
<summary>Answer</summary()>

**B.** `expect_failures` needs a real `validation`/`precondition`/
`postcondition` to trip — with none present, the expected failure
never occurs, and the test itself reports a failure.

</details>

---

**Q3. (Multiple Choice)** `environment_label = 12345` (a number) is
supplied to a `string`-typed variable whose `validation` block
requires lowercase letters only. What actually happens?

- A) Terraform rejects this immediately as a type error, before validation ever runs
- B) `12345` converts to the string `"12345"`, which then fails the existing lowercase-letters validation
- C) The number passes through unchanged and validation is skipped for non-string types
- D) This always succeeds, since numbers are considered valid lowercase input

<details>
<summary>Answer</summary()>

**B.** Terraform's normal type conversion turns the number into its
string form first — `"12345"` then genuinely fails the
`^[a-z]+$` regex check, since digits aren't lowercase letters. This is
a real, deterministic validation failure, not vague "unexpected
behavior."

</details>

---

**Q4. (True/False)** Running `terraform test` against this demo's test
files could accidentally modify or corrupt this demo's own real
`terraform.tfstate` file.

- A) True
- B) False

<details>
<summary>Answer</summary()>

**B) False.** Every test file maintains entirely separate, in-memory
state that starts empty on each run — it's isolated by design from any
real, existing state.

</details>

---

**Q5. (Multiple Choice)** Why does this demo choose `command = plan`
for every VPC-module test, rather than `command = apply`?

- A) `apply`-mode tests aren't supported for registry modules
- B) Applying would re-create a real, billed NAT Gateway, for no added confidence on purely structural questions like subnet count
- C) `plan` mode always runs faster regardless of the resource
- D) The VPC module has no outputs that can be tested in apply mode

<details>
<summary>Answer</summary()>

**B.** This is a deliberate cost decision, directly paralleling Demo
16's own NAT Gateway warning — not a technical limitation of `apply`
mode itself.

</details>

---

**Q6. (Multiple Choice)** Demo 14's `sns-topic` module directory gets
renamed as part of a future series reorganization. What breaks as a
direct result, and why?

- A) Nothing — every demo in this series is fully self-contained
- B) Demo 21's Part A, specifically, because its `main.tf` sources that exact relative path directly
- C) Every demo from 14 onward, since they all reference Demo 14's folder
- D) Only Demo 14's own Break-Fix scenario

<details>
<summary>Answer</summary()>

**B.** Demo 21 is explicitly the one exception to this series'
self-containment — its `main.tf` has a real `source = "../../
14-modules-basics/src/modules/sns-topic"` dependency. No other demo
(including Demo 21's own Break-Fix) has this coupling.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 5-6/6 | Import Anki cards — Phase 2 complete, move to Phase 3 |
| 4/6 | Review the wrong answers, then proceed |
| 3/6 | Re-read the relevant sections, retry those questions |
| Below 3/6 | Re-read the full demo and redo the walkthrough before proceeding |
````