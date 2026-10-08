# Demo 16 — VPC Module

---

## Overview

Every demo in this series so far has run inside the AWS account's
**default VPC** — never explicitly created, never explicitly
managed. That's fine for learning individual services in isolation,
but CloudNova can't run real workloads in the default VPC: no
control over subnet layout, no separation between public-facing and
internal resources, no NAT strategy. This demo builds CloudNova's
first real, purpose-built VPC — using the single most widely-adopted
module on the entire Terraform Registry —
`terraform-aws-modules/vpc/aws`.

**Real-world scenario — CloudNova:** the platform team needs a
properly segmented network before any real application workload can
be deployed on top of it (coming in Phase 3) — public subnets for
anything internet-facing, private subnets for everything else, and a
NAT Gateway so private-subnet resources can still reach the internet
outbound (for package installs, API calls) without being reachable
from it. Hand-writing this from raw `aws_vpc`/`aws_subnet`/
`aws_route_table`/`aws_nat_gateway` resources is exactly the kind of
well-solved problem this module exists for.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Calling the VPC Module                                        │
│  module "vpc" { source = "terraform-aws-modules/vpc/aws" version =      │
│  "~> 6.0" ... } — 2 AZs, 2 public subnets, 2 private subnets            │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Enabling NAT Gateway                                          │
│  enable_nat_gateway = true, single_nat_gateway = true — this series'    │
│  first genuinely non-zero-cost resource                                 │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Verifying Subnet Routing                                      │
│  module.vpc.vpc_id / public_subnets / private_subnets read at root,     │
│  Console check confirming route table differences between the two      │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- Calling `terraform-aws-modules/vpc/aws` — this series' largest
  third-party module surface so far (~118 possible internal
  resources, dozens of documented inputs)
- Public vs. private subnets, and how a module encodes that
  distinction through separate `public_subnets`/`private_subnets`
  list inputs rather than a `public`/`private` flag on one resource
- `enable_nat_gateway` / `single_nat_gateway` — enabling outbound
  internet access for private subnets, and the real cost that comes
  with it
- Reading this module's specific documented outputs:
  `vpc_id`, `public_subnets`, `private_subnets`

**What this demo does NOT cover:** calling this module multiple times
via `for_each` for multiple environments (Demo 17), VPC endpoints,
VPC peering, Transit Gateway, or any of this module's dozens of other
inputs beyond the subset used here.

---

## How This Demo's Pieces Fit Together

**The AWS solution:** one VPC, two Availability Zones, one public
subnet and one private subnet per AZ, one Internet Gateway, one shared
NAT Gateway — all created by a single `module "vpc"` call.

- Root's `main.tf` calls `terraform-aws-modules/vpc/aws`, passing
  `cidr`, `azs`, `public_subnets`, `private_subnets`, and
  `enable_nat_gateway = true` with `single_nat_gateway = true`.
- Internally, this one module call creates the VPC itself, an Internet
  Gateway, a NAT Gateway with its own Elastic IP, and — critically —
  **two different route tables**: the public subnets' route table
  sends `0.0.0.0/0` traffic to the Internet Gateway directly; the
  private subnets' route table sends `0.0.0.0/0` to the NAT Gateway
  instead. This is the actual mechanism that makes a subnet "public" or
  "private" — not a label, a routing decision.
- Root's `outputs.tf` reads `module.vpc.vpc_id`,
  `module.vpc.public_subnets`, and `module.vpc.private_subnets` — the
  last two are **lists** of subnet IDs (one per AZ), not single
  values, since this module creates more than one of each.
- Nothing is deployed *into* these subnets yet — that's Phase 3's job.
  This demo's entire scope is the network itself.

---

## Prerequisites

### Knowledge
- Demo 15 completed — registry module sourcing, version constraints,
  reading a third-party module's documented inputs/outputs rather than
  assuming them

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | `>= 1.15.0` (pinned `~> 1.15.0` in this demo) | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version` |

### Verify AWS Account and Permissions

**Step 1 — Confirm your profile works:**

```bash
aws sts get-caller-identity --profile default --region us-east-2
```

**Step 2 — A cheap, harmless dry-run of this demo's actual service:**

```bash
aws ec2 describe-vpcs --profile default --region us-east-2
# Expected: JSON with a Vpcs array (the default VPC will appear —
# that is fine, this only confirms the permission itself works)
# If you see AccessDenied/UnauthorizedOperation: fix IAM permissions
# before proceeding, not after you're mid-lab
```

**Step 3 — Verify IAM permissions in Console:**

```
Console → IAM → Users → test → Permissions tab
  → Confirm AmazonVPCFullAccess (or equivalent) is attached ✅
```

**Required permissions for this demo:**

```
ec2:CreateVpc, ec2:DeleteVpc, ec2:DescribeVpcs, ec2:CreateTags
ec2:CreateSubnet, ec2:DeleteSubnet, ec2:DescribeSubnets
ec2:CreateInternetGateway, ec2:AttachInternetGateway, ec2:DeleteInternetGateway
ec2:CreateNatGateway, ec2:DeleteNatGateway, ec2:DescribeNatGateways
ec2:AllocateAddress, ec2:ReleaseAddress, ec2:DescribeAddresses
ec2:CreateRouteTable, ec2:CreateRoute, ec2:AssociateRouteTable, ec2:DeleteRouteTable
ec2:CreateSecurityGroup, ec2:DeleteSecurityGroup, ec2:DescribeSecurityGroups
```

> This is a substantially longer permission list than any prior demo —
> a direct reflection of how many distinct resource types one VPC
> module call actually creates under the hood.

### Versions used in this demo

| Tool / Module | Version |
|---|---|
| Terraform | `~> 1.15.0` (module's own stated minimum is looser: `>= 1.0`) |
| AWS Provider | `~> 6.47.0` (module's own stated minimum is looser: `>= 6.28`) |
| `terraform-aws-modules/vpc/aws` | `~> 6.0` |
| AWS CLI | `>= 2.x` |

> **Versions pinned as of September 2026** — same dating convention
> used throughout this series. Check the provider's and module's own
> changelogs before assuming these exact patch/minor levels are still
> current if you're running this well after that date; the `~>`
> constraints themselves don't need to change just because time has
> passed.

> ⚠️ [VERIFY — exact patch-level version]: same caveat as Demo 15 —
> the module's exact latest release tag wasn't confirmable through
> available tooling at authoring time. Run `terraform init` yourself
> and check `.terraform/modules/modules.json` for the exact resolved
> version.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Call a large, complex third-party registry module using only a
   relevant subset of its documented inputs
2. ✅ Explain how a module encodes the public/private subnet
   distinction through separate list inputs, not a boolean flag
3. ✅ Enable NAT Gateway via a module input, and explain what it
   actually costs and why
4. ✅ Explain the routing difference between a public and a private
   subnet — Internet Gateway vs. NAT Gateway as the `0.0.0.0/0` target
5. ✅ Build and verify a real multi-AZ VPC with public and private
   subnets entirely through a single module call

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| VPC, subnets, route tables, Internet Gateway | Always free | **$0.00** | No charge for these regardless of free-tier status |
| NAT Gateway (×1, shared) | **Not free-tier eligible** | **~$0.045/hour** (~$0.75 for a 1-hour session) | Billed per hour it exists, plus ~$0.045/GB of data processed |
| Elastic IP (attached to the NAT Gateway) | **Not free-tier eligible** — AWS bills every public IPv4 address, attached or idle, since February 1, 2024 | **~$0.005/hour**, same rate whether attached or idle | Cleanup releases it to stop the charge — but releasing doesn't retroactively refund hours already billed |
| **Session total (≈1 hour)** | | **≈ $0.75–$1.00** | **First genuinely non-zero-cost demo in this series** |

> ⚠️ [VERIFY — cost total]: the NAT Gateway line's own math doesn't
> reconcile ($0.045/hour × 1 hour ≠ $0.75) and this session-total
> figure matches a project-level planning document's independently
> stated `~$1.00/session` for this demo almost exactly — flagging
> rather than silently correcting, since it isn't clear whether that's
> a shared arithmetic error or a deliberate conservative estimate
> accounting for something not shown here (a longer realistic session,
> heavier data-processing testing, etc.). The Elastic IP row above has
> been corrected to reflect real, current AWS pricing (it is not free
> while attached, confirmed against AWS's own official pricing
> announcement) independent of how the total above is ultimately
> resolved.

> ⚠️ This demo has a real cost, unlike every prior demo. **Do not skip
> Cleanup** — a NAT Gateway left running accrues hourly charges
> indefinitely.

---

## Directory Structure

```
16-vpc-module/
├── README.md
├── 16-vpc-module-anki.csv
├── 16-vpc-module-quiz.md
└── src/
    ├── versions.tf      # terraform block + provider version constraints
    ├── provider.tf       # AWS provider: region, profile
    ├── variables.tf      # root-level inputs: VPC name, CIDR
    ├── main.tf            # module "vpc" block — calls the registry module
    ├── outputs.tf         # root outputs re-exposing vpc_id / subnet lists
    └── break-fix/
        └── broken.tf         # root config with 3 deliberate VPC-module errors
```

---

## Recall Check — Demo 15

Answer from memory before reading further:

1. What does a module version constraint like `~> 5.0` actually
   permit, and what does it block?
2. Where is a resolved module version actually recorded — and where
   is it specifically **not** recorded?
3. Should you assume a new registry module's output names by analogy
   to a module you've already used? Why or why not?

<details>
<summary>Answers</summary>

1. It permits any `5.x` release — patch and minor version increases —
   while blocking resolution to `6.0` or any higher major version,
   preventing a silent breaking upgrade.
2. In `.terraform/modules/modules.json`, inside the `.terraform`
   working directory. It is specifically **not** recorded in
   `.terraform.lock.hcl` — that file exclusively tracks provider
   versions and checksums.
3. No — every module's documented inputs and outputs are its own.
   Demo 15's own module used `s3_bucket_arn`, prefixed differently
   from Demo 14's unprefixed `topic_arn` — assuming by analogy is
   exactly the mistake that demo's Break-Fix tested for.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `cidr` | Module input | The VPC's overall IP address range |
| `azs` | Module input | List of Availability Zones to spread subnets across |
| `public_subnets` / `private_subnets` | Module inputs | Separate lists of CIDR blocks — this module's way of encoding the public/private distinction |
| `enable_nat_gateway` / `single_nat_gateway` | Module inputs | Enables outbound internet access for private subnets, via one shared NAT Gateway |
| `vpc_id`, `public_subnets`, `private_subnets` | Module outputs | This module's documented outputs used in this demo |

**Related constructs worth knowing (not covered in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| `for_each` on this same `module` block, for multiple environments | Calling this module more than once | Demo 17 (Three-Tier Modules) |
| VPC endpoints, VPC peering, Transit Gateway | Advanced networking features this module also supports | Not covered in this series |

---

### Detailed Explanation of New Constructs

#### Calling the VPC Module — `cidr`, `azs`, and the Subnet Lists

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = ["us-east-2a", "us-east-2b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    ManagedBy = "terraform-demo-16"
  }
}
```

**What it does:** `cidr` sets the VPC's overall address block. `azs`
is a plain list of Availability Zone names — this module handles
distributing subnets across them internally; nothing about `count` or
`for_each` is needed at the call site for that distribution to happen.
`public_subnets` and `private_subnets` are each a list of CIDR blocks
— **the module infers "public" or "private" purely from which list a
CIDR block appears in**, not from any name or flag on the CIDR itself.

> **Same as X" ban check — restating, not just pointing:** Demo 15's
> module took a flat `bucket` string as its main input. This module's
> `public_subnets`/`private_subnets` are lists, and their *position*
> in the list, paired with the *position* in `azs`, is what determines
> which AZ each subnet lands in — the first CIDR in `public_subnets`
> pairs with the first AZ in `azs`, and so on. This is a materially
> different input shape from anything this series has called before.

**Reading this module's outputs — `vpc_id`, `public_subnets`,
`private_subnets`:** `module.vpc.vpc_id` is a single value, since
there's exactly one VPC. `module.vpc.public_subnets` and
`module.vpc.private_subnets` are each **lists** of subnet IDs, one per
AZ, in the same order as the corresponding input lists — a direct
consequence of the module creating more than one subnet of each kind.

---

#### `enable_nat_gateway` / `single_nat_gateway` — Outbound Internet for Private Subnets

**What it does:** `enable_nat_gateway = true` creates a NAT Gateway —
a managed AWS resource that lets resources in private subnets
initiate outbound internet connections (installing packages, calling
external APIs) **without** being reachable from the internet
themselves, the way a public subnet's resources are.
`single_nat_gateway = true` means exactly one NAT Gateway is created
and shared by every private subnet, regardless of how many AZs are in
use — the cost-conscious default, versus creating one NAT Gateway per
AZ (higher cost, higher availability, since a single shared NAT
Gateway is itself a single point of failure for outbound traffic).

> **This is the first resource in the entire series with a real,
> non-trivial cost.** A NAT Gateway bills hourly for its own existence
> — roughly $0.045/hour — plus a per-GB charge for data it processes,
> regardless of whether anything is actually using it. This is exactly
> why Cost & Free Tier above flags this demo explicitly, and why
> Cleanup is not optional here the way it was more of a formality in
> prior demos.

---

#### How Routing Actually Makes a Subnet "Public" or "Private"

**What it does:** this module creates two separate route tables — one
associated with the public subnets, one with the private subnets. The
public route table sends `0.0.0.0/0` (all outbound traffic with no
more specific route) to the Internet Gateway. The private route table
sends the same `0.0.0.0/0` to the NAT Gateway instead. Both tables
exist because this module built them, as a direct consequence of the
`public_subnets`/`private_subnets` split at the call site.

> **"Public" and "private" are a routing outcome, not a subnet
> property.** A subnet has no attribute that says "I am public" — a
> subnet in this module's `public_subnets` list ends up associated
> with the route table that happens to point at the Internet Gateway.
> Two subnets with identical CIDR blocks, associated with different
> route tables, would have completely different public/private
> behavior — the distinction lives entirely in the routing, not in
> anything about the subnet resource itself.

---

## Lab Step-by-Step Guide

---

## Part A — Calling the VPC Module

Part A calls the module with a basic 2-AZ, public and private subnet
layout — NAT Gateway not yet enabled.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-2-modules/16-vpc-module/src
```

### Step 2 — Create the root scaffolding files

This step scaffolds the root configuration's provider and version
pins, plus the root-level inputs for the VPC's name and overall CIDR
block.

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

#### `variables.tf` — Root-level inputs

This file declares the two root-level variables this demo uses — the
VPC's name and its overall CIDR block, both passed into the module
call.

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

variable "vpc_name" {
  type        = string
  description = "Name passed into the VPC module's name input"
  default     = "cloudnova-demo16-vpc"
}

variable "vpc_cidr" {
  type        = string
  description = "Overall CIDR block for the VPC"
  default     = "10.0.0.0/16"
}
```

### Step 3 — Call the VPC module, without NAT Gateway yet

This step calls the VPC module for the first time, with a 2-AZ
public/private subnet layout and NAT Gateway left at its default
(disabled).

Create a file **main.tf** and add the below content:

This file contains the single call to `terraform-aws-modules/vpc/aws`,
passing the subset of its documented inputs this demo actually needs.

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = ["us-east-2a", "us-east-2b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  tags = {
    ManagedBy = "terraform-demo-16"
  }
}
```

### Step 4 — Create the root outputs

This step exposes the module's VPC ID and both subnet-ID lists at
root, so all three can be read after apply and checked against the
Console.

Create a file **outputs.tf** and add the below content:

This file reads `module.vpc.vpc_id`, `module.vpc.public_subnets`, and
`module.vpc.private_subnets` and re-exposes all three as root-level
outputs.

```hcl
output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "ID of the VPC created via the module"
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnets
  description = "IDs of the public subnets, one per AZ"
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnets
  description = "IDs of the private subnets, one per AZ"
}
```

### Step 5 — Initialize and apply

This step initializes, validates, and applies the configuration,
creating the VPC, its subnets, the Internet Gateway, and both route
tables — everything except NAT Gateway, which isn't enabled yet.

```bash
terraform init
terraform validate
terraform apply
```

Expected:

```
module.vpc.aws_vpc.this[0]: Creating...
module.vpc.aws_vpc.this[0]: Creation complete after 2s
module.vpc.aws_subnet.public[0]: Creating...
module.vpc.aws_subnet.public[1]: Creating...
module.vpc.aws_subnet.private[0]: Creating...
module.vpc.aws_subnet.private[1]: Creating...
module.vpc.aws_internet_gateway.this[0]: Creating...
module.vpc.aws_route_table.public[0]: Creating...
module.vpc.aws_route_table.private[0]: Creating...
[... additional route table associations ...]

Apply complete! Resources: 11 added, 0 changed, 0 destroyed.

Outputs:

private_subnet_ids = ["subnet-0aaa...", "subnet-0bbb..."]
public_subnet_ids  = ["subnet-0ccc...", "subnet-0ddd..."]
vpc_id             = "vpc-0eee..."
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **No NAT Gateway resources appear yet.** `enable_nat_gateway`
> defaults to `false` — private subnets right now have no outbound
> internet route at all, only whatever's inside the VPC. Part B adds
> this.

---

## Part B — Enabling NAT Gateway

Part B turns on outbound internet access for the private subnets, and
shows the real, billable resources that creates.

### Step 6 — Add NAT Gateway to the module call

This step adds NAT Gateway support to the existing module call,
without touching anything else about the configuration.

In **main.tf**, add the following two lines inside the existing
`module "vpc"` block, alongside the other arguments:

```hcl
  enable_nat_gateway = true
  single_nat_gateway = true
```

### Step 7 — Apply the change

This step applies the NAT Gateway addition and confirms it's purely
additive — nothing from Part A gets replaced or modified.

```bash
terraform plan
```

Expected — note this is an addition, not a modification of anything
created in Part A:

```
Terraform will perform the following actions:

  # module.vpc.aws_eip.nat[0] will be created
  # module.vpc.aws_nat_gateway.this[0] will be created
  # module.vpc.aws_route.private_nat_gateway[0] will be created

Plan: 3 to add, 0 to change, 0 to destroy.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

```bash
terraform apply
```

Expected:

```
module.vpc.aws_eip.nat[0]: Creating...
module.vpc.aws_eip.nat[0]: Creation complete after 1s
module.vpc.aws_nat_gateway.this[0]: Creating...
module.vpc.aws_nat_gateway.this[0]: Still creating... [2m0s elapsed]
module.vpc.aws_nat_gateway.this[0]: Creation complete after 2m34s
module.vpc.aws_route.private_nat_gateway[0]: Creating...
module.vpc.aws_route.private_nat_gateway[0]: Creation complete after 1s

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment. NAT Gateway provisioning genuinely takes 1–4 real
> minutes — this is one of the slowest single resources this series
> has created.

> **This apply added exactly 3 resources on top of Part A's 11** — the
> Elastic IP, the NAT Gateway itself, and one new route in the private
> route table pointing at it. Nothing from Part A was replaced or
> modified; the private subnets themselves are untouched.

---

## Part C — Verifying Subnet Routing

Part C confirms, directly in the Console, that public and private
subnets really do route differently — not just taking that on faith
from the module's naming.

### Step 8 — Read the outputs

```bash
terraform output
```

Expected: the same `vpc_id`, `public_subnet_ids`, and
`private_subnet_ids` values shown in Part A's apply output.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

### Step 9 — Verify in the Console

This step confirms in the Console that public and private subnets
genuinely route differently, rather than trusting the module's naming
alone.

```
Console → VPC → Your VPCs → cloudnova-demo16-vpc
  → VPC exists, ID matches `terraform output vpc_id` exactly ✅

Console → VPC → Route Tables
  → Public route table → Routes tab → 0.0.0.0/0 → target is the
    Internet Gateway (igw-...) ✅
  → Private route table → Routes tab → 0.0.0.0/0 → target is the
    NAT Gateway (nat-...) ✅ — this is the actual routing difference,
    not just a naming convention
```

> 📷 [Screenshot placeholder: AWS Console → VPC → Route Tables,
> showing the public route table's 0.0.0.0/0 target as the Internet
> Gateway and the private route table's 0.0.0.0/0 target as the NAT
> Gateway]

---

## Cleanup

### Step 10 — Destroy all resources

```bash
terraform destroy
```

Type `yes`. Expected — note NAT Gateway deletion also takes real time:

```
module.vpc.aws_route.private_nat_gateway[0]: Destroying...
module.vpc.aws_nat_gateway.this[0]: Destroying...
module.vpc.aws_nat_gateway.this[0]: Still destroying... [1m0s elapsed]
module.vpc.aws_nat_gateway.this[0]: Destruction complete after 1m12s
module.vpc.aws_eip.nat[0]: Destroying...
module.vpc.aws_eip.nat[0]: Destruction complete after 1s
[... remaining resources destroyed ...]
module.vpc.aws_vpc.this[0]: Destroying...
module.vpc.aws_vpc.this[0]: Destruction complete after 1s

Destroy complete! Resources: 14 destroyed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

### Step 11 — Confirm the NAT Gateway is genuinely gone

```bash
aws ec2 describe-nat-gateways --filter "Name=tag:ManagedBy,Values=terraform-demo-16" --profile default --region us-east-2
```

Expected: an empty `NatGateways` list, or all entries showing state
`deleted`.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **Confirm the NAT Gateway is actually gone, specifically.** Of
> everything this demo created, the NAT Gateway is the one resource
> that costs money simply by existing — verifying its absence here
> matters more than it did for any prior demo's cleanup check.

---

## What You Learned

1. ✅ A large third-party module can be called using only the small
   subset of its inputs actually relevant to the task — not all of
   its dozens of documented options
2. ✅ Public vs. private subnets are encoded as separate list inputs
   (`public_subnets`/`private_subnets`), not a flag on one resource
3. ✅ `enable_nat_gateway`/`single_nat_gateway` create a real,
   hourly-billed resource — the first non-zero-cost resource in this
   series
4. ✅ The actual public/private distinction lives in each subnet's
   associated route table's `0.0.0.0/0` target — Internet Gateway for
   public, NAT Gateway for private
5. ✅ A module's outputs can be lists (`public_subnets`,
   `private_subnets`), not just single values, when the module creates
   more than one of something

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| Calling a large registry module with a subset of its inputs | TA-004 Obj 5c | Reinforces "use modules in configuration" at greater real-world scale |
| Reading list-typed module outputs (`public_subnets`) | TA-004 Obj 5c | Distinct from Demo 14/15's single-value outputs |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam asks what makes a subnet "public" vs "private" | Recognizing it's the associated route table's `0.0.0.0/0` target, not a subnet attribute | Assuming there's a `public = true` argument on the subnet resource itself |
| Exam shows `enable_nat_gateway = false` (the module's own default) | Recognizing private subnets have zero outbound internet route at all in that case | Assuming private subnets always have *some* internet access by default |
| Exam asks about NAT Gateway cost | Recognizing it bills hourly regardless of usage, plus a data-processing charge | Assuming it's free-tier eligible like most other networking resources |

### Exam Task — Write a complete configuration

**Task:** CloudNova's staging environment needs its own VPC, in a
different region, with 3 AZs instead of 2, and NAT Gateway disabled
(staging doesn't need real internet egress from private subnets yet).

**Block types required:** `module` (×1), `variable` (×2, for region and
VPC name)

**Official documentation:**
- [`terraform-aws-modules/vpc/aws`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest)

**What to practise:**
1. Check the module's actual documented inputs for the exact argument
   controlling AZ count/list — don't assume it matches this demo's
2. Write the `module` block from scratch, with `enable_nat_gateway`
   explicitly `false`
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
variable "vpc_name" {
  type    = string
  default = "cloudnova-staging-vpc"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.vpc_name
  cidr = "10.1.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  private_subnets = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]

  enable_nat_gateway = false
}
```

**Arguments you must know without looking up:**
- `azs`, `public_subnets`, and `private_subnets` must all have matching
  list lengths — one entry per AZ, in the same order
- `enable_nat_gateway` defaults to `false` — it must be explicitly set
  `true` for any outbound private-subnet internet access to exist at all

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `InvalidParameterValue` on subnet creation, CIDR overlap | Two subnet CIDRs (public or private) overlap each other, or fall outside the VPC's own `cidr` range | Confirm every subnet CIDR is a genuine, non-overlapping subset of the VPC's `cidr` |
| `public_subnets`/`private_subnets`/`azs` list length mismatch | These three lists must have matching lengths — one subnet per AZ, per list | Confirm all three lists have the same number of entries |
| NAT Gateway takes several minutes and `apply` appears to hang | This is expected — NAT Gateway provisioning genuinely takes 1–4 real minutes | Wait; this is not an error |

---

## Break-Fix Scenario

Three deliberate errors calling the VPC module — single self-contained
file, same as Demo 15's break-fix (no local callee to manage here
either).

```bash
cd src/break-fix/
terraform init
```

#### `broken.tf` — Three deliberate errors

This file is a self-contained root configuration calling the real VPC
module, with a subnet/AZ list length mismatch, an out-of-range subnet
CIDR, and a wrong output reference — diagnose all three.

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

  name = "cloudnova-broken-demo16"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2a", "us-east-2b"]
  public_subnets  = ["10.0.1.0/24"]              # Error 1: only 1 entry, azs has 2
  private_subnets = ["10.5.11.0/24", "10.0.12.0/24"] # Error 2: 10.5.11.0/24 is outside the VPC's 10.0.0.0/16 range
}

output "vpc_identifier" {
  value = module.vpc.id # Error 3: wrong output name (should be vpc_id)
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — `public_subnets` has only 1 entry, `azs` has 2**
This module requires matching list lengths across `azs`,
`public_subnets`, and `private_subnets` — a mismatch produces an
"index out of range"-class error during `plan`. Fix: add a second
public subnet CIDR, e.g. `"10.0.2.0/24"`.

**Error 2 — a private subnet CIDR outside the VPC's own range**
`10.5.11.0/24` isn't a subset of `10.0.0.0/16` — AWS rejects this at
`apply` with an `InvalidParameterValue` error on subnet creation. Fix:
correct the CIDR to something within `10.0.0.0/16`, e.g.
`"10.0.11.0/24"`.

**Error 3 — wrong output name (`id` instead of `vpc_id`)**
This module's actual output is `vpc_id` — there is no bare `id`.
Reported as an "Unsupported attribute" error at `validate`. Fix:
reference `module.vpc.vpc_id` instead.

> ⚠️ [VERIFY — behavioral claim, docs-reasoning only, not a live run in
> this environment]: the exact error class and stage (`plan` vs
> `apply`) for Error 1 specifically isn't confirmed here — treat it as
> a genuine error to diagnose via `terraform plan`, not assume the
> precise wording shown above matches exactly.

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

**Q1. A teammate asks: "what actually makes a subnet public instead of
private — is it something in the subnet's own configuration?" How do
you answer?**
No — a subnet has no "I am public" attribute. What makes it public is
which route table it's associated with, and specifically whether that
route table's `0.0.0.0/0` route points at an Internet Gateway (public)
or a NAT Gateway (private, outbound-only). Two subnets with identical
CIDR blocks and identical settings, associated with different route
tables, would behave completely differently.

**Q2. Why does this demo's Cost & Free Tier section look completely
different from every prior demo's?**
Because `enable_nat_gateway = true` creates a NAT Gateway — the first
resource in this series that bills simply for existing, regardless of
whether it's actually processing any traffic. Every prior demo's
resources (SNS topics, S3 buckets, local/registry modules calling
free-tier-eligible services) had no ongoing hourly cost at all.

**Q3. Why does `public_subnets` being a list, rather than a single
string, matter for how this module's outputs behave?**
Because the module creates one subnet per entry in the list — its
`public_subnets` *output* is correspondingly a list of the resulting
subnet IDs, one per AZ, not a single value. Reading
`module.vpc.public_subnets` gives back an ordered list matching the
order of the original `public_subnets` input list, not one arbitrary
subnet.

---

## Key Takeaways

1. **A large third-party module can be called using only the inputs
   genuinely relevant to the task** — this module has dozens of
   documented inputs; this demo used seven.

2. **Public vs. private subnets are encoded as separate list inputs at
   the module call site, not a flag on any one resource** — the actual
   distinction is created downstream, in routing.

3. **The real mechanism behind "public" and "private" is each
   subnet's associated route table's `0.0.0.0/0` target** — Internet
   Gateway for public, NAT Gateway for private.

4. **`enable_nat_gateway = true` is the first genuinely non-zero-cost
   resource in this series** — it bills hourly for existing, plus
   per-GB for data processed, regardless of actual usage. Since
   February 2024, its attached Elastic IP bills separately too,
   whether attached or idle.

> **Demo scope:** Primary concept: calling `terraform-aws-modules/vpc/aws`
> to build a real multi-AZ VPC with public/private subnets and NAT
> Gateway. Supporting concepts: how routing (not subnet attributes)
> creates the public/private distinction, NAT Gateway's real cost.
> Estimated completion time: 40–45 minutes (NAT Gateway provisioning
> and teardown both take several real minutes).
> Checkpoints: 3 natural stopping points (end of Part A, end of
> Part B, end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform output` | Reads all root outputs at once — useful here since there are three (`vpc_id` plus two subnet-ID lists) |
| `aws ec2 describe-nat-gateways --filter ...` | Confirms a NAT Gateway is genuinely deleted after `destroy` — the one resource in this demo worth double-checking for cost reasons |

---

## Next Demo

**Demo 17 — Three-Tier Modules.** Composes this demo's VPC module
alongside additional modules into a full multi-tier architecture, and
introduces `for_each` on a module block — calling the same module
multiple times, deferred from this demo.

---

## Appendix — Anki Cards

**16-vpc-module-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 2 - Modules::16-vpc-module
#separator:Comma
#columns:Front,Back,Tags
"How does the terraform-aws-modules/vpc/aws module encode the public vs private subnet distinction?","Through two separate list inputs, public_subnets and private_subnets — the distinction comes from which list a CIDR block is placed in, not from any flag on the CIDR or subnet itself.","demo16,vpc,modules,ta004-obj5c"
"What actually makes a subnet 'public' at the AWS level?","Its associated route table's 0.0.0.0/0 route points at an Internet Gateway. A private subnet's route table instead points 0.0.0.0/0 at a NAT Gateway. It's a routing outcome, not a subnet attribute.","demo16,vpc,networking"
"What does enable_nat_gateway = true actually cost?","It's billed hourly (~$0.045/hr) simply for existing, plus a per-GB charge for data processed — regardless of whether anything is actively using it. Not free-tier eligible. Its attached Elastic IP bills separately too (~$0.005/hr, since February 2024), whether attached or idle.","demo16,vpc,cost,gotcha"
"What does single_nat_gateway = true mean, versus one NAT Gateway per AZ?","One shared NAT Gateway serves every private subnet regardless of AZ count — cheaper, but a single point of failure for outbound traffic, versus one-per-AZ which costs more but is more resilient.","demo16,vpc,cost"
"Why must azs, public_subnets, and private_subnets all have matching list lengths?","The module creates one subnet per AZ per list — a length mismatch across these three lists produces an index-based error at plan time.","demo16,vpc,break-fix"
"If enable_nat_gateway is left at its default, what internet access do private subnets have?","None — enable_nat_gateway defaults to false, meaning private subnets have zero outbound internet route unless explicitly enabled.","demo16,vpc,networking,ta004-obj5c"
"Why is module.vpc.public_subnets a list rather than a single value?","Because the module creates one subnet per entry in the public_subnets input list — its output correspondingly returns an ordered list of the resulting subnet IDs, one per AZ.","demo16,vpc,outputs"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the individual facts (routing
> mechanism, NAT cost model, list-length rule). This Quiz instead
> leans on reading real `plan`/`apply`-shaped output and diagnosing
> Break-Fix-style configuration mistakes, so the two together cover
> both recall and applied recognition without re-asking the same
> question twice.

**16-vpc-module-quiz.md:**

````markdown
# Quiz — Demo 16: VPC Module

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 17.

---

**Q1. (Multiple Choice)** `terraform plan` shows
`public_subnets = ["10.0.1.0/24"]` against `azs = ["us-east-2a",
"us-east-2b"]`. What should you expect?

- A) Terraform silently creates one public subnet and leaves the second AZ with none
- B) An index/length-mismatch error, since these lists must have matching lengths
- C) Terraform duplicates `10.0.1.0/24` into the second AZ automatically
- D) `plan` succeeds; the mismatch only fails at `apply`

<details>
<summary>Answer</summary>

**B.** `azs`, `public_subnets`, and `private_subnets` must all be the
same length — a mismatch surfaces as an index-based error, not a
silent partial deployment.

</details>

---

**Q2. (Multiple Choice)** A private subnet CIDR of `10.5.11.0/24` is
passed alongside a VPC `cidr` of `10.0.0.0/16`. What happens?

- A) Terraform automatically re-parents the subnet under the nearest valid range
- B) AWS rejects it at `apply` with an `InvalidParameterValue`-class error, since the subnet CIDR isn't a subset of the VPC's own range
- C) It's accepted — subnet CIDRs don't need to fall within the VPC's CIDR
- D) `terraform validate` catches this before `plan` even runs

<details>
<summary>Answer</summary>

**B.** Every subnet CIDR must be a genuine subset of the VPC's own
`cidr`. This is an AWS-side rejection at `apply` (a semantic/API-level
error), not something `validate`'s syntax-only checks would catch.

</details>

---

**Q3. (Multiple Choice)** After a correct `apply`, `output
"vpc_identifier" { value = module.vpc.id }` fails with `Unsupported
attribute`. What's the fix?

- A) Add `depends_on = [module.vpc]` to the output
- B) Reference `module.vpc.vpc_id` instead — the module has no bare `id` output
- C) Re-run `terraform init -upgrade`
- D) Add an explicit `count` index: `module.vpc[0].id`

<details>
<summary>Answer</summary>

**B.** This module's documented output is `vpc_id`, not `id` — a
guess-by-analogy mistake, exactly the class of error this series'
registry-module demos repeatedly warn against.

</details>

---

**Q4. (Multiple Choice)** `terraform plan` (after adding
`enable_nat_gateway = true` to an already-applied VPC) shows:
`Plan: 3 to add, 0 to change, 0 to destroy`. What does this tell you?

- A) The entire VPC will be replaced
- B) NAT Gateway resources are purely additive on top of the existing VPC — nothing from the earlier apply is touched
- C) The plan is invalid; enabling NAT Gateway always forces a subnet replacement
- D) This confirms the private subnets themselves will be recreated

<details>
<summary>Answer</summary>

**B.** Adding NAT Gateway support only adds the EIP, the NAT Gateway,
and one new route — nothing about the VPC, subnets, or route tables
created earlier needs to change or be destroyed.

</details>

---

**Q5. (Multiple Choice)** This module's `public_subnets = ["10.0.1.0/24",
"10.0.2.0/24"]` is paired with `azs = ["us-east-2a", "us-east-2b"]`.
How does the module decide which subnet lands in which AZ?

- A) Alphabetically, regardless of list order
- B) By position — the first CIDR in `public_subnets` pairs with the first AZ in `azs`, and so on
- C) Randomly, re-assigned on every apply
- D) By CIDR size, largest subnet to the first AZ

<details>
<summary>Answer</summary>

**B.** The module pairs list entries positionally — the first CIDR in
`public_subnets` lands in the first AZ listed in `azs`, the second
CIDR in the second AZ, and so on. This is also exactly why the two
lists (and `private_subnets`) must stay the same length.

</details>

---

**Q6. (Multiple Choice)** `terraform destroy` on this demo's resources
takes several real minutes and appears to "hang" during NAT Gateway
teardown. What's the correct response?

- A) Cancel and re-run with `-auto-approve` to force it through faster
- B) This is expected — NAT Gateway destruction genuinely takes 1–4 real minutes on AWS's side; wait
- C) This indicates a stuck Terraform state lock that needs manual clearing
- D) NAT Gateways can't be destroyed via Terraform at all — manual Console deletion is required

<details>
<summary>Answer</summary>

**B.** NAT Gateway create/destroy are both genuinely slow, real AWS
operations — not a Terraform bug or a stuck state lock. Cancelling
mid-destroy or resorting to manual Console deletion would only create
drift between state and reality.

</details>

---

**Q7. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements are accurate about this demo's NAT Gateway cost?

- A) It's billed only if a private-subnet resource actually sends traffic through it
- B) It bills hourly simply for existing, regardless of usage
- C) It also incurs a per-GB data-processing charge
- D) It's covered under the same free tier as the VPC/subnets/route tables themselves

<details>
<summary>Answer</summary>

**B and C.** NAT Gateway bills per hour of existence plus per-GB of
data processed — both apply regardless of whether it's actively being
used, and neither is free-tier eligible (ruling out **A** and **D**).

</details>

---

**Q8. (Multiple Choice)** CloudNova's staging VPC needs `enable_nat_gateway
= false`. What's the actual effect on the private subnets created?

- A) They fall back to routing `0.0.0.0/0` through the Internet Gateway instead
- B) They have zero outbound internet route configured at all
- C) The module refuses to create private subnets without a NAT Gateway
- D) A NAT instance (EC2-based) is created instead, as a fallback

<details>
<summary>Answer</summary>

**B.** With NAT Gateway disabled, private subnets simply have no
outbound internet route — not a silent fallback to the Internet
Gateway, and no automatic NAT-instance substitute.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 7-8/8 | Import Anki cards, move to Demo 17 |
| 6/8 | Review the wrong answers, then proceed |
| 4-5/8 | Re-read the relevant sections, retry those questions |
| Below 4/8 | Re-read the full demo and redo the walkthrough before proceeding |
````