#!/bin/bash
# Executed automatically on every workstation start
# Purges user-installed extension overrides on persistent disk to enforce the container-baked version

echo "[Antigravity Guard] Purging user-installed extension overrides..."
rm -rf /home/user/.vscode-oss/extensions/google.antigravity-* 2>/dev/null || true
rm -rf /home/user/.vscode/extensions/google.antigravity-* 2>/dev/null || true
