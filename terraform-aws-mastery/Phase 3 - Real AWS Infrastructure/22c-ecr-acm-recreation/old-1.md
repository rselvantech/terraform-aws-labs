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
│  PART A — ECR: repo re-creation + image re-push                        │
│  New repos, all 5 services, images pulled from the public gallery      │
│  and re-pushed — same technique as Demo 19, a new, persistent object   │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — ACM: cert re-request + re-validation                         │
│  New certificate on rselvantech.com, validated against the STANDING    │
│  Route53 hosted zone (never torn down) via a data lookup, not a        │
│  resource                                                                │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- Why re-creating a resource you already built once isn't
  duplicated effort — teaching rep versus persistent object are
  different lifecycles for the same technique
- `data "aws_route53_zone"` — a read-only lookup against
  infrastructure this project's Terraform never creates or destroys
- Why this new ACM cert validates against the same standing hosted
  zone Demo 20's (now-gone) cert did, without recreating the zone itself
- Why this demo's module version pins match Demo 19/20's exactly,
  rather than drifting to older constraints for no stated reason

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** five new ECR repositories (one per
`retail-store-sample-app` service) with their images re-pushed, and one
new ACM certificate validated against `rselvantech.com`. Neither
touches compute — 22d is where the ECR images actually get pulled into
a running Deployment, and where the ALB gets created for the cert to
bind to.

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
- 22a/22b completed — this demo's state lives in 22a's backend

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | `>= 1.15.0` | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version` |
| Docker | Any recent | `docker --version` |

### Verify AWS Account and Permissions

**Step 1 — Confirm your profile works:**

```bash
aws sts get-caller-identity --profile default
```

**Step 2 — A cheap, harmless dry-run of this demo's actual services:**

```bash
aws ecr describe-repositories --profile default
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

No new IAM permissions beyond Demo 19/20's own ECR/ACM/Route53 sets.

### Versions used in this demo

| Tool / Module | Version |
|---|---|
| Terraform | `~> 1.15.0` |
| AWS Provider | `~> 6.47.0` |
| `terraform-aws-modules/ecr/aws` | `~> 3.0` |
| `terraform-aws-modules/acm/aws` | `~> 6.0` |

> **Versions pinned as of September 2026, and deliberately matched to
> Demo 19/20 exactly.** This demo calls the identical two modules
> those demos already taught — there's no reason for the version
> constraints to differ here, and an earlier draft of this demo did
> drift to older constraints (`~> 2.0`/`~> 5.0`) with no stated reason.
> If you ever find a demo reusing a module at a different version than
> where that module was first introduced, treat the mismatch itself as
> worth questioning — either there's a real reason (documented) or it's
> a maintenance slip like this one was.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain why re-creating an already-taught resource for a new,
   persistent purpose isn't redundant with the demo that first taught it
2. ✅ Write a `data "aws_route53_zone"` lookup and use its output in an
   ACM validation record, without ever creating or destroying the zone
3. ✅ Re-push `retail-store-sample-app`'s public images into a new,
   private ECR repo set
4. ✅ Confirm a new ACM certificate reaches `Issued` status against a
   zone this project's Terraform doesn't manage
5. ✅ Recognize when a module version pin has drifted from an earlier
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
    └── phase-3-onward/                     # same config 22a's backend serves
        ├── ecr.tf                          # 5 ECR repos via the registry module
        └── acm.tf                          # ACM cert + data "aws_route53_zone"
```

> **No separate `variables.tf`/`outputs.tf` in this demo.** Every
> value both files need (`repository_name`, `domain_name`, `zone_id`)
> is either a literal string or read directly via `data`/`each.key` —
> there's nothing genuinely variable to parameterize here, so this
> demo doesn't manufacture a `variables.tf` just to match the shape of
> prior demos. If a real deployment needed the domain or service list
> configurable per environment, that would be the point to add one.

---

## Recall Check — 22b (Cost Governance)

> **Correction:** this section previously (incorrectly) pointed at
> Demo 21. Demo 21 isn't the immediately preceding demo for 22c — 22b
> is. Fixed to trace to 22b's actual Key Takeaways instead.

Answer from memory before reading anything new:

1. Why did this project choose notify-only cost controls instead of
   pairing them with auto-remediation?
2. Is `notification` on `aws_budgets_budget` a list argument or a
   repeatable block?
3. Are `tflint` and `checkov` Terraform provisioners?

<details>
<summary>Answers</summary>

1. Detection and prevention are different design choices with
   different failure modes. A misfiring auto-remediation Lambda
   destroying real work-in-progress mid-session is worse than the
   cost risk it would solve, for this single-learner lab.
2. A repeatable block — one `notification` block per independent
   threshold, not a single list argument.
3. No — both are external CLI tools that read `.tf` files directly
   off disk, running entirely outside the `plan`/`apply` cycle. They
   are not Terraform resources or provisioners.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `data "aws_route53_zone"` | Data source | Reads the existing, standing hosted zone's ID — this project's Terraform never creates or destroys the zone itself |
| ECR repo re-creation (module reuse) | Applied pattern, not a new construct | Same `terraform-aws-modules/ecr/aws` module Demo 19 taught, applied to a new, persistent set of repos |
| ACM cert re-request (module reuse) | Applied pattern, not a new construct | Same `terraform-aws-modules/acm/aws` module Demo 20 taught, applied to a new, persistent certificate |

---

### Detailed Explanation of New Constructs

#### `data "aws_route53_zone"` — Reading Infrastructure You Don't Manage

| Argument | Required | Description |
|---|---|---|
| `name` | Yes (or `zone_id`) | The domain name to look up — `rselvantech.com` here |
| `private_zone` | No (default: `false`) | `false` for a standard public hosted zone, which this is |

```hcl
data "aws_route53_zone" "main" {
  name         = "rselvantech.com"
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
from memory instead of copied — worth double-checking against the
original demo every time.

---

## Lab Step-by-Step Guide

---

## Part A — ECR: Repo Re-Creation + Image Re-Push

Part A re-creates all five ECR repositories using the exact module and
version Demo 19 taught, then re-pushes each service's real image into
the new, persistent repos.

### Step 1 — Navigate to the project config

```bash
cd terraform-aws-mastery/phase-3-real-aws-infrastructure/22c-ecr-acm-recreation/src/phase-3-onward
```

### Step 2 — Add ecr.tf

This step calls the ECR module once, `for_each`'d over all five
services, using the exact same version pin Demo 19 established.

Create a file **ecr.tf** and add the below content:

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

  tags = {
    Project = "cloudnova-retail-store-e2e"
    Purpose = "persistent-ecr"
  }
}
```

> **Same-as-Demo-19 note, restated:** the module call itself, and its
> version pin, are unchanged from Demo 19. What's new is the `for_each`
> over all five services in one pass, rather than Demo 19's single-repo
> teaching example — a practical scale-up, not a new construct.

### Step 3 — Apply and re-push images

This step applies the five repositories, then re-authenticates Docker
and re-pushes each service's real published image into the new,
persistent registry.

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

```bash
# Authenticate to your new private ECR
aws ecr get-login-password --region us-east-2 --profile default | \
  docker login --username AWS --password-stdin \
  <YOUR_ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com

# Re-push each service's image — same technique as Demo 19
for svc in ui catalog cart orders checkout; do
  docker pull public.ecr.aws/aws-containers/retail-store-sample-${svc}:latest
  docker tag public.ecr.aws/aws-containers/retail-store-sample-${svc}:latest \
    <YOUR_ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-${svc}:latest
  docker push <YOUR_ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-${svc}:latest
done
```

### Step 4 — Verify in Console

This step confirms in the Console that all five repositories genuinely
hold real images, not just that Terraform reported success.

```
Console → ECR → Repositories → cloudnova-retail-ui (and the other 4)
  → Images tab → latest tag present, real image size shown ✅
```

> 📷 [Screenshot placeholder: AWS Console → ECR → Repositories →
> cloudnova-retail-ui, Images tab showing the latest tag with a real,
> non-zero size]

---

## Part B — ACM: Cert Re-Request + Re-Validation

Part B re-requests and re-validates a new ACM certificate against the
same standing hosted zone, reading its ID via a data lookup instead of
a resource this project's Terraform doesn't manage.

### Step 5 — Add acm.tf

This step reads the standing hosted zone and requests a new
certificate against it, using the exact same module version Demo 20
established.

Create a file **acm.tf** and add the below content:

This file contains the zone lookup and the ACM module call together —
the zone's ID flows directly from the `data` block into the module's
`zone_id` input.

```hcl
data "aws_route53_zone" "main" {
  name         = "rselvantech.com"
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
```

> **What's genuinely new here versus Demo 20:** the `zone_id` argument
> now comes from a `data` lookup instead of a `resource` this
> project's own Terraform created — because in this project, nothing
> ever creates the zone. Demo 20's own module call may have differed
> depending on how that demo's own zone reference was set up; this
> demo's version is the one that matches this project's standing-zone
> design going forward. The module version itself (`~> 6.0`) matches
> Demo 20's exactly — no reason to drift from it.

### Step 6 — Apply and wait for validation

This step applies the certificate request and genuinely waits for AWS
to confirm issuance before `apply` completes.

```bash
terraform plan
terraform apply
```

```
⚠️ Simulated expected output

module.acm.aws_acm_certificate.this[0]: Still creating... [30s elapsed]
module.acm.aws_route53_record.validation["app.rselvantech.com"]: Creating...
module.acm.aws_route53_record.validation["app.rselvantech.com"]: Creation complete
module.acm.aws_acm_certificate_validation.this[0]: Still creating... [1m0s elapsed]
module.acm.aws_acm_certificate_validation.this[0]: Creation complete

Apply complete! Resources: X added, 0 changed, 0 destroyed.
```

> ⚠️ [VERIFY — timing claim, docs only] DNS validation typically
> completes within a few minutes once the record propagates, but exact
> timing depends on real DNS propagation and isn't something this
> demo's text can guarantee — `wait_for_validation = true` makes
> Terraform block until AWS reports the cert as validated, whatever
> that actually takes in your session. The `X` above is left as a
> placeholder deliberately, rather than a guessed number — count the
> resources your own `terraform state list` actually shows once this
> completes, and use that as the real figure going forward.

### Step 7 — Verify in Console

This step confirms in the Console that the new certificate reached
Issued status and that the standing zone itself remains otherwise
unchanged.

```
Console → Certificate Manager → Certificates → app.rselvantech.com
  → Status: Issued ✅ (not Pending validation)

Console → Route53 → Hosted zones → rselvantech.com
  → A new CNAME validation record present ✅
  → The zone itself: still the same standing zone, unchanged otherwise
```

> 📷 [Screenshot placeholder: AWS Certificate Manager → Certificates →
> app.rselvantech.com, showing Status: Issued]

---

## Cleanup

**This demo's Cleanup step is verification, not destruction** — same
reasoning as 22a/22b. These objects are meant to persist for the rest
of the project.

### Step 8 — Confirm everything is in its intended, permanent state

```bash
terraform state list
# module.ecr["ui"].aws_ecr_repository.this[0] (and 4 more)
# data.aws_route53_zone.main
# module.acm.aws_acm_certificate.this[0]
# module.acm.aws_route53_record.validation["app.rselvantech.com"]
# module.acm.aws_acm_certificate_validation.this[0]
```

```
Console → ECR → confirm all 5 repos with images present ✅
Console → Certificate Manager → confirm Issued status ✅
```

> ⚠️ **Do not run `terraform destroy` at the end of this session.**
> 22d's EKS deployment depends on these images and this certificate
> already existing.

---

## What You Learned

1. ✅ Re-creating an already-taught resource for a new, persistent
   purpose is a lifecycle decision, not duplicated teaching.
2. ✅ `data "aws_route53_zone"` reads an existing zone's attributes
   without ever proposing to create, modify, or destroy it — the same
   `data`-vs-`resource` distinction Demo 08/10 first taught.
3. ✅ This project's hosted zone is permanently outside its Terraform's
   management scope — every ACM cert this project ever creates reads
   the zone, never manages it.
4. ✅ `for_each` over a service list scales a single module call to
   multiple repos in one pass — a practical application of a Demo 06/10
   construct, not new syntax.
5. ✅ Reusing a module a second time is exactly the moment a version
   pin can quietly drift — worth explicitly double-checking against
   the demo that first introduced it, not just trusting memory.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `data "aws_route53_zone"` | TA-004 Obj 5a — Data sources | Read-only lookup against infrastructure Terraform doesn't manage |
| ACM DNS validation via a data-sourced zone ID | TA-004 Obj 4a/5a | Same validation mechanics as Demo 20, sourced differently |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Can a `data` block appear in the same config that also manages other real resources?" | Yes — `data` and `resource` blocks freely coexist; a `data` lookup just never appears in `plan`'s create/change/destroy summary the way a managed resource does | Assuming a config is either "all data" or "all resources" |
| "Does re-creating a resource you already built once mean the exam expects you to reference the old one somehow?" | No — a new `resource`/module call with a new state address is a completely independent object, regardless of how similar its configuration looks | Assuming any form of implicit continuity between separately-applied resources |

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
| `no matching Route53Zone found` | `name`/`private_zone` combination doesn't match any real zone in this account | Confirm the exact domain name and whether it's actually a public zone |
| ACM cert stuck at `Pending validation` past a few minutes | DNS validation record hasn't propagated yet, or was written to the wrong zone | Confirm the CNAME record exists in the correct hosted zone via Console, allow more time |
| `RepositoryAlreadyExistsException` | A repo with this name already exists (e.g., from a prior partial apply) | Import the existing repo or choose a different name — same class of naming conflict Demo 01 taught for S3 |
| Module version differs from Demo 19/20 with no obvious reason | A copy-paste or memory slip when reusing a module a second time | Diff this demo's `version` constraint against the original demo's — they should match unless there's a documented reason not to |

---

## Break-Fix Scenario

One deliberate error. Diagnose using `terraform validate` and
`terraform plan` — do not look at the answer first.

```bash
cd src/break-fix/
terraform init
terraform validate
terraform plan
```

This file is a single-resource configuration with one local-name
mismatch between a data source and a reference to it — diagnose it
before revealing the answer.

**broken.tf:**

```hcl
data "aws_route53_zone" "main" {
  name         = "rselvantech.com"
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

</details>

**Cleanup:**

```bash
cd src/break-fix/
terraform destroy -auto-approve
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
```

---

## Interview Prep

**Q1. A teammate says "we already built ECR and ACM in Demo 19/20 — why are we building them again here?" How do you explain this isn't wasted work?**
Because Demo 19 and Demo 20's objects were teaching reps — built specifically to be torn down at the end of their own demo, the same guarantee every Phase 1–2 demo makes. This demo builds new objects using the identical technique, but with a different lifecycle: these are meant to persist for the rest of the project, starting with 22d's EKS deployment pulling images from them and binding its ALB to this certificate. The alternative — exempting Demo 19/20's objects from teardown so this demo could just reuse them — would have quietly broken the "every Phase 1–2 demo tears down, no exceptions" guarantee the whole teaching model depends on, for a fairly small convenience.

**Q2. Someone asks why this demo uses a `data` lookup for the Route53 zone instead of a `resource` block, when Demo 20 might have handled it differently.**
Because this project's Terraform never creates or destroys the hosted zone itself — it was created once, before Demo 20's first build, and deliberately excluded from every teardown cycle in this project. If it were managed as a `resource`, `terraform destroy` would attempt to delete it, which would mean re-pointing the domain registrar's nameservers every time a demo tears down — operationally absurd for infrastructure that's supposed to be a stable, continuous fact about the domain. A `data` lookup gets the zone's ID for writing the validation record without ever putting the zone itself into this project's management scope.

**Q3. A reviewer notices this demo's `ecr.tf`/`acm.tf` pin the exact same module versions as Demo 19/20, and asks whether that's just a coincidence.**
No — it's deliberate, and worth calling out precisely because it's the kind of thing that's easy to get wrong. Reusing a module a second time, from memory or a slightly different starting file, is exactly the situation where a version constraint can quietly drift — typing `~> 2.0` instead of `~> 3.0` doesn't look obviously wrong on its own, it only looks wrong when compared against the demo that originally established the constraint. This demo's own version table exists specifically to make that comparison explicit rather than leaving it to chance.

---

## Key Takeaways

1. **Re-creating a resource is a lifecycle decision, not duplicated
   effort.** The same module or resource type can serve two entirely
   different purposes — teaching once versus supporting an ongoing
   system — without contradiction.

2. **`data` blocks read; `resource` blocks manage.** A hosted zone this
   project never wants to destroy stays a `data` lookup forever, no
   matter how many things depend on its ID.

3. **Standing infrastructure and torn-down teaching reps can coexist
   in the same domain's history.** This project's Route53 zone
   predates and outlives every ACM cert ever validated against it,
   built or torn down, across every demo that touches it.

4. **A familiar construct at a larger scale isn't automatically a new
   concept.** `for_each` across five services here is the same
   mechanic taught in Demo 06/10 — recognize reuse rather than
   re-learning it from scratch every time it appears bigger.

5. **Reusing a module is exactly when a version pin can quietly
   drift.** Diff a reused module's version constraint against the demo
   that first introduced it — don't assume a re-typed number is
   automatically correct just because the rest of the call looks right.

> **Demo scope:** Primary concept: re-creating already-taught ECR and
> ACM objects as persistent, rather than torn-down-teaching-rep,
> infrastructure. Supporting concepts: `data "aws_route53_zone"` as a
> read-only lookup against unmanaged infrastructure, `for_each` reuse
> at module scale, catching version-pin drift when reusing a module a
> second time.
> Estimated completion time: 30–35 minutes (includes real ACM
> validation wait time).
> Checkpoints: 2 natural stopping points (end of Part A, end of
> Part B).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws ecr get-login-password` | Authenticates Docker to a private ECR registry |
| `docker pull` / `tag` / `push` | Standard image re-push flow — pulls from the public gallery, retags, pushes to the new private repo |
| `aws ecr describe-repositories --profile <PROFILE>` | Lists ECR repos to verify creation and permissions |
| `terraform init` / `validate` / `plan` / `apply` | Standard workflow, unchanged from prior demos |

---

## Next Demo

**Demo 22d — EKS: Single Service (UI only):** the EKS cluster and OIDC
identity provider, and the actual teaching content this whole
sub-demo group has been building toward — pulling 22c's images into a
running Kubernetes Deployment behind an ALB using 22c's certificate.
The fourth and last of the four sub-demos that together make up what
was originally planned as a single Demo 22.

> ~~Hold point, per project decision~~ — **resolved via ADR-021:** EKS
> Pod Identity, not IRSA. 22d creates no OIDC identity provider at
> all — this was an open blocker at the time this demo was originally
> written; it's settled now, and 22d's own content reflects that
> resolution throughout.

---

## Appendix — Anki Cards

**22c-ecr-acm-recreation-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::22c-ecr-acm-recreation
#separator:Comma
#columns:Front,Back,Tags
"Why does this demo build new ECR/ACM objects instead of reusing Demo 19/20's?","Demo 19/20's objects were teaching reps, torn down at their own Cleanup like every Phase 1-2 demo. This demo's objects are meant to persist for the rest of the project. Same technique, different lifecycle - not duplicated work.","demo22c,ecr,acm,lifecycle"
"What does data \"aws_route53_zone\" do, and why is it a data block instead of a resource?","Reads an existing hosted zone's attributes (like zone_id) without ever proposing to create, modify, or destroy it. This project's zone is permanently outside Terraform's management scope, so every ACM cert reads it via data, never manages it as a resource.","demo22c,route53,data-sources,ta004-obj5a"
"What would happen if the Route53 hosted zone were managed as a resource instead of read via data?","terraform destroy would attempt to delete the hosted zone, which would mean re-pointing the domain registrar's nameservers every teardown cycle - operationally absurd for infrastructure meant to be a stable, continuous fact about the domain.","demo22c,route53,teardown"
"Is a data block and a resource block ever both present in the same Terraform config?","Yes, freely. A data lookup just never appears in plan's create/change/destroy summary the way a managed resource does - the two coexist normally.","demo22c,data-sources,ta004-obj5a"
"Does re-using a module call with for_each across a list of services introduce new Terraform syntax beyond what for_each itself already taught?","No - it's the same for_each-over-a-set mechanic from Demo 06/10, applied to a module block instead of a plain resource. Recognizing this as reuse-at-scale, not a new concept, is itself a useful skill.","demo22c,for_each,modules"
"Why do this demo's ecr.tf and acm.tf pin the exact same module versions as Demo 19 and Demo 20?","Deliberately, not by coincidence - reusing a module a second time is exactly when a version constraint can quietly drift from memory. This demo's version table exists specifically to make the comparison against the original demo explicit.","demo22c,versioning,gotcha"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the individual facts (why
> re-creation isn't redundant, `data` vs. `resource`, version-pin
> consistency). This Quiz instead works through Break-Fix-style
> diagnosis and a version-drift scenario in applied form, so the two
> together cover recall and applied judgment without restating the
> same question twice.

**22c-ecr-acm-recreation-quiz.md:**

````markdown
# Quiz — Demo 22c: ECR/ACM Re-Creation

> Question types: True/False, Multiple Choice, Multiple Answer —
> matching the real TA-004 exam format.
> Target: 80% or above before moving to Demo 22d.

---

**Q1. (Multiple Choice)** A reviewer notices `ecr.tf` here pins
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
which direction is "right." This demo's own content makes exactly
this mistake worth catching, which is why its version table calls the
comparison out explicitly.

</details>

---

**Q2. (Multiple Choice)** Unlike most other demos in this series, this
demo has no separate `variables.tf` or `outputs.tf` file. Why?

- A) This demo forgot to include them — an oversight
- B) Every value both files need is either a literal string or read directly via `data`/`each.key` — there's nothing genuinely variable to parameterize here
- C) Terraform no longer requires separate variable files as of a recent version
- D) The ECR and ACM modules manage their own variables internally, making a root `variables.tf` redundant

<details>
<summary>Answer</summary>

**B.** This demo's own Directory Structure section states this
directly — a `variables.tf`/`outputs.tf` would exist to serve a
purpose neither file actually has here.

</details>

---

**Q3. (Multiple Choice)** Break-Fix references
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

**Q4. (Multiple Choice)** Step 6's simulated `apply` output shows
`Apply complete! Resources: X added...` with a literal `X`, rather
than a specific number. Why?

- A) The demo's author simply forgot to fill in the number
- B) The exact resource count depends on real DNS validation timing/behavior that can't be guaranteed from documentation alone — the demo asks you to read your own `terraform state list` instead of trusting a guessed figure
- C) ACM certificates never have a fixed, countable number of resources
- D) Terraform intentionally hides resource counts during certificate validation

<details>
<summary>Answer</summary>

**B.** This demo is explicit about this — rather than assert an
unverified number, it directs you to confirm the real count in your
own environment once validation completes.

</details>

---

**Q5. (Multiple Choice)** `data "aws_route53_zone"` includes
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

**Q6. (Multiple Answer — Pick the 2 correct responses)** Which TWO
practices does this demo model for safely reusing a module a second
time in the same project?

- A) Re-typing the version constraint from memory, since the module's inputs are already familiar
- B) Explicitly comparing the reused module's version pin against the demo that first introduced it
- C) Adding a version-pin comparison row directly into the demo's own "why this isn't redundant" table
- D) Assuming the AWS provider will reconcile any version mismatch automatically at apply time

<details>
<summary>Answer</summary>

**B and C.** This demo explicitly calls out matching Demo 19/20's
version pins and builds that comparison directly into its own
Concepts table — the opposite of trusting memory (**A**) or assuming
automatic reconciliation (**D**), neither of which Terraform actually
does.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 5-6/6 | Import Anki cards, move to Demo 22d |
| 4/6 | Review the wrong answers, then proceed |
| 3/6 | Re-read the relevant sections, retry those questions |
| Below 3/6 | Re-read the full demo before proceeding |
````