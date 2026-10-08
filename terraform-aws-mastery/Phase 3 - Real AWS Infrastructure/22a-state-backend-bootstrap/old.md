# Demo 22a — State Backend Bootstrap: Project-Layer S3 + DynamoDB

---

## Overview

Every demo so far in this series has used its own throwaway state —
either local (most demos) or the single S3 backend you built yourself
in Demo 01. Phase 3 changes that. Starting now, you're building one
**persistent** environment that survives between sessions, not a fresh
teaching rep every time. That environment needs its own Terraform
state — separate from any individual demo's state — and that state
needs a home before anything else in Phase 3 can be built.

**Real-world scenario — CloudNova:**
The team's proof-of-concept demos are done. Leadership approved moving
`retail-store-sample-app` into a real, ongoing environment — not
another teaching exercise, but infrastructure that keeps running (and
keeps costing money) across every future work session. Before writing
a single line of VPC or EKS configuration, you need somewhere durable,
shared, and locked to keep track of what this environment actually
contains. That "somewhere" is itself infrastructure — and it has a
bootstrapping problem your Demo 01 remote backend never had to solve,
because Demo 01's state bucket was created by hand in the Console.
This time, you'll create it with Terraform too.

**What this demo builds:**
```
┌─────────────────────────────────────────────────────────────────────────┐
│  CONCEPTS — The chicken-and-egg problem, and the standard resolution    │
│  Why the backend that stores state can't be created by the config      │
│  that uses it as a backend — and why this project's answer to that     │
│  differs from Demo 01's                                                │
├─────────────────────────────────────────────────────────────────────────┤
│  LAB — Bootstrap config (local state) → S3 bucket + DynamoDB table →   │
│  main config's backend.tf points at both → first-time terraform init   │
│  (not a migration — nothing was ever tracked in S3 before this)        │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- The chicken-and-egg problem: why a backend's own storage can't be
  created by the config that will use it
- The bootstrap-config pattern: a small, separate, local-state root
  config whose only job is to create the backend's infrastructure
- `aws_dynamodb_table` for state locking — the pre-1.11 pattern, used
  here deliberately, not because it's the current default
- Why this project's state backend won't use `use_lockfile = true`
  even though Demo 01 taught it as the modern standard
- First-time `terraform init` against a freshly created backend versus
  `terraform init -migrate-state` (Demo 01) — same command family,
  different situation
- What "torn down between sessions" does *not* mean for this specific
  resource, and why

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** two resources, created once — an S3
bucket (versioned, encrypted) that will hold the project-layer state
file, and a DynamoDB table that will hold the state lock. Nothing else.
This demo does not touch the VPC, EKS, or any part of
`retail-store-sample-app` — those all arrive in 22d and later.

**Why two separate Terraform configs exist in this one demo:** the
bootstrap config (`src/bootstrap/`) is deliberately small and uses
**local** state — it has exactly one job, creating the S3 bucket and
DynamoDB table, and once that job is done it never needs to run again
except to modify those two resources directly. The main project
config (`src/phase-3-onward/`, which 22d onward will keep building
into) then points its own `backend "s3"` block at what the bootstrap
config just created, and runs `terraform init` for the first time
against that backend. This is not a migration — there is no prior
state to copy, because nothing was ever tracked in S3 before this
moment. That distinction matters: Demo 01's `terraform init
-migrate-state` had local state to carry over; this demo's `terraform
init` starts from nothing.

**Why this demo has no Cleanup that tears anything down:** unlike
every other demo before it, this demo's whole output is meant to
outlive the session. Per the project's teardown categorization
(Solution Architecture §9/ADR-017), the state backend cannot be
destroyed and recreated every session — doing so would destroy the
very state history it exists to preserve, defeating its purpose. This
demo ends with a **verification** step, not a destroy step.

---

## Prerequisites

### Knowledge
- Demo 01 completed — remote S3 backends, `backend "s3"` block syntax,
  state migration, why local state breaks for teams
- Demo 21 completed — most recent demo in the series
- Comfortable with the chicken-and-egg framing generally (Demo 01
  covered it for a single bucket; this demo extends it to a
  bucket-plus-table pair)

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | `>= 1.15.0` | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version` |

### Verify AWS Account and Permissions

```bash
aws sts get-caller-identity --profile default
aws dynamodb list-tables --profile default
# Expected: JSON with TableNames array (may be empty)
```

**Required permissions beyond Demo 01's S3 set:**
```
dynamodb:CreateTable, dynamodb:DescribeTable, dynamodb:DeleteTable
dynamodb:PutItem, dynamodb:GetItem, dynamodb:DeleteItem
```

> For a learning account, `AmazonDynamoDBFullAccess` covers this. In
> production, scope to the minimum required actions.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain the chicken-and-egg problem for a Terraform backend and
   why it applies to any backend, not just S3
2. ✅ Explain why this project's state backend uses `aws_dynamodb_table`
   for locking instead of Demo 01's `use_lockfile = true`
3. ✅ Write a self-contained bootstrap config that uses local state to
   create the infrastructure a different config will use as its remote backend
4. ✅ Distinguish first-time `terraform init` against a new backend
   from `terraform init -migrate-state` against an existing one
5. ✅ Explain why this specific resource is exempt from Phase 3's
   "torn down between sessions" default

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| S3 state bucket (small file) | Covered by free tier | **$0.00** | Same profile as Demo 01's state bucket |
| DynamoDB table (on-demand, tiny) | 25 GB storage / 200M requests free (perpetual, not 12-month) | **$0.00** | Lock table holds one item per active operation |
| **Session total** | | **~$0.00** | This resource is created once and never torn down — no ongoing per-session cost to track here |

> Always run cleanup at the end of the session. This demo has no
> Cleanup section — see "How This Demo's Pieces Fit Together" above
> for why.

---

## Directory Structure

```
22a-state-backend-bootstrap/
├── README.md
├── 22a-state-backend-bootstrap-anki.csv   # Anki flash cards
├── 22a-state-backend-bootstrap-quiz.md    # Quiz
└── src/
    ├── bootstrap/                          # local state — run once
    │   ├── versions.tf                     # terraform block + provider version
    │   ├── provider.tf                     # AWS provider config
    │   ├── variables.tf                    # input variables
    │   ├── main.tf                         # S3 bucket + DynamoDB table
    │   └── outputs.tf                      # bucket name, table name
    └── phase-3-onward/                     # points at the bootstrap's output
        └── backend.tf                      # backend "s3" block — first-time init target
```

> **Note on repo alignment:** in the actual `cloudnova-retail-store-e2e`
> project, these paths correspond to `src/terraform/bootstrap/` and
> `src/terraform/phase-3-onward/` respectively (Solution Architecture
> §2a) — those folders were reserved in advance for exactly this demo.

---

## Recall Check — Demo 21

> ⚠️ **[VERIFY — pending Demo 21 content]** Per the master standard,
> Recall Check questions must trace explicitly to the immediately
> preceding demo's (Demo 21, Terraform Testing Basics) own Key
> Takeaways. Demo 21's actual file content wasn't available when this
> demo was drafted, so real recall questions aren't written here yet —
> filling this in from a plausible guess about what Demo 21 covered
> would violate the same sourcing discipline this project holds every
> other claim to. **Provide Demo 21's Key Takeaways (or full file) to
> complete this section before this demo is considered finished.**

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| Bootstrap config pattern | Design pattern, not a construct | A small, separate root config using local state, whose only job is creating a backend's own infrastructure |
| `aws_dynamodb_table` | Resource | State lock table — pre-1.11 locking mechanism, used deliberately here |
| `billing_mode = "PAY_PER_REQUEST"` | Resource argument | On-demand DynamoDB pricing — no provisioned capacity to size for a lock table this small |
| `hash_key` | Resource argument | DynamoDB's required partition key — must be named `LockID` for Terraform's locking protocol to work |
| `dynamodb_table` (backend argument) | Backend argument | Points the S3 backend at the lock table — the argument Demo 01 told you was deprecated, used here on purpose |
| First-time `terraform init` vs. `-migrate-state` | Workflow distinction | No prior state to copy — this is a fresh backend, not a migration target |

---

### Detailed Explanation of New Constructs

#### The Chicken-and-Egg Problem, Restated for Two Resources

Demo 01 introduced this problem for a single S3 bucket: `terraform
init` needs a working backend before Terraform can manage anything —
including a resource meant to create that same backend. This demo has
the identical problem, just with a second resource added: the
DynamoDB lock table has the same issue. Neither the bucket nor the
table can be created by the configuration that will use them as its
backend, for the same reason — there's nowhere for that configuration
to record "I created these" until the backend already exists.

**The standard resolution — a bootstrap config:**

```
┌──────────────────────────────────────────────────────────────────────┐
│  BOOTSTRAP CONFIG (src/bootstrap/)                                   │
│  - Uses LOCAL state — no backend block at all                        │
│  - Creates: S3 bucket (versioned, encrypted) + DynamoDB table        │
│  - Run once. Its own local state file is the one deliberate          │
│    exception to "everything lives in the remote backend" — it has   │
│    nothing else to ever track                                        │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              │ outputs: bucket name, table name
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  MAIN PROJECT CONFIG (src/phase-3-onward/)                           │
│  - backend.tf points at the bucket + table the bootstrap just made   │
│  - terraform init — FIRST TIME against this backend, not a migration │
│  - Every subsequent Phase 3+ demo (22d onward) runs against this     │
│    same backend                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

This is the same shape as Demo 01's Console-created bucket — a
resource created *outside* the configuration that will use it as a
backend — except this time the creation itself is Terraform-managed,
just by a different, smaller configuration.

---

#### Why This Backend Uses DynamoDB Locking, Not `use_lockfile`

Demo 01 taught you `use_lockfile = true` as the modern replacement for
DynamoDB-based locking, and told you not to use `dynamodb_table` in
new configurations. This demo uses `dynamodb_table` anyway. That's not
a contradiction to paper over — it's a deliberate choice specific to
this project layer, for a reason Demo 01's teaching-rep state never had:

This project-layer state backend is explicitly temporary in a
different sense than "torn down every session" — it's scheduled to
**migrate to HCP Terraform at Demo 31**, several phases from now.
Between now and then, it needs a locking mechanism that works and is
well understood — but since the whole backend gets replaced at Demo
31 anyway, there's no value in adopting the newest S3-native locking
mechanism here just to retire the entire backend a few phases later.
`aws_dynamodb_table` locking is the older, more battle-documented
pattern, and using it here sets up a genuinely useful teaching moment
at Demo 31: migrating *away* from a DynamoDB-locked S3 backend to HCP
Terraform is common, real-world work. Migrating away from
`use_lockfile` would teach the same migration mechanics with a less
representative starting point.

> **Contrast with Demo 01, stated explicitly:** Demo 01's bucket is a
> *teaching-rep* backend — it exists to teach the remote-backend
> concept once, cleanly, using the current best-practice locking
> mechanism. This demo's bucket is a *project-layer* backend with its
> own multi-phase lifecycle (bootstrap now → DynamoDB-locked → HCP
> Terraform later). Different purposes justify different choices —
> this isn't Demo 01 being outdated advice.

---

#### `aws_dynamodb_table` for State Locking

| Argument | Required | Description |
|---|---|---|
| `name` | Yes | Table name — this project uses `terraform-locks-cloudnova` |
| `billing_mode` | No (default: `PROVISIONED`) | `PAY_PER_REQUEST` — no capacity units to size; a lock table's traffic is one item per concurrent operation, never worth provisioning for |
| `hash_key` | Yes | Must be exactly `"LockID"` — Terraform's S3 backend locking protocol looks for an attribute with this specific name; any other name silently fails to lock |
| `attribute` block | Yes, one per key used | Declares the type of the hash key: `{ name = "LockID", type = "S" }` (string) |

> **Why `LockID` specifically, not a configurable name:** this isn't a
> style convention — it's hardcoded into Terraform's S3 backend
> implementation. A table without an attribute literally named
> `LockID` will create successfully but silently fail to provide
> locking, since Terraform's lock-write calls look for that exact key.

---

## Lab Step-by-Step Guide

---

## Part A — Bootstrap the Backend Infrastructure

### Step 1 — Navigate to the bootstrap directory

```bash
cd terraform-aws-mastery/phase-3-real-aws-infrastructure/22a-state-backend-bootstrap/src/bootstrap
```

### Step 2 — Create the bootstrap config files

---

#### `versions.tf` — Version constraints

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
  # No backend block — this config uses local state deliberately.
  # It creates the backend that OTHER configs will use; it can't use
  # a backend it hasn't created yet itself.
}
```

---

#### `provider.tf` — AWS provider configuration

**provider.tf:**

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
```

---

#### `variables.tf` — Input variables

**variables.tf:**

```hcl
variable "aws_region" {
  type        = string
  description = "AWS region for the state backend"
  default     = "us-east-2"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI named profile for authentication"
  default     = "default"
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique name for the project-layer state bucket"
  default     = "tfstate-cloudnova-project-163125980376-us-east-2"
  # Replace the account ID segment with your own account ID
}

variable "lock_table_name" {
  type        = string
  description = "Name of the DynamoDB table used for state locking"
  default     = "terraform-locks-cloudnova"
}
```

---

#### `main.tf` — The backend's own infrastructure

**main.tf:**

```hcl
# ── Project-layer state bucket ──────────────────────────────────────────
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  tags = {
    Name    = var.state_bucket_name
    Purpose = "terraform-state-backend"
    Project = "cloudnova-retail-store-e2e"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"   # undo-button behavior, same reasoning as Demo 01
  }

  depends_on = [aws_s3_bucket.state]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

  depends_on = [aws_s3_bucket.state]
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [aws_s3_bucket.state]
}

# ── State lock table ─────────────────────────────────────────────────────
# Deliberate use of the pre-1.11 DynamoDB locking pattern for this
# project-layer backend — see Concepts above for why this differs from
# Demo 01's use_lockfile approach.
resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"   # no capacity to size for a lock table
  hash_key     = "LockID"            # exact name required by Terraform's S3 backend

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = var.lock_table_name
    Purpose = "terraform-state-locking"
    Project = "cloudnova-retail-store-e2e"
  }
}
```

---

#### `outputs.tf` — Expose values for the main config

**outputs.tf:**

```hcl
output "state_bucket_name" {
  description = "Name of the S3 bucket created for project-layer state"
  value       = aws_s3_bucket.state.bucket
}

output "lock_table_name" {
  description = "Name of the DynamoDB table created for state locking"
  value       = aws_dynamodb_table.locks.name
}
```

### Step 3 — Initialise, plan, and apply

```bash
terraform init
terraform validate
terraform plan
```

Key section of expected output:

```
⚠️ Simulated expected output

  # aws_s3_bucket.state will be created
  # aws_s3_bucket_versioning.state will be created
  # aws_s3_bucket_server_side_encryption_configuration.state will be created
  # aws_s3_bucket_public_access_block.state will be created
  # aws_dynamodb_table.locks will be created

Plan: 5 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply
```

```
⚠️ Simulated expected output

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:
lock_table_name   = "terraform-locks-cloudnova"
state_bucket_name = "tfstate-cloudnova-project-163125980376-us-east-2"
```

> **Bolded takeaway:** this apply used **local** state, sitting right
> here in `src/bootstrap/`. That local state file is intentional and
> permanent — it's the one part of this whole project that will never
> move to the remote backend, because it's the config that creates the
> remote backend in the first place.

### Step 4 — Verify in Console

```
Console → S3 → General purpose buckets → tfstate-cloudnova-project-xxxxxxxx
  → Properties → Bucket Versioning: Enabled ✅
  → Properties → Default encryption: SSE-S3 ✅
  → Permissions → Block public access: all four ON ✅

Console → DynamoDB → Tables → terraform-locks-cloudnova
  → Partition key: LockID (String) ✅
  → Capacity mode: On-demand ✅
```

---

## Part B — Point the Main Config at the New Backend

### Step 1 — Navigate to the main project config

```bash
cd ../phase-3-onward
```

### Step 2 — Create backend.tf

Create a file **backend.tf** and add the below content:

```hcl
terraform {
  backend "s3" {
    bucket = "tfstate-cloudnova-project-163125980376-us-east-2"
    # ↑ output from Part A — the bucket the bootstrap config just created

    key    = "phase-3-onward/terraform.tfstate"
    region = "us-east-2"
    profile = "default"
    encrypt = true

    dynamodb_table = "terraform-locks-cloudnova"
    # ↑ deliberate use of the pre-1.11 locking argument — see Concepts
    # for why this project doesn't use use_lockfile here
  }
}
```

> **Deprecation notice, reproduced verbatim (Terraform S3 backend docs):**
> *"The dynamodb_table field is deprecated in favor of use_lockfile."*
> This project uses `dynamodb_table` anyway, deliberately — see Concepts
> above for why a backend with its own planned Demo 31 migration path
> doesn't gain from adopting the newest locking mechanism. This is the
> one place in the series so far where a deprecated argument is used on
> purpose rather than avoided.

### Step 3 — First-time init against the new backend

```bash
terraform init
```

```
⚠️ Simulated expected output

Initializing the backend...

Successfully configured the backend "s3"!
Terraform has been successfully initialized!
```

> **Bolded takeaway:** notice there was no "Do you want to copy
> existing state to the new backend?" prompt here, unlike Demo 01's
> `-migrate-state` run. That prompt only appears when a *prior* backend
> (local or otherwise) already has state to offer. This config has
> never had any state before this exact command — this is backend
> configuration for the first time, not a migration.

### Step 4 — Verify the lock table works

```bash
# From a second terminal, while a plan is running in the first:
terraform plan
```

```
Console → DynamoDB → Tables → terraform-locks-cloudnova → Explore table items
  → One item appears briefly during the plan/apply, keyed by LockID
  → Item disappears when the operation completes
```

---

## Cleanup

**This demo's Cleanup step is verification, not destruction.** Unlike
every prior demo, nothing built here gets torn down — see "How This
Demo's Pieces Fit Together" for why. Confirm instead that everything
is in the state it should remain in indefinitely:

```bash
cd ../bootstrap
terraform state list
# aws_s3_bucket.state
# aws_s3_bucket_versioning.state
# aws_s3_bucket_server_side_encryption_configuration.state
# aws_s3_bucket_public_access_block.state
# aws_dynamodb_table.locks
```

```
Console → S3 → tfstate-cloudnova-project-xxxxxxxx → confirm it exists ✅
Console → DynamoDB → terraform-locks-cloudnova → confirm it exists ✅
```

> ⚠️ **Do not run `terraform destroy` in either directory at the end
> of this session.** Every subsequent Phase 3+ demo depends on this
> backend still existing.

---

## What You Learned

1. ✅ The chicken-and-egg problem applies to any backend resource, not
   just a single S3 bucket — this demo extended it to a bucket-plus-table pair.
2. ✅ This project's state backend uses `aws_dynamodb_table` locking
   deliberately, because the backend itself migrates to HCP Terraform
   at Demo 31 — not because Demo 01's `use_lockfile` guidance was wrong.
3. ✅ A bootstrap config uses local state to create the infrastructure
   a different config will use as its remote backend — the standard
   resolution to the chicken-and-egg problem.
4. ✅ First-time `terraform init` against a brand-new backend prompts
   differently than `-migrate-state` against one with existing state to copy.
5. ✅ This specific resource is exempt from "torn down between
   sessions" because destroying it would destroy the state history it
   exists to protect.

**Key Takeaway:** A backend's own infrastructure can never be created
by the configuration that uses it — every remote backend this project
builds needs its own bootstrap step, and this project's specific
choice of DynamoDB-based locking here is a deliberate contrast with
Demo 01, not an inconsistency.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| Chicken-and-egg backend bootstrap pattern | TA-004 Obj 6a/6c — Backend configuration | Exam trap: "can a backend create its own storage resource?" → No, always requires an external bootstrap step |
| `aws_dynamodb_table` + `dynamodb_table` backend argument | TA-004 Obj 6b — State locking | Know this is the pre-1.11 pattern, still valid, not removed — only superseded as the *default recommendation* for new configs |
| First-time `init` vs. `-migrate-state` | TA-004 Obj 3a — Core workflow | The confirmation prompt only appears when prior state exists to copy |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Is `dynamodb_table` a removed/invalid backend argument as of Terraform 1.11?" | No — deprecated as the *recommended* default, still fully functional | Assuming deprecated means removed |
| "Can the same Terraform config create its own S3 backend bucket and use it in the same apply?" | No — the backend must exist before `init`, so it can't be created by the config using it | Assuming a `resource` block and `backend` block in the same config resolve in the right order automatically |

### Exam Task — Write a complete configuration

**Task:** Write a bootstrap configuration that creates an S3 bucket
and a DynamoDB lock table suitable for use as a Terraform S3 backend
with `dynamodb_table`-based locking.

**Block types required:** `terraform`, `provider`, `resource` (×2 core types)

**Official documentation:**
- [`aws_dynamodb_table` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table)
- [S3 backend reference](https://developer.hashicorp.com/terraform/language/backend/s3)

**What to practise:**
1. Open both pages — check the Argument Reference sections
2. Write the configuration from scratch without looking at this demo's `src/` files
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
terraform {
  required_version = "~> 1.15.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.47.0" }
  }
}

provider "aws" {
  region  = "us-east-2"
  profile = "default"
}

resource "aws_s3_bucket" "state" {
  bucket = "exam-task-state-bucket"
}

resource "aws_dynamodb_table" "locks" {
  name         = "exam-task-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

**Arguments you must know without looking up:**
- `hash_key` on the lock table must be exactly `"LockID"` — hardcoded
  into Terraform's S3 backend locking protocol
- `billing_mode = "PAY_PER_REQUEST"` avoids sizing provisioned capacity
  for a table with lock-table-scale traffic

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Error acquiring the state lock` on first-ever plan | Stale lock item left in the table from an interrupted prior operation | Confirm no apply is genuinely running, then `terraform force-unlock <ID>` |
| `ValidationException: One or more parameter values were invalid` on table create | `hash_key` doesn't match the declared `attribute` name exactly | Confirm both are exactly `"LockID"`, same case |
| `Backend configuration changed` | `backend.tf` edited after a prior `init` in `phase-3-onward/` | `terraform init -reconfigure` |
| Locking silently doesn't work, no lock item ever appears | Table's hash key isn't named `LockID` | Delete and recreate the table with the correct hash key name |

---

## Break-Fix Scenario

One deliberate error. Diagnose using `terraform validate` and
`terraform plan` — do not look at the answer first.

```bash
cd src/bootstrap/break-fix/
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

resource "aws_dynamodb_table" "locks" {
  name         = "break-fix-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockId"          # Error

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

<details>
<summary>Reveal answer — attempt diagnosis first</summary>

**Error — `hash_key = "LockId"` doesn't match the `attribute` block's `name = "LockID"`**
`terraform validate` will show: `Error: "hash_key": all indexes must
match a defined attribute`. The casing must match exactly — DynamoDB
attribute names are case-sensitive, and Terraform's own S3 backend
locking protocol requires the literal string `LockID`. Fix: change
`hash_key` to `"LockID"`, matching the `attribute` block exactly.

</details>

**Cleanup:**

```bash
cd src/bootstrap/break-fix/
terraform destroy -auto-approve
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
```

---

## Interview Prep

**Q1. A teammate asks why this project's state backend uses a DynamoDB lock table when Terraform 1.11 deprecated that in favor of `use_lockfile`. Isn't that outdated?**
Not in this case — it's a deliberate choice tied to this backend's own lifecycle, not an oversight. This project-layer backend is explicitly scheduled to migrate to HCP Terraform a few phases later, so there's little value in adopting the newest S3-native locking mechanism for a backend that's going to be replaced anyway. Using the DynamoDB pattern here also sets up a more realistic teaching moment later: migrating away from a DynamoDB-locked S3 backend to HCP Terraform is the common real-world scenario, more so than migrating away from `use_lockfile`. The team's other, longer-lived per-demo backends (like Demo 01's) correctly use `use_lockfile` — this is a case where two different backends in the same project legitimately make different choices for different reasons.

**Q2. Someone asks why you can't just add the state bucket as a `resource` block directly inside the main project's `.tf` files, alongside the `backend "s3"` block that uses it. What's actually wrong with that?**
It's a genuine circular dependency, not just an unconventional pattern. `terraform init` needs a working backend before Terraform can manage *any* resource in that configuration — including a resource meant to create the very bucket the backend block points at. There's no ordering fix within a single config that resolves this, because the backend has to be resolved before any resource graph is even built. The only way out is what this demo does: a separate, smaller configuration using its own (local) state, whose only purpose is standing up the backend's infrastructure before the main config ever tries to use it.

**Q3. Three months from now, someone asks why this specific S3 bucket and DynamoDB table were never torn down between sessions, when almost everything else in Phase 3 was. How do you explain that without it sounding like an inconsistency?**
It follows directly from what a state backend actually is: a durable record of what Terraform manages. If you destroyed and recreated this bucket and table every session, you'd destroy the version history and lock table right along with it — the same problem you'd have if a company deleted its own accounting ledger at the end of every fiscal quarter "for tidiness." The project's teardown categorization draws the line at cost, not convenience: this backend costs effectively nothing to leave standing, and there's no safety benefit to destroying it, only real risk of losing state history. The resources that do get torn down every session — the EKS cluster, NAT Gateway, RDS instance — are the ones that actually cost money to leave running.

---

## Key Takeaways

1. **A backend's own storage can never be created by the configuration
   that uses it.** This is a structural limitation, not a style choice
   — plan for a bootstrap step any time you're standing up a new
   remote backend from scratch.

2. **`dynamodb_table` locking isn't wrong just because `use_lockfile`
   is newer.** A backend with its own planned migration path (this
   project's, to HCP Terraform at Demo 31) can reasonably choose the
   older, more battle-documented mechanism instead — know the reason
   before assuming "newest is always correct."

3. **`hash_key` on a Terraform lock table must be exactly `"LockID"`.**
   This isn't configurable — Terraform's S3 backend implementation
   looks for that literal attribute name. Any other name creates a
   working DynamoDB table that silently fails to provide locking.

4. **First-time `init` and `-migrate-state` init are different
   operations with different prompts.** A confirmation to "copy
   existing state" only appears when there's existing state to copy —
   its absence here isn't a bug, it's the expected first-time path.

5. **Not every Phase 3+ resource follows the "torn down between
   sessions" default.** Check a resource's actual cost profile and
   purpose before assuming a blanket teardown policy applies — this
   demo's entire output is meant to persist indefinitely.

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws sts get-caller-identity --profile <PROFILE>` | Confirms which AWS account and identity the named profile authenticates as |
| `aws dynamodb list-tables --profile <PROFILE>` | Lists DynamoDB tables to verify the profile has the required permissions |
| `terraform init` | Downloads providers; in `bootstrap/` initialises local state, in `phase-3-onward/` configures the S3+DynamoDB backend for the first time |
| `terraform validate` | Checks configuration syntax and schema, zero API calls |
| `terraform plan` | Previews changes, including a read-only refresh |
| `terraform apply` | Applies pending changes after confirmation |
| `terraform state list` | Lists every resource address tracked in the bootstrap config's local state |
| `terraform force-unlock <ID>` | Manually releases a stuck DynamoDB lock item — confirm no real operation is running first |

---

## Next Demo

**Demo 22b — Cost Governance:** EventBridge+SNS cost-control
notification, the two-threshold AWS Budgets alarm, and interim
`tflint`/`checkov` static analysis — the second of three sub-demos
that together make up the original Demo 22 Part A bootstrap work.

---

## Appendix — Anki Cards

**22a-state-backend-bootstrap-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::22a-state-backend-bootstrap
#separator:Comma
#columns:Front,Back,Tags
"Why can't a Terraform backend's own storage resource be created by the same config that uses it as a backend?","Chicken-and-egg problem: terraform init needs a working backend before Terraform can manage any resource, including one meant to create that same backend. Requires a separate bootstrap config using a different (usually local) state.","demo22a,backend,bootstrap,ta004-obj6a"
"What must the hash_key be named on a DynamoDB table used for Terraform S3 backend locking?","Exactly LockID (case-sensitive). Hardcoded into Terraform's S3 backend locking implementation — any other name creates a working table that silently fails to lock.","demo22a,dynamodb,locking,ta004-obj6b"
"Why does this project's state backend use aws_dynamodb_table locking instead of Demo 01's use_lockfile pattern?","This backend is scheduled to migrate to HCP Terraform later in the series, so adopting the newest S3-native locking mechanism has little value for a backend being replaced anyway. DynamoDB locking is the more battle-documented pattern and sets up a realistic migration teaching moment later.","demo22a,state,locking,ta004-obj6b"
"What's the difference in prompts between first-time terraform init against a new backend and terraform init -migrate-state?","-migrate-state prompts to copy EXISTING state to the new backend. First-time init against a genuinely new backend has no such prompt, since there's no prior state anywhere to copy.","demo22a,state,init,ta004-obj3a"
"What is a bootstrap config in Terraform, and what state does it use?","A small, separate root configuration whose only job is creating a backend's own infrastructure (e.g. S3 bucket + DynamoDB table). Uses LOCAL state deliberately, since it can't use a backend it hasn't created yet.","demo22a,backend,bootstrap"
"Is dynamodb_table a removed backend argument as of Terraform 1.11?","No — deprecated as the recommended default in favor of use_lockfile, but still fully functional. Deprecated does not mean removed.","demo22a,state,locking,ta004-obj6b"
"Why is this project's state backend exempt from the Phase 3 'torn down between sessions' default?","Destroying and recreating the backend every session would destroy the state history and lock table it exists to preserve, defeating its purpose. Only cost-accruing compute/networking resources follow the every-session teardown default.","demo22a,state,teardown-policy"
```

---

## Appendix — Quiz

**22a-state-backend-bootstrap-quiz.md:**

````markdown
# Quiz — Demo 22a: State Backend Bootstrap

> Question types: True/False, Multiple Choice, Multiple Answer —
> matching the real TA-004 exam format.
> Target: 80% or above before moving to Demo 22b.

---

**Q1. (True/False)** A Terraform configuration can create its own S3
backend bucket as a `resource` block within the same configuration
that uses `backend "s3"` to point at it.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** This is a chicken-and-egg problem — `terraform init`
must resolve the backend before any resource graph is built, so the
backend's storage must already exist beforehand, created by a separate
configuration.

</details>

---

**Q2. (Multiple Choice)** What must a DynamoDB table's `hash_key` be
named for Terraform's S3 backend locking to work correctly?

- A) Any name, as long as it's consistent
- B) `TableKey`
- C) `LockID`, exactly, case-sensitive
- D) `terraform_lock`

<details>
<summary>Answer</summary>

**C.** This is hardcoded into Terraform's S3 backend implementation —
any other name (including different casing) creates a table that
applies successfully but silently fails to provide locking.

</details>

---

**Q3. (Multiple Choice)** Why does this project's state backend use
`dynamodb_table` locking instead of Demo 01's `use_lockfile = true`?

- A) `use_lockfile` doesn't work for project-layer backends
- B) This backend is scheduled to migrate to HCP Terraform later, so the older, more representative pattern is a deliberate choice, not an error
- C) DynamoDB locking is required for any backend holding more than one demo's resources
- D) `use_lockfile` was removed in the Terraform version this project uses

<details>
<summary>Answer</summary>

**B.** The choice is tied to this specific backend's planned lifecycle
— it's scheduled for replacement at Demo 31, so the newest locking
mechanism has little payoff here, and the older pattern sets up a more
realistic migration teaching moment later.

</details>

---

**Q4. (True/False)** `dynamodb_table` is a removed backend argument as
of Terraform 1.11.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** It's deprecated as the *recommended default* for new
configurations, but remains fully functional — deprecated is not the
same as removed.

</details>

---

**Q5. (Multiple Choice)** What's the key difference between a
first-time `terraform init` against a new backend and `terraform init
-migrate-state`?

- A) There is no difference — both commands behave identically
- B) `-migrate-state` prompts to copy existing state; first-time init against a genuinely new backend has nothing to copy and shows no such prompt
- C) First-time init always fails if a DynamoDB table doesn't already have items in it
- D) `-migrate-state` can only be used with local backends, never S3

<details>
<summary>Answer</summary>

**B.** The confirmation prompt exists specifically because there's
prior state to offer copying. A fresh backend, never previously used,
simply has nothing to migrate, so `init` proceeds without that prompt.

</details>

---

**Q6. (Multiple Choice)** Why isn't this demo's S3 bucket and DynamoDB
table torn down at the end of the session, unlike most Phase 3+ resources?

- A) They're too cheap to bother destroying
- B) Destroying them would destroy the state history and lock table they exist to preserve, defeating their purpose — unlike cost-accruing compute/networking resources
- C) AWS doesn't allow deleting DynamoDB tables under $1/month
- D) They're actually torn down too, just not mentioned in this demo

<details>
<summary>Answer</summary>

**B.** The teardown-between-sessions policy targets cost-accruing
resources specifically. A state backend's entire value is its
persistence — tearing it down every session would be self-defeating,
regardless of its (near-zero) cost.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 6/6 | Import Anki cards, move to Demo 22b |
| 5/6 | Review the wrong answer, then proceed |
| 4/6 | Re-read the relevant sections, retry those questions |
| Below 4/6 | Re-read the full demo before proceeding |
````