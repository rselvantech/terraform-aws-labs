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

**Q10. (Multiple Choice)** A new Auto Mode cluster has just finished
creating. `kubectl get nodes` prints `No resources found`, and `aws
eks list-nodegroups` returns an empty list. What is the most accurate
conclusion?

- A) The cluster is broken; recreate it
- B) Node group creation failed silently
- C) Nothing is wrong: Auto Mode has no node groups and launches nodes only when a pod needs capacity
- D) The IAM node role is missing a policy

<details>
<summary>Answer</summary>

**C.** Auto Mode provisions nodes on demand. A throwaway pod is the
way to watch one appear.

</details>

---

**Q11. (Multiple Choice)** `aws_eks_cluster` and `aws_eks_access_entry`
are created successfully, but `aws_eks_access_policy_association`
fails with `ResourceNotFoundException`. A second `apply` succeeds
without changes. What is the best fix?

- A) Add `-parallelism=1` to every `apply`
- B) Make the association reference an attribute of the access entry, so Terraform orders them
- C) Increase the provider timeout
- D) Delete the access entry and recreate it manually

<details>
<summary>Answer</summary>

**B.** The two resources shared only string arguments, so Terraform
had no dependency edge and ran them in parallel. A reference creates
the edge.

</details>

---

**Q12. (Multiple Choice)** `terraform destroy
-target=aws_eks_cluster.main -target=module.vpc -target=module.eks_sg`
prints `No changes. No objects need to be destroyed`, then `Destroy
complete! Resources: 0 destroyed`. The cluster still exists. What is
the most likely cause?

- A) The cluster is protected by AWS from deletion
- B) The command was run from a directory that contains no Terraform configuration
- C) `-target` cannot address a module
- D) The targets must be listed in dependency order

<details>
<summary>Answer</summary>

**B.** With no configuration or state in the working directory, there
is nothing to target. Run the command from the directory that holds
`backend.tf`.

</details>

---

**Q13. (Multiple Answer — Pick the 2 correct responses)** A target
group reports `unhealthy` with `Target.ResponseCodeMismatch` and
`Health checks failed with these codes: [303]`. Which TWO checks are
the most useful next?

- A) `aws elbv2 describe-target-groups` and read `Matcher.HttpCode`
- B) Recreate the VPC
- C) Confirm the annotation name against the controller's documentation (`success-codes`)
- D) Add more replicas
- E) Change the certificate ARN

<details>
<summary>Answer</summary>

**A and C.** The reason names a response code the app legitimately
returns, so the matcher, or the annotation meant to change it, is the
suspect. The matcher shows what the target group actually uses, and
the documentation shows whether the annotation was spelled correctly.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 12-13/13 | Import Anki cards, move to Demo 23 |
| 10-11/13 | Review the wrong answers, then proceed |
| 7-9/13 | Re-read the relevant sections, retry those questions |
| Below 7/13 | Re-read the full demo before proceeding |
