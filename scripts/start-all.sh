#!/usr/bin/env bash
# Inicia todos los componentes del laboratorio en el entorno local:
# cluster (app + Prometheus + Grafana + Kyverno + Falco) y Jenkins.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/init.sh"
"$DIR/start-jenkins.sh"
"$DIR/populate.sh" 30
