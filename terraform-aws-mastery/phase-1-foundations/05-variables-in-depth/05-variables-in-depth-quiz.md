# Quiz — Demo 05: Variables in Depth

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
storage is plaintext regardless. **A** is wrong — nothing about
`sensitive` triggers encryption; that requires a separately-encrypted
backend. **C** is wrong — that's `ephemeral = true`'s behavior, not
`sensitive`'s. **D** is wrong — sensitive values flow into regular
resource arguments exactly like any other value; only `ephemeral`
values have that restriction.

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

**A.** Full order: CLI `-var` > `-var-file` > `*.auto.tfvars` >
`terraform.tfvars` > `TF_VAR_` > `default`. So `-var` is highest and
`terraform.tfvars` actually outranks `TF_VAR_` (not the reverse). **B**
is wrong — it puts `terraform.tfvars` above `-var`, but no file-based
mechanism outranks the CLI flag. **C** is wrong — it places `TF_VAR_`
above `terraform.tfvars`, reversing their actual order. **D** is wrong
— it inverts the entire order, putting the lowest-precedence source
first.

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
`false`. `terraform validate` errors immediately. **A** is wrong —
Terraform has no "truthy string" concept; a condition must be an
actual boolean expression, not a non-empty string. **C** is wrong —
validation is never silently skipped; an invalid condition type is
itself an error. **D** is wrong — this is a `validate`-time error,
before any API call, not something that waits until `apply`.

</details>

---

**Q4.** A variable has `nullable = false` and `default = "dev"`. A
caller passes `-var="environment=null"`. What value is actually used?

A. `null`
B. `"dev"` — the default, since nullable = false substitutes it for null input
C. An empty string
D. An error is raised

<details>
<summary>Answer</summary>

**B.** With `nullable = false`, passing `null` causes Terraform to
substitute the `default` value instead — no error, no `null` value
used. **A** is wrong — that's the `nullable = true` (default) behavior,
where an explicit `null` does override. **C** is wrong — Terraform
never silently converts `null` to an empty string; it either becomes
`null` (`nullable = true`) or falls back to `default` (`nullable =
false`). **D** is wrong — this is a deliberate, documented substitution
behavior, not an error condition.

</details>

---

**Q5.** What does `alltrue([])` (an empty list) return?

A. `false` — an empty list has no true elements
B. `true` — vacuously true, no false elements exist to fail the check
C. An error — `alltrue()` requires at least one element
D. `null`

<details>
<summary>Answer</summary>

**B.** `alltrue([])` returns `true`. This is why validation conditions
using `alltrue([for x in var.list : ...])` pass when the list is empty
— there's nothing to violate the condition. **A** is wrong — it
reflects an intuitive but incorrect assumption; "all elements are true"
is vacuously satisfied by an empty set, the same logical principle as
an empty list satisfying a universally-quantified statement. **C** is
wrong — `alltrue()` doesn't require any minimum element count. **D** is
wrong — the function always returns a boolean, never `null`.

</details>

---

**Q6.** `var.retry_count` is `type = number`. What happens when you
write `var.retry_count + "extra"`?

A. Terraform coerces `"extra"` to `0` and adds it
B. Terraform concatenates them into a string
C. Terraform errors — `+` requires both operands to be numbers
D. Terraform silently drops the string

<details>
<summary>Answer</summary>

**C.** The `+` operator requires both sides to be numbers. Combining a
number into a descriptive string requires interpolation instead:
`"${var.retry_count} extra"`. **A** is wrong — Terraform never coerces
a non-numeric string to `0`; it errors instead of silently guessing.
**B** is wrong — that's what string interpolation does, not the `+`
operator, which is strictly arithmetic. **D** is wrong — there's no
silent-drop behavior anywhere in Terraform's type system; type
mismatches are errors, not warnings.

</details>

---

**Q7.** Which is the correct idiomatic pattern for validating a string
against a regex pattern inside a `validation` block?

A. `condition = regex("^[a-z]+$", var.name)`
B. `condition = can(regex("^[a-z]+$", var.name))`
C. `condition = var.name == regex("^[a-z]+$", var.name)`
D. Both A and B work identically

<details>
<summary>Answer</summary>

**B.** `regex()` alone errors when there's no match (it doesn't return
`false`) — `can()` converts that error into a boolean `false`, which is
what a `condition` requires. **A** is wrong — this is exactly the trap:
`regex()` without `can()` would cause `terraform validate` to error on
any non-matching input instead of cleanly failing the validation with
the custom `error_message`. **C** is wrong — comparing a string to
whatever `regex()` returns (which errors on no match, or a substring on
match) is not a meaningful boolean condition. **D** is wrong precisely
because A does not work identically to B — A errors uncontrolled, B
fails validation cleanly.

</details>

---

**Q8.** A variable is `ephemeral = true`. Which of the following is a
valid use of its value?

A. Passing it directly to a regular `resource` argument
B. Passing it to a `write_only` resource argument (1.10+)
C. Storing it in a `local` for later reuse across the config
D. Referencing it in a non-ephemeral output

<details>
<summary>Answer</summary>

**B.** `write_only` resource arguments are one of exactly two valid
ephemeral contexts (the other being a child-module ephemeral output).
**A** is wrong — regular resource arguments require Terraform to store
the value in state for drift detection, which is exactly what
`ephemeral` forbids. **C** is wrong — locals aren't an ephemeral
context; assigning an ephemeral value to a local doesn't make it safe
to store. **D** is wrong — a non-ephemeral output would itself write
the value to state, defeating the entire purpose of marking the
variable ephemeral.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 06 |
| 7/8 | Review the wrong answer, then proceed |
| 6/8 | Re-read the relevant section, retry those questions |
| Below 6/8 | Re-read the full demo and redo the walkthrough before proceeding |
