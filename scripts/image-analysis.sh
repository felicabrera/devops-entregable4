#!/usr/bin/env bash
# Analiza tamano y capas de las imagenes con SlimToolkit (xray) y dive, y deja
# la salida cruda en reports/image-analysis/. El resumen esta en reports/image-analysis.md.
# Uso: scripts/image-analysis.sh [tag]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
require docker dive

SLIM="${SLIM:-slim}"
TAG="${1:-$IMAGE_TAG}"
OUT="$ROOT_DIR/reports/image-analysis"
mkdir -p "$OUT"

for name in notes-backend notes-frontend; do
  img="$name:$TAG"
  log "$img"
  docker image inspect "$img" --format 'tamano: {{.Size}} bytes | capas: {{len .RootFS.Layers}} | arquitectura: {{.Architecture}}'
  docker history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' "$img" > "$OUT/$name-history.txt"

  if command -v "$SLIM" >/dev/null 2>&1; then
    if "$SLIM" --report "$OUT/$name-slim-xray.json" xray --target "$img" --changes all >/dev/null 2>&1; then
      ok "slim xray -> reports/image-analysis/$name-slim-xray.json"
    else
      warn "slim xray fallo para $img"
    fi
  else
    warn "slim no esta en el PATH (SLIM=/ruta/a/slim); se omite el xray"
  fi

  if CI=true dive "$img" --json "$OUT/$name-dive.json" >/dev/null 2>&1; then
    ok "dive -> reports/image-analysis/$name-dive.json"
  else
    warn "dive fallo para $img"
  fi
done
