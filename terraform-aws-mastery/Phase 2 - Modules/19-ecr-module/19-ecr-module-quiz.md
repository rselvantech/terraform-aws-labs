# Quiz — Demo 19: ECR Module

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 20.

---

**Q1. (Multiple Choice)** `docker push` returns:
`denied: The image tag 'v1.0.0' already exists in the
'cloudnova-retail-ui' repository and cannot be overwritten because the
repository is immutable.` What's the correct next action?

- A) Re-run the exact same push command — it's a transient error
- B) Push under a new tag, e.g. `v1.0.1`
- C) Set `repository_force_delete = true` and re-apply
- D) Delete the repository and recreate it

<details>
<summary>Answer</summary>

**B.** `IMMUTABLE` blocks overwriting an existing tag by design — the
correct response is a new, distinct tag for the new image, not
forcing the old one out. **C** and **D** solve an unrelated problem
(destroy-time cleanup, not push-time rejection).

</details>

---

**Q2. (Multiple Choice)** `terraform destroy` fails with a
repository-not-empty error on an ECR repository that already has
images pushed to it. What's the fix?

- A) Manually delete every image via the Console first, every time
- B) Set `repository_force_delete = true` on that module call and re-apply before destroying
- C) This repository can never be destroyed via Terraform
- D) Switch `repository_image_tag_mutability` to `MUTABLE`

<details>
<summary>Answer</summary>

**B.** `repository_force_delete = true` is exactly what allows
`destroy` to remove a non-empty repository. **A** works but isn't the
Terraform-native fix this demo teaches. **D** is unrelated — mutability
governs pushes, not deletion.

</details>

---

**Q3. (Multiple Choice)** Break-Fix's lifecycle policy rule has a
`selection` block but no `action` block. What happens at `apply`?

- A) AWS defaults to an "expire" action automatically
- B) The rule is silently skipped
- C) AWS rejects the policy document — every rule requires an action
- D) Terraform fills in a default client-side before sending it

<details>
<summary>Answer</summary>

**C.** AWS requires every ECR lifecycle policy rule to include an
`action` — there's no default fallback, silent skip, or
Terraform-side auto-fill.

</details>

---

**Q4. (Multiple Choice)** `repository_image_tag_mutability =
"IMMUTBLE"` (typo) is used in Break-Fix. What error class does this
produce, and at what stage?

- A) A Terraform-side type error at `validate`, since the value isn't a valid enum
- B) An AWS API rejection at `apply`, since `repository_image_tag_mutability` is a plain string Terraform doesn't statically validate
- C) No error — AWS silently falls back to `MUTABLE`
- D) A `terraform init` failure

<details>
<summary>Answer</summary>

**B.** Because this argument is a plain string (not a Terraform-side
enum type), the typo isn't caught until AWS itself rejects it at
`apply`. **A**, **C**, and **D** all describe behavior that doesn't
occur here.

</details>

---

**Q5. (Multiple Choice)** You return to this lab in a later session
and `docker push` suddenly fails with a `no basic auth credentials`
error, even though nothing about the ECR repository or your AWS
credentials has changed. What's the most likely cause?

- A) The repository's lifecycle policy expired your push permissions
- B) The ECR login token from `aws ecr get-login-password` is only valid for 12 hours and needs to be re-run
- C) `IMMUTABLE` tag mutability blocks all pushes after the first session
- D) Docker itself needs to be reinstalled after 12 hours of inactivity

<details>
<summary>Answer</summary>

**B.** The `docker login` token issued by `aws ecr get-login-password`
expires after 12 hours — re-running that authentication step is the
fix, exactly as this demo's own Step 9 callout and Troubleshooting
table both note.

</details>

---

**Q6. (Multiple Choice)** Docker successfully reports `v1.0.0: digest:
sha256:... size: ...` after a push. What has this actually confirmed?

- A) That the image was accepted for upload — not necessarily that it's retrievable
- B) That the image is a real, usable Docker registry endpoint, retrievable by anyone with pull access
- C) Nothing — `docker push` output can't be trusted without a Console check
- D) That the lifecycle policy has already run against this image

<details>
<summary>Answer</summary>

**A.** A successful push confirms upload — this demo deliberately adds
a *separate* step (`docker rmi` then `docker pull` again) specifically
because a push succeeding doesn't by itself prove the image is
genuinely retrievable; that's a distinct thing to verify.

</details>

---

**Q7. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about this demo's `for_each`'d ECR module call are correct?

- A) Each of the 5 repositories can be given a different lifecycle policy directly within this one `for_each` call
- B) Every instance created by this `for_each` call shares the exact same lifecycle policy and mutability setting
- C) A 6th repository needing a different policy requires a second, separate `module` block
- D) `for_each` on this module works differently than `for_each` on Demo 17's security-group module

<details>
<summary>Answer</summary>

**B and C.** A single `for_each` call applies identical argument
values to every instance (ruling out **A**), so a genuinely different
policy needs its own module call. `for_each` mechanics are identical
regardless of which module it's applied to (ruling out **D**).

</details>

---

**Q8. (Multiple Choice)** A real run of this demo logged in
successfully with `docker login` against one registry hostname, then
every `docker push` to a *different*, real repository hostname failed
with `no basic auth credentials`. What actually went wrong?

- A) The IAM permissions were insufficient for push, but sufficient for login
- B) The login command targeted a different registry hostname than the push commands — Docker credentials don't transfer between registries
- C) `IMMUTABLE` tag mutability was blocking every push silently
- D) The Terraform-created repositories were never actually created

<details>
<summary>Answer</summary>

**B.** Docker's credential store is keyed per registry hostname —
authenticating against one hostname provides no credentials for a
different one, even if both are ECR endpoints in the same account.
The fix is deriving the login target from a real output rather than
typing a hostname by hand.

</details>

---

**Q9. (Multiple Choice)** While pushing all 5 services, a learner uses
a single variable, `$REPO`, reassigning it before each service's push.
Partway through, `catalog`'s image ends up tagged and pushed against
`ui`'s repository URL instead. What's the most likely cause?

- A) A bug in the ECR module itself
- B) The variable was reassigned to `catalog`'s URL only after the `docker tag` command had already run using the old, `ui` value
- C) `IMMUTABLE` tag mutability caused the mix-up
- D) `docker push` ignores the tag argument entirely

<details>
<summary>Answer</summary>

**B.** Reusing one variable name across services creates exactly this
risk — if the variable isn't reassigned before every single command
that uses it, a stale value from the previous service silently
carries forward. Giving each service its own uniquely-named variable,
as this demo's Step 10 does, removes the failure mode entirely.

</details>

---

**Q10. (Multiple Choice)** `docker pull public.ecr.aws/aws-containers/retail-store-sample-catalog:latest` fails once with `toomanyrequests: Rate exceeded`, then succeeds immediately on a second, identical attempt. What does this indicate?

- A) The image was corrupted on the first attempt
- B) A transient, anonymous-pull rate limit on the public gallery — not a configuration problem
- C) The ECR repository's lifecycle policy blocked the first pull
- D) Docker needs to be restarted between pull attempts

<details>
<summary>Answer</summary>

**B.** This is a real, transient rate limit on anonymous pulls from
the public gallery, unrelated to anything in this demo's own
configuration — simply retrying resolves it.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 9-10/10 | Import Anki cards, move to Demo 20 |
| 8/10 | Review the wrong answers, then proceed |
| 6-7/10 | Re-read the relevant sections, retry those questions |
| Below 6/10 | Re-read the full demo and redo the walkthrough before proceeding |
