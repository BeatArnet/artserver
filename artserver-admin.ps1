param(
  [switch]$List,
  [switch]$Help,
  [switch]$AssumeConfirmed,
  [string]$Run,
  [string]$ScriptId
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $Utf8NoBom
$OutputEncoding = $Utf8NoBom

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectsRoot = Split-Path -Parent $Root
$MenueplanDeployScript = Join-Path $ProjectsRoot "Menueplan\Deploy-To-Artserver.ps1"
$MenueplanSyncScript = Join-Path $ProjectsRoot "Menueplan\Sync-Data-From-Artserver.ps1"
$MenueplanStartScript = Join-Path $ProjectsRoot "Menueplan\Start_Menüplan.bat"
$ArzttarifDeployScript = Join-Path $ProjectsRoot "Arzttarif_Assistent_dev\scripts\Deploy-Docker-To-Artserver.ps1"
$ArzttarifMergeScript = Join-Path $ProjectsRoot "Arzttarif_Assistent_dev\scripts\git-merge-to-main.ps1"
$ArzttarifCleanupBranchesScript = Join-Path $ProjectsRoot "Arzttarif_Assistent_dev\scripts\cleanup-branches-main.ps1"
$ArzttarifGithubUpdateScript = "/home/art/arkons/deploy/artserver/docker/update-arzttarif-github.sh"
$ScriptCatalogPath = Join-Path $Root "artserver-script-catalog.json"
$RoboWaitRoot = Join-Path $ProjectsRoot "RoboWait"
$RoboWaitAdminScript = Join-Path $RoboWaitRoot "scripts\robowait-admin.cmd"
$Server = "art@artserver"
$PreviewUrl = "http://192.168.1.136/"
$LocalUrl = "http://127.0.0.1:4173/"
$PortainerUrl = "https://192.168.1.136:9443/"

$MenuHelp = @(
  [pscustomobject]@{
    Choice = "1"
    Name = "Website lokal bauen"
    Description = "Erzeugt die statische Website neu aus content/, assets/, downloads/ und templates/. Ergebnis: dist/. Verändert artserver nicht."
    UseWhen = "Nach jeder Inhalts-, Navigations-, CSS-, Bild- oder Download-Änderung."
    Effect = "Nur lokales dist/ wird neu geschrieben."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "2"
    Name = "Website lokal anzeigen"
    Description = "Baut die Website und startet einen lokalen Webserver unter http://127.0.0.1:4173/. Das Fenster offen lassen; mit Ctrl+C beenden."
    UseWhen = "Wenn du die Änderung zuerst auf diesem Windows-Rechner anschauen willst."
    Effect = "Startet lokal Python http.server; artserver bleibt unverändert."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "3"
    Name = "Website nach artserver-Vorschau deployen"
    Description = "Baut die Website, kopiert dist/ als neues Release nach /home/art/arkons/www/releases/ und schaltet /home/art/arkons/www/current um. Caddy wird nicht verändert."
    UseWhen = "Wenn die lokale Änderung in der LAN-Vorschau auf artserver erscheinen soll."
    Effect = "Legt ein neues Release an und schaltet den Symlink current um. Kein sudo, kein Caddy-Reload."
    Risk = "Niedrig bis mittel: betrifft nur die Arkons-Vorschau, nicht Menüplan, RoboWait oder Arzttarif."
  },
  [pscustomobject]@{
    Choice = "4"
    Name = "Arkons-Caddy-Vorschau aktivieren/erneuern"
    Description = "Führt auf artserver das vorbereitete sudo-Skript für /etc/caddy/sites-enabled/arkons-preview.caddy aus. Legt Backups an, validiert Caddy und lädt Caddy neu."
    UseWhen = "Wenn die Vorschau noch nicht aktiv ist oder die Caddy-Vorschaukonfiguration neu geschrieben werden soll."
    Effect = "Schreibt nur arkons-preview.caddy, validiert Caddy und lädt Caddy neu."
    Risk = "Mittel: Caddy wird neu geladen. Das Skript validiert vorher und erstellt Backups."
  },
  [pscustomobject]@{
    Choice = "5"
    Name = "Status prüfen"
    Description = "Prüft die Arkons-Vorschau und die bestehenden Apps Menüplan und RoboWait. Geeignet nach jedem Deployment."
    UseWhen = "Nach Deployments, Caddy-Änderungen oder wenn du schnell wissen willst, ob alles noch antwortet."
    Effect = "Macht HTTP-Checks und SSH-Checks, verändert nichts."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "6"
    Name = "Vorschau im Browser öffnen"
    Description = "Öffnet http://192.168.1.136/ im Standardbrowser. Die Anzeige 'Nicht sicher' ist bei dieser HTTP-LAN-Vorschau normal."
    UseWhen = "Wenn du die aktuelle Vorschau auf artserver im Browser ansehen willst."
    Effect = "Öffnet nur den Browser."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "7"
    Name = "SSH-Shell zu artserver"
    Description = "Öffnet eine interaktive SSH-Sitzung als art@artserver. Nur für manuelle Prüfungen oder gezielte Serverarbeiten."
    UseWhen = "Wenn du direkt auf dem Server arbeiten oder etwas nachsehen willst."
    Effect = "Interaktive Shell; was danach passiert, hängt von deinen Befehlen ab."
    Risk = "Abhängig von den manuell eingegebenen Befehlen"
  },
  [pscustomobject]@{
    Choice = "8"
    Name = "Dienste und Container anzeigen"
    Description = "Zeigt Status von Caddy, Docker, RoboWait, PHP-FPM und den Docker-Containern. Verändert nichts."
    UseWhen = "Wenn eine App nicht erreichbar ist oder nach einem Update geprüft werden soll."
    Effect = "Liest systemd- und Docker-Status, verändert nichts."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "9"
    Name = "Menüplan Smoke-Test starten"
    Description = "Startet den Docker-Smoke-Test des Menüplans auf artserver."
    UseWhen = "Wenn der Menüplan nach Update, Caddy-Änderung oder Docker-Neustart geprüft werden soll."
    Effect = "Prüft Docker-Endpunkt, Startseite und blockierte Datenpfade."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "10"
    Name = "Menüplan Backup starten"
    Description = "Startet das vorhandene Backup-Skript der Menüplan-App. Verändert die Arkons-Website nicht."
    UseWhen = "Vor Wartungsarbeiten am Menüplan oder als manuelles Zusatzbackup."
    Effect = "Erstellt ein Backup im Menüplan-Backupverzeichnis."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "11"
    Name = "Server-Skripte anzeigen"
    Description = "Listet die bekannten Skripte auf artserver und ordnet sie nach Bereich ein. Verändert nichts."
    UseWhen = "Wenn du wissen willst, welche Wartungsskripte auf artserver vorhanden sind."
    Effect = "Liest Dateiliste und zeigt Einordnung."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "12"
    Name = "artserver Systemupdate starten"
    Description = "Startet /home/art/scripts/update_artserver.sh. Das Skript macht apt full-upgrade, Backups, Dienstneustarts und kann bei Bedarf nach 10 Sekunden rebooten. Nur bewusst ausführen."
    UseWhen = "Nur in einem Wartungsfenster, wenn ein Serverupdate wirklich gewünscht ist."
    Effect = "Aktualisiert Ubuntu-Pakete, startet Dienste neu und kann den Server neu starten."
    Risk = "Hoch: Schutzabfrage UPDATE erforderlich."
  },
  [pscustomobject]@{
    Choice = "26"
    Name = "Systemupdate, Neustart und Kontrolle"
    Description = "Startet das artserver-Systemupdate, löst danach bewusst einen frischen Neustart aus, wartet auf SSH und prüft Dienste, Docker, Portainer und Web-Endpunkte."
    UseWhen = "Wenn nach Sicherheitsupdates sicher alles mit neuem Kernel und frisch gestarteten Services laufen soll."
    Effect = "Aktualisiert Pakete, startet den Server neu und führt anschliessend eine Kontrollrunde aus."
    Risk = "Hoch: Schutzabfrage FRISCHSTART erforderlich. Während des Neustarts sind Website und Apps kurz nicht erreichbar."
  },
  [pscustomobject]@{
    Choice = "13"
    Name = "Borg Restore Assistent starten"
    Description = "Startet /home/art/scripts/borg-restore-guided.sh interaktiv mit sudo. Restore kann Daten überschreiben; das Skript fragt mehrfach nach."
    UseWhen = "Nur wenn gezielt Daten aus Borg wiederhergestellt werden sollen."
    Effect = "Startet einen interaktiven Restore-Assistenten auf artserver."
    Risk = "Hoch: Schutzabfrage RESTORE erforderlich."
  },
  [pscustomobject]@{
    Choice = "17"
    Name = "RoboWait Backup starten"
    Description = "Startet das RoboWait-Backup-Skript für SQLite, Uploads, Exporte und Mail-Template-Bilder."
    UseWhen = "Vor RoboWait-Wartungsarbeiten oder als manuelles Zusatzbackup."
    Effect = "Erstellt ein RoboWait-Backup unter /opt/apps/robowait/backup."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "18"
    Name = "RoboWait Update starten"
    Description = "Startet /opt/apps/robowait/scripts/update-artserver.sh mit sudo. Aktualisiert Code und Abhängigkeiten und kann Dienste neu starten. Nur bewusst ausführen."
    UseWhen = "Nur in einem RoboWait-Wartungsfenster."
    Effect = "Aktualisiert RoboWait und startet betroffene Dienste neu."
    Risk = "Hoch: Schutzabfrage ROBOWAIT erforderlich."
  },
  [pscustomobject]@{
    Choice = "19"
    Name = "artserver-Zentrale einrichten/aktualisieren"
    Description = "Erstellt oder aktualisiert /home/art/artserver-hub mit Verweisen auf Dokumente, Skripte, Caddy, systemd und Inventarlisten."
    UseWhen = "Wenn du alle wichtigen Serverunterlagen zentral auffindbar machen willst."
    Effect = "Schreibt nur unter /home/art/artserver-hub. Produktive App-Dateien werden nicht verändert."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "20"
    Name = "artserver-Zentrale anzeigen"
    Description = "Zeigt die README und die Verweise der Zentrale /home/art/artserver-hub an."
    UseWhen = "Wenn du wissen willst, wo Dokumente und Skripte auf artserver zentral erreichbar sind."
    Effect = "Liest Dateien und Verweise, verändert nichts."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "21"
    Name = "Server-Dokumente anzeigen"
    Description = "Listet Markdown-, Text- und Word-Dokumente der bekannten Projekte auf artserver."
    UseWhen = "Wenn du vorhandene Dokumentation, Handbücher und Notizen suchen willst."
    Effect = "Liest Dateilisten, verändert nichts."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "22"
    Name = "Aufräumkandidaten anzeigen"
    Description = "Zeigt temporäre Dateien, alte Logs, lose Backups und Caddy-Backups, die später geprüft oder archiviert werden können."
    UseWhen = "Vor dem Löschen oder Archivieren, damit zuerst klar ist, was betroffen wäre."
    Effect = "Liest Dateilisten und Grössen, löscht nichts."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "32"
    Name = "Skripte ordnen und Altlasten archivieren"
    Description = "Archiviert klar veraltete Skripte und alte temporäre RoboWait-Artefakte in Zeitstempel-Archive. Löscht nichts."
    UseWhen = "Wenn die Skriptlandschaft auf artserver aufgeräumt werden soll, ohne produktive Wartungsskripte anzufassen."
    Effect = "Verschiebt alte temporäre Dateien und einen historischen Beispielinstaller in Archive und schreibt einen Bericht in /home/art/artserver-hub."
    Risk = "Mittel: Es wird verschoben, aber nicht gelöscht. Schutzabfrage SKRIPTORDNUNG erforderlich."
  },
  [pscustomobject]@{
    Choice = "34"
    Name = "Zentralen Skriptkatalog anzeigen"
    Description = "Liest artserver-script-catalog.json und zeigt alle bekannten Skripte aus Menüplan, RoboWait und Arzttarif mit ID, Ort, Risiko und Startstatus."
    UseWhen = "Wenn du wissen willst, welche Skripte zentral bekannt sind und welche davon direkt gestartet werden können."
    Effect = "Liest nur den lokalen Katalog, verändert nichts."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "35"
    Name = "Skript aus zentralem Katalog starten"
    Description = "Startet ein im Skriptkatalog freigegebenes Skript über seine ID. Schutzabfragen aus dem Katalog werden vor dem Start verlangt."
    UseWhen = "Wenn du ein Skript gezielt aus dem zentralen Katalog starten willst."
    Effect = "Je nach Skript lokal oder per SSH auf artserver. Der Katalog zeigt Ort und Risiko vorher an."
    Risk = "Abhängig vom ausgewählten Skript."
  },
  [pscustomobject]@{
    Choice = "23"
    Name = "Docker und Portainer Status anzeigen"
    Description = "Zeigt Docker-Version, Docker-Container, Volumes und den Portainer-Status. Docker-Abfragen brauchen auf artserver meist sudo."
    UseWhen = "Wenn du sehen willst, welche Container laufen oder ob Portainer installiert ist."
    Effect = "Liest Docker-Status, verändert nichts."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "24"
    Name = "Portainer im Browser öffnen"
    Description = "Öffnet die Portainer-Weboberfläche unter https://192.168.1.136:9443/."
    UseWhen = "Wenn Portainer bereits installiert ist und du Docker im Browser verwalten willst."
    Effect = "Öffnet nur den Browser."
    Risk = "Niedrig"
  },
  [pscustomobject]@{
    Choice = "25"
    Name = "Portainer installieren/aktualisieren"
    Description = "Installiert oder erneuert Portainer CE als Docker-Container mit persistentem Volume portainer_data und HTTPS auf Port 9443."
    UseWhen = "Wenn die Docker-Weboberfläche auf artserver eingerichtet oder aktualisiert werden soll."
    Effect = "Erstellt/aktualisiert Docker-Volume und Container portainer. Port 9443 wird im LAN erreichbar."
    Risk = "Mittel bis hoch: Portainer kann Docker steuern. Schutzabfrage PORTAINER erforderlich."
  },
  [pscustomobject]@{
    Choice = "31"
    Name = "Portainer Admin-Passwort zurücksetzen"
    Description = "Zeigt die getesteten Befehle, mit denen das Portainer-Admin-Passwort im bestehenden Volume portainer_data zurückgesetzt wird."
    UseWhen = "Wenn Portainer schon eine Login-Seite zeigt, aber kein Admin-Konto oder Passwort bekannt ist."
    Effect = "Verändert selbst nichts. Die angezeigten Befehle müssen in Menüpunkt 7 oder einer SSH-Shell ausgeführt werden."
    Risk = "Niedrig im Menü. Die manuell ausgeführten Befehle stoppen Portainer kurz und ändern das Admin-Passwort."
  },
  [pscustomobject]@{
    Choice = "27"
    Name = "Menüplan Docker-Update aus GitHub"
    Description = "Ruft das Menüplan-Unterskript auf. Es holt den neuesten GitHub-Stand nach /opt/apps/Menueplan, startet den Docker-Container neu und führt den Smoke-Test aus."
    UseWhen = "Wenn der produktive Menüplan auf den neuesten GitHub-Stand gebracht werden soll."
    Effect = "Aktualisiert Menüplan-Code, lässt data/.env/Zertifikat unberührt, startet den Container neu."
    Risk = "Mittel: App-Update mit Container-Neustart. Schutzabfrage MENUEPLAN erforderlich."
  },
  [pscustomobject]@{
    Choice = "28"
    Name = "Arzttarif Docker-Deploy vom Entwicklungsordner"
    Description = "Ruft das Arzttarif-Unterskript auf. Es packt den lokalen Entwicklungsordner, kopiert ihn nach artserver und startet den Docker-Container neu."
    UseWhen = "Wenn der aktuelle Entwicklungsstand des Arzttarif-Assistenten produktiv getestet oder ausgerollt werden soll."
    Effect = "Aktualisiert /opt/apps/Arzttarif ohne Logs, Env und Docker-Cache zu überschreiben; baut das Image nur bei geänderten requirements neu."
    Risk = "Mittel bis hoch: App-Update direkt vom Entwicklungsrechner. Schutzabfrage ARZTTARIF erforderlich."
  },
  [pscustomobject]@{
    Choice = "33"
    Name = "Arzttarif Docker-Update aus GitHub"
    Description = "Holt den neuesten GitHub-Stand nach /opt/apps/Arzttarif, aktualisiert bei geänderten Abhängigkeiten das Docker-Image, startet den Container neu und führt den Smoke-Test aus."
    UseWhen = "Wenn der produktive Arzttarif-Assistent aus GitHub aktualisiert werden soll."
    Effect = "Aktualisiert /opt/apps/Arzttarif ohne Logs, Env und Docker-Cache zu überschreiben; startet den Docker-Container neu."
    Risk = "Mittel: App-Update mit Container-Neustart. Schutzabfrage ARZTTARIFGITHUB erforderlich."
  },
  [pscustomobject]@{
    Choice = "29"
    Name = "RoboWait Docker-Prototyp starten"
    Description = "Startet den RoboWait-Docker-Prototyp auf artserver mit Web, Reverb und Scheduler parallel zu den alten systemd-Diensten."
    UseWhen = "Wenn RoboWait im Container gebaut und auf 127.0.0.1:18002/18003 getestet werden soll."
    Effect = "Baut das RoboWait-Image, startet drei Container und führt den Docker-Smoke-Test aus. Caddy wird nicht umgeschaltet."
    Risk = "Mittel: Container-Build und App-Start mit produktiver .env und Datenbank, aber ohne öffentliche Umschaltung. Schutzabfrage ROBOWAITDOCKER erforderlich."
  },
  [pscustomobject]@{
    Choice = "30"
    Name = "RoboWait Docker-Smoke-Test"
    Description = "Prüft den bereits laufenden RoboWait-Docker-Prototyp auf artserver."
    UseWhen = "Nach Docker-Start, Update oder Neustart von RoboWait."
    Effect = "Prüft Web auf 127.0.0.1:18002 und Reverb auf 127.0.0.1:18003."
    Risk = "Niedrig"
  }
)

$MenuGroups = @(
  "Website",
  "Server allgemein",
  "Menüplan",
  "RoboWait",
  "Zentrale",
  "Docker"
)

foreach ($item in $MenuHelp) {
  $group = switch ($item.Choice) {
    { $_ -in @("1", "2", "3", "4", "5", "6") } { "Website"; break }
    { $_ -in @("7", "8", "11", "12", "13", "26") } { "Server allgemein"; break }
    { $_ -in @("9", "10") } { "Menüplan"; break }
    { $_ -in @("17", "18") } { "RoboWait"; break }
    { $_ -in @("19", "20", "21", "22", "32", "34", "35") } { "Zentrale"; break }
    { $_ -in @("23", "24", "25", "27", "28", "29", "30", "31", "33") } { "Docker"; break }
    default { "Weitere" }
  }
  $item | Add-Member -NotePropertyName Group -NotePropertyValue $group
}

function Write-Title {
  param([string]$Text)
  Write-Host ""
  Write-Host "== $Text ==" -ForegroundColor Cyan
}

function Pause-Menu {
  Write-Host ""
  Read-Host "Enter drücken für das Menü"
}

function Invoke-Checked {
  param(
    [string]$Program,
    [string[]]$Arguments,
    [string]$WorkingDirectory = $Root
  )

  Push-Location $WorkingDirectory
  try {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "$Program wurde mit Exitcode $LASTEXITCODE beendet."
    }
  } finally {
    Pop-Location
  }
}

function Invoke-RemoteBash {
  param([string]$Script)

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "ssh"
  $psi.Arguments = "-T $Server bash -s"
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8NoBom
  $psi.StandardErrorEncoding = $Utf8NoBom
  $psi.CreateNoWindow = $true
  $standardInputEncodingProperty = $psi.GetType().GetProperty("StandardInputEncoding")
  if ($standardInputEncodingProperty) {
    $standardInputEncodingProperty.SetValue($psi, $Utf8NoBom, $null)
  }

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $psi
  [void]$process.Start()
  $process.StandardInput.Write(($Script -replace "`r", "") + "`n")
  $process.StandardInput.Close()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()

  if ($stdout) {
    Write-Host ($stdout.TrimEnd())
  }
  if ($stderr) {
    Write-Host ($stderr.TrimEnd()) -ForegroundColor Yellow
  }
  if ($process.ExitCode -ne 0) {
    throw "Remote-Bash wurde mit Exitcode $($process.ExitCode) beendet."
  }
}

function Invoke-RemoteBashFile {
  param([string]$Path)

  Get-Content -LiteralPath $Path -Raw | & ssh $Server "tr -d '\r' | bash -s"
  if ($LASTEXITCODE -ne 0) {
    throw "Remote-Bash-Datei wurde mit Exitcode $LASTEXITCODE beendet: $Path"
  }
}

function Build-Website {
  Write-Title "Website bauen"
  Invoke-Checked "python" @("scripts/build.py")
}

function Start-LocalPreview {
  Build-Website
  Write-Title "Lokale Vorschau"
  Write-Host "Öffne $LocalUrl"
  Start-Process $LocalUrl
  Write-Host "Der lokale Webserver läuft, bis dieses Fenster mit Ctrl+C beendet wird."
  Invoke-Checked "python" @("-m", "http.server", "4173", "--directory", "dist")
}

function Deploy-ArtserverPreview {
  Build-Website
  Write-Title "Website nach artserver kopieren"

  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $zip = Join-Path ([System.IO.Path]::GetTempPath()) "arkons-dist-$stamp.zip"

  if (Test-Path $zip) {
    Remove-Item $zip -Force
  }

  try {
    Compress-Archive -Path (Join-Path $Root "dist\*") -DestinationPath $zip -Force
    Invoke-Checked "ssh" @($Server, "mkdir -p /home/art/arkons/www/releases/$stamp")
    Invoke-Checked "scp" @($zip, "$Server`:/home/art/arkons/www/releases/$stamp/dist.zip")
    Invoke-Checked "ssh" @(
      $Server,
      "cd /home/art/arkons/www/releases/$stamp && unzip -q dist.zip && rm dist.zip && find . -type d -exec chmod 755 {} \; && find . -type f -exec chmod 644 {} \; && ln -sfn /home/art/arkons/www/releases/$stamp /home/art/arkons/www/current && test -f /home/art/arkons/www/current/index.html && echo $stamp"
    )
  } finally {
    if (Test-Path $zip) {
      Remove-Item $zip -Force
    }
  }

  Write-Host ""
  Write-Host "Aktualisiert. Vorschau: $PreviewUrl" -ForegroundColor Green
}

function Enable-ArkonsPreview {
  Write-Title "Caddy-Vorschau aktivieren"
  Write-Host "Dieser Schritt fragt nach dem sudo-Passwort auf artserver."
  Write-Host "Er schreibt nur /etc/caddy/sites-enabled/arkons-preview.caddy und lädt Caddy nach erfolgreicher Validierung neu."
  Invoke-Checked "ssh" @("-t", $Server, "sudo bash /home/art/arkons/deploy/apply-arkons-preview.sh")
}

function Show-Status {
  Write-Title "Status Arkons-Vorschau"
  Invoke-Checked "curl.exe" @("-I", "--max-time", "8", $PreviewUrl)

  Write-Title "Status bestehende Apps auf artserver"
  Invoke-Checked "ssh" @(
    $Server,
    "systemctl is-active caddy; echo '--- menueplan'; curl -kI --max-time 8 --resolve arnet.internet-box.ch:443:127.0.0.1 https://arnet.internet-box.ch/ | sed -n '1,8p'; echo '--- robowait'; curl -kI --max-time 8 --resolve robowait.arkons.ch:443:127.0.0.1 https://robowait.arkons.ch/ | sed -n '1,8p'; echo '--- arkons preview'; curl -I --max-time 8 -H 'Host: arkons.ch' http://127.0.0.1/ | sed -n '1,8p'"
  )
}

function Open-ArtserverShell {
  Write-Title "SSH-Shell artserver"
  Write-Host "Öffne ein eigenes SSH-Fenster. Mit 'exit' kommst du dort wieder heraus."
  Start-Process "cmd.exe" -ArgumentList @(
    "/k",
    "title artserver SSH && ssh -tt $Server"
  )
}

function Show-ServiceStatus {
  Write-Title "Dienste und Container"
  Invoke-RemoteBash @'
for svc in caddy docker php8.3-fpm robowait-web robowait-reverb robowait-scheduler; do
  if systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | grep -q .; then
    printf "%-24s active=%-12s enabled=%s\n" "$svc" "$(systemctl is-active "$svc" 2>/dev/null)" "$(systemctl is-enabled "$svc" 2>/dev/null)"
  fi
done
echo "--- docker"
(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || sudo -n docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker-Containerliste braucht sudo-Passwort.")
'@
  $output = & ssh -n $Server $remote 2>&1
  $exitCode = $LASTEXITCODE
  if ($output) {
    $output | ForEach-Object { Write-Host $_ }
  } else {
    Write-Host "Keine SSH-Ausgabe erhalten." -ForegroundColor Yellow
    Write-Host "Prüfe bei Bedarf Menüpunkt 7 oder direkt: ssh $Server `"echo SSH_OK`""
  }
  if ($exitCode -ne 0) {
    throw "ssh wurde mit Exitcode $exitCode beendet."
  }
}

function Run-MenueplanDoctor {
  Write-Title "Menüplan Smoke-Test"
  Invoke-Checked "ssh" @($Server, "cd /home/art/arkons/deploy/artserver/docker && bash smoke-menueplan.sh")
}

function Run-MenueplanBackup {
  Write-Title "Menüplan Backup"
  Invoke-Checked "ssh" @($Server, "cd /opt/apps/Menueplan && bash ops/backup.sh")
}

function Run-MenueplanDockerUpdate {
  Write-Title "Menüplan Docker-Update aus GitHub"
  if (-not (Test-Path -LiteralPath $MenueplanDeployScript -PathType Leaf)) {
    throw "Menüplan-Deploy-Skript nicht gefunden: $MenueplanDeployScript"
  }
  Write-Host "Aktualisiert den produktiven Menüplan und startet den Docker-Container neu." -ForegroundColor Yellow
  if (-not (Confirm-DangerousAction "Nur starten, wenn ein kurzer Menüplan-Neustart möglich ist." "MENUEPLAN")) {
    Write-Host "Abgebrochen."
    return
  }

  & $MenueplanDeployScript -ServerAddress "artserver" -SshUserName "art" -NoPause
  if ($LASTEXITCODE -ne 0) {
    throw "Menüplan-Docker-Update fehlgeschlagen."
  }
}

function Run-ArzttarifDockerDeploy {
  Write-Title "Arzttarif Docker-Deploy vom Entwicklungsordner"
  if (-not (Test-Path -LiteralPath $ArzttarifDeployScript -PathType Leaf)) {
    throw "Arzttarif-Deploy-Skript nicht gefunden: $ArzttarifDeployScript"
  }
  Write-Host "Überträgt den lokalen Entwicklungsstand nach artserver und startet den Arzttarif-Container neu." -ForegroundColor Yellow
  if (-not (Confirm-DangerousAction "Nur starten, wenn der lokale Entwicklungsstand produktiv ausgerollt werden soll." "ARZTTARIF")) {
    Write-Host "Abgebrochen."
    return
  }

  & $ArzttarifDeployScript -ServerAddress "artserver" -SshUserName "art"
  if ($LASTEXITCODE -ne 0) {
    throw "Arzttarif-Docker-Deploy fehlgeschlagen."
  }
}

function Run-ArzttarifDockerGithubUpdate {
  Write-Title "Arzttarif Docker-Update aus GitHub"
  Write-Host "Holt den neuesten GitHub-Stand nach /opt/apps/Arzttarif und startet den Arzttarif-Container neu." -ForegroundColor Yellow
  Write-Host "Der Entwicklungsordner auf diesem Windows-Rechner wird dabei nicht verwendet." -ForegroundColor Yellow
  if (-not (Confirm-DangerousAction "Nur starten, wenn ein kurzer Arzttarif-Neustart möglich ist." "ARZTTARIFGITHUB")) {
    Write-Host "Abgebrochen."
    return
  }

  Invoke-Checked "ssh" @(
    "-t",
    $Server,
    "cd /home/art/arkons/deploy/artserver/docker && sudo bash $ArzttarifGithubUpdateScript"
  )
}

function Run-RoboWaitDockerPrototype {
  Write-Title "RoboWait Docker-Prototyp starten"
  Write-Host "Baut und startet RoboWait im Container auf 127.0.0.1:18002/18003. Caddy bleibt unverändert." -ForegroundColor Yellow
  if (-not (Confirm-DangerousAction "Nur starten, wenn ein RoboWait-Containerstart auf artserver jetzt passt." "ROBOWAITDOCKER")) {
    Write-Host "Abgebrochen."
    return
  }

  Invoke-Checked "ssh" @(
    "-t",
    $Server,
    "cd /opt/apps/robowait && sudo docker compose -f deploy/docker-compose.yml build && sudo docker compose -f deploy/docker-compose.yml up -d && bash scripts/smoke-docker.sh"
  )
}

function Run-RoboWaitDockerSmoke {
  Write-Title "RoboWait Docker-Smoke-Test"
  Invoke-Checked "ssh" @($Server, "cd /opt/apps/robowait && bash scripts/smoke-docker.sh")
}

function Confirm-DangerousAction {
  param(
    [string]$Prompt,
    [string]$Expected
  )

  if ($AssumeConfirmed) {
    Write-Host "Schutzabfrage wurde durch den Web-Runner vorab bestätigt: $Expected" -ForegroundColor Yellow
    return $true
  }

  Write-Host ""
  Write-Host $Prompt -ForegroundColor Yellow
  $answer = Read-Host "Zum Fortfahren '$Expected' eingeben"
  return $answer -eq $Expected
}

function Expand-CatalogValue {
  param([string]$Value)

  if ($null -eq $Value) {
    return $null
  }

  return $Value.Replace("{Root}", $Root).Replace("{ProjectsRoot}", $ProjectsRoot)
}

function Get-ScriptCatalogEntries {
  if (-not (Test-Path -LiteralPath $ScriptCatalogPath -PathType Leaf)) {
    throw "Skriptkatalog nicht gefunden: $ScriptCatalogPath"
  }

  $catalog = Get-Content -LiteralPath $ScriptCatalogPath -Raw | ConvertFrom-Json
  return @($catalog.scripts)
}

function Show-ScriptCatalog {
  Write-Title "Zentraler Skriptkatalog"
  Write-Host "Katalogdatei: $ScriptCatalogPath"
  Write-Host "Diese Liste ist die Basis für das heutige Konsolenmenü und später für eine Weboberfläche."
  Write-Host ""

  $entries = Get-ScriptCatalogEntries | Sort-Object group, label
  foreach ($group in ($entries | Group-Object group)) {
    Write-Host $group.Name -ForegroundColor Cyan
    foreach ($entry in $group.Group) {
      $status = if ($entry.enabled) { "startbar" } else { "nur dokumentiert" }
      $token = if ($entry.requiresConfirmation) { "Schutz: $($entry.requiresConfirmation)" } else { "ohne Schutzwort" }
      Write-Host "  $($entry.id)" -ForegroundColor Yellow
      Write-Host "    $($entry.label)"
      Write-Host "    Ort: $($entry.location); Risiko: $($entry.risk); Status: $status; $token"
      Write-Host "    Quelle: $($entry.source)"
      if ($entry.notes) {
        Write-Host "    Hinweis: $($entry.notes)"
      }
    }
    Write-Host ""
  }
}

function Confirm-CatalogScriptIfNeeded {
  param($Entry)

  if (-not $Entry.requiresConfirmation) {
    return $true
  }

  return Confirm-DangerousAction "Skript '$($Entry.label)' starten? Risiko: $($Entry.risk)." $Entry.requiresConfirmation
}

function Invoke-LocalPowerShellCatalogScript {
  param($Entry)

  $scriptPath = Expand-CatalogValue $Entry.run.path
  $workingDirectory = Expand-CatalogValue $Entry.run.cwd
  $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath)
  if ($Entry.run.args) {
    $arguments += @($Entry.run.args | ForEach-Object { Expand-CatalogValue $_ })
  }

  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Lokales Skript nicht gefunden: $scriptPath"
  }

  $powerShellCommand = Get-Command pwsh -ErrorAction SilentlyContinue
  if (-not $powerShellCommand) {
    $powerShellCommand = Get-Command powershell -ErrorAction Stop
  }

  Invoke-Checked $powerShellCommand.Source $arguments $workingDirectory
}

function Invoke-LocalCommandCatalogScript {
  param($Entry)

  $program = Expand-CatalogValue $Entry.run.path
  $workingDirectory = Expand-CatalogValue $Entry.run.cwd
  $arguments = @()
  if ($Entry.run.args) {
    $arguments += @($Entry.run.args | ForEach-Object { Expand-CatalogValue $_ })
  }

  $extension = [System.IO.Path]::GetExtension($program).ToLowerInvariant()
  if ($extension -in @(".bat", ".cmd")) {
    if (-not (Test-Path -LiteralPath $program -PathType Leaf)) {
      throw "Lokales Skript nicht gefunden: $program"
    }
    Invoke-Checked "cmd.exe" (@("/c", $program) + $arguments) $workingDirectory
    return
  }

  Invoke-Checked $program $arguments $workingDirectory
}

function Invoke-ServerShellCatalogScript {
  param($Entry)

  $cwd = Expand-CatalogValue $Entry.run.cwd
  $command = Expand-CatalogValue $Entry.run.command
  $escapedCwd = $cwd.Replace("'", "'\''")
  $remoteCommand = "cd '$escapedCwd' && $command"
  Invoke-Checked "ssh" @("-t", $Server, $remoteCommand)
}

function Invoke-ScriptCatalogEntry {
  param([string]$Id)

  $entries = Get-ScriptCatalogEntries
  $entry = $entries | Where-Object { $_.id -eq $Id } | Select-Object -First 1
  if (-not $entry) {
    throw "Keine Skript-ID im Katalog gefunden: $Id"
  }

  Write-Title "Skript starten: $($entry.label)"
  Write-Host "ID: $($entry.id)"
  Write-Host "Ort: $($entry.location)"
  Write-Host "Quelle: $($entry.source)"
  Write-Host "Risiko: $($entry.risk)"
  if ($entry.notes) {
    Write-Host "Hinweis: $($entry.notes)"
  }

  if (-not $entry.enabled) {
    Write-Host "Dieses Skript ist im Katalog bewusst nicht direkt startbar." -ForegroundColor Yellow
    return
  }

  switch ($entry.run.type) {
    "AdminFunction" {
      $command = Get-Command $entry.run.function -ErrorAction Stop
      & $command
      break
    }
    "LocalPowerShell" {
      if (-not (Confirm-CatalogScriptIfNeeded $entry)) {
        Write-Host "Abgebrochen."
        return
      }
      Invoke-LocalPowerShellCatalogScript $entry
      break
    }
    "LocalCommand" {
      if (-not (Confirm-CatalogScriptIfNeeded $entry)) {
        Write-Host "Abgebrochen."
        return
      }
      Invoke-LocalCommandCatalogScript $entry
      break
    }
    "ServerShell" {
      if (-not (Confirm-CatalogScriptIfNeeded $entry)) {
        Write-Host "Abgebrochen."
        return
      }
      Invoke-ServerShellCatalogScript $entry
      break
    }
    default {
      throw "Unbekannter Katalog-Run-Typ: $($entry.run.type)"
    }
  }
}

function Start-ScriptFromCatalog {
  Show-ScriptCatalog
  $id = Read-Host "Skript-ID eingeben"
  if ([string]::IsNullOrWhiteSpace($id)) {
    Write-Host "Keine ID eingegeben."
    return
  }

  Invoke-ScriptCatalogEntry $id.Trim()
}

function Write-AdminEntrypoint {
  param(
    [string]$Label,
    [string]$Path,
    [string]$Purpose
  )

  $exists = Test-Path -LiteralPath $Path -PathType Leaf
  $status = if ($exists) { "OK" } else { "FEHLT" }
  $color = if ($exists) { "Green" } else { "Red" }
  Write-Host "  [$status] $Label" -ForegroundColor $color
  Write-Host "       $Path"
  Write-Host "       $Purpose" -ForegroundColor DarkGray
}

function Show-ProjectAdminEntrypoints {
  Write-Title "Projekt-Admin-Einstiege"
  Write-Host "Diese Übersicht referenziert die lokalen Startpunkte der einzelnen Projekte."
  Write-Host "Sie ist bewusst eine Karte: Starten kannst du vieles zusätzlich über Menüpunkt 34/35 im Skriptkatalog."
  Write-Host ""

  Write-Host "Zentrale Kommandozentrale" -ForegroundColor Cyan
  Write-AdminEntrypoint "artserver Admin-Menü" (Join-Path $Root "artserver-admin.cmd") "Startseite für artserver, Website, Caddy, Docker, Backups und zentrale Checks."
  Write-Host ""

  Write-Host "Website / artserver" -ForegroundColor Cyan
  Write-AdminEntrypoint "Website lokal starten" (Join-Path $Root "start-webseite.cmd") "Lokale Website-Vorschau für arkons.ch."
  Write-Host ""

  Write-Host "Menüplan" -ForegroundColor Cyan
  Write-AdminEntrypoint "Menüplan Docker-Deploy" $MenueplanDeployScript "Produktiven Menüplan auf artserver aktualisieren."
  Write-AdminEntrypoint "Menüplan Daten-Sync" $MenueplanSyncScript "Produktive Menüplan-Daten auf den Entwicklungsrechner holen."
  Write-AdminEntrypoint "Menüplan lokal starten" $MenueplanStartScript "Lokale Menüplan-Entwicklungsumgebung starten."
  Write-Host ""

  Write-Host "RoboWait" -ForegroundColor Cyan
  Write-AdminEntrypoint "RoboWait Admin-Menü" $RoboWaitAdminScript "Anwendungsspezifische RoboWait-Verwaltung, Logs, Zielsystem, Docs, Roboter."
  Write-Host ""

  Write-Host "Arzttarif" -ForegroundColor Cyan
  Write-AdminEntrypoint "Arzttarif Docker-Deploy" $ArzttarifDeployScript "Lokalen Entwicklungsstand nach artserver übertragen."
  Write-AdminEntrypoint "Arzttarif Branch nach main mergen" $ArzttarifMergeScript "Git-Helfer für den Projektstand."
  Write-AdminEntrypoint "Arzttarif Branches aufräumen" $ArzttarifCleanupBranchesScript "Git-Aufräumhilfe für lokale Branches."
  Write-Host ""

  Write-Host "Hinweis:" -ForegroundColor Yellow
  Write-Host "  Wenn ein Projekt später ein eigenes Admin-Menü bekommt, hier zuerst den Einstieg ergänzen."
}

function Show-ArtserverScripts {
  Write-Title "Skriptübersicht nach Bereich"
  Write-Host "Ausführliche Einordnung: docs/artserver-skriptordnung.md"
  Write-Host "Auf artserver nach Menüpunkt 19 auch unter: /home/art/artserver-hub/artserver-skriptordnung.md"
  Write-Host ""

  Write-Host "Website / arkons.ch"
  Write-Host "  /home/art/arkons/deploy/apply-arkons-preview.sh       Caddy-Vorschau für arkons.ch"
  Write-Host ""

  Write-Host "Server allgemein"
  Write-Host "  /home/art/scripts/update_artserver.sh              Systemupdate, Dienstneustarts, ggf. Reboot"
  Write-Host "  /home/art/scripts/borg-restore-guided.sh           Interaktiver Borg-Restore"
  Write-Host "  /home/art/scripts/artserver_setup.sh               Neuaufbau/Basissetup, manuell"
  Write-Host ""

  Write-Host "Menüplan"
  Write-Host "  /home/art/arkons/deploy/artserver/docker/smoke-menueplan.sh"
  Write-Host "      Docker-Smoke-Test"
  Write-Host "  /opt/apps/Menueplan/ops/backup.sh                  Backup"
  Write-Host "  /opt/apps/Menueplan/ops/restore.sh                 Restore, manuell"
  Write-Host "  $MenueplanDeployScript"
  Write-Host "      Docker-Update aus GitHub, über Menüpunkt 27"
  Write-Host "  $MenueplanSyncScript"
  Write-Host "      Produktive Daten lokal synchronisieren"
  Write-Host "  $MenueplanStartScript"
  Write-Host "      Lokale Menüplan-Entwicklungsumgebung starten"
  Write-Host ""

  Write-Host "RoboWait"
  Write-Host "  $RoboWaitAdminScript"
  Write-Host "      Lokales RoboWait Admin-Menü"
  Write-Host "  /opt/apps/robowait/scripts/backup.sh               RoboWait Backup"
  Write-Host "  /opt/apps/robowait/scripts/update-artserver.sh     RoboWait Update"
  Write-Host "  /opt/apps/robowait/scripts/smoke-docker.sh         Docker-Smoke-Test"
  Write-Host "  /opt/apps/robowait/deploy/docker-compose.yml       Docker-Compose für Web, Reverb und Scheduler"
  Write-Host "  /opt/apps/robowait/scripts/restore.sh              RoboWait Restore, manuell"
  Write-Host "  /opt/apps/robowait/scripts/robowait-admin.ps1      RoboWait Admin-Helfer, anwendungsspezifisch"
  Write-Host "  /home/art/arkons/deploy/artserver/docker/switch-robowait-caddy.sh"
  Write-Host "      Caddy zwischen Host- und Docker-Ports umschalten"
  Write-Host ""

  Write-Host "Arzttarif"
  Write-Host "  /home/art/arkons/deploy/artserver/docker/smoke-arzttarif.sh"
  Write-Host "      Docker-Smoke-Test"
  Write-Host "  $ArzttarifGithubUpdateScript"
  Write-Host "      Docker-Update aus GitHub, über Menüpunkt 33"
  Write-Host "  $ArzttarifDeployScript"
  Write-Host "      Docker-Deploy vom Entwicklungsordner, über Menüpunkt 28"
  Write-Host "  $ArzttarifMergeScript"
  Write-Host "      Branch nach main mergen"
  Write-Host "  $ArzttarifCleanupBranchesScript"
  Write-Host "      Branches aufräumen"
  Write-Host ""

  Write-Host "Arzttarif / Alt-Skripte"
  Write-Host "  /home/art/scripts/archive/20260516-110724-arzttarif-host-cleanup/"
  Write-Host "      bereits archivierte Host-Migration und altes generisches Update"
  Write-Host "  /opt/apps/Arzttarif/deploy/ubuntu/migrate_to_ubuntu.sh"
  Write-Host "      App-eigene Migration, in Arzttarif-Doku referenziert; nicht als Schnellstart verwenden"
  Write-Host ""
  Write-Host "Bewusst nicht als Schnellstart integriert:"
  Write-Host "  Neuaufbau-, Installations-, Restore- und Migrationsskripte, die bestehende Konfigurationen ersetzen können."
  Write-Host ""
  Write-Host "Aufräumen:"
  Write-Host "  Menüpunkt 32 archiviert klar veraltete Skripte und alte RoboWait-Temporärdateien."
  Write-Host ""
  Write-Host "Dateiliste:"
  Invoke-Checked "ssh" @(
    $Server,
    "find /home/art/scripts /opt/apps/Menueplan/ops /opt/apps/robowait/scripts -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort"
  )
}

function Update-ArtserverHub {
  Write-Title "artserver-Zentrale aktualisieren"
  Write-Host "Erstelle /home/art/artserver-hub mit Verweisen und Inventarlisten."

  Invoke-RemoteBash @'
set -euo pipefail

HUB="/home/art/artserver-hub"
LINKS="$HUB/links"
mkdir -p "$LINKS"

link_dir() {
  local target="$1"
  local link="$2"
  if [ -e "$target" ]; then
    rm -f "$link"
    ln -s "$target" "$link"
  fi
}

link_dir "/home/art/scripts" "$LINKS/server-skripte"
link_dir "/home/art/arkons/deploy" "$LINKS/arkons-deploy"
link_dir "/opt/apps/Menueplan" "$LINKS/menueplan"
link_dir "/opt/apps/robowait" "$LINKS/robowait"
link_dir "/opt/apps/Arzttarif" "$LINKS/arzttarif"
link_dir "/etc/caddy/sites-enabled" "$LINKS/caddy-sites"
link_dir "/etc/systemd/system" "$LINKS/systemd-system"

cat > "$HUB/README.md" <<'EOF'
# artserver-hub

Diese Zentrale ist ein Wegweiser. Sie verschiebt keine produktiven Dateien.

Wichtige Verweise:

- `links/server-skripte`: allgemeine Skripte unter `/home/art/scripts`
- `links/arkons-deploy`: Deployment-Dateien der Website `arkons.ch`
- `links/menueplan`: Menüplan-Projekt unter `/opt/apps/Menueplan`
- `links/robowait`: RoboWait-Projekt unter `/opt/apps/robowait`
- `links/arzttarif`: Arzttarif-Projekt unter `/opt/apps/Arzttarif`
- `links/caddy-sites`: aktive Caddy-Site-Dateien
- `links/systemd-system`: systemd-Unit-Dateien
- Portainer Weboberfläche: `https://192.168.1.136:9443/`

Automatisch erzeugte Listen:

- `inventar-skripte.txt`: bekannte Skripte und Betriebsdateien
- `inventar-dokumente.txt`: Markdown-, Text- und Word-Dokumente
- `git-status.txt`: Git-Status der App-Verzeichnisse
- `docker-status.txt`: Docker-Version, Container, Volumes und Portainer-Erreichbarkeit
- `aufraeumkandidaten.txt`: temporäre Dateien, Logs und lose Backups zur späteren Prüfung

Zusätzliche Anleitungen, aus dem Repository in diese Zentrale kopiert:

- `artserver-skriptordnung.md`
- `docker-portainer-sorgfalt.md`
- `server-neuinstallation-checkliste.md`

Regel: Erst lesen, dann sichern, erst danach loeschen. App-Daten, `.env`-Dateien, Datenbanken und Backups werden hier nicht kopiert.

Portainer-Hinweis: Portainer kann Docker steuern und bekommt Zugriff auf `/var/run/docker.sock`. Installation und Aktualisierung deshalb nur bewusst über das lokale Admin-Menü starten.
EOF

{
  echo "Inventar Skripte - $(date -Is)"
  for d in \
    /home/art/scripts \
    /home/art/arkons/deploy \
    /opt/apps/Menueplan/ops \
    /opt/apps/robowait/scripts \
    /opt/apps/Arzttarif/scripts \
    /opt/apps/Arzttarif/deploy; do
    echo
    echo "== $d =="
    find "$d" -maxdepth 3 -type f \( -iname "*.sh" -o -iname "*.ps1" -o -iname "*.cmd" -o -iname "*.service" -o -iname "*.timer" -o -iname "*.caddy" \) -printf "%TY-%Tm-%Td %TH:%TM %m %s %p\n" 2>/dev/null | sort || true
  done
} > "$HUB/inventar-skripte.txt"

{
  echo "Inventar Dokumente - $(date -Is)"
  for d in /opt/apps/Menueplan /opt/apps/robowait /opt/apps/Arzttarif /home/art/arkons; do
    echo
    echo "== $d =="
    find "$d" -maxdepth 4 -type f \( -iname "*.md" -o -iname "*.txt" -o -iname "*.docx" \) -printf "%TY-%Tm-%Td %TH:%TM %s %p\n" 2>/dev/null | sort || true
  done
} > "$HUB/inventar-dokumente.txt"

{
  echo "Git-Status - $(date -Is)"
  for d in /home/art/arkons /opt/apps/Menueplan /opt/apps/robowait /opt/apps/Arzttarif; do
    echo
    if [ -d "$d/.git" ]; then
      echo "== $d =="
      git -C "$d" remote -v || true
      git -C "$d" status --short --branch || true
    else
      echo "== $d =="
      echo "kein Git-Repository"
    fi
  done
} > "$HUB/git-status.txt"

{
  echo "Docker-Status - $(date -Is)"
  echo
  echo "Versionen:"
  docker --version 2>/dev/null || true
  docker compose version 2>/dev/null || true
  echo
  echo "Container:"
  sudo -n docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}" 2>/dev/null || echo "Docker-Containerliste braucht sudo."
  echo
  echo "Volumes:"
  sudo -n docker volume ls 2>/dev/null || echo "Docker-Volumes brauchen sudo."
  echo
  echo "Portainer HTTP-Test:"
  curl -kI --max-time 8 https://127.0.0.1:9443/ 2>/dev/null | sed -n "1,8p" || echo "Portainer antwortet lokal nicht auf https://127.0.0.1:9443/"
} > "$HUB/docker-status.txt"

{
  echo "Aufräumkandidaten - $(date -Is)"
  echo
  echo "Temporäre RoboWait-Dateien und Logs:"
  find /opt/apps/robowait/.tmp /opt/apps/robowait/.tmp-deploy /opt/apps/robowait/.tmp-docx-export -type f -printf "%TY-%Tm-%Td %TH:%TM %s %p\n" 2>/dev/null | sort || true
  echo
  echo "Allgemeine Server-Update-Logs:"
  find /home/art/scripts/logs -type f -printf "%TY-%Tm-%Td %TH:%TM %s %p\n" 2>/dev/null | sort || true
  echo
  echo "Lose Dateien direkt unter /home/art:"
  find /home/art -maxdepth 1 -type f -printf "%TY-%Tm-%Td %TH:%TM %s %p\n" 2>/dev/null | sort || true
  echo
  echo "Caddy-Backups:"
  find /etc/caddy -maxdepth 3 -type f \( -name "Caddyfile.bak*" -o -name "Caddyfile.save*" -o -path "/etc/caddy/backups/*" \) -printf "%TY-%Tm-%Td %TH:%TM %s %p\n" 2>/dev/null | sort || true
} > "$HUB/aufraeumkandidaten.txt"

chmod -R u+rwX,go+rX "$HUB"
echo "$HUB"
'@

  Invoke-Checked "scp" @(
    (Join-Path $Root "docs\artserver-skriptordnung.md"),
    "$Server`:/home/art/artserver-hub/artserver-skriptordnung.md"
  )
  Invoke-Checked "scp" @(
    (Join-Path $Root "docs\docker-portainer-sorgfalt.md"),
    "$Server`:/home/art/artserver-hub/docker-portainer-sorgfalt.md"
  )
  Invoke-Checked "scp" @(
    (Join-Path $Root "docs\server-neuinstallation-checkliste.md"),
    "$Server`:/home/art/artserver-hub/server-neuinstallation-checkliste.md"
  )

  Write-Host "Zentrale aktualisiert: /home/art/artserver-hub" -ForegroundColor Green
}

function Show-ArtserverHub {
  Write-Title "artserver-Zentrale"
  Invoke-Checked "ssh" @(
    $Server,
    "if [ ! -f /home/art/artserver-hub/README.md ]; then echo 'Zentrale fehlt noch. Bitte zuerst Menüpunkt 19 ausführen.'; exit 0; fi; sed -n '1,220p' /home/art/artserver-hub/README.md; echo; echo 'Verweise:'; find /home/art/artserver-hub/links -maxdepth 1 -mindepth 1 -printf '%f -> %l\n' 2>/dev/null | sort; echo; echo 'Inventar-Dateien:'; find /home/art/artserver-hub -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM %s %p\n' | sort"
  )
}

function Show-ServerDocuments {
  Write-Title "Server-Dokumente"
  Invoke-RemoteBash @'
for d in /opt/apps/Menueplan /opt/apps/robowait /opt/apps/Arzttarif /home/art/arkons; do
  echo
  echo "== $d =="
  find "$d" -maxdepth 4 -type f \( -iname "*.md" -o -iname "*.txt" -o -iname "*.docx" \) -printf "%TY-%Tm-%Td %TH:%TM %s %p\n" 2>/dev/null | sort
done
'@
}

function Show-CleanupCandidates {
  Write-Title "Aufräumkandidaten"
  Invoke-RemoteBash @'
echo "Grössen:"
for d in /opt/apps/robowait/.tmp /opt/apps/robowait/.tmp-deploy /opt/apps/robowait/.tmp-docx-export /home/art/scripts/logs; do
  [ -e "$d" ] && du -sh "$d"
done
echo
echo "Temporäre Dateien und Logs:"
find /opt/apps/robowait/.tmp /opt/apps/robowait/.tmp-deploy /opt/apps/robowait/.tmp-docx-export /home/art/scripts/logs -type f -printf "%TY-%Tm-%Td %TH:%TM %s %p\n" 2>/dev/null | sort | sed -n "1,240p"
echo
echo "Lose Dateien direkt unter /home/art:"
find /home/art -maxdepth 1 -type f -printf "%TY-%Tm-%Td %TH:%TM %s %p\n" 2>/dev/null | sort
echo
echo "Caddy-Backups:"
find /etc/caddy -maxdepth 3 -type f \( -name "Caddyfile.bak*" -o -name "Caddyfile.save*" -o -path "/etc/caddy/backups/*" \) -printf "%TY-%Tm-%Td %TH:%TM %s %p\n" 2>/dev/null | sort
'@
}

function Organize-ArtserverScripts {
  Write-Title "Skripte ordnen"
  Write-Host "Diese Aktion löscht nichts. Klar veraltete Dateien werden in Zeitstempel-Archive verschoben." -ForegroundColor Yellow
  Write-Host "Produktive Skripte für Update, Backup, Restore, Docker, Caddy und App-Betrieb bleiben an ihrem Ort."
  Write-Host ""
  Write-Host "Archiviert werden aktuell:" -ForegroundColor Yellow
  Write-Host "- historische Ablagen unter /home/art/scripts, soweit sie nicht mehr produktiv gebraucht werden"
  Write-Host "- alte Inhalte aus /opt/apps/robowait/.tmp"
  Write-Host "- alte Inhalte aus /opt/apps/robowait/.tmp-deploy"
  Write-Host ""
  Write-Host "Manuell geht derselbe Schritt in Menüpunkt 7 oder deiner SSH-Shell so:"
  Write-Host ""
  Write-Host "sudo bash /home/art/arkons/deploy/organize-artserver-scripts.sh" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Der Bericht liegt danach unter /home/art/artserver-hub/script-cleanup-*.txt."

  if (-not (Confirm-DangerousAction "Nur fortfahren, wenn diese Altlasten archiviert werden sollen." "SKRIPTORDNUNG")) {
    Write-Host "Abgebrochen."
    return
  }

  Write-Host ""
  Write-Host "Gleich kann eine sudo-Passwortfrage vom Server kommen." -ForegroundColor Yellow
  Write-Host "Beim Tippen des Passworts zeigt Linux keine Sterne und keine Punkte an." -ForegroundColor Yellow

  Invoke-Checked "ssh" @("-t", $Server, "sudo bash /home/art/arkons/deploy/organize-artserver-scripts.sh")
}

function Show-DockerStatus {
  Write-Title "Docker und Portainer Status"
  Write-Host "Verbinde per SSH mit $Server. Dieser Menüpunkt fragt bewusst kein sudo-Passwort ab."
  Write-Host "Wenn Containerdetails fehlen, hat der Benutzer art noch keine direkten Docker-Rechte."
  Invoke-RemoteBash @'
set +e
echo "Server:"
hostname
date -Is
echo
echo "Docker:"
if command -v docker >/dev/null 2>&1; then
  docker --version 2>/dev/null || echo "Docker ist installiert, aber die Version konnte nicht gelesen werden."
  docker compose version 2>/dev/null || echo "Docker Compose konnte nicht gelesen werden."
else
  echo "Docker ist nicht im PATH."
fi
echo
echo "Docker-Dienst:"
systemctl is-active docker 2>/dev/null || echo "Docker-Dienst konnte nicht gelesen werden."
echo
echo "Container:"
if docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}" 2>/dev/null; then
  :
elif sudo -n docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}" 2>/dev/null; then
  :
else
  echo "Docker-Containerliste ist ohne sudo nicht lesbar."
  echo "Das ist kein Fehler im Skript. Docker schützt seine Verwaltungs-Schnittstelle."
  echo "Für die komplette Liste: Menüpunkt 7 öffnen und dort eingeben: sudo docker ps"
fi
echo
echo "Volumes:"
if docker volume ls 2>/dev/null; then
  :
elif sudo -n docker volume ls 2>/dev/null; then
  :
else
  echo "Docker-Volumes sind ohne sudo nicht lesbar."
fi
echo
echo "Portainer:"
if docker ps --filter "name=portainer" --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}" 2>/dev/null; then
  :
elif sudo -n docker ps --filter "name=portainer" --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}" 2>/dev/null; then
  :
else
  echo "Portainer-Containerdetails sind ohne sudo nicht lesbar."
fi
echo
echo "Port 9443:"
if command -v ss >/dev/null 2>&1; then
  ss -ltn 2>/dev/null | awk 'NR == 1 || $4 ~ /:9443$/ { print }'
else
  echo "ss ist nicht verfügbar."
fi
echo
echo "Portainer HTTP-Test:"
curl -kIs --max-time 8 https://127.0.0.1:9443/ 2>/dev/null | head -n 4
'@
}

function Open-PortainerBrowser {
  Write-Title "Portainer öffnen"
  Write-Host "Öffne $PortainerUrl"
  Write-Host "Beim ersten Start zeigt der Browser wegen des selbstsignierten Zertifikats vermutlich eine Sicherheitswarnung."
  Write-Host "Wenn Portainer im Browser ein Passwort verlangt, ist das der Portainer-Login. Das ist kein sudo-Passwort vom Server."
  Start-Process $PortainerUrl
}

function Install-OrUpdatePortainer {
  Write-Title "Portainer installieren/aktualisieren"
  Write-Host "Portainer CE ist eine Docker-Weboberfläche. Sie kann Container starten, stoppen und ändern." -ForegroundColor Yellow
  Write-Host "Der Container bekommt Zugriff auf /var/run/docker.sock; das ist technisch nötig, aber mächtig." -ForegroundColor Yellow
  if (-not (Confirm-DangerousAction "Nur fortfahren, wenn Portainer auf artserver eingerichtet oder aktualisiert werden soll." "PORTAINER")) {
    Write-Host "Abgebrochen."
    return
  }

  Invoke-RemoteBashFile (Join-Path $Root "deploy\artserver\docker\install-portainer-ce.sh")

  Write-Host ""
  Write-Host "Portainer sollte nun erreichbar sein: $PortainerUrl" -ForegroundColor Green
  Write-Host "Beim ersten Öffnen legst du den Admin-Benutzer an."
}

function Reset-PortainerAdminPassword {
  Write-Title "Portainer Admin-Passwort zurücksetzen"
  Write-Host "Portainer zeigt bereits eine Login-Seite. Das bedeutet: In portainer_data gibt es schon eine Admin-Konfiguration." -ForegroundColor Yellow
  Write-Host "Die automatische Ausführung über das Windows-Menü ist deaktiviert, weil SSH/sudo die Helfer-Ausgabe hier nicht zuverlässig sichtbar macht." -ForegroundColor Yellow
  Write-Host "Dieser Menüpunkt zeigt deshalb die getesteten Befehle. Sie löschen kein Volume und keine App-Container."
  Write-Host ""
  Write-Host "Benutzername ist normalerweise: admin"
  Write-Host ""
  Write-Host "Diese Befehle in Menüpunkt 7 oder deiner vorhandenen SSH-Shell ausführen:" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "sudo docker stop portainer"
  Write-Host "sudo docker pull portainer/helper-reset-password"
  Write-Host "sudo docker run --rm -v portainer_data:/data portainer/helper-reset-password"
  Write-Host "sudo docker start portainer"
  Write-Host ""
  Write-Host "Das neue Passwort steht nach dem dritten Befehl in dieser Zeile:" -ForegroundColor Yellow
  Write-Host "Use the following password to login:"
  Write-Host ""
  Write-Host "Danach Portainer öffnen: $PortainerUrl" -ForegroundColor Green
  Write-Host "Anmelden mit Benutzername admin und dem ausgegebenen Passwort."
}

function Run-ArtserverUpdate {
  Write-Title "artserver Systemupdate"
  Write-Host "Dieses Skript führt apt full-upgrade aus, startet Dienste neu und kann bei Bedarf nach 10 Sekunden rebooten." -ForegroundColor Yellow
  if (-not (Confirm-DangerousAction "Nur starten, wenn jetzt ein Wartungsfenster passt." "UPDATE")) {
    Write-Host "Abgebrochen."
    return
  }

  Invoke-Checked "ssh" @("-t", $Server, "bash /home/art/scripts/update_artserver.sh")
}

function Invoke-RemoteCommandAllowDisconnect {
  param([string]$Command)

  & ssh -tt $Server $Command
  $exitCode = $LASTEXITCODE

  if ($exitCode -eq 0) {
    return
  }

  if ($exitCode -eq 255) {
    Write-Host ""
    Write-Host "Die SSH-Verbindung wurde beendet. Das passt zu einem laufenden Neustart." -ForegroundColor Yellow
    return
  }

  Write-Host ""
  throw "SSH wurde mit Exitcode $exitCode beendet, bevor ein Neustart erkennbar war."
}

function Get-ArtserverBootId {
  $bootId = & ssh -o BatchMode=yes -o ConnectTimeout=5 $Server "cat /proc/sys/kernel/random/boot_id" 2>$null
  if ($LASTEXITCODE -eq 0) {
    return ($bootId -join "").Trim()
  }

  return ""
}

function Wait-ArtserverSsh {
  param(
    [int]$TimeoutSeconds = 600,
    [string]$PreviousBootId = ""
  )

  Write-Title "Warten auf artserver"
  Write-Host "Der Server startet neu. Ich prüfe alle paar Sekunden, ob SSH wieder erreichbar ist."

  Start-Sleep -Seconds 10
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

  while ((Get-Date) -lt $deadline) {
    & ssh -o BatchMode=yes -o ConnectTimeout=5 $Server "true" *> $null
    if ($LASTEXITCODE -eq 0) {
      $currentBootId = Get-ArtserverBootId
      if ($PreviousBootId -and $currentBootId -and ($currentBootId -eq $PreviousBootId)) {
        Write-Host ""
        Write-Host "SSH antwortet noch aus dem alten Systemstart. Ich warte weiter auf den echten Neustart." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        continue
      }

      Write-Host ""
      Write-Host "SSH ist wieder erreichbar. Ich warte kurz, damit die Dienste fertig starten können." -ForegroundColor Green
      Start-Sleep -Seconds 12
      return
    }

    Write-Host "." -NoNewline
    Start-Sleep -Seconds 5
  }

  throw "artserver war nach $TimeoutSeconds Sekunden nicht per SSH erreichbar."
}

function Show-PostRebootControl {
  Write-Title "Kontrolle nach Neustart"

  Invoke-RemoteBash @'
set +e

echo "=== System ==="
hostnamectl | sed -n '1,8p'
uptime
echo

echo "=== Neustart-Prüfung ==="
if [ -f /var/run/reboot-required ]; then
  echo "WARNUNG: Ein weiterer Neustart wird noch gemeldet:"
  cat /var/run/reboot-required
else
  echo "Kein weiterer Neustart gemeldet."
fi
echo

echo "=== Fehlgeschlagene systemd-Units ==="
systemctl --failed --no-pager || true
echo

echo "=== Wichtige Dienste ==="
SERVICES=(
  caddy
  smbd
  cockpit
  php8.3-fpm
  menuplan-stack
  robowait-web
  robowait-reverb
  robowait-scheduler
  docker
)

for svc in "${SERVICES[@]}"; do
  if systemctl list-unit-files "${svc}.service" --no-pager 2>/dev/null | grep -q "^${svc}.service"; then
    printf "%-24s active=%-12s enabled=%s\n" "$svc" "$(systemctl is-active "$svc" 2>/dev/null)" "$(systemctl is-enabled "$svc" 2>/dev/null)"
  else
    printf "%-24s nicht gefunden\n" "$svc"
  fi
done

if systemctl list-unit-files "menuplan-backup.timer" --no-pager 2>/dev/null | grep -q "^menuplan-backup.timer"; then
  printf "%-24s active=%-12s enabled=%s\n" "menuplan-backup.timer" "$(systemctl is-active menuplan-backup.timer 2>/dev/null)" "$(systemctl is-enabled menuplan-backup.timer 2>/dev/null)"
fi
echo

echo "=== Caddy-Konfiguration ==="
if command -v caddy >/dev/null 2>&1; then
  sudo -n caddy validate --config /etc/caddy/Caddyfile 2>&1 | sed -n '1,60p' || echo "Caddy-Validierung braucht sudo-Passwort oder ist fehlgeschlagen."
else
  echo "caddy-Befehl nicht gefunden."
fi
echo

echo "=== Docker / Portainer ==="
if command -v docker >/dev/null 2>&1; then
  docker --version || true
  (docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || sudo -n docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo "Docker-Containerliste braucht sudo-Passwort.")
else
  echo "Docker ist nicht installiert."
fi
echo

echo "=== HTTP-Kontrollen lokal auf artserver ==="
check_http_head() {
  local name="$1"
  shift
  local status
  status="$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 12 "$@")"
  if [ "$status" -ge 200 ] && [ "$status" -lt 400 ]; then
    printf "OK     %-20s HTTP %s\n" "$name" "$status"
  else
    printf "FEHLER %-20s HTTP %s\n" "$name" "$status"
  fi
}

check_http_body() {
  local name="$1"
  shift
  local body
  if body="$(curl -fsS --max-time 12 "$@")"; then
    printf "OK     %-20s %s\n" "$name" "$body"
  else
    printf "FEHLER %-20s nicht erreichbar\n" "$name"
  fi
}

check_http_head "Arkons Vorschau" -H 'Host: arkons.ch' http://127.0.0.1/
check_http_head "Menüplan" --resolve arnet.internet-box.ch:443:127.0.0.1 https://arnet.internet-box.ch/
check_http_head "RoboWait" --resolve robowait.arkons.ch:443:127.0.0.1 https://robowait.arkons.ch/
check_http_body "Arzttarif API" http://127.0.0.1:18000/api/version
check_http_head "Portainer" https://127.0.0.1:9443/
echo

exit 0
'@
}

function Run-ArtserverUpdateRebootControl {
  Write-Title "Systemupdate, Neustart und Kontrolle"
  Write-Host "Dieser Ablauf macht drei Dinge:" -ForegroundColor Yellow
  Write-Host "1. artserver-Systemupdate starten"
  Write-Host "2. Danach bewusst neu starten, auch wenn Ubuntu keinen Neustart verlangt"
  Write-Host "3. Warten, bis SSH wieder da ist, und dann Dienste/Webseiten prüfen"
  Write-Host ""
  Write-Host "Während des Neustarts sind Website und Apps kurz nicht erreichbar." -ForegroundColor Yellow

  if (-not (Confirm-DangerousAction "Nur starten, wenn jetzt ein Wartungsfenster passt." "FRISCHSTART")) {
    Write-Host "Abgebrochen."
    return
  }

  $bootIdBefore = Get-ArtserverBootId
  if ($bootIdBefore) {
    Write-Host "Aktuelle Boot-ID vor dem Update: $bootIdBefore"
  }

  Write-Host ""
  Write-Host "Gleich kann eine sudo-Passwortfrage vom Server kommen." -ForegroundColor Yellow
  Write-Host "Wichtig: Beim Tippen des Passworts zeigt Linux keine Sterne und keine Punkte an." -ForegroundColor Yellow
  Write-Host "Wenn die Anzeige scheinbar stehen bleibt, das artserver-Passwort eingeben und Enter drücken." -ForegroundColor Yellow

  $remoteCommand = 'if [ ! -x /home/art/scripts/update_artserver.sh ]; then echo "FEHLER: /home/art/scripts/update_artserver.sh fehlt oder ist nicht ausführbar."; exit 2; fi; echo "Sudo-Freigabe für Update und Neustart."; echo "Wenn jetzt keine Zeichen erscheinen: Passwort trotzdem tippen und Enter drücken."; sudo -p "[sudo] Passwort für art auf artserver: " -v || exit 3; bash /home/art/scripts/update_artserver.sh; rc=$?; echo; echo "Frischer Neustart wird jetzt ausgelöst, damit Kernel und alle aktivierten Dienste sauber neu starten."; sudo -p "[sudo] Passwort für art auf artserver: " -v || exit 3; sudo systemctl reboot; exit $rc'

  Invoke-RemoteCommandAllowDisconnect $remoteCommand
  Wait-ArtserverSsh -PreviousBootId $bootIdBefore
  Show-PostRebootControl
}

function Run-BorgRestoreGuided {
  Write-Title "Borg Restore Assistent"
  Write-Host "Restore kann Daten überschreiben. Das Server-Skript ist interaktiv und fragt mehrfach nach." -ForegroundColor Yellow
  if (-not (Confirm-DangerousAction "Nur starten, wenn wirklich ein Restore geplant ist." "RESTORE")) {
    Write-Host "Abgebrochen."
    return
  }

  Invoke-Checked "ssh" @("-t", $Server, "sudo bash /home/art/scripts/borg-restore-guided.sh")
}

function Run-RoboWaitBackup {
  Write-Title "RoboWait Backup"
  Invoke-Checked "ssh" @($Server, "cd /opt/apps/robowait && bash scripts/backup.sh")
}

function Run-RoboWaitUpdate {
  Write-Title "RoboWait Update"
  Write-Host "Aktualisiert RoboWait-Code und Abhängigkeiten und startet Dienste neu." -ForegroundColor Yellow
  if (-not (Confirm-DangerousAction "Nur starten, wenn ein RoboWait-Wartungsfenster passt." "ROBOWAIT")) {
    Write-Host "Abgebrochen."
    return
  }

  Invoke-Checked "ssh" @("-t", $Server, "sudo bash /opt/apps/robowait/scripts/update-artserver.sh")
}

function Open-PreviewBrowser {
  Write-Title "Vorschau öffnen"
  Start-Process $PreviewUrl
}

function Show-Help {
  Write-Title "Hilfe zu den Menüpunkten"
  Write-Host "Grundregel: Für reine Website-Änderungen zuerst 1, optional 2, dann 3 und danach 5 verwenden."
  Write-Host "DNS/Localsearch wird durch dieses Menü nicht umgestellt."
  Write-Host "Produktive HTTPS-Umstellung von arkons.ch bleibt ein separater späterer Schritt."
  Write-Host ""

  Write-Host "Empfohlene Abläufe" -ForegroundColor Cyan
  Write-Host "  Website ändern:"
  Write-Host "    1 bauen -> 2 lokal ansehen -> 3 nach artserver deployen -> 5 Status prüfen -> 6 Vorschau öffnen"
  Write-Host "  Nach Serverwartung:"
  Write-Host "    26 Update + Neustart + Kontrolle oder manuell: 8 Dienste ansehen -> 5 HTTP-Status prüfen"
  Write-Host "  App-Updates im Docker-Betrieb:"
  Write-Host "    Menüplan: 27 Docker-Update aus GitHub"
  Write-Host "    RoboWait: 18 Update aus GitHub"
  Write-Host "    Arzttarif: 33 Docker-Update aus GitHub"
  Write-Host "    Arzttarif lokal: 28 Docker-Deploy vom Entwicklungsordner"
  Write-Host "  Zentrale Skriptsteuerung:"
  Write-Host "    36 Projekt-Admin-Einstiege anzeigen -> 34 Katalog anzeigen -> 35 Skript aus Katalog starten"
  Write-Host "  Vor riskanten App-Arbeiten:"
  Write-Host "    Menüplan: 10 Backup; RoboWait: 17 Backup"
  Write-Host ""

  foreach ($group in $MenuGroups) {
    Write-Host $group -ForegroundColor Cyan
    foreach ($item in ($MenuHelp | Where-Object { $_.Group -eq $group })) {
      Write-Host "$($item.Choice)  $($item.Name)" -ForegroundColor Yellow
      Write-Host "   Zweck: $($item.Description)"
      Write-Host "   Wann: $($item.UseWhen)"
      Write-Host "   Wirkung: $($item.Effect)"
      Write-Host "   Risiko: $($item.Risk)"
    }
    Write-Host ""
  }

  Write-Host "0  Beenden" -ForegroundColor Yellow
  Write-Host "   Schliesst dieses Admin-Menü."
}

function Show-Menu {
  try {
    Clear-Host
  } catch {
    Write-Host ""
  }
  Write-Host "artserver Administration" -ForegroundColor Cyan
  Write-Host "Arbeitsordner: $Root"
  Write-Host ""
  Write-Host "Website / arkons.ch" -ForegroundColor Cyan
  Write-Host " 1  Website lokal bauen"
  Write-Host " 2  Website lokal anzeigen"
  Write-Host " 3  Website nach artserver-Vorschau deployen"
  Write-Host " 4  Arkons-Caddy-Vorschau aktivieren/erneuern (sudo)"
  Write-Host " 5  Status prüfen"
  Write-Host " 6  Vorschau im Browser öffnen"
  Write-Host ""
  Write-Host "Server allgemein" -ForegroundColor Cyan
  Write-Host " 7  SSH-Shell zu artserver"
  Write-Host " 8  Dienste und Container anzeigen"
  Write-Host "11  Server-Skripte anzeigen"
  Write-Host "12  artserver Systemupdate starten (sudo, kann rebooten)"
  Write-Host "13  Borg Restore Assistent starten (sudo)"
  Write-Host "26  Systemupdate, Neustart und Kontrolle (sudo)"
  Write-Host ""
  Write-Host "Menüplan" -ForegroundColor Cyan
  Write-Host " 9  Menüplan Smoke-Test starten"
  Write-Host "10  Menüplan Backup starten"
  Write-Host ""
  Write-Host "RoboWait" -ForegroundColor Cyan
  Write-Host "17  RoboWait Backup starten"
  Write-Host "18  RoboWait Update starten (sudo)"
  Write-Host ""
  Write-Host "Zentrale" -ForegroundColor Cyan
  Write-Host "19  artserver-Zentrale einrichten/aktualisieren"
  Write-Host "20  artserver-Zentrale anzeigen"
  Write-Host "21  Server-Dokumente anzeigen"
  Write-Host "22  Aufräumkandidaten anzeigen"
  Write-Host "32  Skripte ordnen und Altlasten archivieren (sudo)"
  Write-Host "34  Zentralen Skriptkatalog anzeigen"
  Write-Host "35  Skript aus zentralem Katalog starten"
  Write-Host "36  Projekt-Admin-Einstiege anzeigen"
  Write-Host ""
  Write-Host "Docker" -ForegroundColor Cyan
  Write-Host "23  Docker und Portainer Status anzeigen"
  Write-Host "24  Portainer im Browser öffnen"
  Write-Host "25  Portainer installieren/aktualisieren (sudo)"
  Write-Host "27  Menüplan Docker-Update aus GitHub (sudo)"
  Write-Host "28  Arzttarif Docker-Deploy vom Entwicklungsordner (sudo)"
  Write-Host "33  Arzttarif Docker-Update aus GitHub (sudo)"
  Write-Host "29  RoboWait Docker-Prototyp starten (sudo)"
  Write-Host "30  RoboWait Docker-Smoke-Test starten"
  Write-Host "31  Portainer Admin-Passwort zurücksetzen (Befehle anzeigen)"
  Write-Host ""
  Write-Host " H  Hilfe zu den Menüpunkten"
  Write-Host ""
  Write-Host " 0  Beenden"
  Write-Host ""
}

function Invoke-MenuChoice {
  param([string]$Choice)

  switch ($Choice.Trim()) {
    "1" { Build-Website; Pause-Menu }
    "2" { Start-LocalPreview }
    "3" { Deploy-ArtserverPreview; Pause-Menu }
    "4" { Enable-ArkonsPreview; Pause-Menu }
    "5" { Show-Status; Pause-Menu }
    "6" { Open-PreviewBrowser; Pause-Menu }
    "7" { Open-ArtserverShell; Pause-Menu }
    "8" { Show-ServiceStatus; Pause-Menu }
    "9" { Run-MenueplanDoctor; Pause-Menu }
    "10" { Run-MenueplanBackup; Pause-Menu }
    "11" { Show-ArtserverScripts; Pause-Menu }
    "12" { Run-ArtserverUpdate; Pause-Menu }
    "13" { Run-BorgRestoreGuided; Pause-Menu }
    "17" { Run-RoboWaitBackup; Pause-Menu }
    "18" { Run-RoboWaitUpdate; Pause-Menu }
    "19" { Update-ArtserverHub; Pause-Menu }
    "20" { Show-ArtserverHub; Pause-Menu }
    "21" { Show-ServerDocuments; Pause-Menu }
    "22" { Show-CleanupCandidates; Pause-Menu }
    "32" { Organize-ArtserverScripts; Pause-Menu }
    "34" { Show-ScriptCatalog; Pause-Menu }
    "35" { Start-ScriptFromCatalog; Pause-Menu }
    "36" { Show-ProjectAdminEntrypoints; Pause-Menu }
    "23" { Show-DockerStatus; Pause-Menu }
    "24" { Open-PortainerBrowser; Pause-Menu }
    "25" { Install-OrUpdatePortainer; Pause-Menu }
    "26" { Run-ArtserverUpdateRebootControl; Pause-Menu }
    "27" { Run-MenueplanDockerUpdate; Pause-Menu }
    "28" { Run-ArzttarifDockerDeploy; Pause-Menu }
    "29" { Run-RoboWaitDockerPrototype; Pause-Menu }
    "30" { Run-RoboWaitDockerSmoke; Pause-Menu }
    "31" { Reset-PortainerAdminPassword; Pause-Menu }
    "33" { Run-ArzttarifDockerGithubUpdate; Pause-Menu }
    "h" { Show-Help; Pause-Menu }
    "H" { Show-Help; Pause-Menu }
    "?" { Show-Help; Pause-Menu }
    "0" { return $false }
    default {
      Write-Host "Unbekannte Auswahl: $Choice" -ForegroundColor Yellow
      Pause-Menu
    }
  }

  return $true
}

if ($List) {
  Show-Menu
  exit 0
}

if ($Help) {
  Show-Help
  exit 0
}

if ($Run) {
  switch ($Run.Trim()) {
    "1" { Build-Website }
    "3" { Deploy-ArtserverPreview }
    "5" { Show-Status }
    "6" { Open-PreviewBrowser }
    "8" { Show-ServiceStatus }
    "9" { Run-MenueplanDoctor }
    "10" { Run-MenueplanBackup }
    "11" { Show-ArtserverScripts }
    "17" { Run-RoboWaitBackup }
    "18" { Run-RoboWaitUpdate }
    "19" { Update-ArtserverHub }
    "20" { Show-ArtserverHub }
    "21" { Show-ServerDocuments }
    "22" { Show-CleanupCandidates }
    "32" { Organize-ArtserverScripts }
    "34" { Show-ScriptCatalog }
    "35" { Start-ScriptFromCatalog }
    "36" { Show-ProjectAdminEntrypoints }
    "23" { Show-DockerStatus }
    "24" { Open-PortainerBrowser }
    "26" { Run-ArtserverUpdateRebootControl }
    "27" { Run-MenueplanDockerUpdate }
    "28" { Run-ArzttarifDockerDeploy }
    "29" { Run-RoboWaitDockerPrototype }
    "30" { Run-RoboWaitDockerSmoke }
    "31" { Reset-PortainerAdminPassword }
    "33" { Run-ArzttarifDockerGithubUpdate }
    default { throw "Direkt ausführbar sind aktuell die Menüpunkte 1, 3, 5, 6, 8 bis 11, 17 bis 24 und 26 bis 36. Gewünscht war: $Run" }
  }
  exit 0
}

if ($ScriptId) {
  Invoke-ScriptCatalogEntry $ScriptId
  exit 0
}

Set-Location $Root

while ($true) {
  Show-Menu
  $choice = Read-Host "Auswahl"
  if (-not (Invoke-MenuChoice $choice)) {
    break
  }
}
