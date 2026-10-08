# Demo 24 — IAM Least Privilege (via EKS Pod Identity)

---

## Overview

Every service in this cluster has been running under no explicit
per-service AWS identity at all so far — 22d and 23 focused on getting
the app itself deployed and reachable. This demo closes that gap,
fulfilling a promise this series made all the way back in Demo 10:
real least-privilege IAM, scoped per service, once real compute
identities exist to scope it against.

**Real-world scenario — CloudNova:**
With all five services running, "give every pod the same broad
permissions" is no longer an acceptable shortcut — a compromised
Catalog pod shouldn't be able to touch resources only Checkout needs,
and vice versa. This demo gives each service its own IAM role,
associated directly with its own Kubernetes service account, scoped to
exactly what that service needs today — not what it might need once
RDS and DynamoDB exist three demos from now.

**What this demo builds:**
```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — One IAM role per service (5 roles)                          │
│  Trust policy: pods.eks.amazonaws.com, not an OIDC provider           │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Scoped permission policies                                   │
│  CloudWatch Logs/Metrics (all 5) + SNS/SQS publish (Checkout only)     │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Pod Identity associations, binding role to service account  │
│  via the EKS Pod Identity API — no OIDC trust policy anywhere         │
├─────────────────────────────────────────────────────────────────────────┤
│  PART D — Verify: each pod can assume only its own role                │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- The EKS Pod Identity API (`aws eks create-pod-identity-association`)
  — how it differs mechanically from IRSA's OIDC trust policy approach
- Why this demo scopes only ECR/CloudWatch/SNS-SQS today, deliberately
  leaving RDS/DynamoDB permissions ungranted until Demo 26/27
- Kubernetes service accounts — the identity a Pod Identity association
  actually attaches to, distinct from the Pod itself
- Verifying identity boundaries from inside a running pod, not just
  reading policy JSON and assuming it's correct
- Restricting each role's trust policy to its own namespace and
  service account, not just relying on the association alone

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** five IAM roles (one per service),
each with a trust policy allowing the EKS Pod Identity service to
assume it, five Kubernetes service accounts (one per service,
replacing the implicit `default` service account every Pod has used so
far), and five Pod Identity associations tying each role to its
matching service account. Nothing here touches RDS or DynamoDB — those
permissions arrive at Demo 26/27, alongside those resources
themselves.

**Why this demo creates no OIDC identity provider, restated from 22d:**
Pod Identity's trust relationship is with the EKS Pod Identity service
itself, not with a cluster-specific OIDC issuer. This is why these
associations sit in the "created once, left standing" bucket rather
than needing to be re-applied every session alongside the cluster —
unlike an OIDC-anchored trust policy, nothing about a Pod Identity
association depends on the specific cluster instance that happens to
be running this session.

**Why permission scope stops at what exists today:** granting RDS or
DynamoDB access now, before either resource exists, would mean writing
a policy statement referencing a resource this project can't even name
an ARN for yet. This project's own established pattern (Demo 07's
`terraform_remote_state`, ADR-015 broadly) grants access to what's
real, when it's real — Demo 26 and Demo 27 each own their own
permission grant, alongside the connection-string change that actually
uses it.

---

## Prerequisites

### Knowledge
- 23 completed — all five services running, this demo's per-service
  identities attach to those already-running Deployments
- Demo 05/06 completed — basic IAM role/trust-policy syntax, reused
  here with a different trust principal
- Demo 10's own text (referenced, not required reading) originally
  deferred real least-privilege work to this point in the series —
  this demo is that deferred promise, fulfilled

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| Terraform CLI | Same as 22d/23 | `terraform version` |
| AWS CLI | Same as 22d/23 | `aws --version` |
| `kubectl` | Same as 22d/23 | `kubectl version --client` |

No new tools beyond what 22d/23 already required — only a new AWS API
surface (`aws eks create-pod-identity-association`, exposed through
Terraform's `aws_eks_pod_identity_association` resource).

### Verify the Pod Identity Agent Is Running

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent
```

```
⚠️ Simulated expected output

NAME                                  READY   STATUS    RESTARTS   AGE
eks-pod-identity-agent-abc123         1/1     Running   0          2d
```

> **Bolded takeaway:** you didn't install this — it's part of Auto
> Mode's pre-installed, managed add-on set, exactly as ADR-021
> confirmed when choosing Pod Identity over IRSA.

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Write an IAM role whose trust policy allows the EKS Pod Identity
   service (not an OIDC provider) to assume it, restricted to its own
   namespace and service account
2. ✅ Create a Kubernetes service account per service, replacing the
   implicit `default` service account
3. ✅ Create a Pod Identity association binding a role to a service
   account via the EKS Pod Identity API
4. ✅ Explain why RDS/DynamoDB permissions are deliberately absent from
   this demo's policies
5. ✅ Verify from inside a running pod that it can assume only its own
   role, not another service's

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| IAM roles/policies (5) | Always free | **$0.00** | IAM itself has no per-resource charge |
| Pod Identity associations (5) | Always free | **$0.00** | No additional AWS charge for the association itself |
| **Session total** | | **$0.00** | Created once, left standing — see Cleanup |

---

## Directory Structure

```
24-iam-least-privilege-pod-identity/
├── README.md
├── 24-iam-least-privilege-pod-identity-anki.csv
├── 24-iam-least-privilege-pod-identity-quiz.md
├── src/
│   └── phase-3-onward/
│       ├── iam-pod-identity.tf     # 5 IAM roles + policies + Pod Identity associations
│       └── outputs.tf
└── k8s/
    └── service-accounts.yaml       # 5 Kubernetes ServiceAccount objects
```

---

## Recall Check — 23 (EKS: Full Service Mesh)

Answer from memory before reading anything new:

1. Why did Demo 23 create no new Ingress or ALB?
2. What made Catalog different from Cart, Orders, and Checkout in
   Demo 23's build?
3. How does one Pod reach another service's Pod inside the cluster,
   without any external routing involved?

<details>
<summary>Answers</summary>

1. `retail-store-sample-app`'s real architecture only exposes UI
   externally — confirmed against the app's own quickstart and AWS's
   own deployment guide for this exact app. The other four services
   were never meant to be publicly reachable.
2. Catalog is the only one of the five services that empirically fails
   without a database connection (real `docker run` testing, ADR-012)
   — it got a MariaDB sidecar container in its own Pod spec. The other
   three run cleanly against their own built-in defaults.
3. Kubernetes' automatic internal DNS —
   `<service>.<namespace>.svc.cluster.local` — resolvable from any Pod
   in the cluster with no additional configuration.

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| `aws_eks_pod_identity_association` | Terraform resource | Binds an IAM role to a specific Kubernetes service account, via the EKS Pod Identity API |
| Trust policy for `pods.eks.amazonaws.com` | IAM concept, new trust principal | Pod Identity's own service principal — not an OIDC federated identity |
| Kubernetes `ServiceAccount` | Kubernetes API object | The identity a Pod Identity association actually attaches to — distinct from the Pod's own name |
| `serviceAccountName` (Pod spec field) | Kubernetes Pod spec field | Tells a Deployment's Pods which ServiceAccount to run as, replacing the implicit `default` |

---

### Detailed Explanation of New Constructs

#### Pod Identity's Trust Policy — What's Different From IRSA

```hcl
resource "aws_iam_role" "catalog" {
  name = "cloudnova-catalog-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEksAuthToAssumeRoleForPodIdentity"
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:RequestTag/kubernetes-namespace"       = "default"
          "aws:RequestTag/kubernetes-service-account" = "catalog-sa"
        }
      }
    }]
  })
}
```

The `Principal` here is the EKS Pod Identity **service itself**
(`pods.eks.amazonaws.com`) — a fixed, AWS-managed principal, not
something scoped to this specific cluster. Compare this to an IRSA
trust policy, which would reference a specific OIDC provider ARN tied
to one particular cluster's issuer URL. This is the concrete mechanism
behind everything ADR-021 already told you: no cluster-specific
dependency means these roles can be created once and never need
re-anchoring to a new cluster instance every session.

**`sts:TagSession` and the `Condition` block, confirmed against AWS's
own official documentation:** EKS Pod Identity uses `TagSession` to
attach session tags — including `kubernetes-namespace` and
`kubernetes-service-account` — to the temporary credentials it issues.
The `Condition` block above checks those exact tags, which means this
role can genuinely only be assumed by a Pod Identity association whose
namespace and service account match. Without it, a stray association
created elsewhere (a different namespace, a different service account,
even a mistake in an unrelated config) pointing at this same role ARN
would also succeed — the same "confused deputy" risk this
documentation specifically calls out. The association itself
(Part C) controls *which* service account gets *this* role's
credentials in the common case; the `Condition` block is what stops a
second, unintended path to the same role from working at all.

---

#### Kubernetes `ServiceAccount` — The Actual Identity Being Associated

Every Pod runs as some service account, even if you never specify
one — Kubernetes silently uses `default` for anything that doesn't
name one explicitly. Every Deployment in 22d/23 has been running under
that implicit `default` account. This demo makes that identity
explicit, one dedicated `ServiceAccount` per service:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: catalog-sa
```

A Pod Identity association is a binding between **this specific
Kubernetes object** and an IAM role — not between the Pod itself and
the role directly. This is why the Deployment's own Pod spec needs
updating too (`serviceAccountName: catalog-sa`), not just a new AWS
resource — the association only takes effect for Pods actually running
under the named service account.

---

## Lab Step-by-Step Guide

---

## Part A — IAM Roles, One Per Service

Part A creates one IAM role per service, each trusting the EKS Pod
Identity service rather than an OIDC provider, and each restricted to
its own namespace and service account.

### Step 1 — Navigate to the project config

```bash
cd terraform-aws-mastery/phase-3-real-aws-infrastructure/24-iam-least-privilege-pod-identity/src/phase-3-onward
```

### Step 2 — Add iam-pod-identity.tf

This step writes one IAM role per service plus their permission
policies — the baseline CloudWatch access every service gets, and the
SNS publish access only Checkout needs.

Create a file **iam-pod-identity.tf** and add the below content:

This file contains the IAM roles and policies this demo builds — a
role per service, each trusted only by the EKS Pod Identity service
and restricted to its own namespace/service-account pair.

```hcl
locals {
  services = ["ui", "catalog", "cart", "orders", "checkout"]
}

resource "aws_iam_role" "service" {
  for_each = toset(local.services)
  name     = "cloudnova-${each.key}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEksAuthToAssumeRoleForPodIdentity"
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:RequestTag/kubernetes-namespace"       = "default"
          "aws:RequestTag/kubernetes-service-account" = "${each.key}-sa"
        }
      }
    }]
  })
}

# ── CloudWatch Logs/Metrics — every service, baseline ─────────────────────
resource "aws_iam_role_policy" "cloudwatch" {
  for_each = toset(local.services)
  name     = "cloudwatch-access"
  role     = aws_iam_role.service[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "cloudwatch:PutMetricData"
      ]
      Resource = "*"
    }]
  })
}

# ── SNS/SQS publish — Checkout only ────────────────────────────────────────
# Checkout is the service that will publish order-placed events (Demo 28) —
# no other service has a stated reason to need this yet
resource "aws_iam_role_policy" "sns_publish" {
  role = aws_iam_role.service["checkout"].id
  name = "sns-publish-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = "*"   # tightened to the real topic ARN once it's referenced at Demo 28
    }]
  })
}
```

> **No RDS or DynamoDB statement anywhere in this file.** That's the
> demo's whole point — neither resource exists yet, and pre-scoping
> access to something that doesn't exist would teach a worse habit
> than granting it when it's real (Demo 26/27's own job).

### Step 3 — Add outputs.tf

This step exposes each service's role ARN, so they can be referenced
or audited without reading Terraform state directly.

Create a file **outputs.tf** and add the below content:

This file reads the map of service name to role ARN built by the
`for_each`'d role resource.

**outputs.tf:**

```hcl
output "service_role_arns" {
  description = "Map of service name to its IAM role ARN"
  value       = { for k, v in aws_iam_role.service : k => v.arn }
}
```

---

## Part B — Kubernetes Service Accounts

Part B creates a dedicated Kubernetes ServiceAccount per service,
replacing the implicit `default` account every Deployment has used
until now.

### Step 4 — Add service-accounts.yaml

This step declares the five ServiceAccount objects each Pod Identity
association will bind to.

Create a file **k8s/service-accounts.yaml** and add the below content:

This file contains one plain ServiceAccount per service — no
annotations, no special configuration, since Pod Identity's binding
happens outside the Kubernetes object itself.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ui-sa
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: catalog-sa
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cart-sa
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: orders-sa
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: checkout-sa
```

### Step 5 — Apply, and update each Deployment to use its account

This step applies the ServiceAccounts, then updates each running
Deployment to actually use its own dedicated account instead of the
implicit `default`.

```bash
kubectl apply -f k8s/service-accounts.yaml
```

Add `serviceAccountName: catalog-sa` (and the matching name for each
other service) to each Deployment's `spec.template.spec`, then
re-apply:

```bash
kubectl patch deployment catalog -p '{"spec":{"template":{"spec":{"serviceAccountName":"catalog-sa"}}}}'
kubectl patch deployment cart -p '{"spec":{"template":{"spec":{"serviceAccountName":"cart-sa"}}}}'
kubectl patch deployment orders -p '{"spec":{"template":{"spec":{"serviceAccountName":"orders-sa"}}}}'
kubectl patch deployment checkout -p '{"spec":{"template":{"spec":{"serviceAccountName":"checkout-sa"}}}}'
kubectl patch deployment ui -p '{"spec":{"template":{"spec":{"serviceAccountName":"ui-sa"}}}}'
```

> **Bolded takeaway:** this patch triggers a rolling restart of every
> Deployment's pods, since changing `serviceAccountName` changes the
> Pod template. That's expected — not a side effect to worry about.

---

## Part C — Pod Identity Associations

Part C binds each IAM role to its matching ServiceAccount via the EKS
Pod Identity API — the actual mechanism that grants a running pod its
scoped identity.

### Step 6 — Add the associations to iam-pod-identity.tf

This step adds the Pod Identity associations themselves — the
resource that actually connects each ServiceAccount to its matching
IAM role.

**Append to iam-pod-identity.tf:**

```hcl
resource "aws_eks_pod_identity_association" "service" {
  for_each        = toset(local.services)
  cluster_name    = "cloudnova-eks"
  namespace       = "default"
  service_account = "${each.key}-sa"
  role_arn        = aws_iam_role.service[each.key].arn
}
```

### Step 7 — Apply

This step applies all five associations and confirms them in the
Console.

```bash
terraform plan
terraform apply
```

```
⚠️ Simulated expected output

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

```
Console → EKS → Clusters → cloudnova-eks → Access → Pod Identity associations
  → 5 associations, one per service, each pointing at its own role ✅
```

---

## Part D — Verify Identity Boundaries

Part D confirms from inside each running pod that it can assume only
its own role, not another service's.

### Step 8 — Confirm each pod's assumed identity

This step confirms, from inside Catalog's own running pod, exactly
which IAM role it has actually assumed.

```bash
kubectl exec deployment/catalog -c catalog -- sh -c \
  "curl -s http://169.254.170.23/v1/credentials | jq -r .RoleArn 2>/dev/null || \
   aws sts get-caller-identity"
```

```
⚠️ Simulated expected output

arn:aws:sts::<ACCOUNT_ID>:assumed-role/cloudnova-catalog-role/...
```

### Step 9 — Cross-check that a different service can't assume Catalog's role

This step repeats the same check from a different service's pod,
confirming it gets its own distinct identity, not Catalog's.

```bash
kubectl exec deployment/cart -c cart -- aws sts get-caller-identity
```

```
⚠️ Simulated expected output

arn:aws:sts::<ACCOUNT_ID>:assumed-role/cloudnova-cart-role/...
```

> **Bolded takeaway:** Cart's own identity call returns *its own* role
> ARN, never Catalog's — the Pod Identity association is scoped
> per-service-account, and Cart's pod simply has no path to assume a
> role it was never associated with. This is the concrete proof
> least-privilege scoping is actually working, not just configured on
> paper.

---

## Cleanup

**This demo's Cleanup step is verification, not destruction** — same
reasoning as 22a/22b/22c. IAM roles and Pod Identity associations sit
in the "created once, left standing" bucket (ADR-017/018, ADR-021),
unlike the compute they're attached to.

```bash
terraform state list
# aws_iam_role.service["ui"] (and 4 more)
# aws_iam_role_policy.cloudwatch["ui"] (and 4 more)
# aws_iam_role_policy.sns_publish
# aws_eks_pod_identity_association.service["ui"] (and 4 more)
```

```
Console → IAM → Roles → confirm all 5 cloudnova-*-role entries exist ✅
Console → EKS → cloudnova-eks → Pod Identity associations → confirm 5 ✅
```

> ⚠️ **Do not run `terraform destroy` on these resources at the end of
> the session** — even though the cluster itself gets torn down (22d's
> Cleanup), these IAM roles and associations persist independently and
> will simply be re-associated with the next session's freshly-created
> cluster (same cluster name, same association parameters).

---

## What You Learned

1. ✅ Pod Identity's trust policy references the fixed
   `pods.eks.amazonaws.com` service principal, not a cluster-specific
   OIDC provider — the concrete reason these associations don't need
   re-anchoring every session.
2. ✅ A Pod Identity association binds a role to a Kubernetes
   `ServiceAccount`, not to a Pod directly — the Deployment's own spec
   must reference that service account for the binding to take effect.
3. ✅ This demo deliberately grants no RDS or DynamoDB access — neither
   resource exists yet, and pre-scoping access to it would teach a
   worse habit than granting it when it becomes real.
4. ✅ Verifying least-privilege scoping means checking from inside a
   running pod what identity it actually assumes — not just reading
   policy JSON and assuming it's correctly wired.
5. ✅ IAM roles and Pod Identity associations survive cluster teardown
   and re-creation — they're independent AWS resources, not coupled to
   any one cluster instance.
6. ✅ `sts:TagSession` and a `Condition` block on session tags together
   close a real gap the association alone doesn't fully close —
   restricting each role to its own namespace and service account,
   not just relying on how the association is typically used.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| `aws_eks_pod_identity_association` | TA-004 Obj 4a — Resource configuration | Newer resource type; confirm current schema against provider docs before treating as fixed |
| Trust policy for `pods.eks.amazonaws.com` | TA-004 Obj 4f — IAM trust relationships | Contrast directly with an OIDC-federated trust policy from any IRSA-based example you may have seen elsewhere |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Does a Pod Identity association bind directly to a Pod?" | No — it binds to a Kubernetes ServiceAccount, which Pods then reference via `serviceAccountName` | Assuming the binding is Pod-specific rather than ServiceAccount-specific |
| "Should Demo 24 pre-scope RDS/DynamoDB permissions since they're coming soon?" | No — incremental scoping (ADR-015) grants access only to what's real, when it's real | Assuming "coming soon" justifies pre-scoping ahead of the resource actually existing |
| "Does the Pod Identity association alone fully restrict which pods can assume a role?" | Not entirely — a `Condition` block on session tags in the trust policy is what prevents a stray association elsewhere from also succeeding | Assuming the association is the only access-control layer that matters |

### Exam Task — Write a complete configuration

**Task:** Write an IAM role with a Pod Identity trust policy, and a
matching `aws_eks_pod_identity_association`.

**Official documentation:**
- [`aws_eks_pod_identity_association` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association)

**What to practise:**
1. Open the page above — check the required arguments
2. Write the configuration from scratch without looking at this demo's `src/` files
3. Validate: `terraform init && terraform validate`

<details>
<summary>Reference solution (open only after attempting)</summary>

```hcl
resource "aws_iam_role" "exam_task" {
  name = "exam-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_eks_pod_identity_association" "exam_task" {
  cluster_name    = "exam-task-cluster"
  namespace       = "default"
  service_account = "exam-task-sa"
  role_arn        = aws_iam_role.exam_task.arn
}
```

**Arguments you must know without looking up:**
- The trust policy's `Principal` is `pods.eks.amazonaws.com`, not an
  OIDC provider ARN
- `service_account` refers to the Kubernetes object's name, not the
  Pod's own name
- `sts:TagSession` alongside `sts:AssumeRole` is required, confirmed
  against AWS's own documentation — Pod Identity uses it to attach
  session tags (including namespace and service account) that a
  `Condition` block can then check

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `aws sts get-caller-identity` inside a pod returns the node's role, not the expected service role | The Deployment's Pod spec doesn't reference the new `ServiceAccount` yet | Confirm `serviceAccountName` was actually patched and the pod restarted after the patch |
| Pod Identity association creation fails with a validation error | `namespace`/`service_account` don't match a real, already-existing Kubernetes object | Confirm `kubectl apply -f k8s/service-accounts.yaml` ran successfully before the Terraform apply |
| A service can unexpectedly assume another service's role | Two service accounts were accidentally associated with the same role, or a Deployment references the wrong `serviceAccountName` | Cross-check each Deployment's actual `serviceAccountName` against its intended per-service value; confirm each role's trust-policy `Condition` matches only its intended namespace/service account |

---

## Break-Fix Scenario

One deliberate error. Diagnose using `kubectl`/`aws` output — do not
look at the answer first.

```bash
kubectl exec deployment/broken-orders -- aws sts get-caller-identity
```

This excerpt shows a Deployment whose `serviceAccountName` doesn't
match any real ServiceAccount — diagnose the resulting identity
mismatch before revealing the answer.

**break-fix/broken-orders-deployment.yaml (relevant excerpt):**

```yaml
spec:
  template:
    spec:
      serviceAccountName: order-sa   # Error — should be orders-sa
```

<details>
<summary>Reveal answer — attempt diagnosis first</summary>

**Error — `serviceAccountName: order-sa`**
Missing the trailing "s" — doesn't match the real `orders-sa` service
account created in Part B. Kubernetes doesn't error loudly on an
unmatched `serviceAccountName` if the account genuinely doesn't
exist — behavior varies, but commonly the Pod either fails to schedule
or falls back to a default identity with no Pod Identity association
at all, meaning `aws sts get-caller-identity` inside it returns the
node's own role, not the intended service-scoped one. Fix: correct the
typo to `orders-sa`.

</details>

**Cleanup:**

```bash
kubectl delete -f break-fix/
```

---

## Interview Prep

**Q1. A teammate asks how Pod Identity's trust relationship differs from what they've seen in IRSA tutorials.**
IRSA's trust policy references a specific OIDC provider ARN, tied to one cluster's own issuer URL — the trust relationship is cluster-specific by design. Pod Identity's trust policy references a fixed, AWS-managed service principal (`pods.eks.amazonaws.com`) that has nothing to do with any particular cluster. The practical consequence: an IRSA role can't outlive the cluster its OIDC provider belongs to without being re-pointed at a new provider ARN, while a Pod Identity role has no such dependency at all — it can be reused across a cluster that gets torn down and recreated with the same name, which is exactly this project's own session-to-session pattern.

**Q2. Someone asks why this demo doesn't grant RDS or DynamoDB permissions now, since everyone knows they're coming in a few demos.**
Because "coming soon" isn't the same as "real" — writing a policy statement for a resource that doesn't exist yet means either referencing a placeholder ARN that isn't accurate, or granting overly broad access to compensate for not knowing the real ARN. This project's own established pattern grants access to what's real, when it's real: Demo 26 and Demo 27 each add their own IAM policy grant as part of their own swap-in step, alongside making the actual connection real. Pre-scoping ahead of time would teach a worse habit than incremental scoping — that's not how least-privilege is actually practiced day to day.

**Q3. A reviewer asks how you'd actually verify that Catalog's pod can't accidentally assume Cart's role, rather than just trusting the policy JSON looks correct.**
By checking from inside the running pod itself, not by reading configuration. Running `aws sts get-caller-identity` from inside Catalog's pod should return Catalog's own role ARN — and running the same command from Cart's pod should return Cart's role ARN, never Catalog's. If either pod ever returned a role it wasn't associated with, that would be a real, concrete failure worth investigating immediately, not something a policy review alone would necessarily catch. Configuration correctness and runtime behavior are related but distinct claims — this demo's Part D verification checks the second one directly.

**Q4. A reviewer asks whether the Pod Identity association alone is sufficient to guarantee only the intended service account can use a given role.**
Not entirely, which is why this demo's trust policy also includes a `Condition` block checking the session tags Pod Identity attaches via `sts:TagSession`. The association determines which service account *normally* gets which role's credentials, but the trust policy itself is what would stop a second, unintended association — created elsewhere, by mistake or otherwise — from also succeeding against the same role ARN. Relying on the association alone would mean the role's actual security boundary depends on nobody ever misconfiguring a different association anywhere in the account; the `Condition` block makes that boundary real at the IAM level itself, not just by convention.

---

## Key Takeaways

1. **Pod Identity's trust principal is fixed and cluster-independent —
   `pods.eks.amazonaws.com`, not an OIDC provider ARN.** This is the
   concrete mechanism behind why these roles don't need re-anchoring
   every session.

2. **A Pod Identity association binds to a Kubernetes ServiceAccount,
   not directly to a Pod.** The Deployment's own spec must reference
   that ServiceAccount for the binding to actually take effect.

3. **Incremental IAM scoping beats pre-scoping for resources that
   don't exist yet.** "It's coming soon" is not the same claim as
   "it's real" — grant access when the resource actually exists, not before.

4. **Verifying identity boundaries means checking from inside a
   running pod, not just reading policy JSON.** Configuration
   correctness and actual runtime behavior are different claims worth
   confirming separately.

5. **This demo closes a promise made back in Demo 10.** Deferred
   least-privilege work isn't a gap left open indefinitely — it's a
   staged introduction, delivered exactly when real compute identities
   exist to scope against.

6. **The association and the trust policy are two different layers of
   the same access-control story.** The association says who normally
   gets which role; a `Condition` on session tags is what stops an
   unintended second path to the same role from also working.

> **Demo scope:** Primary concept: scoping real, per-service IAM
> least-privilege via EKS Pod Identity, restricted to each service's
> own namespace and service account. Supporting concepts: contrasting
> Pod Identity's trust model with IRSA, incremental permission
> scoping, verifying identity boundaries from inside a running pod.
> Estimated completion time: 35–40 minutes.
> Checkpoints: 4 natural stopping points (end of Part A, end of
> Part B, end of Part C, end of Part D).

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `aws eks create-pod-identity-association` (via Terraform's `aws_eks_pod_identity_association`) | Binds an IAM role to a Kubernetes service account |
| `kubectl apply -f k8s/service-accounts.yaml` | Creates the Kubernetes ServiceAccount objects this demo's associations attach to |
| `kubectl patch deployment <name> -p '...'` | Updates a running Deployment's Pod spec, triggering a rolling restart |
| `kubectl exec deployment/<name> -- aws sts get-caller-identity` | Confirms the actual IAM identity a running pod has assumed |

---

## Next Demo

**Demo 25 — VPC Extension: Isolated Subnets + Endpoints:** extends the
persistent VPC with a third, isolated subnet tier and an S3 gateway
endpoint, ahead of RDS's arrival at Demo 26 — purely networking, no
IAM or compute changes.

---

## Appendix — Anki Cards

**24-iam-least-privilege-pod-identity-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::24-iam-least-privilege-pod-identity
#separator:Comma
#columns:Front,Back,Tags
"What is the trust policy Principal for an EKS Pod Identity role, and how does it differ from IRSA?","pods.eks.amazonaws.com - a fixed, AWS-managed service principal, not tied to any specific cluster. IRSA's trust policy instead references a specific OIDC provider ARN tied to one cluster's own issuer URL.","demo24,pod-identity,irsa,ta004-obj4f"
"Does a Pod Identity association bind directly to a Kubernetes Pod?","No - it binds to a Kubernetes ServiceAccount. A Pod only gets the associated identity if its Deployment's spec references that ServiceAccount via serviceAccountName.","demo24,pod-identity,service-account"
"Why does Demo 24 grant no RDS or DynamoDB permissions, even though they're coming at Demo 26/27?","Incremental scoping (ADR-015) - access is granted to what's real, when it's real. Pre-scoping for resources that don't exist yet would mean referencing inaccurate ARNs or granting overly broad access to compensate.","demo24,least-privilege,ta004-obj"
"How do you verify a pod's actual assumed IAM identity, rather than just reading its intended policy?","Run aws sts get-caller-identity from inside the running pod (kubectl exec). This confirms actual runtime behavior, which is a distinct claim from configuration correctness on paper.","demo24,verification,pod-identity"
"Why don't Pod Identity associations need to be re-applied every session, unlike the EKS cluster itself?","Their trust relationship has no cluster-specific dependency (fixed pods.eks.amazonaws.com principal) - unlike an IRSA design, whose OIDC-anchored trust policy can't outlive the specific cluster instance it was created for.","demo24,pod-identity,teardown-policy,adr-021"
"What does sts:TagSession do in a Pod Identity trust policy, and why does it matter?","EKS Pod Identity uses TagSession to attach session tags (including the pod's namespace and service account) to the temporary credentials it issues. A Condition block in the trust policy can then check these tags to restrict exactly which namespace/service account may assume the role.","demo24,pod-identity,tagsession,gotcha"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the individual facts (trust
> principal, ServiceAccount binding, incremental scoping, verification
> method, teardown independence, `TagSession`'s purpose). This Quiz
> instead works through this demo's own Break-Fix scenario and
> cross-service verification in applied form, so the two together
> cover recall and applied diagnosis without restating the same
> question twice.

**24-iam-least-privilege-pod-identity-quiz.md:**

````markdown
# Quiz — Demo 24: IAM Least Privilege (via EKS Pod Identity)

> Question types: True/False, Multiple Choice, Multiple Answer —
> matching the real TA-004 exam format.
> Target: 80% or above before moving to Demo 25.

---

**Q1. (Multiple Choice)** `kubectl exec deployment/broken-orders --
aws sts get-caller-identity` returns the cluster node's own role, not
`cloudnova-orders-role`. The Deployment's spec sets `serviceAccountName:
order-sa`. What's wrong?

- A) The Pod Identity association wasn't applied
- B) `order-sa` doesn't match the real `orders-sa` service account — a plain typo
- C) `sts:TagSession` is missing from the trust policy
- D) The cluster needs an OIDC identity provider added

<details>
<summary>Answer</summary>

**B.** This is a one-character typo (`order-sa` vs. `orders-sa`) — the
Pod simply isn't running under the service account the association
actually targets, so it falls back to a default identity with no
association at all.

</details>

---

**Q2. (Multiple Choice)** Cart's pod runs `aws sts
get-caller-identity` and correctly returns `cloudnova-cart-role`.
Catalog's pod runs the same command and returns `cloudnova-catalog-role`.
What does this actually prove?

- A) Nothing — this is expected regardless of whether the associations are configured correctly
- B) That least-privilege scoping is genuinely working — each pod can only assume its own associated role, not another's
- C) That both services share the same underlying IAM role
- D) That the EKS cluster has an OIDC identity provider configured

<details>
<summary>Answer</summary>

**B.** This is the actual, concrete proof this demo's Part D exists to
deliver — verifying real runtime identity boundaries, not just
trusting that the policy JSON looks correct.

</details>

---

**Q3. (Multiple Choice)** This demo's IAM roles include a `Condition`
block in their trust policy, checking
`aws:RequestTag/kubernetes-namespace` and
`aws:RequestTag/kubernetes-service-account`. What real problem does
this actually prevent?

- A) It prevents the role from ever being deleted accidentally
- B) It prevents a different Pod Identity association elsewhere (a different namespace/service account) from being able to assume this same role — a "confused deputy" style risk
- C) It's purely cosmetic — Pod Identity associations already fully enforce this on their own with no help from the trust policy
- D) It encrypts the credentials passed to the pod

<details>
<summary>Answer</summary>

**B.** This is confirmed directly against AWS's own EKS Pod Identity
documentation — the `Condition` block is the trust-policy-level
safeguard against a stray or mistaken association elsewhere also
succeeding against the same role.

</details>

---

**Q4. (Multiple Choice)** Why does this demo's trust policy include
`sts:TagSession` alongside `sts:AssumeRole`?

- A) `TagSession` is deprecated boilerplate kept only for backward compatibility
- B) EKS Pod Identity uses `TagSession` to attach session tags (like namespace and service account) to the assumed-role session — these tags are what a `Condition` block can then check
- C) `TagSession` grants the pod permission to tag other AWS resources
- D) It's required only when using `FORECASTED` notification type

<details>
<summary>Answer</summary>

**B.** Confirmed against AWS's own documentation — `TagSession` is
what makes the namespace/service-account `Condition` block possible at
all, not an unrelated or optional permission.

</details>

---

**Q5. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements correctly describe why this demo's IAM roles and Pod
Identity associations don't need to be re-applied every session, even
though the EKS cluster itself does?

- A) IAM roles are always exempt from every project's teardown policy, regardless of design
- B) Pod Identity's trust relationship references a fixed service principal, not a cluster-specific OIDC issuer
- C) The Pod Identity associations reference the cluster by name, and a re-created cluster with the same name and association parameters simply reconnects
- D) AWS automatically recreates IAM roles when a cluster with a matching name is created

<details>
<summary>Answer</summary>

**B and C.** The fixed principal removes any cluster-specific
dependency, and the associations themselves reference the cluster by
name/parameters rather than a specific cluster instance — nothing
about them requires re-creation when the cluster is torn down and
rebuilt. **A** overgeneralizes (this project's own IAM roles from
other demos aren't universally exempt for the same reason); **D** is
not how AWS actually works.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 5/5 | Import Anki cards, move to Demo 25 |
| 4/5 | Review the wrong answer, then proceed |
| 3/5 | Re-read the relevant sections, retry those questions |
| Below 3/5 | Re-read the full demo before proceeding |
````