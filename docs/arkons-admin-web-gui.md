# Arkons Admin Web-GUI

Stand: 2026-05-18

## Ziel

Die neue Administrationsoberfläche soll im Repository `artserver` entstehen und später auch auf `artserver` laufen. Sie wird die zentrale Stelle für Website, Serverstatus, Docker-Container und die Wartungsskripte der Anwendungen.

Wichtig ist dabei: Die Oberfläche soll nicht nur Buttons anzeigen. Sie soll erklären, was ein Button macht, wann man ihn braucht, welches Risiko er hat, was vorher geprüft werden sollte und woran man nachher erkennt, ob alles funktioniert hat. Diese Informationen müssen direkt beim jeweiligen Skript sichtbar sein, damit auch später noch klar ist, warum ein Menüpunkt existiert.

## Ausgangslage

Aktuell laufen die Anwendungen als Container auf `artserver`:

| Bereich | Container / Dienst | Interner Host-Port | Bemerkung |
| --- | --- | --- | --- |
| Arzttarif | `Arzttarif` | `127.0.0.1:18000` | API-Check über `/api/version` |
| Menüplan | `Menueplan` | `127.0.0.1:18001` | Status-Check über `/api.php?type=status` |
| RoboWait Web | `robowait-docker-web` | `127.0.0.1:18002` | Laravel-Weboberfläche |
| RoboWait Reverb | `robowait-docker-reverb` | `127.0.0.1:18003` | WebSocket-Dienst |
| RoboWait Scheduler | `robowait-docker-scheduler` | kein HTTP-Port | Hintergrundaufgaben |
| Webseite | statische Releases | Caddy | noch nicht im Container |

Die Ports `127.0.0.1:18000` bis `18003` sind absichtlich nur auf `artserver` erreichbar. Wenn man im Browser des Entwicklungsrechners `http://127.0.0.1:18001/...` öffnet, fragt der Browser den eigenen Rechner ab, nicht `artserver`. Darum erscheint dort `connection refused`, obwohl der Container auf `artserver` laufen kann.

Für den Browser gibt es drei richtige Wege:

1. Öffentliche oder LAN-Caddy-Adresse der Anwendung verwenden.
2. Einen SSH-Tunnel öffnen, zum Beispiel `ssh -L 18001:127.0.0.1:18001 art@artserver`.
3. Die zukünftige Admin-Oberfläche auf `artserver` laufen lassen und die Checks dort serverseitig ausführen.

Für die neue Admin-Oberfläche ist Punkt 3 der saubere Weg.

## Grundentscheidung

Die Admin-Oberfläche wird nicht in Menüplan, RoboWait oder Arzttarif eingebaut. Sie wird eine eigene kleine Anwendung im Repository `artserver`.

Vorgeschlagener Dienst:

| Eigenschaft | Vorschlag |
| --- | --- |
| Repo | `artserver` |
| App-Ordner | `admin-gui/` |
| Containername | `arkons-admin` |
| Interner Port | `127.0.0.1:18010` |
| Konfiguration | JSON-Dateien im Repo und auf `artserver` |
| Skriptstart | nur über freigegebene Skript-IDs |
| Logs | pro Job ein eigenes Log |

## Startwege

Es soll zwei Startwege geben, weil sie zwei unterschiedliche Situationen abdecken.

### Start vom Entwicklungsrechner

Für den Alltag am Windows-Rechner ist ein `.cmd` sinnvoll, ähnlich wie heute:

```text
C:\Users\beata\OneDrive\Dokumente\Private_Projekte\artserver\artserver-admin.cmd
```

Für die Weboberfläche könnte es zusätzlich geben:

```text
C:\Users\beata\OneDrive\Dokumente\Private_Projekte\artserver\artserver-admin-web.cmd
```

Dieses lokale Startskript könnte:

1. prüfen, ob `artserver` per SSH erreichbar ist,
2. optional einen SSH-Tunnel öffnen,
3. die Admin-Weboberfläche im Browser öffnen,
4. bei Nichterreichbarkeit eine verständliche Fehlermeldung zeigen.

Beispielziel:

```text
http://127.0.0.1:18010/
```

Wenn der Tunnel aktiv ist, zeigt `127.0.0.1:18010` auf deinem Entwicklungsrechner zum Admin-GUI auf `artserver`.

### Direkter Browserzugriff im LAN oder VPN

Zusätzlich kann die Oberfläche direkt im Browser erreichbar sein, aber nur geschützt:

```text
https://admin.arkons.ch/
```

oder im LAN:

```text
https://artserver/admin/
```

Der Zugriff darf nicht einfach offen im Internet hängen. Für die erste produktive Variante ist sinnvoll:

- Zugriff nur aus dem LAN oder über VPN.
- Caddy schützt die Route zusätzlich.
- Login in der Admin-Oberfläche.
- Keine freien Shell-Befehle im Browser.
- Start nur über Skript-IDs aus dem Katalog.

Damit gibt es später zwei gleichwertige Bedienwege:

| Weg | Typischer Gebrauch |
| --- | --- |
| `artserver-admin-web.cmd` | bequem vom Entwicklungsrechner starten |
| Browser im LAN/VPN | von einem berechtigten Gerät direkt öffnen |

## Navigationsmodell

Die Oberfläche soll ruhig, dicht und gut scanbar sein. Keine Landingpage, sondern direkt die Arbeitsoberfläche.

### Linke Navigation

```text
Übersicht
Webseite
artserver
Arzttarif
Menüplan
RoboWait
Skripte
Jobs und Logs
Backups
Einstellungen
```

Die Navigation entsteht später aus einer App-Konfiguration. Wenn eine Anwendung dazukommt, wird sie dort eingetragen. Wenn eine Anwendung wegfällt, wird sie deaktiviert oder entfernt.

### Kopfbereich

Oben auf jeder Seite:

```text
Arkons Admin
artserver: erreichbar
Caddy: aktiv
Docker: aktiv
Letzter Statuscheck: 2026-05-18 14:32
```

Zusätzlich eine kompakte Warnzeile:

```text
Keine kritischen Warnungen
```

oder:

```text
Warnung: RoboWait Scheduler läuft nicht
```

## Startseite

Die Startseite zeigt alle wichtigen Bereiche auf einen Blick:

```text
Webseite       OK      letzte Veröffentlichung, Vorschau, Deploy
artserver      OK      Caddy, Docker, Speicher, Updates
Arzttarif      OK      Container, API, GitHub-Stand, Smoke-Test
Menüplan       OK      Container, Status-API, Backup, Smoke-Test
RoboWait       OK      Web, Reverb, Scheduler, Backup
```

Jede Zeile oder Karte zeigt:

- Status: OK, Warnung, Fehler, unbekannt
- interne Ports
- öffentliche URL
- letzte erfolgreiche Prüfung
- letzter Job
- wichtigste Aktion

Beispiel:

```text
Menüplan
Status: OK
Container: Menueplan läuft seit 2 Tagen
Interner Port: 127.0.0.1:18001
Letzter Smoke-Test: erfolgreich
Letztes Backup: 2026-05-18 06:00

[Öffnen] [Backup] [Update aus GitHub] [Smoke-Test]
```

## Detailseite einer Anwendung

Wenn links `Menüplan` gewählt wird, zeigt das Hauptfenster:

```text
Menüplan

Kurzstatus
- Container: Menueplan
- Port: 127.0.0.1:18001
- Route: Caddy zeigt auf Docker
- GitHub: BeatArnet/Menueplan main
- Datenordner: /opt/apps/Menueplan/data

Aktionen
```

Danach folgen die Skripte. Unter jedem Skript steht direkt die Hilfe.

### Beispiel: Update

```text
[Docker-Update aus GitHub starten]

Was macht dieser Punkt?
Holt den neuesten GitHub-Stand des Menüplans, aktualisiert den Code auf
artserver, lässt produktive Daten und geheime Dateien stehen, startet den
Container neu und führt danach den Smoke-Test aus.

Wann verwenden?
Wenn Änderungen im GitHub-Repository bereit sind und produktiv auf artserver
übernommen werden sollen.

Vorher prüfen
- Ist gerade niemand mitten im Kochen mit dem Menüplan?
- Gibt es ein aktuelles Backup?
- Ist GitHub erreichbar?

Risiko
Mittel. Der Container wird kurz neu gestartet.

Schutzwort
MENUEPLAN

Erfolgskriterium
Smoke-Test erfolgreich, Startseite erreichbar, Datenpfade blockiert.
```

### Beispiel: Backup

```text
[Backup starten]

Was macht dieser Punkt?
Erstellt ein Backup der produktiven Menüplan-Daten auf artserver.

Wann verwenden?
Vor Updates, vor Restore-Tests oder zusätzlich zu automatischen Backups.

Risiko
Niedrig. Es werden nur Daten gelesen und als Backup abgelegt.

Erfolgskriterium
Backup-Datei wurde erstellt und das Skript endet mit Exitcode 0.
```

## Skriptmodell

Die Admin-Oberfläche darf nie beliebige Shell-Befehle entgegennehmen. Sie darf nur eine Skript-ID aus dem Katalog starten.

Beispiel:

```text
menueplan.backup
robowait.update.github
arzttarif.update.github
```

Der Server prüft dann:

1. Gibt es diese ID im Katalog?
2. Ist sie für Web-Start freigegeben?
3. Braucht sie ein Schutzwort?
4. Ist die Anwendung gerade gesperrt, weil schon ein Job läuft?
5. Mit welchem Benutzer und welchem Befehl darf sie gestartet werden?
6. Wohin wird das Log geschrieben?

## Konfigurationsdateien

Es soll zwei zentrale Dateien geben.

### `artserver-apps.json`

Beschreibt die Anwendungen und Bereiche:

- Anzeige in der Navigation
- Container
- Ports
- URLs
- Healthchecks
- zugehörige Skript-IDs
- Hinweise für Menschen

### `artserver-script-catalog.json`

Beschreibt die Skripte:

- ID
- Name
- Gruppe
- Risiko
- Startart
- Schutzwort
- ausführliche Hilfe
- erwartete Wirkung
- Rollback-Hinweis
- Web-Freigabe

Der bestehende Katalog ist bereits eine gute Grundlage. Für das Web-GUI sollte er erweitert werden.

## Vorgeschlagene zusätzliche Felder im Skriptkatalog

```json
{
  "id": "menueplan.update.github",
  "webEnabled": true,
  "title": "Menüplan Docker-Update aus GitHub",
  "summary": "Aktualisiert den produktiven Menüplan aus GitHub.",
  "details": "Ausführlicher Text für Menschen.",
  "whenToUse": "Wenn der GitHub-Stand produktiv übernommen werden soll.",
  "beforeStart": [
    "Prüfen, ob gerade niemand den Menüplan benutzt.",
    "Backup prüfen oder vorher Backup starten."
  ],
  "effect": [
    "Code wird aktualisiert.",
    "Container wird neu gestartet.",
    "Smoke-Test wird ausgeführt."
  ],
  "successCriteria": [
    "Smoke-Test endet erfolgreich.",
    "Startseite antwortet.",
    "Datenpfade bleiben blockiert."
  ],
  "rollback": "Vorheriges Git-Release oder Backup wiederherstellen; bei Caddy-Problemen Route prüfen.",
  "lockScope": "menueplan",
  "logRetentionDays": 90
}
```

## Sicherheitsmodell

Das GUI braucht ein bewusst enges Sicherheitsmodell.

### Keine freien Befehle

Nicht erlaubt:

```text
Benutzer tippt beliebigen Shell-Befehl ins Webformular.
```

Erlaubt:

```text
Benutzer klickt freigegebene Skript-ID.
Runner startet genau den hinterlegten Befehl.
```

### Schutzwörter

Bei riskanten Aktionen muss ein Schutzwort eingegeben werden:

| Risiko | Beispiel | Schutz |
| --- | --- | --- |
| niedrig | Smoke-Test | kein Schutzwort |
| mittel | App-Update | Schutzwort |
| hoch | Restore, Branch-Cleanup | starkes Schutzwort und Warntext |

### Job-Locks

Pro Anwendung darf nur ein verändernder Job gleichzeitig laufen.

Beispiele:

- Während `menueplan.update.github` läuft, ist `menueplan.restore` gesperrt.
- Während `robowait.update.github` läuft, ist `robowait.backup` erlaubt oder gesperrt je nach Entscheidung im Katalog.

### Logs

Jeder Start erzeugt ein eigenes Log:

```text
/var/log/arkons-admin/jobs/20260518-143210-menueplan.update.github.log
```

Die Oberfläche zeigt:

- Startzeit
- Ende
- Exitcode
- Benutzer
- Skript-ID
- gekürzte Ausgabe
- Link zum vollständigen Log

## Runner

Die Weboberfläche sollte nicht selbst direkt Shell-Befehle ausführen. Besser ist ein kleiner Runner:

```text
arkons-admin-runner run menueplan.backup
arkons-admin-runner status
arkons-admin-runner jobs
```

Der Runner kann am Anfang als Bash-Skript umgesetzt werden:

```text
/home/art/arkons/deploy/artserver/admin/arkons-admin-runner.sh
```

Dieser erste Runner existiert nun als Bash-Skript im Repo:

```text
deploy/artserver/admin/arkons-admin-runner.sh
```

Er unterstützt:

```bash
bash arkons-admin-runner.sh list
bash arkons-admin-runner.sh show menueplan.backup
bash arkons-admin-runner.sh run menueplan.backup
bash arkons-admin-runner.sh run menueplan.update.github --confirm MENUEPLAN
bash arkons-admin-runner.sh run menueplan.update.github --confirm MENUEPLAN --dry-run
```

Startbar sind nur Katalogeinträge mit:

```text
enabled: true
location: artserver
run.type: ServerShell
```

Lokale Windows-Skripte bleiben im Katalog sichtbar, werden aber vom Server-Runner nicht ausgeführt. Das ist wichtig, weil das spätere Web-GUI auf `artserver` läuft und dort keine lokalen Dateien vom Entwicklungsrechner starten kann.

Später kann der Runner in Python oder Go ersetzt werden, ohne dass das Web-GUI anders aussieht, solange die Schnittstelle über Skript-IDs gleich bleibt.

## Rechte und sudo

Für die erste Version sollte der Runner als Benutzer `art` laufen. Für einzelne Befehle mit `sudo` braucht es gezielte Freigaben.

Nicht empfohlen:

```text
www-data ALL=(ALL) NOPASSWD: ALL
```

Empfohlen:

```text
arkons-admin darf nur genau definierte Skripte mit sudo starten.
```

Beispielprinzip:

```text
arkons-admin ALL=(root) NOPASSWD: /home/art/arkons/deploy/artserver/docker/update-arzttarif-github.sh
```

Die genaue sudoers-Datei muss vorsichtig erstellt und mit `visudo -c` geprüft werden.

## Statuschecks

Das Dashboard sollte nicht nur Docker anzeigen, sondern aus mehreren Blickwinkeln prüfen.

### Server

- `systemctl is-active caddy`
- `systemctl is-active docker`
- Speicherplatz
- RAM
- Load
- letzte Paketupdates

### Docker

- `docker ps`
- Containerstatus
- Healthcheck-Status
- Compose-Projekt

### Caddy

- aktive Route
- zeigt Route auf Docker-Port?
- `caddy validate`

### Anwendungen

| Anwendung | Check |
| --- | --- |
| Arzttarif | `curl http://127.0.0.1:18000/api/version` |
| Menüplan | `curl http://127.0.0.1:18001/api.php?type=status` |
| RoboWait | `curl http://127.0.0.1:18002/` und Reverb-Port prüfen |
| Webseite | Caddy-Preview und produktive URL prüfen |

## Oberfläche im Detail

### Übersicht

```text
┌──────────────────────────────────────────────────────────────┐
│ Arkons Admin                         artserver OK  Docker OK │
├───────────────┬──────────────────────────────────────────────┤
│ Übersicht     │ Systemübersicht                              │
│ Webseite      │                                              │
│ artserver     │ [Webseite] [artserver] [Arzttarif]           │
│ Arzttarif     │ [Menüplan] [RoboWait]                        │
│ Menüplan      │                                              │
│ RoboWait      │ Letzte Jobs                                  │
│ Skripte       │ - menueplan.backup OK                        │
│ Jobs und Logs │ - robowait.update.github OK                  │
│ Backups       │ - arzttarif.update.github OK                 │
│ Einstellungen │                                              │
└───────────────┴──────────────────────────────────────────────┘
```

### Anwendung

```text
Menüplan

Status
[OK] Container läuft
[OK] Caddy zeigt auf Docker
[OK] Status-API antwortet

Skripte

[Backup starten]
Hilfestellung direkt darunter...

[Docker-Update aus GitHub starten]
Hilfestellung direkt darunter...

[Restore starten]
Hilfestellung direkt darunter...
```

### Skripte

Die Seite `Skripte` ist eine tabellarische Gesamtübersicht:

```text
ID                         Gruppe      Risiko   Startbar   Ort
menueplan.backup           Menüplan    niedrig  ja         artserver
menueplan.restore          Menüplan    hoch     ja         artserver
robowait.update.github     RoboWait    hoch     ja         artserver
arzttarif.clean.json       Arzttarif   mittel   nein       Entwicklungsrechner
```

Nicht startbare Skripte bleiben sichtbar, aber mit Erklärung:

```text
Dieses Skript ist dokumentiert, aber nicht für Web-Start freigegeben,
weil Parameter oder Zielpfade zuerst manuell geprüft werden müssen.
```

## Warum alles im Repo `artserver`

Das ist sinnvoll, weil diese Oberfläche nicht Teil einer Fachanwendung ist. Sie verwaltet die Umgebung:

- Caddy
- Docker
- Website-Releases
- Backups
- GitHub-Updates
- Smoke-Tests
- Serverstatus

Darum gehört sie organisatorisch zum Server-Repository.

## Umsetzung in Etappen

### Etappe 1: Konfiguration

- `artserver-apps.json` anlegen.
- `artserver-script-catalog.json` um ausführliche Web-Hilfetexte erweitern.
- Katalogvalidierung bauen.

### Etappe 2: Runner

- `arkons-admin-runner.sh` mit `list`, `show`, `run`.
- Nur Skript-IDs zulassen.
- Logs pro Job schreiben.
- Lock-Dateien pro Anwendung.

### Etappe 3: Web-GUI nur lesend

- Dashboard zeigt Status.
- Skripte werden angezeigt, aber noch nicht gestartet.
- Hilfetexte sichtbar.

### Etappe 4: Web-GUI mit Startfunktion

- Niedrigrisiko-Skripte starten.
- Danach mittleres Risiko mit Schutzwort.
- Hochrisiko-Skripte erst nach sauberem Log- und Rollback-Konzept.

### Etappe 5: Betrieb absichern

- Login
- Caddy-Zugriff auf LAN oder VPN beschränken
- sudoers minimal freigeben
- Logrotation
- Backup der Konfiguration

## Erste Empfehlung

Als nächstes sollte nicht sofort ein grosses Webframework gebaut werden. Sinnvoller ist:

1. App-Konfiguration und Katalog sauber machen.
2. Runner bauen.
3. Ein kleines Web-GUI daraufsetzen.

Damit bleibt die Logik zuerst testbar in der Shell. Das Web-GUI ist dann nur die grafische Bedienung derselben sicheren Funktionen.
