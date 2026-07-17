# Quiz — Demo 00: IaC & HCL Foundations

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 01.

---

**Q1. (Multiple Choice)** You run `terraform apply` on a configuration
that already matches current infrastructure. What happens?

- A) Destroys and recreates all resources to ensure consistency
- B) Skips apply and shows an error saying nothing to do
- C) Shows a plan of `0 to add, 0 to change, 0 to destroy` and makes no infrastructure changes
- D) Refreshes state and updates the lock file

<details>
<summary>Answer</summary>

**C.** This is idempotency in action — desired state already matches
current state, so nothing happens. D is a common trap: `apply` does
refresh state during planning, but never updates the lock file — that
only changes on `init` or `init -upgrade`.

</details>

---

**Q2. (Multiple Choice)** Which of these three files should always be
committed to version control?

- A) `terraform.tfstate`
- B) `.terraform/`
- C) `.terraform.lock.hcl`
- D) None of them — all three are generated and should be gitignored

<details>
<summary>Answer</summary>

**C.** Records exact provider versions and SHA256 hashes — needed for
team reproducibility. `terraform.tfstate` (A) can contain sensitive
values in plaintext. `.terraform/` (B) holds binary plugins, often
hundreds of MB, and is fully reproducible via `init`.

</details>

---

**Q3. (True/False)** `False` (capital F) is valid HCL for a boolean
value.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** HCL booleans are strictly lowercase — `true` and `false`
only. `False`, `TRUE`, `FALSE` are all invalid HCL syntax.

</details>

---

**Q4. (Multiple Choice)** A resource is created manually in the AWS
Console. A separate Terraform configuration — which never declared that
resource — is applied. What happens to the manually created resource?

- A) Terraform automatically imports it into state
- B) Terraform is completely unaware of it — it's neither managed nor affected
- C) Terraform destroys it to reconcile state
- D) `terraform plan` errors, refusing to proceed

<details>
<summary>Answer</summary>

**B.** Terraform only knows about resources present in its own state.
A resource created entirely outside any Terraform configuration simply
coexists, invisible to Terraform — this is different from drift, which
specifically describes a *Terraform-managed* resource changing outside
Terraform.

</details>

---

**Q5. (Multiple Choice)** What is the most accurate distinction between
`variable` and `locals`?

- A) Variables only hold strings; locals can hold any type
- B) Variables accept external input; locals are computed entirely within the configuration
- C) `locals` is a deprecated alias for `variable`
- D) They are functionally identical

<details>
<summary>Answer</summary>

**B.** `variable` accepts input from outside the config (tfvars, CLI
flags, environment variables, or a default). `locals` computes values
purely from what's already inside the configuration — it can reference
variables, resources, and other locals, but accepts no external
override.

</details>

---

**Q6. (True/False)** `terraform validate` makes read-only API calls to
confirm resources referenced in the configuration actually exist.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `validate` checks syntax and schema entirely locally —
zero API calls, no credentials needed. Confirming that a referenced
resource actually exists happens only at `plan` (read-only) or `apply`.

</details>

---

**Q7. (Multiple Choice)** You run `terraform plan -out=tfplan`, then
edit `main.tf`, then run `terraform apply tfplan`. Which version of the
configuration is actually applied?

- A) The current, edited `main.tf` — apply always re-reads config
- B) The saved plan from before your edit — your changes are silently ignored
- C) Terraform detects the mismatch and asks which version to use
- D) Terraform merges the saved plan with your new edits automatically

<details>
<summary>Answer</summary>

**B.** A saved plan is a binary snapshot taken at plan time.
`apply tfplan` executes exactly that snapshot without re-reading `.tf`
files — this is intentional, and is what makes saved plans safe for
CI/CD approval gates (plan reviewed → exactly that plan applied, no
surprise substitution).

</details>

---

**Q8. (Multiple Choice)** In `required_providers { aws = { source =
"hashicorp/aws" } }`, what does `aws` (the key) represent?

- A) The provider type, which must exactly match the AWS service name
- B) The local name assigned to this provider — referenced elsewhere via this name
- C) The registry namespace
- D) A reserved keyword required by the Terraform language specification

<details>
<summary>Answer</summary>

**B.** `aws` is a local name you're choosing — by convention it matches
the source's last segment, but it isn't required to. Resource types
prefixed `aws_` map to whichever local name was assigned here, not to a
hardcoded string.

</details>

---

**Q9. (Multiple Choice)** What does `<<-EOT` do differently from
`<<EOT` in an HCL heredoc?

- A) Disables string interpolation entirely
- B) Finds the least-indented line and strips that many leading spaces from every line, allowing the closing marker to be indented
- C) Restricts the heredoc to single-line content only
- D) Has no effect — the dash is purely cosmetic in HCL

<details>
<summary>Answer</summary>

**B.** `<<-EOT` strips leading spaces (unlike bash's `<<-`, which only
strips tabs) based on the least-indented line — usually the closing
marker. `<<EOT` preserves everything exactly and forces the closing
marker to column 0.

</details>

---

**Q10. (Multiple Choice)** Which correctly references the `result`
attribute of `resource "random_string" "suffix" { ... }`?

- A) `random.suffix.result`
- B) `random_string.suffix.id`
- C) `random_string.suffix.result`
- D) `var.random_string.suffix`

<details>
<summary>Answer</summary>

**C.** Format: `<resource_type>.<local_name>.<attribute>`. `random` (A)
is the provider name, not the resource type. `.id` (B) exists but isn't
the generated string value. `var.` (D) is exclusively for input
variables.

</details>

---

**Q11. (Multiple Answer — Pick the 2 correct responses)** Which TWO are
among the four specific failure modes of manual, Console-only
infrastructure management?

- A) High AWS bill
- B) Drift — environments silently diverge over time
- C) Slow API response times
- D) No audit trail — no record of who changed what and when
- E) Too many IAM permissions granted

<details>
<summary>Answer</summary>

**B and D.** The four failure modes are drift, no audit trail, not
repeatable, and bus factor. Cost (A), performance (C), and permissions
scope (E) aren't among them — those are separate operational concerns,
not consequences of the Console-only workflow itself.

</details>

---

**Q12. (True/False)** An imperative script that creates a security
group can safely be run twice without any additional logic.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Imperative tools describe *how* to reach a state, step by
step — running the same creation step twice typically errors on the
second run ("already exists") unless the engineer writes their own
existence checks. Declarative tools like Terraform handle this
automatically by comparing desired vs. current state.

</details>

---

**Q13. (Multiple Choice)** Does AWS CloudFormation support managing
infrastructure across multiple cloud providers (AWS, Azure, GCP) in one
workflow?

- A) Yes, identically to Terraform
- B) No — CloudFormation is AWS-only
- C) Yes, but only for Azure, not GCP
- D) Only when combined with AWS CDK

<details>
<summary>Answer</summary>

**B.** CloudFormation is AWS-only by design. Terraform's multi-cloud
scope (3,000+ providers) is a genuine, frequently-tested differentiator
— a common exam trap assumes all major IaC tools are multi-cloud.

</details>

---

**Q14. (Multiple Choice)** What is the practical impact of Terraform's
BUSL 1.1 license (since August 2023) on a DevOps engineer using
Terraform to manage their own company's infrastructure?

- A) They must pay HashiCorp a per-resource licensing fee
- B) None — BUSL only restricts commercial competitors from building competing products on top of Terraform
- C) They can no longer use the `aws` provider
- D) They must switch to OpenTofu within 12 months

<details>
<summary>Answer</summary>

**B.** BUSL restricts *competitors* from embedding/reselling Terraform
in a competing commercial offering — it has no practical effect on
engineers using Terraform to manage their own infrastructure, which is
the vast majority of users.

</details>

---

**Q15. (Multiple Choice)** What is OpenTofu?

- A) A HashiCorp product for enterprise customers only
- B) A Linux Foundation fork of Terraform, license MPL 2.0, HCL-compatible with Terraform
- C) A deprecated predecessor to Terraform
- D) A GUI wrapper around the Terraform CLI

<details>
<summary>Answer</summary>

**B.** OpenTofu was forked by the open-source community under the Linux
Foundation in response to the BUSL license change, using the same HCL
language — configurations are largely interchangeable between the two.
The TA-004 certification is Terraform-specific, not OpenTofu.

</details>

---

**Q16. (Multiple Choice)** In Terraform's three-component architecture,
which component actually makes the HTTPS API calls to a cloud provider
like AWS?

- A) Terraform Core (the CLI binary)
- B) The provider plugin
- C) The state file
- D) The Terraform Registry

<details>
<summary>Answer</summary>

**B.** Terraform Core builds the dependency graph and calculates the
diff, then communicates with the provider plugin via gRPC — it's the
provider plugin that translates resource definitions into actual API
calls to the target service. Core itself never talks to AWS directly.

</details>

---

**Q17. (True/False)** Terraform determines the order resources are
created in strictly by the order they're written in the `.tf` file.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Terraform builds a Directed Acyclic Graph (DAG) from
attribute references in the configuration — file order has no bearing
on execution order. If resource B references resource A's output,
Terraform creates A first regardless of which one appears earlier in
the file.

</details>

---

**Q18. (Multiple Choice)** Which of these is NOT one of the 8 top-level
HCL block types?

- A) `data`
- B) `locals`
- C) `backend`
- D) `module`

<details>
<summary>Answer</summary>

**C.** `backend` is not a top-level block — it's a nested block that
lives *inside* a `terraform {}` block (e.g. `terraform { backend "s3"
{...} }`). The 8 top-level types are `terraform`, `provider`,
`resource`, `variable`, `locals`, `output`, `data`, and `module`.

</details>

---

**Q19. (Multiple Choice)** What does a `data` block do?

- A) Creates new infrastructure, just like a `resource` block
- B) Reads information about existing infrastructure — creates nothing
- C) Declares an input parameter
- D) Only works with the `random` provider

<details>
<summary>Answer</summary>

**B.** `data` sources are read-only lookups — used when you need
information about something that already exists outside the current
configuration (an existing VPC, an AMI ID, the current region), without
Terraform creating or managing its lifecycle.

</details>

---

**Q20. (Multiple Choice)** What is the structural difference between
`map(string)` and `object({ name = string, count = number })`?

- A) They're interchangeable
- B) `map(string)` requires all values to share one type with arbitrary keys; `object({...})` has a fixed, known set of named fields, each independently typed
- C) `object` is deprecated in favor of `map`
- D) `map` supports nested structures; `object` does not

<details>
<summary>Answer</summary>

**B.** `map(type)` = arbitrary/dynamic keys, but every value must match
the same type. `object({...})` = a fixed, known schema where each named
field has its own independent type — ideal for structured config with
mixed types.

</details>

---

**Q21. (Multiple Choice)** Which collection type has no index access
(`var.x[0]` is invalid) and enforces no duplicate values?

- A) `list`
- B) `set`
- C) `map`
- D) `object`

<details>
<summary>Answer</summary>

**B.** `set` is unordered with no duplicates and no index access — use
it when order doesn't matter and uniqueness is required (e.g. security
group IDs). `list` (A) is ordered with index access and allows
duplicates.

</details>

---

**Q22. (Multiple Choice)** In `terraform console`, `keys({ env = "dev",
project = "nova" })` displays its result as `toset([...])`. Does this
mean `keys()` returns a set?

- A) Yes — `keys()` always returns a `set(string)`
- B) No — `keys()` returns `list(string)`; the console renders it as `toset(...)` purely because map keys are inherently unordered and unique, not because the function itself returned a set
- C) It depends on whether the map has more than 2 keys
- D) `toset()` must be called explicitly for this display to appear

<details>
<summary>Answer</summary>

**B.** This is a console rendering quirk, not a change in `keys()`'s
actual return type — `keys()` returns `list(string)`, sorted
lexicographically. The console just displays it wrapped in `toset(...)`
notation because map keys are conceptually unordered/unique.

</details>

---

**Q23. (True/False)** Any filename ending in `.tfvars` (e.g.
`prod.tfvars`) is automatically loaded by `terraform plan`/`apply` with
no extra flags.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Only `terraform.tfvars` (exact name) and any
`*.auto.tfvars` file are auto-loaded. Any other name, like
`prod.tfvars`, requires the explicit `-var-file=prod.tfvars` flag.

</details>

---

**Q24. (Multiple Choice)** What is the current recommended way to force
a resource to be destroyed and recreated on the next apply?

- A) `terraform taint <address>`
- B) `terraform plan -replace=<address>` / `terraform apply -replace=<address>`
- C) Manually delete the resource's entry from `terraform.tfstate`
- D) Change the resource's local name in `.tf`

<details>
<summary>Answer</summary>

**B.** `-replace` is the modern, recommended flag. `terraform taint` (A)
is deprecated since v0.15.2 and removed from documentation. Manually
editing state (C) is unsafe and unnecessary. Renaming the local name (D)
would actually be interpreted as delete-old/create-new, a different
(and messier) outcome than a controlled replace.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 22-24/24 | Import Anki cards, move to Demo 01 |
| 19-21/24 | Review the wrong answers, then proceed |
| 16-18/24 | Re-read the relevant sections, retry those questions |
| Below 16/24 | Re-read the full demo and redo the walkthrough before proceeding |
