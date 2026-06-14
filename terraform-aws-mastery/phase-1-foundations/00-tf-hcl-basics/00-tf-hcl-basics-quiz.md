# Quiz — Demo 00: IaC & HCL Foundations

> TA-004 exam style. One correct answer unless stated otherwise.
> Target: 80% or above before moving to Demo 01.

---

**Q1.** You run `terraform apply` on a configuration that already matches
current infrastructure. What does Terraform do?

- A) Destroys and recreates all resources to ensure consistency
- B) Skips apply and shows an error saying nothing to do
- C) Shows a plan of 0 to add, 0 to change, 0 to destroy and makes no API calls
- D) Refreshes state and updates the lock file

<details>
<summary>Answer</summary>

**C** — Terraform compares desired state (.tf files) against current state
(.tfstate), finds no diff, does nothing. This is idempotency.

Trap: D is wrong — apply does refresh state during planning, but does NOT
update the lock file. The lock file only changes on terraform init or
terraform init -upgrade.

</details>

---

**Q2.** Which file should always be committed to version control?

- A) terraform.tfstate
- B) .terraform/
- C) terraform.tfvars
- D) .terraform.lock.hcl

<details>
<summary>Answer</summary>

**D** — Records exact provider versions and SHA256 hashes.
A: Never — may contain sensitive values in plain text.
B: Never — binary plugin files, hundreds of MB, reproduced by init.
C: Generally not — commit only .tfvars.example with placeholder values.

</details>

---

**Q3.** What is the correct HCL syntax for a boolean false value?

- A) False
- B) "false"
- C) false
- D) FALSE

<details>
<summary>Answer</summary>

**C** — HCL booleans are always lowercase: true and false.
False, TRUE, FALSE are all invalid. "false" is a string, not a bool.

</details>

---

**Q4.** A team member creates an S3 bucket manually in the AWS Console.
Another engineer runs terraform apply on a config that does NOT include
that bucket. What happens to the manually created bucket?

- A) Terraform imports it automatically into state
- B) Terraform ignores it — only manages what is in .tf files and state
- C) Terraform destroys it to reconcile state
- D) Terraform shows an error and stops

<details>
<summary>Answer</summary>

**B** — Terraform only manages resources it knows about (those in state).
A manually created resource outside Terraform is invisible to it.
Terraform neither imports nor destroys it.

Key distinction: this differs from drift. Drift = a Terraform-managed
resource changed outside Terraform. An unmanaged resource simply coexists.

</details>

---

**Q5.** What is the most accurate difference between variable and locals?

- A) Variables are for strings only; locals support all types
- B) Variables accept external input; locals are computed internally
- C) Locals are deprecated in favour of variables with default values
- D) They are identical — locals is just an alias for variable

<details>
<summary>Answer</summary>

**B** — variable accepts input from outside (tfvars, CLI, env vars, defaults).
Reference: var.name. locals are computed inside the config — no external
input. Reference: local.name (singular, block is locals plural).

</details>

---

**Q6.** Which command checks .tf syntax and argument names against the
provider schema, but makes zero API calls?

- A) terraform plan
- B) terraform init
- C) terraform validate
- D) terraform fmt

<details>
<summary>Answer</summary>

**C** — terraform validate checks syntax and schema locally. Zero API calls.
A: terraform plan DOES make API calls (Read() on existing resources).
B: terraform init downloads providers but does not validate your config.
D: terraform fmt only reformats whitespace — no validation.

</details>

---

**Q7.** You run terraform plan -out=tfplan, then edit main.tf, then run
terraform apply tfplan. Which config does Terraform apply?

- A) The current main.tf — apply always re-reads config files
- B) The saved plan — apply uses the snapshot from when plan ran
- C) Neither — Terraform detects the mismatch and asks which to use
- D) Terraform merges the saved plan with the current config changes

<details>
<summary>Answer</summary>

**B** — A saved plan is a binary snapshot. terraform apply tfplan executes
that snapshot — does NOT re-read .tf files. Your edits are silently ignored.

In CI/CD this is a feature: plan on PR, apply exactly what was reviewed.
In development: always re-plan if you edit files after planning.

</details>

---

**Q8.** In required_providers, what is "aws" in: aws = { source = "hashicorp/aws" }?

- A) The provider type — must match the AWS service name
- B) The local name assigned to this provider — used to reference it elsewhere
- C) The registry namespace — equivalent to hashicorp
- D) A required argument name defined by the Terraform specification

<details>
<summary>Answer</summary>

**B** — aws is the local name you assign to this provider. It must match
the last segment of the source path by convention, but you could name it
anything. Resource types prefixed with aws_ map to the provider with
local name aws.

</details>

---

**Q9.** What does <<-EOT do differently from <<EOT in HCL?

- A) Disables string interpolation inside the heredoc
- B) Finds the least-indented line and strips that many spaces from all lines
- C) For single-line strings only; <<EOT is for multi-line
- D) They are identical — the dash has no effect in HCL

<details>
<summary>Answer</summary>

**B** — <<-EOT finds the line with least leading whitespace and strips that
many spaces from all lines. Closing EOT can be indented freely. <<EOT
preserves all whitespace — closing EOT must be at column zero.

</details>

---

**Q10.** Which correctly references an attribute of a random_string resource named suffix?

- A) random.suffix.result
- B) random_string.suffix.id
- C) random_string.suffix.result
- D) var.random_string.suffix

<details>
<summary>Answer</summary>

**C** — Format: resource_type.local_name.attribute → random_string.suffix.result
A: random is the provider name, not the resource type.
B: .id exists but .result is the generated string value.
D: var. prefix is for input variables only.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 10/10 | Proceed to Demo 01 |
| 8-9/10 | Review wrong answers in Anki, then proceed |
| 6-7/10 | Re-read relevant README sections, retry |
| Below 6/10 | Re-read Demo 00 before proceeding |
