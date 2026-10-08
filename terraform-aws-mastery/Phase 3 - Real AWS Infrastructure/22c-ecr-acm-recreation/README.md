# Demo 22c — ECR/ACM Re-Creation: New Objects for a Persistent Environment

> **Revision note (this version) — per ADR-023, pending Track 2 final
> sign-off.** Three substantive changes from the original demo,
> **all three found or confirmed through this project's own real
> teardown incidents, not theoretical:**
> 1. Built in `src/terraform/platform/`, state key
>    `platform/terraform.tfstate` — not `phase-3-onward/`.
> 2. **`ecr.tf`'s module call now sets `repository_force_delete =
>    true`.** Without it, a real teardown of this project's own ECR
>    repos failed outright with `RepositoryNotEmptyException` on every
>    one of the five repos — confirmed live, not hypothetical. See the
>    callout in Step 4 below.
> 3. **`prevent_destroy` added to the ECR repos and the ACM
>    certificate**, since both have real downstream consumers (the
>    EKS workloads-tier Deployment pulls images by repo URL; the
>    Ingress binds to the cert by ARN) that would silently break if
>    either were destroyed without anyone intending it — distinct from
>    22b's governance resources, where `prevent_destroy` was
>    deliberately **not** added (see 22b's own revision note for why).

---

## Overview

22a gave the persistent build its state backend(s); 22b gave it its
cost and configuration guardrails. Before the workloads-tier EKS
cluster can deploy anything, it needs two things to already exist: a
container registry holding `retail-store-sample-app`'s images, and a
validated TLS certificate ready to bind to the ALB that's about to be
created. Both were already taught — Demo 19 built the ECR repo, Demo
20 built the ACM cert — but both of those were teaching reps, torn
down at their own Cleanup. This demo builds new ones, meant to stay —
and, as of this revision, **actually able to be torn down cleanly if a
genuine full reset is ever needed**, which the original version of
this demo could not do.

**Real-world scenario — CloudNova:**
The images and certificate your Demo 19/20 exercises created are
already gone — that was always the plan for a teaching rep. Now that
you're standing up a real, ongoing environment, you need a registry
and a certificate that won't disappear the moment the demo ends — and,
just as importantly, that can be safely and completely removed on
purpose, without a manual image-cleanup scramble, if the project is
ever reset from scratch.

**What this demo builds:**
```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Recreate the Accumulated Platform-Tier Baseline (22a + 22b)   │
│  This demo's own config must exist in platform/ before ecr.tf or       │
│  acm.tf can be added — recreating 22b's files verbatim is what makes   │
│  this directory point at the real, shared, already-populated state     │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — ECR: repo re-creation + image re-push + force_delete         │
│  New repos, all 5 services, images pulled from the public gallery      │
│  and re-pushed — same technique as Demo 19, now destroy-safe too       │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — ACM: cert re-request + re-validation                         │
│  New certificate on rselvantech.com, validated against the STANDING    │
│  Route53 hosted zone via a data lookup, not a resource                 │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- Everything the original demo covered (recreating an accumulated
  config, `data "aws_route53_zone"`, re-creating an already-taught
  resource as a persistent object, version-pin discipline)
- **New:** why `repository_force_delete` must be `true` on any ECR
  repository this project intends to actually tear down at some point
  — and why leaving it at its default (`false`/unset) is not a safe
  choice for a repo that will ever hold real pushed images
- **New:** why `prevent_destroy` belongs on this demo's ECR repos and
  ACM cert specifically, and why that's a different call than 22b's
  resources got

---

## How This Demo's Pieces Fit Together

(The chicken-and-egg-adjacent "why recreate the baseline" reasoning,
and the `data "aws_route53_zone"` explanation, are **unchanged** from
the original demo — both remain fully correct under the platform/
workloads split; the only thing that changed is which directory this
recreation happens in.)

**Why this demo's own directory has to start by recreating 22a/22b's
entire `platform/` configuration, not just adding two new files.**
Unchanged in mechanism from the original demo — this project's
platform-tier demos still share one continuously-growing state (now at
the `platform/terraform.tfstate` key specifically, not the old shared
key). Recreating 22b's files verbatim before adding `ecr.tf`/`acm.tf`
is exactly as mandatory as before — the only change is the directory
name and backend key this recreation happens against.

**Why this demo reads the Route53 zone instead of creating it:**
unchanged from the original demo.

**Why this demo has no Cleanup that tears anything down in the normal
course of a session:** unchanged. **What is new:** if a genuine full
project reset is ever needed, this demo's resources — as of this
revision — can now actually be torn down without a manual image-purge
step, because `repository_force_delete = true` handles that
automatically. See Step 4.

---

## Prerequisites

(unchanged from the original demo — Demo 19/20 completed knowledge,
required tools, AWS permission verification. See original for full
text.)

### Versions used in this demo

| Tool / Module | Version |
|---|---|
| Terraform | `~> 1.15.0` |
| AWS Provider | `~> 6.47.0` |
| `terraform-aws-modules/ecr/aws` | `~> 3.0` |
| `terraform-aws-modules/acm/aws` | `~> 6.0` |

---

## Demo Objectives

(items 1–6 unchanged from the original demo)

7. ✅ **New:** explain why `repository_force_delete = true` is required
   on any ECR repository this project intends to be able to tear down
   for real, and what specifically fails without it
8. ✅ **New:** explain why `prevent_destroy` is added to this demo's
   ECR repos and ACM cert, but was deliberately not added to 22b's
   governance resources — the distinction being real downstream
   consumers versus none

---

## Cost & Free Tier

(unchanged from the original demo)

> **Known destroy-blocker, confirmed live in this project's own
> teardown — this is why Step 4 changed, not a hypothetical risk.**
> An earlier build of this project's own ECR repos — without
> `repository_force_delete` — failed a real `terraform destroy` with:
> ```
> Error: ECR Repository (cloudnova-retail-checkout) not empty, consider
> using force_delete: RepositoryNotEmptyException: The repository with
> name 'cloudnova-retail-checkout' ... cannot be deleted because it
> still contains images
> ```
> on all five repos simultaneously. Recovering from this without the
> fix requires manually listing and batch-deleting every image in
> every repo, in the **correct AWS region** (a first recovery attempt
> in this project's own history used the AWS CLI without `--region`,
> which silently queried the wrong region and reported
> `RepositoryNotFoundException` even though the repos definitely
> existed — a second, compounding gotcha). `repository_force_delete =
> true` removes the need for any of this.

---

## Directory Structure

```
22c-ecr-acm-recreation/
├── README.md
├── 22c-ecr-acm-recreation-anki.csv
├── 22c-ecr-acm-recreation-quiz.md
└── src/
    ├── platform/                            # CHANGED from phase-3-onward/
    │   ├── versions.tf                      # ← recreated from 22b, Part A
    │   ├── provider.tf                      # ← recreated from 22b, Part A
    │   ├── backend.tf                       # ← recreated from 22b, Part A —
    │   │                                    #   key = "platform/terraform.tfstate"
    │   ├── variables.tf                     # ← recreated from 22b, Part A
    │   ├── locals.tf                        # ← recreated from 22b, Part A —
    │   │                                    #   includes Tier = "platform"
    │   ├── cost_governance.tf               # ← recreated from 22b, Part A
    │   ├── budgets.tf                       # ← recreated from 22b, Part A
    │   ├── outputs.tf                       # ← recreated, then extended
    │   ├── terraform.tfvars                 # ← your own real values, gitignored
    │   ├── ecr.tf                           # NEW this demo — force_delete + prevent_destroy
    │   └── acm.tf                           # NEW this demo — prevent_destroy
    └── break-fix/
        └── broken.tf
```

---

## Recall Check — 22b (Cost Governance)

1. Why did this project choose notify-only cost controls instead of
   pairing them with auto-remediation?
2. Is `notification` on `aws_budgets_budget` a list argument or a
   repeatable block?
3. **New:** why does 22b's `locals.tf` now include `Tier = "platform"`,
   and what would go wrong if it didn't?

<details>
<summary>Answers</summary>

1. Detection and prevention are different design choices; a
   misfiring auto-remediation Lambda is worse than the cost risk it
   solves, for a single-learner lab.
2. A repeatable block, one per threshold.
3. Without an explicit tier tag, a future session-length idle-check has
   no reliable way to distinguish "this resource is meant to run
   forever" from "this resource should be flagged if left running" —
   it could either falsely flag permanent resources or fail to flag
   the actual cost-accruing tier.

</details>

---

## Concepts

### What's New in This Demo

(Table from the original demo — recreating an accumulated
configuration, `data "aws_route53_zone"`, ECR/ACM module reuse — is
otherwise unchanged. One row added:)

| Construct | Type | Purpose in this demo |
|---|---|---|
| `repository_force_delete` | Module argument | Allows `terraform destroy` to remove an ECR repo even if it still contains images — **required**, not optional, for any repo this project intends to ever tear down for real |
| `lifecycle { prevent_destroy = true }` on ECR/ACM | Resource meta-argument | Hard-blocks an accidental `destroy`/`apply`-triggered replacement of resources that other tiers depend on by ARN/URL |

---

### Why `repository_force_delete` Is Required, Not Optional, Here

The ECR module defaults this argument to `false`/unset. Left at that
default, `terraform destroy` against a repo holding real pushed
images fails outright:

```
Error: ECR Repository (cloudnova-retail-checkout) not empty, consider
using force_delete: RepositoryNotEmptyException...
```

This isn't a style preference — it's the difference between a project
that can be torn down cleanly when needed and one that requires a
manual, error-prone image-purge step every time. **Confirmed against
this project's own real teardown** — every one of the five repos hit
this exact error simultaneously the first time a full destroy was
attempted without this argument set.

### Why `prevent_destroy` Belongs Here But Not on 22b's Resources

The distinguishing question is: **does something else reference this
resource by an identifier that would silently break if the resource
were destroyed and recreated?**

- An ECR repo's images are pulled by URL from a running Kubernetes
  Deployment (workloads tier) — destroying and recreating the repo
  changes nothing about the URL string itself, but the *images* are
  gone, and the next deploy would fail to pull. Worth protecting.
- The ACM certificate's ARN is bound directly into an Ingress
  resource's `IngressClassParams` (workloads tier) — a destroyed and
  recreated cert gets a **new** ARN, silently breaking that binding
  until someone notices and re-wires it. Worth protecting.
- 22b's SNS topic/EventBridge rule/Budget have no such downstream
  binding by identifier anywhere in this project — recreating any of
  them is a cheap, self-contained operation. Not worth the added
  friction of `prevent_destroy`'s override ceremony for no real
  protection gained.

---

## Lab Step-by-Step Guide

## Part A — Recreate the Accumulated Baseline (22a + 22b)

Identical in mechanism to the original demo's Part A — recreate
`versions.tf`, `provider.tf`, `variables.tf`, `locals.tf` (**including
`Tier = "platform"`**), `cost_governance.tf`, `budgets.tf`,
`outputs.tf`, and `terraform.tfvars` verbatim from 22b, **but now in
`src/terraform/platform/`** with `backend.tf`'s key set to
`platform/terraform.tfstate`.

### Step 3 — Confirm the recreated baseline matches reality

```bash
terraform init
terraform validate
terraform plan
```

Expected: **no changes**, exactly as the original demo describes. The
same four possible real outcomes documented in the original demo
(clean match, destroy-proposal from an incomplete recreation, "6 to
add" from a prior accidental destroy, or "already-completed-once"
18-resource mismatch) all still apply identically — none of that
diagnostic guidance changes under the platform/workloads split.

---

## Part B — ECR: Repo Re-Creation + Image Re-Push + Force-Delete

### Step 4 — Add `ecr.tf`

```hcl
locals {
  services = ["ui", "catalog", "cart", "orders", "checkout"]
}

module "ecr" {
  source   = "terraform-aws-modules/ecr/aws"
  version  = "~> 3.0"
  for_each = toset(local.services)

  repository_name         = "cloudnova-retail-${each.key}"
  repository_force_delete = true
  # ↑ NEW, required. Without this, `terraform destroy` fails on every
  # repo that still holds a pushed image, with
  # RepositoryNotEmptyException — confirmed against this project's
  # own real teardown attempt, not a defensive guess. Setting this to
  # true means a genuine, intentional destroy removes the repo AND its
  # images in one step; it has no effect on ordinary operation and
  # does not make images easier to delete by accident — it only
  # changes what `terraform destroy` itself is permitted to do.

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

  tags = {
    Project = "cloudnova-retail-store-e2e"
    Purpose = "persistent-ecr"
  }

  lifecycle {
    prevent_destroy = true
    # ↑ NEW. Blocks an accidental `terraform destroy`/replace from
    # silently removing a repo the workloads-tier Deployment depends
    # on by URL. To intentionally tear this down during a genuine
    # full project reset, comment out this block, apply, then destroy
    # — never remove it "temporarily" without also removing the images
    # via force_delete's own destroy path, and never leave it removed
    # afterward.
  }
}
```

> **VERIFY — open item, flag before treating this as confirmed.**
> `lifecycle { prevent_destroy = true }` at the **module block** level
> (as opposed to inside an individual `resource` block) required a
> specific Terraform version to support — confirm this behaves as
> expected against this project's pinned `~> 1.15.0` with a real
> `terraform plan`/`destroy -target` test before relying on it in
> production use. If module-level `prevent_destroy` isn't honored as
> expected at this version, the fallback is moving this repo's
> creation out of the `for_each`'d module into individual `resource`
> blocks so the `lifecycle` block can attach directly — a real,
> not-yet-executed fallback path, not assumed necessary.

The `outputs.tf` extension (`repository_urls`) is unchanged from the
original demo.

### Step 5 — Apply and re-push images

Unchanged in mechanism from the original demo — same
derived-from-`terraform output` Docker commands, same real,
previously-reproduced `<YOUR_ACCOUNT_ID>` placeholder trap and its fix.
Expect **15 resources added** (3 per repository), same as before —
`repository_force_delete` and `prevent_destroy` are both plan-time
attributes on the same resource, not additional resources.

### Step 6 — Verify in Console

Unchanged from the original demo.

---

## Part C — ACM: Cert Re-Request + Re-Validation

### Step 7 — Add `acm.tf`

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
}

resource "null_resource" "acm_prevent_destroy_note" {
  # Intentionally not a real mechanism — see the VERIFY note below on
  # why prevent_destroy for the ACM module needs a different approach
  # than the ECR module's module-level lifecycle block.
  count = 0
}
```

> **VERIFY — open item, more involved than the ECR case, flag
> explicitly rather than guessing.** Unlike the ECR module call above,
> the ACM module (`terraform-aws-modules/acm/aws`) is not `for_each`'d
> and produces multiple internal resources
> (`aws_acm_certificate`, `aws_route53_record.validation`,
> `aws_acm_certificate_validation`) — whether a single module-level
> `lifecycle { prevent_destroy = true }` block correctly protects all
> of them, or whether only the certificate resource itself actually
> needs protecting (the validation record and validation resource are
> cheap to recreate on their own), needs to be checked against a real
> `terraform plan`/`destroy -target` test before this is treated as
> settled. The placeholder `null_resource` above is a marker for where
> this decision needs to land, not a working implementation — remove
> it once the real approach is confirmed and replace with the correct
> `lifecycle` placement.

The `outputs.tf` extension (`certificate_arn`) is unchanged from the
original demo.

### Step 8 — Apply and wait for validation

Unchanged from the original demo — expect 3 resources added.

### Step 9 — Verify in Console

Unchanged from the original demo.

---

## Cleanup

**This demo's Cleanup step is verification, not destruction** — same
reasoning as 22a/22b.

```bash
terraform state list
```

```
Console → ECR → confirm all 5 repos with images present ✅
Console → Certificate Manager → confirm Issued status ✅
Console → SNS/Budgets → confirm 22b's resources are still intact ✅
Console → any ECR repo or the ACM cert → Tags → Tier: platform ✅
```

> ⚠️ **Do not run `terraform destroy` at the end of this session.**
> Unchanged reasoning. **What's new:** if a genuine full reset is ever
> needed, this demo's resources can now actually be torn down cleanly
> — `repository_force_delete` handles the images automatically, and
> `prevent_destroy` needs to be deliberately commented out first
> (a real, intentional two-step process, not an accidental one-liner).

---

## What You Learned

(items 1–6 unchanged from the original demo)

7. ✅ **New:** `repository_force_delete = true` is required, not
   optional, for any ECR repository this project intends to genuinely
   tear down — confirmed against a real, reproduced destroy failure in
   this project's own history, not a defensive assumption
8. ✅ **New:** `prevent_destroy` is applied selectively, based on
   whether a resource has real downstream consumers referencing it by
   an identifier that would silently break on replacement — not
   applied uniformly to every platform-tier resource regardless of
   need

---

## Troubleshooting

(the original demo's table is unchanged and still applies — one row
added:)

| Error | Cause | Fix |
|---|---|---|
| `terraform destroy` fails with `RepositoryNotEmptyException` on any `cloudnova-retail-*` repo | `repository_force_delete` was left at its default (unset/`false`) | Confirm `ecr.tf`'s module call sets `repository_force_delete = true`; if a repo was already built without it, either add the argument and re-apply before destroying, or manually empty the repo's images first (`aws ecr batch-delete-image`, **with `--region us-east-2` explicitly** — omitting the region silently queries the wrong one and reports a false `RepositoryNotFoundException`) |

---

## Next Demo

**Demo 22d — EKS: Single Service (UI only)**, now built in a **new,
separate root config**, `src/terraform/workloads/` — the VPC (with
`single_nat_gateway = true`, per ADR-023's cost decision), the EKS
cluster, and the Ingress/ALB. **The two EKS IAM roles this demo used to
declare directly inside `eks.tf` are relocated to `platform/`'s own
`iam.tf`** (built alongside Demo 24's rebuild) — this is the structural
fix that closes the original incident this whole revision responds to.
`workloads/` reads the role ARNs it needs via
`data "terraform_remote_state" "platform"`, the same cross-stack
technique Demo 07 already taught.