# Quiz — Demo 20: ACM + Route53 Module

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 21.

---

**Q1. (Multiple Choice)** `data "aws_route53_zone" { name =
"rselvantech.con." }` (typo) is used in Break-Fix. What happens at
`apply`?

- A) Terraform silently falls back to the closest matching zone
- B) AWS reports no matching hosted zone found, since no zone with that exact name exists
- C) `terraform validate` catches this before `apply` even runs
- D) The lookup succeeds, but `zone_id` comes back empty

<details>
<summary>Answer</summary>

**B.** A typo'd zone name simply doesn't match anything real —
there's no fuzzy matching or silent fallback, and this is a real
lookup against AWS, not something `validate`'s syntax-only checks
would catch.

</details>

---

**Q2. (Multiple Choice)** This demo requests and validates a real
certificate three demos before Demo 22's ALB exists to actually use
it. Why does that work at all — what is DNS validation actually
dependent on?

- A) It requires an ALB or load balancer to already exist as the validation target
- B) It only depends on proving domain ownership via a DNS record — nothing about compute, an ALB, or any other downstream consumer
- C) It requires at least a placeholder EC2 instance running in the account
- D) It depends on Route53 health checks being configured first

<details>
<summary>Answer</summary>

**B.** Certificate validation is entirely independent of whatever will
eventually use the certificate — it only proves domain ownership via
DNS. That independence is exactly why this demo can prove out the
technique three demos early, on a disposable certificate, with nothing
else needing to exist first.

</details>

---

**Q3. (True/False)** `dig +short tf-mastery.rselvantech.com` returning
nothing at all, versus returning `rselvantech.com`, both indicate the
placeholder record was created successfully.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Only a real resolution result confirms success — that's
the entire point of building a *resolvable* placeholder rather than
leaving the subdomain absent. An empty `dig` result means something
didn't work as intended.

</details>

---

**Q4. (Multiple Choice)** Break-Fix sets `validation_method = "DSN"`.
Which statement correctly reflects what this demo says about how that
error surfaces?

- A) It's confirmed to always fail at `terraform plan`, before any AWS API call
- B) It's confirmed to always fail at `apply`, after AWS rejects the request
- C) The demo explicitly flags the exact stage (plan vs. apply) as unconfirmed and recommends checking with a real `terraform plan`
- D) It never produces an error — `"DSN"` is silently treated as `"DNS"`

<details>
<summary>Answer</summary>

**C.** This demo is explicit that whether the AWS provider enforces
`validation_method` as a client-side enum (making it a `plan`-time
error) or only via API rejection at `apply` isn't confirmed — the
honest answer is "check it yourself," not a confident guess either
way.

</details>

---

**Q5. (Multiple Choice)** This demo's `data "aws_route53_zone"` block
uses `name = "rselvantech.com."` — with a trailing dot. What would
most likely happen if the trailing dot were omitted?

- A) The lookup would fail outright, since Route53 requires the exact fully-qualified form with no exceptions
- B) It would likely still work, since AWS normalizes zone names internally, but matching the stored fully-qualified form is the more precise habit
- C) It would silently look up a completely different zone
- D) Terraform would refuse to validate the configuration at all

<details>
<summary>Answer</summary>

**B.** Route53 stores zone names in fully-qualified form internally,
but AWS's own normalization usually tolerates the missing trailing
dot — matching the stored form exactly is the more precise habit, not
a hard requirement enforced by a validation failure.

</details>

---

**Q6. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements correctly distinguish this demo's certificate request from
a hypothetical email-validated one?

- A) DNS validation requires a human to click a link sent to an address at the domain
- B) DNS validation requires only a DNS record, which Terraform itself can create
- C) Email validation can be fully completed inside an unattended `terraform apply`
- D) DNS validation is the standard choice for automated, infrastructure-as-code pipelines

<details>
<summary>Answer</summary>

**B and D.** DNS validation needs only a record Terraform can create
itself, making it the standard automated-pipeline choice. **A**
describes email validation, not DNS (reversed). **C** is false — email
validation is exactly what an unattended `apply` cannot complete.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 5-6/6 | Import Anki cards, move to Demo 21 |
| 4/6 | Review the wrong answers, then proceed |
| 3/6 | Re-read the relevant sections, retry those questions |
| Below 3/6 | Re-read the full demo and redo the walkthrough before proceeding |
