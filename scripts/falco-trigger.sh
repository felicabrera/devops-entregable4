#!/usr/bin/env bash
# Ejecuta acciones sospechosas (sin abrir una shell) dentro de un pod del backend y
# guarda las alertas de Falco en reports/falco-event.log.
#   1. find / -name id_rsa          -> regla por defecto "Search Private Keys or Passwords"
#   2. cat /data/notes.json         -> regla propia "Lectura del archivo de notas por un proceso inesperado"
set -uo pipefail
source "$(dirname "$0")/lib.sh"
require kubectl jq

OUT="$ROOT_DIR/reports/falco-event.log"
mkdir -p "$(dirname "$OUT")"

POD="$("${KUBECTL[@]}" -n "$NAMESPACE" get pod -l app.kubernetes.io/component=backend -o jsonpath='{.items[0].metadata.name}')"
[ -n "$POD" ] || die "no hay pods del backend en $NAMESPACE"
SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log "Accion 1: busqueda de claves privadas en $POD (sin shell)"
"${KUBECTL[@]}" -n "$NAMESPACE" exec "$POD" -- find / -name id_rsa -not -path '/proc/*' 2>/dev/null || true

log "Accion 2: lectura del archivo de notas con un proceso ajeno a la API"
"${KUBECTL[@]}" -n "$NAMESPACE" exec "$POD" -- cat /data/notes.json >/dev/null 2>&1 || true

log "Esperando a que Falco procese los eventos"
sleep 8

{
  echo "# Alertas de Falco"
  echo "# Fecha: $(date -u +%Y-%m-%dT%H:%M:%SZ) | pod: $POD | namespace: $NAMESPACE"
  echo "# Falco: $("${KUBECTL[@]}" -n falco get ds falco -o jsonpath='{.spec.template.spec.containers[0].image}')"
  echo "# Acciones: 'kubectl exec $POD -- find / -name id_rsa' y 'kubectl exec $POD -- cat /data/notes.json'"
  echo
  "${KUBECTL[@]}" -n falco logs ds/falco -c falco --since-time="$SINCE" 2>/dev/null \
    | grep -E '^\{' \
    | jq -c 'select(.rule != null) | {time, priority, rule, output, tags}' \
    | grep -E 'id_rsa|notes.json|Busqueda|Lectura|Search Private' || echo "(sin alertas en la ventana de tiempo)"
} | tee "$OUT"

log "Evidencia guardada en $OUT"
