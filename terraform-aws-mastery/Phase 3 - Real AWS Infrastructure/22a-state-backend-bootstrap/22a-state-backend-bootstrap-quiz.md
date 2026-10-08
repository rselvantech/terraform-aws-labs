# Quiz — Demo 22a: State Backend Bootstrap

> Question types: True/False, Multiple Choice, Multiple Answer —
> matching the real TA-004 exam format.
> Target: 80% or above before moving to Demo 22b.

---

**Q1. (Multiple Choice)** A teammate writes
`backend "s3" { bucket = var.state_bucket_name ... }` inside
`src/platform/01-backend.tf`, reasoning that it would avoid pasting in
a literal string. What happens?

- A) It works, since Terraform 1.15+ added variable support to backend blocks
- B) It fails — backend blocks are resolved before any variable evaluation context exists, in any Terraform release
- C) It works only if the variable has a `default` value set
- D) It works only in the bootstrap config, never in the consuming config

<details>
<summary>Answer</summary>

**B.** This has never been supported in Terraform and isn't
release-dependent — backend configuration is resolved before Terraform
can evaluate `var.*`, `local.*`, or any output reference. The only way
to parameterize it is `-backend-config` flags or files passed to
`terraform init`.

</details>

---

**Q2. (Multiple Choice)** In the Break-Fix file, `terraform init` fails
on a backend block that sets `bucket = var.state_bucket_name`, even
though the variable has a default value. Which change is a correct fix?

- A) Add a second default value to the variable
- B) Replace the reference with the literal bucket name, or supply it with `-backend-config` at `init`
- C) Move the variable into a `locals` block and reference `local.state_bucket_name`
- D) Run `terraform validate` first, which resolves variables before `init`

<details>
<summary>Answer</summary>

**B.** The backend block is resolved before variables, locals or
outputs exist, so defaults don't help (**A**) and a `local.*` reference
fails for the same reason (**C**). `validate` needs an initialised
directory, so it can't run ahead of `init` here (**D**).

</details>

---

**Q3. (Multiple Choice)** Starting with this demo, Break-Fix scenarios
use exactly one deliberate error instead of the three used in every
Phase 1/2 demo. What reason does this demo give for the change?

- A) Phase 3 concepts are considered too advanced for multi-error diagnosis
- B) Phase 3 resources (like an EKS cluster) take far longer per apply/fix cycle, making a three-error loop cost real, significant session time — the diagnostic skill itself is unchanged
- C) Terraform's own testing tools no longer support multi-error scenarios
- D) This demo's break-fix genuinely only has one possible thing that could go wrong

<details>
<summary>Answer</summary>

**B.** This demo's own Break-Fix section states this explicitly — the
change is described as a cost-driven adaptation to Phase 3's much
slower apply/fix cycles, not a reduction in what's being tested.

</details>

---

**Q4. (Multiple Choice)** A team needs the same Terraform configuration
to point at a different S3 backend bucket per environment (dev/
staging/prod), without hardcoding three different `backend.tf` files.
Given backend blocks can't reference variables, what's the actual
mechanism for this?

- A) Use `count` on the `backend` block to select the right bucket
- B) Pass the differing values via `-backend-config` flags or a file, at `terraform init` time
- C) Use a `for_each` over a list of possible buckets in the backend block
- D) Backend values can't ever differ across environments — a separate root config is always required

<details>
<summary>Answer</summary>

**B.** `-backend-config` is the real, supported mechanism for
supplying backend values that differ by environment or deployment —
passed at `init` time, not referenced inside the `backend` block
itself, which stays literal-only regardless.

</details>

---

**Q5. (Multiple Choice)** This demo's bootstrap config creates four
resources for the state bucket: the bucket itself, versioning,
encryption, and a public access block. How does this compare to Demo
01's own state bucket configuration?

- A) It's a stricter, new hardening standard introduced specifically because this bucket is project-layer, not per-demo
- B) It's the same production-grade S3 configuration Demo 01's bucket already used — nothing new in the resource shapes themselves
- C) Public access blocking is skipped here since the bucket is only ever accessed by Terraform
- D) Encryption is optional here since S3 already encrypts everything by default

<details>
<summary>Answer</summary>

**B.** This demo says so explicitly — the only genuinely new content
here is the bootstrap-config pattern itself; the S3 resource shapes
are identical to what Demo 01 already taught.

</details>

---

**Q6. (Multiple Choice)** In Step 2 of Part B, `terraform apply` in
`src/platform/` finishes immediately with `No changes` and `Resources:
0 added, 0 changed, 0 destroyed`, without ever asking you to type
`yes`. What does that indicate?

- A) The backend didn't initialise correctly
- B) Nothing is wrong — the config declares only a backend block, so there is nothing to create, and Terraform doesn't ask for approval when a plan contains no changes
- C) The state lock blocked the apply
- D) `apply` needs `-auto-approve` before it will run against an S3 backend

<details>
<summary>Answer</summary>

**B.** This matches the real output for both project configs. Contrast
with the bootstrap apply in Part A Step 3, which did stop for `yes`
because it had four resources to add. Nothing about the S3 backend
requires `-auto-approve`, and a blocked lock would produce an error,
not a clean completion.

</details>

---

**Q7. (Multiple Choice)** This demo's default `state_bucket_name`
includes a segment that looks like an AWS account ID, with a comment
saying to replace it with your own. If you leave it completely
unmodified and apply, what actually determines whether it succeeds?

- A) Whether the account ID segment matches your actual AWS account
- B) Whether that exact literal bucket name string is already taken by any AWS account, anywhere
- C) Whether your IAM user has an account-ID-matching tag
- D) It will always fail unless the segment is changed

<details>
<summary>Answer</summary>

**B.** In the shared global namespace this demo uses, S3 bucket names
are unique across every AWS account — not scoped per-account — so the
only thing that determines success is whether the literal string is
already taken by *anyone*, not whether its account-ID-shaped segment
happens to match the applying account.

</details>

---

**Q8. (Multiple Choice)** A learner gives `src/platform/01-backend.tf`
and `src/workloads/01-backend.tf` the same bucket and, by copy-paste,
the same `key` (`platform/terraform.tfstate`). What is the consequence
once resources are applied?

- A) Terraform errors immediately at `init`, refusing two configs on one key
- B) Both configs read and write one state file, so each treats the other's resources as its own and a `plan` proposes destroying whatever its own files don't declare
- C) S3 automatically namespaces state by directory, so nothing changes
- D) The second `init` prompts to migrate, and answering yes merges the two safely

<details>
<summary>Answer</summary>

**B.** Nothing stops two configs from sharing a key — `init` succeeds
for both. The isolation this design provides comes entirely from the
two keys being different; with a shared key there is only one state
file, and each config reconciles against resources it never declared.

</details>

---

**Q9. (Multiple Choice)** The bootstrap `terraform apply` stops at the
bucket with `BucketAlreadyOwnedByYou` (HTTP 409), and `terraform state
list` in `src/bootstrap/` prints nothing. What is the sensible first
response?

- A) Run `terraform destroy` to clear whatever was half-created, then start over
- B) Check whether the bucket actually exists in your account with `head-bucket`, and whether Terraform's state has it, before choosing between re-running `apply` and importing the bucket
- C) Change the backend `key` in `src/platform/01-backend.tf`
- D) Set `force_destroy = true` on the bucket and re-apply

<details>
<summary>Answer</summary>

**B.** The error says a bucket with this name already exists and you
own it, but on a real run against this demo an immediate re-run of
`apply` succeeded, so the situation at that moment wasn't what the
message implies. Two quick checks separate the cases: a `404` from
`head-bucket` means a plain re-run is the fix; a bucket that exists
while state is empty means Terraform isn't tracking it and it needs
importing. There is nothing to destroy (**A**), the backend key is
unrelated to bucket creation (**C**), and `force_destroy` only affects
deletion (**D**).

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8-9/9 | Import Anki cards, move to Demo 22b |
| 7/9 | Review the wrong answers, then proceed |
| 5-6/9 | Re-read the relevant sections, retry those questions |
| Below 5/9 | Re-read the full demo before proceeding |
