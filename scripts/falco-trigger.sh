#!/usr/bin/env bash
# Ejecuta acciones sospechosas (sin abrir una shell) dentro de los pods de la app y
# guarda las alertas de Falco en reports/falco-event.log.
#   1. find / -name id_rsa (backend)                       -> regla por defecto "Search Private Keys or Passwords"
#   2. cat del almacenamiento de notas (AOF de Redis, o
#      /data/notes.json del backend si Redis esta apagado)  -> regla propia "Lectura del archivo de notas por un proceso inesperado"
set -uo pipefail
source "$(dirname "$0")/lib.sh"
require kubectl jq

OUT="$ROOT_DIR/reports/falco-event.log"
mkdir -p "$(dirname "$OUT")"

POD="$("${KUBECTL[@]}" -n "$NAMESPACE" get pod -l app.kubernetes.io/component=backend -o jsonpath='{.items[0].metadata.name}')"
[ -n "$POD" ] || die "no hay pods del backend en $NAMESPACE"
REDIS_POD="$("${KUBECTL[@]}" -n "$NAMESPACE" get pod -l app.kubernetes.io/component=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [ -n "$REDIS_POD" ]; then
  DATA_POD="$REDIS_POD"
  DATA_FILE="/data/appendonlydir/appendonly.aof.manifest"
else
  DATA_POD="$POD"
  DATA_FILE="/data/notes.json"
fi
SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log "Accion 1: busqueda de claves privadas en $POD (sin shell)"
"${KUBECTL[@]}" -n "$NAMESPACE" exec "$POD" -- find / -name id_rsa -not -path '/proc/*' 2>/dev/null || true

log "Accion 2: lectura de $DATA_FILE en $DATA_POD con un proceso ajeno al almacenamiento"
"${KUBECTL[@]}" -n "$NAMESPACE" exec "$DATA_POD" -- cat "$DATA_FILE" >/dev/null 2>&1 || true

log "Esperando a que Falco procese los eventos"
sleep 8

{
  echo "# Alertas de Falco"
  echo "# Fecha: $(date -u +%Y-%m-%dT%H:%M:%SZ) | pods: $POD $DATA_POD | namespace: $NAMESPACE"
  echo "# Falco: $("${KUBECTL[@]}" -n falco get ds falco -o jsonpath='{.spec.template.spec.containers[0].image}')"
  echo "# Acciones: 'kubectl exec $POD -- find / -name id_rsa' y 'kubectl exec $DATA_POD -- cat $DATA_FILE'"
  echo
  "${KUBECTL[@]}" -n falco logs ds/falco -c falco --since-time="$SINCE" 2>/dev/null \
    | grep -E '^\{' \
    | jq -c 'select(.rule != null) | {time, priority, rule, output, tags}' \
    | grep -E 'id_rsa|notes.json|appendonly|Busqueda|Lectura|Search Private' || echo "(sin alertas en la ventana de tiempo)"
} | tee "$OUT"

log "Evidencia guardada en $OUT"
