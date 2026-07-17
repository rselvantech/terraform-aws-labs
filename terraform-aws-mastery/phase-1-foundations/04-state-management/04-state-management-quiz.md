# Quiz — Demo 04: State Management and Backends: Import, Surgery, and Recovery

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 05.

---

**Q1. (True/False)** `terraform import` creates a new resource in the
target cloud provider if one doesn't already exist at the given ID.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `import` never creates anything in AWS — it only adds an
*existing* resource to Terraform's state, mapped to the resource
address you specify. If no resource exists at that ID, import fails.

</details>

---

**Q2. (Multiple Choice)** In `terraform.tfstate`, what does the
top-level `version` field actually represent?

- A) The Terraform CLI version that last wrote the file
- B) The state file's own JSON schema/format version — currently `4`
- C) The AWS provider version in use
- D) The number of times `apply` has been run against this state

<details>
<summary>Answer</summary>

**B.** `version` describes the internal storage schema, not the CLI —
that's the separate `terraform_version` field (A). It has nothing to do
with the provider (C) or an apply counter (D, which is what `serial`
tracks).

</details>

---

**Q3. (Multiple Choice)** What is the purpose of the `serial` field in
`terraform.tfstate`?

- A) It's a random identifier generated once, never changing
- B) It's a counter, incremented on every write, used to detect conflicting/stale writes
- C) It records how many resources are currently tracked
- D) It's the schema version of the state file

<details>
<summary>Answer</summary>

**B.** `serial` increments on every backend write (apply, import,
`state mv`, `state push`). If a write is attempted with a serial the
backend has already moved past, Terraform rejects it — this is the
primary defense against two writers corrupting state, especially during
the window between `plan` (no lock held) and `apply`.

</details>

---

**Q4. (Multiple Choice)** What is `lineage` in `terraform.tfstate` used
to detect?

- A) Which engineer last modified state
- B) Whether the current apply is taking too long
- C) Whether a state file being pushed belongs to a completely different, unrelated project
- D) The order resources were created in

<details>
<summary>Answer</summary>

**C.** `lineage` is a UUID generated once at state creation and never
changed. `terraform state push` compares the pushed file's `lineage`
against the backend's current `lineage` — a mismatch means the file
belongs to a different configuration's "family" entirely, and the push
is rejected before any damage occurs.

</details>

---

**Q5. (True/False)** `terraform show -json` and the raw contents of
`terraform.tfstate` use the same JSON schema.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `terraform.tfstate` is the backend's raw internal storage
format — an implementation detail that can change between Terraform
versions. `terraform show -json` outputs a separate, documented, stable
schema intended for external tooling, and even includes its own
`format_version` field that never appears in `.tfstate` at all.

</details>

---

**Q6. (Multiple Answer — Pick the 2 correct responses)** Which TWO of
the following commands make zero changes to state or infrastructure?

- A) `terraform show`
- B) `terraform state rm`
- C) `terraform plan`
- D) `terraform apply -refresh-only`
- E) `terraform import`

<details>
<summary>Answer</summary>

**A and C.** `terraform show` only reads and displays current state.
`terraform plan` refreshes into memory and computes a diff but never
writes anything. `state rm` (B) writes a state change (removes an
entry). `apply -refresh-only` (D) writes to state once you confirm —
that's exactly the "accept drift" behavior this demo used to simulate a
bad write. `import` (E) writes a new entry to state.

</details>

---

**Q7. (Multiple Choice)** A resource is imported successfully, and
`default_tags` are configured in the provider block. What does
`terraform plan` show immediately afterward, and why?

- A) No changes — a successful import always fully matches the live resource
- B) A `tags_all` pending change — the imported resource predates `default_tags` being applied, so the tags haven't been reconciled onto it yet
- C) An error — imports are incompatible with `default_tags`
- D) A prompt asking whether to apply the default tags now

<details>
<summary>Answer</summary>

**B.** This is expected, correct behavior, not a sign anything went
wrong. The import reads the resource's actual current attributes (no
tags), while `default_tags` specifies every resource should carry the
common tags — `tags_all` is where that reconciliation happens. A clean
import is always import + `apply` (to close this gap) + `plan` showing
zero changes.

</details>

---

**Q8. (Multiple Choice)** What is the main practical advantage of an
`import {}` block over the CLI `terraform import` command?

- A) It works with more resource types than the CLI form
- B) It's reviewable in `terraform plan` before anything happens, and lives in version control as a repeatable action
- C) It doesn't require knowing the resource's import ID
- D) It automatically writes the matching resource block for you

<details>
<summary>Answer</summary>

**B.** The CLI form executes immediately with no preview. The `import
{}` block shows as a planned action in `plan` first, and being in a
`.tf` file makes it version-controlled and repeatable. Both forms need
the same import ID (C is wrong); code generation (D) is a separate,
optional flag (`-generate-config-out`), not automatic; and both work
with the same set of importable resource types (A is wrong).

</details>

---

**Q9. (Multiple Choice)** You rename a resource in `.tf` from
`aws_s3_bucket.legacy` to `aws_s3_bucket.uploads`, and run `terraform
plan` without doing anything else first. What does the plan show?

- A) No changes — Terraform detects renames automatically
- B) `1 to add, 0 to change, 1 to destroy` — interpreted as delete-old, create-new
- C) `1 to import` — Terraform treats it as a fresh import
- D) An error requiring `state mv` before `plan` can even run

<details>
<summary>Answer</summary>

**B.** Terraform has no way to distinguish "this was renamed" from
"the old one was deleted and an unrelated new one was declared" — state
still says `.legacy`, config now says `.uploads`, so it plans
destroy+create. The fix is `terraform state mv aws_s3_bucket.legacy
aws_s3_bucket.uploads`, run *before* applying this plan.

</details>

---

**Q10. (Multiple Choice)** After renaming a resource and running `state
mv`, you forget to update a reference to the old resource label in
`outputs.tf`. What happens on the next `plan`?

- A) Nothing — Terraform automatically updates every reference for you
- B) A "Reference to undeclared resource" error, since the old label no longer exists anywhere in the resource blocks
- C) The output silently returns `null`
- D) `state mv` fails retroactively

<details>
<summary>Answer</summary>

**B.** `state mv` only edits *state* — never `.tf` files. Every `.tf`
file that references the old resource label must be updated manually
and separately; missing even one (like an unrelated `outputs.tf`)
produces a hard reference error, not a silent failure.

</details>

---

**Q11. (Multiple Choice)** Does `terraform state rm aws_s3_bucket.uploads`
delete the bucket in AWS?

- A) Yes, immediately
- B) Yes, but only on the next `apply`
- C) No — the resource is untouched in AWS; only Terraform's record of it is removed
- D) Only if `force_destroy = true` is set

<details>
<summary>Answer</summary>

**C.** This is one of the most commonly misunderstood facts about
`state rm` and a frequent exam trap. The resource keeps running exactly
as it was — Terraform simply forgets it exists. `force_destroy` (D) is
unrelated; it only controls whether `destroy` can remove a non-empty S3
bucket.

</details>

---

**Q12. (Multiple Choice)** After `state rm` on a resource whose `.tf`
block still exists, what does `terraform plan` propose next, and what
should you actually do?

- A) Nothing — Terraform re-detects the existing resource automatically
- B) Propose to create the resource; correct fix is `terraform import`, not `apply`
- C) Propose to create the resource; running `apply` is always safe here
- D) Refuse to plan until the resource is manually deleted from AWS first

<details>
<summary>Answer</summary>

**B.** State no longer knows the resource exists, so `plan` proposes
creating it. Running `apply` here is risky — it happens to fail safely
for S3 (`BucketAlreadyExists`, thanks to global uniqueness), but for
resource types without a uniqueness constraint, `apply` could silently
create a genuine duplicate. The correct fix is always re-`import`.

</details>

---

**Q13. (Multiple Choice)** What does `terraform state push
terraform.tfstate` do to the currently stored remote state?

- A) Merges the pushed file's contents with what's already there
- B) Overwrites the current remote state entirely with the pushed file's contents
- C) Compares the two and updates only the fields that differ
- D) Appends the pushed file's resources to the existing list

<details>
<summary>Answer</summary>

**B.** `state push` is a full overwrite, never a merge. Anything
recorded in remote state after the version being pushed is discarded
from Terraform's record (the actual AWS resources are unaffected —
only Terraform's belief about them changes). Always follow with `plan
-refresh-only` to check whether the restored state matches reality.

</details>

---

**Q14. (Multiple Choice)** A teammate sees "Error acquiring the state
lock" and immediately runs `terraform force-unlock <ID>` with no other
checks. What is the risk?

- A) None — `force-unlock` verifies it's safe before removing the lock
- B) If an apply genuinely is still running, a second apply can now start concurrently, risking state corruption
- C) `force-unlock` automatically fails if an apply is actually in progress
- D) The lock silently reappears once the original apply finishes

<details>
<summary>Answer</summary>

**B.** `force-unlock` does not check whether an apply is actually still
running — it simply deletes the lock file. Using it while a real apply
is in progress allows two concurrent writers, exactly the corruption
scenario locking exists to prevent. Always confirm via the lock's `Who`
field before unlocking.

</details>

---

**Q15. (Multiple Choice)** Why does suspending S3 bucket versioning in
the Console produce no drift in `terraform plan` if the configuration
only uses the inline `versioning {}` argument inside `aws_s3_bucket`
(no standalone resource)?

- A) `versioning {}` is deprecated — Terraform only performs drift detection when a configuration value is present to compare against, and the deprecated inline block doesn't provide one
- B) S3 versioning cannot drift once enabled
- C) `terraform plan` never checks S3 configuration at all
- D) Drift detection for versioning requires `-refresh=false`

<details>
<summary>Answer</summary>

**A.** The inline `versioning {}` argument is deprecated as of AWS
provider v4 specifically for this reason — official docs state
Terraform only performs drift detection when a configuration value is
provided. Without the standalone `aws_s3_bucket_versioning` resource,
there's nothing configured to compare live state against, so Console
changes to versioning go completely undetected.

</details>

---

**Q16. (True/False)** `terraform refresh` is the current recommended
command for detecting drift between state and real infrastructure.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `terraform refresh` is deprecated as of Terraform 1.0 and
may be removed in a future version. The recommended replacements are
`terraform plan -refresh-only` (read-only, previews the update) or
`terraform apply -refresh-only` (writes the update to state after
confirmation).

</details>

---

Score guide:

| Score | Action |
|---|---|
| 15-16/16 | Import Anki cards, move to Demo 05 |
| 13-14/16 | Review the wrong answers, then proceed |
| 11-12/16 | Re-read the relevant sections, retry those questions |
| Below 11/16 | Re-read the full demo and redo the walkthrough before proceeding |
