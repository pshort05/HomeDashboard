#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$SCRIPT_DIR/.venv"
SERVICE_NAME="homedashboard"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
INSTALL_SERVICE=false

# ── Argument parsing ──────────────────────────────────────────────────────────

usage() {
    echo "Usage: $0 [--service]"
    echo ""
    echo "  --service   Also install and start a systemd user service"
    exit 1
}

for arg in "$@"; do
    case "$arg" in
        --service) INSTALL_SERVICE=true ;;
        *) usage ;;
    esac
done

# ── Python discovery ──────────────────────────────────────────────────────────

if command -v python3.12 &>/dev/null; then
    PYTHON=python3.12
elif command -v python3.11 &>/dev/null; then
    PYTHON=python3.11
elif command -v python3 &>/dev/null; then
    PYTHON=python3
else
    echo "error: python3 not found in PATH" >&2
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

# ── Configuration ─────────────────────────────────────────────────────────────

if [[ ! -f "$SCRIPT_DIR/config.json" ]]; then
    echo "Creating config.json from sample..."
    cp "$SCRIPT_DIR/config.json.sample" "$SCRIPT_DIR/config.json"
    echo "  Edit $SCRIPT_DIR/config.json to customise your dashboard."
else
    echo "config.json already exists."
fi

# ── Systemd user service (optional) ──────────────────────────────────────────

if [[ "$INSTALL_SERVICE" == true ]]; then
    mkdir -p "$(dirname "$SERVICE_FILE")"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=HomeDashboard
After=network.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$VENV/bin/python $SCRIPT_DIR/run.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE_NAME"
    systemctl --user restart "$SERVICE_NAME"

    echo ""
    echo "Service installed and started."
    echo "  Status:  systemctl --user status $SERVICE_NAME"
    echo "  Logs:    journalctl --user -u $SERVICE_NAME -f"
    echo "  Stop:    systemctl --user stop $SERVICE_NAME"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "Setup complete."
echo ""

if [[ "$INSTALL_SERVICE" == false ]]; then
    echo "Run the dashboard:"
    echo "  $VENV/bin/python $SCRIPT_DIR/run.py"
    echo ""
    echo "Or install as a background service:"
    echo "  bash $0 --service"
    echo ""
fi

echo "Dashboard:  http://localhost:8080"
echo "Settings:   http://localhost:8080/edit"
