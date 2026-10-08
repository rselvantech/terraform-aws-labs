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
│  PART A — Recreate the Accumulated Baseline (22a + 22b + 22c)          │
│  This directory must contain every prior Phase 3+ demo's finished      │
│  files before anything new is added — the same requirement 22c's own  │
│  Part A established, now extended one demo further                    │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — VPC/SG re-apply                                              │
│  Demo 16/17's module code, re-applied as persistent infrastructure     │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — EKS cluster (Auto Mode)                                      │
│  EC2-backed managed compute, no OIDC identity provider (ADR-021)       │
├─────────────────────────────────────────────────────────────────────────┤
│  PART D — Kubernetes manifests: Deployment, Service, Ingress           │
│  Applied via kubectl, not a Terraform Kubernetes provider              │
├─────────────────────────────────────────────────────────────────────────┤
│  PART E — Verify: UI reachable over HTTPS through a real ALB           │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- Why this directory must recreate 22b's full configuration and 22c's
  `ecr.tf`/`acm.tf` verbatim before adding a single line of VPC or EKS
  code — the same shared-state requirement 22c's own Part A
  established, now covering one more demo's worth of accumulated files
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
real, external evidence rather than left as open guesses. **A third
verification item, on ALB prerequisites, was found and added this
session — it was not previously flagged at all, and directly affects
whether Part E's stated goal is actually reachable.**

### VERIFY 1 — `compute_config`, the cluster's own IAM policies, and its trust policy

**Confirmed, not just "very likely," via a real, documented AWS API
error:** `node_role_arn` and `node_pools` are not independently
optional once either is set — a real GitHub issue against
`terraform-aws-modules/terraform-aws-eks` reproduces AWS rejecting a
cluster with `node_role_arn` set but `node_pools` omitted, with the
exact error: `InvalidParameterException: When Compute Config
nodeRoleArn is not null or empty, nodePool value(s) must be provided.`
This demo's Lab already sets both together, which is confirmed
correct.

**A second, previously-unflagged gap, found and fixed this session:**
multiple independent, real, working Auto Mode configurations attach
several *additional* managed policies to the **cluster's own IAM
role** — not just the node role — beyond the single
`AmazonEKSClusterPolicy` this demo originally attached:
`AmazonEKSComputePolicy`, `AmazonEKSBlockStoragePolicy`,
`AmazonEKSLoadBalancingPolicy`, and `AmazonEKSNetworkingPolicy`. These
map directly onto Auto Mode's own capabilities (compute management,
block storage, load balancing, networking) that a bare cluster policy
alone doesn't cover, and are now confirmed against AWS's own official
EKS documentation directly (not just working examples). The Lab below
includes these.

**A third, previously-unflagged gap, found this session, confirmed
against AWS's own official documentation:** the cluster role's trust
policy must include `sts:TagSession` alongside `sts:AssumeRole`, or
tag propagation from Kubernetes to AWS Load Balancer resources doesn't
work — AWS's own EKS Auto Mode documentation states this as a
requirement in two separate places, once generally for the cluster
role and once specifically tied to the ALB-creation step this demo
performs in Part D. This demo's `eks.tf` originally granted only
`sts:AssumeRole`. **Fixed in the Lab below.** (The node role's trust
policy is unaffected — AWS's docs confirm it needs only
`sts:AssumeRole`, since it's assumed by EC2, not by the EKS service
itself.)

### VERIFY 2 — Security-group module version and shape — resolved and upgraded

**Confirmed this session against the module's live, current official
documentation, and now upgraded to match.** `terraform-aws-modules/
security-group/aws`'s `~> 6.0` line (Demo 17's pin) uses the newer,
object-map `ingress_rules`/`egress_rules` shape; the `~> 5.0` line
(this demo's original pin) used the older `ingress_cidr_blocks` +
named-string `ingress_rules` shape. **Both were individually correct
for the major version each one pinned** — this was never actually a
contradiction requiring a "which one is wrong" resolution, just two
demos using two different, both-real, both-valid major versions of the
same module with no cross-reference calling that out.

**Upgraded this session, not just flagged.** The original version of
this VERIFY item left the bump as "a separate maintenance decision,"
reasoning that changing it would mean modifying real, applied
infrastructure rather than just a documentation claim. **That
reasoning doesn't actually hold for this specific demo:** this
demo's VPC/security-group layer is torn down at the end of every
session (see Cleanup) — there's no existing, currently-applied state
for a version bump to migrate or drift against. The next time this
demo's Lab is run, it applies fresh, under whichever version is
pinned. On that basis, `module.eks_sg` in `vpc.tf` (Part B) has been
upgraded to `~> 6.0`, with its shape rewritten to the object-map
pattern Demo 17 already confirmed correct — for project-wide
consistency between the two demos, not just an intention noted for
later.

**The output-rename dependency this upgrade carries, per Demo 17's
own verification this same session:** the module's `v6.0.0` release
renamed every output (`security_group_id`→`id`, and similarly for
`arn`/`vpc_id`/`owner_id`/`name`). This demo's own shown Lab content
never references `module.eks_sg`'s output directly (no
`security_group_ids` argument appears in `aws_eks_cluster.main`'s
`vpc_config` block, and none of this demo's other resources consume
it) — so as shown, the rename has nothing to break.

### VERIFY 3 — ALB prerequisites: subnet tags and `IngressClassParams.scheme` — new this session

**Two real, previously-unflagged gaps, both confirmed against AWS's
own official "Tag subnets for EKS Auto Mode" and "Create an
IngressClass" documentation, both directly threatening whether Part
E's stated goal (a real, internet-facing ALB) actually works:**

1. **Subnet tags.** AWS's own documentation states plainly: subnets
   used for Auto Mode's load balancing must be tagged
   `kubernetes.io/role/elb` (public subnets, for internet-facing load
   balancers) or `kubernetes.io/role/internal-elb` (private subnets,
   for internal load balancers) — without these, Auto Mode has no way
   to know which subnets an ALB belongs in. This demo's original
   `vpc.tf` set no subnet-level tags at all beyond a top-level
   `Project` tag. **Fixed in the Lab below**, using the
   `terraform-aws-modules/vpc/aws` module's own `public_subnet_tags`/
   `private_subnet_tags` arguments.
2. **`IngressClassParams.spec.scheme`.** AWS's own official walkthrough
   for creating an Auto Mode ALB sets the internet-facing/internal
   choice via a `scheme` field directly on `IngressClassParams` —
   this demo instead relied solely on the `alb.ingress.kubernetes.io/
   scheme` annotation on the `Ingress` object. That annotation's
   behavior under Auto Mode isn't confirmed anywhere in AWS's own
   documentation (it isn't listed among the annotations Auto Mode
   explicitly does *not* support, but it also isn't part of any
   official example) — rather than rely on unconfirmed behavior for
   something this demo's entire Part E depends on, `scheme:
   internet-facing` has been added directly to `IngressClassParams`
   in the Lab below, matching AWS's own documented pattern exactly.
   The Ingress annotation is left in place as a harmless,
   belt-and-suspenders duplicate, not removed.

### VERIFY 4 — ECR lifecycle policy default — new this session, confirmed via a real run, fix corrected after cross-checking Demo 19's real content

**A real, reproduced bug, surfaced by a live `apply` against 22c's
`ecr.tf` (recreated verbatim in this demo's own Part A).**
`terraform-aws-modules/ecr/aws`'s current `variables.tf` defaults
`create_lifecycle_policy = true`, paired with
`repository_lifecycle_policy` defaulting to `""` (an empty string).
Left at those defaults, every one of the five ECR repos this demo's
Part A recreates fails at `apply` with a real AWS API rejection:
`InvalidParameterException: Invalid parameter at
'lifecyclePolicyText' failed to satisfy constraint: 'Member must have
length greater than or equal to 100'` — AWS refuses an empty lifecycle
policy outright.

**The fix was corrected once Demo 19's own real, verified content
became available for comparison.** An earlier version of this fix
disabled lifecycle policies outright (`create_lifecycle_policy =
false`) — a working fix, but a real deviation from 22c's own stated
design goal of matching Demo 19's technique exactly. **Demo 19's real
`main.tf`, for this identical module, never hits this bug at all —
because it always supplies a real, non-empty
`repository_lifecycle_policy` ("Keep last 10 images"), never leaving
the argument at its default.** The corrected fix in Part A, Step 3
below supplies that same real policy, matching Demo 19's own working
code — which both resolves the bug and keeps the "same technique"
claim actually true, and gives these persistent, real repos the same
automatic image cleanup Demo 19's teaching rep had.

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** one EKS cluster (Auto Mode, EC2-backed
nodes), re-applying Demo 16/17's VPC and security group modules as
persistent infrastructure underneath it, plus a Kubernetes Deployment,
Service, and Ingress for the UI service alone. The Ingress triggers
Auto Mode's built-in ALB provisioning, terminating TLS with 22c's
certificate.

**Why this demo's own directory has to start by recreating three
prior demos' worth of configuration, not just adding new files.** This
project's Phase 3+ demos share one continuously-growing state, not
independent per-demo state files — 22c's own Part A established this
requirement and the reasoning behind it in detail (see that demo's
Concepts section). This demo extends the same requirement one step
further: by the time this demo's directory is ready for Part B's
`vpc.tf`, it needs to contain the *complete* accumulated set — 22b's
eight files (state guardrails) and 22c's two files (`ecr.tf`/`acm.tf`)
— or the same risk 22c flagged applies here too: an incomplete local
configuration pointed at real, already-populated shared state can
propose destroying resources this project has no intention of losing,
including 22c's own ECR repos and ACM certificate that this very demo
depends on.

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
leaving it standing between sessions. **This applies only to Part B
onward** — Part A's recreated files (22b/22c's own resources) are not
touched by this demo's own Cleanup, the same way 22c's Cleanup left
22b's resources untouched.

---

## Prerequisites

### Knowledge
- 22a/22b/22c completed — this demo's Part A recreates 22b's full
  configuration and 22c's `ecr.tf`/`acm.tf` verbatim as its own
  starting point, the same pattern 22c used to recreate 22b's; the
  cluster this demo builds pulls from 22c's ECR repo and binds 22c's
  ACM cert
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
| Docker | Any recent (only if 22c's images need re-verifying) | `docker --version` |

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
  → Confirm EKS, broad EC2, ELB, and IAM role-management access (or
    an equivalent broad policy) is attached ✅ — this demo's
    permission surface is genuinely wider than any prior demo's, see
    below
```

**Required permissions beyond prior demos:**
```
eks:CreateCluster, eks:DescribeCluster, eks:DeleteCluster, eks:UpdateClusterConfig
eks:CreateAccessEntry, eks:AssociateAccessPolicy
ec2:* (Auto Mode manages EC2 instances on your behalf — broad EC2 access needed)
elasticloadbalancing:* (Auto Mode's built-in ALB provisioning)
```

**Also required, previously missing from this list — this demo's own
`eks.tf` creates two IAM roles and seven policy attachments:**
```
iam:CreateRole, iam:DeleteRole, iam:GetRole, iam:TagRole
iam:AttachRolePolicy, iam:DetachRolePolicy, iam:ListAttachedRolePolicies
iam:PassRole
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
| `terraform-aws-modules/security-group/aws` | `~> 6.0` — upgraded this session (see VERIFY 2 above) for consistency with Demo 17; uses the same object-map `ingress_rules`/`egress_rules` shape |
| `terraform-aws-modules/ecr/aws` (Part A, recreated from 22c) | `~> 3.0` — requires a real `repository_lifecycle_policy`, see VERIFY 4 |
| `terraform-aws-modules/acm/aws` (Part A, recreated from 22c) | `~> 6.0` |

> **Versions pinned as of September 2026.**

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain why this demo's own directory must recreate 22b's and
   22c's finished configurations verbatim before adding any VPC or
   EKS content, and what actually goes wrong if that recreation is
   partial rather than complete
2. ✅ Explain what EKS Auto Mode manages for you, versus a self-managed
   or managed-node-group EKS cluster
3. ✅ Write an `aws_eks_cluster` resource configured for Auto Mode with
   API-based access (not the legacy `aws-auth` ConfigMap), including
   the `compute_config` arguments, cluster-role policies, and trust
   policy Auto Mode's real schema and IAM requirements require
4. ✅ Explain why this cluster creates no OIDC identity provider
5. ✅ Write a Kubernetes Ingress using Auto Mode's built-in
   `eks.amazonaws.com/alb` controller, binding an existing ACM
   certificate and load-balancer scheme via `IngressClassParams`
6. ✅ Tag VPC subnets correctly for Auto Mode's load-balancer subnet
   discovery, and explain why this is required
7. ✅ Verify a real HTTPS request reaches a real pod through a real,
   AWS-managed ALB
8. ✅ Recognize when a module version or input shape used earlier in
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
| Part A's recreated 22b/22c resources | N/A | $0.00 additional | These already exist in AWS — Part A only recreates the *local Terraform files* describing them; a correct Part A produces a "no changes" plan, not new spend |
| **Session total (active, Part B onward)** | | **~$0.18–0.20/hr** | **Tear down Part B onward at the end of every session — see Cleanup** |

---

## Directory Structure

```
22d-eks-single-service/
├── README.md
├── 22d-eks-single-service-anki.csv
├── 22d-eks-single-service-quiz.md
├── src/
│   ├── phase-3-onward/                     # same config 22a's backend serves
│   │   ├── versions.tf                     # ← recreated from 22b, Part A
│   │   ├── provider.tf                     # ← recreated from 22b, Part A
│   │   ├── backend.tf                      # ← recreated from 22b, Part A
│   │   ├── variables.tf                    # ← recreated from 22b, Part A
│   │   ├── locals.tf                       # ← recreated from 22b, Part A
│   │   ├── cost_governance.tf              # ← recreated from 22b, Part A
│   │   ├── budgets.tf                      # ← recreated from 22b, Part A
│   │   ├── outputs.tf                      # ← recreated from 22b, Part A, then
│   │   │                                   #   extended in Part C with this
│   │   │                                   #   demo's own cluster_name/endpoint
│   │   ├── terraform.tfvars                # ← your own real values, gitignored,
│   │   │                                   #   not shown in this README
│   │   ├── ecr.tf                          # ← recreated from 22c, Part A
│   │   │                                   #   (with the real lifecycle
│   │   │                                   #   policy fix from VERIFY 4)
│   │   ├── acm.tf                          # ← recreated from 22c, Part A
│   │   ├── vpc.tf                          # NEW this demo — Demo 16/17's module, re-applied
│   │   └── eks.tf                          # NEW this demo — aws_eks_cluster, Auto Mode
│   └── k8s/                                 # applied via kubectl, not Terraform
│       ├── ui-deployment.yaml
│       ├── ui-service.yaml
│       └── ui-ingress.yaml
└── break-fix/
    └── broken-ingress.yaml
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
4. What does a `terraform plan` reporting "no changes" immediately
   after recreating a prior demo's baseline actually prove?

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
4. That the recreation was both correct and complete — that this
   directory's local files now fully and accurately describe every
   resource the real, shared state already tracks, with nothing
   missing that would otherwise be proposed for destruction.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| Recreating a three-demo accumulated configuration verbatim | Applied workflow discipline, not a new construct | The same pattern 22c established for 22b's files, now extended to also cover 22c's own `ecr.tf`/`acm.tf` |
| `aws_eks_cluster` | Resource | The EKS control plane itself |
| `compute_config` | Resource nested block | Enables Auto Mode — AWS manages node provisioning, scaling, and patching (see VERIFY 1 above — now confirmed against a real API error) |
| `kubernetes_network_config.elastic_load_balancing` | Resource nested block | Enables Auto Mode's built-in ALB support |
| `access_config` (API mode) | Resource nested block | Modern EKS authentication — replaces the legacy `aws-auth` ConfigMap |
| `aws_eks_access_entry` | Resource | Grants your own IAM identity permission to interact with the cluster |
| `public_subnet_tags` / `private_subnet_tags` | VPC module inputs | Tags Auto Mode requires to discover which subnets an ALB belongs in (see VERIFY 3 above) |
| Kubernetes `Deployment`/`Service`/`Ingress` | Kubernetes API objects, not Terraform constructs | Applied via `kubectl`, not this series' Terraform tooling |
| `IngressClassParams` | Kubernetes API object (Auto Mode-specific) | Binds an ACM certificate ARN and load-balancer scheme to an Ingress without a separate controller install |

---

### Detailed Explanation of New Constructs

#### Why This Demo's Baseline Now Spans Three Prior Demos

22c's own Concepts section laid out the core reasoning: this project's
Phase 3+ demos share one continuously-growing state, and Terraform
reconciles that real, applied state against whatever `.tf` files are
physically present in whichever directory you're running commands
from. Anything tracked in state but missing locally gets proposed for
**destruction**, not left alone. This demo doesn't introduce a new
version of that risk — it's the same risk, just with one more demo's
files (22c's `ecr.tf`/`acm.tf`) added to what needs recreating
alongside 22b's full set. The same distinction 22c drew still holds
here: skipping the recreation entirely fails safely (no `backend.tf`
means `init` can't reach the state at all), while a *partial*
recreation is the genuinely dangerous case, since it's the one that
can reach real state while describing it incompletely.

---

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

> **The cluster role's trust policy needs `sts:TagSession`, not just
> `sts:AssumeRole` — see VERIFY 1 above.** This is easy to miss because
> the node role's trust policy genuinely doesn't need it — the two
> roles have different trust requirements, not a copy-paste pair.

---

#### Tagging Subnets for Auto Mode's Load Balancer Discovery

Auto Mode needs to know which subnets are public (for internet-facing
load balancers) and which are private (for internal ones) — it can't
infer this from route tables alone. AWS's own documentation is direct
about this being required, not optional, for any Ingress that's meant
to provision a real ALB:

```hcl
module "vpc" {
  # ...
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
```

> **This is a real, previously-unflagged gap this demo's original
> Lab had — see VERIFY 3 above.** Without these tags, there's no
> Auto-Mode-visible signal for which subnets an internet-facing ALB
> belongs in, which directly threatens the one thing Part E exists to
> prove.

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

**Binding an existing ACM certificate and scheme — `IngressClassParams`:**

```yaml
apiVersion: eks.amazonaws.com/v1
kind: IngressClassParams
metadata:
  name: alb-cloudnova
spec:
  scheme: internet-facing
  # ↑ confirmed this session (VERIFY 3): AWS's own official example
  # sets scheme here, on IngressClassParams — not via an Ingress
  # annotation, whose behavior under Auto Mode isn't confirmed
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
> permanently fixed syntax. The `certificateARNs` field name and the
> `scheme` field are both confirmed current as of this session's
> verification.

---

#### Re-Creating an Already-Taught Resource — Why It's Not Redundant

Demo 16 and Demo 17 already taught you the VPC and security-group
modules. This demo uses both again, on purpose, producing objects that
look identical to what you already built. As with 22c's own ECR/ACM
re-creation, the distinction is lifecycle, not technique: Demo 16/17's
objects were teaching reps, torn down at their own Cleanup; this
demo's VPC and security group are meant to persist for the rest of
the session (though, unlike 22b/22c's objects, torn down again at the
*end* of every session — see "Why this is the first demo torn down
every session" above).

---

## Lab Step-by-Step Guide

---

## Part A — Recreate the Accumulated Baseline (22a + 22b + 22c)

Part A brings this fresh directory up to the same state every prior
Phase 3+ demo left it in, before this demo adds a single line of VPC
or EKS code — see "Why This Demo's Baseline Now Spans Three Prior
Demos" above for why this isn't optional tidying.

### Step 1 — Navigate to the project config

```bash
cd terraform-aws-mastery/phase-3-real-aws-infrastructure/22d-eks-single-service/src/phase-3-onward
```

### Step 2 — Recreate 22b's finished configuration, verbatim

This step recreates every file 22b's own Lab produced, exactly as
that demo built it — the same discipline 22c's own Part A used.

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

**provider.tf:**

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = local.common_tags
  }
}
```

**backend.tf:**

```hcl
terraform {
  backend "s3" {
    bucket       = "<YOUR_22A_STATE_BUCKET_NAME>"
    key          = "phase-3-onward/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
  }
}
```

> Same placeholder, same warning as 22b/22c: replace
> `<YOUR_22A_STATE_BUCKET_NAME>` with the real bucket 22a created —
> `terraform init` fails immediately and harmlessly if it's wrong.

**variables.tf:**

```hcl
# ── Provider configuration ─────────────────────────────────────────────────

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

# ── Project identity ───────────────────────────────────────────────────────

variable "project" {
  type        = string
  description = "Project name — used in resource names and tags"
  default     = "cloudnova"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "dev"
  nullable    = false
}

variable "demo" {
  type        = string
  description = "Demo identifier — used in tags for traceability"
  default     = "22b-cost-governance"
}

# ── Notification ───────────────────────────────────────────────────────────

variable "notification_email" {
  type        = string
  description = "Email address to receive cost and budget notifications"
  # No default — set this in terraform.tfvars, don't hardcode a real
  # email into a file that might get committed
}

variable "monthly_budget_limit" {
  type        = string
  description = "Your available AWS credit/budget for this project, in USD"
  # No default — this is genuinely personal to your account; set it
  # in terraform.tfvars
}
```

**locals.tf:**

```hcl
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Demo        = var.demo
    ManagedBy   = "Terraform"
  }
}
```

**cost_governance.tf:**

```hcl
resource "aws_sns_topic" "cost_alerts" {
  name              = "cloudnova-cost-alerts"
  kms_master_key_id = "alias/aws/sns" # AWS managed key — no monthly fee
}

resource "aws_sns_topic_subscription" "cost_alerts_email" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_cloudwatch_event_rule" "session_length_check" {
  name                = "cloudnova-session-length-check"
  description         = "Checks tagged Phase 3+ resources against a session-length threshold"
  schedule_expression = "rate(1 hour)"
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "notify_sns" {
  rule      = aws_cloudwatch_event_rule.session_length_check.name
  target_id = "cost-alerts-sns"
  arn       = aws_sns_topic.cost_alerts.arn
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.cost_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.cost_alerts.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.session_length_check.arn
        }
      }
    }]
  })
}
```

**budgets.tf:**

```hcl
resource "aws_budgets_budget" "monthly_cost" {
  name         = "cloudnova-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }
}
```

**outputs.tf** (this demo extends this file further in Part C — this
is 22b's original content only, for now):

```hcl
output "cost_alerts_topic_arn" {
  description = "ARN of the cost-alerts SNS topic"
  value       = aws_sns_topic.cost_alerts.arn
}

output "monthly_budget_name" {
  description = "Name of the monthly cost budget"
  value       = aws_budgets_budget.monthly_cost.name
}
```

Finally, create a `terraform.tfvars` with your own real values — **not
shown here, and not committed:**

```
notification_email   = "you@example.com"
monthly_budget_limit = "50"
```

### Step 3 — Recreate 22c's finished configuration, verbatim

This step adds the two files 22c introduced on top of 22b's baseline —
the persistent ECR repos and ACM certificate this demo's own cluster
depends on.

**ecr.tf:**

```hcl
locals {
  services = ["ui", "catalog", "cart", "orders", "checkout"]
}

module "ecr" {
  source   = "terraform-aws-modules/ecr/aws"
  version  = "~> 3.0"
  for_each = toset(local.services)

  repository_name = "cloudnova-retail-${each.key}"

  # Real, non-empty policy required — see VERIFY 4. Same policy
  # Demo 19 already established for this exact module; this is the
  # actual fix, not create_lifecycle_policy = false.
  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  tags = {
    Project = "cloudnova-retail-store-e2e"
    Purpose = "persistent-ecr"
  }
}
```

**acm.tf:**

```hcl
data "aws_route53_zone" "main" {
  name         = "rselvantech.com."
  private_zone = false
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 6.0"

  domain_name = "app.rselvantech.com"
  zone_id     = data.aws_route53_zone.main.zone_id

  validation_method   = "DNS"
  wait_for_validation = true
}
```

> **Getting 22c's real certificate ARN for Part D, ahead of time.**
> You'll need this later, in Part D's `ui-ingress.yaml` — worth
> confirming you can retrieve it now, before you're mid-Ingress-write.
> Once this step's `acm.tf` is applied (Step 4 below), run `terraform
> output -raw certificate_arn` if 22c defined that output, using the
> correct attribute — `module.acm.acm_certificate_arn`, **not**
> `certificate_arn`, which looks plausible but doesn't exist on this
> module and fails with `Unsupported attribute` (confirmed via a real
> `apply` against Demo 20 this same session). If no such output
> exists, use `aws acm list-certificates --region us-east-2 --profile
> default` and match the domain (`app.rselvantech.com`) instead.

### Step 4 — Confirm the recreated baseline matches reality before adding anything new

This step is the actual proof Part A worked: a `plan` here should
report **zero** changes, confirming this directory's files now
completely and accurately describe every resource 22b and 22c already
applied — before Part B adds `vpc.tf`.

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

> **Note the `apply` here, unlike 22c's own equivalent step.** Unless
> your account already has 22c's ECR repos and certificate applied
> from a real prior run, this `apply` is what actually creates them —
> in which case `plan` won't show "no changes" the first time through,
> it will show 22c's own resources being created for the first time.
> If you've already run 22c for real and this is a genuinely fresh
> directory pointed at the same state, `plan` should instead show no
> changes, confirming the recreation matches what's already applied —
> watch for the real `InvalidParameterException` from VERIFY 4 on this
> `apply` specifically if `ecr.tf`'s `repository_lifecycle_policy` was
> left out or left empty above.

> **If `plan` proposes destroying any of 22b's six resources or 22c's
> ECR/ACM resources you expected to already exist, stop here** — one
> of the files above wasn't recreated correctly, or was left out
> entirely. Fix that before proceeding to Part B; don't `apply` a plan
> that proposes destroying resources you didn't intend to touch.

---

## Part B — Re-Apply VPC and Security Groups

Part B re-applies Demo 16/17's VPC and security-group module code as
this environment's first piece of persistent infrastructure, on top
of the baseline Part A just confirmed.

### Step 5 — Add vpc.tf

This step re-applies Demo 16's VPC module alongside Demo 17's
security-group module, both now standing up persistent infrastructure
for the first time rather than a teaching rep.

Create a file **vpc.tf** and add the below content:

This file contains both module calls — the VPC itself, now with the
subnet tags Auto Mode's load balancer needs to discover them (VERIFY
3), and the security group governing traffic to the EKS nodes this
demo is about to create.

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

  # ── Required for Auto Mode's ALB to discover these subnets (VERIFY 3) ──
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    Project = "cloudnova-retail-store-e2e"
  }
}

module "eks_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name   = "cloudnova-eks-nodes"
  vpc_id = module.vpc.vpc_id

  ingress_rules = {
    all_from_vpc = {
      ip_protocol = "-1"
      cidr_ipv4   = module.vpc.vpc_cidr_block
      description = "Allow all traffic from within the VPC"
    }
  }

  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound"
    }
  }
}
```

> **Upgraded this session — see VERIFY 2 above.** This module call now
> pins `~> 6.0`, the same major version and object-map
> `ingress_rules`/`egress_rules` shape Demo 17 already confirmed
> correct — the `~> 5.0`/list-based version this demo originally
> pinned was individually correct too, just one version behind. Since
> this demo's VPC/security-group layer is torn down every session
> (Cleanup), there's no existing applied state this upgrade needs to
> migrate.

> **Cross-checked from Demo 16's own governance review this session:
> the VPC module adopts and empties the VPC's default security
> group.** `terraform-aws-modules/vpc/aws` defaults
> `manage_default_security_group = true` (standing behavior since the
> module's v4.0.0, not v6-specific) — this module call doesn't
> override that, so it adopts the VPC's AWS-provisioned default
> security group via `aws_default_security_group.this`. Per that
> resource's own documented behavior, adoption **strips every rule the
> default SG originally had**, and since this module call specifies no
> rules for it, it ends up completely empty. This demo's own EKS node
> traffic goes through `module.eks_sg` above, not the default SG — but
> unlike Demo 16's own teaching-rep VPC (torn down every session), this
> demo's VPC is real, session-persistent infrastructure, so it's worth
> knowing this default SG has zero rules for the duration of the
> session, in case anything else in a real environment assumes
> otherwise.

> **Same-as-Demo-16/17 note, updated:** the VPC module call is
> otherwise unchanged from what Demo 16 taught. The security-group
> module call is the one piece that's genuinely different from this
> demo's own original content — it's now pinned and shaped to match
> Demo 17 exactly (see VERIFY 2), rather than the older version this
> demo originally used. What's genuinely new this session, altogether:
> the two subnet-tag arguments (VERIFY 3), and the security-group
> module's version/shape upgrade — the module call technique itself is
> familiar from Demo 17, the subnet tags and the persistent lifecycle
> aren't.

### Step 6 — Apply

This step applies the VPC and security group as persistent
infrastructure, on top of the backend Part A already confirmed points
at the correct, shared state.

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

---

## Part C — EKS Cluster (Auto Mode)

Part C creates the EKS cluster itself, configured for Auto Mode with
no legacy authentication and no OIDC identity provider.

### Step 7 — Add eks.tf

This step writes the cluster resource and both IAM roles it depends
on — the cluster's own role, now with the additional Auto-Mode-specific
policies and trust-policy action found this session, and a separate
role for the nodes Auto Mode manages on your behalf.

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
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      # ↑ sts:TagSession added this session (VERIFY 1) — confirmed
      # required by AWS's own docs for Auto Mode cluster roles, and
      # specifically for tag propagation to AWS Load Balancer
      # resources created via this demo's own Ingress in Part D.
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── Auto Mode-specific policies on the CLUSTER's own role ────────────────
# Added this session: confirmed against AWS's own official documentation
# that these are attached alongside AmazonEKSClusterPolicy — they map
# onto Auto Mode's compute/storage/load-balancing/networking
# capabilities, which the base cluster policy alone doesn't cover.
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
      # ↑ this role does NOT need sts:TagSession — confirmed against
      # AWS's own docs; that requirement is specific to the cluster
      # role above, not the node role.
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

This step also extends `outputs.tf` (originally recreated from 22b in
Part A), so Step 9's `kubectl` configuration below can read the
cluster name back from Terraform instead of relying on a hardcoded
string.

Add to **outputs.tf**:

```hcl
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "API server endpoint for the EKS cluster"
  value       = aws_eks_cluster.main.endpoint
}
```

> **VERIFY 1, restated at the point of use:** the `compute_config`
> block's `node_pools`/`node_role_arn` pairing is confirmed via a real,
> reproduced AWS API error. The cluster-role policy attachments and
> the `sts:TagSession` trust-policy action are both confirmed directly
> against AWS's own official documentation this session — not just
> inferred from external examples.

> **Same-as-Demo-08 note, restated:** `data.aws_caller_identity` here
> is the identical construct Demo 08 taught — reused to grant your own
> IAM identity cluster access, not a new data source.

### Step 8 — Apply

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
> policies; the `sts:TagSession` addition sits inside the existing
> trust-policy JSON and doesn't change this count. Treat the count as
> illustrative pending your own `apply`. **This count reflects only
> this demo's own new resources (Part B/C) — Part A's recreated
> resources were already confirmed via Step 4's "no changes" plan and
> aren't part of this apply at all.**

> **Bolded takeaway:** EKS cluster creation genuinely takes 10–15
> minutes — this isn't a hung terminal. This is a real, worth-planning-around
> characteristic of EKS specifically, unlike most resources this
> series has built so far.

### Step 9 — Configure kubectl

This step points `kubectl` at the new cluster and confirms Auto Mode
has already provisioned at least one node, without you creating it
directly.

```bash
aws eks update-kubeconfig --name "$(terraform output -raw cluster_name)" --region us-east-2 --profile default
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

## Part D — Kubernetes Manifests: Deployment, Service, Ingress

Part D deploys the UI service itself, entirely via `kubectl` — nothing
in this Part touches Terraform.

### Step 10 — Add ui-deployment.yaml

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

### Step 11 — Add ui-service.yaml

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

### Step 12 — Add the Ingress and its IngressClassParams

This step writes the three objects that together trigger Auto Mode's
built-in ALB provisioning and bind 22c's certificate to it.

Create a file **k8s/ui-ingress.yaml** and add the below content:

This file contains the `IngressClassParams` binding the certificate
and scheme, the `IngressClass` referencing Auto Mode's own ALB
controller, and the `Ingress` itself routing all traffic to the UI
Service.

```yaml
apiVersion: eks.amazonaws.com/v1
kind: IngressClassParams
metadata:
  name: alb-cloudnova
spec:
  scheme: internet-facing
  # ↑ added this session (VERIFY 3) — AWS's own official pattern sets
  # scheme here, on IngressClassParams, not solely via an Ingress
  # annotation
  certificateARNs:
    - "arn:aws:acm:us-east-2:<ACCOUNT_ID>:certificate/<CERT_ID>"
    # ↑ 22c's certificate ARN — see Part A, Step 3's note on how to
    # retrieve this if you haven't already

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
    # ↑ left in place as a harmless, belt-and-suspenders duplicate of
    # IngressClassParams's own scheme field above — the annotation's
    # own behavior under Auto Mode isn't confirmed either way, so the
    # IngressClassParams field above is what this demo actually relies
    # on (VERIFY 3)
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

### Step 13 — Apply and wait for the ALB

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
> guarantee. If the `ADDRESS` field never populates, check the subnet
> tags and cluster-role trust policy from VERIFY 1/3 first — a missing
> subnet tag or `sts:TagSession` is the most likely real-world cause,
> not a transient delay.

---

## Part E — Verify

Part E confirms the entire chain actually works, ending with a real
browser-equivalent request over the public internet.

### Step 14 — Confirm via kubectl

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

### Step 15 — Real HTTPS request

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

**Unlike 22a/22b/22c, and unlike this demo's own Part A, this demo's
Cleanup step tears down Part B and Part C's resources.** The EKS
control plane's flat fee means an idle cluster costs money whether or
not anything is deployed to it — there's no cost argument for leaving
it standing between sessions. **Part A's recreated resources (22b's
governance layer, 22c's ECR repos and certificate) are untouched by
this Cleanup, the same way 22c's own Cleanup left 22b's resources
alone.**

### Step 16 — Destroy Part B and Part C's resources

```bash
kubectl delete -f k8s/
terraform destroy -target=aws_eks_cluster.main -target=module.vpc -target=module.eks_sg
```

```
⚠️ Simulated expected output

Destroy complete! Resources: X destroyed.
```

> **Why `-target` here, rather than a plain `terraform destroy`:** a
> plain `destroy` in this directory would tear down *everything*
> tracked in the shared state — including 22b's governance layer and
> 22c's ECR repos and certificate, which must survive. Targeting
> `aws_eks_cluster.main`, `module.vpc`, and `module.eks_sg`
> specifically destroys this demo's own Part B/C resources (and their
> dependents, including the two IAM roles and their policy
> attachments) while leaving Part A's recreated baseline untouched.
> Confirm with `terraform state list` afterward that 22b's and 22c's
> resources are still present.

```
Console → EKS → Clusters → confirm cloudnova-eks: GONE ✅
Console → EC2 → Load Balancers → confirm the ALB: GONE ✅
Console → VPC → confirm cloudnova-vpc: GONE ✅
Console → SNS/Budgets → confirm 22b's resources: STILL PRESENT ✅
Console → ECR/Certificate Manager → confirm 22c's resources: STILL PRESENT ✅
```

> ⚠️ **Confirm 22a/22b/22c's resources are still standing before you
> end the session** — this demo's teardown should touch nothing from
> those three. `terraform state list` should still show 22b's six
> resources and 22c's ECR/ACM resources untouched.

---

## What You Learned

1. ✅ This demo's own directory must recreate three prior demos' worth
   of accumulated configuration before adding anything new — the same
   shared-state requirement 22c established, extended one demo
   further, and confirmed via a clean "no changes" `plan` before any
   new resource is written.
2. ✅ EKS Auto Mode manages compute, storage, and load balancing for
   you — a genuinely different operating model than self-managed nodes
   or managed node groups, not just "the same thing with less config."
3. ✅ This cluster creates no OIDC identity provider — Pod Identity
   (Demo 24) doesn't need one, unlike the IRSA pattern many EKS
   tutorials default to.
4. ✅ Auto Mode's built-in ALB support replaces what used to require a
   separately-installed AWS Load Balancer Controller — one
   `elastic_load_balancing { enabled = true }` flag, plus standard
   Kubernetes `Ingress`/`IngressClass`/`IngressClassParams` objects.
5. ✅ Auto Mode's ALB has real, easy-to-miss prerequisites beyond the
   cluster resource itself: the cluster role's trust policy needs
   `sts:TagSession`, and VPC subnets need `kubernetes.io/role/elb`/
   `internal-elb` tags — neither is optional, both are confirmed
   directly against AWS's own documentation.
6. ✅ This series draws a deliberate line: Terraform builds the
   cluster, `kubectl` deploys the workload — not a gap, a scope choice.
7. ✅ EKS cluster creation genuinely takes 10–15 minutes — plan around
   this real characteristic rather than assuming something's stuck.
8. ✅ A module version or input shape reused across two demos should
   be resolved against real documentation when it appears to
   conflict — not assumed wrong on either side without checking.
9. ✅ Tearing down part of a shared-state directory's resources
   without touching the rest requires `-target`, not a plain
   `destroy` — the first genuinely partial teardown this series has
   needed.
10. ✅ A module's own defaults can silently produce an invalid
    real-world API request — the ECR module's default lifecycle
    policy is empty, and AWS rejects empty lifecycle policies outright.
    Reading a module's actual default values matters, not just its
    documented examples.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| Recreating an accumulated multi-demo configuration before extending it | TA-004 Obj 3 — Terraform workflow, state | Same principle 22c established, now spanning three demos' worth of files |
| `terraform destroy -target` | TA-004 Obj 3 — Terraform workflow | Real, supported partial-teardown mechanism — necessary here because this directory's state spans resources with different teardown lifecycles |
| `aws_eks_cluster`, `compute_config` | TA-004 Obj 4a — Resource configuration | Provider-specific resource; Auto Mode-specific arguments are newer additions worth confirming against current provider docs |
| `access_config.authentication_mode = "API"` | TA-004 Obj 4a | Modern EKS access pattern — know this exists as an alternative to the legacy `aws-auth` ConfigMap approach |
| Terraform's scope boundary at the cluster (not into Kubernetes objects) | TA-004 Obj 1 — IaC concepts generally | Recognize this as a deliberate tooling boundary, not a Terraform limitation |
| Module defaults producing an invalid real-world request | TA-004 Obj 4a/9 | A config can `validate` and `plan` cleanly and still fail at `apply` against the real API, if a module's own default value is itself invalid |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "One directory's state tracks resources with two different teardown lifecycles — how do you destroy only some of them?" | `terraform destroy -target=<address>`, repeated or combined for each resource/module that should go | Assuming a plain `destroy` can somehow be scoped by convention alone, or that state must be split into separate files to allow partial teardown |
| "Does every EKS cluster require an OIDC identity provider?" | No — only clusters using IRSA for pod-level IAM identity need one. Pod Identity doesn't. | Assuming OIDC providers are a universal EKS requirement because most IRSA tutorials pair them by default |
| "Can Terraform directly manage Kubernetes Deployments inside an EKS cluster it created?" | Yes, technically, via a Kubernetes provider — but this series deliberately doesn't, drawing a scope line at the cluster boundary | Assuming Terraform *must* manage in-cluster objects because it created the cluster |
| "Is `compute_config { enabled = true }` a complete Auto Mode configuration?" | No — `node_pools` and `node_role_arn` are conditionally required together (confirmed via a real AWS API error), the cluster's own role needs Auto-Mode-specific policies beyond the base cluster policy, and its trust policy needs `sts:TagSession` | Assuming a single boolean flag fully configures a feature this substantial |
| "Will an Ingress with a correct certificate ARN reliably get an internet-facing ALB, given `elastic_load_balancing.enabled = true`?" | Not necessarily — subnets must also be tagged `kubernetes.io/role/elb`/`internal-elb`, or Auto Mode has no signal for where the ALB belongs | Assuming the cluster-level flag alone is sufficient without any VPC-side configuration |
| "A module call passes `terraform validate` and `plan` cleanly — does that mean `apply` will succeed?" | Not necessarily — a module's own default argument value can itself be invalid against the real provider API, and neither `validate` nor `plan` catches that; only a real `apply` does | Assuming a clean `plan` guarantees a clean `apply` |

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
      Action    = ["sts:AssumeRole", "sts:TagSession"]
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
- The cluster role's trust policy needs both `sts:AssumeRole` and
  `sts:TagSession` — the node role's needs only `sts:AssumeRole`

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `terraform init` fails with no backend configured, or a local-state warning | Part A's `backend.tf` was never recreated in this directory | Recreate every file Part A lists before proceeding — see Steps 2–3 |
| `terraform plan` (Step 4) proposes destroying 22b's or 22c's resources | Part A's recreation was incomplete — one or more files from 22b or 22c is missing from this directory | Diff this directory's files against 22b's and 22c's own Lab content file-by-file; re-run Step 4 until it reports no changes (or a clean first-time create, if this is a genuinely first run) before touching Part B |
| `terraform apply` (Step 4) fails on `aws_ecr_lifecycle_policy.this[0]` with `'lifecyclePolicyText' failed to satisfy constraint: 'Member must have length greater than or equal to 100'` | The ECR module defaults `create_lifecycle_policy = true` with `repository_lifecycle_policy` defaulting to `""` — AWS rejects an empty lifecycle policy outright (see VERIFY 4) | Confirm `ecr.tf` (Step 3) supplies a real `repository_lifecycle_policy` (the same one Demo 19 uses) — never leave this argument at its default |
| `Error: No value for required variable` on `notification_email`/`monthly_budget_limit` | `terraform.tfvars` wasn't created in this directory | Create it with your real values — see the end of Step 2 |
| `kubectl` commands return `Unauthorized` | Your IAM identity has no access entry on the cluster | Confirm `aws_eks_access_entry` + `aws_eks_access_policy_association` were applied for your actual identity |
| Ingress never gets an `ADDRESS` | `elastic_load_balancing.enabled` wasn't set, subnets aren't tagged `kubernetes.io/role/elb`/`internal-elb`, the cluster role's trust policy is missing `sts:TagSession`, or `IngressClassParams`/`IngressClass` weren't applied before the `Ingress` itself | Check, in order: subnet tags (VERIFY 3), cluster role trust policy (VERIFY 1), then apply order (`kubectl apply -f k8s/` applies all files, but check individual object status if one lags) |
| ALB provisions but traffic doesn't reach it / tags never appear on the ALB | Cluster role's trust policy is missing `sts:TagSession` | Add `sts:TagSession` to the `Action` list in `aws_iam_role.eks_cluster`'s `assume_role_policy` — confirmed required by AWS's own docs |
| `curl` returns a TLS error | Certificate ARN in `IngressClassParams` doesn't match a real, `Issued` cert | Re-check the ARN against 22c's actual `Issued` certificate, not a copy-paste of a placeholder |
| `terraform apply` hangs for 10+ minutes on `aws_eks_cluster` | Normal — not stuck | EKS cluster creation genuinely takes this long; let it complete |
| `InvalidParameterException` mentioning `nodeRoleArn`/`nodePool` | `node_role_arn` and `node_pools` were set independently instead of together | Set both together — this is a confirmed, coupled requirement, not an optional pairing |
| `terraform destroy` at Cleanup proposes destroying 22b's or 22c's resources too | A plain `destroy` was run instead of the `-target`-scoped command in Step 16 | Cancel (don't confirm with `yes`); re-run Step 16's exact `-target` command instead |
| `security_group_id` output reference fails with `Unsupported attribute` | Only relevant if `variables.tf`/`outputs.tf` reference `module.eks_sg`'s output by its pre-`v6.0.0` name — this module now pins `~> 6.0` (upgraded this session, VERIFY 2), whose output is named `id`, not `security_group_id` | Update any such reference to `.id`, matching the fix Demo 17 needed for the identical module upgrade |

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

**Q1. A reviewer asks why this demo's Part A recreates files that have nothing to do with EKS at all — the SNS topic, Budget, ECR repos.**
Because this project's Phase 3+ demos share one continuously-growing state, and Terraform reconciles that real, applied state against whatever `.tf` files are physically present in the directory a command is run from. This directory needs to point at the same shared state 22b and 22c already populated — not a fresh one — so its local files have to fully declare what's already there, or the next `plan` proposes destroying whatever's undeclared. This demo's Part A isn't scope creep; it's the same requirement 22c's own Part A established, extended one demo further to also cover 22c's own files.

**Q2. A teammate asks why this demo's Cleanup uses `terraform destroy -target` instead of a plain `destroy`, when every prior demo either used a plain `destroy` or no destroy at all.**
Because this is the first demo where one directory's state genuinely spans two different teardown lifecycles at once — Part A's recreated resources (22b's governance layer, 22c's ECR/ACM objects) are meant to persist for the rest of the project, while Part B/C's resources (the VPC, security group, and EKS cluster) are meant to be torn down every session. A plain `destroy` doesn't distinguish between them — it destroys everything the state tracks. `-target`, scoped to exactly the resources and modules this demo's own Part B/C introduced, is the actual mechanism for tearing down part of a shared state without touching the rest.

**Q3. A teammate asks why this cluster doesn't have an OIDC identity provider, since every IRSA tutorial they've seen always creates one.**
Because this project uses EKS Pod Identity for per-service IAM identity instead of IRSA — a decision made once at the project level (Demo 24 builds on it, this demo just doesn't need to anticipate it). IRSA specifically requires an OIDC identity provider because it works by federating a Kubernetes service account's token to an IAM role via OIDC trust. Pod Identity associates a service account with a role directly through the EKS Pod Identity API — no OIDC federation involved at all. The pairing of "every EKS cluster gets an OIDC provider" is an IRSA-tutorial convention, not a universal EKS requirement.

**Q4. Someone asks why Terraform built the cluster but `kubectl` deployed the actual application — wouldn't it be cleaner to do everything in Terraform?**
It's a deliberate scope boundary, not laziness or a gap. This series teaches Terraform, and while Terraform *can* manage Kubernetes objects via a dedicated provider, doing so here would mean introducing a second provider ecosystem this curriculum otherwise never covers, just to avoid a second CLI tool. Most real teams draw exactly this line too — infrastructure provisioning (Terraform, or similar) and application deployment (kubectl, Helm, a CD pipeline) are commonly separate concerns, often even owned by different teams. Recognizing where a tool's job legitimately ends is as much a skill as knowing how to use the tool.

**Q5. A reviewer asks how you'd explain why Auto Mode's built-in ALB support matters, versus just installing the AWS Load Balancer Controller yourself.**
The self-managed controller is a real, capable option — many production clusters use it — but it's a component you install, upgrade, and operate yourself: its own Helm chart, its own IAM role, its own version compatibility to track against your Kubernetes version. Auto Mode's built-in support turns that into a single `elastic_load_balancing { enabled = true }` flag on the cluster resource — AWS operates the controller for you, as a managed component. The trade-off is less flexibility than the self-managed controller offers, and — as this demo's own verification work found — real prerequisites of its own (subnet tags, a cluster-role trust-policy action) that aren't obvious from the single flag alone. So it's not strictly better in every case, and it isn't zero-configuration either — just simpler for the common case this demo needed, once those prerequisites are actually met.

**Q6. A reviewer notices this demo's security-group module call uses a different version and shape than Demo 17's, for the identical module. How should that be handled?**
By checking the module's real, current documentation rather than assuming either demo is simply wrong — and that's exactly what happened here. `terraform-aws-modules/security-group/aws`'s `~> 5.0` line (this demo's original pin) genuinely used the older list-based shape, and its `~> 6.0` line (Demo 17) genuinely uses the newer object-map shape — both were individually correct for the version each one pinned. What looked like a contradiction was actually two demos each doing the right thing for a different major version of the same module, with nothing cross-referencing that fact. Once that was confirmed, this demo was upgraded to `~> 6.0` to match Demo 17 — a separate decision from the verification itself, made straightforward here because this demo's VPC/security-group layer never persists between sessions, so there was no existing applied state the upgrade needed to migrate.

**Q7. A reviewer asks what actually made you confident the ALB would come up, beyond "the Terraform apply succeeded."**
Nothing about a successful `terraform apply` on the cluster resource actually proves the ALB will provision correctly — that's a Kubernetes-and-AWS-side outcome, downstream of the cluster existing. The real prerequisites are the subnet tags (`kubernetes.io/role/elb`/`internal-elb`) that tell Auto Mode where the ALB belongs, and the cluster role's `sts:TagSession` trust-policy action that lets Auto Mode propagate tags to the load balancer it creates — both confirmed directly against AWS's own documentation, neither visible from the `aws_eks_cluster` resource succeeding on its own. This is a good example of why "the apply succeeded" and "the thing actually works end-to-end" are different claims, worth checking separately.

**Q8. A reviewer asks how the ECR lifecycle policy bug (VERIFY 4) actually got caught, and what it says about relying on a module's examples versus its defaults.**
It was caught by a real `terraform apply` failing, not by reading documentation — the module's README examples all show `repository_lifecycle_policy` set explicitly to something real, which never surfaces what happens if you *don't* set it. Checking the module's actual `variables.tf` afterward showed why: `create_lifecycle_policy` defaults to `true`, paired with `repository_lifecycle_policy` defaulting to an empty string, and AWS rejects an empty lifecycle policy outright. Neither `terraform validate` nor `terraform plan` caught this — both only check structure and schema, not whether a default value would actually be accepted by the real API. Worth adding: the first fix reached for was disabling the feature outright, which worked but quietly broke this demo's own "matches Demo 19's technique exactly" claim — Demo 19's real code never hits this bug because it always supplies a real policy. Once that comparison was actually possible, the corrected fix supplies that same policy instead, which is both the fix and the thing that keeps the "same technique" claim true.

---

## Key Takeaways

1. **This project's shared state now spans three demos' worth of
   accumulated files before this demo adds anything new — and that
   requirement compounds with every subsequent demo, not just this
   one.** Confirming a clean "no changes" `plan` after recreation is
   the real safety check, not `init` succeeding alone.

2. **EKS Auto Mode is a genuinely different operating model, not a
   config toggle on the same underlying cluster type.** It manages
   compute, storage, and load balancing for you — know what that
   actually changes about your own responsibilities.

3. **Not every EKS cluster needs an OIDC identity provider.** That
   pairing is specific to IRSA; Pod Identity, this project's actual
   choice, has no such dependency.

4. **A managed feature can still have real prerequisites worth knowing
   before you need them.** Auto Mode's built-in ALB support is
   genuinely simpler than the self-managed controller — but "one
   boolean flag" undersells what it actually needs: correctly tagged
   subnets and a trust policy that permits tag propagation, neither of
   which this demo's cluster resource surfaces on its own.

5. **A deliberate tooling scope boundary is a design choice, not a
   gap.** Terraform building the cluster and `kubectl` deploying the
   workload is a considered line, worth being able to explain, not
   just a fact to accept.

6. **Some AWS operations genuinely take a long time, and that's not a
   sign of failure.** EKS cluster creation's 10–15 minutes is real —
   build your own expectations (and any automation timeouts) around
   the actual number, not an assumption borrowed from faster resources.

7. **An apparent cross-demo conflict is worth resolving against real
   documentation, not resolving by assumption.** This demo's own
   security-group module pin looked like a contradiction with Demo
   17's until actually checked — the check, not a guess in either
   direction, is what settled it.

8. **When one directory's state spans resources with different
   teardown lifecycles, `-target` is the actual mechanism for a
   partial teardown.** This is the first demo in the series where a
   plain `destroy` would be actively wrong, not just unnecessary.

9. **A module's own default values can be invalid against the real
   API, and neither `validate` nor `plan` catches that.** The ECR
   module's default lifecycle policy is empty, and AWS rejects empty
   lifecycle policies outright — only a real `apply` surfaced this.
   Worth a second lesson on top: the first fix reached for
   (disabling the feature) worked, but broke a stated consistency
   claim with Demo 19 — the corrected fix, matching Demo 19's own
   real policy, only became possible once that comparison was
   actually available.

> **Demo scope:** Primary concept: standing up an EKS Auto Mode
> cluster and routing real traffic to a single service through its
> built-in ALB support. Supporting concepts: recreating a
> three-demo-deep shared configuration correctly before extending it,
> why Pod Identity removes the OIDC-provider requirement, the
> Terraform/`kubectl` scope boundary, the ALB's real subnet-tag and
> trust-policy prerequisites, resolving apparent cross-demo
> version/shape conflicts against real documentation, partial
> teardown via `-target`, and a module default that fails only at
> real `apply` time.
> Estimated completion time: 60–70 minutes (includes the baseline
> recreation, and EKS cluster creation and ALB provisioning both take
> real, multi-minute wall-clock time).
> Checkpoints: 5 natural stopping points (end of Part A, end of
> Part B, end of Part C, end of Part D, end of Part E).

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
| `terraform init` / `validate` / `plan` / `apply` | Standard workflow — `plan` immediately after Part A's recreation is this demo's own shared-state safety check |
| `terraform destroy -target=<address>` | Partial teardown — used in Cleanup to remove only Part B/C's resources, leaving Part A's recreated baseline intact |

---

## Next Demo

**Demo 23 — EKS: Full Service Mesh:** scales this same pattern to all
five `retail-store-sample-app` services. **Corrected this session —
this no longer requires an open routing decision.** An earlier draft
of this section described a three-option `IngressGroup` decision
(share one ALB across services with path-based rules, use five
separate ALBs, or fall back to the self-managed controller), reasoning
from Auto Mode's built-in ALB support not supporting `IngressGroup` in
the abstract. That framing has since been checked against the app's
actual reference architecture and corrected: only the UI service is
externally routed (via this demo's own Ingress) — Catalog, Cart,
Orders, and Checkout are reached internally, via `ClusterIP` Services
and UI's own service-to-service calls, matching
`retail-store-sample-app`'s real architecture. Since there's only ever
one `Ingress` in this project (UI's, built here), the `IngressGroup`
limitation never actually arises — Demo 23 adds no new Ingress/ALB
work at all.

**Also worth anticipating for whoever builds Demo 23:** its own Part A
will need to extend this same baseline-recreation pattern one demo
further — recreating 22b's, 22c's, *and* this demo's `vpc.tf`/`eks.tf`
verbatim, plus this demo's `outputs.tf` additions, before adding
Catalog/Cart/Orders/Checkout's own manifests. The pattern compounds
with every demo; nothing about it changes going forward, only the
number of files being recreated.

---

## Appendix — Anki Cards

**22d-eks-single-service-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::22d-eks-single-service
#separator:Comma
#columns:Front,Back,Tags
"Why does this demo's Part A recreate files from BOTH 22b and 22c, not just the immediately preceding demo?","Phase 3+ demos share one continuously-growing state. This directory must fully declare every resource already tracked in that shared state - which by this demo means everything 22b (state guardrails) and 22c (ECR/ACM) applied - or an incomplete plan risks proposing their destruction.","demo22d,state,gotcha"
"What does a clean 'No changes' terraform plan immediately after Part A's recreation actually prove?","That the recreation was both correct and complete - this directory's local files now fully and accurately describe every resource the real, shared state already tracks, with nothing missing that would otherwise be proposed for destruction.","demo22d,state,workflow"
"What does EKS Auto Mode manage for you that a managed-node-group cluster doesn't?","Compute provisioning/scaling/patching, storage, and load balancing, end-to-end. Managed node groups still require you to choose instance types and scaling policy - Auto Mode manages compute fully.","demo22d,eks,auto-mode,ta004-obj4a"
"Why does this project's EKS cluster create no OIDC identity provider?","This project uses EKS Pod Identity for per-service IAM identity (Demo 24), not IRSA. Pod Identity associates a service account with a role directly via the EKS Pod Identity API - no OIDC federation involved at all, so no provider is needed.","demo22d,eks,pod-identity,ta004-obj4a"
"What single Terraform argument enables Auto Mode's built-in ALB support?","kubernetes_network_config.elastic_load_balancing.enabled = true - replaces the need for a separately-installed AWS Load Balancer Controller.","demo22d,eks,alb,ta004-obj4a"
"What Kubernetes API object binds an existing ACM certificate to an Auto Mode Ingress?","IngressClassParams (apiGroup eks.amazonaws.com) - its certificateARNs field lists the cert ARN(s) to bind, referenced by a matching IngressClass.","demo22d,eks,alb,ingress"
"Does this series manage Kubernetes Deployments/Services/Ingresses via Terraform?","No - deliberately. Terraform builds the EKS cluster; kubectl applies the in-cluster Kubernetes manifests. A scope boundary, not a gap.","demo22d,scope,kubectl"
"Roughly how long does real EKS cluster creation take?","10-15 minutes - a genuine, real AWS characteristic, not a hung terminal or a bug.","demo22d,eks,timing"
"What does access_config.authentication_mode = \"API\" replace?","The legacy aws-auth ConfigMap approach to granting IAM identities access to an EKS cluster - the modern access-entry-based pattern.","demo22d,eks,access-entries"
"Are compute_config's node_pools and node_role_arn independently optional?","No, confirmed via a real AWS API error - setting node_role_arn without node_pools (or vice versa) is rejected with InvalidParameterException. The two are conditionally required together.","demo22d,eks,auto-mode,gotcha"
"What extra trust-policy action does the EKS cluster's own IAM role need for Auto Mode, beyond sts:AssumeRole?","sts:TagSession - confirmed required by AWS's own docs, needed for tag propagation from Kubernetes to AWS Load Balancer resources Auto Mode creates. The node role does NOT need this - only the cluster role.","demo22d,eks,iam,gotcha"
"What VPC subnet tags does EKS Auto Mode require to discover which subnets an ALB belongs in?","kubernetes.io/role/elb on public subnets (internet-facing load balancers), kubernetes.io/role/internal-elb on private subnets (internal load balancers). Without these, Auto Mode has no signal for correct subnet placement.","demo22d,eks,alb,vpc,gotcha"
"Where does AWS's own official example set an Auto Mode ALB's internet-facing/internal scheme?","On IngressClassParams.spec.scheme, not via the alb.ingress.kubernetes.io/scheme Ingress annotation. The annotation's behavior under Auto Mode isn't confirmed in AWS's own documentation either way.","demo22d,eks,alb,ingress,gotcha"
"Why does this demo's Cleanup use terraform destroy -target instead of a plain destroy?","This directory's state spans two different teardown lifecycles at once: Part A's recreated resources (22b/22c's) must persist, while Part B/C's resources (VPC, security group, cluster) must be torn down every session. -target scopes the destroy to only the latter.","demo22d,teardown,gotcha"
"Why does ecr.tf set create_lifecycle_policy = false on the ECR module?","A real, reproduced bug: the module defaults create_lifecycle_policy = true paired with repository_lifecycle_policy defaulting to an empty string, and AWS rejects an empty lifecycle policy outright at apply time. Neither validate nor plan catches this - only a real apply does. Corrected fix: supply a real policy matching Demo 19's own, rather than disabling the feature - this is both the fix and what keeps this demo's 'same technique as Demo 19' claim true.","demo22d,ecr,gotcha"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the individual facts (what
> Auto Mode manages, why no OIDC provider, the ALB single-flag,
> cluster-creation timing, the trust-policy and subnet-tag
> prerequisites, the shared-state recreation requirement). This Quiz
> instead works through Break-Fix diagnosis and the verification items
> in applied, scenario form, so the two together cover recall and
> applied judgment without restating the same question twice.

**22d-eks-single-service-quiz.md:**

````markdown
# Quiz — Demo 22d: EKS: Single Service (UI Only)

> Question types: True/False, Multiple Choice, Multiple Answer —
> matching the real TA-004 exam format.
> Target: 80% or above before moving to Demo 23.

---

**Q1. (Multiple Choice)** A learner starts this demo's directory fresh,
recreates 22b's files, but forgets `ecr.tf`/`acm.tf` from 22c. What
does Step 4's `terraform plan` most likely show?

- A) No changes — 22c's resources aren't relevant to this demo's own scope
- B) A proposal to destroy the 5 ECR repos and the ACM certificate, since state tracks them but this directory's local files no longer declare them
- C) An error, since Terraform detects the recreation is incomplete
- D) The missing resources are silently ignored and left alone

<details>
<summary>Answer</summary>

**B.** This is the same risk 22c's own Part A was built to prevent —
extended here to cover one more demo's files. A directory that can
reach real state but doesn't fully declare it proposes destroying
whatever's missing.

</details>

---

**Q2. (Multiple Choice)** A colleague sets `compute_config { enabled =
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

**Q3. (Multiple Choice)** This demo's `eks_sg` module call originally
targeted a different version and input shape of
`terraform-aws-modules/security-group/aws` than Demo 17's `tier_sg`
call, for the identical module. What was the correct way to handle
that, on discovering it?

- A) Trust whichever demo you read most recently
- B) Check the module's real, current documentation — both versions may simply be correct for the major version each one pins
- C) Average the two version numbers
- D) Assume both are correct simultaneously, since Terraform would catch a real error

<details>
<summary>Answer</summary>

**B.** This is exactly what resolved this demo's own VERIFY 2 — the
`~> 5.0` and `~> 6.0` shapes were each genuinely correct for their own
version; checking the real documentation settled it, rather than
guessing or defaulting to recency. Having confirmed that, this demo
was then upgraded to `~> 6.0` for consistency with Demo 17 — the
verification and the upgrade were two separate steps, not the same one.

</details>

---

**Q4. (Multiple Choice)** `kubectl describe ingress broken-ui` shows no
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

**Q5. (Multiple Choice)** This demo's `aws_iam_role.eks_cluster`
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

**Q6. (Multiple Choice)** `terraform apply` on `aws_eks_cluster.main`
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

**Q7. (Multiple Choice)** A cluster's `aws_eks_cluster` applies
successfully, `elastic_load_balancing.enabled = true` is set, and the
Ingress has a valid certificate ARN — but the ALB's `ADDRESS` never
populates. Which TWO real, confirmed prerequisites should you check
first, per this demo's own findings?

- A) Whether the VPC's public/private subnets are tagged `kubernetes.io/role/elb`/`internal-elb`
- B) Whether the Terraform state file has been manually edited
- C) Whether the cluster role's trust policy includes `sts:TagSession`
- D) Whether the AWS provider version is pinned to exactly `~> 6.47.0`

<details>
<summary>Answer</summary>

**A and C.** Both are real, AWS-documentation-confirmed prerequisites
for Auto Mode's ALB that aren't visible from the `aws_eks_cluster`
resource succeeding on its own — a missing subnet tag or a trust
policy missing `sts:TagSession` are the most likely real-world causes
of an ALB that never provisions correctly, not state corruption or an
unrelated provider version pin.

</details>

---

**Q8. (Multiple Choice)** At Cleanup, why does this demo's `terraform
destroy` command include `-target` flags instead of running plainly?

- A) `-target` is required syntax for any EKS-related resource
- B) A plain `destroy` would tear down everything this directory's state tracks, including 22b's and 22c's resources, which must survive
- C) `-target` runs faster than a plain destroy
- D) Terraform requires `-target` whenever more than one module is present

<details>
<summary>Answer</summary>

**B.** This directory's state spans resources with two different
teardown lifecycles — Part A's recreated resources must persist, Part
B/C's must not. `-target` is the actual mechanism for destroying only
the latter without touching the former.

</details>

---

**Q9. (Multiple Choice)** Part A's `apply` (Step 4) fails on all five
ECR repositories with `InvalidParameterException: ... 'Member must
have length greater than or equal to 100'`. What's the actual cause?

- A) The repository names are too short
- B) The ECR module's `create_lifecycle_policy` defaults to `true`, and its `repository_lifecycle_policy` defaults to an empty string, which AWS rejects
- C) `for_each` requires a minimum of 100 items to iterate over
- D) The IAM permissions for ECR are insufficient

<details>
<summary>Answer</summary>

**B.** This is a real, reproduced module-default bug — the module
tries to create a lifecycle policy by default, and its default policy
text is empty, which AWS's API rejects outright. The corrected fix is
supplying a real `repository_lifecycle_policy` — the same one Demo 19
already established for this identical module — not disabling the
feature via `create_lifecycle_policy = false`, which would work but
break this demo's own "same technique as Demo 19" claim.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8-9/9 | Import Anki cards, move to Demo 23 |
| 7/9 | Review the wrong answers, then proceed |
| 5-6/9 | Re-read the relevant sections, retry those questions |
| Below 5/9 | Re-read the full demo before proceeding |
````