# Quiz — Demo 22b: Cost Governance

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 22c.

---

**Q1. (Multiple Choice)** Why is this governance demo placed *before*
22d, which stands up the EKS cluster, rather than after it?

- A) Terraform requires all notification resources to exist before any compute resource
- B) None of this demo's controls depend on compute existing, and the controls are worth having in place before the first cost-accruing resource is ever applied
- C) EventBridge rules can only be created in an account with no running clusters
- D) It's an arbitrary ordering with no real reason

<details>
<summary>Answer</summary>

**B.** All three mechanisms are independent of compute, and the flat,
continuous control-plane fee 22d introduces is exactly what the safety
net exists to catch — so it belongs in place first.

</details>

---

**Q2. (Multiple Choice)** This demo's `aws_sns_topic_policy` includes a
`Condition` block matching `aws:SourceArn` to this specific
EventBridge rule's ARN. What would happen if that `Condition` block
were removed entirely, leaving just
`Principal = { Service = "events.amazonaws.com" }`?

- A) Nothing changes — the Condition block is optional boilerplate with no real effect
- B) Any EventBridge rule in the account, not just this one, would be allowed to publish to this SNS topic
- C) The policy would fail validation, since Condition blocks are required on all SNS topic policies
- D) EventBridge itself would stop being able to publish at all

<details>
<summary>Answer</summary>

**B.** Without the `Condition` block, the policy trusts *any*
EventBridge rule's publish attempt rather than this specific one. It
produces no error — it silently widens the policy, which is precisely
the class of finding Part C's static analysis exists to surface.

</details>

---

**Q3. (Multiple Choice)** A real `tflint --init` run against this
demo's `.tflint.hcl` fails with `"version" attribute cannot be omitted
when specifying "source"`. What does this confirm?

- A) `tflint` cannot use the AWS ruleset plugin at all
- B) Pinning a version is mandatory once `source` is set — it can't be left out as a matter of style
- C) The plugin only works with Terraform, not AWS
- D) `.tflint.hcl` must be written in JSON instead of HCL

<details>
<summary>Answer</summary>

**B.** This is a hard requirement of the plugin configuration, not a
best-practice suggestion — omitting `version` while `source` is
present fails outright before any linting happens.

</details>

---

**Q4. (Multiple Choice)** A real `checkov` run against this demo's
original (pre-fix) `aws_sns_topic` reports `CKV_AWS_26` as failed. What
does this demo do in response?

- A) Adds `CKV_AWS_26` to `.checkov.yaml`'s `skip-check` list
- B) Adds `kms_master_key_id = "alias/aws/sns"` to the topic, fixing the finding directly at no additional cost
- C) Ignores the finding, since checkov findings are only advisory
- D) Deletes the SNS topic and replaces it with a different resource type

<details>
<summary>Answer</summary>

**B.** The fix is free and simple, so it's applied directly rather than
skipped. A skip list is reserved for findings that are genuinely out
of scope or involve a real trade-off — not a default response to any
finding a scan surfaces.

</details>

---

**Q5. (Multiple Choice)** What is the cost difference between using
`kms_master_key_id = "alias/aws/sns"` and creating a dedicated
`aws_kms_key` (customer managed key) for the same purpose?

- A) There is no difference — both cost $1/month
- B) The AWS managed key's storage is free; a customer managed key costs $1/month flat regardless of use
- C) The AWS managed key costs more, since it's shared infrastructure
- D) Customer managed keys are free; only AWS managed keys are billed

<details>
<summary>Answer</summary>

**B.** AWS managed key storage carries no monthly fee — only API calls
against it are billed, with a free-tier allowance. A customer managed
key's $1/month applies whether or not it's ever used.

</details>

---

**Q6. (Multiple Choice)** Break-Fix's `notification_type = "Actual"`
(wrong casing) passes both `terraform validate` and `terraform plan`.
Why?

- A) `"Actual"` is actually a valid alternate spelling AWS accepts
- B) Neither command evaluates provider-side value constraints — they check structure and schema, and the failure only surfaces when `apply` calls the real AWS API
- C) `validate` was run with the wrong flag
- D) This should have failed `validate`, and its passing indicates a bug in the demo

<details>
<summary>Answer</summary>

**B.** An incorrectly cased enum string is exactly the kind of thing
that only surfaces at `apply`. Internalising which failures are caught
where is more useful than memorising this one value.

</details>

---

**Q7. (Multiple Choice)** Your `terraform apply` succeeded and the SNS
topic exists, but no notification email ever arrives. `terraform plan`
reports no changes. What is the most likely cause?

- A) The EventBridge rule is disabled
- B) The email subscription is still `PendingConfirmation` — confirmation happens in AWS, outside Terraform's view, so `plan` sees nothing wrong
- C) Terraform failed to create the subscription resource
- D) The SNS topic policy is missing

<details>
<summary>Answer</summary>

**B.** The subscription resource exists as far as Terraform is
concerned; what's missing is the recipient clicking the confirmation
link. This is a good illustration of "in state and correct" not being
the same as "working."

</details>

---

**Q8. (True/False)** Because this demo shares `platform/terraform.tfstate`
with 22c and Demo 24 once those are built, running `terraform destroy`
in `src/platform/` at the end of a session would reach only this
demo's own six resources, never anything from those later demos.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** A `destroy` operates on everything tracked in that
state — once 22c and Demo 24 add their own files into `src/platform/`,
their resources are tracked in the same state this demo uses, and a
destroy here would reach them too. It would still never reach the VPC
or EKS cluster, since those live in the structurally separate
`workloads/` state — but within `platform/` itself, the tier is
shared by design.

</details>

---

**Q9. (Multiple Choice)** A `terraform.tfvars` file contains a value
for `monthly_budget_limit` before Part B Step 1 has declared that
variable. What actually happens on the next `terraform plan`?

- A) `terraform plan` fails immediately with a hard error
- B) Terraform issues a "Value for undeclared variable" warning but continues normally
- C) The value is silently discarded with no message at all
- D) Terraform automatically creates the missing variable block

<details>
<summary>Answer</summary>

**B.** It's a warning, not an error — the plan still runs. It's worth
fixing anyway, since it's a real signal that the configuration and its
tfvars file are out of sync.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 9/9 | Import Anki cards, move to Demo 22c |
| 7-8/9 | Review the wrong answers, then proceed |
| 5-6/9 | Re-read the relevant sections, retry those questions |
| Below 5/9 | Re-read the full demo and redo the walkthrough before proceeding |
