#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${MENUEPLAN_APP_DIR:-/opt/apps/Menueplan}"
DOCKER_DIR="${MENUEPLAN_DOCKER_DIR:-/home/art/arkons/deploy/artserver/docker}"
COMPOSE_FILE="${DOCKER_DIR}/compose.menueplan.yml"
SMOKE_SCRIPT="${DOCKER_DIR}/smoke-menueplan.sh"

log() {
  printf '\n[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$1"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Befehl fehlt: $1" >&2
    exit 1
  }
}

need_cmd git
need_cmd tar

if [[ ! -d "${APP_DIR}/.git" ]]; then
  echo "Kein Git-Repository unter ${APP_DIR} gefunden." >&2
  exit 1
fi

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Docker-Compose-Datei fehlt: ${COMPOSE_FILE}" >&2
  exit 1
fi

if [[ ! -f "${SMOKE_SCRIPT}" ]]; then
  echo "Smoke-Test fehlt: ${SMOKE_SCRIPT}" >&2
  exit 1
fi

cd "${APP_DIR}"

BRANCH="$(git branch --show-current || true)"
if [[ -z "${BRANCH}" ]]; then
  BRANCH="main"
fi

TMP_DIR="$(mktemp -d /tmp/menueplan-deploy.XXXXXX)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

log "Lade neuesten Menüplan-Stand aus GitHub: origin/${BRANCH}"
git fetch --prune origin "${BRANCH}"

log "Erzeuge Deployment-Snapshot"
mkdir -p "${TMP_DIR}/repo"
git archive "origin/${BRANCH}" | tar -xf - -C "${TMP_DIR}/repo"

log "Aktualisiere Code ohne Eingriff in data, .env, smtp_config.php und Zertifikat"
while IFS= read -r deleted_path; do
  [[ -z "${deleted_path}" ]] && continue
  rm -rf -- "${APP_DIR}/${deleted_path}"
done < <(
  git diff --name-only --diff-filter=D HEAD "origin/${BRANCH}" -- . \
    ':(exclude)data' \
    ':(exclude).env' \
    ':(exclude)smtp_config.php' \
    ':(exclude)Zertifikat'
)

if command -v rsync >/dev/null 2>&1; then
  rsync -a \
    --exclude '.git/' \
    --exclude 'data/' \
    --exclude '.env' \
    --exclude 'smtp_config.php' \
    --exclude 'Zertifikat/' \
    "${TMP_DIR}/repo/" "${APP_DIR}/"
else
  log "rsync fehlt, synchronisiere ohne Löschung alter Dateien."
  (
    cd "${TMP_DIR}/repo"
    tar \
      --exclude='.git' \
      --exclude='data' \
      --exclude='.env' \
      --exclude='smtp_config.php' \
      --exclude='Zertifikat' \
      -cf - .
  ) | (
    cd "${APP_DIR}"
    tar -xf -
  )
fi

git reset --mixed "origin/${BRANCH}" >/dev/null

log "Repariere Datenrechte für den Container-User"
if [[ -f ops/fix_data_permissions.sh ]]; then
  sudo bash ops/fix_data_permissions.sh
else
  echo "[WARN] ops/fix_data_permissions.sh fehlt im Zielstand; nutze Inline-Fallback."
  if [[ -f ops/lib/common.sh ]]; then
    # shellcheck disable=SC1091
    . ./ops/lib/common.sh
    load_env_file ".env"
    APP_DATA_DIR="$(env_get APP_DATA_DIR "${APP_DIR}/data")"
    APP_RUNTIME_USER="$(env_get APP_RUNTIME_USER "www-data")"
    APP_RUNTIME_GROUP="$(env_get APP_RUNTIME_GROUP "${APP_RUNTIME_USER}")"
  else
    APP_DATA_DIR="${APP_DIR}/data"
    APP_RUNTIME_USER="www-data"
    APP_RUNTIME_GROUP="${APP_RUNTIME_USER}"
  fi

  case "${APP_DATA_DIR}" in
    /*) ;;
    *) APP_DATA_DIR="${APP_DIR}/${APP_DATA_DIR}" ;;
  esac

  sudo mkdir -p "${APP_DATA_DIR}" "${APP_DATA_DIR}/recipe_photos"
  sudo chown -R "${APP_RUNTIME_USER}:${APP_RUNTIME_GROUP}" "${APP_DATA_DIR}"
  sudo chmod -R ug+rwX "${APP_DATA_DIR}"
fi

log "Starte Menüplan-Container neu"
sudo docker compose -f "${COMPOSE_FILE}" restart menueplan

log "Docker-Smoke-Test"
bash "${SMOKE_SCRIPT}"

log "Prüfe öffentlichen Menüplan-Endpunkt"
curl -kfsS --max-time 10 https://arnet.internet-box.ch:4443/api.php?type=status >/dev/null

log "Menüplan GitHub-Update abgeschlossen"
