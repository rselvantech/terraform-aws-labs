# Quiz — Demo 02: Providers: Configuration, Versioning, and the Lock File

> One correct answer per question unless stated otherwise.
> Target: 80% or above before moving to Demo 05.
> TA-004 exam style.

---

**Q1.** What does `version = "~> 6.47.0"` allow?

- A) Any version greater than or equal to 6.47.0
- B) Only 6.47.x patch versions — blocks 6.48.0 and above
- C) Any 6.x version — blocks 7.0.0
- D) Exactly 6.47.0 only

<details>
<summary>Answer</summary>

**B** — `~> 6.47.0` locks the minor version (6.47) and allows only patch
updates (6.47.1, 6.47.2...). It blocks 6.48.0 which is a minor version bump.
C would be `~> 6.0`. D would be `= 6.47.0`.

</details>

---

**Q2.** Can two provider aliases use different versions of the same provider?

- A) Yes — each alias can have its own version constraint
- B) No — all aliases share one version constraint in required_providers
- C) Yes — but only if they are in different regions
- D) No — aliases are deprecated in AWS provider v6

<details>
<summary>Answer</summary>

**B** — All instances of the same provider including all aliases share one
version constraint. You cannot have aws v6.47 for one alias and v6.46 for
another. One version for the entire provider.

</details>

---

**Q3.** You forget to add `provider = aws.west` to `aws_s3_bucket_versioning`
for a bucket created with `provider = aws.west`. What error do you get?

- A) Invalid provider reference — aws.west not declared
- B) NoSuchBucket — versioning API called against wrong region
- C) ProviderMismatch — resource and its configuration use different providers
- D) No error — Terraform auto-detects the correct provider from the bucket reference

<details>
<summary>Answer</summary>

**B** — Terraform routes the versioning API call to the default provider
(us-east-2). The bucket lives in us-west-2. AWS returns NoSuchBucket —
confusing because the bucket exists, just not where the default provider
is looking. Every configuration resource for an aliased bucket needs the
same provider meta-argument.

</details>

---

**Q4.** An engineer on macOS gets a checksum mismatch error running
`terraform init` on a lock file generated on Linux. What is the fix?

- A) Delete the lock file and run terraform init again
- B) Run terraform init -upgrade on the macOS machine
- C) Run terraform providers lock -platform=darwin_arm64 to add macOS hashes
- D) Change the version constraint to allow the macOS version

<details>
<summary>Answer</summary>

**C** — The lock file has zh: hashes for linux_amd64 only. Adding
darwin_arm64 hashes with `terraform providers lock -platform=darwin_arm64`
fixes the mismatch. A would work but loses the pinned version. B upgrades
the provider which is not necessary. D is not meaningful — version
constraints are not platform-specific.

</details>

---

**Q5.** What does `terraform init -upgrade` do to `.terraform.lock.hcl`?

- A) Deletes it and regenerates from scratch
- B) Re-resolves version constraints and updates to latest allowed version
- C) Adds hashes for additional platforms
- D) Nothing — the lock file is read-only

<details>
<summary>Answer</summary>

**B** — `terraform init -upgrade` re-resolves the version constraints
from `required_providers`, downloads the latest version that satisfies
them, and updates the lock file with the new version and hashes.
Use C (terraform providers lock) for adding platform hashes.

</details>

---

**Q6.** How does Terraform determine which provider manages `aws_s3_bucket`?

- A) By reading the provider argument inside the resource block
- B) By matching the resource type prefix (aws_) to the provider local name (aws)
- C) By checking the provider registry for the resource type
- D) By the order providers are declared in required_providers

<details>
<summary>Answer</summary>

**B** — Resource type prefix maps to provider local name. `aws_s3_bucket`
starts with `aws_` which maps to the provider declared with local name
`aws` in required_providers. The `provider` meta-argument overrides this
for aliased providers.

</details>

---

**Q7.** Which version constraint should a reusable child module use?

- A) `= 6.47.0` — exact pin for reproducibility
- B) `~> 6.47.0` — same as root module
- C) `>= 6.0` — minimum version, let the root module control exact version
- D) No constraint — modules should accept any version

<details>
<summary>Answer</summary>

**C** — Child modules should declare a minimum version they require
(`>= 6.0`) and let the root module control the exact pinned version.
If a child module pins to `~> 6.47.0` and the root module uses `~> 6.46.0`,
they conflict and Terraform cannot resolve a compatible version.

</details>

---

**Q8.** What is the correct format of the `provider` meta-argument?

- A) `provider = "aws.west"`
- B) `provider = aws.west`
- C) `provider = west`
- D) `provider = "west"`

<details>
<summary>Answer</summary>

**B** — `provider = aws.west` with no quotes. Format is
`<provider_local_name>.<alias_name>`. This is a reference expression, not
a string. Quoting it makes it a string literal — Terraform will error.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 03 |
| 7/8 | Review the wrong answer, then proceed |
| 6/8 | Re-read the relevant section, retry those questions |
| Below 6/8 | Re-read the full demo and redo the walkthrough before proceeding |
