# ACEest Fitness & Gym - DevOps Assignment 2

Flask workout-tracking service with a complete CI/CD pipeline:
**Git/GitHub -> Jenkins -> Pytest -> SonarQube -> Docker/Docker Hub -> Kubernetes**
(rolling update, blue-green, canary, shadow, A/B testing, with rollback).

* Report: [docs/REPORT.md](docs/REPORT.md)
* Setup / run guide: [docs/SETUP.md](docs/SETUP.md)
* SonarQube results: [docs/SONARQUBE_REPORT.md](docs/SONARQUBE_REPORT.md)

## API

| Method | Endpoint | Description |
| ------ | -------- | ----------- |
| GET | `/` | Web UI |
| GET | `/health` | Liveness/readiness probe |
| GET | `/version` | Running release and deployment track |
| POST | `/add_workout` | Add workout (JSON or form) |
| GET | `/workouts` | List workouts and total duration |
| DELETE | `/workouts/<id>` | Delete a workout (v2.0.0+) |
| GET | `/stats` | Count / total / average / longest (v2.0.0+) |

## Versions

| Tag | Change |
| --- | ------ |
| v1.0.0 | Assignment 1 baseline |
| v1.1.0 | `/version`, release headers, non-root image, healthcheck |
| v2.0.0 | Delete workout + stats endpoints |
| v2.0.1 | SonarQube accessibility fix; Jenkins pipeline and K8s manifests |

`legacy_versions/` keeps the original Tkinter desktop versions (Aceestver-*.py)
for reference; they are excluded from analysis and images.

## Layout

```
app.py, templates/, tests/      Flask app and Pytest suite
Dockerfile, .dockerignore       Container image
Jenkinsfile                     CI/CD pipeline
jenkins/Dockerfile, docker-compose.yml   Local Jenkins + SonarQube stack
sonar-project.properties        SonarQube config
k8s/                            Manifests per strategy
scripts/                        deploy / promote / rollback / smoke-test / build-all-versions
.github/workflows/main.yml      GitHub Actions mirror of the CI stage
```

## Quick start

```bash
pip install -r requirements.txt && pytest -v --cov=app
docker build -t aceest-fitness . && docker run -p 5000:5000 aceest-fitness
```
