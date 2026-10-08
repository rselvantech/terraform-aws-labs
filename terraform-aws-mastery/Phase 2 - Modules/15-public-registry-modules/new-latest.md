# Demo 15 — Public Registry Modules

---

## Overview

Demo 14 built CloudNova's first *local* module — code the platform
team wrote and owns. But CloudNova doesn't need to hand-roll
everything: for something as common as "an S3 bucket with sane
defaults," a huge, actively-maintained, community-vetted module
already exists on the **Terraform Registry**. This demo pulls one in —
`terraform-aws-modules/s3-bucket/aws` — instead of writing the
underlying `aws_s3_bucket` resources by hand the way Demo 01 did.

**Real-world scenario — CloudNova:** the platform team doesn't want to
maintain their own S3-bucket module the way they now maintain the
`sns-topic` module from Demo 14 — S3 bucket configuration (versioning,
encryption, public access blocking, lifecycle rules...) is exactly the
kind of thing hundreds of other companies have already solved, tested,
and hardened. Rather than reinventing it, this demo calls the
published `terraform-aws-modules/s3-bucket/aws` module directly,
pinned to a version constraint — the same bucket-creation job Demo 01
did by hand, now delegated to someone else's maintained code.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Calling a Registry Module                                     │
│  module "demo_bucket" { source = "terraform-aws-modules/s3-bucket/aws"  │
│  version = "~> 5.0" ... } — a third-party module, not one we wrote      │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Version Constraints in Practice                               │
│  terraform init resolving "~> 5.0" to a real matching release; where    │
│  that resolution is (and isn't) recorded                                │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Verifying Against Demo 01's Hand-Written Bucket                │
│  module.demo_bucket.s3_bucket_arn read at root, Console check,          │
│  contrasted against Demo 01's manually-written resource                 │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- Sourcing a module from the Terraform Registry:
  `source = "<namespace>/<name>/<provider>"`
- Version constraints on a module call (`version = "~> 5.0"`, and how
  that differs from an unconstrained call)
- What `terraform init` actually resolves a version constraint to, and
  where that resolution is (and is **not**) recorded
- Reading a registry module's own documented inputs/outputs, rather
  than assuming them
- `terraform-aws-modules/s3-bucket/aws` — specific inputs used:
  `bucket`, `versioning`, `force_destroy`, `tags`; specific outputs
  used: `s3_bucket_id`, `s3_bucket_arn`

**What this demo does NOT cover:** the dozens of other features this
particular module supports (lifecycle rules, replication, logging,
website hosting, etc.) — only enough of its surface to demonstrate
registry sourcing and version pinning, the two objectives this demo
actually targets.

---

## How This Demo's Pieces Fit Together

**The AWS solution:** one S3 bucket, created entirely by a third-party
registry module instead of a hand-written `aws_s3_bucket` resource —
directly comparable to the bucket Demo 01 built by hand.

- Root's `main.tf` calls `terraform-aws-modules/s3-bucket/aws`,
  version-constrained with `~> 5.0`, passing `bucket`, `versioning`,
  `force_destroy`, and `tags` — four of this module's many documented
  inputs, chosen because they map directly onto what Demo 01's
  hand-written bucket already did.
- Internally, this module creates far more than Demo 01's bucket did
  (ownership controls, public access block, and more) — none of that
  is authored by CloudNova; it's the module's own internal
  implementation, entirely opaque to this configuration except through
  its documented inputs and outputs.
- Root's `outputs.tf` reads `module.demo_bucket.s3_bucket_arn` —
  same reference mechanism as Demo 14's `module.alerts.topic_arn`, just
  pointed at a module CloudNova doesn't own or maintain.
- The version constraint (`~> 5.0`) is resolved once by `terraform
  init`, and that specific resolved version is what every subsequent
  `plan`/`apply` in this working directory uses, until `init -upgrade`
  is run again.

---

## Prerequisites

### Knowledge
- Demo 14 completed — module calling mechanics
  (`module` block, `source`, `module.<name>.<output>`)
- Demo 01 completed — the hand-written `aws_s3_bucket` resource this
  demo will be contrasted against

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | `>= 1.15.0` (pinned `~> 1.15.0` in this demo) | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version` |

> This module's own stated minimum is looser — `terraform >= 1.5.7`,
> `aws provider >= 6.42` — but this demo pins to the series' usual
> narrower constraints, which comfortably satisfy that minimum.

### Verify AWS Account and Permissions

**Step 1 — Confirm your profile works:**

```bash
aws sts get-caller-identity --profile default --region us-east-2
```

**Step 2 — A cheap, harmless dry-run of this demo's actual service:**

```bash
aws s3api list-buckets --profile default --region us-east-2
# Expected: JSON with a Buckets array (may be empty — that is fine)
# If you see AccessDenied: fix IAM permissions before proceeding,
# not after you're mid-lab
```

**Step 3 — Verify IAM permissions in Console:**

```
Console → IAM → Users → test → Permissions tab
  → Confirm AmazonS3FullAccess (or equivalent) is attached ✅
```

**Required permissions for this demo:**

```
s3:CreateBucket, s3:DeleteBucket, s3:GetBucketVersioning, s3:PutBucketVersioning
s3:GetBucketOwnershipControls, s3:PutBucketOwnershipControls
s3:GetBucketPublicAccessBlock, s3:PutBucketPublicAccessBlock
s3:PutBucketTagging, s3:ListBucket
```

> The registry module creates a few more S3-related resources under
> the hood than Demo 01's bucket did — ownership controls and a public
> access block, specifically — hence the wider permission list above
> compared to Demo 01's.

### Versions used in this demo

| Tool / Module | Version |
|---|---|
| Terraform | `~> 1.15.0` (module's own stated minimum is looser: `>= 1.5.7`) |
| AWS Provider | `~> 6.47.0` (module's own stated minimum is looser: `>= 6.42`) |
| `terraform-aws-modules/s3-bucket/aws` | `~> 5.0` |
| AWS CLI | `>= 2.x` |

> **Versions pinned as of September 2026.** The Terraform CLI and AWS
> provider pins are dated the same way as every other demo in this
> series — check each project's own changelog before assuming these
> exact patch levels are still current if you're reading this well
> after that date; the `~>` constraints themselves don't need to
> change.

> ⚠️ [VERIFY — exact patch-level version]: the module's exact latest
> release tag wasn't confirmable through available tooling at
> authoring time (GitHub's Releases UI requires JavaScript). The
> constraint above (`~> 5.0`) is grounded in the module's actual
> published requirements (fetched from its live `master` README), but
> the specific version Terraform resolves this to may differ from
> whatever exact patch is newest by the time you run this. Run
> `terraform init` yourself and check `.terraform/modules/modules.json`
> for the exact resolved version in your own environment.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Source a module from the Terraform Registry using
   `source = "<namespace>/<name>/<provider>"`
2. ✅ Apply a version constraint to a registry module call, and explain
   what `~>` actually permits versus an exact pin
3. ✅ Explain what `terraform init` resolves a version constraint to,
   and where that resolution is (and is not) recorded
4. ✅ Read and apply a registry module's actual documented inputs and
   outputs, rather than assuming them from a similar module
5. ✅ Build and verify a real AWS S3 bucket entirely through a registry
   module call, and contrast it against a hand-written equivalent

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| S3 Bucket (×1, via registry module) | 5 GB Standard storage free (12-month free tier) | **$0.00** | Same free tier as Demo 01's bucket — this module doesn't change S3's own pricing |
| **Session total** | | **$0.00** | |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
15-public-registry-modules/
├── README.md
├── 15-public-registry-modules-anki.csv
├── 15-public-registry-modules-quiz.md
└── src/
    ├── versions.tf      # terraform block + provider version constraints
    ├── provider.tf       # AWS provider: region, profile
    ├── variables.tf      # root-level inputs: bucket name
    ├── main.tf            # module "demo_bucket" block — calls the registry module
    ├── outputs.tf         # root outputs re-exposing s3_bucket_id / s3_bucket_arn
    └── break-fix/
        └── broken.tf         # root config with 3 deliberate registry-module errors
```

> **No nested module directory this time.** Unlike Demo 14's local
> module, there's no local callee directory to manage or collide with
> — the registry module lives entirely outside this repository, so
> `break-fix/broken.tf` is a single self-contained file, same as every
> pre-Demo-14 break-fix in this series.

---

## Recall Check — Demo 14

Answer from memory before reading further:

1. A module's `variable` block has no `default`, and the calling
   `module` block never sets it. What happens?
2. Can you reference a resource that exists inside a module directly
   from root — e.g. `module.alerts.aws_sns_topic.this.arn`? Why or why
   not?
3. What does the local name in `module "alerts" { ... }` actually
   refer to, and can two calls to the same module coexist under
   different local names?

<details>
<summary>Answers</summary>

1. Terraform errors at `plan`/`apply` with a "Missing required
   argument" message naming the missing variable — there is no silent
   fallback to some default.
2. No — modules aren't transparent. Only what the module explicitly
   exposes through its own `output` blocks is reachable from outside
   it, even though the resource genuinely exists inside the module.
3. The local name is a label chosen entirely at the call site, unrelated
   to the module's directory name or anything declared inside it. Yes
   — two calls to the same module under different local names produce
   two independent sets of resources, addressed separately
   (`module.a.*` vs `module.b.*`), with no collision.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `source = "<namespace>/<name>/<provider>"` | Registry module source format | Points at a published module on the Terraform Registry, instead of a local path |
| `version` (on a `module` block) | Version constraint argument | Restricts which published releases of the module Terraform is allowed to resolve to |
| `.terraform/modules/modules.json` | Resolution record | Where the *exact* resolved module version actually lives — not the dependency lock file |
| `bucket`, `versioning`, `force_destroy`, `tags` | This module's own documented inputs | The specific inputs this demo uses, out of the module's much larger documented surface |
| `s3_bucket_id`, `s3_bucket_arn` | This module's own documented outputs | The specific outputs this demo reads |

**Related constructs worth knowing (not covered in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| `count`/`for_each` on a `module` block | Calling the same module multiple times | Demo 17 (Three-Tier Modules) |
| The module's other ~60 inputs (lifecycle rules, replication, logging, website hosting, etc.) | This module's full documented surface | Not covered — see the module's own README for the complete list |

---

### Detailed Explanation of New Constructs

#### Registry Module Sourcing — `source = "<namespace>/<name>/<provider>"`

```hcl
module "demo_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  bucket        = var.bucket_name
  force_destroy = true

  versioning = {
    enabled = true
  }

  tags = {
    ManagedBy = "terraform-demo-15"
  }
}
```

**What it does:** a three-part `namespace/name/provider` string —
`terraform-aws-modules` (the publisher), `s3-bucket` (the module),
`aws` (the provider it's built for) — tells Terraform to resolve this
against the public Terraform Registry, rather than a filesystem path.
Everything else about calling it — the `module` block syntax, passing
arguments, reading `module.<name>.<output>` afterward — works exactly
like Demo 14's local module call. The only genuinely new things here
are the `source` format itself and the `version` argument (next).

> **Same as X" ban check — restating, not just pointing:** this is the
> same `module` block syntax Demo 14 used, but it is not the same kind
> of `source`. A local `source` (`./modules/sns-topic`) is a
> filesystem path Terraform reads directly off disk. A registry
> `source` is a lookup key Terraform resolves against a remote
> registry API — the module's actual code gets downloaded into
> `.terraform/modules/` during `init`, which never happens for a local
> module (it's already sitting right there on disk).

---

#### Version Constraints — `version = "~> 5.0"`

**What it does:** restricts which published releases of the module
Terraform is allowed to resolve to. `~> 5.0` means "the latest 5.x
release, but never 6.0 or higher" — it allows patch and minor version
increases within the major version, but blocks a breaking major-version
upgrade from happening silently underneath you.

| Constraint | Allows |
|---|---|
| `= 5.7.0` | Exactly that one release — nothing else |
| `>= 5.0.0` | That version or *any* newer one, including breaking major versions — rarely what you actually want |
| `~> 5.0` | Any `5.x` release — the most common real-world choice for exactly this reason |
| `~> 5.7.0` | Only `5.7.x` releases — narrower than `~> 5.0`, blocks even minor version bumps |

> **Omitting `version` entirely is legal, but risky.** Without a
> constraint, `terraform init` simply resolves to whatever the latest
> published release is at that moment — meaning two people running
> `init` a month apart could silently get two different major versions
> of the same module, with no warning. This is exactly why hard
> trigger 1 (external/third-party dependency) called for extra care
> when planning this demo: the module's behavior isn't something this
> series controls or can guarantee stays constant.

---

#### Where Version Resolution Actually Lives

**What it does:** once `terraform init` resolves `~> 5.0` to one
specific real release, that resolution is recorded in
`.terraform/modules/modules.json` — a file inside the `.terraform`
working directory, not meant to be committed to version control.

> **This is genuinely easy to confuse with the dependency lock file,
> and worth getting exactly right.** `.terraform.lock.hcl` — the file
> this series *has* discussed since early provider-related demos —
> records resolved **provider** versions and their checksums, and *is*
> meant to be committed. Module version resolution is a completely
> separate mechanism, tracked in a different, gitignored file. The
> `version = "~> 5.0"` constraint in your `.tf` file itself is what's
> actually committed and re-resolved (potentially to a newer matching
> release) on every fresh `init` — there's no per-module equivalent of
> the provider lock file pinning you to one exact module release
> across machines.

---

#### Reading a Registry Module's Own Documented Inputs and Outputs

**What it does:** unlike Demo 14's module (which this series wrote,
and therefore already fully understood), a registry module's inputs
and outputs have to be looked up from its own documentation — never
assumed by pattern-matching against a similar-looking module. This
demo uses exactly four of this specific module's documented inputs:

| Input | Type | What it does here |
|---|---|---|
| `bucket` | `string` | The bucket's name — same argument name and meaning as Demo 01's raw `aws_s3_bucket.bucket` |
| `versioning` | `map(string)` | A map, not a bare boolean — `{ enabled = true }` — this module's own convention for what was a nested block in the raw resource |
| `force_destroy` | `bool` | Allows a non-empty bucket to be destroyed — used here purely so Cleanup doesn't require manually emptying the bucket first |
| `tags` | `map(string)` | Same purpose as any other AWS resource's `tags` argument |

And two of its documented outputs:

| Output | What it exposes |
|---|---|
| `s3_bucket_id` | The bucket's name |
| `s3_bucket_arn` | The bucket's ARN — format `arn:aws:s3:::bucketname` |

> **This module's outputs are *not* named the way you might guess.**
> There is no `bucket_name` or `arn` output — it's `s3_bucket_id` and
> `s3_bucket_arn`, both prefixed with `s3_bucket_`. Guessing an
> output name by analogy to Demo 14's `topic_arn` (no prefix at all)
> would fail — exactly the kind of assumption this demo's Break-Fix
> scenario tests.

---

## Lab Step-by-Step Guide

---

## Part A — Calling a Registry Module

Part A calls a real, published, third-party module — no code of our
own to write for the bucket itself, only the call.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-2-modules/15-public-registry-modules/src
```

### Step 2 — Create the root scaffolding files

This step scaffolds the root configuration's provider and version
pins, plus the single root-level input variable this demo passes into
the registry module.

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

> **This demo's own pin is `~> 6.47.0`, narrower than the module's
> stated bare minimum of `>= 6.42`.** The module only requires `>=
> 6.42` — but this series pins provider versions narrowly throughout
> (per its version-pinning standard), and `6.47.0` comfortably
> satisfies the module's floor. The two aren't in tension: a module's
> stated minimum is a floor its author guarantees compatibility from,
> not a ceiling you're required to sit at.

#### `provider.tf` — AWS provider configuration

**provider.tf:**

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
```

#### `variables.tf` — Root-level inputs

This file declares the one root-level variable this demo uses — the
bucket name passed into the registry module's `bucket` input.

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

variable "bucket_name" {
  type        = string
  description = "Name passed into the registry module's bucket input"
  default     = "cloudnova-registry-demo15"
}
```

### Step 3 — Call the registry module

This step calls the registry module for the first time, passing four
of its documented inputs to recreate what Demo 01 built by hand.

Create a file **main.tf** and add the below content:

This file contains the single call to
`terraform-aws-modules/s3-bucket/aws`, version-constrained and passed
the four inputs this demo actually exercises.

```hcl
module "demo_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  bucket        = var.bucket_name
  force_destroy = true

  versioning = {
    enabled = true
  }

  tags = {
    ManagedBy = "terraform-demo-15"
  }
}
```

### Step 4 — Create the root outputs

This step exposes two of the module's documented outputs at root, so
both can be read after apply and compared against the real created
bucket.

Create a file **outputs.tf** and add the below content:

This file reads `module.demo_bucket.s3_bucket_id` and
`module.demo_bucket.s3_bucket_arn` and re-exposes both as root-level
outputs.

```hcl
output "bucket_id" {
  value       = module.demo_bucket.s3_bucket_id
  description = "Name of the bucket created via the registry module"
}

output "bucket_arn" {
  value       = module.demo_bucket.s3_bucket_arn
  description = "ARN of the bucket created via the registry module"
}
```

### Step 5 — Initialize

This step downloads the module's actual source code for the first
time and confirms initialization succeeds — something Demo 14's local
module never needed, since it was already sitting on disk.

```bash
terraform init
```

Expected — note Terraform downloading the module's actual source code,
something Demo 14's local module never needed:

```
Initializing modules...
Downloading registry.terraform.io/terraform-aws-modules/s3-bucket/aws 5.x.x for demo_bucket...
- demo_bucket in .terraform/modules/demo_bucket

Initializing the backend...
Initializing provider plugins...
Terraform has been successfully initialized!
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment. The specific `5.x.x` version shown is whatever `~> 5.0`
> resolves to in your own environment at the time you run this — see
> the ⚠️ [VERIFY] note in Prerequisites.

> **Check `.terraform/modules/modules.json` right after this step.**
> This is where the exact resolved version actually lives — open it
> and confirm the `Version` field matches what `init`'s output just
> reported.

---

## Part B — Version Constraints in Practice

Part B confirms directly, in your own environment, exactly what
version `~> 5.0` resolved to — and confirms it's genuinely absent from
the provider lock file.

### Step 6 — Inspect the resolved module version

This step confirms, in your own environment rather than by asserted
claim, exactly which real release `~> 5.0` resolved to.

```bash
cat .terraform/modules/modules.json
```

Expected — a JSON structure listing `demo_bucket`'s resolved `Source`
and `Version`:

```json
{
  "Modules": [
    { "Key": "", "Source": "" },
    { "Key": "demo_bucket", "Source": "registry.terraform.io/terraform-aws-modules/s3-bucket/aws", "Version": "5.x.x" }
  ]
}
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

### Step 7 — Confirm this file is absent from the dependency lock file

This step confirms module version resolution is genuinely absent from
the provider lock file, rather than accepting that claim on faith.

```bash
grep -c "s3-bucket" .terraform.lock.hcl
```

Expected:

```
0
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **Zero is the correct, expected result.** `.terraform.lock.hcl` only
> ever tracks *provider* checksums (you'll see `hashicorp/aws` in
> there, not `terraform-aws-modules/s3-bucket`) — confirming, in your
> own environment rather than by asserted claim alone, that module
> version resolution really does live somewhere else entirely.

---

## Part C — Verifying Against Demo 01's Hand-Written Bucket

Part C applies the module, confirms its outputs against the real
created bucket, and contrasts it directly against Demo 01's
hand-written equivalent.

### Step 8 — Apply

This step applies the module for real, creating every AWS resource
its internal implementation decides to create — not just the one
resource its four lines of input might suggest.

```bash
terraform validate
terraform apply
```

Expected — note `module.demo_bucket.` prefixing every resource this
module creates internally, several more than Demo 01's single
`aws_s3_bucket` resource:

```
module.demo_bucket.aws_s3_bucket.this[0]: Creating...
module.demo_bucket.aws_s3_bucket.this[0]: Creation complete after 2s
module.demo_bucket.aws_s3_bucket_versioning.this[0]: Creating...
module.demo_bucket.aws_s3_bucket_versioning.this[0]: Creation complete after 1s
module.demo_bucket.aws_s3_bucket_ownership_controls.this[0]: Creating...
module.demo_bucket.aws_s3_bucket_ownership_controls.this[0]: Creation complete after 1s
module.demo_bucket.aws_s3_bucket_public_access_block.this[0]: Creating...
module.demo_bucket.aws_s3_bucket_public_access_block.this[0]: Creation complete after 1s

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

bucket_arn = "arn:aws:s3:::cloudnova-registry-demo15"
bucket_id  = "cloudnova-registry-demo15"
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **Four resources, from four lines of module input.** Demo 01 wrote
> one `aws_s3_bucket` resource by hand and got exactly one resource.
> This module's own internal implementation created ownership controls
> and a public access block that CloudNova never had to think about —
> that's the actual value being delegated here, not just fewer lines of
> code.

### Step 9 — Verify in the Console

This step confirms the module's resources are real in AWS and
contrasts them directly against what Demo 01's hand-written bucket
looked like.

```
Console → S3 → Buckets → cloudnova-registry-demo15
  → Bucket exists, ARN matches `terraform output bucket_arn` exactly ✅
  → Properties tab → Bucket Versioning → "Enabled" ✅
  → Permissions tab → Object Ownership → confirm it shows "Bucket
    owner enforced" — ⚠️ [VERIFY: not confirmed in this session
    whether this is this module's own default or AWS's own
    account-level default in effect since 2023; Demo 01 never set
    this explicitly either way, so the two buckets aren't a clean
    before/after comparison on this specific point]
```

> 📷 [Screenshot placeholder: AWS Console → S3 → Buckets →
> cloudnova-registry-demo15, Permissions tab showing the Object
> Ownership setting]

---

## Cleanup

### Step 10 — Destroy all resources

```bash
terraform destroy
```

Type `yes`. Expected:

```
module.demo_bucket.aws_s3_bucket_public_access_block.this[0]: Destroying...
module.demo_bucket.aws_s3_bucket_public_access_block.this[0]: Destruction complete after 1s
module.demo_bucket.aws_s3_bucket_ownership_controls.this[0]: Destroying...
module.demo_bucket.aws_s3_bucket_ownership_controls.this[0]: Destruction complete after 1s
module.demo_bucket.aws_s3_bucket_versioning.this[0]: Destroying...
module.demo_bucket.aws_s3_bucket_versioning.this[0]: Destruction complete after 1s
module.demo_bucket.aws_s3_bucket.this[0]: Destroying...
module.demo_bucket.aws_s3_bucket.this[0]: Destruction complete after 1s

Destroy complete! Resources: 4 destroyed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

### Step 11 — Confirm the bucket is gone

```bash
aws s3api head-bucket --bucket cloudnova-registry-demo15 --profile default --region us-east-2
```

Expected: an error confirming the bucket no longer exists (e.g. `Not
Found`), not a successful response.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## What You Learned

1. ✅ A registry module's `source` is a `namespace/name/provider`
   string, resolved against the Terraform Registry — not a filesystem
   path
2. ✅ `version = "~> 5.0"` restricts resolution to the latest matching
   `5.x` release, blocking a silent breaking major-version upgrade
3. ✅ Module version resolution is recorded in
   `.terraform/modules/modules.json` — **not** in
   `.terraform.lock.hcl`, which only ever tracks provider checksums
4. ✅ A registry module's inputs and outputs must be read from its own
   documentation — never assumed by analogy to a different module's
   naming conventions
5. ✅ A registry module can create substantially more than its call
   site implies — this module's four lines of input produced four
   actual AWS resources, not one

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `source = "<namespace>/<name>/<provider>"` | TA-004 Obj 5a | Core "how Terraform sources modules" objective — registry form specifically |
| `version = "~> 5.0"` on a module block | TA-004 Obj 5d | Core "manage module versions" objective |
| Module version resolution location (`modules.json`, not the lock file) | TA-004 Obj 5d | Frequently confused with provider version locking — expect this exact distinction to be tested |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam shows a module call with no `version` argument at all | Recognizing this resolves to whatever the latest published release is *at that moment* — not a fixed, safe default | Assuming an omitted `version` behaves like an implicit "latest stable, pinned" constraint |
| Exam asks where a module's resolved version is recorded | Recognizing `.terraform/modules/modules.json`, not `.terraform.lock.hcl` | Assuming module versions are locked the same way provider versions are |
| Exam shows `version = "~> 5.0"` and asks whether `6.1.0` would be accepted | Recognizing `~>` on a two-part version blocks the next major version entirely | Assuming `~>` always just means "greater than or equal to" |

### Exam Task — Write a complete configuration

**Task:** CloudNova's billing team wants a standardized way to create
IAM roles instead of hand-writing trust policies every time. Source
the `terraform-aws-modules/iam/aws` (or a comparable published)
module, pin it to a version constraint, and call it with at least one
real input.

**Block types required:** `module` (×1), `variable` (×1, at root, for
the role name)

**Official documentation:**
- [Modules — Module Sources](https://developer.hashicorp.com/terraform/language/modules/sources)
- [Terraform Registry](https://registry.terraform.io)

**What to practise:**
1. Find the module's actual current inputs on its Registry page —
   don't guess by analogy to this demo's S3 module
2. Write the `module` block from scratch, including a version
   constraint
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
variable "role_name" {
  type    = string
  default = "cloudnova-billing-role"
}

module "iam_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "~> 5.0"

  role_name = var.role_name

  trusted_role_services = ["ec2.amazonaws.com"]
}
```

**Arguments you must know without looking up:**
- The registry `source` format is always
  `<namespace>/<name>/<provider>`, optionally followed by
  `//<subdirectory>` for a submodule within a larger repository
- A missing `version` argument resolves to the latest published
  release at `init` time — not a fixed default

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Failed to query available provider packages` mentioning the module's required AWS provider version | The configured provider version constraint doesn't satisfy the module's own stated minimum (`>= 6.42`) | Loosen or update the `required_providers` constraint in `versions.tf` |
| `Unsupported attribute` on `module.demo_bucket.<output>` | Referencing an output name this module doesn't actually expose (guessed by analogy rather than checked) | Check the module's own Registry "Outputs" tab for the exact name — this module uses `s3_bucket_id`/`s3_bucket_arn`, not `bucket_id`/`bucket_arn` |
| `No available releases match the given constraints` | The `version` constraint doesn't match any published release (e.g. a typo, or a version that doesn't exist) | Check the module's Registry page for actual published version numbers |

---

## Break-Fix Scenario

Three deliberate errors calling the registry module. Unlike Demo 14,
there's no local callee to manage — this is a single self-contained
file.

```bash
cd src/break-fix/
terraform init
```

> **Fix errors one at a time and re-run**, same iterative pattern as
> Demo 13 and Demo 14's Break-Fix scenarios.

#### `broken.tf` — Three deliberate errors

This file is a self-contained root configuration calling the real
registry module, with an invalid version constraint, a source typo,
and a wrong output reference — diagnose all three.

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

module "demo_bucket" {
  source  = "terraform-aws-modules/s3-buckets/aws" # Error 1: source typo (extra "s")
  version = "~> 99.0"                                # Error 2: no published release in this range

  bucket        = "cloudnova-broken-demo15"
  force_destroy = true
}

output "bucket_arn" {
  value = module.demo_bucket.bucket_arn # Error 3: wrong output name (should be s3_bucket_arn)
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — source typo (`s3-buckets` instead of `s3-bucket`)**
`terraform-aws-modules/s3-buckets/aws` doesn't exist on the Registry —
`init` fails with a "module not found"-class error. Fix: correct the
path to `terraform-aws-modules/s3-bucket/aws`.

**Error 2 — version constraint matches no published release**
`~> 99.0` doesn't match anything this module has ever published —
`init` fails with "No available releases match the given constraints."
Fix: use a real constraint like `~> 5.0`.

**Error 3 — wrong output name (`bucket_arn` instead of `s3_bucket_arn`)**
This module's actual output is `s3_bucket_arn` — there is no bare
`bucket_arn`. Reported as an "Unsupported attribute" error once the
first two errors are fixed and `init` succeeds. Fix: reference
`module.demo_bucket.s3_bucket_arn` instead.

> ⚠️ [VERIFY — behavioral claim, docs-reasoning only, not a live run in
> this environment]: whether Errors 1 and 2 are reported together in a
> single `init` attempt, or whether one masks the other, isn't
> confirmed here — re-run `init` after each individual fix rather than
> assuming both are visible in the same pass.

</details>

**Cleanup:**
```bash
cd src/break-fix/
terraform destroy -auto-approve
rm -f terraform.tfstate terraform.tfstate.backup
cd ../..
```

---

## Interview Prep

**Q1. A teammate says "we don't need a version constraint, Terraform
will just use the latest version, which is what we want anyway." How
would you respond?**
That's true only at the moment `init` first runs — the risk is that
"latest" isn't a fixed thing. Six months later, a fresh `init` on the
same unconstrained configuration could resolve to a completely
different major version, potentially with breaking changes, with zero
warning that anything changed. A `~>` constraint doesn't prevent
updates — it just prevents a breaking major-version jump from
happening silently underneath an existing configuration.

**Q2. Where would you look to find out exactly which version of a
registry module Terraform actually resolved to in a given working
directory?**
`.terraform/modules/modules.json` — not `.terraform.lock.hcl`. The
lock file only ever tracks provider versions and checksums; module
version resolution is a separate, gitignored record inside the
`.terraform` working directory, re-derived on each `init` rather than
committed alongside the configuration.

**Q3. Why did calling this module create four AWS resources instead of
the one resource Demo 01 wrote by hand for essentially "the same
bucket"?**
Because the module's own internal implementation does more than the
bare minimum — it also manages ownership controls and a public access
block as separate resources, based on its own defaults, entirely
independent of what CloudNova explicitly asked for. That's the actual
trade being made by using a registry module: less code to write and
maintain, in exchange for accepting whatever the module's author
decided a sane default configuration looks like.

---

## Key Takeaways

1. **A registry module's `source` is `namespace/name/provider`,
   resolved against the Terraform Registry** — not a filesystem path,
   and its actual code gets downloaded during `init`, unlike a local
   module.

2. **A `version` constraint on a module block prevents a silent
   breaking upgrade**, but doesn't fully pin you to one exact release
   — `~> 5.0` still allows any matching `5.x` release to resolve.

3. **Module version resolution lives in
   `.terraform/modules/modules.json`, never in
   `.terraform.lock.hcl`** — the lock file exists exclusively for
   provider versions and checksums.

4. **A registry module's inputs and outputs must be read from its own
   documentation, never guessed by analogy** — this module's outputs
   are prefixed `s3_bucket_`, unlike Demo 14's unprefixed `topic_arn`.

> **Demo scope:** Primary concept: sourcing and version-constraining a
> Terraform Registry module. Supporting concepts: where module version
> resolution is recorded, reading a third-party module's documented
> inputs/outputs.
> Estimated completion time: 30–35 minutes.
> Checkpoints: 3 natural stopping points (end of Part A, end of
> Part B, end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform init` | Downloads a registry module's actual source code, in addition to its usual provider-plugin role |
| `cat .terraform/modules/modules.json` | Shows exactly which version a module's constraint resolved to |
| `grep <module-name> .terraform.lock.hcl` | Confirms (by finding nothing) that module versions are never recorded in the provider lock file |

---

## Next Demo

**Demo 16 — VPC Module.** Builds on both Demo 14's local-module
mechanics and this demo's registry-sourcing mechanics — calling
`terraform-aws-modules/vpc/aws`, by far the largest third-party module
surface this series has touched so far.

---

## Appendix — Anki Cards

**15-public-registry-modules-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 2 - Modules::15-public-registry-modules
#separator:Comma
#columns:Front,Back,Tags
"What format does a Terraform Registry module's source argument take?","namespace/name/provider — e.g. terraform-aws-modules/s3-bucket/aws — resolved against the Terraform Registry, unlike a local path which starts with ./ or ../","demo15,modules,registry,ta004-obj5a"
"What does a module version constraint like \"~> 5.0\" actually allow?","Any 5.x release (patch and minor version increases), but blocks resolution to 6.0 or higher — preventing a silent breaking major-version upgrade.","demo15,modules,versioning,ta004-obj5d"
"What happens if a module block has no version argument at all?","Terraform resolves to whatever the latest published release is at that init, with no constraint at all — risky, since a later init could silently resolve to a different major version.","demo15,modules,versioning,ta004-obj5d"
"Where is a resolved module version actually recorded?",".terraform/modules/modules.json — not .terraform.lock.hcl, which only ever tracks provider versions and checksums.","demo15,modules,versioning,gotcha,ta004-obj5d"
"Does .terraform.lock.hcl track module versions the same way it tracks provider versions?","No — the dependency lock file exists exclusively for providers. Module version resolution is a completely separate, gitignored record.","demo15,modules,gotcha,ta004-obj5d"
"Should you assume a registry module's output names by analogy to a similar module you've used before?","No — always check the specific module's own documented outputs. This demo's module uses s3_bucket_arn, not bucket_arn or arn, despite Demo 14's own module using an unprefixed topic_arn.","demo15,modules,registry,gotcha"
"Can calling a registry module create more AWS resources than the inputs you passed would suggest?","Yes — a module's own internal implementation can create additional resources based on its own defaults, entirely independent of what was explicitly requested at the call site.","demo15,modules,registry"
"What's the difference between version = \"= 5.7.0\" and version = \"~> 5.0\" on a module block?","= 5.7.0 pins to exactly that one release. ~> 5.0 allows any 5.x release, blocking only a major-version jump to 6.0+.","demo15,modules,versioning,ta004-obj5d"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** the Anki deck drills the atomic facts.
> This Quiz targets the scenario-application layer instead — reading
> real `init` output, diagnosing Break-Fix-style errors, and telling
> apart genuinely similar-looking version constraints — rather than
> restating "what does `~>` mean" a second time in a different format.

**15-public-registry-modules-quiz.md:**

````markdown
# Quiz — Demo 15: Public Registry Modules

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 16.

---

**Q1. (Multiple Choice)** You run `terraform init` and see:
`Downloading registry.terraform.io/terraform-aws-modules/s3-bucket/aws
5.4.0 for demo_bucket...` even though your `.tf` file says
`version = "~> 5.0"`. Is this expected?

- A) No — `~> 5.0` should resolve to exactly `5.0.0`, never a later patch
- B) Yes — `~> 5.0` allows any `5.x` release, and `5.4.0` is a valid match
- C) No — this means the constraint was ignored
- D) Yes, but only because no `version` was actually set

<details>
<summary>Answer</summary>

**B.** `~> 5.0` allows any `5.x` release (patch and minor drift),
blocking only a jump to `6.0+`. Resolving to `5.4.0` is exactly the
intended, expected behavior — not evidence of anything being ignored.

</details>

---

**Q2. (Multiple Choice)** This demo pins the AWS provider to
`~> 6.47.0`, while the `terraform-aws-modules/s3-bucket/aws` module's
own stated minimum is `>= 6.42`. What does that relationship actually
mean?

- A) The provider pin conflicts with the module's minimum — this demo's version choice is a mistake
- B) The demo's pin comfortably satisfies the module's floor — a module's stated minimum is a floor its author guarantees compatibility from, not a ceiling the caller is required to sit at
- C) The module refuses to run unless the provider is pinned to exactly `6.42`
- D) The narrower demo pin overrides and locks the module into a `6.42`-only compatibility mode

<details>
<summary>Answer</summary>

**B.** A module's stated minimum version is the floor its author has
tested and guarantees compatibility from — any provider version at or
above that floor works, including a narrower, more specific pin like
this demo's `~> 6.47.0`. There's no conflict and no forced ceiling in
either direction.

</details>

---

**Q3. (Multiple Choice)** Break-Fix's `broken.tf` sets
`version = "~> 99.0"`. What actually happens when you run
`terraform init`?

- A) Terraform silently falls back to the latest real release instead
- B) `init` fails with "No available releases match the given constraints"
- C) `init` succeeds, but `apply` fails instead
- D) Terraform creates a placeholder module with no resources

<details>
<summary>Answer</summary>

**B.** A constraint that matches no published release fails at
`init` itself — there's no silent fallback to a real version, and it
never gets as far as `plan`/`apply`.

</details>

---

**Q4. (Multiple Choice)** You need to confirm exactly which module
version your last `terraform init` actually resolved to, in your own
working directory. Which command shows you that?

- A) `cat .terraform.lock.hcl`
- B) `terraform state list`
- C) `cat .terraform/modules/modules.json`
- D) `terraform output`

<details>
<summary>Answer</summary>

**C.** This is the file that records the actual resolved module
version. **A** only ever contains provider version/checksum data —
grepping it for a module name correctly returns nothing, as this
demo's Part B specifically demonstrates.

</details>

---

**Q5. (Multiple Choice)** In Break-Fix, after fixing the `source` typo
and the invalid `version`, `output "bucket_arn"` still fails with
`Unsupported attribute`. Why?

- A) The module needs to be re-initialized a second time
- B) `module.demo_bucket.bucket_arn` doesn't exist — the module's real output is `s3_bucket_arn`
- C) Outputs can't be read until `apply` has run at least twice
- D) `bucket_arn` is a reserved word and can't be used as an output name

<details>
<summary>Answer</summary>

**B.** This module's actual outputs are prefixed `s3_bucket_` — there
is no bare `bucket_arn`. This is the exact "don't assume a registry
module's naming by analogy" gotcha the demo's Concepts section warns
about.

</details>

---

**Q6. (Multiple Choice)** This demo passes `force_destroy = true` to
the module even though the bucket is empty at creation time. Why?

- A) It's a required argument for any bucket this module creates
- B) It's set purely so Cleanup can destroy the bucket without needing to manually empty it first, in case objects were added during the lab
- C) It disables versioning automatically
- D) It's the module's own default regardless of what the caller sets

<details>
<summary>Answer</summary>

**B.** `force_destroy` exists specifically so a non-empty bucket can
still be torn down without a manual empty-bucket step first. It's set
here purely as a Cleanup convenience for this lab, not because the
module requires it or because it interacts with versioning at all.

</details>

---

**Q7. (Multiple Answer — Pick the 2 correct responses)** `terraform
apply` reports "Resources: 4 added" for a module call that only set
`bucket`, `force_destroy`, `versioning`, and `tags`. Which TWO
statements correctly explain this?

- A) The module's internal implementation creates additional resources (ownership controls, public access block) based on its own defaults
- B) Terraform always creates one resource per input argument passed to a module
- C) The four inputs map one-to-one to the four resources created
- D) A registry module's actual resource count is independent of how many inputs you happened to pass

<details>
<summary>Answer</summary>

**A and D.** The module creates whatever its own internal
implementation decides to, driven by its own defaults — not by a
count of the arguments you passed. **B** and **C** both describe a
one-to-one relationship that doesn't exist.

</details>

---

**Q8. (Multiple Choice)** A teammate wants to guarantee that a future
`terraform init` in CI never silently resolves to a different module
version than what was tested locally. Which single change to the
`module` block accomplishes that most precisely?

- A) Remove the `version` argument entirely
- B) Change `version = "~> 5.0"` to an exact pin, e.g. `version = "5.4.0"`
- C) Add `version = ">= 5.0.0"`
- D) Nothing changes this — module versions can never be exactly pinned

<details>
<summary>Answer</summary>

**B.** An exact pin (`= 5.4.0`, or the bare version string, which
Terraform treats as exact) is the only constraint form that allows
zero drift. **A** and **C** both allow *more* drift, not less — the
opposite of the goal.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 7-8/8 | Import Anki cards, move to Demo 16 |
| 6/8 | Review the wrong answers, then proceed |
| 4-5/8 | Re-read the relevant sections, retry those questions |
| Below 4/8 | Re-read the full demo and redo the walkthrough before proceeding |
````