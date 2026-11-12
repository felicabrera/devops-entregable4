#!/usr/bin/env bash
# Borra todos los recursos creados por el laboratorio en el entorno indicado.
#   dev:  release de Helm, namespace, pods de prueba de Kyverno, politicas, Falco, Kyverno
#         y las imagenes locales. Con --keep-operators conserva Kyverno y Falco.
#   prod: release de Helm y pods de prueba del namespace del equipo.
# Uso: scripts/cleanup.sh [--keep-operators]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require kubectl helm

KEEP_OPERATORS=false
[ "${1:-}" != "--keep-operators" ] || KEEP_OPERATORS=true

log "Eliminando el release $RELEASE del namespace $NAMESPACE ($ENV_NAME)"
"${HELM[@]}" uninstall "$RELEASE" -n "$NAMESPACE" --ignore-not-found --wait || true
"${KUBECTL[@]}" -n "$NAMESPACE" delete pod -l app.kubernetes.io/part-of=notes --ignore-not-found
"${KUBECTL[@]}" -n "$NAMESPACE" delete pod pod-conforme pod-latest pod-sin-limites pod-root \
  pod-privilegiado pod-init-no-conforme pod-no-conforme --ignore-not-found
"${KUBECTL[@]}" -n "$NAMESPACE" delete deployment deploy-sin-probes --ignore-not-found
"${KUBECTL[@]}" -n "$NAMESPACE" delete pvc -l app.kubernetes.io/instance="$RELEASE" --ignore-not-found

if [ "$ENV_NAME" = "dev" ]; then
  "${KUBECTL[@]}" delete namespace "$NAMESPACE" --ignore-not-found --wait=false
  if [ "$KEEP_OPERATORS" = false ]; then
    log "Eliminando politicas, Kyverno y Falco"
    "${KUBECTL[@]}" delete -f "$ROOT_DIR/kyverno/policies/" --ignore-not-found || true
    "${HELM[@]}" uninstall falco -n falco --ignore-not-found --wait || true
    "${HELM[@]}" uninstall kyverno -n kyverno --ignore-not-found --wait || true
    "${KUBECTL[@]}" delete namespace falco kyverno --ignore-not-found --wait=false
  fi
  log "Eliminando imagenes locales"
  docker image rm -f "notes-backend:$IMAGE_TAG" "notes-frontend:$IMAGE_TAG" 2>/dev/null || true
fi

log "Recursos restantes en $NAMESPACE"
"${KUBECTL[@]}" -n "$NAMESPACE" get all 2>/dev/null || ok "namespace eliminado"
