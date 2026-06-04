# Demo 00 — IaC & HCL Foundations

## Overview

Before you write your first `terraform apply`, you need to answer two
questions clearly: **why does Infrastructure as Code exist?** and **what
language does Terraform use to describe infrastructure?** Skip this demo
and you will spend every subsequent demo fighting two learning curves
simultaneously — "what does this syntax mean?" and "what is this AWS
resource doing?". Separate them now and every future demo becomes
significantly easier.

**Real-world scenario — CloudNova:**
You have just joined *CloudNova*, a SaaS startup that has been running
on AWS for two years. Their infrastructure lives in the AWS Console and
in a senior engineer's memory — that engineer left last month. Nobody
can reproduce the staging environment. Production has a different
security group configuration than staging and nobody knows when that
diverged or why. The security team asked for an audit trail of every
infrastructure change made in the last 12 months. There is none.

Your first week task: convince the team to adopt Infrastructure as Code.
This demo is that conversation — the theory, the tool comparison, and
your first hands-on proof that Terraform works.

**What this demo covers:**
- What IaC is, the exact problem it solves, and the four failure modes
  of manual infrastructure management
- Declarative vs imperative — why the distinction matters
- Terraform vs CloudFormation vs CDK vs Ansible — honest comparison
- Terraform's architecture: CLI, providers, state, registry
- Terraform merits and real, honest limitations
- OpenTofu — the community fork and when it matters
- HCL: what it is, every block type, all value types, references,
  interpolation, file conventions
- `terraform console` as a live HCL sandbox — no AWS required
- File naming conventions and why they exist
- Full Terraform workflow on a zero-cost local + random provider lab

**No AWS account or credentials required for this demo.**

---

## Recall Check

> First demo in the series — no prior demo to recall from.
> Return here when starting Demo 01 to answer these from memory:
>
> 1. Name the four failure modes of manual infrastructure management.
> 2. Should `.terraform.lock.hcl` be committed to Git? Why?
> 3. What does `terraform plan -out=tfplan` + `terraform apply tfplan`
>    guarantee that `terraform apply` alone does not?

---

## Prerequisites

### Knowledge
- Basic Linux command line (cd, ls, cat, mkdir)
- A text editor (VS Code recommended — install the
  [HashiCorp Terraform extension](https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform)
  for syntax highlighting and auto-complete)

### Required Tools

| Tool | Minimum version | Install | Verify |
|---|---|---|---|
| Terraform CLI | `>= 1.15.0` | See below | `terraform version` |
| Git | Any recent | Pre-installed on most systems | `git --version` |

**Install Terraform CLI:**

```bash
# macOS (Homebrew)
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Linux — Ubuntu / Debian
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Windows — download installer from https://developer.hashicorp.com/terraform/install

# Verify — expected output: Terraform v1.15.x
terraform version
```

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain what IaC is and the four specific failure modes of
   manual infrastructure management
2. ✅ Compare Terraform, CloudFormation, CDK, and Ansible — choose the
   right tool for the right job
3. ✅ Describe Terraform's three-component architecture and what happens
   internally during each CLI command
4. ✅ Identify every top-level HCL block type and explain its purpose
5. ✅ Read any `.tf` file and explain every argument, block, and reference
6. ✅ Write basic HCL: blocks, variables, locals, outputs, interpolation
7. ✅ Use `terraform console` to test and explore HCL expressions live
8. ✅ Run the full Terraform workflow: init → validate → fmt → plan →
   apply → destroy — and explain what each does to the filesystem
9. ✅ Explain what `.terraform/`, `.terraform.lock.hcl`, and
   `terraform.tfstate` are, why each exists, and what to do with each

---

## Part 1 — What is Infrastructure as Code?

### The Four Failure Modes of Manual Infrastructure

Every infrastructure team running on the AWS Console eventually hits
the same four walls. CloudNova hit all four:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  THE FOUR FAILURE MODES OF MANUAL INFRASTRUCTURE                        │
├──────────────────┬──────────────────────────────────────────────────────┤
│                  │                                                       │
│  1. DRIFT        │ What actually exists diverges from what you          │
│                  │ intended — silently, across environments.             │
│                  │                                                       │
│                  │ Real example: An engineer SSHes into a prod server   │
│                  │ and tweaks a config to fix an incident at 2am.       │
│                  │ Nobody updates the runbook. Staging still has the    │
│                  │ old config. Six months later nobody knows which      │
│                  │ environment is "correct" or what changed.            │
│                  │                                                       │
│                  │ With only Console clicks: there is no record of      │
│                  │ what was changed, by whom, or when. The environments  │
│                  │ diverge and you only discover it when something       │
│                  │ breaks.                                               │
│                  │                                                       │
├──────────────────┼──────────────────────────────────────────────────────┤
│                  │                                                       │
│  2. NO AUDIT     │ Who changed the security group at 2pm last Tuesday?  │
│     TRAIL        │ The AWS Console has no answer. Your incident          │
│                  │ postmortem fails. Compliance audit fails.             │
│                  │ With IaC: every change is a Git commit with author,  │
│                  │ timestamp, PR review, and CI run attached to it.      │
│                  │                                                       │
├──────────────────┼──────────────────────────────────────────────────────┤
│                  │                                                       │
│  3. NOT          │ Spin up a new environment = click through 40 Console  │
│     REPEATABLE   │ screens again. Miss one setting. Debug for 2 hours.  │
│                  │ With IaC: terraform apply in a new environment takes  │
│                  │ 3 minutes and produces an identical result every      │
│                  │ time.                                                 │
│                  │                                                       │
├──────────────────┼──────────────────────────────────────────────────────┤
│                  │                                                       │
│  4. BUS FACTOR   │ The senior engineer who built the environment leaves. │
│                  │ Their Console knowledge leaves with them.             │
│                  │ CloudNova is here right now.                          │
│                  │ With IaC: the code is the documentation. New team    │
│                  │ members read the repo, not someone's memory.          │
│                  │                                                       │
└──────────────────┴──────────────────────────────────────────────────────┘
```

IaC solves all four by treating infrastructure like application code:
version-controlled, peer-reviewed, tested, and repeatable.

### Declarative vs Imperative — Why This Matters

This is the most important conceptual split in IaC tooling. The approach
determines how you think about and write infrastructure:

```
┌──────────────────────────────────────────────────────────────────────────┐
│  IMPERATIVE — "Tell me every step"                                       │
│  You describe HOW to get to the desired state.                           │
│                                                                          │
│  if aws_vpc_exists("10.0.0.0/16"):                                       │
│      print("VPC already exists, skipping")                              │
│  else:                                                                   │
│      create_vpc("10.0.0.0/16")                                           │
│  if subnet_exists(...):                                                  │
│      ...                                                                 │
│                                                                          │
│  Problem: YOU must handle every state check. Run it twice               │
│  without the checks → error on second run (VPC already exists).         │
│  Examples: Bash + AWS CLI, Python boto3, Ansible in procedural mode     │
├──────────────────────────────────────────────────────────────────────────┤
│  DECLARATIVE — "Tell me what you want"                                   │
│  You describe WHAT the end state should look like.                       │
│                                                                          │
│  resource "aws_vpc" "main" {                                             │
│    cidr_block = "10.0.0.0/16"                                           │
│  }                                                                       │
│                                                                          │
│  Terraform figures out the steps.                                        │
│  Run it twice → second run does nothing (already matches state).        │
│  Examples: Terraform, CloudFormation, Kubernetes manifests              │
└──────────────────────────────────────────────────────────────────────────┘
```

**Why declarative wins for infrastructure:**
You describe the *desired end state* — "I want a VPC with this CIDR". 
Terraform compares that to *current state* and calculates the minimum set 
of API calls needed. Run it twice and nothing changes. This property is 
called **idempotency** and it is the foundation of reliable automation.


### Idempotency — The Foundation of Reliable Automation

**Idempotent** means: applying the same operation multiple times produces
the same result as applying it once.

Simple analogy: Paint a wall white. Paint it white again. The wall is
still white — the second action had no visible effect. That is idempotency.

In Terraform: run `terraform apply` when nothing in your config has
changed. The plan shows `0 to add, 0 to change, 0 to destroy`. No API
calls are made. The infrastructure is unchanged.

A bash script that creates a security group is **not** idempotent — run it
twice and the second run throws an error because the group already exists.
You have to write the existence check yourself. Terraform handles this
automatically by comparing desired state (`.tf` files) against current
state (`terraform.tfstate`) before taking any action.

```
Desired state (.tf files)  ──┐
                              ├──► terraform plan ──► diff ──► terraform apply
Current state (.tfstate)   ──┘
                                   "0 changes" if they match
```

---

## Part 2 — Terraform vs The Alternatives

### Tool Comparison

| Dimension | Terraform | AWS CloudFormation | AWS CDK | Ansible |
|---|---|---|---|---|
| **Approach** | Declarative HCL | Declarative YAML/JSON | Imperative code (Python/TS) | Procedural YAML |
| **Cloud scope** | Multi-cloud + 3,000+ providers | AWS only | AWS only | Multi-cloud via modules |
| **State** | Explicit state file you manage | Managed by AWS (stacks) | Via CloudFormation stacks | Stateless |
| **Primary use** | Infrastructure provisioning | AWS-native infra | Infra for dev teams | Config management |
| **Learning curve** | Medium — HCL is new but small | Low for AWS teams | High — real programming | Medium |
| **Drift detection** | `terraform plan -refresh-only` | CloudFormation drift detection | Via CFN | External tooling |
| **License** | BUSL 1.1 (source-available) | Proprietary AWS service | Apache 2.0 | GPL v3 |
| **Community** | Largest IaC community | AWS-backed, AWS-only | AWS-backed, growing | Huge, Red Hat |

### When to Use Each Tool

```
✅ Use Terraform when:
   • Multi-cloud or hybrid-cloud is a requirement or future possibility
   • You manage AWS + Kubernetes + monitoring (e.g. Datadog) in one workflow
   • Infrastructure code lives alongside application code in Git
   • Team wants the broadest provider ecosystem

✅ Use CloudFormation when:
   • AWS-only forever — deepest AWS service support on day zero
   • No state management overhead matters to the team (AWS manages stacks)
   • You use AWS Organizations and need StackSets for multi-account deployments

✅ Use CDK when:
   • Developers (not ops) own infrastructure code
   • Complex conditional logic that HCL would make verbose
   • Team is fluent in Python or TypeScript

✅ Use Ansible when:
   • Configuration management — what runs INSIDE the server, not the server
   • OS-level: packages, users, files, services
   • Often paired with Terraform: Terraform provisions, Ansible configures
```

### Terraform's Honest Limitations

```
⚠️  STATE FILE BLAST RADIUS
    The state file is Terraform's memory. Corrupt it and Terraform loses
    track of everything it manages. In teams it must be stored remotely
    (S3) with locking. Covered in Demo 01.

⚠️  HCL IS NOT A PROGRAMMING LANGUAGE
    Complex conditional logic, dynamic iteration, and string manipulation
    are verbose compared to Python or TypeScript. Workarounds exist but
    they can make code hard to read.

⚠️  PROVIDER QUALITY VARIES
    AWS, Azure, GCP providers are production-grade. Niche or newer
    providers can lag behind new service features by weeks or months.

⚠️  BUSL LICENSE (since August 2023)
    HashiCorp changed Terraform's license from MPL to BUSL 1.1.
    Impact for most users: none — BUSL only restricts commercial
    competitors to HashiCorp from using Terraform in their products.
    If you are a DevOps engineer using Terraform to manage your own
    infrastructure, BUSL does not affect you.

⚠️  TESTING IS MATURING
    Built-in testing (terraform test) arrived in v1.6. Test mocks in
    v1.7. The framework is good but newer than application testing
    ecosystems. Covered in depth in Demo 27. For now: know it exists
    and know it is how production teams validate modules before
    applying to real infrastructure.
```

### OpenTofu — The Community Fork

When HashiCorp changed Terraform's license to BUSL in 2023, the open-source
community forked Terraform under the Linux Foundation as **OpenTofu**:

| | Terraform | OpenTofu |
|---|---|---|
| **Maintainer** | HashiCorp (IBM) | Linux Foundation |
| **License** | BUSL 1.1 | Mozilla Public License 2.0 |
| **Latest version** | 1.15.5 (May 2026) | 1.11.6 (April 2026) |
| **HCL compatibility** | Reference implementation | Compatible — same HCL |
| **Certification** | HashiCorp TA-004 | No separate cert |
| **Use when** | Default choice, cert prep | License is a hard constraint |

**For this series:** All demos use Terraform. Every HCL file in this series
runs identically on OpenTofu — the language is the same. The cert is
Terraform-specific. If your organisation has adopted OpenTofu, the
workflow and concepts are identical.

---

## Part 3 — Terraform Architecture

### The Three Components

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      TERRAFORM ARCHITECTURE                              │
│                                                                          │
│   You write .tf files (HCL)                                              │
│         │                                                                │
│         ▼                                                                │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │  TERRAFORM CORE (the CLI binary)                                │   │
│   │                                                                  │   │
│   │  • Parses all .tf files in the working directory                │   │
│   │  • Builds a dependency graph (which resource needs which)       │   │
│   │  • Reads current state from terraform.tfstate                   │   │
│   │  • Calculates the diff: what to create, update, or destroy      │   │
│   │  • Communicates with provider plugins via gRPC                  │   │
│   └───────────────────────┬─────────────────────────────────────────┘   │
│                           │ spawns as subprocess, talks via gRPC         │
│                           ▼                                              │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │  PROVIDER PLUGIN (e.g. hashicorp/aws)                           │   │
│   │                                                                  │   │
│   │  • Downloaded by terraform init from registry.terraform.io      │   │
│   │  • Lives in .terraform/providers/                               │   │
│   │  • Translates Terraform resource definitions into API calls     │   │
│   │  • Handles authentication (AWS credentials, tokens, etc.)       │   │
│   │  • One plugin per provider — runs as a separate process         │   │
│   └───────────────────────┬─────────────────────────────────────────┘   │
│                           │ HTTPS API calls                              │
│                           ▼                                              │
│   ┌──────────────────────────────┐  ┌──────────────────────────────┐    │
│   │  CLOUD / SERVICE API         │  │  STATE FILE                  │    │
│   │  (AWS, Azure, GCP,           │  │  terraform.tfstate           │    │
│   │   Kubernetes, Datadog...)    │  │                              │    │
│   │                              │  │  JSON snapshot of every      │    │
│   │  Provider makes real API     │  │  resource Terraform manages  │    │
│   │  calls: CreateVpc,           │  │                              │    │
│   │  RunInstances, etc.          │  │  Updated after every apply   │    │
│   │                              │  │  Local by default            │    │
│   └──────────────────────────────┘  │  Remote in teams (Demo 01)   │    │
│                                     └──────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────┘
```

**The three components explained:**

| Component | What it is | Lives where |
|---|---|---|
| **Terraform CLI** | The `terraform` binary. Parses HCL, builds graph, runs workflow. | Your machine / CI runner |
| **Provider plugin** | Translates Terraform resources into API calls. One per service type. | Downloaded to `.terraform/` on `init` |
| **State file** | JSON snapshot of everything Terraform manages. The source of truth for drift detection. | Local `terraform.tfstate` or remote backend |


### What Happens Internally During Each Command

```
terraform init
  1. Reads required_providers in versions.tf
  2. Contacts registry.terraform.io to resolve versions
  3. Downloads provider binaries → .terraform/providers/
  4. Records exact versions + SHA256 hashes → .terraform.lock.hcl
  5. Initialises backend (local by default — Demo 01 covers remote S3)
  Result: working directory is ready to use

terraform plan
  1. Reads all .tf files → desired state
  2. Reads terraform.tfstate → current known state
  3. Calls provider's Read() function on existing resources → actual state
  4. Builds dependency graph (DAG) — determines execution order
  5. Calculates diff: desired vs actual
  6. Prints execution plan — no changes made
  Result: you see exactly what will happen before it happens

terraform apply
  1. Re-runs plan (or uses a saved plan file)
  2. Asks for confirmation (unless -auto-approve)
  3. Walks the dependency graph in order
  4. For each resource: calls provider Create/Update/Delete API
  5. On each success: writes resource to terraform.tfstate
  Result: infrastructure matches desired state, state file updated

terraform destroy
  1. Builds a reverse dependency graph (delete dependents first)
  2. Creates a destroy plan (every resource gets -)
  3. Asks for confirmation
  4. Calls provider Delete() API for each resource in order
  5. Updates terraform.tfstate (resources removed)
  Result: all managed infrastructure deleted
```

### The Dependency Graph — Why Order Matters

Terraform does not execute resources in the order you write them. It builds
a **Directed Acyclic Graph (DAG)** from the references in your config:

```
If resource B references resource A's output:
  resource "aws_subnet" "web" {
    vpc_id = aws_vpc.main.id    ← B depends on A
  }

Terraform detects this reference → creates A first, then B.
No manual ordering required. No depends_on needed for explicit references.
```

---

## Part 4 — HCL: The Terraform Language

### What is HCL and Why Learn It Here

HCL (HashiCorp Configuration Language) is the language you write all
Terraform configuration in. It is important to understand what HCL is
**not** before learning what it is:

- It is **not** a general-purpose programming language (no class definitions,
  no traditional loops, no function definitions)
- It is **not** YAML or JSON (though Terraform can read JSON .tf.json files)
- It is **not** executed top-to-bottom like a script

HCL is a **structured configuration language** — designed to be:
- Human-readable and writable (vs JSON/XML which are machine-first)
- Machine-parseable and type-safe
- Declarative — you describe structure, not steps

Every `.tf` file you write is HCL. Every argument, block, and expression
you use in Terraform is HCL syntax. Understanding HCL IS understanding
how to write Terraform configuration.

### The Three Primitives

The official Terraform documentation defines the Terraform language
syntax as built around two key constructs: **arguments** and **blocks**.
Expressions are the third primitive — they produce values.

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PRIMITIVE 1 — ARGUMENT                                                 │
│  Assigns a value to a name. Always lives inside a block.                │
│                                                                         │
│  identifier = expression                                                │
│                                                                         │
│  instance_type = "t3.micro"       # string literal                     │
│  count        = 3                 # number literal                     │
│  encrypted    = true              # bool literal                       │
│  name         = var.project_name  # variable reference                 │
│  tag_value    = "${var.env}-web"  # string interpolation               │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  PRIMITIVE 2 — BLOCK                                                    │
│  A container for arguments and nested blocks.                           │
│  Has a type (keyword), zero or more labels (strings), and a body {}.  │
│                                                                         │
│  <block_type> "<label_1>" "<label_2>" {                                 │
│    <argument> = <value>                                                 │
│    <nested_block> {                                                     │
│      <argument> = <value>                                               │
│    }                                                                    │
│  }                                                                      │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  PRIMITIVE 3 — EXPRESSION                                               │
│  Produces a value. Can be a literal, reference, function call,          │
│  operator, or combination.                                              │
│                                                                         │
│  "us-east-2"                         # string literal                  │
│  42                                  # number literal                  │
│  true                                # bool literal                    │
│  var.region                          # variable reference              │
│  aws_instance.web.id                 # resource attribute reference    │
│  "${var.project}-${var.env}"         # string interpolation            │
│  upper(var.name)                     # function call                   │
│  var.env == "prod" ? 3 : 1           # conditional (ternary)           │
└─────────────────────────────────────────────────────────────────────────┘
```

### All Top-Level Block Types — Annotated

These are the only block types that can appear at the top level of a `.tf`
file (outside any other block). There are exactly 8:

```hcl
# ── 1. terraform ─────────────────────────────────────────────────────────
# Controls Terraform itself. Declares CLI version requirements and
# which providers this configuration depends on.
# One terraform {} block per configuration. Lives in versions.tf by convention.
terraform {
  required_version = "~> 1.15.0"    # Terraform CLI must be 1.15.x

  required_providers {              # nested block — not a resource block
    aws = {                         # "aws" = the LOCAL NAME you assign this provider
      source  = "hashicorp/aws"     # registry path: registry.terraform.io/hashicorp/aws
      version = "~> 6.47.0"         # provider version constraint
    }
    # ANATOMY: aws = { ... } is an OBJECT ARGUMENT inside required_providers
    # The label "aws" becomes how you reference this provider elsewhere:
    #   provider "aws" { ... }       ← matches by the label "aws"
    #   resource "aws_vpc" "main"    ← "aws_" prefix maps to the "aws" provider
  }
}
```

```hcl
# ── 2. provider ───────────────────────────────────────────────────────────
# Configures a specific provider: authentication, region, default tags.
# The label (e.g. "aws") must match a name declared in required_providers.
provider "aws" {
  region = "us-east-2"   # all resources in this provider use this region
}
```

```hcl
# ── 3. resource ───────────────────────────────────────────────────────────
# Declares a real infrastructure object to create/manage.
# ALWAYS has exactly TWO labels: resource TYPE and local NAME.
#
#  resource "<type>" "<local_name>" { ... }
#      │                 │
#      │                 └─ your chosen name — used in references
#      └─ must match a resource type the provider supports
#
resource "aws_s3_bucket" "app_data" {      # type="aws_s3_bucket", name="app_data"
  bucket = "cloudnova-app-data-prod"
  tags   = { Name = "app-data" }
}
# Reference this resource elsewhere: aws_s3_bucket.app_data.id
#                                     <type>.<local_name>.<attribute>
```

```hcl
# ── 4. variable ───────────────────────────────────────────────────────────
# Declares an INPUT PARAMETER your configuration accepts from outside.
# Think of it like a function argument — you declare the parameter here,
# the caller (tfvars file, CLI flag, or environment variable) passes the value.
# This makes the same config reusable across dev/staging/prod without
# changing any resource blocks.
variable "environment" {
  type        = string                       # enforces type at plan time
  description = "Target environment"         # shown in terraform plan output
  default     = "dev"                        # value used when none is supplied

  validation {                               # optional — rejects bad values
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be dev, staging, or prod."
  }
}
# Reference: var.environment
```

```hcl
# ── 5. locals ─────────────────────────────────────────────────────────────
# Named expressions computed once and reused throughout the config.
# Key distinctions:
#   • locals accept NO external input (unlike variables)
#   • Block is PLURAL (locals {}), reference is SINGULAR (local.x)
#   • Can reference other locals and resource attributes
locals {
  project   = var.project_name
  full_name = "${local.project}-${var.environment}"  # references another local

  common_tags = {         # map local — applied to every resource via tags = local.common_tags
    Project   = local.project
    ManagedBy = "Terraform"
  }
}
# Reference: local.full_name
```

```hcl
# ── 6. output ─────────────────────────────────────────────────────────────
# Exposes values after apply: printed in the terminal, queryable via
# terraform output, and readable by other Terraform configurations.
output "bucket_arn" {
  description = "ARN of the application data bucket"
  value       = aws_s3_bucket.app_data.arn    # resource attribute reference
  sensitive   = false                          # set true to hide from terminal
}
```

```hcl
# ── 7. data ───────────────────────────────────────────────────────────────
# Reads EXISTING infrastructure — does NOT create anything.
# ALWAYS has exactly TWO labels: data source TYPE and local NAME.
#
# Use when: you need info about something that exists outside this config
# (e.g. an AMI ID, an existing VPC, the current AWS region)
#
data "aws_region" "current" {}              # reads current region, no arguments needed

output "region" {
  value = data.aws_region.current.region    # v6: use .region not .name (deprecated)
}
# Reference: data.<type>.<local_name>.<attribute>
```

```hcl
# ── 8. module ─────────────────────────────────────────────────────────────
# Calls a reusable group of resources packaged as a unit.
# Covered in depth in Demo 09–12 (Phase 2 — Modules).
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"  # registry module
  version = "~> 5.0"
  name    = local.full_name
  cidr    = "10.0.0.0/16"
}
```

### HCL Value Types — Complete Reference

```hcl
# ── STRING ────────────────────────────────────────────────────────────────
# Always double-quoted. Single quotes are NOT valid HCL.
variable "region" {
  type    = string
  default = "us-east-2"
}

# ── NUMBER ────────────────────────────────────────────────────────────────
# Integer or float. No quotes.
variable "instance_count" {
  type    = number
  default = 2
}

# ── BOOL ──────────────────────────────────────────────────────────────────
variable "enable_versioning" {
  type    = bool
  default = true
}

# ── LIST ──────────────────────────────────────────────────────────────────
# Ordered collection. Same type for all elements. Index access from 0.
variable "availability_zones" {
  type    = list(string)
  default = ["us-east-2a", "us-east-2b", "us-east-2c"]
}
# Access: var.availability_zones[0]  →  "us-east-2a"
# Length: length(var.availability_zones)  →  3

# ── SET ───────────────────────────────────────────────────────────────────
# Unordered collection. No duplicates. No index access.
# Use when order doesn't matter and uniqueness is required
# (e.g. list of security group IDs, list of AZ names).
variable "sg_ids" {
  type    = set(string)
  default = ["sg-abc123", "sg-def456"]
}
# Cannot do: var.sg_ids[0]  ← sets have no index
# Can do:    length(var.sg_ids), contains(var.sg_ids, "sg-abc123")

# ── MAP ───────────────────────────────────────────────────────────────────
# Key-value pairs where ALL VALUES are the same type.
# map(string) = every value must be a string
# map(number) = every value must be a number
# The type in parentheses is the VALUE type constraint.
variable "tags" {
  type = map(string)    # ← map(string) means values must be strings
  default = {
    Environment = "dev"    # key = "Environment", value = "dev" (a string ✓)
    Project     = "nova"   # key = "Project",     value = "nova" (a string ✓)
  }
}
# Access: var.tags["Environment"]  →  "dev"
# Keys:   keys(var.tags)           →  ["Environment", "Project"]

# ── OBJECT ────────────────────────────────────────────────────────────────
# Key-value pairs with a FIXED SCHEMA — each key has its own type.
# Use for structured config with known fields (vs map for arbitrary keys).
variable "instance_config" {
  type = object({
    instance_type = string    # this key must be a string
    volume_size   = number    # this key must be a number
    encrypted     = bool      # this key must be a bool
  })
  default = {
    instance_type = "t3.micro"
    volume_size   = 20
    encrypted     = true
  }
}
# Access: var.instance_config.instance_type  →  "t3.micro"

# ── LIST OF OBJECTS ───────────────────────────────────────────────────────
# Widely used in production for subnet configs, ECS container definitions,
# database replicas — any list of structured items.
variable "subnets" {
  type = list(object({
    name = string
    cidr = string
    az   = string
  }))
  default = [
    { name = "web-a", cidr = "10.0.1.0/24", az = "us-east-2a" },
    { name = "web-b", cidr = "10.0.2.0/24", az = "us-east-2b" },
  ]
}
# Access: var.subnets[0].cidr  →  "10.0.1.0/24"
# Used with for_each in Demo 06 to create one subnet per object.

# ── ANY ───────────────────────────────────────────────────────────────────
# Accepts any type. Disables type validation. Use sparingly.
variable "flexible" {
  type    = any
  default = null
}
```

### String Interpolation and References

```hcl
# String interpolation — embed any expression inside a double-quoted string
locals {
  bucket_name = "${var.project}-${var.environment}-data"
  # → "cloudnova-dev-data"

  # Nested interpolation
  log_prefix  = "logs/${var.environment}/${local.project}/"
  # → "logs/dev/cloudnova/"
}

# Resource attribute reference — access a computed value from another resource
# Format: <resource_type>.<local_name>.<attribute>
output "bucket_arn" {
  value = aws_s3_bucket.app_data.arn       # .arn computed by AWS after create
}

# Data source reference
# Format: data.<source_type>.<local_name>.<attribute>
output "region" {
  value = data.aws_region.current.region   # AWS provider v6: .region not .name
}

# Variable reference: var.<name>
# Local reference:    local.<name>
# Module output:      module.<module_name>.<output_name>
```

### Comments

```hcl
# Single-line comment — most common, use everywhere

// Single-line comment — also valid HCL, less common

/*
  Multi-line comment.
  Use for block-level documentation or temporarily disabling code.
*/

resource "aws_s3_bucket" "app_data" {
  bucket = "cloudnova-prod"  # inline — explain WHY, not WHAT
}
```

### Terraform Terminology — Key Terms

```
Working Directory   The folder containing your .tf files. This is the
                    "root module" — the unit Terraform operates on.
                    Run terraform commands from here.

Root Module         The working directory you run terraform init/plan/apply
                    in. Every configuration has exactly one root module.

Child Module        A module called by the root module via a module {} block.
                    Covered in Demo 09.

Workspace           A named state within one configuration. Allows the same
                    config to manage multiple environments (dev/staging/prod)
                    with separate state files. Covered in Demo 13.

Provider            A plugin that interfaces with a specific service's API.
                    hashicorp/aws, hashicorp/kubernetes, datadog/datadog.

State               The JSON record of everything Terraform manages. Lives in
                    terraform.tfstate locally or a remote backend in teams.
```

## HCL Naming Conventions

All HCL identifiers (resource local names, variable names, local names,
output names, module names) follow the same rules:

| Identifier type        | Convention      | Example                  | Never use          |
|------------------------|-----------------|--------------------------|-------------------|
| Resource local name    | `snake_case`    | `web_server`, `app_sg`   | camelCase, kebab  |
| Variable name          | `snake_case`    | `instance_type`, `vpc_cidr` | camelCase      |
| Local name             | `snake_case`    | `common_tags`, `full_name` | camelCase       |
| Output name            | `snake_case`    | `vpc_id`, `bucket_arn`   | camelCase         |
| Module name            | `snake_case`    | `vpc_module`, `ecs_cluster` | camelCase      |
| Data source local name | `snake_case`    | `current_region`, `ubuntu_ami` | camelCase  |
| Map / object key       | `PascalCase`    | `Environment`, `Project` | snake_case (for AWS tag keys) |
| AWS resource name (tag)| `kebab-case`    | `prod-web-server`        | underscores       |
| File names             | `kebab-case`    | `main.tf`, `versions.tf` | underscores       |

**The one rule that matters most:** HCL identifiers = `snake_case`.
AWS resource names (the `Name` tag, bucket name, etc.) = `kebab-case`.
These are different things — don't mix them.

```hcl
# ✅ Correct
resource "aws_s3_bucket" "app_data" {        # local name: snake_case
  bucket = "cloudnova-app-data-prod"         # AWS resource name: kebab-case
  tags = {
    Name        = "app-data"                 # tag value: kebab-case
    Environment = "prod"                     # tag key: PascalCase
  }
}

# ❌ Wrong
resource "aws_s3_bucket" "appData" {         # camelCase local name
  bucket = "cloudnova_app_data_prod"         # underscores in bucket name
}
```

**"Local name" or "local variable"?**
The correct Terraform term is **local name** (or just **name**) for the
second label in a resource/data block: `resource "aws_s3_bucket" "app_data"` —
`app_data` is the local name. It is NOT called a local variable — that term
is reserved for `locals {}` block values referenced as `local.x`.

## Case Sensitivity

Everything in HCL is case-sensitive:

| Item | Case sensitive? | Example |
|---|---|---|
| Block type keywords | Yes | `resource` not `Resource` |
| Argument names | Yes | `instance_type` not `Instance_Type` |
| Boolean values | Yes | `true`/`false` — never `True`/`False` |
| Variable names | Yes | `var.environment` ≠ `var.Environment` |
| Resource local names | Yes | `aws_s3_bucket.app_data` ≠ `aws_s3_bucket.App_Data` |
| String values | Yes — AWS enforces | `"us-east-2"` ≠ `"US-East-2"` |
| Provider names | Yes | `hashicorp/aws` not `Hashicorp/AWS` |

### File Naming Conventions

Terraform loads **all** `.tf` files in the working directory and merges
them into one configuration. Order of files does not matter to Terraform.
The split below is **convention** followed by every corporate Terraform team:

```
versions.tf      terraform {} block: required_version + required_providers
                 Why: version constraints are infrastructure-level decisions,
                 not environment-specific. Isolate for easy auditing.

provider.tf      provider {} blocks: region, auth, default_tags
                 Why: provider config changes per deployment target.
                 Keep separate from resource definitions.

variables.tf     All variable {} blocks
                 Why: single place to see every input the config accepts.
                 New team members read this first.

locals.tf        All locals {} blocks
                 Why: computed/derived values separate from raw inputs.

main.tf          All resource {} blocks (the infrastructure)
                 Why: convention — where readers expect to find resources.

outputs.tf       All output {} blocks
                 Why: what this config exposes. Single place for callers
                 and operators to find available values.

terraform.tfvars Actual variable values for the default environment
                 Why: auto-loaded by Terraform without any flags.
                 DO NOT commit files with secrets.

*.auto.tfvars    Also auto-loaded, in lexical (alphabetical) order.
                 Avoid using multiple .auto.tfvars files — load order
                 causes subtle precedence bugs.
```

**Important rules about file loading:**

1. All `.tf` files in the same directory share a **single namespace** —
   a resource defined in `network.tf` is accessible from `main.tf` without
   any import statement.
2. `terraform.tfvars` is the only `.tfvars` file auto-loaded. Any other
   name (e.g. `prod.tfvars`) requires `-var-file=prod.tfvars` explicitly.
3. `*.auto.tfvars` files are auto-loaded in lexical order. Having
   `01-base.auto.tfvars` and `02-override.auto.tfvars` is asking for subtle
   bugs — avoid this pattern.
4. Subdirectories are **not** loaded — each directory is an independent
   module with its own namespace.

### Heredoc — Concrete Examples: `<<` vs `<<-`

Heredoc is **not** HCL-specific. It originated in Unix shells and was
adopted by HCL, Python, Ruby and others because it solves the same
problem everywhere: writing multi-line strings cleanly without escaping
every newline.

The delimiter word (`EOF`, `EOT`, `END`, `SCRIPT`) can be anything you
choose. `EOT` (end of text) and `EOF` (end of file) are both conventional
and both valid in HCL. This series uses `EOT` to visually distinguish
HCL files from bash scripts — but there is no technical reason to prefer
one over the other.

---

#### In bash — `<<` vs `<<-`

```bash
# <<EOF — standard form
# ALL leading whitespace is preserved exactly as written
# The closing EOF must be at column 0 (no indentation allowed)

if true; then
    MESSAGE=$(cat <<EOF
    Hello CloudNova
    Environment: prod
EOF
)
fi
# Result stored in MESSAGE:
# "    Hello CloudNova\n    Environment: prod\n"
#  ^^^^                ^^^^
#  4 spaces preserved  4 spaces preserved
```

```bash
# <<-EOF — dash form
# Strips leading TABS only (NOT spaces)
# The closing EOF can be indented with tabs

if true; then
	MESSAGE=$(cat <<-EOF
		Hello CloudNova
		Environment: prod
	EOF
	)
fi
# Result stored in MESSAGE (assuming lines were indented with tabs):
# "Hello CloudNova\nEnvironment: prod\n"
# tabs stripped — content starts at column 0

# ⚠️  GOTCHA: if your editor uses spaces (not tabs) for indentation,
# <<-EOF does NOT strip anything. The spaces are preserved.
# Most modern editors default to spaces — making <<-EOF unreliable in bash.
```

---

#### In HCL — `<<EOT` vs `<<-EOT`

HCL solves the editor gotcha. `<<-EOT` in HCL strips **spaces** (not
just tabs), making it reliable in all editors.

```hcl
# <<EOT — standard HCL heredoc
# ALL leading whitespace preserved exactly
# Closing EOT must be at column 0

locals {
  message = <<EOT
    Hello CloudNova
    Environment: prod
EOT
}
# Value of local.message:
# "    Hello CloudNova\n    Environment: prod\n"
#  ^^^^                 ^^^^
#  4 spaces preserved   4 spaces preserved
# (awkward — forces closing EOT to left edge, breaks indentation)
```

```hcl
# <<-EOT — indented HCL heredoc
# Terraform finds the LEAST indented line and strips that many spaces
# from ALL lines. Closing EOT can be indented freely.

locals {
  message = <<-EOT
    Hello CloudNova
    Environment: prod
  EOT
}
# Least-indented line has 2 spaces (the closing EOT line)
# → Terraform strips 2 spaces from every line
# Value of local.message:
# "  Hello CloudNova\n  Environment: prod\n"
#   ^^                  ^^
#   2 spaces remain     2 spaces remain
# (content lines had 4 spaces, closing EOT had 2 → 4-2 = 2 remain)
```

```hcl
# <<-EOT — when all content lines have equal indentation
# This is the most common real-world pattern

locals {
  message = <<-EOT
    Hello CloudNova
    Environment: prod
    EOT               ← closing EOT also has 4 spaces
}
# Least-indented line = closing EOT = 4 spaces
# → Terraform strips 4 spaces from every line
# Value of local.message:
# "Hello CloudNova\nEnvironment: prod\n"
# content starts at column 0 — clean output
```

---

#### Side-by-side summary

```
                    bash <<EOF    bash <<-EOF     HCL <<EOT    HCL <<-EOT
                    ──────────    ───────────     ─────────    ──────────
Strips spaces       No            No              No           Yes ✅
Strips tabs         No            Yes             No           Yes ✅
Closing marker      Col 0 only    Tab-indent ok   Col 0 only   Indent ok ✅
Works with spaces   Yes           No ⚠️            Yes          Yes ✅
editor (no tabs)
Variable expand     Yes $VAR      Yes $VAR        Yes ${x}     Yes ${x}
```

**Practical rule for this series:**
Always use `<<-EOT` in HCL. It keeps your config properly indented,
produces clean output, and works regardless of whether your editor
uses tabs or spaces. `<<EOT` is only needed when you specifically
want the leading spaces to be part of the string value.

**Never use heredoc for JSON or YAML in Terraform.** Use
`jsonencode()` or `yamlencode()` instead — Terraform guarantees
valid syntax and handles escaping automatically. Heredocs are for
free-form text: shell scripts, user_data, report content, plain text files.

---

## Part 5 — terraform console: Your HCL Sandbox

`terraform console` opens a **REPL** (Read-Eval-Print Loop) for HCL
expressions. A REPL: **R**eads your input → **E**valuates it →
**P**rints the result → **L**oops back. Every time you type an expression
and press Enter, that is one REPL cycle. Python's interactive shell and
the browser console are both REPLs.

No apply, no AWS, no state changes. The fastest way to understand
and test HCL before using it in real configs.

```bash
# Start the console (run from any directory — even empty)
terraform console
# >
```

```hcl
# ── STRING FUNCTIONS ──────────────────────────────────────────────────────
> upper("hello")
"HELLO"

> lower("PROD")
"prod"

> "${upper("cloud")}Nova-${lower("DEV")}"
"CLOUDNova-dev"

> length("terraform")
9

> replace("us-east-2", "-", "_")
"us_east_2"

# ── NUMBER FUNCTIONS ──────────────────────────────────────────────────────
> floor(3.9)
3

> ceil(3.1)
4

> max(1, 5, 3)
5

# ── LIST OPERATIONS ───────────────────────────────────────────────────────
> ["a", "b", "c"][0]
"a"

> length(["us-east-2a", "us-east-2b"])
2

> contains(["dev", "prod"], "staging")
false

> concat(["a", "b"], ["c", "d"])
tolist([
  "a",
  "b",
  "c",
  "d",
])

# ── MAP / KEYS ────────────────────────────────────────────────────────────
> { "key" = "value" }["key"]
"value"

> keys({ env = "dev", project = "nova" })
toset([
  "env",
  "project",
])
# Note: keys() returns list(string), sorted lexicographically.
# The console displays it as toset([...]) because map keys are inherently
# unordered and unique — this is a console rendering quirk, not a function call.

# ── TYPE CONVERSIONS ──────────────────────────────────────────────────────
> tostring(42)
"42"

> tonumber("42")
42

> tolist(toset(["b", "a", "c"]))
tolist([
  "a",
  "b",
  "c",
])
# toset removes duplicates and sorts; tolist converts back to ordered list

# ── CONDITIONAL EXPRESSION ────────────────────────────────────────────────
> "prod" == "prod" ? "match" : "no match"
"match"

> 3 > 1 ? "bigger" : "smaller"
"bigger"

# Exit
> exit
```

> **Pro tip:** In Demo 06 and beyond you will use `cidrsubnet()`,
> `templatefile()`, `for` expressions, and `flatten()` in real configs.
> The console lets you validate them before committing to infrastructure.

---


## Part 6 — The Terraform Workflow

Before running the lab, understand exactly what each command does to your
filesystem, state, and infrastructure:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      THE TERRAFORM WORKFLOW                              │
│                                                                          │
│  terraform init                                                          │
│  ├─ Reads required_providers in versions.tf                             │
│  ├─ Downloads provider plugins → .terraform/providers/                  │
│  ├─ Creates/updates .terraform.lock.hcl (exact version + SHA256 hash)   │
│  └─ Initialises backend (local by default)                              │
│     Filesystem after: .terraform/ + .terraform.lock.hcl created        │
│                                            │                            │
│  terraform validate                        │                            │
│  ├─ Parses all .tf files for syntax errors │                            │
│  ├─ Checks argument names against provider │ schema                     │
│  ├─ Verifies type constraints on variables │                            │
│  └─ Makes ZERO API calls                   │                            │
│     Result: "Success!" or specific error   │                            │
│                                            │                            │
│  terraform fmt                             │                            │
│  ├─ Auto-formats all .tf files in place    │                            │
│  ├─ Enforces: 2-space indent, aligned =,   │ sorted blocks              │
│  └─ Prints names of reformatted files      │                            │
│     Run before every git commit            │                            │
│                                            │                            │
│  terraform plan                            ▼                            │
│  ├─ Reads .tf files → desired state                                     │
│  ├─ Reads .tfstate → last known state                                   │
│  ├─ Calls provider Read() API → actual current state                    │
│  ├─ Calculates diff                                                     │
│  │    + create    resource does not exist, will be created              │
│  │    ~ update    resource exists, arguments will change in-place       │
│  │    - destroy   resource exists, will be deleted                      │
│  │   -/+ replace  argument change forces destroy + recreate             │
│  └─ Prints plan. Makes ZERO changes.                                    │
│     ALWAYS read the plan before applying.                               │
│                                                                         │
│  terraform plan -out=tfplan          ← saves plan to binary file       │
│  terraform apply tfplan              ← applies exactly that plan       │
│  Why: guarantees apply runs what plan showed — no surprise changes      │
│                                                                         │
│  terraform apply                                                        │
│  ├─ Re-runs plan (or uses saved plan file)                              │
│  ├─ Asks: "Do you want to perform these actions? yes/no"                │
│  ├─ -auto-approve skips prompt — USE ONLY IN CI/CD, NOT manually       │
│  ├─ Calls provider APIs to create/update/delete resources               │
│  └─ Updates terraform.tfstate after each resource completes            │
│     Filesystem after: terraform.tfstate created/updated                 │
│                                                                         │
│  terraform destroy                                                      │
│  ├─ Builds reverse dependency graph                                     │
│  ├─ Creates a destroy plan (every resource gets -)                     │
│  ├─ Asks for confirmation                                               │
│  ├─ Calls provider Delete() API for each resource                      │
│  └─ Updates terraform.tfstate (resources removed, serial incremented)  │
│     Always run before ending a demo session to avoid charges           │
└──────────────────────────────────────────────────────────────────────────┘
```

### The Three Files Terraform Creates

```
.terraform/                    ← NEVER commit — add to .gitignore
│                                 Provider plugin binaries live here.
│                                 Can be hundreds of MB.
│                                 Recreated from scratch by terraform init.
│
.terraform.lock.hcl            ← ALWAYS commit to version control
│                                 Records exact resolved provider version
│                                 + SHA256 hash of the downloaded binary.
│
│                                 Without it: Engineer A runs init, gets
│                                 provider v2.9.0. Engineer B runs init
│                                 next week, gets v2.9.1 (just released,
│                                 has a breaking bug). Their plans produce
│                                 different results for identical configs.
│
│                                 With it: every engineer and every CI
│                                 runner downloads the exact same binary.
│
terraform.tfstate              ← NEVER commit to Git (local workflow)
                                  JSON snapshot of all managed resources.
                                  Contains IDs, ARNs, IP addresses,
                                  and possibly sensitive values in plain text.
                                  In teams: always use a remote backend
                                  (S3 + state locking) — covered in Demo 01.
```

## How Outputs and State Work Together

Output values are stored inside `terraform.tfstate` under the `"outputs"` key:

```json
{
  "outputs": {
    "unique_suffix": {
      "value": "k7mx2q",
      "type": "string",
      "sensitive": false
    }
  },
  "resources": [ ... ]
}
```

**When is state updated?**
Every `terraform apply` rewrites the entire state file — both resources
and outputs are recalculated and persisted together. The state file is
a complete snapshot after every apply.

**How does `terraform output` work?**
`terraform output` reads directly from `terraform.tfstate` on disk — it
does NOT make any API calls to AWS. This means:
- If you run `terraform output` before `terraform apply` → empty (no state yet)
- If state is out of date (someone changed infra manually) → output shows
  the last *applied* value, not the current real value
- `terraform refresh` (or `terraform apply -refresh-only`) re-reads actual
  infra and updates state before outputs reflect reality

---

## Directory Structure

```
00-tf-hcl-basics/               
├── README.md                   # this file
├── 00-tf-hcl-basics-anki.csv   # anki Flash cards
├── 00-tf-hcl-basics-quiz.md    # quiz
└── src/
    ├── versions.tf             # terraform block + required_providers
    ├── variables.tf            # input variable declarations
    ├── locals.tf               # computed values using variable inputs
    ├── main.tf                 # two resources: random_string + local_file
    ├── outputs.tf              # exposes filename and suffix after apply
    ├── output/                 # Terraform writes the generated file here
    │   └── .gitkeep            # keeps directory in Git (empty dir workaround)
    └── break-fix/             
        └── broken.tf           # keep break-fix scenario code in one file
```

---

## Lab — Full Terraform Workflow: Zero AWS, Zero Cost

This lab uses two providers that make **no external API calls**. No AWS
account. No credentials. No cost. The result: a generated text file on
your disk — tangible proof the full Terraform workflow works end to end.

### Providers Used

| Provider | Source | Version | What it does |
|---|---|---|---|
| `hashicorp/local` | `hashicorp/local` | `~> 2.9.0` | Creates/manages files on the local filesystem |
| `hashicorp/random` | `hashicorp/random` | `~> 3.9.0` | Generates random values — purely logical, zero API calls |

**Why two providers?** To demonstrate that a single Terraform configuration
can use multiple providers simultaneously. In production you routinely
combine AWS + Kubernetes + Helm + Datadog in one config. The workflow is
identical regardless of how many providers are involved.

---

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/00-tf-hcl-basics/src
```

---

### Step 2 — Review the source files

Before running a single command, read every file and understand its purpose.

---

#### `versions.tf` — What providers does this config need?

**Purpose:** Declares which Terraform CLI version and which provider plugins
this configuration requires. This is the first file `terraform init` reads.

**Why it's separate:** Version constraints are infrastructure-level decisions
that rarely change. Keeping them isolated makes auditing and upgrades easy.

**versions.tf:**

```hcl
terraform {
  required_version = "~> 1.15.0"   # Terraform CLI must be 1.15.x

  required_providers {
    local = {
      source  = "hashicorp/local"   # registry.terraform.io/hashicorp/local
      version = "~> 2.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
  }
}
# No provider {} blocks needed — local and random require no configuration
```

**After `terraform init`:** Terraform downloads both providers into
`.terraform/providers/` and locks their exact versions in
`.terraform.lock.hcl`.

---

#### `variables.tf` — What inputs does this config accept?

**Purpose:** Declares three parameters that can be customised without
changing any resource code. This is how the same configuration works
across different people and environments.

**Why it matters:** Without variables, you would hardcode values like
`"DevOps Engineer"` directly in `main.tf`. To change it you would edit
a resource file — risky. With variables, you change a value, never logic.

**variables.tf:**

```hcl
variable "project_name" {
  type        = string
  description = "Name of the project — used in generated filenames"
  default     = "cloudnova"
}

variable "environment" {
  type        = string
  description = "Target deployment environment"
  default     = "dev"

  validation {                    # Terraform rejects invalid values at plan time
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "author" {
  type        = string
  description = "Your name — written into the generated report file"
  default     = "DevOps Engineer"
}
```

**After `terraform plan`:** If you pass `-var="environment=qa"` Terraform
will fail immediately with the validation error — before any resource is
touched.

---

#### `locals.tf` — Derived values computed from inputs

**Purpose:** Computes reusable values from the input variables. Locals
are evaluated once and referenced throughout the config. They are
never passed in from outside.

**Why it matters:** Without locals, you would repeat
`"${var.project_name}-${var.environment}-${random_string.suffix.result}.txt"`
everywhere it is needed. Change the naming pattern → change one local.

**Key teaching moment:** `random_string.suffix.result` is a **cross-resource
reference**. Terraform sees it and automatically knows `local_file.report`
depends on `random_string.suffix`. It creates the random string first. No
`depends_on` needed — the reference IS the dependency declaration.

**locals.tf:**
```hcl
locals {
  # Level 1 — primitive values
  project     = var.project_name
  environment = var.environment

  # Level 2 — composite values built from level 1
  # random_string.suffix.result is a resource attribute reference
  # this shows cross-resource referencing — the file depends on the random string
  filename    = "${local.project}-${local.environment}-${random_string.suffix.result}.txt"

  # Level 3 — the content written into the file
  # templatefile() would be used here in production; heredoc used for clarity
  file_content = <<-EOT
    ┌──────────────────────────────────────────────┐
    │  CloudNova Infrastructure Report             │
    ├──────────────────────────────────────────────┤
    │  Project     : ${local.project}
    │  Environment : ${local.environment}
    │  Generated   : by Terraform
    │  Author      : ${var.author}
    │  Unique ID   : ${random_string.suffix.result}
    └──────────────────────────────────────────────┘

    This file was created by Terraform.
    It was NOT created by hand — it is 100% reproducible.

    Run 'terraform destroy' then 'terraform apply' again and you get
    a new unique ID but the same structure. That is IaC.
  EOT
}
```

---

#### `main.tf` — The resources (what Terraform actually creates)

**Purpose:** Declares the two resources this configuration manages. This
is the only file that causes real side effects — creating objects in the
world.

**Why two resources?** `random_string.suffix` (provider: `hashicorp/random`)
and `local_file.report` (provider: `hashicorp/local`) each come from a
different provider. Together they demonstrate multi-provider configuration
in a single, cost-free, side-effect-minimal setup.

**main.tf:**
```hcl
# Provider: hashicorp/random
# Generates a short alphanumeric string stored in state.
# Same value on every apply until explicitly replaced.
resource "random_string" "suffix" {
  length  = 6      # mandatory — how many characters
  upper   = false  # optional — no uppercase (cleaner in filenames)
  special = false  # optional — no special chars (!@#) — safe in filenames
  numeric = true   # optional — include digits
}

# Provider: hashicorp/local
# Creates a text file on the filesystem where Terraform runs.
# Terraform manages the file: plan detects changes, destroy removes it.
resource "local_file" "report" {
  filename        = "${path.module}/output/${local.filename}"
  # path.module = the directory containing this .tf file (Terraform built-in)
  content         = local.file_content
  file_permission = "0644"   # rw-r--r--
  # Implicit dependency: local.filename references random_string.suffix.result
  # → Terraform creates random_string.suffix BEFORE local_file.report
}
```

---

#### `outputs.tf` — What does this config expose after apply?

**Purpose:** Makes values available outside the configuration — printed
in the terminal after apply, queryable with `terraform output`, and
readable by other Terraform configs via `terraform_remote_state`.

**Why it matters:** In production, one config's output (e.g. a VPC ID)
is another config's input. Outputs are the glue between Terraform stacks.

**outputs.tf:**
```hcl
output "generated_filename" {
  description = "Full path of the generated report file on disk"
  value       = local_file.report.filename
}

output "unique_suffix" {
  description = "Random 6-character suffix used in the filename"
  value       = random_string.suffix.result
}

output "file_content_preview" {
  description = "Summary line confirming what was created"
  value       = local.file_content
}
```

--

### Step 3 — Initialise

```bash
terraform init
```

Expected output:

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/local versions matching "~> 2.9.0"...
- Finding hashicorp/random versions matching "~> 3.9.0"...
- Installing hashicorp/local v2.9.0...
- Installed hashicorp/local v2.9.0 (signed by HashiCorp)
- Installing hashicorp/random v3.9.0...
- Installed hashicorp/random v3.9.0 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the
provider selections made above.

Terraform has been successfully initialized!
```

**Verify what was created:**

```bash
ls -la
# .terraform/              ← created — provider binaries downloaded here
# .terraform.lock.hcl      ← created — exact versions + checksums locked

# Provider plugins downloaded here — do not commit
ls .terraform/providers/

# Lock file — always commit this
cat .terraform.lock.hcl
# provider "registry.terraform.io/hashicorp/local" {
#   version     = "2.9.0"
#   constraints = "~> 2.9.0"
#   hashes = [
#     "h1:...",   ← SHA256 hash of the binary — tamper detection
#   ]
# }
```

---

### Step 4 — Validate and Format

```bash
# Check syntax and argument names against provider schema — zero API calls
terraform validate
# Success! The configuration is valid.

# Auto-format all .tf files — fix whitespace, alignment, ordering
terraform fmt
# (prints filenames of any files it reformatted, or nothing if already formatted)

# Check what fmt would change without applying it
terraform fmt -check -diff
```

---

### Step 5 — Plan

```bash
terraform plan
```

Expected output (read this carefully — this is the skill):

```
Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # random_string.suffix will be created
  + resource "random_string" "suffix" {
      + id      = (known after apply)    ← computed at apply time
      + length  = 6
      + lower   = true
      + numeric = true
      + result  = (known after apply)    ← the random value — unknown until apply
      + special = false
      + upper   = false
    }

  # local_file.report will be created
  + resource "local_file" "report" {
      + content              = (known after apply)  ← depends on random_string
      + directory_permission = "0777"
      + file_permission      = "0644"
      + filename             = (known after apply)  ← includes the random suffix
      + id                   = (known after apply)
    }

Plan: 2 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + file_content_preview = (known after apply)
  + generated_filename   = (known after apply)
  + unique_suffix        = (known after apply)
```

**Reading plan symbols:**

| Symbol | Meaning | What happens |
|---|---|---|
| `+` | Create | Resource does not exist — will be created |
| `~` | Update | Resource exists — arguments change in-place |
| `-` | Destroy | Resource exists — will be deleted |
| `-/+` | Replace | Argument change forces destroy + recreate |
| `(known after apply)` | Computed value | Not knowable until the resource is created |

**Save the plan to a file (best practice for production):**

```bash
terraform plan -out=tfplan    # saves binary plan file
terraform apply tfplan        # applies exactly what was planned — no surprises
```

---

### Saved Plan Files — What Happens if Config Changes Between Plan and Apply?

```bash
terraform plan -out=tfplan    # plan calculated now, saved to binary file
# ... you edit main.tf here ...
terraform apply tfplan        # applies the SAVED plan — ignores your edits
```

The saved plan is a **binary snapshot** of the exact diff calculated at
plan time. `terraform apply tfplan` applies that snapshot — it does NOT
re-read your `.tf` files. Your edits are silently ignored.

This is actually a feature, not a bug — in CI/CD pipelines:
1. `terraform plan -out=tfplan` runs on PR open (human reviews the plan)
2. `terraform apply tfplan` runs on merge (applies exactly what was reviewed)

Nobody can inject changes between review and apply.

**In development:** if you edit files after planning, run `terraform plan`
again — never apply a stale saved plan you have since modified.

**Saved plans expire with state changes:** if another apply runs against
the same state between your plan and apply (a teammate applies first),
Terraform will detect the state serial mismatch and refuse to apply the
stale plan with an error. This is the state locking mechanism working
correctly.

---

### Step 6 — Apply

```bash
terraform apply
```

Type `yes` when prompted. Expected output:

```
random_string.suffix: Creating...
random_string.suffix: Creation complete after 0s [id=k7mx2q]

local_file.report: Creating...
local_file.report: Creation complete after 0s [id=abc123...]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

file_content_preview = "File created: cloudnova-dev-k7mx2q.txt"
generated_filename   = "/path/to/src/output/cloudnova-dev-k7mx2q.txt"
unique_suffix        = "k7mx2q"
```

**Verify the result:**

```bash
# File created on disk
ls src/output/
# cloudnova-dev-k7mx2q.txt

# Read the generated file
cat src/output/cloudnova-dev-k7mx2q.txt
# ┌──────────────────────────────────────────────┐
# │  CloudNova Infrastructure Report             │
# ...
```

**Query outputs at any time:**

```bash
terraform output                      # all outputs with quotes
terraform output unique_suffix        # specific output with quotes
terraform output -raw unique_suffix   # no quotes — use in shell scripts
terraform output -json                # all outputs as JSON
```

---

### Step 7 — Explore State

```bash
# Human-readable view of all managed resources
terraform show

# List all resources Terraform manages
terraform state list
# local_file.report
# random_string.suffix

# Detailed state of one resource
terraform state show random_string.suffix
# resource "random_string" "suffix" {
#     id      = "k7mx2q"
#     length  = 6
#     lower   = true
#     numeric = true
#     result  = "k7mx2q"
#     special = false
#     upper   = false
# }

# The raw state file — JSON, never edit manually
cat terraform.tfstate
```

**What the state file contains:**

```
terraform.tfstate is a JSON file that records:
  - Every resource Terraform manages (resource type, name, provider)
  - Every attribute of every resource (IDs, ARNs, IPs, config values)
  - The serial number (increments on every apply)
  - The Terraform and provider versions used

Why this matters:
  - terraform plan compares .tf files to terraform.tfstate to find drift
  - If you delete terraform.tfstate, Terraform loses track of everything
    it created — it will try to create everything again on next apply
  - In teams, terraform.tfstate lives in a remote backend (S3 in Demo 01)
    never in Git
```

#### Forcing random_string to regenerate

`random_string` generates once on first apply and is stored in state.
Every subsequent apply reuses the stored value — Terraform reads it from
`.tfstate` rather than regenerating. It only changes when:

1. **A config argument changes** — e.g. changing `length = 6` to `length = 8`
   forces a `-/+` replace (destroy old string, generate new one)
2. **You force replacement** using the modern `-replace` flag:

```bash
# Force random_string.suffix to regenerate on next apply
terraform plan -replace="random_string.suffix"

# Review the -/+ plan — random_string AND local_file will both be replaced
# because local_file depends on random_string.suffix.result

terraform apply -replace="random_string.suffix"
```

> **Note:** `terraform taint` is deprecated since v0.15.2 and removed
> from documentation. Always use `-replace` instead.

---

### Step 8 — Change and Observe the Diff

Edit `variables.tf` — change the `author` default:

```hcl
variable "author" {
  default = "Senior DevOps Engineer"   # was: "DevOps Engineer"
}
```

Re-run plan:

```bash
terraform plan
```

```
  # local_file.report must be replaced   ← -/+ because content hash changes
-/+ resource "local_file" "report" {
      ~ content = <<-EOT
            ...
          - │  Author      : DevOps Engineer
          + │  Author      : Senior DevOps Engineer
        EOT
      ~ id      = "abc123" -> (known after apply)
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

The `-/+` means **destroy and recreate** — `local_file` content change
forces replacement because the resource ID is based on a content hash.
Apply the change:

```bash
terraform apply -auto-approve
# Use -auto-approve only in CI/CD pipelines.
# In development: always review the plan manually before applying.
```

---

### Step 9 — Cleanup

```bash
terraform destroy
```

Type `yes`.

```
local_file.report: Destroying... [id=abc123...]
local_file.report: Destruction complete after 0s
random_string.suffix: Destroying... [id=k7mx2q]
random_string.suffix: Destruction complete after 0s

Destroy complete! Resources: 2 destroyed.
```

**Verify:**

```bash
# Output directory should be empty (Terraform removes the file)
ls src/output/
# (empty)

# State file is now empty
cat terraform.tfstate
# {
#   "version": 4,
#   "terraform_version": "1.15.x",
#   "serial": 4,
#   "lineage": "...",
#   "outputs": {},
#   "resources": [],   ← empty — nothing managed
#   "check_results": null
# }
```

---

## Break-Fix Scenario

The following configuration has **three deliberate errors**. Run it as-is
and diagnose the failures using only `terraform validate`, `terraform plan`,
and the error messages. Fix each error before moving on.

**broken.tf:**

```hcl
# broken.tf — DO NOT COPY VERBATIM — find and fix the errors

terraform {
  required_version = "~> 1.15.0"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
  }
}

variable "team" {
  type    = string
  default = "platform"
}

variable "env" {
  type = string

  validation {
    condition     = contains(["dev", "prod"], env)     # Error 1
    error_message = "Must be dev or prod."
  }
}

resource "random_string" "id" {
  length  = 8
  upper   = False                                       # Error 2
  special = false
}

output "team_id" {
  value = "${var.team}-${random.id.result}"             # Error 3
}
```

#### Running the break-fix

The break-fix config lives in `src/break-fix/` — a separate directory
from the working lab. This isolation is intentional: a broken config
in the same directory as your working lab blocks `terraform apply`.

```bash
# Navigate to the break-fix directory
cd src/break-fix/

# Initialise (downloads only the providers break-fix needs)
terraform init

# First signal — syntax and schema errors
terraform validate

# Second signal — reference and type errors
terraform plan

# Fix broken.tf based on error messages, then repeat validate + plan
# Once both are clean, reveal the answer in the <details> block above
```

<details>
<summary>Reveal answers (attempt diagnosis first)</summary>

**Error 1 — `condition = contains(["dev", "prod"], env)`**
`env` is not a valid reference. Variable references inside validation
blocks must use `var.name`. Fix: `contains(["dev", "prod"], var.env)`

**Error 2 — `upper = False`**
HCL booleans are lowercase: `true` and `false`. `False` with a capital F
is not valid HCL. Fix: `upper = false`

**Error 3 — `value = "${var.team}-${random.id.result}"`**
Resource attribute references use the full resource type, not just the
provider name. Fix: `random_string.id.result`
(format: `<resource_type>.<local_name>.<attribute>`)

</details>

---

## What You Learned

1. ✅ IaC solves four specific failures: drift, missing audit trail,
   non-repeatable environments, bus factor
2. ✅ Declarative IaC describes desired state; Terraform calculates steps.
   Idempotent: run twice, second run changes nothing.
3. ✅ Terraform vs CloudFormation vs CDK vs Ansible — each has a clear
   best-fit scenario. Terraform wins on multi-cloud and ecosystem breadth.
4. ✅ Three-component architecture: CLI core (graph + diff) → provider
   plugin (API translation) → state file (source of truth)
5. ✅ Eight HCL top-level block types: terraform, provider, resource,
   variable, locals, output, data, module
6. ✅ Six value types + set: string, number, bool, list, set, map, object.
   `list(object({...}))` for structured collections (used from Demo 06+)
7. ✅ `terraform console` = REPL for testing HCL expressions live
8. ✅ Full workflow: init → validate → fmt → plan → apply → destroy.
   `.terraform/` = don't commit. `.terraform.lock.hcl` = always commit.
   `terraform.tfstate` = never commit locally, use remote backend in teams.

---

## Cert Tips — TA-004 Objectives Covered

**Objective 1a — What is IaC:**
> IaC = infrastructure defined in version-controlled code files, applied
> programmatically. Key property: **idempotent**. Exam frequently tests:
> "What happens when you run terraform apply with no config changes?" → plan
> shows 0 changes, no API calls made.

**Objective 1b — Advantages of IaC:**
> The five advantages the exam tests: **consistency** (no drift),
> **repeatability** (identical environments), **version control** (audit
> trail), **automation** (no manual clicks), **self-documentation**
> (code IS the docs). Know all five by name.

**Objective 1c — Multi-cloud and service-agnostic:**
> Terraform manages AWS, Azure, GCP, Kubernetes, Datadog, GitHub and 3,000+
> others through one workflow. Exam trap: "CloudFormation supports
> multi-cloud" → **False**.

**Common MCQ traps:**

| Question | Answer | Why |
|---|---|---|
| Should `.terraform.lock.hcl` be committed? | **Yes** | Locks exact provider versions + hashes |
| Should `.terraform/` be committed? | **No** | Binary plugins, reproduced by init |
| Should `terraform.tfstate` be committed? | **No** | Sensitive values, causes conflicts |
| Does `terraform plan` make API calls? | **Yes** — Read() only | Reads current state, writes nothing |
| Is `terraform apply` idempotent? | **Yes** | No changes if config matches state |
| Does `map(string)` allow mixed value types? | **No** | All values must be strings |

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `terraform: command not found` | CLI not installed or not in PATH | Follow install steps; verify with `terraform version` |
| `Error: Required plugins are not installed` | `init` not run | Run `terraform init` |
| `Error: Invalid version constraint "~>1.15"` | Missing space | Must be `"~> 1.15.0"` with space |
| `Error: Unsupported argument` | Wrong argument name for this provider version | Check registry.terraform.io for exact provider version docs |
| `Error: Invalid expression` — `False` | HCL booleans are lowercase | Use `false` not `False` |
| `Error: Reference to undeclared resource` | Wrong resource type in reference | Format: `<resource_type>.<name>.<attr>` |
| `Error: A lock file conflict` | Lock file has different constraints | Run `terraform init -upgrade` |
| `directory output/ does not exist` | Output dir not created | `mkdir -p src/output` before apply |

---

## Key Takeaways

1. **IaC is about removing human error from repeatable processes.** The
   Console is fine for exploration. It is not acceptable for production
   infrastructure that needs to be audited, reproduced, or owned by a team.

2. **Declarative + idempotent = safe to automate.** You can run
   `terraform apply` in a CI/CD pipeline on every merge to main because
   applying an already-correct state does nothing. You cannot safely do
   that with imperative bash scripts.

3. **The state file is Terraform's memory — protect it.** Lost state =
   Terraform creates everything again on next apply. Corrupted state =
   resources orphaned forever. Remote backend with locking from day one
   (S3 + `use_lockfile = true`) — covered in Demo 01.

4. **The lock file is your reproducibility guarantee.** Commit it. A team
   without `.terraform.lock.hcl` is a team where "it works on my machine"
   can mean different provider versions producing different infrastructure.

5. **`terraform plan` is not optional.** Every apply in production should
   start with a plan reviewed by a human or a CI gate. Demo 22 builds a
   GitHub Actions pipeline that enforces exactly this.

---

## Next Demo

**Demo 01 — `01-tf-fundamentals-s3`:** Apply everything you just learned
against real AWS infrastructure. First `terraform apply` against AWS:
an S3 bucket with versioning, encryption, and public-access blocking.
Introduces AWS provider authentication, remote S3 state backend,
and the Console verification workflow.

---

## Appendix — Anki Cards

**00-tf-hcl-basics-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::00-tf-hcl-basics
#separator:Comma
#columns:Front,Back,Tags
"You run terraform apply on a config that already matches current infrastructure. What happens and why?","Plan shows 0 to add, 0 to change, 0 to destroy. No API calls made. Terraform compares desired state (.tf files) against current state (.tfstate), finds no diff, takes no action. This is idempotency — applying the same desired state twice produces the same result as once.","demo00,idempotency,workflow,ta004-obj1"
"A team member manually tweaks a server config at 2am to fix an incident. Nobody updates the runbook. Six months later, staging and prod have different configs. What is this called and what is the root cause?","This is DRIFT — environments diverging silently over time. Root cause: manual changes made outside version control with no audit trail. IaC prevents this by requiring all changes to go through code review and automated apply.","demo00,drift,ta004-obj1"
"Name the four failure modes of manual Console-based infrastructure management.","1. Drift — environments diverge silently. 2. No audit trail — cannot answer who changed what and when. 3. Not repeatable — recreating environments requires clicking screens again. 4. Bus factor — knowledge leaves when the person does.","demo00,iac-concepts,ta004-obj1"
"Should .terraform.lock.hcl be committed to version control? Why?","YES. Records exact provider version AND SHA256 hash of downloaded binary. Without it: Engineer A gets provider v2.9.0, Engineer B gets v2.9.1 released yesterday with a breaking bug. Plans differ for identical configs.","demo00,lockfile,best-practices,ta004-obj2"
"Should .terraform/ be committed to version control? Why?","NO. Contains downloaded provider plugin binaries — can be hundreds of MB. Fully reproduced by running terraform init. Add to .gitignore.","demo00,lockfile,best-practices,ta004-obj2"
"Should terraform.tfstate be committed to Git? Why?","NO. May contain sensitive values in plain text. Also causes merge conflicts when multiple engineers apply simultaneously. In teams: use a remote backend (S3 + locking) — covered in Demo 01.","demo00,state,security,ta004-obj5"
"What is the difference between declarative and imperative IaC?","Declarative: describe WHAT end state you want — Terraform figures out the steps. Idempotent: run twice and nothing changes. Imperative: describe HOW to get there — every step and existence check. Run twice: error if resource already exists. Examples: bash scripts, Python boto3.","demo00,iac-concepts,ta004-obj1"
"Name the 5 advantages of IaC the TA-004 exam tests.","1. Consistency — no configuration drift. 2. Repeatability — identical environments every time. 3. Version control — full audit trail in Git. 4. Automation — no manual clicks. 5. Self-documentation — the code IS the documentation.","demo00,iac-concepts,ta004-obj1b"
"Does CloudFormation support multi-cloud? Does Terraform?","CloudFormation: NO — AWS only. Terraform: YES — AWS, Azure, GCP, Kubernetes, Datadog, GitHub and 3000+ providers through the same workflow and HCL syntax.","demo00,tool-comparison,ta004-obj1c"
"What does terraform init do to the filesystem? Name all 3 effects.","1. Downloads provider plugins → .terraform/providers/. 2. Creates or updates .terraform.lock.hcl with exact versions and SHA256 hashes. 3. Initialises the backend (local by default).","demo00,workflow,init,ta004-obj3"
"What does terraform plan do? Does it change any infrastructure?","Reads .tf files (desired state), reads .tfstate (last known state), calls provider Read() API (actual state), calculates diff, prints execution plan. Makes ZERO changes to infrastructure or state. Always review before applying.","demo00,workflow,plan,ta004-obj3"
"What do the plan symbols +, ~, -, -/+ mean?","+ create: does not exist, will be created. ~ update in-place: exists, arguments change without replacement. - destroy: exists, will be deleted. -/+ replace: argument change forces destroy then recreate.","demo00,workflow,plan,ta004-obj3"
"What does (known after apply) mean in a terraform plan output?","The value cannot be determined until the resource is created. Example: EC2 public IP — AWS assigns it at creation time. Terraform shows this placeholder in the plan.","demo00,workflow,plan,ta004-obj3"
"What does terraform plan -out=tfplan + terraform apply tfplan guarantee?","apply tfplan executes the exact binary snapshot from plan time — does NOT re-read .tf files. Edits made after planning are silently ignored. In CI/CD: plan on PR open (human reviews), apply on merge (executes exactly what was reviewed).","demo00,workflow,plan,best-practices"
"What is the difference between variable and locals in Terraform?","variable: accepts INPUT from outside — tfvars, CLI flags, env vars, or default. Reference: var.name. locals: computed values inside the config. Accept NO external input. Reference: local.name. Block is plural (locals {}), reference is singular (local.x).","demo00,hcl,variables,ta004-obj4"
"What is the difference between map(string) and object({...}) in HCL?","map(string): arbitrary key-value pairs where ALL values must be strings. Keys not predefined. Good for tags. object({...}): FIXED schema where each key has its own type. Good for structured config with mixed types.","demo00,hcl,types,ta004-obj4"
"What type is list(object({name=string, cidr=string}))? Give a use case.","A list of objects — each element is a structured record with fixed schema. Used for subnet definitions, ECS container definitions, DB replica configs. Access: var.subnets[0].cidr","demo00,hcl,types,ta004-obj4"
"What is the difference between list and set in HCL?","list: ordered, allows duplicates, index access via [n]. set: unordered, no duplicates, NO index access. Use set when order does not matter and uniqueness is required — e.g. security group IDs, AZ names.","demo00,hcl,types,ta004-obj4"
"How does Terraform determine resource creation order?","Builds a Directed Acyclic Graph (DAG) from attribute references. If B references A's output, Terraform creates A first — implicit dependency. depends_on only needed when dependency is not expressed as an attribute reference.","demo00,dependency,graph,ta004-obj4"
"What is terraform console? What does REPL stand for?","Interactive Read-Eval-Print Loop for testing HCL expressions. Reads input, Evaluates it, Prints result, Loops. No apply, no API calls, no state changes. Each Enter = one REPL cycle.","demo00,hcl,console,ta004-obj4"
"Fix this validation block: condition = contains(['dev','prod'], env)","Two errors: (1) Single quotes invalid in HCL — must use double quotes. (2) env is not a valid reference — must use var.env. Correct: condition = contains([\"dev\", \"prod\"], var.env)","demo00,hcl,validation,break-fix"
"Fix this argument: upper = False","HCL booleans are always lowercase. False with capital F is invalid HCL. Fix: upper = false","demo00,hcl,types,break-fix"
"Fix this output value reference: ${random.id.result}","random is a provider name, not a resource type. Resource attribute references require the full resource TYPE. Fix: random_string.id.result — format is resource_type.local_name.attribute","demo00,hcl,references,break-fix"
"What does terraform fmt do and when should you run it?","Auto-formats .tf files to canonical style: 2-space indent, aligned = signs, consistent spacing. Run before every git commit. terraform fmt -check exits non-zero if files need formatting (use in CI).","demo00,workflow,fmt,ta004-obj3"
"What is the Terraform Registry?","registry.terraform.io — public repository of providers and modules. terraform init downloads providers from here. URL format: registry.terraform.io/namespace/provider. Example: registry.terraform.io/hashicorp/aws.","demo00,providers,registry,ta004-obj2"
"What is the key difference between Terraform and OpenTofu?","Both use identical HCL syntax and workflow. Terraform: HashiCorp (IBM), BUSL 1.1 license, v1.15.5. OpenTofu: Linux Foundation fork, MPL 2.0 license, v1.11.6. Choose Terraform for cert prep. Choose OpenTofu only if org has a hard OSS license requirement.","demo00,terraform-vs-opentofu"
"What happens to terraform.tfstate after terraform destroy?","The state file is NOT deleted. The resources array becomes empty. Serial number increments. The file remains on disk. Running terraform apply after destroy creates everything fresh.","demo00,state,destroy,ta004-obj5"
"What is path.module in Terraform?","Built-in reference that evaluates to the filesystem path of the directory containing the .tf file that uses it. Used to build relative file paths that work regardless of where terraform is run from.","demo00,hcl,references,ta004-obj4"
"What are terraform.tfvars and *.auto.tfvars? When are they loaded?","terraform.tfvars: auto-loaded on every plan/apply — no flags needed. *.auto.tfvars: auto-loaded in lexical order. Any other .tfvars name requires -var-file=filename.tfvars. Precedence: default → TF_VAR_ → terraform.tfvars → *.auto.tfvars → -var-file → -var (last wins).","demo00,variables,tfvars,ta004-obj4"
"When does random_string regenerate? How do you force it?","Generates once on first apply, stored in state, reused forever. Changes when: (1) config argument changes (length, special, etc.), (2) forced with: terraform apply -replace=random_string.suffix. Never use terraform taint — deprecated since v0.15.2.","demo00,random,replace"
"What does <<EOT display mean in terraform output?","When an output value is a multi-line string (heredoc), the terminal shows it as <<EOT ... EOT. This is correct behaviour — Terraform's way of displaying multi-line strings. Not an error. Use terraform output -json to see it as a plain JSON string.","demo00,outputs,heredoc"
"What is the difference between <<EOT and <<-EOT in HCL?","<<EOT: all leading whitespace preserved, closing EOT must be at column 0. <<-EOT: Terraform finds the least-indented line and strips that many spaces from all lines — closing EOT can be freely indented. Use <<-EOT in all HCL configs.","demo00,hcl,heredoc,ta004-obj4"
"In HCL map(string) — what does the type in parentheses mean?","The type in parentheses is the VALUE type constraint. map(string) = every value must be a string. map(number) = every value must be a number. The keys are always strings in any map.","demo00,hcl,types,ta004-obj4"
"What is the correct Terraform term for the second label in resource 'aws_s3_bucket' 'app_data'?","Local name (or just name) — not local variable. app_data is the local name. Local variable is reserved for locals {} block values referenced as local.x. The local name is used in attribute references: aws_s3_bucket.app_data.arn","demo00,hcl,terminology,ta004-obj4"
```

---

## Appendix — Quiz

**00-tf-hcl-basics-quiz.md:**

```
# Demo 00 — Quiz

> TA-004 exam style. One correct answer unless stated otherwise.
> Target: 80% or above before moving to Demo 01.

---

**Q1.** You run `terraform apply` on a configuration that already matches
current infrastructure. What does Terraform do?

- A) Destroys and recreates all resources to ensure consistency
- B) Skips apply and shows an error saying nothing to do
- C) Shows a plan of 0 to add, 0 to change, 0 to destroy and makes no API calls
- D) Refreshes state and updates the lock file

<details>
<summary>Answer</summary>

**C** — Terraform compares desired state (.tf files) against current state
(.tfstate), finds no diff, does nothing. This is idempotency.

Trap: D is wrong — apply does refresh state during planning, but does NOT
update the lock file. The lock file only changes on terraform init or
terraform init -upgrade.

</details>

---

**Q2.** Which file should always be committed to version control?

- A) terraform.tfstate
- B) .terraform/
- C) terraform.tfvars
- D) .terraform.lock.hcl

<details>
<summary>Answer</summary>

**D** — Records exact provider versions and SHA256 hashes.
A: Never — may contain sensitive values in plain text.
B: Never — binary plugin files, hundreds of MB, reproduced by init.
C: Generally not — commit only .tfvars.example with placeholder values.

</details>

---

**Q3.** What is the correct HCL syntax for a boolean false value?

- A) False
- B) "false"
- C) false
- D) FALSE

<details>
<summary>Answer</summary>

**C** — HCL booleans are always lowercase: true and false.
False, TRUE, FALSE are all invalid. "false" is a string, not a bool.

</details>

---

**Q4.** A team member creates an S3 bucket manually in the AWS Console.
Another engineer runs terraform apply on a config that does NOT include
that bucket. What happens to the manually created bucket?

- A) Terraform imports it automatically into state
- B) Terraform ignores it — only manages what is in .tf files and state
- C) Terraform destroys it to reconcile state
- D) Terraform shows an error and stops

<details>
<summary>Answer</summary>

**B** — Terraform only manages resources it knows about (those in state).
A manually created resource outside Terraform is invisible to it.
Terraform neither imports nor destroys it.

Key distinction: this differs from drift. Drift = a Terraform-managed
resource changed outside Terraform. An unmanaged resource simply coexists.

</details>

---

**Q5.** What is the most accurate difference between variable and locals?

- A) Variables are for strings only; locals support all types
- B) Variables accept external input; locals are computed internally
- C) Locals are deprecated in favour of variables with default values
- D) They are identical — locals is just an alias for variable

<details>
<summary>Answer</summary>

**B** — variable accepts input from outside (tfvars, CLI, env vars, defaults).
Reference: var.name. locals are computed inside the config — no external
input. Reference: local.name (singular, block is locals plural).

</details>

---

**Q6.** Which command checks .tf syntax and argument names against the
provider schema, but makes zero API calls?

- A) terraform plan
- B) terraform init
- C) terraform validate
- D) terraform fmt

<details>
<summary>Answer</summary>

**C** — terraform validate checks syntax and schema locally. Zero API calls.
A: terraform plan DOES make API calls (Read() on existing resources).
B: terraform init downloads providers but does not validate your config.
D: terraform fmt only reformats whitespace — no validation.

</details>

---

**Q7.** You run terraform plan -out=tfplan, then edit main.tf, then run
terraform apply tfplan. Which config does Terraform apply?

- A) The current main.tf — apply always re-reads config files
- B) The saved plan — apply uses the snapshot from when plan ran
- C) Neither — Terraform detects the mismatch and asks which to use
- D) Terraform merges the saved plan with the current config changes

<details>
<summary>Answer</summary>

**B** — A saved plan is a binary snapshot. terraform apply tfplan executes
that snapshot — does NOT re-read .tf files. Your edits are silently ignored.

In CI/CD this is a feature: plan on PR, apply exactly what was reviewed.
In development: always re-plan if you edit files after planning.

</details>

---

**Q8.** In required_providers, what is "aws" in: aws = { source = "hashicorp/aws" }?

- A) The provider type — must match the AWS service name
- B) The local name assigned to this provider — used to reference it elsewhere
- C) The registry namespace — equivalent to hashicorp
- D) A required argument name defined by the Terraform specification

<details>
<summary>Answer</summary>

**B** — aws is the local name you assign to this provider. It must match
the last segment of the source path by convention, but you could name it
anything. Resource types prefixed with aws_ map to the provider with
local name aws.

</details>

---

**Q9.** What does <<-EOT do differently from <<EOT in HCL?

- A) Disables string interpolation inside the heredoc
- B) Finds the least-indented line and strips that many spaces from all lines
- C) For single-line strings only; <<EOT is for multi-line
- D) They are identical — the dash has no effect in HCL

<details>
<summary>Answer</summary>

**B** — <<-EOT finds the line with least leading whitespace and strips that
many spaces from all lines. Closing EOT can be indented freely. <<EOT
preserves all whitespace — closing EOT must be at column zero.

</details>

---

**Q10.** Which correctly references an attribute of a random_string resource named suffix?

- A) random.suffix.result
- B) random_string.suffix.id
- C) random_string.suffix.result
- D) var.random_string.suffix

<details>
<summary>Answer</summary>

**C** — Format: resource_type.local_name.attribute → random_string.suffix.result
A: random is the provider name, not the resource type.
B: .id exists but .result is the generated string value.
D: var. prefix is for input variables only.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 10/10 | Proceed to Demo 01 |
| 8-9/10 | Review wrong answers in Anki, then proceed |
| 6-7/10 | Re-read relevant README sections, retry |
| Below 6/10 | Re-read Demo 00 before proceeding |
```