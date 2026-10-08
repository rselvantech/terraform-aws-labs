# Quiz — Demo 05: Variables in Depth

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 06.

---

**Q1. (True/False)** A variable marked `sensitive = true` is encrypted
when written to `terraform.tfstate`.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `sensitive = true` only redacts the value from
plan/apply terminal output and `terraform output` display. The value
is still written to `terraform.tfstate` in plaintext — state security
depends entirely on how the state itself is stored (encrypted backend,
access control), not on this flag.

</details>

---

**Q2. (Multiple Choice)** Which statement correctly distinguishes
`sensitive = true` from `ephemeral = true` on a variable?

- A) They behave identically — both are just different names for the same feature
- B) `sensitive` redacts from output but is stored in state; `ephemeral` is never stored in state, plan files, or logs
- C) `sensitive` is for strings only; `ephemeral` is for numbers only
- D) `ephemeral` redacts from output but is stored in state; `sensitive` is never stored anywhere

<details>
<summary>Answer</summary>

**B.** This is the core distinction: `sensitive` hides the value from
terminal/log output while still persisting it to state. `ephemeral`
goes further — the value exists only in memory during plan/apply and
is never written to state, saved plan files, or logs at all.

</details>

---

**Q3. (Multiple Choice)** A variable has `nullable = false` and
`default = "dev"`. A caller runs `terraform apply -var="environment=null"`.
What value does Terraform actually use?

- A) `null`
- B) `"dev"` — the default value
- C) An empty string `""`
- D) Terraform raises an error and refuses to proceed

<details>
<summary>Answer</summary>

**B.** With `nullable = false`, an explicitly passed `null` is not
allowed through — Terraform silently substitutes the `default` value
instead. This is documented behavior, not an error. (`nullable = true`,
the default, is what would let `null` override even with a default
present.)

</details>

---

**Q4. (Multiple Choice)** Inside a `variable` block's `validation`
condition, which of the following can it legally reference?

- A) Any other variable declared in the same configuration
- B) Any resource already applied in a previous run
- C) Only `var.<this variable>` — the variable the block belongs to
- D) `local` values computed elsewhere in the configuration

<details>
<summary>Answer</summary>

**C.** A `validation` condition can only reference the variable it
belongs to. Validation runs during variable resolution, before other
variables are guaranteed resolved and before any resources exist —
referencing anything else is out of scope by design.

</details>

---

**Q5. (Multiple Choice)** Rank the variable value precedence order from
**highest** to **lowest**: CLI `-var` flag, `TF_VAR_` environment
variable, `terraform.tfvars`, `default` value.

- A) `-var` > `terraform.tfvars` > `TF_VAR_` > `default`
- B) `TF_VAR_` > `-var` > `terraform.tfvars` > `default`
- C) `terraform.tfvars` > `-var` > `TF_VAR_` > `default`
- D) `default` > `TF_VAR_` > `terraform.tfvars` > `-var`

<details>
<summary>Answer</summary>

**A.** Full order, highest to lowest: CLI `-var` > `-var-file` >
`*.auto.tfvars` > `terraform.tfvars` > `TF_VAR_` environment variable >
`default`. The CLI flag always wins; the default is always the last
resort.

</details>

---

**Q6. (True/False)** HCL provides an `if` statement for writing
conditional logic directly, similar to most general-purpose programming
languages.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** HCL has no `if` statement of any kind. The conditional
operator (`condition ? true_val : false_val`) is the only conditional
mechanism in the language — for values, expressions, and (via
`count = var.create ? 1 : 0`) even conditional resource creation.

</details>

---

**Q7. (Multiple Choice)** `var.retry_count` is declared `type = number`.
What happens when a configuration evaluates `var.retry_count + "extra"`?

- A) Terraform coerces `"extra"` to `0` before adding
- B) Terraform concatenates the two into a single string
- C) Terraform raises an error — `+` requires both operands to be numbers
- D) Terraform silently ignores the string operand

<details>
<summary>Answer</summary>

**C.** The `+` operator is strictly arithmetic and requires both sides
to be numbers — Terraform never silently coerces a non-numeric string
to `0` or drops it. Combining a number into a descriptive string
requires interpolation instead: `"${var.retry_count} extra"`.

</details>

---

**Q8. (Multiple Choice)** What is the purpose of wrapping `regex()` in
`can()` inside a `validation` block, as in `can(regex("^[a-z]+$", var.name))`?

- A) `can()` makes the regex pattern case-insensitive
- B) `regex()` errors on no match rather than returning `false`; `can()` converts that error into a boolean the condition can use
- C) `can()` is required syntax for all functions used inside `validation` blocks
- D) `can()` improves the performance of the regex match

<details>
<summary>Answer</summary>

**B.** `regex()` alone throws an error when the pattern doesn't match —
it never returns `false`. `can()` catches that error and converts it
into `false`, which is exactly what a `validation` block's `condition`
needs (a boolean). Without `can()`, non-matching input would cause
`terraform validate` to fail with an unhandled error instead of
cleanly reporting the custom `error_message`.

</details>

---

**Q9. (Multiple Choice)** What does `alltrue([])` — called on an empty
list — return?

- A) `false`
- B) `true`
- C) An error, since there are no elements to evaluate
- D) `null`

<details>
<summary>Answer</summary>

**B.** `alltrue()` returns `true` if every element in the list is
`true` — and an empty list satisfies that vacuously, since there are no
`false` elements to violate the condition. This is why
`alltrue([for x in var.list : ...])` validations pass cleanly when the
list happens to be empty.

</details>

---

**Q10. (Multiple Answer — Pick the 2 correct responses)** Which TWO of
the following are valid contexts for a value marked `ephemeral = true`
to actually be used?

- A) A regular `resource` argument
- B) An `ephemeral = true` output block in a **child module**
- C) A `write_only` resource argument (Terraform 1.10+)
- D) A `local` value for later reuse elsewhere in the configuration
- E) An `ephemeral = true` output block in the **root module**

<details>
<summary>Answer</summary>

**B and C.** These are the only two ephemeral contexts. A regular
resource argument (A) requires Terraform to store the value in state
for drift detection — exactly what `ephemeral` forbids. Storing it in a
`local` (D) doesn't create an ephemeral context either. A root-module
ephemeral output (E) is specifically disallowed — ephemeral outputs are
restricted to child modules, since a root module's outputs are the
final result of `apply` with nothing downstream to honor the guarantee.

</details>

---

**Q11. (Multiple Choice)** Which type constraint correctly describes a
value where every key must be present, is known in advance, and
different keys may hold different value types?

- A) `map(string)`
- B) `list(any)`
- C) `object({ name = string, count = number })`
- D) `set(string)`

<details>
<summary>Answer</summary>

**C.** `object({...})` is exactly this: a fixed, known set of named
fields, each independently typed. `map(type)` (A) requires all values
to share the same type and allows arbitrary/dynamic keys. `list` (B)
and `set` (D) are both homogeneous, ordered/unordered collections —
neither has named fields at all.

</details>

---

**Q12. (Multiple Choice)** Which argument is **required** when
declaring an `aws_iam_role` resource?

- A) `tags`
- B) `assume_role_policy`
- C) `max_session_duration`
- D) `path`

<details>
<summary>Answer</summary>

**B.** `assume_role_policy` — the JSON trust policy defining who is
allowed to assume the role — is the only required argument.
`max_session_duration`, `path`, and `tags` are all optional, each with
sensible defaults (`3600`, `"/"`, and none, respectively).

</details>

---

**Q13. (Multiple Choice)** A `validation` block is written as
`condition = "prod"` — a string literal instead of a boolean expression.
What happens?

- A) Passes — any non-empty string is treated as truthy
- B) Terraform raises an error at `terraform validate` — a `condition` must evaluate to a boolean
- C) The validation block is silently ignored
- D) It only errors at `apply` time, not at `validate`

<details>
<summary>Answer</summary>

**B.** A `validation` block's `condition` must evaluate to `true` or
`false` — nothing else is valid, and `terraform validate` catches this
immediately. Terraform has no "truthy string" concept the way some
scripting languages do; a condition has to be a genuine boolean
expression, not just a non-empty value.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 12-13/13 | Import Anki cards, move to Demo 06 |
| 10-11/13 | Review the wrong answers, then proceed |
| 8-9/13 | Re-read the relevant sections, retry those questions |
| Below 8/13 | Re-read the full demo and redo the walkthrough before proceeding |
