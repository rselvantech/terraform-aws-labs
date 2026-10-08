# Demo 26 — RDS

---

## Overview

25 gave RDS somewhere to live. This demo actually deploys it — a real
PostgreSQL instance in the isolated subnet tier — and completes the
swap-in this whole project has been staging toward since ADR-012's
real `docker run` testing back before Demo 23 was even built: Catalog
moves from its MariaDB sidecar to real RDS, and Orders moves from its
built-in H2 in-memory database to real RDS. Both services get their
actual, persistent backing store for the first time.

**Real-world scenario — CloudNova:**
The sidecar and the in-memory database both proved the deployment
pattern worked — neither was ever meant to be the real, ongoing data
store. Now that the isolated subnet tier exists, it's time to replace
both temporary arrangements with the actual, production-shaped
database this system is meant to run on. This demo also closes the
IAM gap Demo 24 deliberately left open: Catalog and Orders' Pod
Identity roles get RDS access for the first time, scoped to exactly
this database, granted now because now is when it actually exists.

**What this demo builds:**
```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — RDS PostgreSQL instance                                      │
│  Deployed into 25's isolated subnet tier, IAM DB auth enabled          │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — IAM policy grant: rds-db:connect                             │
│  Added to Catalog and Orders' existing Pod Identity roles (Demo 24)    │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Swap-in: Catalog (sidecar → RDS), Orders (H2 → RDS)          │
│  Connection strings changed, MariaDB sidecar removed                   │
├─────────────────────────────────────────────────────────────────────────┤
│  PART D — Verify: both services connect to real RDS via IAM auth       │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- `aws_db_instance` with `iam_database_authentication_enabled = true`
  — connecting without a shared, long-lived database password
- Why the master credential still uses AWS-managed Secrets Manager
  rotation, even though app-level access goes through IAM auth
- Why this demo grants the `rds-db:connect` IAM permission now, not at
  Demo 24 — the resource this permission references genuinely didn't
  exist until this demo
- The real consequence of RDS being torn down every session: data
  itself does not persist across sessions, only the schema/infrastructure

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** one RDS PostgreSQL instance in 25's
isolated subnets, a security group allowing inbound PostgreSQL traffic
only from the EKS cluster's own security group, and an IAM policy
statement appended to Catalog and Orders' existing Demo 24 roles
granting `rds-db:connect` scoped to this specific instance and their
own database usernames.

**Why this demo adds to Demo 24's roles instead of creating new
ones:** Catalog and Orders already have IAM identity — this demo grants
them one additional, narrowly-scoped permission, exactly the
incremental-scoping pattern ADR-015 established. There's no reason to
create parallel roles or a separate identity mechanism for database
access specifically.

**Why RDS itself is torn down every session, unlike everything else
this demo touches:** RDS instances have a real, continuous hourly fee.
Per this project's own teardown categorization (ADR-017/018), that
puts it in the every-session bucket alongside the EKS cluster and NAT
Gateway — the IAM policy grant and the isolated subnet tier it lives
in are unaffected by this (once-created, left-standing infrastructure
for the subnets; the IAM statement itself costs nothing to leave in
place), but the actual database instance is destroyed and recreated
every session, same as compute.

**The real consequence, stated explicitly:** since RDS itself is
destroyed each session, Catalog and Orders' actual *data* does not
survive between sessions — only the schema, re-created by this same
Terraform config on every apply. Don't design a Pass Criterion or demo
verification that assumes data persisted from a prior session; verify
against data written and read within the same session instead.

---

## Prerequisites

### Knowledge
- 25 completed — the isolated subnet tier this RDS instance deploys into
- 24 completed — Catalog and Orders' existing Pod Identity roles, this
  demo's IAM grant extends rather than replaces
- 23 completed — Catalog's current MariaDB sidecar and Orders' current
  H2 in-memory setup, both replaced in this demo

### Required Tools

Same as prior Phase 3 demos — no new tools, only a new AWS resource
type (`aws_db_instance`) and a new IAM action (`rds-db:connect`).

### Verify the Isolated Subnet Tier Is Ready

```bash
terraform state list | grep intra
# Confirm 25's isolated subnets and S3 endpoint are present before
# deploying RDS into them
```

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Write an `aws_db_instance` with IAM database authentication
   enabled, deployed into isolated subnets
2. ✅ Explain why the master credential still uses Secrets
   Manager-rotated password auth even though app-level access uses IAM
3. ✅ Grant a narrowly-scoped `rds-db:connect` IAM permission to an
   existing Pod Identity role
4. ✅ Swap Catalog and Orders from their temporary backing stores to
   real RDS, generating an IAM auth token instead of using a static password
5. ✅ Explain why RDS data does not persist across sessions in this
   project, and why that's a deliberate, cost-driven consequence

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| RDS PostgreSQL (single-AZ, `db.t4g.micro`) | Free tier eligible if the account's 12-month window is open | ~$0.00–0.02/hr | Likely free tier; genuinely small either way |
| RDS storage (20GB gp3, minimum) | 20GB free tier | ~$0.00 | Within free tier at this size |
| **Session total** | | **~$0.00–0.02/hr** | **Torn down at the end of every session — see Cleanup** |

---

## Directory Structure

```
26-rds/
├── README.md
├── 26-rds-anki.csv
├── 26-rds-quiz.md
├── src/
│   └── phase-3-onward/
│       ├── rds.tf                    # aws_db_instance, subnet group, security group
│       └── iam-rds-grant.tf          # rds-db:connect for Catalog/Orders
└── k8s/
    ├── catalog-deployment-rds.yaml   # sidecar removed, RDS connection env vars
    └── orders-deployment-rds.yaml    # H2 replaced, RDS connection env vars
```

---

## Recall Check — 25 (VPC Extension: Isolated Subnets + Endpoints)

Answer from memory before reading anything new:

1. What structurally distinguishes an isolated subnet from a private one?
2. What is the VPC module's own argument name for the isolated subnet tier?
3. Which AWS services support the free Gateway VPC endpoint type?

<details>
<summary>Answers</summary>

1. Route table shape — isolated subnets have no route to the internet
   at all, in either direction. Private subnets still route outbound
   traffic through a NAT Gateway.
2. `intra_subnets` — not "isolated_subnets."
3. Only S3 and DynamoDB. Every other AWS service requires the paid
   Interface endpoint type.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `aws_db_instance` | Resource | The RDS PostgreSQL instance itself |
| `iam_database_authentication_enabled` | Resource argument | Allows connections authenticated via IAM, not just a static password |
| `manage_master_user_password` | Resource argument | AWS-managed Secrets Manager rotation for the admin credential specifically |
| `rds-db:connect` | IAM action | The specific permission an IAM identity needs to open an IAM-authenticated RDS connection |
| `aws rds generate-db-auth-token` | AWS CLI command | Generates a short-lived auth token in place of a static password |

---

### Detailed Explanation of New Constructs

#### IAM Database Authentication — App Access Without a Shared Secret

```hcl
resource "aws_db_instance" "postgres" {
  identifier     = "cloudnova-postgres"
  engine         = "postgres"
  engine_version = "16.4"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  iam_database_authentication_enabled = true   # app-level connections use IAM, not a shared password

  manage_master_user_password = true   # admin credential still uses Secrets Manager rotation
  username                    = "cloudnova_admin"

  skip_final_snapshot = true   # demo/lab setting — never do this in a real production database
}
```

**Why the master credential is different from app access:** IAM
database authentication only covers ordinary connections — it doesn't
replace the database's own root/admin credential, which RDS itself
still needs for internal management operations. `manage_master_user_password
= true` has AWS generate and rotate that admin credential automatically
via Secrets Manager, so there's still no password this project's own
Terraform code or `.tf` files ever need to store directly — it's
managed, just via a different mechanism than the app-level IAM tokens.

**How app-level IAM auth actually works, mechanically:**

```bash
# Instead of a static password, generate a short-lived token:
TOKEN=$(aws rds generate-db-auth-token \
  --hostname cloudnova-postgres.xxxxx.us-east-2.rds.amazonaws.com \
  --port 5432 \
  --username catalog_app \
  --region us-east-2)

# The token is used as the password for this one connection attempt —
# it expires after 15 minutes and can't be reused past that window
```

The IAM identity generating this token must have `rds-db:connect`
permission scoped to the specific database instance and username — the
IAM policy grant Part B adds to Catalog and Orders' existing roles.

---

#### `rds-db:connect` — Scoped to Instance and Database Username

```hcl
resource "aws_iam_role_policy" "catalog_rds_connect" {
  role = aws_iam_role.service["catalog"].id   # from Demo 24
  name = "rds-connect"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds-db:connect"]
      Resource = "arn:aws:rds-db:us-east-2:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_instance.postgres.resource_id}/catalog_app"
    }]
  })
}
```

**What's genuinely scoped here:** not just "this service can connect
to RDS in general" — the resource ARN names the specific instance
(`resource_id`) *and* the specific database username (`catalog_app`).
Orders' equivalent grant references the same instance but a different
username (`orders_app`) — Catalog's IAM identity has no path to
authenticate as Orders' database user, even though both connect to the
same physical instance.

---

## Lab Step-by-Step Guide

---

## Part A — Deploy RDS

### Step 1 — Navigate to the project config

```bash
cd terraform-aws-mastery/phase-3-real-aws-infrastructure/26-rds/src/phase-3-onward
```

### Step 2 — Add rds.tf

Create a file **rds.tf** and add the below content:

```hcl
resource "aws_db_subnet_group" "rds" {
  name       = "cloudnova-rds-subnet-group"
  subnet_ids = module.vpc.intra_subnets

  tags = {
    Name = "cloudnova-rds-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name   = "cloudnova-rds-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks_sg.security_group_id]   # only the EKS node/pod SG, nothing else
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "postgres" {
  identifier     = "cloudnova-postgres"
  engine         = "postgres"
  engine_version = "16.4"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  iam_database_authentication_enabled = true

  manage_master_user_password = true
  username                    = "cloudnova_admin"

  skip_final_snapshot = true   # demo/lab setting only

  tags = {
    Name = "cloudnova-postgres"
  }
}
```

> ⚠️ [VERIFY — timing claim, docs only] Real RDS instance creation
> typically takes 5–10 minutes — shorter than EKS's 10–15, but still a
> genuine wait, not an instant operation. Confirm current provisioning
> timing against your own real apply.

### Step 3 — Apply

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

```
⚠️ Simulated expected output

aws_db_instance.postgres: Still creating... [7m30s elapsed]
aws_db_instance.postgres: Creation complete after 8m12s

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

---

## Part B — IAM Grant: `rds-db:connect`

### Step 4 — Add iam-rds-grant.tf

Create a file **iam-rds-grant.tf** and add the below content:

```hcl
resource "aws_iam_role_policy" "catalog_rds_connect" {
  role = aws_iam_role.service["catalog"].id
  name = "rds-connect"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds-db:connect"]
      Resource = "arn:aws:rds-db:us-east-2:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_instance.postgres.resource_id}/catalog_app"
    }]
  })
}

resource "aws_iam_role_policy" "orders_rds_connect" {
  role = aws_iam_role.service["orders"].id
  name = "rds-connect"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds-db:connect"]
      Resource = "arn:aws:rds-db:us-east-2:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_instance.postgres.resource_id}/orders_app"
    }]
  })
}
```

> **Same-as-Demo-24 note, restated:** `aws_iam_role.service["catalog"]`
> and `aws_iam_role.service["orders"]` are the exact roles Demo 24
> created — this demo adds a policy to each, it doesn't create new roles.

### Step 5 — Apply

```bash
terraform plan
terraform apply
```

---

## Part C — Swap-In: Catalog and Orders

### Step 6 — Update Catalog's Deployment — remove the sidecar, add RDS env vars

Create a file **k8s/catalog-deployment-rds.yaml** and add the below content:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: catalog
  template:
    metadata:
      labels:
        app: catalog
    spec:
      serviceAccountName: catalog-sa
      containers:
        - name: catalog
          image: <ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-catalog:latest
          ports:
            - containerPort: 8081
          env:
            - name: RETAIL_UI_CATALOG_PERSISTENCE_PROVIDER
              value: "postgres"
            - name: RETAIL_UI_CATALOG_PERSISTENCE_ENDPOINT
              value: "cloudnova-postgres.xxxxx.us-east-2.rds.amazonaws.com:5432"
            - name: RETAIL_UI_CATALOG_PERSISTENCE_USER
              value: "catalog_app"
            - name: RETAIL_UI_CATALOG_PERSISTENCE_IAM_AUTH
              value: "true"
      # ↑ no catalog-db sidecar container here anymore — RDS replaces it entirely
```

> ⚠️ [VERIFY — timing claim, docs only] The exact environment variable
> names Catalog's real container expects for a Postgres/IAM-auth
> connection aren't independently confirmed against the real image in
> this session — treat these as illustrative, and confirm against the
> app's own real configuration surface (or its `docker run`
> documentation) before running this for real.

### Step 7 — Update Orders' Deployment — replace H2 with RDS env vars

Create a file **k8s/orders-deployment-rds.yaml** and add the below content:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
spec:
  replicas: 1
  selector:
    matchLabels:
      app: orders
  template:
    metadata:
      labels:
        app: orders
    spec:
      serviceAccountName: orders-sa
      containers:
        - name: orders
          image: <ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-orders:latest
          ports:
            - containerPort: 8083
          env:
            - name: RETAIL_ORDERS_PERSISTENCE_PROVIDER
              value: "postgres"
            - name: RETAIL_ORDERS_PERSISTENCE_ENDPOINT
              value: "cloudnova-postgres.xxxxx.us-east-2.rds.amazonaws.com:5432"
            - name: RETAIL_ORDERS_PERSISTENCE_USER
              value: "orders_app"
            - name: RETAIL_ORDERS_PERSISTENCE_IAM_AUTH
              value: "true"
```

### Step 8 — Apply both

```bash
kubectl apply -f k8s/catalog-deployment-rds.yaml
kubectl apply -f k8s/orders-deployment-rds.yaml
kubectl get pods -l app=catalog
kubectl get pods -l app=orders
```

```
⚠️ Simulated expected output

NAME                       READY   STATUS    RESTARTS   AGE
catalog-...                1/1     Running   0          30s
orders-...                 1/1     Running   0          30s
```

> **Bolded takeaway:** Catalog now shows `1/1`, not `2/2` — the
> MariaDB sidecar is genuinely gone, replaced entirely by real RDS.
> This is the concrete, visible proof the swap-in happened, the same
> way `2/2` was the proof the sidecar existed back in Demo 23.

---

## Part D — Verify

### Step 9 — Confirm both services connect using IAM auth, not a static password

```bash
kubectl exec deployment/catalog -c catalog -- sh -c \
  "aws rds generate-db-auth-token \
     --hostname cloudnova-postgres.xxxxx.us-east-2.rds.amazonaws.com \
     --port 5432 --username catalog_app --region us-east-2 | head -c 50"
```

```
⚠️ Simulated expected output

cloudnova-postgres.xxxxx.us-east-2.rds.amazonaws.com:5432/?Action=connect...
```

### Step 10 — Confirm each service can only authenticate as its own database user

```bash
# From Catalog's pod, attempting Orders' database username should fail —
# Catalog's IAM role only has rds-db:connect scoped to catalog_app
kubectl exec deployment/catalog -c catalog -- sh -c \
  "aws rds generate-db-auth-token --hostname cloudnova-postgres.xxxxx.us-east-2.rds.amazonaws.com \
   --port 5432 --username orders_app --region us-east-2 > /dev/null; echo \$?"
# Token generation itself may succeed (it's just a signed URL), but
# the actual database connection attempt using it should be rejected
# by RDS, since Catalog's IAM identity has no rds-db:connect grant
# scoped to orders_app
```

> **Bolded takeaway:** `generate-db-auth-token` doesn't itself check
> permissions — it's a locally-signed request. The actual enforcement
> happens when RDS receives the connection and checks whether the
> calling IAM identity has `rds-db:connect` for that specific
> instance+username pair. Don't confuse "the token generated
> successfully" with "the connection will succeed."

### Step 11 — Confirm real data write/read works within this session

```bash
kubectl logs deployment/catalog --tail 50
# Confirm no connection errors, and any startup schema-creation
# messages complete successfully
```

---

## Cleanup

**Torn down every session** — RDS has a real, continuous hourly fee,
placing it in the same every-session bucket as the EKS cluster and NAT
Gateway (ADR-017/018).

```bash
terraform destroy -target=aws_db_instance.postgres -target=aws_db_subnet_group.rds -target=aws_security_group.rds
# Or, if ending the session entirely, follow 22d's full teardown for
# the whole phase-3-onward config
```

```
⚠️ Simulated expected output

Destroy complete! Resources: 3 destroyed.
```

```
Console → RDS → Databases → confirm cloudnova-postgres: GONE ✅
```

> ⚠️ **The IAM policy grants (`catalog_rds_connect`, `orders_rds_connect`)
> can be left standing** — they're near-free IAM statements referencing
> an instance that will be recreated with the same `resource_id`-based
> ARN pattern next session, following the same once-created,
> left-standing lifecycle as the rest of Demo 24's IAM work. Confirm
> this holds for your actual setup rather than assuming it silently.

---

## What You Learned

1. ✅ `iam_database_authentication_enabled` lets app-level connections
   use short-lived IAM tokens instead of a shared, static password.
2. ✅ The RDS master credential still uses Secrets Manager-managed
   password rotation — IAM auth covers ordinary app connections, not
   admin-level database operations.
3. ✅ `rds-db:connect` permissions are scoped to a specific instance
   *and* database username together — one service's IAM identity has
   no path to authenticate as another service's database user.
4. ✅ Catalog's sidecar and Orders' H2 in-memory database are both
   genuinely gone after this demo's swap-in, replaced by real,
   persistent-schema RDS.
5. ✅ RDS data does not survive across sessions in this project — only
   the schema/infrastructure does, re-created by the same Terraform
   config every time.

**Key Takeaway:** This demo completes a chain staged since before
Demo 23 was even built — the temporary Catalog sidecar and Orders'
in-memory database were always meant to be replaced by exactly this.
Recognizing "we knew this was coming" versus treating it as a new
decision is worth noticing.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `aws_db_instance`, `iam_database_authentication_enabled` | TA-004 Obj 4a — Resource configuration | Provider-specific resource; IAM auth is a real, commonly-tested RDS feature |
| `manage_master_user_password` | TA-004 Obj 4a | Know this delegates admin-credential rotation to Secrets Manager automatically |
| `rds-db:connect` scoped to instance + username | TA-004 Obj 4f — IAM trust/permission scoping | A genuinely fine-grained permission pattern worth recognizing |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Does enabling IAM database authentication replace the database's master password entirely?" | No — the master/admin credential still exists and typically uses managed rotation; IAM auth covers app-level connections | Assuming IAM auth eliminates all passwords everywhere on the instance |
| "If two services share the same RDS instance, do they automatically share database access?" | No — `rds-db:connect` is scoped per instance *and* per database username; sharing an instance doesn't imply shared access | Assuming instance-level access is granted uniformly to anything that can reach the instance over the network |

### Exam Task — Write a complete configuration

**Task:** Write an `aws_db_instance` with IAM database authentication
enabled, and a scoped `rds-db:connect` IAM policy for one application role.

**Official documentation:**
- [`aws_db_instance` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance)

**What to practise:**
1. Open the page above — check `iam_database_authentication_enabled` specifically
2. Write the configuration from scratch without looking at this demo's `src/` files
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
resource "aws_db_instance" "exam_task" {
  identifier                          = "exam-task-db"
  engine                               = "postgres"
  instance_class                       = "db.t4g.micro"
  allocated_storage                    = 20
  iam_database_authentication_enabled  = true
  manage_master_user_password          = true
  username                             = "admin"
  skip_final_snapshot                  = true
}

resource "aws_iam_role_policy" "exam_task_connect" {
  role = "exam-task-role"
  name = "rds-connect"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds-db:connect"]
      Resource = "arn:aws:rds-db:us-east-2:123456789012:dbuser:${aws_db_instance.exam_task.resource_id}/app_user"
    }]
  })
}
```

**Arguments you must know without looking up:**
- The `rds-db:connect` resource ARN format includes the instance's
  `resource_id` output *and* the specific database username — both
  parts matter for scoping

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| Connection refused from Catalog/Orders pods to RDS | Security group doesn't allow inbound from the EKS security group specifically | Confirm `aws_security_group.rds`'s ingress rule references the actual EKS node/pod security group ID |
| `rds-db:connect` denied despite the IAM policy existing | Resource ARN's `resource_id` or username doesn't match exactly | Confirm `aws_db_instance.postgres.resource_id` resolves correctly, and the username in the ARN matches the actual database user the app connects as |
| Auth token generated but connection still fails | The database user itself may not exist yet inside PostgreSQL, separate from the IAM grant | Confirm the `catalog_app`/`orders_app` database users were actually created inside PostgreSQL with `rds_iam` role membership — an IAM grant alone doesn't create the DB-side user |
| RDS instance creation takes longer than expected | Normal, real AWS provisioning time | See VERIFY note in Part A — 5–10 minutes is typical, not a sign of a stuck operation |

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
resource "aws_iam_role_policy" "catalog_rds_connect" {
  role = aws_iam_role.service["catalog"].id
  name = "rds-connect"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds-db:connect"]
      Resource = "arn:aws:rds-db:us-east-2:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_instance.postgres.resource_id}/orders_app"
      # Error: this is Catalog's policy, but the resource ARN references orders_app
    }]
  })
}
```

<details>
<summary>Reveal answer — attempt diagnosis first</summary>

**Error — Catalog's policy grants access to `orders_app`, not `catalog_app`**
This won't fail `terraform validate` or `plan` at all — it's valid
HCL, valid JSON, and a syntactically correct IAM policy. It's a
logic error: Catalog's role now has `rds-db:connect` scoped to
Orders' database username, and Catalog itself has no grant for its
own `catalog_app` username at all. This is exactly the class of error
this demo's own Part D verification (checking each service can *only*
authenticate as its own username) exists to catch — a policy that
looks structurally fine but grants the wrong scope. Fix: correct the
resource ARN to reference `catalog_app`.

</details>

**Cleanup:**

```bash
cd src/break-fix/
terraform destroy -auto-approve
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
```

---

## Interview Prep

**Q1. A teammate asks why this project doesn't just use a shared database password stored in Kubernetes Secrets, the way many tutorials do.**
Because IAM database authentication removes the shared-secret problem entirely — there's no long-lived password to rotate, leak, or accidentally commit anywhere. Each service generates a short-lived (15-minute) auth token on demand, using its own existing IAM identity, and RDS checks that identity's actual permissions at connection time. This is also more auditable — every connection attempt is tied to a specific IAM identity in CloudTrail, rather than "whoever had the shared password." The trade-off is a bit more setup complexity than a static password, but for a project already built around per-service IAM identity (Demo 24), it's a natural extension rather than new complexity.

**Q2. Someone asks why the RDS master credential doesn't also use IAM authentication, if it's supposedly better.**
Because IAM database authentication only covers ordinary application-level connections — the database's own internal admin/root credential is a different mechanism RDS itself depends on for certain management operations that IAM auth doesn't cover. `manage_master_user_password = true` still avoids a hardcoded secret in Terraform code — AWS generates and rotates that credential automatically via Secrets Manager — it's just a different automated mechanism than the app-level IAM tokens, not a contradiction of the "no shared secrets" principle.

**Q3. A reviewer asks how this demo's IAM policy makes sure Catalog can't accidentally read or write Orders' database rows, given they share the same RDS instance.**
Two separate layers work together here. First, the IAM `rds-db:connect` grant is scoped to a specific database *username*, not just the instance — Catalog's role can only authenticate as `catalog_app`, never `orders_app`, so it can't even open a connection under Orders' identity. Second, and just as important, actual PostgreSQL-level permissions (which tables each database user can read/write) still need to be configured inside the database itself — the IAM layer controls *who can connect as which user*, not what that user is allowed to do once connected. Both layers matter; IAM alone isn't a complete data-isolation story without correct PostgreSQL-side grants too.

---

## Key Takeaways

1. **IAM database authentication replaces static passwords for
   app-level connections, not the database's own admin credential.**
   Both mechanisms avoid hardcoded secrets, but they're not the same
   thing, and the exam trap is assuming one implies the other.

2. **`rds-db:connect` is scoped to instance *and* username together.**
   Sharing an RDS instance across services doesn't mean sharing
   database access — each service's grant is specific to its own
   database username.

3. **A structurally valid IAM policy can still grant the wrong scope.**
   `terraform validate`/`plan` won't catch a policy that's
   syntactically correct but references the wrong resource ARN — this
   demo's own Break-Fix is exactly that failure mode.

4. **RDS data doesn't survive session teardown in this project.** Only
   schema/infrastructure persists via the same Terraform config
   re-applying — verify against data written within the current
   session, not something assumed to still be there from before.

5. **This demo fulfills a swap-in staged since before Demo 23 was
   built.** ADR-012's real testing predicted exactly this outcome —
   recognizing planned, deferred work versus new decisions is worth
   noticing as a pattern across this whole project.

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws rds generate-db-auth-token --hostname <HOST> --port 5432 --username <USER> --region <REGION>` | Generates a short-lived (15-min) IAM auth token in place of a static password |
| `kubectl get pods -l app=catalog` | Confirms Catalog now shows `1/1`, not `2/2` — the sidecar is gone |
| `terraform destroy -target=<RESOURCE>` | Destroys a specific resource without tearing down the whole config |
| `terraform init` / `validate` / `plan` / `apply` | Standard workflow, unchanged from prior demos |

---

## Next Demo

**Demo 27 — DynamoDB:** the equivalent swap-in for Cart — from its
own built-in default to real DynamoDB, with the same IAM
incremental-scoping pattern this demo just established for RDS, but a
genuinely different teardown lifecycle (DynamoDB is left standing, not
torn down every session).

---

## Appendix — Anki Cards

**26-rds-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::26-rds
#separator:Comma
#columns:Front,Back,Tags
"What does iam_database_authentication_enabled actually change about RDS app-level connections?","Allows connecting with a short-lived (15-min) IAM-generated auth token instead of a static, shared password. The calling IAM identity must have rds-db:connect scoped to the specific instance and database username.","demo26,rds,iam-auth,ta004-obj4a"
"Does IAM database authentication replace RDS's master/admin credential entirely?","No - IAM auth covers ordinary app-level connections. The master credential still exists, typically via manage_master_user_password = true for AWS-managed Secrets Manager rotation - a different automated mechanism, not a contradiction.","demo26,rds,iam-auth,gotcha"
"What two things does an rds-db:connect resource ARN scope access to together?","The specific RDS instance (via its resource_id) AND the specific database username - both together. One service's IAM identity has no path to authenticate as a different service's database user, even on the same instance.","demo26,rds,iam,ta004-obj4f"
"Why doesn't RDS data persist across sessions in this project?","RDS itself is torn down and re-applied every session (real, continuous hourly fee, ADR-017/018). Only the schema/infrastructure survives via the same Terraform config re-applying - actual data does not.","demo26,rds,teardown-policy"
"Can a structurally valid, syntactically correct IAM policy still grant the wrong access scope?","Yes - terraform validate/plan check syntax and schema, not whether a resource ARN references the intended username. A policy referencing the wrong database username is valid HCL/JSON but grants incorrect access.","demo26,rds,iam,gotcha"
```

---

## Appendix — Quiz

**26-rds-quiz.md:**

````markdown
# Quiz — Demo 26: RDS

> Question types: True/False, Multiple Choice — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 27.

---

**Q1. (Multiple Choice)** What does enabling
`iam_database_authentication_enabled` on an RDS instance actually
change about app-level connections?

- A) It removes the need for any database user accounts at all
- B) Connections can use a short-lived IAM-generated token instead of a static password
- C) It disables the master/admin credential entirely
- D) It requires an OIDC identity provider to be configured on the RDS instance

<details>
<summary>Answer</summary>

**B.** IAM auth adds a token-based connection option for app-level
access — it doesn't eliminate database users or the master credential,
and has nothing to do with OIDC.

</details>

---

**Q2. (True/False)** Enabling IAM database authentication means the
RDS master/admin credential no longer needs to exist.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** The master credential still exists — IAM auth covers
ordinary app connections, not the database's own internal admin
operations. `manage_master_user_password = true` still avoids a
hardcoded secret, via a different (Secrets Manager) mechanism.

</details>

---

**Q3. (Multiple Choice)** Two services share the same RDS instance.
Does granting one service's IAM role `rds-db:connect` automatically
grant it access to the other service's database username too?

- A) Yes — access is scoped at the instance level
- B) No — `rds-db:connect` is scoped to both the instance AND the specific database username together
- C) Yes, but only if both services are in the same Kubernetes namespace
- D) No — RDS doesn't support more than one database username per instance

<details>
<summary>Answer</summary>

**B.** The resource ARN includes both the instance's `resource_id` and
the specific username — sharing an instance doesn't imply shared
access between different database usernames.

</details>

---

**Q4. (Multiple Choice)** An IAM policy grants Catalog's role
`rds-db:connect` scoped to `orders_app` instead of `catalog_app`. Does
`terraform validate` catch this?

- A) Yes — it's an invalid ARN format
- B) No — the policy is syntactically valid HCL/JSON; this is a logic error, not a syntax error
- C) Yes, but only at `terraform plan`, not `validate`
- D) No — Terraform never validates IAM policy content at all

<details>
<summary>Answer</summary>

**B.** This is exactly this demo's own Break-Fix scenario — a
structurally correct policy that grants the wrong scope. Neither
`validate` nor `plan` checks whether a resource ARN references the
*intended* username, only whether the syntax and schema are correct.

</details>

---

**Q5. (True/False)** Since Demo 26's RDS instance is torn down every
session, data written to it during one session is available again the
next session.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Only the schema/infrastructure persists, via the same
Terraform config re-applying each session — the actual data does not
survive, since the RDS instance itself is destroyed and recreated.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 5/5 | Import Anki cards, move to Demo 27 |
| 4/5 | Review the wrong answer, then proceed |
| 3/5 | Re-read the relevant sections, retry those questions |
| Below 3/5 | Re-read the full demo before proceeding |
````