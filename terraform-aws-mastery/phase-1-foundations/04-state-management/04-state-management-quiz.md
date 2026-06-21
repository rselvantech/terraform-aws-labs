# Quiz — Demo 04: State Management and Backends: Import, Surgery, and Recovery

Test your understanding of this demo's concepts. Each question is a
scenario — choose the best answer, then check yourself against the
explanation.

---

**Q1.** What does `terraform import aws_s3_bucket.legacy
my-bucket-name` actually do?

A. Creates a new S3 bucket named `my-bucket-name` and tracks it in state
B. Adds the existing bucket `my-bucket-name` to Terraform's state, mapped
   to the address `aws_s3_bucket.legacy` — creates nothing in AWS
C. Generates a `.tf` resource block matching the bucket's configuration
D. Copies the bucket's configuration into a new Terraform workspace

<details>
<summary>Answer</summary>

**B.** `import` only adds the resource to state — it creates nothing in
AWS and does not generate `.tf` code (A and C are both wrong for
different reasons). It also has nothing to do with workspaces (D).

</details>

---

**Q2.** After a successful `terraform import`, `terraform plan` shows
several pending changes. What does this indicate?

A. The import failed silently
B. The `.tf` resource block doesn't yet fully match the real resource's
   configuration — more manual refinement is needed
C. The resource needs to be imported again
D. State is corrupted

<details>
<summary>Answer</summary>

**B.** A successful import only means the resource is tracked in state —
it says nothing about whether your `.tf` code matches reality. The
correct response is to keep editing the `.tf` block and re-running
`plan` until it shows zero changes.

</details>

---

**Q3.** What is the main practical advantage of an `import {}` block over
the CLI `terraform import` command?

A. It's faster to type
B. It can import resources of any type, while the CLI form is limited
C. It's reviewable in `terraform plan` before anything happens, and
   lives in version control
D. It doesn't require knowing the resource's import ID

<details>
<summary>Answer</summary>

**C.** The CLI form executes immediately with no preview. The `import {}`
block shows up as a planned action in `terraform plan` first, and being
in a `.tf` file means it's version-controlled and repeatable. Both forms
require the same import ID (D is wrong) and both work with any
resource type that supports import (B is wrong).

</details>

---

**Q4.** Does `terraform state rm aws_s3_bucket.legacy` delete the bucket
in AWS?

A. Yes, immediately
B. Yes, but only after the next `apply`
C. No — the resource is untouched in AWS; only Terraform's state record
   of it is removed
D. It depends on whether `force_destroy` is set

<details>
<summary>Answer</summary>

**C.** This is one of the most commonly misunderstood facts about
`state rm`. The resource keeps running in AWS exactly as it was —
Terraform simply forgets it exists. `force_destroy` (D) is unrelated; it
only affects whether `destroy` can delete a non-empty bucket.

</details>

---

**Q5.** After `terraform state rm` on a resource whose `.tf` block still
exists, what does the next `terraform plan` propose?

A. No changes — Terraform knows the resource still exists in AWS
B. To create the resource — state no longer knows it exists
C. An error, refusing to plan until the resource is re-imported
D. To destroy the resource

<details>
<summary>Answer</summary>

**B.** Since state no longer tracks the resource but the `.tf` block
still declares it, Terraform interprets this as "this resource doesn't
exist yet and needs to be created." For globally-unique-named resources
this fails safely; for others it risks creating a genuine duplicate.

</details>

---

**Q6.** What does `terraform state push terraform.tfstate` do to the
current remote state?

A. Merges the local file's contents with the current remote state
B. Overwrites the current remote state entirely with the local file's
   contents
C. Compares the two and only updates fields that differ
D. Refuses to run unless the local file's serial is higher

<details>
<summary>Answer</summary>

**B.** `state push` is a full overwrite, not a merge. Any remote state
changes recorded after the version being pushed are discarded from
Terraform's record. (Real AWS resources are unaffected by `state push`
either way — only Terraform's belief about them changes.)

</details>

---

**Q7.** Immediately after restoring an old state version with `state
push`, what should you run, and why?

A. `terraform destroy` — to clear any inconsistency
B. `terraform plan -refresh-only` — to check whether the restored state
   matches current real infrastructure
C. Nothing — the restore is complete
D. `terraform force-unlock` — to release any leftover lock

<details>
<summary>Answer</summary>

**B.** The restore only changes what Terraform believes; it doesn't
verify whether that belief matches reality. `-refresh-only` surfaces any
gap so it can be reconciled with a follow-up `apply` if needed.

</details>

---

**Q8.** A teammate sees an "Error acquiring the state lock" message and
immediately runs `terraform force-unlock <ID>` without checking anything
else. What is the risk?

A. None — `force-unlock` always verifies it's safe before unlocking
B. If an apply genuinely is still running, removing the lock allows a
   second apply to start concurrently, risking state corruption
C. `force-unlock` will simply fail if the apply is still running
D. The lock will automatically reappear if needed

<details>
<summary>Answer</summary>

**B.** `force-unlock` does not check whether an apply is actually still
in progress — it simply removes the lock file. If used while a real
apply is running, two applies can now write to state concurrently,
exactly the corruption scenario locking exists to prevent. Always
confirm via the lock's `Who` field first.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 05 |
| 7/8 | Review the wrong answer, then proceed |
| 6/8 | Re-read the relevant section, retry those questions |
| Below 6/8 | Re-read the full demo and redo the walkthrough before proceeding |
