#!/usr/bin/env bash
# Promote a verified release to 100% of traffic.
#
#   scripts/promote.sh <blue-green|canary|shadow|ab>
set -euo pipefail

STRATEGY="${1:?usage: promote.sh <blue-green|canary|shadow|ab>}"
NS="${NAMESPACE:-aceest}"
TIMEOUT="${ROLLOUT_TIMEOUT:-300s}"
k() { kubectl -n "$NS" "$@"; }

case "$STRATEGY" in
  blue-green)
    LIVE="$(k get svc aceest-bluegreen -o jsonpath='{.spec.selector.slot}')"
    IDLE=$([[ "$LIVE" == "blue" ]] && echo green || echo blue)
    k patch svc aceest-bluegreen -p "{\"spec\":{\"selector\":{\"app\":\"aceest-bluegreen\",\"slot\":\"${IDLE}\"}}}"
    echo "Traffic switched ${LIVE} -> ${IDLE}. Previous slot '${LIVE}' kept for instant rollback."
    ;;

  canary)
    IMG="$(k get deployment aceest-canary -o jsonpath='{.spec.template.spec.containers[0].image}')"
    STABLE_REPLICAS="$(k get deployment aceest-stable -o jsonpath='{.spec.replicas}')"
    k set image deployment/aceest-stable aceest="$IMG"
    k rollout status deployment/aceest-stable --timeout="$TIMEOUT"
    k scale deployment/aceest-canary --replicas=0
    echo "Canary image ${IMG} promoted to stable (${STABLE_REPLICAS} replicas); canary scaled to 0."
    ;;

  shadow|ab)
    TARGET=$([[ "$STRATEGY" == "shadow" ]] && echo aceest-shadow || echo aceest-variant-b)
    BASE=$([[ "$STRATEGY" == "shadow" ]] && echo aceest-primary || echo aceest-variant-a)
    IMG="$(k get deployment "$TARGET" -o jsonpath='{.spec.template.spec.containers[0].image}')"
    k set image "deployment/${BASE}" aceest="$IMG"
    k rollout status "deployment/${BASE}" --timeout="$TIMEOUT"
    echo "Promoted ${IMG} to ${BASE}."
    ;;

  *)
    echo "Unknown strategy: $STRATEGY" >&2
    exit 2
    ;;
esac
