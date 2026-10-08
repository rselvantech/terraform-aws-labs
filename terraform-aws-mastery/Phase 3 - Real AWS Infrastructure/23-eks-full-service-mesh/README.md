# Demo 23 — EKS: Full Service Mesh

---

## Overview

22d proved the whole chain works end-to-end for one service. This demo
scales that proven pattern to all five `retail-store-sample-app`
services — Catalog, Cart, Orders, and Checkout join UI on the same
cluster. Unlike 22d, this demo introduces no new externally-facing
infrastructure at all: UI keeps the Ingress/ALB it already has, and
the other four services are reached only from inside the cluster.

**Real-world scenario — CloudNova:**
With UI proven live, the natural next question is "what about the
rest of the app?" The answer, confirmed against the app's own real
architecture rather than assumed: Catalog, Cart, Orders, and Checkout
were never meant to be publicly reachable in the first place. UI is
the aggregating frontend — it calls the other four internally and
renders their combined results as the page you actually see in a
browser. This demo's job is making that internal call chain real.

**What this demo builds:**
```
┌─────────────────────────────────────────────────────────────────────────┐
│  PART A — Catalog: Deployment with a MariaDB sidecar + ClusterIP Service│
│  The one service that empirically needs help (ADR-012)                 │
├─────────────────────────────────────────────────────────────────────────┤
│  PART B — Cart, Orders, Checkout: Deployment + ClusterIP Service only  │
│  Zero additional infrastructure — built-in defaults, per ADR-012       │
├─────────────────────────────────────────────────────────────────────────┤
│  PART C — Verify: internal DNS-based service-to-service connectivity   │
│  From inside the cluster, not just individual pod health               │
└─────────────────────────────────────────────────────────────────────────┘
```

**What this demo covers:**
- Why this demo introduces **no new Ingress, no new ALB, and no
  routing decision at all** — a genuine scope correction from an
  earlier planning round, not a simplification you have to justify
- A sidecar container in a single Pod spec — Catalog's MariaDB
  container lives alongside Catalog's own container, not as a
  separate Deployment
- Kubernetes' internal, DNS-based service discovery
  (`<service>.<namespace>.svc.cluster.local`) — how UI actually reaches
  the other four services without any of them being externally routed
- Confirming connectivity from *inside* the cluster, since none of
  these four services are reachable from outside it at all

---

## How This Demo's Pieces Fit Together

**The AWS solution being built:** four more Kubernetes Deployments and
their `ClusterIP` Services, one of which (Catalog) carries a second,
sidecar container in the same Pod spec. Nothing here touches AWS load
balancing, Route53, or ACM — those are already fully built at 22d and
don't change.

**Why there's no Ingress/ALB decision in this demo, stated explicitly
rather than left to look like an oversight:** an earlier planning round
generalized a real Auto Mode limitation (no `IngressGroup` support —
you can't share one ALB across multiple `Ingress` resources) into an
assumption that all five services would need external routing, which
would have made that limitation a real problem here. It doesn't apply —
`retail-store-sample-app`'s own quickstart, and AWS's own EKS Auto Mode
deployment guide for this exact app, both confirm only UI is meant to be
externally reachable. This project only ever creates one `Ingress`
(UI's, from 22d), so the multi-Ingress-sharing-one-ALB scenario the
limitation describes never actually arises here. This is a genuine
correction to the plan, not a simplification chosen after the fact.

**Why Catalog alone gets a sidecar, not a separate resource:** ADR-012's
real `docker run` testing showed Catalog is the only one of the five
services that fails without a database — it looks for a `catalog-db`
hostname with no fallback. A sidecar container in Catalog's own Pod
spec satisfies that hostname locally, without standing up a separate
Deployment or introducing a new Service. Cart, Orders, and Checkout
tested clean against their own built-in defaults and need nothing
extra at all.

---

## Prerequisites

### Knowledge
- 22d completed — the EKS cluster, UI's Deployment/Service/Ingress,
  and 22c's ECR images this demo also pulls from
- Comfortable with Kubernetes Service basics (`ClusterIP` specifically)
  — this demo assumes you know what a Service does, even if 22d only
  used it alongside an Ingress

### Required Tools

| Tool | Minimum version | Verify |
|---|---|---|
| `kubectl` | Same as 22d | `kubectl version --client` |

No new Terraform or AWS CLI requirements — this demo's entire new
content is Kubernetes manifests applied via `kubectl` against 22d's
already-running cluster.

### Verify the Cluster Is Running

```bash
kubectl get nodes
kubectl get ingress ui
# Confirm 22d's UI Ingress still shows a real ADDRESS before adding
# anything new — this demo builds alongside it, not on top of it
```

---

## Demo Objectives

By the end of this demo you will be able to:

1. ✅ Explain why this demo introduces no new Ingress or ALB, and why
   that's a correction to an earlier plan, not a simplification
2. ✅ Write a Kubernetes Pod spec with two containers — an app
   container and a sidecar — sharing the same Pod
3. ✅ Explain Kubernetes' internal DNS-based service discovery and use
   it to reach a `ClusterIP` Service from another Pod
4. ✅ Deploy Cart, Orders, and Checkout with no additional
   infrastructure, matching their own empirically-confirmed built-in defaults
5. ✅ Verify service-to-service connectivity from inside the cluster,
   not just each pod's individual health

---

## Cost & Free Tier

| Resource | Free tier | Cost | Notes |
|---|---|---|---|
| 4 additional pods (Cart, Orders, Checkout, Catalog) | Standard EC2 free tier may apply briefly | ~$0.01/hr equivalent per pod | Auto Mode bin-packs onto existing/new nodes as needed |
| Catalog's MariaDB sidecar | None | ~$0.01/hr equivalent | Runs in Catalog's own Pod — a real, small addition, not exactly zero |
| **No new ALB, no new NAT usage change** | | **$0.00 additional** | The corrected scope means no new externally-facing infrastructure at all this demo |
| **Session total (in addition to 22d's)** | | **~$0.04–0.05/hr additional** | Tear down with the rest of the cluster at session end — see Cleanup |

---

## Directory Structure

```
23-eks-full-service-mesh/
├── README.md
├── 23-eks-full-service-mesh-anki.csv
├── 23-eks-full-service-mesh-quiz.md
└── k8s/
    ├── catalog-deployment.yaml    # includes the MariaDB sidecar container
    ├── catalog-service.yaml
    ├── cart-deployment.yaml
    ├── cart-service.yaml
    ├── orders-deployment.yaml
    ├── orders-service.yaml
    ├── checkout-deployment.yaml
    └── checkout-service.yaml
```

---

## Recall Check — 22d (EKS: Single Service)

Answer from memory before reading anything new:

1. Why does 22d's EKS cluster have no OIDC identity provider?
2. What Kubernetes API object did 22d use to bind an ACM certificate
   to Auto Mode's built-in ALB support?
3. Which tool applies the Kubernetes Deployment/Service/Ingress
   objects — Terraform, or something else?

<details>
<summary>Answers</summary>

1. This project uses EKS Pod Identity for per-service IAM identity
   (Demo 24), not IRSA — Pod Identity has no OIDC dependency at all,
   so no provider is needed.
2. `IngressClassParams`, referencing the certificate's ARN, bound via
   a matching `IngressClass`.
3. `kubectl`, applied directly against the cluster Terraform created —
   this series deliberately draws a scope line between infrastructure
   (Terraform) and workload deployment (`kubectl`).

</details>

---

## Concepts

### What's New in This Demo

| Construct | Type | Purpose in this demo |
|---|---|---|
| Multi-container Pod (sidecar pattern) | Kubernetes design pattern | Catalog's MariaDB container runs alongside Catalog's own container, in the same Pod spec |
| Internal DNS-based service discovery | Kubernetes networking concept | `<service>.<namespace>.svc.cluster.local` — how one Pod reaches another Service without any external routing |
| `ClusterIP` Service, used without an Ingress | Applied pattern, not new syntax | 22d already used `ClusterIP`; this demo is the first time a Service exists with *no* Ingress in front of it at all |

---

### Detailed Explanation of New Constructs

#### The Sidecar Pattern — One Pod, Two Containers

```yaml
spec:
  containers:
    - name: catalog          # the app itself
      image: <ECR>/cloudnova-retail-catalog:latest
    - name: catalog-db       # the sidecar — same Pod, different container
      image: mariadb:10.11
      env:
        - name: MYSQL_DATABASE
          value: "catalog"
```

Both containers share the same network namespace — from Catalog's own
container's point of view, the sidecar is reachable at `localhost`,
which is exactly why the app's own expectation of a `catalog-db`
hostname needs a small DNS adjustment (see the actual manifest in Part
A). This is fundamentally different from a separate Deployment: the
sidecar starts, stops, and scales with Catalog's own Pod — it has no
independent lifecycle, no separate Service, and no existence outside
this one Pod.

> **Contrast with a separate Deployment, stated explicitly:** if
> MariaDB were its own Deployment with its own Service, it would
> persist independently of Catalog's own Pod restarts, and would need
> its own resource lifecycle to reason about. The sidecar pattern here
> is deliberately the opposite — tightly coupled, torn down and
> re-applied with Catalog specifically, matching this project's own
> teardown categorization (§9, ADR-012/017) for exactly this resource.

---

#### Internal DNS-Based Service Discovery

Every Kubernetes Service gets a DNS name automatically, resolvable
from any Pod in the same cluster:

```
<service-name>.<namespace>.svc.cluster.local
```

For this demo's default namespace, that's simply
`catalog.default.svc.cluster.local` — or even just `catalog` from
another Pod in the same namespace, since Kubernetes' DNS search path
resolves the short form automatically. This is how UI reaches Catalog,
Cart, Orders, and Checkout — no Ingress, no ALB, no public DNS record
involved at any point in this chain.

```
┌────────────────────────────────────────────────────────────────────┐
│  EXTERNAL (built at 22d, unchanged here)                            │
│  Browser → Route53 → ALB → Ingress → UI's ClusterIP Service → UI Pod│
├────────────────────────────────────────────────────────────────────┤
│  INTERNAL (this demo's actual content)                              │
│  UI Pod → catalog.default.svc.cluster.local → Catalog's ClusterIP   │
│         → Catalog Pod (+ its sidecar)                                │
│  UI Pod → cart.default.svc.cluster.local → Cart's ClusterIP → Pod   │
│  UI Pod → orders... / checkout... — identical pattern                │
└────────────────────────────────────────────────────────────────────┘
```

---

## Lab Step-by-Step Guide

---

## Part A — Catalog: Deployment with a MariaDB Sidecar

### Step 1 — Add catalog-deployment.yaml

Create a file **k8s/catalog-deployment.yaml** and add the below content:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: catalog
  template:
    metadata:
      labels:
        app: catalog
    spec:
      containers:
        - name: catalog
          image: <ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-catalog:latest
          ports:
            - containerPort: 8081
          env:
            - name: RETAIL_UI_CATALOG_ENDPOINT
              value: "http://localhost:8081"
        - name: catalog-db
          image: mariadb:10.11
          ports:
            - containerPort: 3306
          env:
            - name: MYSQL_ALLOW_EMPTY_PASSWORD
              value: "true"
            - name: MYSQL_DATABASE
              value: "catalog"
```

> ⚠️ [VERIFY — timing claim, docs only] Catalog's real container may
> expect the database hostname literally as `catalog-db`, not
> `localhost` — since a sidecar's containers share a network
> namespace, `localhost` is technically correct for same-Pod
> communication, but confirm the app's actual expected hostname
> against its real startup behavior (the same `docker run` testing
> approach ADR-012 used) before treating this manifest as final. This
> demo's manifest is a reasonable starting point, not independently
> re-verified against a live cluster in this session.

### Step 2 — Add catalog-service.yaml

Create a file **k8s/catalog-service.yaml** and add the below content:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: catalog
spec:
  selector:
    app: catalog
  ports:
    - port: 80
      targetPort: 8081
  type: ClusterIP
```

> **No Ingress here, and none needed.** This `Service` is Catalog's
> entire network footprint — reachable inside the cluster at
> `catalog.default.svc.cluster.local`, unreachable from outside it at
> all.

### Step 3 — Apply

```bash
kubectl apply -f k8s/catalog-deployment.yaml
kubectl apply -f k8s/catalog-service.yaml
kubectl get pods -l app=catalog
```

```
⚠️ Simulated expected output

NAME                       READY   STATUS    RESTARTS   AGE
catalog-7d4f9c8b6d-x2kpz   2/2     Running   0          45s
```

> **Bolded takeaway:** `2/2` in the READY column — two containers in
> this one Pod, both running. This is the concrete, visible proof of
> the sidecar pattern: one Pod, two containers, one line in
> `kubectl get pods`.

---

## Part B — Cart, Orders, Checkout: No Additional Infrastructure

### Step 4 — Add the three remaining Deployments and Services

Create a file **k8s/cart-deployment.yaml** and add the below content:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cart
  template:
    metadata:
      labels:
        app: cart
    spec:
      containers:
        - name: cart
          image: <ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com/cloudnova-retail-cart:latest
          ports:
            - containerPort: 8082
```

Create a file **k8s/cart-service.yaml** and add the below content:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cart
spec:
  selector:
    app: cart
  ports:
    - port: 80
      targetPort: 8082
  type: ClusterIP
```

> Repeat the identical pattern for `orders` (port `8083`) and
> `checkout` (port `8084`) — same shape, no sidecar, no special
> handling. This is deliberate: ADR-012's real testing showed these
> three need nothing beyond their own built-in defaults.

### Step 5 — Apply all three

```bash
kubectl apply -f k8s/cart-deployment.yaml -f k8s/cart-service.yaml
kubectl apply -f k8s/orders-deployment.yaml -f k8s/orders-service.yaml
kubectl apply -f k8s/checkout-deployment.yaml -f k8s/checkout-service.yaml
kubectl get pods
```

```
⚠️ Simulated expected output

NAME                        READY   STATUS    RESTARTS   AGE
cart-...                    1/1     Running   0          30s
orders-...                  1/1     Running   0          30s
checkout-...                1/1     Running   0          30s
catalog-...                 2/2     Running   0          2m
ui-...                      1/1     Running   0          25m
```

> **Bolded takeaway:** Cart, Orders, and Checkout all show `1/1` — one
> container each, no sidecar — the visible confirmation that ADR-012's
> empirical finding (only Catalog needs help) holds up in this real
> cluster, not just in the standalone `docker run` tests that first
> established it.

---

## Part C — Verify Internal Connectivity

### Step 6 — Confirm every Service resolves via internal DNS

```bash
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- \
  sh -c "nslookup catalog.default.svc.cluster.local && \
         nslookup cart.default.svc.cluster.local && \
         nslookup orders.default.svc.cluster.local && \
         nslookup checkout.default.svc.cluster.local"
```

```
⚠️ Simulated expected output

Server:    10.100.0.10
Address:   10.100.0.10:53

Name:   catalog.default.svc.cluster.local
Address: 10.100.34.201
... (same pattern for cart, orders, checkout)
```

### Step 7 — Confirm UI's own logs show successful backend calls

```bash
kubectl logs deployment/ui --tail 50
```

```
⚠️ Simulated expected output

Successfully connected to catalog service
Successfully connected to cart service
Successfully connected to orders service
```

> **Bolded takeaway:** this is the real proof this demo exists to
> deliver — not that each pod is individually healthy (Part A/B's
> `kubectl get pods` already showed that), but that UI can genuinely
> reach all four backend services over the network, exactly the way
> the real app expects to.

### Step 8 — Confirm no new external surface exists

```bash
kubectl get ingress
# Expected: still exactly one Ingress — UI's, from 22d. No new one here.

kubectl get svc catalog cart orders checkout -o wide
# Expected: all four show TYPE ClusterIP, no EXTERNAL-IP
```

---

## Cleanup

This demo's resources are torn down alongside the rest of the EKS
cluster at the end of the session — same every-session discipline 22d
established, since these Pods run on the same cost-accruing compute.

```bash
kubectl delete -f k8s/
# Then, if ending the session entirely:
# follow 22d's own Cleanup — kubectl delete for UI's manifests,
# terraform destroy for the cluster itself
```

```
Console → EKS → confirm no unexpected pods remain if the cluster
  itself is staying up for a longer session ✅
```

---

## What You Learned

1. ✅ This demo introduces no new Ingress or ALB — a genuine
   correction to an earlier plan that assumed all 5 services needed
   external routing, confirmed wrong against the app's own real
   architecture.
2. ✅ A sidecar container shares a Pod with its main container —
   tightly coupled lifecycle, no separate Deployment or Service,
   visible directly in `kubectl get pods`' READY count.
3. ✅ Kubernetes Services get automatic internal DNS names
   (`<service>.<namespace>.svc.cluster.local`) — this is how UI reaches
   the other four services with zero external routing involved.
4. ✅ Only Catalog needed a sidecar — Cart, Orders, and Checkout run
   against their own built-in defaults, exactly as ADR-012's real
   `docker run` testing predicted.
5. ✅ Verifying "the app actually works" means checking
   service-to-service connectivity, not just that each pod
   individually reports healthy.

**Key Takeaway:** This demo is smaller and cleaner than an earlier
planning round implied — no Ingress-strategy decision, no `IngressGroup`
question, because the assumption behind that decision didn't match the
app's real design. Catching and correcting that before building around
it, rather than building 5 Ingresses' worth of content first, is the
same discipline this whole project has applied to itself repeatedly.

---

## Cert Tips

### Exam Objective Mapping

| Demo concept / command | Exam objective | Notes |
|---|---|---|
| Multi-container Pod (sidecar) | TA-004 Obj — general Kubernetes-adjacent AWS knowledge | Not a Terraform-specific object, but relevant context for any AWS exam touching EKS workload design |
| Internal `ClusterIP` DNS resolution | Same as above | Understand this as the default, not something you have to configure specially |

### Common Exam Traps

| Scenario | What the task actually requires | Common wrong approach |
|---|---|---|
| "Does every Service in a cluster need an Ingress to be reachable?" | No — only Services meant to be reached from outside the cluster need one. Internal-only Services (like this demo's four) are fully functional without any Ingress at all | Assuming a Service without an Ingress is somehow incomplete or broken |
| "Does a sidecar container need its own Kubernetes Service to be reachable by its own Pod's main container?" | No — containers in the same Pod share a network namespace and reach each other via `localhost` | Assuming every container needs its own Service regardless of context |

### Exam Task — Write a complete configuration

**Task:** Write a Kubernetes Deployment with two containers in one Pod
spec — an app container and a sidecar.

**What to practise:**
1. Write the manifest from scratch without looking at this demo's `k8s/` files
2. Confirm both containers appear under the same `spec.template.spec.containers` list

<details>
<summary>Reference solution (open only after attempting)</summary>

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: exam-task
spec:
  replicas: 1
  selector:
    matchLabels:
      app: exam-task
  template:
    metadata:
      labels:
        app: exam-task
    spec:
      containers:
        - name: main-app
          image: nginx:latest
        - name: sidecar
          image: busybox:1.36
          command: ["sleep", "3600"]
```

**Arguments you must know without looking up:**
- Both containers live under the same `containers:` list — a sidecar
  isn't a separate `spec` block or a different Kubernetes object type

</details>

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `2/2` never becomes ready on Catalog's pod | The sidecar container is crash-looping | `kubectl logs catalog-<pod> -c catalog-db` to check the sidecar's own logs specifically, not just the main container's |
| UI's logs show connection failures to a backend service | DNS name mismatch, or the target Service's `selector` doesn't match the target Deployment's labels | Confirm `kubectl get endpoints <service>` shows a real Pod IP — an empty endpoints list means the selector/label match is wrong |
| `nslookup` fails from the test Pod | DNS is generally reliable in EKS, but confirm CoreDNS itself is healthy | `kubectl get pods -n kube-system -l k8s-app=kube-dns` |

---

## Break-Fix Scenario

One deliberate error. Diagnose using `kubectl` output — do not look at
the answer first.

```bash
kubectl apply -f break-fix/broken-cart-service.yaml
kubectl get endpoints broken-cart
```

**break-fix/broken-cart-service.yaml:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: broken-cart
spec:
  selector:
    app: cart-app   # Error — doesn't match the real Deployment's label
  ports:
    - port: 80
      targetPort: 8082
  type: ClusterIP
```

<details>
<summary>Reveal answer — attempt diagnosis first</summary>

**Error — `selector: app: cart-app`**
The real Cart Deployment labels its Pods `app: cart`, not `app:
cart-app`. `kubectl get endpoints broken-cart` will show an empty
`ENDPOINTS` column — the Service exists, but has no Pods matching its
selector, so it silently routes to nothing. This is a distinctly
Kubernetes-flavored failure mode: no error at apply time, no crash —
just a Service that quietly serves nothing. Fix: correct the selector
to `app: cart`, matching the real Deployment's Pod labels.

</details>

**Cleanup:**

```bash
kubectl delete -f break-fix/broken-cart-service.yaml
```

---

## Interview Prep

**Q1. A teammate asks why this demo doesn't create any new Ingress or ALB, given that it deploys four more services.**
Because those four services were never meant to be reached from outside the cluster in the first place — this is a correction to an earlier planning assumption, confirmed against `retail-store-sample-app`'s own real architecture rather than just decided for convenience. UI is the aggregating frontend; it calls Catalog, Cart, Orders, and Checkout internally and renders the combined result. The app's own quickstart and AWS's own deployment guide for this exact app both only ever expose UI externally. Building four more Ingresses would have meant infrastructure the real app doesn't need and doesn't expect.

**Q2. Someone asks why Catalog gets a sidecar container instead of its own separate database Deployment.**
Because the coupling here is deliberately tight — this MariaDB instance exists only to satisfy Catalog's own hardcoded expectation of a database at startup, has no independent purpose, and shouldn't outlive Catalog's own Pod. A separate Deployment would imply an independent lifecycle and its own Service — more moving parts for a relationship that's actually one-to-one and tightly bound. The sidecar pattern makes that coupling explicit in the architecture itself: when Catalog's Pod is torn down and re-applied, its sidecar goes with it, which matches this project's own teardown categorization for exactly this kind of resource.

**Q3. A reviewer notices `kubectl get svc` shows Cart, Orders, and Checkout all as `ClusterIP` with no `EXTERNAL-IP`. Is that a misconfiguration?**
No — that's the correct, intended state. `ClusterIP` is the default Service type precisely for internal-only reachability; these three services having no external IP isn't a gap, it's the whole point. The way to verify they're working correctly isn't checking for an external address that was never supposed to exist — it's confirming UI can reach them internally, which is exactly what this demo's Part C verification does via DNS lookups and UI's own connection logs.

---

## Key Takeaways

1. **A planning assumption caught and corrected before building around
   it saves real, avoidable work.** This demo would have needed five
   Ingresses' worth of content if the original "all 5 services need
   routing" framing had gone unchecked — instead, it needs none.

2. **A sidecar container is defined by shared lifecycle, not shared
   Service.** Two containers, one Pod, one `kubectl get pods` line —
   that's the concrete signature to recognize, not an abstract concept.

3. **Kubernetes gives every Service a working internal DNS name for
   free.** `<service>.<namespace>.svc.cluster.local` requires no
   additional configuration — it's the default behavior, not an
   opt-in feature.

4. **A Service with no Ingress in front of it isn't incomplete.**
   Internal-only reachability is a valid, common, and often
   intentional end state — not every Service needs external exposure.

5. **Verifying "it works" means proving the actual call path, not just
   individual component health.** Four healthy pods don't prove UI can
   reach any of them — a real DNS lookup and a real log line from UI
   itself do.

---

## Quick Commands Reference

| Command | Description |
|---|---|
| `kubectl get pods -l app=<name>` | Filters pods by label — useful for checking one service's status specifically |
| `kubectl logs <pod> -c <container>` | Shows logs for one specific container in a multi-container Pod |
| `kubectl get endpoints <service>` | Shows which real Pod IPs a Service is actually routing to — an empty list means a broken selector |
| `kubectl run <name> --image=busybox --rm -it --restart=Never -- <cmd>` | Runs a throwaway Pod for network testing, cleaned up automatically |
| `nslookup <service>.<namespace>.svc.cluster.local` | Confirms a Service's internal DNS name resolves |

---

## Next Demo

**Demo 24 — IAM Least Privilege (via EKS Pod Identity):** now that all
five services have real per-service compute identity to scope
policies against, this demo replaces Phase 1's broad self-trust IAM
with one scoped Pod Identity association per service — ECR pull,
CloudWatch, and SNS/SQS only, with RDS/DynamoDB permissions
deliberately deferred until Demo 26/27.

---

## Appendix — Anki Cards

**23-eks-full-service-mesh-anki.csv:**

```
#deck:Terraform AWS Mastery::Phase 3 - Real AWS Infrastructure::23-eks-full-service-mesh
#separator:Comma
#columns:Front,Back,Tags
"Why doesn't this demo create any new Ingress or ALB, despite deploying 4 more services?","retail-store-sample-app's real architecture only exposes UI externally - it aggregates calls to Catalog/Cart/Orders/Checkout internally. Confirmed against the app's own quickstart and AWS's own EKS Auto Mode deployment guide. An earlier planning round wrongly assumed all 5 services needed external routing.","demo23,architecture,correction"
"What defines a sidecar container, as opposed to a separate Deployment?","Shared lifecycle - a sidecar lives in the SAME Pod spec as its main container, sharing a network namespace (reachable via localhost), starting/stopping/scaling together. A separate Deployment would have an independent lifecycle and its own Service.","demo23,sidecar,kubernetes"
"What DNS name does every Kubernetes Service get automatically?","<service-name>.<namespace>.svc.cluster.local - resolvable from any Pod in the cluster with no additional configuration required.","demo23,dns,kubernetes"
"Is a Kubernetes Service without an Ingress in front of it incomplete or misconfigured?","No - ClusterIP is the default Service type specifically for internal-only reachability. Many Services are correctly meant to never be externally exposed.","demo23,clusterip,kubernetes"
"Which of the 5 retail-store-sample-app services empirically needed a sidecar, and why only that one?","Only Catalog - real docker run testing (ADR-012) showed it's the only service that fails without a database, expecting a catalog-db hostname with no fallback. Cart, Orders, and Checkout all run cleanly against their own built-in defaults.","demo23,catalog,adr-012"
"What's the correct way to verify service-to-service connectivity in Kubernetes, beyond checking individual pod health?","Confirm the actual call path works - DNS resolution from one pod to another's Service name, and/or the calling service's own logs showing successful connections. Individually healthy pods don't prove they can reach each other.","demo23,verification,kubernetes"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the individual facts (why no
> new Ingress, sidecar-vs-Deployment, DNS format, which service needed
> help, verification method). This Quiz instead works through this
> demo's own Break-Fix scenario and realistic `kubectl` output-reading
> situations, so the two together cover recall and applied diagnosis
> without restating the same question twice.

**23-eks-full-service-mesh-quiz.md:**

````markdown
# Quiz — Demo 23: EKS: Full Service Mesh

> Question types: True/False, Multiple Choice, Multiple Answer —
> matching the real TA-004 exam format.
> Target: 80% or above before moving to Demo 24.

---

**Q1. (Multiple Choice)** `kubectl get endpoints broken-cart` returns
an empty `ENDPOINTS` column, but `kubectl apply` reported no error and
the real Cart pod is `Running`. What's the most likely cause?

- A) The Cart pod crashed after the Service was applied
- B) The Service's `selector` doesn't match the real Deployment's Pod labels
- C) `ClusterIP` Services require an Ingress to populate endpoints
- D) DNS hasn't propagated yet

<details>
<summary>Answer</summary>

**B.** A Service with no matching Pods produces exactly this
signature — no error, no crash, just an empty endpoints list, because
its `selector` doesn't match any real Pod's labels.

</details>

---

**Q2. (Multiple Choice)** `kubectl get pods` shows Catalog's pod as
`2/2 Running`, but UI's logs show `connection refused` when calling
Catalog. Where should you look first?

- A) The Catalog Deployment's own container logs, specifically the `catalog-db` sidecar's
- B) UI's own Deployment YAML for a typo
- C) The cluster's node count
- D) The Ingress configuration

<details>
<summary>Answer</summary()>

**A.** `2/2 Running` confirms both containers are up, but doesn't
confirm the app inside them is actually serving correctly — checking
the specific container's logs (`kubectl logs catalog-<pod> -c
catalog-db`) is the next diagnostic step, not assuming the problem is
elsewhere. **D** is irrelevant here — Catalog has no Ingress at all.

</details>

---

**Q3. (True/False)** Since Cart, Orders, and Checkout show `1/1
Running` with no `EXTERNAL-IP` on their Services, something is
missing from their configuration compared to Catalog and UI.

- A) True
- B) False

<details>
<summary>Answer</summary>

**B) False.** `1/1` (no sidecar) and no `EXTERNAL-IP` (no Ingress) are
both the correct, intended state for these three services — they
tested clean against their own built-in defaults and were never meant
to be externally reachable.

</details>

---

**Q4. (Multiple Choice)** A reviewer asks how to confirm UI can
actually reach Orders, beyond checking that both pods report
`Running`. What's the correct verification?

- A) Confirm both pods exist in `kubectl get pods` — that's sufficient
- B) Run a DNS lookup for `orders.default.svc.cluster.local` and/or check UI's own logs for a successful connection message
- C) Check the Ingress `ADDRESS` field
- D) Compare both pods' resource requests and limits

<details>
<summary>Answer</summary()>

**B.** Individual pod health doesn't prove connectivity between them —
a real DNS resolution and/or UI's own connection log entry is the
actual proof the call path works. **C** is irrelevant, since Orders
has no Ingress at all.

</details>

---

**Q5. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about this demo's scope are correct?

- A) This demo creates a new Ingress for each of the four additional services
- B) This demo creates zero new externally-facing infrastructure
- C) The decision to skip new Ingresses corrects an earlier planning assumption, confirmed against the real app's architecture
- D) Skipping new Ingresses was a cost-driven shortcut, not an architectural finding

<details>
<summary>Answer</summary()>

**B and C.** No new Ingress or ALB is created (ruling out **A**), and
the demo is explicit that this is a genuine architectural correction —
confirmed against the app's own real design — not a cost-motivated
simplification (ruling out **D**).

</details>

---

Score guide:

| Score | Action |
|---|---|
| 5/5 | Import Anki cards, move to Demo 24 |
| 4/5 | Review the wrong answer, then proceed |
| 3/5 | Re-read the relevant sections, retry those questions |
| Below 3/5 | Re-read the full demo before proceeding |
````