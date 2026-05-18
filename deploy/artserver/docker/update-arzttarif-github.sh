#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Bitte mit sudo ausführen." >&2
  exit 1
fi

APP_DIR="${ARZTTARIF_APP_DIR:-/opt/apps/Arzttarif}"
DOCKER_DIR="${ARZTTARIF_DOCKER_DIR:-/home/art/arkons/deploy/artserver/docker}"
COMPOSE_FILE="${DOCKER_DIR}/compose.arzttarif.yml"
SMOKE_SCRIPT="${DOCKER_DIR}/smoke-arzttarif.sh"
REPO_URL="${ARZTTARIF_REPO_URL:-https://github.com/BeatArnet/Arzttarif_Assistent_dev.git}"
REPO_BRANCH="${ARZTTARIF_REPO_BRANCH:-main}"
APP_OWNER="${ARZTTARIF_APP_OWNER:-art:art}"
TMP_DIR="$(mktemp -d /tmp/arzttarif-github-update.XXXXXX)"
GITHUB_CREDENTIAL_FILE="${ARZTTARIF_GITHUB_CREDENTIAL_FILE:-/home/art/.config/arkons/github.env}"
GIT_ASKPASS_FILE=""
GIT_AUTH_USER_EFFECTIVE=""
GIT_AUTH_TOKEN_EFFECTIVE=""

cleanup() {
  rm -rf "${TMP_DIR}"
  if [[ -n "${GIT_ASKPASS_FILE}" && -f "${GIT_ASKPASS_FILE}" ]]; then
    rm -f "${GIT_ASKPASS_FILE}"
  fi
}
trap cleanup EXIT

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "Befehl fehlt: ${name}" >&2
    exit 1
  fi
}

log() {
  printf '\n[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$1"
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

find_dotenv_value() {
  local key="$1"
  local file

  for file in \
    "${GITHUB_CREDENTIAL_FILE}" \
    "${APP_DIR}/.env" \
    "/etc/arzttarif/arzttarif.env" \
    "/opt/apps/robowait/apps/api/.env"; do
    local value
    value="$(get_dotenv_value "${file}" "${key}")"
    if [[ -n "${value}" ]]; then
      printf '%s' "${value}"
      return
    fi
  done

  printf '%s' ""
}

find_first_dotenv_value() {
  local key

  for key in "$@"; do
    local value
    value="$(find_dotenv_value "${key}")"
    if [[ -n "${value}" ]]; then
      printf '%s' "${value}"
      return
    fi
  done

  printf '%s' ""
}

setup_git_auth() {
  GIT_AUTH_USER_EFFECTIVE="${ARZTTARIF_GITHUB_USERNAME:-${GITHUB_USERNAME:-${RW_GITHUB_USERNAME:-}}}"
  if [[ -z "${GIT_AUTH_USER_EFFECTIVE}" ]]; then
    GIT_AUTH_USER_EFFECTIVE="$(find_first_dotenv_value ARZTTARIF_GITHUB_USERNAME GITHUB_USERNAME RW_GITHUB_USERNAME)"
  fi

  GIT_AUTH_TOKEN_EFFECTIVE="${ARZTTARIF_GITHUB_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-${RW_GITHUB_TOKEN:-}}}}"
  if [[ -z "${GIT_AUTH_TOKEN_EFFECTIVE}" ]]; then
    GIT_AUTH_TOKEN_EFFECTIVE="$(find_first_dotenv_value ARZTTARIF_GITHUB_TOKEN GITHUB_TOKEN GH_TOKEN RW_GITHUB_TOKEN)"
  fi

  if [[ -n "${GIT_AUTH_USER_EFFECTIVE}" && -n "${GIT_AUTH_TOKEN_EFFECTIVE}" ]]; then
    GIT_ASKPASS_FILE="$(mktemp /tmp/arzttarif-git-askpass-XXXXXX.sh)"
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
    log "Git auth: Zugangsdaten gefunden, nutze nicht-interaktive GitHub-Anmeldung."
  else
    log "Git auth: keine Zugangsdaten gefunden, versuche öffentliche GitHub-Anfrage."
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

sync_app_files() {
  local source_dir="$1"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude ".env" \
      --exclude ".venv/" \
      --exclude "venv/" \
      --exclude "__pycache__/" \
      --exclude ".pytest_cache/" \
      --exclude ".vscode/" \
      --exclude "logs/" \
      --exclude ".docker-cache/" \
      --exclude "config.runtime.ini" \
      --exclude "config.runtime.json" \
      --exclude "feedback_local.json" \
      --exclude "temp_artifacts/" \
      "${source_dir}/" "${APP_DIR}/"
  else
    log "rsync fehlt, synchronisiere ohne Löschung alter Dateien."
    (
      cd "${source_dir}"
      tar \
        --exclude ".env" \
        --exclude ".venv" \
        --exclude "venv" \
        --exclude "__pycache__" \
        --exclude ".pytest_cache" \
        --exclude ".vscode" \
        --exclude "logs" \
        --exclude ".docker-cache" \
        --exclude "config.runtime.ini" \
        --exclude "config.runtime.json" \
        --exclude "feedback_local.json" \
        --exclude "temp_artifacts" \
        -cf - .
    ) | (cd "${APP_DIR}" && tar -xf -)
  fi
}

require_cmd git
require_cmd docker
require_cmd tar

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Compose-Datei fehlt: ${COMPOSE_FILE}" >&2
  exit 1
fi

if [[ ! -f "${SMOKE_SCRIPT}" ]]; then
  echo "Smoke-Test fehlt: ${SMOKE_SCRIPT}" >&2
  exit 1
fi

log "Hole Arzttarif aus GitHub: ${REPO_URL} (${REPO_BRANCH})"
setup_git_auth
if ! git_with_optional_auth ls-remote --heads "${REPO_URL}" "${REPO_BRANCH}" >/dev/null; then
  echo "GitHub-Zugriff fehlgeschlagen: ${REPO_URL} (${REPO_BRANCH})" >&2
  echo "Bei privaten Repositories braucht das Skript GitHub-Zugangsdaten." >&2
  echo "Empfohlen: ${GITHUB_CREDENTIAL_FILE} mit GITHUB_USERNAME und GITHUB_TOKEN." >&2
  exit 1
fi
git_with_optional_auth clone --depth 1 --branch "${REPO_BRANCH}" "${REPO_URL}" "${TMP_DIR}/repo"

log "Synchronisiere App-Dateien nach ${APP_DIR}"
mkdir -p "${APP_DIR}"
sync_app_files "${TMP_DIR}/repo"
mkdir -p "${APP_DIR}/logs" "${APP_DIR}/.docker-cache/huggingface" "${APP_DIR}/.docker-cache/torch"
chown -R "${APP_OWNER}" "${APP_DIR}"

log "Prüfe Python-Abhängigkeiten für das Docker-Image"
REBUILD_IMAGE=0
if [[ -f "${APP_DIR}/requirements.txt" ]]; then
  if [[ ! -f "${DOCKER_DIR}/arzttarif/requirements.txt" ]] || ! cmp -s "${APP_DIR}/requirements.txt" "${DOCKER_DIR}/arzttarif/requirements.txt"; then
    cp "${APP_DIR}/requirements.txt" "${DOCKER_DIR}/arzttarif/requirements.txt"
    REBUILD_IMAGE=1
  fi
fi

if [[ "${REBUILD_IMAGE}" == "1" ]]; then
  log "requirements.txt geändert, baue Arzttarif-Image neu"
  docker compose -f "${COMPOSE_FILE}" build arzttarif
else
  log "requirements.txt unverändert, Image-Neubau nicht nötig"
fi

log "Starte Arzttarif-Container neu"
docker compose -f "${COMPOSE_FILE}" up -d --no-deps arzttarif
docker compose -f "${COMPOSE_FILE}" restart arzttarif

log "Smoke-Test"
bash "${SMOKE_SCRIPT}"

log "Arzttarif GitHub-Update abgeschlossen"
