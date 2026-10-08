# Quiz — Demo 22c: ECR/ACM Re-Creation

> Question types: True/False, Multiple Choice, Multiple Answer —
> matching the real TA-004 exam format.
> Target: 80% or above before moving to Demo 22d.

---

**Q1. (Multiple Choice)** A learner starts this demo in a brand-new,
empty directory, adds only `ecr.tf` and `acm.tf`, and skips recreating
any of 22b's files. What happens on `terraform init`?

- A) It succeeds, since ECR/ACM don't depend on 22b's resources
- B) It fails — there's no `backend.tf`, so Terraform has nowhere to even look for the existing, shared state
- C) It succeeds and silently creates a second, separate state file
- D) It succeeds, and the next `plan` proposes destroying 22b's resources

<details>
<summary>Answer</summary>

**B.** Skipping the recreation entirely fails safely — without
`backend.tf`, `init` can't locate the real state at all, so nothing
gets touched. The genuinely dangerous case is a *partial* recreation
(see Q2), not a total skip.

</details>

---

**Q2. (Multiple Choice)** A learner recreates `backend.tf` and
`provider.tf` from 22b, but not `cost_governance.tf` or `budgets.tf`,
then runs `terraform plan` in that directory. What does `plan` most
likely report?

- A) No changes — those files aren't relevant to this demo's own scope
- B) A proposal to destroy the SNS topic, EventBridge rule, topic policy, subscription, and Budget — since state tracks them but this directory's local files no longer declare them
- C) An error, since Terraform detects the recreation is incomplete
- D) The missing resources are automatically re-added to the plan as "no-op"

<details>
<summary>Answer</summary>

**B.** This is the real risk this demo's Part A exists to prevent — a
directory that *can* reach real, existing state (via a working
backend) but whose local configuration no longer fully describes it
proposes destroying whatever's missing, not leaving it alone.

</details>

---

**Q3. (Multiple Choice)** A reviewer notices `ecr.tf` here pins
`terraform-aws-modules/ecr/aws` at a different major version than Demo
19 used for the identical module, with no explanation given anywhere
in the demo. What's the correct response?

- A) Assume the newer demo's version is automatically the more current, correct one
- B) Treat the mismatch as worth questioning — check whether there's a stated reason, and if not, match the original demo's constraint
- C) Ignore it — version constraints between demos calling the same module never need to match
- D) Assume the older demo's pin is now outdated and should be bumped to match this one instead

<details>
<summary>Answer</summary>

**B.** An unexplained version drift between two demos calling the same
module is a signal to check, not something to resolve by guessing
which direction is "right." This demo's own content makes exactly
this mistake worth catching, which is why its version table calls the
comparison out explicitly.

</details>

---

**Q4. (Multiple Choice)** Why does this demo's Part A end with a
`terraform plan` check, before Part B adds `ecr.tf`?

- A) It's a redundant formality — `init` succeeding is already sufficient proof the recreation worked
- B) It's the actual proof the recreation was both correct and complete — `plan` reporting "No changes" confirms this directory's files now fully match the real, already-applied state
- C) `plan` is required before every `terraform` command, regardless of context
- D) It pre-downloads the AWS provider for Part B's use

<details>
<summary>Answer</summary>

**B.** `init` succeeding only proves the backend is reachable — it
says nothing about whether the local `.tf` files fully and accurately
describe what's already applied. Only a clean `plan` (no changes)
proves that.

</details>

---

**Q5. (Multiple Choice)** Unlike most other demos in this series, this
demo's Part B/C add no new content to `variables.tf` or `outputs.tf`
beyond what Part A recreated from 22b. Why?

- A) This demo forgot to add them — an oversight
- B) Every value `ecr.tf`/`acm.tf` need is either a literal string or read directly via `data`/`each.key` — there's nothing genuinely variable to parameterize for these two new files
- C) Terraform no longer requires separate variable files as of a recent version
- D) The ECR and ACM modules manage their own variables internally, making root-level variables redundant

<details>
<summary>Answer</summary>

**B.** This demo's own Directory Structure section states this
directly — `ecr.tf`/`acm.tf` simply don't need anything beyond what
Part A already recreated.

</details>

---

**Q6. (Multiple Choice)** Break-Fix references
`data.aws_route53_zone.primary.zone_id`, but the data source in this
config is actually named `main`. What error results?

- A) `Missing required argument`
- B) `Reference to undeclared resource`
- C) The lookup silently returns an empty string
- D) `terraform init` fails before `validate` even runs

<details>
<summary>Answer</summary>

**B.** This is a plain local-name mismatch, the same error class as
22a's own Break-Fix — `primary` was never declared, only `main` was.

</details>

---

**Q7. (Multiple Choice)** `data "aws_route53_zone"` includes
`private_zone = false` even though this project only has one zone
named `rselvantech.com`. What is this argument actually for?

- A) It's required syntax with no functional purpose when only one zone exists
- B) It disambiguates between a public and a private zone that might share the same name — needed only when both could exist, but safe to set explicitly regardless
- C) It controls whether the zone itself is publicly resolvable on the internet
- D) It determines whether the zone was created via Terraform or manually

<details>
<summary>Answer</summary>

**B.** `private_zone` exists to distinguish a public zone from a
private one sharing the same name — this project only ever has one
zone by this name, but setting the argument explicitly remains good
practice regardless.

</details>

---

**Q8. (Multiple Choice)** This demo's Cleanup step runs
`terraform state list` instead of `terraform destroy`. What would
actually happen if you ran `terraform destroy` here anyway?

- A) Nothing destructive — these resources are protected by AWS from deletion
- B) It would tear down the 5 ECR repos, the new ACM certificate, AND 22b's governance resources, since they're all tracked in the same shared state this directory now points at
- C) It would only destroy the ECR repos; the ACM certificate is immune to `terraform destroy`
- D) Terraform would refuse to run `destroy` against resources created by a registry module

<details>
<summary>Answer</summary>

**B.** Because this directory's state is shared with 22b (and, going
forward, 22d), a `destroy` here doesn't stop at this demo's own
objects — it would take down everything tracked in that state,
including 22b's SNS topic, EventBridge rule, and Budget.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 7-8/8 | Import Anki cards, move to Demo 22d |
| 6/8 | Review the wrong answers, then proceed |
| 4-5/8 | Re-read the relevant sections, retry those questions |
| Below 4/8 | Re-read the full demo before proceeding |
