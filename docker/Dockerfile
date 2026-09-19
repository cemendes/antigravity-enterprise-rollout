# Base Cloud Workstations Code-OSS image
FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

ARG AGY_VERSION="1.2.7"

USER root

# 1. Pre-bake Antigravity extension (.vsix) and backend hub binary (218 MB)
RUN mkdir -p /opt/antigravity/bin /etc/workstation-startup.d /opt/code-oss/data/Machine && \
    curl -fsSL -o /tmp/antigravity.vsix "https://storage.googleapis.com/antigravity-releases/extensions/google.antigravity-${AGY_VERSION}.vsix" && \
    code-oss --install-extension /tmp/antigravity.vsix && \
    rm -f /tmp/antigravity.vsix && \
    curl -fsSL "https://storage.googleapis.com/antigravity-releases/cli/linux_x64/agy-${AGY_VERSION}.tar.gz" | tar -xz -C /opt/antigravity/bin/ && \
    chmod +x /opt/antigravity/bin/agy

# 2. Install machine-level settings to disable auto-updates and manual checks
COPY config/machine-settings.json /opt/code-oss/data/Machine/settings.json
RUN chmod 644 /opt/code-oss/data/Machine/settings.json

# 3. Install workstation lifecycle startup hooks
COPY scripts/050_install_antigravity.sh /etc/workstation-startup.d/050_install_antigravity.sh
COPY scripts/999_antigravity_guard.sh /etc/workstation-startup.d/999_antigravity_guard.sh
RUN chmod +x /etc/workstation-startup.d/*.sh

# IMPORTANT: Never override ENTRYPOINT or CMD! Cloud Workstations relies on /google/scripts/entrypoint.sh
