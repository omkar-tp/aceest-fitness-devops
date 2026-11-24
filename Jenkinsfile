// ACEest Fitness & Gym - CI/CD pipeline
// Poll SCM -> lint -> pytest(+coverage) -> SonarQube + quality gate ->
// Docker build -> tests inside the container -> push to Docker Hub ->
// Kubernetes deployment (rolling | blue-green | canary | shadow | ab) -> smoke test.
//
// Jenkins prerequisites (see docs/SETUP.md):
//   Credentials : dockerhub-creds (username/password), kubeconfig (secret file)
//   SonarQube   : server named "SonarQube" under Manage Jenkins > System
//   Tools       : docker, kubectl and sonar-scanner on the agent (jenkins/Dockerfile)
pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
        timeout(time: 40, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
    }

    // Hook: poll GitHub every ~2 minutes and build on new commits/tags.
    triggers {
        pollSCM('H/2 * * * *')
    }

    parameters {
        choice(name: 'DEPLOY_STRATEGY',
               choices: ['none', 'rolling', 'blue-green', 'canary', 'shadow', 'ab'],
               description: 'Kubernetes deployment strategy to run after a successful build (none = CI only)')
        booleanParam(name: 'PUSH_IMAGE', defaultValue: false,
                     description: 'Push the image to Docker Hub (needs real dockerhub-creds)')
        string(name: 'IMAGE_VERSION', defaultValue: '',
               description: 'Image tag to build/deploy (empty = git describe, e.g. v2.0.0)')
        booleanParam(name: 'PUSH_LATEST', defaultValue: false,
                     description: 'Also tag and push :latest')
    }

    environment {
        IMAGE_NAME = 'aceest-fitness'
        SONAR_PROJECT = 'aceest-fitness'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    def described = sh(script: 'git describe --tags --always', returnStdout: true).trim()
                    env.VERSION_TAG = params.IMAGE_VERSION?.trim() ? params.IMAGE_VERSION.trim() : described
                    env.APP_VERSION = env.VERSION_TAG.replaceFirst(/^v/, '')
                    echo "Building release ${env.VERSION_TAG} (build #${env.BUILD_NUMBER})"
                }
            }
        }

        stage('Install Dependencies') {
            steps {
                sh '''
                    python3 -m venv venv
                    . venv/bin/activate
                    pip install --quiet --upgrade pip
                    pip install --quiet -r requirements.txt flake8
                '''
            }
        }

        stage('Lint') {
            steps {
                sh '''
                    . venv/bin/activate
                    flake8 app.py tests --count --select=E9,F63,F7,F82 --show-source --statistics
                    flake8 app.py tests --count --exit-zero --max-line-length=100 --statistics
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    . venv/bin/activate
                    pytest -v --junitxml=pytest-report.xml \
                           --cov=app --cov-report=xml:coverage.xml --cov-report=term
                '''
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'pytest-report.xml'
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh '''
                        sonar-scanner \
                          -Dsonar.projectKey=${SONAR_PROJECT} \
                          -Dsonar.projectVersion=${APP_VERSION}
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Docker Build') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DH_USER',
                                                  passwordVariable: 'DH_PASS')]) {
                    sh '''
                        docker build \
                          --build-arg APP_VERSION=${APP_VERSION} \
                          -t ${DH_USER}/${IMAGE_NAME}:${VERSION_TAG} \
                          -t ${DH_USER}/${IMAGE_NAME}:build-${BUILD_NUMBER} .
                    '''
                }
            }
        }

        stage('Test In Container') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DH_USER',
                                                  passwordVariable: 'DH_PASS')]) {
                    sh '''
                        docker run --rm ${DH_USER}/${IMAGE_NAME}:${VERSION_TAG} pytest -v
                    '''
                }
            }
        }

        stage('Push To Docker Hub') {
            when {
                allOf {
                    expression { params.PUSH_IMAGE }
                    anyOf {
                        branch 'main'
                        buildingTag()
                        expression { env.BRANCH_NAME == null }   // non-multibranch job
                    }
                }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DH_USER',
                                                  passwordVariable: 'DH_PASS')]) {
                    sh '''
                        echo "${DH_PASS}" | docker login -u "${DH_USER}" --password-stdin
                        docker push ${DH_USER}/${IMAGE_NAME}:${VERSION_TAG}
                        docker push ${DH_USER}/${IMAGE_NAME}:build-${BUILD_NUMBER}
                        if [ "${PUSH_LATEST}" = "true" ]; then
                          docker tag ${DH_USER}/${IMAGE_NAME}:${VERSION_TAG} ${DH_USER}/${IMAGE_NAME}:latest
                          docker push ${DH_USER}/${IMAGE_NAME}:latest
                        fi
                        docker logout
                    '''
                }
            }
        }

        stage('Deploy To Kubernetes') {
            when {
                allOf {
                    expression { params.DEPLOY_STRATEGY != 'none' }
                    anyOf {
                        branch 'main'
                        buildingTag()
                        expression { env.BRANCH_NAME == null }
                    }
                }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DH_USER',
                                                  passwordVariable: 'DH_PASS'),
                                 file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                        export DOCKERHUB_USER="${DH_USER}"
                        chmod +x scripts/*.sh
                        scripts/deploy.sh "${DEPLOY_STRATEGY}" "${VERSION_TAG}"
                    '''
                }
            }
        }

        stage('Smoke Test') {
            when {
                allOf {
                    expression { params.DEPLOY_STRATEGY != 'none' }
                    anyOf {
                        branch 'main'
                        buildingTag()
                        expression { env.BRANCH_NAME == null }
                    }
                }
            }
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    // Port-forward the strategy's entry Service and probe it.
                    sh '''
                        case "${DEPLOY_STRATEGY}" in
                          rolling)    SVC=aceest-rolling ;;
                          blue-green) SVC=aceest-green-preview ;;
                          canary)     SVC=aceest-canary ;;
                          shadow)     SVC=aceest-shadow-entry ;;
                          ab)         SVC=aceest-ab-entry ;;
                        esac
                        kubectl -n aceest port-forward svc/${SVC} 18080:80 >/dev/null 2>&1 &
                        PF=$!
                        trap "kill $PF" EXIT
                        sleep 3
                        scripts/smoke-test.sh http://127.0.0.1:18080
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'tar czf aceest-build-${APP_VERSION:-unknown}.tar.gz app.py templates requirements.txt Dockerfile k8s scripts || true'
            archiveArtifacts artifacts: 'aceest-build-*.tar.gz, coverage.xml, pytest-report.xml',
                             allowEmptyArchive: true, fingerprint: true
            sh 'rm -rf venv || true'
        }
        success {
            echo "BUILD SUCCEEDED: release ${env.VERSION_TAG} passed all quality gates."
        }
        failure {
            echo 'BUILD FAILED: see the failing stage above. Deployments auto-rollback on failure.'
        }
    }
}
