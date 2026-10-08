# Quiz — Demo 09: Expressions and Collection Functions

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 10.

---

**Q1. (Multiple Choice)** What syntax distinguishes a map-producing
`for` expression from a list-producing one?

- A) Map-producing uses `()`; list-producing uses `[]`
- B) Map-producing uses `{}` and `=>`; list-producing uses `[]` with no `=>`
- C) There's no syntactic difference — Terraform infers it from context
- D) Map-producing requires wrapping the whole expression in `map()`

<details>
<summary>Answer</summary>

**B.** `{for x in collection : key => value}` produces a map;
`[for x in collection : value]` produces a list. Mixing brackets with
`=>` is a genuine syntax error, not a style variation.

</details>

---

**Q2. (True/False)** A map-producing `for` expression that both reads
the key and computes a new value requires two loop variables — one
variable alone can't access both.

- A) True
- B) False

<details>
<summary>Answer</summary>

**A) True.** `{for name, config in map : name => config.field}` needs
both `name` and `config` bound — a single loop variable iterating a
map only binds to the key.

</details>

---

**Q3. (Multiple Choice)** `{for k, v in map : k => v if v > 10}` — what
happens to entries where `v <= 10`?

- A) They appear with a `null` value
- B) They are excluded from the result entirely
- C) They cause a validation error
- D) They're kept but marked invalid

<details>
<summary>Answer</summary>

**B.** `if` filters — non-matching entries are removed completely, not
transformed into a placeholder value. There's no error and no "else"
branch; this is the only filtering mechanism `for` expressions have.

</details>

---

**Q4. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about the `...` suffix on a map-producing `for` expression
are correct?

- A) Without it, colliding keys cause a hard `Duplicate object key` error
- B) With it, colliding keys are collected into a list under that key
- C) It's required syntax on every map-producing `for` expression
- D) It only works on list-producing `for` expressions
- E) Terraform silently keeps the last-processed value when keys collide, regardless of `...`

<details>
<summary>Answer</summary>

**A and B.** Confirmed directly: omitting `...` when two elements
produce the same key errors immediately —
`Error: Duplicate object key — Two different items produced the key
"critical" in this 'for' expression.` With `...`, every value that
maps to the same key is collected into a list instead of erroring.
It's optional (C is wrong), only meaningful on map-producing
expressions (D is wrong, backwards), and there is no silent
last-write-wins behavior at all, with or without `...` (E is wrong —
this is the key misconception the question tests).

</details>

---

**Q5. (Multiple Choice)** What is the difference between
`lookup(map, "key", default)` and `map["key"]` when `"key"` doesn't
exist?

- A) Both error identically
- B) `map["key"]` errors; `lookup()` returns the supplied default
- C) `lookup()` errors; `map["key"]` returns `null`
- D) Both silently return `null`

<details>
<summary>Answer</summary>

**B.** `lookup()` exists specifically to make a missing key a
non-error, graceful case. Index syntax (`map["key"]`) always errors on
a genuinely missing key — no silent `null` fallback either way.

</details>

---

**Q6. (Multiple Choice)** What does `zipmap(["a","b"], [1,2])` return?

- A) `[["a",1], ["b",2]]`
- B) `{ a = 1, b = 2 }`
- C) `["a","b",1,2]`
- D) An error — `zipmap()` requires matching types

<details>
<summary>Answer</summary>

**B.** `zipmap()` combines a list of keys and a parallel list of values
(same length, same order) into a single map — the inverse of splitting
a map with `keys()`/`values()`.

</details>

---

**Q7. (Multiple Choice)** What does `flatten([["a","b"], ["c"]])` return?

- A) `[["a","b"], ["c"]]` — unchanged
- B) `["a","b","c"]`
- C) `"a,b,c"` as a single string
- D) An error — nesting depths must match

<details>
<summary>Answer</summary>

**B.** `flatten()` collapses one level of list nesting into a single
flat list — commonly needed right after a `for` expression that itself
produces a list per source element.

</details>

---

**Q8. (Multiple Choice)** `for name in var.service_config` — a map —
using only one loop variable. What does `name` refer to?

- A) Both the key and value, combined
- B) Only the key
- C) Only the value
- D) An error — maps always require two loop variables

<details>
<summary>Answer</summary>

**B.** A single loop variable iterating a map always binds to the key
— the value simply isn't accessible without a second loop variable.
This is valid syntax, just possibly not what was intended if the value
was actually needed.

</details>

---

**Q9. (Multiple Choice)** A map-producing `for` expression attempts to
invert `{ auth = 30, billing = 90 }` into `{30 = "auth", 90 = "billing"}`,
written without the `...` suffix. What does this inversion silently
depend on?

- A) That the map has at least two entries
- B) That the original values are unique — if two services shared the same retention value, the inversion would error with a duplicate-key conflict
- C) That the values are strings, not numbers
- D) Nothing — inversion is always safe regardless of duplicate values

<details>
<summary>Answer</summary>

**B.** Inverting a map turns values into keys — if two original values
are identical, they'd collide as the same new key. Without `...`, this
errors immediately (`Duplicate object key`), the same way any other
key collision does — it does not silently drop or overwrite anything.
**D** is wrong for exactly that reason: inversion is only safe when
the original values are genuinely unique.

</details>

---

**Q10. (Multiple Choice)** `resource "aws_cloudwatch_log_group" "service"
{ for_each = var.service_config, name = "/cloudnova/${each.key}", ... }`
— what does `each.key` refer to for the `"billing"` entry?

- A) The entire `service_config` map
- B) The object `{ retention_days = 90, tier = "critical" }`
- C) The string `"billing"`
- D) The number `90`

<details>
<summary>Answer</summary>

**C.** With `for_each` over a map, `each.key` is the map key (the
service name string), and `each.value` is that key's corresponding
value (the object with `retention_days`/`tier`). `each.value.retention_days`
would be `90` — the number in D is accessible, but not via `each.key`.

</details>

---

**Q11. (Multiple Choice)** After applying 3 `for_each`-driven log
groups and 3 `for_each`-driven metric filters together for the first
time, what does `terraform apply` report?

- A) `Resources: 3 added` — only the log groups count
- B) `Resources: 6 added` — both resource types count individually
- C) `Resources: 1 added` — `for_each` collapses into one resource
- D) An error — two `for_each` resources can't reference each other

<details>
<summary>Answer</summary>

**B.** Each `for_each` instance counts individually toward the
resource tally — 3 log groups + 3 metric filters = 6 total, regardless
of how few `resource` blocks were written to produce them. `for_each` fully supports one resource referencing another's instances (D is wrong) — that's exactly how the metric filter's `log_group_name` gets each group's name.

</details>

---

**Q12. (Multiple Choice)** A `for_each`-driven metric filter shows
`Sum: 0` in `get-metric-statistics`, despite confirmed matching log
lines existing in the log group. What's the most likely cause?

- A) The metric filter pattern is always wrong in this scenario
- B) The log events were written before the metric filter existed — filters don't process retroactively
- C) CloudWatch metrics take 24 hours to populate
- D) `for_each` doesn't support metric filters

<details>
<summary>Answer</summary>

**B.** Metric filters only count matching events from their own
creation forward. Given the log lines are confirmed to match, timing
(events written before the filter existed) is the most likely
explanation, not a broken pattern.

</details>

---

**Q13. (True/False)** Terraform provides a dedicated `filter()`
function separate from the `for` expression's `if` clause.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** There is no standalone `filter()` function in HCL — the
`if` clause inside a `for` expression is the *only* collection
filtering mechanism the language provides.

</details>

---

**Q14. (Multiple Choice)** Why might a team choose `for_each` over
`var.service_config` directly (a map) rather than first converting it
with a `for` expression into a differently-shaped map?

- A) `for_each` cannot accept a map at all — it always requires a `for` expression first
- B) When the map's existing keys and values already have exactly the shape needed, no transformation is required before using it
- C) `for_each` only works with lists, never maps
- D) A `for` expression is always mandatory before `for_each`

<details>
<summary>Answer</summary>

**B.** `for_each` accepts a map or set directly — a `for` expression is
only needed when the *existing* shape doesn't already match what's
needed (e.g. deriving `log_group_names` for Part A's purposes). This
demo uses `var.service_config` directly in Part C precisely because
its existing shape (service name → config object) was already exactly
what `for_each` needed.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 13-14/14 | Import Anki cards, move to Demo 10 |
| 11-12/14 | Review the wrong answers, then proceed |
| 9-10/14 | Re-read the relevant sections, retry those questions |
| Below 9/14 | Re-read the full demo and redo the walkthrough before proceeding |
