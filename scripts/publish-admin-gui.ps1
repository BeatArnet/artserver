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

function Resolve-Tool {
  param(
    [string]$Label,
    [string[]]$Candidates
  )

  foreach ($candidate in $Candidates) {
    if (-not $candidate) {
      continue
    }
    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($command) {
      if ($command.Path) {
        return $command.Path
      }
      if ($command.Source) {
        return $command.Source
      }
      if ($command.Definition) {
        return $command.Definition
      }
    }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return $candidate
    }
  }

  throw "$Label wurde nicht gefunden. Geprüft: $($Candidates -join ', ')"
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
    $success = $?
    $exitCode = $LASTEXITCODE
    if (-not $success) {
      throw "$Program konnte nicht erfolgreich ausgeführt werden."
    }
    if ($null -ne $exitCode -and $exitCode -ne 0) {
      throw "$Program wurde mit Exitcode $exitCode beendet."
    }
  } finally {
    Pop-Location
  }
}

function Invoke-Captured {
  param(
    [string]$Program,
    [string[]]$Arguments,
    [string]$WorkingDirectory = $Root
  )

  $stdoutFile = New-TemporaryFile
  $stderrFile = New-TemporaryFile
  try {
    $process = Start-Process `
      -FilePath $Program `
      -ArgumentList $Arguments `
      -WorkingDirectory $WorkingDirectory `
      -NoNewWindow `
      -Wait `
      -PassThru `
      -RedirectStandardOutput $stdoutFile `
      -RedirectStandardError $stderrFile

    $stdout = Get-Content -LiteralPath $stdoutFile -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue
    if ($process.ExitCode -ne 0) {
      throw "$Program wurde mit Exitcode $($process.ExitCode) beendet. $stderr"
    }
    return $stdout
  } finally {
    Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
  }
}

function Get-GitBranchFromHead {
  param([string]$RepositoryRoot)

  $headPath = Join-Path $RepositoryRoot ".git\HEAD"
  if (-not (Test-Path -LiteralPath $headPath -PathType Leaf)) {
    return ""
  }

  $head = (Get-Content -LiteralPath $headPath -Raw).Trim()
  if ($head -match '^ref:\s+refs/heads/(.+)$') {
    return $Matches[1]
  }
  return ""
}

function Assert-SafeGitName {
  param([string]$Name, [string]$Label)
  if ($Name -notmatch '^[A-Za-z0-9._/-]+$') {
    throw "$Label enthaelt unerwartete Zeichen: $Name"
  }
}

Assert-SafeGitName $Branch "Branch"
Assert-SafeGitName $Remote "Remote"

$PythonExe = Resolve-Tool "Python" @(
  "python",
  "py",
  (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe")
)
$GitExe = Resolve-Tool "Git" @(
  "git",
  "C:\Program Files\Git\cmd\git.exe",
  "C:\Program Files\Git\bin\git.exe",
  "C:\Program Files (x86)\Git\cmd\git.exe"
)
$ScpExe = Resolve-Tool "scp" @(
  "scp",
  "C:\Windows\System32\OpenSSH\scp.exe"
)
$SshExe = Resolve-Tool "ssh" @(
  "ssh",
  "C:\Windows\System32\OpenSSH\ssh.exe"
)

if (-not (Test-Path -LiteralPath (Join-Path $Root ".git") -PathType Container)) {
  throw "Dieses Skript muss im artserver-Git-Repository liegen: $Root"
}

if (-not (Test-Path -LiteralPath $DeployScript -PathType Leaf)) {
  throw "Server-Deploy-Skript nicht gefunden: $DeployScript"
}

Write-Step "Pruefungen"
Invoke-Checked $PythonExe @("-m", "py_compile", "admin-gui\app.py")

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCommand -and (Test-Path -LiteralPath (Join-Path $Root "admin-gui\static\editor.js") -PathType Leaf)) {
  Invoke-Checked $nodeCommand.Source @("--check", "admin-gui\static\editor.js")
}

Write-Step "Git-Stand"
$currentBranch = (Get-GitBranchFromHead $Root)
if (-not $currentBranch) {
  $currentBranch = (Invoke-Captured $GitExe @("-C", $Root, "branch", "--show-current")).Trim()
}
if (-not $currentBranch) {
  $message = "Aktueller Git-Branch konnte nicht ermittelt werden."
  if ($DryRun) {
    Write-Host $message -ForegroundColor Yellow
  } else {
    throw $message
  }
} elseif ($currentBranch -ne $Branch) {
  throw "Aktueller Branch ist '$currentBranch', erwartet ist '$Branch'. Bitte zuerst wechseln oder -Branch angeben."
}

$status = (Invoke-Captured $GitExe @("-C", $Root, "status", "--porcelain"))
if ($status -and -not $SkipCommit) {
  if (-not $CommitMessage.Trim()) {
    Write-Host "Es gibt lokale Aenderungen. Bitte mit -CommitMessage eine Commit-Nachricht angeben." -ForegroundColor Yellow
    Write-Host ""
    $status | ForEach-Object { Write-Host $_ }
    throw "Abgebrochen: keine Commit-Nachricht."
  }

  Invoke-Checked $GitExe @("add", "admin-gui", "deploy/artserver/admin", "scripts/publish-admin-gui.ps1", "scripts/start-admin-gui-local.cmd", "start-admin-gui.cmd", ".vscode/tasks.json", "publish-admin-gui.cmd", "artserver-admin.ps1", "artserver-apps.json", "artserver-script-catalog.json", "admin-gui/README.md", "deploy/artserver/admin/README.md")
  Invoke-Checked $GitExe @("commit", "-m", $CommitMessage)
} elseif ($status) {
  Write-Host "Lokale Aenderungen bleiben uncommitted, weil -SkipCommit gesetzt ist." -ForegroundColor Yellow
  $status | ForEach-Object { Write-Host $_ }
} else {
  Write-Host "Arbeitsbaum ist sauber."
}

if (-not $SkipPush) {
  Write-Step "Nach GitHub pushen"
  Invoke-Checked $GitExe @("push", $Remote, $Branch)
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
    Invoke-Checked $ScpExe @($DeployScript, "$Server`:$remoteScript")

    if ($NonInteractiveSudo) {
      Invoke-Checked $SshExe @($Server, $remoteCommand)
    } else {
      Invoke-Checked $SshExe @("-tt", $Server, $remoteCommand)
    }
  }
}

Write-Host ""
Write-Host "Fertig." -ForegroundColor Green
