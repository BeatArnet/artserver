# Docker-Prototypen für artserver

Diese Dateien bereiten die schrittweise Containerisierung einzelner Apps vor. Caddy bleibt dabei als Host-Dienst aktiv und wird nicht in Docker verschoben.

## Grundprinzip

- Caddy bleibt die einzige öffentliche HTTP-/TLS-Schicht.
- Container binden nur an `127.0.0.1`.
- Bestehende systemd-Dienste werden für Prototypen nicht deaktiviert.
- `.env`-Dateien bleiben auf dem Server und werden nicht ins Repo kopiert.

## Arzttarif parallel testen

Voraussetzungen auf `artserver`:

- Docker Engine
- Docker Compose Plugin
- bestehende App unter `/opt/apps/Arzttarif`
- bestehende Env-Datei unter `/etc/arzttarif/arzttarif.env`

Docker installieren, falls noch nicht vorhanden:

```bash
cd /home/art/arkons/deploy/artserver/docker
sudo bash install-docker-engine.sh
```

Auf `artserver`:

```bash
cd /home/art/arkons/deploy/artserver/docker
sudo docker compose -f compose.arzttarif.yml build
mkdir -p /opt/apps/Arzttarif/.docker-cache/huggingface /opt/apps/Arzttarif/.docker-cache/torch
sudo docker compose -f compose.arzttarif.yml up -d
sudo docker compose -f compose.arzttarif.yml ps
bash smoke-arzttarif.sh
```

`sudo` ist hier bewusst vorgesehen, weil `/etc/arzttarif/arzttarif.env` auf dem Server nur für `root:arzttarif` lesbar ist.

Der Containername in Docker/Portainer ist:

```text
Arzttarif
```

Der Container läuft parallel zum aktuellen Host-Dienst auf:

```text
http://127.0.0.1:18000/api/version
```

Wichtig: Diese Adresse gilt auf `artserver` selbst. Im Browser auf dem Laptop zeigt `127.0.0.1` auf den Laptop, nicht auf `artserver`.

Wenn beim SSH-Tunnel Meldungen wie `connect failed: Connection refused` erscheinen, funktioniert der Tunnel zwar, aber auf `artserver` läuft noch kein Dienst auf Port `18000`. Dann zuerst den Compose-Prototyp starten.

Zum Testen im Browser auf dem Laptop entweder einen SSH-Tunnel öffnen:

```powershell
ssh -L 18000:127.0.0.1:18000 art@artserver
```

und dann lokal öffnen:

```text
http://127.0.0.1:18000/
```

oder direkt auf `artserver` prüfen:

```bash
curl -fsS http://127.0.0.1:18000/api/version
```

Hinweis zum ersten Start: Arzttarif nutzt bei aktiviertem RAG lokal `sentence-transformers/paraphrase-multilingual-mpnet-base-v2`. Beim ersten Containerstart wird der Modellcache unter `/opt/apps/Arzttarif/.docker-cache` aufgebaut. Das kann auf dem Notebook lange dauern und mehrere GiB belegen. Nach gefülltem Cache startet die App deutlich schneller.

Der produktive Host-Dienst bleibt währenddessen auf:

```text
http://127.0.0.1:8000/api/version
```

Aktueller Betriebsstand seit 2026-05-14:

- Caddy routet Arzttarif auf den Docker-Port `127.0.0.1:18000`.
- Der alte Host-Dienst `arzttarif.service` kann nach erfolgreichem operativem Test entfernt werden.
- Der App-Ordner `/opt/apps/Arzttarif` bleibt weiterhin produktiv: Der Container mountet daraus Code, Daten, Logs und Docker-Cache.
- Der öffentliche Test über `https://arnet.internet-box.ch:4444/api/version` ist erfolgreich.

## Arzttarif aus GitHub aktualisieren

`/opt/apps/Arzttarif` ist aktuell kein Git-Checkout. Deshalb kann man dort nicht einfach `git pull` ausführen. Das Update-Skript klont den neuesten GitHub-Stand in ein temporäres Verzeichnis und synchronisiert ihn danach kontrolliert nach `/opt/apps/Arzttarif`.

```bash
cd /home/art/arkons/deploy/artserver/docker
sudo bash update-arzttarif-github.sh
```

Bei privaten GitHub-Repositories braucht das Skript Zugangsdaten. Es sucht zuerst Umgebungsvariablen und danach diese Dateien:

- `/home/art/.config/arkons/github.env`
- `/opt/apps/Arzttarif/.env`
- `/etc/arzttarif/arzttarif.env`

Empfohlen ist die zentrale Datei:

```bash
sudo mkdir -p /home/art/.config/arkons
sudo nano /home/art/.config/arkons/github.env
sudo chmod 600 /home/art/.config/arkons/github.env
```

Inhalt:

```text
GITHUB_USERNAME=dein-github-benutzername
GITHUB_TOKEN=dein-github-token
```

Das Skript lässt Laufzeitdaten bewusst stehen:

- `/etc/arzttarif/arzttarif.env`
- `/opt/apps/Arzttarif/logs`
- `/opt/apps/Arzttarif/.docker-cache`
- lokale Runtime-Dateien wie `feedback_local.json`

Wenn `requirements.txt` geändert wurde, baut es das Arzttarif-Image neu. Danach startet es den Container neu und führt `smoke-arzttarif.sh` aus.

Logs:

```bash
sudo docker compose -f compose.arzttarif.yml logs -f arzttarif
```

Stoppen:

```bash
sudo docker compose -f compose.arzttarif.yml down
```

## Arzttarif testweise auf Docker routen

Wenn der Docker-Prototyp stabil läuft, kann Caddy für Arzttarif auf den Docker-Port `18000` umgestellt werden. Der alte Host-Dienst bleibt dabei zuerst aktiv.

Status:

```bash
cd /home/art/arkons/deploy/artserver/docker
bash switch-arzttarif-caddy.sh status
```

Switch auf Docker:

```bash
cd /home/art/arkons/deploy/artserver/docker
sudo bash switch-arzttarif-caddy.sh docker
```

Rollback auf den bisherigen Host-Dienst:

```bash
cd /home/art/arkons/deploy/artserver/docker
sudo bash switch-arzttarif-caddy.sh host
```

Wenn die Website nach dem Switch erfolgreich getestet wurde, den alten Host-Dienst nur stoppen, nicht löschen:

```bash
sudo bash arzttarif-host-service.sh stop
```

Rollback nach gestopptem Host-Dienst:

```bash
sudo bash arzttarif-host-service.sh start
sudo bash switch-arzttarif-caddy.sh host
```

## Spätere Umschaltung

Erst wenn der parallele Test stabil ist:

1. Backup/Status prüfen.
2. Container auf den Zielport legen oder Caddy auf den Container-Testport zeigen lassen.
3. `caddy validate --config /etc/caddy/Caddyfile` ausführen.
4. Caddy reloaden.
5. Alten systemd-Dienst erst danach deaktivieren.

Rollback bleibt einfach: Caddy wieder auf `127.0.0.1:8000` zeigen lassen und `arzttarif.service` starten.

## Alte Host-Installation bereinigen

Erst ausführen, wenn der Arzttarif-Assistent über die öffentliche Adresse stabil getestet wurde.

```bash
cd /home/art/arkons/deploy/artserver/docker
sudo bash cleanup-arzttarif-host-installation.sh
```

Das Skript prüft zuerst:

- Docker-Arzttarif antwortet auf `127.0.0.1:18000`.
- Caddy zeigt nicht mehr auf den alten Host-Port `8000`.
- Der öffentliche Caddy-Zugriff auf den Arzttarif-Assistenten antwortet.

Danach entfernt es:

- den alten systemd-Dienst `arzttarif.service`,
- den alten Dependency-Update-Timer `arzttarif-deps-update.timer`,
- die alte Python-Umgebung `/opt/apps/Arzttarif/.venv`,
- Python-Zwischencaches wie `__pycache__`,
- alte Migrationsskripte aus `/home/art/scripts` in ein Archiv.

Es lässt bewusst stehen:

- `/opt/apps/Arzttarif` als produktiver App- und Datenordner,
- `/opt/apps/Arzttarif/.docker-cache`,
- `/opt/apps/Arzttarif/logs`,
- `/etc/arzttarif/arzttarif.env`,
- den Docker-Container und die Caddy-Route auf `18000`.

## Menüplan parallel testen

Der Menüplan ist die täglich genutzte Koch-App. Deshalb wird er zuerst parallel gestartet und erst nach einem erfolgreichen Test in Caddy umgeschaltet.

Zielbild:

- Arzttarif Docker: `127.0.0.1:18000`
- Menüplan Docker: `127.0.0.1:18001`
- Host-Caddy bleibt die öffentliche HTTPS-Schicht.
- Der alte PHP-FPM-Socket `/run/php/menuplan.sock` bleibt zuerst als Rollback erhalten.

## Einmalige Umbenennung vorhandener Container

Die Compose-Dateien verwenden klare Container-Namen:

```text
Arzttarif
Menueplan
```

Wenn auf `artserver` noch die alten Namen laufen, können sie ohne Neustart umbenannt werden:

```bash
sudo docker rename arzttarif-docker-preview Arzttarif
sudo docker rename menueplan-docker-preview Menueplan
```

Danach Portainer im Browser aktualisieren.

Auf `artserver`:

```bash
cd /home/art/arkons/deploy/artserver/docker
sudo docker compose -f compose.menueplan.yml build
sudo docker compose -f compose.menueplan.yml up -d
sudo docker compose -f compose.menueplan.yml ps
bash smoke-menueplan.sh
```

Der Containername in Docker/Portainer ist:

```text
Menueplan
```

Der Container verwendet:

- Code: `/opt/apps/Menueplan` read-only nach `/app`
- Daten: `/opt/apps/Menueplan/data` beschreibbar nach `/app/data`
- Container-User: standardmässig UID/GID `33:33`, passend zu `www-data:www-data`
- interner Port: `127.0.0.1:18001`

Direkter Test auf `artserver`:

```bash
curl -fsS http://127.0.0.1:18001/api.php?type=status
```

Test vom Laptop per SSH-Tunnel:

```powershell
ssh -L 18001:127.0.0.1:18001 art@artserver
```

Dann im Browser:

```text
http://127.0.0.1:18001/
```

## Menüplan testweise auf Docker routen

Erst ausführen, wenn der parallele Test erfolgreich war und ein Backup vorhanden ist:

```bash
cd /home/art/arkons/deploy/artserver/docker
sudo bash switch-menueplan-caddy.sh status
sudo bash switch-menueplan-caddy.sh docker
```

Danach öffentlich testen:

```bash
curl -kI --max-time 12 https://arnet.internet-box.ch:4443/
```

Rollback auf den alten Host-Betrieb:

```bash
cd /home/art/arkons/deploy/artserver/docker
sudo bash switch-menueplan-caddy.sh host
```

Der Container kann danach gestoppt werden:

```bash
sudo docker compose -f compose.menueplan.yml down
```

Wichtig: Den alten PHP-FPM-Pool erst deaktivieren oder entfernen, wenn der Menüplan über mehrere Kochzyklen stabil im Container gelaufen ist.

## Alte Menüplan-Host-Installation aufräumen

Erst ausführen, wenn der Menüplan im Container stabil läuft und die öffentliche Adresse getestet wurde:

```bash
cd /home/art/arkons/deploy/artserver/docker
sudo bash cleanup-menueplan-host-installation.sh
```

Das Skript prüft zuerst:

- Docker-Menüplan antwortet auf `127.0.0.1:18001`.
- Die öffentliche Adresse `https://arnet.internet-box.ch:4443/` antwortet.
- Caddy zeigt bereits auf `reverse_proxy 127.0.0.1:18001`.

Danach erledigt es:

- Backup der relevanten Host-Konfiguration unter `/etc/caddy/backups/menueplan-host-cleanup.<Zeitstempel>/`.
- zusätzliches Menüplan-Datenbackup über `/opt/apps/Menueplan/ops/backup.sh`.
- `menuplan-stack.service` deaktivieren.
- den alten PHP-FPM-Pool `/etc/php/8.3/fpm/pool.d/menuplan.conf` aus der aktiven Pool-Konfiguration entfernen und ins Backup verschieben.
- `menuplan-backup.service` vom alten Stack entkoppeln, damit Backups nicht mehr unnötig PHP-FPM starten.

Vorsichtiger Standard: `php8.3-fpm.service` bleibt installiert und aktiviert. Wenn später klar ist, dass keine andere App PHP-FPM braucht, kann man ihn ausdrücklich mit deaktivieren:

```bash
sudo bash cleanup-menueplan-host-installation.sh --disable-php-fpm
```

## RoboWait parallel testen

RoboWait besteht aus drei laufenden Teilen:

- Web: bisher `robowait-web.service` auf Port `4445`
- Reverb/WebSocket: bisher `robowait-reverb.service` auf Port `4446`
- Scheduler: bisher `robowait-scheduler.service`

Der Docker-Prototyp startet deshalb ebenfalls drei Dienste. Damit der aktuelle Host-Betrieb parallel weiterlaufen kann, nutzt Docker zuerst andere Host-Ports:

```text
RoboWait Host-Web:      127.0.0.1:4445
RoboWait Host-Reverb:   127.0.0.1:4446
RoboWait Docker-Web:    127.0.0.1:18002
RoboWait Docker-Reverb: 127.0.0.1:18003
```

Auf `artserver`:

```bash
cd /opt/apps/robowait
sudo docker compose -f deploy/docker-compose.yml build
sudo docker compose -f deploy/docker-compose.yml up -d
sudo docker compose -f deploy/docker-compose.yml ps
bash scripts/smoke-docker.sh
```

Der Container verwendet:

- Code: aus `/opt/apps/robowait`, ins Image gebaut
- `.env`: bleibt auf dem Server unter `/opt/apps/robowait/apps/api/.env`
- Datenbank: `/opt/apps/robowait/apps/api/database`
- Storage: `/opt/apps/robowait/apps/api/storage`
- Laravel Cache: `/opt/apps/robowait/apps/api/bootstrap/cache`
- Container-User: standardmässig UID/GID `994:986`, passend zu `robowait:robowait` auf artserver

## RoboWait testweise auf Docker routen

Erst ausführen, wenn der parallele Docker-Smoke-Test erfolgreich war:

```bash
cd /home/art/arkons/deploy/artserver/docker
sudo bash switch-robowait-caddy.sh status
sudo bash switch-robowait-caddy.sh docker
```

Rollback auf den bisherigen Host-Betrieb:

```bash
cd /home/art/arkons/deploy/artserver/docker
sudo bash switch-robowait-caddy.sh host
```

## Alte RoboWait-Host-Dienste aufräumen

Erst ausführen, wenn RoboWait über die öffentliche Adresse stabil im Container läuft:

```bash
cd /home/art/arkons/deploy/artserver/docker
sudo bash cleanup-robowait-host-installation.sh
```

Das Skript prüft zuerst:

- Docker-Web antwortet auf `127.0.0.1:18002`.
- Docker-Reverb ist auf `127.0.0.1:18003` erreichbar.
- Die öffentliche Adresse `https://robowait.arkons.ch/` antwortet.
- Caddy zeigt bereits auf die Docker-Ports.

Danach deaktiviert und archiviert es nur die alten systemd-Dienste `robowait-web.service`, `robowait-reverb.service` und `robowait-scheduler.service`. Der App-Ordner `/opt/apps/robowait` bleibt bestehen, weil Docker daraus weiterhin Datenbank, Storage, `.env` und Git-Stand nutzt.
