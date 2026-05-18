#!/usr/bin/env bash
set -euo pipefail

PORTAINER_IMAGE="${PORTAINER_IMAGE:-portainer/portainer-ce:lts}"
PORTAINER_NAME="${PORTAINER_NAME:-portainer}"
PORTAINER_VOLUME="${PORTAINER_VOLUME:-portainer_data}"
PORTAINER_PORT="${PORTAINER_PORT:-9443}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Fehlendes Kommando: $1" >&2
    exit 1
  }
}

need_cmd docker

echo "Portainer CE Installation/Aktualisierung"
echo "Image:  $PORTAINER_IMAGE"
echo "Name:   $PORTAINER_NAME"
echo "Volume: $PORTAINER_VOLUME"
echo "Port:   $PORTAINER_PORT"
echo

sudo docker volume create "$PORTAINER_VOLUME"
sudo docker pull "$PORTAINER_IMAGE"

if sudo docker ps -a --format '{{.Names}}' | grep -Fxq "$PORTAINER_NAME"; then
  echo "Bestehender Container wird ersetzt, Daten bleiben im Volume $PORTAINER_VOLUME."
  sudo docker rm -f "$PORTAINER_NAME"
fi

sudo docker run -d \
  -p "${PORTAINER_PORT}:9443" \
  --name "$PORTAINER_NAME" \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "${PORTAINER_VOLUME}:/data" \
  "$PORTAINER_IMAGE"

echo
sudo docker ps --filter "name=$PORTAINER_NAME"
echo
echo "Portainer ist erreichbar unter: https://192.168.1.136:${PORTAINER_PORT}/"
