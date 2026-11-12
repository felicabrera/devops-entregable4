#!/usr/bin/env bash
# Aplica cada manifiesto de prueba contra el cluster con Kyverno activo y registra
# la evidencia (aceptado / rechazado y el motivo) en reports/kyverno-validation.log.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
require kubectl kyverno

OUT="$ROOT_DIR/reports/kyverno-validation.log"
TEST_DIR="$ROOT_DIR/kyverno/test"
mkdir -p "$(dirname "$OUT")"

{
  echo "# Validacion de politicas de Kyverno"
  echo "# Fecha: $(date -u +%Y-%m-%dT%H:%M:%SZ) | contexto: $KUBE_CONTEXT | namespace: $NAMESPACE"
  echo "# Kyverno: $("${KUBECTL[@]}" -n kyverno get deploy kyverno-admission-controller -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
  echo
  echo "## Politicas instaladas"
  "${KUBECTL[@]}" get validatingpolicy 2>&1
  echo
  echo "## Pruebas unitarias con el CLI (kyverno test)"
  (cd "$TEST_DIR" && kyverno test . 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g' | tail -3)
  echo
  echo "## Admision en el cluster (kubectl apply)"
  for f in pod-no-conforme pod-latest pod-sin-limites pod-root pod-privilegiado pod-init-no-conforme deployment-sin-probes pod-conforme; do
    echo
    echo "\$ kubectl apply -n $NAMESPACE -f kyverno/test/$f.yaml"
    if "${KUBECTL[@]}" apply -n "$NAMESPACE" -f "$TEST_DIR/$f.yaml" 2>&1; then
      echo "RESULTADO: ACEPTADO"
    else
      echo "RESULTADO: RECHAZADO"
    fi
  done
  echo
  echo "## Contenedor efimero con latest sobre un pod existente (kubectl debug)"
  echo "\$ kubectl debug -n $NAMESPACE pod-conforme --image=busybox:latest --profile=general -- true"
  if "${KUBECTL[@]}" debug -n "$NAMESPACE" pod-conforme --image=busybox:latest --profile=general -- true 2>&1; then
    echo "RESULTADO: ACEPTADO"
  else
    echo "RESULTADO: RECHAZADO"
  fi
  echo
  echo "## Limpieza"
  "${KUBECTL[@]}" -n "$NAMESPACE" delete pod pod-conforme --ignore-not-found 2>&1
} | tee "$OUT"

log "Evidencia guardada en $OUT"
