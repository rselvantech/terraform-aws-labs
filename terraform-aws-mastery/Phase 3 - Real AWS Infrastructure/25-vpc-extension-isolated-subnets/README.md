# Demo 25 — VPC Extension: Isolated Subnets + Endpoints

---

## Overview

Every service is now running (23) with real, scoped IAM identity (24).
The one thing still missing before RDS can arrive at Demo 26 is
somewhere for it to actually live — a network tier that's neither
public (internet-facing) nor private (outbound-via-NAT), but
genuinely isolated: no route to the internet in either direction at
all. This demo extends the persistent VPC with exactly that tier, plus
an S3 gateway endpoint so isolated-subnet resources can still reach S3
without needing internet access to do it.

**Real-world scenario — CloudNova:**
RDS is coming next demo, and a database has no legitimate reason to
either receive inbound internet traffic or initiate outbound
connections to it. Public and private subnets (Demo 16/17's own
three-tier design) don't capture this distinction cleanly — private
subnets still route outbound through NAT, which is more access than a
database tier should have. This demo adds a third tier, isolated
subnets, specifically for that "no internet path in either direction"
requirement.

**What this demo builds:**
```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Isolated subnet tier                                         │
│  Added to the existing VPC module re-apply — no route table target    │
│  to the internet at all, in either direction                          │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — S3 gateway endpoint                                          │
│  Lets isolated-subnet resources reach S3 without any internet route   │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Verify: route tables show no internet path, endpoint works  │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- Isolated subnets — a genuinely different route-table shape from
  both public and private, not just "private with extra restrictions"
- VPC Gateway Endpoints — a route-table-level mechanism for reaching
  AWS services (S3, DynamoDB) without any internet path
- Why this demo makes no compute or IAM changes at all — purely
  networking, ahead of a resource (RDS) that doesn't exist yet

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** a third subnet tier added to the
same VPC module call 22d already re-applies, plus one
`aws_vpc_endpoint` resource of type `Gateway`, targeting S3. Nothing
here touches compute, IAM, or any of the five services — this demo is
pure networking, staged ahead of RDS specifically because Demo 26
needs somewhere to deploy into that doesn't exist yet.

**Why this lives in the same Terraform state as the VPC and EKS
cluster:** the isolated subnets are part of the same VPC, added via
the same module call 22d already established — there's no separate
"networking-only" state file to introduce. This has a direct
consequence worth stating explicitly: these subnets and the endpoint
follow the exact same every-session teardown lifecycle 22d already
set up for the VPC and cluster, not a new lifecycle category. `22d`'s
own `terraform destroy` already tears this down alongside everything
else in `phase-3-onward` once this demo adds it to that config.

**Why a gateway endpoint, not an interface endpoint:** S3 and
DynamoDB both support the older, free `Gateway` endpoint type — a
route-table entry, not a separate network interface with its own
hourly cost. Most other AWS services (SNS, SQS, ECR, CloudWatch, etc.)
only support the newer `Interface` endpoint type, which does have an
hourly cost. This demo uses S3's Gateway endpoint because it's free
and because Demo 26/27 will actually need isolated-subnet resources
reaching S3 (RDS automated backups) and DynamoDB.

---

## Prerequisites

### Knowledge
- 24 completed — this demo's config lives in the same
  `phase-3-onward` state as 22d/23/24's resources
- Demo 16/17 completed — public/private subnet routing, the
  foundation this demo's isolated tier contrasts against

### Required Tools

Same as 22d/23/24 — no new tools, only a new resource type
(`aws_vpc_endpoint`).

### Verify the VPC Module Is in a Known State

```bash
terraform state list | grep module.vpc
# Confirm the existing public/private subnet resources are present
# before adding a third tier to the same module call
```

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain what makes a subnet "isolated" as distinct from "private"
   — a route-table shape difference, not just a naming convention
2. ✅ Add a third subnet tier to an already-applied VPC module call
3. ✅ Write an `aws_vpc_endpoint` of type `Gateway`, targeting S3
4. ✅ Explain why Gateway endpoints are free and Interface endpoints
   generally aren't
5. ✅ Verify an isolated subnet's route table genuinely has no path to
   the internet, in either direction

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| Isolated subnets | Always free | **$0.00** | Subnets themselves never have an associated cost |
| S3 Gateway VPC Endpoint | Always free | **$0.00** | Gateway endpoints (S3, DynamoDB) have no hourly charge, unlike Interface endpoints |
| **Session total (in addition to 22d/23/24's)** | | **$0.00 additional** | Pure networking, no new cost-accruing resource |

---

## Directory Structure

```
25-vpc-extension-isolated-subnets/
├── README.md
├── 25-vpc-extension-isolated-subnets-anki.csv
├── 25-vpc-extension-isolated-subnets-quiz.md
└── src/
    └── phase-3-onward/                     # same config 22d's VPC/EKS live in
        └── vpc.tf                          # extended: isolated_subnets + S3 endpoint added
```

---

## Recall Check — 24 (IAM Least Privilege via EKS Pod Identity)

Answer from memory before reading anything new:

1. What is the trust policy `Principal` for a Pod Identity IAM role,
   and how does it differ from IRSA's?
2. Does a Pod Identity association bind to a Pod directly, or to
   something else?
3. Why does Demo 24 grant no RDS or DynamoDB permissions, even though
   both are confirmed to be coming soon?

<details>
<summary>Answers</summary>

1. `pods.eks.amazonaws.com` — a fixed, AWS-managed service principal,
   not tied to any specific cluster. IRSA's trust policy instead
   references a specific OIDC provider ARN tied to one cluster's own
   issuer URL.
2. A Kubernetes `ServiceAccount`, not a Pod directly. A Pod only gets
   the associated identity if its Deployment's spec references that
   ServiceAccount via `serviceAccountName`.
3. Incremental scoping (ADR-015) — access is granted to what's real,
   when it's real. Pre-scoping for resources that don't exist yet
   would mean referencing inaccurate ARNs or over-granting to compensate.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| Isolated subnets | VPC module input (`intra_subnets`) | A third subnet tier with no route to the internet in either direction |
| `aws_vpc_endpoint` | Resource | Provides a route-table-level path to an AWS service without using the internet |
| `vpc_endpoint_type = "Gateway"` | Resource argument | The free endpoint type, supported only by S3 and DynamoDB |

---

### Detailed Explanation of New Constructs

#### Isolated Subnets — A Genuinely Different Route-Table Shape

```
┌────────────────────────────────────────────────────────────────────────┐
│  PUBLIC            │  PRIVATE                  │  ISOLATED             │
│  Route: 0.0.0.0/0   │  Route: 0.0.0.0/0          │  No 0.0.0.0/0 route  │
│  → Internet Gateway │  → NAT Gateway              │  at all               │
│  Inbound + outbound │  Outbound only (via NAT)    │  No internet path,   │
│  internet access    │                              │  either direction    │
├────────────────────────────────────────────────────────────────────────┤
│  This demo's isolated tier has neither route — the only traffic that   │
│  reaches it is traffic originating inside the VPC itself, and its own  │
│  outbound traffic can only reach other AWS services via VPC endpoints, │
│  never the open internet.                                               │
└────────────────────────────────────────────────────────────────────────┘
```

This is the same `terraform-aws-modules/vpc/aws` module 22d already
re-applies — isolated subnets are just a third named input
(`intra_subnets`, in the module's own terminology) alongside the
existing `public_subnets`/`private_subnets` this series already uses.
No new resource type for the subnets themselves; the difference is
entirely in which route table each tier's subnets associate with.

---

#### `aws_vpc_endpoint` — Reaching AWS Services Without the Internet

| Argument | Required | Description |
|---|---|---|
| `vpc_id` | Yes | The VPC this endpoint belongs to |
| `service_name` | Yes | e.g. `com.amazonaws.us-east-2.s3` |
| `vpc_endpoint_type` | Yes | `"Gateway"` (free, S3/DynamoDB only) or `"Interface"` (hourly cost, most other services) |
| `route_table_ids` | Yes, for Gateway type | Which route tables get the endpoint's route entry added |

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.us-east-2.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = module.vpc.intra_route_table_ids
}
```

**What this actually does:** rather than a separate network interface
consuming an IP address, a Gateway endpoint adds a route table entry —
traffic destined for S3's IP ranges gets routed to the endpoint
instead of needing an internet path at all. This is why it's free:
there's no additional network appliance running, just a routing rule.

> ⚠️ [VERIFY — timing claim, docs only] The exact `service_name`
> format (`com.amazonaws.<region>.s3`) is region-specific — confirm
> the current format against AWS's own VPC endpoint documentation for
> your actual region before treating this as a fixed, universal string.

---

## Lab Step-by-Step Guide

---

## Part A — Add the Isolated Subnet Tier

### Step 1 — Navigate to the project config

```bash
cd terraform-aws-mastery/phase-3-real-aws-infrastructure/25-vpc-extension-isolated-subnets/src/phase-3-onward
```

### Step 2 — Extend vpc.tf

**Modify the existing `module "vpc"` block** (from 22d) to add a
third subnet tier:

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "cloudnova-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2a", "us-east-2b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  intra_subnets   = ["10.0.201.0/24", "10.0.202.0/24"]   # ← new: isolated tier

  enable_nat_gateway = true

  tags = {
    Project = "cloudnova-retail-store-e2e"
  }
}
```

> **`intra_subnets` is the module's own naming for isolated subnets** —
> worth knowing since it doesn't literally say "isolated" in the
> argument name, a real naming mismatch worth being aware of before
> searching the module's docs for something that isn't there under
> the more intuitive name.

### Step 3 — Add the S3 Gateway endpoint

**Append to vpc.tf:**

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.us-east-2.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = module.vpc.intra_route_table_ids

  tags = {
    Name = "cloudnova-s3-gateway-endpoint"
  }
}
```

### Step 4 — Apply

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

```
⚠️ Simulated expected output

module.vpc.aws_subnet.intra[0]: Creating...
module.vpc.aws_subnet.intra[1]: Creating...
module.vpc.aws_route_table.intra[0]: Creating...
aws_vpc_endpoint.s3: Creating...
aws_vpc_endpoint.s3: Creation complete after 3s

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

---

## Part B — Verify

### Step 5 — Confirm the isolated subnets have no internet route

```
Console → VPC → Route Tables → cloudnova-vpc-rtb-intra1
  → Routes tab
  → Confirm: local route (10.0.0.0/16) + the S3 endpoint's prefix-list
    route only ✅
  → Confirm: NO 0.0.0.0/0 route to any Internet Gateway or NAT Gateway ✅
```

### Step 6 — Confirm the S3 endpoint appears correctly

```bash
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=<VPC_ID>" --profile default --region us-east-2
```

```
Console → VPC → Endpoints → cloudnova-s3-gateway-endpoint
  → State: Available ✅
  → Route tables: the isolated tier's route table(s) ✅
```

> **Bolded takeaway:** the absence of a `0.0.0.0/0` route is the
> actual proof of isolation — not a security group rule, not a NACL,
> the route table itself simply has nowhere to send internet-bound
> traffic. This is a stronger guarantee than a security group, since
> it holds regardless of what's later attached to the subnet.

---

## Cleanup

**Torn down every session, alongside the rest of `phase-3-onward`** —
same lifecycle 22d already established for the VPC and EKS cluster.
This demo adds resources to that same Terraform state; it doesn't
introduce a new teardown category.

```bash
terraform destroy
```

```
⚠️ Simulated expected output

Destroy complete! Resources: X destroyed.
```

```
Console → VPC → confirm the isolated subnets and S3 endpoint: GONE ✅
```

---

## What You Learned

1. ✅ Isolated subnets are a genuinely different route-table shape —
   no internet path in either direction — not "private with extra
   restrictions."
2. ✅ The VPC module's own name for this tier is `intra_subnets`, not
   "isolated" — a real naming gap worth knowing before searching docs.
3. ✅ Gateway endpoints (S3, DynamoDB) are free, route-table-level
   mechanisms; most other services only support the paid Interface
   endpoint type.
4. ✅ This demo's resources follow the exact same every-session
   teardown lifecycle already established for the VPC/EKS cluster —
   not a new category to reason about.
5. ✅ The absence of an internet route in a route table is a stronger,
   structural isolation guarantee than a security group rule.

**Key Takeaway:** This demo is pure preparation — no compute, no IAM,
just the network tier RDS needs to exist before Demo 26 can deploy
into it. Recognizing "this demo builds nothing runnable yet, on
purpose" is itself worth internalizing, not every demo needs to end
with something visibly working.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| VPC module `intra_subnets` input | TA-004 Obj 5c — Modules | Third-tier extension to an already-applied module call |
| `aws_vpc_endpoint`, Gateway type | TA-004 Obj 4a — Resource configuration | Know the Gateway/Interface distinction and which services support which |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Are isolated subnets just private subnets with a stricter security group?" | No — isolated subnets have no internet route in their route table at all; private subnets still route outbound via NAT | Assuming the difference is enforced at the security-group layer rather than the routing layer |
| "Does every AWS service support a free Gateway VPC endpoint?" | No — only S3 and DynamoDB. Everything else requires the paid Interface endpoint type | Assuming Gateway endpoints are a general-purpose, free option for any service |

### Exam Task — Write a complete configuration

**Task:** Write an `aws_vpc_endpoint` for S3, of type `Gateway`,
associated with a given route table.

**Official documentation:**
- [`aws_vpc_endpoint` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint)

**What to practise:**
1. Open the page above — check `vpc_endpoint_type` and `route_table_ids`
2. Write the configuration from scratch without looking at this demo's `src/` files
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
resource "aws_vpc_endpoint" "exam_task" {
  vpc_id            = "vpc-0abc123"
  service_name      = "com.amazonaws.us-east-2.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = ["rtb-0abc123"]
}
```

**Arguments you must know without looking up:**
- `vpc_endpoint_type = "Gateway"` is required explicitly — it doesn't
  default to Gateway even though S3/DynamoDB support it
- `route_table_ids`, not `subnet_ids`, is how a Gateway endpoint
  associates with your network — Interface endpoints use `subnet_ids`
  instead, a real and commonly-confused distinction

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `terraform plan` shows the entire VPC being replaced, not just a new subnet tier added | A change to an existing subnet's CIDR or AZ list, not just an addition | Confirm `intra_subnets` was purely appended, and no existing `public_subnets`/`private_subnets` values were altered |
| S3 endpoint shows `Pending` indefinitely | Rare, but check the route table IDs actually match real, existing route tables | Confirm `module.vpc.intra_route_table_ids` resolves to real values via `terraform console` |
| An isolated-subnet resource can't reach S3 even with the endpoint present | The route table associated with that specific subnet doesn't include the endpoint's route | Confirm the subnet's actual route table association, not just that the endpoint exists somewhere in the VPC |

---

## Break-Fix Scenario

One deliberate error. Diagnose using `terraform plan` — do not look at
the answer first.

```bash
cd src/break-fix/
terraform init
terraform plan
```

**broken.tf (relevant excerpt):**

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.us-east-2.s3"
  vpc_endpoint_type = "Interface"   # Error

  route_table_ids = module.vpc.intra_route_table_ids
}
```

<details>
<summary>Reveal answer — attempt diagnosis first</summary>

**Error — `vpc_endpoint_type = "Interface"` combined with `route_table_ids`**
Interface endpoints don't use `route_table_ids` at all — they use
`subnet_ids` and create an actual network interface with an hourly
cost. Terraform will show a validation error, since `route_table_ids`
isn't a valid argument for an Interface-type endpoint. Fix: either
change the type back to `"Gateway"` (matching this demo's actual
intent, keeping `route_table_ids`), or switch to `subnet_ids` if an
Interface endpoint were genuinely intended.

</details>

**Cleanup:**

```bash
cd src/break-fix/
terraform destroy -auto-approve
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
```

---

## Interview Prep

**Q1. A teammate asks why RDS can't just go into the existing private subnets, since they already don't allow inbound internet traffic.**
Private subnets still route outbound traffic through a NAT Gateway — they can *initiate* connections to the internet, even though nothing on the internet can initiate connections to them. A database has no legitimate reason to make outbound internet connections at all, so private subnets grant it more access than it should have. Isolated subnets remove that outbound path entirely — no NAT route, no internet path in either direction — which is the actual guarantee you want for a data tier.

**Q2. Someone asks why this demo uses a Gateway endpoint instead of an Interface endpoint for S3.**
Because S3 (and DynamoDB) specifically support the older, free Gateway endpoint type — a route-table entry, not a separate network interface with its own hourly cost. Most other AWS services only support the newer Interface endpoint type, which does cost money per hour plus data processing. Since this demo only needs S3 reachability from the isolated tier, and Gateway is both free and fully sufficient for that need, there's no reason to reach for the more expensive option.

**Q3. A reviewer notices this demo builds nothing that's actually usable yet — no new compute, no new IAM, nothing visibly running. Is that a problem?**
No — that's the deliberate shape of this demo. It's pure preparation for Demo 26, which needs an isolated subnet tier to already exist before RDS can be deployed into it. Not every demo in a build sequence needs to end with something end-user-visible; sometimes the correct unit of work is "the prerequisite infrastructure for the next demo," and recognizing that as a legitimate, complete demo in its own right — rather than assuming something's missing — is itself a useful instinct.

---

## Key Takeaways

1. **Isolated subnets are defined by their route table, not their
   security group.** No route to the internet in either direction is
   a structural guarantee — stronger than any security-group rule.

2. **Gateway endpoints (S3, DynamoDB) are free; almost everything else
   requires the paid Interface endpoint type.** Know which category a
   service falls into before assuming free reachability is available.

3. **`route_table_ids` (Gateway) and `subnet_ids` (Interface) are not
   interchangeable arguments.** Using the wrong one for the endpoint
   type you've specified is a real, common configuration error.

4. **The VPC module's own naming (`intra_subnets`) doesn't match the
   more intuitive "isolated" terminology.** Worth knowing before
   searching the module's documentation for a name that isn't there.

5. **Not every demo needs to end with something visibly running.**
   Pure-preparation infrastructure, staged ahead of the demo that will
   actually use it, is a legitimate and complete unit of work.

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws ec2 describe-vpc-endpoints --filters ...` | Lists VPC endpoints matching a filter, confirming state and route table associations |
| `terraform console` | Interactive REPL — useful for confirming a module output (like `intra_route_table_ids`) resolves as expected before applying |
| `terraform init` / `validate` / `plan` / `apply` / `destroy` | Standard workflow, unchanged from prior demos |

---

## Next Demo

**Demo 26 — RDS:** deploys PostgreSQL into this demo's isolated
subnet tier, swaps Catalog (sidecar → RDS) and Orders (H2 → RDS) onto
it, and adds the IAM policy grant Demo 24 deliberately deferred.

---

## Appendix — Anki Cards

**25-vpc-extension-isolated-subnets-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::25-vpc-extension-isolated-subnets
#separator:Comma
#columns:Front,Back,Tags
"What makes a subnet 'isolated' as distinct from 'private'?","Route table shape - isolated subnets have NO route to the internet in either direction. Private subnets still route outbound traffic through a NAT Gateway, even though they block inbound internet traffic.","demo25,vpc,isolated-subnets,ta004-obj"
"What is the VPC module's own argument name for the isolated subnet tier?","intra_subnets - not 'isolated_subnets', a real naming mismatch worth knowing before searching the module's docs under the more intuitive name.","demo25,vpc,modules,gotcha"
"Which AWS services support the free Gateway VPC endpoint type?","Only S3 and DynamoDB. Almost every other AWS service only supports the newer Interface endpoint type, which has an hourly cost plus data processing charges.","demo25,vpc,endpoints,ta004-obj4a"
"What argument does a Gateway endpoint use to associate with your network, versus an Interface endpoint?","Gateway endpoints use route_table_ids (a routing-layer mechanism). Interface endpoints use subnet_ids instead, since they create an actual network interface. These are not interchangeable.","demo25,vpc,endpoints,gotcha"
"Why doesn't this demo make any compute or IAM changes?","It's pure networking preparation for Demo 26 - RDS needs the isolated subnet tier to already exist before it can be deployed into it. Not every demo needs to end with something visibly running.","demo25,scope,sequencing"
```

---

## Appendix — Quiz

**25-vpc-extension-isolated-subnets-quiz.md:**

````markdown
# Quiz — Demo 25: VPC Extension: Isolated Subnets + Endpoints

> Question types: True/False, Multiple Choice — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 26.

---

**Q1. (Multiple Choice)** What structurally distinguishes an isolated
subnet from a private subnet?

- A) Isolated subnets use a stricter default security group
- B) Isolated subnets have no route to the internet at all, in either direction — private subnets still route outbound via NAT
- C) Isolated subnets can't be assigned a CIDR block
- D) There is no structural difference — it's purely a naming convention

<details>
<summary>Answer</summary>

**B.** This is a route-table-level difference, not a security-group
or naming distinction — isolated subnets genuinely have no internet
path in either direction.

</details>

---

**Q2. (Multiple Choice)** Which AWS services support the free Gateway
VPC endpoint type?

- A) All AWS services
- B) Only S3 and DynamoDB
- C) Only compute-related services (EC2, EKS, ECS)
- D) None — all VPC endpoints have an hourly cost

<details>
<summary>Answer</summary>

**B.** S3 and DynamoDB are the two services supporting the free,
route-table-based Gateway endpoint type. Everything else requires the
paid Interface endpoint type.

</details>

---

**Q3. (True/False)** A Gateway endpoint and an Interface endpoint both
use the `subnet_ids` argument to associate with your network.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Gateway endpoints use `route_table_ids`; Interface
endpoints use `subnet_ids`. These arguments are not interchangeable
between the two endpoint types.

</details>

---

**Q4. (Multiple Choice)** What is the VPC module's own argument name
for the isolated subnet tier?

- A) `isolated_subnets`
- B) `intra_subnets`
- C) `db_subnets`
- D) `private_isolated_subnets`

<details>
<summary>Answer</summary>

**B.** `intra_subnets` — a real naming mismatch with the more
intuitive "isolated" terminology, worth knowing before searching the
module's documentation.

</details>

---

**Q5. (True/False)** This demo introduces new compute or IAM resources
to support the isolated subnet tier.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** This demo is pure networking — no compute, no IAM. It's
preparation for Demo 26's RDS deployment, not something that runs on
its own.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 5/5 | Import Anki cards, move to Demo 26 |
| 4/5 | Review the wrong answer, then proceed |
| 3/5 | Re-read the relevant sections, retry those questions |
| Below 3/5 | Re-read the full demo before proceeding |
````