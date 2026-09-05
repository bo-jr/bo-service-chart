# bo-service-chart

One Helm chart for all three services.

Part of a three-cluster GitOps lab demonstrating progressive delivery gated on
**error-budget burn rate**. Spec: [`bo-platform/docs/BUILD-PLAN.md`](https://github.com/bo-jr/bo-platform/blob/main/docs/BUILD-PLAN.md) ·
Working rules: [`CLAUDE.md`](./CLAUDE.md)

Published as an OCI artifact and pinned by exact version in each service repo. Generates the Istio `AuthorizationPolicy` from each service's declared `dependencies`.
