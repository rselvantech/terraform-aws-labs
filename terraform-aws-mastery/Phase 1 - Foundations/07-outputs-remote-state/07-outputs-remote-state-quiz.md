# Quiz — Demo 07: Outputs, Sensitivity, and Remote State

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 08.

---

**Q1. (True/False)** `terraform output -json` redacts a `sensitive =
true` output the same way the default `terraform output` display does.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `-json` (and `-raw`) both bypass sensitive redaction and
show the plaintext value. Only the default `terraform output` display
(and `terraform output NAME` without a flag) redact to `(sensitive
value)`.

</details>

---

**Q2. (Multiple Choice)** An output's `value` references a variable
marked `sensitive = true`, but the output has no `sensitive` argument
of its own. What happens?

- A) It works fine — sensitivity is a variable-only concern
- B) `terraform plan` errors — the output must also be marked `sensitive`
- C) It's silently redacted with no error
- D) Terraform prompts to confirm

<details>
<summary>Answer</summary>

**B.** This is an enforced requirement, not a suggestion — any output
referencing something already sensitive must itself carry `sensitive =
true`, or `plan` errors immediately.

</details>

---

**Q3. (True/False)** An `ephemeral = true` output works identically
whether declared in a root module or a child module.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Ephemeral outputs are restricted to child modules only —
declaring one in a root module errors with "Ephemeral outputs not
allowed in root module." A root module's outputs are the final result
of `apply`, with nothing downstream left to honor the guarantee.

</details>

---

**Q4. (Multiple Choice)** What is the most accurate description of what
`data.terraform_remote_state` grants access to?

- A) Full read/write access to the source configuration's resources
- B) The source configuration's `.tf` files directly
- C) Read-only access to the source configuration's outputs, via its state file
- D) The ability to trigger `terraform apply` remotely on the source configuration

<details>
<summary>Answer</summary>

**C.** It's read-only by construction — it reads a state *file*, never
the source configuration's `.tf` files, and grants no ability to modify
or apply the source configuration.

</details>

---

**Q5. (Multiple Choice)** Why is `sensitive = true` on a Terraform
variable insufficient to prevent that value from being written into an
`aws_ssm_parameter` as plaintext `type = "String"`?

- A) `sensitive` isn't a real Terraform argument
- B) `sensitive` only affects Terraform's own terminal/plan display — it enforces nothing about what resource arguments the value flows into
- C) `plan` catches this, but `apply` doesn't
- D) SSM parameters are always encrypted regardless of `type`

<details>
<summary>Answer</summary>

**B.** This applies successfully and silently — neither `plan` nor
`apply` validates what downstream arguments a sensitive value ends up
in. Catching this requires review or inspecting the parameter's actual
`Type` after the fact.

</details>

---

**Q6. (Multiple Choice)** You run `aws ssm get-parameter --name
/path/to/param` on a `SecureString` parameter, without
`--with-decryption`. What do you get back?

- A) The plaintext value, same as always
- B) An error refusing to run
- C) The KMS-encrypted ciphertext
- D) An empty string

<details>
<summary>Answer</summary>

**C.** The command succeeds but returns the raw encrypted value.
`--with-decryption` is required to get the actual plaintext back for a
`SecureString` parameter — a genuinely common first-time mistake.

</details>

---

**Q7. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about `depends_on` on an output block are correct?

- A) It's required on every output that references a resource attribute
- B) Most outputs never need it — referencing a resource attribute already creates an implicit dependency
- C) It's needed only when the `value` expression doesn't already reference what it logically depends on
- D) It marks the output as sensitive
- E) It changes the order outputs are displayed in `terraform output`

<details>
<summary>Answer</summary>

**B and C.** The vast majority of outputs get their dependency for free
through the `value` expression's own resource reference. `depends_on`
exists for the rarer case where the value doesn't reference what it
actually depends on. `sensitive` (D) is a separate, unrelated argument,
and display order (E) isn't affected by `depends_on` at all.

</details>

---

**Q8. (Multiple Choice)** Two Terraform configurations are owned by the
same team. Configuration B needs one value from Configuration A. Which
factor would push you toward SSM Parameter Store instead of
`terraform_remote_state`?

- A) Configuration B is also Terraform
- B) Configuration B's team is comfortable with state-backend read access
- C) A non-Terraform application also needs to read that same value at runtime
- D) The value is a string, not a number

<details>
<summary>Answer</summary>

**C.** This is the clearest signal to prefer SSM — `terraform_remote_state`
only works for a Terraform-to-Terraform read; a non-Terraform runtime
consumer needs something like SSM instead. A and B actually favor
remote state (simpler, no extra resource); the value's type (D) is
irrelevant to this decision.

</details>

---

**Q9. (Multiple Choice)** `data.terraform_remote_state.iam.outputs.role_arn`
is referenced in a new output in the consuming configuration, without
marking that new output `sensitive`, even though `role_arn` was
sensitive in the source configuration. What happens?

- A) Nothing — sensitivity doesn't propagate across configurations
- B) `terraform plan` errors — the redaction requirement propagates through remote state exactly as it would through any other reference
- C) The value is automatically encrypted
- D) Only the source configuration's output stays redacted; the new one displays it in plaintext with no error

<details>
<summary>Answer</summary>

**B.** Sensitivity requirements follow the reference chain — reading a
sensitive value through `terraform_remote_state` and re-exposing it in
a new output still triggers the same enforcement as any other sensitive
reference.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8-9/9 | Import Anki cards, move to Demo 08 |
| 6-7/9 | Review the wrong answers, then proceed |
| 5/9 | Re-read the relevant sections, retry those questions |
| Below 5/9 | Re-read the full demo and redo the walkthrough before proceeding |
