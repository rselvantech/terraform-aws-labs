# Demo 27 — DynamoDB

---

## Overview

26 gave Catalog and Orders their real, persistent backing store. This
demo does the equivalent for Cart — swapping it from its own built-in
default to real DynamoDB. The mechanics rhyme with Demo 26's (an IAM
grant added to an existing Pod Identity role, a connection-string
change, a real verification step) but the actual teardown story is
the deliberate opposite: DynamoDB is left standing, not torn down
every session, which means — unlike RDS — Cart's data genuinely
persists across a session boundary.

**Real-world scenario — CloudNova:**
Cart never needed a sidecar or an in-memory fallback the way Catalog
and Orders did — ADR-012's real testing confirmed it runs clean
against its own built-in default with zero extra infrastructure. That
made it the natural first candidate for demonstrating real polyglot
persistence: RDS for the relational services, DynamoDB for Cart, both
coexisting in the same system rather than picking one store for
everything. This demo makes that real.

**What this demo builds:**
```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — DynamoDB table                                               │
│  On-demand billing, left standing — a genuinely different lifecycle   │
│  from Demo 26's RDS instance                                           │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — IAM policy grant: DynamoDB actions, scoped to this table    │
│  Added to Cart's existing Pod Identity role (Demo 24)                 │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Swap-in: Cart (built-in default → DynamoDB)                 │
├─────────────────────────────────────────────────────────────────────────┤
│  PART D — Verify: write data, confirm it persists across a real       │
│  session-boundary test, not just within one session                   │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- `aws_dynamodb_table` with on-demand (`PAY_PER_REQUEST`) billing —
  no capacity planning, matching how small this table's actual traffic is
- Why DynamoDB sits in the "created once, left standing" bucket while
  RDS sits in "torn down every session" — a real, cost-driven
  asymmetry, not an inconsistency
- Scoping a DynamoDB IAM policy to a specific table ARN, the DynamoDB
  equivalent of Demo 26's instance+username scoping
- Actually testing data persistence across a session boundary, not
  just asserting it should work

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** one DynamoDB table, on-demand
billing, and an IAM policy statement appended to Cart's existing
Demo 24 role granting the specific DynamoDB actions Cart's own
read/write pattern needs, scoped to this table's ARN.

**Why DynamoDB is left standing while RDS is torn down every
session:** this is a genuine, cost-driven asymmetry stated explicitly
in this project's own teardown categorization (ADR-018), not an
oversight. DynamoDB's on-demand pricing means an idle table with no
traffic costs essentially nothing to leave running — there's no flat,
continuous fee the way RDS has. Since there's no cost argument for
tearing it down, and a real benefit (actual data persistence) to
leaving it standing, this table joins the state backend, ECR repo, and
ACM cert in the same once-created bucket.

**The consequence, worth testing rather than just asserting:** because
this table survives session boundaries, Cart's data should genuinely
still be there next session — a testable claim, not just a design
intention. This demo's own verification step writes real data and
confirms it's still readable, framed explicitly as a positive test of
persistence, not an assumption.

---

## Prerequisites

### Knowledge
- 26 completed — the RDS swap-in pattern this demo mirrors
  structurally, with the teardown-lifecycle contrast now made explicit
- 24 completed — Cart's existing Pod Identity role, this demo extends
  rather than replaces
- 23 completed — confirms Cart already runs clean against its own
  built-in default; this demo replaces that default with something
  real, not something Cart was failing without

### Required Tools

Same as prior Phase 3 demos — no new tools, only a new AWS resource
type (`aws_dynamodb_table`) and its corresponding IAM actions.

### Verify Cart Is Currently Running

```bash
kubectl get pods -l app=cart
kubectl logs deployment/cart --tail 20
# Confirm Cart is healthy against its current built-in default before
# swapping it — same discipline as Demo 26's Step 1 check
```

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Write an `aws_dynamodb_table` with on-demand billing
2. ✅ Explain why DynamoDB sits in a different teardown bucket than
   RDS, and what that asymmetry actually means for data persistence
3. ✅ Scope a DynamoDB IAM policy to a specific table ARN, granting
   only the actions Cart's own access pattern needs
4. ✅ Swap Cart from its built-in default to real DynamoDB
5. ✅ Design and run a real test that confirms data persistence across
   a session boundary, not just assert it should work

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| DynamoDB table (on-demand) | 25GB storage / 200M requests free, perpetual | **$0.00** | Cart's traffic at lab scale is far under this threshold |
| **Session total** | | **$0.00** | Created once, left standing — see Cleanup |

---

## Directory Structure

```
27-dynamodb/
├── README.md
├── 27-dynamodb-anki.csv
├── 27-dynamodb-quiz.md
├── src/
│   └── phase-3-onward/
│       ├── dynamodb.tf               # aws_dynamodb_table
│       └── iam-dynamodb-grant.tf     # DynamoDB actions for Cart
└── k8s/
    └── cart-deployment-dynamodb.yaml # DynamoDB connection env vars
```

---

## Recall Check — 26 (RDS)

Answer from memory before reading anything new:

1. What does `iam_database_authentication_enabled` actually change
   about RDS app-level connections?
2. Does IAM database authentication replace RDS's master/admin
   credential entirely?
3. Why doesn't RDS data persist across sessions in this project?

<details>
<summary>Answers</summary>

1. It allows connecting with a short-lived (15-minute) IAM-generated
   auth token instead of a static, shared password. The calling IAM
   identity must have `rds-db:connect` scoped to the specific instance
   and database username.
2. No — the master credential still exists, typically via
   `manage_master_user_password = true` for AWS-managed Secrets
   Manager rotation. IAM auth covers app-level connections, not
   internal admin operations.
3. RDS itself is torn down and re-applied every session (a real,
   continuous hourly fee, ADR-017/018). Only the schema/infrastructure
   survives via the same Terraform config re-applying — actual data
   does not.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `aws_dynamodb_table` | Resource | Cart's real, persistent backing store |
| `billing_mode = "PAY_PER_REQUEST"` | Resource argument | On-demand pricing — no capacity planning for a table this small |
| DynamoDB IAM actions (`GetItem`, `PutItem`, etc.) | IAM actions | Scoped to this table's ARN specifically, mirroring Demo 26's instance-scoped grant |

---

### Detailed Explanation of New Constructs

#### `aws_dynamodb_table` — On-Demand, No Capacity Planning

```hcl
resource "aws_dynamodb_table" "cart" {
  name         = "cloudnova-cart"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "customerId"

  attribute {
    name = "customerId"
    type = "S"
  }

  tags = {
    Name = "cloudnova-cart"
  }
}
```

`PAY_PER_REQUEST` means there's no provisioned read/write capacity to
size or scale — you pay per actual request, which at this project's
lab-scale traffic is effectively free within DynamoDB's perpetual free
tier. This is the same reasoning 22a applied when choosing
`use_lockfile` over a provisioned mechanism — match the pricing model
to the actual, small scale of the traffic involved, rather than
over-provisioning for load that doesn't exist.

---

#### The Teardown Asymmetry, Restated With Its Real Consequence

```
┌────────────────────────────────────────────────────────────────────────┐
│  RDS (Demo 26)                    │  DYNAMODB (this demo)              │
│  Flat, continuous hourly fee      │  On-demand — near-$0 idle          │
│  Torn down every session          │  Left standing, once created       │
│  Data does NOT persist across     │  Data DOES persist across          │
│  sessions                         │  sessions                          │
├────────────────────────────────────────────────────────────────────────┤
│  Same underlying project pattern (a service's swap from a temporary   │
│  default to a real store), genuinely different lifecycle for each,   │
│  driven entirely by each store's own cost profile — not an           │
│  inconsistency to explain away.                                       │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Lab Step-by-Step Guide

---

## Part A — Deploy the DynamoDB Table

### Step 1 — Navigate to the project config

```bash
cd terraform-aws-mastery/phase-3-real-aws-infrastructure/27-dynamodb/src/phase-3-onward
```

### Step 2 — Add dynamodb.tf

Create a file **dynamodb.tf** and add the below content:

```hcl
resource "aws_dynamodb_table" "cart" {
  name         = "cloudnova-cart"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "customerId"

  attribute {
    name = "customerId"
    type = "S"
  }

  tags = {
    Name    = "cloudnova-cart"
    Project = "cloudnova-retail-store-e2e"
  }
}
```

### Step 3 — Apply

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

```
⚠️ Simulated expected output

aws_dynamodb_table.cart: Creating...
aws_dynamodb_table.cart: Creation complete after 8s

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

> **Bolded takeaway:** 8 seconds, not 8 minutes — DynamoDB tables
> provision almost instantly, a real, worth-noticing contrast with
> Demo 26's RDS instance and 22d's EKS cluster, both of which take
> genuine minutes.

---

## Part B — IAM Grant: DynamoDB Actions

### Step 4 — Add iam-dynamodb-grant.tf

Create a file **iam-dynamodb-grant.tf** and add the below content:

```hcl
resource "aws_iam_role_policy" "cart_dynamodb" {
  role = aws_iam_role.service["cart"].id
  name = "dynamodb-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query"
      ]
      Resource = aws_dynamodb_table.cart.arn
    }]
  })
}
```

> **Same-as-Demo-26 note, restated:** `aws_iam_role.service["cart"]`
> is the exact role Demo 24 created — this demo adds one policy to it,
> the identical incremental-scoping pattern Demo 26 used for Catalog
> and Orders, just with DynamoDB actions and a table ARN instead of
> `rds-db:connect` and an instance+username ARN.

### Step 5 — Apply

```bash
terraform plan
terraform apply
```

---

## Part C — Swap-In: Cart

### Step 6 — Update Cart's Deployment

Create a file **k8s/cart-deployment-dynamodb.yaml** and add the below content:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cart
  template:
    metadata:
      labels:
        app: cart
    spec:
      serviceAccountName: cart-sa
      containers:
        - name: cart
          image: <ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-cart:latest
          ports:
            - containerPort: 8082
          env:
            - name: RETAIL_CART_PERSISTENCE_PROVIDER
              value: "dynamodb"
            - name: RETAIL_CART_PERSISTENCE_TABLE
              value: "cloudnova-cart"
            - name: AWS_REGION
              value: "us-east-2"
```

> ⚠️ [VERIFY — timing claim, docs only] The exact environment variable
> names Cart's real container expects for a DynamoDB connection aren't
> independently confirmed against the real image in this session —
> confirm against the app's own real configuration surface before
> treating these as final, the same caveat Demo 26 flagged for
> Catalog/Orders.

### Step 7 — Apply

```bash
kubectl apply -f k8s/cart-deployment-dynamodb.yaml
kubectl get pods -l app=cart
```

```
⚠️ Simulated expected output

NAME                       READY   STATUS    RESTARTS   AGE
cart-...                   1/1     Running   0          20s
```

> **Unlike Catalog's swap-in, there's no visible READY-count change
> here.** Cart was always `1/1` — it never had a sidecar to lose. The
> swap is entirely in the connection target, not the Pod's shape.

---

## Part D — Verify: Real Persistence Across a Session Boundary

### Step 8 — Write real data in this session

```bash
kubectl exec deployment/cart -- sh -c \
  "aws dynamodb put-item --table-name cloudnova-cart \
     --item '{\"customerId\": {\"S\": \"demo-customer-1\"}, \"items\": {\"S\": \"[]\"}}' \
     --region us-east-2"
```

```
⚠️ Simulated expected output

(empty response — a successful PutItem returns no body by default)
```

### Step 9 — Confirm the write, within this session

```bash
aws dynamodb get-item --table-name cloudnova-cart \
  --key '{"customerId": {"S": "demo-customer-1"}}' \
  --region us-east-2 --profile default
```

```
⚠️ Simulated expected output

{
    "Item": {
        "customerId": {"S": "demo-customer-1"},
        "items": {"S": "[]"}
    }
}
```

### Step 10 — The real persistence test — confirm this data is still there in a later session

> **This is the actual proof this demo's teardown-asymmetry claim is
> real, not just asserted.** Tear down and re-apply the rest of
> `phase-3-onward` (EKS cluster, VPC — everything in 22d/23's
> every-session bucket), start a genuinely new session, and re-run
> the same `get-item` call above **without re-writing the item
> first**. If the item is still there, this demo's central claim —
> that DynamoDB data persists while RDS data doesn't — is confirmed,
> not just described.

```bash
# In a later session, after tearing down and re-applying the cluster:
aws dynamodb get-item --table-name cloudnova-cart \
  --key '{"customerId": {"S": "demo-customer-1"}}' \
  --region us-east-2 --profile default
# Expected: the SAME item, still present — no write happened this
# session, yet the read succeeds
```

---

## Cleanup

**This table is left standing — do not run `terraform destroy` on
it.** Unlike Demo 26's RDS instance, there's no cost reason to tear
this down, and doing so would defeat the actual persistence this demo
just demonstrated.

```bash
terraform state list | grep dynamodb
# Confirm aws_dynamodb_table.cart and its IAM policy are present and
# untouched — this is a verification step, not a destroy step, the
# same pattern 22a/22b/22c/24 already established
```

```
Console → DynamoDB → Tables → cloudnova-cart → confirm it exists ✅
```

> ⚠️ **The EKS cluster, VPC, and RDS instance still get torn down at
> the end of every session as usual** — this Cleanup note applies
> specifically to the DynamoDB table and its IAM grant, not to
> everything else `phase-3-onward` contains.

---

## What You Learned

1. ✅ `aws_dynamodb_table` with `PAY_PER_REQUEST` billing needs no
   capacity planning — the pricing model matches this table's actual,
   small traffic scale.
2. ✅ DynamoDB provisions in seconds, a real contrast with RDS's
   minutes and EKS's 10–15 minutes.
3. ✅ DynamoDB sits in the "created once, left standing" bucket, a
   genuine, cost-driven asymmetry with RDS's every-session teardown —
   not an inconsistency.
4. ✅ A DynamoDB IAM policy scopes to a specific table ARN, the same
   incremental-scoping pattern Demo 26 used for RDS's instance+username scoping.
5. ✅ Data persistence across a session boundary is a testable claim,
   confirmed by actually tearing down and re-applying the rest of the
   environment and re-reading without re-writing — not something to
   just assert works.

**Key Takeaway:** This demo mirrors Demo 26's structure closely on
purpose — same IAM incremental-scoping pattern, same swap-in shape —
so that the one genuine difference (DynamoDB's persistence versus
RDS's non-persistence) stands out clearly as the actual point, not
buried under unrelated mechanical differences.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `aws_dynamodb_table`, `PAY_PER_REQUEST` | TA-004 Obj 4a — Resource configuration | On-demand billing avoids capacity-planning arguments entirely |
| DynamoDB IAM actions scoped to a table ARN | TA-004 Obj 4f — IAM permission scoping | Direct parallel to Demo 26's `rds-db:connect` scoping pattern |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Does every AWS data store in this project follow the same teardown policy?" | No — RDS is torn down every session, DynamoDB is left standing, driven by each store's own cost profile | Assuming a single, uniform teardown rule applies to every stateful resource regardless of its actual pricing model |
| "Is DynamoDB's PAY_PER_REQUEST billing mode always the correct choice?" | Not universally — it's the right fit for small, unpredictable, or low-traffic workloads specifically; provisioned capacity can be cheaper at very high, predictable, sustained load | Assuming on-demand billing is a strictly-better default in every case |

### Exam Task — Write a complete configuration

**Task:** Write an `aws_dynamodb_table` with on-demand billing and a
scoped IAM policy granting `GetItem`/`PutItem` to one application role.

**Official documentation:**
- [`aws_dynamodb_table` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table)

**What to practise:**
1. Open the page above — check `billing_mode` and `hash_key`/`attribute` together
2. Write the configuration from scratch without looking at this demo's `src/` files
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
resource "aws_dynamodb_table" "exam_task" {
  name         = "exam-task-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_iam_role_policy" "exam_task_dynamodb" {
  role = "exam-task-role"
  name = "dynamodb-access"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem"]
      Resource = aws_dynamodb_table.exam_task.arn
    }]
  })
}
```

**Arguments you must know without looking up:**
- Every `hash_key` needs a matching `attribute` block declaring its type
- `PAY_PER_REQUEST` needs no `read_capacity`/`write_capacity`
  arguments at all — those only apply to `PROVISIONED` billing mode

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `AccessDeniedException` on `PutItem`/`GetItem` from Cart's pod | IAM policy not yet applied, or scoped to the wrong table ARN | Confirm `aws_iam_role_policy.cart_dynamodb` applied successfully and references the real table ARN |
| Data missing in a later session's persistence test | The rest of `phase-3-onward` was torn down and re-applied including the DynamoDB table itself, not just the cluster | Confirm only the every-session-bucket resources (VPC, EKS, RDS) were destroyed — the DynamoDB table's own `terraform state` entry should be untouched |
| `ValidationException` on table creation | `hash_key` doesn't have a matching `attribute` block, or the type doesn't match the actual data | Confirm every key used in `hash_key`/`range_key` has a corresponding `attribute` block with the correct type (`S`, `N`, or `B`) |

---

## Break-Fix Scenario

One deliberate error. Diagnose using `terraform validate` — do not
look at the answer first.

```bash
cd src/break-fix/
terraform init
terraform validate
```

**broken.tf (relevant excerpt):**

```hcl
resource "aws_dynamodb_table" "cart" {
  name         = "break-fix-cart"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "customerId"

  attribute {
    name = "customer_id"   # Error — doesn't match hash_key exactly
    type = "S"
  }
}
```

<details>
<summary>Reveal answer — attempt diagnosis first</summary>

**Error — `attribute.name = "customer_id"` doesn't match `hash_key = "customerId"`**
DynamoDB requires an exact-name match between `hash_key` and its
declared `attribute` block. Terraform will show a validation error
along the lines of `hash_key` referencing an attribute that isn't
defined. This is the same class of error as a Terraform local-name
mismatch — a naming inconsistency, not a deeper structural problem.
Fix: change the attribute name to `customerId`, matching exactly.

</details>

**Cleanup:**

```bash
cd src/break-fix/
terraform destroy -auto-approve
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
```

---

## Interview Prep

**Q1. A teammate asks why RDS gets torn down every session but DynamoDB doesn't, when both are "just databases."**
Because the actual driver of this project's teardown policy is cost profile, not resource category. RDS has a flat, continuous hourly fee regardless of load — leaving it running between sessions costs real money whether or not anything's using it. DynamoDB's on-demand pricing means an idle table with no traffic costs essentially nothing — there's no cost argument for tearing it down, and a real benefit (actual data persistence) to leaving it standing. Both are databases, but they have genuinely different cost shapes, and this project's teardown policy tracks cost, not the general category "database."

**Q2. Someone asks how you'd actually prove DynamoDB data persists across sessions, rather than just trusting the design intention.**
By testing it directly, not by describing the design and assuming it holds. This demo's own verification does exactly that: write real data in one session, then in a genuinely later session — after tearing down and re-applying everything in the every-session bucket, including the cluster the write came from — read that same data back *without rewriting it first*. If the read succeeds, persistence is confirmed as an observed fact, not just a claim about how the architecture is supposed to behave. This is the same discipline ADR-012 used elsewhere in this project — real testing beating even well-reasoned inference.

**Q3. A reviewer notices this demo's IAM grant and swap-in structure closely mirror Demo 26's. Is that intentional, or should it have been more differentiated?**
It's intentional, and the similarity is doing real teaching work. Following the identical shape (IAM incremental scoping added to an existing Pod Identity role, a connection-string swap, a real verification step) means the one thing that's genuinely different — DynamoDB's persistence versus RDS's non-persistence — stands out clearly against a familiar backdrop, instead of getting lost among a dozen other structural differences that don't actually matter to the point being taught. Making two demos look similar on purpose, so the real difference is legible, is itself a deliberate instructional choice.

---

## Key Takeaways

1. **Teardown policy in this project tracks cost profile, not resource
   category.** "It's a database" doesn't determine the answer — flat
   continuous fees get torn down, near-free on-demand resources get
   left standing.

2. **DynamoDB IAM scoping mirrors RDS's pattern exactly** — a specific
   resource ARN, added to an existing Pod Identity role via
   incremental scoping, not a new identity mechanism per data store.

3. **Persistence is a testable claim, not just a design description.**
   This demo's own verification proves it by actually tearing down and
   rebuilding the surrounding environment and reading data back
   without rewriting it — the same discipline as ADR-012's real
   `docker run` testing elsewhere in this project.

4. **Structural similarity between two demos can be deliberate, not
   accidental.** Mirroring Demo 26's shape closely makes the one real
   difference (persistence) stand out clearly, rather than burying it
   under unrelated mechanical variation.

5. **On-demand billing isn't universally the "better" choice — it's
   the right fit for this table's actual, small, unpredictable
   traffic.** Provisioned capacity can be more cost-effective at very
   high, sustained, predictable load — know the trade-off, not just
   the default this project happened to pick.

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws dynamodb put-item --table-name <TABLE> --item '<JSON>' --region <REGION>` | Writes an item directly, useful for this demo's persistence test |
| `aws dynamodb get-item --table-name <TABLE> --key '<JSON>' --region <REGION>` | Reads a specific item back — the actual verification for both within-session and cross-session persistence |
| `terraform state list | grep dynamodb` | Confirms the table and its IAM policy exist without risking an accidental destroy |
| `terraform init` / `validate` / `plan` / `apply` | Standard workflow, unchanged from prior demos |

---

## Next Demo

**Demo 28 — Lambda + API Gateway:** must follow this demo specifically
— the SNS→Lambda→DynamoDB analytics flow targets this table, which
didn't exist before now. Checkout publishes an order-placed event;
Lambda processes it into this table's data, and a read-only
`GET /analytics/orders` endpoint reads it back via API Gateway.

---

## Appendix — Anki Cards

**27-dynamodb-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::27-dynamodb
#separator:Comma
#columns:Front,Back,Tags
"Why does DynamoDB sit in the 'created once, left standing' bucket while RDS is torn down every session?","Cost profile, not resource category. RDS has a flat, continuous hourly fee regardless of load. DynamoDB's on-demand pricing means an idle table with no traffic costs essentially nothing, so there's no cost argument for tearing it down.","demo27,dynamodb,teardown-policy,adr-018"
"What does billing_mode = PAY_PER_REQUEST mean for a DynamoDB table?","On-demand pricing - no read/write capacity to size or plan for. You pay per actual request, matching the pricing model to small/unpredictable traffic rather than over-provisioning.","demo27,dynamodb,ta004-obj4a"
"What must match exactly between hash_key and a DynamoDB table's attribute block?","The name, exactly, case-sensitive. hash_key = \"customerId\" requires an attribute block with name = \"customerId\" - a mismatch (e.g. customer_id) fails validation.","demo27,dynamodb,gotcha"
"How does this demo's IAM scoping for DynamoDB mirror Demo 26's RDS scoping?","Both add a policy to an existing Pod Identity role (Demo 24), scoped to a specific resource ARN (the table ARN here, instance+username there) - same incremental-scoping pattern, different resource type.","demo27,dynamodb,iam,ta004-obj4f"
"How do you actually prove DynamoDB data persists across sessions, rather than assume it?","Write data in one session, then in a genuinely later session (after tearing down/re-applying the every-session-bucket resources), read it back WITHOUT rewriting it first. A successful read confirms persistence as an observed fact.","demo27,dynamodb,verification,persistence"
```

---

## Appendix — Quiz

**27-dynamodb-quiz.md:**

````markdown
# Quiz — Demo 27: DynamoDB

> Question types: True/False, Multiple Choice — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 28.

---

**Q1. (Multiple Choice)** Why does DynamoDB sit in a different
teardown bucket than RDS in this project?

- A) DynamoDB is a NoSQL database and RDS is relational — the distinction is data model, not cost
- B) Cost profile — RDS has a flat, continuous hourly fee; DynamoDB's on-demand pricing means near-$0 idle cost
- C) DynamoDB tables can't technically be deleted via Terraform
- D) RDS is always more expensive than DynamoDB regardless of usage pattern

<details>
<summary>Answer</summary>

**B.** The teardown policy tracks actual cost profile, not the
general category of "database" or the underlying data model.

</details>

---

**Q2. (True/False)** `PAY_PER_REQUEST` billing mode requires setting
`read_capacity` and `write_capacity` arguments.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Those arguments only apply to `PROVISIONED` billing
mode — `PAY_PER_REQUEST` needs neither, since there's no capacity to
plan for.

</details>

---

**Q3. (Multiple Choice)** A table's `hash_key = "customerId"` but its
`attribute` block has `name = "customer_id"`. What happens?

- A) Terraform automatically reconciles the casing difference
- B) A validation error — the attribute name must match `hash_key` exactly
- C) The table is created successfully with a default key instead
- D) No error, but reads will silently fail at runtime

<details>
<summary>Answer</summary>

**B.** DynamoDB requires an exact name match between `hash_key` and
its declared `attribute` — a mismatch fails validation before the
table is ever created.

</details>

---

**Q4. (Multiple Choice)** What's the correct way to confirm DynamoDB
data genuinely persists across a session boundary?

- A) Read the ADR that states DynamoDB is left standing — that's sufficient confirmation
- B) Write data in one session, then in a later session read it back without rewriting it first
- C) Check that `terraform plan` shows no changes for the table
- D) Confirm the table's billing mode is `PAY_PER_REQUEST`

<details>
<summary>Answer</summary>

**B.** This is the actual, observed test — a design document stating
data should persist is a claim, not a confirmation; reading back
unwritten-this-session data is the real proof.

</details>

---

**Q5. (True/False)** This demo's IAM policy for Cart's DynamoDB access
uses a fundamentally different scoping mechanism than Demo 26's RDS
IAM grant.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Both use the identical incremental-scoping pattern —
adding a policy to an existing Pod Identity role, scoped to a specific
resource ARN. The resource type differs (table vs. instance+username),
the pattern doesn't.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 5/5 | Import Anki cards, move to Demo 28 |
| 4/5 | Review the wrong answer, then proceed |
| 3/5 | Re-read the relevant sections, retry those questions |
| Below 3/5 | Re-read the full demo before proceeding |
````