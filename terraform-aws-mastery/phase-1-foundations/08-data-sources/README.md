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

<details>
<summary>Answers</summary>

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

</details>

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

**Verify:**

```
Console → IAM → Policies → search "AmazonS3ReadOnlyAccess"
  → confirms this AWS-managed policy exists and its ARN matches
    `data.aws_iam_policy.s3_read_only.arn` (via `terraform console`) ✅
```

---

## Part B — Conditionally Reading an Existing Resource

**What you accomplish in Part B:** add a `count`-gated `data
"aws_s3_bucket"` block, exercise it both with and without
`legacy_bucket_name` set, and confirm the index-out-of-range behavior
when `count` evaluates to `0`.

### Step 1 — Create `05-data-s3-legacy.tf`

**What this file does in this demo:** a single `count`-gated `data`
block — `count` evaluates to `1` only if `var.legacy_bucket_name` is
non-empty, giving Part B a live example of a data source that may or
may not actually read anything, depending on input.

Create a file **05-data-s3-legacy.tf** and add the below content:

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

Now revert to the default (no `legacy_bucket_name`) and observe the
index error directly via `terraform console`, without needing an
output block at all — `07-outputs.tf` isn't created until Part C, so
this demonstration deliberately stays in `console` rather than
requiring a file that doesn't exist yet:

```bash
terraform apply
terraform console
```

```hcl
> data.aws_s3_bucket.legacy[0].arn
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

```bash
exit
```

---

## Part C — Reading Compute Metadata

**What you accomplish in Part C:** look up the latest Amazon Linux
2023 AMI ID, entirely read-only — no EC2 instance is created anywhere
in this demo.

### Step 1 — Create `06-data-ami.tf`

**What this file does in this demo:** a single `data.aws_ami` block —
`most_recent = true` plus two `filter` blocks narrow the search to
exactly one image, an Amazon Linux 2023 AMI, without creating any
compute resource at all.

Create a file **06-data-ami.tf** and add the below content:

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

**What this file does in this demo:** exposes everything this demo has
read across all three Parts — the account ID, the S3 policy ARN, and
the resolved AMI's ID and creation date — so Step 3 has something to
cross-verify against a live API call.

Create a file **07-outputs.tf** and add the below content:

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

**Verify:**

```
Console → EC2 → AMI Catalog (or "AMIs" under Images, filtered to "Owned by me" → "Public images")
  → search for the AMI ID from `terraform output latest_al2023_ami_id`
  → confirm the name matches al2023-ami-*-x86_64 and the creation
    date is recent, not stale ✅
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

## Cert Tips — TA-004

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `data` vs. `resource` distinction | TA-004 Obj 4a (Demonstrate use of resource and data source blocks) | Frequently tested — "does removing this block destroy anything in AWS?" |
| `data.aws_iam_policy` by `name` | TA-004 Obj 4a (AWS resource management) | A typo errors at `plan`, not silently |
| `count` on a `data` block | TA-004 Obj 4a | Same rules as `count` on `resource` — full multiplicity coverage is Demo 10 |
| `data.aws_ami` `most_recent` | TA-004 Obj 4a (AWS resource management) | Required whenever a filter could match more than one AMI |

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
"What is the core distinction between a data block and a resource block?","A resource block tells Terraform to create, update, and destroy something — full lifecycle management, tracked in state. A data block only reads something that already exists — removing a data block from the configuration never destroys anything in AWS.","demo08,data-sources,ta004-obj4a"
"Does data.aws_caller_identity require any arguments?","No — the body is intentionally empty ({}). It makes a single sts:GetCallerIdentity call and returns account_id, arn, and user_id with no input needed.","demo08,data-sources,caller-identity"
"data.aws_iam_policy has a typo in its name argument. What happens at terraform plan?","It errors immediately with 'no matching IAM policy found' — not a silent empty result. The typo must be fixed before plan succeeds.","demo08,data-sources,break-fix,ta004-obj4a"
"Does count work the same way on a data block as it does on a resource block?","Yes — identical rules. count = 0 produces an empty list for that data source; count = 1 produces a single instance addressed as data.x.y[0]. Full multiplicity coverage (for_each, splat) is Demo 10.","demo08,data-sources,count,ta004-obj4a"
"A count-gated data source has count = 0 in the current plan. A teammate references data.x.y[0].attr directly. What happens?","Error: Invalid index — 'the collection has no elements.' This is the same generic out-of-bounds error any empty-list index access produces, not something data-source-specific. Guard with length(data.x.y) > 0 first.","demo08,data-sources,count,break-fix"
"Why does data.aws_ami require most_recent = true when multiple AMIs could match the filters?","Without it, data.aws_ami errors if more than one image matches — Terraform never silently picks one for you. most_recent = true makes the tie-breaking rule explicit rather than leaving ambiguous resolution to chance.","demo08,data-sources,ami,ta004-obj4a"
"What is the simplest test for whether something belongs in a data block vs. a resource block?","Ask: does removing this block from the configuration destroy anything real? If no, it's data. If yes, it's resource. This is the cleanest way to decide, since data never has lifecycle ownership.","demo08,data-sources,distinction"
"Why might you use data.aws_iam_policy instead of hardcoding a well-known AWS-managed policy ARN?","Readability/self-documentation (the code says 'the S3 read-only policy' by name, not an opaque ARN), plus it exposes the policy's actual JSON document via .policy if you need to reference specific statements — something a hardcoded ARN string alone can't provide.","demo08,data-sources,iam-policy"
"What does 'Resources: 0 added, 0 changed, 0 destroyed' mean after applying a configuration made entirely of data blocks?","This is expected and correct — data reads don't count as resources added, changed, or destroyed. They're reads, not managed lifecycle events, so a data-only configuration always reports zero on all three counts.","demo08,data-sources,apply"
"data.aws_iam_policy requires name or arn. When would you use arn instead of name?","Use arn when the policy name alone could be ambiguous or when you already have the ARN available — arn is a more precise, unambiguous identifier. One of name or arn is required; providing both or neither is invalid.","demo08,data-sources,iam-policy,ta004-obj4a"
```

---

## Appendix — Quiz

**08-data-sources-quiz.md:**

````markdown
# Quiz — Demo 08: Data Sources

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 09.

---

**Q1. (True/False)** Removing a `data` block from a Terraform
configuration destroys the real-world thing it was reading.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `data` blocks never have lifecycle ownership — removing
one only means Terraform stops reading it on future plans. The real
resource, wherever it lives, is completely unaffected.

</details>

---

**Q2. (Multiple Choice)** What is the fundamental difference between a
`resource` block and a `data` block?

- A) `resource` blocks are AWS-only; `data` blocks work with any provider
- B) `resource` blocks manage full lifecycle (create/update/destroy, tracked in state); `data` blocks only read
- C) `data` blocks always run before `resource` blocks
- D) There's no real difference — both are interchangeable syntax

<details>
<summary>Answer</summary>

**B.** This is the core distinction. Both block types exist across
every provider (A is wrong), and while data sources are often read
early in the graph, that's a consequence of dependency ordering, not a
fixed rule (C is wrong).

</details>

---

**Q3. (True/False)** `data "aws_caller_identity" "current" {}` is
incomplete — it requires at least a `region` argument.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** An empty body is correct and complete for this data
source — it needs no input at all, and returns the current account ID,
ARN, and user ID based purely on how the provider is authenticated.

</details>

---

**Q4. (Multiple Choice)** `data.aws_iam_policy` requires which of the
following?

- A) Both `name` and `arn` together
- B) Neither `name` nor `arn` — it reads the account's default policy
- C) Exactly one of `name` or `arn`
- D) Only `arn` — `name` isn't a valid argument

<details>
<summary>Answer</summary>

**C.** One of the two identifies which policy to read — providing both
or neither is invalid. `arn` is useful when a name alone could be
ambiguous; `name` is more readable for well-known AWS-managed policies.

</details>

---

**Q5. (Multiple Choice)** `data.aws_iam_policy`'s `name` argument has a
typo that doesn't match any real policy. What happens?

- A) Silently resolves to an empty result
- B) Errors immediately at `plan` time: "no matching IAM policy found"
- C) Falls back to a default AWS-managed policy
- D) Only errors at `apply`, never at `plan`

<details>
<summary>Answer</summary>

**B.** This fails loudly and immediately during `plan`'s refresh step —
data source reads happen at plan time, so a nonexistent-policy error
surfaces well before `apply` would even be considered.

</details>

---

**Q6. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about `count` on a `data` block are correct?

- A) `count = 0` produces `null` for that data source
- B) `count = 0` produces an empty list for that data source
- C) Indexing `[0]` on a `count = 0` data source errors with "Invalid index"
- D) `data` blocks don't support the `count` meta-argument at all
- E) `count` behaves fundamentally differently on `data` blocks than on `resource` blocks

<details>
<summary>Answer</summary>

**B and C.** `count = 0` produces a genuinely empty list (not `null`),
and indexing `[0]` into that empty list produces the same generic
out-of-bounds error any empty-list index access would. `count` works
identically on `data` and `resource` blocks (E is wrong), and `data`
blocks fully support it (D is wrong).

</details>

---

**Q7. (Multiple Choice)** What kind of error does `data.aws_s3_bucket.legacy[0].arn`
produce when `count` evaluated to `0`?

- A) A data-source-specific error naming the missing bucket
- B) A generic "Invalid index — the collection has no elements" error, the same as any out-of-bounds list access
- C) `null`, silently
- D) A warning, but the plan still succeeds

<details>
<summary>Answer</summary>

**B.** Nothing about this error is specific to data sources — it's the
identical error any list literal's out-of-bounds index would produce.
This is exactly why the error message alone doesn't explain *why* the
list is empty; that requires checking what drives `count`.

</details>

---

**Q8. (Multiple Choice)** A `data.aws_ami` block's filters could match
three different AMIs, and `most_recent` is not set. What happens?

- A) Terraform picks the newest one automatically
- B) Terraform picks the first one returned by the API
- C) Terraform errors — ambiguous matches require an explicit tie-breaking rule
- D) Terraform returns all three as a list

<details>
<summary>Answer</summary>

**C.** Without `most_recent = true`, ambiguous filter matches cause an
error rather than an implicit choice — consistent with Terraform's
general avoidance of silent, unpredictable resolution.

</details>

---

**Q9. (Multiple Choice)** Why does `data.aws_ami` typically include
`owners = ["amazon"]` alongside its `filter` blocks?

- A) It's required syntax with no functional effect
- B) It restricts results to images published by a specific trusted account, avoiding unrelated matches from other accounts
- C) It determines which region the AMI is looked up in
- D) It sets the price tier of the resulting AMI

<details>
<summary>Answer</summary>

**B.** AMI names aren't globally unique across AWS accounts — without
restricting `owners`, a `name` filter pattern could theoretically match
images published by unrelated accounts. Scoping to a trusted owner (like
`"amazon"` for AWS-published images) keeps the match meaningful.

</details>

---

**Q10. (Multiple Choice)** A configuration made entirely of `data`
blocks is applied. What does `Resources: 0 added, 0 changed, 0
destroyed` mean?

- A) The apply failed
- B) This is expected — reads don't count toward the resource tally, even though the data was successfully read
- C) No data sources were actually read
- D) All data sources returned empty results

<details>
<summary>Answer</summary()>

**B.** The apply succeeds and the data is genuinely read (visible in
the "Reading.../Read complete" log lines) — it just never counts as
added, changed, or destroyed, since those three counters track only
lifecycle-managed `resource` blocks.

</details>

---

**Q11. (Multiple Choice)** What is the simplest test for deciding
whether something belongs in a `data` block or a `resource` block?

- A) Whether it costs money
- B) Whether removing the Terraform block would destroy the real thing
- C) Whether AWS or Terraform created it originally
- D) Whether it's referenced by other resources

<details>
<summary>Answer</summary()>

**B.** If deleting the code should NOT delete the real thing, it's
`data`. If it should, it's `resource`. Cost (A), original creator (C),
and whether other resources reference it (D) are all unrelated to this
decision.

</details>

---

**Q12. (Multiple Choice)** Beyond avoiding a hardcoded ARN string, what
practical capability does `data.aws_iam_policy` give you that a
hardcoded ARN alone doesn't?

- A) The ability to modify the policy
- B) Access to the policy's actual JSON document via `.policy`, for inspecting or referencing specific statements
- C) Automatic versioning of the policy
- D) The ability to attach the policy without any IAM permissions

<details>
<summary>Answer</summary()>

**B.** `.policy` returns the actual JSON policy document as a string —
useful if you need to inspect or extract details from it. A hardcoded
ARN gives you a string to attach elsewhere, but no visibility into the
policy's actual content. `data` sources never grant modification
ability (A) — that would require a `resource`, and AWS-managed
policies can't be edited regardless.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 11-12/12 | Import Anki cards, move to Demo 09 |
| 9-10/12 | Review the wrong answers, then proceed |
| 7-8/12 | Re-read the relevant sections, retry those questions |
| Below 7/12 | Re-read the full demo and redo the walkthrough before proceeding |
````