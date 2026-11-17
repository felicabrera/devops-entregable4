#!/usr/bin/env bash
# Funciones y variables compartidas por los scripts. Se carga con: source "$(dirname "$0")/lib.sh"
# shellcheck disable=SC2034  # las variables las usan los scripts que cargan este archivo

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="$ROOT_DIR/helm-chart"

# Entorno: dev (Docker Desktop) o prod (cluster de la facultad)
ENV_NAME="${ENV_NAME:-dev}"
RELEASE="${RELEASE:-notes}"
IMAGE_TAG="${IMAGE_TAG:-dev}"

case "$ENV_NAME" in
  dev)
    NAMESPACE="${NAMESPACE:-notes}"
    VALUES_FILE="$CHART_DIR/values-dev.yaml"
    KUBE_CONTEXT="${KUBE_CONTEXT:-docker-desktop}"
    ;;
  prod)
    NAMESPACE="${NAMESPACE:-alumno-team9}"
    VALUES_FILE="$CHART_DIR/values-prod.yaml"
    KUBE_CONTEXT="${KUBE_CONTEXT:-ucu}"
    ;;
  *)
    echo "ENV_NAME debe ser dev o prod (recibido: $ENV_NAME)" >&2
    exit 1
    ;;
esac

# Registry local para el modo kind de Docker Desktop (el mismo que levanta jenkins/docker-compose.yml)
LOCAL_REGISTRY="${LOCAL_REGISTRY:-localhost:5001}"

KUBECTL=(kubectl --context "$KUBE_CONTEXT")
HELM=(helm --kube-context "$KUBE_CONTEXT")

KYVERNO_CHART_VERSION="3.10.0"
FALCO_CHART_VERSION="9.2.2"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m    %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m    %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

require() {
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 || die "falta el comando '$bin' en el PATH"
  done
}

# Espera a que todos los pods de un release esten Ready
wait_for_release() {
  log "Esperando a que los pods del release $RELEASE esten listos"
  "${KUBECTL[@]}" -n "$NAMESPACE" wait --for=condition=available deployment \
    -l "app.kubernetes.io/instance=$RELEASE" --timeout=180s
  "${KUBECTL[@]}" -n "$NAMESPACE" get pods -l "app.kubernetes.io/instance=$RELEASE" -o wide
}

# URL base de la app segun el entorno
app_url() {
  if [ "$ENV_NAME" = "prod" ]; then
    echo "https://notes-team9.reto-ucu.net"
  else
    echo "http://localhost"
  fi
}

# Deja corriendo el registry local en localhost:5001. Reutiliza el contenedor notes-registry de
# jenkins/docker-compose.yml si existe; si no, lo crea con la misma imagen.
ensure_local_registry() {
  if curl -fsS --max-time 3 "http://$LOCAL_REGISTRY/v2/" >/dev/null 2>&1; then
    return 0
  fi
  if docker container inspect notes-registry >/dev/null 2>&1; then
    docker start notes-registry >/dev/null
  else
    docker run -d --name notes-registry --restart unless-stopped -p 5001:5000 registry:3.1.2 >/dev/null
  fi
  for _ in $(seq 1 20); do
    curl -fsS --max-time 3 "http://$LOCAL_REGISTRY/v2/" >/dev/null 2>&1 && return 0
    sleep 1
  done
  die "el registry local no responde en $LOCAL_REGISTRY"
}
