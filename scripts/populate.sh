#!/usr/bin/env bash
# Genera trafico contra la app para poblar los dashboards de Grafana:
# crea notas, las lista, consulta /stats y /health, borra algunas y provoca 404.
#
# Uso: scripts/populate.sh [duracion_en_segundos] [pausa_entre_rondas]
#      ENV_NAME=prod scripts/populate.sh 120
#      APP_URL=http://localhost:8080 scripts/populate.sh 60   (docker compose)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require curl

DURATION="${1:-90}"
PAUSE="${2:-0.2}"
BASE="${APP_URL:-$(app_url)}/api"

log "Generando trafico contra $BASE durante ${DURATION}s"
curl -fsS --max-time 5 "$BASE/health" >/dev/null || die "la API no responde en $BASE"

end=$((SECONDS + DURATION))
round=0
created=0
while [ "$SECONDS" -lt "$end" ]; do
  round=$((round + 1))
  # Entre 1 y 3 notas por ronda
  for _ in $(seq 1 $((RANDOM % 3 + 1))); do
    id=$(curl -s -X POST "$BASE/notes" -H 'Content-Type: application/json' \
      -d "{\"text\":\"nota ${round}-${RANDOM} generada por populate.sh\"}" | sed -E 's/.*"id":([0-9]+).*/\1/')
    created=$((created + 1))
    # La mitad de las notas se borran despues
    if [ $((RANDOM % 2)) -eq 0 ] && [ -n "$id" ]; then
      curl -s -o /dev/null -X DELETE "$BASE/notes/$id"
    fi
  done
  curl -s -o /dev/null "$BASE/notes"
  curl -s -o /dev/null "$BASE/stats"
  curl -s -o /dev/null "$BASE/health"
  curl -s -o /dev/null "$BASE/"
  # Algunos errores de cliente para ver 404 y 422 en el dashboard
  [ $((round % 5)) -ne 0 ] || curl -s -o /dev/null "$BASE/notes/999999"
  [ $((round % 7)) -ne 0 ] || curl -s -o /dev/null -X POST "$BASE/notes" -H 'Content-Type: application/json' -d '{"text":""}'
  # Pedidos legacy
  [ $((round % 10)) -ne 0 ] || curl -s -o /dev/null -X POST "$BASE/add/legacy-$round"
  printf '\r    rondas: %d | notas creadas: %d | total ahora: %s' "$round" "$created" \
    "$(curl -s "$BASE/stats" | sed -E 's/.*"total_notes":([0-9]+).*/\1/')"
  sleep "$PAUSE"
done
echo
ok "Trafico generado. Revisar el dashboard 'Notes: API, recursos y negocio' en Grafana."
