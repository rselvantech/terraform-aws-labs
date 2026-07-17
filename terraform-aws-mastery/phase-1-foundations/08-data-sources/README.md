# Demo 08 — Data Sources: Reading Without Managing

---

## Overview

Every demo so far has used `data.aws_caller_identity` as a light
preview, always with a note pointing here: "full coverage is Demo 08."
This is that demo. A `data` block is Terraform's way of reading
something that already exists — in AWS, in another Terraform
configuration, or computed locally — without creating, updating, or
destroying it. Understanding exactly what `data` can and cannot do
matters before Demo 09's expressions and Demo 10's multiplicity, both
of which lean on data sources for realistic inputs.

**Real-world scenario — CloudNova:** the platform team needs the
account's default AWS-managed S3 read-only policy's ARN (to attach
elsewhere later), needs to conditionally read an already-existing
"legacy" bucket that predates this Terraform configuration, and needs
the latest Amazon Linux 2023 AMI ID for a compute demo two phases away
— all without ever creating or managing any of these things here.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Identity and Managed Policies                                 │
│  data.aws_caller_identity in full   |   data.aws_iam_policy reads two   │
│  AWS-managed policies by name, not ARN                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Conditionally Reading an Existing Resource                    │
│  count on a data source   |   the index-out-of-range trap when count   │
│  evaluates to 0                                                          │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Reading Compute Metadata                                      │
│  data.aws_ami — the latest Amazon Linux 2023 AMI, read-only, no         │
│  EC2 instance created                                                    │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- `data` vs. `resource` — what each does and does not do
- `data.aws_caller_identity` — full depth (previously only previewed)
- `data.aws_iam_policy` — reading an AWS-managed policy by name
- `count` on a `data` block — conditionally reading a resource that may
  not exist
- `data.aws_ami` — filtering for the most recent matching image

**What this demo does NOT cover:** `for` expressions and the
collection functions used to transform data-source results in depth
are Demo 09's focus — this demo introduces `data` blocks themselves,
not what you do with their output afterward.

---

## Prerequisites

### Knowledge
- Demo 07 completed — outputs, `terraform_remote_state`, and the IAM
  role + SNS topic this trilogy has been maintaining (continued here
  only as context; this demo's resources are all `data`, nothing new
  to manage)

### Required Tools

Same as Demos 05–07 — Terraform `>= 1.15.0`, AWS CLI `>= 2.x`, `jq`.

### Verify AWS Account and Permissions

```bash
aws sts get-caller-identity --profile default
aws configure get region --profile default
```

**Required permissions for this demo:**

```
sts:GetCallerIdentity
iam:GetPolicy
s3:GetBucketLocation, s3:ListBucket
ec2:DescribeImages
```

> For a learning account, `ReadOnlyAccess` managed policy covers all of
> the above — this entire demo only reads, nothing here requires
> write permissions.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain the distinction between a `data` block and a `resource`
   block — what Terraform does and does not do with each
2. ✅ Use `data.aws_caller_identity` to read the current AWS identity
3. ✅ Use `data.aws_iam_policy` to read an AWS-managed policy by name
4. ✅ Use `count` on a `data` block to conditionally read a resource
   that may not exist, and avoid the resulting index-out-of-range trap
5. ✅ Use `data.aws_ami` to look up the latest matching AMI without
   creating any compute resource

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| `data.aws_caller_identity` | Always free | **$0.00** | STS read call |
| `data.aws_iam_policy` | Always free | **$0.00** | IAM read call |
| `data.aws_s3_bucket` | Always free | **$0.00** | S3 metadata read — no objects touched |
| `data.aws_ami` | Always free | **$0.00** | EC2 metadata read — no instance created |
| **Session total** | | **$0.00** | This entire demo only reads — nothing is created |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
08-data-sources/
├── README.md
├── 08-data-sources-anki.csv
├── 08-data-sources-quiz.md
└── src/
    ├── 01-versions.tf       # terraform block + provider version constraints
    ├── 02-provider.tf       # AWS provider: region, profile
    ├── 03-variables.tf      # legacy bucket name (optional, gates count) + policy names
    ├── 04-data-identity-iam.tf   # data.aws_caller_identity + data.aws_iam_policy x2
    ├── 05-data-s3-legacy.tf      # count-gated data.aws_s3_bucket
    ├── 06-data-ami.tf            # data.aws_ami
    ├── 07-outputs.tf              # exposes what was read
    └── break-fix/
        └── broken.tf
```

---

## Recall Check — Demo 07

Answer from memory before reading further:

1. An output is marked `sensitive = true`. Which `terraform output`
   variant(s) still show the plaintext value?
2. What access does `data.terraform_remote_state` grant to the source
   configuration it reads from?
3. A sensitive Terraform value is written into an `aws_ssm_parameter`
   with `type = "String"`. Does `terraform plan`/`apply` catch this?

**Answers**

1. `-json` and `-raw` both bypass `sensitive` redaction and show the
   plaintext value. The default `terraform output` and `terraform
   output NAME` (without `-json`/`-raw`) still redact to `(sensitive
   value)`.
2. Read-only access to that configuration's outputs, via its state
   file — nothing more. There's no write path through remote state,
   and no access to the source configuration's `.tf` files at all.
3. No — it applies successfully and stores the value in plaintext.
   `sensitive` only affects Terraform's own terminal/plan display; it
   enforces nothing about what resource arguments that value flows
   into afterward.

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `data` block (concept) | Read-only reference | Reads existing infrastructure without managing it |
| `data.aws_caller_identity` (full depth) | Data source | Current AWS account ID, ARN, user ID |
| `data.aws_iam_policy` | Data source | Reads an AWS-managed policy by name, returns its ARN and document |
| `count` on a `data` block | Data source argument | Conditionally reads 0 or 1 instances based on an expression |
| `data.aws_ami` | Data source | Filters AMIs by owner/name pattern, returns the most recent match |

**Related constructs worth knowing (not used in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| `for` expression (full) | Collection transformation | Demo 09 |
| `for_each` on a `data` block | Reading multiple instances by key | Demo 10 (contrasted with `count`) |
| `aws_iam_policy` (resource) | Creating a *new* managed policy | Not built in this series yet — `data.aws_iam_policy` here only *reads* existing ones |

---

### Detailed Explanation of New Constructs

#### `data` vs. `resource` — The Core Distinction

A `resource` block tells Terraform "create this, and manage its entire
lifecycle — track it in state, update it when the config changes,
destroy it when the block is removed." A `data` block tells Terraform
"go read this — it already exists, I have no intention of managing
it, and removing this block never destroys anything in AWS."

```hcl
# resource — Terraform creates, updates, and destroys this
resource "aws_iam_role" "deploy" {
  name = "cloudnova-dev-deploy-role"
  # ...
}

# data — Terraform only reads this; it must already exist
data "aws_iam_policy" "s3_read_only" {
  name = "AmazonS3ReadOnlyAccess"
}
```

> **Removing a `data` block from your configuration never destroys
> anything in AWS.** It's the single clearest test for whether
> something belongs in a `data` block or a `resource` block: if
> deleting the Terraform code should NOT delete the real thing, it's
> `data`.

---

#### `data.aws_caller_identity` — Full Depth

```hcl
data "aws_caller_identity" "current" {}
```

The body is intentionally empty — no arguments are required or
accepted. Makes a single `sts:GetCallerIdentity` API call.

| Attribute | Example value | Description |
|---|---|---|
| `account_id` | `"163125980376"` | AWS account ID of the calling identity |
| `arn` | `"arn:aws:iam::163125980376:user/wadmin"` | Full ARN of the caller |
| `user_id` | `"AIDAXXXXXXXXXXXXXXXXX"` | Unique identifier of the caller |

**Why this belongs in `data`, not a variable:** the account ID is
knowable at plan time only by asking AWS directly — it's not something
a caller should have to supply manually (and manually supplying it
risks it being wrong for whichever account is actually authenticated).

---

#### `data.aws_iam_policy` — Reading an AWS-Managed Policy by Name

```hcl
data "aws_iam_policy" "s3_read_only" {
  name = "AmazonS3ReadOnlyAccess"
}
```

| Argument | Required | Description |
|---|---|---|
| `name` | One of `name`/`arn` | The policy's exact name |
| `arn` | One of `name`/`arn` | The policy's full ARN — use when the name alone might be ambiguous |

Returns `arn`, `policy_id`, `path`, `policy` (the JSON document itself,
as a string).

```hcl
output "s3_read_only_arn" {
  value = data.aws_iam_policy.s3_read_only.arn
}
```

> **A typo in `name` fails at `plan` time with "no matching IAM policy
> found"** — not a silent empty result. This is diagnosed directly in
> Break-Fix below.

---

#### `count` on a `data` Block — Conditional Reads

```hcl
data "aws_s3_bucket" "legacy" {
  count  = var.legacy_bucket_name != "" ? 1 : 0
  bucket = var.legacy_bucket_name
}
```

**What this does:** if `var.legacy_bucket_name` is a non-empty string,
`count` evaluates to `1` and Terraform reads that one bucket's
metadata. If `var.legacy_bucket_name` is `""` (the default), `count`
evaluates to `0` and Terraform performs **zero** reads — no API call
happens at all, and `data.aws_s3_bucket.legacy` becomes an empty list.

**Referencing a `count`-gated data source safely:**

```hcl
# UNSAFE — errors if count evaluated to 0, since index [0] doesn't exist
value = data.aws_s3_bucket.legacy[0].arn

# SAFE — checks length first
value = length(data.aws_s3_bucket.legacy) > 0 ? data.aws_s3_bucket.legacy[0].arn : null
```

> **This is the same index-based addressing `count` uses on
> resources** (full coverage in Demo 10) — a `data` block with `count`
> follows identical rules. Referencing `[0]` when `count` evaluated to
> `0` is a real, common error, diagnosed directly in Break-Fix below.

---

#### `data.aws_ami` — Filtering for the Most Recent Match

```hcl
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
```

| Argument | Required | Description |
|---|---|---|
| `most_recent` | No | If multiple AMIs match, pick the newest — without this, multiple matches error |
| `owners` | Yes (practically) | Restrict to a trusted owner — `"amazon"` for AWS-published images |
| `filter` | No, but typically needed | One or more `name`/`values` filters — AWS API-level filter names, not free-text search |

Returns `id`, `name`, `creation_date`, `architecture`, and more.

```hcl
output "latest_al2023_ami_id" {
  value = data.aws_ami.amazon_linux_2023.id
}
```

> **`most_recent = true` is required whenever a filter could match more
> than one AMI.** Without it, `data.aws_ami` errors if more than one
> image matches — it never silently picks one for you.

---

## Lab Step-by-Step Guide

---

## Part A — Identity and Managed Policies

**What you accomplish in Part A:** read the current AWS account's
identity in full, then read two AWS-managed IAM policies by name,
proving neither requires any resource to exist first.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/08-data-sources/src
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
}
```

---

#### `03-variables.tf` — Inputs this demo's data sources depend on

**What this file does in this demo:** `legacy_bucket_name` gates Part
B's `count`-conditional data source; the two policy name variables let
you swap which AWS-managed policies Part A reads without editing the
data blocks themselves.

**03-variables.tf:**

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

variable "legacy_bucket_name" {
  type        = string
  description = "Name of a pre-existing S3 bucket to conditionally read. Empty string = skip entirely."
  default     = ""
}

variable "s3_policy_name" {
  type        = string
  description = "Name of the AWS-managed S3 policy to read"
  default     = "AmazonS3ReadOnlyAccess"
}

variable "ec2_policy_name" {
  type        = string
  description = "Name of the AWS-managed EC2 policy to read"
  default     = "AmazonEC2ReadOnlyAccess"
}
```

---

#### `04-data-identity-iam.tf` — Identity and managed policy reads

**What this file does in this demo:** reads the current caller
identity and two AWS-managed IAM policies — three `data` blocks, zero
`resource` blocks, zero things created.

**04-data-identity-iam.tf:**

```hcl
data "aws_caller_identity" "current" {}

data "aws_iam_policy" "s3_read_only" {
  name = var.s3_policy_name
}

data "aws_iam_policy" "ec2_read_only" {
  name = var.ec2_policy_name
}
```

---

### Step 3 — Apply and verify

```bash
terraform init
terraform validate
terraform apply
```

Type `yes`. Expected output:

```
data.aws_caller_identity.current: Reading...
data.aws_caller_identity.current: Read complete after 0s [id=163125980376]
data.aws_iam_policy.s3_read_only: Reading...
data.aws_iam_policy.s3_read_only: Read complete after 0s [id=arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess]
data.aws_iam_policy.ec2_read_only: Reading...
data.aws_iam_policy.ec2_read_only: Read complete after 0s [id=arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess]

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **`Resources: 0 added` — this is expected and correct.** `data`
> reads don't count as resources added, changed, or destroyed; they're
> reads, not managed lifecycle events.

---

## Part B — Conditionally Reading an Existing Resource

**What you accomplish in Part B:** add a `count`-gated `data
"aws_s3_bucket"` block, exercise it both with and without
`legacy_bucket_name` set, and confirm the index-out-of-range behavior
when `count` evaluates to `0`.

### Step 1 — Create `05-data-s3-legacy.tf`

**05-data-s3-legacy.tf:**

```hcl
data "aws_s3_bucket" "legacy" {
  count  = var.legacy_bucket_name != "" ? 1 : 0
  bucket = var.legacy_bucket_name
}
```

### Step 2 — Apply without the variable set

```bash
terraform apply
```

Expected: no `aws_s3_bucket.legacy` read occurs at all — `count`
evaluated to `0`.

```bash
terraform console
```

```hcl
> length(data.aws_s3_bucket.legacy)
0
> data.aws_s3_bucket.legacy
[]
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

### Step 3 — Apply with the variable set, and observe the index trap

```bash
terraform apply -var="legacy_bucket_name=cloudnova-legacy-uploads"
```

Expected — assuming a bucket with that name genuinely exists in your
account:

```
data.aws_s3_bucket.legacy[0]: Reading...
data.aws_s3_bucket.legacy[0]: Read complete after 0s [id=cloudnova-legacy-uploads]

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment. If no such bucket exists in your account, this errors
> with "NoSuchBucket" instead — that's expected if you haven't created
> one; the point of this step is the addressing behavior, not requiring
> you to provision a real legacy bucket.

Now revert to the default (no `legacy_bucket_name`) and try referencing
index `[0]` directly in an output without a length guard:

```hcl
output "legacy_bucket_arn_unsafe" {
  value = data.aws_s3_bucket.legacy[0].arn
}
```

```bash
terraform apply
```

Expected:

```
╷
│ Error: Invalid index
│   The given key does not identify an element in this collection value:
│   the collection has no elements.
╵
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **This error message is generic ("collection has no elements"), not
> specific to `count` or data sources** — it's the same "Invalid index"
> error any out-of-bounds list access produces, which is exactly why
> the length guard from Concepts above matters: nothing about a
> `count`-gated data source's error message tells you *why* the
> collection is empty.

Remove `legacy_bucket_arn_unsafe` before continuing — it must not
remain in `07-outputs.tf`.

---

## Part C — Reading Compute Metadata

**What you accomplish in Part C:** look up the latest Amazon Linux
2023 AMI ID, entirely read-only — no EC2 instance is created anywhere
in this demo.

### Step 1 — Create `06-data-ami.tf`

**06-data-ami.tf:**

```hcl
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
```

### Step 2 — Create `07-outputs.tf` and apply

**07-outputs.tf:**

```hcl
output "current_account_id" {
  description = "Current AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "s3_read_only_policy_arn" {
  description = "ARN of the AWS-managed S3 read-only policy"
  value       = data.aws_iam_policy.s3_read_only.arn
}

output "latest_al2023_ami_id" {
  description = "Latest Amazon Linux 2023 AMI ID in this region"
  value       = data.aws_ami.amazon_linux_2023.id
}

output "latest_al2023_ami_creation_date" {
  description = "Creation date of the resolved AMI, to confirm it's genuinely current"
  value       = data.aws_ami.amazon_linux_2023.creation_date
}
```

```bash
terraform apply
```

### Step 3 — Cross-verify the resolved AMI against a real API call

```bash
aws ec2 describe-images \
  --image-ids "$(terraform output -raw latest_al2023_ami_id)" \
  --query "Images[0].[Name,CreationDate]" --output text
```

Expected: the name and creation date match `terraform output
latest_al2023_ami_creation_date` — confirming `data.aws_ami` resolved
to a real, current image, not a stale or hardcoded one.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## Cleanup

```bash
terraform destroy
```

Expected:

```
Destroy complete! Resources: 0 destroyed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **`0 destroyed` is correct and expected.** Every block in this demo
> was `data` — there was never anything to destroy. "Cleanup" here
> just confirms the state file itself is left clean, not that any real
> AWS resource is removed.

---

## What You Learned

1. ✅ `data` blocks read existing infrastructure without creating,
   updating, or destroying it — removing a `data` block never deletes
   anything real
2. ✅ `data.aws_caller_identity` needs no arguments and returns the
   current account ID, ARN, and user ID
3. ✅ `data.aws_iam_policy` reads an AWS-managed policy by `name` (or
   `arn`) — a typo in `name` errors immediately, not silently
4. ✅ `count` works identically on `data` blocks as on `resource`
   blocks — a `count`-gated data source with `count = 0` becomes an
   empty list, and indexing `[0]` on it errors with "Invalid index"
5. ✅ `data.aws_ami` requires `most_recent = true` whenever a filter
   could match more than one image, and resolves to a genuinely
   current AMI, verifiable against a live `describe-images` call

---

## Cert Tips — TA-004 Objectives Covered

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `data` vs. `resource` distinction | TA-004 Obj 2 (Terraform basics / core concepts) | Frequently tested — "does removing this block destroy anything in AWS?" |
| `data.aws_iam_policy` by `name` | TA-004 Obj (AWS resource management) | A typo errors at `plan`, not silently |
| `count` on a `data` block | TA-004 Obj 2 | Same rules as `count` on `resource` — full multiplicity coverage is Demo 10 |
| `data.aws_ami` `most_recent` | TA-004 Obj (AWS resource management) | Required whenever a filter could match more than one AMI |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam asks what happens when a `data` block is removed from the configuration | Recognizing nothing in AWS is destroyed — `data` never manages lifecycle | Assuming `data` blocks behave like `resource` blocks on removal |
| Exam shows `data.aws_s3_bucket.legacy[0]` referenced when `count` could evaluate to 0 | Recognizing this needs a length guard, or it errors with "Invalid index" | Assuming `data` sources with `count = 0` are simply skipped silently everywhere they're referenced |
| Exam gives a `data.aws_ami` filter matching multiple images with no `most_recent` | Recognizing this errors rather than picking one AMI | Assuming Terraform automatically resolves ambiguity by picking the newest without being told to |

### Exam Task — Write a complete configuration

**Task:** CloudNova needs to read the AWS-managed
`AmazonDynamoDBReadOnlyAccess` policy by name, conditionally read an
existing DynamoDB backup vault only if a `backup_vault_name` variable
is non-empty (using `count`), and look up the latest Amazon Linux 2023
AMI. Write all three `data` blocks plus the `backup_vault_name`
variable from scratch.

**Block types required:** `data "aws_iam_policy"`, `data
"aws_backup_vault"` (×1, `count`-gated), `data "aws_ami"`, `variable`
(×1)

**Official documentation:**
- [Data Sources](https://developer.hashicorp.com/terraform/language/data-sources)
- [`aws_ami` Data Source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami)

**What to practise:**
1. Open the Data Sources page — confirm the exact wording Terraform
   uses for what removing a `data` block does (or doesn't) affect
2. Write the configuration from scratch without looking at this
   demo's `.tf` files
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
variable "backup_vault_name" {
  type        = string
  description = "Name of a pre-existing backup vault to conditionally read"
  default     = ""
}

data "aws_iam_policy" "dynamodb_read_only" {
  name = "AmazonDynamoDBReadOnlyAccess"
}

data "aws_backup_vault" "existing" {
  count = var.backup_vault_name != "" ? 1 : 0
  name  = var.backup_vault_name
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```

**Arguments you must know without looking up:**
- `data.aws_iam_policy` needs `name` or `arn` — not both, not neither
- `count` on a `data` block follows identical addressing rules to
  `count` on a `resource` block — index `[0]` errors if `count`
  evaluated to `0`

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Error: no matching IAM policy found` | Typo or wrong casing in `data.aws_iam_policy`'s `name` argument | Confirm the exact policy name via `aws iam list-policies --scope AWS \| grep -i <partial-name>` |
| `Error: Invalid index` on a `data` block | Referencing `[0]` on a `count`-gated data source when `count` evaluated to `0` | Guard with `length(data.x.y) > 0 ? data.x.y[0].attr : null` |
| `data.aws_ami` errors with multiple matching images | `most_recent = true` missing, and more than one AMI matches the filters | Add `most_recent = true`, or tighten the `filter` blocks |
| `data.aws_s3_bucket` errors with `NoSuchBucket` | The bucket name doesn't exist in this account/region | Confirm the exact bucket name with `aws s3 ls \| grep <partial-name>` |

---

## Break-Fix Scenario

Three deliberate errors, all data-source-specific. Diagnose using
`terraform validate`/`plan` — do not look at answers first.

```bash
cd src/break-fix/
terraform init
terraform validate
terraform plan
```

#### `broken.tf` — Three deliberate data-source errors

**What this file does in this demo:** a self-contained configuration
with a malformed `aws_iam_policy` name, a `data.aws_ami` attribute
typo, and an unguarded index into a `count`-gated `data.aws_s3_bucket`
— diagnose all three.

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
  region = "us-east-2"
}

# Error 1: wrong policy name (typo)
data "aws_iam_policy" "broken_policy" {
  name = "AmazonS3ReadOnlyAcces" # missing final 's'
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Error 2: attribute typo — .image_name doesn't exist, the real attribute is .name
output "ami_name" {
  value = data.aws_ami.amazon_linux_2023.image_name
}

variable "legacy_bucket_name" {
  type    = string
  default = ""
}

data "aws_s3_bucket" "legacy" {
  count  = var.legacy_bucket_name != "" ? 1 : 0
  bucket = var.legacy_bucket_name
}

# Error 3: unguarded index — errors when legacy_bucket_name is left at its default ""
output "legacy_bucket_arn" {
  value = data.aws_s3_bucket.legacy[0].arn
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — malformed/wrong policy name**
`terraform plan` errors: "no matching IAM policy found" — `name` is
missing the final `s` (`AmazonS3ReadOnlyAcces` instead of
`AmazonS3ReadOnlyAccess`). Fix: correct the exact policy name — verify
against `aws iam list-policies --scope AWS` if unsure.

**Error 2 — nonexistent attribute reference**
`terraform plan` errors that `image_name` is not a valid attribute on
`data.aws_ami` — the correct attribute is `.name`. Fix: change
`.image_name` to `.name`.

**Error 3 — unguarded index on a `count`-gated data source**
With `legacy_bucket_name` left at its default `""`, `count` evaluates
to `0`, so `data.aws_s3_bucket.legacy` is an empty list. Referencing
`[0]` errors: "Invalid index — the collection has no elements." Fix:
guard with `length(data.aws_s3_bucket.legacy) > 0 ?
data.aws_s3_bucket.legacy[0].arn : null`.

</details>

**Cleanup:**
```bash
cd src/break-fix/
rm -f terraform.tfstate terraform.tfstate.backup
cd ../..
```
No resources were ever created in this scenario — every block here is
`data`.

---

## Interview Prep

**Q1. A teammate asks: "If I delete this `data` block from my `.tf` file, will it delete the S3 bucket it's reading?" What's your answer?**
No — that's the entire point of `data` versus `resource`. A `data` block only reads something that already exists; Terraform never tracks it as something it's responsible for creating, updating, or destroying. Removing the block just means Terraform stops reading it on future plans — the real S3 bucket is completely unaffected, because Terraform never had lifecycle ownership of it to begin with.

**Q2. Why does `data.aws_ami` require `most_recent = true` when multiple images could match, instead of Terraform just picking one automatically?**
Because silently picking one out of several ambiguous matches would be exactly the kind of implicit, unpredictable behavior Terraform's design philosophy avoids — the same reasoning behind `count`/`for_each` refusing to coexist on one resource. `most_recent = true` makes the tie-breaking rule explicit and visible in the code, rather than leaving "which AMI did this resolve to" as something that could silently change between runs based on API ordering.

**Q3. A `count`-gated data source has `count = 0` in the current plan. A teammate references `data.x.y[0].attr` directly and gets "Invalid index." Walk through your diagnosis.**
First I'd check what `count`'s condition actually evaluated to — most likely a variable that's currently empty or false, causing `count` to resolve to `0` rather than `1`. Since a `data` block with `count = 0` produces an empty list, not a single instance, indexing `[0]` directly is exactly the same class of error as indexing an empty list literal — nothing data-source-specific about the error itself. The fix is either to confirm the input that drives `count` is what you expected, or to add a length guard if `count = 0` is a legitimate, expected state that other code needs to handle gracefully.

**Q4. When would you use `data.aws_iam_policy` instead of just hardcoding the well-known ARN for an AWS-managed policy like `AmazonS3ReadOnlyAccess`?**
The ARN for AWS-managed policies is actually predictable and stable (`arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess`), so hardcoding it would technically work. The real value of `data.aws_iam_policy` is readability and self-documentation — the code says "the S3 read-only policy" by name rather than an opaque ARN string, and it also gives you the policy's actual JSON document via `.policy` if you need to inspect or reference specific statements from it, which a hardcoded ARN string alone can't provide.

---

## Key Takeaways

1. **The test for `data` vs. `resource`: does removing this block
   destroy anything real?** If no, it's `data`. If yes, it's `resource`.

2. **`data.aws_caller_identity` takes no arguments** — an empty `{}`
   body is correct, not incomplete.

3. **A typo in `data.aws_iam_policy`'s `name` fails loudly at `plan`
   time** — "no matching IAM policy found," not a silent empty result.

4. **`count` on a `data` block follows identical rules to `count` on a
   `resource` block.** `count = 0` produces an empty list; indexing
   `[0]` on it errors with "Invalid index," the same generic error any
   out-of-bounds list access produces.

5. **`data.aws_ami` requires `most_recent = true` whenever more than
   one image could match** — Terraform never silently picks one for
   you.

> **Demo scope:** Primary concept: `data` blocks — reading existing
> infrastructure without managing it. Supporting concepts:
> `data.aws_caller_identity` in full, `data.aws_iam_policy`, `count` on
> a data source and its index-out-of-range trap, and `data.aws_ami`
> filtering.
> Estimated completion time: 35 minutes (reading + hands-on + verification).
> Checkpoints: 3 natural stopping points (end of Part A, end of Part B,
> end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws iam list-policies --scope AWS \| grep -i NAME` | Confirms the exact spelling of an AWS-managed policy name |
| `terraform console` | Interactively check a `count`-gated data source's length/contents |
| `length(data.x.y)` | Returns `0` or `1` for a `count`-gated data source — guard indexing with this |
| `aws ec2 describe-images --image-ids ID` | Cross-verifies a `data.aws_ami` result against the live API |
| `aws s3 ls \| grep NAME` | Confirms an S3 bucket name before referencing it in `data.aws_s3_bucket` |

---

## Next Demo

**Demo 09 — Expressions and Collection Functions:** `for` expression
full syntax (list→list, list→map, map→map), filtering with `if`,
advanced patterns, `toset()`/`keys()`/`values()`/`zipmap()`/`lookup()`/
`flatten()`, and a new `aws_cloudwatch_log_metric_filter` alongside
`for_each`-driven `aws_cloudwatch_log_group`s — with a tangible,
verifiable result: real log events actually counted by a real metric.

---

## Appendix — Anki Cards

**08-data-sources-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::08-data-sources
#separator:Comma
#columns:Front,Back,Tags
"What is the core distinction between a data block and a resource block?","A resource block tells Terraform to create, update, and destroy something — full lifecycle management, tracked in state. A data block only reads something that already exists — removing a data block from the configuration never destroys anything in AWS.","demo08,data-sources,ta004"
"Does data.aws_caller_identity require any arguments?","No — the body is intentionally empty ({}). It makes a single sts:GetCallerIdentity call and returns account_id, arn, and user_id with no input needed.","demo08,data-sources,caller-identity"
"data.aws_iam_policy has a typo in its name argument. What happens at terraform plan?","It errors immediately with 'no matching IAM policy found' — not a silent empty result. The typo must be fixed before plan succeeds.","demo08,data-sources,break-fix,ta004"
"Does count work the same way on a data block as it does on a resource block?","Yes — identical rules. count = 0 produces an empty list for that data source; count = 1 produces a single instance addressed as data.x.y[0]. Full multiplicity coverage (for_each, splat) is Demo 10.","demo08,data-sources,count,ta004"
"A count-gated data source has count = 0 in the current plan. A teammate references data.x.y[0].attr directly. What happens?","Error: Invalid index — 'the collection has no elements.' This is the same generic out-of-bounds error any empty-list index access produces, not something data-source-specific. Guard with length(data.x.y) > 0 first.","demo08,data-sources,count,break-fix"
"Why does data.aws_ami require most_recent = true when multiple AMIs could match the filters?","Without it, data.aws_ami errors if more than one image matches — Terraform never silently picks one for you. most_recent = true makes the tie-breaking rule explicit rather than leaving ambiguous resolution to chance.","demo08,data-sources,ami,ta004"
"What is the simplest test for whether something belongs in a data block vs. a resource block?","Ask: does removing this block from the configuration destroy anything real? If no, it's data. If yes, it's resource. This is the cleanest way to decide, since data never has lifecycle ownership.","demo08,data-sources,distinction"
"Why might you use data.aws_iam_policy instead of hardcoding a well-known AWS-managed policy ARN?","Readability/self-documentation (the code says 'the S3 read-only policy' by name, not an opaque ARN), plus it exposes the policy's actual JSON document via .policy if you need to reference specific statements — something a hardcoded ARN string alone can't provide.","demo08,data-sources,iam-policy"
"What does 'Resources: 0 added, 0 changed, 0 destroyed' mean after applying a configuration made entirely of data blocks?","This is expected and correct — data reads don't count as resources added, changed, or destroyed. They're reads, not managed lifecycle events, so a data-only configuration always reports zero on all three counts.","demo08,data-sources,apply"
```

---

## Appendix — Quiz

**08-data-sources-quiz.md:**

```markdown
# Quiz — Demo 08: Data Sources

> One correct answer per question unless stated otherwise.
> Target: 80% or above before moving to Demo 09.
> TA-004 exam style.

---

**Q1.** What is the core distinction between a `data` block and a
`resource` block?

A. `data` blocks are faster to apply
B. `resource` blocks manage full lifecycle (create/update/destroy);
   `data` blocks only read something that already exists
C. `data` blocks can only be used with AWS, `resource` blocks work with
   any provider
D. There is no meaningful distinction — both behave identically

<details>
<summary>Answer</summary>

**B.** `resource` blocks are tracked in state and Terraform manages
their full lifecycle. `data` blocks only read — removing one never
destroys anything real. **A** is wrong — speed isn't the distinguishing
factor. **C** is wrong — both `data` and `resource` blocks exist across
all providers. **D** is wrong — this is precisely the distinction being
tested.

</details>

---

**Q2.** Does `data.aws_caller_identity` require any arguments?

A. Yes — `account_id` must be specified
B. Yes — `region` is required
C. No — the body is intentionally empty
D. Only `profile` is required

<details>
<summary>Answer</summary>

**C.** `data "aws_caller_identity" "current" {}` — an empty body is
correct and complete. **A**, **B**, and **D** are all wrong — none of
these are valid or required arguments; the data source simply reads
whatever identity the provider is currently authenticated as.

</details>

---

**Q3.** `data.aws_iam_policy`'s `name` argument has a typo. What happens
at `terraform plan`?

A. It silently returns an empty result
B. It errors immediately with "no matching IAM policy found"
C. It falls back to a default policy
D. It only errors at `apply`, not `plan`

<details>
<summary>Answer</summary>

**B.** The error surfaces immediately at `plan` time, loudly, not
silently. **A** is wrong — there's no silent-empty-result behavior for
a nonexistent named policy. **C** is wrong — there's no fallback
mechanism. **D** is wrong — `data` blocks are read during `plan`, so
this error appears before `apply` is even considered.

</details>

---

**Q4.** A `data` block has `count = 0` in the current plan. What does
`data.x.y` become?

A. `null`
B. An empty list
C. An error is raised immediately at `plan`
D. A list with one `null` element

<details>
<summary>Answer</summary>

**B.** `count = 0` produces an empty list for that data source —
identical to how `count = 0` behaves on a `resource` block. **A** is
wrong — it's an empty list, not `null`. **C** is wrong — `count = 0`
itself is valid and doesn't error; only referencing `[0]` on the
resulting empty list would error. **D** is wrong — there's no
placeholder `null` element; the list is genuinely empty (length 0).

</details>

---

**Q5.** Referencing `data.aws_s3_bucket.legacy[0].arn` when `count`
evaluated to `0`. What happens?

A. Returns `null`
B. Returns an empty string
C. Errors: "Invalid index — the collection has no elements"
D. Silently skips this output only

<details>
<summary>Answer</summary>

**C.** This is a genuine out-of-bounds index error — the same class of
error any empty-list `[0]` access produces, not something specific to
data sources. **A** and **B** are wrong — Terraform doesn't return a
placeholder value for invalid indices; it errors. **D** is wrong —
there's no per-output silent-skip behavior; the error blocks the
`plan`/`apply` entirely.

</details>

---

**Q6.** Why does `data.aws_ami` require `most_recent = true` when
multiple AMIs could match the given filters?

A. It's purely cosmetic and has no functional effect
B. Without it, Terraform errors if more than one AMI matches — it
   never silently picks one
C. It's required syntax with no semantic meaning
D. It makes the lookup faster

<details>
<summary>Answer</summary>

**B.** `most_recent = true` makes the tie-breaking rule explicit.
Without it, ambiguous matches (more than one AMI) cause an error rather
than an implicit, unpredictable choice. **A** is wrong — it has a real
functional effect on ambiguous-match resolution. **C** is wrong — it
carries genuine semantic meaning. **D** is wrong — it doesn't affect
lookup performance, only tie-breaking behavior.

</details>

---

**Q7.** What is the simplest test for whether something belongs in a
`data` block instead of a `resource` block?

A. Whether it costs money
B. Whether removing the Terraform block would destroy the real thing
C. Whether it's an AWS-managed vs. customer-managed resource
D. Whether it was created before or after this Terraform configuration existed

<details>
<summary>Answer</summary>

**B.** If deleting the code should NOT delete the real thing, it's
`data`. If it should, it's `resource`. **A** is wrong — cost has no
bearing on this distinction. **C** is wrong — AWS-managed vs.
customer-managed is a separate axis (e.g., you can have a `resource`
for a customer-managed policy). **D** is wrong, though tempting — while
`data` is often used for pre-existing things, the deciding factor is
lifecycle ownership, not simply creation order.

</details>

---

**Q8.** After applying a configuration made entirely of `data` blocks,
what does `Apply complete! Resources: 0 added, 0 changed, 0 destroyed`
mean?

A. The apply failed silently
B. This is expected — data reads don't count as resources added, changed, or destroyed
C. Terraform detected no data sources to read
D. All data sources returned empty results

<details>
<summary>Answer</summary>

**B.** This is the correct, expected outcome for a data-only
configuration — reads aren't lifecycle events. **A** is wrong — the
apply succeeded; "0 added" doesn't indicate failure. **C** is wrong —
the data sources were read (visible in the "Reading.../Read complete"
lines); they just don't count toward the resource tally. **D** is
wrong — the data sources can return real, non-empty results while
still reporting zero on all three resource counts.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 09 |
| 7/8 | Review the wrong answer, then proceed |
| 6/8 | Re-read the relevant section, retry those questions |
| Below 6/8 | Re-read the full demo and redo the walkthrough before proceeding |
```