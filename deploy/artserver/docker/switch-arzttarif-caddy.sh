#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-status}"
CADDYFILE="/etc/caddy/Caddyfile"
BACKUP_DIR="/etc/caddy/backups"

case "${MODE}" in
  docker)
    TARGET_PORT="18000"
    ;;
  host)
    TARGET_PORT="8000"
    ;;
  status)
    TARGET_PORT=""
    ;;
  *)
    echo "Usage: sudo bash $0 {docker|host|status}" >&2
    exit 2
    ;;
esac

if [[ "${MODE}" != "status" && "${EUID}" -ne 0 ]]; then
  echo "Bitte mit sudo ausfuehren: sudo bash $0 ${MODE}" >&2
  exit 1
fi

echo "Arzttarif direkte Endpunkte:"
curl -fsS --max-time 15 http://127.0.0.1:8000/api/version >/dev/null && echo "  host   127.0.0.1:8000  OK" || echo "  host   127.0.0.1:8000  FEHLER"
curl -fsS --max-time 15 http://127.0.0.1:18000/api/version >/dev/null && echo "  docker 127.0.0.1:18000 OK" || echo "  docker 127.0.0.1:18000 FEHLER"

echo ""
echo "Aktuelle Caddy-Arzttarif-Route:"
grep -n "reverse_proxy 127.0.0.1:\(8000\|18000\)" "${CADDYFILE}" || true

if [[ "${MODE}" == "status" ]]; then
  exit 0
fi

if ! curl -fsS --max-time 15 "http://127.0.0.1:${TARGET_PORT}/api/version" >/dev/null; then
  echo "Zielport ${TARGET_PORT} antwortet nicht. Caddy wird nicht geaendert." >&2
  exit 1
fi

install -d -m 755 "${BACKUP_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"
cp -a "${CADDYFILE}" "${BACKUP_DIR}/Caddyfile.before-arzttarif-${MODE}.${STAMP}"

python3 - "$CADDYFILE" "$TARGET_PORT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
target_port = sys.argv[2]
text = path.read_text()
old_8000 = "reverse_proxy 127.0.0.1:8000"
old_18000 = "reverse_proxy 127.0.0.1:18000"
new = f"reverse_proxy 127.0.0.1:{target_port}"

count = text.count(old_8000) + text.count(old_18000)
if count != 1:
    raise SystemExit(f"Erwarte genau eine Arzttarif reverse_proxy-Zeile, gefunden: {count}")

text = text.replace(old_8000, new).replace(old_18000, new)
path.write_text(text)
PY

caddy validate --config "${CADDYFILE}"
systemctl reload caddy
systemctl is-active --quiet caddy

echo ""
echo "Caddy-Arzttarif-Route nach Umschaltung:"
grep -n "reverse_proxy 127.0.0.1:\(8000\|18000\)" "${CADDYFILE}" || true

echo ""
echo "Caddy-Test ueber lokalen HTTPS-Port 444:"
curl -kfsS --max-time 20 --resolve arnet.internet-box.ch:444:127.0.0.1 \
  https://arnet.internet-box.ch:444/api/version
echo ""

echo "Fertig. Backup: ${BACKUP_DIR}/Caddyfile.before-arzttarif-${MODE}.${STAMP}"
