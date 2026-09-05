# bo-service-chart

**One** Helm chart for all three services. Published as an OCI artifact, consumed by
version.

Canonical spec: [`bo-platform/docs/BUILD-PLAN.md`](https://github.com/bo-jr/bo-platform/blob/main/docs/BUILD-PLAN.md)
§4 (layout and the Helm-not-Kustomize rationale), Phase 2 (the shared chart).

## Why one chart

The three services are the same shape — Go HTTP, `/healthz`, `/readyz`, `/metrics`, OTel,
chaos knobs. That is the internal "golden path" chart pattern. Kustomize composes one app
across environments well and many apps sharing a shape badly, so it is not used anywhere
in this lab: **one templating tool, not two.**

Published to `oci://k3d-registry:5000/charts/service` and **pinned by exact version in
each service repo**. An unpinned chart edit silently changes all three services'
manifests at once.

> Helm here is **4.x**. Argo CD ≥3.5 renders with Helm 4 only. Watch
> `helm registry login` path components — that changed in Helm 4 and it is the one
> breaking change that touches the OCI publish flow. See `bo-platform/docs/DECISIONS.md`.

## Templates

`Rollout|Deployment` · `Service` · `HTTPRoute` · `AuthorizationPolicy` · `ServiceMonitor`

## Each service supplies

```yaml
name: storefront                   # WITHOUT the bo- prefix
image:
  repository: ghcr.io/bo-jr/bo-storefront   # WITH the prefix
  digest: "sha256:..."             # manifest-list index digest, never per-arch
workload: Rollout                  # the only conditional that earns its place
dependencies: [catalog, pricing]
canary: { analysisTemplate: storefront-burn-rate }
env: { FAILURE_RATE: "0", EXTRA_LATENCY_MS: "0" }
```

**The `bo-` prefix stops at the repo boundary.** `name` is `storefront`;
`image.repository` carries `bo-` only because `ghcr.io/${{ github.repository }}` resolves
that way and fighting the default is not worth it.

## Generate the AuthorizationPolicy from `dependencies`

The service declares what it calls; the chart emits the allow rules, the `readyz`
dependency checks, and the ServiceMonitor from that one list.

Under Istio default-deny, forgetting a policy is an outage. A chart that makes that
mistake **structurally impossible** is worth more than one that saves typing. Allow rules
key on **ServiceAccount identity (SPIFFE)**, never IP or label.

## Discipline — this is how charts like this die

When a service wants something the chart lacks, there are exactly two acceptable answers:

1. **Add it for everyone.**
2. **This service is off the golden path.**

Never "add another conditional." Charts like this die by accumulated `if`s, and the third
conditional is the one you will regret.

`workload: Rollout|Deployment` is the single conditional that earns its place.

## Never install at default resources

Every service gets explicit requests and limits. This is a standing rule across the lab,
and the chart is where it is enforced for services.

## What must never live here

- Rendered output — CI renders, `bo-deploy` stores
- Per-service special cases behind conditionals
- Kustomize anything
## Non-negotiable (inherited from `bo-platform/CLAUDE.md`)

- **No floating tags. Ever.** Not `latest`, `lts`, `stable`, or partial semver (`:1`,
  `:1.2`). Images pinned by **manifest-list digest**, charts by exact semver.
- **Pin the index digest, never a per-arch digest.** A platform-specific digest pulls
  fine on one machine and fails `no match for platform` on the other. This is the most
  likely portability bug in the lab.
- **Cross-platform, always.** Everything must work on `darwin/arm64` (MacBook, the
  runtime target) and `linux/amd64` (Windows/WSL2, build and test only).
- **LF line endings**, enforced by `.gitattributes`. A CRLF `.sh` inside a Linux image
  fails as `bad interpreter: /bin/bash^M`.
- **When something fails, check architecture first** — the usual cause of
  `ImagePullBackOff` and `exec format error` here.
- If reality contradicts the plan, **stop and say so.** Do not improvise around it;
  record the outcome in `bo-platform/docs/DECISIONS.md`.
