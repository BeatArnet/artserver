#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-status}"
SITE_FILE="${ROBOWAIT_CADDY_SITE_FILE:-/etc/caddy/sites-enabled/robowait-443.caddy}"
BACKUP_DIR="${ROBOWAIT_CADDY_BACKUP_DIR:-/etc/caddy/backups}"
HOST_WEB_PORT="${ROBOWAIT_HOST_WEB_PORT:-4445}"
HOST_REVERB_PORT="${ROBOWAIT_HOST_REVERB_PORT:-4446}"
DOCKER_WEB_PORT="${ROBOWAIT_DOCKER_WEB_PORT:-18002}"
DOCKER_REVERB_PORT="${ROBOWAIT_DOCKER_REVERB_PORT:-18003}"

usage() {
  cat <<EOF
Verwendung: sudo bash switch-robowait-caddy.sh [status|docker|host]

status  zeigt die aktuelle RoboWait-Caddy-Route
docker  routet RoboWait auf Docker: 127.0.0.1:${DOCKER_WEB_PORT}/${DOCKER_REVERB_PORT}
host    routet RoboWait zurück auf systemd: 127.0.0.1:${HOST_WEB_PORT}/${HOST_REVERB_PORT}
EOF
}

require_root_for_change() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Bitte mit sudo ausführen." >&2
    exit 1
  fi
}

show_status() {
  echo "Aktuelle Caddy-RoboWait-Route:"
  if [[ -f "${SITE_FILE}" ]]; then
    grep -nE 'reverse_proxy|robowait\.arkons\.ch|@reverb' "${SITE_FILE}" || true
  else
    echo "Site-Datei fehlt: ${SITE_FILE}" >&2
    exit 1
  fi
}

check_endpoint() {
  local name="$1"
  local url="$2"

  if curl -ksS -o /dev/null --max-time 10 "${url}"; then
    echo "  ${name} ${url} OK"
  else
    echo "FEHLER: ${name} ${url} antwortet nicht." >&2
    exit 1
  fi
}

check_tcp() {
  local name="$1"
  local port="$2"

  if timeout 4 bash -lc ":</dev/tcp/127.0.0.1/${port}" 2>/dev/null; then
    echo "  ${name} 127.0.0.1:${port} OK"
  else
    echo "FEHLER: ${name} 127.0.0.1:${port} antwortet nicht." >&2
    exit 1
  fi
}

rewrite_ports() {
  local web_port="$1"
  local reverb_port="$2"
  local tmp_file
  tmp_file="$(mktemp)"

  sed -E \
    -e "s/127\\.0\\.0\\.1:(${HOST_REVERB_PORT}|${DOCKER_REVERB_PORT})/127.0.0.1:${reverb_port}/g" \
    -e "s/127\\.0\\.0\\.1:(${HOST_WEB_PORT}|${DOCKER_WEB_PORT})/127.0.0.1:${web_port}/g" \
    "${SITE_FILE}" > "${tmp_file}"

  cat "${tmp_file}" > "${SITE_FILE}"
  rm -f "${tmp_file}"
}

apply_mode() {
  local target="$1"
  local web_port="$2"
  local reverb_port="$3"

  require_root_for_change

  echo "RoboWait direkte Endpunkte:"
  check_endpoint "${target} web" "http://127.0.0.1:${web_port}/"
  check_tcp "${target} reverb" "${reverb_port}"

  mkdir -p "${BACKUP_DIR}"
  local backup="${BACKUP_DIR}/robowait-caddy.before-${target}.$(date +%Y%m%d-%H%M%S)"
  cp -a "${SITE_FILE}" "${backup}"

  echo "Caddy-RoboWait-Route vor Umschaltung:"
  grep -nE 'reverse_proxy|@reverb' "${SITE_FILE}" || true

  rewrite_ports "${web_port}" "${reverb_port}"

  caddy validate --config /etc/caddy/Caddyfile
  systemctl reload caddy

  echo "Caddy-RoboWait-Route nach Umschaltung:"
  grep -nE 'reverse_proxy|@reverb' "${SITE_FILE}" || true
  echo "Fertig. Backup: ${backup}"
}

case "${MODE}" in
  status)
    show_status
    ;;
  docker)
    apply_mode "docker" "${DOCKER_WEB_PORT}" "${DOCKER_REVERB_PORT}"
    ;;
  host)
    apply_mode "host" "${HOST_WEB_PORT}" "${HOST_REVERB_PORT}"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
