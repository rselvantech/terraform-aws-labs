# Quiz — Demo 16: VPC Module

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 17.

---

**Q1. (Multiple Choice)** `terraform plan` shows
`public_subnets = ["10.0.1.0/24"]` against `azs = ["us-east-2a",
"us-east-2b"]`. What should you expect?

- A) Terraform silently creates one public subnet and leaves the second AZ with none
- B) An index/length-mismatch error, since these lists must have matching lengths
- C) Terraform duplicates `10.0.1.0/24` into the second AZ automatically
- D) `plan` succeeds; the mismatch only fails at `apply`

<details>
<summary>Answer</summary>

**B.** `azs`, `public_subnets`, and `private_subnets` must all be the
same length — a mismatch surfaces as an index-based error, not a
silent partial deployment.

</details>

---

**Q2. (Multiple Choice)** A private subnet CIDR of `10.5.11.0/24` is
passed alongside a VPC `cidr` of `10.0.0.0/16`. What happens?

- A) Terraform automatically re-parents the subnet under the nearest valid range
- B) AWS rejects it at `apply` with an `InvalidParameterValue`-class error, since the subnet CIDR isn't a subset of the VPC's own range
- C) It's accepted — subnet CIDRs don't need to fall within the VPC's CIDR
- D) `terraform validate` catches this before `plan` even runs

<details>
<summary>Answer</summary>

**B.** Every subnet CIDR must be a genuine subset of the VPC's own
`cidr`. This is an AWS-side rejection at `apply` (a semantic/API-level
error), not something `validate`'s syntax-only checks would catch.

</details>

---

**Q3. (Multiple Choice)** After a correct `apply`, `output
"vpc_identifier" { value = module.vpc.id }` fails with `Unsupported
attribute`. What's the fix?

- A) Add `depends_on = [module.vpc]` to the output
- B) Reference `module.vpc.vpc_id` instead — the module has no bare `id` output
- C) Re-run `terraform init -upgrade`
- D) Add an explicit `count` index: `module.vpc[0].id`

<details>
<summary>Answer</summary>

**B.** This module's documented output is `vpc_id`, not `id` — a
guess-by-analogy mistake, exactly the class of error this series'
registry-module demos repeatedly warn against.

</details>

---

**Q4. (Multiple Choice)** `terraform plan` (after adding
`enable_nat_gateway = true` to an already-applied VPC) shows:
`Plan: 3 to add, 0 to change, 0 to destroy`. What does this tell you?

- A) The entire VPC will be replaced
- B) NAT Gateway resources are purely additive on top of the existing VPC — nothing from the earlier apply is touched
- C) The plan is invalid; enabling NAT Gateway always forces a subnet replacement
- D) This confirms the private subnets themselves will be recreated

<details>
<summary>Answer</summary>

**B.** Adding NAT Gateway support only adds the EIP, the NAT Gateway,
and one new route — nothing about the VPC, subnets, or route tables
created earlier needs to change or be destroyed.

</details>

---

**Q5. (Multiple Choice)** This module's `public_subnets = ["10.0.1.0/24",
"10.0.2.0/24"]` is paired with `azs = ["us-east-2a", "us-east-2b"]`.
How does the module decide which subnet lands in which AZ?

- A) Alphabetically, regardless of list order
- B) By position — the first CIDR in `public_subnets` pairs with the first AZ in `azs`, and so on
- C) Randomly, re-assigned on every apply
- D) By CIDR size, largest subnet to the first AZ

<details>
<summary>Answer</summary>

**B.** The module pairs list entries positionally — the first CIDR in
`public_subnets` lands in the first AZ listed in `azs`, the second
CIDR in the second AZ, and so on. This is also exactly why the two
lists (and `private_subnets`) must stay the same length.

</details>

---

**Q6. (Multiple Choice)** `terraform destroy` on this demo's resources
takes several real minutes and appears to "hang" during NAT Gateway
teardown. What's the correct response?

- A) Cancel and re-run with `-auto-approve` to force it through faster
- B) This is expected — NAT Gateway destruction genuinely takes 1–4 real minutes on AWS's side; wait
- C) This indicates a stuck Terraform state lock that needs manual clearing
- D) NAT Gateways can't be destroyed via Terraform at all — manual Console deletion is required

<details>
<summary>Answer</summary>

**B.** NAT Gateway create/destroy are both genuinely slow, real AWS
operations — not a Terraform bug or a stuck state lock. Cancelling
mid-destroy or resorting to manual Console deletion would only create
drift between state and reality.

</details>

---

**Q7. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements are accurate about this demo's NAT Gateway cost?

- A) It's billed only if a private-subnet resource actually sends traffic through it
- B) It bills hourly simply for existing, regardless of usage
- C) It also incurs a per-GB data-processing charge
- D) It's covered under the same free tier as the VPC/subnets/route tables themselves

<details>
<summary>Answer</summary>

**B and C.** NAT Gateway bills per hour of existence plus per-GB of
data processed — both apply regardless of whether it's actively being
used, and neither is free-tier eligible (ruling out **A** and **D**).

</details>

---

**Q8. (Multiple Choice)** CloudNova's staging VPC needs `enable_nat_gateway
= false`. What's the actual effect on the private subnets created?

- A) They fall back to routing `0.0.0.0/0` through the Internet Gateway instead
- B) They have zero outbound internet route configured at all
- C) The module refuses to create private subnets without a NAT Gateway
- D) A NAT instance (EC2-based) is created instead, as a fallback

<details>
<summary>Answer</summary>

**B.** With NAT Gateway disabled, private subnets simply have no
outbound internet route — not a silent fallback to the Internet
Gateway, and no automatic NAT-instance substitute.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 7-8/8 | Import Anki cards, move to Demo 17 |
| 6/8 | Review the wrong answers, then proceed |
| 4-5/8 | Re-read the relevant sections, retry those questions |
| Below 4/8 | Re-read the full demo and redo the walkthrough before proceeding |
