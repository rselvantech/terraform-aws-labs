# Demo 02 — Providers: Configuration, Versioning, and the Lock File

---

## Overview

In Demo 01 you used the AWS provider to create real infrastructure for
the first time. You declared it in `required_providers`, configured it
in `provider.tf`, and Terraform downloaded it on `terraform init`. You
used it without fully understanding what it is, how it is versioned, or
what the lock file actually contains.

This demo fixes that. Providers are the most important dependency in any
Terraform configuration — getting them wrong causes everything from subtle
drift to complete team workflow breakdowns.

**Real-world scenario — CloudNova:**
The team has grown to three DevOps engineers. Two problems surfaced this
week:

Problem 1: Two engineers ran `terraform init` on different machines —
one Linux, one macOS. The lock file was never committed to Git. Each
machine downloaded a slightly different patch version of the AWS provider.
Their plans produce different results for the same configuration. You need
to fix this by committing a lock file with hashes for all platforms the
team uses.

Problem 2: A new regulatory requirement means CloudNova must archive
compliance logs to a second AWS region (`us-west-2`) in addition to the
primary region (`us-east-2`). This means one Terraform configuration must
create resources in two different AWS regions simultaneously — your first
multi-provider configuration using provider aliases.

**What this demo covers:**
- Every argument in the `provider "aws"` block and what each does
- How Terraform discovers which resources belong to which provider
- The `terraform providers` command
- All five version constraint operators with real examples
- Lock file anatomy — every field, what hashes are and why they exist
- Multi-platform hashes — the Linux/macOS team problem and the fix
- `terraform init -upgrade` — when and how to update provider versions safely
- Provider aliases — configure two AWS regions in one Terraform config
- The `provider` meta-argument on a resource
- AWS provider v6 per-resource `region` as the modern alternative to aliases

---

## Prerequisites

### Knowledge
- Demo 00 — HCL syntax, block types, Terraform workflow
- Demo 01 — AWS provider basics, named profile, `default_tags`

### Verify AWS Setup

```bash
# Confirm profile and permissions
aws sts get-caller-identity --profile default
# Expected: JSON with UserId, Account, Arn

# Verify S3 access (used in this demo)
aws s3api list-buckets --profile default
# Expected: JSON with Buckets array — no AccessDenied error
```

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain every argument in the `provider "aws"` block
2. ✅ Explain how Terraform maps resources to providers using the
   resource type prefix
3. ✅ Use the `terraform providers` command to inspect provider usage
4. ✅ Explain all five version constraint operators and when to use each
5. ✅ Read a `.terraform.lock.hcl` file and explain every field
6. ✅ Generate multi-platform hashes to fix the Linux/macOS team problem
7. ✅ Safely upgrade a provider version using `terraform init -upgrade`
8. ✅ Configure provider aliases for multi-region infrastructure
9. ✅ Use the `provider` meta-argument to assign a resource to an alias
10. ✅ Explain when to use aliases vs the v6 per-resource `region` argument

---

## Cost & Free Tier

| Resource | Cost | Notes |
|---|---|---|
| S3 bucket us-east-2 (empty) | **$0.00** | Free tier |
| S3 bucket us-west-2 (empty) | **$0.00** | Free tier — different region, same free tier pool |
| S3 API calls | **<$0.001** | Within free tier |
| **Session total** | **~$0.00** | |

---

## Directory Structure

```
02-providers/
├── README.md
├── 02-providers-anki.csv         # Anki flash cards
├── 02-providers-quiz.md          # Quiz
└── src/
    ├── versions.tf               # terraform block + required_providers
    ├── provider.tf               # default AWS provider + aliased us-west-2 provider
    ├── variables.tf              # region, profile, project, environment
    ├── locals.tf                 # bucket names + common tags
    ├── main.tf                   # two S3 buckets: primary (default) + archive (alias)
    ├── outputs.tf                # both bucket names, ARNs, regions
    └── break-fix/
        └── broken.tf             # break-fix scenario
```

---

## Recall Check — Demo 01

Answer from memory before reading anything new:

1. You get `NoSuchPublicAccessBlockConfiguration` when applying
   `aws_s3_bucket_public_access_block`. What causes this and what is the fix?
2. Backend arguments like `bucket` and `region` cannot use `var.x`.
   Why not? What is the production solution?
3. What is the difference between `terraform plan` and
   `terraform plan -refresh-only` when drift exists?

<details>
<summary>Answers</summary>

1. S3 eventual consistency race condition. `CreateBucket` returns 200 but
   the bucket has not fully propagated internally. Fix: add
   `depends_on = [aws_s3_bucket.app]` to all configuration resources.
2. The backend block is evaluated before variables are loaded — no provider
   has initialised yet. `var.x` references are not available. Production
   solution: partial backend configuration via `-backend-config` flags or
   a `.tfbackend` file.
3. `terraform plan` detects drift AND shows pending config changes together —
   applying it reconciles drift and applies config changes simultaneously.
   `terraform plan -refresh-only` shows drift only, isolated from config
   changes — useful when you want to decide whether to accept or reject
   the drift before touching config changes.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `alias` | Provider argument | Name a second provider configuration for the same provider type |
| `provider = aws.west` | Meta-argument on resource | Assign a resource to a specific provider alias |
| `terraform providers` | CLI command | Show which providers each resource in the config uses |
| `terraform providers lock` | CLI command | Generate/update lock file hashes for specific platforms |
| `terraform init -upgrade` | CLI flag | Upgrade providers to latest allowed by version constraints |
| Version constraint operators | HCL syntax | `=` `!=` `>` `>=` `<=` `~>` — control acceptable provider versions |
| Lock file fields | File anatomy | `version`, `constraints`, `hashes`, `h1:` vs `zh:` prefix |
| Per-resource `region` (v6) | Resource argument | Set region on individual resources — v6 alternative to aliases |

---

### Detailed Explanation of New Constructs

#### Provider Block — All Arguments

The `provider "aws"` block configures a specific instance of the AWS
provider. Here are all the arguments you will encounter in this series:

| Argument | Required | Description |
|---|---|---|
| `region` | Yes (for AWS) | AWS region for all resources created by this provider instance |
| `profile` | No | Named profile from `~/.aws/credentials`. Falls back to default credential chain if omitted. |
| `access_key` / `secret_key` | No — never use | Static credentials — commits secrets to version control. Never use. |
| `alias` | No | Names this provider instance. Required when declaring a second instance of the same provider type. Without alias, only one `provider "aws"` block is allowed. |
| `default_tags` | No | Tags automatically merged into every resource this provider creates. Resource-level tags merge on top; resource wins on conflicts. |
| `assume_role` | No | Assume an IAM role before making API calls — used for cross-account access. Covered in Demo 20. |
| `endpoints` | No | Override AWS service endpoint URLs — used for LocalStack or VPC endpoints. |
| `ignore_tags` | No | Tag keys to ignore during plan — prevents drift detection on tags managed outside Terraform. |

**How Terraform maps resources to providers:**

When Terraform sees `resource "aws_s3_bucket"`, it looks at the resource
type prefix (`aws_`) and maps it to the provider with local name `aws`.
This is why the local name in `required_providers` must match:

```hcl
required_providers {
  aws = {                        # local name = "aws"
    source = "hashicorp/aws"
  }
}

resource "aws_s3_bucket" "app" { # "aws_" prefix → maps to local name "aws"
  ...
}

resource "aws_instance" "web" {  # "aws_" prefix → same provider
  ...
}
```

If you declared the local name as `amazon` instead of `aws`, all
`aws_*` resource types would fail to resolve — the prefix `aws_` would
not match the local name `amazon`.

**`terraform providers`**

Lists every provider the current configuration requires, their version
constraints, and which module uses each. Read-only — downloads or
installs nothing.

| Flag | Description |
|---|---|
| `-chdir=<path>` | Run as if Terraform was started in a different directory |

**When to use:**
- After writing or updating `provider.tf` to confirm all providers resolve
- To audit which resources depend on which provider instance
- To debug provider alias routing issues

```bash
terraform providers
```

Expected output:

```
Providers required by configuration:
.
├── provider[registry.terraform.io/hashicorp/aws] ~> 6.47.0
└── provider[registry.terraform.io/hashicorp/random] ~> 3.9.0
```

This confirms both providers are declared and their constraints are resolved.
The AWS provider appears once even though it has two instances (default and
aliased) — aliases share one version constraint so they appear as one entry.

---

#### Version Constraint Operators — All Five

Version constraints control which provider versions Terraform will accept.
A `~> 6.47.0` constraint allows any version in the 6.47.x series
but prevents updates to 6.48 and later.

```
OPERATOR   MEANING                        EXAMPLE         ALLOWS
─────────────────────────────────────────────────────────────────────
=          Exact version only             = 6.47.0        6.47.0 only
           (rarely used — no patches)

!=         Any version EXCEPT this        != 5.0.0        anything but 5.0.0
           (used to exclude known bugs)

>=         This version or higher         >= 6.0.0        6.0.0, 6.1.0, 7.0.0...
           (no upper bound — risky)

<=         This version or lower          <= 6.47.0       6.47.0 and below

~>         Pessimistic constraint         ~> 6.47.0       6.47.x only (patch)
           "allow patch, lock minor"      ~> 6.0           6.x.x (minor+patch)
           MOST COMMON — use this

COMBINING  Use multiple constraints       >= 6.0, < 7.0   any 6.x version
           together
```

**Which operator to use in practice:**

```
~> 6.47.0   ← this series
  Allows: 6.47.0, 6.47.1, 6.47.2...
  Blocks: 6.48.0 (new minor — may have breaking changes)
  Use: root modules — pin to a known-good minor version

~> 6.0
  Allows: 6.0.0, 6.1.0, 6.47.0...
  Blocks: 7.0.0 (new major — breaking changes guaranteed)
  Use: reusable modules — allow minor updates for callers

>= 6.0, < 7.0
  Same as ~> 6.0 but explicit — preferred in module registries
  for clarity

= 6.47.0
  Exact pin — use only when a specific version is required for
  a known reason (e.g. a bug was introduced in 6.47.1)
```

**Version constraint strategy for teams:**

Before the strategy, two terms to understand:
- **Root module** — the directory you run `terraform init/plan/apply` from.
  Every demo in this series is a root module. It controls the entire
  dependency tree and should pin versions tightly.
- **Child module** — a reusable module called by the root via a `module {}`
  block (covered in Demo 09). It declares only the minimum version it
  needs and lets the root module choose the exact version. If a child
  module pins too tightly (e.g. `~> 6.47.0`) and the root uses `~> 6.46.0`,
  Terraform cannot find a version that satisfies both constraints and errors.

```
Root modules:   ~> X.Y.0  (pin minor, allow patches)
Child modules:  >= X.0    (minimum version, let root control)
Never use:      no constraint at all — Terraform downloads latest
                which changes on every init
```

---

#### Lock File Anatomy — Every Field Explained

You should never directly modify the lock file.
It is generated and maintained by `terraform init`. Here is what every
field means:

```hcl
# .terraform.lock.hcl
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/hashicorp/aws" {

  version     = "6.47.0"
  # The EXACT version Terraform resolved and downloaded.
  # This is what every engineer on the team will get on terraform init.

  constraints = "~> 6.47.0"
  # The constraint from required_providers in versions.tf.
  # Recorded for reference — the lock file enforces version, not constraint.

  hashes = [
    "h1:abc123...",
    # h1: prefix = hash of the zip archive contents (platform-independent)
    # Used as a quick check — same across all OS/arch combinations

    "zh:def456...",
    # zh: prefix = hash of individual files inside the zip (platform-specific)
    # Different for linux_amd64 vs darwin_arm64 vs windows_amd64
    # Terraform verifies BOTH h1 and zh on download
  ]
}
```

**Why hashes exist — two-layer security:**

Terraform uses two mechanisms together to protect provider downloads:

**Layer 1 — GPG signature (protects the first download):**
HashiCorp signs every provider binary with their private GPG key before
publishing it to the registry. On every download, Terraform verifies this
signature against HashiCorp's public key. A binary not signed by HashiCorp
— whether modified or malicious — is rejected before any hash check occurs.
This is why you see `(signed by HashiCorp)` in the `terraform init` output.

**Layer 2 — SHA256 hashes in the lock file (protects all subsequent downloads):**
On the first `terraform init`, Terraform downloads the provider, verifies
the GPG signature, then computes SHA256 hashes and records them in the lock
file. On every subsequent `terraform init`, Terraform re-downloads and checks
the binary against the stored hashes. If the registry serves a different binary
— even one with a valid signature — the hash would not match and `terraform init`
fails with a checksum mismatch error.

The two layers work together: GPG signature protects the first download,
hashes protect all subsequent ones against a binary being swapped after
the initial install.

**The multi-platform problem:**

When Engineer A (Linux) runs `terraform init`, the lock file gets Linux
hashes (`zh:` for linux_amd64). When Engineer B (macOS) pulls the lock
file and runs `terraform init`, it fails:

```
Error: Failed to install provider
The current platform's checksum does not match any of the
checksums recorded in the lock file.
```

Because the macOS hash is not in the lock file — only the Linux hash is.

**The fix — `terraform providers lock`**

Updates `.terraform.lock.hcl` with hashes for the specified platforms.
Downloads provider binaries to compute hashes but does NOT install them
into `.terraform/`. Fully idempotent — adds hashes, never removes existing ones.

| Flag | Description |
|---|---|
| `-platform=os_arch` | Platform to add hashes for. Repeat for each platform. Common values: `linux_amd64`, `darwin_arm64`, `darwin_amd64`, `windows_amd64` |

**When to run:**
- After the first `terraform init`, before committing the lock file to Git
- After `terraform init -upgrade` — new version needs new platform hashes
- When a new engineer on a different OS platform joins the team

**Can you re-run it?** Yes — fully safe at any time. Adds missing hashes
without changing the `version` field or removing existing entries.

```bash
# Generate hashes for all platforms CloudNova engineers use
terraform providers lock \
  -platform=linux_amd64 \
  -platform=darwin_arm64 \
  -platform=windows_amd64

# This adds zh: hashes for all three platforms to the lock file
# Commit the updated lock file — all team members can now init successfully
```

---

#### Provider Aliases — Multi-Region Configuration

By default, one `provider "aws"` block exists and all `aws_*` resources
use it. When you need resources in a **second region**, you declare a
second `provider "aws"` block with an `alias`:

```hcl
# Default provider — used by all resources unless overridden
provider "aws" {
  region  = "us-east-2"
  profile = "default"
}

# Aliased provider — used only by resources that explicitly reference it
provider "aws" {
  alias   = "west"           # the alias name — reference as aws.west
  region  = "us-west-2"
  profile = "default"
}
```

**Rules for aliases:**
- All aliases share the same provider version — you cannot have
  different versions of the same provider. The version constraint
  in `required_providers` applies to all instances.
- The default provider (no `alias`) is used automatically by all resources
  that do not specify a `provider` meta-argument.
- An aliased provider is NEVER used automatically — resources must
  explicitly opt in with `provider = aws.west`.

**Using the `provider` meta-argument on a resource:**

```hcl
# Uses the DEFAULT provider (us-east-2) — no meta-argument needed
resource "aws_s3_bucket" "primary" {
  bucket = "cloudnova-primary-logs"
}

# Uses the ALIASED provider (us-west-2) — explicit meta-argument required
resource "aws_s3_bucket" "archive" {
  bucket   = "cloudnova-archive-logs"
  provider = aws.west        # format: <provider_local_name>.<alias>
}
```

**AWS provider v6 — per-resource `region` as an alternative:**

AWS provider v6 introduced a `region` argument on individual resources,
meaning you can set the region per-resource without needing a full alias:

```hcl
# v6 alternative — set region directly on the resource
resource "aws_s3_bucket" "archive" {
  bucket = "cloudnova-archive-logs"
  region = "us-west-2"       # v6 per-resource region — no alias needed
}
```

**When to use which approach:**

| Scenario | Use |
|---|---|
| Resources in a second region, same credentials | Per-resource `region` (v6) — simpler |
| Resources in a second region, different credentials/account | Provider alias — aliases can have different `profile` |
| Multiple resources in a second region | Provider alias — set region once in provider block |
| Cross-account access | Provider alias with `assume_role` |

In this demo we use **aliases** to learn the pattern. Per-resource `region`
is shown as the v6 alternative.

---

## Lab Step-by-Step Guide

---

## Part A — Provider Configuration and Single Bucket

**What you accomplish in Part A:** write the configuration files for a
single AWS provider with `default_tags`, create one S3 bucket, and use
`terraform providers` to inspect how Terraform maps resources to providers.
At the end of Part A you have one bucket in `us-east-2` and a clear
understanding of what the provider block controls.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/02-providers/src
```

### Step 2 — Create the source files

---

#### `versions.tf` — Version constraints

**What this file does in this demo:** declares both providers — `aws` for
real AWS resources and `random` for unique bucket name suffixes. Same
structure as Demo 01.

**versions.tf:**

```hcl
terraform {
  required_version = "~> 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
  }
}
```

---

#### `provider.tf` — AWS provider with alias

**What this file does in this demo:** declares two AWS provider instances —
the default (us-east-2) used by most resources, and an aliased instance
(us-west-2) used only by the archive bucket. Both share the same version
constraint and credentials profile.

**New in this demo:** the `alias` argument on the second provider block.

**provider.tf:**

```hcl
# Default provider — used by all aws_* resources unless overridden
# No alias argument = this is the default instance
provider "aws" {
  region  = var.aws_region    # us-east-2
  profile = var.aws_profile   # default

  default_tags {
    tags = local.common_tags  # applied to every resource automatically
  }
}

# Aliased provider — used only by resources with provider = aws.west
# Same credentials, different region
provider "aws" {
  alias   = "west"            # referenced as aws.west in resources
  region  = "us-west-2"       # second region for compliance archive
  profile = var.aws_profile   # same credentials as default provider

  default_tags {
    tags = local.common_tags  # same tags applied in both regions
  }
}

# No provider "random" {} block needed — auto-instantiated from required_providers
```

---

#### `variables.tf` — Input variables

**What this file does in this demo:** same variables as Demo 01.
No new variables — the second region is hardcoded in provider.tf
because backend arguments and provider aliases with static regions
are not normally driven by variables.

**variables.tf:**

```hcl
variable "aws_region" {
  type        = string
  description = "Primary AWS region"
  default     = "us-east-2"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI named profile"
  default     = "default"
}

variable "project" {
  type        = string
  description = "Project name used in resource names and tags"
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
  description = "Demo identifier — used in tags"
  default     = "02-providers"
}
```

---

#### `locals.tf` — Computed values

**What this file does in this demo:** computes unique names for both
S3 buckets and the shared tag map. Both buckets share the same random
suffix so their names are clearly paired.

**locals.tf:**

```hcl
locals {
  # Single suffix shared by both buckets — makes pairing clear
  # e.g. cloudnova-dev-primary-a1b2c3d4 + cloudnova-dev-archive-a1b2c3d4
  primary_bucket_name = "${var.project}-${var.environment}-primary-${random_id.suffix.hex}"
  archive_bucket_name = "${var.project}-${var.environment}-archive-${random_id.suffix.hex}"

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

**What this file does in this demo:** declares the `random_id` suffix and
both S3 buckets. The primary bucket uses the default provider (us-east-2).
The archive bucket uses the aliased provider (us-west-2) via the `provider`
meta-argument. Each bucket has versioning and encryption as established
in Demo 01.

**New in this demo:** the `provider = aws.west` meta-argument on the
archive bucket and its configuration resources.

**main.tf:**

```hcl
resource "random_id" "suffix" {
  byte_length = 4
}

# ── Primary bucket — us-east-2 (default provider) ─────────────────────────
resource "aws_s3_bucket" "primary" {
  bucket        = local.primary_bucket_name
  force_destroy = true   # demo only

  tags = { Name = local.primary_bucket_name }
}

resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id
  versioning_configuration { status = "Enabled" }
  depends_on = [aws_s3_bucket.primary]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  bucket = aws_s3_bucket.primary.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
  depends_on = [aws_s3_bucket.primary]
}

resource "aws_s3_bucket_public_access_block" "primary" {
  bucket                  = aws_s3_bucket.primary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.primary]
}

# ── Archive bucket — us-west-2 (aliased provider) ─────────────────────────
# provider = aws.west routes ALL API calls for this resource to us-west-2
# Without this meta-argument, the bucket would be created in us-east-2
resource "aws_s3_bucket" "archive" {
  bucket        = local.archive_bucket_name
  force_destroy = true   # demo only
  provider      = aws.west   # uses the aliased provider — us-west-2

  tags = { Name = local.archive_bucket_name }
}

resource "aws_s3_bucket_versioning" "archive" {
  bucket   = aws_s3_bucket.archive.id
  provider = aws.west        # must match the bucket's provider
  versioning_configuration { status = "Enabled" }
  depends_on = [aws_s3_bucket.archive]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  bucket   = aws_s3_bucket.archive.id
  provider = aws.west
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
  depends_on = [aws_s3_bucket.archive]
}

resource "aws_s3_bucket_public_access_block" "archive" {
  bucket                  = aws_s3_bucket.archive.id
  provider                = aws.west
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.archive]
}
```

> **Important:** Every configuration resource for the archive bucket
> must also have `provider = aws.west`. If you omit it on `aws_s3_bucket_versioning`,
> Terraform will try to configure versioning in us-east-2 on a bucket
> that lives in us-west-2 — and fail with `NoSuchBucket`.

---

#### `outputs.tf` — Expose values after apply

**What this file does in this demo:** exposes names, ARNs, and regions
for both buckets so you can verify each landed in the correct region.

**outputs.tf:**

```hcl
output "primary_bucket_name" {
  description = "Name of the primary bucket (us-east-2)"
  value       = aws_s3_bucket.primary.bucket
}

output "primary_bucket_region" {
  description = "Region of the primary bucket"
  value       = aws_s3_bucket.primary.region
}

output "archive_bucket_name" {
  description = "Name of the archive bucket (us-west-2)"
  value       = aws_s3_bucket.archive.bucket
}

output "archive_bucket_region" {
  description = "Region of the archive bucket"
  value       = aws_s3_bucket.archive.region
}
```

---

### Step 3 — Initialise

```bash
terraform init
```

Expected output:

```
Initializing provider plugins...
- Installing hashicorp/aws v6.47.0...
- Installing hashicorp/random v3.9.0...
Terraform has been successfully initialized!
```

---

### Step 4 — Inspect providers

```bash
# Show which providers the configuration uses and their constraints
terraform providers
```

Expected output:

```
Providers required by configuration:
.
├── provider[registry.terraform.io/hashicorp/aws] ~> 6.47.0
│   ├── module.root (aws — default, us-east-2)
│   └── module.root (aws.west — aliased, us-west-2)
└── provider[registry.terraform.io/hashicorp/random] ~> 3.9.0
```

This shows both the default and aliased instances of the AWS provider —
one version constraint, two configurations.

---

### Step 5 — Validate, Format, Plan

```bash
terraform validate
# Success! The configuration is valid.

terraform fmt

terraform plan
```

Key section of expected output:

```
  # aws_s3_bucket.primary will be created  ← us-east-2 (default provider)
  + resource "aws_s3_bucket" "primary" {
      + bucket   = (known after apply)
      + provider = "registry.terraform.io/hashicorp/aws"
    }

  # aws_s3_bucket.archive will be created  ← us-west-2 (aliased provider)
  + resource "aws_s3_bucket" "archive" {
      + bucket   = (known after apply)
      + provider = "registry.terraform.io/hashicorp/aws.west"
    }

Plan: 9 to add, 0 to change, 0 to destroy.
```

Notice the `region` field in the plan output — `"us-east-2"` for primary
and `"us-west-2"` for archive. This confirms each bucket is routed to the
correct provider instance. The provider routing is verified by the region
shown for each resource — not by a provider label in standard plan output.
After apply, `terraform state show aws_s3_bucket.archive` shows the full
provider reference (covered in Part C).

---

### Step 6 — Apply

```bash
terraform apply
```

Type `yes`. Expected output:

```
random_id.suffix: Creating...
random_id.suffix: Creation complete after 0s

aws_s3_bucket.primary: Creating...           ← us-east-2
aws_s3_bucket.archive: Creating...           ← us-west-2 (parallel)
aws_s3_bucket.primary: Creation complete after 2s
aws_s3_bucket.archive: Creation complete after 2s
... (configuration resources)
Apply complete! Resources: 9 added, 0 changed, 0 destroyed.

Outputs:
primary_bucket_name   = "cloudnova-dev-primary-a1b2c3d4"
primary_bucket_region = "us-east-2"
archive_bucket_name   = "cloudnova-dev-archive-a1b2c3d4"
archive_bucket_region = "us-west-2"
```

Both buckets are created in parallel — they have no dependency on each other.

---

### Step 7 — Verify in AWS Console

**Primary bucket (us-east-2):**

```
Console → S3 → General purpose buckets
  → cloudnova-dev-primary-xxxxxxxx
  → Properties → AWS Region: US East (Ohio) us-east-2 ✅
  → Properties → Bucket Versioning: Enabled ✅
  → Properties → Default encryption: SSE-S3 ✅
  → Permissions → Block public access: all four ON ✅
```

**Archive bucket (us-west-2):**

```
Console → S3 → General purpose buckets
  → cloudnova-dev-archive-xxxxxxxx
  → Properties → AWS Region: US West (Oregon) us-west-2 ✅
  → Properties → Bucket Versioning: Enabled ✅
  → Properties → Default encryption: SSE-S3 ✅
  → Permissions → Block public access: all four ON ✅
```

> The two buckets have the same suffix (`xxxxxxxx`) — this confirms they
> were created from the same `random_id.suffix` resource.

---

## Part B — Lock File Deep Dive and Multi-Platform Hashes

**What you accomplish in Part B:** read and understand every field in the
generated lock file, fix the CloudNova Linux/macOS team problem by adding
multi-platform hashes, and safely upgrade the `random` provider to
demonstrate the `terraform init -upgrade` workflow.

### Step 8 — Read the lock file

```bash
cat .terraform.lock.hcl
```

Expected output (annotated):

```hcl
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/hashicorp/aws" {
  version     = "6.47.0"         # exact version downloaded — not a constraint
  constraints = "~> 6.47.0"      # the constraint from versions.tf (reference only)
  hashes = [
    "h1:abc123...",               # h1: = hash of zip archive (platform-independent)
    "zh:def456...",               # zh: = hash of files inside zip (platform-specific)
    "zh:ghi789...",               # one zh: per platform that has run terraform init
  ]
}

provider "registry.terraform.io/hashicorp/random" {
  version     = "3.9.0"
  constraints = "~> 3.9.0"
  hashes = [
    "h1:jkl012...",
    "zh:mno345...",
  ]
}
```

**Verify the lock file content:**

```bash
# Read the lock file — confirm version and hash fields are present
cat .terraform.lock.hcl
```

Check that:
- `version = "6.47.0"` matches what `terraform init` printed ✅
- `constraints = "~> 6.47.0"` matches your `versions.tf` ✅
- At least one `h1:` and one `zh:` hash entry exist ✅

---

### Step 9 — Fix the multi-platform problem

Currently the lock file only has hashes for YOUR platform (the one that
ran `terraform init`). A teammate on a different OS will fail.

```bash
# Generate hashes for all platforms CloudNova engineers use
terraform providers lock \
  -platform=linux_amd64 \
  -platform=darwin_arm64 \
  -platform=windows_amd64
```

Expected output:

```
Locking provider registry.terraform.io/hashicorp/aws...
- Fetched checksums for linux_amd64
- Fetched checksums for darwin_arm64
- Fetched checksums for windows_amd64
Success! Terraform has updated the lock file.
```

```bash
# Read the lock file again — now has zh: hashes for all three platforms
cat .terraform.lock.hcl
# hashes = [
#   "h1:abc123...",           # platform-independent (unchanged)
#   "zh:linux_hash...",       # linux_amd64
#   "zh:mac_hash...",         # darwin_arm64
#   "zh:windows_hash...",     # windows_amd64
# ]
```

```bash
# Commit the updated lock file
git add .terraform.lock.hcl
git commit -m "chore: add multi-platform provider hashes for team"
```

Now any engineer on Linux, macOS, or Windows can run `terraform init`
and get the identical provider version with a passing hash check.

---

### Step 10 — Understanding terraform init -upgrade

**`terraform init -upgrade`**

Re-resolves all provider version constraints and downloads the latest
version that satisfies each constraint. Then updates the lock file.

**Key distinction — `terraform init` vs `terraform init -upgrade`:**

Once a lock file exists, `terraform init` always installs the exact
version recorded in the lock file — even if a newer patch is available.
The lock file is the source of truth and `terraform init` never overrides it.
`terraform init -upgrade` overrides this. It re-resolves the constraint
  and downloads the newest version that satisfies it, then updates the
  lock file.

```
Example:
  versions.tf says:  version = "~> 6.47.0"  (allows 6.47.x patches)
  lock file says:    version = "6.47.0"
  AWS releases:      6.47.1  (security patch)

  terraform init          → installs 6.47.0  (respects lock file)
  terraform init -upgrade → installs 6.47.1  (re-resolves, updates lock file)
```

**When to use:**
- After updating a version constraint in `versions.tf`
- To pick up a security patch or bug fix within the current constraint
- After a provider releases a fix for a known issue

**When NOT to use:**
- Without reading the provider changelog first
- Without running `terraform plan` after to confirm zero infrastructure changes
- Directly in production — always upgrade in dev/staging first

**Safe upgrade workflow:**
1. Update constraint in `versions.tf` if needed
2. `terraform init -upgrade`
3. `terraform plan` — confirm zero infrastructure changes
4. `git add versions.tf .terraform.lock.hcl` — always commit both together
5. Repeat in staging, then production

> **Why we do not run this in the demo:** `random v3.9.0` is already the
> latest patch — there is nothing to upgrade to. The workflow above is what
> you apply when a real upgrade is needed.

---

## Part C — State Operations Verification

**What you accomplish in Part C:** verify the multi-region deployment
using state commands and confirm each resource is tracked with its correct
provider.

### Step 11 — Inspect state

```bash
# List all managed resources
terraform state list
# random_id.suffix
# aws_s3_bucket.primary
# aws_s3_bucket.archive
# aws_s3_bucket_versioning.primary
# aws_s3_bucket_versioning.archive
# ... (all 9 resources)

# Show the archive bucket — confirm it is in us-west-2
terraform state show aws_s3_bucket.archive
# resource "aws_s3_bucket" "archive" {
#     bucket   = "cloudnova-dev-archive-a1b2c3d4"
#     region   = "us-west-2"    ← confirmed in state ✅
#     provider = "provider[\"registry.terraform.io/hashicorp/aws\"].west"
# }
```

The `provider` line in state confirms which provider instance manages
each resource — `hashicorp/aws` for primary, `hashicorp/aws.west` for archive.

---

## Cleanup

> ⚠️ Run cleanup at the end of every session — resources in both regions.

```bash
terraform destroy
```

Type `yes`. Terraform destroys resources in both regions.

```
aws_s3_bucket.primary: Destroying... [id=cloudnova-dev-primary-a1b2c3d4]
aws_s3_bucket.archive: Destroying... [id=cloudnova-dev-archive-a1b2c3d4]
...
Destroy complete! Resources: 9 destroyed.
```

**Verify both regions in Console:**

```
Console → S3 → General purpose buckets
  → cloudnova-dev-primary-xxxxxxxx: GONE ✅
  → cloudnova-dev-archive-xxxxxxxx: GONE ✅

(Switch region to us-west-2 in Console top-right to confirm archive gone)
```

---

## What You Learned

1. ✅ The `provider "aws"` block controls region, credentials, default tags,
   and role assumption. Resources map to providers via type prefix (`aws_` → `aws`).
2. ✅ `terraform providers` shows every provider instance and which
   resources use each.
3. ✅ Five version constraint operators: `=`, `!=`, `>=`, `<=`, `~>`.
   Use `~> X.Y.0` in root modules to pin minor version and allow patches.
4. ✅ The lock file records exact version + h1 and zh hashes.
   `zh:` hashes are platform-specific — commit multi-platform hashes
   with `terraform providers lock -platform=...` for team use.
5. ✅ `terraform init -upgrade` upgrades within constraints.
   Always commit `versions.tf` + `.terraform.lock.hcl` together.
6. ✅ Provider aliases allow multiple instances of the same provider.
   All aliases share one version constraint.
7. ✅ The `provider` meta-argument explicitly assigns a resource to an alias.
   All configuration resources for an aliased bucket must also carry the alias.
8. ✅ AWS provider v6 per-resource `region` is a simpler alternative to
   aliases when only the region differs and credentials are the same.

---

## Cert Tips — TA-004 Objectives Covered

**Objective 2a — Install and use providers:**
> Providers are installed by `terraform init` from `registry.terraform.io`.
> Exam: "Which command downloads providers?" → `terraform init`.

**Objective 2b — Version constraints:**
> Exam commonly tests `~>` behaviour. `~> 6.47.0` allows 6.47.x, blocks
> 6.48.0. `~> 6.0` allows any 6.x, blocks 7.0.0.

**Objective 2c — Provider configuration:**
> Exam: "Can two provider blocks use different versions of the same provider?"
> → **No** — all instances (including aliases) share the version constraint.

**Objective 2d — Lock file:**
> Exam: "What does `.terraform.lock.hcl` record?" → exact resolved version
> + SHA256 hashes. "Should it be committed?" → **Yes**.
> "How do you update it?" → `terraform init -upgrade` after changing the constraint.

| Question | Answer |
|---|---|
| Can provider aliases have different versions? | **No** — all share one constraint |
| Which command adds multi-platform hashes to lock file? | `terraform providers lock -platform=...` |
| What does `terraform init -upgrade` do? | Downloads latest version within current constraints, updates lock file |
| Should `.terraform.lock.hcl` be committed? | **Yes** — always |
| What does `provider = aws.west` on a resource do? | Routes all API calls for that resource to the `west` aliased provider |

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Failed to install provider: checksum mismatch` | Lock file has hashes for a different platform | Run `terraform providers lock -platform=<your_platform>` |
| `No configuration for provider aws.west` | Resource uses `provider = aws.west` but no alias declared in provider.tf | Add `provider "aws" { alias = "west" ... }` block |
| `provider aws.west is not available` | Typo in alias name — case sensitive | Alias name must match exactly: `alias = "west"` and `provider = aws.west` |
| `NoSuchBucket` on versioning resource | Configuration resource missing `provider = aws.west` | Add `provider = aws.west` to every resource associated with the aliased bucket |
| `Invalid version constraint` | Syntax error in version string | Use `"~> 6.47.0"` with space after `~>` and three-part version |
| `Incompatible provider version` | Lock file has a different version than constraint allows | Run `terraform init -upgrade` after updating the constraint |

---

## Break-Fix Scenario

Three deliberate errors. Diagnose with `terraform validate` and
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

provider "aws" {
  alias  = "west"
  region = "us-west-2"
}

resource "aws_s3_bucket" "primary" {
  bucket = "cloudnova-primary-demo"
}

resource "aws_s3_bucket" "archive" {
  bucket   = "cloudnova-archive-demo"
  provider = aws.east              # Error 1
}

resource "aws_s3_bucket_versioning" "archive" {
  bucket   = aws_s3_bucket.archive.id
                                   # Error 2 — missing provider assignment
  versioning_configuration {
    status = "enabled"             # Error 3
  }
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — `provider = aws.east`**
There is no provider alias named `east`. The default provider has no alias.
To use the default provider explicitly: omit the `provider` meta-argument
entirely, or use `provider = aws` (no dot notation for default).
For the west region: `provider = aws.west`.

**Error 2 — missing `provider = aws.west` on `aws_s3_bucket_versioning.archive`**
Every configuration resource for an aliased bucket must carry the same
`provider` meta-argument. Without it, Terraform routes the versioning
API call to the default provider (us-east-2) — but the bucket lives in
us-west-2. Fix: add `provider = aws.west`.

**Error 3 — `status = "enabled"` (lowercase)**
The valid values for `versioning_configuration.status` are case-sensitive:
`Enabled`, `Suspended`, `Disabled`. Lowercase `enabled` will fail
validation. Fix: `status = "Enabled"`.

</details>

---

## Interview Prep

**Q1. A new engineer asks: "If I want resources in `us-west-2` and I'm already using AWS provider v6, do I actually need a provider alias, or can I just set `region` on the resource?"**
It depends on what's shared between the two regions. AWS provider v6 added a per-resource `region` argument, which works well when only the region differs and credentials/authentication are identical — you just add `region = "us-west-2"` to the resource and skip the alias entirely. A provider alias is still necessary when the second region needs different credentials, a different IAM role (via `assume_role`), or when many resources need that region — declaring it once in a provider block avoids repeating `region = "us-west-2"` on every resource. For this demo's CloudNova scenario — same credentials, one archive bucket — either approach works, but aliases are shown because they're the more common pattern in larger configurations with cross-account access.

**Q2. Your team has engineers on Linux, macOS, and Windows. A Windows engineer runs `terraform init` for the first time on a project whose lock file was generated on a teammate's Mac, and it fails with a checksum mismatch. What's the root cause and the fix — and how do you prevent this going forward?**
The lock file's `zh:` hashes are platform-specific — they hash the individual files inside the provider's zip archive, which differ per OS/architecture. When the Mac engineer ran `init` first, the lock file only recorded `darwin_arm64` hashes. The Windows engineer's `init` computes hashes for `windows_amd64`, which aren't in the lock file, so Terraform refuses to proceed — this is the lock file working as designed, rejecting an unverified binary. The fix is `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=windows_amd64`, run once by anyone on the team, which adds hashes for all three platforms without removing existing ones or changing the resolved version. Going forward, this should be part of the standard workflow any time a provider version changes — run the multi-platform lock command before committing `.terraform.lock.hcl`.

**Q3. You need to upgrade the `random` provider from `3.9.0` to a newly released `3.9.1` patch. Walk through the safe process, and explain what could go wrong if you skip steps.**
The constraint `~> 3.9.0` already allows `3.9.1` — but `terraform init` alone won't pick it up, because once a lock file exists, plain `init` always installs the version *recorded in the lock file*, not the newest version the constraint permits. The safe sequence is: run `terraform init -upgrade`, which re-resolves the constraint and downloads `3.9.1`, updating the lock file; then run `terraform plan` to confirm zero unexpected infrastructure changes — a patch version shouldn't change behavior, but verifying this is the point of the exercise; then commit `versions.tf` (if the constraint changed) and `.terraform.lock.hcl` together as one atomic change, ideally tested in a non-production environment first. Skipping the `plan` step risks applying an upgrade that silently changes resource behavior without anyone reviewing the diff — and skipping the multi-platform lock re-run after an upgrade reintroduces the cross-platform checksum problem for teammates on other operating systems.

**Q4. A resource using `provider = aws.west` is failing with `NoSuchBucket`, but the bucket clearly exists when you check the Console in `us-west-2`. What's the likely cause?**
This is almost always a missing `provider = aws.west` on one of the *related* resources — typically a configuration resource like `aws_s3_bucket_versioning` or `aws_s3_bucket_public_access_block` that references the aliased bucket's ID but wasn't given the same provider meta-argument. Terraform doesn't infer the provider from the bucket ID reference alone; each resource independently determines which provider instance to use, defaulting to the unaliased provider if `provider` isn't set. So the versioning resource ends up calling `PutBucketVersioning` against `us-east-2`, where no bucket with that name exists — hence `NoSuchBucket`, even though the bucket is sitting right there in `us-west-2`. The fix is mechanical but easy to miss: every configuration resource tied to an aliased bucket needs the matching `provider = aws.<alias>` line, not just the bucket resource itself.

**Q5. Someone proposes pinning the `aws` provider to `= 6.47.0` (exact version, no patch updates) across the whole team "for maximum stability." What are the tradeoffs, and what would you recommend instead?**
An exact pin (`= 6.47.0`) guarantees everyone gets identical behavior — no surprise from a provider update — but it also means security patches and bug fixes in `6.47.1`, `6.47.2`, etc. require a manual constraint change and a new `terraform init -upgrade` even though those patches are, by definition, backward-compatible bug fixes within the same minor version. The more common and recommended approach is `~> 6.47.0`, which locks the minor version (blocking `6.48.0` and any breaking changes) while still allowing `terraform init -upgrade` to pick up patch-level fixes when the team chooses to run it. Combined with the lock file — which pins the *exact resolved version* until someone deliberately runs `-upgrade` — `~> 6.47.0` gives you both controlled reproducibility (lock file) and the flexibility to take patches when ready (constraint), without the friction of editing `versions.tf` for every patch release.

---

## Key Takeaways

1. **Commit `.terraform.lock.hcl` with multi-platform hashes.** A lock
   file with only one platform's hashes will break teammates on different
   operating systems. `terraform providers lock -platform=...` is a
   one-time fix per provider upgrade.

2. **`~> X.Y.0` is the right constraint for root modules.** It allows
   patch updates (bug fixes, security patches) while blocking minor and
   major version changes that may include breaking changes.

3. **All provider aliases share one version.** You cannot pin `us-east-2`
   to AWS provider v6.47 and `us-west-2` to v6.46. One version constraint
   applies to all instances of the same provider.

4. **Every resource for an aliased bucket needs the `provider` meta-argument.**
   Forgetting it on configuration resources (`versioning`, `encryption`,
   `public_access_block`) routes API calls to the wrong region.
   The error is `NoSuchBucket` — confusing because the bucket exists,
   just not in the region the default provider is targeting.

5. **Provider upgrades are safe when done deliberately.** Upgrade in
   non-production first, run `terraform plan` to confirm zero infrastructure
   changes, commit `versions.tf` and `.terraform.lock.hcl` together
   as one atomic commit.

---

## Next Demo

**Demo 03 — `03-core-workflow`:** Deep dive into the Terraform workflow
commands — `terraform validate`, `terraform fmt`, `terraform plan` with
all flags, saved plan files, `terraform graph`, `TF_LOG` debugging, and
`-target` for partial applies. The workflow you have been using — now
fully understood.

---

## Appendix — Anki Cards

**02-providers-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::02-providers
#separator:Comma
#columns:Front,Back,Tags
"What does the ~> version constraint operator do? Give an example.","Pessimistic constraint — allows patch and/or minor updates within a locked boundary. ~> 6.47.0 allows 6.47.x only (patch updates), blocks 6.48.0. ~> 6.0 allows any 6.x, blocks 7.0.0. Most common operator for root modules.","demo02,versions,ta004-obj2b"
"You have two engineers — one on Linux, one on macOS. Both run terraform init. The macOS engineer gets a checksum mismatch error. What is the cause and fix?","The lock file only has zh: hashes for the Linux platform. The macOS zh: hash is not present. Fix: run terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=windows_amd64 to add hashes for all platforms. Commit the updated lock file.","demo02,lockfile,platforms,ta004-obj2d"
"What is the difference between h1: and zh: hash prefixes in the lock file?","h1: = hash of the provider zip archive as a whole — platform-independent, same value across all OS/arch combinations. zh: = hash of individual files inside the zip — platform-specific, different for linux_amd64 vs darwin_arm64 vs windows_amd64. Terraform verifies both on download.","demo02,lockfile,hashes,ta004-obj2d"
"Can two provider aliases use different versions of the same provider?","No. All instances of the same provider — including all aliases — share one version constraint declared in required_providers. You cannot pin aws to 6.47.0 for us-east-2 and 6.46.0 for us-west-2. One version for the whole provider.","demo02,aliases,versions,ta004-obj2c"
"What does the provider meta-argument do on a resource?","Explicitly assigns the resource to a specific provider alias. Format: provider = aws.west where aws is the provider local name and west is the alias. Without this, the resource uses the default provider. Required for every resource in a multi-provider config that should use a non-default instance.","demo02,aliases,meta-arguments,ta004-obj2c"
"You declare provider aws alias=west in provider.tf but forget to add provider = aws.west on aws_s3_bucket_versioning for the archive bucket. What happens?","Terraform routes the PutBucketVersioning API call to the default provider (us-east-2). The archive bucket lives in us-west-2. Result: NoSuchBucket error — confusing because the bucket exists, just not in the region the default provider targets.","demo02,aliases,troubleshooting"
"What does terraform providers command show?","Lists every provider the configuration requires, their version constraints, and which resources use each provider instance. Shows both the default and aliased instances of the same provider separately.","demo02,cli,providers,ta004-obj2a"
"What is the safe workflow for upgrading a provider version?","1. Update the constraint in versions.tf. 2. Run terraform init -upgrade. 3. Run terraform plan — confirm zero infrastructure changes. 4. Test in non-production first. 5. Commit versions.tf AND .terraform.lock.hcl together as one atomic commit.","demo02,upgrade,lockfile,ta004-obj2b"
"What is the difference between provider aliases and the v6 per-resource region argument?","Aliases: second provider block with alias=name, set region in provider block, all resources for that region use provider=aws.alias. Per-resource region (v6): set region directly on the resource — no second provider block needed. Use aliases when credentials differ per region. Use per-resource region when only the region differs.","demo02,aliases,v6,ta004-obj2c"
"How does Terraform map an aws_s3_bucket resource to the aws provider?","By the resource type prefix. aws_s3_bucket starts with aws_ which maps to the provider with local name aws declared in required_providers. This is why the local name must match the resource type prefix. Renaming the local name to amazon would break all aws_* resources.","demo02,providers,mapping,ta004-obj2a"
"What is ~> 6.0 vs ~> 6.47.0 as a version constraint? When would you use each?","~> 6.0 allows any 6.x.x version (6.0, 6.1, 6.47...), blocks 7.0.0. ~> 6.47.0 allows only 6.47.x, blocks 6.48.0. Use ~> 6.47.0 in root modules to pin to a known-good minor version. Use ~> 6.0 in reusable child modules to allow callers more flexibility.","demo02,versions,ta004-obj2b"
"What command updates providers to the latest version allowed by current constraints?","terraform init -upgrade. Without -upgrade, terraform init uses the version already in the lock file (never downloads newer). With -upgrade, Terraform re-resolves the constraint and downloads the latest matching version, updating the lock file.","demo02,upgrade,cli,ta004-obj2b"
"What does committing .terraform.lock.hcl guarantee for a team?","Every engineer and every CI runner that runs terraform init downloads the exact same provider binary — same version, verified by the same SHA256 hashes. Prevents the situation where different team members get different patch versions and produce different plan results for identical configs.","demo02,lockfile,teams,ta004-obj2d"
"You run terraform providers and see two entries under provider[registry.terraform.io/hashicorp/aws] ~> 6.47.0 — one labelled 'aws — default, us-east-2' and one 'aws.west — aliased, us-west-2'. What does this confirm?","Both the default provider and the aliased provider (west) are correctly declared and resolve to the same version constraint (~> 6.47.0) as required — aliases must share one version. The two entries show two configurations of the same provider, not two different providers. This is a read-only command — it downloads and installs nothing.","demo02,providers,cli,ta004-obj2a"
"After apply, terraform state show aws_s3_bucket.archive shows provider = \"provider[\\\"registry.terraform.io/hashicorp/aws\\\"].west\". What does the .west suffix confirm?","It confirms this specific resource is managed by the ALIASED provider instance (us-west-2), not the default (us-east-2) instance. This is the definitive way to verify provider routing for a resource after apply — the plan output region field is a useful early signal, but state show with the provider field is the authoritative confirmation.","demo02,providers,state,ta004-obj2c"
```

---

## Appendix — Quiz

**02-providers-quiz.md:**

```
# Quiz — Demo 02: Providers: Configuration, Versioning, and the Lock File

> TA-004 exam style. One correct answer unless stated otherwise.
> Target: 80% or above before moving to Demo 03.

---

**Q1.** What does `version = "~> 6.47.0"` allow?

- A) Any version greater than or equal to 6.47.0
- B) Only 6.47.x patch versions — blocks 6.48.0 and above
- C) Any 6.x version — blocks 7.0.0
- D) Exactly 6.47.0 only

<details>
<summary>Answer</summary>

**B** — `~> 6.47.0` locks the minor version (6.47) and allows only patch
updates (6.47.1, 6.47.2...). It blocks 6.48.0 which is a minor version bump.
C would be `~> 6.0`. D would be `= 6.47.0`.

</details>

---

**Q2.** Can two provider aliases use different versions of the same provider?

- A) Yes — each alias can have its own version constraint
- B) No — all aliases share one version constraint in required_providers
- C) Yes — but only if they are in different regions
- D) No — aliases are deprecated in AWS provider v6

<details>
<summary>Answer</summary>

**B** — All instances of the same provider including all aliases share one
version constraint. You cannot have aws v6.47 for one alias and v6.46 for
another. One version for the entire provider.

</details>

---

**Q3.** You forget to add `provider = aws.west` to `aws_s3_bucket_versioning`
for a bucket created with `provider = aws.west`. What error do you get?

- A) Invalid provider reference — aws.west not declared
- B) NoSuchBucket — versioning API called against wrong region
- C) ProviderMismatch — resource and its configuration use different providers
- D) No error — Terraform auto-detects the correct provider from the bucket reference

<details>
<summary>Answer</summary>

**B** — Terraform routes the versioning API call to the default provider
(us-east-2). The bucket lives in us-west-2. AWS returns NoSuchBucket —
confusing because the bucket exists, just not where the default provider
is looking. Every configuration resource for an aliased bucket needs the
same provider meta-argument.

</details>

---

**Q4.** An engineer on macOS gets a checksum mismatch error running
`terraform init` on a lock file generated on Linux. What is the fix?

- A) Delete the lock file and run terraform init again
- B) Run terraform init -upgrade on the macOS machine
- C) Run terraform providers lock -platform=darwin_arm64 to add macOS hashes
- D) Change the version constraint to allow the macOS version

<details>
<summary>Answer</summary>

**C** — The lock file has zh: hashes for linux_amd64 only. Adding
darwin_arm64 hashes with `terraform providers lock -platform=darwin_arm64`
fixes the mismatch. A would work but loses the pinned version. B upgrades
the provider which is not necessary. D is not meaningful — version
constraints are not platform-specific.

</details>

---

**Q5.** What does `terraform init -upgrade` do to `.terraform.lock.hcl`?

- A) Deletes it and regenerates from scratch
- B) Re-resolves version constraints and updates to latest allowed version
- C) Adds hashes for additional platforms
- D) Nothing — the lock file is read-only

<details>
<summary>Answer</summary>

**B** — `terraform init -upgrade` re-resolves the version constraints
from `required_providers`, downloads the latest version that satisfies
them, and updates the lock file with the new version and hashes.
Use C (terraform providers lock) for adding platform hashes.

</details>

---

**Q6.** How does Terraform determine which provider manages `aws_s3_bucket`?

- A) By reading the provider argument inside the resource block
- B) By matching the resource type prefix (aws_) to the provider local name (aws)
- C) By checking the provider registry for the resource type
- D) By the order providers are declared in required_providers

<details>
<summary>Answer</summary>

**B** — Resource type prefix maps to provider local name. `aws_s3_bucket`
starts with `aws_` which maps to the provider declared with local name
`aws` in required_providers. The `provider` meta-argument overrides this
for aliased providers.

</details>

---

**Q7.** Which version constraint should a reusable child module use?

- A) `= 6.47.0` — exact pin for reproducibility
- B) `~> 6.47.0` — same as root module
- C) `>= 6.0` — minimum version, let the root module control exact version
- D) No constraint — modules should accept any version

<details>
<summary>Answer</summary>

**C** — Child modules should declare a minimum version they require
(`>= 6.0`) and let the root module control the exact pinned version.
If a child module pins to `~> 6.47.0` and the root module uses `~> 6.46.0`,
they conflict and Terraform cannot resolve a compatible version.

</details>

---

**Q8.** What is the correct format of the `provider` meta-argument?

- A) `provider = "aws.west"`
- B) `provider = aws.west`
- C) `provider = west`
- D) `provider = "west"`

<details>
<summary>Answer</summary>

**B** — `provider = aws.west` with no quotes. Format is
`<provider_local_name>.<alias_name>`. This is a reference expression, not
a string. Quoting it makes it a string literal — Terraform will error.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Proceed to Demo 03 |
| 6-7/8 | Review wrong answers in Anki, then proceed |
| 4-5/8 | Re-read relevant README sections, retry |
| Below 4/8 | Re-read Demo 02 before proceeding |
```