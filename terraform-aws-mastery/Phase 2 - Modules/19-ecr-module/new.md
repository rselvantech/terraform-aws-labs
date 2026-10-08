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
  requires: `aws ecr get-login-password`, `docker pull`/`tag`/`push`,
  **run separately and explicitly for each of the 5 services** — not
  as one command "repeated with substitution"
- Why `IMMUTABLE` tags exist and what breaks if you try to overwrite
  one
- Why `docker login` succeeding doesn't guarantee a later `docker
  push` will work, if the two target different registries

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
  Terraform-tracked ARN. **All five services are pushed independently,
  with their own dedicated shell variable — never one shared variable
  reused across services.**

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
| `jq` | Any recent version — used to read the `repository_urls` output map | `jq --version` |

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
| `terraform-aws-modules/ecr/aws` | `~> 3.0` — confirmed against a real `terraform init`, which resolved to `3.2.0` |
| Docker | Any recent version |

> **Versions pinned as of September 2026** — same dating convention as
> the rest of this series; check each project's own changelog before
> assuming these exact levels are still current if you're reading
> this well after that date.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Call `terraform-aws-modules/ecr/aws` with `for_each`, creating
   multiple repositories from one module block
2. ✅ Configure a repository lifecycle policy to automatically expire
   old images
3. ✅ Explain what `IMMUTABLE` tag mutability actually prevents, and
   why it matters for a registry multiple services depend on
4. ✅ Authenticate Docker against ECR **correctly, against the
   registry you're actually pushing to** — not a hardcoded example
   value — then pull, retag, and push all 5 real container images into
   their own, correctly-scoped repositories
5. ✅ Explain why `docker login` succeeding is not sufficient proof
   that a later `docker push` will succeed
6. ✅ Verify a pushed image is genuinely retrievable, not just
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

#### What the Module Actually Creates Per Repository — Confirmed Against a Real `apply`

Each `for_each` instance produces three resources, not one — confirmed
directly in a real `terraform plan`:

- `aws_ecr_repository` — the repository itself, with
  `encryption_configuration { encryption_type = "AES256" }` and
  `image_scanning_configuration { scan_on_push = true }` both enabled
  **by default**, even though neither is set explicitly in this demo's
  `main.tf`. Worth knowing these are the module's own defaults, not
  something this configuration turned on deliberately.
- `aws_ecr_lifecycle_policy` — the JSON policy from Part A.
- `aws_ecr_repository_policy` — a **default resource-based policy**
  the module attaches automatically: a `PrivateReadOnly` statement
  granting the calling account's own root principal a set of read-only
  ECR actions (`ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage`,
  `ecr:DescribeImages`, and similar). This demo never explicitly
  requested this policy — the module builds it internally, reading
  `data.aws_caller_identity` and `data.aws_partition` to construct it,
  which is why a real `apply` shows those two data sources being read
  before anything is created.

This is why Part A's apply reports **15 resources for 5
repositories — 3 each**, confirmed against a real run, not just
theoretical.

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

#### Why `docker login` Succeeding Doesn't Guarantee `docker push` Will Work

Docker's credential store is keyed **per registry endpoint** — logging
in successfully against one registry hostname does nothing for a
different one, even if both are ECR and both look superficially
similar. A real run against this exact demo hit this directly: logging
in against a hardcoded example registry endpoint succeeded (`Login
Succeeded`), but every subsequent `docker push` against the actual,
real repository URLs failed with `no basic auth credentials` — because
the login and the push targeted two different registry hostnames.

**The fix is to never hardcode a registry hostname at all.** Step 9
below derives the registry endpoint directly from one of this
configuration's own real `repository_urls` outputs, so the string
Docker logs into is guaranteed to be the same one every subsequent
push actually targets — there's no example value to accidentally copy
verbatim into a real account.

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

Confirmed against a real run — the module resolves to `3.2.0`, and the
apply reports exactly 15 resources (3 per repository, per the Concepts
section above):

```
Apply complete! Resources: 15 added, 0 changed, 0 destroyed.

Outputs:

repository_urls = {
  "cart"     = "<ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-cart"
  "catalog"  = "<ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-catalog"
  "checkout" = "<ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-checkout"
  "orders"   = "<ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-orders"
  "ui"       = "<ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-ui"
}
```

> **`<ACCOUNT_ID>` is your own real, 12-digit AWS account ID — it will
> be a different number in your own output.** This is intentionally
> shown as a placeholder here rather than one specific example number:
> Part C's login step exists specifically to avoid the mistake of
> copying an example account ID literally into a real command. Read
> your own actual value from your own `terraform output`, never from
> this document.

---

## Part B — Verifying the Lifecycle Policy and Tag Mutability

Part B confirms the settings from Part A are genuinely enforced, not
just recorded in Terraform state.

### Step 7 — Verify in the Console

This step confirms in the Console that the mutability and encryption
settings from Part A are genuinely visible on the real repositories,
not just tracked in state — and, since all five repositories were
created from the same `for_each` call, checking the list view
confirms consistency across all five at once rather than just one.

```
Console → ECR → Private registry → Repositories
  → All 5 repositories present: cloudnova-retail-cart, -catalog,
    -checkout, -orders, -ui
  → Tag immutability: Immutable, on every repository ✅
  → Encryption type: AES-256, on every repository ✅
```

> 📷 Confirmed against a real Console screenshot: the Repositories
> list shows all five repositories, each with **Tag immutability:
> Immutable** and **Encryption type: AES-256** — the same two settings
> from `main.tf`'s single `for_each`'d module call, applied
> identically across every instance. The Lifecycle Policy tab's
> "Keep last 10 images" rule is confirmed separately in Step 8 below,
> directly against the AWS API rather than the Console.

### Step 8 — Confirm via CLI

This step confirms via the AWS CLI directly that the lifecycle policy
was genuinely applied to the real repository, not just accepted by
`terraform apply`.

```bash
aws ecr get-lifecycle-policy --repository-name cloudnova-retail-ui --profile default --region us-east-2
```

Confirmed against a real run — AWS returns the exact policy from
`main.tf`, verbatim, proving it was genuinely applied and not just
accepted client-side:

```json
{
    "registryId": "<ACCOUNT_ID>",
    "repositoryName": "cloudnova-retail-ui",
    "lifecyclePolicyText": "{\"rules\":[{\"rulePriority\":1,\"description\":\"Keep last 10 images\",\"selection\":{\"tagStatus\":\"any\",\"countType\":\"imageCountMoreThan\",\"countNumber\":10},\"action\":{\"type\":\"expire\"}}]}",
    "lastEvaluatedAt": "1969-12-31T19:00:00-05:00"
}
```

> **`lastEvaluatedAt` showing a 1969 epoch-zero timestamp is normal,
> not an error.** The lifecycle policy hasn't actually run yet — ECR
> evaluates lifecycle rules on its own schedule, not immediately on
> creation — so this field simply hasn't been set to a real value yet.

---

## Part C — Real Images In, Real Images Out

Part C authenticates Docker against ECR, then pulls, retags, and
pushes all 5 real `retail-store-sample-app` images into CloudNova's
own registry — **each service gets its own explicit, separate set of
commands below.** Do not try to write one generic command and
"substitute" the service name by hand — a real run of this exact demo
did that and ended up pushing the wrong image into the wrong
repository as a direct result. Follow each block for its own named
service, using that service's own dedicated shell variable.

### Step 9 — Authenticate Docker against ECR

This step authenticates Docker against ECR for the first time in this
series — required before any push or pull against a private
repository. **The login target is derived from your own real
`repository_urls` output, not hardcoded** — this is the fix for the
exact failure mode described in the Concepts section above.

```bash
REGISTRY=$(terraform output -json repository_urls | jq -r '.ui' | cut -d'/' -f1)

aws ecr get-login-password --profile default --region us-east-2 | \
  docker login --username AWS --password-stdin "$REGISTRY"
```

Expected: `Login Succeeded`.

> **Why deriving `$REGISTRY` this way matters:** all 5 repositories
> share the exact same registry hostname (your account ID + region) —
> only the path after the slash differs per service. Reading that
> hostname from a real output, rather than typing a literal account ID
> by hand, guarantees the value Docker logs into is the same one every
> `docker push` below will actually target. A real run of this demo
> hardcoded an example account ID here instead — the login itself
> reported success (against that unrelated, wrong registry), but every
> subsequent push then failed with `no basic auth credentials`,
> because Docker had no stored credentials for the *real* registry
> the pushes were actually going to.

> **Why is `--username AWS` a literal, fixed string, not a real username?**
> Every ECR login uses this exact string, regardless of who you are or
> which account you're pushing to — the actual authentication happens
> entirely through the password (the token from `get-login-password`),
> not the username field. If `docker info` shows a different username
> elsewhere (e.g. under `Server` → `Username:`), that reflects a
> separate login to a *different* registry (commonly Docker Hub) from
> Docker's credential store — it has no bearing on ECR at all, and
> seeing two different "usernames" across two different registries is
> expected, not a misconfiguration.

> **This login token is short-lived.** `get-login-password` issues a
> token valid for 12 hours — re-run this step (Step 9 only, not the
> rest of Part C) if you return to this lab in a later session and
> pushes start failing with an authentication error.

### Step 10 — Pull, retag, and push each service — one block per service

Run each of the five blocks below in order, top to bottom. Each block
is fully self-contained: it declares its own uniquely-named variable,
pulls that service's own real published image, retags it under that
service's own repository URL, and pushes it. Nothing here is meant to
be "substituted" by hand — every value is already correct for its own
service.

**UI:**

```bash
REPO_UI=$(terraform output -json repository_urls | jq -r '.ui')

docker pull public.ecr.aws/aws-containers/retail-store-sample-ui:latest
docker tag public.ecr.aws/aws-containers/retail-store-sample-ui:latest "$REPO_UI:v1.0.0"
docker push "$REPO_UI:v1.0.0"
```

**Catalog:**

```bash
REPO_CATALOG=$(terraform output -json repository_urls | jq -r '.catalog')

docker pull public.ecr.aws/aws-containers/retail-store-sample-catalog:latest
docker tag public.ecr.aws/aws-containers/retail-store-sample-catalog:latest "$REPO_CATALOG:v1.0.0"
docker push "$REPO_CATALOG:v1.0.0"
```

> **If `docker pull` fails here with `toomanyrequests: Rate
> exceeded`:** this is the public gallery's anonymous-pull rate limit,
> not a configuration problem — it's a real, transient error, not
> specific to this service. Wait a few seconds and re-run the same
> `docker pull` command; it succeeds on retry.

**Cart:**

```bash
REPO_CART=$(terraform output -json repository_urls | jq -r '.cart')

docker pull public.ecr.aws/aws-containers/retail-store-sample-cart:latest
docker tag public.ecr.aws/aws-containers/retail-store-sample-cart:latest "$REPO_CART:v1.0.0"
docker push "$REPO_CART:v1.0.0"
```

**Orders:**

```bash
REPO_ORDERS=$(terraform output -json repository_urls | jq -r '.orders')

docker pull public.ecr.aws/aws-containers/retail-store-sample-orders:latest
docker tag public.ecr.aws/aws-containers/retail-store-sample-orders:latest "$REPO_ORDERS:v1.0.0"
docker push "$REPO_ORDERS:v1.0.0"
```

**Checkout:**

```bash
REPO_CHECKOUT=$(terraform output -json repository_urls | jq -r '.checkout')

docker pull public.ecr.aws/aws-containers/retail-store-sample-checkout:latest
docker tag public.ecr.aws/aws-containers/retail-store-sample-checkout:latest "$REPO_CHECKOUT:v1.0.0"
docker push "$REPO_CHECKOUT:v1.0.0"
```

Expected, for each of the five pushes above:

```
v1.0.0: digest: sha256:... size: ...
```

> ✅ **Confirmed against a real, complete run of this demo.** All five
> pushes succeeded end-to-end, each verified afterward with a real
> `docker rmi` + `docker pull` round-trip and a real Console/CLI check
> — see Step 12 and the Cleanup section below. Getting there required
> diagnosing and fixing a real, WSL2-specific network problem first;
> see the note immediately below and **Appendix — WSL2 Docker/ECR
> Upload Bottleneck: Root Cause and Fix** for the full, confirmed
> diagnosis if your own pushes stall or time out the same way.

> **`:latest` is the only tag actually confirmed for all 5 services** —
> verified this session via real `docker run` testing against each
> service, not assumed. (An earlier check confirmed a `1.0.0` tag
> exists for the UI image specifically, but extending that to all 5
> services without checking would have been exactly the kind of
> unverified generalization this series has caught and corrected
> elsewhere — so this demo pulls `:latest` instead.) **`v1.0.0` on the
> push side is CloudNova's own internal import label** — it doesn't
> claim to match any version number the upstream project itself uses.

### If `docker push` hangs, stalls at near-zero speed, or fails with `TLS handshake timeout` — especially on WSL2

A one-off `TLS handshake timeout` is normal network noise and a plain
retry fixes it (see Troubleshooting). If it fails **every time**, or
succeeds but crawls at a tiny fraction of your normal upload speed,
and you're running Docker inside **WSL2** (check with `docker info` —
look for `microsoft-standard-WSL2` under Kernel Version), this has a
confirmed, specific cause and fix, verified end-to-end against this
exact demo: **see Appendix — WSL2 Docker/ECR Upload Bottleneck: Root
Cause and Fix, below.** In short, WSL2's virtualized network interface
commonly runs at a smaller MTU (often `1440`) than Docker's own
bridges default to (`1500`), and WSL2's hardware offload settings
(TSO/GSO/GRO) can independently throttle sustained HTTPS uploads —
the Appendix gives the exact, tested `daemon.json` and `ethtool`
settings that resolved this.

If you're not on WSL2, a shorter diagnostic sequence still applies
before assuming it's the same cause:

```bash
openssl s_client -connect "$REGISTRY:443" </dev/null
```

A working connection ends with `Verify return code: 0 (ok)`. If this
hangs the same way `docker push` does, the problem is network
connectivity to ECR itself. If it succeeds cleanly but pushes still
fail or crawl, an MTU mismatch or offload-related throttling — the
same class of problem the Appendix documents for WSL2 — can still
occur on a VPN, a corporate network, or other virtualized network
setups, even outside WSL2 specifically.

<details>
<summary>Additional flags (reference, not required)</summary>

If you're behind a corporate proxy, confirm the proxy is configured
for the Docker **daemon** itself (not just your shell's environment
variables) via `/etc/systemd/system/docker.service.d/http-proxy.conf`,
and confirm the proxy value uses `http://` even for the `HTTPS_PROXY`
variable — a proxy scheme mismatch here is a separate, documented
cause of the same symptom.

</details>

> **Each block above uses its own variable name
> (`REPO_UI`, `REPO_CATALOG`, `REPO_CART`, `REPO_ORDERS`,
> `REPO_CHECKOUT`) rather than one generic name reused five times.**
> This is deliberate. Reusing a single variable name across services —
> setting it once for `ui`, then forgetting to reset it before moving
> on to `catalog` — is exactly how a real run of this demo ended up
> tagging and pushing the *catalog* image under the *ui* repository's
> URL, with no error until the mismatch became obvious later. A
> distinct variable per service removes that failure mode entirely: a
> stale value simply doesn't exist to accidentally reuse.

### Step 11 — Attempt to overwrite an immutable tag

This step deliberately attempts to push to a tag that already exists,
to confirm `IMMUTABLE` is a genuinely enforced constraint rather than
a Console label with no real effect. This uses `$REPO_UI` from Step
10's first block.

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

> **This confirms `IMMUTABLE` is a real, enforced constraint** — not
> just a Console label. Pushing a genuinely new build requires a new
> tag (`v1.0.1`, for example), never overwriting `v1.0.0`.

### Step 12 — Verify a pushed image is genuinely retrievable

This step confirms the pushed image is genuinely retrievable from
CloudNova's own registry, not just reported as uploaded by the
previous push. This also uses `$REPO_UI` from Step 10.

```bash
docker rmi "$REPO_UI:v1.0.0"
docker pull "$REPO_UI:v1.0.0"
```

Confirmed against a real run — the pull succeeds, confirming the image
genuinely exists in CloudNova's own registry, not just reported as
uploaded by `docker push`.

**Verify:**

```
Console → ECR → Repositories → cloudnova-retail-ui → Images tab
  → v1.0.0 present, real image size shown (not 0 bytes) ✅
```

> 📷 Confirmed against a real Console screenshot: the `Images` tab for
> `cloudnova-retail-ui` shows exactly one image, tag `v1.0.0`, a real
> non-zero size (**248.22 MB**), a real image digest, and a populated
> `Last pulled at` timestamp — direct confirmation that the image is
> genuinely retrievable, not just recorded as uploaded.

---

## Cleanup

### Step 13 — Destroy all resources

```bash
terraform destroy
```

Type `yes`. Confirmed against a real run:

```
Destroy complete! Resources: 15 destroyed.
```

This succeeds even with images still inside each repository,
specifically because `repository_force_delete = true` was set in Part
A — without it, this step would fail with a repository-not-empty
error given how much content Part C pushed into these repositories.

### Step 14 — Confirm all repositories are gone

```bash
aws ecr describe-repositories --repository-names cloudnova-retail-ui --profile default --region us-east-2
```

Confirmed against a real run:

```
An error occurred (RepositoryNotFoundException) when calling the
DescribeRepositories operation: The repository with name
'cloudnova-retail-ui' does not exist in the registry with id
'<ACCOUNT_ID>'
```

---

## What You Learned

1. ✅ `terraform-aws-modules/ecr/aws` called with `for_each` creates
   multiple independent repositories from one module block, the same
   pattern Demo 17 used for security groups — and, confirmed against a
   real `apply`, three resources per instance (repository, lifecycle
   policy, and a module-attached default access policy), not one
2. ✅ A `repository_lifecycle_policy` automatically expires old images
   without manual cleanup
3. ✅ `IMMUTABLE` tag mutability genuinely blocks overwriting an
   existing tag — confirmed by actually attempting it, not just
   reading the setting
4. ✅ A Terraform-created ECR repository's `repository_url` output is
   a real, usable Docker registry endpoint — proven by actually
   pushing and re-pulling a real image
5. ✅ `docker login` succeeding says nothing about whether a later
   `docker push` to a *different* registry hostname will work —
   credentials are scoped per registry, confirmed by a real failure
   this demo's Troubleshooting section now documents directly
6. ✅ `repository_force_delete` controls whether `terraform destroy`
   can remove a repository that still contains images
7. ✅ On WSL2 specifically, a persistently stalling or timing-out
   `docker push` has a confirmed, specific network-level cause (an
   MTU mismatch plus TCP offload throttling) and a confirmed fix — see
   the dedicated Appendix if you hit this

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
| A scenario shows `docker login` succeeding but a later `docker push` failing with an auth error | Recognizing Docker credentials are scoped per registry hostname — success against one doesn't cover a different one | Assuming a successful login is sufficient proof pushes anywhere will work |

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
| `no basic auth credentials` on `docker push`, even right after a successful `docker login` | The `docker login` targeted a different registry hostname than the one being pushed to — most commonly, a hardcoded or example account ID was used instead of the real one from `terraform output` | Re-run Step 9 exactly as written, deriving `$REGISTRY` from your own real `repository_urls` output — never type an account ID by hand |
| `no basic auth credentials` after the ECR login token expired | The login token from `aws ecr get-login-password` is only valid 12 hours | Re-run Step 9 only, then retry the push |
| `denied: Your authorization token has expired. Reauthenticate and try again.` | The same 12-hour login-token expiry as above, surfacing with a more explicit message — confirmed in a real run where a slow push to one service pushed the session past the token's validity window before the next service's push ran | Re-run Step 9 only, then retry the push that failed |
| `RepositoryAlreadyExistsException` on `terraform apply`, while `terraform destroy` immediately afterward reports "No changes. No objects need to be destroyed" | The named repositories already exist in AWS but aren't tracked in this configuration's Terraform state — most often left over from an earlier, interrupted run against a different or since-cleared state file | Either delete the pre-existing repositories directly (`aws ecr delete-repository --repository-name <name> --force --profile default --region us-east-2`) before re-running `apply`, or import each one into this state (`terraform import 'module.ecr["ui"].aws_ecr_repository.this[0]' cloudnova-retail-ui`) if you want to keep their existing contents |
| `docker push` fails partway through uploading layers with `net/http: TLS handshake timeout`, once | A one-off network blip establishing the TLS connection for one layer's upload | Re-run the same `docker push` command — Docker resumes from whichever layers weren't already uploaded, it doesn't restart from zero |
| `docker push` keeps failing with `net/http: TLS handshake timeout` on every retry, or crawls at near-zero speed | Not a Docker or ECR configuration problem — on WSL2 specifically, this has a confirmed root cause (MTU mismatch + TCP offload throttling); see the dedicated Appendix | See "If `docker push` hangs..." below Step 10, and the Appendix for the full, confirmed fix |
| `An image does not exist locally with the tag: <repo-url>:v1.0.0` on `docker push` | `docker tag` was never run for that exact repository URL — often because a stale variable from a *different* service was reused instead of that service's own | Re-run that service's full three-line block from Step 10 (pull → tag → push) using its own dedicated variable, in order |
| The wrong image ends up pushed into a service's repository | A single shared variable name (e.g. `REPO_UI`) was reused across multiple services instead of giving each service its own variable | Use Step 10's five separate, uniquely-named variables exactly as written — never reuse one name for more than one service |
| `toomanyrequests: Rate exceeded` on `docker pull` from `public.ecr.aws` | Anonymous pull rate limiting on the public gallery — transient, not a configuration issue | Wait a few seconds and re-run the identical `docker pull` command |
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

**Q4. A colleague says "I already ran `docker login` successfully, so I don't understand why my push to ECR is failing." What's actually going on, and how do you explain it?**
A successful `docker login` only proves Docker now holds valid credentials for the *specific registry hostname* named in that login command — it says nothing about any other registry, even another ECR registry in the same AWS account. If the login command and the push command reference different hostnames (most commonly because one of them was typed by hand from an example rather than read from a real output), the push fails with `no basic auth credentials` even though the login itself reported success. The fix isn't logging in again the same way — it's making sure both commands reference the exact same, real registry hostname, ideally by deriving it programmatically rather than typing it.

---

## Key Takeaways

1. **`for_each` on a registry module scales the same way it does on a
   local one** — five ECR repositories from one module block, each
   independently addressable and destroyable, and confirmed against a
   real `apply` to be three resources per instance, not one.

2. **`IMMUTABLE` tag mutability is a real, enforced constraint, not
   just a setting** — confirmed by actually attempting to overwrite a
   tag and watching AWS reject it.

3. **A repository lifecycle policy automatically expires old images**
   — no manual cleanup process required to keep a registry from
   growing indefinitely.

4. **A module's output being "just an ARN or URL" doesn't mean it's
   inert** — `repository_url` is a real Docker registry endpoint,
   proven by actually pushing and re-pulling a real image against it.

5. **Never hardcode an account ID or registry hostname in a
   copy-pasteable command.** Derive it from a real output every time —
   a real run of this exact demo showed exactly what goes wrong
   otherwise: a login that reports success against the wrong registry,
   followed by every subsequent push failing with an auth error that
   has nothing to do with permissions.

6. **When pushing multiple services, give each one its own uniquely
   named variable.** Reusing one generic name across services is how a
   real run of this demo ended up pushing one service's image into a
   different service's repository.

> **Demo scope:** Primary concept: calling the ECR registry module
> with `for_each`, and the real Docker push/pull workflow it enables.
> Supporting concepts: lifecycle policies, tag immutability, per-
> registry Docker credential scoping.
> Estimated completion time: 40–45 minutes.
> Checkpoints: 3 natural stopping points (end of Part A, end of
> Part B, end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform output -json repository_urls \| jq -r '.<service>' \| cut -d'/' -f1` | Derives the real registry hostname for `docker login` — never type this by hand |
| `aws ecr get-login-password \| docker login ...` | Authenticates Docker against ECR — required before any push/pull against a private repository |
| `docker tag SOURCE TARGET` | Retags a pulled image under the target repository's URL before pushing |
| `aws ecr get-lifecycle-policy --repository-name NAME` | Confirms a lifecycle policy is genuinely applied, not just recorded in Terraform state |
| `aws ecr describe-repositories --repository-names NAME` | Confirms a repository's existence, or its absence after destroy |

---

## Next Demo

**Demo 20 — ACM + Route53 Module.** Introduces `terraform-aws-modules/acm/aws`, requesting and validating a TLS certificate on the confirmed `rselvantech.com` hosted zone — the second of Phase 2's registry-module-practice additions, ahead of Demo 22's ALB needing it.

---

## Appendix — WSL2 Docker/ECR Upload Bottleneck: Root Cause and Fix

This section documents a real problem hit and resolved during this
exact demo: `docker push` to ECR stalling at near-zero speed or
failing outright with `net/http: TLS handshake timeout`, specifically
under Docker running inside WSL2. It's kept as a standalone reference
— read it only if Step 10's callout above points you here.

### 1. Persistence Notice (Transient vs. Permanent Settings)

* **`/etc/docker/daemon.json` (Docker MTU fix):** **Permanent.** Once
  saved, systemd loads this configuration every time Docker restarts.
* **`ethtool` settings (`sudo ethtool -K eth0 ...`):** **Transient.**
  WSL resets virtual network interfaces on shutdown or reboot. To make
  this setting persist across reboots, it must run at startup (Step B
  below).

### 2. Problem Summary

During `docker push` to ECR, image layer uploads experienced extreme
performance degradation — crawling at roughly 125 KB per 45 seconds —
or stalling completely partway through the upload. The identical local
setup behaved normally pushing to Docker Hub.

### 3. Root Cause

Two compounding issues in the WSL2/Hyper-V network virtualization
stack:

1. **MTU mismatch and path-MTU black-holing.** WSL2's primary virtual
   interface (`eth0`) operates at an MTU of `1440` bytes, due to
   hypervisor tunneling overhead. Docker creates its own bridges
   (`docker0`, `br-*`) at the standard `1500`-byte MTU. When Docker
   transmits max-sized, 1500-byte encrypted TLS packets out through
   the 1440-byte interface, packets are fragmented or silently dropped
   by the gateway — producing TCP retransmissions, socket stalls, and
   the `TLS handshake timeout` error.
2. **TCP segmentation offload (TSO) degradation.** WSL2's virtualized
   network driver uses hardware offloading (TSO/GRO/GSO) to delegate
   packet segmentation to the host OS. For large, continuous HTTPS
   uploads to AWS ECR specifically, this offloading throttled
   throughput severely rather than helping it.

### 4. Fix

**Step A — Configure Docker's daemon MTU (permanent).** Set
`/etc/docker/daemon.json` to match Docker's MTU to `eth0`'s real,
smaller MTU:

```bash
sudo tee /etc/docker/daemon.json <<'EOF'
{
  "mtu": 1440,
  "max-concurrent-uploads": 3,
  "max-concurrent-downloads": 5
}
EOF
```

Restart Docker and recreate the `docker0` bridge so it actually picks
up the new MTU (simply restarting the daemon without recreating the
bridge is not sufficient — the bridge itself was already created at
the old MTU):

```bash
sudo systemctl stop docker
sudo ip link set dev docker0 down 2>/dev/null || true
sudo ip link delete docker0 2>/dev/null || true
sudo systemctl start docker
```

**Step B — Disable offloading on `eth0` (transient — must be made to
run on every boot).** WSL resets interface flags on every restart, so
this has to be re-applied at startup, not just once:

```bash
sudo ethtool -K eth0 tso off gso off gro off rx off tx off
```

To persist this across reboots, add it as a WSL boot command in
`/etc/wsl.conf`:

```bash
sudo tee -a /etc/wsl.conf <<'EOF'

[boot]
command = "ethtool -K eth0 tso off gso off gro off rx off tx off"
EOF
```

If you don't have root boot privileges in your WSL setup, a shell
profile fallback (`~/.bashrc` or `~/.zshrc`) works instead, applying
the fix once per new shell rather than once per boot:

```bash
# Fix WSL2 network offload throttling if eth0 TSO is enabled
if ethtool -k eth0 2>/dev/null | grep -q "tcp-segmentation-offload: on"; then
    sudo ethtool -K eth0 tso off gso off gro off rx off tx off >/dev/null 2>&1
fi
```

### 5. Verification

Confirm both settings actually took effect before retrying the push:

```bash
ip link show docker0
```

Expected: `mtu 1440` (matching `eth0`, not the default `1500`).

```bash
ethtool -k eth0 | grep -E "(tcp-segmentation-offload|generic-segmentation-offload)"
```

Expected: `off` for both.

**Confirmed against a real run of this exact demo:** with both fixes
applied, the `docker push` that had previously stalled or timed out
repeatedly completed successfully, and all five services pushed
without further TLS or timeout errors.

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
"Why can a docker login succeed but a later docker push to ECR still fail with 'no basic auth credentials'?","Docker credentials are scoped per registry hostname. If login and push target different hostnames (e.g. a hardcoded example account ID vs. the real one), the login's success says nothing about the push's registry.","demo19,ecr,docker,gotcha"
"A docker push fails partway through with 'net/http: TLS handshake timeout', even though docker login already succeeded against the correct registry. What kind of problem is this?","A transient network-level failure establishing the TLS connection for one layer's upload — unrelated to authentication or configuration. A single occurrence usually clears on a plain retry, since Docker resumes rather than restarting from zero.","demo19,ecr,docker,troubleshooting"
"If 'net/http: TLS handshake timeout' on docker push happens on every retry (not just once), and Docker is running inside WSL2, what is the confirmed root cause?","Two compounding WSL2/Hyper-V networking issues: an MTU mismatch (eth0 often runs at 1440 bytes while Docker's own bridges default to 1500, causing large TLS packets to be fragmented or dropped) and TCP segmentation offload (TSO/GRO/GSO) throttling sustained HTTPS uploads. Confirmed by directly fixing both and re-running the push successfully.","demo19,ecr,docker,wsl2,troubleshooting"
"What command tests whether a persistent TLS handshake timeout is Docker-specific or a lower-level network problem?","openssl s_client -connect <registry-host>:443 — a clean handshake ends with 'Verify return code: 0 (ok)'. If this hangs the same way docker push does, the problem is network connectivity to the registry, not Docker or ECR configuration.","demo19,ecr,docker,troubleshooting"
"On WSL2, what two settings actually fixed a persistently stalling/timing-out docker push to ECR, confirmed by a real run of this demo?","(1) Setting \"mtu\": 1440 in /etc/docker/daemon.json to match eth0's real MTU, then recreating the docker0 bridge so it picks up the new value. (2) Disabling TCP offloading on eth0 via ethtool -K eth0 tso off gso off gro off rx off tx off, made persistent via an /etc/wsl.conf [boot] command since WSL resets interface flags on every restart.","demo19,ecr,docker,wsl2,troubleshooting"
"Why does the ethtool offload fix need to be added to /etc/wsl.conf's [boot] section, while the daemon.json MTU fix does not?","ethtool interface flags are transient — WSL2 resets them on every shutdown or reboot. The daemon.json file, by contrast, is read by systemd every time Docker itself restarts, so it persists on its own without any extra startup step.","demo19,ecr,docker,wsl2,troubleshooting"
"What three resources does one instance of this demo's for_each'd ECR module call actually create, confirmed via a real apply?","aws_ecr_repository, aws_ecr_lifecycle_policy, and aws_ecr_repository_policy — a default, module-attached PrivateReadOnly access policy is created automatically even though this demo never asks for one explicitly.","demo19,ecr,modules"
"What real, transient error can occur pulling from public.ecr.aws, unrelated to any configuration mistake?","toomanyrequests: Rate exceeded — the public gallery's anonymous-pull rate limit. Waiting a few seconds and retrying the identical pull resolves it.","demo19,ecr,docker,troubleshooting"
"Why does this demo give each of the five services its own uniquely-named shell variable (REPO_UI, REPO_CATALOG, ...) instead of one shared variable name?","Reusing one variable name across services risks a stale value from a previous service still being set when the next service's push runs — which can push the wrong image into the wrong repository with no error at all.","demo19,ecr,docker,gotcha"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the individual facts
> (mutability, force-delete, lifecycle policy shape, per-registry
> auth scoping). This Quiz instead works through the actual Docker
> CLI output this demo produces — including the real login/push
> failure this demo's own Troubleshooting section documents — and its
> own Break-Fix scenario, so a learner who's done both has covered
> recall and real-world diagnosis without seeing the same question
> twice.

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

**Q8. (Multiple Choice)** A real run of this demo logged in
successfully with `docker login` against one registry hostname, then
every `docker push` to a *different*, real repository hostname failed
with `no basic auth credentials`. What actually went wrong?

- A) The IAM permissions were insufficient for push, but sufficient for login
- B) The login command targeted a different registry hostname than the push commands — Docker credentials don't transfer between registries
- C) `IMMUTABLE` tag mutability was blocking every push silently
- D) The Terraform-created repositories were never actually created

<details>
<summary>Answer</summary>

**B.** Docker's credential store is keyed per registry hostname —
authenticating against one hostname provides no credentials for a
different one, even if both are ECR endpoints in the same account.
The fix is deriving the login target from a real output rather than
typing a hostname by hand.

</details>

---

**Q9. (Multiple Choice)** While pushing all 5 services, a learner uses
a single variable, `$REPO`, reassigning it before each service's push.
Partway through, `catalog`'s image ends up tagged and pushed against
`ui`'s repository URL instead. What's the most likely cause?

- A) A bug in the ECR module itself
- B) The variable was reassigned to `catalog`'s URL only after the `docker tag` command had already run using the old, `ui` value
- C) `IMMUTABLE` tag mutability caused the mix-up
- D) `docker push` ignores the tag argument entirely

<details>
<summary>Answer</summary>

**B.** Reusing one variable name across services creates exactly this
risk — if the variable isn't reassigned before every single command
that uses it, a stale value from the previous service silently
carries forward. Giving each service its own uniquely-named variable,
as this demo's Step 10 does, removes the failure mode entirely.

</details>

---

**Q10. (Multiple Choice)** `docker pull public.ecr.aws/aws-containers/retail-store-sample-catalog:latest` fails once with `toomanyrequests: Rate exceeded`, then succeeds immediately on a second, identical attempt. What does this indicate?

- A) The image was corrupted on the first attempt
- B) A transient, anonymous-pull rate limit on the public gallery — not a configuration problem
- C) The ECR repository's lifecycle policy blocked the first pull
- D) Docker needs to be restarted between pull attempts

<details>
<summary>Answer</summary>

**B.** This is a real, transient rate limit on anonymous pulls from
the public gallery, unrelated to anything in this demo's own
configuration — simply retrying resolves it.

</details>

---

**Q11. (Multiple Choice)** On WSL2, `docker push` to ECR consistently crawls at a tiny fraction of normal upload speed and occasionally fails with `TLS handshake timeout`, even though `openssl s_client` against the same registry succeeds cleanly. What two settings, confirmed against a real run of this demo, actually resolved it?

- A) Increasing `max-concurrent-uploads` to 10 and disabling TLS verification
- B) Setting Docker's MTU to match `eth0`'s real, smaller MTU (and recreating the `docker0` bridge), plus disabling TCP offloading (TSO/GSO/GRO) on `eth0`
- C) Reinstalling Docker Desktop and switching to the Hyper-V backend
- D) Increasing the ECR repository's lifecycle policy image count

<details>
<summary>Answer</summary>

**B.** WSL2's virtual `eth0` commonly runs at a smaller MTU (e.g.
`1440`) than Docker's own bridges default to (`1500`), causing large
TLS packets to be fragmented or dropped; WSL2's hardware offload
settings independently throttle sustained HTTPS uploads. Fixing both —
not just concurrency — is what resolved it in a real run of this exact
demo. See the dedicated Appendix for the full, tested configuration.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 10-11/11 | Import Anki cards, move to Demo 20 |
| 8-9/11 | Review the wrong answers, then proceed |
| 6-7/11 | Re-read the relevant sections, retry those questions |
| Below 6/11 | Re-read the full demo and redo the walkthrough before proceeding |
````