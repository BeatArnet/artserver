# artserver-Zentrale

Stand: 2026-05-15

## Ziel

`artserver` enthält mehrere Projekte. Die Website `arkons.ch` bleibt auf dem Server unter `/home/art/arkons`, aber der Überblick über Skripte, Dokumente und Wartung soll zentral auffindbar sein.

Dafür gibt es auf dem Server die Zentrale:

```text
/home/art/artserver-hub
```

Diese Zentrale ist bewusst nur ein Wegweiser. Sie verschiebt keine produktiven Dateien und kopiert keine geheimen Daten.

## Wichtige Orte

- `/home/art/scripts`: allgemeine Server-Skripte, zum Beispiel Update, Restore, Grundsetup.
- `/home/art/arkons/deploy`: Deployment-Dateien für die Website `arkons.ch`.
- `/opt/apps/Menueplan`: Menueplan-App mit Doku und Ops-Skripten.
- `/opt/apps/robowait`: RoboWait-App mit Doku, Skripten und Admin-Helfer.
- `/opt/apps/Arzttarif`: Arzttarif-App und technische Dokumentation.
- `/etc/caddy/sites-enabled`: aktive Caddy-Site-Konfigurationen.
- `/etc/systemd/system`: lokale systemd-Unit-Dateien.

## Zentrale Verweise

Das Admin-Menü erstellt unter `/home/art/artserver-hub/links` symbolische Links auf diese Orte. Ein symbolischer Link ist wie ein Wegweiser oder eine Verknüpfung: Die Datei bleibt am Originalort, ist aber über die Zentrale schnell erreichbar.

## Neue Menüpunkte

Im lokalen Skript `artserver-admin.ps1` gibt es folgende Ergänzungen:

- `19`: artserver-Zentrale einrichten oder aktualisieren
- `20`: artserver-Zentrale anzeigen
- `21`: Server-Dokumente anzeigen
- `22`: Aufräumkandidaten anzeigen
- `23`: Docker und Portainer Status anzeigen
- `24`: Portainer im Browser öffnen
- `25`: Portainer installieren oder aktualisieren
- `26`: Systemupdate, Neustart und Kontrolle

## Analyse

Gefunden wurden diese Hauptbereiche:

- Allgemeine Server-Skripte unter `/home/art/scripts`
- Website-Skripte unter `/home/art/arkons/deploy`
- Menueplan-Dokumente und Ops-Skripte unter `/opt/apps/Menueplan`
- RoboWait-Dokumente, Docx-Exporte, Admin-Skript und viele temporäre Dateien unter `/opt/apps/robowait`
- Arzttarif-Dokumentation unter `/opt/apps/Arzttarif/doku`
- Viele alte Caddy-Backups unter `/etc/caddy`

Git-Status:

- `/opt/apps/Menueplan` ist ein Git-Repo, hat aber lokale Datenänderungen. Deshalb dort nicht automatisch aufräumen.
- `/opt/apps/robowait` ist ein Git-Repo und war sauber.
- `/home/art/arkons` ist kein Git-Repo, sondern Serverablage der Website.
- `/opt/apps/Arzttarif` ist auf dem Server kein Git-Repo.

## Aufräumkandidaten

Nicht automatisch gelöscht:

- `/opt/apps/robowait/.tmp`: alte Logs, Cookies, Snapshots und Testartefakte, etwa 165 MB.
- `/opt/apps/robowait/.tmp-deploy`: kleine temporäre Deploy-Dateien.
- `/opt/apps/robowait/.tmp-docx-export`: temporärer Docx-Export.
- `/home/art/database.sqlite.backup_missing_means_*`: lose Datenbank-Backups direkt im Home-Verzeichnis.
- alte Caddy-Backups unter `/etc/caddy`.

Regel: Erst sichern oder gezielt archivieren, dann löschen. Gerade Datenbanken, Cookies und Logs können vertrauliche Inhalte enthalten.

## Docker-Weboberfläche

Für die Docker-Verwaltung ist Portainer CE vorgesehen. Portainer läuft selbst als Docker-Container und stellt eine Weboberfläche bereit:

```text
https://192.168.1.136:9443/
```

Beim ersten Öffnen muss ein Admin-Benutzer angelegt werden. Das Zertifikat ist selbstsigniert, darum zeigt der Browser wahrscheinlich eine Warnung.

Sicherheitsregel: Portainer bekommt Zugriff auf den Docker-Socket `/var/run/docker.sock`. Damit kann Portainer Container starten, stoppen, verändern und Images verwalten. Deshalb ist die Installation im Admin-Menü mit der Schutzabfrage `PORTAINER` abgesichert.

Weitere Details:

- `docs/docker-portainer-sorgfalt.md`: Bedienung und Vorsichtsmassnahmen.
- `docs/server-neuinstallation-checkliste.md`: was bei einem Neuaufbau von `artserver` wieder eingerichtet werden muss.
