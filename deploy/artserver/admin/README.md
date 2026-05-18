# Arkons Admin Runner

Der Admin Runner ist die Ausführungsschicht für die spätere Weboberfläche. Er startet keine frei eingegebenen Shell-Befehle, sondern nur Skript-IDs aus `artserver-script-catalog.json`.

## Befehle

```bash
cd /home/art/arkons/deploy/artserver/admin
bash arkons-admin-runner.sh list
bash arkons-admin-runner.sh show menueplan.backup
bash arkons-admin-runner.sh run menueplan.backup
```

Bei Skripten mit Schutzwort:

```bash
bash arkons-admin-runner.sh run menueplan.update.github --confirm MENUEPLAN
```

Test ohne Ausführung:

```bash
bash arkons-admin-runner.sh run menueplan.update.github --confirm MENUEPLAN --dry-run
```

## Was startbar ist

Ein Skript ist für den Runner nur startbar, wenn alle Bedingungen erfüllt sind:

- `enabled` ist `true`
- `location` ist `artserver`
- `run.type` ist `ServerShell`

Lokale Windows-Skripte und reine Hilfsskripte bleiben im Katalog sichtbar, werden vom Server-Runner aber nicht ausgeführt.

## Logs

Standardpfad:

```text
/home/art/arkons/logs/admin/jobs
```

Pro Start entsteht ein eigenes Log:

```text
20260518-143210-menueplan.update.github.log
```

Der Pfad kann überschrieben werden:

```bash
ARKONS_ADMIN_LOG_DIR=/tmp/arkons-admin-jobs bash arkons-admin-runner.sh run menueplan.backup
```

## Locks

Der Runner verhindert parallele Jobs pro Bereich. Der Bereich wird aus der Skript-ID abgeleitet:

```text
menueplan.update.github -> menueplan
robowait.backup         -> robowait
arzttarif.update.github -> arzttarif
```

Damit können nicht zwei riskante Jobs derselben Anwendung gleichzeitig laufen.

## Rolle im Web-GUI

Das spätere Web-GUI soll nicht direkt `docker`, `sudo`, `git` oder andere Befehle ausführen. Es soll nur eine Skript-ID an den Runner übergeben.

Beispiel:

```text
Benutzer klickt: Menüplan Backup
Web-GUI sendet: menueplan.backup
Runner startet: bash ops/backup.sh
Runner schreibt: Job-Log
Web-GUI zeigt: laufend / erfolgreich / Fehler
```

Das ist bewusst einfacher und sicherer als eine Weboberfläche, die beliebige Befehle starten kann.
