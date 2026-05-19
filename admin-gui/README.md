# Arkons Admin Web-GUI

Dies ist der erste funktionsfähige Prototyp der grafischen Administrationsoberfläche. Sie liest:

- `artserver-apps.json`
- `artserver-script-catalog.json`

und zeigt daraus Anwendungen, Bereiche, Skripte, Risiken und Hilfetexte. Serverseitig freigegebene Skripte können über den Runner gestartet werden. Der Runner akzeptiert keine freien Shell-Befehle, sondern nur bekannte Skript-IDs aus dem Katalog.

## Lokal starten

```powershell
cd C:\Users\beata\OneDrive\Dokumente\Private_Projekte\artserver
python admin-gui\app.py --host 127.0.0.1 --port 18110
```

Dann öffnen:

```text
http://127.0.0.1:18110/
```

## Auf artserver starten

```bash
cd /home/art/arkons/deploy/artserver
python3 admin-gui/app.py --host 127.0.0.1 --port 18010
```

Empfohlener Betrieb auf artserver: als normaler systemd-Dienst `arkons-admin-web`, nicht als Container. Der Dienst bindet intern an `127.0.0.1:18010`; der Zugriff von anderen Geräten soll nur über LAN/VPN erfolgen.

Nach erfolgreichem Deploy ist die Weboberfläche im LAN/VPN erreichbar unter:

```text
http://192.168.1.136:18110/
```

## Admin-GUI veröffentlichen

Vom Entwicklungsrechner:

```powershell
.\publish-admin-gui.cmd -CommitMessage "Admin-GUI aktualisieren"
```

Einmalig, damit der Web-Start ohne sudo-Passwort funktionieren kann:

```powershell
.\publish-admin-gui.cmd -CommitMessage "Admin-GUI sudo-Helfer installieren" -InstallSudoHelper
```

Aus der lokalen Weboberfläche:

```text
artserver -> Admin-GUI nach GitHub pushen und auf artserver installieren
```

Der Web-Start nutzt den Schutzbegriff `ADMINGUI`. Er fragt bewusst kein sudo-Passwort ab. Stattdessen wird auf artserver einmalig ein root-eigener Helfer eingerichtet, der nur den Dienst `arkons-admin-web` und die interne Caddy-Route aktualisieren darf.

## Aktueller Funktionsumfang

- Übersicht über Website, artserver, Arzttarif, Menüplan und RoboWait
- Detailseiten pro Bereich
- Skripte als Untermenü direkt unter der jeweiligen Anwendung
- im Hauptbereich immer nur der aktuell gewählte Menüpunkt mit Hilfetext und Startknopf
- ausführlicher Hilfetext direkt beim Skript
- ein gemeinsamer Bearbeiten-Modus pro Seite: `Texte bearbeiten`, danach direkt im sichtbaren Text ändern, dann an derselben Stelle `Speichern` oder `Abbrechen`
- technische Ausführung einblendbar
- Runner-Befehl sichtbar
- Start und Dry-run für freigegebene artserver-Skripte
- Schutzwort-Eingabe bei riskanteren Aktionen
- Publish-Deploy per GitHub mit einmaligem sudo-Helfer für den Browser-Start
- Deploy-Ausgabe zeigt am Schluss die interne Adresse und die LAN/VPN-URL

Noch nicht enthalten:

- Login
- echte Statuschecks
- dauerhafte Jobliste im Browser

Diese Reihenfolge ist Absicht. Zuerst werden Anzeige, Katalog und Runner stabil, danach folgen Login, dauerhafte Logs und der Betrieb als eigener Container.
