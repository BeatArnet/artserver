# Webseiten-Baukasten für arkons.ch

Die Webseite wird nicht direkt auf `arkons.ch` geändert. Du änderst lokal Dateien, baust daraus den Ordner `dist/` und spielst diesen Stand danach in die Vorschau oder später produktiv auf den Server.

## Die wichtigsten Dateien

- `content/textbausteine.toml`: normale Texte für Startseite, Produktübersicht, RoboWait und Menüplaner.
- `content/site.json`: Name der Webseite, Navigation, Footer-Links und Adresse.
- `content/pages/*.html`: Seitenstruktur. Hier nur arbeiten, wenn ein Abschnitt, ein Button oder ein Bildblock dazukommen soll.
- `assets/css/styles.css`: Gestaltung, Farben, Abstände, Karten, Galerie und Mobilansicht.
- `assets/img/products/`: Produktbilder und Screenshots.
- `scripts/build.py`: Generator. Den musst Du normalerweise nicht ändern.

## Normale Textänderung

1. `content/textbausteine.toml` öffnen.
2. Den passenden Abschnitt suchen, zum Beispiel `[robowait.hero]` oder `[[menueplaner.features]]`.
3. Nur den Text zwischen den Anführungszeichen ändern.
4. Datei speichern.
5. Webseite neu bauen:

```powershell
python scripts/build.py
```

Danach liegt die neu gebaute Seite in `dist/`.

## Was TOML bedeutet

TOML ist eine einfache Textdatei mit Namen und Werten.

Ein kurzer Text sieht so aus:

```toml
lead = "Kurzer Text für die Webseite."
```

Eine Liste sieht so aus:

```toml
points = [
  "Erster Punkt",
  "Zweiter Punkt",
  "Dritter Punkt"
]
```

Wichtig:

- Anführungszeichen stehen lassen.
- Kommas zwischen Listeneinträgen stehen lassen.
- Eckige Klammern bei Listen stehen lassen.
- Keine HTML-Zeichen nötig, wenn Du nur Text änderst.

## Bilder und Screenshots ändern

Neue Bilder kommen nach `assets/img/products/`.

Ein Screenshot in `content/textbausteine.toml` sieht so aus:

```toml
[[robowait.gallery]]
src = "/assets/img/products/robowait-dashboard.png"
alt = "Kurze Bildbeschreibung für Screenreader"
caption = "Bildlegende unter dem Screenshot."
```

Dabei ist wichtig:

- `src` ist der Webpfad, nicht der Windows-Pfad.
- Das Bild muss im Ordner `assets/img/products/` liegen.
- `alt` beschreibt kurz, was auf dem Bild zu sehen ist.
- `caption` ist die sichtbare Bildlegende.

## Neue Seite anlegen

Für eine ganz neue Seite ist `content/pages/_template.html` der Startpunkt. Das ist etwas näher an HTML. Für normale Textpflege brauchst Du diesen Schritt nicht.

## Prüfen

Nach jeder Änderung:

```powershell
python scripts/build.py
```

Wenn der Befehl ohne Fehlermeldung endet, ist die technische Seite zuerst einmal gebaut. Danach lokal anschauen oder mit dem Admin-Menü in die Vorschau auf `artserver` spielen.
