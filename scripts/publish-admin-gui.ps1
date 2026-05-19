param(
  [string]$Branch = "main",
  [string]$Remote = "origin",
  [string]$Server = "art@artserver",
  [string]$CommitMessage = "",
  [switch]$SkipCommit,
  [switch]$SkipPush,
  [switch]$SkipDeploy,
  [switch]$SkipCaddy,
  [switch]$InstallSudoHelper,
  [switch]$NonInteractiveSudo,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $Utf8NoBom
$OutputEncoding = $Utf8NoBom

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$DeployScript = Join-Path $Root "deploy\artserver\admin\deploy-admin-gui-from-github.sh"

function Write-Step {
  param([string]$Text)
  Write-Host ""
  Write-Host "== $Text ==" -ForegroundColor Cyan
}

function Invoke-Checked {
  param(
    [string]$Program,
    [string[]]$Arguments,
    [string]$WorkingDirectory = $Root
  )

  Write-Host ("> " + $Program + " " + ($Arguments -join " ")) -ForegroundColor DarkGray
  if ($DryRun) {
    return
  }

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

function Assert-SafeGitName {
  param([string]$Name, [string]$Label)
  if ($Name -notmatch '^[A-Za-z0-9._/-]+$') {
    throw "$Label enthaelt unerwartete Zeichen: $Name"
  }
}

Assert-SafeGitName $Branch "Branch"
Assert-SafeGitName $Remote "Remote"

if (-not (Test-Path -LiteralPath (Join-Path $Root ".git") -PathType Container)) {
  throw "Dieses Skript muss im artserver-Git-Repository liegen: $Root"
}

if (-not (Test-Path -LiteralPath $DeployScript -PathType Leaf)) {
  throw "Server-Deploy-Skript nicht gefunden: $DeployScript"
}

Write-Step "Pruefungen"
Invoke-Checked "python" @("-m", "py_compile", "admin-gui\app.py")

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCommand -and (Test-Path -LiteralPath (Join-Path $Root "admin-gui\static\editor.js") -PathType Leaf)) {
  Invoke-Checked $nodeCommand.Source @("--check", "admin-gui\static\editor.js")
}

Write-Step "Git-Stand"
$currentBranch = (& git -C $Root branch --show-current).Trim()
if ($currentBranch -ne $Branch) {
  throw "Aktueller Branch ist '$currentBranch', erwartet ist '$Branch'. Bitte zuerst wechseln oder -Branch angeben."
}

$status = (& git -C $Root status --porcelain)
if ($status -and -not $SkipCommit) {
  if (-not $CommitMessage.Trim()) {
    Write-Host "Es gibt lokale Aenderungen. Bitte mit -CommitMessage eine Commit-Nachricht angeben." -ForegroundColor Yellow
    Write-Host ""
    $status | ForEach-Object { Write-Host $_ }
    throw "Abgebrochen: keine Commit-Nachricht."
  }

  Invoke-Checked "git" @("add", "admin-gui", "deploy/artserver/admin", "scripts/publish-admin-gui.ps1", "scripts/start-admin-gui-local.cmd", "publish-admin-gui.cmd", "artserver-apps.json", "artserver-script-catalog.json", "admin-gui/README.md", "deploy/artserver/admin/README.md")
  Invoke-Checked "git" @("commit", "-m", $CommitMessage)
} elseif ($status) {
  Write-Host "Lokale Aenderungen bleiben uncommitted, weil -SkipCommit gesetzt ist." -ForegroundColor Yellow
  $status | ForEach-Object { Write-Host $_ }
} else {
  Write-Host "Arbeitsbaum ist sauber."
}

if (-not $SkipPush) {
  Write-Step "Nach GitHub pushen"
  Invoke-Checked "git" @("push", $Remote, $Branch)
}

if (-not $SkipDeploy) {
  Write-Step "artserver aus GitHub aktualisieren"
  $remoteArgs = @("--branch", $Branch)
  if ($SkipCaddy) {
    $remoteArgs += "--skip-caddy"
  }
  if ($InstallSudoHelper) {
    $remoteArgs += "--install-sudo-helper"
  }

  $quotedRemoteArgs = (($remoteArgs | ForEach-Object { "'" + ($_ -replace "'", "'\''") + "'" }) -join " ")
  $remoteScript = "/tmp/arkons-admin-deploy-$([guid]::NewGuid().ToString('N')).sh"
  $envPrefix = ""
  if ($NonInteractiveSudo) {
    $envPrefix = "ARKONS_ADMIN_SUDO='sudo -n' "
  }
  $remoteCommand = "sed -i 's/\r`$//' $remoteScript; ${envPrefix}bash $remoteScript $quotedRemoteArgs; rc=`$?; rm -f $remoteScript; exit `$rc"
  Write-Host ("> scp $DeployScript $Server`:$remoteScript") -ForegroundColor DarkGray
  if ($NonInteractiveSudo) {
    Write-Host ("> ssh $Server $remoteCommand") -ForegroundColor DarkGray
  } else {
    Write-Host ("> ssh -tt $Server $remoteCommand") -ForegroundColor DarkGray
  }
  if (-not $DryRun) {
    & scp $DeployScript "$Server`:$remoteScript"
    if ($LASTEXITCODE -ne 0) {
      throw "Deploy-Skript konnte nicht auf artserver kopiert werden."
    }

    if ($NonInteractiveSudo) {
      & ssh $Server $remoteCommand
    } else {
      & ssh -tt $Server $remoteCommand
    }
    if ($LASTEXITCODE -ne 0) {
      throw "Deploy auf artserver ist fehlgeschlagen."
    }
  }
}

Write-Host ""
Write-Host "Fertig." -ForegroundColor Green
