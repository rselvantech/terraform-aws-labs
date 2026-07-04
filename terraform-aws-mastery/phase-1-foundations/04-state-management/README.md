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

Third, the team wants a recovery playbook ready before anything goes
wrong — not written in a hurry during a real incident.

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
- `terraform show`, `terraform show -json`, and `terraform state show` —
  what each shows and when to use which
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
- Demo 01, 02, and 03 are completed — remote S3 backend with locking,
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

1. ✅ Explain the structure of `terraform.tfstate` — `version`, `serial`,
   `lineage`, `resources`, and `outputs` — and what each field means
2. ✅ Use `terraform show`, `terraform show -json`, and
   `terraform state show` correctly, and explain when to use each
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
    ├── 06-main.tf         # imported S3 bucket resource
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
| `terraform show` | CLI command | Human-readable view of current state (all resources) |
| `terraform show -json` | CLI command | Machine-readable view of current state for scripting/CI |
| `terraform state show <address>` | CLI command | Human-readable detail for one specific resource |
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
| `terraform refresh` | ⚠️ Deprecated — older standalone equivalent of `plan -refresh-only`'s refresh step. Use `-refresh-only` instead. |

> **Deprecation note — `terraform refresh`:** this command is deprecated
> as of Terraform 1.0 and may be removed in a future version. You may
> still encounter it in older runbooks or community articles. Always
> replace with `terraform plan -refresh-only` (which is read-only and
> previews the update before accepting it) or `terraform apply
> -refresh-only` (which updates state to match reality after
> confirmation). Do NOT use `terraform refresh` in new workflows.

---

### Detailed Explanation of New Constructs

---

### `terraform.tfstate` — Internal Structure

State is a JSON file. You've used it indirectly since Demo 00, but never
opened it. Understanding its structure explains what `import`, `mv`, and
`rm` actually edit.

**Top-level fields:**

| Field | Meaning |
|---|---|
| `version` | The **state file format version** — currently `4` for all Terraform versions in active use. This is NOT the Terraform CLI version. It describes the JSON schema of the file itself. Terraform sets this; you cannot control it. |
| `terraform_version` | The Terraform CLI version that last wrote this file — e.g. `"1.15.5"`. Used by Terraform to warn if a newer CLI operates on state written by an older CLI. |
| `serial` | An integer counter. Starts at `1` when state is first created. Incremented by the backend on **every write** — every `apply`, every `import`, every `state mv` or `state push`. Used to detect conflicting writes. |
| `lineage` | A UUID (Universally Unique Identifier) generated **once** when state is first created — never changed afterward. Identifies this state file's permanent family identity. Used to detect if Terraform has been accidentally pointed at an unrelated state file. |
| `outputs` | Current values of all `output` blocks |
| `resources` | An array — one entry per resource block (and data source) Terraform manages |

> **`version: 4` is the current format version.** All Terraform CLI
> versions from 0.14 onward write version 4. You cannot change this
> value — Terraform sets it based on its own internal schema. You will
> almost never see this number change in day-to-day work; it only
> increments when HashiCorp changes the storage format in a breaking way.

> **What is a UUID?** A UUID (Universally Unique Identifier) is a
> 128-bit value formatted as 32 hexadecimal characters in five groups
> separated by dashes — e.g. `e23c8740-3c03-8d66-59d1-4856064c38a4`.
> This is NOT a Terraform-specific concept — it is a general computing
> standard (RFC 4122) used wherever a globally unique, randomly-generated
> identifier is needed without a central authority to assign it. The
> probability of two randomly generated UUIDs colliding is
> astronomically small (roughly 1 in 10³⁶). Terraform generates one
> UUID at state creation time and permanently records it as `lineage` —
> the state file's immutable identity marker.

**Inside each `resources` entry:**

```json
{
  "mode": "managed",
  "type": "aws_s3_bucket",
  "name": "uploads",
  "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
  "instances": [
    {
      "schema_version": 0,
      "attributes": {
        "id": "cloudnova-legacy-uploads-345621678",
        "bucket": "cloudnova-legacy-uploads-345621678",
        "arn": "arn:aws:s3:::cloudnova-legacy-uploads-345621678",
        "region": "us-east-2"
      },
      "dependencies": []
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `mode` | `"managed"` for normal resource blocks; `"data"` for data sources (read-only lookups Terraform does not create or destroy) |
| `type` | The resource type, e.g. `aws_s3_bucket` |
| `name` | The local name from your `.tf` file, e.g. `uploads` (full address: `aws_s3_bucket.uploads`) |
| `instances` | An array — more than one entry only if `count`/`for_each` is used |
| `attributes` | Every attribute Terraform knows about this resource, as returned by the provider's last `Read()` call |
| `dependencies` | Other resource addresses this instance depends on — used by Terraform to reconstruct the dependency graph without re-parsing `.tf` files |

**Inspect it directly:**

```bash
cat terraform.tfstate | jq '.serial, .lineage'
cat terraform.tfstate | jq '.resources[].type'
cat terraform.tfstate | jq '.resources[] | select(.type=="aws_s3_bucket")'
```

> **Why `serial` matters — concurrent write conflict:**
> `plan` never acquires a lock — it only reads state into memory.
> `apply` acquires a lock, writes state (bumping serial), then releases
> the lock.
>
> Sequence where serial fires:
> 1. Engineer A runs `terraform plan` — reads state (serial: 7) into
>    memory. No lock held.
> 2. Engineer B runs `terraform apply` — acquires lock, completes,
>    writes state (serial: 7 → 8), releases lock.
> 3. Engineer A runs `terraform apply` — lock is now free (B released
>    it), so A acquires it successfully. A then tries to write with the
>    serial it read at plan time (7) — but S3 now holds serial: 8.
>    Terraform rejects the write. Engineer A must re-run `plan` to get
>    fresh state before retrying.
>
> Serial is therefore the safety net for the window between `plan` and
> `apply` — locking alone cannot protect this gap because `plan` holds
> no lock. If locking is disabled entirely, serial becomes the only
> guard against two simultaneous writes corrupting state.

> **Why `lineage` matters — accidental `state push` across projects:**
> The word comes from genealogy: lineage means "which family does this
> belong to." Terraform uses it the same way — which configuration
> family does this state file belong to?
>
> Where lineage actually fires as a hard guard is during
> `terraform state push`. Say an engineer is recovering Demo 04's state
> and accidentally pushes Demo 03's downloaded state file into Demo 04's
> S3 path:
>
> ```bash
> # Intended: push a backup of Demo 04's state
> # Actual: wrong file downloaded — this is Demo 03's state
> terraform state push terraform.tfstate
> ```
>
> Terraform compares the `lineage` field in the file being pushed
> against the `lineage` already stored at that S3 path. They differ —
> the two files belong to different project families — and the push is
> rejected before any damage is done.
>
> ⚠️ **What lineage does NOT protect against:** if a developer
> accidentally sets the wrong backend key in `03-backend.tf` and runs
> `terraform plan`, lineage plays no role — Terraform reads whatever
> state is at that S3 path and plans against it. There is no local
> record of the "expected" lineage to compare against at plan time. The
> real protection for that scenario is code review (the key is in a
> version-controlled file) and reading the plan output carefully before
> typing `yes`.

---

### `terraform show` vs. `terraform state show` vs. `terraform show -json`

These three commands are related but distinct. Using the wrong one for a
given task produces incomplete or unstable output.

| Command | Scope | Output format | Stable for scripting? | Best used for |
|---|---|---|---|---|
| `terraform show` | All resources in current state | Human-readable, HCL-like | No — display format only | Quick human inspection of the full state |
| `terraform state show <address>` | One specific resource | Human-readable, HCL-like | No — display format only | Debugging one specific resource's attributes |
| `terraform show -json` | All resources in current state | Structured JSON (documented schema) | Yes | CI pipelines, scripting, external tooling |

```bash
# All resources, human-readable
terraform show

# One resource, human-readable (used in Demo 01)
terraform state show aws_s3_bucket.uploads

# All resources, machine-readable JSON
terraform show -json | jq '.values.root_module.resources[] | {address, type}'
```

> **`show -json` vs. reading `terraform.tfstate` directly:** they
> overlap but are not identical. `terraform.tfstate`'s JSON is the
> **raw storage format** the backend writes — its exact shape is an
> internal implementation detail that can change between Terraform
> versions. `terraform show -json` outputs a **documented, stable JSON
> schema** (see [terraform.io/docs/internals/json-format](https://developer.hashicorp.com/terraform/internals/json-format))
> intended for external tooling to consume reliably. Note that
> `show -json` also adds a `format_version` field (e.g. `"1.0"`) that
> is NOT present in `.tfstate` — this is the schema version of the
> `show -json` output itself, separate from the state file's own
> `version` field. For scripting or CI, always prefer `show -json` over
> parsing `.tfstate` directly.

> **When state is empty:** `terraform show -json` returns
> `{"format_version":"1.0"}` and `.values` is `null` — there are no
> resources yet to report. This is expected when no resources have been
> applied, such as at the start of Part A.

---

### Why State Must Never Be Committed to Git

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

### `terraform import` — Bringing Existing Resources Under Management (CLI form)

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
| `cloudnova-legacy-uploads-xxxxxxxx` | The import ID — for S3 buckets, this is the bucket name (see Import ID Reference table below) |

**What happens after `import` succeeds:** the resource is now in state,
but your `.tf` file's resource block may not yet match its full
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

### `import` Block — Declarative Import (Terraform 1.5+)

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
Plan: 1 to import, 0 to add, 1 to change, 0 to destroy.
```

> **Why does plan show `1 to change` alongside `1 to import`?** The
> import itself is the `1 to import`. The `1 to change` is the
> `tags_all` reconciliation — see the `tags_all` callout below in Part B
> Step 4 for the full explanation. This is expected and correct behavior;
> it is not a sign that the import failed or that the `.tf` block is
> wrong.

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
| Generates resource code for you | No | With `-generate-config-out=FILE`, can scaffold a starting `.tf` block (still requires manual review/cleanup) |

> **Practical recommendation:** prefer `import` blocks for anything
> beyond a one-off ad hoc import — they're reviewable, repeatable, and
> can be removed from the configuration after the import completes
> (the block is only needed for the one `apply` that performs the
> import; it has no ongoing effect once the resource is in state).

---

### Import ID Reference — Common Resource Types

The import ID format is resource-type-specific. These are the types used
across this series:

| Resource type | Import ID format | Example |
|---|---|---|
| `aws_s3_bucket` | Bucket name | `cloudnova-legacy-uploads-345621678` |
| `aws_s3_bucket_versioning` | Bucket name | `cloudnova-legacy-uploads-345621678` |
| `aws_s3_bucket_server_side_encryption_configuration` | Bucket name | `cloudnova-legacy-uploads-345621678` |
| `aws_sns_topic` | Topic ARN | `arn:aws:sns:us-east-2:123456789012:cloudnova-alerts` |
| `aws_sqs_queue` | Queue URL | `https://sqs.us-east-2.amazonaws.com/123456789012/cloudnova-jobs` |
| `aws_iam_policy` | Policy ARN | `arn:aws:iam::123456789012:policy/cloudnova-deploy-policy` |
| `aws_security_group` | Security group ID | `sg-0a1b2c3d4e5f67890` |

> The authoritative source for any resource's import ID format is the
> **Import** section at the bottom of that resource's page in the
> [Terraform AWS provider docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs).
> Always verify there before importing an unfamiliar resource type.

---

### `terraform state mv` — Rename/Move Without Destroy

When you rename a resource in `.tf` code — e.g. `aws_s3_bucket.legacy` to
`aws_s3_bucket.uploads` — Terraform has no way to know this is a rename
rather than "delete the old one, create a new one." Comparing state
(which still says `aws_s3_bucket.legacy`) against the new config (which now
says `aws_s3_bucket.uploads`), a plain `plan` would show:

```
Plan: 1 to add, 0 to change, 1 to destroy.
```

This would destroy and recreate the real bucket — exactly what you don't
want for a rename. `terraform state mv` updates state's record of the
resource's address *without* touching AWS at all:

```bash
terraform state mv aws_s3_bucket.legacy aws_s3_bucket.uploads
```

After this, state says `aws_s3_bucket.uploads` — matching the renamed
`.tf` block — and `terraform plan` shows:

```
No changes. Your infrastructure matches the configuration.
```

**Other common uses of `state mv`:**
- Moving a resource into or out of a module (changing its address from
  `aws_s3_bucket.uploads` to `module.storage.aws_s3_bucket.uploads` or
  vice versa)
- Restructuring `for_each`/`count` keys without recreating every instance

> **`state mv` only edits state — never the `.tf` files.** You must
> still manually rename the resource block in your `.tf` code to match;
> `state mv` just keeps state in sync with that rename so Terraform
> doesn't interpret it as destroy+create.

---

### `terraform state rm` — Untrack Without Destroying

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

### State Corruption and Conflicts — Recovery Strategy

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
# Outputs added in Part B once aws_s3_bucket.uploads exists
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

Expected output (no resources yet):

```json
{
  "version": 4,
  "terraform_version": "1.15.5",
  "serial": 1,
  "lineage": "e23c8740-3c03-8d66-59d1-4856064c38a4",
  "outputs": {},
  "resources": [],
  "check_results": null
}
```

```bash
cat terraform.tfstate | jq '.lineage'
```

Expected output:

```
"e23c8740-3c03-8d66-59d1-4856064c38a4"
# Observation: this UUID was generated once when state was first created
# and will never change for this state file's lifetime — it is the
# permanent identity of this state, regardless of how many applies run.
```

> **Why `resources` is empty:** nothing has been declared in
> `06-main.tf` yet. `serial: 1` reflects the first state write (the
> backend's initial write during `init`). `lineage` was generated at
> that moment and is now permanent. Both `serial` and `resources` will
> change as you proceed through Part B.

---

### Step 5 — `terraform show -json`

```bash
terraform show -json
```

Expected output (no resources applied yet):

```json
{"format_version":"1.0"}
```

```bash
terraform show -json | jq '.values'
```

Expected output:

```
null
# Observation: .values is null because no resources exist in state yet.
# format_version "1.0" is the schema version of the show -json output
# itself — this field is present in show -json output but does NOT
# appear in terraform.tfstate. It is NOT the same as the state file's
# own "version": 4 field.
```

> **Why the output looks minimal here:** `terraform show -json` reflects
> current state, and state currently has no resources. You'll revisit
> both `terraform.tfstate` and `show -json` after Part B's import, once
> there's something real to inspect.

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
  cloudnova-legacy-uploads-<your-account-id>
  (must be globally unique — using your AWS account ID suffix ensures this)

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

Update `06-main.tf` with a minimal resource block:

```hcl
# Resources added in Part B — intentionally empty for now

resource "aws_s3_bucket" "legacy" {
  bucket = "cloudnova-legacy-uploads-xxxxxxxx"   # replace with your actual bucket name
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

Expected output — even after a successful import, plan will show one
pending change:

```
  # aws_s3_bucket.legacy will be updated in-place
  ~ resource "aws_s3_bucket" "legacy" {
        id                          = "cloudnova-legacy-uploads-xxxxxxxx"
        tags                        = {}
      ~ tags_all                    = {
          + "Demo"        = "04-state-management"
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Owner"       = "devops-team"
          + "Project"     = "cloudnova"
        }
        # (14 unchanged attributes hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

> **Why `tags_all` shows a pending change after import:** the bucket was
> created manually before the `default_tags` block existed in
> `02-provider.tf`. Terraform's import reads the bucket's current state
> (no tags), but `default_tags` specifies that every resource should
> have the CloudNova common tags. The `tags_all` attribute is where the
> provider reconciles `default_tags` onto the resource — it shows as a
> pending change because the tags exist in config but not yet on the
> real bucket. This is expected, correct behavior. A clean import is
> always a two-step process: `import` (puts resource in state) followed
> by a normal `apply` (closes the `tags_all` gap). Only after that
> second `apply` does `plan` show zero changes.

```bash
terraform apply
```

Type `yes`. Expected output:

```
aws_s3_bucket.legacy: Modifying... [id=cloudnova-legacy-uploads-xxxxxxxx]
aws_s3_bucket.legacy: Modifications complete after 1s [id=cloudnova-legacy-uploads-xxxxxxxx]

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

```bash
terraform plan
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

> **This confirms the import is complete.** A successful `terraform
> import` put the resource in state — it was this `apply` + `plan`
> sequence that confirmed your `.tf` code now accurately describes the
> real bucket, including its tags.

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
resource block:

```hcl
# Resources added in Part B — intentionally empty for now

import {
  to     = aws_s3_bucket.legacy
  id     = "cloudnova-legacy-uploads-xxxxxxxx"   # replace with your actual name
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
  # aws_s3_bucket.legacy will be imported      # => (imported from "cloudnova-legacy-uploads-xxxxxxxx")
  ~ resource "aws_s3_bucket" "legacy" {
        id     = "cloudnova-legacy-uploads-xxxxxxxx"
        tags   = {}
      ~ tags_all = {
          + "Demo"        = "04-state-management"
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Owner"       = "devops-team"
          + "Project"     = "cloudnova"
        }
        # (14 unchanged attributes hidden)
    }

Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.
```

> **Why `0 to change`  alongside `1 to import`:** 
> No change required beacause in Step 3 — the `tags_all` reconciliation is already done


```bash
terraform apply -auto-approve
```

Expected output:

```
aws_s3_bucket.legacy: Importing... [id=cloudnova-legacy-uploads-xxxxxxxx]
aws_s3_bucket.legacy: Import complete [id=cloudnova-legacy-uploads-xxxxxxxx]
aws_s3_bucket.legacy: Modifying... [id=cloudnova-legacy-uploads-xxxxxxxx]
aws_s3_bucket.legacy: Modifications complete after 1s [id=cloudnova-legacy-uploads-xxxxxxxx]

Apply complete! Resources: 1 imported, 0 added, 1 changed, 0 destroyed.
```

```bash
terraform plan
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

**Now remove the `import` block from `06-main.tf`** — it has no ongoing
effect once the import is complete. `06-main.tf` should now contain only:

```hcl
# Resources added in Part B — intentionally empty for now

resource "aws_s3_bucket" "legacy" {
  bucket = "cloudnova-legacy-uploads-xxxxxxxx"
}
```

---

### Step 5 — Add outputs

With the bucket imported and the `import` block removed, add outputs.

Update `07-outputs.tf`:

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

Type `yes`. Expected output:

```
Changes to Outputs:
  + legacy_bucket_arn  = "arn:aws:s3:::cloudnova-legacy-uploads-xxxxxxxx"
  + legacy_bucket_name = "cloudnova-legacy-uploads-xxxxxxxx"

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

```bash
terraform plan
```

Expected: `No changes. Your infrastructure matches the configuration.`

---

### Step 6 — `terraform state mv` — rename without recreate

CloudNova's naming convention prefers `uploads` over `legacy` going
forward. Before making any changes, confirm the `import {}` block is no
longer in `06-main.tf` — if it is still present, remove it now. The
`import {}` block references `aws_s3_bucket.legacy`, and renaming the
resource while the block is still present causes:

```
Error: Configuration for import target does not exist
  on 06-main.tf line 4, in import:
    4:     to = aws_s3_bucket.legacy
```

**With the import block confirmed absent**, rename in `06-main.tf`:

```hcl
resource "aws_s3_bucket" "uploads" {   # renamed from "legacy"
  bucket = "cloudnova-legacy-uploads-xxxxxxxx"
}
```

Also update `07-outputs.tf` — all references to `aws_s3_bucket.legacy`
must change to `aws_s3_bucket.uploads`:

```hcl
output "legacy_bucket_name" {
  description = "Name of the imported legacy bucket"
  value       = aws_s3_bucket.uploads.bucket   # updated reference
}

output "legacy_bucket_arn" {
  description = "ARN of the imported legacy bucket"
  value       = aws_s3_bucket.uploads.arn      # updated reference
}
```

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
> which `.tf` address it's associated with changed. The bucket name
> in AWS (`cloudnova-legacy-uploads-xxxxxxxx`) is unchanged; only
> Terraform's internal label for it changed from `.legacy` to `.uploads`.

---

### Step 7 — `terraform state rm` — untrack without destroying

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
# terraform apply   # required only to closes the tags_all gap . but here not required
terraform plan    # confirm: No changes
```

Expected final output:

```
No changes. Your infrastructure matches the configuration.
```

---

## Part C — Recovery from Corruption and Conflicts

**What you accomplish in Part C:** add versioning as a managed resource,
simulate a bad state write by accepting drift into state, restore from
S3 versioning, reconcile AWS back to the correct state, and practise
`force-unlock` in a realistic scenario.

---

### Step 1 — Add versioning as a managed resource

> **Why a separate `aws_s3_bucket_versioning` resource is required
> for drift detection:** the `versioning {}` argument inside
> `aws_s3_bucket` is deprecated since AWS provider v4. The official
> docs state: "Terraform will only perform drift detection if a
> configuration value is provided — use the resource
> `aws_s3_bucket_versioning` instead." Without the standalone resource,
> suspending versioning in the Console produces no drift in
> `terraform plan` — Terraform intentionally ignores it because no
> configuration value exists to compare against. The standalone
> `aws_s3_bucket_versioning` resource is what gives Terraform something
> managed to track and detect drift against.

Add this block to `06-main.tf`:

```hcl
resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}
```

```bash
terraform plan
```

Expected output:

```
  # aws_s3_bucket_versioning.uploads will be created
  + resource "aws_s3_bucket_versioning" "uploads" {
      + bucket = "cloudnova-legacy-uploads-xxxxxxxx"
      + id     = (known after apply)
      + region = "us-east-2"

      + versioning_configuration {
          + mfa_delete = (known after apply)
          + status     = "Enabled"
        }
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply
```

Type `yes`. Expected output:

```
aws_s3_bucket_versioning.uploads: Creating...
aws_s3_bucket_versioning.uploads: Creation complete after 1s [id=cloudnova-legacy-uploads-xxxxxxxx]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

```bash
terraform state list
```

Expected — both resources now tracked:

```
aws_s3_bucket.uploads
aws_s3_bucket_versioning.uploads
```

```bash
terraform state show aws_s3_bucket_versioning.uploads
```

Expected output:

```
# aws_s3_bucket_versioning.uploads:
resource "aws_s3_bucket_versioning" "uploads" {
    bucket                = "cloudnova-legacy-uploads-xxxxxxxx"
    expected_bucket_owner = null
    id                    = "cloudnova-legacy-uploads-xxxxxxxx"
    region                = "us-east-2"

    versioning_configuration {
        mfa_delete = null
        status     = "Enabled"
    }
}
```

```bash
terraform plan -refresh-only
```

Expected: `No changes. Your infrastructure still matches the configuration.`

This is the clean baseline — both resources in state, both matching AWS.

---

### Step 2 — Capture a known-good state version

```
Console → S3 → state bucket → phase-1/04-state-management/terraform.tfstate
  → Show versions toggle (top right of the Objects tab)
  → Note the timestamp of the current (latest) version — this is your
    known-good baseline. Every terraform apply creates a new version here;
    you now have one version per serial number written to this path.
```

---

### Step 3 — Simulate drift: suspend versioning outside Terraform

```
Console → S3 → cloudnova-legacy-uploads-xxxxxxxx   ← the uploads bucket,
                                                       NOT the state bucket
  → Properties tab → Bucket Versioning → Edit
  → Select "Suspend" → Save changes
```

```bash
terraform plan -refresh-only
```

Expected output — Terraform detects the change on both resources
simultaneously. `aws_s3_bucket_versioning.uploads` is the managed
resource. `aws_s3_bucket.uploads` also shows the same drift because
Terraform's refresh reads the live versioning attribute on the bucket
itself, even though the deprecated `versioning {}` block is not in
your `.tf` config:

```
Note: Objects have changed outside of Terraform

  # aws_s3_bucket.uploads has changed
  ~ resource "aws_s3_bucket" "uploads" {
        id   = "cloudnova-legacy-uploads-xxxxxxxx"
        tags = {}
        # (15 unchanged attributes hidden)

      ~ versioning {
          ~ enabled = true -> false
            # (1 unchanged attribute hidden)
        }

        # (2 unchanged blocks hidden)
    }

  # aws_s3_bucket_versioning.uploads has changed
  ~ resource "aws_s3_bucket_versioning" "uploads" {
        id = "cloudnova-legacy-uploads-xxxxxxxx"
        # (3 unchanged attributes hidden)

      ~ versioning_configuration {
          ~ status = "Enabled" -> "Suspended"
            # (1 unchanged attribute hidden)
        }
    }
```

> **Why two resources show drift for one Console change:**
> Suspending versioning in the Console is one AWS API call — but
> Terraform refreshes every tracked resource independently.
> `aws_s3_bucket.uploads` reads the bucket's versioning attribute
> during its own refresh (even though the deprecated `versioning {}`
> block is not in your `.tf` config — the provider still reads it
> during refresh). `aws_s3_bucket_versioning.uploads` reads the same
> underlying fact via its own API call. Both reflect the same change.
> `aws_s3_bucket_versioning.uploads` is the resource Terraform will
> use to correct the drift when you run `apply`.

---

### Step 4 — Simulate a bad write: accept the drift into state

This is the "mistake" step — simulating what happens when someone runs
`apply -refresh-only` during an incident to "accept" drift that should
have been corrected instead:

```bash
terraform apply -refresh-only
```

Expected output — shows the same two-resource drift, then prompts:

```
Would you like to update the Terraform state to reflect these detected changes?
  Terraform will write these changes to the state without modifying any real infrastructure.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

State has now accepted the bad value. Confirm:

```bash
terraform state show aws_s3_bucket_versioning.uploads
```

Expected — state now says `Suspended`:

```
# aws_s3_bucket_versioning.uploads:
resource "aws_s3_bucket_versioning" "uploads" {
    bucket = "cloudnova-legacy-uploads-xxxxxxxx"
    id     = "cloudnova-legacy-uploads-xxxxxxxx"
    region = "us-east-2"

    versioning_configuration {
        mfa_delete = null
        status     = "Suspended"
    }
}
```

```bash
terraform plan
```

Expected — state says `Suspended`, `.tf` says `Enabled`, so Terraform
now plans to correct it:

```
  # aws_s3_bucket_versioning.uploads will be updated in-place
  ~ resource "aws_s3_bucket_versioning" "uploads" {
      ~ versioning_configuration {
          ~ status = "Suspended" -> "Enabled"
        }
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

> At this point we have a bad state (accepts `Suspended`) and the `.tf`
> config still correctly says `Enabled`. We could simply run `apply`
> here to fix both AWS and state in one step — but the purpose of this
> exercise is to practise the state restore path. We will restore the
> known-good state version from S3 instead, then reconcile.

---

### Step 5 — Restore the known-good state version

```
Console → S3 → state bucket → phase-1/04-state-management/terraform.tfstate
  → Show versions toggle
  → Find the version from Step 2 (the timestamp before Step 4's bad write)
  → Select that version → Download
  → Rename the downloaded file to terraform.tfstate in your local
    working directory (NOT overwriting any .tf files)
```

```bash
terraform state push -force terraform.tfstate
```

Expected output:

```
Successfully pushed state to backend "s3"
```

> **Why `-force` is required here:** the backup file downloaded from
> Step 2 has a lower serial number than the backend currently holds
> (which advanced during Steps 1 and 4). Without `-force`, Terraform
> refuses with:
> `"Failed to write state: cannot import state with serial 9 over newer
> state with serial 11"`
> The `-force` flag tells Terraform you intentionally want to push an
> older version — which is exactly what a deliberate state restore is.
> Use `-force` only in deliberate recovery scenarios, never in normal
> operation.

> **`state push` overwrites — it does not merge.** The bad write from
> Step 4 is gone from state. But the real bucket in AWS still has
> versioning `Suspended` — pushing state only changed what Terraform
> believes, not what AWS holds.

---

### Step 6 — Confirm the gap and reconcile

```bash
terraform plan -refresh-only
```

Expected output — restored state says `Enabled`, but AWS still has
`Suspended`. Both resources show the gap again, now in the opposite
direction from Step 3:

```
Note: Objects have changed outside of Terraform

  # aws_s3_bucket.uploads has changed
  ~ resource "aws_s3_bucket" "uploads" {
      ~ versioning {
          ~ enabled = false -> true
        }
    }

  # aws_s3_bucket_versioning.uploads has changed
  ~ resource "aws_s3_bucket_versioning" "uploads" {
      ~ versioning_configuration {
          ~ status = "Suspended" -> "Enabled"
        }
    }
```

This confirms the restore worked — state is back to the known-good
version. AWS still needs reconciling.

```bash
terraform apply
```

Type `yes`. Expected output:

```
aws_s3_bucket_versioning.uploads: Modifying... [id=cloudnova-legacy-uploads-xxxxxxxx]
aws_s3_bucket_versioning.uploads: Modifications complete after 1s [id=cloudnova-legacy-uploads-xxxxxxxx]

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

```bash
terraform plan
```

Expected: `No changes. Your infrastructure matches the configuration.`

> **The full recovery pattern — three distinct steps, always in this
> order:**
> 1. `state push -force` — restores Terraform's *belief* to a
>    known-good point. Does not touch AWS.
> 2. `plan -refresh-only` — reveals the gap between the restored belief
>    and current AWS reality.
> 3. `apply` — closes the gap. AWS and state now agree.
> Skipping step 2 and going straight from restore to `apply` risks
> misreading what actually changed in AWS during the incident window.

---

### Step 7 — `terraform force-unlock` in a realistic scenario

Simulate a stuck lock by interrupting an apply mid-flight (in a real
incident this would be a crashed CI runner or a killed terminal):

```bash
terraform apply
# While it's running (after you see "Refreshing..." or "Modifying..."),
# press Ctrl+C twice to force an immediate exit and leave the lock behind
```

Expected output after double Ctrl+C:

```
Interrupt received.
Please wait for Terraform to exit or data corruption may occur.

Two interrupts received. Exiting immediately.
```

> Pressing Ctrl+C **once** lets Terraform attempt a clean shutdown and
> release the lock. Pressing it **twice** forces an immediate exit and
> deliberately leaves the lock file behind — which is what this exercise
> needs to simulate the stuck-lock scenario.

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
  → In a real scenario: check the "Who" field above and confirm with
    that person or CI system that no apply is genuinely still running
    before proceeding — force-unlock does not validate this for you
```

```bash
terraform force-unlock <the-lock-ID-from-the-error-above>
```

Expected output:

```
Terraform state has been successfully unlocked!
```

```bash
terraform plan
```

Expected: `No changes. Your infrastructure matches the configuration.`

> **Why the interrupted apply didn't corrupt state:** Terraform's state
> writes to S3 are atomic — the backend either writes the complete new
> state object or nothing at all. A mid-apply interrupt leaves the lock
> file stuck but leaves the last successfully written state intact.
> This is why `plan` shows no changes after unlock — the state is clean,
> just locked.

> **The exam trap:** `force-unlock` does not validate whether an apply
> is actually still running — it simply removes the lock file. If used
> while a real apply is in progress, two applies can now write to state
> concurrently, which is exactly the corruption scenario locking exists
> to prevent. Confirm first; unlock second, every time.
---

## Cleanup

```bash
terraform destroy
```

Type `yes`. Expected output:

```
aws_s3_bucket.uploads: Destroying... [id=cloudnova-legacy-uploads-xxxxxxxx]
aws_s3_bucket.uploads: Destruction complete after 2s

Destroy complete! Resources: 1 destroyed.
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
   `version` (state format schema, currently 4), `serial` (write
   counter, bumped on every change), `lineage` (UUID permanent identity),
   `outputs`, and a `resources` array with one entry per managed
   resource, including its real-world attributes and dependencies
2. ✅ `terraform show`, `terraform show -json`, and `terraform state
   show <address>` serve different purposes: human-readable all-state,
   stable-schema machine-readable all-state, and human-readable
   single-resource, respectively — use `show -json` for scripting
3. ✅ State must never be committed to Git — it can contain sensitive
   attributes in plaintext, and even without secrets, it reveals the
   complete shape of your infrastructure; Git also lacks the locking
   that remote backends provide
4. ✅ `terraform import` (CLI) brings an existing resource into state
   immediately, with no preview; the `import` block (Terraform 1.5+) is
   reviewable in `plan` first and is the modern preferred approach
5. ✅ A successful import is not complete until `plan` shows zero changes
   — a `tags_all` pending change after import is expected when
   `default_tags` are configured; close it with `apply` before
   considering the import done
6. ✅ `terraform state mv` renames/moves a resource's address in state
   without touching the real infrastructure — but the `import {}` block
   must be removed first if still present, or the rename causes an error
7. ✅ `terraform state rm` removes a resource from state without
   destroying it in AWS — the resource keeps running, untouched, but
   Terraform forgets it exists; re-import (not `apply`) is the correct
   recovery
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
  manually keep the `.tf` resource block's name in sync; also remove any
  `import {}` block before renaming or it causes a configuration error
- State file top-level fields: `version` (format schema, not CLI
  version), `terraform_version` (CLI version), `serial` (conflict
  detection counter), `lineage` (UUID permanent identity) — know what
  each is used for
- A `tags_all` pending change immediately after import is expected when
  `default_tags` is configured — close it with `apply`, not a re-import
- `terraform state push` **overwrites** remote state — it does not merge
  with what's currently there
- `terraform force-unlock` requires the lock ID shown in the error
  message, and does not itself verify whether unlocking is safe
- `terraform show -json` outputs a stable, documented schema; reading
  `.tfstate` directly parses an internal format that can change between
  versions — prefer `show -json` for any scripting or CI use

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Error: Cannot import non-existent remote object` | The import ID doesn't match any real resource, or wrong region/account | Verify the resource exists with `aws s3api head-bucket` (or the equivalent CLI command for the resource type) before importing |
| `terraform plan` after import shows `tags_all` change | `default_tags` in the provider block are not yet applied to the imported resource | This is expected. Run `terraform apply` to close the gap; `plan` will show zero changes afterward |
| `terraform plan` after import shows many changes beyond `tags_all` | The `.tf` resource block is still minimal/incomplete relative to the real resource's full configuration | Iterate: add missing arguments, `plan`, repeat until zero changes |
| `BucketAlreadyExists` after `state rm` + `apply` | Forgot to re-import; Terraform tried to create a resource that already exists | Use `terraform import` again instead of `apply` |
| `Error: Configuration for import target does not exist` | `import {}` block still present after renaming the resource it references | Remove the `import {}` block first, then rename the resource in `.tf` and run `terraform state mv` |
| `Reference to undeclared resource` in outputs after rename | `07-outputs.tf` still references the old resource label (e.g. `aws_s3_bucket.legacy`) after renaming to `aws_s3_bucket.uploads` | Update ALL references across ALL `.tf` files — not just `06-main.tf` — before running `state mv` |
| `Error: state data in S3 does not have the expected content` | `state push` was attempted with a malformed or unrelated state file | Confirm the file's `lineage` matches the current backend's expected lineage before pushing |
| `Error acquiring the state lock` immediately after a normal (non-crashed) apply | A previous apply genuinely is still running elsewhere (CI, another engineer) | Wait — do not force-unlock without confirming first |
| `No instance found for the given address` on `terraform state show` | The resource address doesn't exist in state — either wrong address or resource was removed | Run `terraform state list` to see the actual tracked addresses, then use the correct address |
| `jq: command not found` | `jq` not installed | Install via `apt install jq` / `brew install jq` (see Prerequisites) |
| `import` block apply fails with "resource already managed" | The resource is already in state from a previous import attempt | Remove the redundant `import` block — the resource is already tracked |

---

## Break-Fix Scenario

### Scenario

A teammate was troubleshooting a state mismatch on the `uploads` bucket
and, in a hurry, ran:

```bash
terraform state rm aws_s3_bucket.uploads
```

intending to re-import it cleanly afterward. They got pulled into a
meeting immediately after and didn't finish. A day later, you're asked
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

Plan: 1 to add, 0 to change, 0 to destroy.
```

Someone on the team says "just run apply, it'll recreate it and we're
back to normal." Is that correct? What should you actually do?

<details>
<summary>Diagnosis and Fix</summary>

**Diagnosis:**

Running `apply` here would be a mistake. The real bucket
`cloudnova-legacy-uploads-xxxxxxxx` still exists in AWS — `state rm`
only removed Terraform's tracking of it, not the bucket itself. Running
`apply` would attempt `CreateBucket` with a name that already exists,
fail with `BucketAlreadyExists`, and stop. In this case that's a safe
failure — S3's global-uniqueness constraint protects you. But for
resource types without such a constraint, this would silently create a
genuine duplicate.

**The correct fix — re-import:**

```bash
terraform import aws_s3_bucket.uploads cloudnova-legacy-uploads-xxxxxxxx
```

Then close the `tags_all` gap:

```bash
terraform apply
```

Then confirm:

```bash
terraform plan
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

**Root cause (process, not code):** `state rm` was used correctly in
isolation (it does exactly what it's documented to do — untrack without
destroying), but the team process around it broke down: removing a
resource from state with the intent to "re-import cleanly afterward"
left a window where anyone unfamiliar with that specific intent could
reasonably (but incorrectly) assume `apply` was the recovery step. The
fix for the pattern: any `state rm` performed as part of a multi-step
recovery should be documented inline (a comment in the PR/ticket, or
even a temporary comment in the `.tf` file) stating explicitly "this
resource is mid-reimport — use `terraform import`, not `apply`, to
restore tracking."

</details>

---

## Interview Prep

**Q1. A teammate says "we should just delete `terraform.tfstate` and let Terraform recreate it from the `.tf` files — that way we know it's clean." What's wrong with this reasoning?**
Deleting state doesn't make Terraform "recreate it from the .tf files" in the sense they mean — state isn't derived from `.tf` files, it's the record of what Terraform has *already built* in AWS. If state is deleted, Terraform has no memory of any existing resource, and the next `plan` would propose creating every resource from scratch — even though they already exist in AWS. For globally-unique-named resources this fails loudly (`BucketAlreadyExists`), which is at least safe, but for most resource types it would either fail with a less obvious error or, worse, actually create duplicates. The correct way to get a "clean" state when you suspect drift or inconsistency is `terraform plan -refresh-only` to diagnose the gap, not deleting state and starting over.

**Q2. Your team needs to split one large Terraform configuration into two smaller ones, each with its own state file. One resource needs to move from the old configuration to the new one. Walk through the safe sequence.**
The safe sequence is: `terraform state rm <address>` in the *old* configuration (untracks the resource there, without touching AWS), then `terraform import <address> <id>` in the *new* configuration (or an `import` block applied via the new config's `plan`/`apply`). At no point does the actual AWS resource get destroyed or recreated — only which state file is tracking it changes. The risky alternative — deleting the resource from the old `.tf` files and adding it to the new ones without the explicit `state rm`/`import` pair — would cause the old configuration's next `apply` to destroy it (since it's no longer declared there) and the new configuration's next `apply` to create a fresh one, which for most resource types means real downtime and, for stateful resources like databases, real data loss.

**Q3. A junior engineer ran `terraform import` on a resource, saw "Import successful!", and immediately moved on to other work, considering the resource fully migrated. What's missing, and why does it matter?**
A successful import only means the resource is now tracked in state — it says nothing about whether the `.tf` configuration block actually matches the resource's real, full configuration. After any import where `default_tags` are configured, `terraform plan` will show a `tags_all` pending change — this is expected and must be closed with `apply`. Beyond that, if the `.tf` resource block was minimal or incomplete, the next `terraform plan` run by anyone on the team — possibly weeks later — would show unexpected changes. Worse, if someone runs `apply` without noticing, Terraform could modify the real resource to match the incomplete configuration. The required follow-up is always: run `plan` immediately after import, run `apply` to close any pending changes (especially `tags_all`), then run `plan` again until it shows zero changes — only then is the import actually complete.

**Q4. Someone on your team suggests committing `terraform.tfstate` to a private Git repo "since it's a private repo anyway, nobody outside the team can see it." Push back on this.**
Even in a fully private repo, this is still a bad practice for several reasons beyond just "secrets might leak to the public." First, state can't be safely shared this way for *team workflow* reasons — Git doesn't provide the locking that prevents two engineers from applying simultaneously and corrupting state, which is the exact problem Demo 01's S3 backend with `use_lockfile` solves. Second, even "private" repos are accessible to every team member with read access, which may be a broader set of people than should see infrastructure-level resource IDs, ARNs, and any sensitive attribute values. Third, Git history is effectively permanent — even if a sensitive value is later removed from a file, it typically remains recoverable from history unless someone does a full history rewrite, which is disruptive and easy to get wrong. The remote backend (S3, in this series) solves the sharing problem correctly: encrypted storage, IAM-controlled access, locking, and versioning, without any of Git's drawbacks for this use case.

**Q5. A teammate force-unlocked state during an incident, and it turned out an apply genuinely was still running elsewhere. What likely happened as a result, and how should the team change its process to prevent a repeat?**
With the lock removed while a real apply was in progress, a second `apply` (or the same person retrying) could start concurrently — both reading the same starting state, both eventually writing their results, with the second write overwriting the first. The practical result: whichever apply's resources were created or modified by the *first* operation may now be missing from state (even though they exist in AWS), because the *second* apply's write didn't know about them. The process fix: before any `force-unlock`, require a positive confirmation step — checking the lock's `Who` field and actually contacting that person or checking CI pipeline status — rather than treating "I got a lock error" as sufficient evidence that the lock is stale. Document this as a required step, not an optional courtesy, since `force-unlock` itself doesn't validate safety and will happily remove an active lock if asked.

---

## Key Takeaways

1. **State is a record of reality, not derived from `.tf` files.**
   Deleting or mishandling state doesn't reset infrastructure to a clean
   slate — it just makes Terraform forget what it already built, which
   leads to failed or duplicate creates on the next apply.

2. **A successful `terraform import` is the start of the work, not the
   end.** The resource is tracked, but `tags_all` will show as a pending
   change when `default_tags` are configured — close it with `apply`,
   then confirm `plan` shows zero changes before considering the import
   complete.

3. **`import` blocks are reviewable; the CLI form is not.** Prefer
   `import` blocks for anything beyond a one-off, since they show up in
   `plan` before anything happens and live in version control.

4. **`state mv` and `state rm` only edit state — never the real
   infrastructure, and never `.tf` files.** Renames require both a
   `.tf` edit and a `state mv` to stay in sync; removing a resource from
   state never destroys it in AWS.

5. **Before any `state mv` rename, confirm the `import {}` block is
   removed.** If the block still references the old resource label when
   you rename, Terraform errors with "Configuration for import target
   does not exist" — remove the block first, then rename, then `state mv`.

6. **When renaming a resource, update ALL references in ALL `.tf` files.**
   Renaming `aws_s3_bucket.legacy` to `aws_s3_bucket.uploads` in
   `06-main.tf` but leaving the old label in `07-outputs.tf` causes a
   "Reference to undeclared resource" error on the next plan.

7. **`state rm` followed by `apply` is not a safe substitute for
   re-importing.** Whether it "accidentally works" depends entirely on
   whether the resource type has a uniqueness constraint that happens to
   block accidental recreation — never rely on this.

8. **Restoring state from versioning changes what Terraform believes,
   not what's actually deployed.** Always follow a state restore with
   `plan -refresh-only` to check whether the restored state and real
   infrastructure agree.

9. **`force-unlock` does not verify safety — confirmation is a manual,
   required step.** Check the lock's `Who` field and confirm with that
   person or system before unlocking, every time.

10. **State must never be committed to Git, even to a private repo.**
    Beyond potential secrets, Git lacks the locking remote backends
    provide, and history is effectively permanent even after a file is
    removed.

> **Demo scope:** Primary concept: Terraform state — internal structure,
> import, surgical manipulation (mv/rm), and recovery. Supporting
> concepts: `import {}` block declarative syntax, `tags_all` default_tags
> reconciliation, S3 versioning for state recovery, lock management.
> Estimated completion time: 45 minutes (reading + hands-on + verification).
> Checkpoints: 3 natural stopping points (end of Part A, end of Part B
> Step 4, end of Part B Step 5).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform init` | Downloads provider plugins and initialises the backend |
| `jq '<FILTER>' <FILE>` | Queries a JSON file (state, `show -json` output) using a jq filter expression |
| `terraform state pull` | Outputs the current remote state as JSON to stdout |
| `terraform show` | Outputs the entire current state in human-readable form |
| `terraform show -json` | Outputs the entire current state in the stable, documented JSON schema — use for scripting/CI |
| `terraform state show <ADDRESS>` | Shows full state details for one specific resource in human-readable form |
| `terraform import <ADDRESS> <ID>` | Adds an existing AWS resource to state at the given address, immediately, with no preview |
| `terraform plan` | Previews changes, including any pending `import {}` blocks |
| `terraform apply` | Applies pending changes, including any pending imports, after confirmation |
| `terraform state rm <ADDRESS>` | Removes a resource from state without destroying it in AWS |
| `terraform state mv <OLD_ADDRESS> <NEW_ADDRESS>` | Renames or moves a resource's address in state without touching AWS |
| `terraform state list` | Lists every resource address currently tracked in state |
| `aws s3api head-bucket --bucket <NAME> --profile <PROFILE>` | Confirms a bucket still exists in AWS, independent of Terraform state |
| `terraform state push <FILE>` | Overwrites remote state with the contents of a local state file — does not merge |
| `terraform force-unlock <LOCK_ID>` | Removes a stuck state lock — only after confirming no apply is genuinely running |
| `terraform destroy` | Destroys all resources managed by this configuration |

---

## Next Demo

**Demo 05 — Variables, Locals, Outputs:** A deeper look at input
variable types and validation, locals for computed values, output
formatting and sensitivity, and the difference between `terraform_remote_state`
and direct module outputs for sharing values across configurations.

---

## Appendix — Anki Cards

**04-state-management-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::04-state-management
#separator:Comma
#columns:Front,Back,Tags
"What are the six top-level fields in terraform.tfstate's JSON structure?","version (state file FORMAT schema version — currently 4, NOT the CLI version), terraform_version (CLI version that last wrote the file), serial (integer counter bumped on every write), lineage (UUID generated once at state creation — permanent identity), outputs (current output values), resources (array of managed/data resources).","demo04,state,structure"
"What is the state file format version field — and what is version 4?","The 'version' field in terraform.tfstate describes the JSON schema of the state file itself — NOT the Terraform CLI version. Version 4 is the current format used by all Terraform CLI versions from 0.14 onward. You cannot control this value; Terraform sets it. It only increments when HashiCorp changes the storage format in a breaking way.","demo04,state,version"
"What is the difference between state's serial and lineage fields?","serial is an integer counter incremented by the backend on every write (every apply, import, state mv, state push) — used to detect conflicting writes. lineage is a UUID generated once when state is first created and never changed — used to detect if Terraform has been pointed at a completely different project's state file by mistake (identity check, not ordering).","demo04,state,structure"
"What is a UUID, and why does Terraform use one for lineage?","A UUID (Universally Unique Identifier) is a general computing standard (RFC 4122) — not Terraform-specific. It is a 128-bit value formatted as 32 hex characters in five groups (e.g. e23c8740-3c03-8d66-59d1-4856064c38a4). The probability of collision is ~1 in 10^36. Terraform generates one UUID at state creation time and records it as 'lineage' — the permanent identity marker of that state file, used to detect accidental cross-project state confusion.","demo04,state,uuid,lineage"
"What are the three state inspection commands and when do you use each?","terraform show: all resources, human-readable (quick inspection). terraform state show <address>: one specific resource, human-readable (debugging one resource). terraform show -json: all resources, stable documented JSON schema (scripting and CI). Use show -json for any automated tooling — never parse .tfstate directly, as its raw format is an internal implementation detail that can change between Terraform versions.","demo04,state,show-json,ta004"
"What is the difference between terraform show -json output and terraform.tfstate?","terraform.tfstate is the raw storage format the backend writes — its exact JSON shape is an internal implementation detail that can change between Terraform versions. terraform show -json outputs a documented, stable JSON schema (see terraform.io/docs/internals/json-format) intended for external tooling. show -json also adds a 'format_version' field (e.g. '1.0') not present in .tfstate — this is the schema version of the show -json output itself.","demo04,state,show-json"
"Why must terraform.tfstate never be committed to Git, even in a private repo?","Three reasons: (1) State can contain sensitive attributes in plaintext — resource arguments like database passwords appear in cleartext. (2) Git lacks locking — two engineers can apply simultaneously and corrupt state, the exact problem S3 backend with use_lockfile solves. (3) Git history is effectively permanent — even after a file is removed, sensitive values are recoverable from history.","demo04,state,security"
"What does terraform import actually do — does it create anything in AWS?","No. terraform import only adds an existing AWS resource to Terraform's state, mapped to a resource address you specify. It creates nothing in AWS and does not generate .tf code for you — you must already have a resource block whose arguments will eventually need to match the real resource.","demo04,import,state"
"After a successful terraform import, terraform plan shows a tags_all pending change. What causes this and how do you resolve it?","The imported resource was created before default_tags were configured. Terraform's import reads the bucket's current state (no tags), but default_tags specifies that every resource should have the common tags. tags_all is where the provider reconciles default_tags onto the resource. This is expected, correct behavior — resolve it by running terraform apply. Only after that apply does plan show zero changes.","demo04,import,tags-all,fact6"
"What is the key difference between CLI terraform import and an import {} block?","CLI import executes immediately with no preview — you see the result, not a plan. An import {} block is declarative — it shows up in terraform plan as 'will be imported' before anything happens, and lives in version control as a repeatable, reviewable action. import {} (Terraform 1.5+) is the modern preferred approach.","demo04,import,import-block"
"After an import {} block successfully imports a resource, should it stay in the .tf file?","No — remove it after the apply completes. It has no ongoing effect once the import is complete. Leaving it in is harmless, but removing it keeps the configuration clean. Importantly: remove it BEFORE doing any terraform state mv rename, or Terraform will error with 'Configuration for import target does not exist' because the block still references the old resource label.","demo04,import-block"
"You rename a resource in .tf from aws_s3_bucket.legacy to aws_s3_bucket.uploads. What does terraform plan show, and how do you fix it?","Plan: 1 to add, 0 to change, 1 to destroy — Terraform interprets the rename as delete the old resource and create a new one. Fix: run 'terraform state mv aws_s3_bucket.legacy aws_s3_bucket.uploads' to update state's record of the address without touching AWS. After state mv, plan shows no changes. You must also update ALL references in ALL .tf files (not just the resource block) before running state mv.","demo04,state-mv,rename"
"What must you do before running terraform state mv to rename a resource — and what error occurs if you skip it?","Remove any import {} block that still references the old resource label. If the block is still present when you rename the resource block and run plan, Terraform errors: 'Error: Configuration for import target does not exist — the configuration for the given import target aws_s3_bucket.legacy does not exist.' Remove the block first, then rename, then state mv.","demo04,state-mv,import-block,fact7"
"Does terraform state rm delete the resource in AWS?","No — this is the single most commonly misunderstood fact about this command and a frequent exam trap. The resource keeps running in AWS, completely untouched. Only Terraform's state record of it is removed; Terraform simply forgets the resource exists.","demo04,state-rm,ta004"
"After terraform state rm aws_s3_bucket.uploads, the .tf block still exists. What does the next plan propose, and what is the correct recovery?","Plan proposes to CREATE the resource (Terraform no longer knows it exists). Do NOT run apply — for S3, CreateBucket would fail with BucketAlreadyExists (safe by accident due to S3's uniqueness constraint). For other resource types without a uniqueness constraint, apply could create a genuine duplicate. Correct recovery: run terraform import aws_s3_bucket.uploads <bucket-name>, then terraform apply to close the tags_all gap.","demo04,state-rm,risk,recovery"
"What does terraform state push actually do — does it merge with the current remote state?","It OVERWRITES the current remote state with the contents of the local file being pushed. It does not merge. Any state changes recorded after the version being pushed are lost from Terraform's record (real AWS resources are unaffected — only Terraform's belief about them changes). Always follow with terraform plan -refresh-only to verify the restored state matches reality.","demo04,state-push,recovery"
"What AWS feature, set up in Demo 01, makes restoring a previous state version possible?","S3 bucket versioning on the state bucket. Every terraform apply creates a new version of the state object. A previous version can be downloaded from the Console's 'Show versions' view and restored via terraform state push.","demo04,state,versioning,recovery"
"Does terraform force-unlock verify whether it's safe to unlock before removing the lock?","No. force-unlock simply removes the lock file — it does not check whether an apply is genuinely still running. If a real apply is in progress when you force-unlock, a second apply can start concurrently, causing the exact state corruption locking exists to prevent. Always check the lock's Who field and confirm with that person or CI system first.","demo04,force-unlock,ta004"
"What information does the Lock Info block in an 'Error acquiring the state lock' message include?","ID (the lock ID — required for force-unlock), Path (state file location in the backend), Operation (e.g. OperationTypeApply), Who (username@hostname that acquired the lock — use this to confirm with the owner before unlocking), Version (Terraform CLI version), Created (timestamp).","demo04,force-unlock,lock-info"
"What is the mode field in a state file's resources array, and what are the two valid values?","'managed' for normal resource blocks — resources Terraform creates, updates, and destroys. 'data' for data sources — read-only lookups of existing infrastructure that Terraform does not create or manage the lifecycle of, but still records in state for reference during plan.","demo04,state,data-sources"
"In a state file's resources array, what does the 'dependencies' field inside an instance record?","Other resource addresses this specific resource instance depends on — used by Terraform to reconstruct the dependency graph without re-parsing all .tf files from scratch. This is the same graph terraform graph visualizes.","demo04,state,dependencies"
```

## Appendix — Quiz

**04-state-management-quiz.md:**

````markdown
# Quiz — Demo 04: State Management and Backends: Import, Surgery, and Recovery

> One correct answer per question unless stated otherwise.
> Target: 80% or above before moving to Demo 05.
> TA-004 exam style.

---

**Q1.** What does `terraform import aws_s3_bucket.uploads my-bucket` actually do?

A. Creates a new S3 bucket named `my-bucket` and tracks it in state
B. Adds the existing bucket `my-bucket` to Terraform's state, mapped
   to the address `aws_s3_bucket.uploads` — creates nothing in AWS
C. Generates a `.tf` resource block matching the bucket's current configuration
D. Copies the bucket's configuration into a new Terraform workspace

<details>
<summary>Answer</summary>

**B.** `import` only adds the resource to state — it creates nothing in
AWS and does not generate `.tf` code (A and C are both wrong for
different reasons). It also has nothing to do with workspaces (D).

</details>

---

**Q2.** After a successful `terraform import`, `terraform plan` shows a
`tags_all` pending change. What does this indicate, and what should you do?

A. The import failed silently — re-run import
B. The `.tf` block is incomplete — add more arguments until plan is clean
C. This is expected when `default_tags` are configured — run `terraform apply` to close the gap, then confirm plan shows zero changes
D. State is corrupted — restore from S3 versioning

<details>
<summary>Answer</summary>

**C.** A `tags_all` change after import is expected behavior when
`default_tags` are configured in the provider block. The import reads
the resource's current state (no tags), but `default_tags` specifies
that all resources should have the common tags. Running `apply` closes
this gap. Only after that apply does `plan` show zero changes and the
import is truly complete.

</details>

---

**Q3.** What is the main practical advantage of an `import {}` block over
the CLI `terraform import` command?

A. It's faster to type
B. It can import resources of any type, while the CLI form is limited
   to a subset of resource types
C. It is reviewable in `terraform plan` before anything happens, and
   lives in version control as a repeatable, auditable action
D. It doesn't require knowing the resource's import ID

<details>
<summary>Answer</summary>

**C.** The CLI form executes immediately with no preview. The `import {}`
block shows up as a planned action in `terraform plan` first, and being
in a `.tf` file means it's version-controlled and repeatable. Both forms
require the same import ID (D is wrong) and both work with any resource
type that supports import (B is wrong).

</details>

---

**Q4.** Does `terraform state rm aws_s3_bucket.uploads` delete the bucket
in AWS?

A. Yes, immediately
B. Yes, but only after the next `apply`
C. No — the resource is untouched in AWS; only Terraform's state record
   of it is removed
D. It depends on whether `force_destroy` is set to `true`

<details>
<summary>Answer</summary>

**C.** This is one of the most commonly misunderstood facts about
`state rm`. The resource keeps running in AWS exactly as it was —
Terraform simply forgets it exists. `force_destroy` (D) is unrelated; it
only affects whether `destroy` can delete a non-empty S3 bucket.

</details>

---

**Q5.** After `terraform state rm` on a resource whose `.tf` block still
exists, what does the next `terraform plan` propose, and what is the
correct recovery action?

A. No changes — Terraform detects the resource still exists in AWS and re-tracks it automatically
B. To create the resource — state no longer knows it exists. Correct recovery: run `terraform import`, not `terraform apply`
C. An error, refusing to plan until the resource is explicitly re-imported
D. To destroy the resource

<details>
<summary>Answer</summary>

**B.** Since state no longer tracks the resource but the `.tf` block
still declares it, Terraform interprets this as "this resource doesn't
exist yet and needs to be created." For S3 buckets this fails safely
(`BucketAlreadyExists`); for other resource types it risks creating a
genuine duplicate. The correct recovery is `terraform import` to re-track
the existing resource — not `terraform apply`.

</details>

---

**Q6.** You rename `aws_s3_bucket.legacy` to `aws_s3_bucket.uploads` in
`06-main.tf` but the `import {}` block from Part B is still in the file.
You then run `terraform plan`. What happens?

A. Plan shows no changes — Terraform resolves the rename automatically
B. Plan shows destroy + create for the bucket
C. Error: "Configuration for import target does not exist" — the `import {}` block still references `aws_s3_bucket.legacy`
D. Plan shows the import running again

<details>
<summary>Answer</summary>

**C.** The `import {}` block references `to = aws_s3_bucket.legacy`,
but you renamed the resource block to `aws_s3_bucket.uploads`. Terraform
cannot find the import target's configuration. Fix: remove the `import {}`
block first, then rename, then run `terraform state mv`.

</details>

---

**Q7.** What does `terraform state push terraform.tfstate` do to the
current remote state?

A. Merges the local file's contents with the current remote state
B. Overwrites the current remote state entirely with the local file's
   contents — does not merge
C. Compares the two and only updates fields that differ
D. Refuses to run unless the local file's `serial` is higher than the
   remote state's current `serial`

<details>
<summary>Answer</summary>

**B.** `state push` is a full overwrite, not a merge. Any remote state
changes recorded after the version being pushed are discarded from
Terraform's record. Real AWS resources are unaffected — only Terraform's
belief about them changes. Always follow with `plan -refresh-only` to
check whether the restored state matches reality.

</details>

---

**Q8.** A teammate sees an "Error acquiring the state lock" message and
immediately runs `terraform force-unlock <ID>` without checking anything
else. What is the risk?

A. None — `force-unlock` validates it's safe before removing the lock
B. If an apply genuinely is still running, removing the lock allows a
   second apply to start concurrently, risking state corruption
C. `force-unlock` will simply fail if the apply is still running —
   Terraform detects this automatically
D. The lock will automatically reappear if the running apply detects
   it was removed

<details>
<summary>Answer</summary>

**B.** `force-unlock` does not check whether an apply is actually still
in progress — it simply removes the lock file. If used while a real
apply is running, two applies can now write to state concurrently,
exactly the corruption scenario locking exists to prevent. Always
check the lock's `Who` field and confirm with that person or system
first.

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