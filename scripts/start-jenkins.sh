#!/usr/bin/env bash
# Levanta Jenkins en Docker con la configuracion como codigo (jenkins/casc.yaml):
# usuario admin, credenciales tomadas del entorno y el job del pipeline ya creado.
#
# Variables opcionales (se pueden poner en jenkins/.env):
#   JENKINS_ADMIN_PASSWORD  contrasena del usuario admin (por defecto: admin)
#   SNYK_TOKEN              token de Snyk para la etapa de dependencias
#   GHCR_USER / GHCR_TOKEN  credenciales para publicar en ghcr.io
#   KUBECONFIG_FILE         ruta a un kubeconfig para desplegar (por defecto: ~/.kube/config)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require docker

cd "$ROOT_DIR/jenkins"
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi
export JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-admin}"
export SNYK_TOKEN="${SNYK_TOKEN:-}"
export GHCR_USER="${GHCR_USER:-felicabrera}"
export GHCR_TOKEN="${GHCR_TOKEN:-}"
export KUBECONFIG_FILE="${KUBECONFIG_FILE:-$HOME/.kube/config}"

# Jenkins corre en un contenedor: el kubeconfig de Docker Desktop apunta a 127.0.0.1,
# que dentro del contenedor no es el host. Se genera una copia que usa kubernetes.docker.internal.
mkdir -p home
JENKINS_KUBECONFIG="$ROOT_DIR/jenkins/home/kubeconfig"
sed -E 's#https://(127\.0\.0\.1|localhost):6443#https://kubernetes.docker.internal:6443#' "$KUBECONFIG_FILE" > "$JENKINS_KUBECONFIG"
chmod 600 "$JENKINS_KUBECONFIG"

log "Construyendo la imagen de Jenkins (con docker, helm, kubectl, trivy, semgrep y snyk)"
docker compose build

log "Levantando Jenkins y el registry local"
docker compose up -d

log "Esperando a que Jenkins responda"
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null http://localhost:8081/login; then
    ok "Jenkins listo en http://localhost:8081 (admin / $JENKINS_ADMIN_PASSWORD)"
    echo "    Job: http://localhost:8081/job/notes-pipeline/"
    echo "    Registry local: localhost:5001"
    exit 0
  fi
  sleep 5
done
die "Jenkins no respondio a tiempo; revisar: docker compose -f jenkins/docker-compose.yml logs"
