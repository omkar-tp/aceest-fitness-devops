# Custom Jenkins controller: Python (venv + pytest), Docker CLI, kubectl and
# SonarScanner pre-installed so the Jenkinsfile runs without extra agents.
FROM jenkins/jenkins:lts-jdk17

USER root

ARG KUBECTL_VERSION=v1.32.2
ARG SONAR_SCANNER_VERSION=6.2.1.4610

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 python3-venv python3-pip \
        docker.io curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl

RUN curl -fsSL -o /tmp/sonar.zip \
        "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip" \
    && unzip -q /tmp/sonar.zip -d /opt \
    && ln -s /opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-x64/bin/sonar-scanner /usr/local/bin/sonar-scanner \
    && rm /tmp/sonar.zip

USER jenkins

# Pre-install the plugins the pipeline relies on.
RUN jenkins-plugin-cli --plugins \
    workflow-aggregator git github junit credentials-binding \
    sonar pipeline-stage-view timestamps
