# bo-service-chart

**One** Helm chart for all three services. Published as an OCI artifact, consumed by
exact version.

Canonical spec: [`bo-platform/BUILD-PLAN.md`](https://github.com/bo-jr/bo-platform/blob/main/BUILD-PLAN.md)
§4 (layout and the Helm-not-Kustomize rationale), Phase 2 (the shared chart). Where it and
[`bo-platform/DECISIONS.md`](https://github.com/bo-jr/bo-platform/blob/main/DECISIONS.md)
disagree, `DECISIONS.md` wins.

## Why one chart

The three services are the same shape — Go HTTP, `/healthz`, `/readyz`, `/metrics`, OTel,
chaos knobs. That is the internal "golden path" chart pattern. Kustomize composes one app
across environments well and many apps sharing a shape badly, so it is not used anywhere
in this lab: **one templating tool, not two.**

## Where it is published

**`oci://ghcr.io/bo-jr/charts/service`**, not the local registry BUILD-PLAN names — GitHub
Actions renders manifests in Phase 3 and cannot reach a registry on the laptop
(DECISIONS 2026-09-29).

It is **pinned by exact version in each service repo**, in the top-level `chartVersion:`
field of `chart-values.yaml`. The chart refuses to render when that field disagrees with
its own `Chart.yaml` version. An unpinned chart edit would silently change all three
services' manifests at once.

> Helm here is **4.x**. Argo CD ≥3.5 renders with Helm 4 only. Log in host-only
> (`helm registry login ghcr.io`, token on stdin, never argv) — path components on
> `helm registry login` are the one Helm 4 change that touches the OCI publish flow.

## Templates — the chart grows with the platform

A template for a CRD-backed kind lands **in the phase that installs its CRD**, for every
service at once, as a chart minor version. Never behind a per-feature `if`, and never
behind `.Capabilities` — CI's `helm template` has no cluster to ask, so it would render
something different from what the cluster sees.

| Template | Phase |
|---|---|
| `Deployment`, `Service`, `ServiceAccount` | 2 |
| `ServiceMonitor` | 4 |
| `HTTPRoute`, `AuthorizationPolicy` | 5 |
| `Rollout` (`workload: Rollout`) | 6 |

## Each service supplies

```yaml
chartVersion: 0.1.0                # must equal the chart's own version
name: storefront                   # WITHOUT the bo- prefix
version: v1                        # APP_VERSION + the pod's `version` label; never a SHA
image:
  repository: ghcr.io/bo-jr/bo-storefront   # WITH the prefix
  digest: "sha256:..."             # manifest-list index digest, never per-arch
workload: Deployment               # Rollout arrives in Phase 6
dependencies: [catalog, pricing]
env: { FAILURE_RATE: "0", EXTRA_LATENCY_MS: "0" }
```

**The `bo-` prefix stops at the repo boundary.** `name` is `storefront`;
`image.repository` carries `bo-` only because `ghcr.io/${{ github.repository }}` resolves
that way and fighting the default is not worth it.

## Generate the AuthorizationPolicy from `dependencies`

The service declares what it calls. From that one list the chart feeds the kit's `readyz`
dependency checks now, and emits the allow rules in Phase 5.

Under Istio default-deny, forgetting a policy is an outage. A chart that makes that
mistake **structurally impossible** is worth more than one that saves typing. Allow rules
key on **ServiceAccount identity (SPIFFE)**, never IP or label.

## Discipline — this is how charts like this die

When a service wants something the chart lacks, there are exactly two acceptable answers:

1. **Add it for everyone.**
2. **This service is off the golden path.**

Never "add another conditional." Charts like this die by accumulated `if`s, and the third
conditional is the one you will regret. A `range` over a list that is empty for most
services (for example, Secret-backed env vars) is not a conditional.

`workload: Rollout|Deployment` is the single conditional that earns its place.

## Never install at default resources

Every service gets explicit requests and limits. This is a standing rule across the lab,
and the chart is where it is enforced for services — the schema has no defaults for them.

## What must never live here

- Rendered output — CI renders, `bo-deploy` stores
- Per-service special cases behind conditionals
- Stateful infrastructure — catalog's Postgres `Cluster` lives in `bo-platform`
- Kustomize anything

## Non-negotiable (inherited from `bo-platform/CLAUDE.md`)

- **No floating tags. Ever.** Not `latest`, `lts`, `stable`, or partial semver (`:1`,
  `:1.2`). Images pinned by **manifest-list digest**, charts by exact semver.
- **Pin the index digest, never a per-arch digest.** GitHub Actions runners are
  `linux/amd64`; every cluster in the lab is `arm64`. A platform-specific digest pulls
  fine where you tested it and fails `no match for platform` on the other side of that
  boundary — which anything CI renders crosses on every run. This is the most likely
  portability bug in the lab.
- **LF line endings**, enforced by `.gitattributes`. A CRLF `.sh` inside a Linux image
  fails as `bad interpreter: /bin/bash^M`.
- **When something fails, check architecture first** — the usual cause of
  `ImagePullBackOff` and `exec format error` here.
- If reality contradicts the plan, **stop and say so.** Do not improvise around it;
  record the outcome in `bo-platform/DECISIONS.md`.
