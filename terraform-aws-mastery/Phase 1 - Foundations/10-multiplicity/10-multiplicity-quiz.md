# Quiz — Demo 10: Multiplicity — count, for_each, and dynamic

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 11.

---

**Q1. (Multiple Choice)** 4 identical CloudWatch log groups are needed,
none with meaning beyond "one of four." What's the best construct?

- A) `for_each` over a set of 4 arbitrary strings
- B) `count = 4`
- C) Four separate resource blocks
- D) A `dynamic` block

<details>
<summary>Answer</summary>

**B.** Interchangeable instances with no meaningful identity is exactly
`count`'s use case. `for_each` (A) works but adds unnecessary
indirection. `dynamic` (D) repeats nested blocks, not whole resources.

</details>

---

**Q2. (True/False)** `for_each` accepts a `list(string)` variable
directly, with no conversion needed.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `for_each` requires a map or a set — never a plain list,
regardless of whether it has duplicates. A list must be wrapped in
`toset()` first.

</details>

---

**Q3. (Multiple Choice)** `toset(["dev", "dev", "prod"])` is passed to
`for_each`. How many resource instances are created?

- A) 3 — one per list element
- B) 2 — `toset()` silently deduplicates before `for_each` sees it
- C) An error — duplicate values aren't allowed
- D) 1 — only the first element is used

<details>
<summary>Answer</summary()>

**B.** `toset()` collapses duplicates before `for_each` ever runs — the
result has 2 unique values (`"dev"`, `"prod"`), so exactly 2 instances
are created, not 3. This happens silently, with no warning.

</details>

---

**Q4. (True/False)** Inside a `for_each`-driven resource where
`for_each` is a set (via `toset()`), `each.value` is always identical
to `each.key`.

- A) True
- B) False

<details>
<summary>Answer</summary()>

**A) True.** A set has no separate key/value structure — every element
serves as both. This is different from `for_each` over a map, where
`each.key` and `each.value` are genuinely distinct.

</details>

---

**Q5. (Multiple Choice)** `count = 3` on a resource block. What is the
address of the **third** instance?

- A) `resource.name[3]`
- B) `resource.name[2]`
- C) `resource.name[2, 3]`
- D) `resource.name.3`

<details>
<summary>Answer</summary()>

**B.** `count.index` is zero-based — three instances are indexed `[0]`,
`[1]`, `[2]`. This zero-vs-one-indexing confusion is a classic exam
trap.

</details>

---

**Q6. (Multiple Choice)** What is the core structural difference between
`for_each` on a resource block and a `dynamic` block inside a resource?

- A) There is no difference — both create multiple resource instances
- B) `for_each` on a resource creates multiple independent state entries; `dynamic` repeats a nested block within one resource that stays one state entry
- C) `dynamic` blocks require `count`, never `for_each`
- D) `for_each` can only be used inside `dynamic` blocks

<details>
<summary>Answer</summary()>

**B.** This is the demo's central distinction. Both use "for_each" as
an argument name, but at completely different scopes — a whole
resource versus one nested block within a single resource.

</details>

---

**Q7. (True/False)** The `count`+`for_each` mutual-exclusion error is
caught at `terraform apply` time, after AWS API calls have started.

- A) True
- B) False

<details>
<summary>Answer</summary()>

**B) False.** This is caught at `terraform validate`/`plan` time — a
static configuration error detected before any AWS API call is made,
since it's structurally invalid regardless of what any provider says.

</details>

---

**Q8. (Multiple Choice)** A resource block has both `count = 2` and
`for_each = toset(["a","b"])`. What happens?

- A) Terraform creates 2 instances, using `for_each`'s values as names
- B) Terraform creates 4 instances (2 × 2)
- C) `terraform validate` fails — the two are mutually exclusive
- D) `for_each` silently wins and `count` is ignored

<details>
<summary>Answer</summary()>

**C.** No merge, multiplication, or precedence behavior exists between
the two — the configuration is simply rejected outright.

</details>

---

**Q9. (Multiple Choice)** `aws_s3_bucket.env[*].arn`, where `env` is a
`for_each`-driven resource over a 3-entry map. What does this return?

- A) A map of key → arn
- B) A list of the 3 ARNs, in map-iteration order, with no keys attached
- C) A single ARN — the first instance only
- D) An error — splat doesn't work on `for_each` resources

<details>
<summary>Answer</summary()>

**B.** Splat still works on `for_each` resources and still returns a
list — it just isn't keyed by `each.key`. Use a `for` expression
instead if the keys are needed alongside the values.

</details>

---

**Q10. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements accurately describe when to prefer a splat expression over
a full `for` expression?

- A) Splat is strictly more powerful than a `for` expression
- B) A `for` expression can filter and transform; splat cannot do either
- C) Splat always returns results keyed by `each.key`
- D) Splat is the terser choice specifically for "one unmodified attribute from every instance, no filtering needed"
- E) `for` expressions only work on `count`-driven resources

<details>
<summary>Answer</summary()>

**B and D.** A `for` expression is the more powerful, general tool —
splat is just a terse shorthand for the narrow "grab one attribute,
unmodified, from every instance" case. Splat is never keyed (C is
wrong, and contradicts Q9), and `for` expressions work equally well on
`for_each`-driven resources (E is wrong).

</details>

---

**Q11. (Multiple Choice)** A `dynamic "ingress"` block's iterator is
renamed via `iterator = rule`. Which reference is correct inside
`content {}`?

- A) `ingress.value` — the default name always still works
- B) `rule.value` — the renamed iterator must be used
- C) Either works interchangeably
- D) `dynamic.value`

<details>
<summary>Answer</summary()>

**B.** Once renamed, the default label-based name no longer applies —
every reference inside `content {}` must use the new iterator name.
Using the old default after renaming produces an error.

</details>

---

**Q12. (Multiple Choice)** Why does `data "aws_vpc" "default" { default
= true }` fit the `data` vs. `resource` distinction from Demo 08?

- A) It doesn't — VPCs always require a `resource` block
- B) It reads an already-existing VPC without creating or managing it — exactly what `data` blocks are for
- C) `default = true` makes it a special hybrid block type
- D) It's only used for cost calculation, not actual configuration

<details>
<summary>Answer</summary()>

**B.** The security group genuinely needs a real `vpc_id` to attach to,
and the default VPC already exists — reading it via `data` is the
correct choice; there's nothing to create or manage here.

</details>

---

**Q13. (Multiple Choice)** Per the decision framework, what's the right
construct for "CloudNova's single production VPC"?

- A) `count = 1`
- B) `for_each` over a single-entry set
- C) A single resource block, no multiplicity construct at all
- D) A `dynamic` block

<details>
<summary>Answer</summary()>

**C.** Multiplicity constructs exist to eliminate repetition — a
genuine singleton doesn't need `count`, `for_each`, or `dynamic` at
all; a plain resource block is both correct and clearer.

</details>

---

**Q14. (Multiple Choice)** A security group already has a `dynamic
"ingress"` block. Now it also needs a caller-supplied number of egress
rules. What's the right addition?

- A) A second resource block for the egress rules
- B) A second `dynamic "egress"` block on the same resource
- C) Convert the whole resource to use `for_each` instead
- D) Use `count` on the existing resource

<details>
<summary>Answer</summary()>

**B.** Still one resource — the variability is in nested blocks
(ingress AND egress), not whole resources. A second `dynamic` block
for `egress` follows the exact same pattern already used for
`ingress`.

</details>

---

**Q15. (Multiple Choice)** How many `aws_security_group` resources
exist in state after applying one with a `dynamic "ingress"` block
whose `for_each` has 5 entries?

- A) 5 — one per ingress rule
- B) 1 — `dynamic` only generates nested blocks, never separate resources
- C) 6 — the security group plus 5 ingress "resources"
- D) 0 until each rule is individually confirmed

<details>
<summary>Answer</summary()>

**B.** Exactly one security group exists in state regardless of how
many nested `ingress` blocks are generated inside it — this is the
same fact tested from a different angle as Q6/Q14.

</details>

---

**Q16. (Multiple Choice)** CloudNova needs one S3 bucket per AWS region
it operates in, with region names that must stay stable if a region is
added or removed later. Which is correct?

- A) `count`, since it's simpler syntax
- B) `for_each` over a set of region strings — each instance's identity is independent of the others' positions
- C) Either works identically here
- D) A `dynamic` block

<details>
<summary>Answer</summary()>

**B.** This is exactly `for_each`'s use case. `count` (A) risks the
reordering-replacement trap the moment a middle region is removed —
full mechanics of that trap are Demo 11's focus. `dynamic` (D) doesn't
apply — it repeats nested blocks, not whole resources like buckets.

</details>

---

Score guide:

| Score       | Action                                                           |
| ----------- | ---------------------------------------------------------------- |
| 15-16/16    | Import Anki cards, move to Demo 11                               |
| 13-14/16    | Review the wrong answers, then proceed                           |
| 11-12/16    | Re-read the relevant sections, retry those questions             |
| Below 11/16 | Re-read the full demo and redo the walkthrough before proceeding |
