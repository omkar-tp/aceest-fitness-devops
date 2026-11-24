# Setup Guide

All commands assume the repository root. Replace `<user>` with your Docker Hub
username.

## 1. Local development and tests

```bash
python -m venv venv && . venv/bin/activate      # Windows: venv\Scripts\activate
pip install -r requirements.txt flake8
pytest -v --cov=app
python app.py                                    # http://localhost:5000
```

## 2. Git workflow and releases

* `main` is always releasable; work happens on `feature/*`, `docs/*`, merged with `--no-ff`.
* Releases are annotated tags: `v1.0.0` (Assignment 1 baseline), `v1.1.0`
  (version awareness), `v2.0.0` (delete/stats API), `v2.0.1` (SonarQube fix + CI/CD).

```bash
git remote add origin https://github.com/<github-user>/aceest-fitness-devops.git
git push -u origin main --tags
```

## 3. Jenkins + SonarQube

```bash
docker compose up -d --build        # Jenkins :8080, SonarQube :9000
docker compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

SonarQube: log in `admin/admin`, create a token (My Account > Security).

Jenkins configuration:

1. **Manage Jenkins > Credentials**
   * `dockerhub-creds` - Username with password (Docker Hub user + access token)
   * `kubeconfig` - Secret file (kubeconfig of the target cluster)
2. **Manage Jenkins > System > SonarQube servers** - name `SonarQube`,
   URL `http://sonarqube:9000`, token stored as a *Secret text* credential.
3. SonarQube **Administration > Configuration > Webhooks** - add
   `http://jenkins:8080/sonarqube-webhook/` (required for `waitForQualityGate`).
4. **New Item > Pipeline** (or Multibranch) - *Pipeline script from SCM*, point at the
   GitHub repo, script path `Jenkinsfile`. The `pollSCM('H/2 * * * *')` trigger in
   the Jenkinsfile polls Git every ~2 minutes; for push-based builds add a GitHub
   webhook to `http://<jenkins>/github-webhook/` as well.

Pipeline stages: Checkout > Install > Lint > Unit Tests (JUnit + coverage) >
SonarQube Analysis > Quality Gate > Docker Build > Test In Container > Push To
Docker Hub > Deploy To Kubernetes > Smoke Test. Build artifacts
(`aceest-build-<version>.tar.gz`, `coverage.xml`, `pytest-report.xml`) are
archived per build.

## 4. Docker / Docker Hub

```bash
docker build --build-arg APP_VERSION=2.0.1 -t <user>/aceest-fitness:v2.0.1 .
docker run --rm -p 5000:5000 <user>/aceest-fitness:v2.0.1
docker login
DOCKERHUB_USER=<user> scripts/build-all-versions.sh --push   # one image per git tag
```

Podman works unchanged: `podman build -t ...` / `podman push ...`.

## 5. Kubernetes (Minikube)

```bash
minikube start
export DOCKERHUB_USER=<user>
scripts/deploy.sh rolling v1.1.0        # first deployment
scripts/deploy.sh rolling v2.0.1        # rolling update (auto-rollback on failure)
minikube service aceest-rolling -n aceest --url
```

The manifests default to `v1.1.0` (stable) and `v2.0.0` (new) images; `deploy.sh`
then sets the new track to the version you pass.

| Strategy | Deploy | Verify | Promote | Rollback | NodePort |
|----------|--------|--------|---------|----------|----------|
| Rolling update | `deploy.sh rolling vX` | `/version` | gradual | `rollback.sh rolling` (`kubectl rollout undo`) | 30080 |
| Blue-Green | `deploy.sh blue-green vX` | preview svc `aceest-green-preview` | `promote.sh blue-green` | `rollback.sh blue-green` (selector flip) | 30081 / 30085 |
| Canary | `deploy.sh canary vX` | ~10 % of requests hit canary | `promote.sh canary` | `rollback.sh canary` | 30082 |
| Shadow | `deploy.sh shadow vX` | mirrored traffic visible on `aceest-shadow` | `promote.sh shadow` | `rollback.sh shadow` | 30083 |
| A/B testing | `deploy.sh ab vX` | header `X-AB-Group: a` or `b`, cookie, or 50/50 hash | `promote.sh ab` | `rollback.sh ab` | 30084 |

Every response carries `X-App-Version` / `X-Deploy-Color` headers and `/version`
returns `{"color": ..., "version": ...}`, so the active release is observable:

```bash
curl http://$(minikube ip):30081/version
```

On a cloud cluster (EKS/AKS/GKE) change the Services from `NodePort` to
`LoadBalancer` and use the external IP as the submission endpoint.
