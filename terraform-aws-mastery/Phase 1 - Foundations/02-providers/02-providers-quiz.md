# Quiz — Demo 02: Providers: Configuration, Versioning, and the Lock File

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 03.

---

**Q1. (Multiple Choice)** Which `provider "aws"` block argument should
never be used in real configurations because it commits credentials
directly into version control?

- A) `default_tags`
- B) `access_key` / `secret_key`
- C) `alias`
- D) `assume_role`

<details>
<summary>Answer</summary>

**B.** Static credentials hardcoded via `access_key`/`secret_key`
get committed to Git the moment the `.tf` file is committed. Use a
named profile (`profile`), environment variables, or `assume_role`
instead — none of which require the secret itself to live in the file.

</details>

---

**Q2. (True/False)** `default_tags` are only applied to a resource if
that resource also declares its own `tags` argument.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `default_tags` are merged automatically into every
resource created by that provider instance, regardless of whether the
resource declares its own `tags` at all. If the resource does set its
own tags, those merge on top and win on any key conflict.

</details>

---

**Q3. (True/False)** Terraform always requires an explicit `provider`
meta-argument on every resource to determine which provider manages it.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** By default, Terraform maps a resource to a provider via
its type prefix — `aws_s3_bucket` maps to the provider with local name
`aws`. The `provider` meta-argument is only needed to override this
default, typically to route a resource to an aliased instance instead.

</details>

---

**Q4. (Multiple Choice)** What does `terraform providers` actually do?

- A) Downloads and installs any providers not yet present
- B) Lists every provider the configuration requires and which resources use each — read-only, installs nothing
- C) Upgrades all providers to their latest version
- D) Generates multi-platform hashes for the lock file

<details>
<summary>Answer</summary>

**B.** `terraform providers` is purely informational — it lists
declared providers, their constraints, and which resources/aliases use
each. It downloads or installs nothing (that's `init`), doesn't upgrade
anything (that's `init -upgrade`), and doesn't touch hashes (that's
`terraform providers lock`).

</details>

---

**Q5. (Multiple Choice)** What is the difference between `~> 6.0` and
`~> 6.47.0` as version constraints?

- A) They are functionally identical
- B) `~> 6.0` allows any 6.x version and blocks 7.0.0; `~> 6.47.0` allows only 6.47.x and blocks 6.48.0
- C) `~> 6.0` is stricter than `~> 6.47.0`
- D) `~> 6.47.0` allows major version updates; `~> 6.0` does not

<details>
<summary>Answer</summary>

**B.** `~> 6.0` locks the major version, allowing any minor/patch within
6.x (6.1.0, 6.47.0, etc.) while blocking 7.0.0. `~> 6.47.0` locks the
minor version, allowing only patch updates within 6.47.x while blocking
6.48.0. `~> 6.47.0` is actually the stricter of the two, not the looser
one.

</details>

---

**Q6. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about version constraint strategy are correct?

- A) Root modules should always use exact pins (`=`) for every provider
- B) Child modules should declare a minimum version (`>= X.0`) and let the root module control the exact version
- C) A child module pinning too tightly (e.g. `~> 6.47.0`) can conflict with a root module using a different minor version (e.g. `~> 6.46.0`)
- D) All provider aliases in the same configuration can use different version constraints
- E) Declaring no version constraint at all is a safe default for root modules

<details>
<summary>Answer</summary>

**B and C.** Child modules declaring a minimum version lets the root
module control the exact resolved version — over-constraining a child
module risks exactly the conflict described in C, where two
incompatible constraints can't both be satisfied and Terraform errors.
A is wrong — exact pins in root modules block legitimate patch updates
unnecessarily; `~> X.Y.0` is the recommended root-module pattern. D is
wrong — all aliases of the same provider share one version constraint.
E is wrong — no constraint means Terraform downloads the latest version
on every fresh `init`, which is the opposite of reproducible.

</details>

---

**Q7. (Multiple Choice)** In `.terraform.lock.hcl`, what is the
relationship between the `version` and `constraints` fields?

- A) They are always identical
- B) `constraints` is what Terraform enforces; `version` is for reference only
- C) `version` is the exact resolved/installed version; `constraints` is a copy of `required_providers`, recorded for reference only
- D) `version` only exists for providers with `alias` blocks

<details>
<summary>Answer</summary>

**C.** `version` is the exact version Terraform resolved and installed
— this is what every engineer's `init` will install. `constraints` is
just a copy of the `required_providers` constraint string, kept for
reference — it's `version` that Terraform actually enforces on
subsequent `init` runs, not `constraints`.

</details>

---

**Q8. (Multiple Choice)** What is the difference between `h1:` and `zh:`
hash entries in the lock file?

- A) `h1:` is deprecated; only `zh:` matters
- B) `h1:` hashes the whole zip archive (platform-independent); `zh:` hashes individual files inside it (platform-specific)
- C) `h1:` is for the `aws` provider only; `zh:` is for all others
- D) They are two different encodings of the same hash

<details>
<summary>Answer</summary>

**B.** `h1:` is a single hash of the entire provider zip archive,
identical across every OS/architecture. `zh:` hashes individual files
inside the zip, which differ per platform (`linux_amd64` vs
`darwin_arm64` vs `windows_amd64`) — this is why a lock file generated
on one OS can be missing the `zh:` entry another OS needs.

</details>

---

**Q9. (True/False)** The GPG signature check and the SHA256 hash check
in the lock file protect against exactly the same risk, making one of
them redundant.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** They protect two different moments. The GPG signature
verifies the *first* download genuinely came from HashiCorp. The SHA256
hashes recorded in the lock file protect *every subsequent* download —
if the registry ever served a different (even validly-signed) binary
later, the hash wouldn't match and `init` would fail. Removing either
layer would leave a real gap the other doesn't cover.

</details>

---

**Q10. (Multiple Choice)** A lock file was generated on Linux. A
teammate on macOS runs `terraform init` and gets a checksum mismatch.
What is the correct fix?

- A) Delete the lock file and let macOS regenerate it from scratch
- B) Run `terraform init -upgrade` on the macOS machine
- C) Run `terraform providers lock -platform=darwin_arm64` to add the missing platform's hashes
- D) Change the version constraint to something looser

<details>
<summary>Answer</summary>

**C.** The lock file only has `zh:` hashes for `linux_amd64`. Adding
`darwin_arm64` hashes fixes it without disturbing the pinned version or
existing platform entries. Deleting the lock file (A) would work but
discards the whole point of a shared, reviewed lock file. `-upgrade` (B)
changes the resolved version unnecessarily — this isn't a version
problem. Loosening the constraint (D) doesn't address platform hashes
at all.

</details>

---

**Q11. (True/False)** `terraform providers lock -platform=...` installs
the specified platform's provider binary into `.terraform/`, ready for
use on that platform.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** It downloads the binary only long enough to compute its
hash and record it in the lock file — it does not install anything into
`.terraform/`. It's purely a lock-file maintenance operation, safe to
run repeatedly, and never removes existing hash entries.

</details>

---

**Q12. (Multiple Choice)** A lock file records `version = "6.47.0"`.
The constraint in `versions.tf` is `~> 6.47.0`, and AWS has since
released `6.47.1`. What does plain `terraform init` install?

- A) `6.47.1` — the latest matching version
- B) `6.47.0` — the version already recorded in the lock file
- C) Whatever is currently latest on the registry, ignoring the lock file
- D) It errors, requiring a manual choice

<details>
<summary>Answer</summary>

**B.** Once a lock file exists, plain `terraform init` always installs
the exact version recorded in the lock file — never a newer version,
even if the constraint would allow it. Only `terraform init -upgrade`
re-resolves the constraint and would pick up `6.47.1`.

</details>

---

**Q13. (Multiple Choice)** After running `terraform init -upgrade`,
what must be committed together as one atomic change?

- A) Only `.terraform.lock.hcl`
- B) Only `versions.tf`
- C) `versions.tf` (if the constraint changed) and `.terraform.lock.hcl` together
- D) `.terraform/` and `.terraform.lock.hcl`

<details>
<summary>Answer</summary>

**C.** These two files describe the same fact from two angles — the
allowed range and the exact resolved version — and should never be
committed out of sync with each other. `.terraform/` (D) is never
committed at all; it's fully reproducible via `init`.

</details>

---

**Q14. (Multiple Choice)** Can two provider aliases of the same provider
type use different version constraints?

- A) Yes, each alias is independent
- B) No — every instance (default and all aliases) shares one version constraint
- C) Yes, but only across different AWS regions
- D) Only in AWS provider v6 and later

<details>
<summary>Answer</summary>

**B.** All instances of a given provider — the default and every alias —
share the single version constraint declared once in `required_providers`.
You cannot pin `aws` to 6.47.0 for one alias and 6.46.0 for another.

</details>

---

**Q15. (Multiple Choice)** What is the correct syntax for assigning a
resource to an aliased provider named `west` on provider `aws`?

- A) `provider = "aws.west"`
- B) `provider = aws.west`
- C) `provider = "west"`
- D) `alias = aws.west`

<details>
<summary>Answer</summary>

**B.** No quotes — `provider = aws.west` is a reference expression, not
a string literal. Quoting it (A, C) makes it a plain string, which
Terraform rejects for this argument. `alias` (D) is an argument used
inside a `provider` block to *name* an instance, not a resource-level
meta-argument for *selecting* one.

</details>

---

**Q16. (Multiple Choice)** A bucket is created successfully with
`provider = aws.west`, but its `aws_s3_bucket_versioning` resource fails
with `NoSuchBucket`, even though the bucket clearly exists in
`us-west-2`. What is the most likely cause?

- A) The bucket name is misspelled in the versioning resource
- B) The versioning resource is missing its own `provider = aws.west` meta-argument, so its API call goes to the default (us-east-2) provider instead
- C) `aws_s3_bucket_versioning` doesn't support provider aliases at all
- D) The bucket's region attribute wasn't set correctly

<details>
<summary>Answer</summary>

**B.** Terraform does not infer a resource's provider from *another*
resource's ID reference — each resource independently determines its
provider, defaulting to the unaliased instance if `provider` isn't set.
The versioning resource ends up calling the API against `us-east-2`,
where no bucket with that name exists.

</details>

---

**Q17. (Multiple Choice)** When is the AWS provider v6 per-resource
`region` argument the better choice over a provider alias?

- A) When the second region needs different credentials or a different IAM role
- B) When many resources need the second region
- C) When only the region differs and credentials are identical
- D) For cross-account access

<details>
<summary>Answer</summary>

**C.** Per-resource `region` is the simpler v6 alternative specifically
when credentials are shared and only the region needs to change on a
resource-by-resource basis. Different credentials/IAM role (A) or
cross-account access (D) still require a full provider alias (with
`assume_role`), and many resources needing the same second region (B)
is better served by setting the region once in an aliased provider
block rather than repeating it on every resource.

</details>

---

**Q18. (Multiple Choice)** What confirms, after `apply`, which provider
instance actually manages a given resource?

- A) The resource's name in `.tf` files
- B) `terraform state show <address>`'s `provider` field
- C) The order resources appear in `terraform plan` output
- D) The AWS Console's resource tags

<details>
<summary>Answer</summary>

**B.** `terraform state show` displays the full provider reference,
e.g. `provider["registry.terraform.io/hashicorp/aws"].west` — this is
the authoritative confirmation of provider routing. The `plan` output's
`region` field (not listed here) is a useful early signal, but state is
the definitive source after apply.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 17-18/18 | Import Anki cards, move to Demo 03 |
| 15-16/18 | Review the wrong answers, then proceed |
| 13-14/18 | Re-read the relevant sections, retry those questions |
| Below 13/18 | Re-read the full demo and redo the walkthrough before proceeding |
