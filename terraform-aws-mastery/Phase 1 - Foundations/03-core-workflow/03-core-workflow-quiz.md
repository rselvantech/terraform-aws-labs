# Quiz — Demo 03: Core Workflow Deep-Dive: Plan Flags, Graph, and Debug Logging

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Demo 04.

---

**Q1. (Multiple Choice)** `terraform fmt -check` on a misformatted file
returns which exit code, and what does that specific code mean?

- A) `1` — an HCL parse error
- B) `2` — a CLI usage error
- C) `3` — valid HCL, but not in canonical format
- D) `127` — command not found

<details>
<summary>Answer</summary>

**C.** `fmt -check` exit codes: `0` = already formatted, `1` = CLI/usage
error, `2` = HCL parse error, `3` = valid HCL but not canonically
formatted — the one CI pipelines should watch for. `-check` never writes
to disk regardless of the result.

</details>

---

**Q2. (True/False)** `terraform fmt -check` (without `-recursive`) on a
project containing a `modules/` subdirectory with misformatted files
will detect and flag those subdirectory files.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Without `-recursive`, `fmt` only checks the current
directory — any subdirectory (like `modules/` or `break-fix/`) is
silently skipped, giving false confidence that the whole project is
formatted when it wasn't actually checked.

</details>

---

**Q3. (True/False)** `terraform validate` makes API calls to the cloud
provider to confirm resources exist and credentials are valid.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `validate` makes zero API calls — it only checks internal
configuration consistency (syntax, references, types, required
arguments). It needs no AWS credentials at all to run.

</details>

---

**Q4. (Multiple Choice)** Which of the following would `terraform
validate` FAIL to catch?

- A) A resource block missing a required argument
- B) A reference to an undeclared variable
- C) A hardcoded VPC ID in a resource argument that doesn't actually exist in the AWS account
- D) An unknown argument name for a given resource type

<details>
<summary>Answer</summary>

**C.** `validate` checks internal consistency only — syntax, references
within the configuration, types, required arguments (A, B, D are all
things it does catch). Whether a specific hardcoded ID actually exists
in the real AWS account is a semantic question that requires an API
call — that only happens at `plan` (read-only) or `apply` time.

</details>

---

**Q5. (Multiple Answer — Pick the 2 correct responses)** Which TWO of
the following commands refresh state from real infrastructure via API
calls by default (unless a flag disables it)?

- A) `terraform fmt`
- B) `terraform plan`
- C) `terraform validate`
- D) `terraform apply`
- E) `terraform graph`

<details>
<summary>Answer</summary>

**B and D.** Both `plan` and `apply` refresh state from real
infrastructure by default — this is exactly what `-refresh=false` exists
to skip. `fmt` (A) and `graph` (E) never touch AWS at all — pure local
operations. `validate` (C) makes zero API calls by design.

</details>

---

**Q6. (Multiple Choice)** `terraform plan -out=tfplan` is run, then an
hour later `terraform apply tfplan` is run — but the configuration
changed in between (a teammate merged an edit). What happens?

- A) `apply tfplan` silently applies the original plan, ignoring the change
- B) `apply tfplan` silently incorporates the new change automatically
- C) `apply tfplan` fails — the saved plan no longer matches current config/state
- D) `apply tfplan` prompts interactively to choose which version to apply

<details>
<summary>Answer</summary>

**C.** This is the entire point of saved plans: `apply tfplan` requires
the plan to still match current configuration and state. Any change
since the plan was saved causes Terraform to detect the mismatch and
refuse — never silently applying a stale plan (A) or absorbing new
changes (B). There's no interactive prompt (D), since saved-plan applies
are designed for non-interactive CI use.

</details>

---

**Q7. (Multiple Choice)** A configuration has two resources with pending
changes and no dependency between them. You run `terraform apply
-target=<resource-A>` and it completes successfully. What happens to
resource B's pending change?

- A) It was also applied, since both had pending changes
- B) It remains unapplied — a follow-up plan/apply is needed to catch it
- C) It is discarded permanently
- D) `-target` automatically applies everything else in the same file

<details>
<summary>Answer</summary>

**B.** `-target` scopes strictly to the named resource and its
dependencies. With no dependency relationship to resource B, it's
entirely outside scope — its change sits pending until a follow-up plain
`plan`/`apply` (or a target that includes it). Nothing is lost (C) or
auto-applied (A, D).

</details>

---

**Q8. (Multiple Choice)** What is `-target` NOT an appropriate
substitute for?

- A) Recovering from a partial apply where one resource failed
- B) Splitting a large, slow-to-plan configuration into smaller, independently-applied configurations
- C) Testing a single resource's configuration in isolation during development
- D) Applying one resource first because other resources depend on it

<details>
<summary>Answer</summary>

**B.** `-target` is documented as a short-term escape hatch for
exceptional situations — recovery (A), isolated testing (C), and
ordering necessity (D) are all legitimate uses. It is explicitly NOT a
substitute for the structural fix to "plans are routinely too large or
slow," which is splitting the configuration into smaller, independently
managed pieces.

</details>

---

**Q9. (Multiple Choice)** A resource has both configuration drift (a
manually-added tag) and a separate pending `.tf` edit. What does plain
`terraform plan` show, versus `terraform plan -refresh-only`?

- A) Both show identical output
- B) Plain `plan` merges both changes into one undifferentiated diff; `-refresh-only` shows only the drift, isolated and labeled
- C) Plain `plan` shows only the drift; `-refresh-only` shows only the config edit
- D) Neither command can show both types of change

<details>
<summary>Answer</summary>

**B.** Plain `plan` refreshes state and then diffs against `.tf` —
drift and pending config changes appear together with no label
distinguishing which is which. `-refresh-only` is the only mode that
isolates drift specifically, explicitly framed as "Objects have changed
outside of Terraform," and shows nothing about pending config edits at
all.

</details>

---

**Q10. (Multiple Choice)** What does `terraform plan -refresh=false`
actually do?

- A) Actively checks AWS for drift and reports only drift
- B) Skips checking AWS entirely, planning purely from the existing state file
- C) Is functionally identical to `-refresh-only`
- D) Forces a fresh full state rebuild before planning

<details>
<summary>Answer</summary>

**B.** `-refresh=false` skips the refresh step — it never asks AWS
anything, planning from whatever the state file already says. This
makes it faster but risks missing real drift if time has passed or
other engineers/automation have touched the same resources. It is the
near-opposite of `-refresh-only` (A describes `-refresh-only`, not this
flag).

</details>

---

**Q11. (Multiple Choice)** What is the default value of `-parallelism`,
and what does it actually control?

- A) Default 5; controls the order resources are created in
- B) Default 10; controls the maximum number of resource operations that can run concurrently
- C) Default 10; controls how many times Terraform retries a failed API call
- D) Default 1; disables all concurrency unless raised

<details>
<summary>Answer</summary>

**B.** Default is 10. It caps how many independent, ready-to-run
operations execute concurrently during `apply` — it never changes
*order* (the dependency graph still determines that), only how much
happens at once.

</details>

---

**Q12. (Multiple Choice)** In a configuration where every resource forms
a single linear dependency chain, what effect does lowering
`-parallelism` from 10 to 2 have?

- A) Roughly doubles apply time
- B) No meaningful effect — only one resource is ever ready to run at a time regardless of the cap
- C) Causes the apply to fail
- D) Forces resources to apply in reverse order

<details>
<summary>Answer</summary>

**B.** In a fully linear chain, there's never more than one resource
simultaneously ready to run — there's nothing to parallelize regardless
of the `-parallelism` value. The flag only matters when multiple
independent resources are ready at the same moment.

</details>

---

**Q13. (Multiple Choice)** When is lowering `-parallelism` below the
default of 10 actually useful?

- A) Never — the default is always optimal
- B) When an AWS API is returning throttling errors because too many concurrent calls are hitting the same service
- C) Only when using the `random` provider
- D) When the configuration has fewer than 10 resources total

<details>
<summary>Answer</summary>

**B.** Lowering parallelism trades apply speed for staying under a
service's rate limits — directly useful when `ThrottlingException` /
`RequestLimitExceeded` errors appear. It has nothing to do with which
providers are used (C) or simple resource count alone (D) — what
matters is how many *independent* resources are ready simultaneously.

</details>

---

**Q14. (True/False)** `terraform graph` requires AWS credentials and
makes API calls to build an accurate dependency graph.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `terraform graph` makes zero API calls and needs no
credentials — it reflects only the dependency graph Terraform computes
internally from the configuration itself, in DOT format.

</details>

---

**Q15. (Multiple Choice)** Resource A's arguments genuinely reference
both Resource B and Resource C, but `terraform graph`'s output shows no
direct edge from A to C — only A → B and B → C. What explains the
missing A → C edge?

- A) A bug in `terraform graph`
- B) Transitive reduction — since A → C is already implied via A → B → B, the direct edge is pruned from the rendered output for readability
- C) A does not actually depend on C
- D) Circular dependency detection removed it

<details>
<summary>Answer</summary>

**B.** `terraform graph` applies a transitive reduction before
rendering — if a dependency is already reachable through another path,
the direct edge is considered redundant and omitted. The dependency
still exists and still governs apply order; it's simply not drawn as a
separate line when a path already implies it.

</details>

---

**Q16. (True/False)** `TF_LOG=TRACE` produces less verbose output than
`TF_LOG=DEBUG`.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** Verbosity order, highest to lowest: `TRACE` > `DEBUG` >
`INFO` > `WARN` > `ERROR`. `TRACE` is the most verbose level, including
full HTTP request/response bodies — even more detail than `DEBUG`.

</details>

---

**Q17. (Multiple Choice)** `terraform apply` reports success, but a
downstream system that depends on a resource's configuration is
behaving incorrectly, with no error anywhere in Terraform's own output.
What is the most direct way to diagnose this?

- A) Run `terraform validate` again
- B) Run `terraform destroy` and reapply from scratch
- C) Enable `TF_LOG=DEBUG` (or `TRACE`) with `TF_LOG_PATH` and inspect the actual request/response bodies sent to and from the provider
- D) Wait — Terraform will eventually detect the issue on its own

<details>
<summary>Answer</summary>

**C.** This is exactly the scenario `TF_LOG` exists for — situations
where everything passes validation, plan, and apply because the
configuration is syntactically and structurally correct, but a value is
semantically wrong. The debug log shows the actual data sent to and
received from the provider, which is ground truth that Terraform's
summary output doesn't fully surface. `validate` (A) can't catch
semantic errors, and there's no passive detection mechanism (D).

</details>

---

**Q18. (Multiple Choice)** An `aws_sqs_queue_policy` resource's
`queue_url` argument and an `aws_sns_topic_subscription`'s `endpoint`
argument (for `protocol = "sqs"`) both need to identify the same SQS
queue. What identifier does each actually expect?

- A) Both expect the queue's ARN
- B) Both expect the queue's URL
- C) `queue_url` expects the URL; `endpoint` expects the ARN
- D) `queue_url` expects the ARN; `endpoint` expects the URL

<details>
<summary>Answer</summary>

**C.** This is a common mixup — each AWS service's API decides which
identifier it expects, and Terraform's arguments simply follow that.
SQS's `SetQueueAttributes` (which `queue_url` feeds into) addresses the
queue by URL. SNS's `Subscribe` API (which `endpoint` feeds into)
identifies endpoints by ARN. Same queue, two different identifier types
depending on which service's API is being called.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 17-18/18 | Import Anki cards, move to Demo 04 |
| 15-16/18 | Review the wrong answers, then proceed |
| 13-14/18 | Re-read the relevant sections, retry those questions |
| Below 13/18 | Re-read the full demo and redo the walkthrough before proceeding |
