# Demo 17 — Three-Tier Modules

---

## Overview

Every module call so far in this series — Demo 14's `sns-topic`, Demo
15's `s3-bucket`, Demo 16's `vpc` — has been a **single** call to a
**single** module. Real architectures rarely stay that simple:
CloudNova's actual applications need a web tier, an app tier, and a
data tier, each with its own security boundary — and hand-writing
three nearly-identical `module` blocks (one per tier) is exactly the
kind of duplication `for_each` exists to eliminate. This demo composes
Demo 16's VPC module with the `terraform-aws-modules/security-group/aws`
module, called **three times from one `for_each`-driven `module`
block** — one instance per tier.

**Real-world scenario — CloudNova:** the platform team needs network
segmentation for a future three-tier application (web, app, database)
before Phase 3 deploys anything into it. Rather than writing three
separate `module "web_sg"`, `module "app_sg"`, `module "db_sg"` blocks
— each identical except for a name and a port — this demo uses
`for_each` on one `module` block, driven by a `locals` map describing
each tier.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Composing the VPC (NAT Gateway Off)                           │
│  Demo 16's module reused, enable_nat_gateway = false — no compute is    │
│  being deployed here, so there's no reason to pay for it again          │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — One Module, Three Tiers via for_each                          │
│  module "tier_sg" { for_each = local.tiers ... } — web/app/db, each a   │
│  separate security-group module instance from one block                │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Verifying Three Independent Security Groups                   │
│  module.tier_sg["web"].security_group_id and friends, iterated via a   │
│  for expression into one combined output map                            │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- `for_each` on a `module` block — calling the same module multiple
  times, once per key in a map
- Addressing a specific instance of a `for_each`'d module:
  `module.<name>["<key>"].<output>`
- Building a combined output across all instances of a `for_each`'d
  module, using a `for` expression
- Composing two separate modules together (this demo's `tier_sg`
  module consumes Demo 16's VPC module's `vpc_id` output as an input)
- `terraform-aws-modules/security-group/aws` — specific inputs used:
  `name`, `description`, `vpc_id`, `ingress_rules`, `egress_rules`,
  `tags`; specific output used: `security_group_id`

**What this demo does NOT cover:** chaining tiers' security groups
directly to each other (web→app→db, each restricted to traffic
*specifically* from the tier above it) — this demo scopes each tier's
ingress to the VPC's CIDR block instead, a deliberate simplification
to keep `for_each`-on-modules as the single primary concept. True
tier-to-tier SG chaining is a real, more advanced pattern, noted in
Interview Prep but not built here.

---

## How This Demo's Pieces Fit Together

**The AWS solution:** one VPC (no NAT Gateway this time), and three
independent security groups — one per tier — each created by its own
instance of a single `for_each`'d `module` block.

- Root's `04-main.tf` calls Demo 16's VPC module again, with
  `enable_nat_gateway = false` — this demo's focus is security-group
  composition, not networking, so there's no NAT Gateway cost this
  time.
- `05-locals.tf` defines `local.tiers` — a map with three keys (`web`,
  `app`, `db`), each carrying its own ingress port and allowed CIDR.
- `06-security-groups.tf` calls the security-group module **once**,
  with `for_each = local.tiers` — Terraform expands this into three
  independent module instances,
  `module.tier_sg["web"]`/`["app"]`/`["db"]`, each receiving
  `module.vpc.vpc_id` as its `vpc_id` input and a different
  `each.value.port`/`each.value.cidr` for its ingress rule.
- Root's `07-outputs.tf` reads each instance individually via
  `module.tier_sg["<key>"].security_group_id`, and separately builds a
  single combined map of all three using a `for` expression over
  `module.tier_sg` as a whole.

---

## Prerequisites

### Knowledge
- Demo 16 completed — calling `terraform-aws-modules/vpc/aws`, public
  vs. private subnet routing
- Demo 09 completed — `for_each` on a *resource* (the mechanics carry
  over directly to `for_each` on a *module*)

### Required Tools

Same as Demos 05–16 — Terraform `~> 1.15.0`, AWS CLI `>= 2.x`.

### Verify AWS Account and Permissions

```bash
aws sts get-caller-identity --profile default --region us-east-2
```

**Required permissions for this demo:**

```
ec2:CreateVpc, ec2:DeleteVpc, ec2:DescribeVpcs, ec2:CreateTags
ec2:CreateSubnet, ec2:DeleteSubnet, ec2:DescribeSubnets
ec2:CreateInternetGateway, ec2:AttachInternetGateway, ec2:DeleteInternetGateway
ec2:CreateRouteTable, ec2:CreateRoute, ec2:AssociateRouteTable, ec2:DeleteRouteTable
ec2:CreateSecurityGroup, ec2:DeleteSecurityGroup, ec2:DescribeSecurityGroups
ec2:AuthorizeSecurityGroupIngress, ec2:AuthorizeSecurityGroupEgress
ec2:RevokeSecurityGroupIngress, ec2:RevokeSecurityGroupEgress
```

> Shorter than Demo 16's list — no `ec2:CreateNatGateway`/
> `ec2:AllocateAddress` this time, since NAT Gateway is disabled.

### Versions used in this demo

| Tool / Module | Version |
|---|---|
| Terraform | `~> 1.15.0` |
| AWS Provider | `~> 6.47.0` |
| `terraform-aws-modules/vpc/aws` | `~> 6.0` |
| `terraform-aws-modules/security-group/aws` | `~> 6.0` (exact current release confirmed: `6.0.0`) |
| AWS CLI | `>= 2.x` |

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Call a module with `for_each`, producing multiple independent
   instances from one `module` block
2. ✅ Address a specific instance of a `for_each`'d module using
   `module.<name>["<key>"].<output>`
3. ✅ Build a combined output across all instances of a `for_each`'d
   module using a `for` expression
4. ✅ Compose two separate modules together — one module's output
   feeding directly into a second module's input
5. ✅ Build and verify three real, independently-configured AWS
   security groups entirely through one `for_each`'d module call

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| VPC, subnets, route tables, Internet Gateway | Always free | **$0.00** | Same as Demo 16 — no NAT Gateway this time |
| Security Groups (×3) | Always free | **$0.00** | Security groups themselves never have an associated cost |
| **Session total** | | **$0.00** | Back to $0 after Demo 16's NAT-Gateway-driven cost |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
17-three-tier-modules/
├── README.md
├── 17-three-tier-modules-anki.csv
├── 17-three-tier-modules-quiz.md
└── src/
    ├── 01-versions.tf          # terraform block + provider version constraints
    ├── 02-provider.tf           # AWS provider: region, profile
    ├── 03-variables.tf          # root-level inputs: VPC name, CIDR
    ├── 04-main.tf                # module "vpc" block — reused from Demo 16, NAT off
    ├── 05-locals.tf               # local.tiers — the map driving for_each
    ├── 06-security-groups.tf      # module "tier_sg" block — for_each over local.tiers
    ├── 07-outputs.tf              # root outputs — per-tier and combined
    └── break-fix/
        └── broken.tf              # root config with 3 deliberate for_each-on-module errors
```

---

## Recall Check — Demo 16

Answer from memory before reading further:

1. What actually makes a subnet "public" versus "private" at the AWS
   level — is it a property of the subnet resource itself?
2. What does `enable_nat_gateway = true` cost, and does it matter
   whether anything is actively using the NAT Gateway?
3. Why is `module.vpc.public_subnets` a list rather than a single
   value?

<details>
<summary>Answers</summary>

1. No — it's the subnet's associated route table's `0.0.0.0/0` target:
   an Internet Gateway for public, a NAT Gateway for private. The
   subnet resource itself has no such attribute.
2. It bills hourly (~$0.045/hour) simply for existing, plus a per-GB
   charge for data it actually processes — regardless of whether
   anything is using it at all.
3. Because the module creates one subnet per AZ (per the
   `public_subnets` input list) — its output is correspondingly an
   ordered list of the resulting subnet IDs, one per AZ.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `for_each` (on a `module` block) | Meta-argument | Creates one module instance per key in a map |
| `module.<name>["<key>"].<output>` | Reference expression | Addresses one specific instance of a `for_each`'d module |
| `for <key>, <value> in module.<name> : ...` | `for` expression over a module | Builds a combined value across every instance of a `for_each`'d module |
| `ingress_rules`, `egress_rules` | Security-group module inputs | Keyed maps describing this security group's allowed traffic |
| `security_group_id` | Security-group module output | Used both individually and inside the combined `for` expression |

**Related constructs worth knowing (not covered in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| Security-group-to-security-group ingress chaining (`referenced_security_group_id`) | Restricting a tier's ingress to *specifically* the tier above it, not the whole VPC CIDR | Not covered in this series — noted in Interview Prep as a real production pattern |

---

### Detailed Explanation of New Constructs

#### `for_each` on a Module Block

```hcl
# 05-locals.tf
locals {
  tiers = {
    web = { port = 443,  cidr = "0.0.0.0/0" }
    app = { port = 8080, cidr = "10.0.0.0/16" }
    db  = { port = 5432, cidr = "10.0.0.0/16" }
  }
}

# 06-security-groups.tf
module "tier_sg" {
  for_each = local.tiers

  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name        = "cloudnova-${each.key}-tier-sg"
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
    ManagedBy = "terraform-demo-17"
    Tier      = each.key
  }
}
```

**What it does:** `for_each = local.tiers` tells Terraform to create
one instance of the `tier_sg` module per key in that map — three
instances (`web`, `app`, `db`), not three separate `module` blocks.
Inside the block, `each.key` is the current map key (`"web"`,
`"app"`, or `"db"`), and `each.value` is that key's corresponding map
value — exactly the same `each.key`/`each.value` mechanics Demo 09
used for `for_each` on a resource.

> **Same as X" ban check — restating, not just pointing:** this is the
> identical `each.key`/`each.value` mechanic Demo 09 introduced for a
> `for_each`'d *resource* — but a `for_each`'d **module** produces
> three independent module instances, each with its own full set of
> internal resources (a security group plus its rules, in this case),
> not three instances of one resource. The scale of what gets
> duplicated per key is categorically larger.

**The `ingress_rules`/`egress_rules` argument shape:** both are keyed
maps, not lists — each key (`tier_access`, `all`, above) is an
arbitrary label of your choosing, and each value is an object with
`from_port`/`to_port`/`ip_protocol`/`cidr_ipv4`/`description`. The key
itself has no meaning to AWS; it exists purely so Terraform can track
each individual rule's identity across plan/apply, the same reason
Demo 09's `for_each` used meaningful keys instead of a plain list.

---

#### Addressing a Specific Instance — `module.<name>["<key>"]`

**What it does:** once a module is called with `for_each`, its local
name (`tier_sg`) is no longer a single module instance — it becomes a
map of instances, indexed by the same keys used in `for_each`.
`module.tier_sg["web"].security_group_id` reads the `web` tier's
specific security group ID; `module.tier_sg["app"].security_group_id`
reads a completely different one.

> **This is a genuinely different reference shape from every prior
> module call in this series.** Demo 14, 15, and 16's modules were
> each called without `for_each`, so `module.alerts.topic_arn` (no
> bracket, no key) was valid. The moment `for_each` is added to a
> `module` block, referencing it *without* a key
> (`module.tier_sg.security_group_id`) becomes an error — Terraform
> has no way to know which of the three instances you mean.

---

#### Building a Combined Output — `for` Expression Over a Module

```hcl
# 07-outputs.tf
output "tier_security_group_ids" {
  value       = { for tier, sg in module.tier_sg : tier => sg.security_group_id }
  description = "Map of tier name to its security group ID"
}
```

**What it does:** `for tier, sg in module.tier_sg : tier => sg.security_group_id`
iterates over every instance of the `for_each`'d `tier_sg` module,
producing one combined map — `{ web = "sg-...", app = "sg-...", db =
"sg-..." }` — instead of writing three separate `output` blocks
(one per tier). This is the same `for` expression syntax Demo 07
introduced for transforming lists/maps generally, applied here
specifically to a module's own instances.

---

#### Composing Two Modules — the VPC's Output as the Security-Group Module's Input

**What it does:** `vpc_id = module.vpc.vpc_id` inside the `tier_sg`
module call is this demo's actual "composition" — Demo 16's VPC
module's output is consumed directly as Demo 17's security-group
module's input, with no manual copying of an ID string anywhere. This
is precisely why Demo 16's VPC module is called again here (rather
than assuming some VPC already exists) — the dependency has to be a
real Terraform reference, not an out-of-band value pasted in.

---

## Lab Step-by-Step Guide

---

## Part A — Composing the VPC (NAT Gateway Off)

**What you accomplish in Part A:** stand up the same VPC module from
Demo 16, with NAT Gateway explicitly disabled.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-2-modules/17-three-tier-modules/src
```

### Step 2 — Create the root scaffolding files

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

#### `02-provider.tf` — AWS provider configuration

**02-provider.tf:**

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
```

#### `03-variables.tf` — Root-level inputs

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

variable "vpc_name" {
  type        = string
  description = "Name passed into the VPC module's name input"
  default     = "cloudnova-demo17-vpc"
}

variable "vpc_cidr" {
  type        = string
  description = "Overall CIDR block for the VPC"
  default     = "10.0.0.0/16"
}
```

### Step 3 — Call the VPC module, NAT Gateway disabled

Create a file **04-main.tf** and add the below content:

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = ["us-east-2a", "us-east-2b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway = false

  tags = {
    ManagedBy = "terraform-demo-17"
  }
}
```

---

## Part B — One Module, Three Tiers via `for_each`

**What you accomplish in Part B:** define the tier map, then call the
security-group module once with `for_each` to create all three tiers'
security groups.

### Step 1 — Define the tier map

Create a file **05-locals.tf** and add the below content:

```hcl
locals {
  tiers = {
    web = { port = 443,  cidr = "0.0.0.0/0" }
    app = { port = 8080, cidr = "10.0.0.0/16" }
    db  = { port = 5432, cidr = "10.0.0.0/16" }
  }
}
```

### Step 2 — Call the security-group module with `for_each`

Create a file **06-security-groups.tf** and add the below content:

```hcl
module "tier_sg" {
  for_each = local.tiers

  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name        = "cloudnova-${each.key}-tier-sg"
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
    ManagedBy = "terraform-demo-17"
    Tier      = each.key
  }
}
```

### Step 3 — Create the root outputs

Create a file **07-outputs.tf** and add the below content:

```hcl
output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "ID of the VPC"
}

output "web_tier_sg_id" {
  value       = module.tier_sg["web"].security_group_id
  description = "Security group ID for the web tier specifically"
}

output "tier_security_group_ids" {
  value       = { for tier, sg in module.tier_sg : tier => sg.security_group_id }
  description = "Map of every tier name to its security group ID"
}
```

### Step 4 — Initialize and apply

```bash
terraform init
terraform validate
terraform apply
```

Expected — note three distinct `module.tier_sg["<key>"]` addresses,
one per tier:

```
module.vpc.aws_vpc.this[0]: Creating...
module.vpc.aws_vpc.this[0]: Creation complete after 2s
[... VPC subnets, IGW, route tables ...]
module.tier_sg["web"].aws_security_group.this[0]: Creating...
module.tier_sg["app"].aws_security_group.this[0]: Creating...
module.tier_sg["db"].aws_security_group.this[0]: Creating...
module.tier_sg["web"].aws_security_group.this[0]: Creation complete after 2s
module.tier_sg["app"].aws_security_group.this[0]: Creation complete after 2s
module.tier_sg["db"].aws_security_group.this[0]: Creation complete after 2s

Apply complete! Resources: 14 added, 0 changed, 0 destroyed.

Outputs:

tier_security_group_ids = {
  "app" = "sg-0aaa..."
  "db"  = "sg-0bbb..."
  "web" = "sg-0ccc..."
}
vpc_id = "vpc-0ddd..."
web_tier_sg_id = "sg-0ccc..."
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **All three tiers' security groups create in parallel, not
> sequentially.** Since none of the three `tier_sg` instances depend
> on each other (only on the shared `module.vpc.vpc_id`), Terraform is
> free to create them concurrently — this is a direct benefit of using
> `for_each` instead of three independent, hand-written `module`
> blocks that happen to look similar.

---

## Part C — Verifying Three Independent Security Groups

**What you accomplish in Part C:** confirm all three security groups
exist independently, with the correct tier-specific ingress rule each.

### Step 1 — Read the combined output

```bash
terraform output tier_security_group_ids
```

Expected: the same three-key map shown in Part B's apply output.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

### Step 2 — Verify in the Console

```
Console → VPC → Security Groups → cloudnova-web-tier-sg
  → Inbound rules → TCP 443 from 0.0.0.0/0 ✅

Console → VPC → Security Groups → cloudnova-app-tier-sg
  → Inbound rules → TCP 8080 from 10.0.0.0/16 ✅

Console → VPC → Security Groups → cloudnova-db-tier-sg
  → Inbound rules → TCP 5432 from 10.0.0.0/16 ✅
```

> **Three security groups, three different ingress rules, one
> `module` block.** Confirming this in the Console directly is the
> real test that `for_each` actually produced independently
> configured instances — not three identical copies.

---

## Cleanup

```bash
terraform destroy
```

Type `yes`. Expected:

```
module.tier_sg["web"].aws_security_group.this[0]: Destroying...
module.tier_sg["app"].aws_security_group.this[0]: Destroying...
module.tier_sg["db"].aws_security_group.this[0]: Destroying...
[... VPC resources destroyed ...]

Destroy complete! Resources: 14 destroyed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

```bash
aws ec2 describe-security-groups --filters "Name=tag:ManagedBy,Values=terraform-demo-17" --profile default --region us-east-2
```

Expected: an empty `SecurityGroups` list.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## What You Learned

1. ✅ `for_each` on a `module` block creates one independent instance
   per key in a map — not three copy-pasted `module` blocks
2. ✅ A `for_each`'d module is addressed as
   `module.<name>["<key>"].<output>` — referencing it without a key
   becomes an error the moment `for_each` is added
3. ✅ A `for` expression over a `for_each`'d module builds one combined
   value across all its instances, avoiding one `output` block per
   instance
4. ✅ Modules compose directly — one module's output can feed straight
   into a second module's input, with no manual value-copying
5. ✅ Independent instances of a `for_each`'d module create in
   parallel when they don't depend on each other

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `for_each` on a `module` block | TA-004 Obj 5c | "Use modules in configuration" — reinforced at multi-instance scale |
| `module.<name>["<key>"].<output>` addressing | TA-004 Obj 5c | Distinct reference shape from a non-`for_each`'d module call |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam shows `module.tier_sg.security_group_id` on a module with `for_each` | Recognizing this is invalid — a key is required once `for_each` is present | Assuming a `for_each`'d module can still be referenced the same way as a single-instance module |
| Exam asks how to build one output covering all instances of a `for_each`'d module | Recognizing a `for` expression over the module (`for k, v in module.x : ...`) is the correct approach | Writing one `output` block per expected key, which doesn't scale and breaks if the map changes |
| Exam asks whether `for_each`'d module instances execute in a fixed order | Recognizing instances without a dependency on each other create in parallel | Assuming `for_each` implies sequential, ordered creation |

### Exam Task — Write a complete configuration

**Task:** CloudNova wants a fourth tier — a `cache` tier (Redis, port
6379, VPC-CIDR-scoped) — added to this demo's existing `for_each`
setup, with no new `module` blocks written.

**Block types required:** none new — modify the existing `locals` map

**Official documentation:**
- [`for_each` Meta-Argument](https://developer.hashicorp.com/terraform/language/meta-arguments/for_each)

**What to practise:**
1. Add a fourth key to `local.tiers` — no changes to the `module`
   block itself should be needed
2. Confirm `terraform plan` shows exactly one new security group being
   added, not a modification to any existing one

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
locals {
  tiers = {
    web   = { port = 443,  cidr = "0.0.0.0/0" }
    app   = { port = 8080, cidr = "10.0.0.0/16" }
    db    = { port = 5432, cidr = "10.0.0.0/16" }
    cache = { port = 6379, cidr = "10.0.0.0/16" }
  }
}
```

**Arguments you must know without looking up:**
- Adding a key to the map driving `for_each` only creates a new
  instance for that key — every existing instance is completely
  unaffected, since each instance's identity is tied to its own key,
  not its position in the map

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `This map does not have index "web"` (or similar) referencing `module.tier_sg` | Referencing a `for_each`'d module without a key, or with a key that doesn't exist in `local.tiers` | Add the correct key, matching exactly one of `local.tiers`' keys |
| `Unsupported attribute` on `module.tier_sg["web"].<something>` | Referencing an output name the security-group module doesn't actually expose | Check the module's own documented outputs — this demo uses `security_group_id` |
| `Invalid for_each argument` | `for_each` was given a value that isn't a map or set of strings (e.g. a list of unstructured objects) | Confirm `local.tiers` is a map, with string keys |

---

## Break-Fix Scenario

Three deliberate errors in the `for_each`-on-module setup — single
self-contained file, same pattern as Demos 15/16.

```bash
cd src/break-fix/
terraform init
```

#### `broken.tf` — Three deliberate errors

**What this file does in this demo:** a self-contained root
configuration with a missing-key reference, a typo'd `each.value`
attribute, and a wrong output name — diagnose all three.

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

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name            = "cloudnova-broken-demo17"
  cidr            = "10.0.0.0/16"
  azs             = ["us-east-2a", "us-east-2b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]
}

locals {
  tiers = {
    web = { port = 443, cidr = "0.0.0.0/0" }
    app = { port = 8080, cidr = "10.0.0.0/16" }
  }
}

module "tier_sg" {
  for_each = local.tiers

  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name        = "cloudnova-${each.key}-tier-sg"
  description = "Security group for the ${each.key} tier"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    tier_access = {
      from_port   = each.valeu.port # Error 1: typo, "valeu" instead of "value"
      to_port     = each.value.port
      ip_protocol = "tcp"
      cidr_ipv4   = each.value.cidr
    }
  }
}

output "web_sg_id" {
  value = module.tier_sg.security_group_id # Error 2: missing instance key
}

output "db_sg_id" {
  value = module.tier_sg["db"].security_group_id # Error 3: "db" isn't a key in local.tiers
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — typo, `each.valeu` instead of `each.value`**
`each` has no attribute named `valeu` — reported as an "Unsupported
attribute" error at `validate`/`plan`, since `each` only ever exposes
`key` and `value`. Fix: correct the typo to `each.value.port`.

**Error 2 — `module.tier_sg.security_group_id` missing an instance key**
`tier_sg` was called with `for_each`, so it's a map of instances, not
a single instance — referencing it with no key is invalid. Fix: use
`module.tier_sg["web"].security_group_id` (or whichever specific tier
is intended).

**Error 3 — `"db"` isn't a key in `local.tiers` in this broken file**
This particular `broken.tf` only defines `web` and `app` in
`local.tiers` — there's no `db` key, so `module.tier_sg["db"]` doesn't
exist. Fix: either add a `db` entry to `local.tiers`, or reference an
existing key.

> ⚠️ [VERIFY — behavioral claim, docs-reasoning only, not a live run in
> this environment]: the exact wording and ordering of these three
> diagnostics in a single `terraform validate`/`plan` pass isn't
> confirmed here — re-run after each individual fix rather than
> assuming all three are visible simultaneously.

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

**Q1. Why use `for_each` here instead of three separate `module`
blocks, one per tier?**
Three separate blocks would be nearly-identical copy-paste, differing
only in name and port — exactly the duplication Terraform's `for_each`
exists to eliminate. It also means adding a fourth tier later is a
one-line change to a map, not a whole new `module` block, and each
instance is independently addressable and independently updatable
without touching the others.

**Q2. This demo scopes each tier's ingress to the VPC's CIDR block,
not specifically to the tier above it. What's the real production
alternative, and why wasn't it used here?**
The production pattern is chaining security groups directly —
`app`'s ingress rule referencing `web`'s `security_group_id` via
`referenced_security_group_id`, rather than a broad CIDR. That's more
secure (app tier only accepts traffic from the actual web tier, not
anything else in the VPC), but requires one `for_each` instance's
configuration to reference a *specific sibling instance's* output,
which is a materially more complex dependency pattern than the core
`for_each`-on-modules lesson this demo is trying to teach in
isolation.

**Q3. If you added a fourth tier to `local.tiers`, what would happen
to the existing three tiers' security groups?**
Nothing — each existing tier's security group is tied to its own key
in the map (`web`, `app`, `db`), not to its position or count.
Terraform would plan exactly one new resource for the new key, with
zero changes proposed for the existing three, since their
identifying keys haven't changed.

---

## Key Takeaways

1. **`for_each` on a `module` block creates one independent instance
   per key in a map** — not several copy-pasted `module` blocks with
   near-identical content.

2. **A `for_each`'d module is addressed as
   `module.<name>["<key>"].<output>`** — referencing it without a key
   is an error the instant `for_each` is added, even if it worked fine
   before.

3. **A `for` expression over a `for_each`'d module builds one combined
   output across all its instances**, avoiding a separate `output`
   block per expected key.

4. **Modules compose directly** — one module's output can be passed
   straight into a second module's input, with no manual value-copying
   involved.

> **Demo scope:** Primary concept: `for_each` on a module block,
> creating multiple independent instances from one call. Supporting
> concepts: addressing a specific `for_each`'d instance, building a
> combined output with a `for` expression, module-to-module
> composition.
> Estimated completion time: 35–40 minutes.
> Checkpoints: 3 natural stopping points (end of Part A, end of
> Part B, end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform output tier_security_group_ids` | Reads the combined map built by the `for` expression over all `for_each`'d instances |
| `aws ec2 describe-security-groups --filters ...` | Confirms all three tier security groups are genuinely deleted after `destroy` |

---

## Next Demo

**Demo 18 — Workspaces.** Shifts from module composition to
environment isolation — using Terraform workspaces to manage separate
dev/staging/prod state for the same configuration, rather than
`for_each` over a map within one state.

---

## Appendix — Anki Cards

**17-three-tier-modules-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 2 - Modules::17-three-tier-modules
#separator:Comma
#columns:Front,Back,Tags
"What does for_each on a module block actually produce?","One independent module instance per key in the given map — not several copy-pasted module blocks. Each instance has its own full set of internal resources.","demo17,modules,foreach,ta004-obj5c"
"How do you address one specific instance of a for_each'd module?","module.<name>[\"<key>\"].<output> — e.g. module.tier_sg[\"web\"].security_group_id. Referencing it without a key is invalid once for_each is present.","demo17,modules,foreach,ta004-obj5c"
"How do you build one combined output covering every instance of a for_each'd module?","A for expression over the module itself: { for k, v in module.tier_sg : k => v.security_group_id } — one line instead of a separate output block per key.","demo17,modules,foreach,ta004-obj5c"
"Do independent instances of a for_each'd module create in a fixed, sequential order?","No — instances with no dependency on each other create in parallel. Order is only forced when one instance's configuration actually depends on another's output.","demo17,modules,foreach"
"What happens to existing for_each'd module instances when you add a new key to the driving map?","Nothing changes for the existing instances — Terraform plans exactly one new resource for the new key, since each instance's identity is tied to its own key, not its position or count.","demo17,modules,foreach,ta004-obj5c"
"How does one module's output get passed into a second module's input?","Directly, as a plain reference — e.g. vpc_id = module.vpc.vpc_id inside a second module's call. No manual copying of the value is needed.","demo17,modules,composition"
"Why does this demo scope each tier's security group to the VPC CIDR instead of chaining tier-to-tier?","Chaining (app only accepting traffic specifically from web's security group) is more secure but requires one for_each instance to reference a specific sibling instance's output — a more complex pattern kept separate from the core for_each-on-modules lesson.","demo17,modules,foreach,gotcha"
```

---

## Appendix — Quiz

**17-three-tier-modules-quiz.md:**

````markdown
# Quiz — Demo 17: Three-Tier Modules

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 18.

---

**Q1. (Multiple Choice)** What does `for_each = local.tiers` on a
`module` block actually produce?

- A) One module instance, reused three times sequentially
- B) One independent module instance per key in `local.tiers`
- C) A single merged instance combining all three tiers' configuration
- D) A compile-time error, since modules can't use `for_each`

<details>
<summary>Answer</summary>

**B.** `for_each` on a module block produces one fully independent
instance per key, each with its own internal resources. **A**, **C**,
and **D** all describe behaviors that don't occur.

</details>

---

**Q2. (True/False)** Once a `module` block has `for_each`, it can
still be referenced the same way as before — e.g.
`module.tier_sg.security_group_id`.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** A `for_each`'d module must be addressed with a specific
key — `module.tier_sg["web"].security_group_id` — referencing it with
no key becomes an error.

</details>

---

**Q3. (Multiple Choice)** How do you build one output covering every
instance of a `for_each`'d module, without one `output` block per
expected key?

- A) Write a separate `output` block for each key manually
- B) Use a `for` expression over the module: `{ for k, v in module.x : k => v.output }`
- C) Reference `module.x.all_outputs`
- D) This isn't possible — one block per key is required

<details>
<summary>Answer</summary>

**B.** A `for` expression over the module itself builds the combined
map in one line. **A** works but doesn't scale and breaks if keys
change. **C** and **D** describe things that don't exist/aren't true.

</details>

---

**Q4. (Multiple Choice)** Do independent instances of a `for_each`'d
module (with no dependency on each other) create sequentially or in
parallel?

- A) Always sequentially, in map key order
- B) In parallel, since nothing about them depends on another instance
- C) Sequentially, but in a random order
- D) Terraform errors if more than one instance exists at once

<details>
<summary>Answer</summary>

**B.** With no cross-instance dependency, Terraform creates them
concurrently. **A**, **C**, and **D** all describe incorrect
behaviors.

</details>

---

**Q5. (Multiple Choice)** A new key is added to the map driving a
`for_each`'d module. What happens to the existing instances?

- A) All instances are destroyed and recreated
- B) Only the new key's instance is created; existing instances are untouched
- C) Existing instances are renamed to match the new key ordering
- D) Terraform requires manually re-keying every instance

<details>
<summary>Answer</summary>

**B.** Each instance's identity is tied to its own key — adding a new
key only creates that one new instance. **A**, **C**, and **D** all
describe unnecessary, incorrect disruption.

</details>

---

**Q6. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about this demo's module composition are correct?

- A) `module.vpc.vpc_id` is passed directly as the security-group module's `vpc_id` input
- B) The VPC's ID must be manually copied from the Console into the security-group module's configuration
- C) Module composition means one module's output can feed directly into another module's input
- D) Modules cannot consume another module's output — only root-level variables

<details>
<summary>Answer</summary>

**A and C.** The VPC module's output is referenced directly, with no
manual copying — ruling out **B**. This is exactly what module
composition means — ruling out **D**.

</details>

---

**Q7. (True/False)** This demo's tier security groups restrict each
tier's ingress specifically to the security group of the tier above
it (e.g., app only accepts traffic from web's security group).

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** This demo scopes ingress to the VPC's CIDR block for
simplicity — true tier-to-tier security-group chaining is a real,
more advanced pattern, noted but not built in this demo.

</details>

---

**Q8. (Multiple Choice)** What causes an "Unsupported attribute" error
on `each.valeu.port` inside a `for_each`'d module block?

- A) `local.tiers` doesn't have a `port` key
- B) `each` only exposes `key` and `value` — `valeu` is a typo
- C) `for_each` doesn't support nested map values
- D) The module doesn't accept a `port`-shaped ingress rule

<details>
<summary>Answer</summary>

**B.** `each.valeu` is simply a typo of `each.value` — `each` always
exposes exactly `key` and `value`, nothing else. **A**, **C**, and
**D** all misdiagnose a plain typo as something more structural.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 7-8/8 | Import Anki cards, move to Demo 18 |
| 6/8 | Review the wrong answers, then proceed |
| 4-5/8 | Re-read the relevant sections, retry those questions |
| Below 4/8 | Re-read the full demo and redo the walkthrough before proceeding |
````