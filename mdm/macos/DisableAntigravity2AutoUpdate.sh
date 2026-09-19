#!/bin/bash
# ==============================================================================
# DisableAntigravity2AutoUpdate.sh
#
# Jamf Pro / Munki / MDM Post-Install Script for macOS Endpoints
# Purpose: Enforces corporate version lock for Google Antigravity 2.0 by:
#   1. Enforcing system-wide environment variable AGY_CLI_DISABLE_AUTO_UPDATE=1
#      via /etc/zshenv and /etc/profile.
#   2. Adding a DNS sinkhole entry in /etc/hosts for the auto-updater endpoint.
# ==============================================================================

set -euo pipefail

DOMAIN="antigravity-cli-auto-updater-974169037036.us-central1.run.app"
SINKHOLE_ENTRY="0.0.0.0 ${DOMAIN}"
ENV_VAR_LINE="export AGY_CLI_DISABLE_AUTO_UPDATE=1"

echo "Applying Google Antigravity 2.0 corporate version lock..."

# 1. Enforce environment variable for zsh (default macOS shell) and bash
for env_file in "/etc/zshenv" "/etc/profile"; do
    if [ ! -f "$env_file" ]; then
        touch "$env_file"
        chmod 644 "$env_file"
    fi

    if ! grep -q "AGY_CLI_DISABLE_AUTO_UPDATE" "$env_file"; then
        echo "" >> "$env_file"
        echo "# Antigravity 2.0 Auto-Updater Lock" >> "$env_file"
        echo "$ENV_VAR_LINE" >> "$env_file"
        echo "Configured $env_file with $ENV_VAR_LINE"
    else
        echo "$env_file already configured with AGY_CLI_DISABLE_AUTO_UPDATE."
    fi
done

# 2. Add DNS sinkhole to /etc/hosts
HOSTS_FILE="/etc/hosts"
if ! grep -q "$DOMAIN" "$HOSTS_FILE"; then
    echo "" >> "$HOSTS_FILE"
    echo "# Antigravity 2.0 Auto-Updater Sinkhole" >> "$HOSTS_FILE"
    echo "$SINKHOLE_ENTRY" >> "$HOSTS_FILE"
    echo "Added DNS sinkhole for $DOMAIN in $HOSTS_FILE"
else
    echo "DNS sinkhole already present in $HOSTS_FILE"
fi

# 3. Flush macOS DNS cache
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true

echo "Successfully applied Antigravity 2.0 version lock on macOS."
exit 0
