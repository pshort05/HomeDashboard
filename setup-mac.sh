#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$SCRIPT_DIR/.venv"
PLIST_LABEL="com.homedashboard"
PLIST_FILE="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
INSTALL_SERVICE=false

# ── Argument parsing ──────────────────────────────────────────────────────────

usage() {
    echo "Usage: $0 [--service]"
    echo ""
    echo "  --service   Also install and start a launchd user agent"
    exit 1
}

for arg in "$@"; do
    case "$arg" in
        --service) INSTALL_SERVICE=true ;;
        *) usage ;;
    esac
done

# ── Python discovery ──────────────────────────────────────────────────────────

# Check Homebrew locations (Apple Silicon first, then Intel), then PATH fallback
PYTHON=""
for candidate in \
    /opt/homebrew/bin/python3.12 \
    /opt/homebrew/bin/python3.11 \
    /usr/local/bin/python3.12 \
    /usr/local/bin/python3.11 \
    python3.12 \
    python3.11 \
    python3
do
    if command -v "$candidate" &>/dev/null; then
        PYTHON="$candidate"
        break
    fi
done

if [[ -z "$PYTHON" ]]; then
    echo "error: Python not found." >&2
    echo "Install via Homebrew: brew install python@3.12" >&2
    exit 1
fi

PY_VERSION=$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_MAJOR=$("$PYTHON" -c 'import sys; print(sys.version_info.major)')
PY_MINOR=$("$PYTHON" -c 'import sys; print(sys.version_info.minor)')

if [[ "$PY_MAJOR" -lt 3 || ( "$PY_MAJOR" -eq 3 && "$PY_MINOR" -lt 11 ) ]]; then
    echo "error: Python 3.11+ required (found $PY_VERSION)" >&2
    exit 1
fi

echo "Python $PY_VERSION ($PYTHON)"

# ── Virtual environment ───────────────────────────────────────────────────────

if [[ ! -d "$VENV" ]]; then
    echo "Creating virtual environment..."
    "$PYTHON" -m venv "$VENV"
else
    echo "Virtual environment already exists."
fi

echo "Installing dependencies..."
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet -r "$SCRIPT_DIR/requirements.txt"

# ── Font Awesome (self-hosted) ────────────────────────────────────────────────

FA_VERSION=6.5.1
FA_DIR="$SCRIPT_DIR/homedashboard/static/fontawesome"
if [[ ! -f "$FA_DIR/all.min.css" ]]; then
    echo "Downloading Font Awesome $FA_VERSION..."
    curl -fsSL "https://use.fontawesome.com/releases/v${FA_VERSION}/fontawesome-free-${FA_VERSION}-web.zip" \
         -o /tmp/fa.zip
    unzip -q /tmp/fa.zip -d /tmp/fa
    mkdir -p "$FA_DIR/css"
    cp "/tmp/fa/fontawesome-free-${FA_VERSION}-web/css/all.min.css" "$FA_DIR/css/"
    cp -r "/tmp/fa/fontawesome-free-${FA_VERSION}-web/webfonts" "$FA_DIR/"
    rm -rf /tmp/fa /tmp/fa.zip
else
    echo "Font Awesome already present."
fi

# ── Configuration ─────────────────────────────────────────────────────────────

if [[ ! -f "$SCRIPT_DIR/config.json" ]]; then
    echo "Creating config.json from sample..."
    cp "$SCRIPT_DIR/config.json.sample" "$SCRIPT_DIR/config.json"
    echo "  Edit $SCRIPT_DIR/config.json to customise your dashboard."
else
    echo "config.json already exists."
fi

# ── launchd user agent (optional) ────────────────────────────────────────────

if [[ "$INSTALL_SERVICE" == true ]]; then
    mkdir -p "$(dirname "$PLIST_FILE")"

    cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${VENV}/bin/python</string>
        <string>${SCRIPT_DIR}/run.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${SCRIPT_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/homedashboard.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/homedashboard.log</string>
</dict>
</plist>
EOF

    # Unload first if already loaded (idempotent re-install)
    launchctl unload -w "$PLIST_FILE" 2>/dev/null || true
    launchctl load -w "$PLIST_FILE"

    echo ""
    echo "Service installed and started."
    echo "  Status:  launchctl list $PLIST_LABEL"
    echo "  Logs:    tail -f /tmp/homedashboard.log"
    echo "  Stop:    launchctl unload -w $PLIST_FILE"
    echo "  Remove:  launchctl unload -w $PLIST_FILE && rm $PLIST_FILE"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "Setup complete."
echo ""

if [[ "$INSTALL_SERVICE" == false ]]; then
    echo "Run the dashboard:"
    echo "  $VENV/bin/python $SCRIPT_DIR/run.py"
    echo ""
    echo "Or install as a background agent:"
    echo "  bash $0 --service"
    echo ""
fi

echo "Dashboard:  http://localhost:8080"
echo "Settings:   http://localhost:8080/edit"
