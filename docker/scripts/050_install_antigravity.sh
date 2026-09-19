#!/bin/bash
set -euo pipefail

# Executed by Cloud Workstations during container boot before Code-OSS launches.
# Pre-seeds the 218 MB backend hub binary to prevent dynamic download timeouts.

USER_GEMINI_BIN="/home/user/.gemini/bin"

echo "[Antigravity Hook] Initializing Antigravity backend hub..."
mkdir -p "${USER_GEMINI_BIN}"

if [ -f "/opt/antigravity/bin/agy" ]; then
    cp -f /opt/antigravity/bin/agy "${USER_GEMINI_BIN}/agy"
    chmod +x "${USER_GEMINI_BIN}/agy"
    chown -R user:user /home/user/.gemini
    echo "[Antigravity Hook] Successfully seeded agy binary to ${USER_GEMINI_BIN}/agy"
else
    echo "[Antigravity Hook] ERROR: Pre-baked binary /opt/antigravity/bin/agy not found!" >&2
    exit 1
fi
