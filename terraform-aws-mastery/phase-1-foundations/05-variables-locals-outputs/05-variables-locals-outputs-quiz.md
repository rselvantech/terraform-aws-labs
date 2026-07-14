# Quiz — Demo 05: Variables, Locals, and Outputs: Value Flow Through a Configuration

> One correct answer per question unless stated otherwise.
> Target: 80% or above before moving to Demo 06.
> TA-004 exam style.

---

**Q1.** A variable is marked `sensitive = true`. Which statement is
accurate?

A. The value is encrypted in `terraform.tfstate`
B. The value is redacted from plan/apply terminal output but is still
   written to `terraform.tfstate` in plaintext
C. The value is never written to state or any file
D. The value cannot be used in regular resource arguments

<details>
<summary>Answer</summary>

**B.** `sensitive = true` only redacts from terminal output. State
storage is plaintext regardless. For never-written-to-state behaviour,
use `ephemeral = true`. State security requires a secure backend
(encrypted S3, IAM access control), not the `sensitive` flag.

</details>

---

**Q2.** What is the variable value precedence order? Rank from highest
to lowest: `TF_VAR_` environment variable, CLI `-var` flag, `default`
value, `terraform.tfvars` file.

A. `-var` > `TF_VAR_` > `terraform.tfvars` > `default`
B. `terraform.tfvars` > `-var` > `TF_VAR_` > `default`
C. `TF_VAR_` > `terraform.tfvars` > `-var` > `default`
D. `default` > `terraform.tfvars` > `TF_VAR_` > `-var`

<details>
<summary>Answer</summary>

**A.** CLI `-var` flag is highest. `TF_VAR_` environment variables
override `terraform.tfvars`. `default` is the lowest fallback. Full
order: CLI `-var` > `-var-file` > `*.auto.tfvars` > `terraform.tfvars`
> `TF_VAR_` > `default`.

</details>

---

**Q3.** A `validation` block has `condition = "prod"` (a string literal).
What happens?

A. Passes — non-empty strings are truthy in Terraform
B. Errors at `terraform validate` — condition must return a boolean
C. The validation is silently ignored
D. Errors only at `apply` time, not `validate`

<details>
<summary>Answer</summary>

**B.** A `validation` block's `condition` must evaluate to `true` or
`false`. `terraform validate` errors immediately: "A condition expression
must return either true or false."

</details>

---

**Q4.** What does `coalesce(var.custom_name, local.computed_name)`
return when `var.custom_name` is set to `""`?

A. `""` — coalesce returns the first non-null value, and `""` is not null
B. `local.computed_name` — coalesce skips both null AND empty string
C. An error — coalesce requires at least one non-null argument
D. `null`

<details>
<summary>Answer</summary>

**B.** `coalesce()` skips both `null` AND `""` — empty string is treated
the same as null. Only a non-null, non-empty string satisfies coalesce.

</details>

---

**Q5.** You call `merge(local.common_tags, var.extra_tags)`. Both have
key `"Owner"`. Which value appears in the result?

A. `local.common_tags`'s value — the left-most map wins
B. `var.extra_tags`'s value — the right-most map wins
C. Both values are combined into a list
D. An error — duplicate keys are not allowed in merge()

<details>
<summary>Answer</summary>

**B.** `merge()` uses right-most-wins for key conflicts. `var.extra_tags`
is rightmost, so its `"Owner"` value overrides `local.common_tags`'s.

</details>

---

**Q6.** A teammate runs `terraform output -json` and sees the actual
value of an output marked `sensitive = true`. Is this expected?

A. No — this is a bug; sensitive outputs should be redacted everywhere
B. Yes — `sensitive = true` only redacts from human-readable terminal
   display; `-json` always includes the actual value for programmatic use
C. Only if the user has special IAM permissions
D. No — the output should show `null` in JSON format

<details>
<summary>Answer</summary>

**B.** `sensitive = true` redacts from human-readable output only.
`terraform output -json` is designed for programmatic consumption and
always includes sensitive values. Treat `-json` output with the same
care as the state file.

</details>

---

**Q7.** A producer configuration's output is marked `ephemeral = true`.
Can a consumer read it via `data.terraform_remote_state`?

A. Yes — all outputs are available via remote state regardless of
   ephemeral status
B. No — ephemeral outputs are never written to state, so remote state
   has nothing to read
C. Yes — but only if the consumer runs in the same Terraform session
D. Only if the consumer also marks its output `ephemeral = true`

<details>
<summary>Answer</summary>

**B.** Ephemeral outputs are never written to `terraform.tfstate` —
they exist only during the apply session. Since `terraform_remote_state`
reads the state file, ephemeral outputs simply are not there.

</details>

---

**Q8.** You add `ephemeral = true` to an output block in your root module
and run `terraform validate`. What happens?

A. Validates successfully — ephemeral outputs are supported everywhere
B. Validates successfully but warns that ephemeral outputs are experimental
C. Errors: "Ephemeral output not allowed — Ephemeral outputs are not
   allowed in context of a root module"
D. Errors only at apply time, not validate time

<details>
<summary>Answer</summary>

**C.** `ephemeral = true` on outputs is only valid in child modules.
Root modules have no caller to receive the ephemeral value. `terraform
validate` catches this immediately.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 06 |
| 7/8 | Review the wrong answer, then proceed |
| 6/8 | Re-read the relevant section, retry those questions |
| Below 6/8 | Re-read the full demo and redo the walkthrough before proceeding |
