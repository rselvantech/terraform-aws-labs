# Demo 14 — Modules Basics

---

## Overview

Every resource in this series so far has lived directly in the root
configuration — one flat set of `.tf` files, one flat state. That
works, but it doesn't scale: the moment two teams both need "an SNS
topic with an email subscription," copy-pasting the same two resource
blocks repeatedly is exactly the kind of duplication Terraform is
supposed to help avoid. **Modules** are Terraform's answer — a
self-contained, reusable configuration unit with its own declared
inputs and outputs, callable from anywhere.

**Real-world scenario — CloudNova:** the platform team is tired of
every service team hand-writing its own `aws_sns_topic` +
`aws_sns_topic_subscription` pair whenever they need email alerting —
inconsistent naming, inconsistent tagging, the same two resources
retyped each time. This demo builds CloudNova's first reusable
module — a small `sns-topic` module with its own input/output
contract — and calls it once from the root configuration to prove the
contract works.

**What this demo builds:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Building the sns-topic Module                                 │
│  modules/sns-topic/variables.tf, main.tf, outputs.tf — the module's own │
│  input/output contract, independent of anything at root                 │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Calling the Module from Root                                  │
│  module "alerts" { source = "./modules/sns-topic" ... } — passing       │
│  concrete values into the module's declared inputs                      │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Verifying the Module Contract                                 │
│  module.alerts.topic_arn read at root, Console check, confirm the       │
│  email subscription is pending confirmation                             │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- Module directory structure — the conventional
  `variables.tf` / `main.tf` / `outputs.tf` layout inside a module
- Declaring a module's own input variables — its contract with callers
- Declaring a module's own outputs — what it exposes back to the
  calling configuration
- The `module "<name>" { source = ... }` block — calling a local
  module from root
- Passing arguments into a module call
- Referencing a module's outputs from root: `module.<name>.<output>`
- `aws_sns_topic`, `aws_sns_topic_subscription`

**What this demo does NOT cover:** calling a module multiple times via
`count`/`for_each` on the module block itself, and sourcing a module
from the Terraform Registry (both Demo 15's territory) — this demo is
scoped strictly to a single local module, called once.

---

## How This Demo's Pieces Fit Together

**The AWS solution:** one SNS Topic with one email subscription,
created entirely inside the `sns-topic` module and called once from
root.

- `modules/sns-topic/variables.tf` declares the module's own contract:
  `topic_name` and `subscription_email` — both required, no defaults,
  since a module with no meaningful default behavior should make
  callers supply real values.
- `modules/sns-topic/main.tf` creates `aws_sns_topic.this` and
  `aws_sns_topic_subscription.this`, wired to each other by
  `aws_sns_topic.this.arn` — not a rebuilt ARN string.
- `modules/sns-topic/outputs.tf` exposes exactly one value back to the
  caller: `topic_arn`, read directly from
  `aws_sns_topic.this.arn` — the same "reference the actual created
  resource's attribute, never reconstruct it" pattern this series has
  used since Demo 09's log-group/metric-filter pairing, just scoped to
  a module boundary instead of a `for_each` key.
- Root's `main.tf` calls this module once (`module "alerts"`),
  passing concrete values for both inputs.
- Root's `outputs.tf` re-exposes `module.alerts.topic_arn` — proving
  a value can flow out of a module and back into the calling
  configuration without ever touching AWS directly for that value.

---

## Prerequisites

### Knowledge
- Demo 13 completed — provisioners and the decision framework for
  when they're genuinely justified (not required for this demo's
  content directly, but this is the first demo of Phase 2, and
  assumes everything through Phase 1 - Foundations)

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | `>= 1.15.0` (pinned `~> 1.15.0` in this demo) | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version` |
| `jq` | Any recent version | `jq --version` |

### Verify AWS Account and Permissions

**Step 1 — Confirm your profile works:**

```bash
aws sts get-caller-identity --profile default --region us-east-2
```

**Step 2 — A cheap, harmless dry-run of this demo's actual service:**

```bash
aws sns list-topics --profile default --region us-east-2
# Expected: JSON with a Topics array (may be empty — that is fine)
# If you see AccessDenied: fix IAM permissions before proceeding,
# not after you're mid-lab
```

**Step 3 — Verify IAM permissions in Console:**

```
Console → IAM → Users → test → Permissions tab
  → Confirm AmazonSNSFullAccess (or equivalent) is attached ✅
```

**Required permissions for this demo:**

```
sns:CreateTopic, sns:DeleteTopic, sns:GetTopicAttributes, sns:TagResource
sns:Subscribe, sns:Unsubscribe, sns:ListSubscriptionsByTopic
```

> For a learning account, the `AmazonSNSFullAccess` managed policy
> covers the permissions above.

### Versions used in this demo

| Tool | Version |
|---|---|
| Terraform | `~> 1.15.0` |
| AWS Provider | `~> 6.47.0` |
| AWS CLI | `>= 2.x` |

> **Versions pinned as of September 2026.** `~>` allows patch/minor
> drift within the stated line but blocks a breaking jump. Both
> Terraform CLI and the AWS provider ship on their own release
> cadence independent of this series — if you're reading this well
> after September 2026, check the provider's own changelog before
> assuming `6.47.0` is still current; the pin itself doesn't need to
> change, but it's worth knowing how far behind "current" it now is.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Structure a Terraform module using the conventional
   `variables.tf` / `main.tf` / `outputs.tf` file layout
2. ✅ Declare a module's own input variables as its contract with
   callers
3. ✅ Declare a module's own outputs to expose values back to the
   calling configuration
4. ✅ Call a local module from a root configuration using a `module`
   block with a `source` argument
5. ✅ Reference a module's output from root using
   `module.<name>.<output>` syntax
6. ✅ Build and verify a real AWS SNS Topic + email subscription
   entirely through a module call

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| SNS Topic (×1) | 1,000,000 publishes free/month | **$0.00** | |
| SNS Email Subscription (×1) | Always free | **$0.00** | Email deliveries are not billed the way SMS is |
| **Session total** | | **$0.00** | |

> Always run cleanup at the end of the session.

---

## Directory Structure

```
14-modules-basics/
├── README.md
├── 14-modules-basics-anki.csv
├── 14-modules-basics-quiz.md
└── src/
    ├── versions.tf                  # terraform block + provider version constraints
    ├── provider.tf                  # AWS provider: region, profile
    ├── variables.tf                 # root-level inputs: topic name, alert email
    ├── main.tf                      # module "alerts" block — calls the local module
    ├── outputs.tf                   # root output re-exposing module.alerts.topic_arn
    ├── modules/
    │   └── sns-topic/
    │       ├── variables.tf         # module's own input contract
    │       ├── main.tf               # aws_sns_topic + aws_sns_topic_subscription
    │       └── outputs.tf            # module's own output contract
    └── break-fix/
        ├── broken.tf                 # root config with 3 deliberate module-call errors
        └── modules/
            └── sns-topic/
                ├── broken-variables.tf   # correct callee module — unprefixed
                ├── broken-main.tf        #   basenames intentionally NOT used here
                └── broken-outputs.tf     #   to avoid basename collision with src/modules/sns-topic/*
```

> **Note on break-fix module filenames:** `fill_files.sh` matches
> files by basename only. The real module's files
> (`variables.tf`/`main.tf`/`outputs.tf`) already exist under
> `src/modules/sns-topic/`; reusing those exact basenames under
> `break-fix/modules/sns-topic/` would collide. The `broken-` prefix
> here exists purely to keep the extraction script safe — Terraform
> itself doesn't care what `.tf` files inside a module directory are
> named, so this has zero effect on how the module actually loads.
> This is unrelated to root-level file naming (above) — root files
> use plain names with no numeric prefix, matching the rest of this
> series' convention, since Terraform loads every `.tf` file in a
> directory regardless of name or order.

---

## Recall Check — Demo 13

Answer from memory before reading further:

1. You add a `local-exec` provisioner to an `aws_instance`, expecting
   the command to run on the EC2 instance itself once it's created.
   What actually happens?
2. A queue has `provisioner "local-exec" { when = destroy ... }`. When
   `terraform destroy` runs, does that command execute *before* or
   *after* the queue is actually removed from AWS — and why does that
   ordering matter for `self.*` references?
3. A teammate wants to use `remote-exec` to run a setup script against
   a newly created S3 bucket. What's wrong with this plan?

<details>
<summary>Answers</summary>

1. `local-exec` always runs on the machine executing
   `terraform apply` — never on any AWS resource, regardless of
   resource type. The EC2 instance itself stays completely passive;
   there's no mechanism for "the resource executes something."
2. Before — Terraform runs a destroy-time provisioner while the
   resource's last-known state is still available, then proceeds with
   the actual AWS-side deletion. This ordering is exactly why
   `self.name` (or any other `self.*` reference) still resolves
   correctly at that point.
3. `remote-exec` requires a `connection` block and real, reachable
   compute to run commands against — S3 buckets have no compute
   surface at all, nothing for a `connection` block to reach. There's
   nothing for `remote-exec` to connect to.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| Module directory (`variables.tf`/`main.tf`/`outputs.tf`) | File layout convention | Gives a module its own self-contained input/output contract |
| `variable` block (inside a module) | Module input declaration | Defines what a caller must (or may) supply |
| `output` block (inside a module) | Module output declaration | Defines what the module exposes back to its caller |
| `module "<name>" { source = ... }` | Root-level block | Calls a module, passing concrete argument values |
| `module.<name>.<output>` | Reference expression | Reads a value a module has exposed via its own `output` block |
| `aws_sns_topic` | Resource | SNS topic created inside the module |
| `aws_sns_topic_subscription` | Resource | Email subscription attached to the topic, created inside the module |

**Related constructs worth knowing (not covered in full here):**

| Construct | What it is | Where it's covered in full |
|---|---|---|
| `count`/`for_each` on a `module` block | Calling the same module multiple times | Demo 17 (Three-Tier Modules) |
| Registry module sourcing (`source = "terraform-aws-modules/..."`) | Pulling a published, versioned module | Demo 15 |

---

### Detailed Explanation of New Constructs

#### `aws_sns_topic` and `aws_sns_topic_subscription` — CloudNova's First Use of SNS

CloudNova has no existing alerting mechanism in this series — every
prior demo's outputs have been read manually. SNS gives CloudNova a
way to actually push a notification somewhere the moment something
happens, which is exactly why the platform team wants it standardized
into a module before every team reinvents it slightly differently.

```hcl
resource "aws_sns_topic" "this" {
  name = var.topic_name
}

resource "aws_sns_topic_subscription" "this" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = var.subscription_email
}
```

**What it does:** `aws_sns_topic` creates the topic itself — the
channel messages get published to. `aws_sns_topic_subscription`
attaches one subscriber to it; `protocol = "email"` and `endpoint =
<an email address>` together tell SNS to deliver messages by email to
that address.

> **`email` is officially a "partially supported" protocol value, not
> a full one.** Per the AWS provider's own documentation, `sqs`,
> `sms`, `lambda`, `firehose`, and `application` are fully supported —
> `email`, `email-json`, `http`, and `https` are valid but partially
> supported, because AWS requires the endpoint owner to click a
> confirmation link before the subscription becomes active, and
> Terraform has no way to complete that step. Two concrete
> consequences: the subscription stays in `PendingConfirmation` status
> until someone manually confirms it, and Terraform **cannot**
> force-unsubscribe an unconfirmed subscription directly — destroying
> it removes it from Terraform's state but leaves it in AWS, unless
> the *topic itself* is also destroyed, since deleting a topic cascades
> and removes all of its subscriptions regardless of confirmation
> status. This demo's Cleanup destroys the whole topic, so this
> doesn't leave anything orphaned here — but it's a real, exam-relevant
> gotcha to know for any scenario where only the subscription (not the
> topic) is being destroyed. **This gotcha is directly tested in this
> demo's Quiz, not just in Anki — see Quiz Q7/Q8.**

---

#### Module Directory Structure — `variables.tf` / `main.tf` / `outputs.tf`

A module is just a directory containing `.tf` files — Terraform loads
every `.tf` file in that directory and merges them, exactly like it
does at root. The three-file split (`variables.tf`, `main.tf`,
`outputs.tf`) isn't required by Terraform itself; it's a strong
community convention this series follows consistently, precisely
because it makes a module's contract easy to find: its inputs are
always in one file, its outputs in another, regardless of how many
resources `main.tf` ends up containing.

> **A module has no special file, no manifest, no registration step.**
> Any directory with `.tf` files in it can be used as a module source
> — what makes it "a module" is simply that something else's `source`
> argument points at it.

---

#### Declaring a Module's Own Inputs — `variable` Blocks Inside the Module

```hcl
# modules/sns-topic/variables.tf

variable "topic_name" {
  type        = string
  description = "Name of the SNS topic this module creates"
}

variable "subscription_email" {
  type        = string
  description = "Email address to subscribe to the topic for alerts"
}
```

**What it does:** these `variable` blocks work exactly like the root-
level ones this series has used since Demo 05 — same syntax, same
`type`/`description`/optional `default` arguments. The difference is
entirely about *scope*: a `variable` declared inside a module is only
visible inside that module. Root has no direct access to
`var.topic_name` here — root can only supply a value for it through
the `module` block's arguments (covered next).

> **Neither input has a `default`.** Both are required — the caller
> must supply real values for both, since there's no sensible
> "default" topic name or alert email for a module meant to be reused
> by different teams.

---

#### Declaring a Module's Own Outputs — `output` Blocks Inside the Module

```hcl
# modules/sns-topic/outputs.tf

output "topic_arn" {
  value       = aws_sns_topic.this.arn
  description = "ARN of the SNS topic created by this module"
}
```

**What it does:** an `output` block inside a module works the same way
as a root-level output — it exposes a value. The difference is *where*
that value becomes visible: a module's own outputs are invisible
outside the module entirely, unless the calling configuration
explicitly reads them via `module.<name>.<output>` (covered below).
This module deliberately exposes only `topic_arn` — not, say, the
subscription's own ID — because `topic_arn` is the one value a caller
is actually likely to need downstream (e.g., to grant another resource
permission to publish to it).

> **A module's outputs are its only visible surface to the outside.**
> Everything else inside the module — its resources, its local values,
> even its own variable values — stays completely private to the
> module unless explicitly re-exposed through an `output` block.

---

#### Calling a Local Module — the `module` Block

```hcl
# main.tf (root)

module "alerts" {
  source = "./modules/sns-topic"

  topic_name          = var.alert_topic_name
  subscription_email  = var.alert_subscription_email
}
```

**What it does:** `module "alerts"` gives this module call a local
name (`alerts`) — used later to reference its outputs. `source`
points at the module's directory, relative to the file containing this
block. Every other argument inside the block (`topic_name`,
`subscription_email`) must correspond exactly to a `variable` the
module itself declares — these are the module's required inputs being
supplied.

> **The module call's local name (`alerts`) is unrelated to anything
> inside the module.** It's a label chosen entirely at the call site —
> a second call to the same module elsewhere could use a completely
> different local name (e.g. `module "billing_alerts"`), and both
> would independently call the exact same module source.

---

#### Reading a Module's Output — `module.<name>.<output>`

```hcl
# outputs.tf (root)

output "alert_topic_arn" {
  value       = module.alerts.topic_arn
  description = "ARN of the SNS topic created via the alerts module"
}
```

**What it does:** `module.alerts.topic_arn` reads the `topic_arn`
value the module itself exposed via its own `output` block. The
`alerts` here is the local name chosen at the call site above — not
the module's directory name, not anything inside the module itself.
This root-level `output` block then re-exposes that same value one
level further out, to `terraform output` and anything reading root's
own outputs.

> **Same as X" ban check — restating, not just pointing:** this is
> conceptually similar to a resource attribute reference
> (`aws_sns_topic.this.arn`), but it is not the same mechanism. A
> resource reference reads a live AWS attribute Terraform tracked in
> state directly. A module output reference reads a value the module
> *chose* to expose — if the module's own `outputs.tf` didn't declare
> `topic_arn`, no reference to it from root could exist at all, no
> matter what the module's resources actually created internally.

---

## Lab Step-by-Step Guide

---

## Part A — Building the sns-topic Module

Part A creates a self-contained module directory with its own
input/output contract — no calling configuration yet, just the module
itself.

### Step 1 — Navigate to the project

```bash
cd terraform-aws-mastery/phase-2-modules/14-modules-basics/src
```

### Step 2 — Create the root scaffolding files

This step scaffolds the root configuration's provider and version
pins, plus the root-level input variables that will later feed values
into the module call in Part B — none of this is module-specific yet.

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

These are root's own variables — distinct from, and passed into, the
module's own `variable` block declarations in Part A Step 3.

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

variable "alert_topic_name" {
  type        = string
  description = "Name passed into the sns-topic module's topic_name input"
  default     = "cloudnova-alerts-demo14"
}

variable "alert_subscription_email" {
  type        = string
  description = "Email address passed into the sns-topic module's subscription_email input"
  default     = "platform-team@cloudnova.example.com"
}
```

### Step 3 — Build the module itself

This step builds the module directory with no awareness of root at
all — it's fully self-contained, exactly as Concepts described.

Create a file **modules/sns-topic/variables.tf** and add the below
content:

This file declares the module's complete input contract — both
required, no defaults, since a reusable alerting module shouldn't
guess a topic name or recipient on a caller's behalf.

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

Create a file **modules/sns-topic/main.tf** and add the below content:

This file contains the module's only two resources — the topic and
its email subscription — wired together via the topic's own `arn`
attribute, never a reconstructed string.

```hcl
resource "aws_sns_topic" "this" {
  name = var.topic_name

  tags = {
    ManagedBy = "terraform-demo-14"
  }
}

resource "aws_sns_topic_subscription" "this" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = var.subscription_email
}
```

Create a file **modules/sns-topic/outputs.tf** and add the below
content:

This file exposes exactly one value, `topic_arn`, back to whatever
calls this module — the module's entire public surface.

```hcl
output "topic_arn" {
  value       = aws_sns_topic.this.arn
  description = "ARN of the SNS topic created by this module"
}
```

### Step 4 — Validate the module in isolation

This step confirms the module's own files are internally valid before
anything calls it — no root configuration exists yet at this point.

```bash
cd modules/sns-topic
terraform init
terraform validate
cd ../..
```

Expected:

```
Success! The configuration is valid.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **A module can be validated on its own, with no caller.** Terraform
> only checks that the module's own `.tf` files are internally
> consistent here — it has no way yet to know what values a future
> caller will supply for `topic_name`/`subscription_email`, since no
> root configuration has called it yet.

---

## Part B — Calling the Module from Root

Part B wires the module into a real root configuration, and applies
it — the first time this module's resources actually get created in
AWS.

### Step 5 — Create the module call

This step writes the root-level `module` block that calls Part A's
module for the first time, supplying concrete values for both of its
required inputs.

Create a file **main.tf** and add the below content:

This file contains the single `module "alerts"` call — the first
point in this demo where the module and the root configuration
actually connect.

```hcl
module "alerts" {
  source = "./modules/sns-topic"

  topic_name         = var.alert_topic_name
  subscription_email = var.alert_subscription_email
}
```

### Step 6 — Create the root output

This step re-exposes the module's own `topic_arn` output at root,
proving a value can cross a module boundary in both directions.

Create a file **outputs.tf** and add the below content:

This file reads `module.alerts.topic_arn` and re-exposes it as a
root-level output — the only way this value becomes visible to
`terraform output` or anything outside this configuration.

```hcl
output "alert_topic_arn" {
  value       = module.alerts.topic_arn
  description = "ARN of the SNS topic created via the alerts module"
}
```

### Step 7 — Initialize and apply

This step initializes the module for the first time from root's
perspective, then creates the real AWS resources — the first time
this module's contract is exercised end-to-end.

```bash
terraform init
```

Expected — this is the first time `init` needs to do anything with a
local module:

```
Initializing modules...
- alerts in modules/sns-topic

Initializing the backend...
Initializing provider plugins...
Terraform has been successfully initialized!
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

```bash
terraform validate
terraform apply
```

Expected — note the `module.alerts.` prefix on each resource address,
distinguishing these from root-level resources:

```
module.alerts.aws_sns_topic.this: Creating...
module.alerts.aws_sns_topic.this: Creation complete after 1s [id=arn:aws:sns:us-east-2:...:cloudnova-alerts-demo14]
module.alerts.aws_sns_topic_subscription.this: Creating...
module.alerts.aws_sns_topic_subscription.this: Creation complete after 1s [id=arn:aws:sns:...]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

alert_topic_arn = "arn:aws:sns:us-east-2:...:cloudnova-alerts-demo14"
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

> **Every resource created by a module is addressed with a
> `module.<name>.` prefix.** `module.alerts.aws_sns_topic.this` is a
> distinct resource address from a root-level `aws_sns_topic.this` —
> this is what makes calling the same module twice under two different
> local names (e.g. `module.alerts` and `module.billing_alerts`) safe;
> their resource addresses never collide.

---

## Part C — Verifying the Module Contract

Part C confirms the module's output actually reflects the real
created resource, and that the email subscription is genuinely
pending confirmation in AWS — not just reported as created by
Terraform.

### Step 8 — Read the output directly

```bash
terraform output alert_topic_arn
```

Expected: the same ARN shown in the `apply` output above.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

### Step 9 — Verify in the Console

This step confirms the module's resources are real in AWS, not just
reported as created by Terraform, and that the subscription's pending
status is expected rather than a failure.

```
Console → SNS → Topics → cloudnova-alerts-demo14
  → Topic exists, ARN matches `terraform output` exactly ✅
  → Subscriptions tab → one subscription, status "Pending confirmation" ✅
```

> 📷 [Screenshot placeholder: AWS Console → SNS → Topics →
> cloudnova-alerts-demo14, Subscriptions tab showing status "Pending
> confirmation"]

> **"Pending confirmation" is expected, not a failure.** SNS email
> subscriptions require the recipient to click a confirmation link
> sent to their inbox before delivery actually begins — Terraform's
> job ends at creating the subscription resource itself; it has no
> mechanism to complete email confirmation on anyone's behalf.

---

## Cleanup

### Step 10 — Destroy all resources

```bash
terraform destroy
```

Type `yes`. Expected:

```
module.alerts.aws_sns_topic_subscription.this: Destroying...
module.alerts.aws_sns_topic_subscription.this: Destruction complete after 1s
module.alerts.aws_sns_topic.this: Destroying...
module.alerts.aws_sns_topic.this: Destruction complete after 1s

Destroy complete! Resources: 2 destroyed.
```

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

### Step 11 — Confirm the topic is gone

```bash
aws sns list-topics --profile default --region us-east-2 | grep cloudnova-alerts-demo14
```

Expected: no output — the topic no longer exists.

> ⚠️ Simulated expected output — not from a live terminal run in this
> environment.

---

## What You Learned

1. ✅ A module is just a directory of `.tf` files — the
   `variables.tf`/`main.tf`/`outputs.tf` split is convention, not a
   Terraform requirement
2. ✅ A module's own `variable` blocks define its input contract,
   invisible to callers except through the `module` block's arguments
3. ✅ A module's own `output` blocks define its output contract — the
   *only* way anything outside the module can see a value it produced
4. ✅ `module "<name>" { source = ... }` calls a module, and every
   resource it creates is addressed with a `module.<name>.` prefix
5. ✅ `module.<name>.<output>` reads a value the module explicitly
   chose to expose — nothing else inside the module is reachable from
   outside it

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `variable`/`output` blocks inside a module | TA-004 Obj 5b | Tests understanding that a module's variables are scoped to the module itself, not shared with root |
| `module "<name>" { source = ... }`, calling a local module | TA-004 Obj 5c | Core "use modules in configuration" objective |
| `module.<name>.<output>` reference syntax | TA-004 Obj 5c | Frequently tested — expect a scenario asking how to read a module's output from root |
| `source = "./relative/path"` (local module sourcing) | TA-004 Obj 5a *(first touch only — full depth in Demo 15)* | Know that a local relative path is one valid form of `source`; the Registry form is covered next demo |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| Exam shows a module call missing a required input | Recognizing Terraform will error at `plan`/`apply` demanding the missing argument, listing it by name | Assuming missing inputs silently fall back to some default |
| Exam asks how to reference a value a module produced | Recognizing `module.<name>.<output>` — and that the output must have been explicitly declared inside the module | Trying to reference a resource inside the module directly from root (e.g. `module.alerts.aws_sns_topic.this.arn`, which doesn't work — modules aren't transparent) |
| Exam shows two calls to the same module with different local names | Recognizing this creates two independent sets of resources, addressed separately (`module.a.*`, `module.b.*`) | Assuming a second call to the same module modifies or extends the first call's resources |
| Exam asks what happens when destroying an unconfirmed `aws_sns_topic_subscription` with `protocol = "email"` | Recognizing this only removes it from Terraform state, not from AWS, since `email` is a partially-supported protocol | Assuming `terraform destroy` always fully removes a resource from AWS regardless of protocol/confirmation status |

### Exam Task — Write a complete configuration

**Task:** CloudNova's billing team needs their own alert topic, reusing
the exact same module pattern demonstrated in this demo. Write a
module directory with a `topic_name` input, a `subscription_email`
input, and a `topic_arn` output — then call it from a root
configuration and expose its output.

**Block types required:** `variable` (×2, inside the module), `output`
(×1 inside the module, ×1 at root), `resource` (×2, inside the
module), `module` (×1, at root)

**Official documentation:**
- [Modules](https://developer.hashicorp.com/terraform/language/modules)

**What to practise:**
1. Open the Modules page — confirm exactly how `source` is interpreted
   for a local relative path versus other source types
2. Write both the module and the root call from scratch, without
   looking at this demo's `.tf` files
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
# modules/billing-alerts/variables.tf
variable "topic_name" {
  type = string
}
variable "subscription_email" {
  type = string
}

# modules/billing-alerts/main.tf
resource "aws_sns_topic" "this" {
  name = var.topic_name
}
resource "aws_sns_topic_subscription" "this" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = var.subscription_email
}

# modules/billing-alerts/outputs.tf
output "topic_arn" {
  value = aws_sns_topic.this.arn
}

# root main.tf
module "billing_alerts" {
  source              = "./modules/billing-alerts"
  topic_name          = "cloudnova-billing-alerts"
  subscription_email  = "billing-team@cloudnova.example.com"
}

# root outputs.tf
output "billing_alert_topic_arn" {
  value = module.billing_alerts.topic_arn
}
```

**Arguments you must know without looking up:**
- `source` for a local module is a relative filesystem path, always
  starting with `./` or `../`
- A module's `variable` block with no `default` is a required input —
  omitting it at the call site is an error, not a silent no-op

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Module not installed` / `Reference to undeclared module` | `terraform init` was never (re-)run after adding or changing a `module` block | Run `terraform init` again — modules must be initialized, same as providers |
| `Missing required argument` referencing a module's variable | The `module` block omitted an argument the module declares with no `default` | Add the missing argument to the `module` block, matching the module's `variable` name exactly |
| `Unsupported attribute` on a `module.<name>.<output>` reference | The referenced output name doesn't exist in the module's own `outputs.tf` | Check the module's actual `outputs.tf` for the correct output name — a module's internal resource attributes are never directly reachable from root |
| Destroying an SNS email subscription leaves it still present in AWS | `email` is a partially-supported `protocol` value — Terraform can't force-unsubscribe an unconfirmed subscription | Destroy the parent `aws_sns_topic` too (cascades and removes all its subscriptions), or manually confirm/unsubscribe outside Terraform first |

---

## Break-Fix Scenario

Three deliberate errors in how the root configuration calls the
module. The module itself (under `break-fix/modules/sns-topic/`) is a
correct, working callee — every error lives in `broken.tf`.

```bash
cd src/break-fix/
terraform init
```

> **Fix errors one at a time and re-run.** A broken `source` path
> blocks `init` entirely — the other two errors can't be seen until
> that one is fixed first, the same iterative diagnose-fix-rerun
> pattern used in Demo 13's Break-Fix.

#### `modules/sns-topic/broken-variables.tf`, `broken-main.tf`, `broken-outputs.tf` — the correct callee module

These files are an exact, working copy of Part A's module —
deliberately *not* broken. Renamed with a `broken-` prefix only to
avoid a `fill_files.sh` basename collision with the real module under
`src/modules/sns-topic/`; Terraform itself loads any `.tf` file in the
directory regardless of name.

**broken-variables.tf:**

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

**broken-main.tf:**

```hcl
resource "aws_sns_topic" "this" {
  name = var.topic_name
}

resource "aws_sns_topic_subscription" "this" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = var.subscription_email
}
```

**broken-outputs.tf:**

```hcl
output "topic_arn" {
  value = aws_sns_topic.this.arn
}
```

#### `broken.tf` — Three deliberate errors in the module call

This file is a self-contained root configuration calling the module
above, with a typo'd source path, a missing required argument, and a
wrong output reference — diagnose all three.

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

module "alerts" {
  source = "./modules/sns-toppic" # Error 1: typo'd source path (extra "p")

  topic_name = "cloudnova-broken-demo14" # Error 2: subscription_email omitted entirely
}

output "alert_topic_arn" {
  value = module.alerts.topic_id # Error 3: wrong output name (should be topic_arn)
}
```

<details>
<summary>Reveal answers — attempt diagnosis first</summary>

**Error 1 — typo'd `source` path**
`./modules/sns-toppic` doesn't exist (the real directory is
`sns-topic`). `terraform init` fails with a "module not found"-class
error before anything else can even be checked. Fix: correct the path
to `./modules/sns-topic`.

**Error 2 — missing required argument `subscription_email`**
Once the source path is fixed, `terraform validate`/`plan` reports a
"Missing required argument" error — the module declares
`subscription_email` with no `default`, and the call supplies nothing
for it. Fix: add `subscription_email = "<an email>"` to the `module`
block.

**Error 3 — wrong output name (`topic_id` instead of `topic_arn`)**
The module's own `outputs.tf` only declares `topic_arn` — there is no
`topic_id`. This is reported as an "Unsupported attribute" error, a
separate diagnostic from Error 2's "Missing required argument."

> ⚠️ [VERIFY — behavioral claim, docs-reasoning only, not a live run in
> this environment]: whether both diagnostics are reported together in
> a single `terraform validate` pass once the source path is fixed, or
> whether one masks the other, isn't confirmed here — treat each error
> as independently real and re-run `validate` after each fix rather
> than assuming both surface at once.

Fix: reference `module.alerts.topic_arn` instead.

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

**Q1. A junior engineer asks why they can't just reference
`module.alerts.aws_sns_topic.this.arn` directly from root, instead of
going through an output. What would you tell them?**
Modules aren't transparent — nothing inside a module is reachable from
outside it except what the module explicitly exposes through its own
`output` blocks. Even though `aws_sns_topic.this` genuinely exists
inside the module, root has no visibility into the module's internal
resource addresses at all. The module's author controls its entire
public surface through what it chooses to output — that's the whole
point of the input/output contract.

**Q2. Your team wants to call the same module twice — once for
alerting, once for billing notifications. What has to be different
between the two calls?**
Only the local name (e.g. `module "alerts"` vs `module "billing"`) has
to differ — everything else about the module source itself stays
identical. Each call gets its own independent set of resources,
addressed separately (`module.alerts.*` vs `module.billing.*`), and
each can be passed entirely different argument values without
affecting the other.

**Q3. Why does a module's `variable` block with no `default` behave
differently from a root-level variable with no `default`?**
Functionally they behave the same way — both are required inputs that
error if not supplied. The difference is *where* the value has to come
from: a root-level variable can get its value from a `.tfvars` file, a
CLI flag, or an environment variable, since root is the entry point a
user interacts with directly. A module's variable can only get its
value from the calling configuration's `module` block arguments —
there's no equivalent of a `.tfvars` file that speaks directly to a
nested module.

---

## Key Takeaways

1. **A module is just a directory of `.tf` files.** The
   `variables.tf`/`main.tf`/`outputs.tf` split is a strong convention
   this series follows, not a Terraform requirement.

2. **A module's `variable` blocks are its input contract, visible only
   through the calling `module` block's arguments.** Root has no
   direct access to a module's internal variable values any other way.

3. **A module's `output` blocks are the *only* way anything outside it
   can see a value it produced.** Internal resources, even their
   attributes, are never directly reachable from outside the module.

4. **Every resource a module creates is addressed with a
   `module.<name>.` prefix**, where `<name>` is the local name chosen
   at the call site — this is what makes calling the same module twice
   under different names safe.

> **Demo scope:** Primary concept: module structure and the
> input/output contract for calling a module. Supporting concepts:
> local `source` path syntax (first touch only), reading a module's
> output from root.
> Estimated completion time: 35–40 minutes (reading + hands-on +
> verification).
> Checkpoints: 3 natural stopping points (end of Part A, end of
> Part B, end of Part C).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `terraform init` | Required after adding or changing any `module` block — initializes the module the same way it does providers |
| `terraform output <name>` | Reads a specific root-level output, including one that re-exposes a module's own output |

---

## Next Demo

**Demo 15 — Public Registry Modules.** Builds directly on this demo's
module-calling mechanics, extending `source` to pull a published,
versioned module from the Terraform Registry instead of a local path.

---

## Appendix — Anki Cards

**14-modules-basics-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 2 - Modules::14-modules-basics
#separator:Comma
#columns:Front,Back,Tags
"What is a Terraform module, structurally?","Just a directory containing .tf files — Terraform loads every .tf file in it and merges them, exactly like at root. The variables.tf/main.tf/outputs.tf split is convention, not a Terraform requirement.","demo14,modules,ta004-obj5c"
"Where is a variable declared inside a module visible from?","Only inside that module itself. Root has no direct access to it — the only way root can influence its value is by supplying an argument of the same name in the module block that calls it.","demo14,modules,scope,ta004-obj5b"
"How does something outside a module read a value the module produced?","Only through the module's own declared output blocks, referenced as module.<name>.<output>. Nothing else inside the module — no resource, no local value — is directly reachable from outside it.","demo14,modules,outputs,ta004-obj5c"
"What does the module block's local name (e.g. module \"alerts\") actually refer to?","A label chosen entirely at the call site, unrelated to the module's directory name or anything inside the module. It's used afterward to reference this specific call's outputs and resource addresses.","demo14,modules,syntax,ta004-obj5c"
"How is a resource created inside a module addressed?","With a module.<name>. prefix, e.g. module.alerts.aws_sns_topic.this — distinct from any root-level resource address, and distinct from another call to the same module under a different local name.","demo14,modules,addressing,ta004-obj5c"
"What happens if a module's required variable (no default) is omitted at the call site?","Terraform errors during plan/apply with a Missing required argument error, naming the missing variable. There is no silent fallback.","demo14,modules,break-fix,ta004-obj5b"
"Can you reference a resource inside a module directly from root, e.g. module.alerts.aws_sns_topic.this.arn?","No — modules aren't transparent. Only what the module explicitly exposes via its own output blocks is reachable from outside it, even though the resource genuinely exists inside the module.","demo14,modules,scope,ta004-obj5b"
"Does terraform init need to run again after adding a new module block?","Yes — modules must be initialized the same way providers are. Skipping this produces a 'module not installed' class error.","demo14,modules,init,ta004-obj5c"
"What form does source take for a local module?","A relative filesystem path, always starting with ./ or ../ (e.g. ./modules/sns-topic) — distinct from a Terraform Registry source, covered in the next demo.","demo14,modules,source,ta004-obj5a"
"Which aws_sns_topic_subscription protocol values are fully supported versus partially supported?","Fully supported: sqs, sms, lambda, firehose, application. Partially supported: email, email-json, http, https — because AWS requires manual confirmation Terraform can't complete on its own.","demo14,sns,gotcha"
"Can Terraform force-unsubscribe an unconfirmed email subscription by destroying just the subscription resource?","No — destroying an unconfirmed email/email-json/http/https subscription only removes it from Terraform's state, not from AWS. Only destroying the parent topic cascades and actually removes the subscription in AWS.","demo14,sns,gotcha,break-fix"
"Which aws_sns_topic_subscription protocols are fully supported vs. partially supported?","Fully supported: sqs, sms, lambda, firehose, application. Partially supported: email, email-json, http, https — these require manual, out-of-band confirmation that Terraform cannot complete itself.","demo14,sns,protocols"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** the Anki deck above is this demo's recall
> layer — atomic facts, one per card. This Quiz is deliberately built
> to test the material Anki *doesn't* drill directly: scenario
> recognition, Break-Fix-style diagnosis, and the SNS gotchas that
> matter most on exam day. If a question below looks unfamiliar even
> after reading the demo, that's the point — go re-read the relevant
> Concepts section rather than expecting it to mirror a flashcard.

**14-modules-basics-quiz.md:**

````markdown
# Quiz — Demo 14: Modules Basics

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 15.

---

**Q1. (Multiple Choice)** A colleague's `module` block builds fine but
their teammate then writes `module.alerts.aws_sns_topic.this.arn` in a
root output and gets an error. What's the actual problem, and what
should they write instead?

- A) They need to add `aws_sns_topic.this` as an explicit output first — nothing they write from root can skip the module's own `output` blocks
- B) They forgot `terraform init` — re-running it will make the reference resolve
- C) `aws_sns_topic.this.arn` needs `depends_on` added at root
- D) The resource needs a `count` index added, e.g. `aws_sns_topic.this[0].arn`

<details>
<summary>Answer</summary>

**A.** Modules aren't transparent — the fix isn't a missing `init` or
a missing index, it's that root can only ever read what the module's
own `outputs.tf` chose to expose. The correct fix is
`module.alerts.topic_arn`, assuming the module declares that output.

</details>

---

**Q2. (Multiple Choice)** You call the `sns-topic` module twice in the
same root configuration — `module "alerts"` and `module "billing"` —
both pointing at the same `source`. What must be true for `terraform
apply` to succeed?

- A) Both calls must be given identical argument values
- B) Both calls must supply real values for every required variable the module declares — the two calls are otherwise fully independent
- C) Only one call may actually create resources; the second is treated as a no-op
- D) The module's `source` directory must be duplicated on disk for the second call

<details>
<summary>Answer</summary>

**B.** Each `module` block is an independent call — it needs its own
values for the module's required inputs (`topic_name`,
`subscription_email`), but nothing requires the two calls to match
each other, and the same on-disk module directory can be called any
number of times.

</details>

---

**Q3. (Multiple Choice)** A module's `variable "subscription_email"`
has no `default`. Which statement about supplying it is correct?

- A) It can come from a `.tfvars` file passed directly to the module
- B) It can only come from the calling configuration's `module` block argument of the same name
- C) It falls back to the root-level variable of the same name automatically
- D) It must be set as an environment variable (`TF_VAR_subscription_email`)

<details>
<summary>Answer</summary>

**B.** A module has no `.tfvars`/CLI-flag/environment-variable entry
point of its own — the *only* way a value reaches a module's variable
is through the argument of the same name in the `module` block that
calls it. **C** is a common wrong assumption; there is no automatic
name-matching between root and module variables.

</details>

---

**Q4. (Multiple Choice)** You destroy only `aws_sns_topic_subscription.this`
(not the parent topic) where `protocol = "email"` and the subscription
was never confirmed. What actually happens in AWS?

- A) AWS fully removes the subscription — Terraform's destroy always succeeds completely
- B) The subscription is removed from Terraform's state, but still exists in AWS
- C) `terraform destroy` errors and refuses to proceed
- D) AWS automatically re-sends a confirmation email and waits

<details>
<summary>Answer</summary>

**B.** This is the partially-supported-protocol gotcha: Terraform
cannot force-unsubscribe an unconfirmed `email`/`email-json`/`http`/
`https` subscription. It disappears from state but AWS still has it —
only destroying the parent topic actually removes it from AWS.

</details>

---

**Q5. (Multiple Choice)** Which of `sqs`, `sms`, `lambda`, `email`,
`firehose`, `application` are **partially** supported
`aws_sns_topic_subscription` protocols (pick the one correct set)?

- A) `email` only
- B) `email`, `email-json`, `http`, `https`
- C) All six are partially supported
- D) `sqs` and `lambda` only

<details>
<summary>Answer</summary>

**B.** `sqs`, `sms`, `lambda`, `firehose`, and `application` are fully
supported. `email`, `email-json`, `http`, and `https` require manual,
out-of-band confirmation Terraform can't complete — that's what makes
them "partially supported."

</details>

---

**Q6. (Multiple Answer — Pick the 2 correct responses)** Break-Fix's
`broken.tf` has `source = "./modules/sns-toppic"` (typo) and omits
`subscription_email`. Which TWO statements about diagnosing this are
correct?

- A) The source typo must be fixed before `terraform init` will even succeed
- B) Both errors will always be reported together in the very first `terraform validate` pass
- C) Once the source path is fixed, the missing-argument error surfaces as "Missing required argument"
- D) The missing-argument error can be seen without ever fixing the source typo first

<details>
<summary>Answer</summary>

**A and C.** A broken `source` blocks `init` entirely, so nothing
downstream (including the missing-argument check) can be evaluated
until it's fixed — ruling out **D**. Once fixed, the missing
`subscription_email` argument correctly surfaces as "Missing required
argument." **B** overstates what's confirmed — this demo's own
Break-Fix explicitly flags that ordering as unverified.

</details>

---

**Q7. (True/False)** If CloudNova's platform team destroys only the
`aws_sns_topic_subscription` resource for an unconfirmed email
subscription, the recipient will stop being subscribed in AWS
immediately.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** An unconfirmed email subscription can't be force-removed
by destroying just the subscription resource — it's dropped from
Terraform's state but remains live in AWS. Only destroying the parent
topic (or manually unsubscribing/confirming out of band) actually
removes it.

</details>

---

**Q8. (Multiple Choice)** Why does this demo's Cleanup section destroy
the entire `aws_sns_topic`, rather than just the subscription?

- A) It's simpler to write in the lab guide, with no technical reason behind it
- B) Destroying the topic cascades and removes every subscription attached to it, regardless of confirmation status — the only reliable way to fully remove an unconfirmed email subscription
- C) AWS requires the topic to be destroyed first, before any subscription, in all cases
- D) `aws_sns_topic_subscription` cannot be destroyed on its own under any circumstance

<details>
<summary>Answer</summary>

**B.** Destroying the parent topic is the one action guaranteed to
fully remove an unconfirmed subscription from AWS, since the cascade
doesn't depend on confirmation status. **D** is false — a subscription
*can* be destroyed on its own; it just may not fully disappear from
AWS if it was never confirmed.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 7-8/8 | Import Anki cards, move to Demo 15 |
| 6/8 | Review the wrong answers, then proceed |
| 4-5/8 | Re-read the relevant sections, retry those questions |
| Below 4/8 | Re-read the full demo and redo the walkthrough before proceeding |
````