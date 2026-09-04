#!/usr/bin/env bash
set -euo pipefail

trap 'code=$?; printf "\n[FEHLER] Unerwarteter Abbruch in Zeile %s: %s\n" "${LINENO}" "${BASH_COMMAND}" >&2; exit "${code}"' ERR

APP_DIR="${IMMICH_APP_DIR:-/opt/immich}"
TARGET_VERSION="${IMMICH_TARGET_VERSION:-v3}"
CHECK_ONLY=0
STAMP="$(date +%Y%m%d-%H%M%S)"

COMPOSE_FILE=""
COMPOSE_OVERRIDE_FILES=()
ENV_FILE=""
UPLOAD_LOCATION=""
DB_DATA_LOCATION=""
BACKUP_BASE=""
BACKUP_DIR=""
DB_USERNAME=""
DB_DATABASE_NAME=""
DB_PASSWORD=""
CURRENT_ENV_VERSION=""
LATEST_RELEASE=""
DOCKER_CMD=(docker)

usage() {
  cat <<'EOF'
Immich Docker-Update fuer artserver

Verwendung:
  update-immich-docker.sh [--check-only] [--target VERSION]

Beispiele:
  bash update-immich-docker.sh --check-only
  bash update-immich-docker.sh --target v3

Zweck:
  Prueft die Immich-Installation, erstellt ein Update-Backup der
  Datenbank und Konfiguration, setzt IMMICH_VERSION und fuehrt danach
  docker compose pull && docker compose up -d aus.

Hinweise:
  --check-only prueft nur und veraendert nichts.
  VERSION ist standardmaessig v3, passend zur Immich-v3-Migration.
EOF
}

log() {
  printf '\n[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$1"
}

warn() {
  printf '[WARN] %s\n' "$1" >&2
}

fail() {
  printf '\n[FEHLER] %s\n' "$1" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Befehl fehlt: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check-only)
        CHECK_ONLY=1
        ;;
      --target)
        shift
        [[ $# -gt 0 ]] || fail "--target braucht eine Version, zum Beispiel v3."
        TARGET_VERSION="$1"
        ;;
      -h|--help|help)
        usage
        exit 0
        ;;
      *)
        fail "Unbekanntes Argument: $1"
        ;;
    esac
    shift
  done
}

trim_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "${value}"
}

env_get() {
  local key="$1"
  local default_value="${2:-}"
  local line
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${ENV_FILE}" | tail -n 1 || true)"
  if [[ -z "${line}" ]]; then
    printf '%s' "${default_value}"
    return 0
  fi
  trim_value "${line#*=}"
}

make_absolute_path() {
  local path_value="$1"
  if [[ -z "${path_value}" ]]; then
    printf '%s' ""
    return 0
  fi
  case "${path_value}" in
    /*) printf '%s' "${path_value}" ;;
    *) printf '%s' "${APP_DIR}/${path_value}" ;;
  esac
}

can_use_backup_base() {
  local candidate="$1"
  local parent
  parent="$(dirname "${candidate}")"

  if [[ -d "${candidate}" && -w "${candidate}" ]]; then
    return 0
  fi

  if [[ ! -e "${candidate}" && -d "${parent}" && -w "${parent}" ]]; then
    return 0
  fi

  return 1
}

resolve_backup_base() {
  if [[ -n "${IMMICH_UPDATE_BACKUP_DIR:-}" ]]; then
    BACKUP_BASE="${IMMICH_UPDATE_BACKUP_DIR}"
    BACKUP_DIR="${BACKUP_BASE}/${STAMP}"
    return 0
  fi

  local candidates=(
    "${UPLOAD_LOCATION%/}/backups/manual-updates"
    "${UPLOAD_LOCATION%/}/manual-update-backups"
    "/srv/immich/manual-update-backups"
    "/home/art/arkons/logs/admin/immich-update-backups"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if can_use_backup_base "${candidate}"; then
      BACKUP_BASE="${candidate}"
      BACKUP_DIR="${BACKUP_BASE}/${STAMP}"
      return 0
    fi
  done

  BACKUP_BASE="${candidates[0]}"
  BACKUP_DIR="${BACKUP_BASE}/${STAMP}"
}

choose_docker() {
  if docker info >/dev/null 2>&1; then
    DOCKER_CMD=(docker)
    return 0
  fi

  if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER_CMD=(sudo -n docker)
    return 0
  fi

  fail "Docker ist fuer diesen Benutzer nicht ohne Passwort erreichbar."
}

docker_cmd() {
  "${DOCKER_CMD[@]}" "$@"
}

compose_cmd() {
  local compose_args=(--env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
  local override_file
  for override_file in "${COMPOSE_OVERRIDE_FILES[@]}"; do
    compose_args+=(-f "${override_file}")
  done

  (
    cd "${APP_DIR}"
    "${DOCKER_CMD[@]}" compose "${compose_args[@]}" "$@"
  )
}

find_installation_files() {
  [[ -d "${APP_DIR}" ]] || fail "Immich-Ordner fehlt: ${APP_DIR}"

  if [[ -f "${APP_DIR}/docker-compose.yml" ]]; then
    COMPOSE_FILE="${APP_DIR}/docker-compose.yml"
  elif [[ -f "${APP_DIR}/compose.yml" ]]; then
    COMPOSE_FILE="${APP_DIR}/compose.yml"
  else
    fail "Keine docker-compose.yml oder compose.yml unter ${APP_DIR} gefunden."
  fi

  ENV_FILE="${APP_DIR}/.env"
  [[ -f "${ENV_FILE}" ]] || fail ".env fehlt: ${ENV_FILE}"

  COMPOSE_OVERRIDE_FILES=()
  if [[ -f "${APP_DIR}/docker-compose.override.yml" ]]; then
    COMPOSE_OVERRIDE_FILES+=("${APP_DIR}/docker-compose.override.yml")
  fi
  if [[ -f "${APP_DIR}/compose.override.yml" ]]; then
    COMPOSE_OVERRIDE_FILES+=("${APP_DIR}/compose.override.yml")
  fi
}

load_settings() {
  CURRENT_ENV_VERSION="$(env_get IMMICH_VERSION "release")"
  DB_USERNAME="$(env_get DB_USERNAME "postgres")"
  DB_DATABASE_NAME="$(env_get DB_DATABASE_NAME "immich")"
  DB_PASSWORD="$(env_get DB_PASSWORD "")"

  UPLOAD_LOCATION="$(make_absolute_path "$(env_get UPLOAD_LOCATION "/srv/immich/library")")"
  DB_DATA_LOCATION="$(make_absolute_path "$(env_get DB_DATA_LOCATION "/srv/immich/postgres")")"
  resolve_backup_base
}

fetch_latest_release() {
  curl -fsS --max-time 12 https://api.github.com/repos/immich-app/immich/releases/latest \
    | python3 -c 'import json, sys; print(json.load(sys.stdin).get("tag_name", ""))'
}

validate_target() {
  [[ "${TARGET_VERSION}" =~ ^v[0-9A-Za-z._-]+$ ]] || fail "Zielversion wirkt ungueltig: ${TARGET_VERSION}"
}

check_vector_migration() {
  if [[ "${TARGET_VERSION}" != v3* ]]; then
    return 0
  fi

  if grep -q "tensorchord/pgvecto-rs" "${COMPOSE_FILE}"; then
    fail "v3-Update gestoppt: docker-compose.yml verwendet noch pgvecto.rs. Erst die VectorChord-Migration aus der Immich-Doku erledigen."
  fi

  local vector_extension
  vector_extension="$(env_get DB_VECTOR_EXTENSION "")"
  if [[ "${vector_extension}" == *pgvecto* ]]; then
    fail "v3-Update gestoppt: DB_VECTOR_EXTENSION verweist noch auf pgvecto.rs. Erst auf VectorChord migrieren."
  fi
}

check_paths_and_space() {
  [[ -d "${UPLOAD_LOCATION}" ]] || fail "UPLOAD_LOCATION ist nicht erreichbar: ${UPLOAD_LOCATION}"
  [[ -d "${DB_DATA_LOCATION}" ]] || warn "DB_DATA_LOCATION ist nicht als Host-Ordner sichtbar: ${DB_DATA_LOCATION}"

  local df_target
  if [[ -d "${BACKUP_BASE}" ]]; then
    df_target="${BACKUP_BASE}"
  elif [[ -d "$(dirname "${BACKUP_BASE}")" ]]; then
    df_target="$(dirname "${BACKUP_BASE}")"
  else
    df_target="${UPLOAD_LOCATION}"
  fi

  if [[ "${CHECK_ONLY}" != "1" ]]; then
    mkdir -p "${BACKUP_BASE}"
  fi

  local free_kb
  free_kb="$(df -Pk "${df_target}" | awk 'NR == 2 {print $4}')"
  local min_kb=$((1024 * 1024))
  local db_kb=0
  if [[ -d "${DB_DATA_LOCATION}" ]]; then
    db_kb="$(du -sk "${DB_DATA_LOCATION}" 2>/dev/null | awk '{print $1}' || true)"
    if [[ "${db_kb}" =~ ^[0-9]+$ && "${db_kb}" -gt 0 ]]; then
      local half_db_kb=$((db_kb / 2))
      if [[ "${half_db_kb}" -gt "${min_kb}" ]]; then
        min_kb="${half_db_kb}"
      fi
    fi
  fi

  if [[ -n "${free_kb}" && "${free_kb}" =~ ^[0-9]+$ && "${free_kb}" -lt "${min_kb}" ]]; then
    fail "Zu wenig freier Platz fuer das Datenbank-Backup in ${BACKUP_BASE}. Frei: ${free_kb} KB, erwartet mindestens: ${min_kb} KB."
  fi
}

check_containers() {
  log "Docker-Compose-Konfiguration pruefen"
  compose_cmd config >/dev/null

  log "Aktueller Compose-Status"
  compose_cmd ps || true

  if ! docker_cmd inspect immich_postgres >/dev/null 2>&1; then
    fail "Container immich_postgres wurde nicht gefunden. Ohne laufende Datenbank wird kein Update gestartet."
  fi

  local postgres_running
  postgres_running="$(docker_cmd inspect -f '{{.State.Running}}' immich_postgres 2>/dev/null || true)"
  if [[ "${postgres_running}" != "true" ]]; then
    fail "Container immich_postgres läuft nicht. Ohne laufende Datenbank wird kein Update gestartet."
  fi
}

print_status_summary() {
  LATEST_RELEASE="$(fetch_latest_release 2>/dev/null || true)"
  if [[ -z "${LATEST_RELEASE}" ]]; then
    LATEST_RELEASE="unbekannt"
  fi

  local image
  image="$(docker_cmd inspect immich_server --format '{{.Config.Image}}' 2>/dev/null || true)"
  local version_json
  version_json="$(curl -fsS --max-time 5 http://127.0.0.1:18004/api/server/version 2>/dev/null || true)"

  log "Zusammenfassung"
  echo "Immich-Ordner: ${APP_DIR}"
  echo "Compose-Datei: ${COMPOSE_FILE}"
  if [[ "${#COMPOSE_OVERRIDE_FILES[@]}" -gt 0 ]]; then
    echo "Compose-Override: ${COMPOSE_OVERRIDE_FILES[*]}"
  else
    echo "Compose-Override: keine"
  fi
  echo ".env-Datei: ${ENV_FILE}"
  echo "IMMICH_VERSION aktuell: ${CURRENT_ENV_VERSION}"
  echo "IMMICH_VERSION Ziel: ${TARGET_VERSION}"
  echo "Neueste GitHub-Version laut API: ${LATEST_RELEASE}"
  echo "Aktuelles Server-Image: ${image:-nicht ermittelbar}"
  echo "Version laut lokaler API: ${version_json:-nicht erreichbar}"
  echo "Medienordner: ${UPLOAD_LOCATION}"
  echo "Datenbankordner: ${DB_DATA_LOCATION}"
  echo "Backup-Ziel: ${BACKUP_DIR}"
}

create_backup() {
  log "Update-Backup anlegen"
  mkdir -p "${BACKUP_DIR}"

  cp -a "${ENV_FILE}" "${BACKUP_DIR}/env.before"
  cp -a "${COMPOSE_FILE}" "${BACKUP_DIR}/$(basename "${COMPOSE_FILE}").before"
  compose_cmd config >"${BACKUP_DIR}/docker-compose.rendered.before.yml"
  compose_cmd ps >"${BACKUP_DIR}/docker-compose.ps.before.txt" || true
  docker_cmd inspect immich_server immich_postgres immich_machine_learning immich_redis \
    >"${BACKUP_DIR}/docker-inspect.before.json" 2>/dev/null || true

  {
    echo "Start: $(date --iso-8601=seconds)"
    echo "APP_DIR=${APP_DIR}"
    echo "COMPOSE_FILE=${COMPOSE_FILE}"
    printf 'COMPOSE_OVERRIDE_FILES=%s\n' "${COMPOSE_OVERRIDE_FILES[*]:-}"
    echo "ENV_FILE=${ENV_FILE}"
    echo "CURRENT_ENV_VERSION=${CURRENT_ENV_VERSION}"
    echo "TARGET_VERSION=${TARGET_VERSION}"
    echo "LATEST_RELEASE=${LATEST_RELEASE}"
    echo "UPLOAD_LOCATION=${UPLOAD_LOCATION}"
    echo "DB_DATA_LOCATION=${DB_DATA_LOCATION}"
  } >"${BACKUP_DIR}/update-context.txt"

  log "Datenbank-Dump erstellen"
  if [[ -n "${DB_PASSWORD}" ]]; then
    docker_cmd exec -e PGPASSWORD="${DB_PASSWORD}" immich_postgres \
      pg_dump --clean --if-exists --dbname="${DB_DATABASE_NAME}" --username="${DB_USERNAME}" \
      | gzip -9 >"${BACKUP_DIR}/immich-db-${STAMP}.sql.gz"
  else
    docker_cmd exec immich_postgres \
      pg_dump --clean --if-exists --dbname="${DB_DATABASE_NAME}" --username="${DB_USERNAME}" \
      | gzip -9 >"${BACKUP_DIR}/immich-db-${STAMP}.sql.gz"
  fi
  gzip -t "${BACKUP_DIR}/immich-db-${STAMP}.sql.gz"

  log "Backup fertig: ${BACKUP_DIR}"
}

update_env_version() {
  if [[ "${CURRENT_ENV_VERSION}" == "${TARGET_VERSION}" ]]; then
    log "IMMICH_VERSION ist bereits ${TARGET_VERSION}"
    return 0
  fi

  log "Setze IMMICH_VERSION in .env auf ${TARGET_VERSION}"
  local tmp_file
  tmp_file="$(mktemp "${ENV_FILE}.tmp.XXXXXX")"
  awk -v target="${TARGET_VERSION}" '
    BEGIN { done = 0 }
    /^[[:space:]]*IMMICH_VERSION[[:space:]]*=/ {
      print "IMMICH_VERSION=" target
      done = 1
      next
    }
    { print }
    END {
      if (done == 0) {
        if (NR > 0) {
          print ""
        }
        print "IMMICH_VERSION=" target
      }
    }
  ' "${ENV_FILE}" >"${tmp_file}"
  chmod --reference="${ENV_FILE}" "${tmp_file}" 2>/dev/null || true
  mv "${tmp_file}" "${ENV_FILE}"
}

run_update() {
  log "Immich-Images laden"
  compose_cmd pull

  log "Immich mit neuer Version starten"
  compose_cmd up -d
}

wait_for_immich() {
  log "Warte auf Immich-Ping"
  local health_url="http://127.0.0.1:18004/api/server/ping"
  local attempt
  for attempt in $(seq 1 60); do
    if curl -fsS --max-time 5 "${health_url}" >/dev/null 2>&1; then
      echo "Immich antwortet: ${health_url}"
      return 0
    fi
    sleep 5
  done

  fail "Immich antwortet nach dem Update nicht auf ${health_url}. Bitte Job-Log und Docker-Logs pruefen."
}

print_after_status() {
  log "Status nach dem Update"
  compose_cmd ps || true
  local version_json
  version_json="$(curl -fsS --max-time 5 http://127.0.0.1:18004/api/server/version 2>/dev/null || true)"
  echo "Version laut lokaler API: ${version_json:-nicht erreichbar}"
  echo "Backup liegt hier: ${BACKUP_DIR}"
  echo "Alte Docker-Images wurden bewusst nicht automatisch geloescht."
}

main() {
  parse_args "$@"

  need_cmd awk
  need_cmd curl
  need_cmd docker
  need_cmd gzip
  need_cmd python3

  validate_target
  find_installation_files
  load_settings
  choose_docker
  check_vector_migration
  check_paths_and_space
  check_containers
  print_status_summary

  if [[ "${CHECK_ONLY}" == "1" ]]; then
    log "Check-only abgeschlossen: Es wurde nichts veraendert."
    return 0
  fi

  create_backup
  update_env_version
  run_update
  wait_for_immich
  print_after_status

  log "Immich-Update abgeschlossen"
}

main "$@"
