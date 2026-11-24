#!/usr/bin/env bash
# Deploy ACEest Fitness to Kubernetes using a chosen strategy.
#
#   DOCKERHUB_USER=me scripts/deploy.sh <rolling|blue-green|canary|shadow|ab> [version-tag]
#
# Manifests are applied only on first deployment (so a re-run never resets a
# running image); the new release is then rolled out with strategy-specific
# logic. A failed rollout is reverted automatically.
set -euo pipefail

STRATEGY="${1:?usage: deploy.sh <rolling|blue-green|canary|shadow|ab> [version-tag]}"
VERSION="${2:-}"
: "${DOCKERHUB_USER:?set DOCKERHUB_USER (use 'local' for locally loaded images)}"
NS="${NAMESPACE:-aceest}"
TIMEOUT="${ROLLOUT_TIMEOUT:-300s}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${DOCKERHUB_USER}/aceest-fitness"

k() { kubectl -n "$NS" "$@"; }

bootstrap() { # <manifest> <deployment-to-probe>
  kubectl apply -f "$ROOT/k8s/00-namespace.yaml"
  if ! k get deployment "$2" >/dev/null 2>&1; then
    sed "s#DOCKERHUB_USER#${DOCKERHUB_USER}#g" "$1" | kubectl apply -f -
  fi
}

wait_ready() { # <deployment>
  k rollout status "deployment/$1" --timeout="$TIMEOUT"
}

case "$STRATEGY" in
  rolling)
    bootstrap "$ROOT/k8s/rolling-update/rolling-update.yaml" aceest-rolling
    if [[ -n "$VERSION" ]]; then
      k set image deployment/aceest-rolling aceest="${IMAGE}:${VERSION}"
    fi
    if ! wait_ready aceest-rolling; then
      echo "Rollout failed - rolling back to previous revision" >&2
      k rollout undo deployment/aceest-rolling
      wait_ready aceest-rolling
      exit 1
    fi
    ;;

  blue-green)
    bootstrap "$ROOT/k8s/blue-green/blue-green.yaml" aceest-blue
    LIVE="$(k get svc aceest-bluegreen -o jsonpath='{.spec.selector.slot}')"
    IDLE=$([[ "$LIVE" == "blue" ]] && echo green || echo blue)
    if [[ -n "$VERSION" ]]; then
      k set image "deployment/aceest-${IDLE}" aceest="${IMAGE}:${VERSION}"
    fi
    if ! wait_ready "aceest-${IDLE}"; then
      echo "Idle slot ${IDLE} failed to become ready - live slot ${LIVE} untouched" >&2
      exit 1
    fi
    echo "Slot '${IDLE}' is ready and idle. Live slot is '${LIVE}'."
    echo "Verify via the preview service, then run: scripts/promote.sh blue-green"
    ;;

  canary)
    bootstrap "$ROOT/k8s/canary/canary.yaml" aceest-canary
    if [[ -n "$VERSION" ]]; then
      k set image deployment/aceest-canary aceest="${IMAGE}:${VERSION}"
    fi
    k scale deployment/aceest-canary --replicas="${CANARY_REPLICAS:-1}"
    if ! wait_ready aceest-canary; then
      echo "Canary unhealthy - scaling it to 0 (stable keeps serving)" >&2
      k scale deployment/aceest-canary --replicas=0
      exit 1
    fi
    echo "Canary live with ${CANARY_REPLICAS:-1} replica(s). Promote with: scripts/promote.sh canary"
    ;;

  shadow)
    bootstrap "$ROOT/k8s/shadow/shadow.yaml" aceest-shadow
    if [[ -n "$VERSION" ]]; then
      k set image deployment/aceest-shadow aceest="${IMAGE}:${VERSION}"
    fi
    wait_ready aceest-shadow || { echo "Shadow release failed; users unaffected" >&2; exit 1; }
    wait_ready aceest-primary
    wait_ready aceest-shadow-proxy
    ;;

  ab)
    bootstrap "$ROOT/k8s/ab-testing/ab-testing.yaml" aceest-variant-a
    if [[ -n "$VERSION" ]]; then
      k set image deployment/aceest-variant-b aceest="${IMAGE}:${VERSION}"
    fi
    wait_ready aceest-variant-b
    wait_ready aceest-variant-a
    wait_ready aceest-ab-proxy
    ;;

  *)
    echo "Unknown strategy: $STRATEGY" >&2
    exit 2
    ;;
esac

k get deploy,svc
