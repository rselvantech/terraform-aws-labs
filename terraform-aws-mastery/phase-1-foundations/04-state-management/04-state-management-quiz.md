# Quiz — Demo 04: State Management and Backends: Import, Surgery, and Recovery

> One correct answer per question unless stated otherwise.
> Target: 80% or above before moving to Demo 05.
> TA-004 exam style.

---

**Q1.** What does `terraform import aws_s3_bucket.uploads my-bucket` actually do?

A. Creates a new S3 bucket named `my-bucket` and tracks it in state
B. Adds the existing bucket `my-bucket` to Terraform's state, mapped
   to the address `aws_s3_bucket.uploads` — creates nothing in AWS
C. Generates a `.tf` resource block matching the bucket's current configuration
D. Copies the bucket's configuration into a new Terraform workspace

<details>
<summary>Answer</summary>

**B.** `import` only adds the resource to state — it creates nothing in
AWS and does not generate `.tf` code (A and C are both wrong for
different reasons). It also has nothing to do with workspaces (D).

</details>

---

**Q2.** After a successful `terraform import`, `terraform plan` shows a
`tags_all` pending change. What does this indicate, and what should you do?

A. The import failed silently — re-run import
B. The `.tf` block is incomplete — add more arguments until plan is clean
C. This is expected when `default_tags` are configured — run `terraform apply` to close the gap, then confirm plan shows zero changes
D. State is corrupted — restore from S3 versioning

<details>
<summary>Answer</summary>

**C.** A `tags_all` change after import is expected behavior when
`default_tags` are configured in the provider block. The import reads
the resource's current state (no tags), but `default_tags` specifies
that all resources should have the common tags. Running `apply` closes
this gap. Only after that apply does `plan` show zero changes and the
import is truly complete.

</details>

---

**Q3.** What is the main practical advantage of an `import {}` block over
the CLI `terraform import` command?

A. It's faster to type
B. It can import resources of any type, while the CLI form is limited
   to a subset of resource types
C. It is reviewable in `terraform plan` before anything happens, and
   lives in version control as a repeatable, auditable action
D. It doesn't require knowing the resource's import ID

<details>
<summary>Answer</summary>

**C.** The CLI form executes immediately with no preview. The `import {}`
block shows up as a planned action in `terraform plan` first, and being
in a `.tf` file means it's version-controlled and repeatable. Both forms
require the same import ID (D is wrong) and both work with any resource
type that supports import (B is wrong).

</details>

---

**Q4.** Does `terraform state rm aws_s3_bucket.uploads` delete the bucket
in AWS?

A. Yes, immediately
B. Yes, but only after the next `apply`
C. No — the resource is untouched in AWS; only Terraform's state record
   of it is removed
D. It depends on whether `force_destroy` is set to `true`

<details>
<summary>Answer</summary>

**C.** This is one of the most commonly misunderstood facts about
`state rm`. The resource keeps running in AWS exactly as it was —
Terraform simply forgets it exists. `force_destroy` (D) is unrelated; it
only affects whether `destroy` can delete a non-empty S3 bucket.

</details>

---

**Q5.** After `terraform state rm` on a resource whose `.tf` block still
exists, what does the next `terraform plan` propose, and what is the
correct recovery action?

A. No changes — Terraform detects the resource still exists in AWS and re-tracks it automatically
B. To create the resource — state no longer knows it exists. Correct recovery: run `terraform import`, not `terraform apply`
C. An error, refusing to plan until the resource is explicitly re-imported
D. To destroy the resource

<details>
<summary>Answer</summary>

**B.** Since state no longer tracks the resource but the `.tf` block
still declares it, Terraform interprets this as "this resource doesn't
exist yet and needs to be created." For S3 buckets this fails safely
(`BucketAlreadyExists`); for other resource types it risks creating a
genuine duplicate. The correct recovery is `terraform import` to re-track
the existing resource — not `terraform apply`.

</details>

---

**Q6.** You rename `aws_s3_bucket.legacy` to `aws_s3_bucket.uploads` in
`06-main.tf` but the `import {}` block from Part B is still in the file.
You then run `terraform plan`. What happens?

A. Plan shows no changes — Terraform resolves the rename automatically
B. Plan shows destroy + create for the bucket
C. Error: "Configuration for import target does not exist" — the `import {}` block still references `aws_s3_bucket.legacy`
D. Plan shows the import running again

<details>
<summary>Answer</summary>

**C.** The `import {}` block references `to = aws_s3_bucket.legacy`,
but you renamed the resource block to `aws_s3_bucket.uploads`. Terraform
cannot find the import target's configuration. Fix: remove the `import {}`
block first, then rename, then run `terraform state mv`.

</details>

---

**Q7.** What does `terraform state push terraform.tfstate` do to the
current remote state?

A. Merges the local file's contents with the current remote state
B. Overwrites the current remote state entirely with the local file's
   contents — does not merge
C. Compares the two and only updates fields that differ
D. Refuses to run unless the local file's `serial` is higher than the
   remote state's current `serial`

<details>
<summary>Answer</summary>

**B.** `state push` is a full overwrite, not a merge. Any remote state
changes recorded after the version being pushed are discarded from
Terraform's record. Real AWS resources are unaffected — only Terraform's
belief about them changes. Always follow with `plan -refresh-only` to
check whether the restored state matches reality.

</details>

---

**Q8.** A teammate sees an "Error acquiring the state lock" message and
immediately runs `terraform force-unlock <ID>` without checking anything
else. What is the risk?

A. None — `force-unlock` validates it's safe before removing the lock
B. If an apply genuinely is still running, removing the lock allows a
   second apply to start concurrently, risking state corruption
C. `force-unlock` will simply fail if the apply is still running —
   Terraform detects this automatically
D. The lock will automatically reappear if the running apply detects
   it was removed

<details>
<summary>Answer</summary>

**B.** `force-unlock` does not check whether an apply is actually still
in progress — it simply removes the lock file. If used while a real
apply is running, two applies can now write to state concurrently,
exactly the corruption scenario locking exists to prevent. Always
check the lock's `Who` field and confirm with that person or system
first.

</details>

---

Score guide:
| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 05 |
| 7/8 | Review the wrong answer, then proceed |
| 6/8 | Re-read the relevant section, retry those questions |
| Below 6/8 | Re-read the full demo and redo the walkthrough before proceeding |
