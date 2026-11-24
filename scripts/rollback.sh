#!/usr/bin/env bash
# Revert to the last stable version for the given strategy.
#
#   scripts/rollback.sh <rolling|blue-green|canary|shadow|ab>
set -euo pipefail

STRATEGY="${1:?usage: rollback.sh <rolling|blue-green|canary|shadow|ab>}"
NS="${NAMESPACE:-aceest}"
TIMEOUT="${ROLLOUT_TIMEOUT:-300s}"
k() { kubectl -n "$NS" "$@"; }

case "$STRATEGY" in
  rolling)
    k rollout undo deployment/aceest-rolling
    k rollout status deployment/aceest-rolling --timeout="$TIMEOUT"
    ;;

  blue-green)
    LIVE="$(k get svc aceest-bluegreen -o jsonpath='{.spec.selector.slot}')"
    PREV=$([[ "$LIVE" == "blue" ]] && echo green || echo blue)
    k patch svc aceest-bluegreen -p "{\"spec\":{\"selector\":{\"app\":\"aceest-bluegreen\",\"slot\":\"${PREV}\"}}}"
    echo "Traffic switched back ${LIVE} -> ${PREV}."
    ;;

  canary)
    k scale deployment/aceest-canary --replicas=0
    echo "Canary removed; all traffic served by stable."
    ;;

  shadow)
    k scale deployment/aceest-shadow --replicas=0
    echo "Shadow release stopped; primary unaffected."
    ;;

  ab)
    k scale deployment/aceest-variant-b --replicas=0
    k patch configmap aceest-ab-proxy-conf --type merge \
      -p '{"data":{"default.conf":"upstream variant_a { server aceest-variant-a:80; }\nserver { listen 80; location / { proxy_pass http://variant_a; proxy_set_header Host $host; } }\n"}}'
    k rollout restart deployment/aceest-ab-proxy
    k rollout status deployment/aceest-ab-proxy --timeout="$TIMEOUT"
    echo "All users routed to variant A."
    ;;

  *)
    echo "Unknown strategy: $STRATEGY" >&2
    exit 2
    ;;
esac
