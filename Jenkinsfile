// Pipeline CI/CD de la Notes API.
// Etapas: checkout, Semgrep, Snyk, build y test, imagen Docker (build + Trivy + push),
// despliegue con Helm y prueba de humo. Las vulnerabilidades criticas detienen el pipeline.
pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 45, unit: 'MINUTES')
  }

  parameters {
    choice(name: 'TARGET_ENV', choices: ['dev', 'prod'], description: 'dev: Kubernetes de Docker Desktop. prod: cluster de la facultad (alumno-team9).')
    string(name: 'REGISTRY', defaultValue: 'ghcr.io/felicabrera/devops-entregable4', description: 'Registry donde se publican las imagenes. Usar localhost:5001 para el registry local de jenkins/docker-compose.yml.')
    booleanParam(name: 'DEPLOY', defaultValue: true, description: 'Desplegar con Helm al terminar')
    string(name: 'PLATFORM', defaultValue: 'linux/amd64', description: 'Plataforma de las imagenes (los nodos de la facultad son amd64)')
  }

  environment {
    SEMGREP_IMAGE = 'semgrep/semgrep:1.185.0'
    TRIVY_SEVERITY_BLOCK = 'CRITICAL'
    RELEASE = 'notes'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.GIT_SHA = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
          env.IMAGE_TAG = env.GIT_SHA
          env.BACKEND_IMAGE = "${params.REGISTRY}/backend:${env.IMAGE_TAG}"
          env.FRONTEND_IMAGE = "${params.REGISTRY}/frontend:${env.IMAGE_TAG}"
          env.NAMESPACE = params.TARGET_ENV == 'prod' ? 'alumno-team9' : 'notes'
          env.KUBECONFIG_CRED = params.TARGET_ENV == 'prod' ? 'kubeconfig-prod' : 'kubeconfig-dev'
        }
        sh 'git log -1 --oneline && echo "Imagenes: $BACKEND_IMAGE $FRONTEND_IMAGE"'
      }
    }

    stage('Analisis estatico (Semgrep)') {
      steps {
        sh '''
          mkdir -p reports/jenkins
          semgrep scan --config .semgrep --config p/python --config p/dockerfile --config p/kubernetes \
            --config p/secrets --metrics=off --error --text \
            --sarif-output reports/jenkins/semgrep.sarif 2>&1 | tee reports/jenkins/semgrep.txt
        '''
      }
    }

    stage('Dependencias (Snyk)') {
      steps {
        withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
          sh '''
            python3 -m venv .venv-snyk
            .venv-snyk/bin/pip install -q -r backend/requirements.txt
            cd backend
            # Falla si hay vulnerabilidades HIGH o CRITICAL en las dependencias
            snyk test --file=requirements.txt --package-manager=pip --command=../.venv-snyk/bin/python \
              --severity-threshold=high 2>&1 | tee ../reports/jenkins/snyk.txt
            snyk monitor --file=requirements.txt --package-manager=pip --command=../.venv-snyk/bin/python \
              --project-name=devops-entregable4-backend || true
          '''
        }
      }
    }

    stage('Build y test') {
      steps {
        sh '''
          python3 -m venv .venv-test
          .venv-test/bin/pip install -q -r backend/requirements-dev.txt
          cd backend
          ../.venv-test/bin/ruff check . && ../.venv-test/bin/ruff format --check .
          ../.venv-test/bin/pytest -q --junitxml=../reports/jenkins/pytest.xml
          cd ..
          helm lint helm-chart -f helm-chart/values-dev.yaml
          helm lint helm-chart -f helm-chart/values-prod.yaml --set backend.image.tag=x,frontend.image.tag=x
          helm template notes helm-chart -f helm-chart/values-prod.yaml --set backend.image.tag=x,frontend.image.tag=x > reports/jenkins/rendered.yaml
          kyverno apply kyverno/policies/ --resource reports/jenkins/rendered.yaml
          (cd kyverno/test && kyverno test .)
        '''
      }
      post {
        always {
          junit 'reports/jenkins/pytest.xml'
        }
      }
    }

    stage('Imagen Docker') {
      steps {
        sh '''
          docker buildx build --platform "$PLATFORM" --load \
            --build-arg APP_VERSION="$IMAGE_TAG" -t "$BACKEND_IMAGE" backend
          docker buildx build --platform "$PLATFORM" --load -t "$FRONTEND_IMAGE" frontend
          docker image ls "$BACKEND_IMAGE" "$FRONTEND_IMAGE"
        '''
      }
    }

    stage('Escaneo de imagen (Trivy)') {
      steps {
        sh '''
          for img in "$BACKEND_IMAGE" "$FRONTEND_IMAGE"; do
            trivy image --severity HIGH,CRITICAL --ignore-unfixed --scanners vuln "$img" | tee -a reports/jenkins/trivy.txt
            # Una CRITICAL con parche disponible detiene el pipeline (las sin parche se documentan en el README)
            trivy image --severity "$TRIVY_SEVERITY_BLOCK" --ignore-unfixed --scanners vuln --exit-code 1 --quiet "$img"
          done
        '''
      }
    }

    stage('Publicar imagen') {
      steps {
        script {
          if (params.REGISTRY.startsWith('localhost:') || params.REGISTRY.startsWith('registry:')) {
            sh 'docker push "$BACKEND_IMAGE" && docker push "$FRONTEND_IMAGE"'
          } else {
            withCredentials([usernamePassword(credentialsId: 'ghcr-credentials', usernameVariable: 'REG_USER', passwordVariable: 'REG_TOKEN')]) {
              sh '''
                echo "$REG_TOKEN" | docker login ghcr.io -u "$REG_USER" --password-stdin
                docker push "$BACKEND_IMAGE"
                docker push "$FRONTEND_IMAGE"
                docker logout ghcr.io
              '''
            }
          }
        }
      }
    }

    stage('Despliegue (Helm)') {
      when { expression { params.DEPLOY } }
      steps {
        withCredentials([file(credentialsId: env.KUBECONFIG_CRED, variable: 'KUBECONFIG')]) {
          sh '''
            kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
            helm upgrade --install "$RELEASE" helm-chart \
              --namespace "$NAMESPACE" \
              --values "helm-chart/values-${TARGET_ENV}.yaml" \
              --set image.registry="$REGISTRY" \
              --set backend.image.repository=backend --set backend.image.tag="$IMAGE_TAG" \
              --set frontend.image.repository=frontend --set frontend.image.tag="$IMAGE_TAG" \
              --set image.pullPolicy=IfNotPresent \
              --wait --timeout 5m
            kubectl -n "$NAMESPACE" rollout status deployment/notes-backend
            kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/instance="$RELEASE" -o wide
          '''
        }
      }
    }

    stage('Prueba de humo') {
      when { expression { params.DEPLOY } }
      steps {
        withCredentials([file(credentialsId: env.KUBECONFIG_CRED, variable: 'KUBECONFIG')]) {
          sh 'helm test "$RELEASE" -n "$NAMESPACE" --logs'
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'reports/jenkins/**', allowEmptyArchive: true
      sh 'docker image rm -f "$BACKEND_IMAGE" "$FRONTEND_IMAGE" >/dev/null 2>&1 || true'
    }
    failure {
      echo "Pipeline detenido: revisar la etapa fallida. Si fue Snyk o Trivy, hay vulnerabilidades HIGH/CRITICAL que corregir."
    }
  }
}
