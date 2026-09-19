#!/bin/bash
# Antigravity Hub Supervisor and Token Watcher Daemon
set -u

TOKEN_FILE="/home/user/.gemini/jetski-standalone-oauth-token"
HUB_LOG="/home/user/.gemini/antigravity/hub.log"

export AGY_ENABLE_HUB=1
export ANTIGRAVITY_VSCODE_HOST=1
export ANTIGRAVITY_SERVER_URL="http://127.0.0.1:41969"

# Process 1: Token file watcher in background
watch_token() {
  local last_mtime=0
  if [ -f "$TOKEN_FILE" ]; then
    last_mtime=$(stat -c %Y "$TOKEN_FILE" 2>/dev/null || echo 0)
  fi

  while true; do
    sleep 2
    if [ -f "$TOKEN_FILE" ]; then
      current_mtime=$(stat -c %Y "$TOKEN_FILE" 2>/dev/null || echo 0)
      if [ "$current_mtime" -ne "$last_mtime" ]; then
        echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [Supervisor] Token change detected ($last_mtime -> $current_mtime). Restarting Hub..." >> "$HUB_LOG"
        last_mtime="$current_mtime"
        pkill -f "agy.*--hub" 2>/dev/null || true
      fi
    else
      last_mtime=0
    fi
  done
}

watch_token &
WATCHER_PID=$!

cleanup() {
  kill "$WATCHER_PID" 2>/dev/null || true
  pkill -f "agy.*--hub" 2>/dev/null || true
  exit 0
}
trap cleanup SIGTERM SIGINT

# Process 2: Hub auto-respawn loop
echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [Supervisor] Starting Antigravity Hub loop on port 41969..." >> "$HUB_LOG"
while true; do
  /home/user/.gemini/bin/agy --hub --hub-port=41969 --app_data_dir=antigravity >> "$HUB_LOG" 2>&1
  EXIT_CODE=$?
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [Supervisor] Antigravity Hub exited with code $EXIT_CODE. Respawning in 1s..." >> "$HUB_LOG"
  sleep 1
done
