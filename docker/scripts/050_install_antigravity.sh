#!/bin/bash
# Native Cloud Workstations Startup Hook for pre-installing Google Antigravity extension and backend
set -x
echo "[Antigravity Hook] Initializing Google Antigravity extension & backend before Code OSS starts..."

VSIX_PATH="/opt/extensions/Google.google-antigravity.vsix"
EXT_DIR="/home/user/.codeoss-cloudworkstations/extensions"
GEMINI_BIN_DIR="/home/user/.gemini/bin"
AGY_STATE_DIR="/home/user/.gemini/antigravity"
CODEOSS_DATA_MACHINE="/home/user/.codeoss-cloudworkstations/data/Machine"

# 1. Clean up any leftover Gemini CLI paths from user home
rm -rf /home/user/.gemini-cli /home/user/.config/gemini /home/user/.gemini/cli*

# 2. Ensure directories exist
mkdir -p "${EXT_DIR}" "${GEMINI_BIN_DIR}" "${AGY_STATE_DIR}" "${CODEOSS_DATA_MACHINE}" /run/user/1000
chown -R user:user /run/user/1000

# 3. Initialize D-Bus session bus to eliminate 30-second keyring timeout
if command -v dbus-daemon >/dev/null 2>&1; then
  echo "[Antigravity Hook] Initializing D-Bus session bus..."
  DBUS_ADDR=$(sudo -u user dbus-daemon --session --fork --print-address)
  if [ -n "${DBUS_ADDR}" ]; then
    echo "export DBUS_SESSION_BUS_ADDRESS=\"${DBUS_ADDR}\"" > /etc/profile.d/dbus-session.sh
    echo "DBUS_SESSION_BUS_ADDRESS=\"${DBUS_ADDR}\"" >> /etc/environment
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_ADDR}"
  fi
fi

# 4. Pre-seed the backend binary directly into ~/.gemini/bin/agy
if [ -f /opt/antigravity/bin/agy ]; then
  echo "[Antigravity Hook] Seeding backend binary into ${GEMINI_BIN_DIR}/agy..."
  cp -f /opt/antigravity/bin/agy "${GEMINI_BIN_DIR}/agy"
  chmod 755 "${GEMINI_BIN_DIR}/agy"
fi

# 5. Pre-seed Antigravity state (mark onboarding & migrations as completed)
if [ ! -f "${AGY_STATE_DIR}/antigravity_state.pbtxt" ]; then
  cat << 'EOF' > "${AGY_STATE_DIR}/antigravity_state.pbtxt"
post_onboarding: {
  completed_steps: POST_ONBOARDING_STEP_TYPE_MANAGER_WELCOME
  completed_steps: POST_ONBOARDING_STEP_TYPE_USAGE_MODE
  completed_steps: POST_ONBOARDING_STEP_TYPE_AGENT_CONFIGURATION
  completed_steps: POST_ONBOARDING_STEP_TYPE_ADD_WORKSPACE
}
migrate_convos_into_projects: MIGRATION_STATUS_COMPLETED
migrate_retroactive_projects: RETROACTIVE_MIGRATION_STATUS_COMPLETED_UNNECESSARY
migrations: { key: 3 value: MIGRATION_STATUS_COMPLETED }
migrations: { key: 4 value: MIGRATION_STATUS_COMPLETED }
migrations: { key: 5 value: MIGRATION_STATUS_COMPLETED }
EOF
fi

# 6. Configure Code-OSS Machine settings for Antigravity
cat << 'EOF' > "${CODEOSS_DATA_MACHINE}/settings.json"
{
  "update.mode": "none",
  "extensions.autoCheckUpdates": false,
  "extensions.autoUpdate": false,
  "app.autoCheckUpdates": false,
  "security.workspace.trust.enabled": false,
  "antigravity.serverUrl": "http://127.0.0.1:41969",
  "antigravity.serverPort": 41969
}
EOF

# 7. Set environment variables for Code-OSS session
echo "ANTIGRAVITY_SERVER_URL=http://127.0.0.1:41969" >> /etc/environment
echo "export ANTIGRAVITY_SERVER_URL=http://127.0.0.1:41969" > /etc/profile.d/antigravity.sh

# 7b. Pre-configure OAuth token symlinks for CLI and Hub
mkdir -p /home/user/.gemini/antigravity-cli /home/user/.gemini/antigravity
ln -sf /home/user/.gemini/jetski-standalone-oauth-token /home/user/.gemini/antigravity-cli/antigravity-oauth-token
ln -sf /home/user/.gemini/jetski-standalone-oauth-token /home/user/.gemini/antigravity/antigravity-oauth-token

# 8. Set ownership of user directory before running user commands
chown -R user:user /home/user/.codeoss-cloudworkstations /home/user/.gemini

# 9. Install extension into Code-OSS
if [ -f "${VSIX_PATH}" ]; then
  echo "[Antigravity Hook] Installing extension via codeoss-cloudworkstations..."
  sudo -u user /opt/code-oss/bin/codeoss-cloudworkstations \
    --extensions-dir "${EXT_DIR}" \
    --install-extension "${VSIX_PATH}" --force
fi

# 10. Start Antigravity Hub supervisor and token watcher daemon on port 41969 as user
echo "[Antigravity Hook] Launching Antigravity Hub supervisor daemon on port 41969..."
sudo -u user nohup /usr/local/bin/antigravity-hub-supervisor.sh </dev/null >/dev/null 2>&1 &

echo "[Antigravity Hook] Initialization complete."

