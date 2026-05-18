#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${ROBOWAIT_APP_DIR:-/opt/apps/robowait}"
SMOKE_SCRIPT="${APP_DIR}/scripts/smoke-docker.sh"

if [[ ! -f "${SMOKE_SCRIPT}" ]]; then
  echo "RoboWait-Smoke-Skript fehlt: ${SMOKE_SCRIPT}" >&2
  exit 1
fi

cd "${APP_DIR}"
bash "${SMOKE_SCRIPT}"
