# Quiz — Demo 03: Core Workflow Deep-Dive: Plan Flags, Graph, and Debug Logging

Test your understanding of this demo's concepts. Each question is a
scenario — choose the best answer, then check yourself against the
explanation.

---

**Q1.** You run `terraform fmt -check -recursive` in a project with a
`break-fix/` subdirectory and it exits `0`. What does this confirm?

A. All `.tf` files in the project, including `break-fix/`, are already
   in canonical format
B. Only the current directory's `.tf` files are formatted — `break-fix/`
   wasn't checked
C. The configuration is valid and ready to apply
D. No provider credentials are configured

<details>
<summary>Answer</summary>

**A.** `-recursive` checks `.tf` files in the current directory AND all
subdirectories, including `break-fix/`. Exit code `0` with `-check` means
nothing would be reformatted anywhere in scope. (B describes the result
WITHOUT `-recursive`. C and D are unrelated — `fmt` doesn't validate
configuration or check credentials.)

</details>

---

**Q2.** A queue policy's `Condition` block references an SNS topic ARN
from a different AWS account than the one actually deploying this
configuration. What is the EARLIEST point this would be detected?

A. `terraform validate`
B. `terraform plan` (refresh step)
C. `terraform apply` — but only if you inspect the deployed policy
   afterward (e.g. via `TF_LOG=DEBUG`)
D. Never — Terraform has no way to detect this

<details>
<summary>Answer</summary>

**C.** `validate` (A) checks internal consistency only — a well-formed
ARN string for a different account is still a valid string. `plan`'s
refresh (B) checks current resource state but wouldn't flag a policy
value as "wrong" — it's syntactically valid IAM policy. `apply` (C)
will succeed (the API call to set the policy succeeds), but the RESULT
is wrong — only inspecting the deployed policy (e.g. comparing
`terraform output topic_arn` against the debug log's view of the actual
policy) reveals the mismatch. D is incorrect — it CAN be detected, just
not automatically by Terraform's own success/failure reporting.

</details>

---

**Q3.** You run:

```bash
terraform plan -out=tfplan
# (1 hour passes — a teammate merges an unrelated .tf change)
terraform apply tfplan
```

What happens?

A. `apply tfplan` silently applies the original plan, ignoring the new
   change
B. `apply tfplan` silently incorporates the teammate's new change
   automatically
C. `apply tfplan` fails — the saved plan no longer matches current
   config/state
D. `apply tfplan` prompts you to choose which version to apply

<details>
<summary>Answer</summary>

**C.** `apply tfplan` requires the saved plan to still match current
configuration and state. If either has changed since the plan was saved
(here, the teammate's merge changed the configuration), Terraform detects
the mismatch and refuses to apply — it does not silently apply a stale
plan (A) or merge in new changes (B), and there's no interactive prompt
(D) since saved-plan applies are designed for non-interactive/CI use.

</details>

---

**Q4.** A configuration has 2 resources with pending changes: Resource A
(SQS queue) and Resource B (SNS topic), with no dependency between them.
You run `terraform apply -target=aws_sqs_queue.notifications` (Resource
A) and it completes successfully. What is the state of Resource B's
pending change?

A. It was also applied, since both had pending changes
B. It remains unapplied — a follow-up plan/apply is needed
C. It was discarded — the change is lost permanently
D. `-target` automatically applies all resources in the same file

<details>
<summary>Answer</summary>

**B.** `-target` scopes the apply to the named resource AND its
dependencies — since Resource B has no dependency relationship with
Resource A, it's entirely outside the scope of this targeted apply. Its
pending change remains in `.tf` files, unapplied, until a plain
`terraform plan`/`apply` (or a target that includes it) runs. The change
isn't lost (C) — it's just pending, same as before the targeted apply.

</details>

---

**Q5.** Someone manually adds a tag to an SNS topic via the AWS Console.
You run `terraform plan -refresh-only`. What does the output show?

A. Nothing — `-refresh-only` doesn't check tags
B. The tag addition, framed as drift ("changed outside of Terraform"),
   with no proposed action
C. The tag addition, with a proposal to remove it immediately
D. An error, because the topic was modified outside Terraform

<details>
<summary>Answer</summary>

**B.** `-refresh-only` refreshes state from real infrastructure and
reports differences (drift) WITHOUT proposing any changes — the output
is explicitly framed as "Objects have changed outside of Terraform... this
is a refresh-only plan, so Terraform will not take any actions to undo
these changes." A normal `terraform apply` afterward would be what
proposes removing the untracked tag (if not added to `.tf`).

</details>

---

**Q6.** What is the default value of `-parallelism`, and in a
configuration where every resource depends on the previous one (a linear
chain), what effect does changing `-parallelism` from 10 to 2 have on
apply behavior?

A. Default is 10; changing to 2 roughly doubles apply time
B. Default is 5; changing to 2 has no effect
C. Default is 10; changing to 2 has no meaningful effect, since only one
   resource is ever ready to run at a time in a linear chain
D. Default is 10; changing to 2 causes the apply to fail

<details>
<summary>Answer</summary>

**C.** The default is 10. `-parallelism` caps how many INDEPENDENT,
ready-to-run operations can execute concurrently. In a fully linear
dependency chain, only one resource is ever ready at any given moment —
there's nothing to parallelize regardless of the cap, so 10 vs 2 makes no
meaningful difference. It would matter if there were many independent
resources ready simultaneously.

</details>

---

**Q7.** In `terraform graph` output, you see:
`"[root] aws_sns_topic_subscription.queue" -> "[root] aws_sqs_queue_policy.notifications"`
but `aws_sns_topic_subscription.queue`'s arguments (`topic_arn`,
`protocol`, `endpoint`) don't reference the policy resource at all. What
does this edge represent?

A. An error in the graph — this edge shouldn't exist
B. An implicit dependency inferred from a shared variable
C. An explicit dependency added via `depends_on`, expressing an ordering
   requirement with no attribute-reference equivalent
D. A circular dependency that Terraform will fail to resolve

<details>
<summary>Answer</summary>

**C.** Since the subscription's arguments don't reference the policy at
all, this edge can only come from an explicit `depends_on`. It expresses
a real-world ordering requirement (the policy must exist before the
subscription, so SNS has delivery permission from the start) that has no
natural attribute-reference equivalent — similar to Demo 01's S3
`depends_on` case.

</details>

---

**Q8.** You set `TF_LOG=DEBUG TF_LOG_PATH=debug.log` and run `terraform
plan -refresh-only`. The resulting `debug.log` is several thousand lines.
What is the most effective next step to find information about a specific
failing resource, e.g. `aws_sqs_queue_policy.notifications`?

A. Read the entire file from the top
B. Set `TF_LOG=TRACE` instead and try again
C. `grep` the log file for the resource type/relevant API action (e.g.
   `GetQueueAttributes`)
D. Delete the log and re-run without `TF_LOG` — it's too verbose to be
   useful

<details>
<summary>Answer</summary>

**C.** `TF_LOG_PATH` exists specifically so debug output can be searched
rather than scrolled through — `grep` for the resource type or the
specific API action (e.g. `SetQueueAttributes`/`GetQueueAttributes` for
an SQS queue policy) narrows thousands of lines down to the relevant
request/response. Reading from the top (A) is impractical at this scale.
`TRACE` (B) would make the file even larger without first trying `DEBUG`
+ targeted search. Giving up (D) defeats the purpose of debug logging —
the slowness is in the volume, not the usefulness of the content.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 8/8 | Import Anki cards, move to Demo 04 |
| 7/8 | Review the wrong answer, then proceed |
| 6/8 | Re-read the relevant section, retry those questions |
| Below 6/8 | Re-read the full demo and redo the walkthrough before proceeding |
