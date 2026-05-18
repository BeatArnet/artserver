# Docker-Migrationsvorbereitung artserver

Stand: 2026-05-14

Zielbild: Caddy bleibt als Host-Dienst auf `artserver` und reverse-proxied Schritt für Schritt auf containerisierte Apps. Dadurch bleiben Zertifikate, bestehende Domains und die aktuelle Caddy-Integration stabil, waehrend einzelne Apps isoliert migriert werden koennen.

## Server-Bestand

- Host: `artserver`
- OS: Ubuntu 24.04.4 LTS
- Kernel: 6.8.0-111-generic
- RAM: 7.6 GiB gesamt, ca. 6.0 GiB verfuegbar bei der Pruefung
- Swap: 4.0 GiB
- Disk `/`: 98 GiB gesamt, 35 GiB genutzt, 59 GiB frei
- Docker: aktuell nicht installiert bzw. nicht im PATH gefunden
- Node.js/npm: aktuell nicht im PATH gefunden
- Laufende relevante Dienste:
  - `caddy.service`
  - `php8.3-fpm.service`
  - `arzttarif.service`
  - `robowait-web.service`
  - `robowait-reverb.service`
  - `robowait-scheduler.service`

## Aktuelle Netzwerk- und Caddy-Struktur

Caddy lauscht auf Host-Ports `80`, `443`, `444`, `8088` und proxied bzw. serviert:

- `arnet.internet-box.ch`: Menueplan via PHP-FPM Socket `/run/php/menuplan.sock`
- `arnet.internet-box.ch:444`: Arzttarif via `127.0.0.1:8000`
- `robowait.arkons.ch`: RoboWait Web via `127.0.0.1:4445`
- RoboWait Reverb/WebSocket-Pfade `/app/*` und `/apps/*`: `127.0.0.1:4446`
- Arkons-Vorschau:
  - `:8088`
  - `http://arkons.ch`
  - `http://www.arkons.ch`
  - `http://192.168.1.136`

Empfehlung: Caddy nicht containerisieren. Container sollten nur interne Host-Ports binden, idealerweise `127.0.0.1:<port>`, und Caddy leitet weiter.

## App-Bestand

### Menueplan

- Pfad: `/opt/apps/Menueplan`
- Typ: klassische PHP-App, keine Composer-Struktur gefunden
- Laufzeit: PHP 8.3 via FPM
- Caddy-Root: `/opt/apps/Menueplan`
- FPM-Pool: `/etc/php/8.3/fpm/pool.d/menuplan.conf`
- FPM-Socket: `/run/php/menuplan.sock`
- Laufzeit-User/Gruppe für Daten: `www-data:www-data`
- Datenpfad: `/opt/apps/Menueplan/data`
- Backups: `/opt/apps/Menueplan/backups`
- Wichtige Ops-Skripte:
  - `ops/doctor.sh`
  - `ops/backup.sh`
  - `ops/restore.sh`
  - `ops/fix_data_permissions.sh`
  - `ops/install.sh`
- `.env` vorhanden. Inhalt wurde nicht ausgelesen; nur Schluesselnamen wurden erfasst.

Docker-Einschaetzung:

- Komplexitaet: mittel
- Sinnvoller Container: PHP-FPM oder Apache/PHP. Bei Host-Caddy passt PHP-FPM-Container mit TCP-Port besser als Unix-Socket.
- Persistente Volumes:
  - `/opt/apps/Menueplan/data`
  - `/opt/apps/Menueplan/backups` nur falls Backups im Container laufen sollen
- Offene Punkte:
  - Mail/SMTP aus `.env` ueber Container-Env abbilden
  - Schreibrechte für `data/` sauber auf Container-UID mappen
  - Caddy-Regeln für blockierte Pfade beibehalten
  - Doctor-/Backup-Skripte containerfaehig machen oder bewusst auf Host belassen

### RoboWait

- Pfad: `/opt/apps/robowait`
- Typ: Laravel 12 App in `apps/api`
- Laufzeit: PHP CLI Dienste via systemd
- Aktuelle Ports:
  - Web: `0.0.0.0:4445`
  - Reverb/WebSocket: `0.0.0.0:4446`
- Service-User: `robowait:robowait`
- Datenbank: SQLite unter `/opt/apps/robowait/apps/api/database/database.sqlite`
- Wichtige persistente Pfade:
  - `/opt/apps/robowait/apps/api/database`
  - `/opt/apps/robowait/apps/api/storage`
  - `/opt/apps/robowait/apps/api/storage/logs`
  - Upload-/Export-Unterpfade unter `storage/app`
- Bereits vorhanden:
  - `deploy/Dockerfile`
  - `deploy/docker-compose.yml`
  - `scripts/smoke-docker.sh`
- Aktuelles Dockerfile nutzt `php:8.2-cli`, installiert Composer-Abhaengigkeiten und startet `php artisan serve`.
- Aktuelles Compose startet nur einen `robowait`-Service.

Docker-Einschaetzung:

- Komplexitaet: mittel bis hoch
- Gute Nachricht: erste Docker-Artefakte existieren bereits.
- Hauptluecke: Die aktuelle Compose-Datei bildet Scheduler und Reverb noch nicht als eigene Services ab.
- Empfohlenes Ziel:
  - `robowait-web`: Laravel HTTP, intern z.B. `127.0.0.1:4445`
  - `robowait-reverb`: WebSocket, intern z.B. `127.0.0.1:4446`
  - `robowait-scheduler`: `php artisan schedule:work` oder aequivalente Schleife
  - gemeinsames Image, gemeinsame Volumes
- Offene Punkte:
  - `.env` ist für User `art` nicht lesbar; vor Migration mit `robowait`/sudo kontrolliert sichern
  - Container-Image sollte PHP-Extensions der Host-App vollstaendig abdecken
  - Build benoetigt Node 20.19+ oder 22.12+, wenn Vite-Assets im Container gebaut werden sollen
  - Caddy-Routen für Reverb unveraendert uebernehmen
  - SQLite-Locking/Dateirechte bei Container-UID prüfen

### Arzttarif

- Pfad: `/opt/apps/Arzttarif`
- Typ: Python/Flask/Gunicorn
- Aktueller Betrieb seit 2026-05-14: Docker-Prototyp hinter Host-Caddy
- Docker-Port: `127.0.0.1:18000`
- Caddy routet Arzttarif auf `127.0.0.1:18000`
- Alter Host-Dienst: `arzttarif.service`, gestoppt aber noch nicht geloescht/deaktiviert
- Alter Host-Port: `127.0.0.1:8000`, nach Stop frei
- WorkingDirectory im alten Dienst: `/opt/apps/Arzttarif`
- Alter ExecStart: `.venv/bin/gunicorn server:app --bind 127.0.0.1:8000 --workers 1 --timeout 180`
- EnvironmentFile: `/etc/arzttarif/arzttarif.env`, im Docker-Compose weiterverwendet
- Service-User alt: `arzttarif:arzttarif`
- Container-User: UID/GID `1000:1000` passend zu Besitzer `art:art` der App-Dateien
- Datenpfad: `/opt/apps/Arzttarif/data`
- Logs: `/opt/apps/Arzttarif/logs`
- Docker-Modellcache: `/opt/apps/Arzttarif/.docker-cache`, ca. 9 GiB nach erstem Kaltstart
- Requirements:
  - `flask`
  - `gunicorn`
  - `python-dotenv`
  - `requests`
  - `openai`
  - `bleach`
  - `pytest`
  - `anyio`
  - `flask-compress`
  - `faiss-cpu==1.12.0`
  - `sentence-transformers==2.2.2`
  - `huggingface-hub==0.25.2`
- Datenumfang App-Verzeichnis: ca. 7.6 GiB

Docker-Einschaetzung:

- Komplexitaet: niedrig bis mittel
- Technisch als erster Kandidat umgesetzt.
- Hauptthemen:
  - grosser Datenbestand und ML-Abhaengigkeiten machen Image-/Build-Zeit relevant
  - `data/` sollte als Host-Volume gemountet werden, nicht ins Image gebacken werden
  - `/etc/arzttarif/arzttarif.env` muss als Compose-`env_file` oder Secret-Ersatz uebernommen werden
  - Gunicorn bleibt mit `--workers 1 --timeout 180` konservativ
  - Container sollte nur an `127.0.0.1:8000` oder einen neuen internen Port binden
  - Erster Containerstart baut lokalen SentenceTransformer-Cache auf und dauert lange; Folgestarts sollten deutlich schneller sein.

## Empfohlene Reihenfolge

1. Docker Engine plus Compose Plugin installieren, aber noch keinen Produktivdienst umstellen.
2. Nur Arzttarif als ersten Container bauen und parallel auf einem Ausweichport starten, z.B. `127.0.0.1:18000`.
3. Arzttarif gegen Ausweichport testen: HTTP-Health, zentrale Endpunkte, Logs, Datenzugriff.
4. Caddy für Arzttarif auf Container-Port umstellen und Host-`arzttarif.service` erst danach deaktivieren.
5. RoboWait-Docker-Artefakte erweitern: separate Services für Web, Reverb und Scheduler.
6. RoboWait parallel testen, dann Caddy-Ports `4445`/`4446` schrittweise auf Container umlegen.
7. Menueplan zuletzt migrieren, weil PHP-FPM-Socket, Dateirechte und bestehende Datenstruktur sauber nachgebaut werden muessen.

## Betriebsregeln für die Migration

- Vor jeder App-Umstellung ein App-spezifisches Backup ausführen.
- Keine `.env`-Inhalte in dieses Repo kopieren.
- Host-Caddy bleibt die einzige öffentliche TLS-/HTTP-Schicht.
- Container-Ports an `127.0.0.1` binden, nicht an `0.0.0.0`, ausser es gibt einen klaren Grund.
- Bestehende Host-Dienste erst deaktivieren, wenn Container und Caddy-Route getestet sind.
- Rollback je App vorbereiten:
  - Caddy zurueck auf alten Host-Port/Socket
  - Container stoppen
  - alten systemd-Dienst wieder starten

## Naechste konkrete Arbeitsitems

- Arzttarif:
  - Docker-Prototyp liegt unter `deploy/artserver/docker/` und ist auf `artserver` aktiv.
  - `deploy/artserver/docker/arzttarif/Dockerfile` baut ein kleines Python-Dependency-Image.
  - `deploy/artserver/docker/compose.arzttarif.yml` startet die App parallel auf `127.0.0.1:18000` und mounted `/opt/apps/Arzttarif` zur Laufzeit.
  - `deploy/artserver/docker/smoke-arzttarif.sh` prüft `/api/version` und `/`.
  - Caddy wurde erfolgreich auf Docker-Port `18000` umgestellt.
  - Alter Host-Dienst wurde gestoppt, bleibt aber als Rollback bestehen.
- RoboWait:
  - vorhandenes `deploy/docker-compose.yml` in drei Services aufteilen
  - Reverb- und Scheduler-Startbefehle aus systemd uebernehmen
  - Image auf PHP-Version/Extensions prüfen
- Menüplan:
  - Docker-Prototyp liegt unter `deploy/artserver/docker/` und nutzt `127.0.0.1:18001`
  - `compose.menueplan.yml` startet den Menüplan parallel zum alten PHP-FPM-Socket
  - der Container mountet `/opt/apps/Menueplan` read-only und `/opt/apps/Menueplan/data` beschreibbar
  - UID/GID ist standardmässig `33:33`, passend zu `www-data:www-data`
  - `smoke-menueplan.sh` prüft API, Startseite und blockierte Datenpfade
  - `switch-menueplan-caddy.sh` kann Caddy zwischen Docker-Port und altem Socket umschalten
