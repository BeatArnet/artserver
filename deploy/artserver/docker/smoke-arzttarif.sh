#!/usr/bin/env bash
set -euo pipefail

PORT="${ARZTTARIF_DOCKER_PORT:-18000}"
BASE_URL="${1:-http://127.0.0.1:${PORT}}"

echo "Prüfe Arzttarif Docker-Prototyp: ${BASE_URL}"

version_body="$(mktemp)"
headers_body="$(mktemp)"
trap 'rm -f "${version_body}" "${headers_body}"' EXIT

ready=0
for attempt in $(seq 1 36); do
  if curl -fsS --max-time 10 "${BASE_URL}/api/version" -o "${version_body}"; then
    ready=1
    break
  fi
  echo "Warte auf App-Start (${attempt}/36)..."
  sleep 5
done

if [[ "${ready}" != "1" ]]; then
  echo "Arzttarif antwortet noch nicht auf ${BASE_URL}/api/version" >&2
  exit 1
fi

python3 -m json.tool "${version_body}" >/dev/null

curl -fsSI --max-time 30 "${BASE_URL}/" -o "${headers_body}"
head -n 1 "${headers_body}" | grep -Eq 'HTTP/[0-9.]+ 2[0-9][0-9]|HTTP/[0-9.]+ 3[0-9][0-9]'

echo "OK: /api/version liefert JSON und / ist erreichbar."
