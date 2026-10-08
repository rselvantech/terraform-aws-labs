# Quiz — Demo 01: Terraform Fundamentals: First Real AWS Project with S3

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 02.

---

**Q1. (True/False)** The Terraform CLI and the AWS provider are
versioned together as one package — upgrading one always upgrades the
other.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** They are two completely independent, separately versioned
software packages. Terraform CLI (e.g. `v1.15.0`) is the engine; the AWS
provider (e.g. `v6.47.0`) is a plugin downloaded on `init`. A new AWS
service feature requires a provider update, not a CLI update.

</details>

---

**Q2. (Multiple Choice)** Why did AWS provider v6 move S3 settings like
versioning and encryption out of inline blocks inside `aws_s3_bucket`
into their own standalone resources?

- A) Inline blocks were removed for performance reasons
- B) Standalone resources allow each setting to be independently managed, imported, or removed without affecting the bucket resource itself
- C) AWS's API no longer supports nested configuration
- D) Standalone resources are required for `terraform fmt` to work correctly

<details>
<summary>Answer</summary>

**B.** The whole point of the v6 change is fine-grained control — each
setting can now be imported, modified, or removed independently of the
bucket resource and of each other. This has nothing to do with
performance (A), AWS's actual API (C), or formatting (D).

</details>

---

**Q3. (Multiple Choice)** Which AWS provider authentication method
should never be used in a real configuration?

- A) Named profile via `profile = "default"`
- B) Static credentials directly in the provider block (`access_key`/`secret_key`)
- C) Environment variables (`AWS_ACCESS_KEY_ID`)
- D) IAM Instance Profile / ECS Task Role

<details>
<summary>Answer</summary>

**B.** Static credentials hardcoded into the provider block get
committed to version control the moment the file is committed — a
direct secrets leak. Every other method (named profile, environment
variables, instance role, SSO) avoids putting the secret directly into
a tracked file.

</details>

---

**Q4. (True/False)** `random_id.suffix.hex` generates a new random value
on every `terraform apply`, so the bucket name changes each time.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `random_id` generates its value once, on first apply, and
stores it in state. Every subsequent apply reuses the same stored value
— the bucket name stays stable across applies unless the resource is
explicitly replaced (e.g. `-replace`).

</details>

---

**Q5. (Multiple Choice)** Once `aws_s3_bucket_versioning`'s status has
been set to `Enabled`, can it later be fully turned off (`Disabled`)?

- A) Yes, set `status = "Disabled"` at any time
- B) No — once enabled, it can only be `Suspended`, never fully disabled
- C) Only by destroying and recreating the bucket
- D) Only via the AWS CLI, not Terraform

<details>
<summary>Answer</summary>

**B.** `Disabled` is only valid for a bucket that has *never* had
versioning enabled. Once enabled, the only way to stop new versions is
`Suspended` — existing versions are kept, but no new ones are created.
This is an AWS S3 constraint, not a Terraform limitation.

</details>

---

**Q6. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about `aws_s3_bucket_public_access_block`'s four boolean
arguments are correct?

- A) All four default to `true`
- B) All four default to `false`
- C) Setting only `block_public_policy = true` provides complete protection
- D) All four must be set to `true` together for complete protection — a public ACL can bypass a blocked policy and vice versa
- E) `block_public_acls` only affects individual objects, never the bucket itself

<details>
<summary>Answer</summary>

**B and D.** All four arguments default to `false` — protection is opt-in,
not automatic. Setting only some of them leaves real gaps (C is wrong):
a public ACL can grant access even with a blocked policy, and vice
versa, which is exactly why all four together (D) are needed for
complete protection. E is wrong — `block_public_acls` affects both
bucket-level and object-level ACLs.

</details>

---

**Q7. (Multiple Choice)** What is the cost difference between SSE-S3
(`AES256`) and SSE-KMS encryption on an S3 bucket?

- A) Both are always free
- B) SSE-S3 is free; SSE-KMS costs $0.03/10,000 requests plus ~$1/month per key
- C) SSE-S3 costs more because it's the newer standard
- D) Both are billed per GB stored, regardless of algorithm

<details>
<summary>Answer</summary>

**B.** SSE-S3 (AES256) uses AWS-managed keys and is always free. SSE-KMS
uses customer-managed keys via AWS KMS, which bills per API request plus
a monthly per-key charge — the tradeoff is finer-grained key control and
audit trails.

</details>

---

**Q8. (Multiple Choice)** Which of the following is one of Terraform's
five meta-arguments (arguments that control Terraform's own behavior,
independent of any provider)?

- A) `region`
- B) `tags`
- C) `lifecycle`
- D) `bucket`

<details>
<summary>Answer</summary>

**C.** The five meta-arguments are `depends_on`, `count`, `for_each`,
`provider`, and `lifecycle`. `region`, `tags`, and `bucket` are all
ordinary resource-specific arguments the AWS provider itself
understands — not meta-arguments.

</details>

---

**Q9. (Multiple Choice)** `aws_s3_bucket_public_access_block.app`
references `aws_s3_bucket.app.id`, which already creates an implicit
dependency. Why is an explicit `depends_on` still needed for S3
specifically?

- A) Implicit references don't work for S3 resources at all
- B) `CreateBucket` returning `200 OK` doesn't guarantee the bucket has fully propagated across S3's internal systems yet — `depends_on` waits for full completion, not just a successful API response
- C) `depends_on` is required syntax for every `aws_s3_bucket_*` resource regardless of ordering
- D) The implicit reference only works if `force_destroy = true` is set

<details>
<summary>Answer</summary>

**B.** This is AWS S3's eventual consistency model — a real AWS
behavior, not a Terraform limitation. The implicit reference correctly
orders bucket creation before the configuration resource, but Terraform
considers the bucket "done" as soon as the API call succeeds, which can
be before AWS's internal systems are fully ready. `depends_on` adds a
wait for full completion, giving that propagation gap time to close.

</details>

---

**Q10. (Multiple Choice)** Two engineers both use local Terraform state
against the same configuration. Engineer B clones the repo (no state
file included) and adds a resource. What is the most likely result of
Engineer B's `apply`?

- A) Terraform automatically detects Engineer A's existing resources
- B) Engineer B's plan shows zero existing resources, so it attempts to create everything from scratch — risking duplicates or `AlreadyExists` errors
- C) The apply is blocked entirely until state is manually merged
- D) Git resolves the state conflict automatically on push

<details>
<summary>Answer</summary>

**B.** With no local state file, Terraform has no memory of what
Engineer A already created — it plans as if nothing exists yet. This
either fails with an "already exists" error, or worse, silently creates
duplicate resources with different random suffixes. Neither engineer
now has a state file that reflects reality.

</details>

---

**Q11. (True/False)** Only `terraform apply` acquires a state lock;
`terraform plan` never touches the lock.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `terraform plan` also briefly acquires the state lock
during its refresh step, even though it makes no changes — this is a
commonly tested exam trap.

</details>

---

**Q12. (Multiple Choice)** Is a DynamoDB table required for S3 backend
state locking in Terraform 1.11+?

- A) Yes — DynamoDB is the only supported locking mechanism for S3 backends
- B) No — `use_lockfile = true` uses S3 conditional writes; `dynamodb_table` is deprecated
- C) No — locking was removed entirely in 1.11
- D) Yes, but only for buckets outside `us-east-2`

<details>
<summary>Answer</summary>

**B.** Terraform 1.10 introduced S3 native locking via conditional
writes, creating a `.tflock` file directly in the state bucket — no
DynamoDB table, no extra IAM permissions, no extra monthly cost. The
older `dynamodb_table` backend argument is deprecated as of v1.11.

</details>

---

**Q13. (Multiple Choice)** Can `var.aws_region` be used inside a
`backend "s3"` block to set the `region` argument dynamically?

- A) Yes, exactly like any other resource argument
- B) No — the backend block is evaluated before variables are loaded, so `Variables may not be used here` is the resulting error
- C) Yes, but only if the variable has a `default` value
- D) No — backend blocks don't support the `region` argument at all

<details>
<summary>Answer</summary>

**B.** The backend block is resolved before any provider initializes and
before variables are loaded — there's no variable resolution available
at that point in the process. This is why `backend.tf` always has
hardcoded values; the production workaround is partial backend
configuration via `-backend-config` flags or a `.tfbackend` file.

</details>

---

**Q14. (Multiple Choice)** What does `terraform init -migrate-state` do
to the local `terraform.tfstate` file?

- A) Deletes it immediately after copying
- B) Copies its contents to the new backend and prompts for confirmation first; the local file becomes a stale, unused backup
- C) Merges it with any existing state already in the new backend
- D) Converts it into the `.tflock` file format

<details>
<summary>Answer</summary>

**B.** `init -migrate-state` prompts for confirmation before copying —
never automatic — then copies local state to the new backend. The S3
copy becomes authoritative; the local file is left on disk as a stale
backup, not deleted or actively used going forward.

</details>

---

**Q15. (True/False)** `terraform state show <address>` makes a read-only
API call to AWS to fetch the resource's current live attributes.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `state show` reads only from the state file already on
disk (or in the backend) — it makes zero AWS API calls. This is
different from `terraform show` after a `plan`/`apply` refresh, and very
different from `plan` itself, which does refresh via API calls.

</details>

---

**Q16. (Multiple Choice)** After running `terraform plan -refresh-only`
and confirming drift exists, what are the two available responses?

- A) `apply -refresh-only` (accept the drift into state) or plain `apply` (reconcile AWS back to match `.tf` files)
- B) `destroy` and recreate, or ignore it permanently
- C) `state rm` the resource, or manually edit the state file
- D) There is only one option: plain `apply`

<details>
<summary>Answer</summary>

**A.** `apply -refresh-only` accepts the drift by updating state to
match the observed reality, without touching `.tf` files or removing
the manual change. A plain `apply` reconciles the opposite direction —
removing whatever isn't declared in `.tf`. Production default is
usually the latter, since Terraform should remain the source of truth.

</details>

---

**Q17. (Multiple Choice)** What is a required condition before running
`terraform force-unlock <LOCK_ID>`?

- A) None — it's always safe to run immediately when a lock error appears
- B) Confirming that no apply is actually still running — force-unlock does not verify this itself
- C) The lock must be older than 24 hours
- D) It can only be run by the same engineer who created the lock

<details>
<summary>Answer</summary>

**B.** `force-unlock` simply removes the lock — it performs no check on
whether an apply is genuinely still in progress. Using it while a real
apply is running allows two concurrent writers and risks exactly the
state corruption locking exists to prevent. Always confirm first (e.g.
check with the team, check CI status).

</details>

---

**Q18. (Multiple Choice)** Why must the S3 bucket that stores Terraform
state be created outside of Terraform (e.g. via Console), rather than
as a resource inside the same configuration?

- A) Terraform cannot create S3 buckets at all
- B) It's a chicken-and-egg problem — Terraform needs the backend bucket to exist before `init` can configure the backend that would store state about creating that same bucket
- C) AWS restricts state buckets to being created only via the Console
- D) It's a stylistic convention, not a technical requirement

<details>
<summary>Answer</summary>

**B.** This is a genuine circular dependency, not just a convention.
`terraform init` needs to connect to a backend bucket before it can
manage anything — including a resource meant to create that very
bucket. The bootstrap step (creating the state bucket) must happen
outside the configuration that will use it as a backend.

</details>

---

**Q19. (Multiple Choice)** What does `aws_s3_bucket`'s `force_destroy`
argument control, and when is it appropriate to use?

- A) Forces immediate deletion regardless of versioning — safe for production
- B) When `true`, allows `terraform destroy` to empty a non-empty bucket before deleting it — intended for demo/test environments only
- C) Forces the bucket to be recreated on every apply
- D) Prevents accidental deletion by requiring a second confirmation

<details>
<summary>Answer</summary>

**B.** With `force_destroy = true`, `destroy` will delete all objects in
the bucket first, then the bucket itself — without it, `destroy` fails
on any non-empty bucket. This should be removed in production, since it
makes accidental data loss much easier.

</details>

---

**Q20. (Multiple Choice)** Which of the following S3-related resources
was NOT used in this demo, and what does it do?

- A) `aws_s3_bucket_versioning` — enables object version history
- B) `aws_s3_bucket_lifecycle_configuration` — auto-deletes or archives objects after N days
- C) `aws_s3_bucket_public_access_block` — blocks public access paths
- D) `aws_s3_bucket_server_side_encryption_configuration` — encrypts objects at rest

<details>
<summary>Answer</summary>

**B.** `aws_s3_bucket_lifecycle_configuration` is a related resource
mentioned as "worth knowing" but not actually used in this demo's
configuration — it manages automatic transition/expiration rules for
objects over time. The other three (A, C, D) are all part of this
demo's four core standalone resources.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 19-20/20 | Import Anki cards, move to Demo 02 |
| 16-18/20 | Review the wrong answers, then proceed |
| 14-15/20 | Re-read the relevant sections, retry those questions |
| Below 14/20 | Re-read the full demo and redo the walkthrough before proceeding |
