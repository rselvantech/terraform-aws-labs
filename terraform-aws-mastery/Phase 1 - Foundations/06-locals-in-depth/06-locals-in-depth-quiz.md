# Quiz — Demo 06: Locals in Depth

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 07.

---

**Q1. (Multiple Choice)** What is the correct distinction test for
choosing a `local` over a `variable`?

- A) Locals hold complex types; variables hold only primitives
- B) If the value would ever need external override, it's a variable; if it's always derived internally, it's a local
- C) Locals are evaluated faster
- D) There's no real distinction — use whichever is shorter to type

<details>
<summary>Answer</summary>

**B.** The test is about external overridability, not type or
performance. A local that's just `local.x = var.x` with no
transformation should be a variable instead.

</details>

---

**Q2. (True/False)** A `locals` block supports a `type` argument, just
like a `variable` block does.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Locals have no `type` argument at all — Terraform infers
the type entirely from the assigned expression.

</details>

---

**Q3. (Multiple Choice)** A local is defined as `{ Project = var.project,
Count = 3 }`, where `var.project` is `type = string`. What type does
Terraform infer?

- A) `map(string)`
- B) `map(number)`
- C) `object({ Project = string, Count = number })`
- D) `tuple([string, number])`

<details>
<summary>Answer</summary>

**C.** The two values have different types (string and number), so
Terraform infers `object({...})`, not `map(...)`. A `map` is only
inferred when every value shares the same type.

</details>

---

**Q4. (True/False)** If `local.b` is declared before `local.a` in a
file, but `local.a` references `local.b`, Terraform will error because
`local.b` isn't defined yet when `local.a` is evaluated.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Declaration order in the file has zero effect. Terraform
builds a dependency graph from the references inside each expression
and resolves evaluation order automatically — the same mechanism used
for resources.

</details>

---

**Q5. (Multiple Choice)** `local.a = "prefix-${local.b}"` and
`local.b = "suffix-${local.a}"`. What happens at `terraform plan`?

- A) Terraform picks an arbitrary order and one side gets an empty value
- B) A clear "Cycle in local values" error, before any value is evaluated
- C) Both resolve successfully using empty-string placeholders
- D) Only `local.a` (declared first) is evaluated

<details>
<summary>Answer</summary>

**B.** Circular references are detected at plan time with an explicit
cycle error — never silently resolved or partially evaluated. Fix by
extracting the shared value into a third local neither side references.

</details>

---

**Q6. (Multiple Choice)** What does `coalesce(var.name, "fallback")`
return when `var.name` is set to `""` (empty string)?

- A) `""` — empty string is not null, so it's returned
- B) `"fallback"` — `coalesce()` skips both null and empty string
- C) An error
- D) `null`

<details>
<summary>Answer</summary>

**B.** `coalesce()` treats `""` the same as `null` — both are skipped.
This is a common exam trap: empty string "not technically being null"
doesn't stop `coalesce()` from skipping it.

</details>

---

**Q7. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about `try(expr1, expr2, ...)` are correct?

- A) It returns `true` or `false`
- B) It returns the value of the first argument that evaluates without error
- C) It only errors if every single argument errors
- D) It is functionally identical to `coalesce()`
- E) It requires exactly two arguments

<details>
<summary>Answer</summary>

**B and C.** `try()` returns an actual value (not a boolean — that's
`can()`), and only fails if all provided expressions error. It accepts
any number of arguments (not exactly two), and solves a different
problem than `coalesce()` (errors vs. null/empty values).

</details>

---

**Q8. (Multiple Choice)** What is the key functional difference between
`try()` and `coalesce()`?

- A) They solve the same problem with different syntax
- B) `try()` catches expression evaluation errors; `coalesce()` catches null/empty-string values
- C) `try()` is for numbers only; `coalesce()` is for strings only
- D) `coalesce()` is deprecated in favor of `try()`

<details>
<summary>Answer</summary>

**B.** `try()` is for expressions that might error (e.g. an optional
object attribute that may not exist). `coalesce()` is for values that
might be `null` or `""`. They're often combined:
`coalesce(try(var.config.name, null), local.default)`.

</details>

---

**Q9. (Multiple Choice)** `merge(local.common_tags, var.extra_tags)` —
both have key `"Owner"`. Which value wins?

- A) `local.common_tags`'s value
- B) `var.extra_tags`'s value
- C) Both are kept as a list
- D) An error — duplicate keys aren't allowed

<details>
<summary>Answer</summary>

**B.** `merge()` is right-most-wins on key conflicts. Since
`var.extra_tags` is listed last, its value overrides
`local.common_tags`'s for any shared key.

</details>

---

**Q10. (Multiple Choice)** You want caller-supplied tags to override a
set of base defaults. Which argument order to `merge()` achieves this?

- A) `merge(caller_tags, base_tags)`
- B) `merge(base_tags, caller_tags)`
- C) Either order — `merge()` is commutative
- D) Neither — `merge()` cannot express "caller overrides base"

<details>
<summary>Answer</summary>

**B.** Base defaults go first, caller overrides go last — the
"higher authority" map always goes last in `merge()`. Reversing the
order (A) silently flips precedence with no error, which is exactly
the kind of mistake that's hard to spot without knowing this rule.

</details>

---

**Q11. (Multiple Choice)** Why can `jsonencode()` and `merge()`,
originally used to build an IAM trust policy, be reused unchanged to
build an SNS topic's resource policy?

- A) They can't — each AWS service requires its own policy-building functions
- B) They are general-purpose functions with no awareness of which resource consumes their output
- C) SNS and IAM share the same underlying API
- D) Only because both policies happen to have identical structure

<details>
<summary>Answer</summary>

**B.** `jsonencode()` converts any HCL value to a JSON string; `merge()`
combines any maps. Neither function knows or cares what AWS resource
the result is eventually assigned to — the same composition pattern
applies to any policy document, for any service.

</details>

---

**Q12. (Multiple Choice)** A local is defined as `local.c = { type =
string, value = "test" }`. Does this declare a type constraint on
`local.c`?

- A) Yes — `type` inside any block enforces a constraint
- B) No — `type` here is just an ordinary map key; locals have no type-constraint mechanism at all
- C) Yes, but only for the `value` field
- D) It causes a `terraform validate` error

<details>
<summary>Answer</summary>

**B.** Nothing about `locals` blocks treats `type` as special — it's an
ordinary key in an ordinary map literal here. This is valid HCL that
does nothing resembling a `variable` block's `type` argument, which is
exactly what makes this a subtle trap rather than an obvious syntax error.

</details>

---

**Q13. (True/False)** Unlike `variable` blocks, `locals` blocks can
reference resources and data sources directly.

- A) True
- B) False

<details>
<summary>Answer</summary>

**A) True.** A `local` can reference `data.aws_caller_identity.current.account_id`,
a resource attribute, another local, or a variable — variables can only
reference `var.<themselves>`, and only inside a `validation` block.

</details>

---

**Q14. (Multiple Choice)** Two locals reference `data.aws_caller_identity.current.account_id`
in constructing an ARN string manually. What is a safer alternative
where the target resource is also managed by this same configuration?

- A) There is no safer alternative — manual ARN construction is required
- B) Reference the resource's own `.arn` attribute directly (e.g. `aws_sns_topic.x.arn`) instead of reconstructing it
- C) Hardcode the ARN as a literal string
- D) Use `jsonencode()` to generate the ARN automatically

<details>
<summary>Answer</summary>

**B.** Manually reconstructing an ARN from region/account ID/name risks
drift if any component doesn't match the resource's actual ARN.
Referencing the resource's own `.arn` attribute is always authoritative
and avoids that class of bug entirely.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 13-14/14 | Import Anki cards, move to Demo 07 |
| 11-12/14 | Review the wrong answers, then proceed |
| 9-10/14 | Re-read the relevant sections, retry those questions |
| Below 9/14 | Re-read the full demo and redo the walkthrough before proceeding |
