# Demo 13 — Provisioners

---

## Overview

Every resource this series has built has been fully described
declaratively — Terraform tells AWS what should exist, and AWS handles
making it so. Sometimes that's not enough: CloudNova occasionally needs
to run an imperative script tied to a resource's creation or
destruction — writing a local audit record when a role is created,
running cleanup logic when a queue is destroyed. **Provisioners** are
Terraform's escape hatch for exactly this — and this demo's real
teaching point is as much about when *not* to reach for them as how
they work.

**Real-world scenario — CloudNova:** the platform team wants a local
audit log entry written the moment the deploy role is created (for
their own tracking, outside AWS entirely), and a cleanup message logged
locally when a queue is destroyed — before reaching for a provisioner
for anything more, this demo makes the case for exactly when that's
actually justified.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — local-exec on Creation                                        │
│  Write a local audit record the moment the IAM role is created          │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — local-exec with when = destroy                                │
│  Log a cleanup message when a queue is destroyed — provisioners tied    │
│  to destruction, not creation                                            │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — The Decision Framework: Provisioners as a Last Resort         │
│  When a provisioner is genuinely justified vs. when it's covering for   │
│  a missing Terraform-native feature   |   remote-exec's real            │
│  requirements, shown without needing live compute                       │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- `provisioner "local-exec"` — running a command on the machine
  running Terraform, tied to a resource's creation
- `when = destroy` provisioners — running a command tied to a
  resource's destruction instead
- `remote-exec` — what it requires (a `connection` block, real compute)
  and why it isn't demonstrated live in this series
- The decision framework: provisioners as a documented last resort, not
  a general-purpose scripting mechanism

**What this demo does NOT cover:** this is the final demo in
Phase 1 - Foundations. Phase 2 moves into modules — reusable,
parameterized Terraform configuration units.

---

## How This Demo's Pieces Fit Together

**This demo builds no connected AWS solution** — like Demos 11 and 12,
each Part demonstrates one provisioner concept independently. What
connects them is the decision framework itself: every provisioner in
this demo does something that has **no Terraform-native alternative**
(writing to a local file outside any AWS resource's own state) —
that's deliberate, since it's the one category where a provisioner is
actually the right tool. Part C makes this explicit by walking through
scenarios where a provisioner is *not* the right tool, because a native
`lifecycle` argument (Demo 12) or resource argument already solves the
same problem better.

---

## Prerequisites

### Knowledge
- Demo 12 completed — the `lifecycle` meta-argument, particularly
  `create_before_destroy` and `replace_triggered_by`, since Part C
  contrasts provisioners against lifecycle-based alternatives directly

### Required Tools

Same as Demos 05–12 — Terraform `>= 1.15.0`, AWS CLI `>= 2.x`, `jq`.

### Verify AWS Account and Permissions

```bash
aws sts get-caller-identity --profile default
aws configure get region --profile default
```

**Required permissions for this demo:**

```
iam:CreateRole, iam:DeleteRole, iam:GetRole
sqs:CreateQueue, sqs:DeleteQueue, sqs:GetQueueAttributes
```

> For a learning account, `IAMFullAccess` and `AmazonSQSFullAccess`
> managed policies cover the permissions above.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Use `provisioner "local-exec"` to run a command on the machine
   running Terraform, tied to a resource's creation
2. ✅ Use `when = destroy` to run a provisioner tied to a resource's
   destruction instead of its creation
3. ✅ Explain what `remote-exec` requires and why it needs a
   `connection` block and real compute to function
4. ✅ Apply the decision framework for when a provisioner is genuinely
   justified versus when a Terraform-native feature already solves the
   same problem

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| IAM role (×1) | Always free | **$0.00** | |
| SQS queue (×1) | Free forever — 1M requests/month | **$0.00** | |
| **Session total** | | **$0.00** | |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
13-provisioners/
├── README.md
├── 13-provisioners-anki.csv
├── 13-provisioners-quiz.md
└── src/
    ├── 01-versions.tf       # terraform block + provider version constraints
    ├── 02-provider.tf       # AWS provider: region, profile
    ├── 03-variables.tf      # role name, queue name, audit log path
    ├── 04-role-provisioner.tf   # local-exec on creation
    ├── 05-queue-provisioner.tf  # local-exec with when = destroy
    ├── 06-outputs.tf        # exposes what was built
    └── break-fix/
        └── broken.tf
```

---

## Recall Check — Demo 12

Answer from memory before reading further:

1. What plan symbol does `create_before_destroy = true` produce for a
   forced replacement, instead of the default?
2. Does `prevent_destroy = true` stop a resource from being deleted
   directly in the AWS Console?
3. What does `replace_triggered_by` actually watch, and what does it
   do when that changes?

**Answers**

1. `+/-` (create then destroy) — reversing the default `-/+` (destroy
   then create), so there's a brief overlap instead of a gap where
   neither instance exists.
2. No — `prevent_destroy` is a Terraform-only guard. It blocks
   `terraform destroy` and block-removal, but has zero effect on
   deletions made outside Terraform entirely.
3. A specific attribute reference on a *different* resource (e.g.
   `aws_iam_role.deploy.arn`). When that attribute's value changes,
   the resource with `replace_triggered_by` is replaced too — even
   though nothing about its own arguments changed.

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `provisioner "local-exec"` | Resource sub-block | Runs a command on the machine running Terraform |
| `when = destroy` | Provisioner argument | Ties a provisioner to destruction instead of creation |
| `provisioner "remote-exec"` | Resource sub-block | Runs a command on the remote resource itself — requires a `connection` block |
| `connection` block | Provisioner sub-block | Specifies how Terraform connects to the remote resource (SSH/WinRM details) |

**Related constructs worth knowing (not covered in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| `lifecycle` meta-argument | Overriding default create/update/destroy behavior | Demo 12 |
| Modules | Reusable, parameterized configuration units | Phase 2 |

---

### Detailed Explanation of New Constructs

#### `provisioner "local-exec"` — Running a Command on the Terraform Machine

```hcl
resource "aws_iam_role" "deploy" {
  name               = var.role_name
  assume_role_policy = local.trust_policy

  provisioner "local-exec" {
    command = "echo \"Role ${self.name} created at $(date -u)\" >> ${var.audit_log_path}"
  }
}
```

**What it does:** after the resource is successfully created, Terraform
runs the given command on the machine actually running `terraform
apply` — not on any AWS resource, not remotely. `self.name` refers to
this same resource's own `name` attribute, available inside a
provisioner block attached to that resource.

> **`local-exec` runs on your machine, never on AWS.** There's no
> concept of "the resource executing something" here — the queue,
> role, or bucket is completely passive; the command runs wherever
> Terraform itself is running (your laptop, a CI runner, etc.).

---

#### `when = destroy` — Provisioners Tied to Destruction

```hcl
resource "aws_sqs_queue" "notifications" {
  name = var.queue_name

  provisioner "local-exec" {
    when    = destroy
    command = "echo \"Queue ${self.name} destroyed at $(date -u)\" >> ${var.audit_log_path}"
  }
}
```

By default, a provisioner runs on **creation**. `when = destroy` flips
this — the command runs instead when the resource is being destroyed,
using the resource's last-known state (`self.name` here still resolves
correctly, since Terraform runs destroy-time provisioners before
actually removing the resource from AWS).

> **Destroy-time provisioners run before the resource is actually
> destroyed, using its last-known attributes.** If Terraform couldn't
> read `self.name` after destruction, this wouldn't be possible at
> all — the ordering (provisioner, then real destroy) is what makes it
> work.

---

#### `remote-exec` — What It Requires, and Why It's Not Demonstrated Live

```hcl
# Illustrative only — this requires a real EC2 instance with SSH
# access, which is out of scope for Phase 1 - Foundations
resource "aws_instance" "example" {
  # ... AMI, instance type, etc. — Phase 3 territory

  provisioner "remote-exec" {
    inline = ["sudo yum install -y nginx"]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("~/.ssh/id_rsa")
      host        = self.public_ip
    }
  }
}
```

**What it requires:** `remote-exec` runs commands *on* the resource
itself (an EC2 instance, typically) rather than on the machine running
Terraform — which means it needs a `connection` block specifying how
to actually reach that resource (SSH details, a private key, the
resource's own IP address). This demo doesn't build a real EC2 instance
(compute is Phase 3's territory), so `remote-exec` is shown here only
as a labeled illustration — the syntax and requirements are real, but
this code is never applied in this demo's lab.

> **`remote-exec` needs the target resource to already be reachable.**
> A `connection` block requires real network access and credentials to
> the resource — this is exactly why `remote-exec` doesn't make sense
> for a resource type like an SQS queue or S3 bucket; there's nothing
> to "connect to" on them at all. It only applies to compute resources
> that can actually run commands, like EC2 instances.

---

#### Provisioners as a Last Resort — The Decision Framework

Terraform's own documentation is explicit that provisioners are a last
resort — most needs that look like "run a script when this resource
changes" already have a better, Terraform-native answer:

| Need | Reach for a provisioner? | Better alternative |
|---|---|---|
| Bootstrap software on a new EC2 instance | Sometimes, but... | User data (`user_data` argument) is usually preferred — no SSH dependency, runs at boot |
| Tag a resource with metadata | No | Just use the `tags` argument directly |
| Rebuild a resource when another one changes | No | `lifecycle.replace_triggered_by` (Demo 12) |
| Write a local audit record outside any AWS resource's own state | **Yes** — this demo's actual use case | No Terraform-native equivalent exists for "write to a local file on the machine running Terraform" |
| Run cleanup logic when a resource is destroyed | Sometimes — narrow local-only cases | For anything AWS-side, prefer an AWS-native mechanism (e.g., an S3 lifecycle policy, an EventBridge rule) over a destroy-time provisioner |

> **The pattern to notice:** every genuinely-justified case in this
> table is about the **local machine running Terraform**, not about
> AWS itself. The moment a "provisioner need" is actually about AWS
> resource behavior, there's almost always a Terraform-native argument
> or AWS-native feature that does the same job more reliably —
> provisioners aren't tracked in state the way resource arguments are,
> and don't participate in `plan`'s diffing at all.

---

## Lab Step-by-Step Guide

---

## Part A — local-exec on Creation

**What you accomplish in Part A:** create an IAM role with a
`local-exec` provisioner that writes an audit record to a local file
the moment the role is created.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-1-foundations/13-provisioners/src
```

### Step 2 — Create the source files

---

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

---

#### `02-provider.tf` — AWS provider configuration

**02-provider.tf:**

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
```

---

#### `03-variables.tf` — Inputs for all three Parts

**What this file does in this demo:** `audit_log_path` is shared by
both Part A and Part B's provisioners — the same local file
accumulates both a creation record and a destruction record.

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

variable "role_name" {
  type        = string
  description = "Name of the IAM role provisioned with a local-exec audit record"
  default     = "cloudnova-provisioner-demo-role"
}

variable "queue_name" {
  type        = string
  description = "Name of the SQS queue provisioned with a destroy-time local-exec record"
  default     = "cloudnova-provisioner-demo-queue"
}

variable "audit_log_path" {
  type        = string
  description = "Local file path both provisioners append audit records to"
  default     = "/tmp/cloudnova-audit.log"
}
```

---

#### `04-role-provisioner.tf` — IAM role with a creation-time local-exec

**What this file does in this demo:** the `provisioner` block is the
entire subject of Part A — everything else in this resource is a
standard IAM role, unchanged from earlier demos' pattern.

**04-role-provisioner.tf:**

```hcl
resource "aws_iam_role" "deploy" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAssumeRole"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::163125980376:root" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    ManagedBy = "terraform-demo-13"
  }

  provisioner "local-exec" {
    command = "echo \"[$(date -u +%FT%TZ)] Role ${self.name} created\" >> ${var.audit_log_path}"
  }
}
```

---

### Step 3 — Apply and confirm the audit record

```bash
terraform init
terraform validate
terraform apply
```

Expected: the `local-exec` provisioner's output appears inline with
the rest of the `apply` output, distinctly labeled:

```
aws_iam_role.deploy: Creating...
aws_iam_role.deploy: Provisioning with 'local-exec'...
aws_iam_role.deploy (local-exec): Executing: ["/bin/sh" "-c" "echo ..."]
aws_iam_role.deploy: Creation complete after 1s [id=cloudnova-provisioner-demo-role]
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

```bash
cat /tmp/cloudnova-audit.log
```

Expected: `[<timestamp>] Role cloudnova-provisioner-demo-role created`

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

**Verify:**

```
Console → IAM → Roles → cloudnova-provisioner-demo-role
  → exists — confirms the AWS resource creation succeeded independently
    of whether the local-exec command itself succeeded ✅
```

> **If `local-exec`'s command fails, the resource is still considered
> created** (unless `on_failure = fail` is explicitly set, which is
> the default — a failing creation-time provisioner actually **does**
> fail the whole `apply` by default). Confirm the distinction is real:
> a *destroy-time* provisioner failing has different implications,
> covered in Part B.

---

## Part B — local-exec with when = destroy

**What you accomplish in Part B:** create an SQS queue with a
destroy-time `local-exec` provisioner, then destroy it and confirm the
cleanup record was written before the queue actually disappeared.

### Step 1 — Create `05-queue-provisioner.tf`

**What this file does in this demo:** `when = destroy` is this Part's
entire subject — the provisioner never runs at creation, only when
this specific resource is later destroyed.

Create a file **05-queue-provisioner.tf** and add the below content:

```hcl
resource "aws_sqs_queue" "notifications" {
  name = var.queue_name

  tags = {
    ManagedBy = "terraform-demo-13"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "echo \"[$(date -u +%FT%TZ)] Queue ${self.name} destroyed\" >> ${var.audit_log_path}"
  }
}
```

### Step 2 — Apply, then destroy this one resource and confirm the record

```bash
terraform apply
```

Confirm the audit log does **not** yet contain a destruction record —
only Part A's creation record:

```bash
cat /tmp/cloudnova-audit.log
```

```bash
terraform destroy -target=aws_sqs_queue.notifications
```

Expected:

```
aws_sqs_queue.notifications: Destroying... [id=...]
aws_sqs_queue.notifications: Provisioning with 'local-exec'...
aws_sqs_queue.notifications (local-exec): Executing: ["/bin/sh" "-c" "echo ..."]
aws_sqs_queue.notifications: Destruction complete after 1s
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

```bash
cat /tmp/cloudnova-audit.log
```

Expected: now contains **both** records — Part A's creation line and
this Part's destruction line.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **The provisioner ran *before* "Destruction complete."** This
> confirms `self.name` was still readable at the moment the command
> ran — Terraform executes destroy-time provisioners while the
> resource's last-known state is still available, then proceeds with
> the actual AWS-side deletion.

**Verify:**

```
Console → SQS → Queues
  → cloudnova-provisioner-demo-queue is gone ✅
```

---

## Part C — The Decision Framework: Provisioners as a Last Resort

**What you accomplish in Part C:** apply the decision framework from
Concepts to three new scenarios, and confirm you can distinguish a
genuinely-justified provisioner use from one that's covering for a
missing Terraform-native feature.

### Step 1 — Apply the decision framework to three new scenarios

| Scenario | Provisioner justified? | Better alternative, if any |
|---|---|---|
| Send a Slack notification from your local machine when a critical resource is destroyed | Yes — this is genuinely local-machine-only, no AWS-native equivalent | None — this is a legitimate `local-exec` (`when = destroy`) use case |
| Install a specific application version on a new EC2 instance at boot | Not ideally | `user_data` — runs at boot without needing SSH/`connection` at all |
| Force a cache-clearing dependent resource to rebuild whenever a source S3 object changes | No | `lifecycle.replace_triggered_by` (Demo 12) referencing the object's `etag` |

### Step 2 — Confirm your understanding with a quick self-check

Before moving to Phase 2, make sure you can answer: why does every
genuinely-justified provisioner use case in this demo involve the
*local machine running Terraform*, never AWS resource behavior itself?
(Answer: because Terraform has no native mechanism for "run something
on my own machine" outside a provisioner — but it has native
mechanisms for nearly everything AWS-side, which is why AWS-side needs
almost always have a better alternative.)

---

## Cleanup

```bash
terraform destroy
```

Type `yes`. Expected: `Destroy complete! Resources: 1 destroyed.` (the
IAM role — the queue was already destroyed individually in Part B).

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

```bash
aws iam get-role --role-name cloudnova-provisioner-demo-role --profile default --region us-east-2
rm -f /tmp/cloudnova-audit.log
```

Expected: the `get-role` command returns a "not found" error; the
audit log file is removed.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## What You Learned

1. ✅ `provisioner "local-exec"` runs a command on the machine running
   Terraform, tied to a resource's creation by default
2. ✅ `when = destroy` ties a provisioner to a resource's destruction
   instead — running before the resource is actually removed, while
   its last-known state (`self.*`) is still readable
3. ✅ `remote-exec` requires a `connection` block and real, reachable
   compute — it has no meaningful use on resource types like SQS
   queues or S3 buckets
4. ✅ Nearly every AWS-side need that looks like "run a script when
   this changes" has a better, Terraform-native alternative
   (`user_data`, `lifecycle.replace_triggered_by`) — provisioners are
   genuinely justified almost exclusively for local-machine-only needs

---

## Cert Tips — TA-004 Objectives Covered

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `provisioner "local-exec"` | TA-004 Obj (provisioners) | Know it runs on the Terraform machine, never on AWS |
| `when = destroy` | TA-004 Obj (provisioners) | Tests understanding that this runs before actual destruction, using last-known state |
| `remote-exec` + `connection` block | TA-004 Obj (provisioners) | Know the `connection` block is required, and why it doesn't apply to non-compute resources |
| Provisioners as last resort | TA-004 Obj (provisioners) | Frequently tested — expect a scenario asking for the *better* Terraform-native alternative |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam asks where a `local-exec` provisioner's command actually runs | Recognizing it runs on the machine executing Terraform, never on any AWS resource | Assuming it runs "on" the resource itself, the way `remote-exec` does |
| Exam shows a scenario for bootstrapping software on a new EC2 instance | Recognizing `user_data` is generally preferred over `remote-exec` | Assuming a provisioner is always the correct tool for instance bootstrapping |
| Exam asks what's required for `remote-exec` to function | Recognizing a `connection` block (with real reachability) is mandatory | Assuming `remote-exec` works the same way as `local-exec`, with no extra requirements |

### Exam Task — Write a complete configuration

**Task:** CloudNova needs an IAM role that writes a local audit record
on creation, and a separate SQS queue that writes a different local
audit record when destroyed. Write both from scratch.

**Block types required:** `resource` (×2), `provisioner` (×2, one
default/creation-time, one `when = destroy`)

**Official documentation:**
- [Provisioners](https://developer.hashicorp.com/terraform/language/resources/provisioners/syntax)

**What to practise:**
1. Open the Provisioners page — confirm the default `on_failure`
   behavior for a creation-time provisioner
2. Write both resources from scratch without looking at this demo's
   `.tf` files
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
resource "aws_iam_role" "audit_demo" {
  name               = "cloudnova-audit-demo-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [] })

  provisioner "local-exec" {
    command = "echo \"Role ${self.name} created\" >> /tmp/audit.log"
  }
}

resource "aws_sqs_queue" "audit_demo" {
  name = "cloudnova-audit-demo-queue"

  provisioner "local-exec" {
    when    = destroy
    command = "echo \"Queue ${self.name} destroyed\" >> /tmp/audit.log"
  }
}
```

**Arguments you must know without looking up:**
- Default `on_failure` behavior for a creation-time provisioner is
  `fail` — a failing provisioner fails the whole `apply`, unless
  `on_failure = continue` is explicitly set
- `when = destroy` is the only argument needed to flip a provisioner
  from creation-time to destroy-time

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `apply` fails even though the AWS resource shows as created | A creation-time `local-exec` command itself failed, and default `on_failure = fail` applies | Fix the command, or explicitly set `on_failure = continue` if the provisioner's success genuinely shouldn't block the resource |
| A destroy-time provisioner's `self.*` reference returns empty/unknown | Referencing an attribute that wasn't set or known at the time of destruction | Only reference attributes that were genuinely part of the resource's last-known state |
| `remote-exec` never connects | Missing or incorrect `connection` block, or the target resource isn't actually reachable (no public IP, wrong security group) | Confirm the `connection` block's `host`/credentials are correct, and that network access genuinely exists |

---

## Break-Fix Scenario

Three deliberate errors, all provisioner-specific. Diagnose using
`terraform validate`/`plan` — do not look at answers first.

```bash
cd src/break-fix/
terraform init
terraform validate
terraform plan
```

#### `broken.tf` — Three deliberate provisioner errors

**What this file does in this demo:** a self-contained configuration
with a `remote-exec` provisioner missing its required `connection`
block, a destroy-time provisioner referencing an attribute that
doesn't exist on the resource, and a `local-exec` command with a
shell-syntax error — diagnose all three.

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

resource "aws_sqs_queue" "broken_one" {
  name = "cloudnova-broken-queue-one"

  # Error 1: remote-exec with no connection block at all
  provisioner "remote-exec" {
    inline = ["echo hello"]
  }
}

resource "aws_sqs_queue" "broken_two" {
  name = "cloudnova-broken-queue-two"

  provisioner "local-exec" {
    when    = destroy
    command = "echo \"Queue ${self.nonexistent_attribute} destroyed\"" # Error 2
  }
}

resource "aws_sqs_queue" "broken_three" {
  name = "cloudnova-broken-queue-three"

  provisioner "local-exec" {
    command = "echo \"Created\" >> /tmp/audit.log && && echo done" # Error 3 — double &&
  }
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — `remote-exec` with no `connection` block**
`remote-exec` needs to know how to reach the target — without a
`connection` block, Terraform has no host, credentials, or protocol to
use. This fails at `apply` time (SQS queues aren't even a valid target
for `remote-exec` regardless, since they have nothing to connect to)
— the missing `connection` block is the immediate, structural problem.
Fix: either remove the `remote-exec` provisioner (SQS queues can't be
`remote-exec` targets at all), or, for a genuinely connectable resource
like an EC2 instance, add a complete `connection` block.

**Error 2 — referencing a nonexistent attribute via `self`**
`self.nonexistent_attribute` isn't a real exported attribute of
`aws_sqs_queue`. `terraform validate` errors that this attribute
doesn't exist on the resource. Fix: reference a real attribute, e.g.
`self.name` or `self.id`.

**Error 3 — shell syntax error in the command string**
`&& &&` (doubled) is invalid shell syntax — the command itself would
fail when executed, not at Terraform's own validation stage (Terraform
doesn't parse the *contents* of the `command` string, only that it's a
valid string). This surfaces as an execution failure during `apply`,
not a `validate`-time error. Fix: correct the shell syntax —
`&&` once, not twice.

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

**Q1. A teammate wants to use `remote-exec` to install software on a new EC2 instance at launch. What would you suggest instead, and why?**
`user_data` is generally the better choice — it runs at boot time, requires no SSH connectivity or `connection` block, and doesn't depend on the instance being reachable from wherever Terraform happens to be running. `remote-exec` introduces a real dependency (network access, credentials) that `user_data` avoids entirely, for a need that AWS already has a native mechanism for.

**Q2. Why does `local-exec` make sense for a local audit log, but not for something like tagging a resource?**
`local-exec` is genuinely necessary when the need is about the machine running Terraform itself — writing to a local file has no Terraform-native equivalent. Tagging a resource, by contrast, is something Terraform already has a first-class mechanism for (the `tags` argument) — reaching for a provisioner there would just be reimplementing something that already exists, and worse, tags set via a provisioner wouldn't be tracked in state the way the `tags` argument's values are.

**Q3. What happens if a creation-time `local-exec` provisioner's command fails?**
By default (`on_failure = fail`), the entire `apply` fails — the resource is left tainted, and Terraform treats the operation as unsuccessful even though the underlying AWS resource may have been created successfully. This is worth knowing precisely because it means a provisioner's own reliability becomes part of the resource's effective reliability, unless `on_failure = continue` is explicitly set to decouple them.

---

## Key Takeaways

1. **`local-exec` runs on the machine running Terraform, never on
   AWS.** There's no "the resource executes something" — the resource
   itself stays completely passive.

2. **`when = destroy` runs before the resource is actually removed**,
   using its last-known state — this is what makes `self.*` references
   still work at destroy time.

3. **`remote-exec` requires a `connection` block and real,
   reachable compute.** It has no meaningful application to resource
   types that aren't actual compute (SQS, S3, IAM all have nothing to
   "connect to").

4. **Nearly every AWS-side "run a script when this changes" need has a
   better, Terraform-native alternative.** `user_data` for bootstrap,
   `lifecycle.replace_triggered_by` for forced rebuilds. Provisioners
   earn their place almost exclusively for local-machine-only needs.

> **Demo scope:** Primary concept: provisioners (`local-exec`,
> `remote-exec`) and the decision framework for when they're genuinely
> justified. Supporting concepts: `when = destroy`, the `connection`
> block's requirements, and contrasting provisioners against
> Terraform-native alternatives from Demo 12.
> Estimated completion time: 30 minutes (reading + hands-on + verification).
> Checkpoints: 3 natural stopping points (end of Part A, end of Part B,
> end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform destroy -target=ADDRESS` | Destroys one specific resource, useful for observing its destroy-time provisioner in isolation |
| `cat /tmp/cloudnova-audit.log` | Confirms what a `local-exec` provisioner actually wrote |

---

## Next Demo

**Phase 2 begins — Demo 14, Modules Basics.** This closes out
Phase 1 - Foundations. Phase 2 moves into building and consuming
reusable, parameterized Terraform configuration units.

---

## Appendix — Anki Cards

**13-provisioners-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 1 - Foundations::13-provisioners
#separator:Comma
#columns:Front,Back,Tags
"Where does a local-exec provisioner's command actually run?","On the machine running Terraform itself (your laptop, a CI runner) — never on any AWS resource. The resource stays completely passive; there is no concept of 'the resource executing something.'","demo13,local-exec,ta004"
"What does when = destroy change about a provisioner's default behavior?","By default a provisioner runs on resource creation. when = destroy flips this — the command runs instead when the resource is being destroyed, using the resource's last-known state (self.* references still resolve).","demo13,destroy-time,ta004"
"Does a destroy-time provisioner run before or after the resource is actually removed from AWS?","Before — Terraform executes the provisioner while the resource's last-known attributes are still available, then proceeds with the actual AWS-side deletion afterward.","demo13,destroy-time,ordering"
"What does remote-exec require that local-exec does not?","A connection block — remote-exec runs commands ON the target resource itself, so it needs real network reachability and credentials (SSH/WinRM details) to get there. local-exec never needs this since it runs locally.","demo13,remote-exec,ta004"
"Why doesn't remote-exec make sense on an SQS queue or S3 bucket?","Because remote-exec requires something to connect to and run commands on — SQS queues and S3 buckets have no compute, no SSH access, nothing for a connection block to reach. remote-exec only applies to actual compute resources like EC2 instances.","demo13,remote-exec,decision"
"What is generally preferred over remote-exec for bootstrapping software on a new EC2 instance?","user_data — it runs at boot time without requiring SSH connectivity or a connection block, and doesn't depend on the instance being reachable from wherever Terraform happens to be running.","demo13,decision,user-data"
"What happens by default if a creation-time local-exec provisioner's command fails?","The entire apply fails (default on_failure = fail) — the resource may have been created in AWS, but Terraform treats the whole operation as unsuccessful. Set on_failure = continue explicitly to decouple the provisioner's success from the resource's.","demo13,local-exec,on-failure,ta004"
"Why is 'write an audit record to a local file' considered a genuinely justified use of local-exec, unlike tagging a resource?","Because writing to a local file has no Terraform-native equivalent at all — it's about the machine running Terraform, not AWS. Tagging, by contrast, already has a first-class Terraform mechanism (the tags argument), so using a provisioner for it would just reimplement something that exists and isn't tracked in state the way tags argument values are.","demo13,decision,tags"
"A local-exec command contains a shell syntax error (e.g. doubled &&). Does terraform validate catch this?","No — Terraform doesn't parse the contents of the command string, only that it's a valid string. A shell syntax error inside it only surfaces as an execution failure during apply, not a validate-time error.","demo13,local-exec,break-fix"
```

---

## Appendix — Quiz

**13-provisioners-quiz.md:**

````markdown
# Quiz — Demo 13: Provisioners

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Phase 2.

---

**Q1. (Multiple Choice)** Where does a `local-exec` provisioner's
command actually execute?

- A) On the AWS resource itself
- B) On the machine running Terraform
- C) On a temporary Lambda function Terraform creates
- D) Nowhere — it only logs what it would do

<details>
<summary>Answer</summary>

**B.** `local-exec` always runs on the machine executing
`terraform apply` — never on AWS. **A** is wrong — that's what
`remote-exec` targets, and even then only compute resources support
it. **C** is wrong — no such mechanism exists. **D** is wrong — the
command genuinely executes, it isn't a dry-run.

</details>

---

**Q2. (True/False)** A destroy-time provisioner (`when = destroy`)
runs after the resource has already been removed from AWS.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** It runs *before* actual removal, while the resource's
last-known state is still available — this is exactly why `self.*`
references still resolve correctly at that point.

</details>

---

**Q3. (Multiple Choice)** What does `remote-exec` require that
`local-exec` does not?

- A) A `tags` argument
- B) A `connection` block specifying how to reach the target resource
- C) A `lifecycle` block
- D) A `moved` block

<details>
<summary>Answer</summary>

**B.** `remote-exec` runs commands on the target resource itself, so
it needs real reachability information (host, credentials, protocol).
**A**, **C**, and **D** are all unrelated constructs with no
connection to `remote-exec`'s actual requirement.

</details>

---

**Q4. (Multiple Answer — Pick the 2 correct responses)** Which TWO of
the following are genuinely justified uses of a provisioner, per this
demo's decision framework?

- A) Writing a local audit log entry when a resource is created
- B) Tagging a newly-created resource
- C) Sending a local notification when a resource is destroyed
- D) Forcing a resource to rebuild when an unrelated resource changes
- E) Bootstrapping software on a new EC2 instance, when `user_data` isn't a viable option

<details>
<summary>Answer</summary>

**A and C** (and **E** is a reasonable secondary justified case, but
the two most clearly justified per this demo's own local-machine-only
framing are A and C). Writing to a local file or sending a local
notification are genuinely local-machine-only needs with no
Terraform-native alternative. **B** is wrong — the `tags` argument
already handles this natively. **D** is wrong —
`lifecycle.replace_triggered_by` (Demo 12) is the correct tool.

</details>

---

**Q5. (Multiple Choice)** A creation-time `local-exec` provisioner's
command fails. What happens by default?

- A) Nothing — the resource is created and the failure is silently logged
- B) The entire `apply` fails, even if the AWS resource was created successfully
- C) Terraform automatically retries the command up to 3 times
- D) The resource is rolled back and never created

<details>
<summary>Answer</summary>

**B.** Default `on_failure = fail` means a failing provisioner fails
the whole operation, regardless of whether the underlying resource
itself succeeded. **A** is wrong — this is not silent; it's a hard
failure. **C** is wrong — there's no automatic retry behavior. **D**
is wrong — the AWS resource isn't automatically rolled back; it may
remain created even though `apply` reports failure.

</details>

---

**Q6. (Multiple Choice)** Why doesn't `remote-exec` make sense on an
`aws_sqs_queue` or `aws_s3_bucket` resource?

- A) These resource types don't support any provisioners at all
- B) They have no compute or network reachability for a `connection` block to target
- C) `remote-exec` only works with resources created via `for_each`
- D) SQS and S3 resources are always created with `prevent_destroy`

<details>
<summary>Answer</summary>

**B.** `remote-exec` needs something to actually connect to and run
commands on — SQS/S3 have no such surface at all. **A** is wrong —
these resource types can use `local-exec` fine, just not `remote-exec`
meaningfully. **C** and **D** are both unrelated, invented
constraints.

</details>

---

**Q7. (True/False)** `terraform validate` catches a shell syntax error
inside a `local-exec` command string, such as a doubled `&&`.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Terraform only checks that `command` is a valid string
— it never parses the shell syntax inside it. A syntax error there
only surfaces as an execution failure during `apply`.

</details>

---

**Q8. (Multiple Choice)** CloudNova needs software installed on a new
EC2 instance the moment it launches, without depending on SSH
reachability. What's the best approach?

- A) `remote-exec` with a `connection` block
- B) `local-exec` with `when = destroy`
- C) `user_data`
- D) A `moved` block

<details>
<summary>Answer</summary>

**C.** `user_data` runs at boot without needing SSH or a `connection`
block at all — the better-fitting, Terraform/AWS-native mechanism for
this exact need. **A** introduces an SSH dependency the question
explicitly wants to avoid. **B** is wrong — that's for destruction, not
bootstrap. **D** is unrelated — `moved` blocks are about state
addressing, not provisioning.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 7-8/8 | Import Anki cards — Phase 1 - Foundations complete, move to Phase 2 |
| 6/8 | Review the wrong answers, then proceed |
| 4-5/8 | Re-read the relevant sections, retry those questions |
| Below 4/8 | Re-read the full demo and redo the walkthrough before proceeding |
````