# artserver Neuinstallation Checkliste

Stand: 2026-05-15

Diese Liste ist für einen späteren Neuaufbau von `artserver`. Sie ist bewusst breit, damit neu hinzugefügte Bausteine wie Docker, Portainer und Caddy nicht vergessen gehen.

## Grundsystem

- Ubuntu installieren und aktualisieren.
- Hostname auf `artserver` setzen.
- Benutzer `art` einrichten.
- SSH-Zugang prüfen.
- Feste LAN-Adresse oder DHCP-Reservierung prüfen, aktuell:

```text
192.168.1.136
```

- Zeitzone setzen:

```text
Europe/Zurich
```

## Basisdienste

Aufnehmen:

- SSH
- UFW oder anderes Firewall-Konzept
- systemd-timesyncd oder anderer Zeitdienst
- unattended-upgrades, falls weiter gewünscht
- BorgBackup und Restore-Skript
- Samba/NAS-Mounts, falls weiterhin verwendet
- Cockpit, falls weiterhin verwendet

Vorhandenes allgemeines Setup-Skript:

```text
/home/art/scripts/artserver_setup.sh
```

Dieses Skript vor einer echten Neuinstallation zuerst prüfen. Es ist stark und verändert Systemkonfiguration.

## Webserver und Routing

Caddy muss wieder eingerichtet werden.

Wichtige Orte:

```text
/etc/caddy/Caddyfile
/etc/caddy/sites-enabled/
/etc/caddy/backups/
```

Wichtige Aufgaben:

- Caddy installieren.
- Caddy-Service aktivieren.
- Bestehende Site-Dateien wiederherstellen oder neu erzeugen.
- `caddy validate --config /etc/caddy/Caddyfile` ausführen.
- Caddy reloaden.

Für die Website `arkons.ch` bleiben die Serverpfade absichtlich unter:

```text
/home/art/arkons
```

## Docker

Docker gehört inzwischen zur Standardinstallation von `artserver`.

Wichtige Bestandteile:

- Docker Engine
- Docker Compose Plugin
- Docker-Dienst aktiv und laufend

Installationsskript im Repository:

```text
deploy/artserver/docker/install-docker-engine.sh
```

Nach Installation prüfen:

```bash
docker --version
docker compose version
sudo docker ps
```

## Portainer

Portainer ist die Docker-Weboberfläche und soll bei einem Neuaufbau ebenfalls wieder eingerichtet werden.

Installationsskript im Repository:

```text
deploy/artserver/docker/install-portainer-ce.sh
```

Standard:

- Containername: `portainer`
- Image: `portainer/portainer-ce:lts`
- Volume: `portainer_data`
- Webzugang: `https://192.168.1.136:9443/`

Wichtig: Wenn es ein Backup des Docker-Volumes `portainer_data` gibt, zuerst überlegen, ob dieses wiederhergestellt werden soll. Sonst wird Portainer frisch eingerichtet und der Admin-Benutzer neu angelegt.

## Anwendungen

Aktuelle Anwendungen:

- Website `arkons.ch`: `/home/art/arkons`
- Menueplan: `/opt/apps/Menueplan`
- RoboWait: `/opt/apps/robowait`
- Arzttarif: `/opt/apps/Arzttarif`

Bei jeder Anwendung klären:

- Wo liegt der Code?
- Wo liegen produktive Daten?
- Wo liegen `.env`-Dateien oder andere Geheimnisse?
- Gibt es systemd-Units?
- Gibt es Docker Compose Dateien?
- Gibt es Backups?

## Systemd

Lokale Unit-Dateien prüfen:

```text
/etc/systemd/system
```

Bekannte Dienste:

- `caddy`
- `php8.3-fpm`
- `menuplan-stack`
- `menuplan-backup.timer`
- `robowait-web`
- `robowait-reverb`
- `robowait-scheduler`
- `arzttarif`

Bei Docker-Migrationen können einige alte Host-Dienste später wegfallen. Darum vor einer Neuinstallation den aktuellen Stand aus `/home/art/artserver-hub/git-status.txt` und den Inventarlisten prüfen.

## artserver-hub

Nach dem Grundsetup wieder anlegen:

```powershell
.\artserver-admin.ps1 -Run 19
```

Dadurch entsteht:

```text
/home/art/artserver-hub
```

Diese Zentrale enthält Verweise und Inventarlisten, aber keine produktiven App-Daten.

## Reihenfolge nach Neuinstallation

1. Grundsystem und Netzwerk.
2. SSH-Zugriff.
3. Caddy installieren.
4. Docker und Docker Compose installieren.
5. Portainer installieren.
6. Projektverzeichnisse und Daten wiederherstellen.
7. `.env`-Dateien und Rechte prüfen.
8. systemd-Units wiederherstellen oder Docker-Compose-Stacks starten.
9. Caddy validieren und reloaden.
10. Admin-Menü Status prüfen.
11. artserver-hub aktualisieren.
12. Backups und Restore testen.

