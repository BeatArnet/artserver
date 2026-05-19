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

Später soll diese Anwendung in einen eigenen Container `arkons-admin`.

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

Noch nicht enthalten:

- Login
- echte Statuschecks
- dauerhafte Jobliste im Browser
- automatische Rechteprüfung für sudo-Kommandos

Diese Reihenfolge ist Absicht. Zuerst werden Anzeige, Katalog und Runner stabil, danach folgen Login, dauerhafte Logs und der Betrieb als eigener Container.
