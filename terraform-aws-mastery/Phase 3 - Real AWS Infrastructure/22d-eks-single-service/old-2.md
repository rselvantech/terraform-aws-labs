# Demo 22d — EKS: Single Service (UI Only)

---

## Overview

22a/22b/22c gave the persistent build its state, its guardrails, and
its images and certificate. This demo is where compute finally
enters — the first time this series creates anything a user could
actually visit in a browser. By the end of this demo, `retail-store-sample-app`'s
UI service is running on a real EKS cluster, reachable over HTTPS
through a real AWS-managed load balancer.

**Real-world scenario — CloudNova:**
Leadership wants to see something real, not another `terraform plan`
output. This demo delivers exactly one thing end-to-end — the UI
service, live — proving the whole chain works (image → cluster →
Deployment → Service → Ingress → ALB → TLS) before scaling up to all
five services in Demo 23. Single-service first, full mesh second — the
same incremental-rollout discipline this series already used for VPC
(Demo 16/17) and ECR/ACM (Demo 19/20 → 22c).

**What this demo builds:**
```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — VPC/SG re-apply                                              │
│  Demo 16/17's module code, re-applied as persistent infrastructure     │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — EKS cluster (Auto Mode)                                      │
│  EC2-backed managed compute, no OIDC identity provider (ADR-021)       │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Kubernetes manifests: Deployment, Service, Ingress           │
│  Applied via kubectl, not a Terraform Kubernetes provider              │
├─────────────────────────────────────────────────────────────────────────┤
│  PART D — Verify: UI reachable over HTTPS through a real ALB           │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- EKS Auto Mode — what it manages for you versus a self-managed or
  managed-node-group cluster
- Why this cluster creates no OIDC identity provider at all (Pod
  Identity, not IRSA — a decision made once, at the project level, not
  re-derived here)
- Auto Mode's built-in ALB support — an `Ingress` with
  `IngressClass` controller `eks.amazonaws.com/alb`, no separate AWS
  Load Balancer Controller install
- Binding an existing ACM certificate (22c's) to that Ingress via
  `IngressClassParams`
- Why Terraform builds the cluster but `kubectl` deploys the workload
  — a deliberate scope boundary for this series, not an oversight

---

## Verification Items — Read Before Building This Demo

This demo originally flagged two pieces of Terraform code that
couldn't be confirmed against a live `terraform plan`/`apply` at
authoring time. Both have now been substantially resolved against
real, external evidence rather than left as open guesses.

### VERIFY 1 — `compute_config` and the cluster's own IAM policies

**Confirmed, not just "very likely," via a real, documented AWS API
error:** `node_role_arn` and `node_pools` are not independently
optional once either is set — a real GitHub issue against
`terraform-aws-modules/terraform-aws-eks` reproduces AWS rejecting a
cluster with `node_role_arn` set but `node_pools` omitted, with the
exact error: `InvalidParameterException: When Compute Config
nodeRoleArn is not null or empty, nodePool value(s) must be provided.`
This demo's Lab already sets both together, which is confirmed
correct — the earlier hedge ("very likely missing," sourced only from
external examples) is now backed by a real, reproduced API error, not
just pattern-matching against other people's code.

**A second, previously-unflagged gap, found and fixed this session:**
multiple independent, real, working Auto Mode configurations attach
several *additional* managed policies to the **cluster's own IAM
role** — not just the node role — beyond the single
`AmazonEKSClusterPolicy` this demo originally attached:
`AmazonEKSComputePolicy`, `AmazonEKSBlockStoragePolicy`,
`AmazonEKSLoadBalancingPolicy`, and `AmazonEKSNetworkingPolicy`. These
map directly onto Auto Mode's own capabilities (compute management,
block storage, load balancing, networking) that a bare cluster policy
alone doesn't cover. The Lab below now includes these. This is
corroborated by multiple real, working examples rather than a single
official AWS documentation page stating it as a hard requirement — a
lighter-weight caveat than the original VERIFY 1, but still worth a
`terraform plan` sanity check in your own environment before treating
it as beyond question.

### VERIFY 2 — Security-group module version and shape — resolved

**Confirmed this session against the module's live, current official
documentation.** `terraform-aws-modules/security-group/aws`'s `~> 6.0`
line (Demo 17's pin) uses the newer, object-map `ingress_rules`/
`egress_rules` shape; the `~> 5.0` line (this demo's pin) uses the
older `ingress_cidr_blocks` + named-string `ingress_rules` shape this
demo's Lab already has. **Both demos are individually correct for the
major version each one pins** — this was never actually a
contradiction requiring a "which one is wrong" resolution, just two
demos using two different, both-real, both-valid major versions of the
same module with no cross-reference calling that out. What this
*does* mean: `~> 6.0` is the module's current major version; this
demo's `~> 5.0` pin is one version behind current, not incorrect.
Whether to bump this demo to `~> 6.0` (and rewrite its shape to match)
is a separate maintenance decision for whoever next touches this
demo's actual applied infrastructure — noted here, not changed
unilaterally, since it would mean modifying real, applied resources
rather than just a documentation claim.

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** one EKS cluster (Auto Mode, EC2-backed
nodes), re-applying Demo 16/17's VPC and security group modules as
persistent infrastructure underneath it, plus a Kubernetes Deployment,
Service, and Ingress for the UI service alone. The Ingress triggers
Auto Mode's built-in ALB provisioning, terminating TLS with 22c's
certificate.

**Why Terraform stops at the cluster boundary:** this series teaches
Terraform, not Kubernetes-via-Terraform. Once the EKS cluster exists,
everything inside it — Deployments, Services, Ingresses — is applied
with `kubectl` directly, the same way most real teams split
infrastructure provisioning (Terraform's job) from application
deployment (a different tool's job, whether that's `kubectl`, Helm, or
a CD pipeline). Conflating the two would teach a Terraform Kubernetes
provider this series never otherwise covers, for a boundary most real
setups don't cross either.

**Why this cluster has no OIDC identity provider:** this project
settled on EKS Pod Identity over IRSA for per-service IAM identity
(Demo 24, not this demo) — a decision made once at the project level.
Pod Identity associates a Kubernetes service account with an IAM role
directly through the EKS Pod Identity API, with no OIDC trust
relationship involved at all. This demo's cluster doesn't need to
anticipate Demo 24's identity work; it just needs Auto Mode's Pod
Identity Agent add-on, which ships pre-installed.

**Why this is the first demo torn down every session, unlike 22a/22b/22c:**
the EKS control plane's flat, continuous fee (§5) means an idle
cluster costs money whether or not anything is deployed to it — unlike
22a/22b/22c's near-free bootstrap resources, there's no argument for
leaving this standing between sessions.

---

## Prerequisites

### Knowledge
- 22a/22b/22c completed — this demo's cluster uses 22a's state
  backend, is subject to 22b's cost guardrails, and pulls from 22c's
  ECR repo and binds 22c's ACM cert
- Demo 16/17 completed — the VPC and security group modules this
  demo re-applies
- Comfortable with basic Kubernetes vocabulary (Pod, Deployment,
  Service) — this demo introduces Ingress but assumes the others are
  at least conceptually familiar; it does not re-teach Kubernetes
  fundamentals from scratch

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | `>= 1.15.0` | `terraform version` |
| AWS CLI | `>= 2.x` | `aws --version` |
| `kubectl` | Compatible with your EKS version | `kubectl version --client` |

### Verify AWS Account and Permissions

**Step 1 — Confirm your profile works:**

```bash
aws sts get-caller-identity --profile default
```

**Step 2 — A cheap, harmless dry-run of this demo's actual service:**

```bash
aws eks list-clusters --profile default --region us-east-2
# Expected: JSON with a clusters array (may be empty — that is fine)
# If you see AccessDenied: fix IAM permissions before proceeding,
# not after you're 10+ minutes into an EKS cluster creation
```

**Step 3 — Verify IAM permissions in Console:**

```
Console → IAM → Users → test → Permissions tab
  → Confirm EKS, broad EC2, and ELB access (or an equivalent broad
    policy) is attached ✅ — this demo's permission surface is
    genuinely wider than any prior demo's, see below
```

**Required permissions beyond prior demos:**
```
eks:CreateCluster, eks:DescribeCluster, eks:DeleteCluster, eks:UpdateClusterConfig
eks:CreateAccessEntry, eks:AssociateAccessPolicy
ec2:* (Auto Mode manages EC2 instances on your behalf — broad EC2 access needed)
elasticloadbalancing:* (Auto Mode's built-in ALB provisioning)
```

> ⚠️ [VERIFY — timing claim, docs only] EKS Auto Mode's exact IAM
> permission surface is broader than a self-managed cluster's, since
> AWS manages compute and load balancing on your behalf. Confirm the
> current minimum policy against AWS's own EKS Auto Mode IAM
> documentation before scoping a production identity — the list above
> is illustrative, not exhaustive.

### Versions used in this demo

| Tool / Module | Version |
|---|---|
| Terraform | `~> 1.15.0` |
| AWS Provider | `~> 6.47.0` |
| `terraform-aws-modules/vpc/aws` | `~> 6.0` |
| `terraform-aws-modules/security-group/aws` | `~> 5.0` — resolved (see VERIFY 2 above): correct for this major version, one version behind Demo 17's `~> 6.0`, not incorrect |

> **Versions pinned as of September 2026.**

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain what EKS Auto Mode manages for you, versus a self-managed
   or managed-node-group EKS cluster
2. ✅ Write an `aws_eks_cluster` resource configured for Auto Mode with
   API-based access (not the legacy `aws-auth` ConfigMap), including
   the `compute_config` arguments and cluster-role policies Auto
   Mode's real schema requires
3. ✅ Explain why this cluster creates no OIDC identity provider
4. ✅ Write a Kubernetes Ingress using Auto Mode's built-in
   `eks.amazonaws.com/alb` controller, binding an existing ACM
   certificate via `IngressClassParams`
5. ✅ Verify a real HTTPS request reaches a real pod through a real,
   AWS-managed ALB
6. ✅ Recognize when a module version or input shape used earlier in
   this series appears to conflict with how it's used later, and
   resolve it against real documentation rather than guessing

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| EKS control plane (Auto Mode) | None | ~$0.10/hr flat | Accrues regardless of load — the reason this demo's teardown discipline matters more than any prior demo's |
| Auto Mode EC2 nodes (1 pod, UI only) | Standard EC2 free tier may apply briefly | ~$0.01–0.02/hr | Smaller than Demo 23's 5-pod figure — this demo runs one service only |
| ALB (via Ingress) | None | ~$0.025/hr + ~$0.008/LCU-hr | Provisioned automatically by Auto Mode when the Ingress is applied |
| NAT Gateway (re-applied) | None | ~$0.045/hr + data processing | Same NAT Demo 16/17 taught, now re-applied persistently |
| **Session total (active)** | | **~$0.18–0.20/hr** | **Tear down at the end of every session — see Cleanup** |

---

## Directory Structure

```
22d-eks-single-service/
├── README.md
├── 22d-eks-single-service-anki.csv
├── 22d-eks-single-service-quiz.md
└── src/
    ├── phase-3-onward/                     # same config 22a's backend serves
    │   ├── vpc.tf                          # Demo 16/17's module, re-applied
    │   ├── eks.tf                          # aws_eks_cluster, Auto Mode
    │   ├── variables.tf
    │   └── outputs.tf
    └── k8s/                                 # applied via kubectl, not Terraform
        ├── ui-deployment.yaml
        ├── ui-service.yaml
        └── ui-ingress.yaml
```

---

## Recall Check — 22c (ECR/ACM Re-Creation)

Answer from memory before reading anything new:

1. Why does this demo pull images from a private ECR repo instead of
   the public gallery directly?
2. What kind of Terraform block reads the standing Route53 hosted zone
   — a `resource` or a `data` block, and why?
3. Is the ACM certificate this demo binds to the Ingress the same
   object Demo 20 created?

<details>
<summary>Answers</summary>

1. Because 22c re-created a persistent, private ECR repo and re-pushed
   the images there specifically so this project's own infrastructure
   controls and serves them, rather than depending on the public
   gallery's continued availability for every deploy.
2. A `data` block — `data "aws_route53_zone"`. This project's Terraform
   never creates or destroys the hosted zone itself; it only reads the
   zone's ID to write validation records against it.
3. No — Demo 20's cert was a teaching rep, torn down at its own
   Cleanup. 22c requested and validated a new certificate, meant to
   persist for the rest of the project.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `aws_eks_cluster` | Resource | The EKS control plane itself |
| `compute_config` | Resource nested block | Enables Auto Mode — AWS manages node provisioning, scaling, and patching (see VERIFY 1 above — now confirmed against a real API error) |
| `kubernetes_network_config.elastic_load_balancing` | Resource nested block | Enables Auto Mode's built-in ALB support |
| `access_config` (API mode) | Resource nested block | Modern EKS authentication — replaces the legacy `aws-auth` ConfigMap |
| `aws_eks_access_entry` | Resource | Grants your own IAM identity permission to interact with the cluster |
| Kubernetes `Deployment`/`Service`/`Ingress` | Kubernetes API objects, not Terraform constructs | Applied via `kubectl`, not this series' Terraform tooling |
| `IngressClassParams` | Kubernetes API object (Auto Mode-specific) | Binds an ACM certificate ARN to an Ingress without a separate controller install |

---

### Detailed Explanation of New Constructs

#### EKS Auto Mode — What It Actually Manages For You

```
┌────────────────────────────────────────────────────────────────────────┐
│  SELF-MANAGED NODES          MANAGED NODE GROUPS         AUTO MODE     │
│  You provision, patch,       AWS provisions/patches,     AWS manages   │
│  and scale EC2 instances     you still choose instance   compute,      │
│  yourself                    types/scaling policy        storage, and  │
│                                                            load         │
│                                                            balancing    │
│                                                            end-to-end   │
├────────────────────────────────────────────────────────────────────────┤
│  This demo uses Auto Mode — the least infrastructure-management        │
│  overhead of the three, and the option that ships Pod Identity and     │
│  built-in ALB support as pre-installed, managed add-ons rather than    │
│  things you install and maintain yourself.                             │
└────────────────────────────────────────────────────────────────────────┘
```

> ⚠️ [VERIFY — timing claim, docs only] Confirm Auto Mode's current
> exact feature set and default add-on list against AWS's own EKS
> documentation before relying on any specific claim here as
> permanently accurate — managed-service defaults are the kind of
> detail that shifts over time.

---

#### `aws_eks_cluster` for Auto Mode

| Argument | Required | Description |
|---|---|---|
| `name` | Yes | Cluster name — this demo uses `cloudnova-eks` |
| `role_arn` | Yes | IAM role the EKS service itself assumes to manage cluster resources |
| `vpc_config` | Yes | Subnet IDs from the re-applied VPC module |
| `compute_config.enabled` | Yes, for Auto Mode | `true` — turns on Auto Mode's managed compute |
| `compute_config.node_pools` | Confirmed required once `node_role_arn` is set (per VERIFY 1) | e.g. `["general-purpose", "system"]` |
| `compute_config.node_role_arn` | Confirmed required once `node_pools` is set (per VERIFY 1) | A distinct IAM role for the Auto Mode–managed nodes — not the same role as the cluster's own `role_arn` |
| `kubernetes_network_config.elastic_load_balancing.enabled` | Yes, for built-in ALB support | `true` — required for the Ingress pattern this demo uses |
| `access_config.authentication_mode` | Yes | `"API"` — modern access-entry-based auth, not the legacy `aws-auth` ConfigMap |
| `storage_config.block_storage.enabled` | No | `true` — Auto Mode-managed EBS storage class, not needed for this stateless UI deployment but commonly enabled |

> **No `identity` block or OIDC provider resource anywhere in this
> config.** That's deliberate, not an omission — this project uses Pod
> Identity (Demo 24), which doesn't require one. If you're used to
> IRSA tutorials that always pair an EKS cluster with an
> `aws_iam_openid_connect_provider` resource, that pairing is IRSA-specific,
> not a universal EKS requirement.

---

#### Auto Mode's Built-In ALB Support — No Separate Controller Install

Historically, routing external traffic into an EKS cluster required
installing the **AWS Load Balancer Controller** as a separate,
self-managed component — its own Helm chart, its own IAM role, its own
upgrade lifecycle. Auto Mode changes this:

```hcl
kubernetes_network_config {
  elastic_load_balancing {
    enabled = true    # this single flag is what replaces the
                       # self-managed controller install
  }
}
```

With this enabled, any `Ingress` object using `IngressClass` controller
`eks.amazonaws.com/alb` gets a real ALB provisioned automatically —
Auto Mode manages the controller for you, as a first-class, AWS-managed
component rather than something you install and maintain.

**Binding an existing ACM certificate — `IngressClassParams`:**

```yaml
apiVersion: eks.amazonaws.com/v1
kind: IngressClassParams
metadata:
  name: alb-cloudnova
spec:
  certificateARNs:
    - "arn:aws:acm:us-east-2:<ACCOUNT_ID>:certificate/<CERT_ID>"
    # ↑ the cert 22c created and validated
```

> ⚠️ [VERIFY — timing claim, docs only] The exact
> `IngressClassParams` schema and field names are specific to EKS Auto
> Mode's own API group (`eks.amazonaws.com/v1`) and are newer, less
> battle-documented territory than most of this series' content —
> confirm the current field names against AWS's own
> `auto-configure-alb.html` documentation before treating this as
> permanently fixed syntax.

---

## Lab Step-by-Step Guide

---

## Part A — Re-Apply VPC and Security Groups

Part A re-applies Demo 16/17's VPC and security-group module code as
this environment's first piece of persistent infrastructure.

### Step 1 — Navigate to the project config

```bash
cd terraform-aws-mastery/phase-3-real-aws-infrastructure/22d-eks-single-service/src/phase-3-onward
```

### Step 2 — Add vpc.tf

This step re-applies Demo 16's VPC module alongside Demo 17's
security-group module, both now standing up persistent infrastructure
for the first time rather than a teaching rep.

Create a file **vpc.tf** and add the below content:

This file contains both module calls — the VPC itself, and the
security group governing traffic to the EKS nodes this demo is about
to create.

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "cloudnova-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2a", "us-east-2b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true   # same cost lesson Demo 16 taught — real, but needed for this environment

  tags = {
    Project = "cloudnova-retail-store-e2e"
  }
}

module "eks_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name   = "cloudnova-eks-nodes"
  vpc_id = module.vpc.vpc_id

  ingress_cidr_blocks = [module.vpc.vpc_cidr_block]
  ingress_rules       = ["all-all"]

  egress_rules = ["all-all"]
}
```

> **Version and shape confirmed — see VERIFY 2 above.** This module
> call's `~> 5.0` pin and its `ingress_cidr_blocks`/named-string
> `ingress_rules` shape are correct for that major version — Demo 17's
> `~> 6.0` pin and object-map shape are correct for *that* version.
> Neither demo is wrong; `~> 6.0` is simply the more current line.

> **Same-as-Demo-16/17 note, restated:** these module calls are
> otherwise unchanged from what those demos taught. What's genuinely
> new is that this apply is the first one meant to persist between
> sessions — the technique is familiar, the lifecycle isn't.

### Step 3 — Apply

This step applies the VPC and security group as persistent
infrastructure, using 22a's backend for the first time in this demo.

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

---

## Part B — EKS Cluster (Auto Mode)

Part B creates the EKS cluster itself, configured for Auto Mode with
no legacy authentication and no OIDC identity provider.

### Step 4 — Add eks.tf

This step writes the cluster resource and both IAM roles it depends
on — the cluster's own role, now with the additional Auto-Mode-specific
policies found this session, and a separate role for the nodes Auto
Mode manages on your behalf.

Create a file **eks.tf** and add the below content:

This file contains everything needed to bring up the EKS control
plane itself: two IAM roles, the cluster resource configured for Auto
Mode, and the access entry granting your own identity admin rights on it.

```hcl
resource "aws_iam_role" "eks_cluster" {
  name = "cloudnova-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── Auto Mode-specific policies on the CLUSTER's own role ────────────────
# Added this session: multiple real, working Auto Mode configurations
# attach these alongside AmazonEKSClusterPolicy — they map onto Auto
# Mode's compute/storage/load-balancing/networking capabilities, which
# the base cluster policy alone doesn't cover.
resource "aws_iam_role_policy_attachment" "eks_cluster_auto_mode_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy",
  ])
  role       = aws_iam_role.eks_cluster.name
  policy_arn = each.value
}

# ── Auto Mode's own node role — distinct from the cluster's role above ──
# Confirmed required per VERIFY 1: AWS's own API rejects a cluster with
# node_role_arn set but node_pools omitted (or vice versa) — the two
# arguments are conditionally coupled, not independently optional.
resource "aws_iam_role" "eks_auto_node" {
  name = "cloudnova-eks-auto-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_auto_node_policy" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
  ])
  role       = aws_iam_role.eks_auto_node.name
  policy_arn = each.value
}

resource "aws_eks_cluster" "main" {
  name     = "cloudnova-eks"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = concat(module.vpc.private_subnets, module.vpc.public_subnets)
  }

  compute_config {
    enabled       = true                                 # Auto Mode
    node_pools    = ["general-purpose", "system"]         # confirmed required alongside node_role_arn — VERIFY 1
    node_role_arn = aws_iam_role.eks_auto_node.arn         # confirmed required alongside node_pools — VERIFY 1
  }

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true   # required for built-in ALB support
    }
  }

  storage_config {
    block_storage {
      enabled = true
    }
  }

  access_config {
    authentication_mode = "API"   # modern access-entry auth, not aws-auth ConfigMap
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_cluster_auto_mode_policies,
  ]
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_caller_identity.current.arn   # your own IAM identity
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_caller_identity.current.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

data "aws_caller_identity" "current" {}
```

> **VERIFY 1, restated at the point of use:** the `compute_config`
> block's `node_pools`/`node_role_arn` pairing is confirmed via a real,
> reproduced AWS API error (see the Verification Items section above)
> — not just inferred from external examples. The cluster-role policy
> attachments are a newer addition, corroborated by multiple real
> working examples rather than a single authoritative source — still
> worth a `terraform plan` sanity check in your own environment.

> **Same-as-Demo-08 note, restated:** `data.aws_caller_identity` here
> is the identical construct Demo 08 taught — reused to grant your own
> IAM identity cluster access, not a new data source.

### Step 5 — Apply

This step applies the cluster itself — expect this to genuinely take
10–15 minutes, not a hung terminal.

```bash
terraform plan
terraform apply
```

```
⚠️ Simulated expected output

aws_eks_cluster.main: Still creating... [10m0s elapsed]
aws_eks_cluster.main: Creation complete after 12m34s

Apply complete! Resources: 12 added, 0 changed, 0 destroyed.
```

> ⚠️ Simulated expected output — the resource count above (12) reflects
> the corrected config including both the node role's two policy
> attachments and the cluster role's four additional Auto Mode
> policies; treat it as illustrative pending your own `apply`.

> **Bolded takeaway:** EKS cluster creation genuinely takes 10–15
> minutes — this isn't a hung terminal. This is a real, worth-planning-around
> characteristic of EKS specifically, unlike most resources this
> series has built so far.

### Step 6 — Configure kubectl

This step points `kubectl` at the new cluster and confirms Auto Mode
has already provisioned at least one node, without you creating it
directly.

```bash
aws eks update-kubeconfig --name cloudnova-eks --region us-east-2 --profile default
kubectl get nodes
```

```
⚠️ Simulated expected output

NAME                                          STATUS   ROLES    AGE   VERSION
i-0abc123def456.us-east-2.compute.internal    Ready    <none>   2m    v1.31.x
```

> **Bolded takeaway:** you didn't create this node — Auto Mode did,
> automatically, in response to the cluster's compute needs. This is
> the practical meaning of "Auto Mode manages compute for you."

---

## Part C — Kubernetes Manifests: Deployment, Service, Ingress

Part C deploys the UI service itself, entirely via `kubectl` — nothing
in this Part touches Terraform.

### Step 7 — Add ui-deployment.yaml

This step writes the Deployment that will actually run the UI
container, pulling its image from 22c's persistent ECR repo.

Create a file **k8s/ui-deployment.yaml** and add the below content:

This file describes a single-replica Deployment running the UI
service's real image, the same image 22c pushed.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ui
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ui
  template:
    metadata:
      labels:
        app: ui
    spec:
      containers:
        - name: ui
          image: <ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-ui:latest
          # ↑ 22c's persistent ECR repo, not the public gallery
          ports:
            - containerPort: 8080
```

### Step 8 — Add ui-service.yaml

This step writes the internal Service that gives the Deployment's pods
a stable address for the Ingress to route to.

Create a file **k8s/ui-service.yaml** and add the below content:

This file exposes the UI Deployment internally, on port 80, routing to
the container's actual port 8080.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ui
spec:
  selector:
    app: ui
  ports:
    - port: 80
      targetPort: 8080
  type: ClusterIP
```

### Step 9 — Add the Ingress and its IngressClassParams

This step writes the three objects that together trigger Auto Mode's
built-in ALB provisioning and bind 22c's certificate to it.

Create a file **k8s/ui-ingress.yaml** and add the below content:

This file contains the `IngressClassParams` binding the certificate,
the `IngressClass` referencing Auto Mode's own ALB controller, and the
`Ingress` itself routing all traffic to the UI Service.

```yaml
apiVersion: eks.amazonaws.com/v1
kind: IngressClassParams
metadata:
  name: alb-cloudnova
spec:
  certificateARNs:
    - "arn:aws:acm:us-east-2:<ACCOUNT_ID>:certificate/<CERT_ID>"
    # ↑ 22c's certificate ARN

---
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb-cloudnova
spec:
  controller: eks.amazonaws.com/alb
  parameters:
    apiGroup: eks.amazonaws.com
    kind: IngressClassParams
    name: alb-cloudnova

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ui
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
spec:
  ingressClassName: alb-cloudnova
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ui
                port:
                  number: 80
```

### Step 10 — Apply and wait for the ALB

This step applies all three Kubernetes manifest files and watches the
Ingress until Auto Mode finishes provisioning a real ALB for it.

```bash
kubectl apply -f k8s/
kubectl get ingress ui --watch
```

```
⚠️ Simulated expected output

NAME   CLASS          HOSTS   ADDRESS                                          PORTS   AGE
ui     alb-cloudnova  *       cloudnova-eks-....us-east-2.elb.amazonaws.com   80,443  90s
```

> ⚠️ [VERIFY — timing claim, docs only] ALB provisioning after the
> Ingress is applied typically takes a few minutes — exact timing
> depends on real AWS provisioning, not something this demo's text can
> guarantee.

---

## Part D — Verify

Part D confirms the entire chain actually works, ending with a real
browser-equivalent request over the public internet.

### Step 11 — Confirm via kubectl

This step confirms both the Kubernetes-side and AWS-side halves of the
routing chain independently, before attempting a real request.

```bash
kubectl get ingress ui
kubectl get pods -l app=ui
```

```
Console → EC2 → Load Balancers → confirm a new ALB exists, matching
  the Ingress's ADDRESS field ✅
Console → Certificate Manager → app.rselvantech.com → confirm this ALB's
  HTTPS listener uses 22c's certificate ✅
```

> 📷 [Screenshot placeholder: AWS Console → EC2 → Load Balancers,
> showing the new ALB whose DNS name matches the Ingress's ADDRESS
> field, and its HTTPS listener bound to app.rselvantech.com's
> certificate]

### Step 12 — Real HTTPS request

This step is the actual proof this demo exists to deliver — a real
request over the public internet reaching the running application.

```bash
curl -sk https://<ALB_ADDRESS_FROM_INGRESS>/
# Expected: the UI service's actual HTML response, HTTP 200 or a
# genuine app-level redirect — not a TLS handshake failure, not a 5xx
```

> **Bolded takeaway:** this is the first genuinely externally-reachable
> thing this entire series has built. Every prior demo verified success
> via Console or CLI output; this one is verified by a real browser (or
> `curl`) actually reaching a running application over the public internet.

---

## Cleanup

**Unlike 22a/22b/22c, this demo's Cleanup step tears everything down.**
The EKS control plane's flat fee means an idle cluster costs money
whether or not anything is deployed to it — there's no cost argument
for leaving it standing between sessions.

### Step 13 — Destroy everything

```bash
kubectl delete -f k8s/
terraform destroy
```

```
⚠️ Simulated expected output

Destroy complete! Resources: X destroyed.
```

```
Console → EKS → Clusters → confirm cloudnova-eks: GONE ✅
Console → EC2 → Load Balancers → confirm the ALB: GONE ✅
Console → VPC → confirm cloudnova-vpc: GONE ✅
```

> ⚠️ **Confirm 22a/22b/22c's resources are still standing before you
> end the session** — this demo's teardown should touch nothing from
> those three. `terraform state list` in `22a`/`22b`/`22c`'s own
> directories should still show their resources untouched.

---

## What You Learned

1. ✅ EKS Auto Mode manages compute, storage, and load balancing for
   you — a genuinely different operating model than self-managed nodes
   or managed node groups, not just "the same thing with less config."
2. ✅ This cluster creates no OIDC identity provider — Pod Identity
   (Demo 24) doesn't need one, unlike the IRSA pattern many EKS
   tutorials default to.
3. ✅ Auto Mode's built-in ALB support replaces what used to require a
   separately-installed AWS Load Balancer Controller — one
   `elastic_load_balancing { enabled = true }` flag, plus standard
   Kubernetes `Ingress`/`IngressClass`/`IngressClassParams` objects.
4. ✅ This series draws a deliberate line: Terraform builds the
   cluster, `kubectl` deploys the workload — not a gap, a scope choice.
5. ✅ EKS cluster creation genuinely takes 10–15 minutes — plan around
   this real characteristic rather than assuming something's stuck.
6. ✅ A module version or input shape reused across two demos should
   be resolved against real documentation when it appears to
   conflict — not assumed wrong on either side without checking.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `aws_eks_cluster`, `compute_config` | TA-004 Obj 4a — Resource configuration | Provider-specific resource; Auto Mode-specific arguments are newer additions worth confirming against current provider docs |
| `access_config.authentication_mode = "API"` | TA-004 Obj 4a | Modern EKS access pattern — know this exists as an alternative to the legacy `aws-auth` ConfigMap approach |
| Terraform's scope boundary at the cluster (not into Kubernetes objects) | TA-004 Obj 1 — IaC concepts generally | Recognize this as a deliberate tooling boundary, not a Terraform limitation |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Does every EKS cluster require an OIDC identity provider?" | No — only clusters using IRSA for pod-level IAM identity need one. Pod Identity doesn't. | Assuming OIDC providers are a universal EKS requirement because most IRSA tutorials pair them by default |
| "Can Terraform directly manage Kubernetes Deployments inside an EKS cluster it created?" | Yes, technically, via a Kubernetes provider — but this series deliberately doesn't, drawing a scope line at the cluster boundary | Assuming Terraform *must* manage in-cluster objects because it created the cluster |
| "Is `compute_config { enabled = true }` a complete Auto Mode configuration?" | No — `node_pools` and `node_role_arn` are conditionally required together (confirmed via a real AWS API error), and the cluster's own role needs Auto-Mode-specific policies beyond the base cluster policy | Assuming a single boolean flag fully configures a feature this substantial |

### Exam Task — Write a complete configuration

**Task:** Write an `aws_eks_cluster` resource configured for Auto Mode
with API-based access, no legacy `aws-auth` ConfigMap dependency.

**Block types required:** `resource` (×3 minimum: cluster + its IAM
role + the Auto Mode node role)

**Official documentation:**
- [`aws_eks_cluster` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster)

**What to practise:**
1. Open the page above — check the `compute_config` and `access_config` arguments specifically, including whether `node_pools`/`node_role_arn` are genuinely required or merely commonly set
2. Write the configuration from scratch without looking at this demo's `src/` files
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
resource "aws_iam_role" "eks_cluster" {
  name = "exam-task-eks-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "eks_auto_node" {
  name = "exam-task-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_eks_cluster" "exam_task" {
  name     = "exam-task-cluster"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = ["subnet-aaa", "subnet-bbb"]
  }

  compute_config {
    enabled       = true
    node_pools    = ["general-purpose", "system"]
    node_role_arn = aws_iam_role.eks_auto_node.arn
  }

  access_config {
    authentication_mode = "API"
  }
}
```

**Arguments you must know without looking up:**
- `compute_config.enabled = true` is what turns on Auto Mode
- `access_config.authentication_mode = "API"` avoids the legacy
  `aws-auth` ConfigMap pattern entirely
- `compute_config.node_pools` and `compute_config.node_role_arn` are
  conditionally required together — setting one without the other
  produces a real AWS API rejection, confirmed against a documented
  error

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `kubectl` commands return `Unauthorized` | Your IAM identity has no access entry on the cluster | Confirm `aws_eks_access_entry` + `aws_eks_access_policy_association` were applied for your actual identity |
| Ingress never gets an `ADDRESS` | `elastic_load_balancing.enabled` wasn't set, or `IngressClassParams`/`IngressClass` weren't applied before the `Ingress` itself | Confirm cluster-level config, and apply order (`kubectl apply -f k8s/` applies all files, but check individual object status if one lags) |
| `curl` returns a TLS error | Certificate ARN in `IngressClassParams` doesn't match a real, `Issued` cert | Re-check the ARN against 22c's actual `Issued` certificate, not a copy-paste of a placeholder |
| `terraform apply` hangs for 10+ minutes on `aws_eks_cluster` | Normal — not stuck | EKS cluster creation genuinely takes this long; let it complete |
| `InvalidParameterException` mentioning `nodeRoleArn`/`nodePool` | `node_role_arn` and `node_pools` were set independently instead of together | Set both together — this is a confirmed, coupled requirement, not an optional pairing |
| Security-group module call behaves differently than Demo 17's | Expected — Demo 17 pins `~> 6.0` (newer shape), this demo pins `~> 5.0` (older shape). Both are correct for their own version. | No fix needed unless you're deliberately upgrading this demo to `~> 6.0` |

---

## Break-Fix Scenario

One deliberate error. Diagnose using `kubectl` output — do not look at
the answer first.

```bash
kubectl apply -f break-fix/
kubectl get ingress broken-ui
kubectl describe ingress broken-ui
```

This file is a single Ingress with one typo'd `ingressClassName` that
`kubectl apply` accepts without error — diagnose why it never gets an
ALB before revealing the answer.

**break-fix/broken-ingress.yaml:**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: broken-ui
spec:
  ingressClassName: alb-cloudnov   # Error — typo
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ui
                port:
                  number: 80
```

<details>
<summary>Reveal answer — attempt diagnosis first</summary>

**Error — `ingressClassName: alb-cloudnov`**
Missing the trailing "a" — doesn't match the real `IngressClass` name
(`alb-cloudnova`). Unlike a Terraform reference error, this doesn't
fail loudly at apply time — `kubectl apply` succeeds, but the Ingress
never gets an ALB provisioned, because no matching `IngressClass`
exists. `kubectl describe ingress broken-ui` will show no `ADDRESS`
and often an event mentioning the class couldn't be found. Fix:
correct the typo to match the real `IngressClass` name exactly.

</details>

**Cleanup:**

```bash
kubectl delete -f break-fix/
```

---

## Interview Prep

**Q1. A teammate asks why this cluster doesn't have an OIDC identity provider, since every IRSA tutorial they've seen always creates one.**
Because this project uses EKS Pod Identity for per-service IAM identity instead of IRSA — a decision made once at the project level (Demo 24 builds on it, this demo just doesn't need to anticipate it). IRSA specifically requires an OIDC identity provider because it works by federating a Kubernetes service account's token to an IAM role via OIDC trust. Pod Identity associates a service account with a role directly through the EKS Pod Identity API — no OIDC federation involved at all. The pairing of "every EKS cluster gets an OIDC provider" is an IRSA-tutorial convention, not a universal EKS requirement.

**Q2. Someone asks why Terraform built the cluster but `kubectl` deployed the actual application — wouldn't it be cleaner to do everything in Terraform?**
It's a deliberate scope boundary, not laziness or a gap. This series teaches Terraform, and while Terraform *can* manage Kubernetes objects via a dedicated provider, doing so here would mean introducing a second provider ecosystem this curriculum otherwise never covers, just to avoid a second CLI tool. Most real teams draw exactly this line too — infrastructure provisioning (Terraform, or similar) and application deployment (kubectl, Helm, a CD pipeline) are commonly separate concerns, often even owned by different teams. Recognizing where a tool's job legitimately ends is as much a skill as knowing how to use the tool.

**Q3. A reviewer asks how you'd explain why Auto Mode's built-in ALB support matters, versus just installing the AWS Load Balancer Controller yourself.**
The self-managed controller is a real, capable option — many production clusters use it — but it's a component you install, upgrade, and operate yourself: its own Helm chart, its own IAM role, its own version compatibility to track against your Kubernetes version. Auto Mode's built-in support turns that into a single `elastic_load_balancing { enabled = true }` flag on the cluster resource — AWS operates the controller for you, as a managed component. The trade-off is less flexibility than the self-managed controller offers (this demo's own Demo-23 preview flags a real one — no `IngressGroup` support) — so it's not strictly better in every case, just simpler for the common case this demo needed.

**Q4. A reviewer notices this demo's security-group module call uses a different version and shape than Demo 17's, for the identical module. How should that be handled?**
By checking the module's real, current documentation rather than assuming either demo is simply wrong. That's exactly what resolved it: `terraform-aws-modules/security-group/aws`'s `~> 5.0` line (this demo) genuinely uses the older list-based shape, and its `~> 6.0` line (Demo 17) genuinely uses the newer object-map shape — both demos are individually correct for the version each one pins. What looked like a contradiction was actually two demos each doing the right thing for a different major version of the same module, with nothing cross-referencing that fact. The lesson isn't "one of these must be a bug" — it's "verify before concluding that," which is what actually resolved this rather than picking a side.

---

## Key Takeaways

1. **EKS Auto Mode is a genuinely different operating model, not a
   config toggle on the same underlying cluster type.** It manages
   compute, storage, and load balancing for you — know what that
   actually changes about your own responsibilities.

2. **Not every EKS cluster needs an OIDC identity provider.** That
   pairing is specific to IRSA; Pod Identity, this project's actual
   choice, has no such dependency.

3. **A managed feature can still have real limitations worth knowing
   before you need them.** Auto Mode's built-in ALB support is
   genuinely simpler than the self-managed controller — but it isn't a
   strict superset of its capabilities, as Demo 23's `IngressGroup` gap
   will show.

4. **A deliberate tooling scope boundary is a design choice, not a
   gap.** Terraform building the cluster and `kubectl` deploying the
   workload is a considered line, worth being able to explain, not
   just a fact to accept.

5. **Some AWS operations genuinely take a long time, and that's not a
   sign of failure.** EKS cluster creation's 10–15 minutes is real —
   build your own expectations (and any automation timeouts) around
   the actual number, not an assumption borrowed from faster resources.

6. **An apparent cross-demo conflict is worth resolving against real
   documentation, not resolving by assumption.** This demo's own
   security-group module pin looked like a contradiction with Demo
   17's until actually checked — the check, not a guess in either
   direction, is what settled it.

> **Demo scope:** Primary concept: standing up an EKS Auto Mode
> cluster and routing real traffic to a single service through its
> built-in ALB support. Supporting concepts: why Pod Identity removes
> the OIDC-provider requirement, the Terraform/`kubectl` scope
> boundary, resolving apparent cross-demo version/shape conflicts
> against real documentation.
> Estimated completion time: 50–60 minutes (EKS cluster creation and
> ALB provisioning both take real, multi-minute wall-clock time).
> Checkpoints: 4 natural stopping points (end of Part A, end of
> Part B, end of Part C, end of Part D).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws eks update-kubeconfig --name <CLUSTER> --region <REGION>` | Configures `kubectl` to talk to a specific EKS cluster |
| `kubectl get nodes` | Lists the cluster's nodes — Auto Mode-provisioned, not manually created |
| `kubectl apply -f <DIR>/` | Applies every manifest in a directory |
| `kubectl get ingress <NAME> --watch` | Watches an Ingress until it gets a real ALB address |
| `kubectl describe ingress <NAME>` | Shows events explaining why an Ingress hasn't provisioned, if it hasn't |
| `curl -sk https://<ADDRESS>/` | Real HTTPS request against the Ingress's ALB — the actual proof this demo worked |
| `terraform init` / `validate` / `plan` / `apply` / `destroy` | Standard workflow, unchanged from prior demos |

---

## Next Demo

**Demo 23 — EKS: Full Service Mesh:** scales this same pattern to all
five `retail-store-sample-app` services. Requires an explicit routing
decision this demo doesn't need to make — Auto Mode's built-in ALB
support doesn't support `IngressGroup` (sharing one ALB across
multiple `Ingress` resources), so Demo 23 must state, not assume,
whether all five services share one `Ingress`/ALB with path-based
rules, use five separate ALBs, or fall back to the self-managed
controller for that demo specifically.

---

## Appendix — Anki Cards

**22d-eks-single-service-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::22d-eks-single-service
#separator:Comma
#columns:Front,Back,Tags
"What does EKS Auto Mode manage for you that a managed-node-group cluster doesn't?","Compute provisioning/scaling/patching, storage, and load balancing, end-to-end. Managed node groups still require you to choose instance types and scaling policy - Auto Mode manages compute fully.","demo22d,eks,auto-mode,ta004-obj4a"
"Why does this project's EKS cluster create no OIDC identity provider?","This project uses EKS Pod Identity for per-service IAM identity (Demo 24), not IRSA. Pod Identity associates a service account with a role directly via the EKS Pod Identity API - no OIDC federation involved at all, so no provider is needed.","demo22d,eks,pod-identity,ta004-obj4a"
"What single Terraform argument enables Auto Mode's built-in ALB support?","kubernetes_network_config.elastic_load_balancing.enabled = true - replaces the need for a separately-installed AWS Load Balancer Controller.","demo22d,eks,alb,ta004-obj4a"
"What Kubernetes API object binds an existing ACM certificate to an Auto Mode Ingress?","IngressClassParams (apiGroup eks.amazonaws.com) - its certificateARNs field lists the cert ARN(s) to bind, referenced by a matching IngressClass.","demo22d,eks,alb,ingress"
"Does this series manage Kubernetes Deployments/Services/Ingresses via Terraform?","No - deliberately. Terraform builds the EKS cluster; kubectl applies the in-cluster Kubernetes manifests. A scope boundary, not a gap.","demo22d,scope,kubectl"
"Roughly how long does real EKS cluster creation take?","10-15 minutes - a genuine, real AWS characteristic, not a hung terminal or a bug.","demo22d,eks,timing"
"What does access_config.authentication_mode = \"API\" replace?","The legacy aws-auth ConfigMap approach to granting IAM identities access to an EKS cluster - the modern access-entry-based pattern.","demo22d,eks,access-entries"
"Are compute_config's node_pools and node_role_arn independently optional?","No, confirmed via a real AWS API error - setting node_role_arn without node_pools (or vice versa) is rejected with InvalidParameterException. The two are conditionally required together.","demo22d,eks,auto-mode,gotcha"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the individual facts (what
> Auto Mode manages, why no OIDC provider, the ALB single-flag,
> cluster-creation timing). This Quiz instead works through Break-Fix
> diagnosis and the two verification items in applied, scenario form,
> so the two together cover recall and applied judgment without
> restating the same question twice.

**22d-eks-single-service-quiz.md:**

````markdown
# Quiz — Demo 22d: EKS: Single Service (UI Only)

> Question types: True/False, Multiple Choice, Multiple Answer —
> matching the real TA-004 exam format.
> Target: 80% or above before moving to Demo 23.

---

**Q1. (Multiple Choice)** A colleague sets `compute_config { enabled =
true, node_role_arn = aws_iam_role.node.arn }` — deliberately leaving
out `node_pools` since they only need a custom node role. What happens?

- A) This works fine — `node_pools` and `node_role_arn` are independent, optional arguments
- B) AWS rejects the cluster creation with `InvalidParameterException: When Compute Config nodeRoleArn is not null or empty, nodePool value(s) must be provided`
- C) `node_pools` silently defaults to `["general-purpose"]`
- D) Terraform catches this at `plan` time before any AWS API call happens

<details>
<summary>Answer</summary>

**B.** This is a real, documented AWS API rejection — the two
arguments are conditionally required together, not independently
optional. Terraform's own schema doesn't statically catch this; it
only surfaces once AWS's API actually evaluates the request.

</details>

---

**Q2. (Multiple Choice)** This demo's `eks_sg` module call and Demo
17's `tier_sg` module call both target
`terraform-aws-modules/security-group/aws`, but use different
versions and different input shapes. What's the correct response?

- A) Trust whichever demo you read most recently
- B) Check the module's real, current documentation — both versions may simply be correct for the major version each one pins
- C) Average the two version numbers
- D) Assume both are correct simultaneously, since Terraform would catch a real error

<details>
<summary>Answer</summary>

**B.** This is exactly what resolved this demo's own VERIFY 2 — the
`~> 5.0` and `~> 6.0` shapes are each genuinely correct for their own
version; checking the real documentation settled it, rather than
guessing or defaulting to recency.

</details>

---

**Q3. (Multiple Choice)** `kubectl describe ingress broken-ui` shows no
`ADDRESS` and an event about a missing class. `ingressClassName:
alb-cloudnov` is set. What's wrong?

- A) The Ingress needs `apiVersion: eks.amazonaws.com/v1alpha1` instead
- B) The class name has a typo and doesn't match any real, applied `IngressClass`
- C) `kubectl apply` failed and needs to be re-run
- D) The certificate ARN is invalid

<details>
<summary>Answer</summary>

**B.** This is a plain typo (`alb-cloudnov` vs. the real
`alb-cloudnova`) — `kubectl apply` succeeds regardless, since nothing
about the string itself is invalid YAML; the Ingress just never
matches a real `IngressClass` and never gets an ALB.

</details>

---

**Q4. (Multiple Choice)** This demo's `aws_iam_role.eks_cluster`
originally only had `AmazonEKSClusterPolicy` attached. Based on real,
working Auto Mode examples, what was likely still missing?

- A) Nothing — `AmazonEKSClusterPolicy` alone is sufficient for any EKS cluster, Auto Mode or not
- B) Additional Auto-Mode-specific managed policies on the same cluster role — compute, block storage, load balancing, and networking policies that Auto Mode's own capabilities require
- C) The cluster role needs `AdministratorAccess` instead
- D) Auto Mode clusters don't use IAM roles for the cluster itself at all

<details>
<summary>Answer</summary>

**B.** Multiple real, working Auto Mode configurations attach
`AmazonEKSComputePolicy`, `AmazonEKSBlockStoragePolicy`,
`AmazonEKSLoadBalancingPolicy`, and `AmazonEKSNetworkingPolicy` to the
cluster's own role alongside the base cluster policy — this demo's
`eks.tf` has since been updated to include them.

</details>

---

**Q5. (Multiple Choice)** `terraform apply` on `aws_eks_cluster.main`
is still running after 8 minutes with no error. What should you do?

- A) Cancel it — 8 minutes indicates something is stuck
- B) Wait — EKS cluster creation genuinely takes 10–15 minutes
- C) Open a second terminal and run `terraform apply` again
- D) Run `terraform force-unlock`, assuming a stuck state lock

<details>
<summary>Answer</summary>

**B.** This is expected, real EKS behavior, not a sign of a stuck
operation — cancelling, re-applying concurrently, or force-unlocking
would all be responses to a problem that doesn't actually exist here.

</details>

---

**Q6. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements correctly describe this demo's two verification items,
after this session's resolution work?

- A) Both remain fully unresolved, exactly as originally flagged
- B) VERIFY 1's `node_pools`/`node_role_arn` coupling is now confirmed via a real, documented AWS API error, and a previously-unflagged cluster-role-policy gap was also found and fixed
- C) VERIFY 2 is resolved — both this demo's and Demo 17's security-group module versions are individually correct for their own pinned major version
- D) Both VERIFY items turned out to be false alarms with no real issue underlying either one

<details>
<summary>Answer</summary>

**B and C.** Both items were substantially resolved this session, but
not by discovering "nothing was actually wrong" (ruling out **D**) —
VERIFY 1 uncovered a real, additional gap in the cluster role's
policies, and VERIFY 2 confirmed the version difference was
legitimate rather than a bug in either demo.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 5-6/6 | Import Anki cards, move to Demo 23 |
| 4/6 | Review the wrong answers, then proceed |
| 3/6 | Re-read the relevant sections, retry those questions |
| Below 3/6 | Re-read the full demo before proceeding |
````