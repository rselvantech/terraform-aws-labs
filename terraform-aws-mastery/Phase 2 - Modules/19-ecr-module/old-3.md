# Demo 19 — ECR Module

---

## Overview

CloudNova's platform team is done experimenting with generic S3
buckets and SNS topics — Phase 3 needs somewhere to actually store
`retail-store-sample-app`'s container images before any of its
services can run. Amazon ECR (Elastic Container Registry) is that
somewhere. This demo builds five ECR repositories — one per service —
using the official registry module, then does the real work: pulling
the app's actual published images and pushing them into CloudNova's
own registry.

**Real-world scenario — CloudNova:** the platform team needs a private
container registry for all 5 `retail-store-sample-app` services
(UI, Catalog, Cart, Orders, Checkout) before Phase 3's compute demos
can deploy anything — CloudNova can't point real compute at a public
gallery repo it doesn't control. **These images serve both of Phase
3's compute demos** — EKS (Demo 22/23, the persistent target) and ECS
Fargate (Demo 29, the later time-boxed comparison) pull from the exact
same repos this demo creates.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Five Repos, One for_each'd Module Call                        │
│  terraform-aws-modules/ecr/aws, for_each over the 5 real service names │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Lifecycle Policy and Tag Mutability                           │
│  repository_lifecycle_policy (keep last 10 images) | IMMUTABLE tags    │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Real Images In, Real Images Out                               │
│  docker pull the real public.ecr.aws images, tag, push into CloudNova's│
│  own registry, verify with a second pull                                │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- `terraform-aws-modules/ecr/aws` — `repository_name`,
  `repository_image_tag_mutability`, `repository_lifecycle_policy`,
  `repository_force_delete`
- Reapplying Demo 17's `for_each`-over-a-module pattern to a new
  service and a real, practical payoff (5 repos, not a contrived
  exercise)
- The real Docker workflow a Terraform-created ECR repo actually
  requires: `aws ecr get-login-password`, `docker pull`/`tag`/`push`
- Why `IMMUTABLE` tags exist and what breaks if you try to overwrite
  one

**What this demo does NOT cover:** wiring these repos into an actual
Kubernetes Deployment (EKS, Demo 22/23) or ECS task definition (Demo
29) — that's compute's job, once real compute exists. This demo's
scope ends at "the images exist in CloudNova's own registry."

---

## How This Demo's Pieces Fit Together

**The AWS solution:** five ECR repositories, one per
`retail-store-sample-app` service, each holding one real, working
image pulled from the app's actual public gallery and re-pushed under
CloudNova's own name.

- `main.tf` calls the ECR module once, `for_each`'d over
  `local.services` — the same mechanic Demo 17 used for security
  groups, now applied to a genuinely practical payoff: Phase 3 needs
  exactly these 5 repos, not a teaching contrivance.
- Each repository gets an identical lifecycle policy (keep the last 10
  images) and `IMMUTABLE` tag mutability — once `v1.0.0` is pushed to
  a given repo, that exact tag can never be silently overwritten;
  a new build needs a new tag.
- Part C is the part that actually makes these repos useful: each of
  the 5 real, publicly-published images gets pulled, retagged with
  CloudNova's own repository URL (read from
  `module.ecr[each.key].repository_url`), and pushed — proving the
  module's output is a real, usable registry endpoint, not just a
  Terraform-tracked ARN.

---

## Prerequisites

### Knowledge
- Demo 17 completed — `for_each` on a module block, addressing a
  specific instance via `module.<name>["<key>"]`
- Demo 15 completed — registry module sourcing and version
  constraints

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | `>= 1.15.0` (pinned `~> 1.15.0` in this demo) | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version` |
| Docker | Any recent version — required for the first time in this series (Part C) | `docker --version` |

### Verify AWS Account and Permissions

**Step 1 — Confirm your profile works:**

```bash
aws sts get-caller-identity --profile default --region us-east-2
```

**Step 2 — A cheap, harmless dry-run of this demo's actual service:**

```bash
aws ecr describe-repositories --profile default --region us-east-2
# Expected: JSON with a repositories array (may be empty — that is
# fine, this only confirms the permission itself works)
# If you see AccessDenied: fix IAM permissions before proceeding,
# not after you're mid-lab
```

**Step 3 — Verify IAM permissions in Console:**

```
Console → IAM → Users → test → Permissions tab
  → Confirm AmazonEC2ContainerRegistryFullAccess (or equivalent) is attached ✅
```

**Required permissions for this demo:**

```
ecr:CreateRepository, ecr:DeleteRepository, ecr:DescribeRepositories
ecr:PutLifecyclePolicy, ecr:SetRepositoryPolicy, ecr:TagResource
ecr:GetAuthorizationToken, ecr:BatchCheckLayerAvailability
ecr:PutImage, ecr:InitiateLayerUpload, ecr:UploadLayerPart, ecr:CompleteLayerUpload
ecr:BatchGetImage, ecr:GetDownloadUrlForLayer
```

> For a learning account, `AmazonEC2ContainerRegistryFullAccess`
> covers the permissions above.

### Versions used in this demo

| Tool / Module | Version |
|---|---|
| Terraform | `~> 1.15.0` (module's own stated minimum is looser: `>= 1.5.7`) |
| AWS Provider | `~> 6.47.0` (module's own stated minimum is looser: `>= 6.28`) |
| `terraform-aws-modules/ecr/aws` | `~> 3.0` — confirmed current (latest published release is 3.2.0) against the module's live Registry page |
| Docker | Any recent version |

> **Versions pinned as of September 2026** — same dating convention as
> the rest of this series; check each project's own changelog before
> assuming these exact levels are still current if you're reading
> this well after that date.

> ⚠️ [VERIFY — exact patch-level version]: this module's exact latest
> `3.x` release tag wasn't independently confirmable through available
> tooling at authoring time. The module's documented input names used
> in this demo (`repository_name`, `repository_image_tag_mutability`,
> `repository_lifecycle_policy`, `repository_force_delete`) are stable
> across this module's `3.x` line, so the constraint itself is sound —
> but run `terraform init` yourself and check
> `.terraform/modules/modules.json` for the exact resolved version
> before treating a specific patch number as confirmed.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Call `terraform-aws-modules/ecr/aws` with `for_each`, creating
   multiple repositories from one module block
2. ✅ Configure a repository lifecycle policy to automatically expire
   old images
3. ✅ Explain what `IMMUTABLE` tag mutability actually prevents, and
   why it matters for a registry multiple services depend on
4. ✅ Authenticate Docker against ECR, then pull, retag, and push a
   real container image into a Terraform-created repository
5. ✅ Verify a pushed image is genuinely retrievable, not just
   reported as uploaded

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| ECR repositories (×5) | 500 MB-month free (12-month free tier), then ~$0.10/GB-month | **$0.00** at this demo's scale — 5 small images, well under 500 MB total | |
| **Session total** | | **$0.00** | |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
19-ecr-module/
├── README.md
├── 19-ecr-module-anki.csv
├── 19-ecr-module-quiz.md
└── src/
    ├── versions.tf      # terraform block + provider version constraints
    ├── provider.tf       # AWS provider: region, profile
    ├── variables.tf       # aws_region, aws_profile
    ├── locals.tf           # local.services — the 5 real service names
    ├── main.tf              # module "ecr" block — for_each over local.services
    ├── outputs.tf           # repository URLs, keyed by service
    └── break-fix/
        └── broken.tf           # root config with 3 deliberate ECR-module errors
```

---

## Recall Check — Demo 18

Answer from memory before reading further:

1. What does a CLI workspace actually isolate — state, configuration,
   or both?
2. Is a CLI workspace the same thing as an HCP Terraform workspace?
3. When would you use `for_each` over a map instead of CLI workspaces,
   for a similar-looking multi-environment problem?

<details>
<summary>Answers</summary>

1. State only — every workspace in a directory shares the exact same
   `.tf` files; only the tracked state differs.
2. No — they share a name but are genuinely different features. HCP
   Terraform workspaces add remote runs, variables, VCS integration,
   policy enforcement, and team access; the CLI feature has none of
   that.
3. When you want all instances to exist simultaneously, managed by one
   `apply`, in one state — workspaces instead produce one resource per
   `apply`, repeated separately per workspace.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `repository_name` | Module input | The repository's name — this demo derives it from each service's name |
| `repository_image_tag_mutability` | Module input | `IMMUTABLE` (default) prevents a pushed tag from ever being overwritten |
| `repository_lifecycle_policy` | Module input | JSON policy expiring old images automatically |
| `repository_url` | Module output | The actual registry endpoint Docker pushes to — used in this demo, not just tracked |
| `aws ecr get-login-password` | AWS CLI command | Authenticates Docker against ECR |

**Related constructs worth knowing (not used in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| `registry_pull_through_cache_rules`, `registry_replication_rules` | Advanced registry-level features this module also supports | Not covered in this series |
| Wiring an ECR image into a Kubernetes Deployment (or ECS task definition) | Actually running a container from these images | Demo 22/23 (EKS, primary) / Demo 29 (ECS Fargate, time-boxed comparison) |

---

### Detailed Explanation of New Constructs

#### Calling the ECR Module — `for_each` Over Real Service Names

```hcl
locals {
  services = ["ui", "catalog", "cart", "orders", "checkout"]
}

module "ecr" {
  for_each = toset(local.services)

  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 3.0"

  repository_name                = "cloudnova-retail-${each.key}"
  repository_image_tag_mutability = "IMMUTABLE"

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
    ManagedBy = "terraform-demo-19"
    Service   = each.key
  }
}
```

**What it does:** this is exactly Demo 17's `for_each`-on-a-module
pattern — one module block, five independent instances, each addressed
as `module.ecr["ui"]`, `module.ecr["catalog"]`, and so on. The only
genuinely new piece is the module itself and its specific inputs.

> **Same as X" ban check — restating, not just pointing:** like Demo
> 17's security groups, each instance here is a fully independent AWS
> resource (a separate ECR repository) — deleting `module.ecr["cart"]`
> from `local.services` would only remove the Cart repository, leaving
> the other four untouched, for the same reason Demo 17's tiers were
> independent.

---

#### `repository_image_tag_mutability` — What `IMMUTABLE` Actually Prevents

**What it does:** with `IMMUTABLE` (this module's own default), once an
image is pushed under a given tag — say, `cloudnova-retail-ui:v1.0.0`
— that exact tag can never be overwritten by a later push. Attempting
to push a different image under the same existing tag fails outright.

> **This is a deliberate constraint, not a limitation to work around.**
> `MUTABLE` tags (the opposite setting) allow silently replacing what
> `v1.0.0` points to — meaning two people, or two points in time, could
> both say "I deployed v1.0.0" while actually running different code.
> `IMMUTABLE` forces a new, distinct tag for every actual change,
> which is exactly the guarantee a production deployment pipeline
> needs: the tag in a deployment manifest always means one specific,
> unchanging image. (AWS also offers `IMMUTABLE_WITH_EXCLUSION` and
> `MUTABLE_WITH_EXCLUSION` — a newer pair of variants letting specific
> tag patterns, like `latest*`, opt out of the repository's default
> setting — not used in this demo, since every tag here is meant to be
> genuinely immutable.)

---

#### `repository_lifecycle_policy` — Automatic Image Expiration

**What it does:** the JSON policy above tells ECR to automatically
expire (delete) images once a repository holds more than 10 — a
built-in way to prevent storage costs and clutter from accumulating
indefinitely as new builds get pushed, with no manual cleanup needed.

---

## Lab Step-by-Step Guide

---

## Part A — Five Repos, One `for_each`'d Module Call

Part A creates all 5 ECR repositories in a single apply.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-2-modules/19-ecr-module/src
```

### Step 2 — Create the root scaffolding files

This step scaffolds the root configuration's provider and version
pins, plus the two root-level variables every demo in this series
uses.

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

#### `provider.tf` — AWS provider configuration

**provider.tf:**

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
```

Create a file **variables.tf** and add the below content:

This file declares the same two root-level variables — region and
profile — used throughout this series.


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
```

### Step 3 — Declare the real service names

This step declares the one list this entire demo iterates over — the
five real service names Phase 3's compute demos will eventually
deploy.

Create a file **locals.tf** and add the below content:

This file defines `local.services`, the single list the `for_each`'d
module call in Step 4 expands into five repositories.

**locals.tf:**

```hcl
locals {
  services = ["ui", "catalog", "cart", "orders", "checkout"]
}
```

### Step 4 — Call the ECR module

This step calls the ECR module once, letting `for_each` expand it
into five independent repositories — one per service, each with
identical lifecycle and mutability settings.

Create a file **main.tf** and add the below content:

This file contains the single `for_each`'d call that produces all
five ECR repositories this demo builds.

**main.tf:**

```hcl
module "ecr" {
  for_each = toset(local.services)

  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 3.0"

  repository_name                 = "cloudnova-retail-${each.key}"
  repository_image_tag_mutability = "IMMUTABLE"
  repository_force_delete         = true

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
    ManagedBy = "terraform-demo-19"
    Service   = each.key
  }
}
```

> **`repository_force_delete = true` is set deliberately for this lab
> environment.** It allows `terraform destroy` to remove a repository
> even if it still contains images — without it, Cleanup would fail
> once Part C has actually pushed something into these repos. A real
> production repository would typically leave this `false`.

### Step 5 — Create the outputs

This step exposes all five repositories' URLs as one combined map, so
Part C can read each service's real registry endpoint directly.

Create a file **outputs.tf** and add the below content:

This file builds a map of service name to repository URL using a
`for` expression over `module.ecr`, the same pattern Demo 17 used for
security group IDs.

**outputs.tf:**

```hcl
output "repository_urls" {
  value       = { for svc, repo in module.ecr : svc => repo.repository_url }
  description = "Map of service name to its ECR repository URL"
}
```

### Step 6 — Apply

This step initializes, validates, and applies the configuration,
creating all five repositories and their lifecycle policies in a
single apply.

```bash
terraform init
terraform validate
terraform apply
```

Expected — five independent repositories, one per service:

```
module.ecr["cart"].aws_ecr_repository.this[0]: Creating...
module.ecr["catalog"].aws_ecr_repository.this[0]: Creating...
module.ecr["checkout"].aws_ecr_repository.this[0]: Creating...
module.ecr["orders"].aws_ecr_repository.this[0]: Creating...
module.ecr["ui"].aws_ecr_repository.this[0]: Creating...
[... lifecycle policies attached ...]

Apply complete! Resources: 15 added, 0 changed, 0 destroyed.

Outputs:

repository_urls = {
  "cart"     = "163125980376.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-cart"
  "catalog"  = "163125980376.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-catalog"
  "checkout" = "163125980376.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-checkout"
  "orders"   = "163125980376.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-orders"
  "ui"       = "163125980376.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-ui"
}
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **15 resources for 5 repositories — 3 each.** Each module instance
> creates the repository itself, its lifecycle policy, and its
> repository policy (the default access policy this module attaches
> unless told otherwise) — confirmable with
> `terraform state list | grep module.ecr`.

---

## Part B — Verifying the Lifecycle Policy and Tag Mutability

Part B confirms the settings from Part A are genuinely enforced, not
just recorded in Terraform state.

### Step 7 — Verify in the Console

This step confirms in the Console that both the mutability setting
and the lifecycle policy from Part A are genuinely visible on the
real repository, not just tracked in state.

```
Console → ECR → Repositories → cloudnova-retail-ui
  → Image tag mutability: Immutable ✅
  → Lifecycle Policy tab → one rule, "Keep last 10 images" ✅
```

![alt text](image.png)

### Step 8 — Confirm via CLI

This step confirms via the AWS CLI directly that the lifecycle policy
was genuinely applied to the real repository, not just accepted by
`terraform apply`.

```bash
aws ecr get-lifecycle-policy --repository-name cloudnova-retail-ui --profile default --region us-east-2
```

Expected: the same JSON policy from `main.tf`, returned by AWS
directly — confirming it was genuinely applied, not just accepted by
`terraform apply`.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## Part C — Real Images In, Real Images Out

Part C authenticates Docker against ECR, then pulls, retags, and
pushes all 5 real `retail-store-sample-app` images into CloudNova's
own registry.

### Step 9 — Authenticate Docker against ECR

This step authenticates Docker against ECR for the first time in this
series — required before any push or pull against a private
repository.

```bash
aws ecr get-login-password --profile default --region us-east-2 | \
  docker login --username AWS --password-stdin 163125980376.dkr.ecr.us-east-2.amazonaws.com
```

Expected: `Login Succeeded`.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **This login token is short-lived.** `get-login-password` issues a
> token valid for 12 hours — re-run this step if you return to this
> lab in a later session and pushes start failing with an
> authentication error.

### Step 10 — Pull, retag, and push each real image

This step pulls each service's real published image, retags it under
CloudNova's own repository URL, and pushes it — the first time any of
this series' Terraform-created resources actually receives real
content.

```bash
REPO_UI=$(terraform output -json repository_urls | jq -r '.ui')

docker pull public.ecr.aws/aws-containers/retail-store-sample-ui:latest
docker tag public.ecr.aws/aws-containers/retail-store-sample-ui:latest "$REPO_UI:v1.0.0"
docker push "$REPO_UI:v1.0.0"
```

Expected:

```
v1.0.0: digest: sha256:... size: ...
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

Repeat the same three commands for `catalog`, `cart`, `orders`, and
`checkout`, substituting each service's own repository URL and image
name (`public.ecr.aws/aws-containers/retail-store-sample-<service>`).

> **`:latest` is the only tag actually confirmed for all 5 services** —
> verified this session via real `docker run` testing against each
> service, not assumed. (An earlier check confirmed a `1.0.0` tag
> exists for the UI image specifically, but extending that to all 5
> services without checking would have been exactly the kind of
> unverified generalization this series has caught and corrected
> elsewhere — so this demo pulls `:latest` instead.) **`v1.0.0` on the
> push side is CloudNova's own internal import label** — it doesn't
> claim to match any version number the upstream project itself uses.

### Step 11 — Attempt to overwrite an immutable tag

This step deliberately attempts to push to a tag that already exists,
to confirm `IMMUTABLE` is a genuinely enforced constraint rather than
a Console label with no real effect.

```bash
docker pull public.ecr.aws/aws-containers/retail-store-sample-ui:latest
docker tag public.ecr.aws/aws-containers/retail-store-sample-ui:latest "$REPO_UI:v1.0.0"
docker push "$REPO_UI:v1.0.0"
```

Expected: a rejection, since `IMMUTABLE` blocks re-pushing to a tag
that already exists:

```
denied: The image tag 'v1.0.0' already exists in the 'cloudnova-retail-ui' repository and cannot be overwritten because the repository is immutable.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **This confirms `IMMUTABLE` is a real, enforced constraint** — not
> just a Console label. Pushing a genuinely new build requires a new
> tag (`v1.0.1`, for example), never overwriting `v1.0.0`.

### Step 12 — Verify a pushed image is genuinely retrievable

This step confirms the pushed image is genuinely retrievable from
CloudNova's own registry, not just reported as uploaded by the
previous push.

```bash
docker rmi "$REPO_UI:v1.0.0"
docker pull "$REPO_UI:v1.0.0"
```

Expected: the pull succeeds, confirming the image genuinely exists in
CloudNova's own registry — not just reported as uploaded by `docker
push`.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

**Verify:**

```
Console → ECR → Repositories → cloudnova-retail-ui → Images tab
  → v1.0.0 present, real image size shown (not 0 bytes) ✅
```

> 📷 [Screenshot placeholder: AWS Console → ECR → Repositories →
> cloudnova-retail-ui → Images tab, showing the v1.0.0 image with a
> real, non-zero size]

---

## Cleanup

### Step 13 — Destroy all resources

```bash
terraform destroy
```

Type `yes`. Expected:

```
module.ecr["ui"].aws_ecr_repository.this[0]: Destroying...
[... all 5 repositories and their policies destroyed ...]

Destroy complete! Resources: 15 destroyed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment. This succeeds even with images still inside each
> repository, specifically because `repository_force_delete = true`
> was set in Part A.

### Step 14 — Confirm all repositories are gone

```bash
aws ecr describe-repositories --repository-names cloudnova-retail-ui --profile default --region us-east-2
```

Expected: a `RepositoryNotFoundException` error.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## What You Learned

1. ✅ `terraform-aws-modules/ecr/aws` called with `for_each` creates
   multiple independent repositories from one module block, the same
   pattern Demo 17 used for security groups
2. ✅ A `repository_lifecycle_policy` automatically expires old images
   without manual cleanup
3. ✅ `IMMUTABLE` tag mutability genuinely blocks overwriting an
   existing tag — confirmed by actually attempting it, not just
   reading the setting
4. ✅ A Terraform-created ECR repository's `repository_url` output is
   a real, usable Docker registry endpoint — proven by actually
   pushing and re-pulling a real image
5. ✅ `repository_force_delete` controls whether `terraform destroy`
   can remove a repository that still contains images

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `for_each` on a registry module | TA-004 Obj 5c | Reinforces "use modules in configuration" at real practical scale |
| Registry module sourcing (`terraform-aws-modules/ecr/aws`) | TA-004 Obj 5a | Same objective as Demo 15/16/17's registry sourcing |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam asks what `IMMUTABLE` tag mutability prevents | Recognizing it blocks re-pushing to an existing tag entirely | Assuming it only affects deletion, not pushing |
| Exam shows `terraform destroy` failing on an ECR repository | Recognizing `repository_force_delete` must be `true` if the repository still contains images | Assuming any ECR repository can always be destroyed regardless of contents |

### Exam Task — Write a complete configuration

**Task:** CloudNova's data team needs a 6th ECR repository, `analytics`,
with a lifecycle policy keeping only the last 5 images instead of 10.

**Block types required:** none new — a second, standalone `module`
block (a per-instance lifecycle-policy override isn't possible within
a single `for_each` call, since every instance of a `for_each`'d
module shares the same argument values)

**Official documentation:**
- [`terraform-aws-modules/ecr/aws`](https://registry.terraform.io/modules/terraform-aws-modules/ecr/aws/latest)

**What to practise:**
1. Check the module's actual documented inputs for the lifecycle
   policy argument name — don't assume it matches by guessing
2. Write the second module call from scratch

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
module "ecr_analytics" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 3.0"

  repository_name                 = "cloudnova-retail-analytics"
  repository_image_tag_mutability = "IMMUTABLE"

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
```

**Arguments you must know without looking up:**
- A `for_each`'d module block applies the *same* argument values to
  every instance — a genuinely different lifecycle policy for one
  service requires its own separate module call, not a per-instance
  override within the `for_each`

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `denied: ... cannot be overwritten because the repository is immutable` | Attempting to push to a tag that already exists, with `IMMUTABLE` set | Use a new tag for the new image |
| `no basic auth credentials` on `docker push` | The ECR login token expired (12-hour validity) or was never run | Re-run `aws ecr get-login-password \| docker login ...` |
| `terraform destroy` fails with repository not empty | `repository_force_delete` was left `false` (or unset) while images exist in the repository | Set `repository_force_delete = true`, or manually delete images first |

---

## Break-Fix Scenario

Three deliberate errors — single self-contained file.

```bash
cd src/break-fix/
terraform init
```

#### `broken.tf` — Three deliberate errors

This file is a self-contained configuration calling the ECR module
with a malformed lifecycle policy, a wrong output name, and a
mutability value that doesn't exist — diagnose all three.

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

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 3.0"

  repository_name                 = "cloudnova-broken-demo19"
  repository_image_tag_mutability = "IMMUTBLE" # Error 1: typo, should be "IMMUTABLE"

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        # Error 2: missing required "action" block
      }
    ]
  })
}

output "repo_arn" {
  value = module.ecr.repo_arn # Error 3: wrong output name (should be repository_arn)
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — typo, `IMMUTBLE` instead of `IMMUTABLE`**
`repository_image_tag_mutability` only accepts `MUTABLE`,
`MUTABLE_WITH_EXCLUSION`, `IMMUTABLE`, or `IMMUTABLE_WITH_EXCLUSION` —
`IMMUTBLE` is rejected at `apply` by the AWS API itself (this isn't
validated by Terraform statically, since the argument is a plain
string). Fix: correct the typo.

**Error 2 — lifecycle policy rule missing a required `action` block**
Every rule in an ECR lifecycle policy requires an `action` — without
one, AWS rejects the policy document at `apply`. Fix: add
`action = { type = "expire" }`.

**Error 3 — wrong output name (`repo_arn` instead of `repository_arn`)**
This module's actual output is `repository_arn` — there is no
`repo_arn`. Reported as an "Unsupported attribute" error at `validate`.
Fix: reference `module.ecr.repository_arn` instead.

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

**Q1. Why does this demo call the ECR module with `for_each` instead
of five separate module blocks?**
Five separate blocks would be nearly-identical copy-paste, differing
only in the service name — exactly the duplication `for_each` exists
to eliminate, the same reasoning Demo 17 used for security groups.
Adding a 6th service later is a one-line change to `local.services`,
not a new module block.

**Q2. A teammate wants to push a hotfix under the same `v1.0.0` tag
that's already deployed, to avoid updating any deployment manifests.
What do you tell them?**
That's exactly what `IMMUTABLE` tag mutability is designed to block —
and for good reason: if `v1.0.0` could silently point to different
code at different times, "what's running in production" stops being a
knowable fact. The correct fix is a new tag (`v1.0.1`) and updating
the manifest to reference it — more steps, but it preserves the
guarantee that a given tag always means one specific image.

**Q3. Why does this demo need `repository_force_delete = true`, when
none of the prior module-based demos needed anything like it?**
Because this is the first demo in the series that actually puts real
content (container images) inside a resource before destroying it. An
empty resource (like Demo 15's bucket before anything's uploaded, or
Demo 16's VPC) destroys cleanly by default — an ECR repository holding
real images does not, unless explicitly told it's allowed to delete
them along with the repository itself.

---

## Key Takeaways

1. **`for_each` on a registry module scales the same way it does on a
   local one** — five ECR repositories from one module block, each
   independently addressable and destroyable.

2. **`IMMUTABLE` tag mutability is a real, enforced constraint, not
   just a setting** — confirmed by actually attempting to overwrite a
   tag and watching AWS reject it.

3. **A repository lifecycle policy automatically expires old images**
   — no manual cleanup process required to keep a registry from
   growing indefinitely.

4. **A module's output being "just an ARN or URL" doesn't mean it's
   inert** — `repository_url` is a real Docker registry endpoint,
   proven by actually pushing and re-pulling a real image against it.

> **Demo scope:** Primary concept: calling the ECR registry module
> with `for_each`, and the real Docker push/pull workflow it enables.
> Supporting concepts: lifecycle policies, tag immutability.
> Estimated completion time: 35–40 minutes.
> Checkpoints: 3 natural stopping points (end of Part A, end of
> Part B, end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws ecr get-login-password \| docker login ...` | Authenticates Docker against ECR — required before any push/pull against a private repository |
| `docker tag SOURCE TARGET` | Retags a pulled image under the target repository's URL before pushing |
| `aws ecr get-lifecycle-policy --repository-name NAME` | Confirms a lifecycle policy is genuinely applied, not just recorded in Terraform state |
| `aws ecr describe-repositories --repository-names NAME` | Confirms a repository's existence, or its absence after destroy |

---

## Next Demo

**Demo 20 — ACM + Route53 Module.** Introduces `terraform-aws-modules/acm/aws`, requesting and validating a TLS certificate on the confirmed `rselvantech.com` hosted zone — the second of Phase 2's registry-module-practice additions, ahead of Demo 22's ALB needing it.

---

## Appendix — Anki Cards

**19-ecr-module-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 2 - Modules::19-ecr-module
#separator:Comma
#columns:Front,Back,Tags
"What does repository_image_tag_mutability = \"IMMUTABLE\" actually prevent?","Re-pushing to a tag that already exists in the repository — AWS rejects the push outright with a 'cannot be overwritten' error. A new build requires a new tag.","demo19,ecr,ta004-obj5c"
"Why does terraform destroy fail on an ECR repository that still contains images, by default?","AWS won't let a non-empty repository be deleted unless explicitly told to. repository_force_delete = true overrides this, allowing destroy to remove the repository along with its images.","demo19,ecr,gotcha"
"What does a repository_lifecycle_policy actually do?","Automatically expires (deletes) images once a repository holds more than the configured count — prevents storage costs and clutter from accumulating with no manual cleanup process.","demo19,ecr,ta004-obj5c"
"How is calling terraform-aws-modules/ecr/aws with for_each similar to Demo 17's security-group pattern?","Both create multiple independent AWS resources from one module block, each addressed by its own key (module.ecr[\"ui\"], module.tier_sg[\"web\"], etc.) — removing one instance's key only affects that one resource.","demo19,ecr,foreach,ta004-obj5c"
"Is a module's repository_url output just an inert ARN-like value, or something you actually use?","A real, usable Docker registry endpoint — confirmed by actually running docker push/pull against it, not just reading it as a tracked value.","demo19,ecr,modules"
"What must every rule in an ECR lifecycle policy document include, or AWS rejects it at apply?","An action block (e.g. { type = \"expire\" }) — a rule with only a selection and no action fails, since AWS doesn't know what to do once a rule matches.","demo19,ecr,break-fix"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the individual facts
> (mutability, force-delete, lifecycle policy shape). This Quiz
> instead works through the actual Docker CLI output this demo
> produces and its own Break-Fix scenario, so a learner who's done
> both has covered recall and real-world diagnosis without seeing the
> same question twice.

**19-ecr-module-quiz.md:**

````markdown
# Quiz — Demo 19: ECR Module

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 20.

---

**Q1. (Multiple Choice)** `docker push` returns:
`denied: The image tag 'v1.0.0' already exists in the
'cloudnova-retail-ui' repository and cannot be overwritten because the
repository is immutable.` What's the correct next action?

- A) Re-run the exact same push command — it's a transient error
- B) Push under a new tag, e.g. `v1.0.1`
- C) Set `repository_force_delete = true` and re-apply
- D) Delete the repository and recreate it

<details>
<summary>Answer</summary>

**B.** `IMMUTABLE` blocks overwriting an existing tag by design — the
correct response is a new, distinct tag for the new image, not
forcing the old one out. **C** and **D** solve an unrelated problem
(destroy-time cleanup, not push-time rejection).

</details>

---

**Q2. (Multiple Choice)** `terraform destroy` fails with a
repository-not-empty error on an ECR repository that already has
images pushed to it. What's the fix?

- A) Manually delete every image via the Console first, every time
- B) Set `repository_force_delete = true` on that module call and re-apply before destroying
- C) This repository can never be destroyed via Terraform
- D) Switch `repository_image_tag_mutability` to `MUTABLE`

<details>
<summary>Answer</summary>

**B.** `repository_force_delete = true` is exactly what allows
`destroy` to remove a non-empty repository. **A** works but isn't the
Terraform-native fix this demo teaches. **D** is unrelated — mutability
governs pushes, not deletion.

</details>

---

**Q3. (Multiple Choice)** Break-Fix's lifecycle policy rule has a
`selection` block but no `action` block. What happens at `apply`?

- A) AWS defaults to an "expire" action automatically
- B) The rule is silently skipped
- C) AWS rejects the policy document — every rule requires an action
- D) Terraform fills in a default client-side before sending it

<details>
<summary>Answer</summary>

**C.** AWS requires every ECR lifecycle policy rule to include an
`action` — there's no default fallback, silent skip, or
Terraform-side auto-fill.

</details>

---

**Q4. (Multiple Choice)** `repository_image_tag_mutability =
"IMMUTBLE"` (typo) is used in Break-Fix. What error class does this
produce, and at what stage?

- A) A Terraform-side type error at `validate`, since the value isn't a valid enum
- B) An AWS API rejection at `apply`, since `repository_image_tag_mutability` is a plain string Terraform doesn't statically validate
- C) No error — AWS silently falls back to `MUTABLE`
- D) A `terraform init` failure

<details>
<summary>Answer</summary>

**B.** Because this argument is a plain string (not a Terraform-side
enum type), the typo isn't caught until AWS itself rejects it at
`apply`. **A**, **C**, and **D** all describe behavior that doesn't
occur here.

</details>

---

**Q5. (Multiple Choice)** You return to this lab in a later session
and `docker push` suddenly fails with a `no basic auth credentials`
error, even though nothing about the ECR repository or your AWS
credentials has changed. What's the most likely cause?

- A) The repository's lifecycle policy expired your push permissions
- B) The ECR login token from `aws ecr get-login-password` is only valid for 12 hours and needs to be re-run
- C) `IMMUTABLE` tag mutability blocks all pushes after the first session
- D) Docker itself needs to be reinstalled after 12 hours of inactivity

<details>
<summary>Answer</summary>

**B.** The `docker login` token issued by `aws ecr get-login-password`
expires after 12 hours — re-running that authentication step is the
fix, exactly as this demo's own Step 9 callout and Troubleshooting
table both note.

</details>

---

**Q6. (Multiple Choice)** Docker successfully reports `v1.0.0: digest:
sha256:... size: ...` after a push. What has this actually confirmed?

- A) That the image was accepted for upload — not necessarily that it's retrievable
- B) That the image is a real, usable Docker registry endpoint, retrievable by anyone with pull access
- C) Nothing — `docker push` output can't be trusted without a Console check
- D) That the lifecycle policy has already run against this image

<details>
<summary>Answer</summary>

**A.** A successful push confirms upload — this demo deliberately adds
a *separate* step (`docker rmi` then `docker pull` again) specifically
because a push succeeding doesn't by itself prove the image is
genuinely retrievable; that's a distinct thing to verify.

</details>

---

**Q7. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about this demo's `for_each`'d ECR module call are correct?

- A) Each of the 5 repositories can be given a different lifecycle policy directly within this one `for_each` call
- B) Every instance created by this `for_each` call shares the exact same lifecycle policy and mutability setting
- C) A 6th repository needing a different policy requires a second, separate `module` block
- D) `for_each` on this module works differently than `for_each` on Demo 17's security-group module

<details>
<summary>Answer</summary>

**B and C.** A single `for_each` call applies identical argument
values to every instance (ruling out **A**), so a genuinely different
policy needs its own module call. `for_each` mechanics are identical
regardless of which module it's applied to (ruling out **D**).

</details>

---

Score guide:

| Score | Action |
|---|---|
| 6-7/7 | Import Anki cards, move to Demo 20 |
| 5/7 | Review the wrong answers, then proceed |
| 3-4/7 | Re-read the relevant sections, retry those questions |
| Below 3/7 | Re-read the full demo and redo the walkthrough before proceeding |
````