# Quiz — Demo 18: Workspaces

> Question types: True/False, Multiple Choice (1 answer), Multiple
> Answer (N answers, stated in the question) — matching the real
> TA-004 exam format.
> Target: 80% or above before moving to Phase 3.

---

**Q1. (Multiple Choice)** A teammate writes
`bucket = "cloudnova-demo18-shared"` (a plain, static string) instead
of interpolating `terraform.workspace`, then applies it in `dev` and
later in `staging`. What actually happens?

- A) Both applies succeed; Terraform automatically appends the workspace name
- B) The second `apply` fails, since S3 bucket names are globally unique and both workspaces would target the identical name
- C) The `staging` apply silently overwrites the `dev` bucket's state
- D) Terraform refuses at `plan` time with a workspace-naming validation error

<details>
<summary>Answer</summary>

**B.** With no `terraform.workspace` interpolation, both workspaces
try to create the same literal bucket name — the second `apply` fails
against AWS's global-uniqueness constraint. This is exactly Break-Fix
Error 1's failure mode, and it's a silent design mistake, not a syntax
error `plan` would catch.

</details>

---

**Q2. (Multiple Choice)** You need to confirm which workspace is
currently selected before running a destructive command. Which
command tells you, without side effects?

- A) `terraform workspace new`
- B) `terraform workspace show`
- C) `terraform state list`
- D) `terraform.workspace` (used directly in the shell)

<details>
<summary>Answer</summary>

**B.** `terraform workspace show` prints the active workspace with no
side effects. **A** would create a new (unnamed) workspace, which is
the opposite of a safe read. `terraform.workspace` (**D**) is a
configuration-language reference, not a shell command.

</details>

---

**Q3. (Multiple Choice)** `terraform workspace select qa` fails with
`Workspace "qa" does not exist`. What's the correct fix?

- A) Run `terraform init -upgrade`
- B) Run `terraform workspace new qa` first, then select it (or select an existing workspace instead)
- C) Manually create a `qa.tfstate` file
- D) Add `qa` to `terraform.workspace` in the `.tf` files

<details>
<summary>Answer</summary>

**B.** `select` only switches between workspaces that already exist —
`new` is what creates one. There's no manual state-file trick or
configuration-file edit that substitutes for actually creating the
workspace.

</details>

---

**Q4. (Multiple Choice)** You run `terraform workspace delete dev`
while `dev` still has real, un-destroyed AWS resources tracked in its
state, and a different workspace is currently selected. What happens?

- A) Terraform deletes the workspace successfully; the AWS resources become unmanaged, invisible orphans
- B) Terraform refuses — a workspace must have empty state before it can be deleted, not just be non-active
- C) Terraform automatically runs `destroy` first, then deletes the workspace
- D) The workspace is deleted but silently retains its state file on disk for manual recovery

<details>
<summary>Answer</summary>

**B.** Being non-active isn't sufficient on its own — a workspace also
must have empty state (i.e., already be fully destroyed) before
`delete` will succeed. Terraform doesn't auto-destroy on your behalf,
and it doesn't allow deleting a workspace that still has resources
tracked in it.

</details>

---

**Q5. (True/False)** After running `terraform workspace new dev`
followed immediately by `terraform workspace new staging`, `dev`
remains the currently active workspace.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `workspace new` both creates and switches to the new
workspace in the same step — so after creating `staging` second,
`staging` is the active workspace, not `dev`, exactly as this demo's
own Part A walkthrough shows.

</details>

---

**Q6. (Multiple Choice)** `terraform workspace delete dev` is run while
`dev` is the currently selected workspace. What happens?

- A) It deletes successfully and falls back to `default` automatically
- B) Terraform refuses — a different workspace must be selected first
- C) It deletes the workspace's state file but keeps the name reserved
- D) It silently no-ops

<details>
<summary>Answer</summary>

**B.** Terraform refuses to delete the currently active workspace —
`default` (or any other workspace) must be selected first, exactly as
this demo's own Cleanup section does.

</details>

---

**Q7. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements correctly distinguish a CLI workspace from an HCP Terraform
workspace?

- A) Both features are identical in every respect, aside from the name
- B) The CLI feature isolates state only; it has no remote-run, VCS, or policy capability
- C) HCP Terraform workspaces add remote runs, variables, VCS integration, policy enforcement, and team access
- D) CLI workspaces are strictly a superset of HCP Terraform workspace features

<details>
<summary>Answer</summary>

**B and C.** The two features share exactly the word "workspace" —
the CLI feature is local, state-only, with none of HCP Terraform's
broader capabilities. **A** and **D** both misstate the relationship.

</details>

---

**Q8. (Multiple Choice)** During Break-Fix diagnosis, `terraform
validate` reports an error on `Environment = terraform.workspce`.
What's the correct read of this error?

- A) `workspce` is a reserved word that must be quoted
- B) It's a plain typo — `terraform` only exposes a `workspace` attribute, not `workspce`
- C) `terraform.workspace` can only be used inside `resource` blocks, not `tags`
- D) The `terraform` object doesn't support attribute access at all

<details>
<summary>Answer</summary>

**B.** This is simply a misspelling of `workspace` — the fix is
correcting the typo, not restructuring where the reference is used or
adding quoting.

</details>

---

Score guide:

| Score | Action |
|---|---|
| 7-8/8 | Import Anki cards — Phase 2 complete, move to Phase 3 |
| 6/8 | Review the wrong answers, then proceed |
| 4-5/8 | Re-read the relevant sections, retry those questions |
| Below 4/8 | Re-read the full demo and redo the walkthrough before proceeding |
