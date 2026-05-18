#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Bitte mit sudo ausfuehren: sudo bash $0" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/home/art/artserver-hub/script-cleanup-${STAMP}.txt"

mkdir -p /home/art/artserver-hub

log() {
  printf "%s\n" "$*" | tee -a "$REPORT"
}

archive_file() {
  local source="$1"
  local target_dir="$2"
  local reason="$3"

  if [[ -e "$source" ]]; then
    mkdir -p "$target_dir"
    log "ARCHIVIERE: $source"
    log "  Grund: $reason"
    mv "$source" "$target_dir/"
  else
    log "FEHLT BEREITS: $source"
  fi
}

archive_dir_contents() {
  local source_dir="$1"
  local target_dir="$2"
  local reason="$3"

  if [[ ! -d "$source_dir" ]]; then
    log "FEHLT BEREITS: $source_dir"
    return
  fi

  mkdir -p "$target_dir"

  shopt -s dotglob nullglob
  local items=("$source_dir"/*)
  if (( ${#items[@]} == 0 )); then
    log "LEER: $source_dir"
  else
    log "ARCHIVIERE INHALT: $source_dir"
    log "  Ziel: $target_dir"
    log "  Grund: $reason"
    mv "${items[@]}" "$target_dir/"
  fi
  shopt -u dotglob nullglob

  mkdir -p "$source_dir"
}

log "artserver Skriptordnung - ${STAMP}"
log ""
log "Diese Aktion loescht nichts. Dateien werden nur in Archive verschoben."
log ""

SCRIPT_ARCHIVE="/home/art/scripts/archive/${STAMP}-script-cleanup"
ROBOWAIT_ARCHIVE="/opt/apps/robowait/archive/${STAMP}-script-cleanup"

mkdir -p "$SCRIPT_ARCHIVE" "$ROBOWAIT_ARCHIVE"

archive_file \
  "/home/art/scripts/install-artserver.sh" \
  "$SCRIPT_ARCHIVE" \
  "Historischer RoboWait-Beispielinstaller mit Beispiel-Repo-URL; produktive RoboWait-Wartung liegt unter /opt/apps/robowait/scripts."

archive_dir_contents \
  "/opt/apps/robowait/.tmp" \
  "$ROBOWAIT_ARCHIVE/tmp" \
  "Alte Diagnose-, Deploy- und Logartefakte aus frueheren RoboWait-Arbeiten; keine systemd-Referenzen."

archive_dir_contents \
  "/opt/apps/robowait/.tmp-deploy" \
  "$ROBOWAIT_ARCHIVE/tmp-deploy" \
  "Alte temporaere Deploy-Artefakte; keine systemd-Referenzen."

cat > "$SCRIPT_ARCHIVE/README.txt" <<README
Archiviert am ${STAMP} durch organize-artserver-scripts.sh.

install-artserver.sh war ein historischer RoboWait-Beispielinstaller mit Beispiel-Repo-URL.
Produktive RoboWait-Wartung liegt unter /opt/apps/robowait/scripts/.
README

cat > "$ROBOWAIT_ARCHIVE/README.txt" <<README
Archiviert am ${STAMP} durch organize-artserver-scripts.sh.

Inhalt:
- alte Dateien aus /opt/apps/robowait/.tmp
- alte Dateien aus /opt/apps/robowait/.tmp-deploy

Produktive RoboWait-Skripte unter /opt/apps/robowait/scripts bleiben unveraendert.
README

log ""
log "Aktive wichtige Skripte bleiben an ihrem Ort:"
log "- /home/art/scripts/update_artserver.sh"
log "- /home/art/scripts/borg-restore-guided.sh"
log "- /home/art/scripts/artserver_setup.sh"
log "- /home/art/arkons/deploy/apply-arkons-preview.sh"
log "- /home/art/arkons/deploy/artserver/docker/*.sh"
log "- /opt/apps/Menueplan/ops/*.sh"
log "- /opt/apps/robowait/scripts/*.sh"
log ""
log "Archivorte:"
log "- $SCRIPT_ARCHIVE"
log "- $ROBOWAIT_ARCHIVE"
log ""
log "Fertig. Bericht: $REPORT"
