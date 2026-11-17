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

EXTRA_ARGS=()
if [ "$ENV_NAME" = "dev" ]; then
  log "Construyendo imagenes locales (tag $IMAGE_TAG)"
  docker build --build-arg "APP_VERSION=$IMAGE_TAG" -t "notes-backend:$IMAGE_TAG" "$ROOT_DIR/backend"
  docker build -t "notes-frontend:$IMAGE_TAG" "$ROOT_DIR/frontend"

  # Docker Desktop tiene dos modos de Kubernetes. En modo kubeadm el nodo usa el daemon del host
  # (runtime docker://) y ve las imagenes recien construidas. En modo kind el nodo usa su propio
  # containerd y no las ve: hay que publicarlas en el registry local (localhost:5001).
  runtime="$("${KUBECTL[@]}" get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}')"
  if [[ "$runtime" != docker://* ]]; then
    log "Nodo con runtime $runtime: publicando las imagenes en el registry local $LOCAL_REGISTRY"
    ensure_local_registry
    # El tag incluye el id de la imagen para que cada cambio de codigo genere un rollout
    for comp in backend frontend; do
      id="$(docker image inspect -f '{{.Id}}' "notes-$comp:$IMAGE_TAG" | cut -d: -f2 | cut -c1-12)"
      ref="$LOCAL_REGISTRY/$comp:$IMAGE_TAG-$id"
      docker tag "notes-$comp:$IMAGE_TAG" "$ref"
      docker push -q "$ref" >/dev/null
      ok "$ref"
      EXTRA_ARGS+=(--set "$comp.image.repository=$comp" --set "$comp.image.tag=$IMAGE_TAG-$id")
    done
    EXTRA_ARGS+=(--set "image.registry=$LOCAL_REGISTRY")
  fi

  "$ROOT_DIR/scripts/install-operators.sh"
fi

log "Creando namespace $NAMESPACE (si no existe)"
"${KUBECTL[@]}" get namespace "$NAMESPACE" >/dev/null 2>&1 \
  || "${KUBECTL[@]}" create namespace "$NAMESPACE"

log "Desplegando el chart con Helm"
if [ "$ENV_NAME" = "prod" ]; then
  [ "$IMAGE_TAG" != "dev" ] || die "en prod hay que indicar IMAGE_TAG=<tag publicado en GHCR>"
  EXTRA_ARGS+=(--set "backend.image.tag=$IMAGE_TAG" --set "frontend.image.tag=$IMAGE_TAG")
  [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ] || EXTRA_ARGS+=(--set "monitoring.grafana.adminPassword=$GRAFANA_ADMIN_PASSWORD")
fi
"${HELM[@]}" upgrade --install "$RELEASE" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE" \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} \
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
