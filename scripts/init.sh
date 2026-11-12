#!/usr/bin/env bash
# Inicializa el entorno completo:
#   1. construye las imagenes (solo dev; en prod las publica el pipeline en GHCR)
#   2. instala los operadores (Kyverno y Falco) y las politicas (solo dev)
#   3. despliega la app, Prometheus y Grafana con Helm
#   4. verifica que los pods arranquen y que el servicio responda
#
# Uso: scripts/init.sh              (dev, Docker Desktop)
#      ENV_NAME=prod IMAGE_TAG=<sha> scripts/init.sh   (cluster de la facultad)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require docker kubectl helm curl

log "Entorno: $ENV_NAME | contexto: $KUBE_CONTEXT | namespace: $NAMESPACE | release: $RELEASE"
"${KUBECTL[@]}" cluster-info | head -1

if [ "$ENV_NAME" = "dev" ]; then
  log "Construyendo imagenes locales (tag $IMAGE_TAG)"
  docker build --build-arg "APP_VERSION=$IMAGE_TAG" -t "notes-backend:$IMAGE_TAG" "$ROOT_DIR/backend"
  docker build -t "notes-frontend:$IMAGE_TAG" "$ROOT_DIR/frontend"

  "$ROOT_DIR/scripts/install-operators.sh"
fi

log "Creando namespace $NAMESPACE (si no existe)"
"${KUBECTL[@]}" get namespace "$NAMESPACE" >/dev/null 2>&1 \
  || "${KUBECTL[@]}" create namespace "$NAMESPACE"

log "Desplegando el chart con Helm"
EXTRA_ARGS=()
if [ "$ENV_NAME" = "prod" ]; then
  [ "$IMAGE_TAG" != "dev" ] || die "en prod hay que indicar IMAGE_TAG=<tag publicado en GHCR>"
  EXTRA_ARGS+=(--set "backend.image.tag=$IMAGE_TAG" --set "frontend.image.tag=$IMAGE_TAG")
  [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ] || EXTRA_ARGS+=(--set "monitoring.grafana.adminPassword=$GRAFANA_ADMIN_PASSWORD")
fi
"${HELM[@]}" upgrade --install "$RELEASE" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE" \
  "${EXTRA_ARGS[@]}" \
  --wait --timeout 5m

wait_for_release

log "Prueba de humo del release (helm test)"
"${HELM[@]}" test "$RELEASE" -n "$NAMESPACE" --logs

URL="$(app_url)"
log "Verificando acceso externo: $URL"
for i in $(seq 1 30); do
  if curl -fsS --max-time 5 "$URL/api/health" >/dev/null 2>&1; then
    ok "$(curl -fsS --max-time 5 "$URL/api/health")"
    break
  fi
  sleep 3
  [ "$i" -lt 30 ] || warn "la app todavia no responde en $URL (revisar el Service / la ruta)"
done

log "Listo"
if [ "$ENV_NAME" = "dev" ]; then
  echo "  App:        http://localhost"
  echo "  Prometheus: http://localhost:9091"
  echo "  Grafana:    http://localhost:3001 (admin / admin)"
else
  echo "  App:        https://notes-team9.reto-ucu.net"
  echo "  Prometheus: https://prometheus-team9.reto-ucu.net"
  echo "  Grafana:    https://grafana-team9.reto-ucu.net"
fi
echo "  Poblar dashboards: ENV_NAME=$ENV_NAME scripts/populate.sh"
