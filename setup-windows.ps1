#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Venv      = Join-Path $ScriptDir '.venv'

# ── Python discovery ──────────────────────────────────────────────────────────

$Python = $null
foreach ($candidate in @('py', 'python3', 'python')) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) {
        $Python = $candidate
        break
    }
}

if (-not $Python) {
    Write-Error @"
Python not found in PATH.
Download from https://www.python.org/downloads/ and ensure
"Add python.exe to PATH" is checked during installation.
"@
    exit 1
}

$PyVersion = & $Python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
$parts = $PyVersion.Split('.')
$pyMajor = [int]$parts[0]
$pyMinor = [int]$parts[1]

if ($pyMajor -lt 3 -or ($pyMajor -eq 3 -and $pyMinor -lt 11)) {
    Write-Error "Python 3.11+ required (found $PyVersion)"
    exit 1
}

Write-Host "Python $PyVersion ($Python)"

# ── Virtual environment ───────────────────────────────────────────────────────

if (-not (Test-Path $Venv)) {
    Write-Host "Creating virtual environment..."
    & $Python -m venv $Venv
} else {
    Write-Host "Virtual environment already exists."
}

$Pip    = Join-Path $Venv 'Scripts\pip.exe'
$PyExe  = Join-Path $Venv 'Scripts\python.exe'
$RunPy  = Join-Path $ScriptDir 'run.py'

Write-Host "Installing dependencies..."
& $Pip install --quiet --upgrade pip
& $Pip install --quiet -r (Join-Path $ScriptDir 'requirements.txt')

# ── Configuration ─────────────────────────────────────────────────────────────

$ConfigFile = Join-Path $ScriptDir 'config.json'
$SampleFile = Join-Path $ScriptDir 'config.json.sample'

if (-not (Test-Path $ConfigFile)) {
    Write-Host "Creating config.json from sample..."
    Copy-Item $SampleFile $ConfigFile
    Write-Host "  Edit $ConfigFile to customise your dashboard."
} else {
    Write-Host "config.json already exists."
}

# ── Done ──────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Setup complete."
Write-Host ""
Write-Host "Run the dashboard:"
Write-Host "  $PyExe $RunPy"
Write-Host ""
Write-Host "To start automatically at login, add that command to Task Scheduler"
Write-Host "or create a shortcut in your Startup folder:"
Write-Host "  shell:startup"
Write-Host ""
Write-Host "Dashboard:  http://localhost:8080"
Write-Host "Settings:   http://localhost:8080/edit"
