# Demo 22c — ECR/ACM Re-Creation: New Objects for a Persistent Environment

---

## Overview

22a gave the persistent build its state backend; 22b gave it its cost
and configuration guardrails. Before 22d's EKS cluster can deploy
anything, it needs two things to already exist: a container registry
holding `retail-store-sample-app`'s images, and a validated TLS
certificate ready to bind to the ALB that's about to be created. Both
were already taught — Demo 19 built the ECR repo, Demo 20 built the
ACM cert — but both of those were teaching reps, torn down at their
own Cleanup. This demo builds new ones, meant to stay.

Both belong in `platform/` — the created-once, never-torn-down half of
the persistent build. 22d's VPC and cluster will live in `workloads/`,
a structurally separate state that can be destroyed every session
without ever being able to reach what this demo builds.

**Real-world scenario — CloudNova:**
The images and certificate your Demo 19/20 exercises created are
already gone — that was always the plan for a teaching rep. Now that
you're standing up a real, ongoing environment, you need a registry
and a certificate that won't disappear the moment the demo ends. The
technique is identical to what you already know; what's different is
the object's intended lifetime.

**What this demo builds:**
```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Bring 22b's finished config into this demo's directory       │
│  This demo's own directory must declare everything 22b applied before  │
│  ecr or acm files can be added — that's what makes it point at the     │
│  real, shared, already-populated platform state, not an empty one      │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — ECR: repo re-creation + image re-push                        │
│  New repos, all 5 services, images pulled from the public gallery      │
│  and re-pushed — same technique as Demo 19, a new, persistent object   │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — ACM: cert re-request + re-validation                         │
│  New certificate on app.rselvantech.com, validated against the         │
│  STANDING Route53 hosted zone (never torn down) via a data lookup,     │
│  not a resource                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- Why every `platform/`-tier demo's own directory has to contain the
  entire accumulated configuration before adding anything new — this
  is one continuously-growing shared state, not a series of independent
  per-demo environments, and a partially-copied config is a real, not
  just theoretical, risk to resources prior demos already applied
- Why re-creating an already-taught resource for a new, persistent
  purpose isn't duplicated effort — teaching rep versus persistent
  object are different lifecycles for the same technique
- `data "aws_route53_zone"` — a read-only lookup against
  infrastructure this project's Terraform never creates or destroys
- Why this new ACM cert validates against the same standing hosted
  zone Demo 20's (now-gone) cert did, without recreating the zone itself
- What protects these two resources from an accidental destroy — and
  why it is the state boundary, not `prevent_destroy`
- Why this demo's module version pins match Demo 19/20's exactly,
  rather than drifting to older constraints for no stated reason

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** five new ECR repositories (one per
`retail-store-sample-app` service) with their images re-pushed, and one
new ACM certificate validated against `rselvantech.com`'s hosted zone.
Neither touches compute — 22d is where the ECR images actually get
pulled into a running Deployment, and where the ALB gets created for
the cert to bind to.

**Why this demo's own directory has to start with 22b's entire
configuration, not just two new files.** Every `platform/`-tier demo —
22b, 22c, and later Demo 24, 27, 28 and 28a — writes into one
continuously-growing state, `platform/terraform.tfstate`. That only
works if whichever directory you're actually running `terraform`
commands from contains the *complete*, accumulated set of `.tf` files
every prior platform demo added — not just the new ones this demo
introduces. Terraform reconciles the real, already-applied state
against whatever `.tf` files are physically present in the current
directory: anything tracked in state but **missing** from the local
files gets proposed for **destruction** on the next `plan`, not
silently ignored. A fresh directory containing only the ECR and ACM
files can't even reach that state to begin with (no backend file means
no way to load it) — but a directory that carries *some* of 22b's
files and not others is the genuinely dangerous middle ground, since
it's the one that *can* load real, existing state while declaring an
incomplete picture of what should still exist in it.

**Why Part A copies 22b's files instead of retyping them.** An earlier
form of this demo listed 22b's files in full and asked you to retype
them. That listing went stale the moment 22b changed — new file
names, a new state key, a new tag, a customer-managed key and a Lambda
— and a stale baseline is exactly the partial-recreation risk above,
built into the instructions. Copying 22b's finished folder can't drift
from 22b, so this demo copies it and then *proves* the copy with a
clean `plan`.

**Why `workloads/` is not part of this.** 22d's VPC and EKS cluster
write to `workloads/terraform.tfstate`, a separate key in the same
bucket, from a separate directory. A `terraform destroy` run there
structurally cannot reach anything in this demo's state — and 22d will
not recreate this demo's files; it reads what it needs (the
certificate's ARN, later IAM role ARNs) from this state's outputs via
`terraform_remote_state`, the technique Demo 07 taught.

**Why this demo reads the Route53 zone instead of creating it:** the
hosted zone itself was created once, before Demo 20's first build, and
is explicitly excluded from every teardown cycle in this project —
recreating it would mean re-pointing the domain registrar's nameservers
every single time, which never happens in practice. This demo's ACM
cert needs the zone's ID to write its DNS validation record, so it
reads that ID with `data "aws_route53_zone"` rather than managing the
zone as a `resource`.

**Why this demo has no Cleanup that tears anything down:** same
reasoning as 22a/22b — these are near-free, foundational resources
meant to persist for the life of the project, re-created once here and
then left standing for every subsequent Phase 3+ demo to use.

---

## Prerequisites

### Knowledge
- Demo 19 completed — `terraform-aws-modules/ecr/aws`, public gallery
  image pull/push mechanics
- Demo 20 completed — `terraform-aws-modules/acm/aws`, DNS validation,
  why the hosted zone itself is a standing exception to teardown
- 22a/22b completed — this demo's state lives in 22a's backend, under
  the `platform/` key. **22b must be completed through Part D**: this
  demo's Part A copies 22b's *final* configuration, and its clean-`plan`
  check only holds if what 22b applied matches what it now declares
  (see the outcomes callouts in Step 3)
- Demo 08 completed — `data` blocks, the basis for this demo's zone
  lookup

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | `~> 1.15.0` | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version` |
| Docker | Any recent | `docker --version` |
| `jq` | Any recent | `jq --version` |
| `tflint` / `checkov` | As installed in 22b | `tflint --version` / `checkov --version` |

### Verify AWS Account and Permissions

**Step 1 — Confirm your profile works:**

```bash
aws sts get-caller-identity --profile default --region us-east-2
```

**Step 2 — A cheap, harmless dry-run of this demo's actual services:**

```bash
aws ecr describe-repositories --profile default --region us-east-2
# Expected: JSON with repositories array (may be empty)
aws route53 list-hosted-zones --profile default
# Expected: JSON with HostedZones array, including rselvantech.com
```

**Step 3 — Verify IAM permissions in Console:**

```
Console → IAM → Users → test → Permissions tab
  → Confirm ECR, ACM, and Route53 access (or an equivalent broad
    policy) is still attached ✅
```

No new IAM permissions beyond Demo 19/20's own ECR/ACM/Route53 sets,
plus `ecr:ListTagsForResource`, `ecr:DescribeImages` and
`acm:DescribeCertificate` for the Cleanup CLI checks.

### Versions used in this demo

| Tool / Module | Version |
|---|---|
| Terraform | `~> 1.15.0` |
| AWS Provider | `~> 6.47.0` |
| `terraform-aws-modules/ecr/aws` | `~> 3.0` (resolved to `3.2.0` in the recorded run) |
| `terraform-aws-modules/acm/aws` | `~> 6.0` |

> **Versions pinned as of September 2026, and deliberately matched to
> Demo 19/20 exactly.** This demo calls the identical two modules
> those demos already taught — there's no reason for the version
> constraints to differ here. If you ever find a demo reusing a module
> at a different version than where that module was first introduced,
> treat the mismatch itself as worth questioning — either there's a
> real reason (documented) or it's a maintenance slip.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain why every `platform/`-tier demo's directory contains the
   entire accumulated configuration before adding anything new, and
   what actually goes wrong if that copy is partial rather than
   complete or entirely absent
2. ✅ Explain why re-creating an already-taught resource for a new,
   persistent purpose isn't redundant with the demo that first taught it
3. ✅ Write a `data "aws_route53_zone"` lookup and use its output in an
   ACM validation record, without ever creating or destroying the zone
4. ✅ Re-push `retail-store-sample-app`'s public images into a new,
   private ECR repo set
5. ✅ Confirm a new ACM certificate reaches `Issued` status against a
   zone this project's Terraform doesn't manage
6. ✅ Explain what protects registry-module resources from an
   accidental destroy, and why `prevent_destroy` can't be that
   protection
7. ✅ Recognize when a module version pin has drifted from an earlier
   demo's own established constraint with no stated reason, and treat
   that as worth questioning rather than assuming it's intentional

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| ECR repos (5, private) | 500 MB-month **total across the account's private repositories**, first 12 months — not 500 MB per individual repo | **$0.00–~small** | `retail-store-sample-app` images are small collectively; likely within the shared free-tier pool, but the pool is one 500 MB allowance shared by all 5 repos, not 500 MB each |
| ACM certificate | Always free for certs used with ALB/CloudFront | **$0.00** | AWS never charges for the certificate itself in this configuration |
| **Session total** | | **~$0.00** | Created once, left standing |

---

## Directory Structure

```
22c-ecr-acm-recreation/
├── README.md
├── 22c-ecr-acm-recreation-anki.csv
├── 22c-ecr-acm-recreation-quiz.md
└── src/
    ├── platform/                       # ADR-023 — same state key as 22b: platform/terraform.tfstate
    │   ├── 01-backend.tf               # ← copied from 22b, Part A
    │   ├── 02-versions.tf              # ← copied from 22b
    │   ├── 03-provider.tf              # ← copied from 22b
    │   ├── 04-variables.tf             # ← copied from 22b
    │   ├── 05-locals.tf                # ← copied from 22b (incl. Tier = platform)
    │   ├── 06-cost-governance.tf       # ← copied from 22b
    │   ├── 07-budgets.tf               # ← copied from 22b
    │   ├── 08-outputs.tf               # ← copied from 22b, then extended in
    │   │                               #   Part B and Part C
    │   │                               #   (repository_urls, certificate_arn)
    │   ├── 09-notify-gate.tf           # ← copied from 22b (Part D of 22b)
    │   ├── lambda/
    │   │   └── session_check.py        # ← copied from 22b
    │   ├── .tflint.hcl                 # ← copied from 22b
    │   ├── .checkov.yaml               # ← copied from 22b
    │   ├── terraform.tfvars            # ← copied from 22b; your real values, gitignored
    │   ├── 10-ecr.tf                   # NEW this demo — 5 ECR repos
    │   └── 11-acm.tf                   # NEW this demo — ACM cert + data lookup
    └── break-fix/
        └── broken.tf                   # one deliberate local-name mismatch
```

> **Numbering continues 22b's.** 22b introduced `01`–`09`; this demo's
> new files are `10` and `11`, rather than restarting at `01`.

> **`04-variables.tf` gets no new content in this demo — `08-outputs.tf`
> does.** Every value the ECR and ACM files need (`repository_name`,
> `domain_name`, `zone_id`) is either a literal string or read directly
> via `data`/`each.key` — there's nothing genuinely variable to
> parameterize. Outputs are different: a real run of this demo showed
> that without a `repository_urls` output there's no way to derive the
> real registry URL Docker needs, which led to a real, reproduced
> failure (see Step 5) — so the outputs file is extended twice, once
> per Part. The outputs also become this state's contract with
> `workloads/`: 22d reads `certificate_arn` from here.

---

## Recall Check — 22b (Cost Governance)

Answer from memory before reading anything new:

1. Why did this project choose notify-only cost controls instead of
   pairing them with auto-remediation?
2. Why can't an EventBridge rule publish to an SNS topic encrypted with
   the AWS managed key `alias/aws/sns` — and which check, run in
   22b, could not see the problem?
3. Are `tflint` and `checkov` Terraform provisioners?

<details>
<summary>Answers</summary>

1. Detection and prevention are different design choices with
   different failure modes. A misfiring auto-remediation Lambda
   destroying real work-in-progress mid-session is worse than the
   cost risk it would solve, for this single-learner lab.
2. AWS requires a topic that EventBridge publishes to, if encrypted, to
   use a customer-managed KMS key. `checkov`'s `CKV_AWS_26` only
   verifies that *a* key is set, not which kind, so it passes either
   way — and so do `apply` and the Console. 22b's Part D replaces the
   key.
3. No — both are external CLI tools that read `.tf` files directly
   off disk, running entirely outside the `plan`/`apply` cycle. They
   are not Terraform resources or provisioners.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| Carrying an accumulated multi-demo configuration into a new directory verbatim | Applied workflow discipline, not a new construct | The same baseline-first pattern Demo 06 established for a single prior demo, now applied to a whole tier's accumulated config |
| `data "aws_route53_zone"` | Data source | Reads the existing, standing hosted zone's ID — this project's Terraform never creates or destroys the zone itself |
| ECR repo re-creation (module reuse) | Applied pattern, not a new construct | Same `terraform-aws-modules/ecr/aws` module Demo 19 taught, applied to a new, persistent set of repos |
| `repository_force_delete` | Module input | Lets a repository that holds pushed images be destroyed and recreated at all |
| ACM cert re-request (module reuse) | Applied pattern, not a new construct | Same `terraform-aws-modules/acm/aws` module Demo 20 taught, applied to a new, persistent certificate |

---

### Detailed Explanation of New Constructs

#### Why Carrying the Baseline Is Mandatory Here, Not Optional Tidiness

Demo 06 recreated Demo 05's finished IAM role as an isolated teaching
rep's own starting point — useful for continuity, but if a reader had
skipped that step, nothing outside that one demo's own state would
have been affected. **This demo's situation is different in a way
worth being precise about:** every `platform/`-tier demo shares one
state file, at one S3 key, for the entire persistent build. Skip
Part A entirely and start writing ECR files in an empty directory, and
`terraform init` simply fails — there's no backend file to even locate
the shared state, so nothing gets touched. That failure is safe, if
unhelpful. **The real risk is a partial copy** — say, the backend and
provider files brought over, but the cost-governance files left out.
That directory *can* reach the real, already-applied state (the
backend config is complete enough for `init` to succeed), but its
local `.tf` files no longer declare 22b's SNS topic, EventBridge rule,
Lambda, key or Budget — so the next `plan` proposes destroying all of
them, not because anything about those resources changed, but because
Terraform has no way to know they're still wanted if nothing local
says so.

---

#### `data "aws_route53_zone"` — Reading Infrastructure You Don't Manage

| Argument | Required | Description |
|---|---|---|
| `name` | Optional* | The domain name to look up — `rselvantech.com` here |
| `private_zone` | Optional (default: `false`) | `false` for a standard public hosted zone, which this is |

> **\*`name` and `zone_id` are each individually optional, but
> mutually exclusive** — per the official argument reference, you
> identify the zone with one or the other, never both together, and
> whichever filter you supply must match exactly one hosted zone.
> This demo uses `name`; `zone_id` isn't used here.

```hcl
data "aws_route53_zone" "main" {
  name         = "rselvantech.com."
  private_zone = false
}
```

This is a `data` block, not a `resource` block — the same distinction
Demo 08 taught for `data.aws_caller_identity` and Demo 10 taught for
`data.aws_vpc`. Terraform reads the zone's current attributes (its ID,
name servers) without ever proposing to create, modify, or destroy it.
The zone's own lifecycle — created once, before this project's
Terraform existed, never touched since — is completely outside this
project's `terraform plan`/`apply` graph.

> **Why this matters for teardown specifically:** if this were a
> `resource "aws_route53_zone"` block instead, `terraform destroy`
> would attempt to delete the hosted zone — exactly the operationally
> absurd outcome (re-pointing registrar nameservers every session) the
> project's design avoids by never managing the zone as a resource at all.

---

#### What Protects These Resources — the State Boundary, Not `prevent_destroy`

The natural instinct for "created once, never torn down" is
`lifecycle { prevent_destroy = true }`. It doesn't work here: Terraform
does not allow a `lifecycle` block on a `module` block at all
(HashiCorp/terraform issue #27360, open), and both the ECR and ACM
resources live inside registry modules. No module version changes
this; it's a language limitation, not a pin.

What protects them instead, and it's worth being exact about the
strength of each:

| Mechanism | What it guarantees |
|---|---|
| The `platform/` vs. `workloads/` state split (ADR-023) | **Structural.** A `terraform destroy` run in `workloads/` — the every-session teardown — cannot reach anything in `platform/`'s state |
| The `Tier = "platform"` tag | A label, not a lock. Lets 22b's cost check and a human tell platform resources from workload resources |
| Your discipline | **Nothing enforces it.** A `terraform destroy` run *inside `platform/`* still destroys these resources, and 22b's, and Demo 24's |

Compare the IAM roles Demo 24 will add to this same tier: those are
native `aws_iam_role` resources, so `prevent_destroy = true` *does*
work on them. "Platform tier" therefore doesn't mean uniformly
protected — ECR and ACM get the weaker, process-level guarantee.

**`repository_force_delete = true` is the companion setting.** An ECR
repository holding pushed images can't be deleted by default, so a
destroy-and-recreate of this repo set would fail. The input exists on
`terraform-aws-modules/ecr/aws` at the `~> 3.0` line this project pins
(confirmed at both `v3.0.0` and `v3.2.0`, the version the recorded run
resolved). It makes the repos *recreatable*; it does not make them
safer to destroy.

---

#### Re-Creating an Already-Taught Resource — Why It's Not Redundant

Demo 19 and Demo 20 already taught you the ECR module and the ACM
module. This demo uses both again, on purpose, producing objects that
happen to look identical to what you already built. The distinction is
lifecycle, not technique:

| | Demo 19/20's objects | This demo's objects |
|---|---|---|
| Purpose | Teach the module, once | Serve the persistent build, indefinitely |
| Torn down at own Cleanup? | Yes, always | No — left standing for the rest of the project |
| Reused by 22d onward? | No — already gone | Yes — this is what 22d's EKS deployment actually pulls images from and binds its ALB to |
| Module version pin | `ecr ~> 3.0` / `acm ~> 6.0` | Same — `ecr ~> 3.0` / `acm ~> 6.0` |

Building this demo's objects *instead of* exempting Demo 19/20's
objects from teardown was itself a real decision (not the only option
considered) — keeping every Phase 1–2 demo's "tears down, no
exceptions" guarantee intact was judged worth the minor cost of a
re-push/re-request here, rather than making Demo 19/20 quietly special
cases. The version pin row above is deliberately included in this
table: reusing the same module a second time is exactly the situation
where a version constraint might accidentally be typed differently
from memory instead of copied.

---

## Lab Step-by-Step Guide

---

## Part A — Bring 22b's Finished Configuration Into This Directory

Part A brings this fresh directory up to the same state 22b left the
`platform/` tier in, before this demo adds anything new — see "Why
Carrying the Baseline Is Mandatory Here" above for why this isn't
optional tidying.

### Step 1 — Navigate to the project config

```bash
cd "terraform-aws-mastery/Phase 3 - Real AWS Infrastructure/22c-ecr-acm-recreation/src/platform"
```

The quotes matter — the phase folder name contains spaces.

### Step 2 — Copy 22b's finished configuration, verbatim

This step copies every file 22b's Lab produced, exactly as that demo
left it — no edits. It deliberately leaves behind what shouldn't be
copied: the `.terraform/` working directory (rebuilt by `init`) and the
generated Lambda zip (rebuilt by `plan`).

```bash
tar -C ../../../22b-cost-governance/src/platform \
    --exclude='.terraform' --exclude='*.zip' -cf - . | tar -xf -
ls -A
```

> ⚠️ [VERIFY — the copy command and the listing below have not been run
> in a 22c directory yet.] Expected: `01-backend.tf` through
> `09-notify-gate.tf`, `lambda/`, `.tflint.hcl`, `.checkov.yaml`,
> `.terraform.lock.hcl` and your `terraform.tfvars` — 22b's whole
> folder, and nothing else.

**What this copies, and why each piece is needed:**

| File | Why 22c needs it |
|---|---|
| `01-backend.tf` | Points at `platform/terraform.tfstate` in 22a's bucket — how this directory reaches the real state at all |
| `02-versions.tf`, `03-provider.tf` | Provider pins, region, and `default_tags` (which is what puts `Tier = platform` on this demo's new resources too) |
| `04-variables.tf`, `05-locals.tf` | Inputs and the shared tag set |
| `06-cost-governance.tf`, `07-budgets.tf`, `09-notify-gate.tf`, `lambda/` | 22b's applied resources — the ones a partial copy would propose destroying |
| `08-outputs.tf` | Extended twice by this demo |
| `.tflint.hcl`, `.checkov.yaml` | The static-analysis config this demo's pre-apply checks use |
| `terraform.tfvars` | Your real values — required, see below |

> ⚠️ **Warning**
>
> **`terraform.tfvars` is required, not optional, despite not being part
> of this demo's own new content.** `notification_email` and
> `monthly_budget_limit` have no defaults — without it,
> `init`/`plan`/`apply` will either fail or prompt for these values
> interactively every time. It comes across with the copy; if 22b's
> copy of it is missing, recreate it with your own values. It stays
> gitignored.

> ⚠️ **Warning**
>
> Copy 22b's **finished** directory — after its Part D — not a
> half-finished one. This demo's clean-`plan` check in the next step
> compares this directory's files against what 22b actually applied.

### Step 3 — Confirm the copied baseline matches reality before adding anything new

This step is the actual proof Part A worked. On a genuine first pass
through this demo, `plan` here should report **zero** changes,
confirming this directory's files now completely and accurately
describe the resources 22b already applied — before Part B adds
anything on top. Other outcomes are possible too, covered in the
callouts below — read whichever one matches what you actually see
before deciding whether to `apply`.

```bash
terraform init
terraform validate
terraform plan
```

Expected — if Part A was carried over correctly, `plan` reports **no
changes**, the same way 22a's own first-time-`init`-against-the-new-
backend check did:

```
No changes. Your infrastructure matches the configuration.
```

> **If `plan` instead proposes destroying any of 22b's resources**
> (the SNS topic, its subscription, the EventBridge rule and target,
> the Lambda gate, the key, or the Budget), **stop here** — this means
> one of the files above wasn't copied correctly, or was left out
> entirely. Fix that before proceeding to Part B; don't `apply` a plan
> that proposes destroying resources you didn't intend to touch.

> **If `plan` proposes *adding* 22b's Part D resources** (the Lambda,
> key, log group, IAM role and cooldown parameter) **and changing the
> topic and event target, with no destroys of anything else:** 22b was
> applied only through Part C, but you copied its finished (Part D)
> configuration. That's not an error in this demo — finish 22b's
> Part D, then re-run this step. Don't apply it from here: Part D
> belongs to 22b's own walkthrough, including its live tests.

> **A third, real outcome, observed in an actual run: `plan` reports a
> full set of adds** — "6 to add" when 22b had been applied through
> Part C only; a full recount (13, ⚠️ [VERIFY]) if 22b had been taken
> through Part D. This happens when 22b's resources no longer exist in
> AWS at all — most commonly because a plain `terraform destroy` was
> run against an earlier, incomplete directory that shared 22b's state
> but never *declared* 22b's resources locally, so the destroy removed
> them along with whatever that directory did declare. **This is safe to
> `apply`** — `0 to destroy` means nothing gets removed, only
> recreated — but two things are worth knowing first: the recreated
> `aws_sns_topic_subscription` will be a genuinely new subscription,
> starting at `PendingConfirmation` again even if the old one was
> already confirmed, so re-click the confirmation email afterward; and
> continue on to Part B/C's own `plan` checks to see whether the same
> thing happened to this demo's own ECR/ACM resources, or whether those
> survived intact.

> **A fourth, real outcome, observed in an actual re-run: `plan`
> proposes destroying 18 resources, every one of them ECR or ACM, with
> 22b's resources not appearing in the plan at all — no destroy, no
> change.** This happens when you're re-running this demo a second time
> in a fresh directory, **after already completing it successfully
> once before** — the shared state still has this demo's own ECR repos
> and ACM certificate from that earlier run, but this fresh directory
> has only reached Part A and hasn't added the ECR/ACM files yet. The
> absence of 22b's resources from the plan is the actual signal here:
> it confirms Part A's copy is correct, and what's being flagged as
> "extra" is only the content Part B/C haven't put back yet. **Do not
> apply this plan** — it's not wrong, it's premature. Continue on to
> Step 4 (`10-ecr.tf`) and Step 7 (`11-acm.tf`); once both are back in
> place, a fresh `plan` will find all 18 resources already match and
> report no changes.

---

## Part B — ECR: Repo Re-Creation + Image Re-Push

Part B re-creates all five ECR repositories using the exact module and
version Demo 19 taught, then re-pushes each service's real image into
the new, persistent repos.

### Step 4 — Add 10-ecr.tf

This step calls the ECR module once, `for_each`'d over all five
services, using the exact same version pin Demo 19 established.

Create a file **10-ecr.tf** and add the below content:

This file contains the single `for_each`'d ECR module call that
produces all five persistent repositories this demo builds.

```hcl
locals {
  services = ["ui", "catalog", "cart", "orders", "checkout"]
}

module "ecr" {
  source   = "terraform-aws-modules/ecr/aws"
  version  = "~> 3.0"
  for_each = toset(local.services)

  repository_name = "cloudnova-retail-${each.key}"

  # Lets a repository that holds pushed images be destroyed and
  # recreated at all — see Concepts. It makes the repos recreatable,
  # not safer to destroy.
  repository_force_delete = true

  # Real, non-empty policy required — see the note below. Same policy
  # Demo 19 already established for this exact module.
  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  # Project, Environment, ManagedBy and Tier = platform come from the
  # provider's default_tags; only what's specific to these repos goes here
  tags = {
    Demo    = "22c-ecr-acm-recreation"
    Purpose = "persistent-ecr"
  }
}
```

> **Why `tags` no longer sets `Project`.** The provider's
> `default_tags` (from 22b's locals) already stamps every resource with
> `Project = cloudnova`, `Environment`, `ManagedBy` and — the one that
> matters for ADR-023 — `Tier = platform`. A module-level `Project`
> would override the shared value with a different one for these repos
> only. `Demo` is set here because the shared `Demo` value belongs to
> 22b.

> **A real, reproduced bug, and how this file avoids it — the way Demo
> 19's own content does, not by disabling the feature.** This module
> defaults `create_lifecycle_policy = true`, paired with
> `repository_lifecycle_policy` defaulting to `""` (empty string). Left
> at those defaults, apply fails against the real AWS API with
> `InvalidParameterException: 'lifecyclePolicyText' failed to satisfy
> constraint: 'Member must have length greater than or equal to 100'`:
> AWS rejects an empty lifecycle policy outright. **Demo 19's own real
> `main.tf`, for this identical module, never hits this bug — because
> it always supplies a real policy, never leaves the argument at its
> default.** Supplying the same policy here, rather than disabling
> lifecycle policies altogether, is both the fix and the thing that
> keeps this demo's "same technique as Demo 19" claim true — a
> persistent, ongoing registry benefits from automatic image cleanup at
> least as much as Demo 19's teaching rep did.

> **Same-as-Demo-19 note, restated:** the module call itself, and its
> version pin, are unchanged from Demo 19. What's new is the `for_each`
> over all five services in one pass, rather than Demo 19's single-repo
> teaching example — plus `repository_force_delete`, which this demo
> needs because its repos are meant to be recreatable.

This step also extends `08-outputs.tf` (copied from 22b in Part A),
adding the one output Step 5's Docker commands actually depend on —
without it, there's no way to derive each repository's real registry
URL, and typing an account ID by hand into a shell command is exactly
the mistake a real run of this demo made (see Step 5's own note below).

Add to **08-outputs.tf**:

```hcl
output "repository_urls" {
  description = "Map of service name to its ECR repository URL"
  value       = { for svc, repo in module.ecr : svc => repo.repository_url }
}
```

> **Same pattern Demo 19 already established** — a `for` expression
> over the `for_each`'d module's instances, building one combined map
> instead of five separate outputs. Demo 19's own Step 9 authentication
> step derives its registry hostname from this exact output shape; this
> demo's Step 5 now does the same.

### Step 5 — Check, apply and re-push images

**Static analysis first.** ADR-011's convention — `tflint` and `checkov`
run before every real apply from 22b onward — applies here too. Both
pick up the config files copied from 22b.

```bash
tflint --init
tflint
checkov -d .
```

> ⚠️ [VERIFY — not yet run against this demo's ECR code.] `tflint`
> should stay silent. `checkov` may report findings on the new
> repositories that 22b never triggered (repository encryption with a
> customer-managed key, for instance). Read each one and decide, as in
> 22b: fix if it's cheap, skip with a written reason in
> `.checkov.yaml` if it isn't. A note for modules: `checkov` scans the
> configuration you point it at, and whether it also evaluates the
> registry module's *internals* depends on whether the module source has
> been downloaded — so a clean result may cover less of the ECR module
> than of 22b's plain resources.

This step applies the five repositories, then re-authenticates Docker
and re-pushes each service's real published image into the new,
persistent registry — **deriving every registry value from a real
`terraform output`, never typing an account ID by hand.**

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

**Confirmed against a real run** — the module resolves to `3.2.0`
(matching Demo 19's own confirmed resolution), and the apply reports
exactly 15 resources (3 per repository — repository, lifecycle policy,
and the module's own default access policy — the same shape Demo 19
confirmed):

```
Apply complete! Resources: 15 added, 0 changed, 0 destroyed.
```

> ⚠️ [VERIFY — the recorded run predates `repository_force_delete` and
> the tag change. Neither adds a resource, so 15 is still expected; the
> setting is an argument on the repository itself. Confirm on the next
> run.]

> **A real run of this exact demo hit the precise failure Demo 19's
> own Concepts section warns about — worth reading as a real,
> reproduced example, not just a hypothetical.** An attempt at this
> step used the literal placeholder text `<YOUR_ACCOUNT_ID>` directly
> in the shell commands, unreplaced. The shell interpreted the `<` as
> input redirection rather than as part of a hostname, and every
> `docker pull` succeeded (it doesn't need the registry hostname at
> all) while every `docker tag`/`docker push` silently no-opped with
> `zsh: no such file or directory: YOUR_ACCOUNT_ID` — not an
> authentication error, not an ECR error, a shell parsing error from a
> placeholder that was never meant to be pasted in literally. **The
> commands below derive every value from the real `repository_urls`
> output added in Step 4**, the same fix Demo 19 already applied for
> the identical class of mistake — there's no placeholder left to
> accidentally leave unreplaced.

```bash
# Authenticate to your new private ECR — registry derived from a real
# output, not typed by hand
REGISTRY=$(terraform output -json repository_urls | jq -r '.ui' | cut -d'/' -f1)

aws ecr get-login-password --region us-east-2 --profile default | \
  docker login --username AWS --password-stdin "$REGISTRY"
```

Expected: `Login Succeeded`.

Run each of the five blocks below in order — each is self-contained,
with its own uniquely-named variable, matching Demo 19's own Step 10
pattern exactly (never reuse one variable name across services).

**UI:**

```bash
REPO_UI=$(terraform output -json repository_urls | jq -r '.ui')

docker pull public.ecr.aws/aws-containers/retail-store-sample-ui:latest
docker tag public.ecr.aws/aws-containers/retail-store-sample-ui:latest "$REPO_UI:latest"
docker push "$REPO_UI:latest"
```

**Catalog:**

```bash
REPO_CATALOG=$(terraform output -json repository_urls | jq -r '.catalog')

docker pull public.ecr.aws/aws-containers/retail-store-sample-catalog:latest
docker tag public.ecr.aws/aws-containers/retail-store-sample-catalog:latest "$REPO_CATALOG:latest"
docker push "$REPO_CATALOG:latest"
```

**Cart:**

```bash
REPO_CART=$(terraform output -json repository_urls | jq -r '.cart')

docker pull public.ecr.aws/aws-containers/retail-store-sample-cart:latest
docker tag public.ecr.aws/aws-containers/retail-store-sample-cart:latest "$REPO_CART:latest"
docker push "$REPO_CART:latest"
```

**Orders:**

```bash
REPO_ORDERS=$(terraform output -json repository_urls | jq -r '.orders')

docker pull public.ecr.aws/aws-containers/retail-store-sample-orders:latest
docker tag public.ecr.aws/aws-containers/retail-store-sample-orders:latest "$REPO_ORDERS:latest"
docker push "$REPO_ORDERS:latest"
```

**Checkout:**

```bash
REPO_CHECKOUT=$(terraform output -json repository_urls | jq -r '.checkout')

docker pull public.ecr.aws/aws-containers/retail-store-sample-checkout:latest
docker tag public.ecr.aws/aws-containers/retail-store-sample-checkout:latest "$REPO_CHECKOUT:latest"
docker push "$REPO_CHECKOUT:latest"
```

**Confirmed against a real, complete run** — once the account-ID
placeholder was replaced with a real, derived value, all five pushes
succeeded end-to-end:

```
latest: digest: sha256:4825f0aa334108172019714014a2443633fac16ae44359b5f8794ab5a1c46213 size: 1579
latest: digest: sha256:d646b6be5d5a35d6980a144a62a8e83d4c3833cfabca658b8eb5ebb03aa7a169 size: 1573
latest: digest: sha256:aede046d8194d46df2df4ff9638422cb7e467db458b25985c45fbe4de11f6ef3 size: 1579
latest: digest: sha256:c49707787725145f113bb8d21f934617f34e83b6c9a14abf812de45389830674 size: 1579
latest: digest: sha256:29e627c0335b94d8ff21796cf0dfa55115a2a16bac41a1c75cf13291ca14adaa size: 2209
```

> **This demo pushes under the `:latest` tag, not `:v1.0.0` like Demo
> 19.** That's intentional, not an inconsistency — this demo's
> repositories are `IMMUTABLE` by inheritance from the module's own
> default (this demo never overrides
> `repository_image_tag_mutability`), so re-running this step with a
> newer upstream image would fail the same way Demo 19's Step 11
> deliberately demonstrates. For this persistent registry, re-running
> Part B with a genuinely new upstream image should use a new tag
> (`v1.1`, a date stamp, or similar) — the same lesson Demo 19 already
> taught, not a new one.

### Step 6 — Verify in Console

This step confirms in the Console that all five repositories genuinely
hold real images, not just that Terraform reported success.

```
Console → ECR → Repositories → cloudnova-retail-ui (and the other 4)
  → Images tab → latest tag present, real image size shown ✅
```

![ECR Private registry — Repositories list showing all five cloudnova-retail-* repositories, each Immutable, AES-256 encrypted](images/image.png)

![cloudnova-retail-ui repository — Images tab showing the latest tag, real image size 248.22 MB, real image digest](images/image-1.png)

> **Confirmed against a real Console screenshot.** All five
> repositories are present with the correct name pattern, `Tag
> immutability: Immutable`, and `Encryption type: AES-256` — the same
> two settings from the single `for_each`'d module call in Step 4,
> applied identically across every instance. The UI repository's
> `Images` tab confirms a real, non-zero-size image (**248.22 MB** —
> the identical size Demo 19's own real run confirmed for this same
> published image), not just a Terraform-reported success.

---

## Part C — ACM: Cert Re-Request + Re-Validation

Part C re-requests and re-validates a new ACM certificate against the
same standing hosted zone, reading its ID via a data lookup — the same
technique Demo 20 already used, applied to a different, persistent
domain.

### Step 7 — Add 11-acm.tf

This step reads the standing hosted zone and requests a new
certificate against it, using the exact same module version and
zone-lookup technique Demo 20 established.

Create a file **11-acm.tf** and add the below content:

This file contains the zone lookup and the ACM module call together —
the zone's ID flows directly from the `data` block into the module's
`zone_id` input.

```hcl
data "aws_route53_zone" "main" {
  name         = "rselvantech.com."
  private_zone = false
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 6.0"

  domain_name = "app.rselvantech.com"
  zone_id     = data.aws_route53_zone.main.zone_id

  validation_method   = "DNS"
  wait_for_validation = true

  tags = {
    Demo    = "22c-ecr-acm-recreation"
    Purpose = "persistent-acm"
  }
}
```

> **Confirmed against Demo 20's real content, not assumed.** Demo 20
> already used this exact `data "aws_route53_zone"` → `zone_id`
> pattern — nothing about *how* the zone is looked up is new here. The
> module version (`~> 6.0`) also matches Demo 20's exactly, as
> intended. **What genuinely is different is the domain itself.** Demo
> 20 requested a certificate for `tf-mastery.rselvantech.com` — a
> deliberately disposable practice subdomain, chosen so a mistake
> there wouldn't affect anything real. This demo requests
> `app.rselvantech.com` instead — the actual subdomain the persistent
> ALB will serve traffic on once 22d creates it, not a placeholder.
> That domain change is deliberate, not an oversight. The trailing dot
> on `"rselvantech.com."` also matches Demo 20's own established
> convention for matching Route53's internally-stored, fully-qualified
> zone name — worth keeping consistent for the same reason the module
> version pins are kept consistent.

This step also extends `08-outputs.tf` a second time, adding the
certificate's ARN — the value 22d's own Ingress work reads, from this
state, to bind this certificate.

Add to **08-outputs.tf**:

```hcl
output "certificate_arn" {
  description = "ARN of the validated ACM certificate"
  value       = module.acm.acm_certificate_arn
}
```

> **The module's real output is `acm_certificate_arn`, not
> `certificate_arn` — confirmed twice now, not assumed.** Demo 20's
> own Break-Fix and Troubleshooting sections already document this
> exact naming trap (a plausible-looking `certificate_arn` doesn't
> exist on this module and fails with `Unsupported attribute`). The
> **root** output above is free to be named `certificate_arn` — that's
> this configuration's own choice of name for its output block,
> unrelated to what the module itself calls its internal attribute.

### Step 8 — Check, apply and wait for validation

Run the same pre-apply checks as Step 5, then apply. This step applies
the certificate request and genuinely waits for AWS to confirm
issuance before `apply` completes.

```bash
tflint
checkov -d .
terraform plan
terraform apply
```

> ⚠️ [VERIFY — the static-analysis output for the ACM module hasn't
> been recorded; expect the same judgement-per-finding approach as
> Step 5.]

```
Confirmed against a real run:

module.acm.aws_acm_certificate.this[0]: Creating...
module.acm.aws_acm_certificate.this[0]: Creation complete after 8s [id=arn:aws:acm:us-east-2:<ACCOUNT_ID>:certificate/96a7aa8b-27e7-4187-a59f-7c8d96a23034]
module.acm.aws_route53_record.validation[0]: Creating...
module.acm.aws_route53_record.validation[0]: Still creating... [00m29s elapsed]
module.acm.aws_route53_record.validation[0]: Creation complete after 29s [id=<ZONE_ID>__e93640de592ca6a1ce543aa8bce5dc89.app.rselvantech.com._CNAME]
module.acm.aws_acm_certificate_validation.this[0]: Creating...
module.acm.aws_acm_certificate_validation.this[0]: Creation complete after 1s

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

> **Real resource count, confirmed: 3** (`aws_acm_certificate`,
> `aws_route53_record.validation`, `aws_acm_certificate_validation`),
> matching what `module.acm`'s own resource shape predicts. In this
> real run, the certificate itself issued in 8 seconds and the
> validation CNAME took 29 seconds to create — both well inside normal
> range, not something to wait minutes for in practice.

### Step 9 — Verify in Console

This step confirms in the Console that the new certificate reached
Issued status and that the standing zone itself remains otherwise
unchanged.

```
Console → Certificate Manager → Certificates → app.rselvantech.com
  → Status: Issued ✅ (not Pending validation)
```

![AWS Certificate Manager — Certificates list showing app.rselvantech.com, Amazon Issued, Status: Issued, RSA 2048](images/image-2.png)

```
Console → Route53 → Hosted zones → rselvantech.com
  → A new CNAME validation record present ✅
  → The zone itself: still the same standing zone, unchanged otherwise
```

![Route53 hosted zone rselvantech.com — Records (4): the zone's own NS and SOA records, one pre-existing, unrelated CNAME validating a different certificate on the bare apex domain, and this demo's new validation CNAME for app.rselvantech.com](images/image-3.png)

> **Confirmed against real Console screenshots, and cross-checked
> directly against the real apply log.** The certificate shows
> `Status: Issued`, `Amazon Issued`, common name `app.rselvantech.com`
> — not `Pending validation`. The hosted zone shows exactly **4**
> records, matching Demo 20's own established expectation of "more
> than just this demo's own record": the zone's NS/SOA pair, one
> pre-existing, unrelated CNAME validating a different certificate on
> the bare `rselvantech.com` apex (not something this demo created or
> manages), and this demo's own new validation CNAME —
> `_e93640de592ca6a1ce543aa8bce5dc89.app.rselvantech.com`, the exact
> record ID the real `apply` log reported creating in Step 8. Don't be
> thrown by the extra, unrelated record; only the `app.rselvantech.com`-
> prefixed one is this demo's own.

---

## Cleanup

**This demo's Cleanup step is verification, not destruction** — same
reasoning as 22a/22b. These objects are meant to persist for the rest
of the project.

### Step 10 — Confirm everything is in its intended, permanent state

**1. What Terraform tracks:**

```bash
terraform state list
```

> ⚠️ [VERIFY — expected, not yet recorded against the current layout;
> ordering may differ.] 22b's fifteen entries (its thirteen managed
> resources and two data sources) are not new here — their presence is
> exactly what confirms Part A's copy worked. This demo adds the rest:

```
module.ecr["ui"].aws_ecr_repository.this[0]          (and 4 more repositories,
module.ecr["ui"].aws_ecr_lifecycle_policy.this[0]     each with a lifecycle
module.ecr["ui"].aws_ecr_repository_policy.this[0]    policy and access policy)
data.aws_route53_zone.main
module.acm.aws_acm_certificate.this[0]
module.acm.aws_route53_record.validation[0]
module.acm.aws_acm_certificate_validation.this[0]
```

**2. What actually exists in AWS — CLI:**

```bash
aws ecr describe-repositories \
  --query 'repositories[].[repositoryName,imageTagMutability]' \
  --output table --profile default --region us-east-2

aws ecr describe-images --repository-name cloudnova-retail-ui \
  --query 'imageDetails[].[imageTags[0],imageSizeInBytes]' \
  --output table --profile default --region us-east-2

aws acm describe-certificate \
  --certificate-arn "$(terraform output -raw certificate_arn)" \
  --query 'Certificate.[DomainName,Status]' --output text \
  --profile default --region us-east-2
```

> ⚠️ [VERIFY — expected output, not captured in the recorded run.]
> Five `cloudnova-retail-*` repositories, each `IMMUTABLE`; one image
> tagged `latest` in the UI repository at roughly 248 MB (the size the
> recorded run's Console screenshot showed, in bytes here); and
> `app.rselvantech.com   ISSUED`.

**Tier tag** — the label ADR-023 puts on every platform resource:

```bash
aws ecr list-tags-for-resource \
  --resource-arn "$(aws ecr describe-repositories --repository-names cloudnova-retail-ui \
      --query 'repositories[0].repositoryArn' --output text --profile default --region us-east-2)" \
  --query 'tags[?Key==`Tier`]' --output table \
  --profile default --region us-east-2
```

> ⚠️ [VERIFY — expected output, not captured in the recorded run.] A
> single `Tier` / `platform` row, coming from the provider's
> `default_tags`.

**3. Confirm nothing has drifted:**

```bash
terraform plan
```

> ⚠️ [VERIFY — expected output, not captured in the recorded run.]
> `No changes. Your infrastructure matches the configuration.`

**4. Console checks:**

```
Console → ECR → confirm all 5 repos with images present ✅
Console → Certificate Manager → confirm Issued status ✅
Console → SNS/Budgets/Lambda → confirm 22b's resources are still intact and unchanged ✅
```

> ⚠️ **Do not run `terraform destroy` at the end of this session.**
> 22d's EKS deployment depends on these images and this certificate
> already existing, and 22b's governance resources — and Demo 24's IAM
> identity, once built — share this same state. A destroy run here
> takes all of them down together; `prevent_destroy` can't stop it for
> the ECR and ACM modules (see Concepts). It would **not** touch the
> VPC or EKS cluster: those live in `workloads/`, a structurally
> separate state.

---

## What You Learned

1. ✅ Every `platform/`-tier demo's own directory contains the entire
   accumulated configuration verbatim before adding anything new — not
   because it's good hygiene, but because that state is shared across
   demos, and an incomplete local configuration risks proposing real
   destruction of resources prior demos already applied. Copying the
   previous demo's finished folder is safer than retyping it, because
   a retyped listing drifts.
2. ✅ Re-creating an already-taught resource for a new, persistent
   purpose is a lifecycle decision, not duplicated teaching.
3. ✅ `data "aws_route53_zone"` reads an existing zone's attributes
   without ever proposing to create, modify, or destroy it — the same
   `data`-vs-`resource` distinction Demo 08/10 first taught, and the
   same zone-lookup technique Demo 20 already used.
4. ✅ This project's hosted zone is permanently outside its Terraform's
   management scope — every ACM cert this project ever creates reads
   the zone, never manages it.
5. ✅ `for_each` over a service list scales a single module call to
   multiple repos in one pass — a practical application of a Demo 06/10
   construct, not new syntax.
6. ✅ Reusing a module a second time is exactly the moment a version
   pin can quietly drift — worth explicitly double-checking against
   the demo that first introduced it, not just trusting memory. The
   same double-check applies to prose claims about what changed versus
   an earlier demo, not just version numbers.
7. ✅ `prevent_destroy` can't be attached to a `module` block, so ECR
   and ACM are protected by the platform/workloads state boundary — a
   real guarantee against a `workloads/` destroy — and by nothing at all
   against a destroy run inside `platform/`.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| Carrying a multi-file configuration into a new directory before extending it | TA-004 Obj 3 — Terraform workflow, state | Illustrates why `plan` against shared state is the real safety check, not `validate` alone |
| `data "aws_route53_zone"` | TA-004 Obj 5a — Data sources | Read-only lookup against infrastructure Terraform doesn't manage |
| ACM DNS validation via a data-sourced zone ID | TA-004 Obj 4a/5a | Same validation mechanics as Demo 20, sourced identically |
| `lifecycle` is not allowed on a `module` block | TA-004 Obj 4a — Resource configuration | `prevent_destroy` and the other lifecycle arguments apply to resources, not modules |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Can a `data` block appear in the same config that also manages other real resources?" | Yes — `data` and `resource` blocks freely coexist; a `data` lookup just never appears in `plan`'s create/change/destroy summary the way a managed resource does | Assuming a config is either "all data" or "all resources" |
| "Does re-creating a resource you already built once mean the exam expects you to reference the old one somehow?" | No — a new `resource`/module call with a new state address is a completely independent object, regardless of how similar its configuration looks | Assuming any form of implicit continuity between separately-applied resources |
| "If a config's local files don't declare a resource that's tracked in the state it's pointed at, what does `plan` propose?" | Destroying it — Terraform reconciles state against local configuration, and an absent declaration reads as "this should no longer exist" | Assuming Terraform leaves untracked-by-local-config resources alone by default |
| "Protect a module-created resource with `prevent_destroy`" | Recognising a `lifecycle` block isn't permitted on a `module` block at all — protection has to come from elsewhere (state separation, or the module's own inputs) | Putting `lifecycle { prevent_destroy = true }` inside the module call and expecting it to work |

### Exam Task — Write a complete configuration

**Task:** Write a `data "aws_route53_zone"` lookup and use its `zone_id`
output in an `aws_route53_record` resource.

**Block types required:** `data`, `resource`

**Official documentation:**
- [`aws_route53_zone` data source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone)

**What to practise:**
1. Open the page above — check the Attribute Reference for `zone_id`
2. Write the configuration from scratch without looking at this demo's `src/` files
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
data "aws_route53_zone" "main" {
  name         = "example.com"
  private_zone = false
}

resource "aws_route53_record" "example" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "app.example.com"
  type    = "CNAME"
  ttl     = 300
  records = ["target.example.com"]
}
```

**Arguments you must know without looking up:**
- `data "aws_route53_zone"` requires either `name` or `zone_id` to
  identify which zone to look up — not both required, but at least one
- `private_zone` defaults to `false`; must be set explicitly to `true`
  to disambiguate if a public and private zone share the same name

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `cd` into the demo folder fails with "No such file or directory" | The phase folder name contains spaces and the path wasn't quoted | Quote the path: `cd "terraform-aws-mastery/Phase 3 - Real AWS Infrastructure/22c-ecr-acm-recreation/src/platform"` |
| `terraform init` fails with no backend configured, or a local-state warning | `01-backend.tf` wasn't copied into this directory | Redo Step 2's copy — every file it lists must be present |
| `terraform plan` proposes destroying `aws_sns_topic.cost_alerts`, the Budget, the Lambda, or any of 22b's other resources | The copy was incomplete — one or more of 22b's files is missing from this directory, even though the backend file is present and state loads correctly | Diff this directory's files against 22b's `src/platform/` file-by-file; re-run Step 3's `plan` until it reports no changes before touching Part B |
| `terraform plan` (Step 3) proposes *adding* 22b's Part D resources | 22b was applied only through Part C, but its finished (Part D) configuration was copied | Finish 22b's Part D first, then re-run Step 3 |
| `terraform plan` (Step 3) reports a full set of adds instead of "no changes" | 22b's resources no longer exist in AWS at all — most likely a `terraform destroy` was run against an earlier, incomplete directory that shared 22b's state but never declared its resources locally | Confirmed real, safe recovery: apply the plan (`0 to destroy`, so nothing is removed), then re-confirm the recreated SNS subscription's confirmation email — it will be a genuinely new subscription |
| `terraform plan` (Step 3) proposes destroying ~18 resources, all ECR/ACM, with none of 22b's resources appearing in the plan at all | You're re-running this demo in a fresh directory after already completing it once — this demo's own ECR repos and ACM certificate still exist in the shared state, but this directory hasn't reached Part B/C yet this time through | **Do not apply.** Continue on to Steps 4 and 7 and add the ECR and ACM files; a fresh `plan` afterward will find all resources already match and report no changes |
| `docker tag`/`docker push` fail with `zsh: no such file or directory: YOUR_ACCOUNT_ID` (or similar), while `docker pull` succeeds | The literal placeholder text `<YOUR_ACCOUNT_ID>` was left unreplaced in the shell command — the shell interpreted `<` as input redirection, not as part of a hostname | Use Step 5's derived-variable commands (`$REPO_UI`, etc., from the real `repository_urls` output) instead of typing an account ID by hand |
| `Error: No value for required variable` on `notification_email`/`monthly_budget_limit` | `terraform.tfvars` wasn't copied into this directory | Copy or create it with your real values — see Step 2 |
| `no matching Route53Zone found` | `name`/`private_zone` combination doesn't match any real zone in this account | Confirm the exact domain name and whether it's actually a public zone |
| ACM cert stuck at `Pending validation` past a few minutes | DNS validation record hasn't propagated yet, or was written to the wrong zone | Confirm the CNAME record exists in the correct hosted zone via Console, allow more time |
| `RepositoryAlreadyExistsException` | A repo with this name already exists (e.g., from a prior partial apply) | Import the existing repo or choose a different name — same class of naming conflict Demo 01 taught for S3 |
| `terraform apply` fails on `aws_ecr_lifecycle_policy.this[0]` with `'lifecyclePolicyText' failed to satisfy constraint: 'Member must have length greater than or equal to 100'` | The ECR module defaults `create_lifecycle_policy = true` with `repository_lifecycle_policy` defaulting to `""` — AWS rejects an empty lifecycle policy outright | `10-ecr.tf` already supplies a real `repository_lifecycle_policy` (the same one Demo 19 uses) — never leave this argument at its default |
| A destroy-and-recreate of the ECR repos fails with a "repository contains images" error | `repository_force_delete` isn't set, so a repository holding pushed images can't be deleted | Set `repository_force_delete = true` on the module call, as `10-ecr.tf` does |
| Module version differs from Demo 19/20 with no obvious reason | A copy-paste or memory slip when reusing a module a second time | Diff this demo's `version` constraint against the original demo's — they should match unless there's a documented reason not to |

---

## Break-Fix Scenario

One deliberate error. Diagnose using `terraform validate` — do not look
at the answer first.

```bash
cd src/break-fix/
terraform init
terraform validate
```

This file is a single-resource configuration with one local-name
mismatch between a data source and a reference to it — diagnose it
before revealing the answer.

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

data "aws_route53_zone" "main" {
  name         = "rselvantech.com."
  private_zone = false
}

resource "aws_route53_record" "validation" {
  zone_id = data.aws_route53_zone.primary.zone_id   # Error
  name    = "_acme-challenge.app.rselvantech.com"
  type    = "CNAME"
  ttl     = 300
  records = ["dummy-validation-target.acm-validations.aws."]
}
```

<details>
<summary>Reveal answer — attempt diagnosis first</summary>

**Error — `data.aws_route53_zone.primary.zone_id`**
The data source is named `main`, not `primary`. Terraform will show:
`Reference to undeclared resource`. Same class of local-name mismatch
error as 22a's own break-fix — the pattern recurs because it's an easy
typo to make, not because it's a hard concept. Fix:
`data.aws_route53_zone.main.zone_id`.

⚠️ [VERIFY — this Break-Fix was not executed in the recorded session.
Run it once and confirm `terraform validate` reports the error above
before `plan`, then add the real output here.]

</details>

**Cleanup:**

```bash
cd src/break-fix/
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
```

No `terraform destroy` is needed — `validate` fails before anything is
planned, so nothing exists in AWS to remove. This break-fix uses its own
local state and never touches the persistent backend.

---

## Interview Prep

**Q1. A teammate says "we already built ECR and ACM in Demo 19/20 — why are we building them again here?" How do you explain this isn't wasted work?**
Because Demo 19 and Demo 20's objects were teaching reps — built specifically to be torn down at the end of their own demo, the same guarantee every Phase 1–2 demo makes. This demo builds new objects using the identical technique, but with a different lifecycle: these are meant to persist for the rest of the project, starting with 22d's EKS deployment pulling images from them and binding its ALB to this certificate. The alternative — exempting Demo 19/20's objects from teardown so this demo could just reuse them — would have quietly broken the "every Phase 1–2 demo tears down, no exceptions" guarantee the whole teaching model depends on, for a fairly small convenience.

**Q2. Someone asks why this demo uses a `data` lookup for the Route53 zone instead of a `resource` block, when Demo 20 might have handled it differently.**
It didn't handle it differently — Demo 20 already used `data "aws_route53_zone"` to read this same zone's ID before feeding it into its own ACM module call, the exact same pattern this demo uses. The reason it's a `data` lookup at all, in both demos, is that this project's Terraform never creates or destroys the hosted zone itself — it was created once, before Demo 20's first build, and deliberately excluded from every teardown cycle in this project. If it were managed as a `resource`, `terraform destroy` would attempt to delete it, which would mean re-pointing the domain registrar's nameservers every time a demo tears down — operationally absurd for infrastructure that's supposed to be a stable, continuous fact about the domain.

**Q3. A reviewer notices this demo's ECR/ACM files pin the exact same module versions as Demo 19/20, and asks whether that's just a coincidence.**
No — it's deliberate, and worth calling out precisely because it's the kind of thing that's easy to get wrong. Reusing a module a second time, from memory or a slightly different starting file, is exactly the situation where a version constraint can quietly drift — typing `~> 2.0` instead of `~> 3.0` doesn't look obviously wrong on its own, it only looks wrong when compared against the demo that originally established the constraint. This demo's own version table exists specifically to make that comparison explicit rather than leaving it to chance.

**Q4. A reviewer asks why this demo's Part A brings in a dozen files that have nothing to do with ECR or ACM. Isn't that out of scope for a demo titled "ECR/ACM Re-Creation"?**
It looks out of scope until you consider what this project's state sharing actually implies. This demo's directory has to point at the same, real, already-populated `platform/` state 22b left behind — not a fresh one — because the platform-tier demos are one continuously-growing environment, not independent per-demo sandboxes. The only way for `terraform plan` here to correctly recognize "22b's resources already exist and should stay untouched" is for this directory's own files to actually declare them. Skipping that isn't a scope violation avoided — it's a real risk of Terraform proposing to destroy 22b's SNS topic, Lambda, key and Budget the moment this demo's `plan` runs, since nothing here would tell it those resources are still wanted.

**Q5. Why not just put `prevent_destroy` on the ECR and ACM modules, given they're meant to be permanent?**
Terraform doesn't allow a `lifecycle` block on a `module` block at all — it's a language limitation, not a version issue. So the protection is structural instead: these resources live in `platform/`'s state, and the every-session teardown runs against `workloads/`'s separate state, which can't reach them. That's a real guarantee against the destroy you're most likely to run by accident. It's no guarantee against a destroy run inside `platform/` itself, which is why the demo's Cleanup is verification and carries a warning — and why the IAM roles added to this same tier later, being native resources, can use `prevent_destroy` where these can't.

---

## Key Takeaways

1. **The `platform/`-tier demos share one continuously-growing state —
   every demo's directory has to contain the full accumulated
   configuration, not just add its own new files.** An incomplete copy
   isn't a documentation nicety being skipped — it's a real risk of
   Terraform proposing to destroy resources a prior demo already
   applied, since state and local configuration are reconciled against
   each other on every `plan`. Copy the previous demo's finished
   folder rather than retyping it, and prove the copy with a clean
   `plan`.

2. **Re-creating a resource is a lifecycle decision, not duplicated
   effort.** The same module or resource type can serve two entirely
   different purposes — teaching once versus supporting an ongoing
   system — without contradiction.

3. **`data` blocks read; `resource` blocks manage.** A hosted zone this
   project never wants to destroy stays a `data` lookup forever, no
   matter how many things depend on its ID.

4. **Standing infrastructure and torn-down teaching reps can coexist
   in the same domain's history.** This project's Route53 zone
   predates and outlives every ACM cert ever validated against it,
   built or torn down, across every demo that touches it.

5. **"Protected" needs saying precisely.** `prevent_destroy` can't
   guard a module's resources; the platform/workloads state split
   guards them against a `workloads/` destroy and against nothing else.
   Say which guarantee applies to which resource.

6. **Reusing a module is exactly when a version pin can quietly
   drift — and the same discipline applies to claims about what
   changed, not just to version numbers.** Diff a reused module's
   version constraint against the demo that first introduced it, and
   check any "this is new" claim against what that earlier demo
   actually did, rather than assuming either is correct by default.

> **Demo scope:** Primary concept: carrying an accumulated,
> multi-demo shared configuration into a new directory correctly before
> extending it, and re-creating already-taught ECR and ACM objects as
> persistent, rather than torn-down-teaching-rep, infrastructure.
> Supporting concepts: `data "aws_route53_zone"` as a read-only lookup
> against unmanaged infrastructure, why `prevent_destroy` can't protect
> module resources, `for_each` reuse at module scale, catching
> version-pin drift when reusing a module a second time.
> Estimated completion time: 40–45 minutes (includes real ACM
> validation wait time and the baseline step).
> Checkpoints: 3 natural stopping points (end of Part A, end of
> Part B, end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws ecr get-login-password` | Authenticates Docker to a private ECR registry |
| `docker pull` / `tag` / `push` | Standard image re-push flow — pulls from the public gallery, retags, pushes to the new private repo |
| `aws ecr describe-repositories --profile default --region us-east-2` | Lists ECR repos to verify creation and permissions |
| `aws ecr describe-images --repository-name cloudnova-retail-ui` | Shows the images (tag, size) actually held in a repository |
| `aws acm describe-certificate --certificate-arn <ARN>` | Shows a certificate's domain and validation status |
| `terraform init` / `validate` / `plan` / `apply` | Standard workflow — `plan` immediately after Part A's copy is this demo's real safety check |
| `tflint` / `checkov -d .` | Pre-apply static analysis, run before every real apply from 22b onward |
| `terraform state list` | Confirms both the copied baseline and this demo's new objects are all correctly tracked |

---

## Next Demo

**Demo 22d — EKS: Single Service (UI only):** the EKS cluster (Auto
Mode, with no OIDC identity provider — Pod Identity replaces IRSA,
ADR-021) and the actual teaching content this whole sub-demo group has
been building toward — pulling 22c's images into a running Kubernetes
Deployment behind an ALB using 22c's certificate. The fourth and last
of the four sub-demos that together make up what was originally planned
as a single Demo 22. **22d writes into `workloads/`, a separate state
and directory, so it does not copy this demo's files.** It reads this
demo's outputs — the certificate ARN today, IAM role ARNs later — through
`terraform_remote_state`, the technique Demo 07 taught.

---

## Appendix — Anki Cards

**22c-ecr-acm-recreation-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::22c-ecr-acm-recreation
#separator:Comma
#columns:Front,Back,Tags
"Why does every platform-tier demo's own directory need the FULL accumulated configuration, not just its own new files?","The platform-tier demos share one continuously-growing state (platform/terraform.tfstate), not independent per-demo state. Terraform reconciles real applied state against whatever local .tf files are present - anything tracked in state but missing locally gets proposed for destruction on the next plan, not ignored.","demo22c,state,gotcha"
"What's the actual risk of a PARTIAL baseline copy (e.g. the backend file but not the cost-governance files), versus skipping it entirely?","Skipping entirely fails safely - no backend file means terraform init can't even reach the existing state. A PARTIAL copy is the dangerous middle ground - init succeeds and loads real state, but local files no longer declare some already-applied resources, so plan proposes destroying them.","demo22c,state,gotcha"
"Why does this demo copy 22b's finished folder instead of retyping its files?","A retyped listing goes stale the moment the earlier demo changes - and a stale baseline is exactly the partial-copy risk. Copying the finished folder cannot drift, and a clean terraform plan then proves the copy is complete.","demo22c,state,workflow"
"Why does 22d NOT copy this demo's files the way this demo copies 22b's?","22d writes to a different state and directory (workloads/, not platform/). It reads what it needs from platform's outputs via terraform_remote_state instead. Only demos sharing the platform state need the accumulated config.","demo22c,state,platform-workloads"
"Why does this demo build new ECR/ACM objects instead of reusing Demo 19/20's?","Demo 19/20's objects were teaching reps, torn down at their own Cleanup like every Phase 1-2 demo. This demo's objects are meant to persist for the rest of the project. Same technique, different lifecycle - not duplicated work.","demo22c,ecr,acm,lifecycle"
"What does data \"aws_route53_zone\" do, and why is it a data block instead of a resource?","Reads an existing hosted zone's attributes (like zone_id) without ever proposing to create, modify, or destroy it. This project's zone is permanently outside Terraform's management scope, so every ACM cert reads it via data, never manages it as a resource.","demo22c,route53,data-sources,ta004-obj5a"
"What would happen if the Route53 hosted zone were managed as a resource instead of read via data?","terraform destroy would attempt to delete the hosted zone, which would mean re-pointing the domain registrar's nameservers every teardown cycle - operationally absurd for infrastructure meant to be a stable, continuous fact about the domain.","demo22c,route53,teardown"
"Is a data block and a resource block ever both present in the same Terraform config?","Yes, freely. A data lookup just never appears in plan's create/change/destroy summary the way a managed resource does - the two coexist normally.","demo22c,data-sources,ta004-obj5a"
"Can prevent_destroy protect the ECR and ACM resources in this demo?","No. Terraform does not allow a lifecycle block on a module block at all (HashiCorp/terraform issue #27360), and both resources live inside registry modules. Protection comes from the platform/workloads state split, which guards against a workloads destroy - and nothing guards against a destroy run inside platform/.","demo22c,lifecycle,prevent-destroy,ta004-obj4a"
"What is repository_force_delete = true for on the ECR module?","It lets a repository that holds pushed images be destroyed and recreated at all - by default deleting a non-empty repository fails. It makes the repos recreatable, not safer to destroy. The input exists on terraform-aws-modules/ecr/aws at the ~> 3.0 line (confirmed at v3.0.0 and v3.2.0).","demo22c,ecr,gotcha"
"Does re-using a module call with for_each across a list of services introduce new Terraform syntax beyond what for_each itself already taught?","No - it's the same for_each-over-a-set mechanic from Demo 06/10, applied to a module block instead of a plain resource. Recognizing this as reuse-at-scale, not a new concept, is itself a useful skill.","demo22c,for_each,modules"
"Why do this demo's ECR and ACM files pin the exact same module versions as Demo 19 and Demo 20?","Deliberately, not by coincidence - reusing a module a second time is exactly when a version constraint can quietly drift from memory. This demo's version table exists specifically to make the comparison against the original demo explicit.","demo22c,versioning,gotcha"
"What actually changed between Demo 20's ACM certificate and this demo's, if the zone-lookup technique is identical in both?","The domain itself. Demo 20 validated a deliberately disposable subdomain, tf-mastery.rselvantech.com. This demo validates app.rselvantech.com - the real subdomain the persistent ALB will serve once 22d exists. The data-lookup mechanism was never the difference; the target domain is.","demo22c,acm,route53,gotcha"
"After copying 22b's baseline into this demo's own directory, what should the very next terraform plan report, before Part B adds anything new?","No changes - 'Your infrastructure matches the configuration.' This is the actual proof the copy was complete and correct, not just that init succeeded.","demo22c,state,workflow"
"If Step 3's plan proposes ADDING 22b's Part D resources (Lambda, key, IAM role) while changing the topic and target, what does that mean?","22b was applied only through Part C, but its finished (Part D) configuration was copied. Finish 22b's Part D first, then re-run the check - Part D belongs to 22b's own walkthrough, including its live tests.","demo22c,state,gotcha"
"If Step 3's plan reports a full set of adds instead of 'no changes', what does that mean and is it safe to apply?","22b's resources no longer exist in AWS - most likely destroyed by an earlier, incomplete directory that shared 22b's state without declaring its resources locally. Safe to apply (0 to destroy), but the recreated SNS subscription will need re-confirming via email, since it's a genuinely new subscription.","demo22c,state,gotcha"
"Why do docker tag/push fail with a shell error like 'no such file or directory: YOUR_ACCOUNT_ID' if the literal placeholder text is left unreplaced in a command?","The shell interprets '<' as input redirection, not as part of a hostname - this is a shell parsing error, not an ECR or authentication error. The fix is deriving the registry value from a real terraform output (repository_urls), the same fix Demo 19 already established, rather than typing an account ID by hand.","demo22c,docker,gotcha"
"Why does this demo's 10-ecr.tf supply a real repository_lifecycle_policy?","A reproduced bug: the module defaults create_lifecycle_policy = true paired with repository_lifecycle_policy defaulting to an empty string, and AWS rejects an empty lifecycle policy outright. Demo 19's own real code for this identical module always supplies a real policy - matching it here is both the fix and what keeps the 'same technique as Demo 19' claim true.","demo22c,ecr,gotcha"
"Which tag does the provider's default_tags put on this demo's ECR and ACM resources, and what does it mean?","Tier = platform (from 22b's locals). It labels the resource as created-once, never torn down - a label used by 22b's cost check, not a lock that prevents deletion.","demo22c,tagging,platform-workloads"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the individual facts (why
> re-creation isn't redundant, `data` vs. `resource`, version-pin
> consistency, the shared-state requirement). This Quiz instead works
> through Break-Fix-style diagnosis and applied scenarios, so the two
> together cover recall and applied judgment without restating the same
> question twice.

**22c-ecr-acm-recreation-quiz.md:**

````markdown
# Quiz — Demo 22c: ECR/ACM Re-Creation

> Question types: True/False, Multiple Choice, Multiple Answer —
> matching the real TA-004 exam format.
> Target: 80% or above before moving to Demo 22d.

---

**Q1. (Multiple Choice)** A learner starts this demo in a brand-new,
empty directory, adds only the ECR and ACM files, and skips bringing
across any of 22b's files. What happens on `terraform init`?

- A) It succeeds, since ECR/ACM don't depend on 22b's resources
- B) It fails — there's no backend file, so Terraform has nowhere to even look for the existing, shared state
- C) It succeeds and silently creates a second, separate state file
- D) It succeeds, and the next `plan` proposes destroying 22b's resources

<details>
<summary>Answer</summary>

**B.** Skipping the copy entirely fails safely — without the backend
file, `init` can't locate the real state at all, so nothing gets
touched. The genuinely dangerous case is a *partial* copy (see Q2), not
a total skip.

</details>

---

**Q2. (Multiple Choice)** A learner copies the backend and provider
files from 22b, but not the cost-governance or budget files, then runs
`terraform plan` in that directory. What does `plan` most likely report?

- A) No changes — those files aren't relevant to this demo's own scope
- B) A proposal to destroy 22b's SNS topic, EventBridge rule, Lambda, key and Budget — since state tracks them but this directory's local files no longer declare them
- C) An error, since Terraform detects the copy is incomplete
- D) The missing resources are automatically re-added to the plan as "no-op"

<details>
<summary>Answer</summary>

**B.** This is the real risk this demo's Part A exists to prevent — a
directory that *can* reach real, existing state (via a working
backend) but whose local configuration no longer fully describes it
proposes destroying whatever's missing, not leaving it alone.

</details>

---

**Q3. (Multiple Choice)** A reviewer notices a `10-ecr.tf` pinning
`terraform-aws-modules/ecr/aws` at a different major version than Demo
19 used for the identical module, with no explanation given anywhere
in the demo. What's the correct response?

- A) Assume the newer demo's version is automatically the more current, correct one
- B) Treat the mismatch as worth questioning — check whether there's a stated reason, and if not, match the original demo's constraint
- C) Ignore it — version constraints between demos calling the same module never need to match
- D) Assume the older demo's pin is now outdated and should be bumped to match this one instead

<details>
<summary>Answer</summary>

**B.** An unexplained version drift between two demos calling the same
module is a signal to check, not something to resolve by guessing
which direction is "right."

</details>

---

**Q4. (Multiple Choice)** Why does this demo's Part A end with a
`terraform plan` check, before Part B adds the ECR file?

- A) It's a redundant formality — `init` succeeding is already sufficient proof the copy worked
- B) It's the actual proof the copy was both correct and complete — `plan` reporting "No changes" confirms this directory's files now fully match the real, already-applied state
- C) `plan` is required before every `terraform` command, regardless of context
- D) It pre-downloads the AWS provider for Part B's use

<details>
<summary>Answer</summary>

**B.** `init` succeeding only proves the backend is reachable — it
says nothing about whether the local `.tf` files fully and accurately
describe what's already applied. Only a clean `plan` (no changes)
proves that.

</details>

---

**Q5. (Multiple Choice)** This demo's Part B/C add nothing to
`04-variables.tf`, and only two outputs to `08-outputs.tf`. Why?

- A) This demo forgot to add them — an oversight
- B) Every value the ECR/ACM files need is either a literal string or read directly via `data`/`each.key` — there's nothing genuinely variable to parameterize; the outputs exist because 22d needs values from this state
- C) Terraform no longer requires separate variable files as of a recent version
- D) The ECR and ACM modules manage their own variables internally, making root-level variables redundant

<details>
<summary>Answer</summary>

**B.** This demo's own Directory Structure section states this
directly — the new files simply don't need anything beyond what Part A
carried over, and the outputs are this state's contract with
`workloads/`.

</details>

---

**Q6. (Multiple Choice)** Break-Fix references
`data.aws_route53_zone.primary.zone_id`, but the data source in this
config is actually named `main`. What error results?

- A) `Missing required argument`
- B) `Reference to undeclared resource`
- C) The lookup silently returns an empty string
- D) `terraform init` fails before `validate` even runs

<details>
<summary>Answer</summary>

**B.** This is a plain local-name mismatch, the same error class as
22a's own Break-Fix — `primary` was never declared, only `main` was.

</details>

---

**Q7. (Multiple Choice)** `data "aws_route53_zone"` includes
`private_zone = false` even though this project only has one zone
named `rselvantech.com`. What is this argument actually for?

- A) It's required syntax with no functional purpose when only one zone exists
- B) It disambiguates between a public and a private zone that might share the same name — needed only when both could exist, but safe to set explicitly regardless
- C) It controls whether the zone itself is publicly resolvable on the internet
- D) It determines whether the zone was created via Terraform or manually

<details>
<summary>Answer</summary>

**B.** `private_zone` exists to distinguish a public zone from a
private one sharing the same name — this project only ever has one
zone by this name, but setting the argument explicitly remains good
practice regardless.

</details>

---

**Q8. (Multiple Choice)** This demo's Cleanup step runs
`terraform state list` instead of `terraform destroy`. What would
actually happen if you ran `terraform destroy` inside `src/platform/`
anyway?

- A) Nothing destructive — these resources are protected by AWS from deletion
- B) It would tear down the 5 ECR repos, the new ACM certificate, AND 22b's governance resources, since they're all tracked in the same shared state — but it would not touch the VPC or EKS cluster, which live in `workloads/`
- C) It would only destroy the ECR repos; the ACM certificate is immune to `terraform destroy`
- D) Terraform would refuse to run `destroy` against resources created by a registry module

<details>
<summary>Answer</summary>

**B.** Because this directory's state is shared with 22b (and, going
forward, Demo 24 and the other platform-tier demos), a `destroy` here
doesn't stop at this demo's own objects. What it can't reach is
`workloads/` — a structurally separate state.

</details>

---

**Q9. (Multiple Choice)** A teammate proposes adding
`lifecycle { prevent_destroy = true }` inside the `module "ecr"` block
to protect the repositories. What happens?

- A) The repositories become undeletable, as intended
- B) Terraform rejects it — a `lifecycle` block isn't permitted on a `module` block, so protection has to come from elsewhere (here, the platform/workloads state split)
- C) It applies only to the module's first resource
- D) It works, but only on Terraform versions before 1.10

<details>
<summary>Answer</summary>

**B.** Lifecycle arguments belong on resources, not modules, at any
version. The state split protects against a `workloads/` destroy; it is
not a lock against a destroy run inside `platform/`.

</details>

---

**Q10. (True/False)** `repository_force_delete = true` makes the ECR
repositories safer, because it prevents them from being deleted while
they hold images.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** It does the opposite: it allows a repository holding
pushed images to be deleted at all. Without it, destroy-and-recreate
fails. It makes the repos *recreatable*, not protected.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 9-10/10 | Import Anki cards, move to Demo 22d |
| 8/10 | Review the wrong answers, then proceed |
| 5-7/10 | Re-read the relevant sections, retry those questions |
| Below 5/10 | Re-read the full demo before proceeding |
````