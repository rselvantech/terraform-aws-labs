# Complete Demo List — All Phases

> Handoff snapshot for the demo-building session, regenerated from
> `cloudnova-retail-store-e2e/docs/Solution-Architecture.md`'s current
> state (21 ADRs, §15 Per-Demo Decision Checklist, Appendix B evidence)
> — not a separately maintained living document. If this ever disagrees
> with `Solution-Architecture.md`, the architecture doc wins. Total: 39
> demos, 00–38, across 5 phases. **Regenerated after ADR-019** (EKS
> replaces ECS Fargate as the primary compute target for Demo 22/23;
> ECS Fargate moves to Demo 29 as the time-boxed comparison exercise)
> **and ADR-020** (Demo 22 subdivided into 22a/22b/22c/22d — sub-demo
> numbering granularity only; the 39-demo/00–38 total and Demo
> 23-onward numbering are unaffected, not a scope expansion).
> **This round also revised ADR-009** (S3 state backend now uses
> `use_lockfile`, not a DynamoDB lock table — deprecated pattern
> dropped before anything using it was built) **and added ADR-021**
> (EKS Pod Identity replaces IRSA for Demo 22d/24 — resolved, not an
> open item anymore; no OIDC provider is created at Demo 22d).
> **Also resolved this round:** the ALB mechanism for Demo 22d (Auto
> Mode's built-in ALB support, confirmed against real AWS docs — no
> live check deferred) and the naming convention for Phase 3+
> (`cloudnova-*` continues, not forked). **Demo 23's routing scope was
> corrected, not decided** — a prior round proposed a 3-option
> Ingress/ALB decision for all 5 services that turned out not to apply;
> confirmed against the app's own quickstart and AWS's own EKS Auto
> Mode deployment guide, only UI is externally routed, the other 4 get
> a `ClusterIP` Service only, and the `IngressGroup` limitation never
> arises here at all. **Demos 22a/22b/22c/22d/23/24 are now built**,
> not just planned — 22a/22b/22c/23/24 built clean; **22d has two
> genuine open VERIFY items** (compute_config's real required
> arguments; a security-group module version/shape conflict with
> Demo 17) needing a live check before being treated as confirmed
> correct — see Open Items below. **Neither
> `Phase-1-Implementation.md` nor `Phase-2-Implementation.md` is
> affected by any of this** — both are
> closed, audited, and predate Demo 22 entirely; no need to re-check
> either against this round's changes.

---

## Phase 1 — Demos 00–13 (built, unchanged)

| # | Demo | AWS service(s) / content | Status |
|---|---|---|---|
| 00 | tf-hcl-basics | — (language only, zero AWS) | Built — confirmed, full content |
| 01 | tf-fundamentals-s3 | S3 app bucket (v6 4-resource pattern) + S3 remote state backend, `use_lockfile` | Built — confirmed, full content |
| 02 | providers | Provider aliases, multi-region (us-east-2/us-west-2), lock file, `terraform providers lock` | Built — confirmed, full content |
| 03 | core-workflow | SNS + SQS scaffolding (topic → queue, policy, subscription) | Built — confirmed via objectives |
| 04 | state-management-backends | `terraform.tfstate` internals, `import`, `state mv`/`rm`, recovery from S3 versioning | Built — confirmed, full content |
| 05 | Variables in Depth | `aws_iam_role.deploy` + inline policy | Built — confirmed, full content |
| 06 | Locals in Depth | Same IAM role refined + introduces `aws_sns_topic.deploy_notifications` | Built — confirmed, full content |
| 07 | Outputs, Sensitivity, and Remote State | `aws_ssm_parameter` + full `terraform_remote_state` exercise (separate `consumer/` root config, zero write access) | Built — confirmed, full content |
| 08 | Data Sources: Reading Without Managing | `data` blocks only (`aws_caller_identity`, `aws_iam_policy`, conditional `count`, `aws_ami`), zero resources created | Built — confirmed, full content |
| 09 | expressions-functions | CloudWatch Logs + Metric Filters (`for_each`-driven) | Built — confirmed via objectives |
| 10 | multiplicity | SQS (`count`), S3+IAM users (`for_each`), security group (`dynamic`), `data.aws_vpc` lookup | Built — fully confirmed. Had a stale cross-reference bug, fixed directly (ADR-008) |
| 11 | state-addressing-multiplicity-migration | State mechanics on Demo 10's resources — `resource[0]` vs. `resource["key"]`, `moved` blocks | Built — fully confirmed |
| 12 | lifecycle | `create_before_destroy`/`prevent_destroy`/`ignore_changes`/`replace_triggered_by` | Built — fully confirmed |
| 13 | provisioners | Provisioners deep-dive | Built — fetched + verified |

---

## Phase 2 — Demos 14–21 (all 8 built and closed; Cross-Stack-State dropped entirely)

| # | Demo | Content | Status |
|---|---|---|---|
| 14 | Modules Basics | Local `sns-topic` module | Built |
| 15 | Public Registry Modules | `terraform-aws-modules/s3-bucket/aws` | Built |
| 16 | VPC Module | `terraform-aws-modules/vpc/aws`, 2 AZs, public/private, **NAT Gateway ON** (~$1.00/session) | Built |
| 17 | Three-Tier Modules | `terraform-aws-modules/security-group/aws`, generic `web`/`app`/`db`, NAT off | Built |
| 18 | Workspaces | `dev`+`staging` both genuinely applied once (to prove state isolation), `prod` in Exam Task only | Built |
| 19 | ECR Module | `terraform-aws-modules/ecr/aws` — real `retail-store-sample-app` images, verified publicly pullable, no auth. `us-east-2` | Built |
| 20 | ACM + Route53 Module | `terraform-aws-modules/acm/aws` on `rselvantech.com` (confirmed real domain), `us-east-2`, placeholder record. Cert + validation record torn down at Demo 20's own Cleanup like every Phase 2 demo — a new cert is re-requested at Demo 22c, not this one surviving. **The Route53 hosted zone itself is a separate, standing exception** — created once (at or before Demo 20's first build), never torn down, not part of this teardown cycle at all (ADR-013, ADR-018) | Built |
| 21 | Terraform Testing Basics | `terraform test` applied to the VPC (Demo 16, version pin verified matching: `~> 6.0`) and `sns-topic` modules | Built |

**Cross-Stack State does not exist as a demo.** Confirmed redundant with
Demo 07's full `terraform_remote_state` exercise (ADR-006) — Demo 07's
real content already covers the mechanics a new demo would have taught.
Phase 5's Demo 35 credits Demo 07 for the basics instead.

---

## Phase 3 — Demos 22–30

Full per-demo decision reverse-index (every applicable ADR, verification
checklist) lives in `Solution-Architecture.md` §15 — reproduced here at
summary level.

| # | Demo | Scope | Note |
|---|---|---|---|
| 22a | State Backend Bootstrap | Project-layer S3 state backend with `use_lockfile = true` (revised from an original S3+DynamoDB design — `dynamodb_table` is deprecated, ADR-009), via a small separate local-state bootstrap config — once only, never torn down | Built |
| 22b | Cost Governance | EventBridge+SNS cost-control notify, two-threshold Budgets alarm, `tflint`/`checkov` interim static analysis — once only, never torn down (ADR-010/011) | Built |
| 22c | ECR/ACM Re-Creation | ECR repo re-creation + image re-push, ACM cert re-request + re-validation — once only, never torn down (ADR-013) | Built |
| 22d | EKS — Single Service (**UI only**) *(swapped from ECS Fargate, ADR-019; IAM resolved to Pod Identity, ADR-021)* | **Persistent-build begins here** (ADR-004). VPC/SG re-apply + EKS cluster (no OIDC provider needed, ADR-021) + UI-only Kubernetes Deployment/Service/Ingress teaching content, torn down every session. **ALB mechanism resolved:** Auto Mode's built-in ALB support (managed, no separate controller install), ACM cert bound via `IngressClassParams`. **Two open VERIFY items — see Solution-Architecture.md §14:** (1) `compute_config` may be missing required `node_pools`/`node_role_arn` arguments; (2) security-group module version/shape conflicts with Demo 17 | Built, unverified in two places |
| 23 | EKS — Full Service Mesh *(swapped from ECS Fargate, ADR-019)* | Scales to all 5 services. **Empirically tested, not inferred (ADR-012, orchestrator-agnostic):** Catalog fails without a real DB, needs a lightweight MariaDB sidecar (torn down every session, tied to its own pod). Cart, Orders, Checkout, UI all run cleanly standalone — zero extra infrastructure (Orders uses built-in H2; Checkout's own log states `Creating InMemoryRepository...`). **Corrected, not an open decision:** Catalog, Cart, Orders, Checkout each get a `ClusterIP` Service only (internal, reached via UI's own service-to-service calls) — confirmed against the app's own quickstart and AWS's own EKS Auto Mode deployment guide, only UI is externally routed. No Ingress/ALB decision applies — there's only ever one `Ingress` (UI's, from 22d), so the `IngressGroup` limitation an earlier round raised here never actually arises | Built |
| 24 | IAM Least Privilege (via EKS Pod Identity) | Scopes only what exists at this point: ECR pull, CloudWatch, SNS/SQS. **Mechanism: EKS Pod Identity associations (ADR-021), no OIDC provider — created once, left standing**, not re-applied every session. RDS/DynamoDB permissions explicitly NOT pre-scoped — added later at Demo 26/27 (ADR-015) | Built |
| 25 | VPC Extension — Isolated Subnets + Endpoints | Extends the persistent VPC with an isolated tier + S3 gateway endpoint, ahead of RDS | — |
| 26 | RDS | Catalog + Orders swap-in (sidecar→RDS for Catalog, H2→RDS for Orders) + IAM policy grant added here (ADR-012, ADR-015). **Torn down every session — RDS data does NOT persist across sessions** (ADR-017/018) | — |
| 27 | DynamoDB | Cart swap-in (built-in default→DynamoDB) + IAM policy grant added here (ADR-012, ADR-015). **Left standing, near-$0 — Cart's data DOES persist across sessions**, deliberate cost-driven asymmetry with RDS (ADR-018) | — |
| 28 | Lambda + API Gateway | SNS → Lambda → Demo 27's DynamoDB. **Design confirmed:** read-only `GET /analytics/orders` endpoint, same Lambda, reading the analytics table. Left standing, near-$0 (ADR-018) | Must follow Demo 27 (dependency-ordering fix) |
| 29 | ECS Fargate *(swapped from EKS, ADR-019 — same time-boxed role, reversed)* | Time-boxed exception — stood up once, torn down once, never revisited (ADR-018). Reuses Demo 26/27's existing RDS/DynamoDB, not separate instances (ADR-014, reversed direction). Needs ECS task SG access into the isolated data tier | — |
| 30 | CloudWatch Observability | Real telemetry from the running EKS deployment (and momentarily ECS Fargate during Demo 29's session). Left standing, near-$0 (ADR-018) | — |

---

## Phase 4 — Demos 31–34

| # | Demo | Scope |
|---|---|---|
| 31 | HCP Terraform | Migrates the project-layer state (S3, `use_lockfile` — ADR-009) to HCP Terraform — a real, taught migration step |
| 32 | CI/CD (GitLab CI override) | Build → ECR (Demo 19) → plan/apply → EKS (Demo 22/23), `dev`-only real applies. **OIDC federation assigned here** (no static IAM keys). This is the only OIDC trust relationship this project builds — Demo 24's IAM identity goes through EKS Pod Identity instead (ADR-021), which involves no OIDC provider at all. Also formalizes `tflint`/`checkov` into the pipeline |
| 33 | Policy as Code | Enforces `dev`-only real applies programmatically |
| 34 | DevSecOps Scanning | Container image + IaC scanning, extending Demo 32's pipeline — complements, not redundant with, the interim Demo 22b/formalized Demo 32 static analysis |

---

## Phase 5 — Demos 35–38

| # | Demo | Scope | Note |
|---|---|---|---|
| 35 | Cross-stack state | Real VPC/app/data stack separation, integration-scale | Basics credited to Demo 07, not a dropped Phase 2 demo |
| 36 | Drift and Import | Phase 1 Demo 04 techniques, real multi-service scale | Unchanged in substance |
| 37 | Terraform Testing | Integration-level tests on the real stacks | Basics credited to Demo 21 |
| 38 | Capstone | Full rebuild/validation, empty account to running app | Portfolio deliverable |

---

## Naming convention

Every Phase 1 resource is prefixed `cloudnova-*`. **Demo 19 has since
settled this for ECR specifically** — all 5 repos use
`cloudnova-retail-<service>`, confirmed and built. **Still not decided:**
whether the same prefix carries into Phase 3's EKS cluster/node naming
or RDS/DynamoDB resources, or gets replaced by something derived from
`retail-store-sample-app`'s own service names — narrowed from a
whole-Phase-3 open item to just this, flag it for a decision before
Demo 22d locks in a naming scheme (22a/22b/22c's bootstrap resources
don't need this decided first).

## Repository structure

Terraform code for each phase lives under
`cloudnova-retail-store-e2e/src/terraform/phase-N/`, embedded in that
phase's `docs/Phase-N-Implementation.md` (file-path-labeled code blocks,
e.g. `**src/terraform/phase-1/providers.tf:**`) rather than existing as
standalone `.tf` files yet. Reserved, not-yet-used folders:
`src/terraform/bootstrap/` (ADR-009's state backend, first needed Demo
22a), `src/terraform/modules/` (Phase 2, Demo 14 onward),
`src/terraform/phase-3-onward/` (the persistent build). See
`Solution-Architecture.md` §2a for the full layout including `.gitignore`,
`terraform.tfvars.example` vs. gitignored `terraform.tfvars`, and README
placeholders.

## Open items

- **Grep sweep** (stale cross-references across already-built demos,
  same pattern as Demo 10's ADR-008 fix) — in progress, run
  independently by the project owner
- ~~Naming convention continuity into Phase 3~~ — **resolved:**
  `cloudnova-*` continues throughout, including EKS/RDS/DynamoDB
  resources — not forked to app-derived names. Consistency with 19
  already-built demos' naming, no functional reason to fork the
  convention partway through
- ~~EKS Pod Identity vs. IRSA for Demo 22d/24~~ — **resolved: Pod
  Identity, via ADR-021.** No OIDC provider is created at Demo 22d.
  Confirmed against real 2026 evidence (AWS's current recommended
  default; Auto Mode ships the EKS Pod Identity Agent as a
  pre-installed managed add-on; the one real limitation — no Fargate
  support — doesn't apply, since this project's EKS build runs on
  Auto Mode's EC2-backed nodes, not EKS-on-Fargate)
- ~~Region~~ — **resolved:** `us-east-2`, one common region across the
  whole project, evidenced by Demos 14–21's consistent use throughout
  Phase 2 and now applied to Phase 1's milestone too (was `us-east-1`,
  updated for project-wide consistency — no functional dependency, so
  no risk in the change)
- ~~Domain~~ — **resolved:** `rselvantech.com`, confirmed real and in
  active use since Demo 20
- **VERIFY 1 (Demo 22d) — `compute_config` may be missing required
  arguments, open, needs a live check.** Every independently-checked
  real-world Auto Mode example sets `node_pools` inside
  `compute_config` (and usually a distinct `node_role_arn`) — 22d's
  Lab now includes a best-effort corrected version with both added,
  but it's unverified against a real `terraform apply`
- **VERIFY 2 (Demo 22d vs. Demo 17) — security-group module
  version/shape conflict, open, needs a live check.** 22d pins
  `terraform-aws-modules/security-group/aws` at `~> 5.0` with the
  older list-based shape; Demo 17 pins the same module at `~> 6.0`
  with a keyed-map shape — these can't both be correct as written.
  External evidence favors 22d's shape; neither pin should be treated
  as confirmed until checked against the module's real documentation
- Everything else: either empirically confirmed (ADR-012, all 5
  services tested via real `docker run`), read directly from primary
  source (Demos 00–13 in full), or a clearly-marked, reasoned plan
  (14–15, 19–38)