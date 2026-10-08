# Phase 2 Implementation — CloudNova Platform Modules

> Part of `cloudnova-retail-store-e2e`. Companion to
> `docs/Solution-Architecture.md` (governs the whole project) and
> `Phase-1-Implementation.md` (Phase 1's own milestone, same four-part
> structure). This document has four parts, in order: **Terraform
> Configuration** (what the code is and why), **Execution** (the
> commands, in sequence), **Verification** (Pass Criteria, then
> proof), **Teardown**.

---

## What This Milestone Builds

Every demo in Phase 2 (14–21) taught one module-related concept in
isolation — a local module, a registry module, `for_each` on a module,
workspaces, and so on. This milestone combines eight of those
individual patterns into **one real, applied AWS environment**, the
same way `Phase-1-Implementation.md` combined Phase 1's ten reused
demos — not eight disconnected reps, one coherent system.

**What actually gets created in AWS**, precisely:

- **1 SNS topic + subscription**, via the local `sns-topic` module
  (Demo 14) — CloudNova's platform-alerts channel, unchanged from the
  module Demo 14 built
- **1 S3 bucket**, via the registry `s3-bucket` module (Demo 15) —
  workspace-aware (Demo 18's mechanic applied to this one resource),
  standing in for CloudNova's build-artifact storage
- **1 VPC, 2 AZs, public + private subnets, 1 NAT Gateway**, via the
  registry `vpc` module (Demo 16) — CloudNova's first real,
  purpose-built network, replacing the default VPC every Phase 1 demo
  ran in
- **3 security groups** (web/app/db), via `for_each` on the
  `security-group` module (Demo 17) — composed directly against this
  milestone's own VPC, not a separate one
- **5 ECR repositories**, via `for_each` on the `ecr` module (Demo
  19) — one per real `retail-store-sample-app` service, the exact
  repos Phase 3's compute demos will pull from
- **1 ACM certificate + Route53 placeholder record**, via the `acm`
  module (Demo 20) — validated against CloudNova's real,
  already-owned `rselvantech.com` zone
- **2 `.tftest.hcl` test files**, via `terraform test` (Demo 21) —
  one apply-mode suite against the `sns-topic` module, one plan-mode
  suite against the `vpc` module, both testing this milestone's own
  module calls directly rather than a separate copy

**What this milestone deliberately does NOT build:** anything Phase
3 owns. No EKS, no RDS, no DynamoDB, no Lambda. Every resource above
is either a teaching-rep artifact (torn down at this milestone's own
Cleanup, same as every individual Phase 2 demo) or infrastructure
Phase 3 will explicitly re-create on its own persistent cadence
(ECR/ACM, per ADR-013) — nothing here survives into Phase 3 by
default.

```
┌───────────────────────────────────────────────────────────────────────┐
│                   CloudNova Phase 2 Milestone (us-east-2)              │
│                                                                          │
│  module "alerts"          module "artifacts_bucket"                    │
│  (local: sns-topic)       (registry: s3-bucket)                        │
│  ┌──────────────────┐    ┌──────────────────────────┐                 │
│  │ SNS topic          │    │ S3 bucket                  │                 │
│  │  └─ email sub       │    │  cloudnova-${workspace}-... │                 │
│  └──────────────────┘    └──────────────────────────┘                 │
│                                                                          │
│  module "vpc" (registry: vpc, ~> 6.0)                                  │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │  2 AZs · public/private subnets · 1 NAT Gateway (real cost)       │   │
│  │       │                                                             │   │
│  │       ▼ vpc_id                                                     │   │
│  │  module "tier_sg" (for_each: web / app / db)                       │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐                              │   │
│  │  │ web:443  │ │ app:8080 │ │ db:5432  │  ← 3 independent instances  │   │
│  │  └─────────┘ └─────────┘ └─────────┘     from one module block     │   │
│  └────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  module "ecr" (for_each: ui/catalog/cart/orders/checkout)              │
│  ┌────────┐┌────────┐┌────────┐┌────────┐┌────────┐                  │
│  │  ui     ││ catalog ││  cart   ││ orders  ││checkout │  5 repos,       │
│  └────────┘└────────┘└────────┘└────────┘└────────┘  IMMUTABLE       │
│                                                                          │
│  data.aws_route53_zone (rselvantech.com, real, unmanaged)              │
│       │                                                                 │
│       ▼ zone_id                                                        │
│  module "acm"  →  cert (DNS-validated)  +  placeholder CNAME           │
│                                                                          │
│  tests/sns-topic.tftest.hcl (apply)   tests/vpc.tftest.hcl (plan)      │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Alignment to Phase 2 Demos

Every module call above traces back to a specific demo's teaching
content — nothing here introduces a new concept, it only combines
ones already taught and confirmed built:

| Milestone component | Demo(s) it reuses | What that demo actually taught |
|---|---|---|
| `modules/sns-topic` (local module) + `module "alerts"` | Demo 14 | Module directory structure, `variable`/`output` blocks inside a module, calling a local module, `module.<name>.<output>` |
| `module "artifacts_bucket"` (registry S3 module) | Demo 15 | Registry sourcing (`namespace/name/provider`), version constraints (`~> 5.0`), reading a third-party module's real documented inputs/outputs |
| `terraform.workspace` on the artifacts bucket's name | Demo 18 | What a workspace isolates (state, not configuration), `terraform.workspace` as a built-in reference, contrasted against `for_each` |
| `module "vpc"` (registry VPC module, NAT on) | Demo 16 | Calling a large module with only a relevant input subset, `enable_nat_gateway`/`single_nat_gateway`, routing as the real public/private mechanism |
| `module "tier_sg"` (`for_each` over 3 tiers) | Demo 17 | `for_each` on a module block, `module.<name>["<key>"].<output>` addressing, a `for` expression building a combined output, module-to-module composition (`vpc_id` feeding the SG module) |
| `module "ecr"` (`for_each` over 5 services) | Demo 19 | Reapplying Demo 17's `for_each`-on-module pattern to a genuinely practical payoff, `repository_image_tag_mutability`, `repository_lifecycle_policy`, the real Docker push/pull workflow |
| `data.aws_route53_zone` + `module "acm"` + placeholder record | Demo 20 | `data` reading a zone this project doesn't own or manage, DNS-validated ACM certificates, `wait_for_validation`, why a deliberately temporary placeholder record is legitimate |
| `tests/sns-topic.tftest.hcl`, `tests/vpc.tftest.hcl` | Demo 21 | `run`/`assert` blocks, `command = apply` vs. `command = plan` as a real cost/confidence choice, `terraform test`'s isolated per-file state |

**No demo from Phase 2 is out of scope here** — unlike Phase 1's
milestone (which genuinely excluded four demos with no applicable
content), every one of Demos 14–21's teaching points has a real,
load-bearing place in this build. The one demo this milestone
deliberately does **not** replicate in full is Demo 18: rather than
switching the *entire* configuration between `dev` and `staging`
workspaces (which would mean standing up the NAT Gateway and all 5
ECR repos twice, a real, avoidable cost for a mechanic already fully
proven in Demo 18's own isolated exercise), this milestone applies
`terraform.workspace` to exactly one cheap resource — the artifacts
bucket — and demonstrates the workspace-switch mechanic against that
one resource only, via `-target`. The mechanic itself (state
isolation, empty-state-on-`new`, `terraform.workspace` resolution) is
identical; only the scope of what gets duplicated per workspace is
deliberately narrowed, for the same cost-discipline reason Demo 17
turned NAT Gateway off when it reused Demo 16's VPC module.

---

## Prerequisites

- Terraform `~> 1.15.0`
- AWS Provider `~> 6.47.0`
- AWS CLI `>= 2.x`, configured with credentials for a personal/lab
  AWS account, region `us-east-2`
- **Docker**, for the ECR push/pull steps (Part 2, Step 7) — same
  requirement Demo 19 introduced
- Completed Demos 14–21
- A real Route53 hosted zone you own (this milestone uses
  `rselvantech.com`, per Demo 20 — substitute your own domain if
  different)

## Directory Structure

```
cloudnova-retail-store-e2e/
├── README.md
├── docs/
│   ├── Phase-1-Implementation.md
│   └── Phase-2-Implementation.md        (this document)
├── src/
│   └── terraform/
│       ├── modules/
│       │   └── sns-topic/
│       │       ├── variables.tf
│       │       ├── main.tf
│       │       └── outputs.tf
│       └── phase-2/
│           ├── versions.tf
│           ├── provider.tf
│           ├── variables.tf
│           ├── locals.tf
│           ├── alerts.tf
│           ├── s3.tf
│           ├── vpc.tf
│           ├── security-groups.tf
│           ├── ecr.tf
│           ├── acm.tf
│           ├── outputs.tf
│           └── tests/
│               ├── sns-topic.tftest.hcl
│               └── vpc.tftest.hcl
```

---

# Part 1 — Terraform Configuration

### `src/terraform/modules/sns-topic/variables.tf`, `main.tf`, `outputs.tf`

**What this reuses:** Demo 14's local module, verbatim — this
milestone doesn't fork or modify it, it calls the exact same
self-contained module.

**variables.tf:**

```hcl
variable "topic_name" {
  type        = string
  description = "Name of the SNS topic this module creates"
}

variable "subscription_email" {
  type        = string
  description = "Email address to subscribe to the topic for alerts"
}
```

**main.tf:**

```hcl
resource "aws_sns_topic" "this" {
  name = var.topic_name

  tags = {
    ManagedBy = "terraform-phase-2-milestone"
  }
}

resource "aws_sns_topic_subscription" "this" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = var.subscription_email
}
```

**outputs.tf:**

```hcl
output "topic_arn" {
  value       = aws_sns_topic.this.arn
  description = "ARN of the SNS topic created by this module"
}
```

### `src/terraform/phase-2/versions.tf`

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

### `src/terraform/phase-2/provider.tf`

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
```

### `src/terraform/phase-2/variables.tf`

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

variable "alert_subscription_email" {
  type        = string
  description = "Email address passed into the sns-topic module's subscription_email input"
  default     = "platform-team@cloudnova.example.com"
}

variable "domain_name" {
  type        = string
  description = "Root domain for the ACM certificate — real, already-owned hosted zone (Demo 20)"
  default     = "rselvantech.com"
}
```

### `src/terraform/phase-2/locals.tf`

**What this reuses:** Demo 17's `local.tiers` map, unchanged.

```hcl
locals {
  services = ["ui", "catalog", "cart", "orders", "checkout"]

  tiers = {
    web = { port = 443,  cidr = "0.0.0.0/0" }
    app = { port = 8080, cidr = "10.0.0.0/16" }
    db  = { port = 5432, cidr = "10.0.0.0/16" }
  }
}
```

### `src/terraform/phase-2/alerts.tf`

**What this reuses:** Demo 14's module call, unchanged in mechanics.

```hcl
module "alerts" {
  source = "../modules/sns-topic"

  topic_name         = "cloudnova-phase2-alerts"
  subscription_email = var.alert_subscription_email
}
```

### `src/terraform/phase-2/s3.tf`

**What this reuses:** Demo 15's registry module call, combined with
Demo 18's `terraform.workspace` mechanic (see Alignment above for why
this is the one place workspace-switching is demonstrated in this
milestone).

```hcl
module "artifacts_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  bucket        = "cloudnova-${terraform.workspace}-artifacts-p2"
  force_destroy = true

  versioning = {
    enabled = true
  }

  tags = {
    ManagedBy   = "terraform-phase-2-milestone"
    Environment = terraform.workspace
  }
}
```

### `src/terraform/phase-2/vpc.tf`

**What this reuses:** Demo 16's module call. **NAT Gateway is ON**
here (unlike Demo 17's reuse of this same module, which turned it
off) — this milestone's security groups need a real VPC to attach to,
and the whole point of combining these demos is proving the pieces
work together against one real network, not a second, artificially
cost-free one.

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "cloudnova-phase2-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2a", "us-east-2b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway = true
  single_nat_gateway  = true

  tags = {
    ManagedBy = "terraform-phase-2-milestone"
  }
}
```

### `src/terraform/phase-2/security-groups.tf`

**What this reuses:** Demo 17's `for_each`-on-module pattern,
unchanged, composed against this milestone's own `module.vpc.vpc_id`
rather than a separately-created VPC.

```hcl
module "tier_sg" {
  for_each = local.tiers

  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name        = "cloudnova-${each.key}-tier-sg-p2"
  description = "Security group for the ${each.key} tier"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    tier_access = {
      from_port   = each.value.port
      to_port     = each.value.port
      ip_protocol = "tcp"
      cidr_ipv4   = each.value.cidr
      description = "${each.key} tier access"
    }
  }

  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound"
    }
  }

  tags = {
    ManagedBy = "terraform-phase-2-milestone"
    Tier      = each.key
  }
}
```

> ⚠️ Same open item Demo 17 itself flagged: `ingress_rules`/
> `egress_rules`'s exact object-map shape for
> `terraform-aws-modules/security-group/aws ~> 6.0` was not
> independently re-confirmed for this milestone — run `terraform
> init` and check the module's real "Inputs" tab before applying, per
> Demo 17's own Verification Note.

### `src/terraform/phase-2/ecr.tf`

**What this reuses:** Demo 19's `for_each`-on-module call over the 5
real service names, unchanged.

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
    ManagedBy = "terraform-phase-2-milestone"
    Service   = each.key
  }
}
```

### `src/terraform/phase-2/acm.tf`

**What this reuses:** Demo 20's zone lookup, module call, and
placeholder record, unchanged — same real, already-owned
`rselvantech.com` zone, same DNS-validation technique this milestone
inherits rather than re-derives.

```hcl
data "aws_route53_zone" "this" {
  name = "${var.domain_name}."
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 6.0"

  domain_name = "phase2-milestone.${var.domain_name}"
  zone_id     = data.aws_route53_zone.this.zone_id

  validation_method   = "DNS"
  wait_for_validation = true

  tags = {
    ManagedBy = "terraform-phase-2-milestone"
  }
}

resource "aws_route53_record" "placeholder" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "phase2-milestone.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [var.domain_name]
}
```

### `src/terraform/phase-2/outputs.tf`

```hcl
output "alert_topic_arn" {
  value       = module.alerts.topic_arn
  description = "ARN of the SNS topic created via the alerts module"
}

output "artifacts_bucket_name" {
  value       = module.artifacts_bucket.s3_bucket_id
  description = "Name of the workspace-scoped artifacts bucket"
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "ID of the milestone's VPC"
}

output "tier_security_group_ids" {
  value       = { for tier, sg in module.tier_sg : tier => sg.security_group_id }
  description = "Map of tier name to its security group ID"
}

output "ecr_repository_urls" {
  value       = { for svc, repo in module.ecr : svc => repo.repository_url }
  description = "Map of service name to its ECR repository URL"
}

output "acm_certificate_arn" {
  value       = module.acm.certificate_arn
  description = "ARN of the validated ACM certificate"
}
```

### `src/terraform/phase-2/tests/sns-topic.tftest.hcl`

**What this reuses:** Demo 21's apply-mode pattern, pointed at this
milestone's own `module.alerts` call instead of a separate copy.

```hcl
run "creates_topic_and_subscription" {
  command = apply

  assert {
    condition     = module.alerts.topic_arn != ""
    error_message = "Expected a non-empty topic ARN output"
  }
}
```

### `src/terraform/phase-2/tests/vpc.tftest.hcl`

**What this reuses:** Demo 21's plan-mode pattern (zero cost, no NAT
Gateway re-applied by the test), pointed at this milestone's own
`module.vpc` call.

```hcl
run "creates_correct_subnet_counts" {
  command = plan

  assert {
    condition     = length(module.vpc.public_subnets) == 2
    error_message = "Expected exactly 2 public subnets"
  }

  assert {
    condition     = length(module.vpc.private_subnets) == 2
    error_message = "Expected exactly 2 private subnets"
  }
}
```

> **Why `command = plan` here despite this milestone's own `vpc.tf`
> having `enable_nat_gateway = true`:** same cost reasoning as Demo
> 21 itself — a plan-mode test against subnet counts gets full
> confidence on a purely structural question without re-billing for
> a NAT Gateway the main `apply` (Part 2) already stands up once.

---

# Part 2 — Step-by-Step Execution

### Step 1 — Initialize

```bash
cd cloudnova-retail-store-e2e/src/terraform/phase-2
terraform init
```

Expected — note both a local and a registry-module download, in one
`init`:

```
Initializing modules...
- alerts in ../modules/sns-topic
Downloading registry.terraform.io/terraform-aws-modules/s3-bucket/aws 5.x.x for artifacts_bucket...
Downloading registry.terraform.io/terraform-aws-modules/vpc/aws 6.x.x for vpc...
Downloading registry.terraform.io/terraform-aws-modules/security-group/aws 6.x.x for tier_sg["web"]...
Downloading registry.terraform.io/terraform-aws-modules/security-group/aws 6.x.x for tier_sg["app"]...
Downloading registry.terraform.io/terraform-aws-modules/security-group/aws 6.x.x for tier_sg["db"]...
Downloading registry.terraform.io/terraform-aws-modules/ecr/aws 3.x.x for ecr["ui"]...
[... 4 more ecr instances ...]
Downloading registry.terraform.io/terraform-aws-modules/acm/aws 6.x.x for acm...

Terraform has been successfully initialized!
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

### Step 2 — Apply against the `default` workspace

```bash
terraform validate
terraform apply
```

Expected — every module from Part 1, in one `apply`:

```
module.alerts.aws_sns_topic.this: Creating...
module.vpc.aws_vpc.this[0]: Creating...
module.ecr["ui"].aws_ecr_repository.this[0]: Creating...
module.ecr["catalog"].aws_ecr_repository.this[0]: Creating...
[... remaining ecr, artifacts_bucket, tier_sg (after vpc completes), acm resources ...]

Apply complete! Resources: 39 added, 0 changed, 0 destroyed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment. **Resource count is illustrative, not independently
> re-verified for this exact combination** — it's the sum of each
> demo's own confirmed counts (VPC module: 14 with NAT on, per Demo
> 16; 3× tier_sg at ~4–5 each, per Demo 17's own caveat about that
> module's exact `~> 6.0` resource shape; ECR: 15, per Demo 19; ACM:
> 3–4, per Demo 20; SNS: 2, per Demo 14; S3: 4, per Demo 15) — treat
> the total as a sanity-check ballpark, not a pass/fail criterion in
> its own right.

> **NAT Gateway provisioning genuinely takes 1–4 real minutes**, same
> as Demo 16 — this is the slowest single resource in this apply.

### Step 3 — Docker: authenticate and push all 5 services

```bash
aws ecr get-login-password --profile default --region us-east-2 | \
  docker login --username AWS --password-stdin "$(terraform output -json ecr_repository_urls | jq -r '.ui' | cut -d/ -f1)"
```

Then, for each of `ui`, `catalog`, `cart`, `orders`, `checkout`:

```bash
SVC=ui   # repeat for catalog, cart, orders, checkout
REPO=$(terraform output -json ecr_repository_urls | jq -r ".${SVC}")
docker pull "public.ecr.aws/aws-containers/retail-store-sample-${SVC}:latest"
docker tag "public.ecr.aws/aws-containers/retail-store-sample-${SVC}:latest" "$REPO:v1.0.0"
docker push "$REPO:v1.0.0"
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment. Same `:latest`-only-confirmed caveat as Demo 19: only
> the `:latest` tag is confirmed to exist for all 5 services; `v1.0.0`
> on the push side is CloudNova's own import label.

### Step 4 — Demonstrate workspace isolation on the artifacts bucket only

```bash
terraform workspace new dev
terraform apply -target=module.artifacts_bucket
```

Expected — only the bucket is affected, not the VPC/ECR/ACM/SG stack
already standing in `default`:

```
module.artifacts_bucket.aws_s3_bucket.this[0]: Creating...
module.artifacts_bucket.aws_s3_bucket.this[0]: Creation complete after 2s [id=cloudnova-dev-artifacts-p2]

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

```bash
terraform workspace select default
```

> **Why `-target` here, and why this doesn't undermine Demo 18's own
> lesson:** Demo 18 already proved the workspace mechanic in full
> isolation, cheaply, with nothing else in the configuration. This
> milestone's `default` workspace already carries a real NAT Gateway
> and 5 ECR repos — applying the *entire* configuration a second time
> under `dev` would re-create all of that a second time, a real,
> avoidable cost for a mechanic already fully demonstrated elsewhere.
> `-target` scopes this step to exactly the one resource actually
> being used to demonstrate it here.

### Step 5 — Run the test suites

```bash
terraform test
```

Expected:

```
tests/sns-topic.tftest.hcl... pass
tests/vpc.tftest.hcl... pass

Success! 3 passed, 0 failed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment. The `sns-topic` test genuinely creates and destroys its
> own SNS topic (in the test framework's own isolated, in-memory
> state) — it does not touch `module.alerts`'s real, already-applied
> topic from Step 2, per Demo 21's own "test state is entirely
> separate from real state" guarantee.

---

# Part 3 — Verification

## Pass Criteria

1. `terraform apply` (Step 2) completes cleanly against the `default`
   workspace, with all 6 module blocks represented in the resource
   count
2. All 5 ECR repositories show a real, non-zero-size `v1.0.0` image in
   the Console (Step 3)
3. `module.artifacts_bucket` exists under **both** `default` and `dev`
   workspaces simultaneously, with different real bucket names
   (Step 4)
4. `terraform test` reports all runs passing, with the VPC suite
   creating zero real infrastructure (Step 5)
5. The ACM certificate shows `Issued`, not `Pending validation`, in
   the Console
6. Each of the three security groups' inbound rule matches its tier's
   configured port and CIDR exactly

### Verification steps — AWS Console first, CLI only where required

**#1 — SNS.** Console → SNS → Topics → `cloudnova-phase2-alerts` →
confirm it exists, one subscription, status "Pending confirmation."

**#2 — S3, both workspaces.** Console → S3 → confirm
`cloudnova-default-artifacts-p2` and `cloudnova-dev-artifacts-p2` both
exist simultaneously.

**#3 — VPC and security groups.** Console → VPC → Your VPCs →
`cloudnova-phase2-vpc` → confirm 2 public + 2 private subnets, 1 NAT
Gateway. Console → Security Groups → confirm
`cloudnova-web-tier-sg-p2` / `-app-` / `-db-` each show their own
distinct inbound rule.

> **If Pass Criterion #6 fails, check *what* failed before treating it
> as a milestone defect.** Wrong ports or wrong CIDRs on the security
> groups is this milestone's own bug. But if `apply` itself errors on
> the `ingress_rules`/`egress_rules` shape (an "Unsupported argument"
> or similar, not a wrong-value mismatch), that's Demo 17's own
> unresolved open item surfacing here, not something this milestone
> introduced — see Part 1's `security-groups.tf` note and Demo 17's
> own Verification Note before debugging this as a milestone-level
> problem.

**#4 — ECR.** Console → ECR → confirm all 5
`cloudnova-retail-<service>` repositories exist, each with one
`v1.0.0` image, real size shown (not 0 bytes).

**#5 — ACM.** Console → Certificate Manager → confirm
`phase2-milestone.rselvantech.com` shows **Issued**.

## Results

| # | Check | Pass? | Notes |
|---|---|---|---|
| 1 | `apply` completes cleanly | ☐ | |
| 2 | 5 ECR repos, real images | ☐ | |
| 3 | Bucket exists in both workspaces | ☐ | |
| 4 | `terraform test` all pass | ☐ | |
| 5 | ACM cert `Issued` | ☐ | |
| 6 | 3 SGs, correct per-tier rules | ☐ | |

---

# Part 4 — Teardown and Confirm

### Step 6 — Destroy the `dev` workspace's targeted resource first

```bash
terraform workspace select dev
terraform destroy -target=module.artifacts_bucket
terraform workspace select default
terraform workspace delete dev
```

> **Order matters here, same reason as Demo 18's own Cleanup:** a
> workspace must be empty and not currently selected before it can be
> deleted.

### Step 7 — Destroy everything in `default`

```bash
terraform destroy
```

Type `yes`. Expected — note NAT Gateway and ACM/Route53 teardown both
take real time, same as Demos 16 and 20 individually:

```
module.tier_sg["web"].aws_security_group.this[0]: Destroying...
module.ecr["ui"].aws_ecr_repository.this[0]: Destroying...
[... remaining resources ...]
module.vpc.aws_nat_gateway.this[0]: Destroying...
module.vpc.aws_nat_gateway.this[0]: Still destroying... [1m12s elapsed]
[... remainder ...]

Destroy complete! Resources: 39 destroyed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment. `repository_force_delete = true` (Demo 19) is what
> allows the ECR repos to destroy cleanly despite still holding real
> pushed images — confirmed in Part 1's `ecr.tf`.

### Step 8 — Confirm nothing is left standing

```bash
aws ec2 describe-nat-gateways --filter "Name=tag:ManagedBy,Values=terraform-phase-2-milestone" --profile default --region us-east-2
aws ecr describe-repositories --repository-names cloudnova-retail-ui --profile default --region us-east-2
aws acm list-certificates --profile default --region us-east-2 --query "CertificateSummaryList[?DomainName=='phase2-milestone.rselvantech.com']"
```

Expected: an empty/deleted NAT Gateway, a `RepositoryNotFoundException`
for ECR, and an empty ACM list — same three highest-cost-or-highest-
residual-risk resources this milestone created, each confirmed gone
individually rather than trusting `destroy`'s exit code alone.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **The `rselvantech.com` hosted zone itself is never touched by this
> destroy** — same standing exception as Demo 20, ADR-013/ADR-018:
> only the certificate and the two records this milestone created are
> removed.

---

## What's Next

**Phase 3 begins at Demo 22.** Everything this milestone built is
torn down at its own Cleanup, same as every individual Phase 1 and
Phase 2 demo — nothing here is the persistent build. Demo 22 Part A
re-creates ECR and ACM from scratch (ADR-013), and stands up the EKS
cluster (Auto Mode, per ADR-019) as the actual, every-session-torn-
down-and-reapplied compute layer this whole series has been building
toward. This milestone's real value carries forward as **proof the
pieces compose correctly together** — a local module, a registry
module, `for_each`-on-modules, workspaces, and `terraform test`, all
working against one real VPC and one real domain at once — not as
infrastructure Phase 3 inherits directly.