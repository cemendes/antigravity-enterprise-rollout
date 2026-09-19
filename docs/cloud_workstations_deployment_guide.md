# Google Cloud Workstations Deployment Guide: Google Antigravity (AGY)
*A technical engineering handbook for platform teams, DevOps, and SREs deploying version-controlled Antigravity environments inside secure Google Cloud perimeters.*

---

## 1. Overview & Architecture

Deploying Google Antigravity (AGY) inside **Google Cloud Workstations** provides organizations with an immutable, deterministic, and perimeter-isolated development sandbox. Source code, credentials, and model interactions remain strictly contained within your Google Cloud Virtual Private Cloud (VPC), with zero data residing on physical laptops.

```mermaid
graph TD
    subgraph "1. Network & Security Perimeter"
        VPC[Custom VPC: workstation-vpc] --> Subnet[Subnet: workstation-subnet<br/>Private Google Access Enabled<br/>disable_public_ip_addresses = true]
        IAM[Workstation SA: artifactregistry.reader, storage.objectUser]
    end

    subgraph "2. Container Build Pipeline"
        Docker[Dockerfile + machine-settings.json] --> CB[Cloud Build / GitHub Actions]
        CB --> AR[Artifact Registry: workstation-images<br/>custom-dev-image:v1.6.0]
    end

    subgraph "3. Workstation Infrastructure"
        Subnet --> Cluster[Workstation Cluster: enterprise-agy-cluster]
        Cluster --> Config[Workstation Config: agy-linux-stable<br/>Shielded VM + Attached SA]
        AR -.->|Pulls Private Container| Config
    end

    subgraph "4. Developer Runtime & Startup Lifecycle"
        Config --> WS[Developer Workstation: dev-demo-v8]
        WS --> StartupHook[/etc/workstation-startup.d/050_install_antigravity.sh<br/>Seeds ~/.gemini/bin/agy & sets up token symlinks]
        WS --> SupervisorDaemon[/usr/local/bin/antigravity-hub-supervisor.sh<br/>Maintains :41969 Hub loop & monitors token file]
        WS --> GuardHook[/etc/workstation-startup.d/999_antigravity_guard.sh<br/>Purges local extension overrides on boot]
        WS --> MachinePolicy[/opt/code-oss/data/Machine/settings.json<br/>update.mode=none]
        WS --> PersistentHome[(Persistent SSD: /home/user)]
    end
```

---

## 2. The 2-Tier Runtime Architecture & Pre-Baking Strategy

Antigravity operates across two distinct components inside Cloud Workstations:

1. **Frontend Editor Bridge (`.vsix`)**: Installed inside Code-OSS (`google.antigravity`), rendering the editor UI, sidebar panels, and inline code suggestions.
2. **Backend Hub Process (`~/.gemini/bin/agy`)**: A native Go binary that powers agentic planning, multi-file editing, tool execution, and communication with Google Cloud foundation models.

### The 218 MB Download Problem in Private Networks
If the backend binary `~/.gemini/bin/agy` is absent when Code-OSS activates the extension, the extension attempts to dynamically download a **218 MB** compressed archive (`cli_linux_x64.tar.gz`) from `storage.googleapis.com`.

The extension enforces a hard 15-second initialization deadline (`waitForServerReady`). In enterprise VPCs—where external egress is disabled, restricted, or inspected through corporate proxy firewalls—downloading and extracting 218 MB fails to complete within 15 seconds, throwing:
> `"Unable to start Antigravity. Could not connect to the update server. Please check your network connection and try again. Server failed to start at http://127.0.0.1:<port>"`

### The Pre-Baking Solution
We eliminate runtime downloads entirely by decoupling binary staging from runtime execution:

```
[Container Build Time]
  curl & extract agy binary (v1.2.7) ──► Staged at /opt/antigravity/bin/agy (root)

[Workstation Boot Time]
  /etc/workstation-startup.d/050_install_antigravity.sh ──► Copies to /home/user/.gemini/bin/agy

[Code-OSS Launch]
  Extension detects existing valid binary ──► Instant 0-second startup (No network download)
```

1. **Build Time**: Pre-stage the vetted binary inside `/opt/antigravity/bin/agy` in the container image.
2. **Boot Time**: Run `/etc/workstation-startup.d/050_install_antigravity.sh` on instance startup, copying `/opt/antigravity/bin/agy` into the developer's `/home/user/.gemini/bin/agy` before Code-OSS initializes.
3. **Instant Activation**: The extension detects the pre-existing binary and initializes instantly with **zero network overhead**.

---

## 3. Container Build Rules & Avoiding Traps

When building custom Cloud Workstations images, two engineering rules must be followed:

### Trap 1: Overriding `ENTRYPOINT` or `CMD`
```dockerfile
# ⚠️ NEVER DO THIS IN CLOUD WORKSTATIONS DOCKERFILES:
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/start.sh"]
```
* **Why this breaks**: Overriding `ENTRYPOINT` bypasses Google’s base initialization script (`/google/scripts/entrypoint.sh`). This prevents `/etc/workstation-startup.d/010_add-user.sh` from provisioning the unprivileged `user` account (UID 1000) and mounting the persistent disk, crashing the instance with a fatal `"no users found"` error.
* **The Rule**: **Leave `ENTRYPOINT` and `CMD` untouched.** Always place custom initialization logic inside executable scripts under `/etc/workstation-startup.d/`.

### Trap 2: User Extension Overrides on Persistent SSDs
Because `/home/user` is mounted to a persistent SSD across workstation restarts, a developer could manually install an unapproved `.vsix` into `~/.vscode-oss/extensions/`. In Code-OSS, user-level extensions override system-level extensions.
* **The Rule**: Add `/etc/workstation-startup.d/999_antigravity_guard.sh` to purge user-level overrides on every boot:
  ```bash
  #!/bin/bash
  rm -rf /home/user/.vscode-oss/extensions/google.antigravity-* 2>/dev/null || true
  rm -rf /home/user/.vscode/extensions/google.antigravity-* 2>/dev/null || true
  ```

---

## 4. Production Container Reference & Startup Hooks

### 1. `Dockerfile` Reference Snippet
```dockerfile
FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

ARG AGY_VERSION="1.2.7"

# 1. Pre-stage Antigravity extension and CLI binary in /opt
RUN mkdir -p /opt/antigravity/bin /etc/workstation-startup.d && \
    curl -fsSL -o /tmp/antigravity.vsix \
      "https://storage.googleapis.com/antigravity-releases/extensions/google.antigravity-${AGY_VERSION}.vsix" && \
    code-oss --install-extension /tmp/antigravity.vsix && rm /tmp/antigravity.vsix && \
    curl -fsSL "https://storage.googleapis.com/antigravity-releases/cli/linux_x64/agy-${AGY_VERSION}.tar.gz" \
      | tar -xz -C /opt/antigravity/bin/ && \
    chmod +x /opt/antigravity/bin/agy && \
    ln -sf /opt/antigravity/bin/agy /usr/local/bin/agy

# 2. Inject Machine-level lockdown settings
COPY config/machine-settings.json /opt/code-oss/data/Machine/settings.json

# 3. Inject startup scripts and supervisor daemon
COPY scripts/050_install_antigravity.sh /etc/workstation-startup.d/050_install_antigravity.sh
COPY scripts/999_antigravity_guard.sh /etc/workstation-startup.d/999_antigravity_guard.sh
COPY scripts/antigravity-hub-supervisor.sh /usr/local/bin/antigravity-hub-supervisor.sh
COPY scripts/agy-hub-restart /usr/local/bin/agy-hub-restart

RUN chmod +x /etc/workstation-startup.d/*.sh /usr/local/bin/antigravity-hub-supervisor.sh /usr/local/bin/agy-hub-restart
```

### 2. Machine Lockdown Configuration (`machine-settings.json`)
Placed at `/opt/code-oss/data/Machine/settings.json`:
```json
{
  "update.mode": "none",
  "extensions.autoCheckUpdates": false,
  "extensions.autoUpdate": false,
  "app.autoCheckUpdates": false
}
```

### 3. Startup Hook (`/etc/workstation-startup.d/050_install_antigravity.sh`)
```bash
#!/bin/bash
set -e

echo "[Antigravity] Seeding pre-baked agy binary..."
mkdir -p /home/user/.gemini/bin
cp -f /opt/antigravity/bin/agy /home/user/.gemini/bin/agy
chmod +x /home/user/.gemini/bin/agy

# Establish multi-directory token symlinks
mkdir -p /home/user/.gemini/antigravity-cli /home/user/.gemini/antigravity
ln -sf /home/user/.gemini/jetski-standalone-oauth-token /home/user/.gemini/antigravity-cli/antigravity-oauth-token
ln -sf /home/user/.gemini/jetski-standalone-oauth-token /home/user/.gemini/antigravity/antigravity-oauth-token
chown -R user:user /home/user/.gemini

# Start the Hub Supervisor in the background under user context
nohup su - user -c "/usr/local/bin/antigravity-hub-supervisor.sh" > /tmp/agy-supervisor.log 2>&1 &
```

---

## 5. Hub Supervisor & Automated Token Reloading

### The Problem: In-Memory Token Caching
When the Antigravity Hub (`agy --hub --hub-port=41969`) launches, it loads OAuth credentials into memory on startup. When a developer subsequently logs in via the CLI (`agy`), the newly written token on disk is **not automatically picked up** by the running Hub process without a process restart.

### The Solution: `/usr/local/bin/antigravity-hub-supervisor.sh`
The workstation runs a lightweight supervisor daemon that:
1. **Runs the Hub Loop**: Keeps `agy --hub --hub-port=41969 --app_data_dir=antigravity` active in an auto-respawn loop.
2. **Monitors Token Changes**: Checks the modification timestamp (`stat -c %Y`) of `/home/user/.gemini/jetski-standalone-oauth-token` every 2 seconds.
3. **Automated Zero-Downtime Reload**: When a token write occurs (e.g., login completed), the supervisor terminates the running Hub process (`pkill -f 'agy.*--hub'`). The outer loop catches the exit and immediately restarts the Hub within 1 second, loading the authenticated session (`gcp-ge-plus-tier`).
4. **On-Demand Helper**: Developers can also execute `agy-hub-restart` in the terminal to force an immediate reload.

---

## 6. Developer Workflows & Access Models

Developers can connect to their Cloud Workstations environment through three validated workflows:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Option A: Browser-Only (Port 80 Code-OSS + Port 41969 Antigravity Web Hub)   │
│ - Code-OSS: https://80-<workstation>.<cluster>.cloudworkstations.dev/       │
│ - Antigravity Hub: https://41969-<workstation>.<cluster>.cloudworkstations.dev│
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ Option B: Desktop IDE via Secure Tunnel (Port 22 SSH or Port 41969 Hub)      │
│ - gcloud workstations start-tcp-tunnel <workstation> 22                     │
│ - Connect Desktop VS Code / Antigravity via Remote - SSH                    │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ Option C: Antigravity CLI (agy) Terminal Access                             │
│ - Built-in interactive agent inside Code-OSS terminal or SSH session         │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Validated Developer Onboarding Flow
1. **Open Terminal**: In Code-OSS (`https://80-.../?authuser=0`), press `Ctrl + \`` to open the integrated terminal.
2. **Initiate Login**: Run `agy`. Select **Log In** &rarr; **Google Account**.
3. **Authorize**: Open the generated URL in a browser tab, log in with your corporate Google identity (`@yourcompany.com`), and copy the redirected URL. Paste it back into the terminal.
4. **Auto-Reload**: The supervisor detects the token write within 2 seconds and reloads the Hub daemon in the background.
5. **Open Antigravity Web Hub**: Navigate to `https://41969-.../?authuser=0` in a parallel browser tab—fully authenticated and ready for agent development.

---

## 7. Known Platform Bug: Code-OSS Sidebar Iframe (`b/563594437`)

> **Buganizer Tracking**: Internal Bug **[b/563594437](http://b/563594437)** (P2, Assigned to Antigravity Extension Engineering).

### The Symptom
Inside browser-based Code-OSS (Port 80), clicking the Antigravity sidebar icon displays:
`workstations.cloud.google.com refused to connect`

### Root Cause
1. **Subdomain Isolation**: Code-OSS maps the backend Hub on port 41969 to a separate subdomain (`https://41969-...cloudworkstations.dev/`).
2. **Nested Iframe CSP**: Extension webviews run inside a sandboxed iframe on `https://<uuid>.cloudworkstations.googleusercontent.com`.
3. **Cookie & CSP Block**: Chrome blocks third-party cookie forwarding across nested frames, triggering a redirect to the Google login page. The gateway sends `Content-Security-Policy: frame-ancestors 'self'`, causing Chrome to block the inner frame.

### Recommended Workaround
Until `b/563594437` is resolved by Cloud Workstations engineering, teams should adopt:
* **Option A**: Use the **Standalone Antigravity Web Hub** (`:41969`) in a dedicated browser tab side-by-side with Code-OSS.
* **Option B**: Connect via **Desktop VS Code** using `gcloud workstations start-tcp-tunnel <workstation> 22`, where sidebar webviews execute natively.

---

## 8. Rollout & Maintenance Lifecycle (CI/CD)

Promoting a new Antigravity version across the fleet follows a deterministic GitOps / Terraform workflow:

1. **Test New Release**: Bump `ARG AGY_VERSION="1.2.8"` in `docker/Dockerfile`.
2. **Build & Push**:
   ```bash
   docker build -t us-central1-docker.pkg.dev/${PROJECT_ID}/workstations/custom-dev-image:v1.7.0 docker/
   docker push us-central1-docker.pkg.dev/${PROJECT_ID}/workstations/custom-dev-image:v1.7.0
   ```
3. **Update Terraform Configuration**:
   ```hcl
   # terraform.tfvars
   workstation_image_tag = "v1.7.0"
   ```
   ```bash
   terraform apply
   ```
4. **Workstation Instance Cycling**: When workstations stop and restart (or cycle during scheduled nightly maintenance), instances pull the new container tag. Persistent SSDs in `/home/user` remain untouched, while all system tooling upgrades seamlessly.

---

## 9. Related Guides & Resources

* 🛡️ **Enterprise Governance & MDM**: See the [Enterprise Governance & Version Control Guide](enterprise_governance_and_version_control.md) for local laptop policies and compliance ring strategies.
* 📦 **Production Repository**: Turnkey Terraform modules and Docker build configurations are available at [github.com/cemendes/antigravity-enterprise-rollout](https://github.com/cemendes/antigravity-enterprise-rollout).
