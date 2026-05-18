# Docker und Portainer sorgfältig verwenden

Stand: 2026-05-15

## Worum es geht

Docker ist die Laufzeitumgebung für Container. Ein Container ist vereinfacht gesagt ein abgegrenztes Paket, in dem eine Anwendung mit ihren Abhängigkeiten läuft.

Portainer ist eine Weboberfläche für Docker. Statt nur Befehle wie `docker ps` oder `docker compose up -d` im Terminal einzugeben, kann man viele Dinge im Browser sehen und teilweise auch bedienen.

Auf `artserver` ist Portainer vorgesehen unter:

```text
https://192.168.1.136:9443/
```

Der Browser wird wegen des selbstsignierten Zertifikats wahrscheinlich warnen. Das ist bei dieser internen Verwaltungsoberfläche erwartbar.

## Was man mit Portainer machen kann

Nützlich:

- Laufende Container sehen.
- Container starten, stoppen und neu starten.
- Logs eines Containers anschauen.
- Images sehen und alte Images erkennen.
- Volumes sehen, also dauerhafte Docker-Datenbereiche.
- Netzwerke sehen.
- Docker Compose Stacks verwalten, wenn sie in Portainer sauber als Stack angelegt wurden.

Praktisch für uns:

- Prüfen, ob der Arzttarif-Container läuft.
- Später Menueplan und RoboWait als Container kontrollieren.
- Nach einem Neustart sehen, ob Container wieder gestartet sind.
- Bei Fehlern schnell Logs öffnen, ohne lange Befehle suchen zu müssen.

Aktuelle klare Container-Namen in Portainer:

- `Arzttarif`
- `Menueplan`
- `portainer`

## Was man nicht leichtfertig tun sollte

Portainer bekommt Zugriff auf den Docker-Socket:

```text
/var/run/docker.sock
```

Das bedeutet: Portainer darf Docker weitgehend steuern. Darum ist Portainer keine harmlose Anzeige, sondern ein Administrationswerkzeug.

Nicht spontan tun:

- Container löschen.
- Volumes löschen.
- Images löschen, wenn unklar ist, ob sie noch gebraucht werden.
- Ports ändern.
- Netzwerke ändern.
- Stacks aus Portainer heraus neu erzeugen, wenn sie eigentlich über Dateien im Repository verwaltet werden.
- Einen Container „neu deployen“, ohne vorher zu wissen, wo dessen Daten liegen.

Besonders wichtig: Ein Docker-Volume kann die eigentlichen Daten enthalten. Wenn ein Volume gelöscht wird, sind diese Daten oft wirklich weg.

## Vorsichtiger Arbeitsablauf

Für Änderungen an Docker-Apps:

1. Status anschauen:

```powershell
.\artserver-admin.ps1 -Run 23
```

2. Prüfen, welche App betroffen ist.
3. Falls Daten betroffen sein könnten: Backup starten.
4. In Portainer nur ansehen, nicht sofort ändern.
5. Vor Änderungen notieren:
   - Containername
   - Image
   - Ports
   - Volumes
   - Compose-Datei oder Stack-Quelle
6. Änderung möglichst über die versionierten Dateien im Repository machen.
7. Nach der Änderung prüfen:
   - Container läuft
   - Logs zeigen keinen offensichtlichen Fehler
   - Webanwendung antwortet
   - Admin-Menü-Status ist plausibel

## Portainer installieren oder aktualisieren

Im Admin-Menü:

```powershell
.\artserver-admin.ps1
```

Dann Menüpunkt:

```text
25  Portainer installieren/aktualisieren
```

Das Menü fragt absichtlich nach:

```text
PORTAINER
```

Das Installationsskript liegt im Repository:

```text
deploy/artserver/docker/install-portainer-ce.sh
```

Es verwendet:

- Image: `portainer/portainer-ce:lts`
- Containername: `portainer`
- Volume: `portainer_data`
- Port: `9443`

Bei einer Aktualisierung wird der Container ersetzt, aber das Volume `portainer_data` bleibt erhalten. Darin liegen die Portainer-Einstellungen.

## Erste Anmeldung

Nach der Installation:

```text
https://192.168.1.136:9443/
```

Beim ersten Öffnen legt man einen Admin-Benutzer an. Das Passwort muss notiert oder im Passwortmanager gespeichert werden.

Danach normalerweise die lokale Docker-Umgebung auswählen. Portainer erkennt Docker über den gemounteten Docker-Socket.

## Wenn die Login-Seite erscheint, aber kein Konto bekannt ist

Wenn Portainer direkt `Log in to your account` zeigt, wurde Portainer schon einmal initialisiert. Die Kontoangaben liegen dann im Docker-Volume:

```text
portainer_data
```

In diesem Fall nicht das Volume löschen und Portainer nicht neu installieren. Das würde Einstellungen verlieren. Stattdessen im Admin-Menü:

```text
31  Portainer Admin-Passwort zurücksetzen
```

Das Menü zeigt die getesteten Befehle für den offiziellen Portainer-Helfer `portainer/helper-reset-password`. Die Befehle werden bewusst in Menüpunkt `7` oder einer vorhandenen SSH-Shell ausgeführt, weil die automatische Ausgabe über Windows-SSH/sudo nicht zuverlässig sichtbar war.

Die Befehle stoppen Portainer kurz, setzen im bestehenden Volume ein neues Admin-Passwort und starten Portainer wieder.

Danach in Portainer anmelden mit:

```text
Benutzername: admin
Passwort: das im Konsolenfenster ausgegebene neue Passwort
```

## Einordnung zu Caddy

Caddy ist der Webserver und Reverse Proxy auf `artserver`. Er ist für öffentliche Webzugriffe wie `arkons.ch`, RoboWait oder Arzttarif zuständig.

Portainer muss nicht zwingend über Caddy laufen. Für den Anfang ist der direkte interne Zugriff auf Port `9443` einfacher und weniger fehleranfällig.

Portainer sollte nicht unüberlegt öffentlich ins Internet gestellt werden. Wenn später ein schöner Name oder HTTPS über Caddy gewünscht ist, dann erst bewusst mit Zugriffsschutz planen.
