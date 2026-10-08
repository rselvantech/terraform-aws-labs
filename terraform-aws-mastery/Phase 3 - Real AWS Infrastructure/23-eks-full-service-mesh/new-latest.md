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
- The real environment variables `retail-store-sample-app`'s Catalog
  service actually reads to find its database — not assumed, checked
  against the app's own official configuration

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
6. ✅ Configure Catalog's actual database connection using the app's
   real, documented environment variables, not a guessed or
   unrelated one

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
| `RETAIL_CATALOG_PERSISTENCE_*` environment variables | App-specific configuration, not a Kubernetes construct | The real, documented set of variables Catalog's own code reads to find its database — confirmed against AWS's own EKS Workshop documentation for this exact app |

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
not by the sidecar container's *name* (`catalog-db` is a label for
Kubernetes' own bookkeeping, not a resolvable hostname the way a
Service's name is). This is fundamentally different from a separate
Deployment: the sidecar starts, stops, and scales with Catalog's own
Pod — it has no independent lifecycle, no separate Service, and no
existence outside this one Pod.

> **Contrast with a separate Deployment, stated explicitly:** if
> MariaDB were its own Deployment with its own Service, it would
> persist independently of Catalog's own Pod restarts, and would need
> its own resource lifecycle to reason about. The sidecar pattern here
> is deliberately the opposite — tightly coupled, torn down and
> re-applied with Catalog specifically, matching this project's own
> teardown categorization (§9, ADR-012/017) for exactly this resource.

---

#### Confirming Catalog's Real Database Configuration — Not Assumed

**A previous draft of this demo's Catalog manifest set
`RETAIL_UI_CATALOG_ENDPOINT`, a variable that has nothing to do with
Catalog's own database connection at all** — it would, if it exists,
belong on the *UI* Deployment (to tell UI where to reach Catalog), not
on Catalog's own Pod. That earlier draft never actually configured
Catalog's database connection, only its own network endpoint address —
a real error, not caught until checked directly against the app's real
configuration.

**Confirmed against AWS's own EKS Workshop documentation for this
exact application**, Catalog's real environment variables are:

| Variable | Purpose |
|---|---|
| `RETAIL_CATALOG_PERSISTENCE_PROVIDER` | Which backend to use — `mysql` for a MariaDB/MySQL-compatible database |
| `RETAIL_CATALOG_PERSISTENCE_ENDPOINT` | `host:port` of the database — `localhost:3306` here, since the sidecar shares Catalog's own network namespace |
| `RETAIL_CATALOG_PERSISTENCE_DB_NAME` | The database name — `catalog` |
| `RETAIL_CATALOG_PERSISTENCE_USER` / `RETAIL_CATALOG_PERSISTENCE_PASSWORD` | Credentials matching the sidecar's own configured MySQL user |

The Lab below now sets these directly, replacing the earlier
draft's unrelated variable entirely.

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

Part A deploys Catalog alongside a MariaDB sidecar, configured with
the app's real, confirmed database environment variables.

### Step 1 — Add catalog-deployment.yaml

This step writes Catalog's Deployment, now correctly wired to its
sidecar database via the app's actual documented environment
variables rather than an unrelated one.

Create a file **k8s/catalog-deployment.yaml** and add the below content:

This file contains Catalog's own container and its MariaDB sidecar in
one Pod spec — the app container's environment variables now match
`retail-store-sample-app`'s real, confirmed configuration.

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
            - name: RETAIL_CATALOG_PERSISTENCE_PROVIDER
              value: "mysql"
            - name: RETAIL_CATALOG_PERSISTENCE_ENDPOINT
              value: "localhost:3306"
              # ↑ localhost, not "catalog-db" — the sidecar's container
              # NAME isn't a resolvable hostname; same-Pod containers
              # share a network namespace and reach each other via
              # localhost specifically.
            - name: RETAIL_CATALOG_PERSISTENCE_DB_NAME
              value: "catalog"
            - name: RETAIL_CATALOG_PERSISTENCE_USER
              value: "catalog"
            - name: RETAIL_CATALOG_PERSISTENCE_PASSWORD
              value: "catalog"
              # ⚠️ Lab-only plaintext credential, matching the sidecar's
              # own MYSQL_USER/MYSQL_PASSWORD below — fine for a
              # disposable lab database, not a real-world pattern.
        - name: catalog-db
          image: mariadb:10.11
          ports:
            - containerPort: 3306
          env:
            - name: MYSQL_ALLOW_EMPTY_PASSWORD
              value: "true"
            - name: MYSQL_DATABASE
              value: "catalog"
            - name: MYSQL_USER
              value: "catalog"
            - name: MYSQL_PASSWORD
              value: "catalog"
```

> ⚠️ [VERIFY — timing claim, docs only] These exact variable names and
> the `mysql` provider value are confirmed against AWS's own EKS
> Workshop documentation for this application — but the specific
> credential values above are this lab's own simple choice, not
> independently re-verified against a live `kubectl apply` in this
> session. Confirm the app actually connects successfully in your own
> cluster (Catalog's own container logs, not just `2/2 Running`) before
> treating this as final.

### Step 2 — Add catalog-service.yaml

This step exposes Catalog internally, giving it the DNS name UI will
use to reach it.

Create a file **k8s/catalog-service.yaml** and add the below content:

This file is Catalog's entire network footprint — a `ClusterIP`
Service with no Ingress, deliberately.

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

This step applies both Catalog files and confirms both containers in
its Pod come up healthy together.

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

Part B deploys the three remaining services, each with nothing beyond
a plain Deployment and Service — no sidecar, no special configuration.

### Step 4 — Add the three remaining Deployments and Services

This step writes Cart's Deployment and Service, then repeats the
identical shape for Orders and Checkout with no sidecar and no extra
environment configuration.

Create a file **k8s/cart-deployment.yaml** and add the below content:

This file is a plain, single-container Deployment — Cart needs nothing
beyond its own built-in defaults, per ADR-012's real testing.

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

This file exposes Cart internally at `cart.default.svc.cluster.local`,
the same pattern as Catalog's Service.

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

This step applies Cart, Orders, and Checkout together and confirms all
five services (these three plus Catalog and UI) are running.

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

Part C confirms the actual call path works end-to-end — not just that
each pod individually reports healthy.

### Step 6 — Confirm every Service resolves via internal DNS

This step confirms each Service's DNS name genuinely resolves from
inside the cluster, using a disposable test Pod.

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

This step confirms UI itself, not just a test Pod, can actually reach
all four backend services.

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

This step confirms the demo's own scope claim directly — that nothing
new was exposed outside the cluster.

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
6. ✅ A sidecar container's *name* is not a resolvable hostname — the
   real connection needed `localhost`, and the real environment
   variables Catalog's own code reads had to be confirmed against the
   app's actual documented configuration, not guessed.

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
| "Does a sidecar container need its own Kubernetes Service to be reachable by its own Pod's main container?" | No — containers in the same Pod share a network namespace and reach each other via `localhost` | Assuming every container needs its own Service regardless of context, or that its container *name* is itself a resolvable hostname |

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
| Catalog's app container logs show a database connection error | Wrong environment variable name, wrong endpoint, or a credential mismatch between the app container and the sidecar | Confirm `RETAIL_CATALOG_PERSISTENCE_*` variables match the sidecar's own `MYSQL_USER`/`MYSQL_PASSWORD`/`MYSQL_DATABASE` exactly, and that the endpoint is `localhost:3306`, not the sidecar's container name |
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

This file is a single Service with a `selector` that doesn't match any
real Deployment's Pod labels — diagnose the resulting empty endpoints
list before revealing the answer.

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

**Q4. A reviewer asks how you know Catalog's actual database configuration is correct, rather than just plausible-looking.**
Because it's checked against the app's own real, documented configuration rather than inferred from the manifest's own internal logic. An earlier draft of this manifest set a variable (`RETAIL_UI_CATALOG_ENDPOINT`) that sounded plausible but actually belongs to a completely different concern — UI's own routing, not Catalog's database connection — and never configured a database connection at all. Confirming the real `RETAIL_CATALOG_PERSISTENCE_*` variables against AWS's own EKS Workshop documentation for this exact app is what caught that, the same discipline this project has applied to every other unverified claim rather than trusting a manifest that merely looks reasonable.

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

6. **A plausible-looking configuration value is not the same as a
   confirmed one.** A variable name that sounds right for the job it's
   near isn't the same as being checked against the app's own real,
   documented behavior — this demo's own Catalog fix is a direct
   example of that gap.

> **Demo scope:** Primary concept: scaling the proven single-service
> pattern to all five `retail-store-sample-app` services, using
> internal-only Services and DNS for four of them. Supporting
> concepts: the sidecar pattern, why no new Ingress/ALB is needed,
> confirming an app's real configuration against its actual
> documentation rather than a plausible guess.
> Estimated completion time: 30–35 minutes.
> Checkpoints: 3 natural stopping points (end of Part A, end of
> Part B, end of Part C).

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
"What are the real, confirmed environment variables retail-store-sample-app's Catalog service reads to connect to its database?","RETAIL_CATALOG_PERSISTENCE_PROVIDER, RETAIL_CATALOG_PERSISTENCE_ENDPOINT, RETAIL_CATALOG_PERSISTENCE_DB_NAME, RETAIL_CATALOG_PERSISTENCE_USER, and RETAIL_CATALOG_PERSISTENCE_PASSWORD - confirmed against AWS's own EKS Workshop documentation for this exact app.","demo23,catalog,persistence,gotcha"
```

---

## Appendix — Quiz

> **Note on Quiz vs. Anki:** Anki drills the individual facts (why no
> new Ingress, sidecar-vs-Deployment, DNS format, which service needed
> help, verification method, the real Catalog env vars). This Quiz
> instead works through this demo's own Break-Fix scenario and
> realistic `kubectl` output-reading situations, so the two together
> cover recall and applied diagnosis without restating the same
> question twice.

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
<summary>Answer</summary>

**A.** `2/2 Running` confirms both containers are up, but doesn't
confirm the app inside them is actually serving correctly — checking
the specific container's logs (`kubectl logs catalog-<pod> -c
catalog-db`) is the next diagnostic step, not assuming the problem is
elsewhere. **D** is irrelevant here — Catalog has no Ingress at all.

</details>

---

**Q3. (Multiple Choice)** This demo's Catalog Deployment needs to tell
the app's own code where to find its database. Based on the real,
official `retail-store-sample-app` configuration, which environment
variable actually controls this?

- A) `RETAIL_UI_CATALOG_ENDPOINT`
- B) `RETAIL_CATALOG_PERSISTENCE_ENDPOINT`
- C) `CATALOG_DB_HOST`
- D) `MYSQL_HOST`

<details>
<summary>Answer</summary>

**B.** Confirmed against AWS's own EKS Workshop documentation for this
exact app. **A** is a variable an earlier draft of this demo
mistakenly set on Catalog's own Pod — it's unrelated to Catalog's
database connection entirely.

</details>

---

**Q4. (Multiple Choice)** Catalog's sidecar container is named
`catalog-db` in the Pod spec, but
`RETAIL_CATALOG_PERSISTENCE_ENDPOINT` should be set to
`localhost:3306`, not `catalog-db:3306`. Why?

- A) The sidecar's container name is irrelevant to networking — containers in the same Pod share a network namespace and reach each other via `localhost`, not by each other's container names
- B) `catalog-db` is a reserved name and cannot be used as a hostname
- C) MariaDB always listens only on `localhost` by default, regardless of Pod structure
- D) The container name and the DNS name are supposed to match, so this would actually be a bug in reverse

<details>
<summary>Answer</summary>

**A.** A container's `name:` field in a Pod spec is Kubernetes'
own bookkeeping label — it doesn't create a resolvable hostname the
way a Service's name does. Same-Pod containers reach each other via
`localhost`, regardless of what each container is named.

</details>

---

**Q5. (Multiple Answer — Pick the 2 correct responses)** Which TWO
statements about this demo's scope are correct?

- A) This demo creates a new Ingress for each of the four additional services
- B) This demo creates zero new externally-facing infrastructure
- C) The decision to skip new Ingresses corrects an earlier planning assumption, confirmed against the real app's architecture
- D) Skipping new Ingresses was a cost-driven shortcut, not an architectural finding

<details>
<summary>Answer</summary>

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