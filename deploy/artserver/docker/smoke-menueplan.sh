#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${MENUEPLAN_BASE_URL:-http://127.0.0.1:18001}"

echo "Prüfe Menüplan Docker-Prototyp: ${BASE_URL}"

for i in $(seq 1 30); do
  if curl -fsS --max-time 5 "${BASE_URL}/api.php?type=status" >/tmp/menueplan-status.json 2>/tmp/menueplan-status.err; then
    echo "API status OK"
    break
  fi
  if [[ "$i" == "30" ]]; then
    cat /tmp/menueplan-status.err >&2 || true
    echo "Menüplan antwortet noch nicht auf ${BASE_URL}/api.php?type=status" >&2
    exit 1
  fi
  sleep 2
done

curl -fsSI --max-time 8 "${BASE_URL}/" | sed -n '1,12p'

blocked_status="$(curl -sSI --max-time 8 -o /tmp/menueplan-blocked.headers -w '%{http_code}' "${BASE_URL}/data/users.json" || true)"
if [[ "$blocked_status" != "403" ]]; then
  echo "FEHLER: /data/users.json muss 403 liefern, bekam aber ${blocked_status}." >&2
  cat /tmp/menueplan-blocked.headers >&2
  exit 1
fi

echo "Blockierter Datenpfad OK"
echo "Menüplan Docker-Smoke-Test OK"
