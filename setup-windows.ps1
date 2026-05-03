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

# ── Font Awesome (self-hosted) ────────────────────────────────────────────────

$FaVersion = '6.5.1'
$FaDir     = Join-Path $ScriptDir 'homedashboard\static\fontawesome'
if (-not (Test-Path (Join-Path $FaDir 'all.min.css'))) {
    Write-Host "Downloading Font Awesome $FaVersion..."
    $FaZip = Join-Path $env:TEMP 'fa.zip'
    $FaTmp = Join-Path $env:TEMP 'fa'
    Invoke-WebRequest -Uri "https://use.fontawesome.com/releases/v$FaVersion/fontawesome-free-$FaVersion-web.zip" `
        -OutFile $FaZip
    Expand-Archive -Path $FaZip -DestinationPath $FaTmp -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $FaDir 'css') | Out-Null
    Copy-Item (Join-Path $FaTmp "fontawesome-free-$FaVersion-web\css\all.min.css") (Join-Path $FaDir 'css')
    Copy-Item (Join-Path $FaTmp "fontawesome-free-$FaVersion-web\webfonts") $FaDir -Recurse -Force
    Remove-Item $FaZip, $FaTmp -Recurse -Force
} else {
    Write-Host "Font Awesome already present."
}

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
