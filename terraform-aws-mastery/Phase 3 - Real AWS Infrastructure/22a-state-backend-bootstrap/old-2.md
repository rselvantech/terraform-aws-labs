# Demo 22a — State Backend Bootstrap: Project-Layer S3 Backend

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
│  that uses it as a backend — and why this project's answer reuses      │
│  Demo 01's own locking mechanism for a new, separate purpose           │
├─────────────────────────────────────────────────────────────────────────┤
│  LAB — Bootstrap config (local state) → S3 bucket → main config's      │
│  backend.tf points at it, use_lockfile = true → first-time terraform   │
│  init (not a migration — nothing was ever tracked in S3 before this)   │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- The chicken-and-egg problem: why a backend's own storage can't be
  created by the config that will use it
- The bootstrap-config pattern: a small, separate, local-state root
  config whose only job is to create the backend's infrastructure
- Reusing Demo 01's `use_lockfile = true` pattern at the project layer
  — same mechanic, new and separate backend, different purpose
- Why a `backend` block can never reference a variable, local, or
  output — and why that's the actual reason this demo's bucket name
  gets pasted in as a literal string, not wired through the way every
  other cross-config value in this series has been
- First-time `terraform init` against a freshly created backend versus
  `terraform init -migrate-state` (Demo 01) — same command family,
  different situation
- What "torn down between sessions" does *not* mean for this specific
  resource, and why

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** one resource, created once — an S3
bucket (versioned, encrypted) that will hold the project-layer state
file. Nothing else. This demo does not touch the VPC, EKS, or any part
of `retail-store-sample-app` — those all arrive in 22d and later.

**Why two separate Terraform configs exist in this one demo:** the
bootstrap config (`src/bootstrap/`) is deliberately small and uses
**local** state — it has exactly one job, creating the S3 bucket, and
once that job is done it never needs to run again except to modify
that resource directly. The main project config (`src/phase-3-onward/`,
which 22d onward will keep building into) then points its own
`backend "s3"` block at what the bootstrap config just created, with
`use_lockfile = true` for locking, and runs `terraform init` for the
first time against that backend. This is not a migration — there is no
prior state to copy, because nothing was ever tracked in S3 before this
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
  `use_lockfile = true` locking, state migration, why local state
  breaks for teams
- Demo 21 completed — most recent demo in the series
- Comfortable with the chicken-and-egg framing generally (Demo 01
  covered it for a single bucket; this demo applies the identical
  pattern at the project layer)

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | `>= 1.15.0` | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version` |

### Verify AWS Account and Permissions

**Step 1 — Confirm your profile works:**

```bash
aws sts get-caller-identity --profile default
```

**Step 2 — A cheap, harmless dry-run of this demo's actual service:**

```bash
aws s3api list-buckets --profile default
# Expected: JSON with a Buckets array — no new permissions are
# introduced by this demo beyond Demo 01's own S3 set
```

**Step 3 — Verify IAM permissions in Console:**

```
Console → IAM → Users → test → Permissions tab
  → Confirm AmazonS3FullAccess (or equivalent) is still attached ✅
```

No permissions beyond Demo 01's own S3 set are required — this demo
doesn't introduce any new AWS service.

### Versions used in this demo

| Tool | Version |
|---|---|
| Terraform | `~> 1.15.0` |
| AWS Provider | `~> 6.47.0` |

> **Versions pinned as of September 2026** — same dating convention
> as the rest of this series; check each project's own changelog
> before assuming these exact levels are still current if you're
> reading this well after that date.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain the chicken-and-egg problem for a Terraform backend and
   why it applies to any backend, at any layer of a project
2. ✅ Explain why this demo reuses Demo 01's `use_lockfile = true`
   pattern rather than treating the project-layer backend as needing
   different locking mechanics
3. ✅ Write a self-contained bootstrap config that uses local state to
   create the infrastructure a different config will use as its remote backend
4. ✅ Explain why a `backend` block can never reference a variable,
   local, or output value
5. ✅ Distinguish first-time `terraform init` against a new backend
   from `terraform init -migrate-state` against an existing one
6. ✅ Explain why this specific resource is exempt from Phase 3's
   "torn down between sessions" default

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| S3 state bucket (small file) | Covered by free tier | **$0.00** | Same profile as Demo 01's state bucket |
| **Session total** | | **~$0.00** | This resource is created once and never torn down — no ongoing per-session cost to track here |

> Always run cleanup at the end of the session. This demo has no
> teardown step — see "How This Demo's Pieces Fit Together" above for
> why.

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
    │   ├── main.tf                         # S3 bucket
    │   └── outputs.tf                      # bucket name
    └── phase-3-onward/                     # points at the bootstrap's output
        └── backend.tf                      # backend "s3" block — first-time init target
```

> **Note on repo alignment:** in the actual `cloudnova-retail-store-e2e`
> project, these paths correspond to `src/terraform/bootstrap/` and
> `src/terraform/phase-3-onward/` respectively (Solution Architecture
> §2a) — those folders were reserved in advance for exactly this demo.

---

## Recall Check — Demo 21

Answer from memory before reading anything new:

1. When would you deliberately choose `command = plan` over
   `command = apply` for a `terraform test` `run` block?
2. Does `expect_failures` pass for *any* error a `run` block produces,
   or does it require something more specific?
3. Can a `run` block's `variables` argument override values the
   configuration's own `variable` blocks declare as defaults?

<details>
<summary>Answers</summary>

1. When the resource under test is expensive or otherwise costly to
   apply for real — `plan` mode tests structurally (does the config
   produce the expected plan) without paying for or waiting on a real
   apply. Cheap resources are still worth testing with real applies.
2. Something more specific — `expect_failures` targets a genuine
   validation/precondition/postcondition failure, not any error in
   general. A test asserting `expect_failures` against, say, a syntax
   error wouldn't be testing what it claims to test.
3. Yes — a `run` block's `variables` argument supplies test-specific
   input, independent of whatever defaults the configuration itself
   declares.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| Bootstrap config pattern | Design pattern, not a construct | A small, separate root config using local state, whose only job is creating a backend's own infrastructure |
| `use_lockfile` at the project layer | Applied concept, not a new construct | The identical mechanism Demo 01 taught, reused here for a new, separate backend serving a different, ongoing purpose |
| Backend blocks are literal-only | Structural rule | No `var.*`, `local.*`, or `*.output` reference is ever valid inside a `backend` block, at any layer |
| First-time `terraform init` vs. `-migrate-state` | Workflow distinction | No prior state to copy — this is a fresh backend, not a migration target |

---

### Detailed Explanation of New Constructs

#### The Chicken-and-Egg Problem, Applied at the Project Layer

Demo 01 introduced this problem for a single S3 bucket: `terraform
init` needs a working backend before Terraform can manage anything —
including a resource meant to create that same backend. This demo has
the identical problem, just one level up: instead of a single demo's
throwaway backend, this is the project's own persistent backend, and
it still can't be created by the configuration that will use it.

**The standard resolution — a bootstrap config:**

```
┌──────────────────────────────────────────────────────────────────────┐
│  BOOTSTRAP CONFIG (src/bootstrap/)                                   │
│  - Uses LOCAL state — no backend block at all                        │
│  - Creates: S3 bucket (versioned, encrypted)                         │
│  - Run once. Its own local state file is the one deliberate          │
│    exception to "everything lives in the remote backend" — it has   │
│    nothing else to ever track                                        │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              │ output: bucket name
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  MAIN PROJECT CONFIG (src/phase-3-onward/)                           │
│  - backend.tf points at the bucket the bootstrap just made           │
│  - use_lockfile = true — the same mechanism Demo 01 taught           │
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

#### Reusing Demo 01's Locking Pattern — Same Mechanic, New Purpose

This is the same `use_lockfile = true` mechanic Demo 01 taught —
reused here to stand up the project-layer's own persistent backend,
the same way Demo 16's VPC module and Demo 19/20's ECR/ACM techniques
get reused for real, persistent infrastructure starting at Demo 22.
Demo 01's own backend was a teaching-rep, torn down at its own
Cleanup — this is a new, separate backend serving a different, ongoing
purpose.

This is worth stating explicitly because it heads off a natural
question: **didn't we already build this in Demo 01?** No — Demo 01's
backend and this demo's backend are two different S3 buckets serving
two different lifecycles. Phase 1's own milestone deliberately stayed
on local/throwaway state for its own resources and explicitly deferred
building a real, persistent backend to this demo. Nothing before this
point has created a backend meant to survive past its own demo's
session.

> **Locking mechanism, confirmed:** this project's state backend uses
> `use_lockfile = true` — the current, non-deprecated locking pattern
> — at every layer, per-demo and project-layer alike. There's no
> divergence in mechanism to track between Demo 01 and this demo, only
> a difference in what each backend is *for*.

---

#### Why a `backend` Block Can Never Reference a Variable, Local, or Output

**This is a hard, structural rule, not a stylistic choice** — and it's
the actual reason Part B's `backend.tf` pastes in the bucket name as a
literal string instead of wiring it through from the bootstrap
config's `output`, the way every other cross-config value in this
series has been connected.

Terraform must resolve the `backend` block **before** it evaluates
anything else in the configuration — before variable defaults are
read, before `.tfvars` files are loaded, before any resource graph is
built. A `var.*`, `local.*`, or module/output reference inside a
`backend` block would require Terraform to already have a working
configuration evaluation context, which doesn't exist yet at the point
the backend itself is being resolved. This is why `backend.tf`'s
`bucket` argument is the exact string Part A's `terraform output`
printed, copied by hand — not a mistake, not a shortcut, a hard
language limitation.

> **This is a frequently-tested, genuinely common exam trap.** A
> question phrased as "can `backend "s3" { bucket = var.state_bucket
> }` work?" has exactly one correct answer: no, under any
> circumstances, regardless of Terraform version. If you ever find
> yourself wanting to parameterize a backend block dynamically, the
> real-world answer is partial interpolation via `-backend-config`
> flags or a separate `.hcl` file passed to `terraform init` — not a
> `var.*` reference inside the block itself.

---

## Lab Step-by-Step Guide

---

## Part A — Bootstrap the Backend Infrastructure

Part A creates the S3 bucket itself, using a small, separate local-
state configuration — this bucket doesn't exist yet, so nothing can
use it as a backend until after this Part completes.

### Step 1 — Navigate to the bootstrap directory

```bash
cd terraform-aws-mastery/phase-3-real-aws-infrastructure/22a-state-backend-bootstrap/src/bootstrap
```

### Step 2 — Create the bootstrap config files

This step scaffolds the bootstrap configuration itself — deliberately
using local state, since it exists specifically to create the backend
that other configs will later use.

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

This file declares the region, profile, and the globally-unique bucket
name this bootstrap config will create.

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
```

---

#### `main.tf` — The backend's own infrastructure

This file contains the four resources that make up the state bucket
itself — the bucket, its versioning, its encryption, and its public
access block.

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
```

> **Nothing new here versus Demo 01's own bucket resources.** This is
> deliberate — the project-layer backend's storage needs the same
> production-grade S3 configuration any other backend needs. The only
> genuinely new content in this demo is the bootstrap-config pattern
> itself, not the S3 resource shapes.

---

#### `outputs.tf` — Expose values for the main config

This file exposes the bucket's real name, so Part B can paste it into
`backend.tf` as a literal string.

**outputs.tf:**

```hcl
output "state_bucket_name" {
  description = "Name of the S3 bucket created for project-layer state"
  value       = aws_s3_bucket.state.bucket
}
```

### Step 3 — Initialise, plan, and apply

This step initializes the bootstrap config for the first time and
creates the actual S3 bucket and its hardening settings.

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

Plan: 4 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply
```

```
⚠️ Simulated expected output

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:
state_bucket_name = "tfstate-cloudnova-project-163125980376-us-east-2"
```

> **Bolded takeaway:** this apply used **local** state, sitting right
> here in `src/bootstrap/`. That local state file is intentional and
> permanent — it's the one part of this whole project that will never
> move to the remote backend, because it's the config that creates the
> remote backend in the first place.

### Step 4 — Verify in Console

This step confirms the bucket's hardening settings are genuinely
applied in AWS, not just reported as created by Terraform.

```
Console → S3 → General purpose buckets → tfstate-cloudnova-project-xxxxxxxx
  → Properties → Bucket Versioning: Enabled ✅
  → Properties → Default encryption: SSE-S3 ✅
  → Permissions → Block public access: all four ON ✅
```

![alt text](image.png)

![alt text](image-1.png)

![alt text](image-2.png)

---

## Part B — Point the Main Config at the New Backend

Part B configures the main project config to use the bucket Part A
just created as its remote backend, for the very first time.

### Step 5 — Navigate to the main project config

```bash
cd ../phase-3-onward
```

### Step 6 — Create backend.tf

This step writes the `backend "s3"` block that every subsequent Phase
3+ demo will initialize against, using Part A's bucket name pasted in
as a literal value.

#### `backend.tf` — S3 backend


**backend.tf:**

```hcl
terraform {
  backend "s3" {
    bucket = "tfstate-cloudnova-project-163125980376-us-east-2"
    # ↑ output from Part A, pasted in as a literal string — a backend
    # block cannot reference var.*/local.*/module outputs at all, at
    # any Terraform version. See "Why a backend Block Can Never
    # Reference a Variable, Local, or Output" in Concepts above.

    key    = "phase-3-onward/terraform.tfstate"
    region = "us-east-2"
    profile = "default"
    encrypt = true

    use_lockfile = true
    # ↑ the same locking mechanism Demo 01 taught — reused here for a
    # new, separate, project-layer backend. No new locking concept to
    # learn in this demo.
  }
}
```

### Step 7 — First-time init against the new backend

This step initializes the main config against the new backend for the
very first time — genuinely different from Demo 01's migration, since
there's no prior state anywhere to copy.

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

### Step 8 — Verify the lock works

This step confirms the S3-native lock genuinely activates during a
real operation, the same mechanism Demo 01 demonstrated, now protecting
a different bucket.

```bash
# From a second terminal, while a plan is running in the first:
terraform plan
```

```
Console → S3 → tfstate-cloudnova-project-xxxxxxxx → phase-3-onward/
  → Enable "Show versions" toggle (top right of Objects tab)
  → terraform.tfstate.tflock appears briefly during the plan, then
    disappears when it completes — the same S3-native lock behavior
    Demo 01 showed you, at a different bucket
```

![alt text](image-3.png)

---

## Cleanup

**This demo's Cleanup step is verification, not destruction.** Unlike
every prior demo, nothing built here gets torn down — see "How This
Demo's Pieces Fit Together" for why. Confirm instead that everything
is in the state it should remain in indefinitely:

### Step 9 — Confirm everything is in its intended, permanent state

```bash
cd ../bootstrap
terraform state list
# aws_s3_bucket.state
# aws_s3_bucket_versioning.state
# aws_s3_bucket_server_side_encryption_configuration.state
# aws_s3_bucket_public_access_block.state
```

```
Console → S3 → tfstate-cloudnova-project-xxxxxxxx → confirm it exists ✅
```

> ⚠️ **Do not run `terraform destroy` in either directory at the end
> of this session.** Every subsequent Phase 3+ demo depends on this
> backend still existing.

---

## What You Learned

1. ✅ The chicken-and-egg problem applies to any backend resource, at
   any layer of a project — this demo applied Demo 01's own framing
   to the project's persistent backend, not a new problem.
2. ✅ `use_lockfile = true` isn't a per-demo-only pattern — it's this
   project's standing locking mechanism, reused unchanged at the
   project layer.
3. ✅ A bootstrap config uses local state to create the infrastructure
   a different config will use as its remote backend — the standard
   resolution to the chicken-and-egg problem.
4. ✅ A `backend` block can never reference a variable, local, or
   output — it's resolved before any of those exist in Terraform's
   evaluation context, at any Terraform version.
5. ✅ First-time `terraform init` against a brand-new backend prompts
   differently than `-migrate-state` against one with existing state to copy.
6. ✅ This specific resource is exempt from "torn down between
   sessions" because destroying it would destroy the state history it
   exists to preserve.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| Chicken-and-egg backend bootstrap pattern | TA-004 Obj 6a/6c — Backend configuration | Exam trap: "can a backend create its own storage resource?" → No, always requires an external bootstrap step |
| `backend` blocks cannot reference variables/locals/outputs | TA-004 Obj 6a | A near-guaranteed exam question in some form — the answer is always "no," with no version-dependent exception |
| `use_lockfile = true` reused at a new layer | TA-004 Obj 6b — State locking | Know that the same locking mechanism can back multiple, independent state files — locking is per-backend, not a project-wide singleton |
| First-time `init` vs. `-migrate-state` | TA-004 Obj 3a — Core workflow | The confirmation prompt only appears when prior state exists to copy |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Can the same Terraform config create its own S3 backend bucket and use it in the same apply?" | No — the backend must exist before `init`, so it can't be created by the config using it | Assuming a `resource` block and `backend` block in the same config resolve in the right order automatically |
| "Can `backend "s3" { bucket = var.state_bucket_name }` work, in any Terraform version?" | No, never — backend blocks only accept literal values, resolved before any variable evaluation context exists | Assuming a recent-enough Terraform version eventually added variable support to backend blocks |
| "If a project already has one `use_lockfile` backend, can another config reuse the same mechanism for a different bucket?" | Yes — locking is scoped to the individual backend's bucket, not shared or exclusive across a project | Assuming one project can only have one locked backend at a time |

### Exam Task — Write a complete configuration

**Task:** Write a bootstrap configuration that creates an S3 bucket
suitable for use as a Terraform S3 backend with `use_lockfile = true`
locking.

**Block types required:** `terraform`, `provider`, `resource` (×4, matching Demo 01's own pattern)

**Official documentation:**
- [S3 backend reference](https://developer.hashicorp.com/terraform/language/backend/s3)

**What to practise:**
1. Open the page above — check the `use_lockfile` argument specifically
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

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
  depends_on = [aws_s3_bucket.state]
}
```

**Arguments you must know without looking up:**
- `use_lockfile` is set in the *consuming* config's `backend "s3"`
  block, not in the bootstrap config that creates the bucket — the
  bootstrap config has no backend block at all
- The bootstrap config's bucket needs versioning enabled the same way
  any state bucket does, regardless of which config created it
- The consuming config's `backend "s3" { bucket = "..." }` value must
  be a literal string — never a `var.*` reference, regardless of how
  tempting it is to wire it through from the bootstrap's own output

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Error acquiring the state lock` on first-ever plan | Stale `.tflock` file left from an interrupted prior operation | Confirm no apply is genuinely running, then `terraform force-unlock <ID>` |
| `Backend configuration changed` | `backend.tf` edited after a prior `init` in `phase-3-onward/` | `terraform init -reconfigure` |
| `BucketAlreadyExists` on the bootstrap apply | S3 names are globally unique across all AWS accounts | Confirm the account ID segment in `state_bucket_name` is your own |
| `Variables not allowed` (or similar) referencing `var.*` inside `backend.tf` | Attempting to parameterize the backend block directly | Paste the literal value in instead, or use `-backend-config` flags/file passed to `terraform init` |

---

## Break-Fix Scenario

> **Why one error instead of three, starting with this demo:** every
> Break-Fix from Demo 14 through Demo 21 uses three deliberate errors,
> fixed one at a time. From this demo forward, Break-Fix uses exactly
> one. This is a deliberate adaptation to Phase 3's actual costs, not a
> simplification of the diagnostic skill being tested — Phase 3
> resources (an EKS cluster especially, at 10–15 minutes per
> apply/fix cycle) make a three-separate-failures diagnostic loop cost
> real, significant session time in a way Phase 1/2's cheaper, faster
> resources never did. The skill under test — diagnose from real
> output, fix, re-run — is identical; there's just one repetition of
> it per demo instead of three. This note isn't repeated in 22b/22c/22d
> and onward — it applies from here forward for the reason stated once,
> here.

One deliberate error. Diagnose using `terraform validate` and
`terraform plan` — do not look at the answer first.

```bash
cd src/bootstrap/break-fix/
terraform init
terraform validate
terraform plan
```

This file is a self-contained configuration with one deliberate
local-name mismatch between a bucket resource and a reference to it —
diagnose it before revealing the answer.

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

resource "aws_s3_bucket" "state" {
  bucket = "break-fix-state-bucket"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.main.id   # Error

  versioning_configuration {
    status = "Enabled"
  }
}
```

<details>
<summary>Reveal answer — attempt diagnosis first</summary>

**Error — `aws_s3_bucket.main.id`**
The bucket resource is named `state`, not `main`. Terraform will show:
`Reference to undeclared resource`. This is the same class of error
Demo 01's own break-fix taught — a local-name mismatch, not a syntax
error — worth recognizing quickly since it recurs across the series.
Fix: `aws_s3_bucket.state.id`.

</details>

**Cleanup:**

```bash
cd src/bootstrap/break-fix/
terraform destroy -auto-approve
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
```

---

## Interview Prep

**Q1. A teammate asks why this project needs a second `use_lockfile`-based S3 backend when Demo 01 already built one. Isn't that redundant?**
No — they're two different backends serving two different purposes with different lifecycles. Demo 01's backend was a teaching-rep: built to demonstrate the remote-backend concept once, then torn down at its own Cleanup like everything else in Phase 1–2. This demo's backend is the project's own persistent state store, meant to outlive every individual session from here through Demo 38. They happen to use the identical locking mechanism because that mechanism is simply the current standard — reusing it here isn't redundancy, it's consistency. If anything, having two different backends use two different locking mechanisms for no real reason would be the thing worth questioning.

**Q2. Someone asks why you can't just add the state bucket as a `resource` block directly inside the main project's `.tf` files, alongside the `backend "s3"` block that uses it. What's actually wrong with that?**
It's a genuine circular dependency, not just an unconventional pattern. `terraform init` needs a working backend before Terraform can manage *any* resource in that configuration — including a resource meant to create the very bucket the backend block points at. There's no ordering fix within a single config that resolves this, because the backend has to be resolved before any resource graph is even built. The only way out is what this demo does: a separate, smaller configuration using its own (local) state, whose only purpose is standing up the backend's infrastructure before the main config ever tries to use it.

**Q3. Three months from now, someone asks why this specific S3 bucket was never torn down between sessions, when almost everything else in Phase 3 was. How do you explain that without it sounding like an inconsistency?**
It follows directly from what a state backend actually is: a durable record of what Terraform manages. If you destroyed and recreated this bucket every session, you'd destroy its version history right along with it — the same problem you'd have if a company deleted its own accounting ledger at the end of every fiscal quarter "for tidiness." The project's teardown categorization draws the line at cost, not convenience: this backend costs effectively nothing to leave standing, and there's no safety benefit to destroying it, only real risk of losing state history. The resources that do get torn down every session — the EKS cluster, NAT Gateway, RDS instance — are the ones that actually cost money to leave running.

**Q4. A teammate wants to wire `backend.tf`'s `bucket` argument through from the bootstrap config's `output`, the way every other cross-config value in this series has been connected. Why can't that work here?**
Because a `backend` block is resolved before Terraform evaluates anything else in the configuration — before variables, before `.tfvars`, before any resource or module graph exists. There's no evaluation context yet for a `var.*` or output reference to resolve against, at any Terraform version. This is different from every other place in this series where one config's output feeds another's input (Demo 17's `module.vpc.vpc_id`, for example) — those are ordinary resource-graph references, evaluated well after the backend is already settled. The practical alternative, if a value genuinely needs to be dynamic, is `-backend-config` flags or file passed to `terraform init` — not an in-block reference.

---

## Key Takeaways

1. **A backend's own storage can never be created by the configuration
   that uses it.** This is a structural limitation, not a style choice
   — plan for a bootstrap step any time you're standing up a new
   remote backend from scratch, at any layer of a project.

2. **A `backend` block can never reference a variable, local, or
   output, at any Terraform version.** It's resolved before Terraform
   has an evaluation context for any of those — this is why this
   demo's bucket name is a pasted-in literal, not a wired-through
   reference.

3. **`use_lockfile = true` isn't tied to a single backend — it's a
   reusable mechanism.** This demo's backend and Demo 01's backend use
   it identically; what differs between them is purpose and lifecycle,
   not locking mechanics.

4. **A new backend at a new layer isn't automatically a new concept to
   learn.** Recognizing "this is the same technique, applied again for
   a different reason" is itself a skill worth building — not every
   new demo introduces genuinely new mechanics.

5. **First-time `init` and `-migrate-state` init are different
   operations with different prompts.** A confirmation to "copy
   existing state" only appears when there's existing state to copy —
   its absence here isn't a bug, it's the expected first-time path.

6. **Not every Phase 3+ resource follows the "torn down between
   sessions" default.** Check a resource's actual cost profile and
   purpose before assuming a blanket teardown policy applies — this
   demo's entire output is meant to persist indefinitely.

> **Demo scope:** Primary concept: the chicken-and-egg backend
> bootstrap pattern and why `backend` blocks can never reference a
> variable, local, or output. Supporting concepts: reusing Demo 01's
> `use_lockfile` mechanism at a new layer, first-time `init` vs.
> `-migrate-state`, the "torn down between sessions" exemption for
> this specific resource.
> Estimated completion time: 25–30 minutes.
> Checkpoints: 2 natural stopping points (end of Part A, end of
> Part B).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws sts get-caller-identity --profile <PROFILE>` | Confirms which AWS account and identity the named profile authenticates as |
| `aws s3api list-buckets --profile <PROFILE>` | Lists S3 buckets to verify the profile has the required permissions |
| `terraform init` | Downloads providers; in `bootstrap/` initialises local state, in `phase-3-onward/` configures the S3 backend for the first time |
| `terraform validate` | Checks configuration syntax and schema, zero API calls |
| `terraform plan` | Previews changes, including a read-only refresh |
| `terraform apply` | Applies pending changes after confirmation |
| `terraform state list` | Lists every resource address tracked in the bootstrap config's local state |
| `terraform force-unlock <ID>` | Manually releases a stuck lock — confirm no real operation is running first |

---

## Next Demo

**Demo 22b — Cost Governance:** EventBridge+SNS cost-control
notification, the two-threshold AWS Budgets alarm, and interim
`tflint`/`checkov` static analysis — the second of four sub-demos
that together make up the original Demo 22 Part A bootstrap work.

---

## Appendix — Anki Cards

**22a-state-backend-bootstrap-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::22a-state-backend-bootstrap
#separator:Comma
#columns:Front,Back,Tags
"Why can't a Terraform backend's own storage resource be created by the same config that uses it as a backend?","Chicken-and-egg problem: terraform init needs a working backend before Terraform can manage any resource, including one meant to create that same backend. Requires a separate bootstrap config using a different (usually local) state.","demo22a,backend,bootstrap,ta004-obj6a"
"Can a backend block ever reference a variable, local value, or module output, in any Terraform version?","No, never. A backend block is resolved before Terraform has an evaluation context for variables, locals, or outputs — every argument must be a literal value. Dynamic values go through -backend-config flags/files instead.","demo22a,backend,ta004-obj6a,gotcha"
"Does this project's project-layer state backend use a different locking mechanism than Demo 01's backend?","No. Both use use_lockfile = true, the current, non-deprecated S3-native locking mechanism. They differ in purpose and lifecycle (teaching-rep vs. persistent), not in locking mechanics.","demo22a,state,locking,ta004-obj6b"
"What's the difference in prompts between first-time terraform init against a new backend and terraform init -migrate-state?","-migrate-state prompts to copy EXISTING state to the new backend. First-time init against a genuinely new backend has no such prompt, since there's no prior state anywhere to copy.","demo22a,state,init,ta004-obj3a"
"What is a bootstrap config in Terraform, and what state does it use?","A small, separate root configuration whose only job is creating a backend's own infrastructure (e.g. an S3 bucket). Uses LOCAL state deliberately, since it can't use a backend it hasn't created yet.","demo22a,backend,bootstrap"
"Is it redundant for a project to have two separate use_lockfile-based S3 backends?","No. Locking is scoped per-backend, not shared across a project. Two backends serving different purposes and lifecycles (e.g. a per-demo teaching backend and a persistent project-layer backend) can both use the same mechanism without conflict or redundancy.","demo22a,state,locking"
"Why is this project's state backend exempt from the Phase 3 'torn down between sessions' default?","Destroying and recreating the backend every session would destroy the state history it exists to preserve, defeating its purpose. Only cost-accruing compute/networking resources follow the every-session teardown default.","demo22a,state,teardown-policy"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the individual facts
> (chicken-and-egg, locking reuse, init-vs-migrate prompts, teardown
> exemption). This Quiz instead works through Break-Fix-style
> diagnosis and the backend-literal-value rule in scenario form, so
> the two together cover recall and applied judgment without asking
> the same question twice.

**22a-state-backend-bootstrap-quiz.md:**

````markdown
# Quiz — Demo 22a: State Backend Bootstrap

> Question types: True/False, Multiple Choice, Multiple Answer —
> matching the real TA-004 exam format.
> Target: 80% or above before moving to Demo 22b.

---

**Q1. (Multiple Choice)** A teammate writes
`backend "s3" { bucket = var.state_bucket_name ... }` inside
`phase-3-onward/backend.tf`, reasoning that it would avoid pasting in
a literal string. What happens?

- A) It works, since Terraform 1.15+ added variable support to backend blocks
- B) It fails — backend blocks are resolved before any variable evaluation context exists, at any Terraform version
- C) It works only if the variable has a `default` value set
- D) It works only in the bootstrap config, never in the consuming config

<details>
<summary>Answer</summary>

**B.** This has never been supported and isn't version-dependent —
backend configuration is resolved before Terraform can evaluate
`var.*`, `local.*`, or any output reference. The only way to
parameterize it is `-backend-config` flags or files passed to
`terraform init`.

</details>

---

**Q2. (Multiple Choice)** `aws_s3_bucket_versioning.state` in
Break-Fix references `aws_s3_bucket.main.id`. What error results, and
why?

- A) `Missing required argument`, since `main` needs to be declared first
- B) `Reference to undeclared resource`, since the actual bucket resource is named `state`, not `main`
- C) No error — Terraform infers the correct resource by type
- D) `Invalid provider configuration`

<details>
<summary>Answer</summary>

**B.** This is a plain local-name mismatch — the bucket resource in
this config is `aws_s3_bucket.state`, and `main` was never declared.

</details>

---

**Q3. (Multiple Choice)** Starting with this demo, Break-Fix scenarios
use exactly one deliberate error instead of the three used in every
Phase 1/2 demo. Why the change?

- A) Phase 3 concepts are considered too advanced for multi-error diagnosis
- B) Phase 3 resources (like an EKS cluster) take far longer per apply/fix cycle, making a three-error loop cost real, significant session time — the diagnostic skill itself is unchanged
- C) Terraform's own testing tools no longer support multi-error scenarios
- D) This demo's break-fix genuinely only has one possible thing that could go wrong

<details>
<summary>Answer</summary>

**B.** This demo's own Break-Fix section states this explicitly — the
change is a cost-driven adaptation to Phase 3's much slower
apply/fix cycles, not a reduction in what's being tested.

</details>

---

**Q4. (Multiple Choice)** A team needs the same Terraform configuration
to point at a different S3 backend bucket per environment (dev/
staging/prod), without hardcoding three different `backend.tf` files.
Given backend blocks can't reference variables, what's the actual
mechanism for this?

- A) Use `count` on the `backend` block to select the right bucket
- B) Pass the differing values via `-backend-config` flags or a file, at `terraform init` time
- C) Use a `for_each` over a list of possible buckets in the backend block
- D) Backend values can't ever differ across environments — a separate root config is always required

<details>
<summary>Answer</summary>

**B.** `-backend-config` is the real, supported mechanism for
supplying backend values that differ by environment or deployment —
passed at `init` time, not referenced inside the `backend` block
itself, which stays literal-only regardless.

</details>

---

**Q5. (Multiple Choice)** This demo's bootstrap config creates four
resources for the state bucket: the bucket itself, versioning,
encryption, and a public access block. How does this compare to Demo
01's own state bucket configuration?

- A) It's a stricter, new hardening standard introduced specifically because this bucket is project-layer, not per-demo
- B) It's the same production-grade S3 configuration Demo 01's bucket already used — nothing new in the resource shapes themselves
- C) Public access blocking is skipped here since the bucket is only ever accessed by Terraform
- D) Encryption is optional here since S3 already encrypts everything by default

<details>
<summary>Answer</summary>

**B.** This demo says so explicitly — the only genuinely new content
here is the bootstrap-config pattern itself; the S3 resource shapes
are identical to what Demo 01 already taught.

</details>

---

**Q6. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements correctly describe why `phase-3-onward/backend.tf` pastes
in a literal bucket name instead of referencing Part A's `output`
directly?

- A) It's a shortcut this demo took to save time, not a requirement
- B) Backend blocks are resolved before Terraform has any evaluation context for variables, locals, or outputs
- C) A future Terraform release is expected to lift this restriction
- D) The practical alternative for dynamic backend values is `-backend-config` flags or files, not an in-block reference

<details>
<summary>Answer</summary>

**B and D.** This is a hard language limitation with no
version-dependent exception (ruling out **A** and **C**) — the real
mechanism for dynamic backend configuration is `-backend-config`, used
at `terraform init` time, not a reference inside the block itself.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 5-6/6 | Import Anki cards, move to Demo 22b |
| 4/6 | Review the wrong answers, then proceed |
| 3/6 | Re-read the relevant sections, retry those questions |
| Below 3/6 | Re-read the full demo before proceeding |
````