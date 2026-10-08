# Quiz — Demo 17: Three-Tier Modules

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 18.

---

**Q1. (Multiple Choice)** `output "web_sg_id" { value =
module.tier_sg.id }` fails once `for_each` is added to
the `tier_sg` module block. What's the fix?

- A) Add `depends_on = [module.tier_sg]`
- B) Add the specific instance key: `module.tier_sg["web"].id`
- C) Re-run `terraform init` — the reference will then resolve
- D) Remove `for_each` from the module block entirely

<details>
<summary>Answer</summary>

**B.** Once a module has `for_each`, its local name becomes a map of
instances — referencing it with no key is invalid. **D** would "fix"
it by removing the very feature the demo is teaching.

</details>

---

**Q2. (Multiple Choice)** Break-Fix's `broken.tf` has `each.valeu.port`
(typo) inside the `tier_sg` module's `ingress_rules`. What error
class does this produce?

- A) `Invalid for_each argument`
- B) `Unsupported attribute`, since `each` only ever exposes `key` and `value`
- C) `Missing required argument`
- D) A silent fallback to `each.value.port` with no error at all

<details>
<summary>Answer</summary>

**B.** `each` has exactly two attributes, `key` and `value` — `valeu`
doesn't exist, so this is an attribute-reference error, not a
missing-argument or `for_each`-shape problem.

</details>

---

**Q3. (Multiple Choice)** `local.tiers` only defines `web` and `app`.
A separate output references `module.tier_sg["db"].id`.
What happens?

- A) Terraform creates a `db` instance automatically to satisfy the reference
- B) An error, since `"db"` isn't a key in the map driving `for_each`
- C) The output silently returns `null`
- D) `terraform plan` succeeds; only `apply` fails

<details>
<summary>Answer</summary>

**B.** A `for_each`'d module only has instances for the keys actually
present in the driving map — referencing a key that was never in
`local.tiers` is an error, not something that auto-creates the
missing instance or resolves to `null`.

</details>

---

**Q4. (Multiple Choice)** This demo's `ingress_rules.tier_access` sets
both `from_port` and `to_port` explicitly to the same value
(`each.value.port`). Per the security-group module's own current
documented behavior, what would happen if only `from_port` were
supplied?

- A) Terraform would error, since both are always required
- B) `to_port` would default to the same value as `from_port` automatically
- C) The rule would default to covering all ports (0–65535)
- D) `to_port` would default to `from_port + 1`

<details>
<summary>Answer</summary>

**B.** The module's current (`~> 6.0`) behavior symmetrically defaults
whichever of `from_port`/`to_port` is omitted to match the one that
was supplied — this demo sets both explicitly, but doesn't strictly
need to for a single-port rule like this one.

</details>

---

**Q5. (True/False)** Because `module.vpc.vpc_id` is passed as
`vpc_id` into every `tier_sg` instance, all three security groups will
be created only after the VPC module completes.

- A) True
- B) False

<details>
<summary>Answer</summary>

**A) True.** All three `tier_sg` instances genuinely depend on
`module.vpc.vpc_id`, so Terraform correctly sequences the VPC's
creation first — parallelism applies *among* the three `tier_sg`
instances (since they don't depend on each other), not between them
and the VPC they all reference.

</details>

---

**Q6. (Multiple Choice)** Which of the following is this demo's actual
security-group input shape for describing allowed traffic, confirmed
against the module's current live documentation?

- A) A flat list of port numbers, e.g. `ports = [443, 8080, 5432]`
- B) A keyed map of rule objects, e.g. `ingress_rules = { tier_access = { from_port = ..., ip_protocol = ..., cidr_ipv4 = ... } }`
- C) A single `cidr_block` string argument on the module itself
- D) Individual `aws_security_group_rule` resources written by hand inside this demo

<details>
<summary>Answer</summary>

**B.** This is exactly the shape used in `security-groups.tf` — a
keyed map, where the key is an arbitrary label and the value is a rule
object — confirmed current for the `~> 6.0` line against the module's
live Registry and GitHub documentation.

</details>

---

**Q7. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements correctly describe why this demo scopes each tier's
ingress to a CIDR block rather than chaining security groups
tier-to-tier?

- A) SG-to-SG chaining isn't possible in AWS at all
- B) CIDR-scoping is simpler and keeps the demo focused on the `for_each`-on-modules mechanic
- C) Chaining would require one `for_each` instance's config to reference a specific sibling instance's output — a materially more complex dependency
- D) CIDR-scoping is what CloudNova would actually run in production

<details>
<summary>Answer</summary>

**B and C.** The demo is explicit that this is a deliberate
simplification for teaching clarity, not a production recommendation
— ruling out **D**. SG-to-SG chaining is a real, supported AWS/
Terraform pattern (via `referenced_security_group_id`), ruling out
**A**.

</details>

---

**Q8. (Multiple Choice)** A teammate wants exactly one NAT Gateway
cost avoided in this demo, matching Demo 16's warning about real
billing. What setting in this demo's VPC module call accomplishes
that?

- A) `single_nat_gateway = true`
- B) `enable_nat_gateway = false`
- C) Omitting the VPC module entirely
- D) `nat_gateway_cost = 0`

<details>
<summary>Answer</summary>

**B.** This demo explicitly sets `enable_nat_gateway = false` when
reusing Demo 16's VPC module — that's what keeps this demo's Cost &
Free Tier table at $0.00, in direct contrast to Demo 16's NAT-driven
cost.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 7-8/8 | Import Anki cards, move to Demo 18 |
| 6/8 | Review the wrong answers, then proceed |
| 4-5/8 | Re-read the relevant sections, retry those questions |
| Below 4/8 | Re-read the full demo and redo the walkthrough before proceeding |
