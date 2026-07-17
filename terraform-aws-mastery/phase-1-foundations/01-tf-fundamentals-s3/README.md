# Demo 01 — Terraform Fundamentals: First Real AWS Project with S3

---

## Overview

In Demo 00 you learned why IaC exists and how HCL works — using two
local providers with no AWS, no credentials, no cost. Now you apply
that same workflow against real AWS infrastructure for the first time.

**Real-world scenario — CloudNova:**
The team adopted Terraform. Your first task: create a production-grade
S3 bucket for CloudNova's deployment artefacts. The previous bucket was
manually created, had no versioning, no encryption, and no public-access
block — the security team flagged it and it was deleted. You are creating
the replacement, this time properly configured and Terraform-managed so
it can never silently drift again.

There is a second problem. You are the only DevOps engineer right now,
but a second engineer joins next month. If both run `terraform apply`
simultaneously with local state files, they will corrupt the state. Before
that happens, you need to move Terraform state off your local machine into
a shared remote backend with locking.

**What this demo builds:**
```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Production-grade S3 app bucket                                │
│  versioning + AES-256 encryption + public-access block                  │
│  First real terraform apply against AWS                                 │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Remote S3 backend + state locking                             │
│  State bucket → backend.tf → migrate local state → remote              │
│  S3 native locking (use_lockfile = true — no DynamoDB needed)           │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — State operations + drift detection                            │
│  terraform state list/show → manual Console change →                   │
│  terraform plan -refresh-only → reconcile                               │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- AWS provider authentication using a named profile
- All four standalone S3 configuration resources (v6 pattern)
- `depends_on` to prevent S3 race conditions
- Remote S3 backend with S3 native state locking (`use_lockfile = true`)
- State migration: local → remote with `terraform init -migrate-state`
- State CLI: `terraform state list`, `terraform state show`, `terraform show`
- Drift detection: `terraform plan -refresh-only`
- Console-first verification at every apply step

---

## Prerequisites

### Knowledge
- Demo 00 completed — HCL syntax, block types, full Terraform workflow
- Basic AWS concepts: S3, IAM, regions, AWS Console navigation

### Required Tools

| Tool | Minimum version | Install | Verify |
|---|---|---|---|
| Terraform CLI | `>= 1.15.0` | [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install) | `terraform version` |
| AWS CLI | `>= 2.x` | [docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | `aws --version` |
| Git | Any recent | Pre-installed on most systems | `git --version` |

### Verify AWS Account and Permissions

**Step 1 — Confirm your profile works:**

```bash
aws sts get-caller-identity --profile default
# Expected:
# {
#     "UserId": "AIDAXXXXXXXXXXXXXXXXX",
#     "Account": "163125980376",
#     "Arn": "arn:aws:iam::163125980376:user/test"
# }

aws configure get region --profile default
# Expected: <default region configured>
```

**Step 2 — Verify S3 permissions:**

```bash
aws s3api list-buckets --profile default
# Expected: JSON with Buckets array (may be empty — that is fine)
# If you see AccessDenied: fix IAM permissions before proceeding
```

**Step 3 — Verify IAM permissions in Console:**

```
Console → IAM → Users → test → Permissions tab
  → Confirm AmazonS3FullAccess (or equivalent) is attached ✅
```

**Required S3 permissions for this demo:**

```
s3:CreateBucket, s3:DeleteBucket, s3:ListBucket, s3:GetBucketLocation
s3:GetBucketVersioning, s3:PutBucketVersioning
s3:GetEncryptionConfiguration, s3:PutEncryptionConfiguration
s3:GetBucketPublicAccessBlock, s3:PutBucketPublicAccessBlock
s3:GetObject, s3:PutObject, s3:DeleteObject
s3:ListBucketVersions, s3:DeleteObjectVersion
```

> For a learning account, `AmazonS3FullAccess` managed policy covers all of
> the above. In production, always scope to the minimum required permissions.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain what an AWS provider version means and why v6 differs from v5
2. ✅ Configure the AWS provider with a named profile and `default_tags`
3. ✅ Explain why S3 uses four standalone resources in AWS provider v6
4. ✅ Explain what a meta-argument is and use `depends_on` correctly
5. ✅ Apply the full Terraform workflow against real AWS and verify in Console
6. ✅ Explain why local state breaks for teams and what remote state solves
7. ✅ Explain state locking — what it is, why it is needed, how S3 native locking works
8. ✅ Create a remote S3 backend and migrate local state to it
9. ✅ Use state CLI commands and detect drift with `terraform plan -refresh-only`

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| S3 app bucket (empty) | 5GB / 2,000 PUT / 20,000 GET per month | **$0.00** | No objects stored in this demo |
| S3 state bucket (~2KB file) | Covered by free tier | **$0.00** | |
| AES-256 encryption (SSE-S3) | Always free | **$0.00** | AWS absorbs the cost of S3-managed keys. SSE-KMS (customer-managed) is paid — we use AES256. |
| S3 API calls | Within free tier | **<$0.001** | |
| `random_id` | Free — no AWS resource | **$0.00** | |
| **Session total** | | **~$0.00** | |

> Always run cleanup at the end of the session. Empty S3 buckets
> cost nothing but good hygiene means destroying everything completely.

---

## Directory Structure

```
01-tf-fundamentals-s3/
├── README.md
├── 01-tf-fundamentals-s3-anki.csv   # Anki flash cards
├── 01-tf-fundamentals-s3-quiz.md    # Quiz
└── src/
    ├── versions.tf                   # terraform block + provider version constraints
    ├── provider.tf                   # AWS provider: region, profile, default_tags
    ├── variables.tf                  # input variables
    ├── locals.tf                     # computed bucket name + common tags
    ├── main.tf                       # S3 bucket + 3 config resources + random_id
    ├── outputs.tf                    # bucket name, ARN, region, suffix
    ├── backend.tf                    # S3 remote backend (added in Part B)
    └── break-fix/
        └── broken.tf                 # break-fix scenario
```

---

## Recall Check — Demo 00

Answer from memory before reading anything new:

1. Name the four failure modes of manual infrastructure management.
2. What does `terraform plan -out=tfplan` + `terraform apply tfplan`
   guarantee that plain `terraform apply` does not?
3. Should `.terraform.lock.hcl` be committed to version control? Why?

<details>
<summary>Answers</summary>

1. Drift, no audit trail, not repeatable, bus factor.
2. The saved plan is a binary snapshot — `apply tfplan` executes exactly
   what was reviewed without re-reading `.tf` files. Plain `apply`
   recalculates before executing — a config edit between plan and apply
   would be silently included.
3. Yes — records exact provider versions and SHA256 hashes so every
   engineer and CI runner downloads the identical provider binary.

</details>

---

## Concepts

### What's New in This Demo

Every new Terraform construct introduced in this demo is listed below.
The next section explains each one in full before you write any code.

| Construct | Type | Purpose in this demo |
|---|---|---|
| `provider "aws"` | Provider config block | AWS authentication, region, default tags |
| `default_tags` | Provider argument (nested block) | Auto-tag every AWS resource this provider creates |
| `profile` | Provider argument | Named profile from `~/.aws/credentials` |
| `aws_s3_bucket` | Resource | The S3 bucket itself |
| `aws_s3_bucket_versioning` | Resource | Enable object version history |
| `aws_s3_bucket_server_side_encryption_configuration` | Resource | Encrypt objects at rest |
| `aws_s3_bucket_public_access_block` | Resource | Block all public access paths |
| `random_id` | Resource | Generate unique bucket name suffix |
| `depends_on` | Meta-argument | Force sequential resource creation |
| `backend "s3"` | Backend block in `terraform {}` | Store state in S3 with locking |
| `use_lockfile` | Backend argument | S3 native state locking — no DynamoDB |

**Related S3 resources worth knowing (not used in this demo):**

| Resource | What it does |
|---|---|
| `aws_s3_bucket_lifecycle_configuration` | Auto-delete or archive objects after N days |
| `aws_s3_bucket_cors_configuration` | Allow browser cross-origin requests |
| `aws_s3_bucket_website_configuration` | Host a static website |
| `aws_s3_bucket_replication_configuration` | Cross-region replication |
| `aws_s3_object` | Upload a file into a bucket |

---

### Detailed Explanation of New Constructs

#### Provider Versions — What v5 and v6 Actually Mean

Providers are **separate software packages** maintained independently from
Terraform CLI. The AWS provider is a plugin that translates Terraform
resource blocks into AWS API calls. Like any software it has its own
version history with new features, bug fixes, and breaking changes.

```
Terraform CLI   v1.15.0    ← the engine (what you installed)
AWS Provider    v6.47.0    ← the AWS plugin (downloaded on terraform init)

These are two completely independent versioned packages.
A new AWS service feature requires a provider update, not a CLI update.
```

**Specific versions:**
- AWS provider **v5** = versions `5.x` (released May 2023)
- AWS provider **v6** = versions `6.x` (released June 2025, breaking changes from v5)
- This series uses `v6.47.0` — the latest as of May 2026

**Why v6 matters for S3 specifically:**

In AWS provider v5, S3 configuration was nested inline inside `aws_s3_bucket`:

```hcl
# v5 pattern — ERRORS in v6. Do not copy this.
resource "aws_s3_bucket" "app" {
  bucket = "my-bucket"
  versioning {                        # removed in v6
    enabled = true
  }
  server_side_encryption_configuration {  # removed in v6
    rule { ... }
  }
}
```

In AWS provider v6, every S3 setting is its own **standalone resource**:

```hcl
# v6 pattern — required in this series
resource "aws_s3_bucket" "app" { ... }
resource "aws_s3_bucket_versioning" "app" { ... }
resource "aws_s3_bucket_server_side_encryption_configuration" "app" { ... }
resource "aws_s3_bucket_public_access_block" "app" { ... }
```

**Why the change?** Inline nested blocks could not be independently managed,
imported, or removed without affecting the bucket resource. Standalone
resources give fine-grained control over each setting independently.

**Practical impact:** Many tutorials, Stack Overflow answers, and course
materials online still use v5 syntax. They will not work with v6. When you
see nested `versioning {}` inside `aws_s3_bucket`, that is v5 — do not copy.

---

#### AWS Provider Authentication

The `provider "aws"` block needs to know which AWS account and region to
use, and how to authenticate. It tries these methods in order — first found wins:

```
┌──────────────────────────────────────────────────────────────────────────┐
│  AWS PROVIDER AUTH — PRECEDENCE (highest to lowest)                      │
│                                                                          │
│  1. Static credentials in provider block         ← NEVER — secrets in   │
│     access_key = "AKIA..."                          version control      │
│     secret_key = "..."                                                   │
│                                                                          │
│  2. Environment variables                   ← Good for CI/CD            │
│     AWS_ACCESS_KEY_ID                                                    │
│     AWS_SECRET_ACCESS_KEY                                                │
│     AWS_SESSION_TOKEN (for temporary credentials)                        │
│                                                                          │
│  3. Shared credentials file (~/.aws/credentials)                        │
│     + Named profile in provider block       ← This demo uses this       │
│     provider "aws" { profile = "default" }                              │
│                                                                          │
│  4. IAM Instance Profile / ECS Task Role          ← Production on AWS   │
│     No credentials needed — role attached to compute resource            │
│                                                                          │
│  5. IAM Identity Center (SSO)                     ← Corporate standard  │
│     aws sso login --profile my-profile                                   │
└──────────────────────────────────────────────────────────────────────────┘
```

This demo uses **Option 3** — the named profile you already configured
with `aws configure`. The profile name `"default"` matches what
`aws sts get-caller-identity --profile default` uses.

---

#### New Resources and Their Arguments

**`random_id`** — generates a random value and stores it in state.
Once generated, the same value is reused on every subsequent apply.

| Argument | Required | Description |
|---|---|---|
| `byte_length` | Yes | Number of random bytes. `4` bytes = 8-character hex string (2 hex chars per byte). e.g. `"a1b2c3d4"` |

Output attributes: `.hex`, `.dec`, `.b64_std`, `.b64_url`

---

**`aws_s3_bucket`** — the S3 bucket resource. In v6, this block only
contains bucket-level settings. All configuration (versioning, encryption,
public access) lives in separate resources.

| Argument | Required | Description |
|---|---|---|
| `bucket` | No — but always set | Globally unique bucket name. If omitted, AWS generates a random name. |
| `force_destroy` | No (default: `false`) | When `true`: `terraform destroy` empties the bucket then deletes it. When `false`: destroy fails if bucket has objects. Use `true` for demos only — never in production. |
| `tags` | No | Resource-level tags, merged with `default_tags` from provider. |

---

**`aws_s3_bucket_versioning`** — enables a version history for every
object in the bucket. Each upload creates a new version. Deleted objects
get a delete marker instead of being permanently removed. Protects against
accidental deletions.

| Argument | Required | Description |
|---|---|---|
| `bucket` | Yes | The bucket ID — use `aws_s3_bucket.app.id` |
| `versioning_configuration.status` | Yes | `Enabled` — turns versioning on. `Suspended` — pauses versioning (existing versions kept). `Disabled` — only for buckets that have never had versioning. Once enabled, cannot be fully disabled — only suspended. |
| `depends_on` | Recommended | See Meta-arguments section below |

---

**`aws_s3_bucket_server_side_encryption_configuration`** — encrypts
every object stored in the bucket. Encryption happens at the storage layer
— transparent to readers with correct permissions.

| Argument | Required | Description |
|---|---|---|
| `bucket` | Yes | The bucket ID |
| `rule.apply_server_side_encryption_by_default.sse_algorithm` | Yes | `AES256` — S3-managed keys, always free. `aws:kms` — customer-managed keys via AWS KMS, paid ($0.03/10k requests + $1/month per key). Use `AES256` unless you need key rotation audit trails or cross-account access control. |
| `depends_on` | Recommended | See Meta-arguments section below |

---

**`aws_s3_bucket_public_access_block`** — four independent controls
that together block every path to public access. All four must be `true`
for complete protection.

| Argument | Required | Description |
|---|---|---|
| `bucket` | Yes | The bucket ID |
| `block_public_acls` | No (default: `false`) | Ignores any ACL that would grant public access to the bucket or objects |
| `block_public_policy` | No (default: `false`) | Rejects any bucket policy that grants public access |
| `ignore_public_acls` | No (default: `false`) | Ignores existing public ACLs on the bucket and objects |
| `restrict_public_buckets` | No (default: `false`) | Restricts access to bucket owner and AWS service principals only |
| `depends_on` | Recommended | See Meta-arguments section below |

> Setting only some of these to `true` leaves gaps. A public ACL can bypass
> a blocked policy. A public policy can bypass blocked ACLs. Set all four.

---

#### Meta-Arguments — What `depends_on` Is Called

In Demo 00 you learned the eight top-level HCL block types. Inside a
`resource` block, Terraform supports five special arguments called
**meta-arguments**. These are not arguments the AWS API understands —
they control Terraform's own behaviour regardless of provider.

| Meta-argument | What it does | Covered in |
|---|---|---|
| `depends_on` | Explicit dependency — force sequential execution | This demo |
| `count` | Create N copies of a resource | Demo 06 |
| `for_each` | Create one resource per item in a map or set | Demo 06 |
| `provider` | Specify which provider alias to use | Demo 02 |
| `lifecycle` | Control create/update/delete behaviour | Demo 08 |


> Meta-arguments are covered in full in Demo 06/08. Here we use `depends_on` for one specific, practical reason explained next.

---

#### S3 Race Condition — Why `depends_on` Is Required

This section explains a real AWS behaviour that catches many engineers
the first time they use Terraform with S3.

**Step 1 — Terraform's default execution model:**

By default, Terraform runs independent resources **in parallel** (up to
10 simultaneously). This makes large deployments fast. The dependency
graph controls which resources must wait for others.

**Step 2 — What an implicit reference does:**

When you write:

```hcl
resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id    # ← implicit reference
  ...
}
```

Terraform sees `aws_s3_bucket.app.id` and adds an edge in the dependency
graph: "create `aws_s3_bucket.app` before `aws_s3_bucket_public_access_block.app`."
This is called an **implicit dependency** — Terraform detected it from
the attribute reference.

**Step 3 — Why implicit is not enough for S3:**

"Created" to Terraform means: the AWS API returned HTTP 200 OK for the
`CreateBucket` call. Terraform marks the bucket as done and immediately
starts the configuration resources.

However, AWS S3 is a distributed system. When `CreateBucket` returns 200,
the bucket exists — but it may not have fully propagated across all of S3's
internal systems yet. AWS calls this **eventual consistency**.

When Terraform immediately calls `PutPublicAccessBlock` on a bucket that
is still propagating internally, AWS may return:

```
Error: NoSuchBucket
Error: NoSuchPublicAccessBlockConfiguration
Error: RequestCanceled
```

The bucket was created — but AWS's internal systems are not yet ready to
accept configuration for it.

**Step 4 — What depends_on actually does:**

```hcl
resource "aws_s3_bucket_public_access_block" "app" {
  bucket     = aws_s3_bucket.app.id
  depends_on = [aws_s3_bucket.app]   # explicit dependency
  ...
}
```

`depends_on` tells Terraform: do not start this resource until
`aws_s3_bucket.app` has **fully completed all its own operations** —
including any post-creation steps Terraform runs internally. This adds
a small sequential gap between bucket creation and configuration, giving
AWS's internal propagation the milliseconds it needs.

```
Without depends_on:            With depends_on:
──────────────────             ─────────────────────────────
CreateBucket → 200 OK          CreateBucket → 200 OK
     ↓ (immediately)                ↓ (waits for full completion)
PutPublicAccessBlock           [Terraform marks bucket complete]
→ NoSuchBucket ERROR                ↓
                               PutPublicAccessBlock → 200 OK ✅
```

This is not a Terraform bug. It is AWS S3's eventual consistency model.
`depends_on` is the correct Terraform solution.

---

#### Remote State — The Problem and the Solution

**What breaks with local state in a team:**

Before you see why local state breaks for teams, understand what state
is at this point in the demo.

When you ran `terraform apply` in Part A, Terraform created
`terraform.tfstate` on your local machine. This is Terraform's memory —
it records every resource Terraform created and all their attributes.
Every future plan reads this file to know what already exists. Without
it, Terraform has no memory of what it built.

Now imagine a two-engineer team:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  DAY 1                                                                  │
│                                                                         │
│  Engineer A creates main.tf with one S3 bucket and runs apply.         │
│  AWS: bucket-A exists                                                   │
│  A's state: "I manage bucket-A"                                        │
│                                                                         │
│  Engineer A shares main.tf with Engineer B via Git.                    │
│  Git has the code. Git does NOT have the state file.                   │
│  (.gitignore correctly excludes terraform.tfstate)                     │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  DAY 2                                                                  │
│                                                                         │
│  Engineer B clones the repo, adds a second S3 bucket to main.tf,      │
│  and runs terraform apply.                                              │
│                                                                         │
│  B has no state file — Terraform starts with empty state.              │
│  B's plan: desired = 2 buckets, known existing = 0 buckets.            │
│  B's Terraform tries to CREATE BOTH buckets.                           │
│                                                                         │
│  bucket-A already exists in AWS → BucketAlreadyExists error            │
│  OR bucket-A has a random suffix → B creates a duplicate with          │
│  a different suffix. Now two "bucket-A equivalent" buckets exist.      │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  RESULT                                                                 │
│                                                                         │
│  A's state says: I manage 1 bucket (the original)                     │
│  B's state says: I manage 2 buckets (including a duplicate)            │
│  AWS reality:    2 or more buckets exist, partially orphaned           │
│                                                                         │
│  Neither engineer can safely run terraform destroy.                    │
│  Neither engineer knows what the other manages.                        │
│  The infrastructure is now impossible to reason about.                 │
└─────────────────────────────────────────────────────────────────────────┘
```

With **remote state**, both engineers read and write the same
`terraform.tfstate` file in S3. B's plan on Day 2 would correctly show:
desired = 2 buckets, known existing = 1 bucket → creates only the new one.
State locking ensures A and B cannot apply simultaneously.

**Remote state solves this:**

| | Local state | Remote state (S3) |
|---|---|---|
| Accessible by | One machine only | Every engineer + CI/CD |
| Lost if | Machine fails | S3 99.999999999% durability |
| Simultaneous protection | None | State locking (see next) |
| History | None | S3 versioning — every apply = new version |
| Recovery | None | Download older version → restore |

**S3 versioning on the state bucket** means every `terraform apply` creates
a new version of the state file. If state becomes corrupted (rare but
possible), you can open the state bucket in Console, find the previous
version, download it, and restore it. This is your undo button for state.

To view and restore an older state version:

```
Console → S3 → your-state-bucket → terraform.tfstate
  → Click "Show versions" toggle (top right of Objects tab)
  → Each apply created a new version with a timestamp
  → Download an older version → rename to terraform.tfstate
  → Run: terraform state push terraform.tfstate
  → Terraform restores that version as the current state
```

---

#### State Locking — What It Is and How It Works

**What is a lock?**

A lock is a signal that says: "I am using this shared resource right now —
wait until I am done before you start." Databases, operating systems, and
file systems all use locks. Terraform uses a state lock to prevent two
`terraform apply` operations from running simultaneously against the same
state file.

**Why simultaneous applies corrupt state:**

```
Without locking:

  Engineer A: reads state → plans → starts applying → writing state...
  Engineer B: reads state → plans → starts applying → writing state...

  Both read the same state at the start.
  Both write their results at the end.
  B's write overwrites A's changes.
  State now reflects only B's apply.
  A's resources exist in AWS but are gone from state.
  Next apply will try to create A's resources again.
  Duplicate resources. Broken infrastructure.
```

**How locking worked before — DynamoDB:**

Before Terraform 1.10, the S3 backend required a separate AWS DynamoDB
table to store the lock. When an apply started, Terraform wrote a lock
record to DynamoDB. When another apply tried to start, it checked DynamoDB
and saw the lock — and waited or errored.

Problems with the DynamoDB approach:
- Extra AWS resource to create, manage, and pay for (~$0.25/month)
- Extra IAM permissions required for DynamoDB
- If the DynamoDB table and S3 bucket are in different regions, the lock
  could lag behind the state

> **Deprecated:** the `dynamodb_table` argument on the S3 backend is
> deprecated as of Terraform 1.11 in favor of `use_lockfile = true`.
> Do NOT use `dynamodb_table` in new configurations.

**How locking works now — S3 native (`use_lockfile = true`):**

Terraform 1.10 introduced S3 native locking. Instead of DynamoDB, Terraform
uses an S3 feature called **conditional writes** to create a `.tflock` file
in the same bucket as the state:

```
Apply starts:
  Terraform attempts to create: terraform.tfstate.tflock
  S3 conditional write = "only create this file if it does not exist"
  If file does not exist → write succeeds → lock acquired → apply proceeds
  If file already exists → write fails → another apply is running → error

Apply finishes:
  Terraform deletes terraform.tfstate.tflock
  Lock released → next apply can proceed
```

```
Console view during an active apply:
  S3 → state-bucket → path/
    terraform.tfstate          ← the state file
    terraform.tfstate.tflock   ← appears during apply, disappears after
```

**Can you lock local state?** No — locking only makes sense when state is
shared. A lock on your local machine protects nothing because nobody else
can access your local file anyway.

**Releasing a stuck lock** (if Terraform crashed mid-apply):

```bash
# Terraform shows you the lock ID when it errors:
# Error acquiring the state lock: Lock ID: "abc123-..."

terraform force-unlock abc123-...
# Or: delete the .tflock file manually in S3 Console
# Only do this when you are certain no apply is actually running
```

---

#### `backend "s3"` Block Arguments

The `backend "s3"` block lives inside a `terraform {}` block — in
`backend.tf` in this demo. It tells Terraform where to store and lock state.

| Argument | Required | Description |
|---|---|---|
| `bucket` | **Yes** | Name of the S3 bucket that stores the state file |
| `key` | **Yes** | Path within the bucket: `phase/demo/terraform.tfstate` |
| `region` | **Yes** | AWS region of the state bucket — mandatory, S3 is regional |
| `profile` | No | Named AWS profile. If omitted, falls back to default credential chain |
| `encrypt` | No (default: `false`) | Encrypt state file at rest in S3 |
| `use_lockfile` | No (default: `false`) | S3 native locking — creates `.tflock` file |

> **Can backend arguments use Terraform variables?**
> **No.** The backend block is evaluated before variables are loaded —
> before any provider initialises. Using `var.aws_region` in a backend block
> errors: `Variables may not be used here`. This is why `backend.tf` always
> has hardcoded values. The production solution for teams is **partial backend
> configuration** — pass dynamic values via `-backend-config` flags or a
> `.tfbackend` file. This is covered in tf-complete-guide Demo 04.

---

## Lab Step-by-Step Guide

---

## Part A — Create a Production-Grade S3 Bucket

**What you accomplish in Part A:** Write five Terraform resources —
a random ID suffix, the S3 bucket, and its three configuration resources
(versioning, encryption, public-access block). Apply them against AWS and
verify each setting in the Console. At the end of Part A you have a
production-grade S3 bucket fully managed by Terraform.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/01-tf-fundamentals-s3/src
```

### Step 2 — Create the source files

---

#### `versions.tf` — Version constraints

**What this file does in this demo:** declares the Terraform CLI version
and the two provider plugins this demo needs — `aws` (for all `aws_*`
resources) and `random` (for the unique bucket name suffix). Same structure
as Demo 00 — new here: the `aws` provider is added.

**versions.tf:**

```hcl
terraform {
  required_version = "~> 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47.0"   # v6 — standalone S3 resource pattern
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"    # for unique bucket name suffix
    }
  }
}
```

---

#### `provider.tf` — AWS provider configuration

**What this file does in this demo:** configures how Terraform connects
to AWS — which region, which credential profile, and which tags to apply
to every resource automatically via `default_tags`.

**`default_tags` block:** Tags defined here are automatically merged into
every resource created by this provider — no need to write
`tags = local.common_tags` in every resource block. Resource-level tags
merge on top; in conflicts the resource-level tag wins.

**provider.tf:**

```hcl
provider "aws" {
  region  = var.aws_region    # which AWS region — us-east-2
  profile = var.aws_profile   # named profile from ~/.aws/credentials

  default_tags {
    tags = local.common_tags  # applied automatically to every resource
  }
}

provider "random" {}          # random provider needs no configuration
```

> **Note:** `var.aws_region` and `var.aws_profile` are safe to use here
> because they have static default values. The anti-pattern to avoid is
> using a `data` source (which itself requires a working provider) inside
> the same provider's configuration — that creates a circular dependency.



---

#### `variables.tf` — Input variables

**What this file does in this demo:** declares all values that change
between engineers, environments, or accounts — so nothing is hardcoded
in resource blocks. Same pattern as Demo 00 — new here: `aws_region`,
`aws_profile`, and `project` are added.

**variables.tf:**

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

variable "project" {
  type        = string
  description = "Project name — used in resource names and tags"
  default     = "cloudnova"
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
  default     = "01-tf-fundamentals-s3"
}
```

---

#### `locals.tf` — Computed values

**What this file does in this demo:** computes two values used across
multiple resources — the globally unique bucket name (project + environment
+ random suffix) and the common tag map passed to `provider.tf`'s
`default_tags`.

**locals.tf:**

```hcl
locals {
  # Globally unique bucket name — e.g. "cloudnova-dev-app-a1b2c3d4"
  # random_id.suffix.hex is a cross-resource reference:
  # Terraform creates random_id.suffix BEFORE aws_s3_bucket.app
  bucket_name = "${var.project}-${var.environment}-app-${random_id.suffix.hex}"

  # Tag map — passed to provider default_tags
  # Applied automatically to every resource this provider creates
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Demo        = var.demo
    ManagedBy   = "Terraform"
    Owner       = "devops-team"
  }
}
```

---

#### `main.tf` — The infrastructure

**What this file does in this demo:** declares all five resources —
`random_id` for the bucket name suffix, `aws_s3_bucket` for the bucket
itself, and the three standalone configuration resources required by
AWS provider v6. All arguments are explained in the Concepts section above.

**main.tf:**

```hcl
# Generates a unique 8-character hex suffix — e.g. "a1b2c3d4"
# Generated once on first apply, stored in state, reused on all subsequent applies
resource "random_id" "suffix" {
  byte_length = 4   # 4 bytes = 8 hex characters
}

# ── S3 app bucket ──────────────────────────────────────────────────────────
resource "aws_s3_bucket" "app" {
  bucket        = local.bucket_name   # globally unique name from locals.tf
  force_destroy = true                # demo only — allows destroy even if not empty
                                      # remove this in production

  tags = {
    Name = local.bucket_name          # merged with default_tags from provider.tf
  }
}

# ── Versioning ─────────────────────────────────────────────────────────────
# Protects against accidental deletions — every overwrite creates a new version
resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = "Enabled"
  }

  depends_on = [aws_s3_bucket.app]   # prevents S3 eventual consistency race condition
}

# ── Server-side encryption ─────────────────────────────────────────────────
# AES256 = AWS-managed keys, always free. Encrypts objects stored on disk.
resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"        # free — no KMS cost
    }
  }

  depends_on = [aws_s3_bucket.app]   # prevents S3 eventual consistency race condition
}

# ── Public access block ────────────────────────────────────────────────────
# All four set to true — closes every path to public access
# This is the #1 S3 security control — enable on every bucket
resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true    # ignore public ACLs on the bucket
  block_public_policy     = true    # reject public bucket policies
  ignore_public_acls      = true    # ignore public ACLs on objects
  restrict_public_buckets = true    # restrict access to only authorised principals

  depends_on = [aws_s3_bucket.app]   # prevents S3 eventual consistency race condition
}
```

---

#### `outputs.tf` — Expose values after apply

**What this file does in this demo:** makes the bucket name, ARN, region,
and random suffix available in the terminal after apply, and queryable by
other Terraform configs via `terraform_remote_state`.

**outputs.tf:**

```hcl
output "bucket_name" {
  description = "Name of the app S3 bucket"
  value       = aws_s3_bucket.app.bucket
}

output "bucket_arn" {
  description = "ARN of the app S3 bucket"
  value       = aws_s3_bucket.app.arn
}

output "bucket_region" {
  description = "AWS region where the bucket was created"
  value       = aws_s3_bucket.app.region
}

output "random_suffix" {
  description = "Random hex suffix used in the bucket name"
  value       = random_id.suffix.hex
}
```

---

### Step 3 — Initialise

> **Note:** Make sure `backend.tf` file not created at this stage. It should be created in Part-B  

```bash
terraform init
```

Expected output:

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.47.0"...
- Finding hashicorp/random versions matching "~> 3.9.0"...
- Installing hashicorp/aws v6.47.0...
- Installed hashicorp/aws v6.47.0 (signed by HashiCorp)
- Installing hashicorp/random v3.9.0...
- Installed hashicorp/random v3.9.0 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl

Terraform has been successfully initialized!
```

---

### Step 4 — Validate and Format

```bash
terraform validate
# Success! The configuration is valid.

terraform fmt
```

---

### Step 5 — Plan

```bash
terraform plan
```

Key section of expected output:

```
  # random_id.suffix will be created          ← created first (no dependencies)
  + resource "random_id" "suffix" {
      + byte_length = 4
      + hex         = (known after apply)
    }

  # aws_s3_bucket.app will be created         ← created second (depends on suffix)
  + resource "aws_s3_bucket" "app" {
      + bucket        = (known after apply)   ← depends on random_id.suffix.hex
      + force_destroy = true
      + region        = (known after apply)
      + arn           = (known after apply)
    }

  # aws_s3_bucket_versioning.app will be created
  + resource "aws_s3_bucket_versioning" "app" {
      + bucket = (known after apply)
      + versioning_configuration {
          + status = "Enabled"
        }
    }

  # aws_s3_bucket_server_side_encryption_configuration.app will be created
  # aws_s3_bucket_public_access_block.app will be created
  # ↑ all three created last (depends_on aws_s3_bucket.app)

Plan: 5 to add, 0 to change, 0 to destroy.
```

---

### Step 6 — Apply

```bash
terraform apply
```

Type `yes`. Expected output:

```
random_id.suffix: Creating...
random_id.suffix: Creation complete after 0s [id=...]

aws_s3_bucket.app: Creating...
aws_s3_bucket.app: Creation complete after 2s [id=cloudnova-dev-app-a1b2c3d4]

aws_s3_bucket_versioning.app: Creating...
aws_s3_bucket_server_side_encryption_configuration.app: Creating...
aws_s3_bucket_public_access_block.app: Creating...
aws_s3_bucket_versioning.app: Creation complete after 1s
aws_s3_bucket_server_side_encryption_configuration.app: Creation complete after 1s
aws_s3_bucket_public_access_block.app: Creation complete after 1s

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:
bucket_arn    = "arn:aws:s3:::cloudnova-dev-app-a1b2c3d4"
bucket_name   = "cloudnova-dev-app-a1b2c3d4"
bucket_region = "us-east-2"
random_suffix = "a1b2c3d4"
```

---

### Step 7 — Verify in AWS Console
**Navigate:** `AWS Console → S3 → General purpose buckets`

```
Console → S3 → General purpose buckets → cloudnova-dev-app-xxxxxxxx → click it

Properties tab:
  → Bucket Versioning: Enabled ✅
  → Default encryption: SSE-S3 (AES-256) ✅

Permissions tab:
  → Block public access (bucket settings): all four ON ✅
  → Bucket policy: none (expected — we did not create one)

Properties tab → Tags → User-defined tags (scroll down):
  → Demo: 01-tf-fundamentals-s3 ✅
  → Environment: dev ✅
  → ManagedBy: Terraform ✅
  → Name: cloudnova-dev-app-xxxxxxxx ✅
  → Project: cloudnova ✅
  → Owner: devops-team ✅
```

> **Console-first principle:** Never accept "it worked" from the terminal
> alone. Verify in the Console that what Terraform reports matches what
> AWS actually created. This habit catches provider bugs and permission
> issues early.

---

## Part B — Move State to a Remote S3 Backend

**What you accomplish in Part B:** move Terraform state off your local
machine and into a shared S3 bucket with locking enabled. You will create
the state bucket in the Console, add `backend.tf`, and run
`terraform init -migrate-state` to copy local state to S3. At the end
of Part B, state is shared and locked — ready for team use and CI/CD.

### Step 8 — Create the state bucket in AWS Console

The state bucket is created in the Console — not with Terraform.Reason: you cannot use Terraform to create the bucket that will store
Terraform's own state. The chicken-and-egg problem..Terraform needs the bucket to already exist before
`terraform init` can configure the backend.

```
Console → S3 → General purpose buckets → Create bucket

Bucket name:
  tfstate-cloudnova-163125980376-us-east-2
  (replace 163125980376 with YOUR account ID from the verify step above)
  naming convention: tfstate-project-accountid-region

AWS Region:
  US East (Ohio) us-east-2

Object Ownership:
  ✅ ACLs disabled (recommended)

Block Public Access settings:
  ✅ Block all public access (leave all four checked)

Bucket Versioning:
  ✅ Enable
  Reason: every terraform apply creates a new state version — your undo button

Default encryption:
  ✅ Server-side encryption with Amazon S3 managed keys (SSE-S3)
  Bucket key: Enable

→ Click Create bucket
```

**Verify the state bucket:**

```
Console → S3 → tfstate-cloudnova-163125980376-us-east-2
  → Properties → Bucket Versioning: Enabled ✅
  → Properties → Default encryption: SSE-S3 ✅
  → Permissions → Block public access: all four ON ✅
```

---

### Step 9 — Add backend.tf

**What this file does in this demo:** adds an S3 backend configuration
to the Terraform project. Once initialised, all state reads and writes go
to S3 instead of the local disk. Contains a second `terraform {}` block —
valid because Terraform merges all `.tf` files (explained in Concepts above).

**backend.tf:**

```hcl
terraform {
  backend "s3" {
    bucket  = "tfstate-cloudnova-163125980376-us-east-2"
    # ↑ the state bucket you just created in Step 8
    # replace with your actual state bucket name

    key     = "phase-1/01-tf-fundamentals-s3/terraform.tfstate"
    # ↑ path within the bucket — like a folder/filename
    # convention: phase/demo-name/terraform.tfstate
    # keeps multiple demos organised in one state bucket

    region  = "us-east-2"
    profile = "default"
    encrypt = true          # encrypt state file at rest in S3

    use_lockfile = true     # S3 native locking — creates .tfstate.tflock file
                            # no DynamoDB table needed
                            # fully supported in Terraform 1.11+
  }
}
```
> **Two `terraform {}` blocks in one directory:** `versions.tf` already
> has a `terraform {}` block. Adding `backend.tf` with another `terraform {}`
> is valid — Terraform merges all `.tf` files. The `backend` block in
> `backend.tf` merges cleanly with `required_version` and `required_providers`
> in `versions.tf`. The only restriction: the same setting cannot be
> declared twice (two `backend` blocks would error).

---

### Step 10 — Migrate state to S3

```bash
terraform init -migrate-state
```

Expected output:

```
Initializing the backend...

Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend
  to the newly configured "s3" backend. No existing state was found in the
  newly configured "s3" backend. Do you want to copy this state to the
  new backend? Enter a value: yes

Successfully configured the backend "s3"!
Terraform has been successfully initialized!
```

**What just happened:**
- Terraform copied `terraform.tfstate` from your local disk to S3
- The S3 copy is now the authoritative state
- Your local `terraform.tfstate` is a stale backup — not used anymore


**Verify the migrated state in Console:**

```
Console → S3 → tfstate-cloudnova-163125980376-us-east-2
  → Browse: phase-1/ → 01-tf-fundamentals-s3/
  → Enable "Show versions" toggle (top right of Objects tab)

You will see three objects:
  terraform.tfstate          ← the current state file (7-8 KB) ✅
  terraform.tfstate.tflock   ← the actual lock file (283 bytes) ✅
  terraform.tfstate.tflock   ← a Delete marker (0 bytes) ✅
```

**Why the delete marker?**
The lock file was created at the start of the migration, then deleted
when it completed. Because the state bucket has versioning enabled,
S3 does not permanently delete objects — it adds a delete marker instead.
This is expected behaviour, not an error.
The delete marker is S3's version history of the lock lifecycle.


Click `terraform.tfstate` → Object actions → Open to read the JSON —
all 5 resources are recorded inside.

**Verify state versioning:**

```
Console → S3 → state bucket → terraform.tfstate
  → Click "Show versions" toggle (top right of Objects tab)
  → Version 1 exists — this was created by the migration
  → Each future apply will create a new version here
```

---

### Step 11 — Verify remote state works

```bash
# Terraform now reads state from S3
terraform plan
# Expected: Plan: 0 to add, 0 to change, 0 to destroy.
# Proves Terraform read the remote state and knows all 5 resources exist
```

**Observe the lock file (optional — in a second terminal):**

```
While terraform plan is running:
Console → S3 → state bucket → phase-1/01-tf-fundamentals-s3/
  → terraform.tfstate.tflock appears briefly then disappears
  → This is the S3 native lock — acquired at start, released at end
```

---

## Part C — State Operations and Drift Detection

**What you accomplish in Part C:** use the state CLI commands to inspect
what Terraform manages, then experience drift firsthand. You will manually
change a resource in the Console, detect the change with Terraform, and
reconcile. At the end of Part C you have seen the full drift cycle:
introduce → detect → reconcile.

### Step 12 — State CLI commands

```bash
# List all resources Terraform currently manages
terraform state list
# random_id.suffix
# aws_s3_bucket.app
# aws_s3_bucket_public_access_block.app
# aws_s3_bucket_server_side_encryption_configuration.app
# aws_s3_bucket_versioning.app

# Full state details of one resource — reads from state, no AWS API calls
terraform state show aws_s3_bucket.app
# resource "aws_s3_bucket" "app" {
#     arn    = "arn:aws:s3:::cloudnova-dev-app-a1b2c3d4"
#     bucket = "cloudnova-dev-app-a1b2c3d4"
#     region = "us-east-2"
# }

# Summary of all managed resources
terraform show

# Query outputs
terraform output bucket_name
terraform output -raw bucket_name      # no quotes — use in shell scripts
terraform output -json                 # all outputs as JSON
```

---

### Step 13 — Introduce drift in Console
Drift is the silent divergence between what Terraform manages and what
actually exists in AWS. Let's make it tangible.

**Introduce drift in Console:**

```
Console → S3 → General purpose buckets → cloudnova-dev-app-xxxxxxxx
  → Properties tab → Tags → Edit
  → Add tag: Key = ManualTag, Value = added-outside-terraform
  → Save changes
```

---

### Step 14 — Detect the drift

**Two ways to see drift — understanding the difference:**

Regular `terraform plan` also detects drift. It calls the provider Read()
API on every managed resource, compares to state, and shows manual changes
as `~` updates in the plan. If you run `terraform apply` from here,
Terraform removes the manual tag AND applies any other pending config changes.

`terraform plan -refresh-only` shows drift **only** — it isolates the drift
detection from any config changes you may have pending. It asks: "do you
want to update state to match reality?" without applying .tf file changes.
Useful when you want to accept drift (keep the manual change in state) rather
than reconcile it.

**For this demo:** we use `-refresh-only` to isolate the drift detection concept,
then regular `terraform apply` to reconcile.


```bash
# Reads actual AWS state, compares to .tfstate, shows what changed
# Makes ZERO changes to infrastructure or state
# Shows ONLY what changed outside Terraform — no config changes included
terraform plan -refresh-only
```

Expected output:

```
Note: Objects have changed outside of Terraform.

  ~ aws_s3_bucket.app
      ~ tags_all = {
          + "ManualTag" = "added-outside-terraform"
            # (5 unchanged elements hidden)
        }

Plan: 0 to add, 0 to change, 0 to destroy.
Changes to Outputs:

Note: Objects have changed outside of Terraform.
Terraform detected the following changes made outside of Terraform since the
last "terraform apply". If you'd like to update the Terraform state to match,
you can run "terraform apply -refresh-only", or
discard it to leave the state as-is.
```

---

### Step 15 — Reconcile — remove the drift

**Reconcile — two choices:**

```bash
# Choice 1: Accept the drift into state (keep the manual tag in state, don't remove it)
terraform apply -refresh-only

# Choice 2: Remove the drift (reconcile AWS back to desired state)
terraform apply
# This removes ManualTag because it is not in your .tf files
```

For this demo use **Choice 2** — remove the drift. This is the correct
production behaviour: Terraform is the single source of truth.

```bash
terraform apply
# aws_s3_bucket.app will be updated:
#   ~ tags_all = { - "ManualTag" = "added-outside-terraform" }
# Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```


**Verify in Console:**

```
Console → S3 → cloudnova-dev-app-xxxxxxxx → Properties → Tags
  → ManualTag is GONE ✅
  → Only Terraform-managed tags remain ✅
```

---

## Cleanup

> ⚠️ **Run cleanup at the end of every session.** S3 buckets with no
> objects are free, but good hygiene means destroying demo resources
> completely.

### Step 16 — Destroy app resources

```bash
terraform destroy
```

Type `yes`. Expected:

```
aws_s3_bucket_public_access_block.app: Destroying...
aws_s3_bucket_server_side_encryption_configuration.app: Destroying...
aws_s3_bucket_versioning.app: Destroying...
aws_s3_bucket_public_access_block.app: Destruction complete after 1s
aws_s3_bucket_server_side_encryption_configuration.app: Destruction complete after 1s
aws_s3_bucket_versioning.app: Destruction complete after 1s
aws_s3_bucket.app: Destroying...
aws_s3_bucket.app: Destruction complete after 2s
random_id.suffix: Destroying...
random_id.suffix: Destruction complete after 0s

Destroy complete! Resources: 5 destroyed.
```

**Verify in Console:**

```
Console → S3 → Buckets
  → cloudnova-dev-app-xxxxxxxx: GONE ✅
```

### Step 17 — Delete backend.tf and the state bucket

The state bucket was created outside Terraform (Console), so it must be
deleted outside Terraform (Console) too.

**Remove backend.tf first:**

```bash
# Remove backend.tf so Terraform reverts to local state
# (if you don't, the next terraform init will fail — bucket no longer exists)
rm src/backend.tf
```

**Empty the state bucket in Console:**

```
Console → S3 → tfstate-cloudnova-163125980376-us-east-2
  → Empty button (top right)
  → Type "permanently delete" to confirm
  → Empty bucket ✅

(Empty removes all objects AND all versioned objects including the
 state file and all its versions — no CLI needed)
```

**Delete the state bucket in Console:**

```
Console → S3 → tfstate-cloudnova-163125980376-us-east-2
  → Delete button
  → Type the bucket name to confirm
  → Delete bucket ✅
```

**Verify:**

```
Console → S3 → Buckets
  → tfstate-cloudnova-163125980376-us-east-2: GONE ✅
  → cloudnova-dev-app-xxxxxxxx: GONE ✅
```

---

## What You Learned

1. ✅ AWS provider v5 = 5.x (May 2023), v6 = 6.x (June 2025). v6 removed
   all inline S3 nested blocks — all configuration uses standalone resources.
2. ✅ `provider "aws"` configures region, named profile, and `default_tags`
   that auto-apply to every resource without repeating them individually.
3. ✅ Four standalone resources make a production-grade S3 bucket in v6:
   bucket, versioning, encryption, public-access block.
4. ✅ `depends_on` is a meta-argument. S3 eventual consistency means the
   implicit reference is not enough — `depends_on` adds sequential execution
   to prevent NoSuchBucket race condition errors.
5. ✅ Local state breaks for teams — two engineers with different copies
   of state create duplicate resources. Remote state in S3 is the solution.
6. ✅ State locking prevents simultaneous applies from corrupting state.
   `use_lockfile = true` uses S3 conditional writes — no DynamoDB needed.
7. ✅ `terraform init -migrate-state` copies local state to S3 without
   data loss. Local file becomes stale backup.
8. ✅ `terraform state list/show` reads from state without API calls.
   `terraform plan -refresh-only` detects drift without making changes.
9. ✅ `terraform apply` reconciles AWS back to desired state — removing
   anything not in `.tf` files.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| AWS provider v5 vs v6, version constraints (`~> 6.47.0`) | TA-004 Obj 2a/2b — Providers and version constraints | Exam trap: "Where does Terraform download providers?" → `registry.terraform.io` |
| `aws_s3_bucket` + 3 standalone config resources | TA-004 Obj 4 — Resource configuration | v6 pattern — no inline `versioning {}` etc. |
| `depends_on` meta-argument | TA-004 Obj 4 | S3 eventual consistency — implicit reference alone is insufficient |
| State purpose, `terraform.tfstate` | TA-004 Obj 2d — State purpose | "What happens if you delete terraform.tfstate?" → Terraform loses track of everything; next apply recreates it all |
| `backend "s3"`, remote state | TA-004 Obj 5a — Remote backends | Team collaboration, no local state loss, CI/CD integration |
| `use_lockfile = true` | TA-004 Obj 5b — State locking | See deprecation note in Concepts — DynamoDB no longer required |
| `terraform init -migrate-state` | TA-004 Obj 3a–3e — Core workflow | Prompts for confirmation before copying, never automatic |
| `terraform plan -refresh-only` / `apply -refresh-only` | TA-004 Obj 3 — Drift detection | Refresh-only isolates drift detection from pending config changes |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Does `terraform plan` make any changes to infrastructure or state?" | No — read-only, calls provider `Read()` only | Assuming `plan` writes to state because it performs a refresh |
| "Is DynamoDB required for S3 state locking in Terraform 1.11+?" | No — `use_lockfile = true` uses S3 conditional writes | Assuming DynamoDB is still mandatory because older guides say so |
| "Can local state be locked?" | No — locking requires shared remote state; a local lock protects nothing | Assuming locking applies regardless of backend type |
| "What happens if two engineers apply simultaneously against S3-locked state?" | Second apply fails immediately with "Error acquiring the state lock" | Assuming the second apply queues and waits |
| "Does `depends_on` need to be used everywhere two resources reference each other?" | No — only needed when a dependency can't be expressed via attribute reference (e.g. eventual consistency, not data flow) | Adding `depends_on` redundantly where an implicit reference already creates the dependency |

### Exam Task — Write a complete configuration

**Task:** Write a Terraform configuration for a single S3 bucket with versioning enabled, AES256 encryption, and all public access blocked, using AWS provider v6 standalone resources.

**Block types required:** `terraform`, `provider`, `resource` (×4), `depends_on` meta-argument

**Official documentation:**
- [`aws_s3_bucket_versioning` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning)
- [`aws_s3_bucket_public_access_block` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block)

**What to practise:**
1. Open both registry pages — check the Argument Reference sections
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

resource "aws_s3_bucket" "app" {
  bucket = "cloudnova-exam-task-demo"
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration {
    status = "Enabled"
  }
  depends_on = [aws_s3_bucket.app]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
  depends_on = [aws_s3_bucket.app]
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.app]
}
```

**Arguments you must know without looking up:**
- `versioning_configuration.status` — must be `Enabled` or `Suspended`, never `Disabled` once versioning has been turned on
- All four booleans on `aws_s3_bucket_public_access_block` must be `true` together — partial protection leaves gaps

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `BucketAlreadyExists` | S3 names are globally unique across all AWS accounts | Add `random_id` suffix or change the name |
| `AccessDenied` on list-buckets | IAM permissions not set | Attach `AmazonS3FullAccess` to your IAM user |
| `NoSuchPublicAccessBlockConfiguration` | S3 race condition | Confirm `depends_on = [aws_s3_bucket.app]` on all config resources |
| `Error acquiring the state lock` | Another apply running or lock stuck | Wait, or `terraform force-unlock <ID>` if certain no apply is running |
| `Backend configuration changed` | `backend.tf` edited after init | Run `terraform init -reconfigure` |
| `Error: state data in S3 does not have the expected content` | State file corrupted or wrong key | Check S3 key path in backend.tf matches actual file location |
| `BucketNotEmpty` on state bucket delete | Objects still in bucket | Use Console → Empty bucket first, then Delete |
| `InvalidLocationConstraint` | `us-east-1` has different bucket creation syntax | `us-east-1` does not need `LocationConstraint` — all other regions do |
| `An argument named "versioning" is not expected here` | v5 inline syntax used with v6 provider | Remove inline block, use `aws_s3_bucket_versioning` standalone resource |

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

resource "aws_s3_bucket" "app" {
  bucket = "cloudnova-break-fix-demo"

  versioning {              # Error 1
    enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.main.id    # Error 2

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = True    # Error 3
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — `versioning {}` inline block inside `aws_s3_bucket`**
Inline versioning blocks are deprecated in AWS provider v6. Terraform
will show: `An argument named "versioning" is not expected here.`
Fix: remove the inline block. Create a separate
`aws_s3_bucket_versioning` resource.

**Error 2 — `aws_s3_bucket.main.id`**
The bucket resource is named `app`, not `main`. The reference must match
the local name exactly. Terraform will show: `Reference to undeclared resource`.
Fix: `aws_s3_bucket.app.id`

**Error 3 — `restrict_public_buckets = True`**
HCL booleans are always lowercase. `True` is invalid.
Fix: `restrict_public_buckets = true`

</details>

**Cleanup:**

```bash
# Still inside src/break-fix/
terraform destroy -auto-approve
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup

# Verify — clean state
ls -la
# Only broken.tf should remain
```

---

## Interview Prep

**Q1. A junior engineer copies an S3 bucket example from a tutorial they found online. `terraform validate` fails with `An argument named "versioning" is not expected here`. How do you explain what's wrong?**
The tutorial was written for AWS provider v5, where S3 settings like `versioning`, `server_side_encryption_configuration`, and `lifecycle_rule` were nested inline inside the `aws_s3_bucket` resource. AWS provider v6 (released June 2025) removed all of these inline blocks — each setting is now its own standalone resource: `aws_s3_bucket_versioning`, `aws_s3_bucket_server_side_encryption_configuration`, `aws_s3_bucket_public_access_block`, and so on, each referencing the bucket via `bucket = aws_s3_bucket.app.id`. The practical takeaway for the team: before copying any Terraform example found online, check which provider version it targets — a lot of older content, Stack Overflow answers, and even some courses still show v5 syntax, which will fail validation against v6.

**Q2. During `terraform apply`, `aws_s3_bucket_public_access_block` fails intermittently with `NoSuchPublicAccessBlockConfiguration`, but re-running `apply` immediately succeeds. What's happening, and what's the permanent fix?**
This is an S3 eventual-consistency race condition, not a flaky network issue. When `aws_s3_bucket.app` finishes creating, AWS's API returns `200 OK`, but the bucket may not have fully propagated across all of S3's internal systems yet. If `aws_s3_bucket_public_access_block` starts immediately afterward — which Terraform will do based on the implicit attribute reference alone — AWS may reject the configuration call because its internal systems aren't ready. The permanent fix is `depends_on = [aws_s3_bucket.app]` on every S3 configuration resource (versioning, encryption, public access block). `depends_on` tells Terraform to wait until the bucket resource has *fully completed*, not just returned success, giving AWS the propagation time it needs. Re-running `apply` "fixes" it by chance — the second attempt happens after enough time has passed — but that's not a reliable production pattern.

**Q3. Your team is about to onboard a second engineer who will also run `terraform apply` against the same infrastructure. What changes are required before that happens, and why can't you wait?**
Before a second engineer applies against the same configuration, state must move from local to a remote backend with locking — in this demo, S3 with `use_lockfile = true`. With local state, each engineer's `terraform.tfstate` is an independent snapshot on their own machine. If both engineers run `apply` based on different (possibly stale) copies of state, their changes can conflict — one apply's results overwrite the other's in state, even though both sets of resources exist in AWS. The fix isn't optional once a second person is involved; it's foundational. State locking via `use_lockfile = true` additionally prevents two simultaneous applies from corrupting the shared state file — if Engineer A's apply is running, Engineer B's apply will fail immediately with "Error acquiring the state lock" rather than racing.

**Q4. Someone manually adds a tag to an S3 bucket through the Console "just to test something," then forgets about it. Three weeks later, `terraform plan` shows an unexpected change. Walk through what happened and how to resolve it.**
This is drift — a Terraform-managed resource was modified outside Terraform. Running `terraform plan -refresh-only` would show the discrepancy in isolation: Terraform calls the provider's `Read()` function, sees the extra tag in actual AWS state, compares it against the last-known `.tfstate`, and reports the difference without making any changes. From here there are two choices: `terraform apply -refresh-only` accepts the drift into state (keeping the manual tag), or a normal `terraform apply` reconciles AWS back to match the `.tf` files — removing the manually added tag because it's not declared in code. The correct production behavior is almost always the second option: Terraform is the source of truth, and untracked manual changes should be removed, not silently absorbed. The broader lesson for the team: any change that needs to persist must go into the `.tf` files and through review — Console edits, even "temporary" ones, create exactly this kind of surprise.

**Q5. A teammate asks: "Why do we need a separate S3 bucket just to hold the state file? Why not just create everything — including the state bucket — with one `terraform apply`?"**
This is the chicken-and-egg problem with remote state. Before `terraform init` can configure the S3 backend, the bucket that will hold the state file must already exist — Terraform needs somewhere to write its state *before* it can manage anything, including the bucket meant to store that state. If you tried to define the state bucket as a resource in the same configuration that uses it as a backend, you'd have a circular dependency: Terraform can't create the bucket because it needs the bucket to track that it created it. The practical solution is to create the state bucket manually (via Console or a one-off `aws s3api create-bucket` command) as a one-time bootstrap step, completely outside the Terraform configuration that will use it.

---

## Key Takeaways

1. **AWS provider version changes are breaking changes.** v5 → v6
   changed S3 fundamentally. Always check which provider version an
   example was written for before copying it.

2. **`depends_on` on S3 config resources is a real-world requirement.**
   AWS S3 eventual consistency means the implicit reference is not
   sufficient. This affects most AWS resources that have configuration
   applied shortly after creation — not just S3.

3. **Remote state + locking from day one.** Do not wait until the second
   engineer joins. Set up the remote backend before the first shared apply.
   `use_lockfile = true` — no DynamoDB, no extra cost, no extra dependency.

4. **`terraform plan -refresh-only` is your drift detector.** Run it
   before any apply in a shared environment to see if anything changed
   outside Terraform. Make it a team habit before every apply.

5. **S3 bucket versioning on the state bucket is your safety net.** Every
   apply creates a new version. If state corrupts, download the previous
   version from Console and restore with `terraform state push`.

6. **Do NOT use the `dynamodb_table` backend argument.** Deprecated since
   Terraform 1.11 — `use_lockfile = true` replaces it with no extra AWS
   resource, no extra cost, no extra IAM permissions.

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws sts get-caller-identity --profile <PROFILE>` | Confirms which AWS account and identity the named profile authenticates as |
| `aws s3api list-buckets --profile <PROFILE>` | Lists S3 buckets to verify the profile has S3 permissions |
| `terraform init` | Downloads providers and initialises the backend (local, before Part B) |
| `terraform validate` | Checks configuration syntax and schema with zero API calls |
| `terraform fmt` | Auto-formats `.tf` files to canonical style |
| `terraform plan` | Previews changes against AWS, including a read-only refresh |
| `terraform apply` | Applies pending changes after confirmation |
| `terraform init -migrate-state` | Copies existing local state into a newly configured remote backend |
| `terraform plan -refresh-only` | Shows drift only, without proposing or making any changes |
| `terraform apply -refresh-only` | Accepts detected drift into state without changing AWS |
| `terraform state list` | Lists every resource address tracked in state |
| `terraform state show <ADDRESS>` | Shows full state details for one resource, no AWS API calls |
| `terraform destroy` | Destroys all resources managed by this configuration |

---

## Next Demo

**Demo 02 — `02-providers`:** Deep dive into providers — multiple providers,
aliases, version constraints in depth, lock file anatomy, and authentication
patterns for CI/CD.

---

## Appendix — Anki Cards

**01-tf-fundamentals-s3-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::01-tf-fundamentals-s3
#separator:Comma
#columns:Front,Back,Tags
"You get: NoSuchPublicAccessBlockConfiguration when applying aws_s3_bucket_public_access_block. What causes this and how do you fix it?","Race condition — AWS S3 eventual consistency. CreateBucket returned 200 OK but the bucket had not fully propagated internally when PutPublicAccessBlock was called. Fix: add depends_on = [aws_s3_bucket.app] to the public access block resource. This forces sequential execution.","demo01,s3,depends_on,race-condition,ta004-obj4,needs-verification"
"What is a meta-argument in Terraform? Name all five.","A meta-argument is a special argument available on every resource block regardless of provider — controls Terraform's own behaviour. The five: depends_on (explicit dependency), count (N copies), for_each (one per map/set item), provider (which alias), lifecycle (create/update/delete behaviour).","demo01,meta-arguments,ta004-obj4"
"What does depends_on do differently from an implicit attribute reference?","Implicit reference (aws_s3_bucket.app.id): creates graph dependency, starts dependent immediately when bucket API returns 200. depends_on: waits for the dependency to fully complete ALL operations before starting the dependent — gives AWS time to propagate internally.","demo01,depends_on,s3,ta004-obj4"
"What specific versions are AWS provider v5 and v6?","v5 = versions 5.x, released May 2023. v6 = versions 6.x, released June 2025 with breaking changes from v5. This series uses v6.47.0. Key v6 change: all S3 inline configuration blocks removed — standalone resources required.","demo01,provider,versions,ta004-obj2"
"In AWS provider v6 you write versioning {} inside aws_s3_bucket. What happens?","terraform validate errors: An argument named versioning is not expected here. v6 removed all inline S3 blocks. Fix: use aws_s3_bucket_versioning standalone resource.","demo01,s3,v6,ta004-obj2"
"What are the four standalone resources for a production-grade S3 bucket in v6?","1. aws_s3_bucket — the bucket. 2. aws_s3_bucket_versioning — version history. 3. aws_s3_bucket_server_side_encryption_configuration — AES256 or KMS. 4. aws_s3_bucket_public_access_block — all four booleans true.","demo01,s3,v6,ta004-obj4"
"What does default_tags in the AWS provider block do?","Tags in default_tags are automatically merged into every resource created by that provider. No need to write tags = local.common_tags in every resource block. Resource-level tags merge on top — in conflicts the resource-level tag wins.","demo01,provider,tags,ta004-obj2"
"Why must the S3 state bucket be created outside Terraform?","Chicken-and-egg: Terraform needs the state bucket to exist before it can initialise the backend. You cannot use Terraform to create the bucket that stores Terraform's own state. Create via Console first.","demo01,state,backend,ta004-obj5"
"What does terraform init -migrate-state do?","Copies existing local state to the newly configured remote backend. Prompts for confirmation. Local terraform.tfstate becomes stale backup. S3 copy is now authoritative for all future applies.","demo01,state,backend,ta004-obj5,live-verified"
"What is state locking and why is it needed?","Prevents two simultaneous terraform apply runs from corrupting state. Without locking: two applies read same state, both write results, one overwrites the other — resources exist in AWS but disappear from state. Locking ensures only one apply modifies state at a time.","demo01,state,locking,ta004-obj5b"
"Is DynamoDB required for S3 state locking in Terraform 1.11+?","No. use_lockfile = true uses S3 conditional writes to create a .tfstate.tflock file. dynamodb_table is deprecated in v1.11. No DynamoDB table, no extra cost, no extra service dependency.","demo01,state,locking,ta004-obj5b,needs-verification"
"How does S3 native locking work technically?","S3 conditional write attempts to create terraform.tfstate.tflock — only succeeds if the file does not already exist (atomic operation). If file exists: another apply is running — error. When apply finishes: .tflock file deleted. Lock released.","demo01,state,locking,ta004-obj5b,live-verified"
"Can you lock local state? Why or why not?","No. Locking only makes sense for shared remote state. A lock on your local machine protects nothing — no other machine can access your local file. State locking is a coordination mechanism between multiple machines.","demo01,state,locking,ta004-obj5b"
"What does terraform plan -refresh-only do?","Reads actual current state from AWS via provider Read() API, compares to last known state in .tfstate, shows what changed outside Terraform. Makes ZERO changes to infrastructure or state. Use to detect drift.","demo01,drift,plan,ta004-obj3,live-verified"
"After detecting drift with terraform plan -refresh-only, what are your two choices?","1. terraform apply -refresh-only: accepts drift into state — keeps the manual change. 2. terraform apply: removes drift — reconciles AWS back to desired state in .tf files. Choice 2 is correct production behaviour (Terraform is source of truth).","demo01,drift,apply,ta004-obj3,live-verified"
"How much does AES256 (SSE-S3) encryption cost on S3?","Always free — AWS absorbs the cost of S3-managed keys. SSE-KMS (customer-managed keys) is paid: $0.03 per 10,000 requests + $1/month per CMK. Use AES256 unless you need key rotation audit trails.","demo01,s3,encryption"
"What does S3 versioning on the state bucket give you?","Every terraform apply creates a new version of the state file. Recovery procedure: Console → state bucket → terraform.tfstate → Show versions → download older version → terraform state push terraform.tfstate. This is the undo button for state corruption.","demo01,state,versioning"
"Two terraform {} blocks exist — versions.tf and backend.tf. Is this valid?","Yes. Terraform merges all .tf files in a directory. backend {} in backend.tf merges with required_version and required_providers in versions.tf. Only restriction: same setting cannot be declared twice.","demo01,hcl,backend,ta004-obj2"
"What does force_destroy = true on aws_s3_bucket do?","Allows terraform destroy to delete the bucket even if it contains objects — Terraform deletes all objects first. Remove in production — prevents accidental deletion of live data. Use only in demo/test environments.","demo01,s3,force_destroy,needs-verification"
"What is the S3 state bucket naming convention and why?","tfstate-project-accountid-region. Example: tfstate-cloudnova-163125980376-us-east-2. Account ID = globally unique across all AWS accounts. Region = location explicit. Avoids generic names that conflict across projects.","demo01,state,naming"
"List the AWS provider's credential resolution order, highest to lowest precedence.","1. Static credentials in provider block (NEVER use — secrets in version control). 2. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN) — good for CI/CD. 3. Shared credentials file (~/.aws/credentials) + named profile in provider block — this demo's approach. 4. IAM Instance Profile / ECS Task Role — no credentials needed, used in production on AWS. 5. IAM Identity Center (SSO) — corporate standard.","demo01,provider,authentication"
"Name all five Terraform meta-arguments and what each controls.","depends_on (explicit dependency ordering), count (create N copies of a resource), for_each (create one resource per item in a map or set), provider (which provider alias to use), lifecycle (controls create/update/delete behavior). All five are available on any resource block regardless of provider — they control Terraform's own behavior, not something the AWS API understands.","demo01,meta-arguments"
"Name five S3-related resources NOT used in this demo and what each does.","aws_s3_bucket_lifecycle_configuration (auto-delete/archive objects after N days), aws_s3_bucket_cors_configuration (allow browser cross-origin requests), aws_s3_bucket_website_configuration (host a static website), aws_s3_bucket_replication_configuration (cross-region replication), aws_s3_object (upload a file into a bucket).","demo01,s3,related-resources"
```

---

## Appendix — Quiz

**01-tf-fundamentals-s3-quiz.md:**

````markdown
# Quiz — Demo 01: Terraform Fundamentals: First Real AWS Project with S3

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 02.

---

**Q1. (True/False)** The Terraform CLI and the AWS provider are
versioned together as one package — upgrading one always upgrades the
other.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** They are two completely independent, separately versioned
software packages. Terraform CLI (e.g. `v1.15.0`) is the engine; the AWS
provider (e.g. `v6.47.0`) is a plugin downloaded on `init`. A new AWS
service feature requires a provider update, not a CLI update.

</details>

---

**Q2. (Multiple Choice)** Why did AWS provider v6 move S3 settings like
versioning and encryption out of inline blocks inside `aws_s3_bucket`
into their own standalone resources?

- A) Inline blocks were removed for performance reasons
- B) Standalone resources allow each setting to be independently managed, imported, or removed without affecting the bucket resource itself
- C) AWS's API no longer supports nested configuration
- D) Standalone resources are required for `terraform fmt` to work correctly

<details>
<summary>Answer</summary>

**B.** The whole point of the v6 change is fine-grained control — each
setting can now be imported, modified, or removed independently of the
bucket resource and of each other. This has nothing to do with
performance (A), AWS's actual API (C), or formatting (D).

</details>

---

**Q3. (Multiple Choice)** Which AWS provider authentication method
should never be used in a real configuration?

- A) Named profile via `profile = "default"`
- B) Static credentials directly in the provider block (`access_key`/`secret_key`)
- C) Environment variables (`AWS_ACCESS_KEY_ID`)
- D) IAM Instance Profile / ECS Task Role

<details>
<summary>Answer</summary>

**B.** Static credentials hardcoded into the provider block get
committed to version control the moment the file is committed — a
direct secrets leak. Every other method (named profile, environment
variables, instance role, SSO) avoids putting the secret directly into
a tracked file.

</details>

---

**Q4. (True/False)** `random_id.suffix.hex` generates a new random value
on every `terraform apply`, so the bucket name changes each time.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `random_id` generates its value once, on first apply, and
stores it in state. Every subsequent apply reuses the same stored value
— the bucket name stays stable across applies unless the resource is
explicitly replaced (e.g. `-replace`).

</details>

---

**Q5. (Multiple Choice)** Once `aws_s3_bucket_versioning`'s status has
been set to `Enabled`, can it later be fully turned off (`Disabled`)?

- A) Yes, set `status = "Disabled"` at any time
- B) No — once enabled, it can only be `Suspended`, never fully disabled
- C) Only by destroying and recreating the bucket
- D) Only via the AWS CLI, not Terraform

<details>
<summary>Answer</summary>

**B.** `Disabled` is only valid for a bucket that has *never* had
versioning enabled. Once enabled, the only way to stop new versions is
`Suspended` — existing versions are kept, but no new ones are created.
This is an AWS S3 constraint, not a Terraform limitation.

</details>

---

**Q6. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about `aws_s3_bucket_public_access_block`'s four boolean
arguments are correct?

- A) All four default to `true`
- B) All four default to `false`
- C) Setting only `block_public_policy = true` provides complete protection
- D) All four must be set to `true` together for complete protection — a public ACL can bypass a blocked policy and vice versa
- E) `block_public_acls` only affects individual objects, never the bucket itself

<details>
<summary>Answer</summary>

**B and D.** All four arguments default to `false` — protection is opt-in,
not automatic. Setting only some of them leaves real gaps (C is wrong):
a public ACL can grant access even with a blocked policy, and vice
versa, which is exactly why all four together (D) are needed for
complete protection. E is wrong — `block_public_acls` affects both
bucket-level and object-level ACLs.

</details>

---

**Q7. (Multiple Choice)** What is the cost difference between SSE-S3
(`AES256`) and SSE-KMS encryption on an S3 bucket?

- A) Both are always free
- B) SSE-S3 is free; SSE-KMS costs $0.03/10,000 requests plus ~$1/month per key
- C) SSE-S3 costs more because it's the newer standard
- D) Both are billed per GB stored, regardless of algorithm

<details>
<summary>Answer</summary>

**B.** SSE-S3 (AES256) uses AWS-managed keys and is always free. SSE-KMS
uses customer-managed keys via AWS KMS, which bills per API request plus
a monthly per-key charge — the tradeoff is finer-grained key control and
audit trails.

</details>

---

**Q8. (Multiple Choice)** Which of the following is one of Terraform's
five meta-arguments (arguments that control Terraform's own behavior,
independent of any provider)?

- A) `region`
- B) `tags`
- C) `lifecycle`
- D) `bucket`

<details>
<summary>Answer</summary>

**C.** The five meta-arguments are `depends_on`, `count`, `for_each`,
`provider`, and `lifecycle`. `region`, `tags`, and `bucket` are all
ordinary resource-specific arguments the AWS provider itself
understands — not meta-arguments.

</details>

---

**Q9. (Multiple Choice)** `aws_s3_bucket_public_access_block.app`
references `aws_s3_bucket.app.id`, which already creates an implicit
dependency. Why is an explicit `depends_on` still needed for S3
specifically?

- A) Implicit references don't work for S3 resources at all
- B) `CreateBucket` returning `200 OK` doesn't guarantee the bucket has fully propagated across S3's internal systems yet — `depends_on` waits for full completion, not just a successful API response
- C) `depends_on` is required syntax for every `aws_s3_bucket_*` resource regardless of ordering
- D) The implicit reference only works if `force_destroy = true` is set

<details>
<summary>Answer</summary>

**B.** This is AWS S3's eventual consistency model — a real AWS
behavior, not a Terraform limitation. The implicit reference correctly
orders bucket creation before the configuration resource, but Terraform
considers the bucket "done" as soon as the API call succeeds, which can
be before AWS's internal systems are fully ready. `depends_on` adds a
wait for full completion, giving that propagation gap time to close.

</details>

---

**Q10. (Multiple Choice)** Two engineers both use local Terraform state
against the same configuration. Engineer B clones the repo (no state
file included) and adds a resource. What is the most likely result of
Engineer B's `apply`?

- A) Terraform automatically detects Engineer A's existing resources
- B) Engineer B's plan shows zero existing resources, so it attempts to create everything from scratch — risking duplicates or `AlreadyExists` errors
- C) The apply is blocked entirely until state is manually merged
- D) Git resolves the state conflict automatically on push

<details>
<summary>Answer</summary>

**B.** With no local state file, Terraform has no memory of what
Engineer A already created — it plans as if nothing exists yet. This
either fails with an "already exists" error, or worse, silently creates
duplicate resources with different random suffixes. Neither engineer
now has a state file that reflects reality.

</details>

---

**Q11. (True/False)** Only `terraform apply` acquires a state lock;
`terraform plan` never touches the lock.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `terraform plan` also briefly acquires the state lock
during its refresh step, even though it makes no changes — this is a
commonly tested exam trap.

</details>

---

**Q12. (Multiple Choice)** Is a DynamoDB table required for S3 backend
state locking in Terraform 1.11+?

- A) Yes — DynamoDB is the only supported locking mechanism for S3 backends
- B) No — `use_lockfile = true` uses S3 conditional writes; `dynamodb_table` is deprecated
- C) No — locking was removed entirely in 1.11
- D) Yes, but only for buckets outside `us-east-2`

<details>
<summary>Answer</summary>

**B.** Terraform 1.10 introduced S3 native locking via conditional
writes, creating a `.tflock` file directly in the state bucket — no
DynamoDB table, no extra IAM permissions, no extra monthly cost. The
older `dynamodb_table` backend argument is deprecated as of v1.11.

</details>

---

**Q13. (Multiple Choice)** Can `var.aws_region` be used inside a
`backend "s3"` block to set the `region` argument dynamically?

- A) Yes, exactly like any other resource argument
- B) No — the backend block is evaluated before variables are loaded, so `Variables may not be used here` is the resulting error
- C) Yes, but only if the variable has a `default` value
- D) No — backend blocks don't support the `region` argument at all

<details>
<summary>Answer</summary>

**B.** The backend block is resolved before any provider initializes and
before variables are loaded — there's no variable resolution available
at that point in the process. This is why `backend.tf` always has
hardcoded values; the production workaround is partial backend
configuration via `-backend-config` flags or a `.tfbackend` file.

</details>

---

**Q14. (Multiple Choice)** What does `terraform init -migrate-state` do
to the local `terraform.tfstate` file?

- A) Deletes it immediately after copying
- B) Copies its contents to the new backend and prompts for confirmation first; the local file becomes a stale, unused backup
- C) Merges it with any existing state already in the new backend
- D) Converts it into the `.tflock` file format

<details>
<summary>Answer</summary>

**B.** `init -migrate-state` prompts for confirmation before copying —
never automatic — then copies local state to the new backend. The S3
copy becomes authoritative; the local file is left on disk as a stale
backup, not deleted or actively used going forward.

</details>

---

**Q15. (True/False)** `terraform state show <address>` makes a read-only
API call to AWS to fetch the resource's current live attributes.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `state show` reads only from the state file already on
disk (or in the backend) — it makes zero AWS API calls. This is
different from `terraform show` after a `plan`/`apply` refresh, and very
different from `plan` itself, which does refresh via API calls.

</details>

---

**Q16. (Multiple Choice)** After running `terraform plan -refresh-only`
and confirming drift exists, what are the two available responses?

- A) `apply -refresh-only` (accept the drift into state) or plain `apply` (reconcile AWS back to match `.tf` files)
- B) `destroy` and recreate, or ignore it permanently
- C) `state rm` the resource, or manually edit the state file
- D) There is only one option: plain `apply`

<details>
<summary>Answer</summary>

**A.** `apply -refresh-only` accepts the drift by updating state to
match the observed reality, without touching `.tf` files or removing
the manual change. A plain `apply` reconciles the opposite direction —
removing whatever isn't declared in `.tf`. Production default is
usually the latter, since Terraform should remain the source of truth.

</details>

---

**Q17. (Multiple Choice)** What is a required condition before running
`terraform force-unlock <LOCK_ID>`?

- A) None — it's always safe to run immediately when a lock error appears
- B) Confirming that no apply is actually still running — force-unlock does not verify this itself
- C) The lock must be older than 24 hours
- D) It can only be run by the same engineer who created the lock

<details>
<summary>Answer</summary>

**B.** `force-unlock` simply removes the lock — it performs no check on
whether an apply is genuinely still in progress. Using it while a real
apply is running allows two concurrent writers and risks exactly the
state corruption locking exists to prevent. Always confirm first (e.g.
check with the team, check CI status).

</details>

---

**Q18. (Multiple Choice)** Why must the S3 bucket that stores Terraform
state be created outside of Terraform (e.g. via Console), rather than
as a resource inside the same configuration?

- A) Terraform cannot create S3 buckets at all
- B) It's a chicken-and-egg problem — Terraform needs the backend bucket to exist before `init` can configure the backend that would store state about creating that same bucket
- C) AWS restricts state buckets to being created only via the Console
- D) It's a stylistic convention, not a technical requirement

<details>
<summary>Answer</summary>

**B.** This is a genuine circular dependency, not just a convention.
`terraform init` needs to connect to a backend bucket before it can
manage anything — including a resource meant to create that very
bucket. The bootstrap step (creating the state bucket) must happen
outside the configuration that will use it as a backend.

</details>

---

**Q19. (Multiple Choice)** What does `aws_s3_bucket`'s `force_destroy`
argument control, and when is it appropriate to use?

- A) Forces immediate deletion regardless of versioning — safe for production
- B) When `true`, allows `terraform destroy` to empty a non-empty bucket before deleting it — intended for demo/test environments only
- C) Forces the bucket to be recreated on every apply
- D) Prevents accidental deletion by requiring a second confirmation

<details>
<summary>Answer</summary>

**B.** With `force_destroy = true`, `destroy` will delete all objects in
the bucket first, then the bucket itself — without it, `destroy` fails
on any non-empty bucket. This should be removed in production, since it
makes accidental data loss much easier.

</details>

---

**Q20. (Multiple Choice)** Which of the following S3-related resources
was NOT used in this demo, and what does it do?

- A) `aws_s3_bucket_versioning` — enables object version history
- B) `aws_s3_bucket_lifecycle_configuration` — auto-deletes or archives objects after N days
- C) `aws_s3_bucket_public_access_block` — blocks public access paths
- D) `aws_s3_bucket_server_side_encryption_configuration` — encrypts objects at rest

<details>
<summary>Answer</summary>

**B.** `aws_s3_bucket_lifecycle_configuration` is a related resource
mentioned as "worth knowing" but not actually used in this demo's
configuration — it manages automatic transition/expiration rules for
objects over time. The other three (A, C, D) are all part of this
demo's four core standalone resources.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 19-20/20 | Import Anki cards, move to Demo 02 |
| 16-18/20 | Review the wrong answers, then proceed |
| 14-15/20 | Re-read the relevant sections, retry those questions |
| Below 14/20 | Re-read the full demo and redo the walkthrough before proceeding |
````