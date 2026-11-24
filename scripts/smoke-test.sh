#!/usr/bin/env bash
# Smoke-test a deployed endpoint: /health must return 200 and /version must
# report the expected release (optional).
#
#   scripts/smoke-test.sh http://<host>:<port> [expected-version]
set -euo pipefail

URL="${1:?usage: smoke-test.sh <base-url> [expected-version]}"
EXPECTED="${2:-}"

for attempt in $(seq 1 15); do
  if curl -fsS "${URL}/health" >/dev/null 2>&1; then break; fi
  [[ "$attempt" == 15 ]] && { echo "Health check failed for ${URL}" >&2; exit 1; }
  sleep 2
done

BODY="$(curl -fsS "${URL}/version")"
echo "version endpoint: ${BODY}"
if [[ -n "$EXPECTED" && "$BODY" != *"\"version\":\"${EXPECTED}\""* && "$BODY" != *"\"version\": \"${EXPECTED}\""* ]]; then
  echo "Expected version ${EXPECTED} not found" >&2
  exit 1
fi
echo "Smoke test passed for ${URL}"
