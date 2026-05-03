#!/usr/bin/env bash
set -euo pipefail

SRC="$HOME/.config/google-chrome/Default/History"
TMP="/tmp/_chrome_history_sync_$$"
DEST="neptune:/home/paul/HomeDashboard/chrome_history"

if [[ ! -f "$SRC" ]]; then
    echo "$(date): Chrome history not found at $SRC" >&2
    exit 1
fi

cp "$SRC" "$TMP"
rsync -q "$TMP" "$DEST"
rm -f "$TMP"
