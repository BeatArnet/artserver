#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
CADDYFILE="${CADDYFILE_PATH:-/etc/caddy/Caddyfile}"
BACKUP_DIR="${CADDY_BACKUP_DIR:-/etc/caddy/backups}"
DOCKER_TARGET="${MENUEPLAN_DOCKER_TARGET:-127.0.0.1:18001}"
HOST_TARGET="${MENUEPLAN_HOST_TARGET:-unix//run/php/menuplan.sock}"

usage() {
  echo "Aufruf: sudo bash $0 {docker|host|status}" >&2
}

if [[ "$MODE" != "docker" && "$MODE" != "host" && "$MODE" != "status" ]]; then
  usage
  exit 2
fi

echo "Menüplan direkte Endpunkte:"
curl -fsS --max-time 10 "http://${DOCKER_TARGET}/api.php?type=status" >/dev/null \
  && echo "  docker http://${DOCKER_TARGET} OK" \
  || echo "  docker http://${DOCKER_TARGET} FEHLER"

if [[ -S /run/php/menuplan.sock ]]; then
  echo "  host ${HOST_TARGET} vorhanden"
else
  echo "  host ${HOST_TARGET} nicht als Socket gefunden"
fi

echo "Aktuelle Caddy-Menüplan-Route:"
grep -nE 'php_fastcgi unix//run/php/menuplan.sock|reverse_proxy 127\.0\.0\.1:18001' "$CADDYFILE" || true

if [[ "$MODE" == "status" ]]; then
  exit 0
fi

if [[ ! -f "$CADDYFILE" ]]; then
  echo "Caddyfile nicht gefunden: $CADDYFILE" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
cp -a "$CADDYFILE" "${BACKUP_DIR}/Caddyfile.before-menueplan-${MODE}.${STAMP}"

python3 - "$CADDYFILE" "$MODE" "$DOCKER_TARGET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
mode = sys.argv[2]
docker_target = sys.argv[3]
text = path.read_text()

host_line = "\t\tphp_fastcgi unix//run/php/menuplan.sock"
docker_line = f"\t\treverse_proxy {docker_target}"

if mode == "docker":
    if docker_line in text:
        pass
    elif host_line in text:
        if text.count(host_line) != 1:
            raise SystemExit(f"Erwarte genau eine Host-Menüplan-Zeile, gefunden: {text.count(host_line)}")
        text = text.replace(host_line, docker_line)
    else:
        raise SystemExit("Weder Host- noch Docker-Menüplan-Zeile gefunden.")
elif mode == "host":
    if host_line in text:
        pass
    elif docker_line in text:
        if text.count(docker_line) != 1:
            raise SystemExit(f"Erwarte genau eine Docker-Menüplan-Zeile, gefunden: {text.count(docker_line)}")
        text = text.replace(docker_line, host_line)
    else:
        raise SystemExit("Weder Docker- noch Host-Menüplan-Zeile gefunden.")

path.write_text(text)
PY

caddy validate --config "$CADDYFILE"
systemctl reload caddy
systemctl is-active --quiet caddy

echo "Caddy-Menüplan-Route nach Umschaltung:"
grep -nE 'php_fastcgi unix//run/php/menuplan.sock|reverse_proxy 127\.0\.0\.1:18001' "$CADDYFILE" || true
echo "Fertig. Backup: ${BACKUP_DIR}/Caddyfile.before-menueplan-${MODE}.${STAMP}"
