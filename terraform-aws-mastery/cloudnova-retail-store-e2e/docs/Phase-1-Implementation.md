# Phase 1 Implementation — CloudNova Foundations

> Part of `cloudnova-retail-store-e2e`. Companion to
> `docs/Solution-Architecture.md` (governs the whole project) and
> `Phase-1-Recall-Check.md` (Phase 1's recall/quiz content, lives inside
> `Phase 1 - Foundations/`). This document has four parts, in order:
> **Terraform Configuration** (what the code is and why), **Execution**
> (the commands, in sequence), **Verification** (Pass Criteria, then
> proof), **Teardown**.

---

## What This Milestone Builds

Every demo in Phase 1 (00–13) taught one Terraform concept in isolation
— apply it, verify it, tear it down, move to the next demo. This
milestone is different in kind, not just scale: it combines eight of
those individual patterns into **one real, applied AWS environment**,
built and verified as a single coherent system rather than eight
disconnected exercises.

**What actually gets created in AWS**, precisely:

- **3 S3 buckets** (`dev`, `staging`, `prod`) — one per environment, the
  future artifact/upload storage for whatever app eventually runs on
  top of this scaffolding (Phase 3 onward)
- **1 SNS topic → 1 SQS queue**, connected by a subscription and a
  queue policy — the notification backbone a future event-driven
  feature (Phase 3's Lambda analytics bolt-on) will attach to
- **3 CloudWatch log groups + 3 metric filters** — one pair per
  environment, ready to receive real application logs the moment
  compute exists
- **1 IAM role** — the identity a future CI/CD pipeline will assume to
  deploy this system, deliberately broad/self-trust at this stage
- **1 security group**, dynamic-block-driven, on the account's default
  VPC — a placeholder network boundary until real VPC networking
  arrives (Phase 2, Demo 16)
- **3 SSM parameters** — built first with `count`, then migrated live to
  `for_each` via a real `moved` block, so the migration itself is a
  verified event in AWS, not just a code change

**What this milestone deliberately does NOT build:** anything that
runs — no EC2, no containers, no application code. Phase 1 has taught
zero compute. Every resource above is scaffolding a future phase
activates, not a working system on its own.

```
┌─────────────────────────────────────────────────────────────────────┐
│                     CloudNova Phase 1 Milestone                      │
│                                                                        │
│   environments = { dev, staging, prod }   ◄── single source map      │
│         │                                     driving 3 of the 5      │
│         │ for_each                            resource groups below  │
│         ▼                                                             │
│   ┌───────────┐   ┌──────────────┐   ┌─────────────────────┐        │
│   │  S3        │   │  CloudWatch   │   │  SSM Parameter        │        │
│   │  bucket    │   │  log group +  │   │  (SNS topic ARN)      │        │
│   │  ×3        │   │  metric filter│   │  ×3 — count→for_each  │        │
│   │  (prod has │   │  ×3           │   │  migration exercise   │        │
│   │  prevent_  │   │               │   │                        │        │
│   │  destroy)  │   │               │   │                        │        │
│   └───────────┘   └──────────────┘   └─────────────────────┘        │
│                                                                        │
│   ┌────────────────────────┐        ┌───────────────────────────┐   │
│   │  SNS topic               │        │  Security group              │   │
│   │  "order-events"           │        │  (default VPC)               │   │
│   │       │                   │        │  dynamic ingress:             │   │
│   │       ▼ subscription       │        │   - https (0.0.0.0/0)         │   │
│   │  SQS queue                │        │   - ssh   (your IP only)       │   │
│   └────────────────────────┘        └───────────────────────────┘   │
│                                                                        │
│   ┌──────────────────────────────────────────────────────────────┐  │
│   │  IAM role "cloudnova-cicd-deploy-role"                          │  │
│   │  trust: this account's root  |  permissions: S3, SNS, Logs      │  │
│   │  (broad/self-trust — least-privilege is Phase 3, Demo 24)        │  │
│   └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Alignment to Phase 1 Demos

Every resource above traces back to a specific demo's teaching content
— nothing in this milestone introduces a new concept, it only combines
ones already taught:

| Milestone component | Demo(s) it reuses | What that demo actually taught |
|---|---|---|
| `environments` map, `for_each` pattern | Demo 10 | `for_each` over a map, S3+IAM users built per-environment |
| S3 buckets | Demo 10 | `for_each`-driven S3 creation, one bucket per environment |
| SNS → SQS pipeline | Demo 03, Demo 06 | Demo 03: topic → queue → policy → subscription. Demo 06: the SNS topic itself, built via locals |
| CloudWatch log group + metric filter | Demo 09 | `for_each`-driven CloudWatch log groups and metric filters |
| IAM role (broad, self-trust) | Demo 05, Demo 06 | `aws_iam_role` + inline policy pattern, refined with locals |
| `data.aws_caller_identity` (account ID lookup, used in the IAM trust policy) | Demo 08 | Full depth of `data.aws_caller_identity` — the empty-body pattern, `data` vs. `resource` distinction |
| Security group, `dynamic` blocks, `data.aws_vpc` lookup | Demo 10 | `dynamic` ingress block over a map, on the default VPC. The `data "aws_vpc" { default = true }` lookup itself belongs to Demo 10, not Demo 08, per Demo 08's own text |
| `prevent_destroy` on the `prod` bucket | Demo 12 | The `lifecycle` meta-argument block, including its literal-value-only constraints |
| SSM parameter, `count` → `for_each` migration | Demo 07 (resource type) + Demo 11 (mechanics) | Demo 07 introduces `aws_ssm_parameter` itself. Demo 11's actual subject is `resource[0]` vs. `resource["key"]` addressing and `moved` blocks — taught there on Demo 10's SQS/S3/IAM resources, not on SSM. This milestone deliberately combines Demo 11's mechanics with Demo 07's resource type — a cross-demo combination, not a literal repeat of either |
| `terraform_remote_state` standalone check | Demo 07 | The full `consumer/`-style separate root config, zero write access |
| `local-exec` provisioner on the SQS queue | Demo 13 | Provisioners wired to a real resource's real state |

**Demos 00, 01, 02, and 04 are deliberately out of scope, confirmed after reading
their real content — not an oversight:**
- **Demo 00** (IaC & HCL Foundations) — pure HCL/workflow concepts, zero AWS
  resources (local `random`/`local` providers only). Nothing to carry
  forward into an AWS-resource milestone.
- **Demo 01** (Terraform Fundamentals: S3) — its distinguishing content is
  Demo 01 Part B's real remote S3 state backend (`backend "s3"` block,
  `use_lockfile` locking, `init -migrate-state`). **This milestone's actual
  Terraform doesn't build one** — `providers.tf` has no `backend` block at
  all (implicit local backend), and `remote-state-check/main.tf` explicitly
  uses `backend = "local"` pointed at a local file path, not an S3 key.
  That's correct, not a gap: per §3/ADR-009, Phase 1–2 deliberately stays
  on local/throwaway state — the real S3+DynamoDB backend is reserved for
  Demo 22 Part A. This milestone's S3 buckets are purely Demo 10's
  `for_each` application-bucket pattern, unrelated to Demo 01's
  state-backend content.
- **Demo 02** (Providers) — its distinguishing content is provider aliases,
  multi-region configuration, and lock-file platform hashes. This milestone
  is single-region, single (default) provider throughout — nothing in Demo
  02's specific teaching applies here.
- **Demo 04** (State Management: Import, Surgery, Recovery) — `terraform
  import`, `state mv`/`rm`, and recovery from S3-versioned backups. This
  milestone's Part 6 migration exercise uses Demo 11's `moved`-block
  mechanics, not Demo 04's state-surgery commands — genuinely different
  content, not a missed connection.

This milestone reuses **10 of the 14** Phase 1 demos (00–13) — not a
"cumulative exam of Demos 00–13" as an earlier draft overclaimed, and not
11 either (an earlier version of this table miscredited Demo 01's
state-backend content to this milestone's S3 buckets; corrected above).
The four excluded demos are named above with the specific reason each
doesn't apply, rather than left as an unexplained gap.

---

## Prerequisites

- Terraform ~> 1.15.0
- AWS CLI configured with credentials for a personal/lab AWS account
- Completed Demos 00–13
- Your own public IP, for the security group's SSH rule:
  ```bash
  curl -s https://checkip.amazonaws.com
  ```

## Directory Structure

```
cloudnova-retail-store-e2e/
├── README.md
├── docs/
│   └── Phase-1-Implementation.md        (this document)
├── src/
│   └── terraform/
│       └── phase-1/
│           ├── providers.tf
│           ├── variables.tf
│           ├── terraform.tfvars.example     # committed template
│           ├── terraform.tfvars             # your real values — gitignored, never committed
│           ├── s3.tf
│           ├── sns_sqs.tf
│           ├── cloudwatch.tf
│           ├── iam.tf
│           ├── security_group.tf
│           ├── migration.tf
│           ├── outputs.tf
│           └── remote-state-check/
│               └── main.tf
```

---

# Part 1 — Terraform Configuration

Every file below, in the order you'll actually write them. Each section
explains **what the file does and why it's shaped this way** before
showing the code — read the explanation first, since several of these
files exist specifically to work around a real Terraform constraint,
not just to organize code neatly.

### `src/terraform/phase-1/providers.tf`

Declares which providers this configuration needs and pins their
versions. Two providers, not one: `aws` for every real resource, and
`null` for the provisioner exercise in Part 1's SNS/SQS section (`null`
provides a resource type with no real infrastructure behind it — just
somewhere to attach a provisioner).

**`src/terraform/phase-1/providers.tf`:**
```hcl
terraform {
  required_version = "~> 1.15.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region # set in variables.tf, defaults to us-east-2
}
```

### `src/terraform/phase-1/variables.tf`

Three variables, and they're the reason almost every other file in this
milestone can use `for_each` instead of repeating itself three times.
`environments` is the single source map — S3, CloudWatch, and the SSM
migration all iterate over the same map, so changing it in one place
changes every dependent resource consistently.

**`src/terraform/phase-1/variables.tf`:**
```hcl
variable "environments" {
  description = "Single source map driving every for_each-based resource in this milestone"
  type = map(object({
    versioning_enabled = bool
  }))
  default = {
    dev     = { versioning_enabled = false }
    staging = { versioning_enabled = false }
    prod    = { versioning_enabled = true } # only prod keeps object version history
  }
}

variable "aws_region" {
  description = "AWS region for every resource in this milestone"
  type        = string
  default     = "us-east-2"
}

variable "allowed_ingress_cidr" {
  description = "Your own IP, as a /32 CIDR, for the security group's SSH rule"
  type        = string
  # No default on purpose — this is personal and shouldn't silently
  # default to something insecure. Set it in terraform.tfvars (see below).
}
```

### `src/terraform/phase-1/terraform.tfvars.example` (committed) and `terraform.tfvars` (local, gitignored)

Two files, not one — `terraform.tfvars` holds your real IP address,
which shouldn't be committed even to a private repo. Commit only the
`.example` template; add `terraform.tfvars` to `.gitignore` alongside
`.terraform/` and `*.tfstate*`.

**`src/terraform/phase-1/terraform.tfvars.example`:**
```hcl
allowed_ingress_cidr = "203.0.113.0/32" # replace with YOUR real IP from checkip.amazonaws.com, then copy this file to terraform.tfvars — 203.0.113.0/24 is the RFC 5737 documentation range, never a real address
```

Copy it and fill in your real value — this second file is the one
Terraform actually reads, and it stays local:

```bash
cp terraform.tfvars.example terraform.tfvars
```

**`src/terraform/phase-1/terraform.tfvars`** (gitignored, not shown here
since it holds your real IP):
```hcl
allowed_ingress_cidr = "203.0.113.42/32" # <-- your real IP here, from checkip.amazonaws.com
```

### `src/terraform/phase-1/s3.tf`

> **⚠️ The one real Terraform constraint that shapes this whole file:**
> `prevent_destroy` only accepts a **literal** `true`/`false` — never a
> computed expression like `each.key == "prod" ? true : false`.
> Terraform evaluates `lifecycle` block arguments before resource
> expansion happens, so a single `for_each`'d resource can't apply
> `prevent_destroy` conditionally to just one of its instances. That's
> why `prod` gets pulled out into its own separate resource block below
> instead of staying inside the `dev`/`staging`/`prod` loop — not a
> stylistic choice, a hard requirement.

```
              var.environments
                     │
        ┌────────────┼────────────┐
        │            │            │
     "dev"       "staging"     "prod"
        │            │            │
        ▼            ▼            ▼
  ┌───────────────────────┐  ┌──────────────────────┐
  │  aws_s3_bucket.env      │  │  aws_s3_bucket.prod    │
  │  (for_each, filtered     │  │  (separate resource,   │
  │   to exclude "prod")     │  │   literal              │
  │                           │  │   prevent_destroy=true)│
  └───────────────────────┘  └──────────────────────┘
```

**`src/terraform/phase-1/s3.tf`:**
```hcl
# dev and staging — plain for_each, no lifecycle guard. The map
# comprehension `{ for k, v in ... if k != "prod" }` filters prod out
# before the loop ever sees it.
resource "aws_s3_bucket" "env" {
  for_each = { for k, v in var.environments : k => v if k != "prod" }

  bucket = "cloudnova-${each.key}-phase1-milestone"
}

resource "aws_s3_bucket_versioning" "env" {
  for_each = { for k, v in var.environments : k => v if k != "prod" }

  bucket = aws_s3_bucket.env[each.key].id
  versioning_configuration {
    status = each.value.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# prod — pulled out of the for_each entirely, specifically so
# prevent_destroy can be the literal `true` the constraint above requires.
resource "aws_s3_bucket" "prod" {
  bucket = "cloudnova-prod-phase1-milestone"

  lifecycle {
    prevent_destroy = true # protects the literal "production" entry from an accidental destroy
  }
}

resource "aws_s3_bucket_versioning" "prod" {
  bucket = aws_s3_bucket.prod.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

**Security posture, stated rather than left unaddressed:** no explicit
`aws_s3_bucket_server_side_encryption_configuration` or
`aws_s3_bucket_public_access_block` resource is declared for any of
these buckets. This is very likely fine in practice — AWS has defaulted
new buckets to encrypted (SSE-S3) and blocked-public-access since
January 2023 — but it's worth confirming that default is actually what
you're getting (`aws s3api get-bucket-encryption` /
`get-public-access-block` in Part 3's verification) rather than assuming
it silently, given how much other attention this document pays to
state-file secrets and `.gitignore` hygiene elsewhere.

### `src/terraform/phase-1/sns_sqs.tf`

```
  aws_sns_topic          aws_sqs_queue_policy         aws_sqs_queue
  "order_events"    ──▶   (only order_events'    ──▶   "order_events"
                           ARN may publish)
        │
        │  aws_sns_topic_subscription
        └───────────────────────────────────────▶  (wires the two together)

  After apply: null_resource.verify_queue_exists runs a real
  `aws sqs get-queue-attributes` call via local-exec, proving the
  queue is real — not just that `terraform apply` said so.
```

The queue policy's `Condition` block is the part worth reading
carefully — without it, the policy would let *any* SNS topic in the
account publish to this queue, not just this one.

**`src/terraform/phase-1/sns_sqs.tf`:**
```hcl
resource "aws_sns_topic" "order_events" {
  name = "cloudnova-order-events"
}

resource "aws_sqs_queue" "order_events" {
  name                       = "cloudnova-order-events-queue"
  visibility_timeout_seconds = 30
}

# The Condition block is what actually restricts this to ONE topic.
# Without it, Principal = sns.amazonaws.com alone would let any SNS
# topic in this AWS account publish here, not just order_events.
resource "aws_sqs_queue_policy" "order_events" {
  queue_url = aws_sqs_queue.order_events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOrderEventsTopicOnly"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.order_events.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.order_events.arn }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "order_events_to_sqs" {
  topic_arn = aws_sns_topic.order_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.order_events.arn
}

# Reproduces Demo 13's provisioner pattern on this milestone's own
# resource — a real, live AWS CLI call proving the queue exists,
# not a copy of Demo 13's exact script.
resource "null_resource" "verify_queue_exists" {
  depends_on = [aws_sqs_queue.order_events]

  provisioner "local-exec" {
    command = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.order_events.id} --attribute-names QueueArn"
  }
}
```

### `src/terraform/phase-1/cloudwatch.tf`

Straightforward `for_each` over the same `environments` map — the
point of including this file is proving the map gets reused across
resource *types*, not just repeated within one type.

**`src/terraform/phase-1/cloudwatch.tf`:**
```hcl
resource "aws_cloudwatch_log_group" "env" {
  for_each = var.environments

  name              = "/cloudnova/${each.key}/app"
  retention_in_days = 14 # keeps lab cost near-zero; real retention policy is a Phase 3+ decision
}

resource "aws_cloudwatch_log_metric_filter" "env_errors" {
  for_each = var.environments

  name           = "${each.key}-error-count"
  log_group_name = aws_cloudwatch_log_group.env[each.key].name
  pattern        = "ERROR"

  metric_transformation {
    name      = "${each.key}ErrorCount"
    namespace = "CloudNova/${each.key}"
    value     = "1"
  }
}
```

### `src/terraform/phase-1/iam.tf`

```
      Trust policy                          Permission policy
  ┌───────────────────────┐            ┌──────────────────────────┐
  │ Principal:              │            │ s3:GetObject/PutObject/   │
  │  this account's root     │  role can  │  ListBucket → all 3 buckets│
  │  (broad — NOT scoped to  │  assume,   │ sns:Publish → order_events │
  │  a specific service yet) │  then...   │ logs:CreateLogStream/       │
  └───────────────────────┘            │  PutLogEvents → all 3 log   │
                                          │  groups                     │
                                          └──────────────────────────┘

  Deliberately broad. Real least-privilege scoping is Phase 3, Demo 24,
  once real per-service compute identities exist to scope policies
  against (IRSA roles on EKS, per the project's current compute design).
```

**`src/terraform/phase-1/iam.tf`:**
```hcl
data "aws_caller_identity" "current" {}

# Broad, self-trust pattern — deliberately NOT least-privilege yet.
# Don't treat this policy's breadth as a tested security boundary;
# that's Phase 3, Demo 24's job, once real per-service targets exist.
resource "aws_iam_role" "cicd" {
  name = "cloudnova-cicd-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cicd" {
  name = "cloudnova-cicd-deploy-policy"
  role = aws_iam_role.cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        # concat() combines the for_each'd bucket ARNs with prod's
        # separately-declared bucket ARN — both objects and the
        # buckets themselves need to be covered (hence the "/*" pairs).
        #
        # Acknowledged imprecision: ListBucket is a bucket-level action
        # and GetObject/PutObject are object-level actions, granted
        # together over a Resource list that mixes bucket ARNs and
        # object ARNs ("/*"). IAM tolerates this — it just means each
        # action only applies to the ARNs it actually matches — but
        # it's not clean least-privilege hygiene. Left as-is because
        # this role is deliberately broad pending Demo 24's real
        # least-privilege pass, which will split this properly; not
        # an oversight, just not fixed here.
        Resource = concat(
          [for b in aws_s3_bucket.env : b.arn],
          [for b in aws_s3_bucket.env : "${b.arn}/*"],
          [aws_s3_bucket.prod.arn],
          ["${aws_s3_bucket.prod.arn}/*"]
        )
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.order_events.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [for lg in aws_cloudwatch_log_group.env : "${lg.arn}:*"]
      }
    ]
  })
}
```

### `src/terraform/phase-1/security_group.tf`

```
  aws_security_group "milestone"  (on the DEFAULT VPC — Demo 16 changes this)
  │
  ├── dynamic "ingress"  (loops over local.ingress_rules)
  │     ├── https  → port 443, 0.0.0.0/0     (world-open, standard for HTTPS)
  │     └── ssh    → port 22,  YOUR IP only  (locked to var.allowed_ingress_cidr)
  │
  └── egress  → all ports/protocols, 0.0.0.0/0  (unrestricted outbound)
```

**`src/terraform/phase-1/security_group.tf`:**
```hcl
data "aws_vpc" "default" {
  default = true # on the default VPC by design, not oversight —
                  # real networking doesn't arrive until Phase 2, Demo 16
}

locals {
  ingress_rules = {
    https = { port = 443, cidr = "0.0.0.0/0" }
    ssh   = { port = 22, cidr = var.allowed_ingress_cidr }
  }
}

resource "aws_security_group" "milestone" {
  name        = "cloudnova-milestone-sg"
  description = "Phase 1 milestone security group on the default VPC"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = local.ingress_rules
    content {
      description = ingress.key
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = [ingress.value.cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### `src/terraform/phase-1/migration.tf`

This file has **two stages** — you write and apply stage 1 first,
confirm it's real, then replace it with stage 2. The whole exercise
only means something if the `count`-based version is genuinely applied
before you migrate it, not written and immediately replaced.

```
  STAGE 1 (count)                       STAGE 2 (for_each)
  ─────────────────                     ───────────────────
  keys(var.environments) sorted:        Same 3 real resources, now
  ["dev", "prod", "staging"]            addressed by key instead of
                                         index — moved blocks tell
  [0] = dev                             Terraform "this isn't a new
  [1] = prod                            resource, it's the same one,
  [2] = staging                         just addressed differently"

  aws_ssm_parameter.sns_topic_arn[0]  ──moved──▶  ...sns_topic_arn["dev"]
  aws_ssm_parameter.sns_topic_arn[1]  ──moved──▶  ...sns_topic_arn["prod"]
  aws_ssm_parameter.sns_topic_arn[2]  ──moved──▶  ...sns_topic_arn["staging"]
```

**Stage 1 — `src/terraform/phase-1/migration.tf` (initial version):**
```hcl
resource "aws_ssm_parameter" "sns_topic_arn" {
  count = length(keys(var.environments))

  name  = "/cloudnova/${keys(var.environments)[count.index]}/sns-topic-arn"
  type  = "String"
  value = aws_sns_topic.order_events.arn
}
```

**Stage 2 — `src/terraform/phase-1/migration.tf` (replace entirely
with this, after stage 1 is applied):**
```hcl
resource "aws_ssm_parameter" "sns_topic_arn" {
  for_each = var.environments

  name  = "/cloudnova/${each.key}/sns-topic-arn"
  type  = "String"
  value = aws_sns_topic.order_events.arn
}

# keys() returns map keys in SORTED order, so at stage 1,
# keys(var.environments) was ["dev", "prod", "staging"] — meaning
# index 0 was dev, 1 was prod, 2 was staging. These moved blocks map
# each old index to its correct new key accordingly.
moved {
  from = aws_ssm_parameter.sns_topic_arn[0]
  to   = aws_ssm_parameter.sns_topic_arn["dev"]
}
moved {
  from = aws_ssm_parameter.sns_topic_arn[1]
  to   = aws_ssm_parameter.sns_topic_arn["prod"]
}
moved {
  from = aws_ssm_parameter.sns_topic_arn[2]
  to   = aws_ssm_parameter.sns_topic_arn["staging"]
}
```

### `src/terraform/phase-1/outputs.tf`

One output, needed by the standalone remote-state check below — this
is the value that config will read back.

**`src/terraform/phase-1/outputs.tf`:**
```hcl
output "sns_topic_arn" {
  value = aws_sns_topic.order_events.arn
}
```

### `src/terraform/phase-1/remote-state-check/main.tf`

A **separate root configuration** — its own directory, own provider
block, own (tiny) state. This reproduces Demo 07's `terraform_remote_state`
exercise from scratch: read one value out of the primary build's state,
with zero ability to write back to it.

```
  phase-1/  (primary build, its own state)
     │
     │  data "terraform_remote_state"  (READ ONLY —
     │   this config never writes here)
     ▼
  remote-state-check/  (separate directory, separate state)
     └── reads phase-1's sns_topic_arn output
```

**`src/terraform/phase-1/remote-state-check/main.tf`:**
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
  region = "us-east-2" # match phase-1's aws_region
}

# Zero write access — this config only ever READS the primary build's
# state file, never modifies it.
data "terraform_remote_state" "milestone" {
  backend = "local"
  config = {
    path = "../terraform.tfstate" # adjust if phase-1 uses a remote backend instead
  }
}

output "sns_topic_arn_from_remote_state" {
  value = data.terraform_remote_state.milestone.outputs.sns_topic_arn
}
```

---

# Part 2 — Step-by-Step Execution

All commands run from `src/terraform/phase-1/` unless noted. **AWS
Console is the primary verification tool throughout this milestone —
CLI is used only where Terraform itself requires it (init/plan/apply
are inherently CLI) or where Console genuinely can't show something
Console can.** You will not need more than a handful of `aws` CLI
commands total.

### Step 1 — Initialize

```bash
terraform init
```
*What this does:* downloads the `aws` and `null` providers declared in
`providers.tf`, sets up the local backend. *Why it matters:* nothing
below works until the providers are actually present locally.

### Step 2 — Apply Parts 1 (S3) through 5 (Security Group)

Write `providers.tf`, `variables.tf`, `terraform.tfvars.example` (then
copy it to `terraform.tfvars` and fill in your real IP), `s3.tf`,
`sns_sqs.tf`, `cloudwatch.tf`, `iam.tf`, `security_group.tf` exactly as
shown in Part 1 above, then:

```bash
terraform plan
```
*What to expect:* a plan showing **20 resources to add** (2 env S3 buckets + 2 env versioning + 1 prod bucket + 1 prod versioning = 6; SNS topic + SQS queue + queue policy + subscription + null_resource = 5; 3 CloudWatch log groups + 3 metric filters = 6; IAM role + policy = 2; 1 security group = 1; total 6+5+6+2+1 = **20**), **0 to change, 0 to destroy**. Read it before applying — this is where a typo (a wrong `each.key` reference, a missing `data` block) shows up as an error before it costs you anything.

```bash
terraform apply
```
Type `yes` when prompted. *What this does:* creates every resource
above for real, in your AWS account. *Why apply, not just plan:* Pass
Criteria in Part 3 require real resources — a clean plan alone doesn't
satisfy anything.

### Step 3 — Migration exercise, stage 1

Add `migration.tf` with the **`count`-based** version shown in Part 1.

```bash
terraform apply
```

Confirm index-based addressing:
```bash
terraform state list | grep sns_topic_arn
```
Expected:
```
aws_ssm_parameter.sns_topic_arn[0]
aws_ssm_parameter.sns_topic_arn[1]
aws_ssm_parameter.sns_topic_arn[2]
```

### Step 4 — Migration exercise, stage 2

Replace `migration.tf`'s entire contents with the **`for_each` +
`moved`** version shown in Part 1.

```bash
terraform plan
```
*What to expect:* **zero resources to add or destroy** — only address
moves. If you see any `+`/`-` instead, stop: it means a `moved` block's
`from`/`to` pairing is wrong, most likely the index-to-key mapping.
Fix it before applying.

**Why this matters, stated concretely rather than left implicit:**
without the `moved` blocks, Terraform has no way to know
`aws_ssm_parameter.sns_topic_arn[0]` and
`aws_ssm_parameter.sns_topic_arn["dev"]` are the same underlying object
under a new address — it would see three index-addressed resources
disappear and three key-addressed ones appear, and plan a destroy +
recreate of all three SSM parameters. For a throwaway SSM parameter
that's a nuisance; picture the same addressing change made against
Demo 26's RDS instance instead, and "zero add/destroy" stops being a
nice-to-have and becomes the difference between a clean migration and
a real, avoidable data-loss event. That's the actual stake this
exercise is teaching, not just the mechanical pass/fail of the plan
output.

```bash
terraform apply
terraform state list | grep sns_topic_arn
```
Expected — key-based addressing has replaced index-based:
```
aws_ssm_parameter.sns_topic_arn["dev"]
aws_ssm_parameter.sns_topic_arn["prod"]
aws_ssm_parameter.sns_topic_arn["staging"]
```

### Step 5 — Add the output, re-apply

Add `outputs.tf` as shown in Part 1.

```bash
terraform apply
```
*What this does:* this only adds an output value, no resources change
— confirms `Plan: 0 to add, 0 to change, 0 to destroy` with just the
new output appearing.

### Step 6 — Standalone remote-state check

```bash
mkdir remote-state-check && cd remote-state-check
```
Write `main.tf` as shown in Part 1.
```bash
terraform init
terraform apply
```
*What this does:* stands up a second, completely separate Terraform
state that reads (never writes) the primary build's `sns_topic_arn`
output. *Why it matters:* proves you can reproduce Demo 07's exercise
from scratch, on your own resource, not just recall how it worked.

---

# Part 3 — Verification

## Pass Criteria

**⚠️ These numeric thresholds are proposed, not yet confirmed against
your specific setup or reviewed by you.**

| # | Component | Threshold |
|---|---|---|
| 1 | S3 buckets | 3 buckets exist (`dev`/`staging`/`prod`), versioning enabled per environment's config |
| 2 | SNS → SQS | A message published to the topic is confirmed delivered to the queue |
| 3 | CloudWatch | 3 log group + metric filter pairs exist, one per environment |
| 4 | IAM role | Role exists, trust policy scoped to this account only (no `*` principal), permission policy attached |
| 5 | Security group | 2 dynamic ingress rules present (HTTPS, SSH) |
| 6 | `prevent_destroy` | Confirmed blocking — a destroy attempt without removing the lifecycle block fails |
| 7 | `count`→`for_each` migration | State shows key-based addressing; the stage-2 plan showed zero destroy/recreate |
| 8 | Provisioner | `local-exec` ran during apply and its AWS CLI output confirmed the queue's real state |
| 9 | Remote state read | Second root config successfully read the primary build's output, zero write access |

### Verification steps — AWS Console first, CLI only where required

**#1 — S3 buckets.** Console → S3 → confirm `cloudnova-dev-phase1-milestone`,
`cloudnova-staging-phase1-milestone`, `cloudnova-prod-phase1-milestone`
all exist. Click each bucket → **Properties** tab → **Bucket
Versioning** → confirm `prod` shows **Enabled**, `dev`/`staging` show
**Suspended**. Same **Properties** tab → confirm **Default
encryption** shows enabled (SSE-S3) and the **Permissions** tab shows
**Block all public access** on — this project didn't declare either
explicitly (see the s3.tf note above), so this confirms the AWS-default
posture is actually what got applied, not just assumed.

**#2 — SNS → SQS delivery.** Console → SNS → `cloudnova-order-events`
topic → **Publish message** button → send any test message body →
Console → SQS → `cloudnova-order-events-queue` → **Send and receive
messages** → **Poll for messages** → confirm your test message appears.
Entirely Console-based, no CLI needed.

**#3 — CloudWatch.** Console → CloudWatch → **Log groups** → confirm
`/cloudnova/dev/app`, `/cloudnova/staging/app`, `/cloudnova/prod/app`
all exist. For one of them: **Actions** → create a test log stream and
put a log event containing the word `ERROR` (or use **Metric Filters**
tab → **Test pattern** with a sample line containing `ERROR`) → confirm
the filter matches.

**#4 — IAM role.** Console → IAM → **Roles** → `cloudnova-cicd-deploy-role`
→ **Trust relationships** tab → confirm the principal is this account's
root ARN only, not `"*"`. **Permissions** tab → confirm
`cloudnova-cicd-deploy-policy` is attached.

**#5 — Security group.** Console → EC2 → **Security Groups** →
`cloudnova-milestone-sg` → **Inbound rules** tab → confirm 2 rules:
port 443 from `0.0.0.0/0`, port 22 from your `/32` CIDR only.

**#6 — `prevent_destroy`.** CLI required here — this specifically tests
Terraform's own behavior, which Console can't show:
```bash
terraform destroy -target=aws_s3_bucket.prod
```
Expected: Terraform refuses, with an error naming `prevent_destroy`.
This is the correct, passing result — don't remove the lifecycle block
to make this succeed; that's only for the real Teardown in Part 4.

**#7 — Migration.** Already verified in Part 2, Step 4's `terraform
state list` output — key-based addressing, zero destroy/recreate on
the stage-2 plan.

**#8 — Provisioner.** Look back at your `terraform apply` output from
Part 2, Step 2 — the `null_resource.verify_queue_exists` resource's
provisioner output should show real JSON from `aws sqs
get-queue-attributes`, including a real `QueueArn`.

**#9 — Remote state read.** Already verified in Part 2, Step 6's
`terraform apply` output — a real ARN printed back, zero resources
created in that second directory.

## Results

*(Fill in after running every verification step above.)*

| # | Component | Result |
|---|---|---|
| 1 | S3 buckets | ☐ Pass ☐ Fail |
| 2 | SNS → SQS | ☐ Pass ☐ Fail |
| 3 | CloudWatch | ☐ Pass ☐ Fail |
| 4 | IAM role | ☐ Pass ☐ Fail |
| 5 | Security group | ☐ Pass ☐ Fail |
| 6 | `prevent_destroy` | ☐ Pass ☐ Fail |
| 7 | Migration | ☐ Pass ☐ Fail |
| 8 | Provisioner | ☐ Pass ☐ Fail |
| 9 | Remote state read | ☐ Pass ☐ Fail |

---

# Part 4 — Teardown and Confirm

Complete in this exact order — `prevent_destroy` requires a config edit
before anything can be destroyed at all.

**1. Remove the destroy guard.** In `s3.tf`, either delete the
`lifecycle` block on `aws_s3_bucket.prod` or set
`prevent_destroy = false`.

**2. Destroy the remote-state check first** — no dependents:
```bash
cd remote-state-check
terraform destroy
cd ..
```

**3. Destroy the primary build:**
```bash
terraform destroy
```

**4. Confirm via Console, not just CLI exit code.** Check S3, SNS, SQS,
CloudWatch Log Groups, IAM Roles, and EC2 Security Groups — confirm
nothing from this milestone remains in any of them.

**5. Check for orphans outside Terraform's state.** As a general habit,
don't rely solely on `terraform destroy`'s exit code — check the Console
directly for S3, SNS, SQS, CloudWatch Log Groups, IAM Roles, and EC2
Security Groups. (An earlier version of this note asserted that
CloudWatch Logs specifically retains log streams briefly after its log
group is deleted — that's not standard, documented AWS behavior, and
wasn't independently verified, so it's been removed rather than stated
as settled fact. The console-check habit itself is still worth keeping,
just not for that specific claimed reason.)

**Cost, stated explicitly rather than silently omitted:** every resource
in this milestone is free or negligible-cost at this scale (S3, SNS/SQS,
CloudWatch at low volume, IAM, a security group, SSM parameters — all
within AWS free tier or near-$0). No cost table is included for that
reason. Real, non-trivial cost begins at Phase 3, Demo 22 Part A, where
`Solution-Architecture.md` §5's cost table and Budgets alarm apply.

**Naming convention continuity — narrowed since Demo 19:** every
resource here is prefixed `cloudnova-*`. Demo 19 has since settled this
for ECR specifically (`cloudnova-retail-<service>`, all 5 repos, built
and confirmed). Still not decided: EKS cluster/node and RDS/DynamoDB
naming for Phase 3 — worth deciding before Demo 22 Part B locks in a
scheme (Part A's bootstrap resources don't depend on this).

---

## What's Next

Phase 2 (Demos 14–21) introduces **modules** — this same
environments-map / S3 / SNS / CloudWatch / IAM pattern set gets rebuilt
as reusable local and registry modules, starting Demo 14.

**Hard prerequisite for Phase 3:** Demo 16 (VPC Module) is the first
point real networking exists in this series. This milestone's security
group deliberately stayed on the default VPC — Phase 2, Demo 16 is
where that changes, and Phase 3, Demo 22 is where compute (EKS, Auto
Mode — the project's compute target as of the ADR-019 swap; ECS
Fargate now appears later, at Demo 29, as a time-boxed comparison)
and the persistent-build environment actually begin.

No component built in this milestone is wasted: the S3 buckets, SNS
pipeline, CloudWatch scaffolding, and IAM pattern all get real
consumers starting Phase 3, per `Solution-Architecture.md`'s target
architecture, once compute and the real app enter the curriculum.