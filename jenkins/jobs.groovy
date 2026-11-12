// Job DSL: crea el pipeline que lee el Jenkinsfile del repositorio publico
pipelineJob('notes-pipeline') {
  displayName('Notes API: CI/CD')
  description('Semgrep, Snyk, tests, imagen Docker, Trivy, publicacion y despliegue con Helm')
  logRotator { numToKeep(20) }
  definition {
    cpsScm {
      scm {
        git {
          remote { url('https://github.com/felicabrera/devops-entregable4.git') }
          branch('*/main')
        }
      }
      scriptPath('Jenkinsfile')
      lightweight(true)
    }
  }
  triggers {
    scm('H/5 * * * *')
  }
}
