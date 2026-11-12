#!/usr/bin/env bash
# Instala los operadores de Kubernetes del laboratorio en el cluster local:
#   - Kyverno (chart oficial) y las politicas de kyverno/policies
#   - Falco (chart oficial) con falco/values.yaml
# Solo aplica al entorno dev: en el cluster de la facultad la cuenta del equipo
# no tiene permisos de cluster (CRDs, ClusterPolicy, DaemonSets privilegiados).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require kubectl helm jq

[ "$ENV_NAME" = "dev" ] || die "los operadores solo se instalan en dev (ENV_NAME=dev)"

helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1 || true
helm repo update kyverno falcosecurity >/dev/null

log "Instalando Kyverno (chart $KYVERNO_CHART_VERSION)"
# Si una instalacion anterior quedo en estado failed (sin revision desplegada), se limpia primero
if "${HELM[@]}" status kyverno -n kyverno >/dev/null 2>&1 \
   && [ "$("${HELM[@]}" status kyverno -n kyverno -o json | jq -r .info.status)" != "deployed" ]; then
  warn "release kyverno en estado no desplegado: se desinstala para reintentar"
  "${HELM[@]}" uninstall kyverno -n kyverno --wait || true
fi
"${HELM[@]}" upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace \
  --version "$KYVERNO_CHART_VERSION" \
  --values "$ROOT_DIR/kyverno/values.yaml" \
  --wait --timeout 5m
"${KUBECTL[@]}" -n kyverno get pods

log "Aplicando las politicas de Kyverno"
"${KUBECTL[@]}" apply -f "$ROOT_DIR/kyverno/policies/"
# La admision queda activa en cuanto el webhook esta configurado; "ready" ademas exige
# que el reports controller tenga permisos para los reportes en segundo plano
"${KUBECTL[@]}" wait --for=jsonpath='{.status.conditionStatus.ready}'=true validatingpolicy --all --timeout=60s \
  || warn "alguna politica no esta lista para reportes (la admision igual esta activa)"
"${KUBECTL[@]}" get validatingpolicy

log "Instalando Falco (chart $FALCO_CHART_VERSION)"
"${HELM[@]}" upgrade --install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --version "$FALCO_CHART_VERSION" \
  --values "$ROOT_DIR/falco/values.yaml" \
  --wait --timeout 5m
"${KUBECTL[@]}" -n falco get pods
