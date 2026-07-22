# Quiz — Demo 08: Data Sources

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 09.

---

**Q1. (True/False)** Removing a `data` block from a Terraform
configuration destroys the real-world thing it was reading.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `data` blocks never have lifecycle ownership — removing
one only means Terraform stops reading it on future plans. The real
resource, wherever it lives, is completely unaffected.

</details>

---

**Q2. (Multiple Choice)** What is the fundamental difference between a
`resource` block and a `data` block?

- A) `resource` blocks are AWS-only; `data` blocks work with any provider
- B) `resource` blocks manage full lifecycle (create/update/destroy, tracked in state); `data` blocks only read
- C) `data` blocks always run before `resource` blocks
- D) There's no real difference — both are interchangeable syntax

<details>
<summary>Answer</summary>

**B.** This is the core distinction. Both block types exist across
every provider (A is wrong), and while data sources are often read
early in the graph, that's a consequence of dependency ordering, not a
fixed rule (C is wrong).

</details>

---

**Q3. (True/False)** `data "aws_caller_identity" "current" {}` is
incomplete — it requires at least a `region` argument.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** An empty body is correct and complete for this data
source — it needs no input at all, and returns the current account ID,
ARN, and user ID based purely on how the provider is authenticated.

</details>

---

**Q4. (Multiple Choice)** `data.aws_iam_policy` requires which of the
following?

- A) Both `name` and `arn` together
- B) Neither `name` nor `arn` — it reads the account's default policy
- C) Exactly one of `name` or `arn`
- D) Only `arn` — `name` isn't a valid argument

<details>
<summary>Answer</summary>

**C.** One of the two identifies which policy to read — providing both
or neither is invalid. `arn` is useful when a name alone could be
ambiguous; `name` is more readable for well-known AWS-managed policies.

</details>

---

**Q5. (Multiple Choice)** `data.aws_iam_policy`'s `name` argument has a
typo that doesn't match any real policy. What happens?

- A) Silently resolves to an empty result
- B) Errors immediately at `plan` time: "no matching IAM policy found"
- C) Falls back to a default AWS-managed policy
- D) Only errors at `apply`, never at `plan`

<details>
<summary>Answer</summary>

**B.** This fails loudly and immediately during `plan`'s refresh step —
data source reads happen at plan time, so a nonexistent-policy error
surfaces well before `apply` would even be considered.

</details>

---

**Q6. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about `count` on a `data` block are correct?

- A) `count = 0` produces `null` for that data source
- B) `count = 0` produces an empty list for that data source
- C) Indexing `[0]` on a `count = 0` data source errors with "Invalid index"
- D) `data` blocks don't support the `count` meta-argument at all
- E) `count` behaves fundamentally differently on `data` blocks than on `resource` blocks

<details>
<summary>Answer</summary>

**B and C.** `count = 0` produces a genuinely empty list (not `null`),
and indexing `[0]` into that empty list produces the same generic
out-of-bounds error any empty-list index access would. `count` works
identically on `data` and `resource` blocks (E is wrong), and `data`
blocks fully support it (D is wrong).

</details>

---

**Q7. (Multiple Choice)** What kind of error does `data.aws_s3_bucket.legacy[0].arn`
produce when `count` evaluated to `0`?

- A) A data-source-specific error naming the missing bucket
- B) A generic "Invalid index — the collection has no elements" error, the same as any out-of-bounds list access
- C) `null`, silently
- D) A warning, but the plan still succeeds

<details>
<summary>Answer</summary>

**B.** Nothing about this error is specific to data sources — it's the
identical error any list literal's out-of-bounds index would produce.
This is exactly why the error message alone doesn't explain *why* the
list is empty; that requires checking what drives `count`.

</details>

---

**Q8. (Multiple Choice)** A `data.aws_ami` block's filters could match
three different AMIs, and `most_recent` is not set. What happens?

- A) Terraform picks the newest one automatically
- B) Terraform picks the first one returned by the API
- C) Terraform errors — ambiguous matches require an explicit tie-breaking rule
- D) Terraform returns all three as a list

<details>
<summary>Answer</summary>

**C.** Without `most_recent = true`, ambiguous filter matches cause an
error rather than an implicit choice — consistent with Terraform's
general avoidance of silent, unpredictable resolution.

</details>

---

**Q9. (Multiple Choice)** Why does `data.aws_ami` typically include
`owners = ["amazon"]` alongside its `filter` blocks?

- A) It's required syntax with no functional effect
- B) It restricts results to images published by a specific trusted account, avoiding unrelated matches from other accounts
- C) It determines which region the AMI is looked up in
- D) It sets the price tier of the resulting AMI

<details>
<summary>Answer</summary>

**B.** AMI names aren't globally unique across AWS accounts — without
restricting `owners`, a `name` filter pattern could theoretically match
images published by unrelated accounts. Scoping to a trusted owner (like
`"amazon"` for AWS-published images) keeps the match meaningful.

</details>

---

**Q10. (Multiple Choice)** A configuration made entirely of `data`
blocks is applied. What does `Resources: 0 added, 0 changed, 0
destroyed` mean?

- A) The apply failed
- B) This is expected — reads don't count toward the resource tally, even though the data was successfully read
- C) No data sources were actually read
- D) All data sources returned empty results

<details>
<summary>Answer</summary()>

**B.** The apply succeeds and the data is genuinely read (visible in
the "Reading.../Read complete" log lines) — it just never counts as
added, changed, or destroyed, since those three counters track only
lifecycle-managed `resource` blocks.

</details>

---

**Q11. (Multiple Choice)** What is the simplest test for deciding
whether something belongs in a `data` block or a `resource` block?

- A) Whether it costs money
- B) Whether removing the Terraform block would destroy the real thing
- C) Whether AWS or Terraform created it originally
- D) Whether it's referenced by other resources

<details>
<summary>Answer</summary()>

**B.** If deleting the code should NOT delete the real thing, it's
`data`. If it should, it's `resource`. Cost (A), original creator (C),
and whether other resources reference it (D) are all unrelated to this
decision.

</details>

---

**Q12. (Multiple Choice)** Beyond avoiding a hardcoded ARN string, what
practical capability does `data.aws_iam_policy` give you that a
hardcoded ARN alone doesn't?

- A) The ability to modify the policy
- B) Access to the policy's actual JSON document via `.policy`, for inspecting or referencing specific statements
- C) Automatic versioning of the policy
- D) The ability to attach the policy without any IAM permissions

<details>
<summary>Answer</summary()>

**B.** `.policy` returns the actual JSON policy document as a string —
useful if you need to inspect or extract details from it. A hardcoded
ARN gives you a string to attach elsewhere, but no visibility into the
policy's actual content. `data` sources never grant modification
ability (A) — that would require a `resource`, and AWS-managed
policies can't be edited regardless.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 11-12/12 | Import Anki cards, move to Demo 09 |
| 9-10/12 | Review the wrong answers, then proceed |
| 7-8/12 | Re-read the relevant sections, retry those questions |
| Below 7/12 | Re-read the full demo and redo the walkthrough before proceeding |
