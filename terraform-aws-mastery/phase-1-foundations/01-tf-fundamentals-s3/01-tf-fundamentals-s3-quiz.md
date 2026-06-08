# Demo 01 — Quiz

> TA-004 exam style. One correct answer unless stated otherwise.
> Target: 80% or above before moving to Demo 02.

---

**Q1.** You add a `versioning {}` block inside `aws_s3_bucket` using AWS
provider v6.47. What happens when you run `terraform validate`?

- A) Passes — creates bucket with versioning enabled
- B) Errors: An argument named "versioning" is not expected here
- C) Ignores the block — creates bucket without versioning
- D) Automatically creates a separate aws_s3_bucket_versioning resource

<details>
<summary>Answer</summary>

**B** — v6 removed all inline S3 blocks. versioning, server_side_encryption_configuration,
and lifecycle_rule no longer exist inside aws_s3_bucket. Use standalone resources.

</details>

---

**Q2.** Why is `depends_on = [aws_s3_bucket.app]` needed on
`aws_s3_bucket_public_access_block` when the bucket ID is already referenced?

- A) Terraform cannot detect the dependency from the bucket ID reference
- B) AWS S3 eventual consistency — the bucket needs time to propagate internally before configuration applies
- C) It prevents the bucket from being deleted before the public access block
- D) Required syntax by AWS provider v6 schema

<details>
<summary>Answer</summary>

**B** — The reference creates a graph dependency and Terraform creates
the bucket first. But it starts the configuration resource immediately
when CreateBucket returns 200. AWS S3 is eventually consistent — the bucket
may not have propagated to all internal S3 systems yet. depends_on forces
full sequential completion before the configuration resource starts.

</details>

---

**Q3.** Is DynamoDB required for S3 state locking in Terraform 1.15?

- A) Yes — DynamoDB is the only locking mechanism for S3 backends
- B) No — use_lockfile = true uses S3 conditional writes, DynamoDB is deprecated
- C) No — Terraform 1.15 uses S3 object tagging for locking
- D) Yes — but only when more than one engineer uses the same state

<details>
<summary>Answer</summary>

**B** — use_lockfile = true introduced in v1.10, fully supported in v1.11.
Creates .tfstate.tflock using S3 conditional writes. dynamodb_table deprecated.
No DynamoDB table, no extra cost.

</details>

---

**Q4.** Two engineers run `terraform apply` simultaneously with S3 native
locking enabled. What happens?

- A) Both succeed — S3 handles concurrent writes safely
- B) Second apply fails immediately: Error acquiring the state lock
- C) Second apply queues and waits until the first finishes
- D) Both partially succeed, merging their changes

<details>
<summary>Answer</summary>

**B** — First apply creates .tfstate.tflock via conditional write. Second
apply tries to create the same file — S3 returns conflict. Terraform errors:
Error acquiring the state lock. Second apply exits immediately — it does
not queue.

</details>

---

**Q5.** After `terraform init -migrate-state`, what is the status of the
local `terraform.tfstate` file?

- A) Deleted automatically
- B) Emptied — resources removed, serial reset to 0
- C) Stale backup — S3 copy is authoritative, local not updated by future applies
- D) Symlinked to the S3 object

<details>
<summary>Answer</summary>

**C** — Local file becomes a stale backup. Terraform uses S3 for all
future operations. Local file not deleted or updated. Safe to delete.

</details>

---

**Q6.** What does `default_tags` in the AWS provider block do?

- A) Sets tags only on resources with no tags argument of their own
- B) Automatically merges specified tags into every resource the provider creates
- C) Overrides resource-level tags when both define the same key
- D) Only applies to resources in the default region

<details>
<summary>Answer</summary>

**B** — default_tags merged into every resource automatically. Resource-level
tags merge on top — in conflicts the resource-level tag wins, not default_tags.
C is wrong: resource wins, not default.

</details>

---

**Q7.** `versions.tf` has a `terraform {}` block. You add `backend.tf`
with another `terraform {}` block. Is this valid?

- A) No — only one terraform {} block per directory
- B) Yes — Terraform merges all .tf files and their terraform {} blocks cleanly
- C) No — backend block must be in versions.tf
- D) Yes — but only if versions.tf has no required_providers

<details>
<summary>Answer</summary>

**B** — Terraform merges all .tf files. Multiple terraform {} blocks merge
cleanly as long as the same setting is not declared twice. backend in
backend.tf + required_version in versions.tf = valid.

</details>

---

**Q8.** How much does AES256 (SSE-S3) encryption cost on an S3 bucket?

- A) $0.03 per 10,000 requests
- B) $1.00 per month per bucket
- C) Free — AWS absorbs the cost of S3-managed keys
- D) Free only within free tier, paid after 5GB

<details>
<summary>Answer</summary>

**C** — SSE-S3 (AES256) is always free. AWS manages keys internally at
no charge. SSE-KMS (customer-managed) is paid. This is why we use AES256.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Proceed to Demo 02 |
| 6-7/8 | Review wrong answers in Anki, then proceed |
| 4-5/8 | Re-read relevant README sections, retry |
| Below 4/8 | Re-read Demo 01 before proceeding |
