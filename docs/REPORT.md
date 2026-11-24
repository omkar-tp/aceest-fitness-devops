# ACEest Fitness & Gym - CI/CD Report (Assignment 2)

## 1. CI/CD architecture overview

```
 Developer -> Git (feature/* -> main, tags vX.Y.Z) -> GitHub
                                   |  pollSCM (2 min) / webhook
                                   v
   Jenkins pipeline:  Checkout -> Install -> flake8 -> Pytest (+JUnit, coverage)
        -> SonarQube analysis -> Quality Gate (abort on fail)
        -> docker build -> pytest INSIDE the image -> push to Docker Hub
        -> kubectl deploy (strategy parameter) -> smoke test -> archive artifacts
                                   |
                                   v
      Docker Hub: <user>/aceest-fitness:v1.0.0 | v1.1.0 | v2.0.0 | v2.0.1
                                   |
                                   v
      Kubernetes (Minikube / cloud): rolling | blue-green | canary | shadow | A/B
```

| Concern | Tool / file |
|---------|-------------|
| Application | Flask 3 + gunicorn, `app.py`, `templates/` |
| Version control | Git, feature branches merged `--no-ff`, annotated tags `v1.0.0`-`v2.0.1` |
| Tests | Pytest, 15 tests, 98.5 % coverage (`tests/test_app.py`) |
| Build server | Jenkins (`Jenkinsfile`, `jenkins/Dockerfile`, `docker-compose.yml`) |
| Code quality | SonarQube + quality gate (`sonar-project.properties`) |
| Container | Non-root `Dockerfile`, `HEALTHCHECK`, `APP_VERSION` build arg |
| Registry | Docker Hub, one tag per release (`scripts/build-all-versions.sh`) |
| Orchestration | Kubernetes manifests in `k8s/`, scripts in `scripts/` |

**Versioning.** Each release is a git tag and an image tag. The running version
is observable at runtime (`/version`, `X-App-Version` and `X-Deploy-Color`
headers), which is what makes every deployment strategy verifiable from outside.
The Assignment 1 Tkinter versions are preserved in `legacy_versions/`.

**Deployment strategies** (namespace `aceest`, all with readiness/liveness probes
on `/health` and resource limits):

* **Rolling update** - `maxSurge=1, maxUnavailable=0`: capacity never drops (zero
  downtime). Failed rollout -> `kubectl rollout undo` (automatic in `deploy.sh`).
* **Blue-green** - two full Deployments; the live Service selector flips
  blue<->green instantly. The idle slot is testable via a preview Service first.
  Rollback = flip the selector back.
* **Canary** - stable (9 replicas) and canary (1 replica) behind one Service, ~10 %
  of traffic to the new version; promote by updating stable, abort by scaling the
  canary to 0.
* **Shadow** - an nginx proxy answers from the primary and mirrors every request to
  the new version; mirrored responses are discarded.
* **A/B testing** - nginx proxy assigns users to variant A (v1.1.0) or B (v2.0.0) by
  `X-AB-Group` header, then cookie, then a 50/50 hash; the choice is sticky via cookie.

**Rollback mechanisms.** Rolling: revision history (5). Blue-green: previous slot
kept running. Canary/shadow/A-B: scale the experimental track to 0 (A/B also
re-points the proxy). `deploy.sh` reverts automatically when a rollout does not
become ready within the timeout.

## 2. Challenges faced and mitigations

| Challenge | Mitigation |
|-----------|------------|
| Coverage failed inside the container because `/app` was root-owned while the app runs as non-root | Create the user first and `COPY --chown`; tests and coverage now run in the image |
| Rolling update timed out on a resource-constrained node (pods took ~30 s to become ready) | Raised default rollout timeout/`progressDeadlineSeconds` to 300 s; the same logic correctly triggered an automatic rollback for a deliberately bad image (`v9.9.9`) |
| Shadow and A/B traffic need a service mesh or a specific ingress controller | Implemented both with a small nginx proxy (ConfigMap) so they work on any cluster, including Minikube without add-ons |
| Re-running `kubectl apply` would reset a running image to the manifest default | `deploy.sh` applies manifests only on first deployment and then uses `kubectl set image` |
| Shell scripts committed with Windows CRLF line endings break on Linux Jenkins | `.gitattributes` forces LF for `*.sh`, `Jenkinsfile`, `Dockerfile` |
| SonarQube initially flagged a reliability bug (table without caption) and a CSRF hotspot | Fixed the bug (v2.0.1, 0 bugs afterwards); hotspot reviewed and documented as safe for a stateless JSON API |
| `docker build` with the buildx container driver did not load the image locally | Use `--load` in scripts and docs |
| Port 9000 already in use on the workstation | SonarQube mapped to another host port for local verification (compose uses 9000) |

## 3. Key automation outcomes

* **Every commit is validated**: lint -> 15 Pytest tests -> SonarQube gate before any
  image is built or deployed; tests also run inside the built image.
* **Quality**: 98.5 % coverage, 0 bugs, 0 vulnerabilities, 0 code smells, 0 %
  duplication; quality gate passed (`docs/SONARQUBE_REPORT.md`).
* **Reproducible releases**: four tagged versions each built from a clean export of
  its git tag and pushed to Docker Hub.
* **All five strategies exercised on a real Kubernetes cluster (kind)** with observed
  results: rolling upgrade v1.1.0 -> v2.0.0 with zero unavailable pods and an
  automatic rollback for a bad image; blue-green switch and instant rollback;
  canary receiving a minority of requests (2 of 40 in one sample) and then promoted;
  shadow pod receiving a mirrored `POST /add_workout` while users got the primary's
  response; A/B routing by header, cookie and a 10/10 hash split over 20 clients.
* **Time to rollback** is seconds for blue-green/canary/shadow/A-B and one rollout
  for rolling updates, with no manual image rebuild.

## 4. Submission checklist (items requiring your accounts)

* Push the repository to a public GitHub repo and share the link.
* Run the Jenkins job against it (screenshots of green runs for recent commits).
* `scripts/build-all-versions.sh --push` to publish all versions to your Docker Hub.
* Deploy the five strategies on Minikube or a cloud cluster and submit the endpoint URL(s).
