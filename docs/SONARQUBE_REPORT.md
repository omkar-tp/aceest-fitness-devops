# SonarQube Report - ACEest Fitness & Gym

Analysed with SonarQube 9.9 LTS Community (project key `aceest-fitness`) using
`sonar-scanner` and the settings in [`sonar-project.properties`](../sonar-project.properties).
Coverage comes from `pytest --cov` (`coverage.xml`). Raw API output:
[`sonarqube-measures.json`](sonarqube-measures.json),
[`sonarqube-quality-gate.json`](sonarqube-quality-gate.json).

## Result: Quality Gate **PASSED** (release 2.0.1)

| Metric                      | Value  | Rating |
| --------------------------- | ------ | ------ |
| Bugs                        | 0      | A      |
| Vulnerabilities             | 0      | A      |
| Code smells                 | 0      | A      |
| Coverage                    | 98.5 % | -      |
| Duplicated lines            | 0.0 %  | -      |
| Lines of code               | 183    | -      |
| Security hotspots to review | 1      | -      |

## Findings and remediation

| # | Type | Location | Finding | Action |
|---|------|----------|---------|--------|
| 1 | Bug (minor) | `templates/index.html` | Table had no description (accessibility) | **Fixed** - added `<caption>`; re-scan shows 0 bugs (v2.0.1) |
| 2 | Security hotspot | `app.py` | "Make sure disabling CSRF protection is safe" | **Reviewed / accepted** - the service is a stateless JSON API with no authentication, sessions or cookies, so there is no ambient credential for CSRF to abuse. Revisit if login is added. |

Scan history: 2.0.0 (1 bug, reliability rating B) -> 2.0.1 (0 bugs, rating A).

## Reproduce

```bash
docker run -d --name sonarqube -p 9000:9000 sonarqube:lts-community
pytest --cov=app --cov-report=xml:coverage.xml
sonar-scanner -Dsonar.host.url=http://localhost:9000 -Dsonar.token=<token>
```

In Jenkins the same analysis runs in the **SonarQube Analysis** stage and the
**Quality Gate** stage aborts the build if the gate fails.
