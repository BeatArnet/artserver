# arkons.ch

Statische Website fuer Arnet Konsilium. Die Seite ersetzt den bisherigen Websitebaukasten und dient als Informations- und Portal-Seite fuer separate Anwendungen.

## Aenderungen spaeter

Die Website wird aus einfachen Inhaltsdateien erzeugt:

- Texte und Seiten: `content/pages/*.html`
- Navigation, Footer und Basisdaten: `content/site.json`
- Gemeinsames Layout: `templates/base.html`
- Gestaltung: `assets/css/styles.css`
- Bilder und Downloads: `assets/`, `downloads/`

Nach einer Aenderung:

```powershell
python scripts/build.py
```

Das Ergebnis liegt in `dist/` und kann von artserver als statische Website ausgeliefert werden.

## Neue Seite anlegen

1. `content/pages/_template.html` kopieren.
2. `title`, `description` und `path` im Kopf der Datei anpassen.
3. Inhalt im `<main>`-Bereich schreiben.
4. Falls die Seite in die Hauptnavigation soll, einen Eintrag in `content/site.json` unter `nav` ergaenzen.
5. `python scripts/build.py` ausfuehren.

## Seite aendern oder loeschen

- Aendern: passende Datei in `content/pages/` bearbeiten und neu bauen.
- Loeschen: Datei aus `content/pages/` entfernen und den Navigationseintrag aus `content/site.json` entfernen.
- Anwendungen: nur die Startlinks in den Inhaltsdateien anpassen; die Anwendungen selbst sind nicht Teil dieser Website.

## Aktuelle Struktur

- `/` Startseite
- `/apps/` Anwendungsuebersicht
- `/produkte/` Arzttarif-Assistent
- `/Tarifvergleich/` Tarifvergleich und Download
- `/uber-uns/` Profil und Impressum-nahe Informationen
- `/kontakt/` Adresse und Telefon, ohne Mailadresse und ohne Formular
- `/privacy/` Datenschutzhinweise
