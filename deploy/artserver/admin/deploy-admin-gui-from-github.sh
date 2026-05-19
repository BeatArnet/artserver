#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${ARKONS_ADMIN_REPO_URL:-https://github.com/BeatArnet/artserver.git}"
BRANCH="${ARKONS_ADMIN_BRANCH:-main}"
APP_ROOT="${ARKONS_ADMIN_ROOT:-/home/art/arkons/deploy/artserver}"
SERVICE_NAME="${ARKONS_ADMIN_SERVICE:-arkons-admin-web}"
SERVICE_PORT="${ARKONS_ADMIN_PORT:-18010}"
SERVICE_HOST="${ARKONS_ADMIN_HOST:-127.0.0.1}"
LAN_IP="${ARKONS_ADMIN_LAN_IP:-192.168.1.136}"
LAN_PORT="${ARKONS_ADMIN_LAN_PORT:-18110}"
LOG_DIR="${ARKONS_ADMIN_WEB_LOG_DIR:-/home/art/arkons/logs/admin/jobs}"
CADDY_SITE="${ARKONS_ADMIN_CADDY_SITE:-/etc/caddy/sites-enabled/arkons-admin-lan.caddy}"
SUDO="${ARKONS_ADMIN_SUDO:-sudo}"
GITHUB_CREDENTIAL_FILE="${ARKONS_ADMIN_GITHUB_CREDENTIAL_FILE:-/home/art/.config/arkons/github.env}"
PRIVILEGED_HELPER="${ARKONS_ADMIN_PRIVILEGED_HELPER:-/usr/local/sbin/arkons-admin-web-apply}"
SUDOERS_FILE="${ARKONS_ADMIN_SUDOERS_FILE:-/etc/sudoers.d/arkons-admin-web}"
GIT_ASKPASS_FILE=""
GIT_AUTH_USER_EFFECTIVE=""
GIT_AUTH_TOKEN_EFFECTIVE=""
TMP_CLONE=""
SKIP_CADDY=0
FORCE=0
INSTALL_SUDO_HELPER=0

cleanup() {
  if [[ -n "${GIT_ASKPASS_FILE}" && -f "${GIT_ASKPASS_FILE}" ]]; then
    rm -f "${GIT_ASKPASS_FILE}"
  fi
  if [[ -n "${TMP_CLONE}" && -d "${TMP_CLONE}" ]]; then
    rm -rf "${TMP_CLONE}"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Arkons Admin Web-GUI aus GitHub deployen

Verwendung:
  deploy-admin-gui-from-github.sh [--branch main] [--skip-caddy] [--force] [--install-sudo-helper]

Standard:
  - holt den aktuellen artserver-Stand aus GitHub
  - richtet arkons-admin-web.service ein
  - aktiviert Autostart bei jedem Serverneustart
  - richtet eine LAN/VPN-Caddy-Route ein: http://192.168.1.136:18110/

Hinweis:
  Der Web-Start kann kein sudo-Passwort eingeben. Einmalig im Terminal mit
  --install-sudo-helper starten, damit ein eng begrenzter root-Helfer installiert wird.

Umgebung:
  ARKONS_ADMIN_REPO_URL       Git-Repository
  ARKONS_ADMIN_ROOT           Zielordner auf artserver
  ARKONS_ADMIN_BRANCH         Branch
  ARKONS_ADMIN_HOST           interner Python-Host, Standard 127.0.0.1
  ARKONS_ADMIN_PORT           interner Python-Port, Standard 18010
  ARKONS_ADMIN_LAN_IP         LAN/VPN-Adresse, Standard 192.168.1.136
  ARKONS_ADMIN_LAN_PORT       LAN/VPN-Port, Standard 18110
  ARKONS_ADMIN_WEB_LOG_DIR    Web-Job-Logs
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      shift
      [[ $# -gt 0 ]] || { echo "--branch braucht einen Wert." >&2; exit 2; }
      BRANCH="$1"
      ;;
    --skip-caddy)
      SKIP_CADDY=1
      ;;
    --force)
      FORCE=1
      ;;
    --install-sudo-helper)
      INSTALL_SUDO_HELPER=1
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "Unbekanntes Argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

log() {
  printf '== %s ==\n' "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Befehl fehlt: $1" >&2; exit 3; }
}

safe_git_name() {
  [[ "$1" =~ ^[A-Za-z0-9._/-]+$ ]]
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

get_dotenv_value() {
  local file="$1"
  local key="$2"

  if [[ ! -f "${file}" ]]; then
    printf '%s' ""
    return
  fi

  local line
  line="$(grep -m1 -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" || true)"
  if [[ -z "${line}" ]]; then
    printf '%s' ""
    return
  fi

  local value="${line#*=}"
  value="$(trim_whitespace "${value}")"

  if [[ "${#value}" -ge 2 ]]; then
    if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi

  printf '%s' "${value}"
}

find_first_credential() {
  local key
  for key in "$@"; do
    local value
    value="$(get_dotenv_value "${GITHUB_CREDENTIAL_FILE}" "${key}")"
    if [[ -n "${value}" ]]; then
      printf '%s' "${value}"
      return
    fi
  done
  printf '%s' ""
}

setup_git_auth() {
  GIT_AUTH_USER_EFFECTIVE="${ARKONS_ADMIN_GITHUB_USERNAME:-${GITHUB_USERNAME:-}}"
  if [[ -z "${GIT_AUTH_USER_EFFECTIVE}" ]]; then
    GIT_AUTH_USER_EFFECTIVE="$(find_first_credential ARKONS_ADMIN_GITHUB_USERNAME GITHUB_USERNAME GH_USERNAME)"
  fi

  GIT_AUTH_TOKEN_EFFECTIVE="${ARKONS_ADMIN_GITHUB_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
  if [[ -z "${GIT_AUTH_TOKEN_EFFECTIVE}" ]]; then
    GIT_AUTH_TOKEN_EFFECTIVE="$(find_first_credential ARKONS_ADMIN_GITHUB_TOKEN GITHUB_TOKEN GH_TOKEN)"
  fi

  if [[ -n "${GIT_AUTH_USER_EFFECTIVE}" && -n "${GIT_AUTH_TOKEN_EFFECTIVE}" ]]; then
    GIT_ASKPASS_FILE="$(mktemp /tmp/arkons-admin-git-askpass-XXXXXX.sh)"
    cat > "${GIT_ASKPASS_FILE}" <<'EOF'
#!/usr/bin/env bash
prompt="$1"
if [[ "${prompt}" == *"Username"* || "${prompt}" == *"username"* ]]; then
  printf '%s\n' "${GIT_AUTH_USER}"
  exit 0
fi
printf '%s\n' "${GIT_AUTH_TOKEN}"
EOF
    chmod 700 "${GIT_ASKPASS_FILE}"
    log "GitHub: Zugangsdaten gefunden, nutze HTTPS-Login."
  else
    log "GitHub: keine Zugangsdaten gefunden, versuche anonymen HTTPS-Zugriff."
    log "Falls das Repository privat ist: ${GITHUB_CREDENTIAL_FILE} mit GITHUB_USERNAME und GITHUB_TOKEN anlegen."
  fi
}

git_with_optional_auth() {
  if [[ -n "${GIT_ASKPASS_FILE}" ]]; then
    GIT_ASKPASS="${GIT_ASKPASS_FILE}" \
      GIT_TERMINAL_PROMPT=0 \
      GIT_AUTH_USER="${GIT_AUTH_USER_EFFECTIVE}" \
      GIT_AUTH_TOKEN="${GIT_AUTH_TOKEN_EFFECTIVE}" \
      git "$@"
  else
    GIT_TERMINAL_PROMPT=0 git "$@"
  fi
}

write_privileged_helper_payload() {
  cat <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/home/art/arkons/deploy/artserver"
SERVICE_NAME="arkons-admin-web"
SERVICE_PORT="18010"
SERVICE_HOST="127.0.0.1"
LAN_IP="192.168.1.136"
LAN_PORT="18110"
LOG_DIR="/home/art/arkons/logs/admin/jobs"
CADDY_SITE="/etc/caddy/sites-enabled/arkons-admin-lan.caddy"
SKIP_CADDY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-caddy)
      SKIP_CADDY=1
      ;;
    -h|--help|help)
      echo "Verwendung: arkons-admin-web-apply [--skip-caddy]"
      exit 0
      ;;
    *)
      echo "Unbekanntes Argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

log() {
  printf '== %s ==\n' "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Befehl fehlt: $1" >&2; exit 3; }
}

need_cmd python3
need_cmd systemctl
need_cmd curl
need_cmd ss
need_cmd fuser

log "Log-Ordner vorbereiten"
install -d -m 0755 -o art -g art "$LOG_DIR"

log "systemd-Service installieren"
service_file="$(mktemp)"
caddy_tmp=""
cleanup() {
  rm -f "$service_file"
  if [[ -n "${caddy_tmp}" ]]; then
    rm -f "$caddy_tmp"
  fi
}
trap cleanup EXIT

cat > "$service_file" <<UNIT
[Unit]
Description=Arkons Admin Web-GUI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=art
Group=art
WorkingDirectory=$APP_ROOT
Environment=PYTHONUNBUFFERED=1
Environment=ARKONS_ADMIN_WEB_LOG_DIR=$LOG_DIR
ExecStart=$(command -v python3) $APP_ROOT/admin-gui/app.py --host $SERVICE_HOST --port $SERVICE_PORT --job-log-dir $LOG_DIR
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

install -m 0644 "$service_file" "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
if ss -ltn "sport = :${SERVICE_PORT}" | grep -q ":${SERVICE_PORT}"; then
  echo "Port ${SERVICE_PORT} ist noch belegt; alter Admin-Web-Prozess wird beendet."
  fuser -k "${SERVICE_PORT}/tcp" >/dev/null 2>&1 || true
  sleep 1
fi
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
systemctl is-active --quiet "$SERVICE_NAME"

log "Interner HTTP-Test"
curl -fsS "http://${SERVICE_HOST}:${SERVICE_PORT}/" >/dev/null

if [[ "$SKIP_CADDY" != "1" ]]; then
  log "Interne LAN/VPN-Caddy-Route installieren"
  need_cmd caddy
  install -d -m 0755 "$(dirname "$CADDY_SITE")" /etc/caddy/backups
  if [[ -f "$CADDY_SITE" ]]; then
    cp -a "$CADDY_SITE" "/etc/caddy/backups/$(basename "$CADDY_SITE").$(date +%Y%m%d-%H%M%S)"
  fi

  caddy_tmp="$(mktemp)"
  cat > "$caddy_tmp" <<CADDY
# arkons-managed: Admin-GUI nur im LAN/VPN.
# Kein oeffentlicher Domain-Name, kein offener Internet-Zugang.

http://${LAN_IP}:${LAN_PORT} {
	bind ${LAN_IP}
	encode zstd gzip
	reverse_proxy ${SERVICE_HOST}:${SERVICE_PORT}
}
CADDY

  install -m 0644 "$caddy_tmp" "$CADDY_SITE"

  if ! grep -Eq 'sites-enabled/.+\.caddy|sites-enabled/\*\.caddy' /etc/caddy/Caddyfile; then
    echo "Warnung: /etc/caddy/Caddyfile scheint /etc/caddy/sites-enabled/*.caddy nicht zu importieren." >&2
    echo "Die Datei wurde geschrieben, Caddy koennte sie aber ignorieren: $CADDY_SITE" >&2
  fi

  caddy validate --config /etc/caddy/Caddyfile
  systemctl reload caddy
  systemctl is-active --quiet caddy
fi

log "Status"
systemctl --no-pager --full status "$SERVICE_NAME" | sed -n '1,18p'
echo ""
echo "Intern auf artserver: http://${SERVICE_HOST}:${SERVICE_PORT}/"
if [[ "$SKIP_CADDY" != "1" ]]; then
  echo "LAN/VPN: http://${LAN_IP}:${LAN_PORT}/"
fi
HELPER
}

install_sudo_helper() {
  log "sudo-Helfer installieren"
  helper_tmp="$(mktemp)"
  sudoers_tmp="$(mktemp)"
  write_privileged_helper_payload > "$helper_tmp"
  cat > "$sudoers_tmp" <<EOF
# arkons-managed: erlaubt art nur den festen Admin-Web-Helfer ohne Passwort.
art ALL=(root) NOPASSWD: ${PRIVILEGED_HELPER}
EOF

  ${SUDO} install -m 0755 -o root -g root "$helper_tmp" "$PRIVILEGED_HELPER"
  ${SUDO} visudo -cf "$sudoers_tmp" >/dev/null
  ${SUDO} install -m 0440 -o root -g root "$sudoers_tmp" "$SUDOERS_FILE"
  ${SUDO} visudo -cf "$SUDOERS_FILE" >/dev/null
  rm -f "$helper_tmp" "$sudoers_tmp"
  echo "sudo-Helfer installiert: $PRIVILEGED_HELPER"
  echo "sudo-Regel installiert: $SUDOERS_FILE"
}

run_privileged_apply() {
  if [[ ! -x "$PRIVILEGED_HELPER" ]]; then
    echo "Der sudo-Helfer fehlt noch: $PRIVILEGED_HELPER" >&2
    echo "Einmalig im PowerShell-Terminal ausführen:" >&2
    echo "  .\\publish-admin-gui.cmd -CommitMessage \"Admin-GUI sudo-Helfer installieren\" -InstallSudoHelper" >&2
    exit 5
  fi

  if ! ${SUDO} "$PRIVILEGED_HELPER" "$@"; then
    echo "" >&2
    echo "Privilegierter Admin-Web-Schritt fehlgeschlagen." >&2
    if [[ "$SUDO" == *"-n"* ]]; then
      echo "Der Web-Start kann kein sudo-Passwort eingeben." >&2
      echo "Einmalig im PowerShell-Terminal ausführen:" >&2
      echo "  .\\publish-admin-gui.cmd -CommitMessage \"Admin-GUI sudo-Helfer installieren\" -InstallSudoHelper" >&2
    fi
    exit 6
  fi
}

need_cmd git
need_cmd python3
need_cmd "${SUDO%% *}"
need_cmd curl

safe_git_name "$BRANCH" || { echo "Unsicherer Branch-Name: $BRANCH" >&2; exit 2; }
setup_git_auth

if [[ "$INSTALL_SUDO_HELPER" == "1" && "$SUDO" == *"-n"* ]]; then
  echo "--install-sudo-helper braucht ein Terminal, weil dabei einmalig sudo nach dem Passwort fragen muss." >&2
  exit 2
fi

log "Git-Checkout aktualisieren"
if [[ -d "$APP_ROOT/.git" ]]; then
  cd "$APP_ROOT"
  if [[ -n "$(git status --porcelain)" && "$FORCE" != "1" ]]; then
    echo "Der Zielordner hat lokale Aenderungen: $APP_ROOT" >&2
    echo "Bitte zuerst pruefen oder mit --force bewusst ueberschreiben." >&2
    exit 4
  fi
  git remote set-url origin "$REPO_URL"
  git_with_optional_auth fetch origin "$BRANCH"
  if [[ "$FORCE" == "1" ]]; then
    git checkout "$BRANCH"
    git reset --hard "origin/$BRANCH"
  else
    git checkout "$BRANCH"
    git_with_optional_auth pull --ff-only origin "$BRANCH"
  fi
else
  TMP_CLONE="$(mktemp -d /tmp/arkons-admin-git.XXXXXX)"
  git_with_optional_auth clone --branch "$BRANCH" "$REPO_URL" "$TMP_CLONE"
  python3 -m py_compile "${TMP_CLONE}/admin-gui/app.py"

  if [[ -e "$APP_ROOT" ]]; then
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup="${APP_ROOT}.before-admin-git.${stamp}"
    echo "Zielordner ist noch kein Git-Checkout. Verschiebe ihn als Sicherheitskopie:"
    echo "  $backup"
    mv "$APP_ROOT" "$backup"
  fi
  mkdir -p "$(dirname "$APP_ROOT")"
  mv "$TMP_CLONE" "$APP_ROOT"
  TMP_CLONE=""
  cd "$APP_ROOT"
fi

log "Python pruefen"
python3 -m py_compile admin-gui/app.py

log "Log-Ordner vorbereiten"
mkdir -p "$LOG_DIR"

if [[ "$INSTALL_SUDO_HELPER" == "1" ]]; then
  install_sudo_helper
fi

privileged_args=()
if [[ "$SKIP_CADDY" == "1" ]]; then
  privileged_args+=(--skip-caddy)
fi

run_privileged_apply "${privileged_args[@]}"
