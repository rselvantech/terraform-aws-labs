<!--
Revision note (Track 1, aligned to SA v2.1.3 after Track 2's update log):
Applied from Track-4's 22a review: 22a-1 (prevent_destroy, SA ADR-026 amendment, now decided), 22a-4 (canonical working
directories, SA ADR-023 amendment), 22a-16 (Tier = "bootstrap"), 22a-2, 22a-3, 22a-5, 22a-6 (hypothesis, unconfirmed),
22a-8, 22a-9, 22a-11, 22a-13, 22a-14, 22a-17 (partial).
Still needs a live run: Check 1 (terraform plan -destroy, Part A Step 5), Step 6 lock test (22a-2), 22a-7 (Cleanup CLI output
is simulated), 22a-10 (account provenance). The live outputs in Part A/B predate the lifecycle block and default_tags.
Confirm with Track 2: where the built 22a code currently sits (see Directory Structure).
Not changed: 22a-12 (governance), 22a-17 depends_on cleanup (kept, matches Demo 01 pattern as written).
-->

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

That one environment is built as **two Terraform configurations with
two different lifecycles**, each with its own state file:

| Config | Directory | State key | Lifecycle |
|---|---|---|---|
| **Platform** | `platform/` | `platform/terraform.tfstate` | Created once, never torn down — cost governance (22b), ECR/ACM (22c), IAM identity (Demo 24) |
| **Workloads** | `workloads/` | `workloads/terraform.tfstate` | Torn down and re-applied every session — VPC, EKS cluster, Ingress/ALB (22d onward) |

Both state files live in **the same S3 bucket**, which this demo
creates. Only the state **key** differs. This demo builds that bucket
and points both configs at it; the resources that go into each config
arrive in later demos.

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
│  LAB — Bootstrap config (local state) → S3 bucket → platform/ and      │
│  workloads/ each get a backend.tf pointing at it under their own key,  │
│  use_lockfile = true → first-time terraform init in each (not a        │
│  migration — nothing was ever tracked in S3 before this) → watch the   │
│  lock appear, then prove it refuses a second operation                 │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- The chicken-and-egg problem: why a backend's own storage can't be
  created by the config that will use it
- The bootstrap-config pattern: a small, separate, local-state root
  config whose only job is creating the backend's infrastructure
- Reusing Demo 01's `use_lockfile = true` pattern at the project layer
  — same mechanic, new and separate backend, different purpose
- Why one S3 bucket can safely serve two independent state files, and
  why the backend's `key` argument — not a second bucket — is what
  separates the platform config's state from the workloads config's
- Why a `backend` block can never reference a variable, local, or
  output — and why that's the actual reason this demo's bucket name
  gets pasted in as a literal string, not wired through the way every
  other cross-config value in this series has been
- First-time `terraform init` against a freshly created backend versus
  `terraform init -migrate-state` (Demo 01) — same command family,
  different situation
- What "torn down between sessions" does *not* mean for this specific
  resource, and why
- Why `force_destroy = false` alone is not a guardrail on a state
  bucket, and how `prevent_destroy` closes the gap

**What this demo does NOT cover:**
- Any resource this environment will eventually run — no VPC, no EKS,
  nothing from `retail-store-sample-app`. This demo builds only the
  state backend itself.
- The actual cost-governance, ECR/ACM, or IAM resources that will
  later share `platform/`'s state — those arrive in 22b, 22c, and
  Demo 24.

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** one resource, created once — an S3
bucket (versioned, encrypted) that will hold the project-layer state
files, one per config. Nothing else. This demo does not touch the VPC,
EKS, or any part of `retail-store-sample-app` — those all arrive in
22d and later.

**Why three Terraform configs exist in this one demo:** the bootstrap
config (`bootstrap/`) is deliberately small and uses **local**
state — it has exactly one job, creating the S3 bucket, and once that
job is done it never needs to run again except to modify that resource
directly. The two project configs then each point their own
`backend "s3"` block at what the bootstrap config just created, with
`use_lockfile = true` for locking, and run `terraform init` for the
first time against that backend:

- `platform/` — everything created once and left standing. 22b,
  22c, and Demo 24 build into it.
- `workloads/` — everything torn down and re-applied every
  session. 22d and Demo 23 build into it.

Neither `init` is a migration — there is no prior state to copy,
because nothing was ever tracked in S3 before this moment. That
distinction matters: Demo 01's `terraform init -migrate-state` had
local state to carry over; this demo's `terraform init` starts from
nothing.

**Why this demo has no Cleanup that tears anything down:** unlike
every other demo before it, this demo's whole output is meant to
outlive the session. Per the project's teardown categorization
(`Solution-Architecture.md` §9/ADR-017), the state backend cannot be
destroyed and recreated every session — doing so would destroy the
very state history it exists to preserve, defeating its purpose. That
holds for the bucket regardless of which key is involved: the
workloads config's own resources are torn down every session, but the
bucket holding its state history is not. This demo ends with a
**verification** step, not a destroy step.

---

## Prerequisites

### Knowledge
- Demo 01 completed — remote S3 backends, `backend "s3"` block syntax,
  `use_lockfile = true` locking, state migration, why local state
  breaks for teams
- Demo 21 completed — most recent demo in the series
- Demo 12 completed — the `prevent_destroy` lifecycle argument, used here on the state bucket
- Comfortable with the chicken-and-egg framing generally (Demo 01
  covered it for a single bucket; this demo applies the identical
  pattern at the project layer)

### Required Tools

| Tool | Version constraint | Verify |
|---|---|---|
| Terraform CLI | `~> 1.15.0` (any 1.15.x; excludes 1.16 and later) | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version` |

### Verify AWS Account and Permissions

**Step 1 — Confirm your profile works:**

```bash
aws sts get-caller-identity --profile default --region us-east-2
```

**Step 2 — A cheap, harmless dry-run of this demo's actual service:**

```bash
aws s3api list-buckets --profile default --region us-east-2
# Expected: JSON with a Buckets array — no new permissions are
# introduced by this demo beyond Demo 01's own S3 set
```

**Step 3 — Verify IAM permissions in Console:**

```
Console → IAM → Users → test → Permissions tab
  → Confirm AmazonS3FullAccess (or equivalent) is still attached ✅
```

> 📷 [Screenshot placeholder: AWS Console → IAM → Users → test →
> Permissions tab, showing AmazonS3FullAccess attached]

No permissions beyond Demo 01's own S3 set are required — this demo
doesn't introduce any new AWS service.

### Versions used in this demo

| Tool | Version |
|---|---|
| Terraform | `~> 1.15.0` |
| AWS Provider | `~> 6.47.0` |
| AWS CLI | `>= 2.x` |

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
7. ✅ Explain why one S3 bucket can serve two independent state files
   (platform and workloads) distinguished only by the backend's `key`,
   and why that is the correct design rather than two buckets
8. ✅ Show, not just assume, that a held state lock makes a second
   operation fail
9. ✅ Explain why `force_destroy = false` alone does not protect the
   state bucket from an accidental `terraform destroy`, and how
   `prevent_destroy` does

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| S3 state bucket (small files, two keys) | Free tier covers it; pennies even outside it | **~$0.00** | Same profile as Demo 01's state bucket; two small state files in one bucket cost the same as one |
| **Session total** | | **~$0.00** | This resource is created once and never torn down — no ongoing per-session cost to track here |

> Run the verification in Part B Step 6 and the Cleanup section at the
> end of this session — this demo has no destroy step, see "How This
> Demo's Pieces Fit Together" above for why.

---

## Directory Structure

**This demo's Terraform code lives in the project's canonical working
directories, not in a copy inside the demo folder** (`Solution-Architecture.md`
§2a, ADR-023 amendment: one live working directory per state key).
Throughout this README, `bootstrap/`, `platform/` and `workloads/` mean
these three directories:

```
terraform-aws-labs/terraform-aws-mastery/cloudnova-retail-store-e2e/
└── src/
    └── terraform/
        ├── bootstrap/                      # local state — run once
        │   ├── 01-versions.tf              # terraform block + provider version
        │   ├── 02-provider.tf              # AWS provider config + Tier default tag
        │   ├── 03-variables.tf             # input variables
        │   ├── 04-main.tf                  # S3 bucket (+ prevent_destroy), versioning, encryption, access block
        │   └── 05-outputs.tf               # bucket name
        ├── platform/                       # created once, never torn down
        │   └── 01-backend.tf               # backend "s3" block — key platform/terraform.tfstate
        └── workloads/                      # torn down every session
            └── 01-backend.tf               # backend "s3" block — key workloads/terraform.tfstate
```

The demo folder itself holds only the learning material:

```
22a-state-backend-bootstrap/
├── README.md
├── 22a-state-backend-bootstrap-anki.csv   # Anki flash cards
├── 22a-state-backend-bootstrap-quiz.md    # Quiz
└── break-fix/
    └── broken.tf
```

> **Note on numbering across demos:** `platform/01-backend.tf` and
> `workloads/01-backend.tf` are each the only file in their directory
> as of this demo. 22b, 22c and Demo 24 add their own files into the
> **same** `platform/` directory, continuing the numbering from where
> this demo leaves off — not restarting at `01`, and never creating a
> second `platform/` directory with its own `backend` block. The
> numeric prefix is a teaching-order convention, not part of the
> logical file name (`01-backend.tf` is `backend.tf` in SA §2a), and
> Terraform ignores it.

> ⚠️ **If you built 22a earlier with its code inside this demo folder
> (an earlier layout used `src/` beside the README), move that code to
> the canonical directories above, or point the new work at them,
> before 22b builds on it.** Two directories pointing at the same
> `platform/terraform.tfstate` key would share one state file, which is
> the hazard Quiz Q8 describes. Moving the files does not change state:
> the state lives in S3 and in `bootstrap/`'s local `terraform.tfstate`,
> so move that file with the bootstrap directory.

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
| Backend blocks are literal-only | Structural rule | No `var.*`, `local.*`, or `*.output` reference is ever valid inside a `backend` block in Terraform |
| First-time `terraform init` vs. `-migrate-state` | Workflow distinction | No prior state to copy — this is a fresh backend, not a migration target |
| One bucket, two state keys | Design decision, not a new construct | The `key` argument in each config's `backend "s3"` block is what keeps the platform config's state and the workloads config's state separate — no second bucket needed |

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
│  BOOTSTRAP CONFIG (bootstrap/)                                       │
│  - Uses LOCAL state — no backend block at all                        │
│  - Creates: S3 bucket (versioned, encrypted)                         │
│  - Run once. Its own local state file is the one deliberate          │
│    exception to "everything lives in the remote backend" — it has   │
│    nothing else to ever track                                        │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              │ output: bucket name
                              ▼
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│  PLATFORM CONFIG                │  │  WORKLOADS CONFIG               │
│  (platform/)                    │  │  (workloads/)                   │
│  - key = platform/              │  │  - key = workloads/             │
│    terraform.tfstate            │  │    terraform.tfstate            │
│  - use_lockfile = true — the    │  │  - use_lockfile = true — same   │
│    same mechanism Demo 01       │  │    mechanism, its own lock file │
│    taught                       │  │  - terraform init — FIRST TIME  │
│  - terraform init — FIRST TIME  │  │    against this backend, not a  │
│    against this backend, not a  │  │    migration                    │
│    migration                    │  │  - Torn down and re-applied     │
│  - Created once, never torn     │  │    every session (22d onward)   │
│    down (22b, 22c, Demo 24)     │  │                                 │
└─────────────────────────────────┘  └─────────────────────────────────┘
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

#### One Bucket, Two State Keys — Why Not Two Buckets

A natural question once there are two configs with different
lifecycles: shouldn't each get its own bucket? No — one bucket with
two `key` values is the correct pattern here, not a shortcut.

The bucket's job — hold state files safely, versioned, encrypted, and
locked — doesn't change with how many state files it holds. What has
to be separated is the **state file each config reads and reconciles
against**, and the `key` argument in a `backend "s3"` block does
exactly that:

| | Platform config | Workloads config |
|---|---|---|
| Directory | `platform/` | `workloads/` |
| Backend `key` | `platform/terraform.tfstate` | `workloads/terraform.tfstate` |
| Lock file (`use_lockfile`) | `platform/terraform.tfstate.tflock` | `workloads/terraform.tfstate.tflock` |
| Torn down between sessions? | No | Yes |

Each key is its own state file with its own lock — a `plan` or
`destroy` run inside one directory can only ever see and change what
that directory's own state tracks. **That is the property this design
exists to provide:** an untargeted `terraform destroy` inside
`workloads/` at the end of a session cannot reach anything in
`platform/`'s state, because it is a different state file — not
because someone remembered to scope the command correctly.

A second bucket would add nothing to that isolation, and would mean
maintaining a second set of versioning, encryption, and public-access
settings, and a second bootstrap run, for no additional benefit. The
one thing that must never happen is two configs sharing the *same*
key — they would then read and write one state file, and each would
treat the other's resources as its own, proposing to destroy whatever
its own files don't declare (see Break-Fix-style Q8 in the Quiz).

---

#### Why a `backend` Block Can Never Reference a Variable, Local, or Output

**This is a hard, structural rule of Terraform, not a stylistic
choice** — and it's the actual reason Part B's `backend.tf` files
paste in the bucket name as a literal string instead of wiring it
through from the bootstrap config's `output`, the way every other
cross-config value in this series has been connected.

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
> }` work?" has exactly one correct answer for Terraform: no, in any
> Terraform release, including the 1.15.x this series pins. If you
> ever find yourself wanting to parameterize a backend block
> dynamically, the real-world answer is partial configuration via
> `-backend-config` flags or a separate `.hcl` file passed to
> `terraform init` — not a `var.*` reference inside the block itself.

> **Scope of this claim:** it is about Terraform, which is what this
> series and the TA-004 exam cover. OpenTofu, a separate fork, has
> relaxed this restriction in later releases (verify against its own
> documentation if you ever use it) — which is why the exam framing is
> "Terraform: no", not a universal law of infrastructure tools.

---

## Lab Step-by-Step Guide

---

## Part A — Bootstrap the Backend Infrastructure

Part A creates the S3 bucket itself, using a small, separate local-
state configuration — this bucket doesn't exist yet, so nothing can
use it as a backend until after this Part completes.

### Step 1 — Navigate to the bootstrap directory

```bash
cd terraform-aws-labs/terraform-aws-mastery/cloudnova-retail-store-e2e/src/terraform/bootstrap
```

### Step 2 — Create the bootstrap config files

This step scaffolds the bootstrap configuration itself — deliberately
using local state, since it exists specifically to create the backend
that other configs will later use.

---

#### `01-versions.tf` — Version constraints

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
  # No backend block — this config uses local state deliberately.
  # It creates the backend that OTHER configs will use; it can't use
  # a backend it hasn't created yet itself.
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
    tags = {
      Tier = "bootstrap"
    }
  }
}
```

> **Why `Tier = "bootstrap"`:** the project tags every resource with a
> `Tier` value for cost allocation and audit — `platform` and
> `workloads` for the two project configs, and `bootstrap` for the
> state backend, which is neither (ADR-023 amendment). `default_tags`
> applies it to every taggable resource this provider creates. No
> automation reads the tag; it exists so the bucket shows up under its
> own line in cost reports.

---

#### `03-variables.tf` — Input variables

This file declares the region, profile, and the globally-unique bucket
name this bootstrap config will create.

**03-variables.tf:**

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

> **Note on the account-ID segment:** the digits in this default
> aren't a technical binding between the bucket and any particular AWS
> account — in the shared global namespace this demo uses, S3 bucket
> names are unique across *all* AWS accounts, regardless of whose
> account ID appears in the string. Folding an account ID into the
> name is just a convention for making the string likely to be unique,
> nothing more. Practically: if you leave this default exactly as
> written and it happens not to collide with a bucket someone else
> already owns anywhere on AWS, `apply` will simply succeed under your
> own account — there's no silent cross-account issue to worry about.
> The only failure mode is an immediate, loud one: `BucketAlreadyExists`
> at `apply` time if the literal string is already taken (see
> Troubleshooting below). Still worth substituting your own account ID
> in for real projects, mainly to keep the name self-documenting and
> collision-unlikely on purpose, rather than by chance.

> **One qualification, checked against AWS's own documentation:**
> since March 2026, S3 also offers an opt-in *account regional
> namespace* for general purpose buckets — names of the form
> `<prefix>-<account-id>-<region>-an`, which only your own account can
> create. Inside that namespace the account-ID segment **is** enforced,
> unlike the convention described above. This demo does not use it: the
> `aws_s3_bucket` plan output in Step 3 lists a `bucket_namespace`
> attribute, and this configuration leaves it unset, so the bucket is
> created in the default shared global namespace.

---

#### `04-main.tf` — The backend's own infrastructure

This file contains the four resources that make up the state bucket
itself — the bucket, its versioning, its encryption, and its public
access block.

**04-main.tf:**

```hcl
# ── Project-layer state bucket ──────────────────────────────────────────
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  tags = {
    Name    = var.state_bucket_name
    Purpose = "terraform-state-backend"
    Project = "cloudnova-retail-store-e2e"
  }

  # Two guards on this bucket (ADR-026, amended):
  #  1. prevent_destroy rejects any plan that would destroy it, so a plain
  #     `terraform destroy` fails at PLAN time, before anything is removed.
  #  2. force_destroy is left at its default (false), so a non-empty
  #     versioned bucket still refuses deletion (BucketNotEmpty) if this
  #     lifecycle block is ever removed.
  lifecycle {
    prevent_destroy = true
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

> **Why two guards, not one.** The versioning, encryption and
> public-access-block resources below all depend on the bucket, so in
> Terraform's normal dependency order a plain `destroy` would remove
> **them first** and only then try the bucket — and fail on
> `BucketNotEmpty`, leaving a state bucket with its protections
> stripped (the provider documents that deleting
> `aws_s3_bucket_versioning` suspends versioning on the bucket).
> Right after Part A the bucket is also still empty, so a destroy at
> that point would simply succeed. `prevent_destroy` stops the whole
> destroy plan up front; `force_destroy = false` is the backstop if
> someone removes the lifecycle block. Part A Step 5 shows the guard
> working. Demo 12 taught the argument itself.

> **Nothing new here versus Demo 01's own bucket resources, apart from
> the lifecycle block.** This is
> deliberate — the project-layer backend's storage needs the same
> production-grade S3 configuration any other backend needs. The only
> genuinely new content in this demo is the bootstrap-config pattern
> itself, not the S3 resource shapes.

---

#### `05-outputs.tf` — Expose values for the main config

This file exposes the bucket's real name, so Part B can paste it into
each `backend.tf` as a literal string.

**05-outputs.tf:**

```hcl
output "state_bucket_name" {
  description = "Name of the S3 bucket created for project-layer state"
  value       = aws_s3_bucket.state.bucket
}
```

### Step 3 — Initialise, plan, and apply

This step initializes the bootstrap config for the first time and
creates the actual S3 bucket and its hardening settings. This apply
creates all four resources; nothing existing is being modified.

> **Static analysis note (ADR-011):** this is the project's first real
> apply, and ADR-011 asks for `tflint` and `checkov` before every real
> apply from Demo 22 onward. They are introduced in 22b, so they were
> **not** run for this demo. 22b scans `bootstrap/` retroactively;
> expect some findings on a state bucket (for example around access
> logging or replication) and either fix them or record a deliberate
> skip — a state bucket does not need every check.

```bash
terraform init
terraform validate
terraform plan
```

> ✅ Verified against a live run. Key section of actual output
> (resource ordering in a real `plan` is alphabetical by resource
> address, not the order written in `04-main.tf` — that's Terraform's
> own behavior, not something to debug):

```
  # aws_s3_bucket.state will be created
  # aws_s3_bucket_public_access_block.state will be created
  # aws_s3_bucket_server_side_encryption_configuration.state will be created
  # aws_s3_bucket_versioning.state will be created

Plan: 4 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply
```

> ✅ Verified against a live run.

```
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

state_bucket_name = "tfstate-cloudnova-project-163125980376-us-east-2"
```

> ⚠️ The live outputs above were captured **before** the
> `prevent_destroy` block and the `Tier` default tag were added
> (ADR-026 and ADR-023 amendments). Neither changes the resource count
> on a fresh build; re-run Part A once to refresh the output. On a
> bucket that already exists, the tag change shows as one in-place
> update, not a replacement.

> **Bolded takeaway:** this apply used **local** state, sitting right
> here in `bootstrap/`. That local state file is intentional and
> permanent — it's the one part of this whole project that will never
> move to the remote backend, because it's the config that creates the
> remote backend in the first place.

> **Protect that local state file.** It is kept out of git (state can
> hold secrets), so if this machine is lost the bucket is still in AWS
> but no longer managed by any state. Copy `terraform.tfstate` from
> `bootstrap/` somewhere outside the repository after the apply. If
> it is ever lost, Demo 04's `terraform import` is the recovery path:
> re-import each of the four resources into a fresh bootstrap state.

> ⚠️ [VERIFY — root cause not isolated] The first `apply` in a real run
> against this configuration can fail with `BucketAlreadyOwnedByYou`:
>
> ```
> Error: creating S3 Bucket (tfstate-cloudnova-project-163125980376-us-east-2):
> operation error S3: CreateBucket, https response error StatusCode: 409, ...
> BucketAlreadyOwnedByYou: Your previous request to create the named bucket
> succeeded and you already own it.
> ```
>
> A second, immediate `terraform apply` created all four resources
> cleanly (`aws_s3_bucket.state: Creation complete after 1s`). AWS's
> own S3 documentation describes this error as "the bucket already
> exists and you own it" (returned in every Region except us-east-1,
> where the legacy behavior is `200 OK`) — yet the retry's `CreateBucket`
> call succeeded, so the state of that name at the moment of the first
> call isn't explained by what the error says. One candidate cause,
> **unconfirmed**: a bucket with this exact name may have been deleted
> shortly before the run (for example by an earlier build of this
> demo), and S3 can lag in releasing a deleted name. Two checks tell
> you which situation you're in before you decide anything:
>
> ```bash
> aws s3api head-bucket --bucket <YOUR_22A_STATE_BUCKET_NAME> --region us-east-2 --profile default
> terraform state list
> ```
>
> `head-bucket` returning a `404` means the bucket doesn't exist and a
> plain re-run of `terraform apply` is the whole fix. If instead
> `head-bucket` succeeds while `terraform state list` is empty, the
> bucket exists in your account but Terraform isn't tracking it —
> Demo 04's `terraform import` is the standard tool for that case (not
> exercised in this demo).

### Step 4 — Verify in Console

This step confirms the bucket's hardening settings are genuinely
applied in AWS, not just reported as created by Terraform.

```
Console → S3 → General purpose buckets → tfstate-cloudnova-project-xxxxxxxx
  → Properties → Bucket Versioning: Enabled ✅
  → Properties → Default encryption: SSE-S3 ✅
  → Permissions → Block public access: all four ON ✅
```

> 📷 [Screenshot placeholder: AWS Console → S3 → bucket → Properties
> tab, Bucket Versioning: Enabled]

> 📷 [Screenshot placeholder: AWS Console → S3 → bucket → Properties
> tab, Default encryption: SSE-S3 (Amazon S3 managed keys)]

> 📷 [Screenshot placeholder: AWS Console → S3 → bucket → Permissions
> tab, Block all public access: On, all four settings checked]

### Step 5 — Prove the destroy guard (read-only)

This step shows that an accidental `destroy` in `bootstrap/` would be
refused, without destroying anything. `terraform plan -destroy` only
*previews* a destroy — it changes nothing. **Never run `terraform
destroy` here to test this.**

```bash
terraform plan -destroy
```

> ⚠️ [VERIFY — not yet run] Expected: the plan fails with an error of
> the form `Instance cannot be destroyed`, naming
> `aws_s3_bucket.state` and `lifecycle.prevent_destroy`, and lists no
> resources for destruction. Paste the real output here.

**Optional — see what the guard is protecting against.** Comment out
the `lifecycle` block in `04-main.tf`, run `terraform plan -destroy`
again (still read-only), and note which resources it plans to destroy.
Expected: all four. Restore the block immediately afterwards and
re-run `terraform plan -destroy` to confirm the error is back. The
point of the comparison is the ordering: without the guard, the
versioning, encryption and access-block resources are destroyed first.

> ⚠️ [VERIFY — not yet run] Whether the plan lists all four, and in
> which order, is the behaviour Track-4's review argued from Terraform's
> dependency rules and the provider's documentation; it has not been
> demonstrated on this bucket.

---

## Part B — Point Both Project Configs at the New Backend

Part B configures the two project configs — platform and workloads —
to use the bucket Part A just created as their remote backend, each
for the very first time, each under its own state key. Each config
gets its own create-file step and its own init, plan, and apply, so
you can see exactly what each one does on its own.

### Step 1 — Create the platform backend

This step writes the `backend "s3"` block that every subsequent
platform-tier demo (22b, 22c, Demo 24) will initialize against, using
Part A's bucket name pasted in as a literal value.

```bash
mkdir -p ../platform ../workloads
cd ../platform
```

#### `01-backend.tf` — S3 backend, platform config

Create a file **01-backend.tf** and add the below content:

```hcl
terraform {
  backend "s3" {
    bucket = "tfstate-cloudnova-project-163125980376-us-east-2"
    # ↑ output from Part A, pasted in as a literal string — a backend
    # block cannot reference var.*/local.*/module outputs at all, in
    # any Terraform release. See "Why a backend Block Can Never
    # Reference a Variable, Local, or Output" in Concepts above.

    key    = "platform/terraform.tfstate"
    # ↑ this key holds everything created once and left standing —
    # cost governance (22b), ECR/ACM (22c), IAM identity (Demo 24).
    # The workloads config uses a different key in the same bucket.

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

### Step 2 — Initialise, plan, and apply the platform config

This step points the platform config at the new backend for the very
first time — genuinely different from Demo 01's migration, since
there's no prior state anywhere to copy — then runs `plan` and `apply`
to confirm the backend works end to end. Run all three from
`platform/`.

First, initialise:

```bash
terraform init
```

> ✅ Verified against a live run.

```
Initializing provider plugins found in the configuration...

Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Terraform has been successfully initialized!
```

> **Bolded takeaway:** notice there was no "Do you want to copy
> existing state to the new backend?" prompt here, unlike Demo 01's
> `-migrate-state` run. That prompt only appears when a *prior* backend
> (local or otherwise) already has state to offer. This config has
> never had any state before its own `init` — this is backend
> configuration for the first time, not a migration.

Then plan. There's nothing else in `platform/` yet besides the
backend block itself, so an empty plan is expected — not a sign
anything is missing:

```bash
terraform plan
```

> ✅ Verified against a live run.

```
No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration and found no
differences, so no changes are needed.
```

Then apply. With no changes to make, Terraform doesn't stop for an
approval prompt — it completes straight away:

```bash
terraform apply
```

> ✅ Verified against a live run.

```
No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration and found no
differences, so no changes are needed.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

> Running `apply` here is still worth doing even though it changes
> nothing: it's the first real operation to write to the new backend.
> The Console view in Step 5 shows a small `terraform.tfstate` object
> under the `platform/` key, timestamped to the same second as the
> second lock cycle — consistent with this `apply` being what wrote it.

### Step 3 — Create the workloads backend

This step writes the second `backend "s3"` block — same bucket, same
locking mechanism, a different `key`. Every subsequent workloads-tier
demo (22d, Demo 23) will initialize against it.

```bash
cd ../workloads
```

#### `01-backend.tf` — S3 backend, workloads config

Create a file **01-backend.tf** and add the below content:

```hcl
terraform {
  backend "s3" {
    bucket = "tfstate-cloudnova-project-163125980376-us-east-2"
    # ↑ the SAME bucket as platform/01-backend.tf — deliberate,
    # see "One Bucket, Two State Keys — Why Not Two Buckets" in
    # Concepts above. Still a literal string, for the same reason.

    key    = "workloads/terraform.tfstate"
    # ↑ a DIFFERENT key from the platform config — this is what keeps
    # the two state files separate. This key holds everything torn
    # down and re-applied every session: the VPC, the EKS cluster, and
    # the Ingress/ALB (22d onward).

    region = "us-east-2"
    profile = "default"
    encrypt = true

    use_lockfile = true
    # ↑ same mechanism — the lock file is per key, so this config's
    # lock (workloads/terraform.tfstate.tflock) is independent of the
    # platform config's.
  }
}
```

### Step 4 — Initialise, plan, and apply the workloads config

This step repeats Step 2 for the workloads config, against the same
bucket under its own key. The two configs are independent of each
other; neither depends on the other having run. Run all three from
`workloads/`.

```bash
terraform init
```

> ✅ Verified against a live run — same successful first-time backend
> output as Step 2, with no migration prompt:

```
Initializing provider plugins found in the configuration...

Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Terraform has been successfully initialized!
```

```bash
terraform plan
```

> ✅ Verified against a live run.

```
No changes. Your infrastructure matches the configuration.
```

```bash
terraform apply
```

> ✅ Verified against a live run.

```
No changes. Your infrastructure matches the configuration.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

> **Bolded takeaway — worth internalizing before 22b/22c:** from this
> point forward, `terraform plan`/`apply`/`destroy` run **inside
> `platform/`** can only ever see and change resources declared in
> `platform/`'s own `.tf` files and tracked in
> `platform/terraform.tfstate` — it has no visibility into anything
> tracked under the `workloads/` key, and vice versa. That separation
> is a property of using two state files, not a naming convention
> someone has to remember to follow.

### Step 5 — Observe the lock lifecycle

This step shows the S3-native lock appearing and being released
during real operations — the same mechanism Demo 01 demonstrated, now
protecting a different bucket. It shows a lock being **taken and
released**; Step 6 shows a held lock **refusing** a second operation.

> ✅ Verified against a live run, for the create-then-release lock
> cycle described below. With "Show versions" enabled, `platform/`
> holds a single `terraform.tfstate` version (181 B) and two
> create-then-release cycles of `terraform.tfstate.tflock` — each a
> lock object with a delete marker above it. The first lock was held
> for about one second, the second was released within the same second
> it was taken, and the state object carries the same timestamp as the
> second cycle — consistent with the `plan` and `apply` run in Step 2,
> in that order.

```
Console → S3 → tfstate-cloudnova-project-xxxxxxxx
  → Objects tab (Show versions off): exactly two prefixes, platform/
    and workloads/ — one bucket, two state keys ✅
  → platform/ → enable the "Show versions" toggle (top right of the
    Objects tab)
  → terraform.tfstate.tflock appears as lock versions, each with a
    delete marker above it (one create-then-release pair per plan or
    apply you ran), next to a single terraform.tfstate version ✅
```

With "Show versions" **off**, `terraform.tfstate.tflock` is only visible
while an operation is holding it. With it **on**, every finished
operation stays visible as history — a lock version plus a delete
marker.

> 📷 [Screenshot placeholder: AWS Console → S3 → bucket → Objects tab,
> Show versions off, showing exactly two prefixes: platform/ and
> workloads/]

> 📷 [Screenshot placeholder: AWS Console → S3 → bucket → platform/ →
> Objects tab, Show versions on, showing one terraform.tfstate version
> and terraform.tfstate.tflock as two lock versions each followed by a
> delete marker]

> Only `platform/` was opened at the version level for this
> screenshot; `workloads/` is expected to look the same and is
> confirmed here only as an existing prefix.

### Step 6 — Prove the lock refuses a second operation

A single, uncontended command takes and releases its lock in about a
second, so you can't catch contention by hand in this demo — both
configs are empty and `apply` never pauses at an approval prompt. This
step makes the contention deterministic instead: you place a lock
object in S3 yourself, in the format Terraform writes, and watch
Terraform refuse to run against it. `platform/` has no resources,
so nothing real is at risk. Run it only when no other Terraform
operation is running against `platform/`.

> ⚠️ [VERIFY — not yet run] The expected outputs below are what this
> step should produce; replace them with a pasted real run. If the
> first `plan` fails with a parse error on the lock object instead,
> paste the error: it still shows the lock object blocks the
> operation, and the JSON fields below are the thing to adjust.

```bash
cd ../platform
BUCKET=$(cd ../bootstrap && terraform output -raw state_bucket_name)
echo "$BUCKET"

printf '%s' '{"ID":"22a-fake-lock","Operation":"OperationTypePlan","Info":"","Who":"demo-22a@test","Version":"1.15.0","Created":"2026-09-30T00:00:00Z","Path":"platform/terraform.tfstate"}' \
  | aws s3 cp - "s3://${BUCKET}/platform/terraform.tfstate.tflock" --region us-east-2 --profile default

terraform plan
```

Expected: `terraform plan` refuses to run and prints
`Error acquiring the state lock`, with a Lock Info section showing the
ID `22a-fake-lock`.

Now release it the way you would a real stale lock — the same command
the Troubleshooting table lists — and confirm Terraform works again:

```bash
terraform force-unlock -force 22a-fake-lock
terraform plan
```

Expected: the second `plan` finishes with `No changes.`

> This proves a lock object in S3 stops a second operation, which is
> the property that matters. The object here was written by hand, so
> it doesn't by itself prove that a *running* `plan` creates one —
> Step 5's lock versions show that. Together the two steps cover both
> halves.

---

## Cleanup

> Run this after completing the demo to avoid ongoing AWS charges. This
> demo's Cleanup step is verification, not destruction — see "How This
> Demo's Pieces Fit Together" for why. Nothing built here gets torn
> down; confirm instead that everything is in the state it should
> remain in indefinitely.

### Confirm everything is in its intended, permanent state

This step checks the same thing three ways — from Terraform's own
state, from the AWS CLI, and from the Console — so a discrepancy
between any two of them is visible.

**Terraform's view.** Start with the bootstrap config, which tracks the
bucket:

```bash
cd ../bootstrap
terraform state list
```

> ✅ Verified against a live run.

```
aws_s3_bucket.state
aws_s3_bucket_public_access_block.state
aws_s3_bucket_server_side_encryption_configuration.state
aws_s3_bucket_versioning.state
```

Then the two project configs, which have no resources of their own yet:

```bash
cd ../platform
terraform state list

cd ../workloads
terraform state list
```

> ✅ Verified against a live run — no output from either command:
> nothing has been built into `platform/` (22b will) or
> `workloads/` (22d will), so there is nothing for either state to
> list yet.

**The AWS CLI's view.** These three commands are the ones worth
memorising for any state bucket, from the bootstrap directory where the
bucket name output lives:

```bash
cd ../bootstrap
BUCKET=$(terraform output -raw state_bucket_name)

# Does the bucket exist, and can this profile reach it?
aws s3api head-bucket --bucket "$BUCKET" --region us-east-2 --profile default

# Is versioning still on? State history depends on it.
aws s3api get-bucket-versioning --bucket "$BUCKET" --region us-east-2 --profile default

# Are both state keys actually there?
aws s3api list-objects-v2 --bucket "$BUCKET" --region us-east-2 --profile default \
  --query 'Contents[].Key'
```

> ⚠️ Simulated expected output — not from a live terminal run. Run the
> three commands above and replace this block with the real output:

```
head-bucket:          succeeds (exit status 0), silently or with a small JSON summary
get-bucket-versioning: { "Status": "Enabled" }
list-objects-v2:      [ "platform/terraform.tfstate", "workloads/terraform.tfstate" ]
```

`list-objects-v2` shows only current object versions, so a released
lock (a delete-marked `.tflock`) doesn't appear in it — the two state
keys are what remain. It only lists both keys if Steps 2 and 4 each ran
their `apply`. If you ran Step 6, a leftover `platform/terraform.tfstate.tflock`
here means the fake lock was not released — run the `force-unlock`
from that step.

<details>
<summary>Additional flags (reference, not required)</summary>

```bash
# Encryption and public-access settings, checked from the CLI
aws s3api get-bucket-encryption --bucket "$BUCKET" --region us-east-2 --profile default \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm'
# expected: "AES256"

aws s3api get-public-access-block --bucket "$BUCKET" --region us-east-2 --profile default \
  --query 'PublicAccessBlockConfiguration'
# expected: all four settings true

# Lock and state history under one key, including delete markers — the CLI
# equivalent of Step 5's "Show versions" view
aws s3api list-object-versions --bucket "$BUCKET" --prefix platform/ \
  --region us-east-2 --profile default \
  --query '{Versions: Versions[].Key, DeleteMarkers: DeleteMarkers[].Key}'
```

> ⚠️ Simulated expected output — not from a live terminal run: `Versions`
> listing `platform/terraform.tfstate` once and
> `platform/terraform.tfstate.tflock` per lock cycle, and
> `DeleteMarkers` listing `platform/terraform.tfstate.tflock` once per
> release.

</details>

**The Console's view:**

```
Console → S3 → tfstate-cloudnova-project-xxxxxxxx → confirm it exists ✅
  → Objects tab: both platform/ and workloads/ prefixes present ✅
    (see the Step 5 screenshots)
```

> ⚠️ **Do not run `terraform destroy` in any of the three directories
> at the end of this session.** Every subsequent Phase 3+ demo depends
> on this backend still existing.

> **This bucket is guarded twice (ADR-026, amended).**
> `aws_s3_bucket.state` carries `lifecycle { prevent_destroy = true }`
> **and** leaves `force_destroy` at its default (`false`).
> `prevent_destroy` makes a plain `terraform destroy` in `bootstrap/`
> fail at plan time with nothing removed; `force_destroy = false` makes
> a non-empty versioned bucket refuse deletion (`BucketNotEmpty`) if the
> lifecycle block is ever taken out. Either alone leaves a gap:
> `force_destroy = false` by itself would not stop Terraform destroying
> the versioning, encryption and access-block resources first, and
> while the bucket is still empty (right after Part A) a destroy would
> simply succeed.

> **Genuine, full project reset only — never a normal session
> boundary.** In order: (1) destroy whatever `workloads/` and
> `platform/` manage, because deleting the bucket deletes their state
> history too; (2) remove the `prevent_destroy` block from
> `04-main.tf` — a deliberate, visible edit; (3) empty every object
> version and delete marker (commands below), since every state write
> and lock create/release leaves versions behind; (4) `terraform
> destroy` in `bootstrap/`. **Never use `-target` in `bootstrap/`:**
> `prevent_destroy` does not stop a targeted destroy of one of the
> dependent sub-resources, and it does not protect a resource block
> that has been deleted from the configuration. Deleting a bucket in
> the shared global namespace also releases its name — per AWS's own
> documentation, another account can register it afterwards, so a
> reset that wants the same name back isn't guaranteed to get it.

> **This is a deliberate asymmetry with Demo 22c's
> `repository_force_delete = true` (ADR-026), not an inconsistency.**
> 22c's ECR repos set that argument specifically so a genuine
> `terraform destroy` can remove them cleanly, images included. This
> bucket does the opposite on purpose. The two resources look alike —
> both refuse to delete while non-empty — but what each one holds is
> not interchangeable. ECR's images are disposable; 22c re-pulls and
> re-pushes them from the public gallery in minutes. This bucket holds
> `platform/terraform.tfstate` and `workloads/terraform.tfstate` — the
> entire persistent build's only record of what exists, with no
> "re-derive it" path if it's lost. Setting `force_destroy = true`
> here would remove the backstop, and dropping `prevent_destroy` would
> remove the first guard. The manual steps above are the intended path
> for a genuine reset, not a gap waiting to be automated.

<details>
<summary>Additional flags (reference, not required) — emptying the versioned bucket</summary>

```bash
aws s3api list-object-versions --bucket <YOUR_22A_STATE_BUCKET_NAME> \
  --region us-east-2 --profile default --output json \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' > /tmp/versions.json
aws s3api delete-objects --bucket <YOUR_22A_STATE_BUCKET_NAME> \
  --region us-east-2 --profile default --delete file:///tmp/versions.json

aws s3api list-object-versions --bucket <YOUR_22A_STATE_BUCKET_NAME> \
  --region us-east-2 --profile default --output json \
  --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' > /tmp/markers.json
aws s3api delete-objects --bucket <YOUR_22A_STATE_BUCKET_NAME> \
  --region us-east-2 --profile default --delete file:///tmp/markers.json
```

If either `list-object-versions` returns no entries, that `delete-
objects` call errors on the empty list — skip it. Then, with the
`prevent_destroy` block removed, `terraform destroy` in `bootstrap/`
succeeds. These commands are sized for
lab-scale state (well under 1,000 versions per call).

</details>

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
   output in Terraform — it's resolved before any of those exist in
   Terraform's evaluation context, in any Terraform release.
5. ✅ First-time `terraform init` against a brand-new backend prompts
   differently than `-migrate-state` against one with existing state to copy.
6. ✅ This specific resource is exempt from "torn down between
   sessions" because destroying it would destroy the state history it
   exists to preserve.
7. ✅ One S3 bucket can serve two independent state files, distinguished
   only by the backend's `key` argument — and that separation, not a
   naming convention, is what keeps a `destroy` run against the
   workloads config from ever reaching the platform config's resources.
8. ✅ A held state lock makes a second operation fail with `Error
   acquiring the state lock`, and `terraform force-unlock` is the
   release path for a stale one.
9. ✅ `force_destroy = false` alone does not protect a state bucket: a
   destroy can strip the dependent versioning, encryption and
   access-block resources before failing on the bucket. `prevent_destroy`
   rejects the whole destroy plan up front, and `force_destroy = false`
   stays as the backstop.

**Key Takeaway:** a state backend's own storage can never be created
by the configuration that uses it, and once that backend exists, the
`key` argument — not a second bucket, not a documented convention — is
what actually keeps two independently-lifecycled configs from ever
reaching each other's resources.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| Chicken-and-egg backend bootstrap pattern | TA-004 Obj 6a/6c (backend configuration) | Exam trap: "can a backend create its own storage resource?" → No, always requires an external bootstrap step |
| `backend` blocks cannot reference variables/locals/outputs | TA-004 Obj 6a (backend configuration) | A near-guaranteed exam question in some form — for Terraform the answer is always "no," with no release-dependent exception |
| `use_lockfile = true` reused at a new layer | TA-004 Obj 6b (state locking) | Know that the same locking mechanism can back multiple, independent state files — locking is per-backend, not a project-wide singleton |
| First-time `init` vs. `-migrate-state` | TA-004 Obj 3a (core workflow) | The confirmation prompt only appears when prior state exists to copy |
| Two configs sharing one bucket via different `key` values | TA-004 Obj 6a/6b (backend configuration, state locking) | Each `key` is its own state file with its own lock; the same `key` in two configs means one shared state file |
| `terraform force-unlock <ID>` | TA-004 Obj 6b (state locking) | Releases a stale lock; confirm no real operation is running first |
| `lifecycle { prevent_destroy = true }` | TA-004 lifecycle meta-arguments (Demo 12) | Rejects any plan that would destroy the resource, at plan time; does not stop `-target` on a dependent resource and does not protect a block deleted from the configuration |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Can the same Terraform config create its own S3 backend bucket and use it in the same apply?" | No — the backend must exist before `init`, so it can't be created by the config using it | Assuming a `resource` block and `backend` block in the same config resolve in the right order automatically |
| "Can `backend "s3" { bucket = var.state_bucket_name }` work, in any Terraform release?" | No, never — backend blocks only accept literal values, resolved before any variable evaluation context exists | Assuming a recent-enough Terraform release eventually added variable support to backend blocks |
| "If a project already has one `use_lockfile` backend, can another config reuse the same mechanism for a different bucket?" | Yes — locking is scoped to the individual backend's bucket, not shared or exclusive across a project | Assuming one project can only have one locked backend at a time |
| "Does an account-ID-shaped segment in a bucket name actually bind that bucket to a specific AWS account?" | No, in the default shared global namespace — S3 bucket names there are unique across all AWS accounts; the segment is just a human convention for avoiding collisions | Assuming a naming convention is an enforced technical constraint |
| "Two configs point at the same bucket with different `key` values — do they share state or a lock?" | No — each `key` is a separate state file, and `use_lockfile` creates a separate lock object per key | Assuming one bucket means one shared state, or one shared lock |
| "A state bucket has `force_destroy = false`. Is a `terraform destroy` therefore harmless?" | No — dependent resources (versioning, encryption, access block) can be destroyed first and the destroy then fail on the bucket; `prevent_destroy` rejects the plan before anything is removed | Assuming the bucket's refusal to delete protects everything around it |

### Exam Task — Write a complete configuration

**Task:** Write a bootstrap configuration that creates an S3 bucket
suitable for use as a Terraform S3 backend with `use_lockfile = true`
locking.

**Block types required:** `terraform`, `provider`, `resource` (×4, matching Demo 01's own pattern)

**Official documentation:**
- [S3 backend reference](https://developer.hashicorp.com/terraform/language/backend/s3)

**What to practise:**
1. Open the page above — check the `use_lockfile` argument specifically
2. Write the configuration from scratch without looking at this demo's files
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
  bucket = "<your-globally-unique-bucket-name>"   # S3 names are global; pick your own
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
| `Error acquiring the state lock` on first-ever plan | Stale `.tflock` file left from an interrupted prior operation (or the deliberate fake lock from Part B Step 6 that was not released) | Confirm no apply is genuinely running, then `terraform force-unlock <ID>` |
| `Backend configuration changed` | A `backend.tf` edited after a prior `init` in `platform/` or `workloads/` | `terraform init -reconfigure` |
| `BucketAlreadyExists` on the bootstrap apply | The name is already taken by another account — in the shared global namespace this demo uses, S3 bucket names are unique across all AWS accounts, and this is the failure mode from a naming collision; anything else succeeding (even with the unmodified default literal) just means no one else has taken that exact name | Confirm the account ID segment in `03-variables.tf`'s `state_bucket_name` is your own, or otherwise change the literal to something unique |
| `BucketAlreadyOwnedByYou` (HTTP 409) on the bootstrap apply | AWS reports that a bucket with this name already exists and you own it. Observed on a real run, where an immediate re-run of `apply` succeeded; the cause of that first failure was not isolated `[UNVERIFIED]` | Run `aws s3api head-bucket` for the name and `terraform state list`: a `404` means re-run `terraform apply`; a bucket that exists but isn't in state means it needs importing (Demo 04's `terraform import`) — see Step 3 |
| `Variables not allowed` (or similar) referencing `var.*` inside a `backend.tf` | Attempting to parameterize the backend block directly | Paste the literal value in instead, or use `-backend-config` flags/file passed to `terraform init` |
| A `plan` in one config proposes changes to resources the other config declared | Both `backend.tf` files use the same `key`, so both configs are reading and writing one state file | Confirm `platform/01-backend.tf` uses `platform/terraform.tfstate` and `workloads/01-backend.tf` uses `workloads/terraform.tfstate`; if state was already written under a shared key, stop and inspect before applying anything |
| `Instance cannot be destroyed` (`lifecycle.prevent_destroy`) on `terraform destroy` or `plan -destroy` in `bootstrap/` | The state bucket's `prevent_destroy` guard is working as intended | Do not work around it at a normal session boundary; for a genuine full reset follow the ordered steps in Cleanup |
| `terraform destroy` in `bootstrap/` fails with `BucketNotEmpty` (only after the lifecycle block was removed) | The bucket is versioned and still holds object versions or delete markers — the second guard | Only relevant for a genuine full project reset — see the emptying commands in Cleanup |
| Bootstrap `terraform.tfstate` is lost | Local state was never backed up and the machine or directory is gone; the bucket still exists in AWS | Re-run `terraform init` in a fresh `bootstrap/`, then `terraform import` each of the four resources (Demo 04) |

---

## Break-Fix Scenario

One deliberate error, not three. Every Break-Fix from Demo 14 through
Demo 21 uses three deliberate errors, fixed one at a time; from this
demo forward, Break-Fix uses exactly one. This is a deliberate
adaptation to Phase 3's actual costs, not a simplification of the
diagnostic skill being tested — Phase 3 resources (an EKS cluster
especially, at 10–15 minutes per apply/fix cycle) make a
three-separate-failures diagnostic loop cost real, significant session
time in a way Phase 1/2's cheaper, faster resources never did. The
skill under test — diagnose from real output, fix, re-run — is
identical; there's just one repetition of it per demo instead of
three. This note isn't repeated in 22b and onward — it applies from
here forward for the reason stated once, here.

Diagnose from the real error — do not look at the answer first.

```bash
cd 22a-state-backend-bootstrap/break-fix/
terraform init
```

This file is a self-contained configuration with one deliberate
error in its `backend` block — it tests this demo's primary concept
directly. It points at this project's state bucket under its own
throwaway key, and you only run `init` here, never `plan` or `apply`.
Diagnose it before revealing the answer.

**break-fix/broken.tf:**

```hcl
terraform {
  required_version = "~> 1.15.0"

  backend "s3" {
    bucket       = var.state_bucket_name   # Error
    key          = "break-fix/terraform.tfstate"
    region       = "us-east-2"
    profile      = "default"
    use_lockfile = true
  }
}

variable "state_bucket_name" {
  type    = string
  default = "tfstate-cloudnova-project-163125980376-us-east-2"
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error — `var.state_bucket_name` inside the `backend` block**
A `backend` block is resolved before Terraform has any evaluation
context for variables, so a `var.*` reference is never valid there —
even though the variable has a default. `terraform init` fails with a
`Variables not allowed`-style error (the exact wording was not
captured from a live run `[UNVERIFIED]`). Note it fails at `init`, not
at `validate`, because the backend is resolved first.
Fix: replace it with the literal string, or leave the argument out and
pass it with `terraform init -backend-config="bucket=..."`. No cascade
effect — this is the only error in the file.

</details>

**Cleanup:** this file creates no resources, so there is nothing to
destroy.

```bash
cd 22a-state-backend-bootstrap/break-fix/
rm -rf .terraform .terraform.lock.hcl
```

> If you did run `plan` or `apply` after fixing it, a
> `break-fix/terraform.tfstate` object now exists in the state bucket.
> Delete it from the Console (all versions) so it doesn't sit beside
> the real state keys.

---

## Interview Prep

**Q1. A teammate asks why this project needs a second `use_lockfile`-based S3 backend when Demo 01 already built one. Isn't that redundant?**
No — they're two different backends serving two different purposes with different lifecycles. Demo 01's backend was a teaching-rep: built to demonstrate the remote-backend concept once, then torn down at its own Cleanup like everything else in Phase 1–2. This demo's backend is the project's own persistent state store, meant to outlive every individual session from here through Demo 38. They happen to use the identical locking mechanism because that mechanism is simply the current standard — reusing it here isn't redundancy, it's consistency. If anything, having two different backends use two different locking mechanisms for no real reason would be the thing worth questioning.

**Q2. Someone asks why you can't just add the state bucket as a `resource` block directly inside the main project's `.tf` files, alongside the `backend "s3"` block that uses it. What's actually wrong with that?**
It's a genuine circular dependency, not just an unconventional pattern. `terraform init` needs a working backend before Terraform can manage *any* resource in that configuration — including a resource meant to create the very bucket the backend block points at. There's no ordering fix within a single config that resolves this, because the backend has to be resolved before any resource graph is even built. The only way out is what this demo does: a separate, smaller configuration using its own (local) state, whose only purpose is standing up the backend's infrastructure before the main config ever tries to use it.

**Q3. Three months from now, someone asks why this specific S3 bucket was never torn down between sessions, when almost everything else in Phase 3 was. How do you explain that without it sounding like an inconsistency?**
It follows directly from what a state backend actually is: a durable record of what Terraform manages. If you destroyed and recreated this bucket every session, you'd destroy its version history right along with it — the same problem you'd have if a company deleted its own accounting ledger at the end of every fiscal quarter "for tidiness." The project's teardown categorization draws the line at cost, not convenience: this backend costs effectively nothing to leave standing, and there's no safety benefit to destroying it, only real risk of losing state history. The resources that do get torn down every session — the EKS cluster, NAT Gateway, RDS instance — are the ones that actually cost money to leave running.

**Q4. A teammate wants to wire `backend.tf`'s `bucket` argument through from the bootstrap config's `output`, the way every other cross-config value in this series has been connected. Why can't that work here?**
Because a `backend` block is resolved before Terraform evaluates anything else in the configuration — before variables, before `.tfvars`, before any resource or module graph exists. There's no evaluation context yet for a `var.*` or output reference to resolve against, in any Terraform release. This is different from every other place in this series where one config's output feeds another's input (Demo 17's `module.vpc.vpc_id`, for example) — those are ordinary resource-graph references, evaluated well after the backend is already settled. The practical alternative, if a value genuinely needs to be dynamic, is `-backend-config` flags or file passed to `terraform init` — not an in-block reference. (OpenTofu has relaxed this restriction, but the exam and this series are about Terraform.)

**Q5. A teammate points out that this demo's `03-variables.tf` default bucket name includes what looks like an AWS account ID, but the comment says to replace it with your own. If you don't, does `apply` actually fail?**
Not necessarily, and that's worth understanding precisely rather than assuming. In the shared global namespace this demo uses, S3 bucket names are unique across every AWS account, not scoped per-account — the account-ID-shaped digits in the default are only a convention for making the name likely to be unique, not something AWS actually checks or enforces. If the literal string happens not to already be taken by anyone, `apply` succeeds under whichever account ran it, account-ID-looking substring or not. The only real failure mode from skipping that substitution is an immediate, unambiguous `BucketAlreadyExists` error if someone else already owns that exact name — there's no silent cross-account behavior to worry about either way. (S3's newer opt-in account regional namespace is different: there the account ID segment is enforced. This demo doesn't use it.)

**Q6. A reviewer asks why the platform and workloads configs share one state bucket instead of each having its own. Wouldn't separate buckets give stronger isolation?**
Not stronger isolation of the thing that matters. What has to be separate is the state file each config reads and reconciles against, and the backend's `key` already provides that — a `plan` or `destroy` in one directory can only see what its own state file tracks. A second bucket would duplicate the versioning, encryption, and public-access configuration and a second bootstrap run, without adding any isolation the `key` doesn't already give. The real risk isn't sharing a bucket, it's sharing a *key*: two configs pointed at the same key would read and write one state file, and each would propose destroying whatever the other declared. Keeping the two keys distinct — `platform/terraform.tfstate` and `workloads/terraform.tfstate` — is the one thing that has to stay true.

**Q7. Someone says "we have `use_lockfile = true`, so concurrent runs are safe." How would you actually show that, rather than assume it?**
Make the contention happen on purpose. A single run takes and releases its lock in about a second, so you can't catch it by hand; instead, place a lock object at the key's `.tflock` path in the bucket, run `terraform plan`, and confirm it refuses with `Error acquiring the state lock` and the lock ID, then release it with `terraform force-unlock`. The version history in the Console shows the lock being created and released by real runs; the deliberate lock shows it blocking. Seeing both is what turns "it's configured" into "it works".

**Q8. The state bucket already has `force_destroy = false`. Why add `prevent_destroy` as well?**
Because `force_destroy = false` only governs the bucket resource itself. The bucket's versioning, encryption and public-access-block are separate resources that depend on it, so a plain `destroy` removes them first and only then fails on the bucket — leaving a state bucket with versioning suspended and its protections stripped. And while the bucket is still empty, the destroy would just succeed. `prevent_destroy` rejects the whole destroy plan before anything is touched; `force_destroy = false` remains as the backstop if someone removes the lifecycle block. Neither stops a `-target` destroy of a dependent resource, so the README forbids `-target` in `bootstrap/`.

---

## Key Takeaways

1. **A backend's own storage can never be created by the configuration
   that uses it, and the standard resolution is a small bootstrap
   config using local state.** This is a structural limitation, not a
   style choice — plan for a bootstrap step any time you're standing up
   a new remote backend from scratch, at any layer of a project.

2. **A `backend` block can never reference a variable, local, or
   output in Terraform.** It's resolved before Terraform has an
   evaluation context for any of those — this is why this demo's
   bucket name is a pasted-in literal, not a wired-through reference.

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

7. **Separate lifecycles get separate state files, not necessarily
   separate buckets.** One bucket with two distinct `key` values gives
   the platform config and the workloads config genuinely independent
   state and locks — and that structural separation, rather than a
   convention someone has to remember, is what stops a workloads
   teardown from ever reaching platform resources.

8. **A configured control isn't a verified control.** A lock that has
   only ever been taken and released has not been seen refusing
   anything; making it refuse on purpose is the actual check.

9. **A guardrail on one resource says nothing about the resources that
   depend on it.** `force_destroy = false` guarded the bucket but not
   the versioning, encryption and access-block resources Terraform
   removes first. `prevent_destroy` fails the whole plan instead.

> **Demo scope:** Primary concept: the chicken-and-egg backend
> bootstrap pattern and why `backend` blocks can never reference a
> variable, local, or output. Supporting concepts: reusing Demo 01's
> `use_lockfile` mechanism at a new layer, first-time `init` vs.
> `-migrate-state`, the "torn down between sessions" exemption for
> this specific resource, one bucket serving two independent state
> keys, proving the lock blocks a second operation, and guarding the
> state bucket against an accidental destroy.
> Estimated completion time: 40–45 minutes.
> Checkpoints: 2 natural stopping points (end of Part A, end of
> Part B).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws sts get-caller-identity --profile default --region us-east-2` | Confirms which AWS account and identity the named profile authenticates as |
| `aws s3api list-buckets --profile default --region us-east-2` | Lists S3 buckets to verify the profile has the required permissions |
| `terraform init` | Downloads providers; in `bootstrap/` initialises local state, in `platform/` and `workloads/` configures the S3 backend for the first time, each under its own key |
| `terraform validate` | Checks configuration syntax and schema, zero API calls |
| `terraform plan` | Previews changes, including a read-only refresh |
| `terraform plan -destroy` | Previews what a destroy would remove, without removing anything — used in `bootstrap/` to see the `prevent_destroy` guard refuse |
| `terraform apply` | Applies pending changes after confirmation — with no changes, it completes without an approval prompt |
| `terraform state list` | Lists every resource address tracked in the current config's state — the bootstrap config's local state in `bootstrap/`, the remote state for each key in `platform/` and `workloads/` |
| `terraform output -raw <NAME>` | Prints one output value with no quoting — used here to feed the bucket name into AWS CLI commands |
| `terraform force-unlock <ID>` | Manually releases a stuck lock — confirm no real operation is running first; add `-force` to skip the confirmation prompt |
| `aws s3 cp - s3://<BUCKET>/<KEY>` | Writes standard input to an S3 object — used in Step 6 to place a test lock |
| `aws s3api head-bucket --bucket <BUCKET> --region us-east-2 --profile default` | Confirms a bucket exists and the profile can reach it |
| `aws s3api get-bucket-versioning --bucket <BUCKET> --region us-east-2 --profile default` | Confirms versioning is still enabled — state history depends on it |
| `aws s3api list-objects-v2 --bucket <BUCKET> --region us-east-2 --profile default --query 'Contents[].Key'` | Lists the current objects in a bucket — here, the two state keys |
| `aws s3api list-object-versions --bucket <BUCKET> --region us-east-2 --profile default` | Lists every object version and delete marker in a versioned bucket — used to see lock history, and for a genuine full project reset to empty the state bucket before it can be destroyed |

---

## Next Demo

**Demo 22b — Cost Governance:** the cost-alert notification path as
taught content — an SNS topic with a customer-managed KMS key, the
two-threshold AWS Budgets alarm, and a one-time EventBridge Scheduler
test schedule — plus interim `tflint`/`checkov` static analysis, which
also scans this demo's `bootstrap/` retroactively. It is the first
config to write real resources into `platform/`, continuing this
demo's own file numbering from `02-` onward. The second of the three
administrative-and-setup sub-demos (22a, 22b, 22c) that precede 22d,
the first every-session demo.

---

## Appendix — Anki Cards

**22a-state-backend-bootstrap-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::22a-state-backend-bootstrap
#separator:Comma
#columns:Front,Back,Tags
"Why can't a Terraform backend's own storage resource be created by the same config that uses it as a backend?","Chicken-and-egg problem: terraform init needs a working backend before Terraform can manage any resource, including one meant to create that same backend. Requires a separate bootstrap config using a different (usually local) state.","demo22a,backend,bootstrap,ta004-obj6a"
"Can a backend block ever reference a variable, local value, or module output in Terraform?","No, never. A backend block is resolved before Terraform has an evaluation context for variables, locals, or outputs - every argument must be a literal value. Dynamic values go through -backend-config flags/files instead. (OpenTofu has relaxed this; Terraform and the exam have not.)","demo22a,backend,ta004-obj6a,gotcha"
"Does this project's project-layer state backend use a different locking mechanism than Demo 01's backend?","No. Both use use_lockfile = true, the current, non-deprecated S3-native locking mechanism. They differ in purpose and lifecycle (teaching-rep vs. persistent), not in locking mechanics.","demo22a,state,locking,ta004-obj6b"
"What's the difference in prompts between first-time terraform init against a new backend and terraform init -migrate-state?","-migrate-state prompts to copy EXISTING state to the new backend. First-time init against a genuinely new backend has no such prompt, since there's no prior state anywhere to copy.","demo22a,state,init,ta004-obj3a"
"What is a bootstrap config in Terraform, and what state does it use?","A small, separate root configuration whose only job is creating a backend's own infrastructure (e.g. an S3 bucket). Uses LOCAL state deliberately, since it can't use a backend it hasn't created yet.","demo22a,backend,bootstrap"
"Is it redundant for a project to have two separate use_lockfile-based S3 backends?","No. Locking is scoped per-backend, not shared across a project. Two backends serving different purposes and lifecycles (e.g. a per-demo teaching backend and a persistent project-layer backend) can both use the same mechanism without conflict or redundancy.","demo22a,state,locking"
"Why is this project's state backend exempt from the Phase 3 'torn down between sessions' default?","Destroying and recreating the backend every session would destroy the state history it exists to preserve, defeating its purpose. Only cost-accruing compute/networking resources follow the every-session teardown default.","demo22a,state,teardown-policy"
"Does an account-ID-shaped segment in an S3 bucket name actually bind that bucket to a specific AWS account?","Not in the default shared global namespace this demo uses: bucket names there are unique across all AWS accounts, and the segment is only a human convention for making the name likely unique, not something AWS checks. Leaving it unmodified only risks BucketAlreadyExists if someone else already owns that exact name. (The opt-in account regional namespace is different - see the namespace card.)","demo22a,s3,naming,gotcha"
"Why do the platform and workloads configs share one state bucket instead of each having its own?","The bucket's job (safe, versioned, locked storage) doesn't depend on how many state files it holds. The backend key argument is what separates the two state files, so each config can only see and change what its own state tracks. A second bucket would duplicate the bucket settings without adding isolation.","demo22a,state,backend,design"
"Do the platform and workloads configs share a state lock, given they use the same bucket?","No. use_lockfile creates one lock object per state key - platform/terraform.tfstate.tflock and workloads/terraform.tfstate.tflock - so a lock held by an operation in one directory is a different object from the other directory's lock.","demo22a,state,locking,backend"
"With versioning enabled on the state bucket, what does terraform.tfstate.tflock look like in the Console after a plan finishes, with Show versions on?","A lock object version with a delete marker above it. The lock is created when the operation starts and released (deleted) when it ends, and on a versioned bucket a delete leaves a delete marker with the earlier version still behind it. With Show versions off the lock is only visible while it is held. Each plan or apply leaves one such pair.","demo22a,state,locking,s3"
"How can you show that use_lockfile actually blocks a second operation, when a normal plan holds the lock for only about a second?","Write a lock object to the key's .tflock path in the bucket yourself (JSON with ID, Operation, Who, Version, Created, Path), then run terraform plan: it should refuse with Error acquiring the state lock and the lock ID. Release it with terraform force-unlock -force <ID>. Only do this when no real operation is running.","demo22a,state,locking,verification"
"Why does terraform destroy in the bootstrap config fail with BucketNotEmpty on the state bucket?","The bucket is versioned and holds state objects, lock objects, and delete markers written by the platform and workloads configs; S3 will not delete a bucket that still contains any object version or delete marker. Only relevant to a genuine full project reset: empty every version and delete marker first, never at a normal session boundary. This is the second guard - with prevent_destroy in place the destroy plan is rejected before this error can occur.","demo22a,s3,destroy,gotcha"
"Why does the state bucket carry prevent_destroy as well as force_destroy = false?","force_destroy = false only governs the bucket itself. Its versioning, encryption and public-access-block resources depend on it, so a destroy removes them first and only then fails on the bucket - leaving it unhardened with versioning suspended; and an empty bucket would be deleted outright. prevent_destroy rejects the whole destroy plan at plan time; force_destroy = false is the backstop if the lifecycle block is removed. Neither stops a -target destroy.","demo22a,s3,destroy,lifecycle,gotcha"
"Which Tier tag value does the bootstrap state bucket carry, and what reads it?","Tier = bootstrap, set through the provider default_tags, as a third value alongside platform and workloads. Nothing reads it: it exists for cost allocation and audit.","demo22a,tagging"
"What is the difference between the S3 CreateBucket errors BucketAlreadyExists and BucketAlreadyOwnedByYou?","Both are HTTP 409. BucketAlreadyExists means the name is taken by another account. BucketAlreadyOwnedByYou means a bucket with that name already exists and you own it (returned in every Region except us-east-1, where the legacy behavior is 200 OK). On a real run against this demo, the first apply hit BucketAlreadyOwnedByYou and an immediate re-run succeeded - the cause was not isolated.","demo22a,s3,errors,gotcha"
"What changed for S3 bucket naming in March 2026, and does this demo use it?","S3 added an opt-in account regional namespace for general purpose buckets: names of the form prefix-accountId-region-an that only your own account can create. This demo does not use it - its bucket lives in the default shared global namespace, where an account-ID-shaped segment is only a convention.","demo22a,s3,naming"
"When is terraform force-unlock appropriate, and what must you confirm first?","For a stale lock left behind by an interrupted operation, such as a killed terminal. Confirm no plan or apply is genuinely running against that state first, then pass the lock ID printed in the error message.","demo22a,state,locking,troubleshooting"
"A backend.tf is edited after an earlier init in the same directory and Terraform reports Backend configuration changed. What re-initialises it?","terraform init -reconfigure - it re-initialises against the new backend configuration without treating the change as a migration of existing state. -migrate-state is the variant that copies existing state.","demo22a,backend,init,troubleshooting"
"Where is the bootstrap config's state kept, and what happens if it is lost?","In a local terraform.tfstate in bootstrap/, deliberately never moved to the remote backend and kept out of git. If lost, the bucket still exists in AWS but is unmanaged; recover by re-running init in a fresh bootstrap directory and terraform import for each of the four resources (Demo 04). Back the file up outside the repo.","demo22a,state,bootstrap,recovery"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the individual facts
> (chicken-and-egg, locking reuse, init-vs-migrate prompts, teardown
> exemption, one bucket with two keys, lock objects and versions, the
> S3 create errors). This Quiz instead works through Break-Fix-style
> diagnosis, the backend-literal-value rule, and situations from a real
> verification run in scenario form, so the two together cover recall
> and applied judgment without asking the same question twice.

**22a-state-backend-bootstrap-quiz.md:**

````markdown
# Quiz — Demo 22a: State Backend Bootstrap

> Question types: True/False, Multiple Choice, Multiple Answer —
> matching the real TA-004 exam format.
> Target: 80% or above before moving to Demo 22b.

---

**Q1. (Multiple Choice)** A teammate writes
`backend "s3" { bucket = var.state_bucket_name ... }` inside
`platform/01-backend.tf`, reasoning that it would avoid pasting in
a literal string. What happens?

- A) It works, since Terraform 1.15+ added variable support to backend blocks
- B) It fails — backend blocks are resolved before any variable evaluation context exists, in any Terraform release
- C) It works only if the variable has a `default` value set
- D) It works only in the bootstrap config, never in the consuming config

<details>
<summary>Answer</summary>

**B.** This has never been supported in Terraform and isn't
release-dependent — backend configuration is resolved before Terraform
can evaluate `var.*`, `local.*`, or any output reference. The only way
to parameterize it is `-backend-config` flags or files passed to
`terraform init`.

</details>

---

**Q2. (Multiple Choice)** In the Break-Fix file, `terraform init` fails
on a backend block that sets `bucket = var.state_bucket_name`, even
though the variable has a default value. Which change is a correct fix?

- A) Add a second default value to the variable
- B) Replace the reference with the literal bucket name, or supply it with `-backend-config` at `init`
- C) Move the variable into a `locals` block and reference `local.state_bucket_name`
- D) Run `terraform validate` first, which resolves variables before `init`

<details>
<summary>Answer</summary>

**B.** The backend block is resolved before variables, locals or
outputs exist, so defaults don't help (**A**) and a `local.*` reference
fails for the same reason (**C**). `validate` needs an initialised
directory, so it can't run ahead of `init` here (**D**).

</details>

---

**Q3. (Multiple Choice)** Starting with this demo, Break-Fix scenarios
use exactly one deliberate error instead of the three used in every
Phase 1/2 demo. What reason does this demo give for the change?

- A) Phase 3 concepts are considered too advanced for multi-error diagnosis
- B) Phase 3 resources (like an EKS cluster) take far longer per apply/fix cycle, making a three-error loop cost real, significant session time — the diagnostic skill itself is unchanged
- C) Terraform's own testing tools no longer support multi-error scenarios
- D) This demo's break-fix genuinely only has one possible thing that could go wrong

<details>
<summary>Answer</summary>

**B.** This demo's own Break-Fix section states this explicitly — the
change is described as a cost-driven adaptation to Phase 3's much
slower apply/fix cycles, not a reduction in what's being tested.

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

**Q6. (Multiple Choice)** In Step 2 of Part B, `terraform apply` in
`platform/` finishes immediately with `No changes` and `Resources:
0 added, 0 changed, 0 destroyed`, without ever asking you to type
`yes`. What does that indicate?

- A) The backend didn't initialise correctly
- B) Nothing is wrong — the config declares only a backend block, so there is nothing to create, and Terraform doesn't ask for approval when a plan contains no changes
- C) The state lock blocked the apply
- D) `apply` needs `-auto-approve` before it will run against an S3 backend

<details>
<summary>Answer</summary>

**B.** This matches the real output for both project configs. Contrast
with the bootstrap apply in Part A Step 3, which did stop for `yes`
because it had four resources to add. Nothing about the S3 backend
requires `-auto-approve`, and a blocked lock would produce an error,
not a clean completion.

</details>

---

**Q7. (Multiple Choice)** This demo's default `state_bucket_name`
includes a segment that looks like an AWS account ID, with a comment
saying to replace it with your own. If you leave it completely
unmodified and apply, what actually determines whether it succeeds?

- A) Whether the account ID segment matches your actual AWS account
- B) Whether that exact literal bucket name string is already taken by any AWS account, anywhere
- C) Whether your IAM user has an account-ID-matching tag
- D) It will always fail unless the segment is changed

<details>
<summary>Answer</summary>

**B.** In the shared global namespace this demo uses, S3 bucket names
are unique across every AWS account — not scoped per-account — so the
only thing that determines success is whether the literal string is
already taken by *anyone*, not whether its account-ID-shaped segment
happens to match the applying account.

</details>

---

**Q8. (Multiple Choice)** A learner gives `platform/01-backend.tf`
and `workloads/01-backend.tf` the same bucket and, by copy-paste,
the same `key` (`platform/terraform.tfstate`). What is the consequence
once resources are applied?

- A) Terraform errors immediately at `init`, refusing two configs on one key
- B) Both configs read and write one state file, so each treats the other's resources as its own and a `plan` proposes destroying whatever its own files don't declare
- C) S3 automatically namespaces state by directory, so nothing changes
- D) The second `init` prompts to migrate, and answering yes merges the two safely

<details>
<summary>Answer</summary>

**B.** Nothing stops two configs from sharing a key — `init` succeeds
for both. The isolation this design provides comes entirely from the
two keys being different; with a shared key there is only one state
file, and each config reconciles against resources it never declared.

</details>

---

**Q9. (Multiple Choice)** The bootstrap `terraform apply` stops at the
bucket with `BucketAlreadyOwnedByYou` (HTTP 409), and `terraform state
list` in `bootstrap/` prints nothing. What is the sensible first
response?

- A) Run `terraform destroy` to clear whatever was half-created, then start over
- B) Check whether the bucket actually exists in your account with `head-bucket`, and whether Terraform's state has it, before choosing between re-running `apply` and importing the bucket
- C) Change the backend `key` in `platform/01-backend.tf`
- D) Set `force_destroy = true` on the bucket and re-apply

<details>
<summary>Answer</summary>

**B.** The error says a bucket with this name already exists and you
own it, but on a real run against this demo an immediate re-run of
`apply` succeeded, so the situation at that moment wasn't what the
message implies. Two quick checks separate the cases: a `404` from
`head-bucket` means a plain re-run is the fix; a bucket that exists
while state is empty means Terraform isn't tracking it and it needs
importing. There is nothing to destroy (**A**), the backend key is
unrelated to bucket creation (**C**), and `force_destroy` only affects
deletion (**D**).

</details>

---

**Q10. (Multiple Choice)** The state bucket in `bootstrap/` has
`force_destroy = false`, and its versioning, encryption and
public-access-block are separate resources that depend on it. Without
any other guard, what is the risk of running `terraform destroy` there?

- A) None — `force_destroy = false` makes the whole destroy fail immediately
- B) Terraform may remove the three dependent resources first and only then fail on the bucket, leaving it unhardened; while the bucket is still empty the destroy would simply succeed
- C) Terraform deletes the bucket but keeps the state objects
- D) The destroy waits for a lock that never releases

<details>
<summary>Answer</summary>

**B.** `force_destroy` only affects deleting the bucket resource. The
dependents are destroyed before it, in Terraform's normal order, so
their protections can be stripped before the bucket refuses. This is
why `aws_s3_bucket.state` also carries `prevent_destroy = true`, which
rejects the whole destroy plan at plan time.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 9-10/10 | Import Anki cards, move to Demo 22b |
| 8/10 | Review the wrong answers, then proceed |
| 5-7/10 | Re-read the relevant sections, retry those questions |
| Below 5/10 | Re-read the full demo before proceeding |
````