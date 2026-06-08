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

```
┌─────────────────────────────────────────────────────────────────────────┐
│  SCENARIO: Two engineers, local state                                   │
│                                                                          │
│  Engineer A runs terraform apply at 2pm.                                │
│  State on A's machine: vpc=vpc-111, subnet=subnet-222                   │
│                                                                          │
│  Engineer B's machine has a copy of state from yesterday.               │
│  State on B's machine: vpc=vpc-111 (no subnet yet)                      │
│                                                                          │
│  Engineer B runs terraform apply at 2:05pm.                             │
│  B's Terraform compares desired state against B's STALE state.          │
│  B's plan says subnet-222 does not exist → creates a second subnet.     │
│  Now there are TWO subnets. State on B's machine says one exists.       │
│  State on A's machine says one exists. Both are wrong.                  │
│                                                                          │
│  Next engineer to apply will create a THIRD subnet.                     │
│  Production infrastructure diverges silently.                           │
└─────────────────────────────────────────────────────────────────────────┘
```

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
| `bucket` | Yes | Name of the S3 bucket that stores the state file |
| `key` | Yes | Path within the bucket: `phase/demo/terraform.tfstate`. Like a folder+filename inside the bucket. |
| `region` | Yes | AWS region of the state bucket |
| `profile` | No | Named AWS profile to authenticate with |
| `encrypt` | No (default: `false`) | Encrypt the state file at rest in S3 |
| `use_lockfile` | No (default: `false`) | Enable S3 native locking — creates `.tflock` file. No DynamoDB needed. |

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

**Verify the state file in Console:**

```
Console → S3 → tfstate-cloudnova-163125980376-us-east-2
  → Browse: phase-1/ → 01-tf-fundamentals-s3/
  → terraform.tfstate ✅  (the migrated state file)

Click terraform.tfstate → Object actions → Open
  → You can read the JSON — see all 5 resources recorded
```

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
Console → S3 → cloudnova-dev-app-xxxxxxxx
  → Properties tab → Tags → Edit
  → Add tag: Key = ManualTag, Value = added-outside-terraform
  → Save changes
```

---

### Step 14 — Detect the drift

```bash
# Reads actual AWS state, compares to .tfstate, shows what changed
# Makes ZERO changes to infrastructure or state
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

## Cert Tips — TA-004 Objectives Covered

**Objective 2a/2b — Providers and version constraints:**
> Providers are separately versioned plugins. `~> 6.47.0` allows 6.47.x
> patches, rejects 6.48+. Exam: "Where does Terraform download providers?"
> → `registry.terraform.io`

**Objective 2d — State purpose:**
> State maps Terraform resource addresses to real-world infrastructure IDs.
> Without state: Terraform cannot detect drift or know what it manages.
> Exam: "What happens if you delete terraform.tfstate?" → Terraform loses
> track of everything; next apply tries to create all resources again.

**Objective 5a — Remote backends:**
> Remote backends store state outside the local machine — S3, HCP Terraform,
> Azure Blob. Exam: "What is the benefit of remote state?" → team
> collaboration, no local state loss, CI/CD integration.

**Objective 5b — State locking:**
> Locking prevents concurrent applies from corrupting state. Exam traps:

| Question | Answer |
|---|---|
| Is DynamoDB required for S3 locking? | **No** — deprecated in v1.11, use `use_lockfile = true` |
| What does `terraform force-unlock` do? | Releases a stuck lock — only when NO apply is running |
| Does `terraform plan` lock state? | **Yes** — briefly during refresh |
| What file does S3 locking create? | `.tfstate.tflock` — same path as state file |
| Can local state be locked? | **No** — locking requires shared remote state |

**Objective 3a–3e — Core workflow:**
> `terraform init -migrate-state` is a variant of `terraform init` that
> copies existing state to a new backend configuration. It prompts for
> confirmation before copying — never automatic.

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
"You get: NoSuchPublicAccessBlockConfiguration when applying aws_s3_bucket_public_access_block. What causes this and how do you fix it?","Race condition — AWS S3 eventual consistency. CreateBucket returned 200 OK but the bucket had not fully propagated internally when PutPublicAccessBlock was called. Fix: add depends_on = [aws_s3_bucket.app] to the public access block resource. This forces sequential execution.","demo01,s3,depends_on,race-condition,ta004-obj4"
"What is a meta-argument in Terraform? Name all five.","A meta-argument is a special argument available on every resource block regardless of provider — controls Terraform's own behaviour. The five: depends_on (explicit dependency), count (N copies), for_each (one per map/set item), provider (which alias), lifecycle (create/update/delete behaviour).","demo01,meta-arguments,ta004-obj4"
"What does depends_on do differently from an implicit attribute reference?","Implicit reference (aws_s3_bucket.app.id): creates graph dependency, starts dependent immediately when bucket API returns 200. depends_on: waits for the dependency to fully complete ALL operations before starting the dependent — gives AWS time to propagate internally.","demo01,depends_on,s3,ta004-obj4"
"What specific versions are AWS provider v5 and v6?","v5 = versions 5.x, released May 2023. v6 = versions 6.x, released June 2025 with breaking changes from v5. This series uses v6.47.0. Key v6 change: all S3 inline configuration blocks removed — standalone resources required.","demo01,provider,versions,ta004-obj2"
"In AWS provider v6 you write versioning {} inside aws_s3_bucket. What happens?","terraform validate errors: An argument named versioning is not expected here. v6 removed all inline S3 blocks. Fix: use aws_s3_bucket_versioning standalone resource.","demo01,s3,v6,ta004-obj2"
"What are the four standalone resources for a production-grade S3 bucket in v6?","1. aws_s3_bucket — the bucket. 2. aws_s3_bucket_versioning — version history. 3. aws_s3_bucket_server_side_encryption_configuration — AES256 or KMS. 4. aws_s3_bucket_public_access_block — all four booleans true.","demo01,s3,v6,ta004-obj4"
"What does default_tags in the AWS provider block do?","Tags in default_tags are automatically merged into every resource created by that provider. No need to write tags = local.common_tags in every resource block. Resource-level tags merge on top — in conflicts the resource-level tag wins.","demo01,provider,tags,ta004-obj2"
"Why must the S3 state bucket be created outside Terraform?","Chicken-and-egg: Terraform needs the state bucket to exist before it can initialise the backend. You cannot use Terraform to create the bucket that stores Terraform's own state. Create via Console first.","demo01,state,backend,ta004-obj5"
"What does terraform init -migrate-state do?","Copies existing local state to the newly configured remote backend. Prompts for confirmation. Local terraform.tfstate becomes stale backup. S3 copy is now authoritative for all future applies.","demo01,state,backend,ta004-obj5"
"What is state locking and why is it needed?","Prevents two simultaneous terraform apply runs from corrupting state. Without locking: two applies read same state, both write results, one overwrites the other — resources exist in AWS but disappear from state. Locking ensures only one apply modifies state at a time.","demo01,state,locking,ta004-obj5b"
"Is DynamoDB required for S3 state locking in Terraform 1.11+?","No. use_lockfile = true uses S3 conditional writes to create a .tfstate.tflock file. dynamodb_table is deprecated in v1.11. No DynamoDB table, no extra cost, no extra service dependency.","demo01,state,locking,ta004-obj5b"
"How does S3 native locking work technically?","S3 conditional write attempts to create terraform.tfstate.tflock — only succeeds if the file does not already exist (atomic operation). If file exists: another apply is running — error. When apply finishes: .tflock file deleted. Lock released.","demo01,state,locking,ta004-obj5b"
"Can you lock local state? Why or why not?","No. Locking only makes sense for shared remote state. A lock on your local machine protects nothing — no other machine can access your local file. State locking is a coordination mechanism between multiple machines.","demo01,state,locking,ta004-obj5b"
"What does terraform plan -refresh-only do?","Reads actual current state from AWS via provider Read() API, compares to last known state in .tfstate, shows what changed outside Terraform. Makes ZERO changes to infrastructure or state. Use to detect drift.","demo01,drift,plan,ta004-obj3"
"After detecting drift with terraform plan -refresh-only, what are your two choices?","1. terraform apply -refresh-only: accepts drift into state — keeps the manual change. 2. terraform apply: removes drift — reconciles AWS back to desired state in .tf files. Choice 2 is correct production behaviour (Terraform is source of truth).","demo01,drift,apply,ta004-obj3"
"How much does AES256 (SSE-S3) encryption cost on S3?","Always free — AWS absorbs the cost of S3-managed keys. SSE-KMS (customer-managed keys) is paid: $0.03 per 10,000 requests + $1/month per CMK. Use AES256 unless you need key rotation audit trails.","demo01,s3,encryption"
"What does S3 versioning on the state bucket give you?","Every terraform apply creates a new version of the state file. Recovery procedure: Console → state bucket → terraform.tfstate → Show versions → download older version → terraform state push terraform.tfstate. This is the undo button for state corruption.","demo01,state,versioning"
"Two terraform {} blocks exist — versions.tf and backend.tf. Is this valid?","Yes. Terraform merges all .tf files in a directory. backend {} in backend.tf merges with required_version and required_providers in versions.tf. Only restriction: same setting cannot be declared twice.","demo01,hcl,backend,ta004-obj2"
"What does force_destroy = true on aws_s3_bucket do?","Allows terraform destroy to delete the bucket even if it contains objects — Terraform deletes all objects first. Remove in production — prevents accidental deletion of live data. Use only in demo/test environments.","demo01,s3,force_destroy"
"What is the S3 state bucket naming convention and why?","tfstate-project-accountid-region. Example: tfstate-cloudnova-163125980376-us-east-2. Account ID = globally unique across all AWS accounts. Region = location explicit. Avoids generic names that conflict across projects.","demo01,state,naming"
```

---

## Appendix — Quiz

**01-tf-fundamentals-s3-quiz.md:**

```
# Demo 01 — Quiz

> TA-004 exam style. One correct answer unless stated otherwise.
> Target: 80% or above before moving to Demo 02.

---

**Q1.** You add a `versioning {}` block inside `aws_s3_bucket` using AWS
provider v6.47. What happens when you run `terraform validate`?

- A) Passes — creates bucket with versioning enabled
- B) Errors: An argument named "versioning" is not expected here
- C) Ignores the block — creates bucket without versioning
- D) Automatically creates a separate aws_s3_bucket_versioning resource

<details>
<summary>Answer</summary>

**B** — v6 removed all inline S3 blocks. versioning, server_side_encryption_configuration,
and lifecycle_rule no longer exist inside aws_s3_bucket. Use standalone resources.

</details>

---

**Q2.** Why is `depends_on = [aws_s3_bucket.app]` needed on
`aws_s3_bucket_public_access_block` when the bucket ID is already referenced?

- A) Terraform cannot detect the dependency from the bucket ID reference
- B) AWS S3 eventual consistency — the bucket needs time to propagate internally before configuration applies
- C) It prevents the bucket from being deleted before the public access block
- D) Required syntax by AWS provider v6 schema

<details>
<summary>Answer</summary>

**B** — The reference creates a graph dependency and Terraform creates
the bucket first. But it starts the configuration resource immediately
when CreateBucket returns 200. AWS S3 is eventually consistent — the bucket
may not have propagated to all internal S3 systems yet. depends_on forces
full sequential completion before the configuration resource starts.

</details>

---

**Q3.** Is DynamoDB required for S3 state locking in Terraform 1.15?

- A) Yes — DynamoDB is the only locking mechanism for S3 backends
- B) No — use_lockfile = true uses S3 conditional writes, DynamoDB is deprecated
- C) No — Terraform 1.15 uses S3 object tagging for locking
- D) Yes — but only when more than one engineer uses the same state

<details>
<summary>Answer</summary>

**B** — use_lockfile = true introduced in v1.10, fully supported in v1.11.
Creates .tfstate.tflock using S3 conditional writes. dynamodb_table deprecated.
No DynamoDB table, no extra cost.

</details>

---

**Q4.** Two engineers run `terraform apply` simultaneously with S3 native
locking enabled. What happens?

- A) Both succeed — S3 handles concurrent writes safely
- B) Second apply fails immediately: Error acquiring the state lock
- C) Second apply queues and waits until the first finishes
- D) Both partially succeed, merging their changes

<details>
<summary>Answer</summary>

**B** — First apply creates .tfstate.tflock via conditional write. Second
apply tries to create the same file — S3 returns conflict. Terraform errors:
Error acquiring the state lock. Second apply exits immediately — it does
not queue.

</details>

---

**Q5.** After `terraform init -migrate-state`, what is the status of the
local `terraform.tfstate` file?

- A) Deleted automatically
- B) Emptied — resources removed, serial reset to 0
- C) Stale backup — S3 copy is authoritative, local not updated by future applies
- D) Symlinked to the S3 object

<details>
<summary>Answer</summary>

**C** — Local file becomes a stale backup. Terraform uses S3 for all
future operations. Local file not deleted or updated. Safe to delete.

</details>

---

**Q6.** What does `default_tags` in the AWS provider block do?

- A) Sets tags only on resources with no tags argument of their own
- B) Automatically merges specified tags into every resource the provider creates
- C) Overrides resource-level tags when both define the same key
- D) Only applies to resources in the default region

<details>
<summary>Answer</summary>

**B** — default_tags merged into every resource automatically. Resource-level
tags merge on top — in conflicts the resource-level tag wins, not default_tags.
C is wrong: resource wins, not default.

</details>

---

**Q7.** `versions.tf` has a `terraform {}` block. You add `backend.tf`
with another `terraform {}` block. Is this valid?

- A) No — only one terraform {} block per directory
- B) Yes — Terraform merges all .tf files and their terraform {} blocks cleanly
- C) No — backend block must be in versions.tf
- D) Yes — but only if versions.tf has no required_providers

<details>
<summary>Answer</summary>

**B** — Terraform merges all .tf files. Multiple terraform {} blocks merge
cleanly as long as the same setting is not declared twice. backend in
backend.tf + required_version in versions.tf = valid.

</details>

---

**Q8.** How much does AES256 (SSE-S3) encryption cost on an S3 bucket?

- A) $0.03 per 10,000 requests
- B) $1.00 per month per bucket
- C) Free — AWS absorbs the cost of S3-managed keys
- D) Free only within free tier, paid after 5GB

<details>
<summary>Answer</summary>

**C** — SSE-S3 (AES256) is always free. AWS manages keys internally at
no charge. SSE-KMS (customer-managed) is paid. This is why we use AES256.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Proceed to Demo 02 |
| 6-7/8 | Review wrong answers in Anki, then proceed |
| 4-5/8 | Re-read relevant README sections, retry |
| Below 4/8 | Re-read Demo 01 before proceeding |
```