#!/usr/bin/env bash
# Build one Docker image per git release tag (v1.0.0, v1.1.0, ...) from a clean
# export of that tag, so the Docker Hub repo holds every application version.
#
#   DOCKERHUB_USER=me scripts/build-all-versions.sh          # build only
#   DOCKERHUB_USER=me scripts/build-all-versions.sh --push   # build + push (docker login first)
set -euo pipefail

: "${DOCKERHUB_USER:?set DOCKERHUB_USER}"
PUSH="${1:-}"
REPO="${DOCKERHUB_USER}/aceest-fitness"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$(git rev-parse --show-toplevel)"
for tag in $(git tag --list 'v*' --sort=version:refname); do
  echo "=== ${REPO}:${tag}"
  rm -rf "${WORK:?}/src" && mkdir "$WORK/src"
  git archive "$tag" | tar -x -C "$WORK/src"
  docker build --load --build-arg APP_VERSION="${tag#v}" -t "${REPO}:${tag}" "$WORK/src"
  if [[ "$PUSH" == "--push" ]]; then
    docker push "${REPO}:${tag}"
  fi
  LATEST_TAG="$tag"
done

if [[ "$PUSH" == "--push" ]]; then
  docker tag "${REPO}:${LATEST_TAG}" "${REPO}:latest"
  docker push "${REPO}:latest"
fi
