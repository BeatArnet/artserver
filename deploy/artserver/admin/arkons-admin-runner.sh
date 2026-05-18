#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CATALOG="${SCRIPT_DIR}/../artserver-script-catalog.json"
if [[ ! -f "${DEFAULT_CATALOG}" ]]; then
  DEFAULT_CATALOG="${SCRIPT_DIR}/../../../artserver-script-catalog.json"
fi
if [[ ! -f "${DEFAULT_CATALOG}" ]]; then
  DEFAULT_CATALOG="/home/art/arkons/deploy/artserver/artserver-script-catalog.json"
fi

CATALOG="${ARKONS_ADMIN_SCRIPT_CATALOG:-${DEFAULT_CATALOG}}"
LOG_DIR="${ARKONS_ADMIN_LOG_DIR:-/home/art/arkons/logs/admin/jobs}"
LOCK_DIR="${ARKONS_ADMIN_LOCK_DIR:-/tmp/arkons-admin-locks}"
COMMAND=""
SCRIPT_ID=""
CONFIRMATION=""
DRY_RUN=0

usage() {
  cat <<'EOF'
Arkons Admin Runner

Verwendung:
  arkons-admin-runner.sh list
  arkons-admin-runner.sh show <skript-id>
  arkons-admin-runner.sh run <skript-id> [--confirm SCHUTZWORT] [--dry-run]

Zweck:
  Startet nur freigegebene serverseitige Skripte aus artserver-script-catalog.json.
  Freie Shell-Befehle werden nicht akzeptiert.

Umgebung:
  ARKONS_ADMIN_SCRIPT_CATALOG  Pfad zum Skriptkatalog
  ARKONS_ADMIN_LOG_DIR         Logverzeichnis für Jobs
  ARKONS_ADMIN_LOCK_DIR        Lockverzeichnis gegen parallele Jobs
EOF
}

die() {
  echo "Fehler: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Befehl fehlt: $1"
}

parse_args() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 2
  fi

  COMMAND="$1"
  shift

  case "${COMMAND}" in
    list)
      if [[ $# -ne 0 ]]; then
        die "list erwartet keine weiteren Argumente."
      fi
      ;;
    show)
      if [[ $# -ne 1 ]]; then
        die "show erwartet genau eine Skript-ID."
      fi
      SCRIPT_ID="$1"
      ;;
    run)
      if [[ $# -lt 1 ]]; then
        die "run erwartet eine Skript-ID."
      fi
      SCRIPT_ID="$1"
      shift
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --confirm)
            shift
            [[ $# -gt 0 ]] || die "--confirm braucht ein Schutzwort."
            CONFIRMATION="$1"
            ;;
          --dry-run)
            DRY_RUN=1
            ;;
          *)
            die "Unbekanntes Argument: $1"
            ;;
        esac
        shift
      done
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      die "Unbekannter Befehl: ${COMMAND}"
      ;;
  esac
}

assert_catalog() {
  [[ -f "${CATALOG}" ]] || die "Skriptkatalog nicht gefunden: ${CATALOG}"
}

list_scripts() {
  python3 - "${CATALOG}" <<'PY'
import json
import sys

catalog_path = sys.argv[1]
with open(catalog_path, encoding="utf-8") as handle:
    data = json.load(handle)

scripts = data.get("scripts", [])
print("ID\tGruppe\tRisiko\tStartbar\tOrt\tName")
for entry in sorted(scripts, key=lambda item: (item.get("group", ""), item.get("id", ""))):
    run_type = (entry.get("run") or {}).get("type", "")
    server_runnable = entry.get("enabled") is True and entry.get("location") == "artserver" and run_type == "ServerShell"
    status = "ja" if server_runnable else "nein"
    print(
        f"{entry.get('id', '')}\t"
        f"{entry.get('group', '')}\t"
        f"{entry.get('risk', '')}\t"
        f"{status}\t"
        f"{entry.get('location', '')}\t"
        f"{entry.get('label', '')}"
    )
PY
}

show_script() {
  python3 - "${CATALOG}" "${SCRIPT_ID}" <<'PY'
import json
import sys

catalog_path, script_id = sys.argv[1], sys.argv[2]
with open(catalog_path, encoding="utf-8") as handle:
    data = json.load(handle)

entry = next((item for item in data.get("scripts", []) if item.get("id") == script_id), None)
if entry is None:
    print(f"Skript-ID nicht gefunden: {script_id}", file=sys.stderr)
    sys.exit(3)

run = entry.get("run") or {}
server_runnable = entry.get("enabled") is True and entry.get("location") == "artserver" and run.get("type") == "ServerShell"

print(f"ID: {entry.get('id', '')}")
print(f"Name: {entry.get('label', '')}")
print(f"Gruppe: {entry.get('group', '')}")
print(f"Ort: {entry.get('location', '')}")
print(f"Risiko: {entry.get('risk', '')}")
print(f"Startbar auf artserver: {'ja' if server_runnable else 'nein'}")
print(f"Schutzwort: {entry.get('requiresConfirmation', '') or '-'}")
print(f"Quelle: {entry.get('source', '')}")
print("")
print("Hinweis:")
print(entry.get("notes", "") or "-")
if run:
    print("")
    print("Ausführung:")
    print(f"  Typ: {run.get('type', '')}")
    if run.get("cwd"):
        print(f"  Ordner: {run.get('cwd')}")
    if run.get("command"):
        print(f"  Befehl: {run.get('command')}")
PY
}

load_script_env() {
  python3 - "${CATALOG}" "${SCRIPT_ID}" <<'PY'
import json
import re
import shlex
import sys

catalog_path, script_id = sys.argv[1], sys.argv[2]
with open(catalog_path, encoding="utf-8") as handle:
    data = json.load(handle)

entry = next((item for item in data.get("scripts", []) if item.get("id") == script_id), None)
if entry is None:
    print(f"ERROR={shlex.quote('Skript-ID nicht gefunden: ' + script_id)}")
    print("ERROR_CODE=3")
    sys.exit(0)

run = entry.get("run") or {}
if entry.get("enabled") is not True:
    print(f"ERROR={shlex.quote('Skript ist im Katalog nicht freigegeben: ' + script_id)}")
    print("ERROR_CODE=4")
    sys.exit(0)

if entry.get("location") != "artserver" or run.get("type") != "ServerShell":
    print(f"ERROR={shlex.quote('Skript ist nicht serverseitig ausführbar: ' + script_id)}")
    print("ERROR_CODE=5")
    sys.exit(0)

cwd = run.get("cwd") or "/"
command = run.get("command") or ""
if not command:
    print(f"ERROR={shlex.quote('ServerShell-Eintrag hat keinen Befehl: ' + script_id)}")
    print("ERROR_CODE=6")
    sys.exit(0)

lock_scope = entry.get("lockScope")
if not lock_scope:
    lock_scope = script_id.split(".", 1)[0]
lock_scope = re.sub(r"[^A-Za-z0-9_.-]+", "-", lock_scope)

safe_id = re.sub(r"[^A-Za-z0-9_.-]+", "-", script_id)

values = {
    "ENTRY_ID": script_id,
    "ENTRY_SAFE_ID": safe_id,
    "ENTRY_LABEL": entry.get("label", ""),
    "ENTRY_GROUP": entry.get("group", ""),
    "ENTRY_RISK": entry.get("risk", ""),
    "ENTRY_CONFIRMATION": entry.get("requiresConfirmation", "") or "",
    "ENTRY_CWD": cwd,
    "ENTRY_COMMAND": command,
    "ENTRY_LOCK_SCOPE": lock_scope,
}

for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
print("ERROR_CODE=0")
PY
}

confirm_if_needed() {
  if [[ -z "${ENTRY_CONFIRMATION}" ]]; then
    return 0
  fi

  if [[ -n "${CONFIRMATION}" ]]; then
    [[ "${CONFIRMATION}" == "${ENTRY_CONFIRMATION}" ]] || die "Falsches Schutzwort für ${ENTRY_ID}."
    return 0
  fi

  if [[ -t 0 ]]; then
    echo ""
    echo "Skript: ${ENTRY_LABEL}"
    echo "Risiko: ${ENTRY_RISK}"
    read -r -p "Zum Fortfahren '${ENTRY_CONFIRMATION}' eingeben: " typed
    [[ "${typed}" == "${ENTRY_CONFIRMATION}" ]] || die "Abgebrochen: Schutzwort stimmt nicht."
    return 0
  fi

  die "Skript braucht Schutzwort. Verwende --confirm SCHUTZWORT."
}

run_script() {
  need_cmd python3
  assert_catalog

  local entry_env
  entry_env="$(load_script_env)"
  eval "${entry_env}"
  if [[ "${ERROR_CODE}" != "0" ]]; then
    die "${ERROR}"
  fi

  confirm_if_needed

  mkdir -p "${LOG_DIR}" "${LOCK_DIR}"

  local lock_file="${LOCK_DIR}/${ENTRY_LOCK_SCOPE}.lock"
  exec 9>"${lock_file}"
  if ! flock -n 9; then
    die "Für '${ENTRY_LOCK_SCOPE}' läuft bereits ein Job."
  fi

  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  local job_id="${stamp}-${ENTRY_SAFE_ID}"
  local log_file="${LOG_DIR}/${job_id}.log"

  echo "Job: ${job_id}"
  echo "Skript: ${ENTRY_ID}"
  echo "Name: ${ENTRY_LABEL}"
  echo "Log: ${log_file}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "Dry-Run: kein Befehl gestartet."
    echo "Ordner: ${ENTRY_CWD}"
    echo "Befehl: ${ENTRY_COMMAND}"
    return 0
  fi

  local exit_code=0
  {
    echo "== Arkons Admin Job =="
    echo "Start: $(date --iso-8601=seconds)"
    echo "Skript-ID: ${ENTRY_ID}"
    echo "Name: ${ENTRY_LABEL}"
    echo "Gruppe: ${ENTRY_GROUP}"
    echo "Risiko: ${ENTRY_RISK}"
    echo "Ordner: ${ENTRY_CWD}"
    echo "Befehl: ${ENTRY_COMMAND}"
    echo ""
    cd "${ENTRY_CWD}"
    bash -lc "${ENTRY_COMMAND}"
  } >"${log_file}" 2>&1 || exit_code=$?

  {
    echo ""
    echo "Ende: $(date --iso-8601=seconds)"
    echo "Exitcode: ${exit_code}"
  } >>"${log_file}"

  if [[ "${exit_code}" == "0" ]]; then
    echo "Fertig: OK"
  else
    echo "Fertig: Fehler ${exit_code}" >&2
    echo "Letzte Logzeilen:" >&2
    tail -n 30 "${log_file}" >&2 || true
    exit "${exit_code}"
  fi
}

main() {
  parse_args "$@"
  need_cmd python3
  assert_catalog

  case "${COMMAND}" in
    list) list_scripts ;;
    show) show_script ;;
    run) run_script ;;
  esac
}

main "$@"
