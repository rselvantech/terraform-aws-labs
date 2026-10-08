# Terraform AWS Mastery — Solution Architecture

## 1. Document Control

| Field | Value |
|---|---|
| Document | `terraform-aws-mastery` — Solution Architecture |
| Version | 1.0 (consolidated) |
| Version history | Consolidates and supersedes: `Solution-Architecture-Design.md` (v1–v3), `Syllabus-Scope-Alignment.md` (v1–v3), `Complete-Demo-List-All-Phases.md` (v1–v3), `Phase-2-Reconciliation-Validation.md`, and the original `Terraform-AWS-Mastery — Project & Milestone Design` doc. Those five documents are retired as living files — their content lives here now, or in `Phase-1-Implementation.md`/`Phase-1-Recall-Check.md` where it's phase-1-specific and hands-on. |
| Status | Living document — updated as later phases are actually designed |
| Scope owner | `terraform-aws-mastery` series only |
| Note on Requirements | The retired v1–v3 documents referenced "FR1–FR5, NFR1–NFR2, unchanged" repeatedly but their text was never provided in this session — only the labels. Section 4 below is written fresh from what's actually been stated across this project's design discussions, not copied from unseen originals. |

## 1a. Decisions Index — categorized

Every cross-cutting decision made for this project, split the same way the reference template splits AWS/Kubernetes/Cross-Cutting decisions — because collapsing "this is Terraform curriculum design" and "this is a real AWS architecture choice" into one list hides a distinction worth keeping explicit.

- **AWS Infrastructure** — decisions about the real target AWS architecture that would hold regardless of how it's taught (VPC shape, compute target, data stores, IAM boundary).
- **Curriculum / Teaching** — decisions about how the *series itself* is structured (demo numbering, phase boundaries, what's a standalone demo vs. folded into another).
- **Cross-Cutting** — a decision that looks like curriculum sequencing but is actually driven by a real AWS/operational constraint, or vice versa — the cases most likely to get mis-filed.

| Decision | Category | Where |
|---|---|---|
| App: `retail-store-sample-app` | AWS Infrastructure | §6 |
| EKS (Auto Mode) primary, ECS Fargate time-boxed | AWS Infrastructure | §8, §10, ADR-019 |
| RDS (Catalog/Orders) + DynamoDB (Cart), coexisting | AWS Infrastructure | §10 |
| IAM DB auth for RDS (no separate secrets mechanism) | AWS Infrastructure | §10 |
| Mid-course compute swap: EKS replaces ECS as primary (Demo 22/23), ECS becomes the time-boxed comparison (Demo 29) | AWS Infrastructure | §6, §8, §9, ADR-019 |
| IAM least-privilege via EKS Pod Identity, not IRSA or ECS task roles | AWS Infrastructure | §10, ADR-003, ADR-021 |
| VPC: public/private (Phase 2) → +isolated tier (Phase 3) | AWS Infrastructure | §8 |
| NAT Gateway: provisioned Demo 16, reversed Demo 17 | AWS Infrastructure | §9, ADR-002 |
| Domain: `rselvantech.com` (confirmed real, in active use since Demo 20), ACM cert via registry module | AWS Infrastructure | §10, ADR-013 |
| Naming convention: `cloudnova-*` prefix continues into Phase 3+ (EKS/RDS/DynamoDB resources), not replaced with app-derived names — consistency with 19 already-built demos, no functional reason to fork | AWS Infrastructure | §10 |
| Region: `us-east-2`, one common region across the whole project (Phase 1 aligned on request) | AWS Infrastructure | §8, §10, §14 |
| Total 39 demos (00–38), 5 phases | Curriculum / Teaching | §7 |
| Cross-Stack State dropped (redundant with Demo 07) | Curriculum / Teaching | ADR-006 |
| EKS split into single-service + full-mesh demos | Curriculum / Teaching | §7, ADR-005 |
| Teaching-rep (00–21) vs. persistent-build (22 onward) | Cross-Cutting | §9, ADR-004 |
| IAM least-privilege deferred to Demo 24, not Phase 1 | Cross-Cutting | §10, ADR-003 |
| Only `dev` gets real applies, Phase 3 onward | Cross-Cutting | §11, ADR-007 |
| CI/CD: GitLab CI, overriding series' GitHub Actions default | Cross-Cutting | §12 |
| Total available AWS credit/budget, AWS Budgets alarm as a real control | Cross-Cutting | §11 |

## 2. Purpose & Scope

**Purpose:** build one canonical, high-level sketch of the complete target AWS system for `terraform-aws-mastery`, mapped phase-by-phase, so later-phase design doesn't create rework for earlier phases — and so there are two deliverables at series end, not one: (a) verified mastery of each phase's content via a phase-gate milestone, and (b) one real, running, portfolio-grade AWS system, grown incrementally rather than assembled from disconnected demos.

**In scope:** target architecture at full build-out; phase-by-phase delivery map; AWS component inventory tagged by introducing demo; app-to-AWS-component mapping; the teaching-rep vs. persistent-build distinction; cost/CI/CD constraints for the project layer.

**Out of scope:** exact resource/variable names below the demo level; Phase 3–5 demo-level Lab content (that gets designed when each phase is actually reached, in the other session per the agreed plan); CI/CD pipeline YAML specifics.

**Explicitly separate:** the OSS-Observability series (own app, own infra, own roadmap) — not touched by this document.

**Precedence, going forward:** this document governs curriculum-plus-target-architecture decisions for the whole series. `Phase-1-Implementation.md` governs Phase 1's actual hands-on build content. `Phase-1-Recall-Check.md` governs Phase 1's recall/quiz content. Where a future phase's actual demo design (built in the other session) conflicts with something stated here, the real, built demo wins — this document gets corrected to match, the same discipline already applied repeatedly during this project's reconciliation passes.

## 2a. Repository Structure

Finalized layout — the e2e project lives in its own folder, parallel to
each phase's own demo folders, named for portfolio/interviewer
visibility rather than a generic label:

```
terraform-aws-labs/terraform-aws-mastery/          (existing repo root)
├── README.md                              # repo overview, phase navigation
├── .gitignore                             # .terraform/, *.tfstate*, crash logs
├── Learning-System.md
├── Phase 1 - Foundations/
│   ├── 00-tf-hcl-basics/  ...  13-provisioners/
│   └── Phase-1-Recall-Check.md
├── Phase 2 - Modules/
│   ├── 14-modules-basics/  ...  18-workspaces/
│   └── Phase-2-Recall-Check.md          (future)
└── cloudnova-retail-store-e2e/
    ├── README.md                          # project overview, how to run — portfolio/interview framing should lead with the ADR discipline, empirical testing, and cost-governance model (ADR-019 addendum), not the compute target alone
    ├── .gitlab-ci.yml                     # placeholder, wired up at Demo 32
    ├── docs/
    │   ├── Solution-Architecture.md
    │   ├── Phase-1-Implementation.md
    │   ├── Phase-2-Implementation.md
    │   └── images/                        # colocated with the docs that reference them
    └── src/
        └── terraform/
            ├── bootstrap/                 # reserved — ADR-009's state backend, Demo 22a
            │   └── main.tf
            ├── modules/                   # reserved — Phase 2, Demo 14 onward
            ├── phase-1/
            │   ├── providers.tf
            │   ├── variables.tf
            │   ├── terraform.tfvars.example   # committed template — real values stay local, gitignored
            │   ├── s3.tf
            │   ├── sns_sqs.tf
            │   ├── cloudwatch.tf
            │   ├── iam.tf
            │   ├── security_group.tf
            │   ├── migration.tf
            │   ├── outputs.tf
            │   └── remote-state-check/
            │       └── main.tf
            └── phase-3-onward/            # reserved — Demo 22's persistent build
```

**Hygiene items added after review, not present in the first draft of
this structure:** `.gitignore` (excludes `.terraform/`, `*.tfstate*`,
crash logs — committing state was a real gap, not just polish, since
state can hold plaintext secrets); `terraform.tfvars.example` in place
of a real `terraform.tfvars` (the real file — holding a personal IP
address — stays local and gitignored, never committed); root and
project `README.md` files (this repo is explicitly meant to be
portfolio/interview-facing per ADR-001's resume-value reasoning, and
had no entry point before); `bootstrap/` and `modules/` reserved now
rather than improvised later, so Demo 22 and Demo 14 don't have to
invent folder names under time pressure; `phase-3-onward/` reserved as
the eventual home for the persistent build; `.gitlab-ci.yml` placeholder
reserved for Demo 32.

**`Phase-N-Recall-Check.md` lives inside each phase's own folder**, not
inside `cloudnova-retail-store-e2e/` — it's demo-content-adjacent
(sourced from that phase's own Interview Prep/Quiz banks), not part of
the e2e project build. `Solution-Architecture.md` and every
`Phase-N-Implementation.md` live together under
`cloudnova-retail-store-e2e/docs/`, since they're one continuous design
+ build narrative. Terraform code stays embedded in each
`Phase-N-Implementation.md`, not extracted into the `src/terraform/`
`.tf` files shown above yet — those paths are the intended eventual
location, used as the label on every embedded code block
(`**src/terraform/phase-1/providers.tf:**`) so the walkthrough reads
as file-by-file even before the files exist standalone.

## 3. Assumptions

- Single AWS account, real applies required for every practical component (plan-only doesn't satisfy any Pass Criteria in this series)
- `retail-store-sample-app`'s container images remain publicly available on the Amazon ECR Public Gallery at the URLs verified this session
- Phase 3+ session cadence is roughly the driver of real cost — teardown-between-sessions discipline is assumed to hold; §11 flags what happens if it doesn't
- Demos 00–21's teaching-rep model (build → verify → destroy, same session) continues to hold for any not-yet-built Phase 2 content, consistent with every already-built demo in the series
- IAM least-privilege, real VPC networking, and real compute are all deliberately absent from Phase 1 — not gaps, staged introductions (Demo 16 for VPC, Demo 22 for compute, Demo 24 for least-privilege)
- **RDS data does not persist across sessions** (ADR-017/018) — since RDS itself is torn down and re-applied every session, only Catalog/Orders' schema/infrastructure survives, not the data in it. Whoever designs Demo 26's Lab and Pass Criteria should not assume data persistence across sessions is available to test against. DynamoDB, by contrast, is left standing (near-$0 idle cost), so Cart's data does persist — this asymmetry is deliberate, not an oversight (see the DynamoDB row in §10)

## 4. Objectives & Success Criteria

- Every phase's milestone (`Phase-N-Implementation.md` + `Phase-N-Recall-Check.md`) is buildable and verifiable using only what that phase's demos have actually taught by that point — no forward-borrowed content
- The Phase 3+ persistent environment survives being extended, not rebuilt, phase over phase (Phase 4 wraps it in CI/CD; Phase 5 exercises it at integration scale) — nothing built early gets thrown away later
- Total real AWS spend across the series stays inside your available AWS credit/budget, with an actual monitoring control (AWS Budgets alarm), not just a documented intention
- Every non-trivial AWS/curriculum decision in this document has a stated reason and a stated "revisit if," not just a stated value — same standing rule the k8s reference project uses

## 5. AWS Cost Estimate — project level

| Component | Rough cost | Notes |
|---|---|---|
| NAT Gateway + ALB (Demo 22 onward) | ~$0.07/hr combined | Only while sessions are active |
| NAT Gateway data processing | ~$0.045/GB processed | Omitted from earlier versions — small at lab traffic volumes, but the doc already flags thin margin, so it belongs in the table |
| Route53 hosted zone (`rselvantech.com`) | $0.50/mo flat | Unlike everything else here, this accrues regardless of session activity — not session-gated, because the hosted zone itself is created once and never torn down (ADR-013, ADR-018), unlike the ACM cert validated against it. **Domain confirmed real and in active use as of Demo 20** — this line previously used the `<your-domain>.com` placeholder |
| EKS control plane (Demo 22 onward, Auto Mode) | ~$0.10/hr flat | **Persistent target now (ADR-019) — this fee accrues regardless of load, unlike Fargate's old pay-per-task model. Reinforces, not relaxes, teardown-between-sessions discipline for compute** |
| EKS Auto Mode nodes (5 pods, UI/Catalog/Cart/Orders/Checkout) | ~$0.02–0.03/hr equivalent | Auto Mode bin-packs onto managed nodes; comparable to the old Fargate per-task figure at this scale |
| Catalog MariaDB sidecar (pod, Demo 23 onward) | ~$0.01/hr equivalent | Added after review — same standard already applied to NAT/Route53: cheap but not exactly zero, belongs in the table |
| RDS (single-AZ, small instance) | ~$0.00–0.02/hr | Likely free-tier eligible if the account's 12-month window is open |
| DynamoDB, Lambda, API Gateway, ACM | ~$0.00 | On-demand/free tier covers lab-scale usage |
| ECS Fargate (Demo 29 only, time-boxed comparison) | ~$0.02–0.03/hr (5 small tasks) | One-time, a few hours total — mirrors what EKS's time-boxed role used to be, direction reversed (ADR-019) |

**Rough total across ~15–20 active sessions (2–4 hrs each): plausibly low tens of dollars — recomputed after the swap, correcting an arithmetic error from the first recomputation.** The first pass subtracted Fargate's ~$0.02–0.03/hr from EKS's $0.10/hr control-plane fee to get a "$0.07–0.08/hr delta" — that's wrong, because it treated the control-plane fee as *replacing* the Fargate figure when it's actually pure addition on top of it. The correct comparison: EKS Auto Mode's node cost (~$0.02–0.03/hr, its own line above) is what actually washes against the old Fargate figure — a like-for-like swap, ~$0 delta on that piece. The **control-plane fee has no ECS equivalent at all**; nothing about the old design paid for anything like it. So the true delta is the control-plane fee in full, not the difference between two node-cost figures:
- Old (ECS-primary): ~$0.02–0.03/hr (Fargate tasks only)
- New (EKS-primary): ~$0.10/hr (control plane) + ~$0.02–0.03/hr (Auto Mode nodes) ≈ **$0.125/hr**
- True delta ≈ **$0.10/hr**, not $0.07–0.08/hr

The persistent compute layer (Demo 22 onward) is live for roughly 12–15 of the 15–20 total sessions at 2–4 hrs each, call it 24–60 hours of persistent-compute runtime across the project — so the corrected total impact is **roughly $2.40–$6 more across the whole project** than the pre-swap estimate, not "$2–5." The qualitative conclusion still holds (small, not zero, still "low tens of dollars" overall) — but on the corrected number, not the original one. Whether the resulting total is comfortably inside your available AWS credit/budget or a tight fit depends entirely on what that budget actually is — plug in your own number against the per-hour rates above rather than treating any fixed figure here as universal. The margin only holds if teardown-between-sessions is followed every time — **more so now than before the compute swap:** EKS's control-plane fee is flat and continuous, not pay-per-task, so an idle cluster left running costs money whether or not anything is actually deployed to it. As a sizing example, the EKS control plane alone left running a week by accident is ~$16.80 — the same figure that used to describe a one-off time-boxed EKS exercise now describes what happens if the *primary, every-session* compute layer isn't torn down. That raises, not lowers, the stakes of the teardown checklist below, and it's the number Demo 22's Budgets-alarm thresholds should be sized against, not the earlier, understated delta.

**Control, not just a note — and detection, not prevention, needs saying explicitly.** A Budgets alarm tells you *after* spend has happened; it doesn't stop it. Two required elements as part of Demo 22b (sub-demo citation per ADR-020 — this was "Demo 22 Part A" before the split):
- **AWS Budgets alarm, two thresholds:** 50% of your available budget as an early warning, 80% as an escalated notification.
- **A literal teardown checklist/command as the last step of every Phase 3+ demo's Lab** — reduces reliance on memory, the actual failure mode behind the EKS example above.

**Decided, not just flagged: EventBridge + SNS notification, not auto-destroy.** A scheduled EventBridge rule checks tagged Phase 3+ resources against a session-length threshold and sends an SNS notification if exceeded — proactive, doesn't rely purely on memory or the lagging, spend-based Budgets alarm. **Deliberately not** paired with a Lambda that force-destroys automatically: for a single-learner lab (not shared production), the failure mode of a misfiring idle-detection auto-destroying real work-in-progress mid-session is worse than the cost risk it would solve. This is a locked decision (see ADR-010), not deferred to Demo 22's designer.

## 6. Application Architecture — `retail-store-sample-app`

**Chosen over Yelb** (full comparison retained in decision history, not repeated here in full): official AWS Terraform for RDS/DynamoDB/EKS/ECS/App Runner, native Prometheus/OTLP observability, real polyglot persistence (RDS + DynamoDB coexisting, not mutually exclusive), richer CI/CD teaching surface (3-language monorepo), stronger resume/interview pedigree. Trade-offs accepted: no native Lambda mode (small bolt-on needed for Demo 28), heavier JVM footprint — **confirmed mitigation, not just a proposal:** EKS Auto Mode (not managed node groups) as the primary persistent compute target + smallest viable instance classes, with the environment torn down between sessions rather than left running continuously. **ECS Fargate, previously the primary target, is now the time-boxed comparison exercise (Demo 29) — a direct swap, not an addition (ADR-019).**

**Services:** UI, Catalog, Cart, Orders, Checkout — 5 services, 3 languages (Java/Go/Node).

**Images:** confirmed publicly pullable, no auth, from `public.ecr.aws/aws-containers/retail-store-sample-<service>` — verified against the real repo's own published pull command.

**Persistence split (final, post-Demo-26/27 swap-in):** RDS (PostgreSQL) backs Catalog + Orders; DynamoDB backs Cart — a real polyglot-persistence demonstration, not an either/or. This sentence was dropped during the ADR-012 empirical-testing rewrite and restored here after review — the underlying facts survived in §10's RDS/DynamoDB rows, but the explicit framing didn't.


**Sequencing gap, resolved with real evidence, not inference (Demo 23 deploys before Demo 26/27 exist):** Demo 23 (EKS — Full Service Mesh) deploys all 5 services, but RDS (Demo 26) and DynamoDB (Demo 27) don't exist until 3–4 demos later. **Ground-truth tested — `docker run` against each real published image, no DB env vars set, real logs captured — not assumed:**

| Service | Result | Evidence |
|---|---|---|
| **Catalog** | **Fails.** Exits within 15 seconds, nothing listening (`curl` → connection failure) | Log: `Failed to prep migration dial tcp: lookup catalog-db on ...: i/o timeout` — tries to resolve a `catalog-db` hostname, no fallback exists |
| **Cart** | **Runs clean.** Fully started, stable, `curl` → HTTP 404 (expected — server up, no root route) | Spring Boot startup completes with zero DB connection attempts or errors in the log |
| **Orders** | **Runs clean.** Fully started, stable, `curl` → HTTP 404 (expected, same as Cart) | Log: `Using dialect: org.hibernate.dialect.H2Dialect` and `Using in-memory messaging provider` — genuine built-in H2 in-memory DB and in-memory messaging as Orders' default profile |

**This inverts both prior hypotheses.** The original (unsourced, rejected) claim said Orders needed a real DB and Catalog/Cart had native fallbacks — backwards. Document 26's evidence-based inference (all three need lightweight sidecar containers) was the best-supported guess *available at the time*, but empirical testing now shows it's wrong for two of three services: **only Catalog actually needs help.**

**Decision, locked:** Catalog gets a lightweight MariaDB sidecar container at Demo 23 (satisfying the `catalog-db` hostname it expects), scoped as bootstrap infrastructure alongside Catalog's own pod — **torn down and re-applied every session** (ADR-017/018), since it's tightly coupled to Catalog's own compute lifecycle, not a standalone persistent resource. In Kubernetes terms, this is a sidecar container in Catalog's own pod spec, not a separate Deployment. Cart and Orders need **zero special handling** at Demo 23 — they run against their own built-in defaults (Cart's unspecified local/no-op provider, Orders' H2) with no additional infrastructure. Demo 26 (RDS) still swaps Catalog *and* Orders onto real PostgreSQL — Orders' H2 is non-persistent/ephemeral, fine for proving the EKS deployment pattern but not for the real system Phase 3 builds toward. Demo 27 (DynamoDB) swaps Cart onto real DynamoDB, same reasoning. **This entire empirical picture is orchestrator-agnostic** — it was tested via plain `docker run`, not against ECS or EKS specifically, so the mid-course compute swap (ADR-019) doesn't touch it at all.

**Timing correction, caught while building §15's per-demo checklist:** Demo 22 deploys **UI only** (its own single-service scope, per §7/ADR-005) — Catalog, Cart, and Orders don't enter the picture until Demo 23's full-mesh deploy. Every reference to "Demo 22/23" for the sidecar/backend question in earlier drafts of this section was imprecise; the sidecar and backend behavior only matter starting Demo 23, since that's when Catalog is first deployed at all.

**Checkout and UI: empirically confirmed stateless, not merely assumed.** Same `docker run`, no env vars, real logs: Checkout's own log states `Creating InMemoryRepository...` — an explicit, positive statement of a genuine built-in in-memory data layer, not silent success. UI shows the same clean pattern as Cart/Orders — full Spring Boot startup, zero DB-related log lines, `curl` → HTTP 303 (an expected redirect for a UI root route, not an error). Both need zero additional infrastructure at Demo 23, same as Cart and Orders. Full transcripts in Appendix B.12.

## 7. Phase-wise Delivery Plan

| Phase | Demos | Focus | Status |
|---|---|---|---|
| 1 | 00–13 (14) | Terraform Foundations — HCL, workflow, state, vars/locals/outputs, remote state, data sources, `count`/`for_each`, state addressing/`moved`, lifecycle, provisioners | Built |
| 2 | 14–21 (8) | Modules — local/registry modules, VPC, three-tier SGs, workspaces, ECR, ACM/Route53, Terraform testing basics | **Built — all 8, closed** (19–21 built and cross-checked against this document; region `us-east-2` and domain `rselvantech.com` confirmed by their real content) |
| 3 | 22–30 (9) | Real AWS Infrastructure — EKS (split), IAM least-privilege (EKS Pod Identity), VPC extension, RDS, DynamoDB, Lambda/API Gateway, ECS Fargate (time-boxed comparison), CloudWatch Observability | **In progress — 22a/22b/22c/22d/23/24 built** (22d has two open VERIFY items, §14); 25–30 planned |
| 4 | 31–34 (4) | HCP Terraform & Governance — remote runs, GitLab CI, Policy as Code, DevSecOps scanning | Planned |
| 5 | 35–38 (4) | Advanced Patterns & Capstone — cross-stack state (integration), drift/import, Terraform testing (integration), capstone | Planned |

**Total: 39 demos, 00–38.** Demo builds beyond Phase 1 happen in a separate session per the agreed working split — this document stays the shared reference both sessions design against.

## 8. Target Architecture — Full Build-Out (end of Phase 5)

> **Dependency note, updated:** Demos 19–21 (ECR, ACM/Route53, Terraform Testing Basics) are now **built and cross-checked against this document** — the ECR repo/service names, the ACM/Route53 teardown-and-recreate behavior (ADR-013), and the testing-basics scope all match what's described here. This diagram's Demo 22 assumptions are confirmed, not provisional.
>
> **Region, locked:** `us-east-2` is the confirmed Phase 3+ persistent-build region — not an arbitrary default, evidenced by Demos 14–21's consistent, unbroken use of it across the whole demo-building track (VPC, ECR, ACM, testing). Stated explicitly here rather than left inferable from demo code, consistent with this document's own standard elsewhere (cf. the Route53 hosted-zone lifecycle and ACM-cert-continuity gaps, both of which were "obvious from context" until they weren't stated and became real ambiguities). ACM certificates for a regional ALB listener must be issued in the same region as the ALB — Demo 20 already proved out DNS validation in `us-east-2`, so Demo 22 Part A's cert re-request stays in-region, not a fresh region-mismatch problem. **Phase 1 originally defaulted to `us-east-1` — updated to `us-east-2` on request, purely for project-wide consistency, since Phase 1's resources never actually depended on region.** The whole project — Phase 1 through Phase 3+ — now runs in one common region, not just the persistent build.
>
> **Four sequencing notes the diagram itself can't show:** (1) Catalog needs a lightweight MariaDB sidecar starting Demo 23, when it's first deployed (Demo 22 is UI-only) — empirically confirmed necessary, orchestrator-agnostic (§6, ADR-012). Cart and Orders need no additional infrastructure, running against their own built-in defaults — the RDS/DynamoDB boxes below aren't live for any of the three until Demo 26/27's swap-in step. (2) The ECR and ACM boxes shown as feeding this persistent environment are re-created at Demo 22c, not survivors of Demo 19/20's own teardown (§9, ADR-013, ADR-020). (3) IAM least-privilege (Demo 24) only covers what exists at that point — RDS/DynamoDB permissions are added at Demo 26/27's swap-in step, not pre-scoped at Demo 24 (ADR-015). (4) **Since ADR-021, IAM identity at Demo 24 is via EKS Pod Identity, not IRSA and not ECS task roles — each service's Kubernetes service account is associated with an IAM role directly through the EKS Pod Identity API, with no OIDC identity provider involved at all.** This is a genuine simplification over the IRSA design it replaces: because there's no cluster-anchored OIDC provider for the association to depend on, Demo 24's Pod Identity associations sit in the "created once, left standing" bucket (ADR-017/018) the same way Phase 1's broad self-trust IAM did — not the every-session-teardown bucket IRSA's OIDC-anchored trust policies required. See ADR-021 and the updated IAM row in §10.

```
                                   ┌─────────────────────────────┐
                                   │   GitLab CI/CD (Phase 4)     │
                                   │   build → scan → plan/apply  │
                                   └──────────────┬────────────────┘
                                                  │
                                   ┌──────────────▼────────────────┐
                                   │   HCP Terraform (Phase 4)     │
                                   │   remote runs, policy as code  │
                                   └──────────────┬────────────────┘
                                                  │ applies
┌─────────────────────────────────────────────────▼──────────────────────────────────┐
│  VPC (module code from Demo 16/17, re-applied persistently from Demo 22 onward)     │
│  ┌─────────────┐   ┌──────────────────────────────────────────┐  ┌──────────────┐ │
│  │ Public       │   │ Private (compute)                        │  │ Isolated     │ │
│  │ subnets      │   │                                           │  │ (data, from  │ │
│  │              │   │  ┌────────┐ ┌────────┐ ┌────────┐        │  │  Demo 25)    │ │
│  │  ALB ────────┼──▶│  │  UI    │ │Catalog │ │  Cart   │       │  │              │ │
│  │  (via ALB    │   │  └────────┘ └────────┘ └────────┘        │  │  RDS         │ │
│  │  Controller/  │   │  ┌────────┐ ┌────────┐                   │  │  Postgres    │ │
│  │  Ingress,     │   │  │ Orders │ │Checkout│                   │  │  (Demo 26)   │ │
│  │  Demo 22/23)  │   │  └────────┘ └────────┘                   │  │              │ │
│  │  ACM cert    │   │  EKS Auto Mode (Demo 22/23) or ECS Fargate│  │  DynamoDB    │ │
│  │  (Demo 20)   │   │  (Demo 29, time-boxed comparison)          │  │  (Demo 27)   │ │
│  └─────────────┘   └──────────────────────────────────────────┘  └──────────────┘ │
│  IAM least-privilege per service — EKS Pod Identity (Demo 24, ADR-021 —           │
│  replaces Phase 1's broad self-trust; created once, left standing, no OIDC step)   │
│  ECR (Demo 19) supplies every service's container image                            │
└───────────────────────────────────────────────────────────────────────────────────┘
                    │                                    │
                    ▼                                    ▼
   ┌───────────────────────────────┐    ┌───────────────────────────────────┐
   │  SNS "order-events" (Demo 03  │    │  CloudWatch (Phase 1 scaffolding,  │
   │  scaffolding, topic built     │───▶│  Demo 09, real consumers Demo 30)  │
   │  Demo 06) → SQS → Lambda      │    │  — app logs + metrics              │
   │  analytics bolt-on (Demo 28,  │    └───────────────────────────────────┘
   │  after DynamoDB) → DynamoDB   │
   └───────────────────────────────┘
```

Compute is drawn as "EKS *or* ECS Fargate," never both simultaneously live — ECS Fargate is a time-boxed, standalone exercise (Demo 29); EKS (Auto Mode) is the persistent target (ADR-019, reversing the primary/comparison framing that lived in the original ADR-014 and this section's own prose — ADR-005 was always about the single-service/full-mesh split, not about which compute layer is primary, and its logic is unchanged by this swap).

## 9. Teaching-Rep vs. Persistent-Build Model

**Demos 00–21 (Phase 1 and Phase 2) are isolated teaching reps.** Each builds real AWS resources, verifies them, and tears them down at its own Cleanup step — nothing survives past its own demo.

**Demo 22 (EKS — Single Service, first Phase 3 demo) marks the shift.** Demo 16/17's module code is re-applied — not as a fresh lesson, as the actual ongoing infrastructure the rest of the series builds on. From Demo 22 onward, "mandatory teardown discipline" means **between sessions**, not between every demo — but **not everything gets torn down**, see the Part A/B split below and ADR-017. **The cluster and its control plane are themselves in the torn-down-every-session bucket, not the created-once bucket** — EKS's flat, continuous control-plane fee (§5) makes this a stronger requirement than it was under ECS Fargate's pay-per-task model, not a weaker one.

**Demo 22's scope load, addressed explicitly (not left implicit against ADR-005's own sizing principle).** ADR-005 splits EKS into two demos specifically to avoid overloading one demo with teaching content. Demo 22 has since accumulated real setup weight beyond its own teaching content: the state backend, cost-control automation, the Budgets alarm, static analysis, and ECR/ACM re-creation. **Resolved by structuring Demo 22 as two explicit parts, not by adding a new demo number:**
- **22a — State backend bootstrap, run once only, never torn down (ADR-009, ADR-017):** the project-layer S3 state backend with `use_lockfile = true`.
- **22b — Cost governance, run once only, never torn down (ADR-010, ADR-011, ADR-017):** EventBridge+SNS cost-control notification, two-threshold Budgets alarm, `tflint`/`checkov` local checks.
- **22c — ECR/ACM re-creation, run once only, never torn down (ADR-013, ADR-017):** ECR repo re-creation + image re-push, ACM cert re-request + re-validation.
- **22d — EKS: Single Service, re-applied every session (ADR-005, ADR-017, ADR-019):** the VPC/SG module re-apply, the EKS cluster itself (Auto Mode — no OIDC identity provider needed, per ADR-021's Pod Identity adoption), and the actual teaching content — the ECR image → Kubernetes Deployment/Service → Ingress/ALB routing pattern this demo exists to teach, for the UI service only (Demo 22's single-service scope, per ADR-005). **The Catalog MariaDB sidecar belongs to Demo 23, not here** — Demo 22 doesn't touch Catalog at all.

**22a/22b/22c together reconstitute exactly what ADR-016 originally called "Part A"; 22d is exactly the original "Part B" — this is a numbering-granularity change, not a rescope (ADR-020).** Total demo count (39, 00–38) and Demo 23-onward numbering are unaffected.

This isn't a violation of ADR-005's principle — that principle is about teaching-concept load, not one-time administrative setup. Splitting into 22a/22b/22c/22d keeps that distinction explicit rather than letting six unrelated bootstrap tasks read as if they were six more teaching concepts crammed into one demo. It also resolves a deeper issue than wording: 22a/22b/22c's tasks are all free or near-free (state backend, ECR repo, ACM cert, EventBridge, Budgets) and have no cost reason to be destroyed between sessions — see ADR-017 for why "teardown between sessions" only ever meant the cost-accruing compute/networking layer, not everything Demo 22 touches. **IAM no longer needs an exception, as of ADR-021.** Under the IRSA design this project briefly specified, Demo 24's role trust policies would have been anchored to the cluster's own OIDC identity provider, created and destroyed with the cluster — meaning they'd have had to ride 22d's every-session cadence rather than sitting in the once-only bucket with everything else IAM-related. **Pod Identity removes that coupling entirely: there's no cluster-anchored OIDC provider for an association to depend on**, so Demo 24's Pod Identity associations sit cleanly in the "created once, left standing" bucket, the same as Phase 1's broad self-trust IAM did. This is a genuine simplification, not just a substitution — see the updated IAM row in §10 and ADR-021.

**Same treatment required for ECR (Demo 19) and ACM (Demo 20), resolved — not exempted from teardown.** Both are teaching reps like every other Phase 2 demo: Demo 19's ECR repo and pushed images, and Demo 20's ACM cert, are destroyed at their own Cleanup, no exception. Demo 22c re-creates the ECR repo and re-pushes the images, and re-requests + re-validates the ACM cert — **once, not every session** (ADR-017) — alongside the rest of the bootstrap sub-demos. Rejected alternative: exempting ECR/ACM from teardown at Demo 19/20 so Demo 22 could just find them already there — this would silently break the "every Phase 1–2 demo tears down, no exceptions" guarantee the whole model depends on, for a savings of a few re-push/re-request commands.

## 10. Component Inventory

**Confidence key:** Confirmed = real demo text checked directly. Objectives = confirmed via the demo's stated objectives, not full content. Unread = asserted from the app/curriculum design, not checked against the demo's own file at all — treat these as the current best assumption, not fact, until the grep sweep (§14 — in progress, run by the user) completes.

| AWS Service | Introduced | Role | Confidence |
|---|---|---|---|
| IAM (role/policy) | Phase 1, Demo 05 (broad) → Demo 24 (least-privilege, via EKS Pod Identity) | CI/CD + app service identity — **Demo 24 scopes only what exists at that point** (ECR pull, CloudWatch, SNS/SQS); RDS/DynamoDB permissions don't exist yet since Demo 24 lands before Demo 26/27, see ADR-015. **Since ADR-021, Demo 24's roles are associated via EKS Pod Identity**, with no OIDC identity provider involved — **created once, left standing**, the same as Phase 1's broad self-trust roles, not re-applied every session | Confirmed (05) |
| `data.aws_caller_identity` | Phase 1, Demo 08 | Read-only account-ID lookup, used in the Phase 1 milestone's IAM trust policy — **was missing from this inventory entirely until review found the omission** | Confirmed (08) |
| SNS / SQS | Phase 1, Demo 03 (scaffolding) / Demo 06 (topic built) | Order-event scaffolding, real producer arrives Demo 28 | Objectives (03) / Confirmed (06) |
| S3 | Phase 1, Demo 10 (`for_each` teaching example) / **Demo 01 (state backend)** | Generic teaching example, no app-literal connection assumed. Demo 01 Part B confirmed: builds a real S3 remote state backend (manual bucket creation, `backend "s3"` block, `use_lockfile` locking, `init -migrate-state`) | Confirmed (10) / **Confirmed (01)** |
| **Security group** | Phase 1, Demo 10 (`dynamic` blocks) | Default-VPC security group with map-driven ingress rules — real resource this series creates, replaced when Phase 2/Demo 16 introduces real VPC networking. Added here after review found it missing from this inventory entirely | Confirmed (10) |
| `data.aws_vpc` | Phase 1, Demo 10 | Read-only default-VPC lookup, feeding the security group above — per Demo 08's own text, this pattern belongs to Demo 10, not Demo 08. Added for the same completeness standard `data.aws_caller_identity` got | Confirmed (10) |
| SSM Parameter Store | Phase 1, Demo 07 | Second config-sharing pattern, alongside `terraform_remote_state` | Confirmed |
| CloudWatch Logs/Metrics | Phase 1, Demo 09 | Real app telemetry arrives Demo 30, **left standing once created — near-$0 at lab scale, no cost reason to tear down** (ADR-018) | Objectives |
| VPC | Phase 2, Demo 16 (pattern) → re-applied persistently Demo 22d | Networking foundation, `us-east-2` (one common region across the whole project, incl. Phase 1 — see §8) | Confirmed (16 built) |
| ECR | Phase 2, Demo 19 (teaching rep, torn down) → **re-created + images re-pushed at Demo 22c** | Container image registry, `us-east-2` | Confirmed (19 built) |
| ACM cert + validation record | Phase 2, Demo 20 (teaching rep, torn down) → **cert re-requested + re-validated once, at Demo 22c, then left standing** | TLS cert on `rselvantech.com` (confirmed real domain, in active use since Demo 20 — previously the `<your-domain>.com` placeholder), `us-east-2` | Confirmed (20 built) |
| **Route53 hosted zone** | **Created once, at or before Demo 20's first build — never torn down, including at Demo 20's own Cleanup** (ADR-013, ADR-018) | The domain's DNS itself — every ACM cert validated against it (Demo 20's reps and Demo 22c's re-request alike) points at this same standing zone; destroying/recreating it would mean re-pointing registrar nameservers every session, which never happens | Confirmed (20 built) |
| **`data.aws_route53_zone`** | **Phase 2, Demo 20 — read-only, every rep and Demo 22c's re-apply alike** | Since the hosted zone itself is never created or destroyed by this project's Terraform (ADR-013), Demo 20's module needs a `data` lookup to find the existing zone's ID for the ACM DNS-validation record — a `data`, not a `resource`, block, same completeness standard `data.aws_caller_identity` (Demo 08) and `data.aws_vpc` (Demo 10) got | Confirmed (20 built) |
| EKS (Auto Mode) | Phase 3, Demo 22d (single) → Demo 23 (all 5) | Compute target #1, persistent, **torn down and re-applied every session** (ADR-017, ADR-019) — control plane + Auto Mode nodes both fall in the every-session bucket, since the control-plane fee is flat/continuous, not pay-per-task. See §6 for the empirically-confirmed per-service backend picture (only Catalog needs a bootstrap sidecar) — that picture is orchestrator-agnostic and carried over unchanged from the ECS-primary design. **Built, with two open verification items — see §14 (VERIFY 1: `compute_config`'s real required arguments; VERIFY 2: security-group module version/shape conflict with Demo 17)** | Built, unverified in two places (22d) |
| **EKS Pod Identity associations** | **Demo 24, created once, left standing** (ADR-021) | Associates each service's Kubernetes service account with an IAM role directly via the EKS Pod Identity API — no OIDC identity provider required at all, unlike the IRSA design this replaces (ADR-021 supersedes the original "Cluster OIDC identity provider (for IRSA)" row this document previously carried here) | Confirmed (24 built) |
| **Catalog MariaDB sidecar** | **Demo 23, tied to Catalog's own pod, torn down and re-applied every session** (ADR-012, ADR-017) — not Demo 22, which is UI-only | Lightweight local database container satisfying the `catalog-db` hostname Catalog's container requires — empirically confirmed necessary via direct `docker run` testing (Cart and Orders need no equivalent), orchestrator-agnostic. Swapped for real RDS at Demo 26, same as Orders | Decision, empirically confirmed |
| ECS Fargate | Phase 3, Demo 29 | Compute target #2 (**reversed from the original design — was primary, now the comparison exercise, ADR-019**) — **third category, distinct from both ADR-017 buckets: stood up once, torn down once, after its own one-session exercise, never revisited** (ADR-018) — reuses Demo 26/27's existing RDS/DynamoDB instances, not separate ones (avoids a second RDS instance's cost for a one-session exercise); ECS tasks need equivalent network/security-group access into the isolated data tier for this to work — an implementation detail for whoever designs Demo 29, not an open architectural question | Planned |
| RDS PostgreSQL | Phase 3, Demo 26 | Catalog/Orders backing store, **torn down and re-applied every session** (ADR-017) — **Demo 26's swap-in step includes both** the connection-string swap (Catalog: sidecar → RDS; Orders: H2 → RDS) and the IAM policy update granting Catalog/Orders' task roles RDS access, since Demo 24 couldn't scope that permission before this demo existed (ADR-015). **Consequence, stated explicitly (not left implicit):** since RDS itself is destroyed each session, Catalog/Orders' actual *data* doesn't persist across sessions — only the schema/infrastructure does, via the same Terraform config re-applying it. See §3 Assumptions | Planned |
| DynamoDB | Phase 3, Demo 27 | Cart backing store, analytics bolt-on, **left standing once created — on-demand pricing means near-$0 idle cost, no reason to tear down** (ADR-018) — **Demo 27's swap-in step includes both** the connection swap and the IAM policy update granting Cart's task role DynamoDB access, same reasoning as RDS above (ADR-015). **Asymmetry with RDS is deliberate, not an oversight:** Cart's data persists across sessions while Catalog/Orders' doesn't, because the underlying cost profiles genuinely differ | Planned |
| Lambda + API Gateway | Phase 3, Demo 28 (after DynamoDB) | Serverless analytics bolt-on — **confirmed:** read-only `GET /analytics/orders` endpoint, same Lambda that processes the SNS event, reading the DynamoDB analytics table. **Left standing once created** — pay-per-request pricing means near-$0 idle cost (ADR-018) | Planned, design confirmed |
| HCP Terraform | Phase 4, Demo 31 | Remote runs — also the destination for the project-layer state migration (see state row below) | Planned |
| GitLab CI *(overrides GitHub Actions)* | Phase 4, Demo 32 | Build/scan/deploy pipeline — **OIDC federation to AWS assigned here** (no static IAM keys in CI variables), and Demo 32 is also where `tflint`/`checkov` gets formally integrated into the pipeline, superseding the informal Demo-22-onward local checks | Planned |
| DevSecOps Scanning (image + IaC) | Phase 4, Demo 34 | Formalizes and extends Demo 22b's interim `tflint`/`checkov` checks with container image scanning, inside Demo 32's actual pipeline — not redundant with ADR-011, a later, more complete version of the same concern | Planned |
| **Terraform state backend (project layer)** | **Demo 22a, once only — never torn down** (ADR-017) | **S3 backend, `use_lockfile = true`** (revised from an original S3+DynamoDB design — `dynamodb_table` is a documented Terraform deprecation, ADR-009), bootstrapped via a small separate local-state config before the main VPC/EKS applies (see ADR-009 for the bootstrap mechanics) — for the persistent build's own state (distinct from each Phase 1–2 demo's own throwaway state, and the same locking mechanism Demo 01 taught). Migrated to **HCP Terraform state as an explicit, taught step in Demo 31**, not before | Confirmed (22a built) |
| **Cost-control automation (EventBridge + SNS)** | **Demo 22b, once only — never torn down** (ADR-017) | Scheduled rule checking tagged resources against a session-length threshold, SNS notification only — see ADR-010 | Confirmed (22b built) |
| **AWS Budgets alarm (two-threshold)** | **Demo 22b, once only — never torn down** (ADR-017) | 50%/80% thresholds against your available AWS credit/budget — see §5 | Confirmed (22b built) |
| **Static analysis (`tflint`/`checkov`)** | **Demo 22b, once only — never torn down** (interim, local/manual) → **formalized into Demo 32's pipeline, extended with image scanning at Demo 34** | Closes the gap between real applies starting (22) and Policy as Code (33) — see ADR-011 | Confirmed (22b built) |

## 11. Cost & Governance Constraints

- **Total available AWS credit/budget** — modeled at low tens of dollars across Phase 3–5, thin margin regardless of the exact figure (§5)
- **Mandatory teardown discipline, between sessions, from Demo 22 onward** (not between every demo, the way Phase 1–2 works)
- **Only `dev` gets real applies, Phase 3 onward** — a going-forward policy, not something Demo 18 itself follows (Demo 18 applies both `dev` and `staging` once, to prove workspace state isolation — that was its whole teaching point)
- **EKS (persistent, flat control-plane fee) and RDS are the highest-cost items requiring every-session teardown discipline; ECS Fargate is the highest-cost *time-boxed* item** (Demo 29 only, ADR-019)

## 12. CI/CD & Tooling

**GitLab CI**, project-layer override of the series' own GitHub Actions default (user is learning GitLab in parallel). Pipeline: build → push to ECR (Demo 19) → `plan`/`apply` → deploy to EKS (Demo 22/23), `dev`-only real applies, Policy as Code (Demo 33) enforcing that programmatically.

**Authentication — OIDC federation, not static keys, assigned to Demo 32.** GitLab CI authenticates to AWS via OIDC trust (GitLab's ID token → an AWS IAM role, no long-lived access keys stored in GitLab CI variables) — standard practice. **Decision: taught as part of Demo 32 itself** (the GitLab CI demo), since it's specifically how the pipeline authenticates, not a per-service app-identity concern the way Demo 24's least-privilege work is. No longer left to "whichever session decides" — assigned. **Only one OIDC trust relationship exists in this project as of ADR-021** — worth stating explicitly here, since an earlier round of this document described two. Demo 24's per-service IAM identity now goes through EKS Pod Identity (ADR-021), which involves no OIDC provider at all; Demo 32's GitLab-CI-to-AWS trust is the only OIDC federation this project actually builds. Don't assume the "two distinct OIDC relationships" framing from an earlier draft still applies when designing either demo.

**Static analysis in this pipeline:** Demo 32 also formalizes the `tflint`/`checkov` checks first introduced informally at Demo 22b (ADR-011) into an actual pipeline stage, and Demo 34 (DevSecOps Scanning) extends that further with container image scanning — three distinct points on the same progression, not overlapping work.

## 13. Testing & Validation Plan

- Every phase milestone's Pass Criteria requires real applies, verified via real AWS CLI/Console checks — not plan-only, not assumed from `terraform apply` succeeding alone
- Phase 3 onward: an AWS Budgets alarm is a required control, not a documented intention
- **Static analysis, decided (ADR-011): `tflint` + `checkov` (or `tfsec`) run before every real apply from Demo 22 onward** — closes the gap between real-apply demos starting (Demo 22) and Policy as Code landing (Demo 33). Read-only, non-destructive, no reason to defer it.
- Cross-reference hygiene: any demo renumbering must be checked against already-built, frozen demo content for stale forward-references (see ADR-008 — this was a real bug found and fixed, not a hypothetical)
- **Implementation convention, forward-only, not retroactive:** any new demo (Demo 22b onward, wherever the pattern next comes up) needing a provisioner-hosting resource with no real infrastructure behind it — the `null_resource` pattern Demo 13 taught — should use **`terraform_data`** instead, the current built-in-provider successor, requiring no separate `hashicorp/null` provider. **This does not apply retroactively** to Demo 13 or the Phase 1 milestone's own `null_resource.verify_queue_exists` — both are already built and audited, and this convention governs unbuilt content only.

## 14. Risks & Open Questions

| Item | Status |
|---|---|
| Demos 00, 01, 02, 04, 08 | **Confirmed, all read.** Demo 00: pure HCL/workflow fundamentals, zero AWS resources — genuinely out of scope for this milestone. Demo 01: confirmed the S3 state-backend claim (Part B builds a real remote backend). Demo 02: provider aliases/multi-region — genuinely out of scope, milestone is single-region/single-provider throughout. Demo 04: state surgery (import/mv/rm/recovery) — genuinely out of scope, not exercised in this milestone. Demo 08: **was missing from §10 entirely** — `data.aws_caller_identity` is used in this milestone's IAM role and directly traces to Demo 08's Part A; added as a component-inventory row. Grep sweep for stale cross-references still in progress, run independently by the user |
| Root volume / long-running-cost drift if teardown discipline slips | Accepted operational risk, mitigated by the Budgets alarm (§5, §11) and the notify-only EventBridge check (ADR-010), not eliminated — neither is prevention |
| **Compounding cost risk, not two independent ones** | The app chosen for portfolio depth (`retail-store-sample-app`) is also the heavier, JVM-based option — the same choice that increased teaching value also increased the pressure on an already-thin cost margin (§5). Worth remembering these aren't separable when re-evaluating either one |
| **Mid-course compute swap (ADR-019): flat EKS control-plane fee raises the cost of a slipped teardown** | Built (Demo 22d) — the risk itself is unchanged by building it: under EKS-primary, the control-plane fee (~$0.10/hr) accrues whether or not anything is deployed to the cluster, so the teardown checklist (§5) protects against a materially higher failure cost than it did before the swap, not the same one |
| **VERIFY 1 (Demo 22d) — `compute_config` may be missing required arguments** | Open, needs a live check. Checked against multiple independent real-world Auto Mode examples (including AWS's own CDK docs for the equivalent construct) — every one sets `node_pools` inside `compute_config`, and most also set a distinct `node_role_arn` for the Auto Mode-managed nodes. 22d's Lab now includes a best-effort corrected version with both added, but this correction is itself unverified against a real `terraform apply` — run `terraform plan` against the real, current `aws_eks_cluster` schema before trusting this block completely |
| **VERIFY 2 (Demo 22d vs. Demo 17) — security-group module version/shape conflict, unresolved** | Open, needs a live check. Demo 22d's `eks_sg` module call pins `terraform-aws-modules/security-group/aws` at `~> 5.0` using the older `ingress_cidr_blocks`/named-rule-string shape; **Demo 17 pins the identical module at `~> 6.0`** using a completely different keyed-map-of-objects shape — these two demos cannot both be correct as written. External evidence found so far favors 22d's shape, which is why Demo 17's own Verification Note now flags itself as "likely incorrect" rather than being silently rewritten — but **neither demo's version pin should be treated as confirmed** until checked against the module's real, current documentation. If resolved in Demo 17's favor instead, 22d's Concepts/Lab/Break-Fix all need rework to match |
| ~~IRSA/OIDC coupling moves IAM out of the "created once" bucket for compute-linked roles~~ | **Resolved by ADR-021, in the other direction than this row originally worried about.** This was a real consequence *if* IRSA had been built — Pod Identity replaces it instead, and Pod Identity associations have no OIDC-provider dependency, so they sit cleanly in the "created once, left standing" bucket after all. The concern this row raised no longer applies |
| ~~EKS Pod Identity vs. IRSA for Demo 22d/24~~ | **Resolved: Pod Identity, via ADR-021.** Confirmed with real 2026 evidence (AWS's current recommended default for new clusters; Auto Mode ships the EKS Pod Identity Agent as a pre-installed managed add-on; the one real limitation — no Fargate support — doesn't apply since this project runs Auto Mode on EC2-backed nodes, not EKS-on-Fargate). Written up as its own ADR, not a silent swap, per this row's own original requirement |
| ~~Demo 22's IRSA/OIDC time-box guardrail has a threshold still to be set~~ | **Moot, per ADR-021 — not resolved by picking a number, resolved by the guardrail no longer applying.** Pod Identity has no OIDC provider setup to time-box. Dropped from Demo 22d's checklist (§15); kept as a historical note in ADR-019 itself rather than silently deleted |
| **Domain coupling — `rselvantech.com`** | ACM/Route53 (Demo 20 onward) is wired to this specific, real, already-registered domain — confirmed in active use as of Demo 20, not a placeholder any longer. If it lapses or gets reused elsewhere, the dependent demos need re-pointing to a temporary Route53-registered test domain — the risk itself is unchanged by confirmation, just no longer hypothetical |
| ~~Phase 1's version pins predate Phase 2's~~ | **Resolved:** `Phase-1-Implementation.md` previously pinned Terraform `>= 1.9` / AWS provider `~> 5.0`, looser/older than Demos 14–21's `~> 1.15.0` / `~> 6.47.0`. Updated to match on request — the whole project now uses one common Terraform and AWS provider version, not just one common region |
| **Upstream source dependency** | This document's ADRs cite "Demo N's own text confirms..." repeatedly — that's only as reliable as the source material available in the session that wrote each ADR. Independent verification of those specific citations wasn't possible without the underlying demo files themselves; treat ADR citations as self-reported, not independently re-checked here |

---

## 15. Per-Demo Decision Checklist (Demos 22–30)

Generated by walking every ADR in Appendix A once and bucketing it by demo number — a reverse index, not a new decision layer. Built while writing this section: it immediately surfaced the Demo 22/23 sidecar-timing error just fixed above, exactly the kind of gap this checklist exists to catch before Demo 22 is actually built. Regenerate or spot-check this whenever a new ADR is added.

**Demo 22a — State Backend Bootstrap** *(sub-demo split from Demo 22 Part A, ADR-020 — Built)*
- Once, never torn down: project-layer S3 state backend with `use_lockfile = true` enabled, matching Demo 01's own locking pattern, via a small separate local-state bootstrap config (ADR-009, revised from an original S3+DynamoDB design)
- Verify: `terraform destroy`/`apply` cycle works cleanly against the S3 backend; confirm lock behavior via `use_lockfile` (e.g., a concurrent `apply` attempt is correctly blocked while the first is in progress)

**Demo 22b — Cost Governance** *(sub-demo split from Demo 22 Part A, ADR-020 — Built)*
- Once, never torn down: EventBridge+SNS notify (ADR-010), Budgets alarm two-threshold (§5), `tflint`/`checkov` local/interim (ADR-011)
- Verify: Budgets alarm and EventBridge notification both fire correctly on a test threshold

**Demo 22c — ECR/ACM Re-Creation** *(sub-demo split from Demo 22 Part A, ADR-020 — Built)*
- Once, never torn down: ECR re-create + repush (ADR-013), ACM re-request + revalidate (ADR-013)
- Verify: all 5 ECR repos re-populated; ACM cert shows `Issued`, not `Pending validation`

**Demo 22d — EKS: Single Service (UI only)** *(sub-demo split from Demo 22 Part B, ADR-020; swapped from ECS Fargate, ADR-019; IAM mechanism resolved to Pod Identity, ADR-021 — Built, with two open VERIFY items, see §14)*
- Torn down every session: VPC/SG module re-apply (§9), EKS cluster (Auto Mode — no OIDC identity provider needed, ADR-021), UI-only Kubernetes Deployment/Service + Ingress-to-ALB routing (ADR-005, ADR-019)
- Marks the teaching-rep → persistent-build shift (ADR-004); establishes the once-vs-per-session teardown scoping (ADR-017) later extended in ADR-018 — 22a/22b/22c fall in the once-only bucket, 22d in the every-session bucket
- Explicitly out of scope here: Catalog/Cart/Orders, any backing store — none of the app's other services are touched (ADR-012)
- **ALB mechanism, resolved, no live check needed at build time:** use EKS Auto Mode's built-in ALB support (a managed component, not a separate install) — create an `Ingress` with `IngressClass` controller `eks.amazonaws.com/alb`, and bind Demo 22c's ACM cert to it via `IngressClassParams`. Confirmed against AWS's own EKS Best Practices Guide and the documented `auto-configure-alb.html` mechanism; fits this demo's single-service, single-Ingress scope with no known gaps
- ~~Set the actual session-hour threshold for the ADR-019 IRSA/OIDC time-box guardrail~~ — **dropped, not deferred:** moot per ADR-021, since Pod Identity has no OIDC setup to time-box (see §14)
- **Objective:** the UI service is reachable over HTTPS through a real, AWS-managed ALB, with TLS terminated using Demo 22c's certificate
- Verify: UI reaches healthy via ALB; `kubectl get ingress` shows the ALB's real DNS name and confirms the `IngressClassParams` cert binding; a request to the Ingress's HTTPS endpoint returns the UI service's actual response, not a TLS or 5xx error

**Together, 22a+22b+22c reconstitute the original Demo 22 Part A exactly; 22d is the original Part B exactly (ADR-020) — total demo count and Demo 23-onward numbering are unaffected.**

**Demo 23 — EKS: Full Service Mesh** *(swapped from ECS Fargate, ADR-019 — Built)*
- Scales to all 5 services (5 Kubernetes Deployments/Services) + inter-service networking (ADR-005)
- Catalog MariaDB sidecar required, tied to Catalog's own pod, torn down every session (ADR-012, ADR-017) — Cart, Orders, Checkout, and UI all need zero additional infrastructure, run against their own built-in defaults (Checkout's own log confirms `Creating InMemoryRepository...`)
- **Corrected, not an open decision:** Catalog, Cart, Orders, and Checkout each get a `ClusterIP` Service only — internal, reached via UI's own service-to-service calls, matching `retail-store-sample-app`'s actual reference architecture. Confirmed against real sources, not assumed: the app's own README quickstart instructs `kubectl get svc ui` specifically for the frontend load balancer URL (singular, named, UI only); AWS's own "Getting started with Amazon EKS Auto Mode" blog post deploying this exact app annotates only the `ui` service with `aws-load-balancer-scheme=internet-facing`; the app's own architecture description states UI's role as aggregating calls to the other four services and rendering the HTML UI, not standing as a peer alongside them. **No Ingress or ALB decision applies here** — there's only ever one `Ingress` (UI's, built at 22d), so the `IngressGroup` limitation (Auto Mode doesn't support sharing one ALB across multiple `Ingress` resources) never arises in this project at all. **Correction, stated rather than silently overwritten:** an earlier round of this document generalized "all 5 services need routing" from the ALB/`IngressGroup` research without checking it against the app's real architecture, and proposed a three-option routing decision here that doesn't actually apply — the same class of gap this document has caught in itself before (Demo 22/23 sidecar timing, the Demo 01 misattribution). This is smaller and cleaner than that earlier framing implied, and is worth noting explicitly in the demo's own text rather than left implicit, the same way 22d's Pod Identity simplification was called out.
- **Objective:** UI reaches all four backend services over internal, DNS-based service-to-service calls (`catalog.default.svc.cluster.local`-style) — no new Ingress or ALB work at all
- Verify: Catalog reaches healthy via sidecar; Cart, Orders, Checkout, and UI all reach healthy with no extra infrastructure; cost table reflects the sidecar only (§5), not any additional ALB; confirm service-to-service connectivity from UI to all four backend services via internal DNS, not just that each pod is individually healthy

**Demo 24 — IAM Least Privilege (via EKS Pod Identity)** *(mechanism resolved from IRSA, which itself had replaced the original ECS task-role design — ADR-019, ADR-021 — Built)*
- Scopes only what exists at this point: ECR pull, CloudWatch, SNS/SQS (ADR-003, ADR-015)
- Mechanism: one IAM role per service, associated with its Kubernetes service account directly via the EKS Pod Identity API (`aws eks create-pod-identity-association`) — no OIDC identity provider, no per-role trust policy tied to a cluster-scoped issuer
- **Teardown bucket, resolved by ADR-021:** these associations are **created once, left standing** (ADR-017/018) — unlike the IRSA design originally planned, there's no cluster-anchored OIDC provider for them to depend on, so they don't need re-applying every session with the cluster
- Explicitly deferred: RDS/DynamoDB permissions — added later at Demo 26/27, not pre-scoped here (ADR-015)
- **Objective:** each service's pod can assume only its own scoped role, and no service can assume another's
- Verify: no policy statement references an RDS or DynamoDB ARN yet; each service's pod can assume only its own associated role (`aws sts get-caller-identity` from inside the pod matches the expected role ARN, and matches only that service's own role — cross-check by confirming a different service's pod cannot assume it)

**Demo 25 — VPC Extension: Isolated Subnets + Endpoints**
- Extends the persistent VPC with an isolated tier + S3 gateway endpoint, ahead of RDS's arrival at Demo 26
- No ADRs specific to this demo beyond the general VPC-persistence pattern (§9)

**Demo 26 — RDS**
- Swap-in step for both Catalog (sidecar → RDS) and Orders (H2 → RDS) (ADR-012)
- IAM policy grant added here, not pre-scoped at Demo 24 (ADR-015)
- Torn down and re-applied every session (ADR-017) — **consequence: RDS data does not persist across sessions**, only schema/infrastructure does (§3, §10)
- Verify: Catalog and Orders both connect to real RDS post-swap; confirm the data-non-persistence consequence doesn't break any Pass Criterion that assumes persisted data

**Demo 27 — DynamoDB**
- Swap-in step for Cart (built-in default → DynamoDB) (ADR-012)
- IAM policy grant added here, not pre-scoped at Demo 24 (ADR-015)
- **Left standing once created, not torn down every session** (ADR-018) — near-$0 idle cost. **Consequence: Cart's data DOES persist across sessions**, unlike RDS — deliberate asymmetry, not an inconsistency (§3, §10)
- Verify: Cart connects to real DynamoDB post-swap; confirm data actually does survive a session boundary as a positive test, not just assumed

**Demo 28 — Lambda + API Gateway**
- Must follow Demo 27 — targets DynamoDB, which didn't exist earlier in the original plan (dependency-ordering fix, applied during the renumbering rounds)
- Design confirmed: read-only `GET /analytics/orders` endpoint, same Lambda that processes the SNS event, reading the DynamoDB analytics table
- Left standing once created, not torn down every session (ADR-018) — pay-per-request pricing, near-$0 idle
- Verify: end-to-end SNS → Lambda → DynamoDB write, then a real `GET /analytics/orders` call against it

**Demo 29 — ECS Fargate** *(swapped from EKS, ADR-019 — same time-boxed role, direction reversed)*
- Time-boxed exception, not part of either ADR-017 bucket — stood up once, torn down once, after its own session, never revisited (ADR-018)
- Reuses Demo 26/27's existing RDS/DynamoDB instances, not separate ones (ADR-014, direction reversed: ECS now reuses EKS's stores)
- Needs ECS task security-group access into the isolated data tier — an implementation detail, not an open architectural question
- Uses ECS task roles for its own IAM identity — a real, worth-noting contrast with Demo 24's EKS Pod Identity associations, since this is the one demo in the series still using the older per-task-role model (and, incidentally, the one demo still resembling what the IRSA design would have looked like, structurally, before ADR-021 replaced it)
- Verify: the app runs correctly on ECS Fargate against the same data stores EKS already uses

**Demo 30 — CloudWatch Observability**
- Real telemetry from the running EKS deployment (and momentarily ECS Fargate during Demo 29's own session)
- Left standing once created, not torn down every session (ADR-018) — near-$0 at lab scale
- Extends Phase 1 Demo 09's pattern with genuine data for the first time

---

## Appendix A — Architecture Decision Records

**ADR-001 — App choice: `retail-store-sample-app` over Yelb**
*Decision:* Use `aws-containers/retail-store-sample-app` as the recurring e2e project app.
*Alternative considered:* Yelb — lighter, native Lambda/DynamoDB serverless mode, official S3 static-hosting pattern for its UI, cheaper to run continuously.
*Why chosen:* Wins on dimensions that compound over a multi-phase course — real polyglot persistence (RDS+DynamoDB coexisting), richer IAM/EKS/CI-CD teaching depth, stronger resume pedigree. Yelb's advantages (no Lambda bolt-on, lower cost) are both manageable, not blocking.
*Status:* Locked.
*Revisit if:* ongoing AWS cost becomes a harder constraint than portfolio depth — Yelb remains a legitimate fallback, not a compromise pick.

**ADR-002 — No NAT Gateway retrofit; Demo 16/17 stand as built**
*Decision:* NAT Gateway is provisioned once in Demo 16 (~$1.00/session) and reversed in Demo 17, as a deliberate cost lesson — not deferred to Phase 3 as an earlier draft assumed.
*Alternative considered:* Retroactively describe NAT as "deferred to Phase 3" to match a proposal written without seeing the actual built demo.
*Why chosen:* Demo 16/17 were already built and approved with this arc; correcting the planning docs to match reality was the right direction of correction, not rewriting already-built content to match an unverified assumption.
*Status:* Implemented, confirmed against real demo text.
*Revisit if:* never — this is closed.

**ADR-003 — IAM least-privilege deferred to Demo 24, not Phase 1** *(mechanism detail updated by ADR-021 — Pod Identity replaces IRSA)*
*Decision:* Phase 1 uses broad, self-trust IAM patterns; real least-privilege scoping waits until Demo 24, after real per-service compute identities exist to scope against — **since ADR-021, these are Pod Identity associations, not IRSA roles (nor ECS task roles, the original pre-ADR-019 design)**.
*Alternative considered:* Introduce least-privilege scoping earlier, in Phase 1.
*Why chosen:* Demo 10's own text confirms this was the original intent (verbatim: "deferring real least-privilege work to Phase 3, Demo 20" — now Demo 24 under current numbering); there's nothing real to scope against until per-service compute exists.
*Status:* Confirmed via Demo 10's real text.
*Revisit if:* never — sequencing is sound.

**ADR-004 — Teaching-rep (00–21) vs. persistent-build (22+) split**
*Decision:* Every Phase 1–2 demo tears itself down at its own Cleanup; Demo 22 begins a persistent environment that survives between sessions instead.
*Alternative considered:* Leave this distinction implicit, or make Phase 1–2 resources persist too.
*Why chosen:* Phase 1–2 is about learning mechanics safely in isolation; making anything persist early adds state-management risk with no teaching benefit. The switch at Demo 22 is where compute — and therefore a real running system — first becomes possible.
*Status:* Explicit, documented (§9).
*Revisit if:* never, for this project's stated goal of ending with one real system.

**ADR-005 — EKS split into two demos (single service, then full mesh)** *(content updated by ADR-019; the split itself is unchanged)*
*Decision:* Demo 22 deploys UI only, onto EKS; Demo 23 scales to all 5 services on the same cluster.
*Alternative considered:* One combined "EKS" demo deploying all 5 services at once.
*Why chosen:* Same one-primary-concept-per-demo sizing discipline already applied elsewhere in this series (e.g. Demo 16 keeping VPC scope tight) — proving the pattern end-to-end (cluster → Deployment → Service → Ingress/ALB routing, for one service) before scaling it up to a full mesh mirrors real incremental rollout, and keeps either demo from being oversized. The reasoning is identical to the original ECS-based version of this ADR; only the compute target changed (ADR-019).
*Status:* Locked, reflected in current numbering.
*Revisit if:* never.

**ADR-006 — Cross-Stack State demo dropped from Phase 2**
*Decision:* No dedicated "Cross-Stack State" demo in Phase 2. Demo 07 already teaches `terraform_remote_state` in full (a separate `consumer/` root config, its own state, zero write access).
*Alternative considered:* Add a new Phase 2 demo teaching the same mechanics against a VPC module's outputs instead of a single ARN.
*Why chosen:* Confirmed, not assumed — Demo 07's real content was checked directly. The mechanics are identical; only the data shape differs, which doesn't justify a new demo. This is the direct product of insisting on real content before finalizing a plan — the demo was proposed, redesigned once, and only fully dropped once Demo 07's actual text settled the question.
*Status:* Closed. Phase 5's cross-stack-state demo (now Demo 35) credits Demo 07 for the basics instead.
*Revisit if:* never, for this project.

**ADR-007 — "Only `dev` gets real applies" scoped as a Phase 3+ policy, not a Demo 18 rule**
*Decision:* The dev-only-real-applies policy takes effect starting Phase 3. Demo 18 itself applies both `dev` and `staging` for real, once, specifically to prove workspace state isolation.
*Alternative considered:* Describe Demo 18 as already enforcing dev-only applies.
*Why chosen:* Demo 18's own Lab directly contradicts that description — Part C's isolation verification has nothing real to check if only `dev` was ever applied. The policy is real and sensible, just scoped to where ongoing multi-session cost actually starts (Phase 3), not retrofitted onto a demo whose entire point was proving you can apply more than one workspace.
*Status:* Confirmed via Demo 18's real Lab content.
*Revisit if:* never.

**ADR-008 — Demo 10's stale cross-reference, fixed directly**
*Decision:* Demo 10's frozen text ("deferring real least-privilege work to Phase 3, Demo 20") was corrected to "Demo 24" after three rounds of renumbering left it pointing at the wrong (and now unrelated) demo number.
*Alternative considered:* Log it as build-debt, defer the fix.
*Why chosen:* A broken forward-reference is a factual-correctness fix, the same category as a typo — not a scope change requiring the "don't retroactively touch approved demos" caution applied elsewhere in this project.
*Status:* Fixed directly in the repo.
*Revisit if:* the grep sweep the user is running (§14) finds other instances of the same pattern.

**ADR-009 — Project-layer state: S3 using `use_lockfile` now, migrate to HCP Terraform at Demo 31** *(revised — see the reversal note below; originally specified an S3 backend with a DynamoDB lock table)*
*Decision:* From Demo 22a onward, the persistent build's own Terraform state lives in an S3 backend using `use_lockfile = true` for locking — the same locking mechanism Demo 01 taught, applied here at the persistent-build layer instead of the per-demo layer — distinct from each Phase 1–2 demo's own throwaway local/S3 state. State migrates to HCP Terraform as an explicit, taught step in Demo 31, not before.
*Bootstrap mechanics (added after review — the chicken-and-egg problem needed stating, not left implicit):* the S3 bucket can't be created by the same Terraform config that will use it as its backend — nothing exists yet to track that creation. Standard resolution, used here: a small, separate bootstrap root config, run once with **local** state, creates the S3 bucket (versioning + encryption enabled). Demo 22a's main config then points its `backend "s3"` block (with `use_lockfile = true`) at that bucket and runs `terraform init` (first-time init against the new backend, not a migration, since nothing was previously tracked in S3). This bootstrap config's own local state file is the one deliberate exception to "everything lives in the S3 backend" — it has nothing else to track once the backend it creates exists.
*Reversal — DynamoDB dropped, not just simplified:* the original version of this ADR specified an S3 backend with a DynamoDB lock table, the older, more widely-documented pattern. **`dynamodb_table` is a documented Terraform deprecation, superseded by `use_lockfile` (Terraform 1.10+)** — this project defaults to the current idiom rather than teaching a pattern Terraform itself is moving away from. This doesn't touch the Demo 31 HCP Terraform migration lesson: that lesson is about migrating an S3 backend generally, not specifically a DynamoDB-locked one — nothing about Demo 31's own content changes.
*Alternative considered:* Use HCP Terraform state from Demo 22a directly, since the project ends up there anyway. **Separately, on locking specifically:** keep DynamoDB locking anyway, for a more "historically typical" migration scenario at Demo 31 — many real-world HCP Terraform migrations in the wild are moving off exactly this older S3+DynamoDB pattern, which has its own pedagogical realism.
*Why chosen:* HCP Terraform isn't introduced as curriculum content until Demo 31 — starting there at Demo 22a would mean either teaching it five phases early (out of sequence) or using it silently without teaching it (inconsistent with how every other tool in this series is introduced before it's used). **On locking, separately:** the deprecation concern outweighs the "typical migration scenario" argument — teaching a deprecated pattern for the sake of matching a common real-world migration story isn't worth it when the current idiom (`use_lockfile`) is no harder to teach and doesn't require defending an intentionally-deprecated choice later. S3 with `use_lockfile` is the standard, current interim backend, and migrating to HCP Terraform in Demo 31 remains a real, valuable teaching moment regardless of which locking mechanism preceded it.
*Status:* Decision only — not yet built, since Demo 22a doesn't exist yet. Locked.
*Revisit if:* never, unless `use_lockfile` itself is later deprecated — or Demo 22a's actual design (built in the other session) has a reason to diverge from this.

**ADR-010 — Cost-control automation: notify, don't auto-destroy**
*Decision:* From Demo 22 onward, an EventBridge scheduled rule checks tagged resources against a session-length threshold and sends an SNS notification if exceeded. No Lambda force-destroys resources automatically.
*Alternative considered:* Pair the same EventBridge rule with a Lambda that force-destroys tagged resources after N idle hours — a fully enforced control, not just a nudge.
*Why chosen:* This is a single-learner lab, not shared production infrastructure. The failure mode of auto-destroy — idle-detection misfires and destroys real work-in-progress mid-session — is worse than the cost risk it solves. A notification gets most of the benefit (proactive, not memory-dependent, faster than the spend-based Budgets alarm) with none of that downside.
*Status:* Locked.
*Revisit if:* this environment ever stops being single-learner/personal-lab in nature — a shared or team environment would change this trade-off.

**ADR-011 — Static analysis (`tflint`/`checkov`) from Demo 22 onward, not deferred to Demo 33**
*Decision:* Every real apply from Demo 22 onward runs `tflint` + `checkov` (or `tfsec`) first — closing the gap between real applies starting and Policy as Code (Demo 33) landing.
*Alternative considered:* Leave Demos 22–30 on manual review alone until Demo 33's automated guardrail exists.
*Why chosen:* Unlike ADR-010's auto-teardown question, there's no real trade-off here — static analysis is read-only, non-destructive, and free. With 9 real-apply demos running before any automated check exists otherwise, there's no reason to defer a control that costs nothing to adopt.
*Status:* Locked.
*Revisit if:* never — this is a strictly-better-than-nothing addition with no identified downside.

**ADR-012 — Empirically tested per-service backend behavior for all 5 services; only Catalog needs a bootstrap sidecar (from Demo 23, when it's first deployed)**
*Decision:* Cart, Orders, Checkout, and UI deploy at Demo 23 with no additional infrastructure — all four run cleanly against their own built-in defaults. Catalog gets a lightweight MariaDB sidecar container (satisfying the `catalog-db` hostname it requires), scoped as Demo 23 bootstrap infrastructure tied to Catalog's own task lifecycle. **Demo 22 itself doesn't touch any of this — it's UI-only** (ADR-005); the per-service backend question only becomes live at Demo 23's full-mesh deploy. Demo 26 (RDS) swaps both Catalog and Orders onto real PostgreSQL; Demo 27 (DynamoDB) swaps Cart onto real DynamoDB. Checkout and UI never get a swap-in step — they have no backing store to swap, confirmed not assumed.
*Alternative considered (original, superseded):* Reorder Phase 3 so RDS and DynamoDB land before the full-service-mesh deploy. Rejected — same reasoning as before: it ripples through IAM scoping (Demo 24) and the isolated-subnet dependency (Demo 25), and invalidates numbering already communicated downstream.
*Alternative considered (intermediate, superseded):* Give all three services (Catalog, Cart, Orders) a lightweight sidecar container uniformly — the best-evidenced option available before direct testing, based on the official README's Terraform table (only EKS Minimal ships an official "skip RDS/DynamoDB" path) and a third-party build log pairing Cart with a `dynamodb-local` emulator. Superseded by direct evidence: Cart and Orders both run cleanly with zero sidecar, making a uniform three-service sidecar unnecessary infrastructure.
*Why chosen:* This is the one thing in the whole ADR-012 saga that stopped being inference — real `docker run` tests against the actual published images, no DB env vars set, with captured logs: Catalog's container exits within 15 seconds (`dial tcp: lookup catalog-db ... i/o timeout`, no fallback); Cart starts and stays running with zero DB-related log lines; Orders starts and stays running, and its own log states `Using dialect: org.hibernate.dialect.H2Dialect` and `Using in-memory messaging provider` — a genuine, documented-by-its-own-output in-memory default. This inverts what every prior version of this ADR assumed (an unsourced claim guessed Orders needed a real DB and Catalog/Cart didn't; the best-evidenced pre-test guess assumed all three needed help) — ground truth beat both.
*Status:* **Confirmed, empirically** — not "well-supported" or "primary-source-backed," actually tested against the real images.
*Revisit if:* the official images change their default startup behavior in a future release — worth a quick re-check if `retail-store-sample-app` gets bumped to a new major version before Demo 22 is actually built.

**ADR-013 — ECR and ACM re-created at Demo 22, not exempted from teardown; the Route53 hosted zone itself is a separate, standing exception**
*Decision:* Demo 19 (ECR) and Demo 20 (ACM **cert + validation record**) tear down at their own Cleanup like every other Phase 2 demo. Demo 22 Part A re-creates the ECR repo, re-pushes images, and re-requests/re-validates a **new** ACM cert — the same treatment already established for VPC (Demo 16/17). **The Route53 hosted zone itself is explicitly excluded from this teardown cycle.** It's created once — at or before Demo 20's first build, most plausibly manually or via a one-time apply outside the Demo 19/20/22 teaching-rep cycle entirely — and left standing continuously for the life of the project, independent of every ACM cert that gets validated against it. This has to be true for the design to work at all: destroying and recreating a Route53 hosted zone every Demo 20 rep (and again at Demo 22 Part A) would mean re-pointing nameservers at the domain registrar every single session, which is operationally absurd and isn't mentioned anywhere as a step. §5's cost table already prices the hosted zone as a flat, non-session-gated monthly fee, consistent with this — that pricing note was previously the only place this was stated; it's now also stated here and in ADR-018's bucket enumeration. **Mechanically, this means Demo 20's module reads the existing zone via a `data "aws_route53_zone"` lookup rather than creating one** — see the corresponding §10 row, added for the same completeness standard `data.aws_caller_identity` and `data.aws_vpc` got.
*Alternative considered:* Exempt ECR and ACM (cert) from teardown specifically, so their resources are already there when Demo 22 needs them.
*Why chosen:* An exception for the cert here breaks the "every Phase 1–2 demo tears down, no exceptions" guarantee the whole teaching-rep model depends on (§9), for the minor convenience of skipping a re-push/re-request. Consistency with the VPC precedent was worth more than the saved steps. The hosted zone is a genuinely different case, not an inconsistency with this reasoning — it's infrastructure the domain itself depends on continuously, not a teaching-rep artifact, so it was never a candidate for the teardown cycle in the first place; it simply hadn't been stated as its own explicit item before.
*Status:* Locked.
*Revisit if:* never — this closes a real gap the original §9/§8 left silent, and a second gap (the hosted zone's own lifecycle) that stayed implicit even after the first fix.

**ADR-014 — ECS Fargate (Demo 29) reuses Demo 26/27's RDS and DynamoDB, not separate instances** *(direction reversed by ADR-019 — was "EKS reuses ECS's stores," now "ECS reuses EKS's stores")*
*Decision:* The time-boxed ECS Fargate exercise connects to the same persistent RDS and DynamoDB instances Demo 26/27 already stood up for EKS, via appropriate network/security-group access for the ECS tasks — not a second, parallel set of data stores.
*Alternative considered:* Stand up ECS Fargate with its own RDS/DynamoDB, fully isolated from the EKS deployment.
*Why chosen:* ECS Fargate is explicitly a one-session, time-boxed exercise demonstrating the same app on a different compute layer — a second RDS instance for that would be a real, avoidable cost with no teaching benefit, and would undercut the "same app, two compute patterns" framing this comparison is supposed to make. This reasoning is unchanged from the original ADR-014 — only which compute layer is "primary" vs. "the comparison" flipped (ADR-019).
*Status:* Locked.
*Revisit if:* never, given ECS Fargate's time-boxed scope stays as currently defined.

**ADR-015 — IAM least-privilege scoped incrementally, not pre-scoped ahead of its targets**
*Decision:* Demo 24 scopes least-privilege IAM only for what exists at that point (ECR pull, CloudWatch, SNS/SQS) — not RDS/DynamoDB, since neither exists yet (they land at Demo 26/27). Demo 26 and Demo 27 each add the relevant IAM policy grant as part of their own swap-in step, alongside the connection-string change.
*Alternative considered:* Have Demo 24 pre-scope RDS/DynamoDB permissions in anticipation of Demo 26/27, even though those resources don't exist yet.
*Why chosen:* Pre-scoping access to resources that don't exist yet is a worse habit to teach than incremental scoping — it's not how least-privilege is actually practiced (you grant access to what's real, when it's real). This also keeps the same pattern already established for the in-memory→real-store swap (ADR-012): each backing store's own demo owns both halves of "make this connection real" — the connection itself and the permission to use it.
*Status:* Locked.
*Revisit if:* never — incremental scoping is the more defensible teaching pattern regardless of demo ordering.

**ADR-016 — Demo 22 split into Part A (Environment Bootstrap) / Part B (EKS teaching content)** *(content updated by ADR-019; the split itself is unchanged. Split into finer sub-demo granularity by ADR-020 — this ADR's own reasoning against renumbering is unchanged and still the operative constraint; only the number of sub-demos within Part A was revised.)*
*Decision:* Demo 22 is structured as two explicit parts. Part A covers one-time, non-teaching setup (state backend, cost-control automation, Budgets alarm, static analysis, ECR/ACM re-creation). Part B is the actual EKS — Single Service teaching content, including the cluster itself (ADR-019; no OIDC identity provider, per ADR-021's later Pod Identity adoption).
*Alternative considered:* Leave the six-plus bootstrap tasks folded into Demo 22 undifferentiated from its teaching content, or split them into a separately-numbered "Demo 22a," which would mean renumbering every subsequent demo again.
*Why chosen:* ADR-005 splits EKS specifically to avoid overloading one demo with teaching content — Demo 22 had, without anyone stating it, accumulated six bootstrap tasks that made it look like it violated that same principle. It doesn't, because those tasks are one-time administrative setup, not new concepts to learn — but that distinction needed to be stated, not left for a reader to assume. A Part A/B split states it explicitly without the cost of another renumbering pass.
*Status:* Locked. **See ADR-020 for the current sub-demo numbering (22a/22b/22c/22d) — this ADR's Part A/Part B content boundary is still the operative one; only its internal granularity changed.**
*Revisit if:* never — this resolves the ambiguity without disrupting numbering already communicated to the demo-building session.

**ADR-017 — "Teardown between sessions" scopes to cost-accruing resources only, not everything Demo 22 touches**
*Decision:* From Demo 22 onward, only cost-accruing compute/networking resources — NAT Gateway, ALB, EKS cluster/Auto Mode nodes, RDS instance — are destroyed and re-applied every session. Free or near-free foundational resources — the state backend, ECR repo, ACM cert, the EventBridge cost-control rule, the Budgets alarm, and (as of ADR-021) **IAM roles/policies including Demo 24's Pod Identity associations** — are created once, at Demo 22 Part A (22a/22b/22c) or Demo 24, and left standing for the rest of the project. **IAM was briefly a planned exception to this** under the IRSA design ADR-019 originally specified (its OIDC-anchored trust policies would have needed re-applying every session with the cluster) — ADR-021 replaced IRSA with Pod Identity specifically before that design was built, so the exception never materialized; IAM sits in the once-only bucket cleanly, same as everything else here.
*Alternative considered:* Treat "torn down between sessions" as applying uniformly to everything Demo 22 stands up, including Part A's bootstrap resources.
*Why chosen:* Surfaced by tracing ADR-016's own Part A/B split further — the state backend specifically **cannot** be destroyed and recreated every session without destroying the state history it exists to preserve, which would defeat its purpose. More generally, there's no cost reason to tear down free resources just because they were stood up alongside expensive ones — real-world teams don't re-provision their state backend, IAM roles, or DNS records every work session either.
*Status:* Locked. Component Inventory (§10) and §9 now state "once only, never torn down" explicitly for every Part A item, rather than leaving readers to infer it from context.
*Revisit if:* never — this is the correct, standard scoping for what "cost control via teardown" actually means.

**ADR-018 — ADR-017's teardown categorization extended to every Phase 3+ resource, not just Demo 22's** *(bucket membership updated by ADR-019 — see the IAM caveat below, new since the compute swap)*
*Decision:* Three explicit categories apply across the whole persistent build, not just what Demo 22 stands up:
1. **Torn down and re-applied every session** (cost-accruing): NAT Gateway, ALB, EKS cluster + Auto Mode nodes, RDS instance. **IAM does not ride in this bucket** — an IRSA design would have put it here (OIDC-anchored trust policies can't outlive the cluster), but ADR-021 replaced IRSA with EKS Pod Identity before that design was built, and Pod Identity associations have no such dependency — see bucket 2.
2. **Created once, left standing for the rest of the project** (free or near-$0 idle cost): state backend, ECR repo, ACM cert, EventBridge cost-control rule, Budgets alarm, DynamoDB, Lambda + API Gateway, CloudWatch Logs/Metrics, **EKS Pod Identity associations (Demo 24, ADR-021)**. **The Route53 hosted zone belongs here too (ADR-013) — with one distinction from the rest of this bucket: everything else here is first created at Demo 22 Part A, but the hosted zone predates that, created once at or before Demo 20's first build and simply never touched by any later teardown/recreate cycle, including Demo 20's own.**
3. **Time-boxed exception**: ECS Fargate — stood up once, torn down once, after its own one-session comparison exercise (Demo 29), never revisited. Neither "every session" nor "left standing forever." **This is the same slot EKS occupied before ADR-019 — the category itself didn't change, only which compute layer fills it.**
*Alternative considered:* Leave each later demo's designer to independently derive ADR-017's principle case by case, as each demo actually gets designed.
*Why chosen:* ADR-017 stated a real principle but was only applied to the resources that prompted it — the same silent-gap pattern this document has now caught and fixed several separate times (VPC persistence, ECR/ACM teardown, IAM pre-scoping, the IRSA/OIDC coupling surfaced by ADR-019, and now the Route53 hosted zone's own omission from this exact enumeration). Stating the categorization once, comprehensively, means whoever designs Demo 27, 28, or 30 inherits the answer instead of re-deriving it — and it surfaces a real, worth-stating consequence: RDS being torn down every session while DynamoDB is left standing means Cart's data persists across sessions and Catalog/Orders' doesn't. That's a deliberate, cost-driven asymmetry, not an inconsistency — but only if it's stated, which it now is (§3, §10).
*Status:* Locked.
*Revisit if:* actual per-service pricing at scale changes any resource's free/near-free classification — e.g. if CloudWatch Logs volume grows large enough that leaving it standing stops being near-$0.

**ADR-019 — EKS (Auto Mode) replaces ECS Fargate as the primary, persistent compute target; ECS Fargate becomes the time-boxed comparison exercise** *(IRSA/OIDC-specific detail below superseded by ADR-021 — Pod Identity replaces IRSA; the compute-layer decision itself is unaffected)*
*Decision:* From this point forward, EKS (Auto Mode) is the compute layer the persistent Phase 3–5 build actually runs on — Demo 22 (single service) and Demo 23 (full mesh) deploy to EKS, and the environment that carries forward through Phase 4 (CI/CD) and Phase 5 (capstone) is the EKS deployment. ECS Fargate moves to Demo 29, taking over the role EKS used to have: a deliberately time-boxed, one-session exercise showing the same app on a second compute layer, reusing Demo 26/27's existing RDS/DynamoDB instances rather than standing up its own. This is a direct swap of roles, not an addition of a second persistent target — the diagram note in §8 ("compute is drawn as X *or* Y, never both simultaneously live") still holds, with the labels reversed.
*Alternative considered:* Keep ECS Fargate as primary and leave EKS as the time-boxed exercise (status quo, the original design). Rejected because it works against the stated purpose of a portfolio/learning project when the learner is actively deepening Kubernetes skills — running the primary, most-repeated workload on the simpler, more-abstracted compute layer (ECS Fargate) spends the bulk of the project's hands-on repetition on the tool that teaches *less* of what's actually being learned right now.
*Alternative considered:* Run both compute layers as co-equal persistent targets (dual-track). Rejected — doubles the persistent-compute cost surface (two flat/ongoing compute bills instead of one) for a project whose budget is already modeled as a thin margin (§5), and contradicts the "never both simultaneously live" framing this document has used since §8 was first written; a comparison exercise makes the same teaching point without doubling the standing infrastructure.
*Why chosen:* For a portfolio/learning project specifically, "built and ran a real multi-service app on EKS" is a stronger, more differentiated resume story than the same claim about ECS Fargate, and ECS Fargate's simplicity — its main selling point in the original design — is precisely what makes it teach less Kubernetes. Most of the project's existing reasoning discipline (ADR-012's empirical per-service backend findings, the app choice, the cost-governance model, the teardown-categorization framework, Phase 1–2 content, the RDS/DynamoDB/Lambda decisions at Demo 25–28) is unaffected in substance, since it was derived either orchestrator-agnostically (ADR-012, tested via plain `docker run`) or from decisions that don't depend on which compute layer is primary. What genuinely changes, and is the real work of this swap: (1) Demo 22 Part B / Demo 23's actual teaching content — ECS task definitions/services become Kubernetes Deployments/Services, and ALB integration becomes either the AWS Load Balancer Controller (Ingress → ALB) or EKS Auto Mode's own built-in ALB support; (2) Demo 24's IAM mechanism — ECS task roles become IRSA, which needs an OIDC identity provider tied to the cluster, itself now torn down and re-applied every session (ADR-017/018's IAM caveat); (3) §5's cost model — EKS's flat, continuous control-plane fee replaces Fargate's pay-per-task model as the number that actually drives the budget conversation, which is why teardown discipline matters *more* under this design, not less; (4) ADR-005 and ADR-014 needed their content rewritten (not just search-and-replace) — ADR-005's split logic held, its labels didn't; ADR-014's reuse direction flipped outright; (5) the Fargate+EKS-Auto-Mode cost-control decision from §6, originally scoped to EKS as the *time-boxed* exercise, is confirmed to still make sense now that EKS is the thing running continuously — Auto Mode's built-in ALB support and lighter node-management overhead reduce point (1)'s complexity rather than adding to it, so no further change is needed there.
*Status:* Locked — a real architecture decision touching Demo 22/23/24/29 directly plus the cost model, not a rebuild of the whole Phase 3–5 plan. Demo numbering is unaffected; no renumbering cascade.
*Revisit if:* the learner's stated goal shifts away from deepening Kubernetes skills specifically, or EKS Auto Mode's pricing/feature set changes materially enough to undercut the "less node-management overhead, built-in ALB support" reasoning above before Demo 22 is actually built.
*Reaffirmed after comparative review (EKS-primary vs. ECS-primary, full project held constant):* Decision confirmed, not just re-asserted — the strongest argument turned out to be coherence with the learner's parallel `k8s-platform-labs` project: that's a compounding-depth argument (skills reinforce each other, lowering total time-to-competence), which matters specifically given the stated time-bandwidth constraint, not just resume signal in the abstract. Two gaps surfaced by that review are closed here rather than left as unaddressed risk:
- **Differentiation risk, previously unaddressed:** `retail-store-sample-app` on EKS closely follows AWS's own official EKS Workshop pattern, raising a real "did you just follow the tutorial" risk. This ADR's original reasoning never weighed that. Resolution: this isn't asymmetric between the two compute layers — the same app has an equally official `terraform/ecs/default` tutorial pairing (ADR-001, Appendix B) — so switching layers wouldn't fix it. **This project's actual differentiation is the ADR discipline, empirical `docker run`-verified findings, and cost-governance model layered on top of either compute target, not the compute target itself.** Whoever writes this project's README/portfolio framing should lead with that, not with "deployed retail-store to EKS" on its own.
- **Time risk from Auto Mode/IRSA being newer and less battle-documented than Fargate:** genuine, and distinct from the already-addressed cost risk. **Guardrail, binding on Demo 22d's design** *(sub-demo citation updated by ADR-020 — this was Demo 22 Part B at the time this guardrail was written)*: if EKS cluster + IRSA/OIDC setup isn't working within a bounded number of session-hours (a specific figure to be set when Demo 22d's Lab is actually written, based on real time spent), stop debugging open-endedly — document the failure mode as a real, empirically-confirmed finding (consistent with this project's existing standard for setbacks, e.g. ADR-012) and proceed with a documented workaround. This converts a stall into a legitimate troubleshooting story instead of an unbounded time sink. **Retired by ADR-021, not carried forward:** Pod Identity replaces IRSA, and there's no OIDC provider setup left to time-box — this guardrail is moot, not just relabeled. Kept here as a historical record of the reasoning at the time, rather than deleted, per this project's own discipline about not silently erasing superseded decisions.
- **Cost governance, underlined rather than changed:** the Budgets alarm and EventBridge notify-check (ADR-010, §5, §11) were already designed to catch exactly the flat-fee risk this swap introduces. Nothing new is needed architecturally — but given EKS's continuous control-plane fee, those controls move from "good practice" to load-bearing the moment Demo 22 goes live, and should be verified working *before* Demo 22b is considered done (sub-demo citation updated by ADR-020), not treated as a later nice-to-have.

---

**ADR-020 — Demo 22's Part A subdivided into 22a/22b/22c; Part B becomes 22d — granularity only, ADR-016's content split unchanged** *(22d's OIDC-identity-provider detail superseded by ADR-021 — Pod Identity replaces IRSA, no OIDC provider is created; the sub-demo boundary itself is unaffected)*
*Decision:* Demo 22's original Part A (ADR-016) is further subdivided into three letter-suffixed sub-demos: **22a** (project-layer state backend bootstrap — ADR-009), **22b** (cost governance — EventBridge+SNS notify, the two-threshold Budgets alarm, `tflint`/`checkov` interim static analysis — ADR-010/ADR-011), **22c** (ECR repo + ACM cert re-creation — ADR-013). The original Part B becomes **22d** (VPC/SG re-apply, EKS cluster + OIDC identity provider, UI-only Kubernetes deploy — ADR-005/ADR-019). Total demo count (39, 00–38) and Demo 23-onward numbering are **unaffected** — no renumbering cascade.
*Alternative considered:* Leave Demo 22 as the single Part A/Part B split ADR-016 established, with the four sub-concerns folded together undifferentiated inside "Part A" the way they were before this decision.
*Why chosen:* ADR-016 rejected a separately-numbered "Demo 22a" specifically because a full new demo number would force renumbering every subsequent demo (Demo 23 onward shifting). Letter-suffixed sub-demos don't trigger that mechanism at all — Demo 23 stays Demo 23, unchanged. ADR-016's actual protected concern (avoid a renumbering cascade) is fully honored here, not overridden — only a separate, narrower question (how many named sub-parts sit inside the already-established Part A/Part B boundary) is being revised. This is not a rescope: 22a+22b+22c together reconstitute exactly what ADR-016 called "Part A," with nothing added, dropped, or moved between the original two halves — confirmed by cross-checking the new sub-demo boundaries against ADR-009, ADR-010, ADR-011, and ADR-013's own content directly, not re-derived independently. Precedent for revising a "Locked... revisit if: never" decision this way already exists in this same document — ADR-019 revised ADR-005 and ADR-014's actual content via an explicit new ADR plus an annotation on the original, rather than a silent rewrite; this decision follows that identical pattern rather than inventing a new exception.
*Status:* Locked — supersedes ADR-016's granularity only, not its underlying Part-A/Part-B content boundary, which this decision preserves unchanged.
*Revisit if:* never, for the same numbering-stability reasons ADR-016 itself gave.

**ADR-021 — EKS Pod Identity replaces IRSA for Demo 22d/24's per-service IAM identity**
*Decision:* EKS Pod Identity replaces IRSA as the mechanism for Demo 22d/24's per-service IAM identity. **No OIDC identity provider is created at Demo 22d.** Role-to-service-account association happens via the EKS Pod Identity API (`aws eks create-pod-identity-association`) instead of an OIDC trust policy.
*Alternative considered:* Keep IRSA (status quo, ADR-019's original design) — the OIDC-federated mechanism this project had specified since the EKS-primary swap.
*Why chosen:* Four independent lines of evidence, checked rather than assumed: (1) **Pod Identity is AWS's current recommended default for new EKS clusters** — confirmed via real 2026 sources, not just a general impression; IRSA carries no deprecation timeline, so this is a "better default" call, not an "avoid the deprecated one" call, a meaningfully different and lower-urgency kind of decision than ADR-009's DynamoDB reversal. (2) **Pod Identity's one real limitation — no Fargate support — doesn't apply here.** This project's EKS build runs on Auto Mode's EC2-backed nodes, not EKS-on-Fargate; Demo 29's "ECS Fargate" comparison exercise is a completely different compute layer (ECS, not EKS), so the Fargate gap is a non-issue for this architecture, confirmed against the specific setup rather than assumed compatible. (3) **Directly confirmed, not inferred:** AWS's own EKS Best Practices Guide lists the "EKS Pod Identity Agent" as one of Auto Mode's pre-installed, managed add-ons — Auto Mode ships Pod Identity support out of the box as a first-class component, which is stronger evidence than general "AWS recommends it" guidance. (4) **Consistent with this project's own just-set precedent (ADR-009):** given a current-idiom-vs-more-mechanism-heavy tradeoff with no deprecation risk either way, this project has already decided to favor the current, real-job-idiomatic default — the DynamoDB→`use_lockfile` reversal made exactly this call, and Pod Identity vs. IRSA is the same shape of choice. IRSA's "more mechanism to understand OIDC federation" teaching argument is real but doesn't outweigh that precedent — and OIDC federation as a concept isn't lost from the curriculum regardless, since Demo 32's GitLab CI-to-AWS OIDC trust relationship (a separate, still-necessary federation) remains.
*Consequence, stated explicitly rather than left to be re-derived elsewhere:* removing the OIDC provider **simplifies** Demo 22d's scope and reopens a bucket-membership question ADR-017/018 previously answered for IRSA specifically — see the updated IAM row in §10 and the ADR-017/018 note below. It also makes the ADR-019 addendum's IRSA/OIDC session-hour time-box guardrail **moot** — there's no OIDC setup left to time-box. That guardrail is retired here, not carried forward as a phantom open item; see §14.
*Status:* Locked.
*Revisit if:* AWS materially changes Pod Identity's Fargate/Windows support in a way that affects this project's actual architecture, or the learner's goals shift toward needing IRSA specifically (e.g., a job requirement naming it explicitly).

## Appendix B — Decision Evidence

Per the rule established on review: an ADR gets a B-entry only if its "why chosen" cites something checked against a real external source (a demo's actual text, a real `docker run`, a real repo README, a real comparison table) — not pure internal design reasoning. ADR-002, ADR-004, ADR-005, ADR-009, ADR-010, ADR-011, ADR-013, ADR-014, ADR-015, ADR-016, ADR-017, ADR-018, ADR-019 are pure reasoning and get no entry here; that's not a gap, per the rule itself. **ADR-009 was previously misfiled with its own B.9 entry despite that entry admitting no external evidence was collected for it — corrected here by moving it into this list and dropping B.9, rather than tightening the rule's wording to fit it.**

### B.1 — ADR-001: App choice comparison (Yelb vs. `retail-store-sample-app`)

Recovered from earlier in this project's conversation history — ADR-001 referenced this as "retained in decision history, not repeated here in full," which left it a citation to nothing inside this document itself. Reconstructed here from that same conversation, not re-fetched externally.

**Phase 3 demo-by-demo verdict:**

| Demo | Yelb | `retail-store-sample-app` | Verdict |
|---|---|---|---|
| ECS Fargate | Cheaper to run continuously | Heavier (JVM), official `terraform/ecs/default` target | Tie — both officially supported |
| IAM Least Privilege | Simpler scoping surface | 5 services × multiple backends = more distinct policies | `retail-store` — more teaching depth |
| Lambda + API Gateway | Native serverless variant, no bolt-on | No native serverless mode | Yelb — clear win, official vs. invented |
| RDS | Native | Native | Tie |
| DynamoDB | Mutually exclusive with RDS (can't demo both live) | Coexists with RDS — real polyglot persistence | `retail-store` — demonstrates both live simultaneously |
| EKS | Official manifests exist | Official `eks/default` + `eks/minimal`, per-service Helm charts | `retail-store` — more thorough tooling |
| CloudWatch Observability | Infra-level capture only | Same baseline, plus native OTLP headroom | `retail-store` — same floor, more ceiling |

**Other factors:** S3 hosting (Yelb — official static-hosting pattern for its UI), API Gateway (Yelb — native fit for its serverless mode), ongoing AWS cost (Yelb — cheaper, non-JVM), CI/CD teaching depth (`retail-store` — 3-language monorepo, richer matrix-build material), resume/interview recognizability (`retail-store` — official AWS workshop pedigree, with a "did you just follow the tutorial" framing risk noted as a real caveat). VPC, ALB, ECR, Route53/ACM, SNS/SQS: ties, app-agnostic.

**Tally:** Yelb wins outright on Lambda+API Gateway, S3 hosting, API Gateway fit, and ongoing cost. `retail-store-sample-app` wins outright on IAM depth, DynamoDB (real coexistence), EKS/Helm tooling, and resume value. The decision went to `retail-store-sample-app` because those wins compound over a multi-phase course, while Yelb's wins (avoiding one bolt-on, lower cost) are both manageable — consistent with ADR-001's stated reasoning.

### B.3, B.6, B.7, B.8 — ADR-003, ADR-006, ADR-007, ADR-008: raw demo text

These ADRs each cite a specific demo's actual content (Demo 10's least-privilege deferral language, Demo 07's `terraform_remote_state` exercise, Demo 18's workspace Lab, Demo 10's stale cross-reference). **The raw source text isn't reproducible here** — it lives in each demo's own file, external to this document, and was read directly during the review sessions that wrote these ADRs rather than pasted into this document at the time. Only the citations already in each ADR's own text are on record. If bit-for-bit verification is ever needed, it requires re-reading Demos 07, 10, and 18 directly, not this appendix.

### B.12 — ADR-012: `docker run` test transcripts

Real commands, run by the user against a local minikube node (`minikube ssh`), real output pasted directly into this project's conversation — not reconstructed or summarized secondhand.

**Catalog** (`public.ecr.aws/aws-containers/retail-store-sample-catalog:latest`, no env vars):
```
docker ps --filter name=test-catalog
→ (empty — container had already exited)

docker logs test-catalog --tail 30
2026/08/22 06:00:37 Error: Failed to prep migration dial tcp: lookup catalog-db on 192.168.58.1:53: read udp 172.17.0.2:32937->192.168.58.1:53: i/o timeout
2026/08/22 06:00:37 Error: Failed to run migration dial tcp: lookup catalog-db on 192.168.58.1:53: read udp 172.17.0.2:32937->192.168.58.1:53: i/o timeout

curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8081/
HTTP 000
```

**Cart** (`public.ecr.aws/aws-containers/retail-store-sample-cart:latest`, no env vars):
```
docker ps --filter name=test-cart
→ Up 58 seconds

docker logs test-cart --tail 30
[Spring Boot startup, no DB-related lines at all]
Started CartApplication in 4.556 seconds (JVM running for 5.572)

curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8082/
HTTP 404   (expected — server up, no root route mapped)
```

**Orders** (`public.ecr.aws/aws-containers/retail-store-sample-orders:latest`, no env vars):
```
docker ps --filter name=test-orders
→ Up 43 seconds

docker logs test-orders --tail 30
HikariPool-1 - Starting...
HikariPool-1 - Start completed.
HHH000400: Using dialect: org.hibernate.dialect.H2Dialect
Using in-memory messaging provider
Started OrdersApplication in 8.103 seconds (JVM running for 9.297)

curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8083/
HTTP 404   (expected, same as Cart)
```

**Checkout** (`public.ecr.aws/aws-containers/retail-store-sample-checkout:latest`, no env vars):
```
docker ps --filter name=test-checkout
→ Up 50 seconds

docker logs test-checkout --tail 30
Creating InMemoryRepository...
[Nest] LOG [NestApplication] Nest application successfully started +75ms

curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8084/
HTTP 404   (expected — root not mapped; real routes are /health, /checkout/:customerId, etc.)
```

**UI** (`public.ecr.aws/aws-containers/retail-store-sample-ui:latest`, no env vars):
```
docker ps --filter name=test-ui
→ Up 48 seconds

docker logs test-ui --tail 30
[Spring Boot startup, no DB-related lines at all]
Started UiApplication in 5.44 seconds (JVM running for 7.031)

curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8085/
HTTP 303   (expected — UI root redirects, not an error)
```

---

## Key Takeaways

| Concept | Detail |
|---|---|
| A design document exists to make decisions traceable, not to slow work down | Every ADR above states why, and what would change the decision — not just what was decided |
| Real, already-built content always wins over a planning assumption | Every renumbering pass in this project's history was triggered by checking a proposal against real demo text, not by preference |
| "Deferred" and "not yet needed" are different claims | Least-privilege IAM, real VPC, and real compute are staged deliberately (Demo 24/16/22) — not gaps, sequencing |
| Teaching reps and a persistent build are genuinely different models, not the same thing at different scales | Conflating them (an earlier draft did) breaks the "nothing persists in Phase 1–2" guarantee the whole teaching approach depends on |
| A redundant demo is a real cost, not a free addition | Cross-Stack State was proposed, redesigned, and only dropped once Demo 07's actual content proved it taught nothing new |
| A renumbering pass isn't complete until already-built content is checked too | Demo 10's stale reference survived three renumbering passes because only the planning documents were kept in sync with each other |
| Cost control needs a mechanism, not just a number | An AWS Budgets alarm converts "hopefully my budget is enough" into an actual safety net — and even that is detection, not prevention |
| A document can be honest about its overall gaps and still overclaim in a specific spot | An independent review caught §10 stating Demo 01's role as fact while §14 listed Demo 01 as unread — both were true statements, just never checked against each other until reviewed |
| "What a demo teaches" and "what the persistent system needs to keep running" are two different questions | VPC's re-apply pattern (§8/§9) was stated explicitly from the start; ECR, ACM, and the app's backing-store timing weren't — the same class of gap, caught only once someone traced the full sequence end to end rather than checking each demo in isolation |
| "Torn down between sessions" needed its own scope, not just a location | Chasing a bootstrap-mechanics question down to its root revealed the cost-control model itself was underspecified — a state backend genuinely can't survive being destroyed every session, which forced stating explicitly what actually gets torn down versus what's created once |
| Even well-evidenced inference is still inference — a five-minute real test settled what three rounds of document analysis couldn't | The best-sourced guess before testing (all three services need a sidecar) was wrong for two of three services. A real `docker run` with captured logs beat every reading of documentation, official or third-party, because it's what actually happens, not what should plausibly happen |
| Stating a principle once doesn't mean it's been applied everywhere it holds | ADR-017 was correct but only checked against the resources that prompted it — DynamoDB, Lambda/API Gateway, and CloudWatch needed the same explicit categorization, not an assumption that the principle would obviously extend to them |
| Building the tool that prevents a failure mode can itself trigger that exact failure mode one more time | Writing §15's per-demo checklist — specifically to stop decisions from silently failing to propagate — immediately surfaced a real timing error (the Catalog sidecar attributed to "Demo 22/23" when Demo 22 is UI-only) that five prior review rounds on this exact ADR hadn't caught |
| The last "obviously fine, no need to test" assumption is exactly the one worth testing | Checkout and UI were flagged as reasonable assumptions for several rounds — cheap to verify, and worth doing once ground-truth testing had already overturned two out of three assumptions on the same underlying question |
| A mid-course infrastructure swap is contained exactly to the degree its dependencies were already made explicit | Swapping EKS and ECS Fargate's roles (ADR-019) touched only Demo 22/23/24/29 and the cost model precisely because §8's target-architecture diagram, §9's teardown categorization, and ADR-012's orchestrator-agnostic testing had already separated "what's true about this app" from "what's true about this specific compute layer" — the swap would have been far more invasive if those two things had been tangled together the first time around |