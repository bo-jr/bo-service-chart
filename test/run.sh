#!/usr/bin/env bash
# Chart tests: one valid render, then one render per rule that MUST fail.
# Run from the repo root: ./test/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."

pass=0 fail=0
ok()  { echo "  ok    $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $*"; fail=$((fail + 1)); }

echo "lint"
helm lint . -f test/valid.yaml >/dev/null && ok "helm lint" || bad "helm lint"

echo "valid render"
out=$(helm template t . -f test/valid.yaml)
kinds=$(echo "$out" | grep '^kind:' | sort | tr '\n' ' ')
[ "$kinds" = "kind: Deployment kind: Service kind: ServiceAccount " ] && ok "kinds: $kinds" || bad "kinds: $kinds"
echo "$out" | grep -q 'image: "ghcr.io/bo-jr/bo-storefront@sha256:0\{64\}"' && ok "image is repository@digest" || bad "image reference"
echo "$out" | grep -q 'name: DEPENDENCIES' && echo "$out" | grep -q 'value: "catalog,pricing"' && ok "DEPENDENCIES rendered" || bad "DEPENDENCIES"
echo "$out" | grep -q 'key: uri' && ok "secretEnv rendered" || bad "secretEnv"
[ "$(echo "$out" | grep -c '^    version: v1$')" -ge 1 ] && ok "version label" || bad "version label"
echo "$out" | grep -A2 'selector:' | grep -q 'app: storefront' && ok "selector is app" || bad "selector"
# The commit timestamp rides on the workload's own metadata and nowhere else:
# not the pod template (a timestamp alone must not restart pods), not the
# Service or ServiceAccount (they must not diff between builds).
dep=$(helm template t . -f test/valid.yaml --show-only templates/deployment.yaml)
[ "$(echo "$dep" | grep -c '^    gitops-lab/commit-timestamp: "2026-09-30T14:05:00Z"$')" -eq 1 ] \
  && ok "commit-timestamp on Deployment metadata" || bad "commit-timestamp on Deployment metadata"
[ "$(echo "$out" | grep -c 'gitops-lab/commit-timestamp')" -eq 1 ] \
  && ok "commit-timestamp nowhere else" || bad "commit-timestamp appears more than once"

# Each case: description, then helm args that break exactly one rule.
must_fail() {
  local desc=$1; shift
  if helm template t . -f test/valid.yaml "$@" >/dev/null 2>&1; then
    bad "accepted: $desc"
  else
    ok "rejected: $desc"
  fi
}

echo "must fail"
# No values file at all: the chart has no defaults for the fields that matter.
if helm template t . >/dev/null 2>&1; then bad "accepted: chart defaults alone"; else ok "rejected: chart defaults alone"; fi
must_fail "tag instead of digest"               --set image.digest=v1.2.3
must_fail "per-image tag on repository"         --set image.repository=ghcr.io/bo-jr/bo-storefront:latest
must_fail "digest AND tag on repository"        --set image.repository=ghcr.io/bo-jr/bo-storefront@sha256
must_fail "missing limits"                      --set resources.limits=null
must_fail "missing requests"                    --set resources.requests=null
must_fail "limits without memory"               --set resources.limits.memory=null
must_fail "SHA as version"                      --set version=3f2a9c1
must_fail "digest as version"                   --set version=sha256:abc
must_fail "bo- prefix in name"                  --set name=bo-storefront
must_fail "bo- prefix in a dependency"          --set 'dependencies={bo-catalog}'
must_fail "chartVersion pinned to another chart" --set chartVersion=0.0.9
must_fail "workload Rollout before Phase 6"     --set workload=Rollout
must_fail "reserved env name"                   --set env.APP_VERSION=v9
# --set coerces integers (not floats), so an int is what reaches the schema
# the way an unquoted YAML number would.
must_fail "unquoted (non-string) env value"     --set env.EXTRA_LATENCY_MS=300
must_fail "unknown top-level key"               --set tag=latest
must_fail "commit timestamp missing"            --set commitTimestamp=null
must_fail "commit timestamp empty"              --set-string commitTimestamp=
must_fail "commit timestamp not UTC"            --set-string commitTimestamp=2026-09-30T14:05:00+02:00
must_fail "commit timestamp date only"          --set-string commitTimestamp=2026-09-30
must_fail "commit timestamp fractional seconds" --set-string commitTimestamp=2026-09-30T14:05:00.123Z

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
