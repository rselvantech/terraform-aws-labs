# Demo 04 — State Management and Backends: Import, Surgery, and Recovery

---

## Overview

In Demos 01–03 you treated `terraform.tfstate` as something Terraform
manages for you — you never opened it, edited it, or needed to reason
about its internal structure. That changes in this demo. CloudNova has
hit two situations that require understanding state directly:

**Real-world scenario — CloudNova:**
First, an old S3 bucket — `cloudnova-legacy-uploads` — was created
manually in the Console over a year ago, months before the team adopted
Terraform. It's still in active use; recreating it would mean a new
bucket name, lost object history, and a migration nobody wants to do.
The team needs this bucket under Terraform management *as it currently
exists*, without destroying and recreating it.

Second, a teammate wants to rename a resource in `main.tf` from
`aws_s3_bucket.app` to `aws_s3_bucket.uploads` for clarity — but a plain
rename in code makes Terraform think the old resource was deleted and a
new one needs to be created, which would destroy and recreate the real
bucket. There's a way to tell Terraform "this is the same resource, just
renamed" without touching AWS at all.

Third, the team needs a documented recovery procedure for the day state
becomes corrupted or two applies conflict — before that day arrives
during a production incident.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — State File Anatomy                                            │
│  terraform.tfstate JSON structure: resources, serial, lineage, outputs  │
│  terraform show -json   |   what NOT to put in version control          │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — State Surgery: import, mv, rm                                 │
│  Manually-created S3 bucket → terraform import → import {} block        │
│  terraform state mv (rename without recreate)                           │
│  terraform state rm (untrack without destroying)                        │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Recovery from Corruption and Conflicts                        │
│  Simulate a state/reality mismatch → restore from S3 versioning         │
│  terraform force-unlock in a recovery context                           │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- The internal JSON structure of `terraform.tfstate`: `resources`,
  `serial`, `lineage`, `outputs`, dependency tracking
- `terraform show -json` for machine-readable state output
- Why state must never be committed to Git or shared insecurely
- `terraform import` (CLI form) and `import {}` blocks (declarative form)
- `terraform state mv` — renaming/moving a resource address without
  destroy/recreate
- `terraform state rm` — removing a resource from state without
  destroying it in AWS
- Restoring a previous state version from S3 bucket versioning
- `terraform force-unlock` in a real recovery scenario

---

## Prerequisites

### Knowledge
- Demo 01, 02, and 03 completed — remote S3 backend with locking,
  provider configuration, `terraform state list/show`, drift detection,
  `-target`, `terraform graph`, `TF_LOG`
- Comfortable running `terraform init / plan / apply / destroy`

### Required Tools

| Tool | Minimum version | Install | Verify |
|---|---|---|---|
| Terraform CLI | `>= 1.15.0` | [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install) | `terraform version` |
| AWS CLI | `>= 2.x` | [docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | `aws --version` |
| `jq` | Any recent | `apt install jq` / `brew install jq` | `jq --version` |
| Git | Any recent | Pre-installed on most systems | `git --version` |

> **New in this demo:** `jq` — a command-line JSON processor. Used to
> inspect `terraform.tfstate` and `terraform show -json` output without
> manually scrolling through raw JSON.

### Verify AWS Account and Permissions

```bash
aws sts get-caller-identity --profile default
aws configure get region --profile default
```

**Required permissions for this demo:**

```
s3:CreateBucket, s3:DeleteBucket, s3:ListBucket, s3:GetBucketLocation
s3:GetBucketVersioning, s3:PutBucketVersioning
s3:GetEncryptionConfiguration, s3:PutEncryptionConfiguration
s3:GetBucketPublicAccessBlock, s3:PutBucketPublicAccessBlock
s3:GetObject, s3:PutObject, s3:DeleteObject
```

> For a learning account, `AmazonS3FullAccess` managed policy covers all
> of the above.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain the structure of `terraform.tfstate` — `resources`,
   `serial`, `lineage`, and `outputs` — and what each field means
2. ✅ Use `terraform show -json` to inspect state in machine-readable form
3. ✅ Explain why `terraform.tfstate` must never be committed to Git
4. ✅ Import a manually-created AWS resource into Terraform management
   using both `terraform import` (CLI) and an `import {}` block
5. ✅ Use `terraform state mv` to rename a resource address without
   destroying and recreating the underlying infrastructure
6. ✅ Use `terraform state rm` to remove a resource from state without
   destroying it in AWS, and explain the risk of doing so
7. ✅ Restore a previous state file version from S3 bucket versioning
8. ✅ Use `terraform force-unlock` correctly in a real recovery scenario


---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| S3 bucket (legacy, imported) | 5GB / 2,000 PUT / 20,000 GET per month | **$0.00** | No objects stored in this demo |
| S3 API calls | Within free tier | **<$0.001** | |
| State bucket (existing from Demo 01 pattern) | Covered by free tier | **$0.00** | |
| **Session total** | | **~$0.00** | |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
04-state-management/
├── README.md
├── 04-state-management-anki.csv   # Anki flash cards
├── 04-state-management-quiz.md    # Quiz
└── src/
    ├── 01-versions.tf     # terraform block + provider version constraints
    ├── 02-provider.tf     # AWS provider: region, profile, default_tags
    ├── 03-backend.tf      # S3 remote backend (from Demo 01 pattern)
    ├── 04-variables.tf    # input variables
    ├── 05-locals.tf       # computed names + common tags
    ├── 06-main.tf         # imported S3 bucket + config resources
    └── 07-outputs.tf      # bucket name, ARN, region
```

---

## Recall Check — Demo 03

Answer from memory before reading anything new:

1. What is the difference between `terraform plan` (default) and
   `terraform plan -refresh-only` in terms of what each shows?
2. Why does `terraform graph` sometimes NOT show a direct edge between
   two resources, even when one resource's arguments clearly reference
   the other?
3. After a `terraform apply -target=ADDR` completes successfully, what
   should you do immediately afterward, and why?

<details>
<summary>Answers</summary>

1. Plain `terraform plan` refreshes state from AWS and then shows the
   combined difference between real infrastructure and your `.tf`
   configuration — drift and pending configuration changes are merged
   into one undifferentiated diff. `terraform plan -refresh-only` shows
   **only** drift (changes made outside Terraform), explicitly labeled,
   and proposes no remediation — pending configuration changes are not
   shown at all in this mode.
2. `terraform graph` applies a transitive reduction before rendering —
   if a dependency is already reachable through another path (e.g. via
   an explicit `depends_on` to an intermediate resource), the direct
   edge is considered redundant and pruned from the output, even though
   the underlying dependency still exists and still affects apply order.
3. Run a plain `terraform plan` (no `-target`) immediately, to confirm
   nothing else was left pending. `-target` only applies the named
   resource and its dependencies — any other pending changes in the
   configuration remain unapplied until a follow-up plain plan/apply
   catches them.

</details>


---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `terraform.tfstate` (internal structure) | File format | Tracks every resource Terraform manages and its real-world ID |
| `terraform show -json` | CLI command | Machine-readable view of current state |
| `terraform import` | CLI command | Bring an existing AWS resource under Terraform management (legacy syntax) |
| `import` block | Configuration block | Bring an existing AWS resource under Terraform management (modern, declarative, Terraform 1.5+) |
| `terraform state mv` | CLI command | Rename/move a resource's address in state without destroying/recreating it |
| `terraform state rm` | CLI command | Remove a resource from state without destroying it in AWS |
| `terraform state list` / `show` | CLI command | Already used in Demo 01 — revisited here for deeper inspection |
| `terraform force-unlock` | CLI command | Already introduced in Demo 01 — revisited here in a real recovery scenario |

**Related state commands worth knowing (not used in this demo):**

| Command | What it does |
|---|---|
| `terraform state pull` | Outputs the current state as JSON to stdout (used in Demo 01 to restore a downloaded version) |
| `terraform state push` | Writes a local state file to the configured backend — used for manual restoration |
| `terraform state replace-provider` | Updates which provider a resource is associated with, without recreating it |
| `terraform refresh` (deprecated) | Older standalone equivalent of `plan -refresh-only`'s refresh step — use `-refresh-only` instead |

---

### Detailed Explanation of New Constructs

#### `terraform.tfstate` — Internal Structure

State is a JSON file. You've used it indirectly since Demo 00, but never
opened it. Understanding its structure explains what `import`, `mv`, and
`rm` actually edit.

**Top-level fields:**

| Field | Meaning |
|---|---|
| `version` | The state file format version (not the Terraform CLI version) |
| `terraform_version` | The Terraform CLI version that last wrote this file |
| `serial` | An incrementing counter — bumped every time state changes. Used to detect conflicting writes. |
| `lineage` | A UUID generated once, when state is first created. Identifies this state file's "family" — used to detect if someone has pointed Terraform at an unrelated state file by mistake. |
| `outputs` | Current values of all `output` blocks |
| `resources` | An array — one entry per resource Terraform manages |

**Inside each `resources` entry:**

```json
{
  "mode": "managed",
  "type": "aws_s3_bucket",
  "name": "app",
  "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
  "instances": [
    {
      "schema_version": 0,
      "attributes": {
        "id": "cloudnova-dev-app-a1b2c3d4",
        "bucket": "cloudnova-dev-app-a1b2c3d4",
        "arn": "arn:aws:s3:::cloudnova-dev-app-a1b2c3d4",
        "region": "us-east-2"
      },
      "dependencies": [
        "random_id.suffix"
      ]
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `mode` | `"managed"` for normal resources, `"data"` for data sources |
| `type` | The resource type, e.g. `aws_s3_bucket` |
| `name` | The local name from your `.tf` file, e.g. `app` (full address: `aws_s3_bucket.app`) |
| `instances` | An array — more than one entry only if `count`/`for_each` is used |
| `attributes` | Every attribute Terraform knows about this resource, as returned by the provider's last `Read()` call |
| `dependencies` | Other resource addresses this instance depends on |

**Inspect it directly:**

```bash
cat terraform.tfstate | jq '.serial, .lineage'
cat terraform.tfstate | jq '.resources[].type'
cat terraform.tfstate | jq '.resources[] | select(.type=="aws_s3_bucket")'
```

> **Why `serial` and `lineage` matter:** if two engineers somehow end up
> with different local copies of state (shouldn't happen with the S3
> backend from Demo 01, but matters if someone bypasses it), `serial`
> tells Terraform which copy is newer. `lineage` prevents Terraform from
> accidentally treating two *unrelated* state files (e.g. from different
> projects) as the same infrastructure just because the JSON happens to
> parse correctly.

---

#### `terraform show -json` — Machine-Readable State

`terraform state show <address>` (used in Demo 01) shows one resource in
human-readable HCL-like form. `terraform show -json` (no address) dumps
the **entire** current state as structured JSON — useful for scripting,
CI tooling, or piping into `jq` for queries that `state show` can't do
across multiple resources at once.

```bash
terraform show -json | jq '.values.root_module.resources[] | {address, type}'
```

Expected output (abbreviated):

```json
{
  "address": "aws_s3_bucket.legacy",
  "type": "aws_s3_bucket"
}
{
  "address": "aws_s3_bucket_versioning.legacy",
  "type": "aws_s3_bucket_versioning"
}
```

> **`show -json` vs. reading `terraform.tfstate` directly:** they overlap
> but aren't identical. `terraform.tfstate`'s JSON is the **raw storage
> format** the backend writes to disk/S3 — its exact shape is considered
> an internal implementation detail and can change between Terraform
> versions. `terraform show -json`'s output is a **documented, stable
> JSON schema** intended for external tooling to consume. For scripting
> or CI, prefer `show -json` over parsing `.tfstate` directly.

---

#### Why State Must Never Be Committed to Git

State files can contain **plaintext sensitive values** — not because
Terraform chooses to store secrets carelessly, but because state must
record every attribute a resource has, and some resource types have
attributes that are inherently sensitive: database passwords set via a
resource argument, generated private keys, connection strings.

```bash
# Example: if a resource had a sensitive attribute, it would appear
# in plaintext inside terraform.tfstate, e.g.:
grep -i "password\|secret\|private_key" terraform.tfstate
```

Even when nothing in *this specific* configuration is sensitive, the
practice of "never commit state" remains absolute, because:

- A future resource added to the same configuration might introduce a
  sensitive attribute, and by then state may already be in Git history
  (which is very difficult to fully purge)
- State reveals the complete shape of your infrastructure — resource
  IDs, ARNs, internal naming — which is itself reconnaissance value for
  an attacker even without literal secrets
- `.gitignore` should always include `*.tfstate` and `*.tfstate.backup`
  from the very first commit of any Terraform project

This is precisely why Demo 01 moved state to a remote S3 backend with
encryption — remote state with proper IAM access control is the
correct way to share state across a team, never via Git.

---

#### `terraform import` — Bringing Existing Resources Under Management (CLI form)

`terraform import` tells Terraform: "this real AWS resource already
exists — start tracking it in state, mapped to this resource address in
your `.tf` files." It does **not** create anything in AWS, and it does
**not** generate `.tf` code for you — you must already have (or write) a
resource block whose arguments will eventually match the real resource's
actual configuration.

```bash
terraform import aws_s3_bucket.legacy cloudnova-legacy-uploads-xxxxxxxx
```

| Part | Meaning |
|---|---|
| `aws_s3_bucket.legacy` | The resource address in your `.tf` files — must already exist as an empty/minimal resource block |
| `cloudnova-legacy-uploads-xxxxxxxx` | The import ID — for S3 buckets, this is the bucket name. Different resource types use different ID formats (documented per resource type) |

**What happens after `import` succeeds:** the resource is now in state,
but your `.tf` file's resource block may not yet match its real
configuration. Run `terraform plan` immediately — any difference between
what you wrote and what the real resource actually has will show up as
a planned change. You must manually edit the `.tf` block until `plan`
shows zero changes, confirming your code now accurately describes the
imported resource.

> **The single biggest mistake with `import`:** treating a successful
> import as "done." A successful import only means state now tracks the
> resource — it does NOT mean your `.tf` code matches reality. Skipping
> the `plan`-until-clean step risks the next `apply` silently modifying
> or even partially recreating the resource to match an incomplete `.tf`
> block.

---

#### `import` Block — Declarative Import (Terraform 1.5+)

The `import` block achieves the same outcome as `terraform import`, but
declaratively — defined in a `.tf` file, applied via the normal
`plan`/`apply` workflow instead of a separate imperative command. This is
the modern, preferred approach.

```hcl
import {
  to = aws_s3_bucket.legacy
  id = "cloudnova-legacy-uploads-xxxxxxxx"
}
```

| Argument | Description |
|---|---|
| `to` | The resource address to import into — same meaning as the CLI form's first argument |
| `id` | The import ID — same meaning as the CLI form's second argument |

```bash
terraform plan
```

With an `import` block present, `terraform plan` shows the import as a
planned action:

```
Terraform will perform the following actions:

  # aws_s3_bucket.legacy will be imported
    resource "aws_s3_bucket" "legacy" {
        id     = "cloudnova-legacy-uploads-xxxxxxxx"
        bucket = "cloudnova-legacy-uploads-xxxxxxxx"
        ...
    }

Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply
```

The import happens as part of a normal `apply` — reviewable in the plan
output just like any other change, which the CLI form does not offer
(the CLI form imports immediately with no preview).

**`import` block vs. CLI `import` — when to use which:**

| | CLI `terraform import` | `import` block |
|---|---|---|
| Reviewable before it happens | No — imports immediately | Yes — shows in `plan` first |
| Where it lives | Not in any file — a one-off command | In a `.tf` file — version-controlled, repeatable |
| Can import multiple resources at once | One at a time | Multiple `import` blocks in one `apply` |
| Generates resource code for you | No (Terraform 1.5") | With `-generate-config-out=FILE`, can scaffold a starting `.tf` block (still requires manual review/cleanup) |

> **Practical recommendation:** prefer `import` blocks for anything
> beyond a one-off ad hoc import — they're reviewable, repeatable, and
> can be removed from the configuration after the import completes
> (the block is only needed for the one `apply` that performs the
> import; it has no ongoing effect once the resource is in state).

---

#### `terraform state mv` — Rename/Move Without Destroy

When you rename a resource in `.tf` code — e.g. `aws_s3_bucket.app` to
`aws_s3_bucket.uploads` — Terraform has no way to know this is a rename
rather than "delete the old one, create a new one." Comparing state
(which still says `aws_s3_bucket.app`) against the new config (which now
says `aws_s3_bucket.uploads`), a plain `plan` would show:

```
Plan: 1 to add, 0 to change, 1 to destroy.
```

This would destroy and recreate the real bucket — exactly what you don't
want for a rename. `terraform state mv` updates state's record of the
resource's address *without* touching AWS at all:

```bash
terraform state mv aws_s3_bucket.app aws_s3_bucket.uploads
```

After this, state says `aws_s3_bucket.uploads` — matching the renamed
`.tf` block — and `terraform plan` shows:

```
No changes. Your infrastructure matches the configuration.
```

**Other common uses of `state mv`:**
- Moving a resource into or out of a module (changing its address from
  `aws_s3_bucket.app` to `module.storage.aws_s3_bucket.app` or vice
  versa)
- Restructuring `for_each`/`count` keys without recreating every instance

> **`state mv` only edits state — never the `.tf` files.** You must
> still manually rename the resource block in your `.tf` code to match;
> `state mv` just keeps state in sync with that rename so Terraform
> doesn't interpret it as destroy+create.

---

#### `terraform state rm` — Untrack Without Destroying

`terraform state rm` removes a resource from state entirely — Terraform
forgets it exists. The resource itself is **not** touched in AWS; it
keeps running exactly as it was.

```bash
terraform state rm aws_s3_bucket.legacy
```

**Why you'd do this:**
- You're splitting one Terraform configuration into two, and a resource
  needs to move to a different state file (combine with `import` in the
  destination configuration to bring it back under management there)
- A resource was imported by mistake and you want to stop managing it
  without deleting it
- Recovering from a situation where Terraform's tracking of a resource
  has become unreliable, and you plan to re-import it cleanly

**The risk:** once removed from state, if the *same* resource address
still exists in your `.tf` files, the next `terraform plan` will propose
to **create** it — because as far as Terraform's state is concerned, it
doesn't exist yet. If you forget to also remove (or didn't intend to
remove) the `.tf` block, the next `apply` may try to create a duplicate
resource — which often fails for globally-unique-named resources like S3
buckets (`BucketAlreadyExists`), but for other resource types could
silently succeed and create an actual duplicate.

> **`state rm` does not delete the AWS resource.** This is the single
> most commonly misunderstood fact about this command, and a frequent
> exam trap. The resource keeps running in AWS, untouched — only
> Terraform's awareness of it is removed.

---

#### State Corruption and Conflicts — Recovery Strategy

"Corruption" here doesn't usually mean literally invalid JSON (rare) — it
more often means state that's become an unreliable description of
reality: a resource Terraform thinks exists but doesn't, a state file
overwritten by a stale write, or a lock left stuck after a crashed apply.

**Recovery toolkit, in order of how often you'll actually need each:**

| Tool | What it fixes | Risk if used incorrectly |
|---|---|---|
| `terraform plan -refresh-only` | Diagnoses the gap — shows what's different between state and reality before you act | None — read-only |
| Restore a previous state version from S3 versioning | A bad write (e.g. partial apply that corrupted state) — roll back to the last-known-good version | Loses any legitimate changes made between the bad version and the restore point |
| `terraform force-unlock` | A stuck lock left behind by a crashed/killed apply | If used while an apply IS actually still running, two applies can corrupt state simultaneously |
| `terraform state rm` + re-`import` | State's record of a resource has drifted so far from reality that surgical correction isn't practical | Temporarily un-tracks the resource; must re-import correctly or it's permanently orphaned from Terraform |

**Restoring from S3 versioning (built on Demo 01's setup):**

```
Console → S3 → your state bucket → terraform.tfstate
  → "Show versions" toggle (top right of Objects tab)
  → Each apply created a new version with a timestamp
  → Identify the last-known-good version (before the bad write)
  → Download that version
  → Rename the downloaded file to terraform.tfstate
```

```bash
terraform state push terraform.tfstate
```

This **overwrites the current remote state** with the contents of the
local file you just pushed — it does not merge, it replaces. Use with
care: any changes recorded in state *after* the version you're restoring
will be lost from Terraform's view (the actual AWS resources are
unaffected either way — only Terraform's record of them changes).

> **Always run `terraform plan -refresh-only` immediately after a state
> push.** This confirms whether the restored state now matches real
> infrastructure, or whether there's a gap that needs reconciling — the
> push only changes what Terraform *believes*, not what's actually
> deployed in AWS.

**`terraform force-unlock` in a real recovery scenario:**

You used this command in passing in Demo 01. Here's the actual recovery
flow when you hit it for real:

```bash
terraform plan
```

```
Error: Error acquiring the state lock

Lock Info:
  ID:        7a3f9c21-...
  Path:      phase-1/04-state-management/terraform.tfstate
  Operation: OperationTypePlan
  Who:       wadmin@ubuntu-lab
  Version:   1.15.0
  Created:   2026-06-14 03:12:07 UTC
```

**Before force-unlocking, confirm no apply is actually running:**

```
Console → S3 → state bucket → phase-1/04-state-management/
  → Check for terraform.tfstate.tflock
  → If present: confirm with the "Who" field above whether that
    engineer's apply is genuinely still in progress (ask them, check
    CI pipeline status, etc.) before assuming it's stuck
```

```bash
# Only once confirmed no apply is actually running:
terraform force-unlock 7a3f9c21-...
```

> **The exam trap:** `force-unlock` does not validate anything about
> whether it's safe to unlock — it simply removes the lock file. If an
> apply genuinely is still running when you force-unlock, a second apply
> can now start concurrently with the first, which is exactly the state
> corruption scenario locking exists to prevent. Confirm first; unlock
> second.

---

## Lab Step-by-Step Guide

---

## Part A — State File Anatomy

**What you accomplish in Part A:** build a small baseline configuration,
apply it, then inspect `terraform.tfstate` directly to see the structure
explained in Concepts. No new AWS resources beyond what's needed to have
real state to inspect.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/04-state-management/src
```

### Step 2 — Create the source files

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
    tags = local.common_tags
  }
}
```

---

#### `03-backend.tf` — Remote S3 backend

**What this file does in this demo:** uses the same remote-backend
pattern from Demo 01 — state bucket created manually (Console) before
`terraform init`, S3 native locking via `use_lockfile`.

**03-backend.tf:**

```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-cloudnova-163125980376-us-east-2"
    # ↑ reuse the same state bucket from Demo 01, or create a fresh one —
    # replace with your actual state bucket name

    key          = "phase-1/04-state-management/terraform.tfstate"
    region       = "us-east-2"
    profile      = "default"
    encrypt      = true
    use_lockfile = true
  }
}
```

> **Note:** If you deleted the state bucket during Demo 01's cleanup,
> recreate it now using the same Console steps from Demo 01 Step 8
> before running `terraform init` below.

---

#### `04-variables.tf` — Input variables

**04-variables.tf:**

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
}

variable "demo" {
  type        = string
  description = "Demo identifier — used in tags for traceability"
  default     = "04-state-management"
}
```

---

#### `05-locals.tf` — Computed values

**05-locals.tf:**

```hcl
locals {
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

#### `06-main.tf` — Starting point (empty — populated in Part B)

**What this file does in this demo:** starts empty. Part B will add the
`aws_s3_bucket.legacy` resource block used for the import exercise. For
Part A, this file exists but contains no resources — its only purpose
right now is for `terraform init` to succeed.

**06-main.tf:**

```hcl
# Resources added in Part B — intentionally empty for now
```

---

#### `07-outputs.tf` — Expose values after apply

**07-outputs.tf:**

```hcl
# Outputs added in Part B once aws_s3_bucket.legacy exists
```

---

### Step 3 — Initialise

```bash
terraform init
```

Expected output:

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.47.0"...
- Installing hashicorp/aws v6.47.0...
- Installed hashicorp/aws v6.47.0 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl

Terraform has been successfully initialized!
```

```bash
terraform apply
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

This is expected — there are no resources yet. State now exists (created
by `init` + the backend), but it's nearly empty. This is your baseline.

---

### Step 4 — Inspect `terraform.tfstate` directly

Since state is remote (S3), pull a local copy to inspect:

```bash
terraform state pull > terraform.tfstate
cat terraform.tfstate | jq '.'
```

Expected output (abbreviated — no resources yet):

```json
{
  "version": 4,
  "terraform_version": "1.15.0",
  "serial": 1,
  "lineage": "3f9a2c1e-...",
  "outputs": {},
  "resources": []
}
```

```bash
# Top-level fields only
cat terraform.tfstate | jq '.version, .terraform_version, .serial, .lineage'
```

> **Why `resources` is empty:** nothing has been declared in
> `06-main.tf` yet — `serial: 1` reflects the one state-creating
> operation (the backend's first write during `init`/`apply`), and
> `lineage` was generated once, at that moment. Both will change as you
> proceed through Part B.

---

### Step 5 — `terraform show -json`

```bash
terraform show -json | jq '.values'
```

Expected output:

```json
{
  "root_module": {}
}
```

Empty for the same reason — no resources yet. You'll revisit both
`terraform.tfstate` and `show -json` after Part B's import, once there's
something real to inspect.

---

## Part B — State Surgery: Import, Move, Remove

**What you accomplish in Part B:** manually create a bucket (simulating
CloudNova's legacy resource), import it two ways, rename it with
`state mv`, then practise `state rm`.

### Step 1 — Manually create the "legacy" bucket

Simulate the pre-Terraform resource. In the Console (not Terraform):

```
Console → S3 → General purpose buckets → Create bucket

Bucket name:
  cloudnova-legacy-uploads-<your-initials-or-random-digits>
  (must be globally unique — add digits if taken)

AWS Region:
  US East (Ohio) us-east-2

Bucket Versioning:
  ✅ Enable

Default encryption:
  ✅ Server-side encryption with Amazon S3 managed keys (SSE-S3)

→ Click Create bucket
```

**Verify:**

```bash
aws s3api list-buckets --profile default | jq '.Buckets[] | select(.Name | startswith("cloudnova-legacy"))'
```

---

### Step 2 — Write the matching resource block

Add to `06-main.tf` — note this resource block is **empty of most
arguments at first**, since you don't yet know exactly how the real
bucket is configured:

```hcl
resource "aws_s3_bucket" "legacy" {
  # Intentionally minimal — will be filled in once import reveals
  # the real bucket's configuration
}
```

---

### Step 3 — Import via CLI

```bash
terraform import aws_s3_bucket.legacy cloudnova-legacy-uploads-xxxxxxxx
```

Expected output:

```
aws_s3_bucket.legacy: Importing from ID "cloudnova-legacy-uploads-xxxxxxxx"...
aws_s3_bucket.legacy: Import prepared!
  Prepared aws_s3_bucket for import
aws_s3_bucket.legacy: Refreshing state... [id=cloudnova-legacy-uploads-xxxxxxxx]

Import successful!

The resources that were imported are shown above. These resources are now
in your Terraform state and will henceforth be managed by Terraform.
```

```bash
terraform plan
```

Expected output — even though import succeeded, the bare resource block
doesn't yet match reality on every attribute Terraform tracks:

```
  # aws_s3_bucket.legacy will be updated in-place
  ~ resource "aws_s3_bucket" "legacy" {
        id     = "cloudnova-legacy-uploads-xxxxxxxx"
      ~ bucket = "cloudnova-legacy-uploads-xxxxxxxx" -> (known after apply)
        ...
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

Fix `06-main.tf` to declare the actual bucket name explicitly:

```hcl
resource "aws_s3_bucket" "legacy" {
  bucket = "cloudnova-legacy-uploads-xxxxxxxx"   # replace with your actual name
}
```

```bash
terraform plan
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

> **This confirms the import is "clean."** A successful `terraform
> import` only put the resource in state — it was this follow-up
> `plan`-until-zero-changes loop that confirmed your `.tf` code now
> accurately describes the real bucket.

---

### Step 4 — Remove it, then re-import declaratively with an `import` block

To practise the modern approach, first undo the CLI import (without
touching AWS):

```bash
terraform state rm aws_s3_bucket.legacy
```

Expected output:

```
Removed aws_s3_bucket.legacy
Successfully removed 1 resource instance(s).
```

```bash
terraform state list
```

Expected output: empty — Terraform no longer tracks the bucket, but it
still exists in AWS (verify in Console if you'd like — it's untouched).

Now add an `import` block to `06-main.tf`, alongside the existing
(still-correct) resource block:

```hcl
import {
  to = aws_s3_bucket.legacy
  id = "cloudnova-legacy-uploads-xxxxxxxx"   # replace with your actual name
}

resource "aws_s3_bucket" "legacy" {
  bucket = "cloudnova-legacy-uploads-xxxxxxxx"   # replace with your actual name
}
```

```bash
terraform plan
```

Expected output:

```
Terraform will perform the following actions:

  # aws_s3_bucket.legacy will be imported
    resource "aws_s3_bucket" "legacy" {
        id     = "cloudnova-legacy-uploads-xxxxxxxx"
        bucket = "cloudnova-legacy-uploads-xxxxxxxx"
        ...
    }

Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply
```

Type `yes`. Expected output:

```
aws_s3_bucket.legacy: Importing... [id=cloudnova-legacy-uploads-xxxxxxxx]
aws_s3_bucket.legacy: Import complete after 1s [id=cloudnova-legacy-uploads-xxxxxxxx]

Apply complete! Resources: 1 imported, 0 added, 0 changed, 0 destroyed.
```

> **The `import` block can now be removed from `06-main.tf`** — it has
> no ongoing effect once the import is complete. Leaving it in is
> harmless (subsequent applies simply re-confirm the resource is already
> imported and do nothing), but removing it keeps the file clean. Remove
> it now before continuing.

---

### Step 5 — Add the remaining configuration resources

Now that the bucket is under management, add versioning and encryption
config to match what you created manually in Step 1 — this is normal
Terraform work, same pattern as Demo 01:

```hcl
resource "aws_s3_bucket_versioning" "legacy" {
  bucket = aws_s3_bucket.legacy.id

  versioning_configuration {
    status = "Enabled"
  }

  depends_on = [aws_s3_bucket.legacy]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "legacy" {
  bucket = aws_s3_bucket.legacy.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

  depends_on = [aws_s3_bucket.legacy]
}
```

```bash
terraform plan
```

Expected output:

```
  # aws_s3_bucket_versioning.legacy will be created
  + resource "aws_s3_bucket_versioning" "legacy" { ... }

  # aws_s3_bucket_server_side_encryption_configuration.legacy will be created
  + resource "aws_s3_bucket_server_side_encryption_configuration" "legacy" { ... }

Plan: 2 to add, 0 to change, 0 to destroy.
```

These are genuinely new to Terraform's tracking (you only imported the
bucket itself, not its sub-configurations) — but since versioning and
encryption already exist in AWS exactly as declared, `apply` here
**adopts** them via `Create` calls that AWS treats as idempotent
no-ops on already-matching configuration, rather than changing anything.

```bash
terraform apply
```

Type `yes`, then verify `terraform plan` shows no further changes.

---

### Step 6 — Add outputs

**07-outputs.tf:**

```hcl
output "legacy_bucket_name" {
  description = "Name of the imported legacy bucket"
  value       = aws_s3_bucket.legacy.bucket
}

output "legacy_bucket_arn" {
  description = "ARN of the imported legacy bucket"
  value       = aws_s3_bucket.legacy.arn
}
```

```bash
terraform apply
```

---

### Step 7 — `terraform state mv` — rename without recreate

CloudNova's naming convention prefers `uploads` over `legacy` going
forward. Rename the resource in code:

```hcl
resource "aws_s3_bucket" "uploads" {   # renamed from "legacy"
  bucket = "cloudnova-legacy-uploads-xxxxxxxx"
}
```

(Also rename the matching `bucket = aws_s3_bucket.legacy.id` references
in the versioning/encryption resources to `aws_s3_bucket.uploads.id`,
and their own resource labels if you want full consistency — for this
exercise, just rename `aws_s3_bucket.legacy` itself.)

```bash
terraform plan
```

Expected output — without `state mv`, this looks like destroy + recreate:

```
  # aws_s3_bucket.legacy will be destroyed
  - resource "aws_s3_bucket" "legacy" { ... }

  # aws_s3_bucket.uploads will be created
  + resource "aws_s3_bucket" "uploads" { ... }

Plan: 1 to add, 0 to change, 1 to destroy.
```

**Stop — do not apply this.** Fix it with `state mv` instead:

```bash
terraform state mv aws_s3_bucket.legacy aws_s3_bucket.uploads
```

Expected output:

```
Move "aws_s3_bucket.legacy" to "aws_s3_bucket.uploads"
Successfully moved 1 object(s).
```

```bash
terraform plan
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

> **The real bucket in AWS was never touched** — only state's record of
> which `.tf` address it's associated with changed.

---

### Step 8 — `terraform state rm` — untrack without destroying

Demonstrate the untrack behavior (without permanently abandoning the
resource — you'll re-import it right after):

```bash
terraform state rm aws_s3_bucket.uploads
```

```bash
terraform state list
```

Expected: `aws_s3_bucket.uploads` is gone from the list.

```bash
aws s3api head-bucket --bucket cloudnova-legacy-uploads-xxxxxxxx --profile default
```

Expected: succeeds with no error — the bucket still exists in AWS,
completely unaffected by `state rm`.

```bash
terraform plan
```

Expected output — since the `.tf` block for `aws_s3_bucket.uploads`
still exists, but state no longer knows about it, Terraform now thinks
it needs to be **created**:

```
  # aws_s3_bucket.uploads will be created
  + resource "aws_s3_bucket" "uploads" {
      + bucket = "cloudnova-legacy-uploads-xxxxxxxx"
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

> **Do not run `apply` here** — since S3 bucket names are globally
> unique, this `apply` would fail with `BucketAlreadyExists` (a safe
> failure mode for this resource type). For resource types without
> globally-unique naming, this exact situation could succeed and create
> a genuine duplicate. Re-import correctly instead:

```bash
terraform import aws_s3_bucket.uploads cloudnova-legacy-uploads-xxxxxxxx
terraform plan
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

---

## Part C — Recovery from Corruption and Conflicts

**What you accomplish in Part C:** simulate a bad state write, restore
from S3 versioning, and practise `force-unlock` in a realistic scenario.

### Step 1 — Capture a known-good state version

Confirm current state is clean:

```bash
terraform plan
```

Expected: `No changes. Your infrastructure matches the configuration.`

```
Console → S3 → state bucket → phase-1/04-state-management/terraform.tfstate
  → Show versions toggle
  → Note the timestamp of the current (latest) version — this is your
    known-good baseline
```

### Step 2 — Simulate a bad write

Add a deliberately incorrect attribute override that will get written to
state (a tag value that doesn't match reality after a manual Console
edit, similar to drift scenarios in Demos 01/03, but this time used to
set up a state recovery exercise):

```bash
# In Console, manually delete the legacy-uploads bucket's versioning
# configuration (Properties tab → Bucket Versioning → Suspend)
```

```bash
terraform apply -refresh-only
```

Type `yes` to accept the drift into state — this is the "bad write" for
this exercise: state now reflects suspended versioning, even though your
`.tf` files still declare it as `Enabled`.

```bash
terraform state show aws_s3_bucket_versioning.uploads
```

Expected output shows the drifted (Suspended) status now recorded in
state.

### Step 3 — Identify and restore the known-good version

```
Console → S3 → state bucket → phase-1/04-state-management/terraform.tfstate
  → Show versions toggle
  → Find the version from Step 1 (before the bad write)
  → Select it → Download
  → Rename the downloaded file to terraform.tfstate (in your local
    working directory, NOT overwriting your already-correct .tf files)
```

```bash
terraform state push terraform.tfstate
```

Expected output:

```
Successfully pushed state to backend "s3"
```

> **`state push` overwrites, it does not merge.** Any state changes
> made between the known-good version and now are discarded from
> Terraform's record — but real AWS resources are unaffected by this
> command either way; only Terraform's belief about them changes.

### Step 4 — Confirm and reconcile

```bash
terraform plan -refresh-only
```

Expected output — now that restored state says versioning should be
`Enabled`, and a fresh refresh confirms AWS still actually has it
`Suspended` (you never reverted the Console change, only restored an
older copy of state), this surfaces as real drift again:

```
Note: Objects have changed outside of Terraform

  # aws_s3_bucket_versioning.uploads has changed
  ~ resource "aws_s3_bucket_versioning" "uploads" {
      ~ versioning_configuration {
          ~ status = "Enabled" -> "Suspended"
        }
    }
```

```bash
terraform apply
```

Type `yes` — this reconciles AWS back to `Enabled`, matching `.tf`.

> **The full recovery pattern:** restoring an old state version doesn't
> by itself fix anything in AWS — it only changes what Terraform
> believes. Always follow a state restore with `plan -refresh-only` to
> see whether reality and the restored state now agree, and `apply` if
> they don't.

---

### Step 5 — `terraform force-unlock` in a realistic scenario

Simulate a stuck lock by interrupting an apply mid-flight (in a real
incident this would be a crashed CI runner or a killed terminal):

```bash
terraform apply
# While it's running (after you see "Creating..." or "Refreshing..."),
# press Ctrl+C once
```

Expected output:

```
Interrupt received.
Please wait for Terraform to exit or data corruption may occur.

Two interrupts received. Exiting immediately.
```

> Pressing Ctrl+C **once** lets Terraform attempt a clean shutdown
> (releasing the lock if possible). Pressing it twice forces an immediate
> exit and can leave the lock file behind — for this exercise, press it
> twice to deliberately simulate the stuck-lock scenario.

```bash
terraform plan
```

Expected output:

```
Error: Error acquiring the state lock

Lock Info:
  ID:        <a UUID>
  Path:      phase-1/04-state-management/terraform.tfstate
  Operation: OperationTypeApply
  Who:       <your-username>@<hostname>
  Version:   1.15.0
  Created:   <timestamp>
```

**Confirm before unlocking:**

```
Console → S3 → state bucket → phase-1/04-state-management/
  → Confirm terraform.tfstate.tflock is present
  → Since you just interrupted this yourself, you know no apply is
    actually still running — in a real scenario, verify with the
    "Who" field and check with that person/CI system first
```

```bash
terraform force-unlock <the-lock-ID-from-the-error>
```

Expected output:

```
Terraform state has been successfully unlocked!
```

```bash
terraform plan
```

Expected output: `No changes. Your infrastructure matches the
configuration.` — confirming the interrupted apply didn't leave state in
a half-written condition (Terraform's state writes are designed to be
atomic — either fully written or not at all — so an interrupt mid-apply
typically leaves the lock stuck without corrupting the state content
itself).

---

## Cleanup

```bash
terraform destroy
```

Type `yes`. Expected output:

```
aws_s3_bucket_server_side_encryption_configuration.uploads: Destroying...
aws_s3_bucket_versioning.uploads: Destroying...
aws_s3_bucket_server_side_encryption_configuration.uploads: Destruction complete after 1s
aws_s3_bucket_versioning.uploads: Destruction complete after 1s

aws_s3_bucket.uploads: Destroying...
aws_s3_bucket.uploads: Destruction complete after 2s

Destroy complete! Resources: 3 destroyed.
```

> **Note:** even though this bucket was originally created manually
> (outside Terraform), `terraform destroy` deletes it like any other
> managed resource — once imported, Terraform treats it identically to a
> resource it created itself. There is no "imported resources are
> protected from destroy" special case.

**Verify in Console:**

```
Console → S3 → Buckets
  → cloudnova-legacy-uploads-xxxxxxxx: GONE ✅
```

```bash
rm -f terraform.tfstate
```

---

## What You Learned

1. ✅ `terraform.tfstate` has a documented internal structure —
   `serial`, `lineage`, `outputs`, and a `resources` array with one
   entry per managed resource, including its real-world attributes and
   dependencies
2. ✅ `terraform show -json` provides a stable, documented JSON schema
   for external tooling — preferred over parsing `.tfstate` directly,
   whose raw format is an internal implementation detail
3. ✅ State must never be committed to Git — it can contain sensitive
   attributes in plaintext, and even without secrets, it reveals the
   complete shape of your infrastructure
4. ✅ `terraform import` (CLI) brings an existing resource into state
   immediately, with no preview; the `import` block (Terraform 1.5+) is
   reviewable in `plan` first and is the modern preferred approach
5. ✅ A successful import only means state tracks the resource — `.tf`
   code must still be manually refined until `plan` shows zero changes
6. ✅ `terraform state mv` renames/moves a resource's address in state
   without touching the real infrastructure — essential for renames and
   module restructuring
7. ✅ `terraform state rm` removes a resource from state without
   destroying it in AWS — the resource keeps running, untouched, but
   Terraform forgets it exists
8. ✅ State recovery from S3 versioning restores Terraform's *belief*
   about infrastructure, not infrastructure itself — always follow a
   restore with `plan -refresh-only` to check whether reality agrees
9. ✅ `terraform force-unlock` should only be used after confirming no
   apply is genuinely still running — it doesn't validate this for you

---

## Cert Tips — TA-004 Objectives Covered

This demo covers **TA-004 Objective on state management** in depth:

- `terraform import` and `import` blocks achieve the same end state —
  know that only the `import` block is previewable in `plan` before it
  happens
- **`terraform state rm` does NOT delete the AWS resource** — this is
  one of the most frequently tested facts in this objective area
- `terraform state mv` only edits state, never `.tf` files — you must
  manually keep the `.tf` resource block's name in sync
- State file top-level fields: `version`, `terraform_version`, `serial`,
  `lineage`, `outputs`, `resources` — know what `serial` and `lineage`
  are each used for (conflict detection vs. identity verification)
- `terraform state push` **overwrites** remote state — it does not merge
  with what's currently there
- `terraform force-unlock` requires the lock ID shown in the error
  message, and does not itself verify whether unlocking is safe

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Error: Cannot import non-existent remote object` | The import ID doesn't match any real resource, or wrong region/account | Verify the resource exists with `aws s3api head-bucket` (or the equivalent CLI command for the resource type) before importing |
| `terraform plan` after import shows many changes, not zero | The `.tf` resource block is still minimal/incomplete relative to the real resource's full configuration | Iterate: add missing arguments, `plan`, repeat until zero changes |
| `BucketAlreadyExists` after `state rm` + `apply` | Forgot to re-import; Terraform tried to create a resource that already exists | Use `terraform import` again instead of `apply` |
| `Error: state data in S3 does not have the expected content` | `state push` was attempted with a malformed or unrelated state file | Confirm the file's `lineage` matches the current backend's expected lineage before pushing |
| `Error acquiring the state lock` immediately after a normal (non-crashed) apply | A previous apply genuinely is still running elsewhere (CI, another engineer) | Wait — do not force-unlock without confirming first |
| `jq: command not found` | `jq` not installed | Install via `apt install jq` / `brew install jq` (see Prerequisites) |
| `import` block apply fails with "resource already managed" | The resource is already in state from a previous import attempt | Remove the redundant `import` block — the resource is already tracked |

---

## Break-Fix Scenario

### Scenario

A teammate was troubleshooting a state mismatch on the `uploads` bucket
and, in a hurry, ran:

```bash
terraform state rm aws_s3_bucket.uploads
terraform state rm aws_s3_bucket_versioning.uploads
terraform state rm aws_s3_bucket_server_side_encryption_configuration.uploads
```

intending to re-import all three cleanly afterward. They got pulled into
a meeting immediately after and didn't finish. A day later, you're asked
to pick up where they left off. You run:

```bash
terraform plan
```

```
Terraform will perform the following actions:

  # aws_s3_bucket.uploads will be created
  + resource "aws_s3_bucket" "uploads" {
      + bucket = "cloudnova-legacy-uploads-xxxxxxxx"
      ...
    }

  # aws_s3_bucket_versioning.uploads will be created
  + resource "aws_s3_bucket_versioning" "uploads" {
      ...
    }

  # aws_s3_bucket_server_side_encryption_configuration.uploads will be created
  + resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
      ...
    }

Plan: 3 to add, 0 to change, 0 to destroy.
```

Someone on the team says "just run apply, it'll recreate them and we're
back to normal." Is that correct? What should you actually do?

<details>
<summary>Diagnosis and Fix</summary>

**Diagnosis:**

Running `apply` here would be a serious mistake for two of the three
resources, and only accidentally safe for one — and you can't tell which
is which just from the plan output alone.

Walking through each:

1. **`aws_s3_bucket.uploads`** — S3 bucket names are globally unique.
   The real bucket `cloudnova-legacy-uploads-xxxxxxxx` still exists in
   AWS (only state's tracking of it was removed, not the bucket itself —
   exactly as `state rm` is documented to behave). `apply` would attempt
   `CreateBucket` with a name that already exists, fail with
   `BucketAlreadyExists`, and stop. Safe by accident — the failure
   protects you here, but only because of S3's global-uniqueness
   constraint specifically.

2. **`aws_s3_bucket_versioning.uploads`** and
   **`aws_s3_bucket_server_side_encryption_configuration.uploads`** —
   these resource types do **not** have a global-uniqueness constraint
   the same way bucket names do. If `apply` reached these (it won't in
   this exact case, because it would fail on the bucket first since
   Terraform processes resources based on the dependency graph — but
   imagine a scenario where the bucket import succeeds first, separately)
   — AWS would simply accept the `Put...Configuration` calls again. This
   *could* appear to "work," because setting versioning/encryption to a
   value that already matches reality is not inherently destructive —
   but you'd have gotten lucky, not because `apply` is safe to use as a
   substitute for `import` here. For other resource types without this
   forgiving idempotency (e.g., resources that generate a new ID on
   every create, like some IAM resources or certain compute resources),
   running `apply` after a `state rm` instead of re-importing can create
   genuine duplicates.

**The correct fix — re-import each resource, in dependency order:**

```bash
terraform import aws_s3_bucket.uploads cloudnova-legacy-uploads-xxxxxxxx
terraform import aws_s3_bucket_versioning.uploads cloudnova-legacy-uploads-xxxxxxxx
terraform import aws_s3_bucket_server_side_encryption_configuration.uploads cloudnova-legacy-uploads-xxxxxxxx
```

```bash
terraform plan
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

**Root cause (process, not code):** `state rm` was used correctly in
isolation (it does exactly what it's documented to do — untrack without
destroying), but the *team process* around it broke down: removing
multiple resources from state with the intent to "re-import cleanly
afterward" left a window where anyone unfamiliar with that specific
intent could reasonably (but incorrectly) assume `apply` was the
recovery step. The fix for the pattern: any `state rm` performed as part
of a multi-step recovery should be documented inline (a comment in the
PR/ticket, or even a temporary comment in the `.tf` file) stating
explicitly "these resources are mid-reimport — use `terraform import`,
not `apply`, to restore tracking."

</details>

---

## Interview Prep

**Q1. A teammate says "we should just delete `terraform.tfstate` and let Terraform recreate it from the `.tf` files — that way we know it's clean." What's wrong with this reasoning?**
Deleting state doesn't make Terraform "recreate it from the .tf files" in the sense they mean — state isn't derived from `.tf` files, it's the record of what Terraform has *already built* in AWS. If state is deleted, Terraform has no memory of any existing resource, and the next `plan` would propose creating every resource from scratch — even though they already exist in AWS. For globally-unique-named resources this fails loudly (`BucketAlreadyExists`), which is at least safe, but for most resource types it would either fail with a less obvious error or, worse, actually create duplicates. The correct way to get a "clean" state when you suspect drift or inconsistency is `terraform plan -refresh-only` to diagnose the gap, not deleting state and starting over.

**Q2. Your team needs to split one large Terraform configuration into two smaller ones, each with its own state file. One resource needs to move from the old configuration to the new one. Walk through the safe sequence.**
The safe sequence is: `terraform state rm <address>` in the *old* configuration (untracks the resource there, without touching AWS), then `terraform import <address> <id>` in the *new* configuration (or an `import` block applied via the new config's `plan`/`apply`). At no point does the actual AWS resource get destroyed or recreated — only which state file is tracking it changes. The risky alternative — deleting the resource from the old `.tf` files and adding it to the new ones without the explicit `state rm`/`import` pair — would cause the old configuration's next `apply` to destroy it (since it's no longer declared there) and the new configuration's next `apply` to create a fresh one, which for most resource types means real downtime and, for stateful resources like databases, real data loss.

**Q3. A junior engineer ran `terraform import` on a resource, saw "Import successful!", and immediately moved on to other work, considering the resource fully migrated. What's missing, and why does it matter?**
A successful import only means the resource is now tracked in state — it says nothing about whether the `.tf` configuration block actually matches the resource's real, full configuration. If the engineer's resource block was minimal (missing arguments the real resource actually has set), the very next `terraform plan` run by anyone on the team — possibly weeks later — would show unexpected changes, because Terraform is comparing an incomplete `.tf` block against the real resource's complete attribute set. Worse, if someone runs `apply` without noticing, Terraform could modify the real resource to match the incomplete configuration, potentially undoing settings nobody intended to change. The required follow-up is always: run `plan` immediately after import, and keep refining the `.tf` block until `plan` shows zero changes — only then is the import actually complete.

**Q4. Someone on your team suggests committing `terraform.tfstate` to a private Git repo "since it's a private repo anyway, nobody outside the team can see it." Push back on this.**
Even in a fully private repo, this is still a bad practice for several reasons beyond just "secrets might leak to the public." First, state can't be safely shared this way for *team workflow* reasons — Git doesn't provide the locking that prevents two engineers from applying simultaneously and corrupting state, which is the exact problem Demo 01's S3 backend with `use_lockfile` solves. Second, even "private" repos are accessible to every team member with read access, which may be a broader set of people than should see infrastructure-level resource IDs, ARNs, and any sensitive attribute values — access to view code and access to view live infrastructure details are different concerns that shouldn't be conflated. Third, Git history is effectively permanent — even if a sensitive value is later removed from a file, it typically remains recoverable from history unless someone does a full history rewrite, which is disruptive and easy to get wrong. The remote backend (S3, in this series) solves the sharing problem correctly: encrypted storage, IAM-controlled access, locking, and versioning, without any of Git's drawbacks for this use case.

**Q5. A teammate force-unlocked state during an incident, and it turned out an apply genuinely was still running elsewhere. What likely happened as a result, and how should the team change its process to prevent a repeat?**
With the lock removed while a real apply was in progress, a second `apply` (or the same person retrying) could start concurrently — both reading the same starting state, both eventually writing their results, with the second write overwriting the first. The practical result: whichever apply's resources were created or modified by the *first* operation may now be missing from state (even though they exist in AWS), because the *second* apply's write didn't know about them. This is precisely the corruption scenario state locking exists to prevent, just achieved by deliberately bypassing the protection. The process fix: before any `force-unlock`, require a positive confirmation step — checking the lock's `Who` field and actually contacting that person or checking CI pipeline status — rather than treating "I got a lock error" as sufficient evidence that the lock is stale. Document this as a required step, not an optional courtesy, since `force-unlock` itself doesn't validate safety and will happily remove an active lock if asked.

---

## Key Takeaways

1. **State is a record of reality, not derived from `.tf` files.**
   Deleting or mishandling state doesn't reset infrastructure to a clean
   slate — it just makes Terraform forget what it already built, which
   leads to failed or duplicate creates on the next apply.

2. **A successful `terraform import` is the start of the work, not the
   end.** The resource is tracked, but the `.tf` block must be refined
   until `plan` shows zero changes before the import is actually
   complete.

3. **`import` blocks are reviewable; the CLI form is not.** Prefer
   `import` blocks for anything beyond a one-off, since they show up in
   `plan` before anything happens and live in version control.

4. **`state mv` and `state rm` only edit state — never the real
   infrastructure, and never `.tf` files.** Renames require both a
   `.tf` edit and a `state mv` to stay in sync; removing a resource from
   state never destroys it in AWS.

5. **`state rm` followed by `apply` is not a safe substitute for
   re-importing.** Whether it "accidentally works" depends entirely on
   whether the resource type has a uniqueness constraint that happens to
   block accidental recreation — never rely on this.

6. **Restoring state from versioning changes what Terraform believes,
   not what's actually deployed.** Always follow a state restore with
   `plan -refresh-only` to check whether the restored state and real
   infrastructure agree.

7. **`force-unlock` does not verify safety — confirmation is a manual,
   required step.** Check the lock's `Who` field and confirm with that
   person or system before unlocking, every time.

8. **State must never be committed to Git, even to a private repo.**
   Beyond potential secrets, Git lacks the locking remote backends
   provide, and history is effectively permanent even after a file is
   removed.

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform init` | Downloads provider plugins and initialises the backend |
| `jq '<FILTER>' <FILE>` | Queries a JSON file (state, `show -json` output) using a jq filter expression |
| `terraform state pull` | Outputs the current remote state as JSON to stdout |
| `terraform show -json` | Outputs the entire current state in the stable, documented JSON schema |
| `terraform import <ADDRESS> <ID>` | Adds an existing AWS resource to state at the given address, immediately |
| `terraform plan` | Previews changes, including any pending `import {}` blocks |
| `terraform apply` | Applies pending changes, including any pending imports, after confirmation |
| `terraform state rm <ADDRESS>` | Removes a resource from state without destroying it in AWS |
| `terraform state mv <OLD_ADDRESS> <NEW_ADDRESS>` | Renames or moves a resource's address in state without touching AWS |
| `terraform state list` | Lists every resource address currently tracked in state |
| `terraform state show <ADDRESS>` | Shows full state details for one resource |
| `aws s3api head-bucket --bucket <NAME> --profile <PROFILE>` | Confirms a bucket still exists in AWS, independent of Terraform state |
| `terraform state push <FILE>` | Overwrites remote state with the contents of a local state file |
| `terraform force-unlock <LOCK_ID>` | Removes a stuck state lock — only after confirming no apply is genuinely running |
| `terraform destroy` | Destroys all resources managed by this configuration |

---

## Next Demo

**Demo 05 — Variables, Locals, Outputs:** A deeper look at input
variable types and validation, locals for computed values, output
formatting and sensitivity, and the difference between `terraform_remote_state`
and direct module outputs for sharing values across configurations.

## Appendix — Anki Cards

**04-state-management-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::04-state-management
#separator:Comma
#columns:Front,Back,Tags
"What are the six top-level fields in terraform.tfstate's JSON structure?","version (state format version), terraform_version (CLI version that last wrote it), serial (incrementing counter, bumped on every change), lineage (UUID identifying this state's identity), outputs (current output values), resources (array of managed/data resources).","demo04,state,structure"
"What is the difference between state's serial and lineage fields?","serial is an incrementing counter used to detect conflicting/stale writes (which copy of state is newer). lineage is a UUID generated once when state is first created, used to detect if Terraform has been pointed at an unrelated state file by mistake (identity check, not ordering).","demo04,state,structure"
"What is the difference between terraform.tfstate's raw JSON and terraform show -json's output?","terraform.tfstate is the raw storage format the backend writes — its exact shape is an internal implementation detail that can change between Terraform versions. terraform show -json provides a documented, stable JSON schema intended for external tooling. Prefer show -json for scripting/CI.","demo04,state,show-json"
"Why must terraform.tfstate never be committed to Git, even in a private repo?","State can contain sensitive attributes in plaintext (passwords, keys set via resource arguments). Even without secrets, it reveals the complete shape of infrastructure (resource IDs, ARNs). Git also lacks locking (two engineers could apply simultaneously and corrupt state) and history is effectively permanent even after a file is removed.","demo04,state,security"
"What does terraform import actually do — does it create anything in AWS?","No. terraform import only adds an existing AWS resource to Terraform's state, mapped to a resource address you specify. It creates nothing in AWS and does not generate .tf code for you — you must already have a resource block whose arguments will eventually need to match the real resource.","demo04,import,state"
"After a successful terraform import, terraform plan still shows changes. What does this mean, and what should you do?","It means the .tf resource block doesn't yet fully match the real resource's actual configuration — import only tracks the resource in state, it doesn't validate or sync the .tf code. Iterate: add/adjust arguments in the .tf block and re-run plan until it shows zero changes — only then is the import complete.","demo04,import,plan"
"What is the key difference between CLI terraform import and an import {} block?","CLI import executes immediately with no preview. An import {} block is declarative — it shows up in terraform plan as a previewable action ('will be imported') before anything happens, and lives in version control. import {} (Terraform 1.5+) is the modern preferred approach.","demo04,import,import-block"
"What are the two required arguments inside an import {} block?","to (the resource address to import into, e.g. aws_s3_bucket.legacy) and id (the import ID — format depends on resource type; for S3 buckets, the bucket name).","demo04,import-block"
"After an import {} block successfully imports a resource, should it stay in the .tf file?","No, it can be removed — it has no ongoing effect once the import is complete. Leaving it in is harmless (subsequent applies just re-confirm the resource is already imported), but removing it keeps the configuration clean.","demo04,import-block"
"You rename a resource in .tf from aws_s3_bucket.app to aws_s3_bucket.uploads with no other action. What does terraform plan show?","Plan: 1 to add, 0 to change, 1 to destroy. Terraform has no way to know this is a rename — comparing state (still says .app) against new config (says .uploads) looks identical to deleting the old resource and creating a new one.","demo04,state-mv,rename"
"What command prevents a resource rename from destroying and recreating the real infrastructure, and what does it actually edit?","terraform state mv <old-address> <new-address>. It edits ONLY Terraform's state — never the real AWS infrastructure, and never the .tf files. You must still manually rename the resource block in .tf to match; state mv just keeps state in sync with that rename.","demo04,state-mv"
"Besides simple renames, what is another common use case for terraform state mv?","Moving a resource into or out of a module (changing its address from aws_s3_bucket.app to module.storage.aws_s3_bucket.app or vice versa) without destroying/recreating it. Also used for restructuring for_each/count keys without recreating every instance.","demo04,state-mv,modules"
"Does terraform state rm delete the resource in AWS?","No — this is the single most commonly misunderstood fact about this command and a frequent exam trap. The resource keeps running in AWS, completely untouched. Only Terraform's state record of it is removed; Terraform simply forgets the resource exists.","demo04,state-rm,ta004"
"After terraform state rm aws_s3_bucket.legacy, the resource block for aws_s3_bucket.legacy still exists in .tf. What does the next terraform plan propose, and why is this risky?","It proposes to CREATE the resource — because state no longer knows it exists. For globally-unique-named resources (like S3 buckets) this is a safe failure (BucketAlreadyExists). For resource types without a uniqueness constraint, running apply here could create a genuine duplicate resource.","demo04,state-rm,risk"
"What is the correct recovery step after a state rm that was meant to be temporary (with intent to re-import)?","Run terraform import (or add an import {} block and apply) to bring the resource back under management — NOT terraform apply, which would attempt to CREATE a new resource rather than re-track the existing one.","demo04,state-rm,import,recovery"
"What does terraform state push actually do — does it merge with the current remote state?","It OVERWRITES the current remote state with the contents of the local file being pushed. It does not merge. Any state changes recorded after the version being pushed are lost from Terraform's record (though the real AWS resources are unaffected either way — only Terraform's belief about them changes).","demo04,state-push,recovery"
"After restoring an older state version with terraform state push, what should you run immediately, and why?","terraform plan -refresh-only. The push only changes what Terraform believes — it doesn't verify whether the restored state actually matches current real infrastructure. -refresh-only surfaces any gap between the restored state and reality so it can be reconciled.","demo04,state-push,refresh-only"
"What AWS feature, set up in Demo 01, makes restoring a previous state version possible?","S3 bucket versioning on the state bucket. Every terraform apply creates a new version of the state object. A previous version can be downloaded from the Console's 'Show versions' view and restored via terraform state push.","demo04,state,versioning,recovery"
"Does terraform force-unlock verify whether it's safe to unlock before removing the lock?","No. force-unlock simply removes the lock file — it does not check whether an apply is genuinely still running. If a real apply is in progress when you force-unlock, a second apply can now start concurrently, causing the exact state corruption locking exists to prevent.","demo04,force-unlock,ta004"
"Before running terraform force-unlock, what should you check?","The lock error's 'Who' field (shows who/what acquired the lock) — then confirm with that person or check the relevant CI pipeline's status to verify the apply is genuinely stuck and not still legitimately running, before removing the lock.","demo04,force-unlock,recovery"
"What information does the Lock Info shown in an 'Error acquiring the state lock' message include?","ID (the lock ID, needed for force-unlock), Path (state file location), Operation (e.g. OperationTypePlan/Apply), Who (username@hostname that acquired it), Version (Terraform CLI version), Created (timestamp).","demo04,force-unlock,lock-info"
"What is the difference between mode: 'managed' and mode: 'data' in a state file's resources array?","'managed' resources are ones Terraform creates/updates/destroys (normal resource blocks). 'data' resources are data sources — read-only lookups of existing infrastructure that Terraform does not create or manage the lifecycle of, but still records in state for reference.","demo04,state,data-sources"
"In a state file's resources array, what does the 'dependencies' field inside an instance record?","Other resource addresses this specific resource instance depends on — used by Terraform to reconstruct the dependency graph (the same graph terraform graph visualizes) without re-parsing all the .tf files from scratch.","demo04,state,dependencies"
```

## Appendix — Quiz

**04-state-management-quiz.md:**

````markdown
# Quiz — Demo 04: State Management and Backends: Import, Surgery, and Recovery

Test your understanding of this demo's concepts. Each question is a
scenario — choose the best answer, then check yourself against the
explanation.

---

**Q1.** What does `terraform import aws_s3_bucket.legacy
my-bucket-name` actually do?

A. Creates a new S3 bucket named `my-bucket-name` and tracks it in state
B. Adds the existing bucket `my-bucket-name` to Terraform's state, mapped
   to the address `aws_s3_bucket.legacy` — creates nothing in AWS
C. Generates a `.tf` resource block matching the bucket's configuration
D. Copies the bucket's configuration into a new Terraform workspace

<details>
<summary>Answer</summary>

**B.** `import` only adds the resource to state — it creates nothing in
AWS and does not generate `.tf` code (A and C are both wrong for
different reasons). It also has nothing to do with workspaces (D).

</details>

---

**Q2.** After a successful `terraform import`, `terraform plan` shows
several pending changes. What does this indicate?

A. The import failed silently
B. The `.tf` resource block doesn't yet fully match the real resource's
   configuration — more manual refinement is needed
C. The resource needs to be imported again
D. State is corrupted

<details>
<summary>Answer</summary>

**B.** A successful import only means the resource is tracked in state —
it says nothing about whether your `.tf` code matches reality. The
correct response is to keep editing the `.tf` block and re-running
`plan` until it shows zero changes.

</details>

---

**Q3.** What is the main practical advantage of an `import {}` block over
the CLI `terraform import` command?

A. It's faster to type
B. It can import resources of any type, while the CLI form is limited
C. It's reviewable in `terraform plan` before anything happens, and
   lives in version control
D. It doesn't require knowing the resource's import ID

<details>
<summary>Answer</summary>

**C.** The CLI form executes immediately with no preview. The `import {}`
block shows up as a planned action in `terraform plan` first, and being
in a `.tf` file means it's version-controlled and repeatable. Both forms
require the same import ID (D is wrong) and both work with any
resource type that supports import (B is wrong).

</details>

---

**Q4.** Does `terraform state rm aws_s3_bucket.legacy` delete the bucket
in AWS?

A. Yes, immediately
B. Yes, but only after the next `apply`
C. No — the resource is untouched in AWS; only Terraform's state record
   of it is removed
D. It depends on whether `force_destroy` is set

<details>
<summary>Answer</summary>

**C.** This is one of the most commonly misunderstood facts about
`state rm`. The resource keeps running in AWS exactly as it was —
Terraform simply forgets it exists. `force_destroy` (D) is unrelated; it
only affects whether `destroy` can delete a non-empty bucket.

</details>

---

**Q5.** After `terraform state rm` on a resource whose `.tf` block still
exists, what does the next `terraform plan` propose?

A. No changes — Terraform knows the resource still exists in AWS
B. To create the resource — state no longer knows it exists
C. An error, refusing to plan until the resource is re-imported
D. To destroy the resource

<details>
<summary>Answer</summary>

**B.** Since state no longer tracks the resource but the `.tf` block
still declares it, Terraform interprets this as "this resource doesn't
exist yet and needs to be created." For globally-unique-named resources
this fails safely; for others it risks creating a genuine duplicate.

</details>

---

**Q6.** What does `terraform state push terraform.tfstate` do to the
current remote state?

A. Merges the local file's contents with the current remote state
B. Overwrites the current remote state entirely with the local file's
   contents
C. Compares the two and only updates fields that differ
D. Refuses to run unless the local file's serial is higher

<details>
<summary>Answer</summary>

**B.** `state push` is a full overwrite, not a merge. Any remote state
changes recorded after the version being pushed are discarded from
Terraform's record. (Real AWS resources are unaffected by `state push`
either way — only Terraform's belief about them changes.)

</details>

---

**Q7.** Immediately after restoring an old state version with `state
push`, what should you run, and why?

A. `terraform destroy` — to clear any inconsistency
B. `terraform plan -refresh-only` — to check whether the restored state
   matches current real infrastructure
C. Nothing — the restore is complete
D. `terraform force-unlock` — to release any leftover lock

<details>
<summary>Answer</summary>

**B.** The restore only changes what Terraform believes; it doesn't
verify whether that belief matches reality. `-refresh-only` surfaces any
gap so it can be reconciled with a follow-up `apply` if needed.

</details>

---

**Q8.** A teammate sees an "Error acquiring the state lock" message and
immediately runs `terraform force-unlock <ID>` without checking anything
else. What is the risk?

A. None — `force-unlock` always verifies it's safe before unlocking
B. If an apply genuinely is still running, removing the lock allows a
   second apply to start concurrently, risking state corruption
C. `force-unlock` will simply fail if the apply is still running
D. The lock will automatically reappear if needed

<details>
<summary>Answer</summary>

**B.** `force-unlock` does not check whether an apply is actually still
in progress — it simply removes the lock file. If used while a real
apply is running, two applies can now write to state concurrently,
exactly the corruption scenario locking exists to prevent. Always
confirm via the lock's `Who` field first.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 05 |
| 7/8 | Review the wrong answer, then proceed |
| 6/8 | Re-read the relevant section, retry those questions |
| Below 6/8 | Re-read the full demo and redo the walkthrough before proceeding |
````