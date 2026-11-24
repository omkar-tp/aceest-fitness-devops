#!/usr/bin/env bash
# Bring up SonarQube + Jenkins with everything pre-wired:
#   1. start SonarQube, wait until UP
#   2. create an analysis token and a webhook to Jenkins (for waitForQualityGate)
#   3. write the token to .env and start Jenkins (credentials, Sonar server and the
#      pipeline job are created from jenkins/casc.yaml)
#   4. optionally trigger the first build
#
#   scripts/bootstrap-ci.sh [--build]
set -euo pipefail

cd "$(dirname "$0")/.."
[[ -f .env ]] || cp .env.example .env

get() { grep -E "^$1=" .env | head -1 | cut -d= -f2-; }
setenv() { # key value
  if grep -qE "^$1=" .env; then sed -i.bak "s#^$1=.*#$1=$2#" .env && rm -f .env.bak; else echo "$1=$2" >> .env; fi
}

SONAR_PORT="$(get SONAR_HOST_PORT)"; SONAR_PORT="${SONAR_PORT:-9000}"
SONAR_URL="http://localhost:${SONAR_PORT}"
JENKINS_PASS="$(get JENKINS_ADMIN_PASSWORD)"; JENKINS_PASS="${JENKINS_PASS:-admin123}"

echo ">> starting SonarQube on ${SONAR_URL}"
docker compose up -d sonarqube sonar-db
for _ in $(seq 1 60); do
  curl -fs "${SONAR_URL}/api/system/status" | grep -q '"UP"' && break
  sleep 5
done
curl -fs "${SONAR_URL}/api/system/status" | grep -q '"UP"' || { echo "SonarQube did not start" >&2; exit 1; }

SONAR_PASS="admin"
if ! curl -fs -u "admin:${SONAR_PASS}" "${SONAR_URL}/api/authentication/validate" | grep -q 'true'; then
  echo "SonarQube admin password is no longer 'admin'; set SONAR_TOKEN in .env manually." >&2
  exit 1
fi

TOKEN="$(get SONAR_TOKEN)"
if [[ -z "$TOKEN" || "$TOKEN" == "not-set" ]]; then
  curl -fs -u "admin:${SONAR_PASS}" -X POST "${SONAR_URL}/api/user_tokens/revoke" -d name=jenkins >/dev/null || true
  TOKEN="$(curl -fs -u "admin:${SONAR_PASS}" -X POST "${SONAR_URL}/api/user_tokens/generate" -d name=jenkins \
           | sed -E 's/.*"token":"([^"]+)".*/\1/')"
  setenv SONAR_TOKEN "$TOKEN"
fi

curl -fs -u "admin:${SONAR_PASS}" -X POST "${SONAR_URL}/api/webhooks/create" \
  -d name=jenkins -d url=http://jenkins:8080/sonarqube-webhook/ >/dev/null || true

echo ">> starting Jenkins on http://localhost:8080 (admin / ${JENKINS_PASS})"
docker compose up -d --build jenkins
for _ in $(seq 1 60); do
  code="$(curl -s -o /dev/null -w '%{http_code}' -u "admin:${JENKINS_PASS}" http://localhost:8080/api/json || true)"
  [[ "$code" == "200" ]] && break
  sleep 5
done
[[ "$code" == "200" ]] || { echo "Jenkins did not become ready" >&2; exit 1; }

if [[ "${1:-}" == "--build" ]]; then
  JAR="$(mktemp)"
  CRUMB="$(curl -s -c "$JAR" -u "admin:${JENKINS_PASS}" 'http://localhost:8080/crumbIssuer/api/json' \
           | sed -E 's/.*"crumb":"([^"]+)".*/\1/')"
  curl -s -b "$JAR" -u "admin:${JENKINS_PASS}" -H "Jenkins-Crumb: ${CRUMB}" \
       -X POST http://localhost:8080/job/aceest-fitness/build -o /dev/null -w "trigger HTTP %{http_code}\n"
  rm -f "$JAR"
fi

echo "Jenkins  : http://localhost:8080  (admin / ${JENKINS_PASS})"
echo "SonarQube: ${SONAR_URL}  (admin / admin)"
