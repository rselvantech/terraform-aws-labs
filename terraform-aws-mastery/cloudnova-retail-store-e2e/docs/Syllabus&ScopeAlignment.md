# Syllabus & Scope Alignment — vs. Target E2E Solution

> Handoff snapshot for the demo-building session, generated from
> `cloudnova-retail-store-e2e/docs/Solution-Architecture.md`'s current
> state — not a separately maintained living document.
> `Solution-Architecture.md` is the source of truth for anything this
> document might drift from later. This snapshot reflects every
> empirical finding and every propagation-gap fix made across this
> project's full review chain, through ADR-021 (EKS Pod Identity
> replaces IRSA for Demo 22d/24 — no OIDC provider is created; resolves
> what was an open item as of the prior round). **Also resolved this
> round:** the ALB mechanism for Demo 22d (Auto Mode's built-in ALB
> support, confirmed against real AWS docs) and the naming convention
> for Phase 3+ (`cloudnova-*` continues). **Demo 23's routing scope was
> corrected, not decided** — the prior round's proposed 3-option
> Ingress/ALB decision for all 5 services didn't apply; confirmed
> against the app's own quickstart and AWS's own EKS Auto Mode
> deployment guide, only UI is externally routed (built at 22d), the
> other 4 get a `ClusterIP` Service only, and the `IngressGroup`
> limitation never arises in this project at all. ADR-009's revision
> (S3 state backend
> now uses `use_lockfile`, not a deprecated DynamoDB lock table) and
> the `terraform_data` forward guidance from the prior round both still
> apply. `Phase-1-Implementation.md` and `Phase-2-Implementation.md`
> are both unaffected by any of this — closed, audited, predate Demo 22.

---

## Phase 1 (Demos 00–13) — No changes required, all fully confirmed

All 14 demos now have confirmed content — full text for 00–13 except
03/09, which are confirmed at the objectives level. Phase 1 needs no
retroactive content changes. Two points worth carrying forward
explicitly, since later phases depend on them:

- **Demo 08's `data.aws_caller_identity`** is directly reused in the
  Phase 1 milestone's IAM role — this was found missing from
  `Solution-Architecture.md`'s Component Inventory on review and has
  since been added. If Phase 3+ demos use `data.aws_caller_identity`
  again (likely, for any account-ID-scoped IAM policy), Demo 08 is the
  correct citation.
- **Demo 10's `data.aws_vpc` lookup** — per Demo 08's own text, this
  pattern belongs to Demo 10, not Demo 08. Worth keeping straight
  if Phase 3 demos need a similar default-VPC-style lookup pattern
  before Demo 16's real VPC exists.

---

## Phase 2 (Demos 14–21) — 5 existing demos unchanged, 3 new demos, one dropped

### Demos 14–18 — unchanged, as already built and verified

No content changes.

### Demo 19 — ECR Module *(new)*

`terraform-aws-modules/ecr/aws` — verified live, real, adopted module.
Real repos created; `retail-store-sample-app`'s actual published
container images pulled and pushed — **verified publicly pullable, no
auth required**, via the Amazon ECR Public Gallery
(`public.ecr.aws/aws-containers/retail-store-sample-<service>`). Taught
as registry-module practice, extending Demo 15's theme — not a
standalone "learn ECR" lesson.

### Demo 20 — ACM + Route53 Module *(new)*

`terraform-aws-modules/acm/aws` — verified live, real module.
Certificate requested/validated against `rselvantech.com` (confirmed
real, already-registered domain — not a placeholder), in `us-east-2`
(confirmed as the locked Phase 3+ region); no ALB
exists yet, so the demo validates the cert and leaves the record
pointed at a placeholder. **This cert object is a teaching rep, torn
down at Demo 20's own Cleanup like every other Phase 2 demo — it does
not survive to Demo 22.** Demo 22c *(sub-demo split by ADR-020)*
re-requests and re-validates a
new ACM cert from scratch, alongside re-creating Demo 19's ECR repo
(ADR-013). **The Route53 hosted zone itself is a separate, standing
exception to all of this** — created once, at or before Demo 20's
first build, and never torn down at all (not at any Demo 20 rep, not
at Demo 22c) — every ACM cert validated against it, this one and
the one re-created later, points at the same standing zone (ADR-013,
ADR-018; §5's cost table already prices it as a flat, non-session-gated
fee, consistent with this). Same registry-module-practice framing as Demo 19.

### Cross-Stack State — dropped entirely, not built

**Confirmed redundant, not just at risk.** Demo 07's Part B already
builds a full `terraform_remote_state` exercise: a separate
`consumer/` root configuration, its own state, own `provider` block,
reading `role_arn`/`sns_topic_arn` back from the main configuration
with zero write access. The mechanics a new demo would have taught are
identical — only the data shape would differ (a VPC module's list
outputs vs. a single ARN), which doesn't justify a whole new demo
(ADR-006). Phase 5's cross-stack-state demo (Demo 35) credits Demo 07
for the basics instead.

### Demo 21 — Terraform Testing Basics *(new, renumbered from a dropped position)*

`terraform test` framework fundamentals (`run` blocks, assertions)
applied to the VPC module (Demo 16) and the local `sns-topic` module
(Demo 14). Pulls forward Phase 5 Demo 37's entire subject — testing
modules is a natural extension of building them, taught while they're
still fresh.

---

## Phase 3 (Demos 22–30) — Full scope, empirically grounded per-service backend decisions

### Demo 22 — EKS: Single Service (UI only) *(swapped from ECS Fargate — ADR-019; split into 22a/22b/22c/22d — ADR-020)*

**This is where the persistent-build environment begins** (ADR-004).
Originally structured as two explicit parts (ADR-016), then further
subdivided into four letter-suffixed sub-demos (ADR-020) — a
numbering-granularity change only, not a rescope: 22a+22b+22c together
reconstitute the original Part A exactly, 22d is the original Part B
exactly. Demo 23-onward numbering is unaffected.

- **22a — State Backend Bootstrap, once only, never torn down
  (ADR-009, ADR-017) — Built:** the project-layer S3 state backend with
  `use_lockfile = true` (revised from an original S3+DynamoDB design —
  `dynamodb_table` is a documented Terraform deprecation), bootstrapped
  via a separate local-state config first.
- **22b — Cost Governance, once only, never torn down (ADR-010,
  ADR-011, ADR-017) — Built:** EventBridge+SNS cost-control notification
  (notify-only, not auto-destroy), two-threshold AWS Budgets alarm
  (§5), `tflint`/`checkov` static analysis (interim, local).
- **22c — ECR/ACM Re-Creation, once only, never torn down (ADR-013,
  ADR-017) — Built:** ECR repo re-created + images re-pushed, ACM cert
  re-requested + re-validated.
- **22d — EKS: Single Service, re-applied every session (ADR-005,
  ADR-017, ADR-019, ADR-021) — Built, with two open VERIFY items (see
  below):** VPC/SG module re-apply, the EKS cluster
  itself (Auto Mode — no OIDC identity provider needed, per ADR-021's
  Pod Identity adoption), and the actual teaching
  content — ECR image → Kubernetes Deployment/Service →
  Ingress-to-ALB routing, for the **UI service only**. **ALB mechanism
  resolved, no live check needed:** Auto Mode's built-in ALB support
  (a managed component, not a separate install) — create an `Ingress`
  with `IngressClass` controller `eks.amazonaws.com/alb`, bind 22c's
  ACM cert via `IngressClassParams`. Confirmed against AWS's own EKS
  Best Practices Guide and documented `auto-configure-alb.html`
  mechanism; fits this demo's single-service, single-Ingress scope
  with no known gaps. **Two genuine open items surfaced during the
  actual build, unresolved:** (1) `compute_config { enabled = true }`
  is very likely missing required arguments — every independently-
  checked real Auto Mode example also sets `node_pools` and usually a
  distinct `node_role_arn`; the Lab now includes a best-effort
  corrected version, unverified against a live `apply`; (2) 22d's
  security-group module call (`~> 5.0`, list-based shape) directly
  contradicts Demo 17's pin of the identical module (`~> 6.0`,
  keyed-map shape) — these can't both be right as written, and
  external evidence currently favors 22d's shape, but neither pin is
  confirmed. See `Solution-Architecture.md` §14 for both. ALB
  provisioned; the ACM cert + Route53 record
  re-created in 22c (same
  pattern Demo 20 taught, a new object, not the Demo 20 one) are
  pointed at it for the first time. NAT Gateway re-applied as part of
  the persistent VPC, not created fresh. **The cluster is torn down
  and re-applied every session along with
  everything else in 22d** — EKS's flat control-plane fee means
  there's no cost argument for leaving it standing, unlike 22a/22b/22c's
  near-free bootstrap resources.
  **Objective:** the UI service is reachable over HTTPS through a real,
  AWS-managed ALB, with TLS terminated using 22c's certificate.
  **Verify:** `kubectl get ingress` shows the ALB's real DNS name and
  confirms the cert binding; a request to the Ingress's HTTPS endpoint
  returns the UI service's actual response, not a TLS or 5xx error.

**Demo 22 (all four sub-demos) does not touch Catalog, Cart, Orders,
or Checkout at all.**

### Demo 23 — EKS: Full Service Mesh *(swapped from ECS Fargate — ADR-019 — Built)*

Scales from Demo 22d's single UI service to all 5
`retail-store-sample-app` services, plus inter-service networking.
Confirmed as the primary, persistent-into-Phase-4/5 compute target
**as of ADR-019** — this reverses the original design, where ECS
Fargate held this role and EKS was the time-boxed exercise; ECS
Fargate now fills that role instead, at Demo 29.

**Per-service backend behavior — empirically tested, not inferred
(ADR-012), and orchestrator-agnostic.** Real `docker run` tests against
the actual published images, no DB environment variables set — this is
the single best-evidenced finding in the whole document, and it
inverted two prior hypotheses along the way (an unsourced claim guessed
Orders needed a real DB and Catalog/Cart didn't — backwards; a
best-evidenced-but-untested guess assumed all three needed a sidecar —
wrong for two of three). **Because this was tested via plain `docker
run` rather than against ECS or EKS specifically, the ADR-019 compute
swap doesn't touch this table at all:**

| Service | Result | What the logs actually showed |
|---|---|---|
| Catalog | **Fails** — exits within 15 seconds | `dial tcp: lookup catalog-db ... i/o timeout` — no fallback exists |
| Cart | **Runs clean** | Full Spring Boot startup, zero DB-related log lines |
| Orders | **Runs clean** | `Using dialect: org.hibernate.dialect.H2Dialect` + `Using in-memory messaging provider` — genuine built-in defaults |
| Checkout | **Runs clean** | `Creating InMemoryRepository...` — explicit, positive confirmation |
| UI | **Runs clean** | Full Spring Boot startup, zero DB-related lines, expected redirect on root |

**Decision:** Catalog gets a lightweight MariaDB sidecar container
(satisfying the `catalog-db` hostname it requires) at Demo 23, tied to
Catalog's own pod lifecycle (a sidecar container in the same pod spec,
not a separate Deployment), torn down every session. Every other
service needs zero additional infrastructure. Full test transcripts
for all 5 services are preserved in `Solution-Architecture.md`
Appendix B.12 — worth reading directly before designing this demo's
Lab, rather than re-deriving from this summary alone.

**Corrected, not an open decision.** Catalog, Cart, Orders, and
Checkout each get a `ClusterIP` Service only — internal, reached via
UI's own service-to-service calls, matching
`retail-store-sample-app`'s actual reference architecture. Confirmed
against real sources, not assumed: the app's own README quickstart
instructs `kubectl get svc ui` specifically to get the frontend load
balancer's URL (singular, named, UI only); AWS's own "Getting started
with Amazon EKS Auto Mode" blog post, deploying this exact app,
annotates only the `ui` service with
`aws-load-balancer-scheme=internet-facing` — no equivalent step for
the other four; the app's own architecture description states UI's
role as aggregating API calls to the other services and rendering the
HTML UI, not standing as a peer alongside them. **No Ingress or ALB
decision applies here** — there's only ever one `Ingress` (UI's, built
at 22d), so the `IngressGroup` limitation (Auto Mode doesn't support
sharing one ALB across multiple `Ingress` resources) never arises in
this project at all.

**Correction, stated rather than silently overwritten:** an earlier
round of this document generalized "all 5 services need routing" from
the ALB/`IngressGroup` research without checking it against the app's
real architecture, and proposed a three-option routing decision here
that doesn't actually apply — the same class of gap this project has
caught in itself before (the Demo 22/23 sidecar timing, the Demo 01
misattribution). This is smaller and cleaner than that earlier framing
implied — worth stating explicitly, the same way 22d's Pod Identity
simplification was called out rather than left implicit.

**Objective:** UI reaches all four backend services over internal,
DNS-based service-to-service calls (`catalog.default.svc.cluster.local`-
style) — no new Ingress or ALB work at all. **Verify:** confirm
service-to-service connectivity from UI to all four backend services
via internal DNS, not just that each pod is individually healthy; cost
table reflects the sidecar only (§5), not any additional ALB.

### Demo 24 — IAM Least Privilege (via EKS Pod Identity) *(mechanism resolved from IRSA — which itself had replaced the original ECS task roles — ADR-019, ADR-021 — Built)*

Must follow Demo 23 — real per-service compute identities now exist to
scope policies against. **Since ADR-021, this means EKS Pod Identity: one
IAM role per service, associated with its Kubernetes service account
directly via the EKS Pod Identity API (`aws eks
create-pod-identity-association`) — no OIDC identity provider
involved at all.** One scoped policy per service,
replacing Phase 1's broad self-trust pattern (fulfilling Demo 10's own
deferral promise). **Teardown bucket, resolved by ADR-021:** because
there's no cluster-anchored OIDC provider for the association to
depend on, these Pod Identity associations are **created once, left
standing** — the same bucket as Phase 1's IAM roles and Demo 19's ECR
permissions (ADR-017/018), not the every-session cadence an IRSA
design would have required. **Objective:** each service's pod can
assume only its own scoped role. **Verify:** `aws sts
get-caller-identity` from inside each service's pod matches that
service's own role ARN, and cross-check that a different service's
pod cannot assume it.

**Scoped incrementally, not pre-scoped ahead of its targets
(ADR-015).** Demo 24 covers only what exists at this point: ECR pull,
CloudWatch, SNS/SQS. RDS and DynamoDB don't exist yet (they land at
Demo 26/27) — so their permissions are explicitly **not** granted
here. Pre-scoping access to resources that don't exist yet would teach
a worse practice than incremental scoping.

### Demo 25 — VPC Extension: Isolated Subnets + Endpoints

Extends the persistent VPC with a third, isolated subnet tier and an
S3 gateway endpoint, ahead of RDS's arrival. No RDS yet — purely the
networking extension.

### Demo 26 — RDS

Catalog + Orders backing store, PostgreSQL, deployed into Demo 25's
isolated subnets. IAM database authentication, tied to Demo 24's
least-privilege work.

**Swap-in step includes both halves (ADR-012, ADR-015):** the
connection-string swap (Catalog: sidecar → RDS; Orders: H2 → RDS) *and*
the IAM policy grant giving Catalog/Orders' task roles RDS access —
since Demo 24 couldn't scope that permission before this demo existed.

**Torn down and re-applied every session (ADR-017).** Consequence,
stated explicitly: RDS itself being destroyed each session means
Catalog/Orders' actual *data* does not persist across sessions — only
the schema/infrastructure does, via the same Terraform config
re-applying it. Whoever writes this demo's Pass Criteria should not
assume data persistence is available to test against.

### Demo 27 — DynamoDB

Cart backing store. Swap-in step includes both the connection swap and
the IAM policy grant for Cart's task role, same reasoning as RDS
above.

**Left standing once created, not torn down every session
(ADR-018)** — on-demand pricing means near-$0 idle cost. Consequence:
**Cart's data DOES persist across sessions**, unlike Catalog/Orders'
RDS data. This asymmetry is deliberate and cost-driven, not an
inconsistency — state it explicitly wherever this demo's content
discusses data persistence.

### Demo 28 — Lambda + API Gateway

Must follow Demo 27 — the SNS→Lambda→DynamoDB flow requires DynamoDB
to exist first (a real dependency-ordering bug in an earlier plan,
fixed by resequencing). Reuses Phase 1's SNS topic (Demo 03/06
scaffolding) — its first real producer/consumer pair. Checkout service
publishes an order-placed event; Lambda processes it into Demo 27's
DynamoDB analytics table.

**API Gateway's role — confirmed, not provisional:** a read-only
analytics query endpoint (`GET /analytics/orders`), same Lambda,
reading the DynamoDB analytics table — distinct from the SNS-triggered
ingestion path, which alone wouldn't need API Gateway at all.

Left standing once created, not torn down every session (ADR-018) —
pay-per-request pricing, near-$0 idle cost.

### Demo 29 — ECS Fargate *(swapped from EKS — ADR-019, same role reversed)*

Explicitly time-boxed, non-persistent — same app redeployed via ECS
Fargate, built/verified/torn down within one session, never revisited.
This is a third category distinct from both ADR-017 buckets (ADR-018).
**This is the same time-boxed slot EKS occupied under the original
design** — the swap changed which compute layer is primary vs.
comparison, not the shape of the comparison itself.

**Reuses Demo 26/27's existing RDS and DynamoDB instances, not
separate ones (ADR-014, direction reversed by ADR-019)** — avoids a
second RDS instance's real, avoidable cost for a one-session exercise.
ECS tasks need security-group access into the isolated data tier — an
implementation detail for this demo's actual design, not an open
architectural question. **Uses ECS task roles for IAM** —
worth calling out explicitly as the one demo in the series still using
the older per-task-role model, since it's demonstrating an older
compute pattern on purpose (and, incidentally, the one demo that still
structurally resembles what the IRSA design would have looked like,
before ADR-021 replaced it with Pod Identity).

### Demo 30 — CloudWatch Observability

Real telemetry from the running EKS deployment (and momentarily ECS
Fargate during Demo 29's own session). Extends Phase 1 Demo 09's
pattern with genuine data for the first time.

Left standing once created, not torn down every session (ADR-018) —
near-$0 at lab scale.

---

## Phase 4 (Demos 31–34) — Renumbered, content unchanged

### Demo 31 — HCP Terraform

Migrates state management for the persistent VPC/three-tier/app
modules from the S3 backend (`use_lockfile`, ADR-009) to HCP Terraform,
remote runs — a real, valuable teaching moment ("migrating existing
state to HCP Terraform"), not a gap the architecture left unaddressed.

### Demo 32 — CI/CD, GitLab CI

Project-layer override of the series' GitHub Actions default.
Pipeline: build → push to ECR (Demo 19) → `plan`/`apply` → deploy to
EKS (Demo 22/23). Targets `dev` only for real applies, per Demo 18's
pattern and the Phase 3-onward policy.

**Authentication — OIDC federation, assigned here specifically.**
GitLab's ID token → an AWS IAM role, no long-lived access keys in
GitLab CI variables. **This is the only OIDC trust relationship this
project builds, as of ADR-021** — worth stating explicitly, since an
earlier round of this document described two. Demo 24's per-service
IAM identity now goes through EKS Pod Identity (ADR-021), which
involves no OIDC provider at all; this GitLab-CI-to-AWS trust is the
only OIDC federation left in the curriculum. Don't assume the
"two distinct OIDC relationships" framing from an earlier draft still
applies. Also where Demo 22b's interim
`tflint`/`checkov`
checks get formalized into an actual pipeline stage.

### Demo 33 — Policy as Code

Enforces "only `dev` gets real applies" programmatically (Sentinel/OPA).

### Demo 34 — DevSecOps Scanning

Container image scanning + IaC scanning added to Demo 32's pipeline —
extends, doesn't duplicate, Demo 22's interim static analysis
(ADR-011).

---

## Phase 5 (Demos 35–38) — Renumbered, two demos now integration-scale

### Demo 35 — Cross-stack state

Since Demo 07 already teaches `terraform_remote_state` basics in full,
this demo doesn't need to introduce the syntax — it applies
cross-stack organization at real scale, against the full persistent
system (VPC stack, app stack, data stack) built through Phase 3–4.

### Demo 36 — Drift and Import

Unchanged in substance — already correctly scoped as the Phase 1
Demo 04 techniques applied to the real, running system.

### Demo 37 — Terraform Testing

Basics taught in Demo 21 (Phase 2) — this demo focuses on
integration-level tests against the real VPC/app/data stacks, not
re-teaching framework syntax.

### Demo 38 — Capstone

Full rebuild/validation of the persistent `dev` environment,
end-to-end — the portfolio deliverable.

---

## Cross-cutting notes for whoever builds Phase 3+

- **Teardown categorization (ADR-017/018) applies to every demo, not
  just the one that introduced it.** Three buckets: torn down every
  session (NAT, ALB, EKS cluster/nodes, RDS); created once, left
  standing (state backend, ECR, ACM, EventBridge, Budgets alarm,
  DynamoDB, Lambda+API Gateway, CloudWatch, **Demo 24's EKS Pod
  Identity associations, per ADR-021** — an IRSA design would have put
  these in the every-session bucket instead, since IRSA's OIDC-anchored
  trust policies can't outlive the cluster, but ADR-021 replaced IRSA
  with Pod Identity before that design was built, so they sit here
  cleanly instead); time-boxed exception (**ECS Fargate,
  as of ADR-019 — this is the same slot EKS occupied before the
  compute swap**). Check this table before assuming a new Phase 3+
  resource's teardown status — don't leave it implicit, that exact gap
  has already been found and fixed several separate times in this
  project.
- **Mid-course compute swap (ADR-019):** EKS (Auto Mode) is now the
  primary compute target for Demo 22/23 and everything built on top of
  it through Phase 4/5; ECS Fargate moved to Demo 29 as the time-boxed
  comparison. Demo numbering is unaffected. `Solution-Architecture.md`
  is the source of truth for the full reasoning and every downstream
  ripple (ADR-005, ADR-014, ADR-016, ADR-017, ADR-018 all updated
  alongside the new ADR-019).
- **§15 of `Solution-Architecture.md`** is a per-demo reverse index of
  every applicable ADR for Demos 22–30 — read it before starting any
  of those demos, since it's specifically designed to catch a decision
  that was made correctly somewhere else but never propagated to the
  demo that needed it. **Since ADR-020, what used to be one "Demo 22"
  entry is now four (22a/22b/22c/22d)** — if you're looking for the
  single entry you remember from before the split, it's been divided
  by sub-concern, not removed; check all four rather than assuming
  the content moved elsewhere.
- ~~Naming convention~~ (`cloudnova-*` prefix, used throughout Phase 1)
  — **resolved:** continues throughout, including EKS/RDS/DynamoDB
  resources — not forked to app-derived names. Consistency with 19
  already-built demos' naming, no functional reason to fork the
  convention partway through.
- ~~EKS Pod Identity vs. IRSA for Demo 22d/24~~ — **resolved: Pod
  Identity, via ADR-021.** No OIDC identity provider is created at
  Demo 22d. Confirmed against real 2026 evidence: AWS's current
  recommended default for new clusters; Auto Mode ships the EKS Pod
  Identity Agent as a pre-installed managed add-on; the one real
  limitation — no Fargate support — doesn't apply, since this
  project's EKS build runs on Auto Mode's EC2-backed nodes, not
  EKS-on-Fargate (Demo 29's ECS Fargate exercise is a separate, unrelated
  compute layer). Written up as its own ADR, not a silent swap.
- **Implementation convention, forward-only:** any new demo (Demo 22b
  onward) needing a provisioner-hosting resource with no real
  infrastructure behind it — the `null_resource` pattern Demo 13
  taught — should use `terraform_data` instead, the current
  built-in-provider successor. **Not retroactive** — Demo 13 and the
  Phase 1 milestone's own `null_resource.verify_queue_exists` are
  already built and audited and are unaffected.
- **`Phase-1-Implementation.md` and `Phase-2-Implementation.md` are
  unaffected by the ADR-009 state-backend revision, ADR-020's split,
  ADR-021's Pod Identity adoption, or the naming/ALB resolutions above**
  — both milestones are closed,
  audited, and predate Demo 22 entirely. No need to re-check either
  against this round's changes.
- **VERIFY 1 (Demo 22d) — `compute_config` may be missing required
  arguments, open, needs a live check.** Every independently-checked
  real-world Auto Mode example sets `node_pools` inside
  `compute_config` (and usually a distinct `node_role_arn`) — 22d's
  Lab now includes a best-effort corrected version with both added,
  but it's unverified against a real `terraform apply`.
- **VERIFY 2 (Demo 22d vs. Demo 17) — security-group module
  version/shape conflict, open, needs a live check.** 22d pins
  `terraform-aws-modules/security-group/aws` at `~> 5.0` with the
  older list-based shape; Demo 17 pins the same module at `~> 6.0`
  with a keyed-map shape — these can't both be correct as written.
  External evidence favors 22d's shape; neither pin should be treated
  as confirmed until checked against the module's real documentation.
  Demo 17's own Verification Note now states this directly rather
  than being silently rewritten.

## Verification note

Every claim above about already-built content (Demos 00–21) traces to
real file text, confirmed in full this project — **Demos 19–21 moved
from planned to built and cross-checked against `Solution-Architecture.md`
this round** (region `us-east-2` and domain `rselvantech.com` both
confirmed by their real content, propagated back into the architecture
doc). Every claim about Phase 3's app behavior (Demo 22/23's per-service
backend picture) is empirically tested against real container images,
not inferred — see `Solution-Architecture.md` Appendix B.12 for the full
test transcripts. Everything else about not-yet-built content (Demos
24–38) is a clearly-marked, reasoned plan, not a verified fact.