# Demo 23 — EKS: Full Service Mesh

> **Revision note (this version) — per ADR-023/024, pending Track 2
> final sign-off.** This demo's original Governance Note (below,
> otherwise unchanged) fixed four real problems against the
> pre-ADR-023 `phase-3-onward/` layout. This revision adds a fifth
> layer of changes, all mechanical consequences of 22d's own rebuild
> onto `platform/`/`workloads/` — none of them change this demo's
> teaching content, Pass Criteria, or the app-behavior findings
> (ADR-012), only which directory each command targets:
> 1. **Every `-chdir` reference to 22d's old, single
>    `phase-3-onward/` directory now splits across `platform/`
>    (ECR repository URLs, ACM certificate ARN) and `workloads/`
>    (cluster name, `kubeconfig_command`)** — the two values were
>    always logically distinct; they just used to live in one
>    directory.
> 2. **Part A's three-scenario decision tree now checks `workloads/`
>    specifically for rebuild-vs-live**, and only ever confirms
>    `platform/` with a no-op `plan` — it is never rebuilt as part of
>    this demo's own Scenario 2a, consistent with `platform/` never
>    being torn down in the first place.
> 3. **Cleanup drops `-target` entirely.** 22d's own Cleanup no longer
>    needs it (VERIFY 6 is resolved structurally there), and since this
>    demo tears down the identical `workloads/` state 22d does, the
>    same simplification applies here — a plain `terraform destroy` in
>    `workloads/`, full stop.
> 4. **Every VERIFY 6 reference in this demo — the Governance Note's
>    own point 3, the "How This Demo's Pieces Fit Together" section,
>    Part A's decision tree, the Recall Check, Troubleshooting,
>    Interview Prep Q1/Q6, Key Takeaways, and the Anki/quiz content —
>    is updated from "a live risk this demo inherits and must carry
>    forward" to "resolved structurally at 22d; this demo inherits the
>    resolution, not the risk."** VERIFY 6 itself is kept as historical
>    record in each place it's mentioned, per this project's own
>    standard for not silently erasing a superseded finding.
> 5. **This demo now points to 22d's own session-start checklist**
>    (`plan` `platform/` first, expect no changes, then apply
>    `workloads/`) rather than re-deriving session-start guidance —
>    this demo's Part A already does the equivalent check, just needed
>    to be explicitly tied to that same standing convention.
>
> Everything else — the app-wiring findings (UI's real endpoint
> variables, Catalog's real persistence variables), the sidecar
> pattern content, the version pins (`mariadb:12.3`, `busybox:1.37`),
> and the "no new Ingress" architectural correction — is carried
> forward **unchanged in substance**. This demo remains, as its own
> Governance Note already states, an unrun draft — nothing in this
> revision changes that status; it changes which directories an
> eventual real run would target.

---

## Governance Note — Read Before Using This Demo — [UNCHANGED, see original for the full four-point account]

This revision was produced by a governance review against the
now-confirmed Demo 22d, `Solution-Architecture.md`, and the series'
own verification standard. [Points 1–5 as originally written are
unaffected by the platform/workloads split — see the original demo
text for the full account of the UI-wiring fix, the placeholder fix,
the original session-continuity fix, the version pins, and the
original Cleanup fix.] **One correction to point 3 specifically, made
by this revision:** the original session-continuity fix (Part A's
three-scenario decision tree) is preserved in full, but now checks
`workloads/` rather than the old shared directory — see the Revision
Note above.

---

## Overview — [UNCHANGED — see original for full text]

22d proved the whole chain works end-to-end for one service. This demo
scales that proven pattern to all five `retail-store-sample-app`
services...

**What this demo builds — [UNCHANGED diagram, one label added]:**
```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Confirm workloads/, Rebuild workloads/, or Bootstrap Fully    │
│  platform/ is only ever CONFIRMED (a no-op plan) — never rebuilt here  │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Catalog: Deployment with a MariaDB Sidecar                   │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Cart, Orders, Checkout: Deployment + ClusterIP Service only  │
├─────────────────────────────────────────────────────────────────────────┤
│  PART D — Wire UI to the Backend Services                              │
├─────────────────────────────────────────────────────────────────────────┤
│  PART E — Verify: internal DNS-based service-to-service connectivity   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Verification Items — Read Before Building This Demo — [UNCHANGED — see original for VERIFY 1 (23), VERIFY 2 (23), VERIFY 3 (23) in full]

None of the three open verification items in this demo (UI's real
endpoint variable names, the `mariadb`/`busybox` version pins, and this
demo's own unrun status) are affected by the platform/workloads split —
they're app-behavior and image-pin questions, orthogonal to which
Terraform directory anything lives in.

---

## How This Demo's Pieces Fit Together — [CHANGED — VERIFY 6 reference updated]

**The AWS solution being built** — [UNCHANGED — see original].

**Why this demo has to start by confirming (or rebuilding) 22d's
cluster, not assuming it's there — [UNCHANGED reasoning, one sentence
corrected]:** unchanged in substance — this project's teardown
discipline tears the cluster down at the end of every session, and
this demo doesn't get to assume it's continuing 22d's own session. **What
changed:** the original text here warned that "VERIFY 6 from 22d ...
applies directly here too" as a live risk to carry forward. **As of
22d's own rebuild (ADR-023), VERIFY 6 is resolved structurally — the
two IAM roles live in `platform/`, which this demo's own rebuild never
touches at all.** What this demo's own rebuild (Scenario 2a, below)
actually needs to carry forward is simpler: `platform/` gets a no-op
`plan` to confirm it's stable, then `workloads/` gets rebuilt from
scratch — no `-target` discipline, no file-recreation-before-apply
warning, because `workloads/` has nothing in it that's ever meant to
survive.

**Why there's no Ingress/ALB decision in this demo** — [UNCHANGED —
see original in full].

**Why Catalog alone gets a sidecar, not a separate resource** —
[UNCHANGED — see original in full].

**Why deploying four services is not, by itself, "the mesh"** —
[UNCHANGED — see original in full].

---

## Prerequisites — [CHANGED — Terraform/AWS CLI directory targets updated]

### Knowledge, Required Tools — [UNCHANGED — see original in full]

### Fast Path — Skip This If You're Not Sure — [UNCHANGED — see original]

```bash
kubectl get nodes
kubectl get ingress ui
```

If both return real results, skip to **Part B**. Otherwise, go to
**Part A** — [reasoning unchanged, see original].

---

## Demo Objectives — [CHANGED — objective 1 reworded]

1. ~~Identify which of three starting scenarios applies...including the
   VERIFY 6 risk carried forward from 22d~~ — **replaced:** Identify
   which of three starting scenarios applies to `workloads/`
   specifically (nothing built yet, a prior session's `workloads/`
   torn down, or `workloads/` already live), while confirming
   `platform/` with a no-op `plan` rather than rebuilding it — and
   explain why this demo no longer carries any VERIFY-6-shaped risk,
   since that risk was resolved structurally at 22d, not merely
   documented around.
2–9. [UNCHANGED — see original]

---

## Cost & Free Tier — [UNCHANGED — see original in full]

(The NAT-gateway-count correction from 22d's own rebuild — single, not
dual — is inherited automatically here, since this demo rebuilds the
identical `workloads/vpc.tf`. No separate edit needed in this demo's
own cost table beyond noting the inheritance.)

---

## Directory Structure — [UNCHANGED — this demo's own `k8s/` folder is unaffected; only the *external* directories it reads from, in Part A/D, changed]

---

## Recall Check — 22d (EKS: Single Service) — [CHANGED — answer 4 updated]

4. ~~What did 22d's VERIFY 6 find, and why does it matter for a demo
   that starts a new session against the same cluster?~~ —
   **replaced:** What did 22d's VERIFY 6 find, and how was it
   resolved? *A bare `terraform plan`/`apply`, run in a directory that
   had only recreated 22b's/22c's files (the old Part A) but not yet
   `vpc.tf`/`eks.tf`, proposed and then actually destroyed the two IAM
   roles a prior session's `-target`-scoped destroy had correctly left
   standing. It was resolved by moving those two roles into
   `platform/iam.tf` (ADR-023) — a directory this demo's own rebuild
   never touches at all, so the failure mode can no longer occur, not
   just a risk that's now smaller.*

---

## Concepts — [UNCHANGED — see original in full for the sidecar pattern, UI/Catalog env var findings, internal DNS]

---

## Lab Step-by-Step Guide

---

## Part A — Confirm, Rebuild, or Bootstrap the Environment — [CHANGED]

Part A exists because this demo can honestly be entered from three
different starting points. **This revision retargets the check from
22d's old single directory to the two-directory split — `platform/`
is only ever confirmed, `workloads/` is what's actually checked for
rebuild-vs-live.**

```
                    cd into 22d's platform/ directory:
      22d-eks-single-service/src/platform
                              │
                              ▼
                terraform init && terraform plan
                              │
              ┌───────────────┴───────────────┐
              │ init FAILS outright             │ init succeeds, plan
              │ (no reachable S3 backend)        │ reports "no changes"
              ▼                                  ▼
   SCENARIO 1 — Direct run, nothing has    Good — platform/ is stable.
   ever been built in this account for     cd into 22d's workloads/
   this series' Phase 3. Go build, in      directory instead:
   full, in order: 22a → 22b → 22c → 22d.       22d-eks-single-service/
   Then return here, continue to Part B.        src/workloads
   (If platform/'s plan proposes ANY                    │
   change here, stop — that means                       ▼
   platform/ itself has drifted, a               terraform init && plan
   separate problem from this demo's own                │
   own scope; do not proceed until               ┌───────┴────────┐
   platform/ itself reports clean)               │ proposes ADDING │ reports 0 to
                                                  │ the VPC/SG/     │ add, 0 to
                                                  │ cluster (torn   │ change
                                                  │ down by a prior │
                                                  │ session's       │
                                                  │ Cleanup)        │
                                                  ▼                 ▼
                                   SCENARIO 2a — Fresh    SCENARIO 2b —
                                   session, workloads/    Continued session.
                                   gone. Apply, then      The cluster is
                                   re-apply UI's k8s      already up. Skip
                                   manifests (22d's own   straight to Part B.
                                   Step 12a), confirm
                                   Ingress ADDRESS, then
                                   continue to Part B.
```

**A third, related case — not a fourth branch:** re-running this demo
after its own Cleanup resolves through the identical `workloads/` plan
check, since this demo's own Cleanup (below) leaves `workloads/`
completely empty — the same state Terraform reconciles against on any
fresh rebuild. **No VERIFY-6-style caveat applies here anymore** — the
old caveat ("recreate `vpc.tf`/`eks.tf` before any unscoped `plan`")
described a risk that lived in the old shared-directory design; under
the split, there's nothing in `platform/` for a `workloads/`-only
rebuild to threaten, so the caveat has nothing left to protect against.

### Step 1 — Scenario 1 only: bootstrap the full stack — [UNCHANGED reasoning, directory-agnostic — see original for full text]

### Step 2 — Scenario 2a only: rebuild `workloads/` — [CHANGED]

```bash
cd workloads
terraform apply
```

This reproduces 22d's own Part B/Part C build — expect the same real
characteristics 22d documented **for its own rebuilt content**: one
NAT gateway (not two), roughly 2.5 minutes for the VPC, then 9–15
minutes for the cluster.

Reconnect `kubectl` and re-apply UI's manifests:

```bash
$(terraform output -raw kubeconfig_command)
kubectl get nodes
```

```bash
cd ..            # from workloads to src/
export UI_IMAGE="$(terraform -chdir=../platform output -json repository_urls | jq -r '.ui'):latest"
export CERT_ARN="$(terraform -chdir=../platform output -raw certificate_arn)"
for f in k8s/ui-deployment.yaml k8s/ui-service.yaml k8s/ui-ingress.yaml; do
  envsubst '${UI_IMAGE} ${CERT_ARN}' < "$f" | kubectl apply -f -
done
```

**Note the split `-chdir` targets** — `repository_urls` and
`certificate_arn` are `platform/`'s outputs (ECR and ACM are both
platform-tier), while `kubeconfig_command` above came from
`workloads/`'s own output. This is the one mechanical change from the
original build's single `-chdir=../22d-eks-single-service/src/phase-3-onward`.

Confirm the cluster is genuinely ready before proceeding to Part B —
[UNCHANGED — see original Step 13 timing guidance].

### Step 3 — Scenario 2b only: nothing to do — [UNCHANGED]

---

## Part B — Catalog: Deployment with a MariaDB Sidecar — [UNCHANGED in content — see original in full]

## Part C (folded into Part B, Step 3) — [UNCHANGED — see original]

---

## Part D — Wire UI to the Backend Services — [CHANGED — Step 2's `-chdir` target updated]

### Step 1 — Edit 22d's own ui-deployment.yaml — [UNCHANGED — see original]

### Step 2 — Re-apply the edited file — [CHANGED]

```bash
cd 22d-eks-single-service/src
export UI_IMAGE="$(terraform -chdir=workloads output -json repository_urls | jq -r '.ui'):latest"
```

> ⚠️ **This is deliberately wrong as written above, and worth pointing
> out why:** `repository_urls` is a `platform/` output, not a
> `workloads/` output — the corrected command is:
> ```bash
> export UI_IMAGE="$(terraform -chdir=platform output -json repository_urls | jq -r '.ui'):latest"
> ```
> This callout is left in deliberately, not trimmed, because it's
> exactly the kind of directory-target mistake this revision exists to
> prevent — a copy-paste from Part A's cluster-specific commands into a
> spot that actually needs `platform/`'s own output. Use the corrected
> line above.

```bash
envsubst '${UI_IMAGE}' < k8s/ui-deployment.yaml | kubectl apply -f -
cd -   # back to this demo's own directory
```

Alternative fast-iteration path via `kubectl set env` — [UNCHANGED —
see original, including the "doesn't survive a rebuild unless the
source file is also edited" caveat, which is unaffected by the state
split].

### Steps 3–4 — [UNCHANGED — see original in full]

---

## Part E — Verify Internal Connectivity — [UNCHANGED — see original in full]

---

## Cleanup — [CHANGED — drops `-target` entirely]

This demo's own pods and 22d's UI, the VPC, the security group, and
the EKS cluster itself are all torn down together at the end of the
session — same as before. **What changed: the destroy step is now a
plain, untargeted `terraform destroy` in `workloads/`, not the
`-target`-scoped command the original build used**, because
`workloads/` no longer contains anything meant to survive (the IAM
roles moved to `platform/` at 22d's own rebuild).

### Step 1 — Delete this demo's own Kubernetes objects — [UNCHANGED]

```bash
kubectl delete -f k8s/
```

### Step 2 — Delete UI's own Kubernetes objects — [UNCHANGED]

```bash
cd ../22d-eks-single-service/src
kubectl delete -f k8s/
cd -
```

Confirm the ALB is gone:

```bash
aws elbv2 describe-load-balancers --region us-east-2 --query 'LoadBalancers[].LoadBalancerName'
```

### Step 3 — Destroy `workloads/` in full

```bash
cd ../22d-eks-single-service/src/workloads
terraform destroy
```

**Expected shape, not yet run against a live cluster — see VERIFY 3
(23).** Based on 22d's own rebuild expectations: a plan destroying
everything `workloads/`'s state tracks — roughly 15 VPC/SG resources
(single NAT gateway, per 22d's own corrected count) plus the cluster,
access entry, and access policy association, with **zero `-target`
flags and zero "not for routine use" warning**, since a plain destroy
is now the ordinary, intended operation here.

```bash
terraform state list
```

Expected: **empty.** Nothing in `workloads/` is ever meant to survive
— unlike the original build, where 9 IAM resources deliberately
remained after this exact step.

```bash
cd ../platform
terraform state list
```

Expected: unchanged — `platform/`'s own governance, ECR, ACM, and IAM
resources, all still present, completely untouched by the
`workloads/` destroy that just ran. **This is the actual proof this
demo's own Cleanup is correct — the same structural proof 22d's own
rebuild established, exercised a second time by a different demo
against the identical `workloads/` state, not a new mechanism specific
to this demo.**

### Step 4 — Confirm in the Console — [UNCHANGED — see original]

> ⚠️ **Before your next session's first command — in `workloads/`, in
> this demo, in Demo 24, or anywhere else in this project — run
> 22d's own session-start checklist:** `plan` `platform/` first,
> confirm no changes, then proceed to `workloads/`. **No VERIFY-6-style
> warning belongs here anymore** — the checklist above is a routine
> ordering convention now, not a workaround for a structural gap.

---

## What You Learned — [CHANGED — item 1 reworded]

1. ~~This demo can honestly be entered from three different starting
   points...as long as vpc.tf/eks.tf are recreated first every time
   (VERIFY 6, carried forward directly from 22d)~~ — **replaced:**
   This demo can honestly be entered from three different starting
   points for `workloads/` specifically — nothing built yet, a prior
   session's `workloads/` torn down, or `workloads/` already live —
   while `platform/` is simply confirmed stable with a no-op `plan`,
   never rebuilt. Re-running this demo after its own Cleanup resolves
   through the identical check, since Cleanup leaves `workloads/`
   completely empty.
2–9. [UNCHANGED — see original]

---

## Cert Tips, Common Exam Traps, Exam Task — [UNCHANGED — see original in full]

---

## Troubleshooting — [CHANGED — one row updated]

| Error | Cause | Fix |
|---|---|---|
| `kubectl get nodes`/`kubectl get ingress ui` returns nothing at the start of this demo | Fresh session — `workloads/`'s own Cleanup tore the cluster down at the end of the last session | Start at Part A; check `workloads/` for rebuild-vs-live, and confirm `platform/` separately with a no-op `plan` |

~~`terraform plan` in 22d's directory (Part A) proposes destroying
`aws_iam_role.eks_cluster`/`aws_iam_role.eks_auto_node`...~~ — **row
removed.** This scenario cannot occur under the platform/workloads
split — `workloads/` never declares these roles and never will.

All other rows — [UNCHANGED — see original in full].

---

## Break-Fix Scenario — [UNCHANGED — see original in full]

## Interview Prep — [CHANGED — Q1 and Q6 updated]

**Q1 (unchanged core content, one clause updated).** *A teammate asks
why this demo doesn't create any new Ingress or ALB...* [answer
unchanged — see original].

**Q6 (reworded).** *A reviewer asks why this demo needed its own
"rebuild the cluster" step when 22d already built one, and whether
that still carries the same risk 22d's own VERIFY 6 described.* Same
reasoning as before on the "why a rebuild step at all" question — this
project's teardown discipline tears `workloads/` down every session,
and this demo doesn't get to assume it's continuing 22d's own session.
**What's different now:** the risk this rebuild step used to carry —
VERIFY 6, where a bare `apply` could destroy IAM roles that should
have survived — no longer applies, because those roles live in
`platform/`, a directory this demo's own rebuild (Scenario 2a) never
touches. The rebuild step is still necessary; the specific danger it
used to carry alongside is gone.

All other Interview Prep questions — [UNCHANGED — see original in full].

---

## Key Takeaways — [CHANGED — item 7 reworded]

7. ~~A resource meant to persist between demos only does so if the
   workflow crossing that boundary is explicit about it. This demo
   inherits 22d's own VERIFY 6 risk directly...~~ — **replaced:** A
   resource meant to persist between demos is safest when the
   directory that gets torn down simply never declares it — this demo
   inherits 22d's own *resolution* of that problem (the platform/
   workloads split), not the problem itself. The distinction matters:
   inheriting a fix is different from inheriting a risk with a
   workaround attached, and this project has now demonstrated both
   versions of that pattern in the same two consecutive demos.

All other Key Takeaways — [UNCHANGED — see original in full].

---

## Quick Commands Reference — [UNCHANGED — see original in full]

---

## Next Demo

**Demo 24 — IAM Least Privilege (via EKS Pod Identity):** now that all
five services have real per-service compute identity to scope
policies against, this demo builds `platform/iam.tf`'s Pod Identity
associations. **Two things this demo's own rebuild must include, both
already fully specified (ADR-024), not left as design questions for
whoever builds it:** (1) a `terraform_data` indirection resource
wrapping `workloads/`'s new `eks_cluster_created_at` output (added at
22d's own rebuild), with the Pod Identity association's
`replace_triggered_by` pointing at that `terraform_data` resource —
**not** directly at the remote-state value, which that argument cannot
reference; (2) a required survival test in this demo's own Verify
steps — destroy and reapply `workloads/`, then confirm the association
still resolves — required together with, not instead of, the
structural destroy-isolation proof this demo's own Cleanup (above)
already exercises a second time.

---

## Appendix — Anki Cards — [UNCHANGED except two cards reworded]

Two cards from the original deck need updating; all others —
[UNCHANGED — see original CSV in full]:

```
"What real risk from 22d's VERIFY 6 applies directly to this demo's own cluster rebuild?","None, as of the platform/workloads split (ADR-023) - VERIFY 6 was resolved structurally by moving the two IAM roles into platform/iam.tf, a directory this demo's own workloads/ rebuild never touches. This card is kept to record what the risk WAS, not because it still applies.","demo23,verify6,resolved"
"Does re-running this demo after its own Cleanup require any special VERIFY-6-style precaution?","No - re-running resolves through the identical workloads/ plan check Scenario 2 already uses, and Cleanup leaves workloads/ completely empty (no surviving IAM resources to worry about, unlike the pre-split design). The only standing convention is 22d's own session-start checklist: confirm platform/ first, then act on workloads/.","demo23,cleanup,session,resolved"
```

## Appendix — Quiz — [UNCHANGED except Q2, reworded]

**Q2 (reworded).** *While rebuilding the cluster in Part A, a learner's
`workloads/` directory shows `terraform plan` proposing to add the VPC
and cluster. Is there anything else this learner needs to check before
proceeding?*
- A) Nothing — `workloads/`'s own plan is the complete picture
- B) Confirm `platform/` separately reports a no-op `plan` first, since `workloads/`'s `eks.tf` depends on `platform/`'s IAM role ARNs being stable and correct
- C) Recreate `platform/`'s files verbatim before proceeding, the same discipline the pre-split design required
- D) Nothing — `platform/` is rebuilt automatically alongside `workloads/`

<details>
<summary>Answer</summary>

**B.** `platform/` is never rebuilt (ruling out C and D) — it's
confirmed once, with a no-op `plan`, per 22d's own session-start
checklist. `workloads/`'s `eks.tf` reads `platform/`'s outputs via
remote state, so confirming those outputs are stable is a real
prerequisite, not optional (ruling out A).

</details>

All other quiz questions — [UNCHANGED — see original in full].