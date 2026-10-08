# Demo 22a — State Backend Bootstrap: Project-Layer S3 Backend

> **Revision note (this version) — per ADR-023, pending Track 2 final
> sign-off on the ADR text itself.** The single shared state key
> `phase-3-onward/terraform.tfstate` is retired. This bootstrap now
> serves **two** state keys instead of one — `platform/terraform.tfstate`
> and `workloads/terraform.tfstate` — living in two separate root
> configs (`src/terraform/platform/` and `src/terraform/workloads/`)
> rather than one growing directory. This bucket, its versioning, and
> its locking mechanism are otherwise **unchanged** — this demo's own
> content was never the source of the incident that prompted ADR-023;
> only what points at it downstream has changed. See the
> [Incident & Fix Appendix] (attached separately) for the full history
> of why this split exists.

---

## Overview

Every demo so far in this series has used its own throwaway state —
either local (most demos) or the single S3 backend you built yourself
in Demo 01. Phase 3 changes that. Starting now, you're building a
**persistent** environment that survives between sessions, not a fresh
teaching rep every time. That environment needs its own Terraform
state — separate from any individual demo's state — and that state
needs a home before anything else in Phase 3 can be built.

**As of this revision, "the persistent environment" is no longer one
thing — it's two, deliberately separated by lifecycle:**

| Tier | Directory | State key | Torn down between sessions? |
|---|---|---|---|
| **Platform** | `src/terraform/platform/` | `platform/terraform.tfstate` | **No** — created once, left standing (governance, registry, certs, IAM identity) |
| **Workloads** | `src/terraform/workloads/` | `workloads/terraform.tfstate` | **Yes** — every session (VPC, EKS cluster/nodes, Ingress/ALB) |

Both tiers live in **the same S3 bucket** this demo creates — only the
state **key** differs. This bootstrap step doesn't change at all; what
changes is what gets built on top of it, starting in 22b.

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
│  LAB — Bootstrap config (local state) → S3 bucket → TWO downstream     │
│  configs (platform/, workloads/) each point their own backend.tf at    │
│  this same bucket, under two different keys                            │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- The chicken-and-egg problem: why a backend's own storage can't be
  created by the config that will use it
- The bootstrap-config pattern: a small, separate, local-state root
  config whose only job is creating the backend's infrastructure
- Reusing Demo 01's `use_lockfile = true` pattern at the project layer
- Why a `backend` block can never reference a variable, local, or
  output — and why that's the actual reason this demo's bucket name
  gets pasted in as a literal string
- **New in this revision:** why one bucket safely serves two
  independent state files, as long as their keys never collide, and
  why that's the correct way to represent two genuinely different
  resource lifecycles rather than two separate buckets
- Why "torn down between sessions" now applies to the **workloads**
  key only — the platform key is exempt for the same reason this
  bucket itself always was

---

## Why Two Keys, One Bucket — Not Two Buckets

A natural question: if platform and workloads resources have such
different lifecycles, why not give each its own bucket entirely?
**One bucket, two keys is the correct and standard pattern here** —
not a shortcut. The bucket itself is infrastructure with exactly one
job (hold state files safely, with locking) and that job doesn't
change based on how many logical configs use it. What actually needs
separating is the **state file each config reads and reconciles
against** — and an S3 backend's `key` argument does exactly that,
cleanly, without needing a second bucket, a second set of versioning/
encryption/public-access settings to maintain, or a second bootstrap
run. Two buckets would be redundant infrastructure solving a problem
that a second `key` value already solves completely.

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** one resource, created once — an S3
bucket (versioned, encrypted) that will hold **both** the platform-tier
and workloads-tier state files, at two different keys. Nothing else.
This demo does not touch the VPC, EKS, or any part of
`retail-store-sample-app` — those all arrive in later demos, and now
live in a genuinely separate root config (`workloads/`) from the
governance/registry/certificate content that follows in 22b/22c
(`platform/`).

**Why two separate Terraform configs exist in this one demo, same as
before:** the bootstrap config (`src/terraform/bootstrap/`) is
deliberately small and uses **local** state — it has exactly one job,
creating the S3 bucket, and once that job is done it never needs to
run again except to modify that resource directly. **What's new:**
instead of one downstream config pointing at this bucket, there are
now two — `platform/` and `workloads/` — each with its own
`backend.tf`, each a first-time `init` against this same bucket under
its own key.

**Why this demo has no Cleanup that tears anything down:** unchanged
from the original — this bucket's whole output is meant to outlive
every session, for the same reason it always was. Per ADR-017/018
(now folded into ADR-023's platform/workloads framing), the state
backend cannot be destroyed and recreated every session without
destroying the state history it exists to preserve.

---

## Prerequisites

### Knowledge
- Demo 01 completed — remote S3 backends, `backend "s3"` block syntax,
  `use_lockfile = true` locking, state migration, why local state
  breaks for teams
- Demo 21 completed — most recent demo in the series
- Comfortable with the chicken-and-egg framing generally

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | `>= 1.15.0` | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version` |

### Verify AWS Account and Permissions

```bash
aws sts get-caller-identity --profile default
aws s3api list-buckets --profile default
```

```
Console → IAM → Users → test → Permissions tab
  → Confirm AmazonS3FullAccess (or equivalent) is still attached ✅
```

No permissions beyond Demo 01's own S3 set are required.

### Versions used in this demo

| Tool | Version |
|---|---|
| Terraform | `~> 1.15.0` |
| AWS Provider | `~> 6.47.0` |

---

## Demo Objectives

1. ✅ Explain the chicken-and-egg problem for a Terraform backend
2. ✅ Explain why this demo reuses Demo 01's `use_lockfile = true` pattern
3. ✅ Write a self-contained bootstrap config that uses local state
4. ✅ Explain why a `backend` block can never reference a variable,
   local, or output value
5. ✅ Distinguish first-time `terraform init` from `-migrate-state`
6. ✅ **New:** explain why one S3 bucket can safely serve two
   independent state keys with two different teardown policies, and
   why that's the correct pattern rather than two separate buckets
7. ✅ Explain why this specific bucket is exempt from "torn down
   between sessions" regardless of which downstream key is involved

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| S3 state bucket (small files, two keys) | Covered by free tier | **$0.00** | Two state files in one bucket cost the same as one — storage is billed per byte, not per key |
| **Session total** | | **~$0.00** | Created once and never torn down |

> **Known destroy-blocker, learned the hard way in this project's own
> history — document this before it bites the next person.** This
> bucket has versioning enabled. `terraform destroy` against a
> versioned bucket that still holds any object versions or delete
> markers will fail outright — S3 refuses to delete a non-empty
> versioned bucket. If you ever need to genuinely tear this down (a
> full project reset, not a normal session boundary), empty every
> version and delete-marker first:
> ```bash
> aws s3api list-object-versions --bucket <bucket-name> \
>   --output json --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' > /tmp/versions.json
> aws s3api delete-objects --bucket <bucket-name> --delete file:///tmp/versions.json
>
> aws s3api list-object-versions --bucket <bucket-name> \
>   --output json --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' > /tmp/markers.json
> aws s3api delete-objects --bucket <bucket-name> --delete file:///tmp/markers.json
> ```
> Then `terraform destroy` succeeds normally. This is not a routine
> step — it only applies to a genuine full reset, never to an ordinary
> end-of-session teardown (which never touches this bucket at all).

---

## Directory Structure

```
22a-state-backend-bootstrap/
├── README.md
├── 22a-state-backend-bootstrap-anki.csv
├── 22a-state-backend-bootstrap-quiz.md
└── src/
    ├── bootstrap/                          # local state — run once
    │   ├── versions.tf
    │   ├── provider.tf
    │   ├── variables.tf
    │   ├── main.tf                         # S3 bucket — UNCHANGED
    │   ├── outputs.tf
    │   └── break-fix/
    │       └── broken.tf
    ├── platform/                           # NEW — was part of
    │   │                                   #   phase-3-onward/; built
    │   │                                   #   out starting 22b
    │   └── backend.tf                      # key = "platform/terraform.tfstate"
    └── workloads/                          # NEW — was part of
        │                                   #   phase-3-onward/; built
        │                                   #   out starting the EKS demo
        └── backend.tf                      # key = "workloads/terraform.tfstate"
```

> **Note on repo alignment:** `src/terraform/bootstrap/`,
> `src/terraform/platform/`, and `src/terraform/workloads/` replace the
> single `src/terraform/phase-3-onward/` folder this project's repo
> structure previously reserved. Update any local checkout accordingly
> before continuing to 22b.

---

## Recall Check — Demo 21

(unchanged from the original demo — see prior version for the full
three-question recall check on `terraform test` `run` blocks,
`expect_failures`, and variable overrides.)

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| Bootstrap config pattern | Design pattern | A small, separate root config using local state, creating a backend's own infrastructure |
| `use_lockfile` at the project layer | Applied concept | Reused for both downstream keys, unchanged mechanism |
| Backend blocks are literal-only | Structural rule | No `var.*`/`local.*`/`*.output` ever valid inside a `backend` block |
| First-time `init` vs. `-migrate-state` | Workflow distinction | No prior state to copy — confirmed by a real run |
| **One bucket, two state keys** | **New this revision** | The `key` argument in `backend "s3"` is what actually separates platform-tier state from workloads-tier state — not a second bucket |

---

### Why a `backend` Block Can Never Reference a Variable, Local, or Output

(Unchanged from the original demo — this remains a hard, structural
Terraform limitation, unaffected by the platform/workloads split. See
prior version for the full explanation and the associated exam-trap
callout.)

---

## Lab Step-by-Step Guide

## Part A — Bootstrap the Backend Infrastructure

**Unchanged from the original demo.** Steps 1–4 (navigate to
`src/bootstrap`, create `versions.tf`/`provider.tf`/`variables.tf`/
`main.tf`/`outputs.tf`, `init`/`plan`/`apply`, verify in Console) are
identical — this bucket's own creation was never part of the incident
this revision fixes. Follow the original demo's Part A exactly.

**Confirmed against a real run** (from the original build): 4
resources added (`aws_s3_bucket`, `aws_s3_bucket_versioning`,
`aws_s3_bucket_server_side_encryption_configuration`,
`aws_s3_bucket_public_access_block`), real `state_bucket_name` output
matching the literal in `variables.tf`.

---

## Part B — Point TWO Downstream Configs at the New Backend

> **This Part replaces the original demo's single "Part B."** Where
> the original pointed one config (`phase-3-onward/`) at this bucket,
> this revision points two.

### Step 5 — Create `platform/backend.tf`

```bash
mkdir -p ../platform
cd ../platform
```

**backend.tf:**

```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-cloudnova-project-163125980376-us-east-2"
    # ↑ output from Part A, pasted in as a literal string — unchanged rule

    key          = "platform/terraform.tfstate"
    # ↑ CHANGED from "phase-3-onward/terraform.tfstate" — this key holds
    # every resource meant to be created once and left standing:
    # cost governance (22b), ECR/ACM (22c), and — once Demo 24 is
    # rebuilt — the EKS IAM roles and Pod Identity associations.

    region       = "us-east-2"
    profile      = "default"
    encrypt      = true
    use_lockfile = true
  }
}
```

### Step 6 — Create `workloads/backend.tf`

```bash
mkdir -p ../workloads
cd ../workloads
```

**backend.tf:**

```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-cloudnova-project-163125980376-us-east-2"
    # ↑ the SAME bucket as platform/ — this is deliberate, see
    # "Why Two Keys, One Bucket" above

    key          = "workloads/terraform.tfstate"
    # ↑ this key holds only what's torn down and reapplied every
    # session: the VPC, the EKS cluster and node pools, and the
    # Ingress/ALB that binds to platform/'s certificate

    region       = "us-east-2"
    profile      = "default"
    encrypt      = true
    use_lockfile = true
  }
}
```

### Step 7 — First-time init against both, independently

```bash
cd ../platform
terraform init
```

Expected: `Successfully configured the backend "s3"!` — no migration
prompt, same as the original Part B, since neither key has ever held
state before.

```bash
cd ../workloads
terraform init
```

Expected: identical success message, independently, for the second
key. **These two `init` calls are fully independent of each other** —
neither backend's existence depends on the other's; only the physical
bucket is shared.

> **Why this matters, worth internalizing before 22b/22c:** from this
> point forward, `terraform plan`/`apply` run **inside `platform/`**
> can only ever see and affect resources declared in `platform/`'s own
> `.tf` files — it has no visibility into, and cannot destroy,
> anything tracked under the `workloads/` key, and vice versa. This is
> the actual mechanism that prevents the class of incident this
> revision exists to fix — not a naming convention, a structural
> property of using two separate state files.

---

## Cleanup

**Unchanged in spirit — this is a verification step, not a
destruction step**, now checked against both configs:

```bash
cd ../bootstrap
terraform state list
# aws_s3_bucket.state
# aws_s3_bucket_public_access_block.state
# aws_s3_bucket_server_side_encryption_configuration.state
# aws_s3_bucket_versioning.state

cd ../platform
terraform state list
# (empty at this point — 22b hasn't built anything yet)

cd ../workloads
terraform state list
# (empty at this point — the EKS demo hasn't built anything yet)
```

> ⚠️ **Do not run `terraform destroy` in `bootstrap/`, `platform/`, or
> `workloads/` at the end of this session.** `platform/` in particular
> must never be destroyed as a matter of routine — see the
> `prevent_destroy` guidance introduced in 22c for why its individual
> resources are additionally protected at the resource level, not just
> by convention.

---

## What You Learned

1. ✅ The chicken-and-egg problem applies to any backend resource, at
   any layer
2. ✅ `use_lockfile = true` is this project's standing locking
   mechanism, reused unchanged across both new keys
3. ✅ A bootstrap config uses local state to create infrastructure a
   different config will use as its remote backend
4. ✅ A `backend` block can never reference a variable, local, or
   output
5. ✅ First-time `init` prompts differently than `-migrate-state`
6. ✅ **New:** one S3 bucket can safely and correctly serve multiple,
   independently-teardown-policied state files, distinguished purely
   by the backend's `key` argument — and this is the actual mechanism
   that gives platform-tier and workloads-tier resources genuinely
   independent blast radii, not just a documentation convention

---

## Next Demo

**Demo 22b — Cost Governance**, now built in `src/terraform/platform/`
(not `phase-3-onward/`) — EventBridge+SNS cost-control notification,
the two-threshold AWS Budgets alarm, interim `tflint`/`checkov` static
analysis, and (new in this revision) a `Tier` tag distinguishing
platform-tier resources from the workloads-tier resources that will
exist starting the EKS demo.