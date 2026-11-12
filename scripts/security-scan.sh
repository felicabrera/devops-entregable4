#!/usr/bin/env bash
# Corre los analisis de seguridad y guarda los resultados en reports/:
#   semgrep-report.txt   analisis estatico (reglas registradas + .semgrep/)
#   snyk-report.txt      dependencias de Python (Snyk, requiere 'snyk auth')
#   trivy-report.txt     vulnerabilidades de las imagenes
# Uso: scripts/security-scan.sh [tag]   (por defecto: dev)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
require semgrep snyk trivy docker

TAG="${1:-$IMAGE_TAG}"
REPORTS="$ROOT_DIR/reports"
mkdir -p "$REPORTS"
cd "$ROOT_DIR" || exit 1

log "Semgrep"
{
  echo "# Semgrep $(semgrep --version) | $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# semgrep scan --config .semgrep --config p/python --config p/dockerfile --config p/kubernetes --config p/secrets --config p/owasp-top-ten"
  echo
  semgrep scan --config .semgrep --config p/python --config p/dockerfile --config p/kubernetes \
    --config p/secrets --config p/owasp-top-ten --metrics=off --text --error 2>&1
  rc=$?
  echo
  echo "# Codigo de salida: $rc"
} > "$REPORTS/semgrep-report.txt"
tail -15 "$REPORTS/semgrep-report.txt"

log "Snyk (dependencias de Python)"
if [ ! -d backend/.venv ]; then
  python3 -m venv backend/.venv && backend/.venv/bin/pip install -q -r backend/requirements.txt
fi
{
  echo "# Snyk $(snyk --version) | $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# snyk test --file=backend/requirements.txt --package-manager=pip --severity-threshold=high"
  echo
  (cd backend && snyk test --file=requirements.txt --package-manager=pip --command=.venv/bin/python --severity-threshold=high 2>&1)
  rc=$?
  echo "# Codigo de salida: $rc"
  echo
  echo "# snyk test (todas las severidades)"
  (cd backend && snyk test --file=requirements.txt --package-manager=pip --command=.venv/bin/python 2>&1)
  echo
  echo "# snyk code test backend/"
  snyk code test backend 2>&1
  rc=$?
  echo "# Codigo de salida: $rc"
} > "$REPORTS/snyk-report.txt"
tail -15 "$REPORTS/snyk-report.txt"

log "Trivy (imagenes)"
{
  echo "# Trivy $(trivy --version | head -1) | $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for img in "notes-backend:$TAG" "notes-frontend:$TAG"; do
    echo
    echo "## trivy image --severity HIGH,CRITICAL --ignore-unfixed $img"
    trivy image --severity HIGH,CRITICAL --ignore-unfixed --scanners vuln "$img" 2>&1
    echo
    echo "## trivy image --severity CRITICAL --ignore-unfixed --exit-code 1 $img (criterio de bloqueo del pipeline)"
    trivy image --severity CRITICAL --ignore-unfixed --scanners vuln --exit-code 1 "$img" 2>&1
    rc=$?
    echo "# Codigo de salida (CRITICAL con parche): $rc"
    echo
    echo "## trivy image --severity CRITICAL $img (incluye vulnerabilidades sin parche, solo informativo)"
    trivy image --severity CRITICAL --scanners vuln "$img" 2>&1
  done
  echo
  echo "## trivy config (Dockerfiles, Helm chart, Kubernetes, workflows)"
  trivy config --severity HIGH,CRITICAL --skip-dirs reports,jenkins/home,backend/.venv,kyverno/test . 2>&1
} > "$REPORTS/trivy-report.txt"
tail -20 "$REPORTS/trivy-report.txt"
