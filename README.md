# artserver

Dieses Repository sammelt die lokalen Hilfsdateien und Notizen für die Installation auf `artserver`. Dazu gehört auch die statische Website `arkons.ch`; diese Website bleibt auf dem Server weiterhin unter dem Namen `arkons`.

## Aktueller Stand

- Die Website ist statisch und wird lokal aus `content/pages/*.html` nach `dist/` gebaut.
- Die öffentliche Domain `arkons.ch` bleibt vorerst noch bei Localsearch.
- Auf `artserver` ist eine interne Vorschau aktiv:
  - `http://192.168.1.136/`
  - `http://192.168.1.136/produkte/`
  - `http://192.168.1.136/robowait/`
  - `http://192.168.1.136/menueplaner/`
- Die Meldung "Nicht sicher" ist in dieser Vorschau normal, weil sie absichtlich per HTTP im lokalen Netzwerk läuft.
- Die spätere produktive HTTPS-Umschaltung auf `https://arkons.ch` erfolgt separat, erst wenn Localsearch wirklich abgelöst werden soll.

## Wichtig vor jeder Aenderung

- Bestehende Anwendungen auf `artserver` nicht direkt verändern, wenn es nur um diese Website geht.
- Die Caddy-Konfiguration für Menüplan, RoboWait und Arzttarif nicht manuell überschreiben.
- Keine DNS-Änderung für `arkons.ch` oder `www.arkons.ch` machen, solange Localsearch noch produktiv bleiben soll.
- Für Website-Änderungen reicht normalerweise das lokale Admin-Menü.

## Schnellstart

Empfohlenes Admin-Menue starten:

```powershell
.\artserver-admin.ps1
```

Alternativ per CMD oder Doppelklick:

```text
artserver-admin.cmd
```

Wichtige Menuepunkte nach Bereich:

Website / arkons.ch:

- `1` Website lokal bauen
- `2` Website lokal anzeigen
- `3` Website nach artserver-Vorschau deployen
- `4` Arkons-Caddy-Vorschau aktivieren/erneuern, braucht `sudo`
- `5` Status prüfen
- `6` Vorschau im Browser öffnen

Server allgemein:

- `7` SSH-Shell zu artserver
- `8` Dienste und Container anzeigen
- `11` Server-Skripte anzeigen
- `12` artserver Systemupdate starten, braucht `sudo`, kann rebooten
- `13` Borg Restore Assistent starten, braucht `sudo`
- `14` Notebook-Headless Status anzeigen
- `15` Notebook-Headless Modus setzen, braucht `sudo`
- `16` Notebook-Headless Modus zuruecksetzen, braucht `sudo`
- `26` Systemupdate, Neustart und Kontrolle, braucht `sudo`

Menüplan:

- `9` Menüplan Smoke-Test starten
- `10` Menüplan Backup starten

RoboWait:

- `17` RoboWait Backup starten
- `18` RoboWait Update starten, braucht `sudo`

Zentrale:

- `19` artserver-Zentrale einrichten/aktualisieren
- `20` artserver-Zentrale anzeigen
- `21` Server-Dokumente anzeigen
- `22` Aufräumkandidaten anzeigen
- `32` Skripte ordnen und Altlasten archivieren, braucht `sudo`
- `34` Zentralen Skriptkatalog anzeigen
- `35` Skript aus zentralem Katalog starten
- `36` Projekt-Admin-Einstiege anzeigen

Docker:

- `23` Docker und Portainer Status anzeigen
- `24` Portainer im Browser öffnen
- `25` Portainer installieren/aktualisieren, braucht `sudo`
- `27` Menüplan Docker-Update aus GitHub, braucht `sudo`
- `28` Arzttarif Docker-Deploy vom Entwicklungsordner, braucht `sudo`
- `29` RoboWait Docker-Prototyp starten, braucht `sudo`
- `30` RoboWait Docker-Smoke-Test starten
- `31` Portainer Admin-Passwort zurücksetzen, zeigt die manuellen `sudo`-Befehle

Hilfe:

- `H` Hilfe zu allen Menuepunkten direkt im Skript anzeigen
- `.\artserver-admin.ps1 -Help` dieselbe Hilfe direkt ohne interaktives Menue anzeigen
- `.\artserver-admin.ps1 -Run 19` neuen Direktstart für die artserver-Zentrale ausführen
- `.\artserver-admin.ps1 -Run 26` Systemupdate mit frischem Neustart und anschliessender Kontrolle starten
- `.\artserver-admin.ps1 -Run 36` lokale Admin-Einstiege der einzelnen Projekte anzeigen

Hinweis zu Menüpunkt `26`: Wenn der Ablauf scheinbar stehen bleibt, wartet Linux oft auf das `sudo`-Passwort für `artserver`. Beim Tippen zeigt Linux keine Sterne und keine Punkte an. Passwort eingeben und Enter drücken.

## Typischer Ablauf nach einer Website-Aenderung

1. Datei in `content/pages/`, `content/site.json`, `assets/` oder `downloads/` anpassen.
2. Admin-Menue starten:

```powershell
.\artserver-admin.ps1
```

3. Menuepunkt `1` ausführen und prüfen, ob der Build fehlerfrei ist.
4. Optional Menuepunkt `2` ausführen und lokal ansehen:

```text
http://127.0.0.1:4173/
```

5. Menuepunkt `3` ausführen, um die Vorschau auf `artserver` zu aktualisieren.
6. Im Browser prüfen:

```text
http://192.168.1.136/
```

7. Menuepunkt `5` ausführen, um Arkons-Vorschau und bestehende Apps zu prüfen.

## Dateien und Struktur

- `content/pages/*.html`: einzelne Inhaltsseiten
- `content/site.json`: Navigation, Footer und Basisdaten
- `templates/base.html`: gemeinsames HTML-Grundlayout
- `assets/css/styles.css`: gemeinsame Gestaltung
- `assets/img/`: Bilder
- `assets/img/products/`: Produktbilder für RoboWait und Menueplaner
- `downloads/`: Downloads
- `scripts/build.py`: Generator
- `dist/`: gebaute statische Website, wird bei jedem Build neu erzeugt
- `artserver-admin.ps1`: lokales Admin-Menue für PowerShell
- `artserver-admin.cmd`: Wrapper für Doppelklick/CMD
- `deploy/artserver/apply-arkons-preview.sh`: Server-Skript für die Caddy-Vorschau
- `deploy/artserver/arkons-production.caddy`: Vorlage für die spätere produktive HTTPS-Konfiguration
- `deploy/artserver/docker-migration-audit.md`: Vorarbeit für eine spätere Docker-Migration der Apps, mit Host-Caddy als Reverse Proxy
- `deploy/artserver/docker/`: Docker-Prototypen und Smoke-/Umschalt-/Aufräumskripte für Arzttarif und Menüplan, mit Host-Caddy als Reverse Proxy
- `docs/artserver-zentrale.md`: Übersicht zur zentralen Dokumenten- und Skriptablage auf `artserver`
- `docs/artserver-skriptordnung.md`: Einordnung der wichtigen, alten und zu archivierenden Skripte
- `docs/docker-portainer-sorgfalt.md`: Anleitung, was Portainer kann und wie man Docker vorsichtig verwaltet
- `docs/server-neuinstallation-checkliste.md`: Checkliste für einen späteren Neuaufbau von `artserver`

## Neue Seite anlegen

1. `content/pages/_template.html` kopieren.
2. Im Kopf der Datei `title`, `description` und `path` anpassen.
3. Inhalt innerhalb von `<main>...</main>` schreiben.
4. Falls die Seite in die Hauptnavigation oder ins Produkt-Dropdown soll, `content/site.json` anpassen.
5. Build ausführen:

```powershell
python scripts/build.py
```

6. Danach lokal und auf `artserver` prüfen.

## Seite ändern oder löschen

- Ändern: passende Datei unter `content/pages/` bearbeiten und neu bauen.
- Löschen: Datei unter `content/pages/` entfernen und passende Navigationseinträge aus `content/site.json` entfernen.
- Bilder: unter `assets/img/` ablegen und mit absolutem Webpfad verlinken, z. B. `/assets/img/products/beispiel.png`.
- Anwendungen: nur Links und Beschreibungstexte in dieser Website anpassen. Die Anwendungen selbst liegen separat auf `artserver`.

## Aktuelle Seiten

- `/` Startseite
- `/apps/` Anwendungsübersicht
- `/produkte/` Produktübersicht
- `/arzttarif-assistent/` Arzttarif-Assistent
- `/Tarifvergleich/` Tarifvergleich und Download
- `/Quiz_NeuerArzttarif/` Spiel und Quiz Neuer Arzttarif
- `/robowait/` Produktseite RoboWait
- `/menueplaner/` Produktseite Menueplaner
- `/uber-uns/` Profil und Impressum-nahe Informationen
- `/kontakt/` Adresse, Telefon und Mailadresse
- `/privacy/` Datenschutzhinweise

## artserver

Zugang:

```powershell
ssh art@artserver
```

Aktuelle LAN-Adresse:

```text
192.168.1.136
```

Website-Vorschau auf dem Server:

```text
/home/art/arkons/www/current
```

Wichtig: Dieser Serverpfad bleibt absichtlich unter `arkons`, weil er zur Website `arkons.ch` gehört. Der neue Repository- und lokale Projektname `artserver` ändert daran nichts.

Releases:

```text
/home/art/arkons/www/releases/YYYYMMDD-HHMMSS
```

Das Admin-Menü kopiert neue Builds als neues Release und schaltet dann nur den Symlink `current` um. Dadurch kann ein älterer Stand bei Bedarf wiederhergestellt werden.

## Manuelles Deployment ohne Admin-Menue

Normalerweise Menuepunkt `3` verwenden. Manuell geht es so:

```powershell
python scripts/build.py
```

Dann `dist/` als neues Release nach `artserver` kopieren und `/home/art/arkons/www/current` auf dieses Release zeigen lassen. Der genaue Ablauf ist in `artserver-admin.ps1` in der Funktion `Deploy-ArtserverPreview` dokumentiert.

## Caddy-Vorschau erneuern

Normalerweise Menuepunkt `4` verwenden.

Manuell:

```powershell
ssh -t art@artserver "sudo bash /home/art/arkons/deploy/apply-arkons-preview.sh"
```

Das Skript:

- prüft, ob `/home/art/arkons/www/current/index.html` existiert,
- legt Backups unter `/etc/caddy/backups/` an,
- schreibt nur `/etc/caddy/sites-enabled/arkons-preview.caddy`,
- validiert Caddy,
- lädt Caddy neu,
- prüft, ob Caddy aktiv bleibt.

## Status prüfen

Mit Admin-Menuepunkt `5`.

Manuell:

```powershell
curl.exe -I --max-time 8 http://192.168.1.136/
ssh art@artserver "systemctl is-active caddy"
```

Bestehende Apps werden im Admin-Menue ebenfalls geprüft:

- Menüplan über `arnet.internet-box.ch`
- RoboWait über `robowait.arkons.ch`
- Arkons-Vorschau per Host `arkons.ch` gegen lokalen Caddy

## Bestehende Anwendungen auf artserver

Aktuell erkennbare Anwendungen:

- Menüplan: `/opt/apps/Menueplan`, PHP-FPM/Caddy; Docker-Prototyp geplant auf `127.0.0.1:18001`, extern bisher `https://arnet.internet-box.ch:4443/`
- RoboWait: `/opt/apps/robowait`, Laravel/Systemd, aktuell `https://robowait.arkons.ch/`
- Arzttarif: `/opt/apps/Arzttarif`, Docker/Gunicorn, intern auf `127.0.0.1:18000`; Caddy routet die öffentliche Adresse darauf.

Diese Anwendungen sind nicht Teil der statischen Website. Die Website verlinkt nur darauf.

Vorarbeit für eine spätere Docker-Migration liegt in:

```text
deploy/artserver/docker-migration-audit.md
```

## Integrierte Server-Skripte nach Bereich

Das Admin-Menue integriert einige vorhandene Skripte von `artserver`.

## Projekt-Admin-Einstiege auf dem Entwicklungsrechner

Die zentrale Kommandozentrale verweist zusätzlich auf die wichtigsten lokalen Admin-Startpunkte der einzelnen Projekte. Im Menü ist das Punkt `36`; im Skriptkatalog erscheinen sie unter der Gruppe `Projekt-Admin-Einstiege`.

- artserver: `C:\Users\beata\OneDrive\Dokumente\Private_Projekte\artserver\artserver-admin.cmd`
- Menüplan: `C:\Users\beata\OneDrive\Dokumente\Private_Projekte\Menueplan\Deploy-To-Artserver.ps1`, `Sync-Data-From-Artserver.ps1`, `Start_Menüplan.bat`
- RoboWait: `C:\Users\beata\OneDrive\Dokumente\Private_Projekte\RoboWait\scripts\robowait-admin.cmd`
- Arzttarif: `C:\Users\beata\OneDrive\Dokumente\Private_Projekte\Arzttarif_Assistent_dev\scripts\Deploy-Docker-To-Artserver.ps1`, `git-merge-to-main.ps1`, `cleanup-branches-main.ps1`

Website / arkons.ch:

- `/home/art/arkons/deploy/apply-arkons-preview.sh`: Caddy-Vorschau für arkons.ch.

Server allgemein:

- `/home/art/scripts/update_artserver.sh`: Systemupdate mit `apt full-upgrade`, Dienstneustarts und ggf. Reboot. Nur in einem Wartungsfenster starten.
- Admin-Menuepunkt `26`: führt das Systemupdate aus, erzwingt danach einen frischen Neustart, wartet auf SSH und kontrolliert systemd-Dienste, Docker/Portainer und Web-Endpunkte.
- `/home/art/scripts/borg-restore-guided.sh`: interaktiver Borg-Restore. Kann Daten wiederherstellen oder überschreiben; nur bewusst starten.
- `/home/art/scripts/artserver_setup.sh`: Neuaufbau/Basissetup, nur manuell nach Prüfung.

Menüplan:

- `/home/art/arkons/deploy/artserver/docker/smoke-menueplan.sh`: Docker-Smoke-Test.
- `/opt/apps/Menueplan/ops/backup.sh`: Backup.
- `/opt/apps/Menueplan/ops/laptop_headless.sh`: Status, Aktivierung oder Rücksetzung des Notebook-Headless-Modus.
- `/opt/apps/Menueplan/ops/restore.sh`: Restore, nur manuell nach Prüfung.
- `/opt/apps/Menueplan/ops/install.sh`: Alt-Installation, nicht für Docker-Updates verwenden.

RoboWait:

- `/opt/apps/robowait/scripts/backup.sh`: RoboWait Backup.
- `/opt/apps/robowait/scripts/update-artserver.sh`: RoboWait Update mit Code-/Abhängigkeitsupdate und Dienstneustarts.
- `/opt/apps/robowait/scripts/restore.sh`: Restore, nur manuell nach Prüfung.
- `/opt/apps/robowait/scripts/install-artserver.sh`: Installation, nur manuell nach Prüfung.
- `/opt/apps/robowait/scripts/robowait-admin.ps1`: anwendungsspezifischer Admin-Helfer.

Docker / Portainer:

- Docker Engine und Docker Compose sind auf `artserver` installiert.
- Portainer CE kann als Weboberfläche für Docker unter `https://192.168.1.136:9443/` laufen.
- Das Admin-Menue installiert Portainer mit persistentem Docker-Volume `portainer_data`.
- Portainer bekommt Zugriff auf `/var/run/docker.sock`. Das ist technisch nötig, bedeutet aber: Portainer kann Docker weitgehend steuern.
- Details zur vorsichtigen Bedienung: `docs/docker-portainer-sorgfalt.md`.
- Klare Container-Namen in Portainer: `Arzttarif`, `Menueplan`, `portainer`.
- Wenn Portainer schon eine Login-Seite zeigt, aber kein Passwort bekannt ist: Admin-Menuepunkt `31` zeigt die getesteten SSH-Befehle für den offiziellen Portainer-Helfer. Das Volume `portainer_data` bleibt dabei erhalten.
- Bei einer Neuinstallation von `artserver` müssen Docker, Docker Compose, Portainer und Caddy wieder eingeplant werden. Checkliste: `docs/server-neuinstallation-checkliste.md`.
- App-Updates im Docker-Betrieb laufen über das zentrale Admin-Menü:
  - Menüpunkt `27`: Menüplan aus GitHub aktualisieren, Container neu starten, Smoke-Test.
  - Menüpunkt `28`: Arzttarif-Assistent vom lokalen Entwicklungsordner deployen, Container neu starten, Smoke-Test.

Arzttarif / Alt-Skripte:

- `/home/art/arkons/deploy/artserver/docker/cleanup-arzttarif-host-installation.sh`: entfernt nach erfolgreichem Docker-Test den alten Host-Dienst, die alte `.venv` und alte Migrationsskripte. Braucht `sudo`.
- `/home/art/scripts/migrate_arzttarif_to_ubuntu.sh`: Arzttarif-Migration/Installation, nur manuell nach Prüfung. Nach der Docker-Bereinigung wird dieses Skript archiviert.
- `/home/art/scripts/oaat-update-apps.sh`: älteres generisches Update gegen `/etc/oaat/repos.list`. Nach der Docker-Bereinigung wird dieses Skript archiviert.

Bewusst nicht als Schnellstart integriert:

- `/home/art/scripts/install-artserver.sh`: historische RoboWait-Installation mit Beispiel-Repo.
- alle Neuaufbau-, Installations-, Restore- und Migrationsskripte, die bestehende Konfigurationen ersetzen können.

Diese Skripte können bestehende Konfigurationen verändern und sollten nur nach gezielter Prüfung manuell gestartet werden.

## Wiederherstellung eines älteren Website-Releases

Auf `artserver`:

```bash
ls -1 /home/art/arkons/www/releases
ln -sfn /home/art/arkons/www/releases/GEWUENSCHTES-RELEASE /home/art/arkons/www/current
```

Danach prüfen:

```bash
curl -I http://127.0.0.1/
```

Falls Caddy selbst geändert wurde, liegen Backups unter:

```text
/etc/caddy/backups/
```

## Spätere produktive Umschaltung von Localsearch auf artserver

Erst durchführen, wenn die eigene Website wirklich produktiv werden soll.

Vorher prüfen:

- Vorschau auf `http://192.168.1.136/` ist inhaltlich korrekt.
- Menuepunkt `5` im Admin-Menue ist fehlerfrei.
- Router leitet HTTP/HTTPS passend auf `artserver` weiter.
- Bestehende Apps funktionieren weiter.
- DNS-Zugriff für `arkons.ch` und `www.arkons.ch` ist vorhanden.

Dann wird die Vorschau-Konfiguration durch eine produktive Caddy-Konfiguration ersetzt. Vorlage:

```text
deploy/artserver/arkons-production.caddy
```

Erst danach DNS umstellen:

- `arkons.ch` auf die öffentliche IP von `artserver` bzw. des Routers
- `www.arkons.ch` ebenfalls auf diese Zieladresse oder als CNAME passend konfigurieren

Wichtig: Caddy kann das öffentliche HTTPS-Zertifikat erst holen, wenn DNS und Router wirklich auf `artserver` zeigen.

## Git-Hinweis

`dist/` ist die gebaute Ausgabe und ändert sich bei jedem Build. Die eigentlichen Inhalte liegen in `content/`, `assets/`, `downloads/`, `templates/` und `scripts/`.

Beim Prüfen von Aenderungen ist vor allem relevant:

```powershell
git status --short
```

Bekannte lokale Aenderung, die nichts mit dem artserver-Setup zu tun hat:

- In `content/pages/uber-uns.html` wurde ein Gremienzeitraum von `2021-heute` auf `2021-2025` angepasst.
