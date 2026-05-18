#!/usr/bin/env bash
set -euo pipefail

WEB_CURRENT="/home/art/arkons/www/current"
CADDY_SITE="/etc/caddy/sites-enabled/arkons-preview.caddy"
BACKUP_DIR="/etc/caddy/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ $EUID -ne 0 ]]; then
  echo "Bitte mit sudo ausfuehren: sudo bash $0" >&2
  exit 1
fi

if [[ ! -f "$WEB_CURRENT/index.html" ]]; then
  echo "Webseite nicht gefunden: $WEB_CURRENT/index.html" >&2
  exit 1
fi

install -d -m 755 "$BACKUP_DIR"

if [[ -f /etc/caddy/Caddyfile ]]; then
  cp -a /etc/caddy/Caddyfile "$BACKUP_DIR/Caddyfile.$STAMP"
fi

if [[ -f "$CADDY_SITE" ]]; then
  cp -a "$CADDY_SITE" "$BACKUP_DIR/arkons-preview.caddy.$STAMP"
fi

cat > "$CADDY_SITE" <<'CADDY'
# arkons-managed: static website preview before DNS cutover.
# Safe preview URLs:
# - http://artserver:8088/
# - http://192.168.1.136/
# - http://arkons.ch/ with a local hosts/DNS override to artserver
#
# This intentionally does not configure HTTPS for arkons.ch yet, because
# public DNS still points to Localsearch and ACME validation would fail.

:8088 {
	encode zstd gzip
	root * /home/art/arkons/www/current
	file_server
}

http://arkons.ch, http://www.arkons.ch {
	encode zstd gzip
	root * /home/art/arkons/www/current
	file_server
}

http://192.168.1.136 {
	encode zstd gzip
	root * /home/art/arkons/www/current
	file_server
}
CADDY

caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
systemctl is-active --quiet caddy

echo "Arkons preview enabled."
echo "Preview: http://artserver:8088/"
