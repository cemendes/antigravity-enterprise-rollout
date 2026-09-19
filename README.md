# Enterprise Version Control & Rollout: Google Antigravity 2.0 (AGY)

> Production-ready reference architecture, Terraform modules, Docker runtime recipes, and MDM policy payloads to deploy and version-control Google Antigravity across Google Cloud Workstations and enterprise developer endpoints.

---

## 1. Executive Summary & Scope

Developer AI tools typically default to continuous background auto-updates. In enterprise environments, unmanaged client updates can disrupt compliance, introduce unvetted dependencies, or violate internal change control standards. 

This repository provides two governed deployment models:

1. **Google Cloud Workstations (Recommended)**: Provision remote developer workstations on Google Cloud with the approved Antigravity version pre-baked into a custom container image. Auto-updates are completely disabled inside the workstation environment, giving your platform team deterministic control over updates via Infrastructure-as-Code (Terraform + Artifact Registry).
2. **Local Endpoints via Enterprise MDM**: Govern developer laptops across macOS, Windows, and Linux using Jamf Pro, Microsoft Intune, or Ansible. Machine-level policies lock update modes and grey out manual update checks in developer IDEs.

> [!NOTE]
> **Enterprise Scope & Compliance Notice**:  
> This repository covers enterprise deployment and version control of Antigravity 2.0 (AGY) across **Google Cloud Workstations**, the official **VS Code extension**, and the official **JetBrains plugin**. It specifically **does not cover the standalone Antigravity IDE desktop application**, which is a consumer preview product and is not covered under the Google Cloud Business Associate Agreement (BAA) or enterprise commercial terms.

---

## 2. Strategic Decision Matrix

| Dimension | Google Cloud Workstations | Local Laptops via Enterprise MDM |
| :--- | :--- | :--- |
| **Data Governance & Exfiltration** | **100% Perimeter Isolation**. The developer machine acts as a display terminal. Code, secrets, and agent loops execute inside your GCP VPC. <br/><br/>*Note on Clipboard*: Cloud Workstations does not include a native toggle to block copy/paste; enforcing clipboard isolation requires [BeyondCorp Enterprise Threat and Data Protection](https://cloud.google.com/beyondcorp-enterprise/docs/protect-sensitive-data) or Chrome Enterprise DLP policies. | **Shared Boundary**. Source code resides on physical local drives. If developers have local root/admin access, configuration policies are managed guardrails that can be bypassed unless paired with strict EDR application hash whitelisting (CrowdStrike / Carbon Black). |
| **Environment Determinism** | **Bit-for-Bit Identical**. Every developer runs from an immutable container image hosted in Artifact Registry. Toolchains and extensions are guaranteed consistent across the fleet. | **Fleet Variation**. Prone to configuration drift across OS versions, local environment variables, and user-level customizations. |
| **Mobility & Offline Access** | **Always-Connected**. Requires an active internet connection to access the remote workstation instance. | **Hybrid Offline**. Developers can view, edit, and compile code locally without internet. However, **all Antigravity AI capabilities (reasoning, chat, and agent execution) require an active internet connection** to query Google Cloud models; AGY cannot be routed to local LLMs. |
| **Operational & Change Management** | **Managed as Code (IaC)**. Managed via Terraform and CI/CD (Cloud Build, GitHub Actions, GitLab CI). Releasing an update means publishing a new container tag to Artifact Registry and cycling instances. | **Centralized IT Policies**. Managed by corporate IT via `.mobileconfig` profiles, Intune PowerShell remediation scripts, and phased deployment rings. |

---

## 3. Architecture Overview

```mermaid
graph TD
    subgraph "1. Network & Security Perimeter"
        VPC[Custom VPC] --> Subnet[Workstation Subnet<br/>Private Google Access Enabled<br/>disable_public_ip_addresses = true]
        IAM[IAM Roles: storage.objectUser, artifactregistry.reader]
    end

    subgraph "2. Container Build Pipeline"
        Docker[Dockerfile + machine-settings.json] --> CI[Cloud Build / GitHub Actions / GitLab CI]
        CI --> AR[Artifact Registry: workstation-images<br/>custom-dev-image:v1.6.0]
    end

    subgraph "3. Workstation Infrastructure"
        Subnet --> Cluster[Workstation Cluster: enterprise-workstations]
        Cluster --> Config[Workstation Config: agy-linux-stable<br/>Shielded VM + Attached SA]
        AR -.->|Pulls Private Container| Config
    end

    subgraph "4. Developer Runtime & Startup Lifecycle"
        Config --> WS[Developer Workstation: dev-user]
        WS --> StartupHook[/etc/workstation-startup.d/050_install_antigravity.sh<br/>Seeds ~/.gemini/bin/agy before Code-OSS boots]
        WS --> GuardHook[/etc/workstation-startup.d/999_antigravity_guard.sh<br/>Purges local extension overrides on boot]
        WS --> MachinePolicy[/opt/code-oss/data/Machine/settings.json<br/>update.mode=none]
        WS --> PersistentHome[(Persistent SSD: /home/user)]
    end
```

---

## 4. Repository Structure

```text
.
├── docker/
│   ├── Dockerfile                         # Custom Cloud Workstations image pre-baking AGY
│   ├── config/
│   │   └── machine-settings.json          # Machine-level policy disabling auto-updates
│   └── scripts/
│       ├── 050_install_antigravity.sh     # Startup hook seeding agy and starting supervisor
│       ├── 999_antigravity_guard.sh       # Startup hook purging user-level extension overrides
│       ├── antigravity-hub-supervisor.sh  # Persistent Hub daemon with token auto-reload
│       └── agy-hub-restart                # CLI utility to restart Hub and reload credentials
├── docs/
│   ├── enterprise_governance_and_version_control.md # IT Admin, MDM policies, auto-updates & compliance
│   ├── cloud_workstations_deployment_guide.md       # Platform Eng & DevOps deployment handbook
│   └── antigravity_cloud_workstations_handover.md   # Cloud Workstations validation & known issues handover
├── terraform/
│   ├── versions.tf                        # Terraform and Google provider constraints
│   ├── variables.tf                       # Configurable parameters (image tag, machine type, etc.)
│   ├── main.tf                            # Cluster, Workstation Config, and IAM bindings
│   ├── outputs.tf                         # Deployed resource identifiers
│   └── terraform.tfvars.example           # Example variable definitions
├── ci-cd/
│   ├── cloudbuild.yaml                    # Google Cloud Build pipeline definition
│   └── github-actions-workflow.yml        # GitHub Actions reference workflow
└── mdm/
    ├── macos/
    │   ├── com.google.antigravity.mobileconfig # macOS Jamf/Intune configuration profile
    │   └── DisableAntigravity2AutoUpdate.sh    # macOS Jamf Pro / Munki post-install script
    ├── windows/
    │   └── DisableVSCodeAutoUpdate.ps1 # Windows Intune remediation PowerShell script
    └── linux/
        └── playbook.yml                      # Linux Ansible policy enforcement playbook
```

---

## 5. Quickstart: Cloud Workstations Deployment

### Prerequisites
* A Google Cloud project with billing enabled.
* Google Cloud CLI (`gcloud`) authenticated (`gcloud auth login`).
* Terraform `>= 1.5.0` installed.
* Docker installed locally or access to Cloud Build.
* A VPC subnet with Private Google Access enabled and external IP creation disabled.

### Step 1: Build & Stage the Container Image

The Dockerfile decouples extension installation from runtime execution by pre-baking the **218 MB** backend binary (`agy`) directly into the image:

```bash
PROJECT_ID="your-gcp-project-id"
LOCATION="us-central1"
REPO="workstation-images"
IMAGE_NAME="custom-dev-image"
IMAGE_TAG="v1.6.0"
AGY_VERSION="1.2.5"

# Build image
docker build \
  --build-arg AGY_VERSION="${AGY_VERSION}" \
  -t "${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE_NAME}:${IMAGE_TAG}" \
  -t "${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE_NAME}:latest" \
  ./docker

# Configure Docker auth and push
gcloud auth configure-docker ${LOCATION}-docker.pkg.dev --quiet
docker push --all-tags "${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE_NAME}"
```

### Step 2: Deploy Infrastructure via Terraform

1. Navigate to the `terraform/` directory:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```
2. Edit `terraform.tfvars` with your project ID, VPC self-links, and desired region.
3. Initialize and apply:
   ```bash
   terraform init
   terraform apply
   ```

### Step 3: Developer Access Models & Workflows

Once the workstation instance is in `STATE_RUNNING`, developers have two validated access options:

#### Option A: Browser-Only / Zero Local Setup (Side-by-Side)
* **Code-OSS Web IDE (Port 80)**: Open `https://<workstation-name>.<cluster-name>.cloudworkstations.dev/?authuser=0` for code editing, terminal commands, and file management.
* **Standalone Antigravity Web Hub (Port 41969)**: Open `https://41969-<workstation-name>.<cluster-name>.cloudworkstations.dev/?authuser=0` in a dedicated browser tab side-by-side. 
* **Capabilities**: 100% functional OAuth, chat conversations, agent workflows, diff viewer, and Gemini Enterprise inference.

#### Option B: Native Desktop IDE Experience via SSH Tunnel
Connect your local Desktop VS Code / Antigravity client to the remote workstation:
```bash
# 1. Establish secure TCP tunnel for SSH (Port 22)
gcloud workstations start-tcp-tunnel <workstation-name> 22 \
  --cluster=<cluster-name> \
  --config=agy-linux-stable \
  --region=<region> \
  --project=<project-id>

# 2. Or establish direct tunnel for Antigravity Hub (Port 41969)
gcloud workstations start-tcp-tunnel <workstation-name> 41969:41969 \
  --cluster=<cluster-name> \
  --config=agy-linux-stable \
  --region=<region> \
  --project=<project-id>
```
Connect via VS Code Remote - SSH to `localhost:22`. The Antigravity extension sidebar runs natively without encountering browser CSP restrictions.

#### Option C: Antigravity CLI (`agy`) Terminal Access
The CLI binary is installed globally in system PATH (`/usr/local/bin/agy`) and pre-configured to use the synchronized OAuth credentials:
* **Inside Code-OSS**: Open the integrated terminal (`Ctrl + \``) and run `agy` for interactive mode or `agy -p "prompt"` for automated runs.
* **Direct SSH from local laptop**: Run `gcloud workstations ssh <workstation-name> --cluster=<cluster-name> --config=agy-linux-stable --region=<region> --project=<project-id>` and run `agy` directly.

### Recommended Developer Onboarding Flow (CLI-First + Auto-Reloading Hub)
Because Cloud Workstations runs behind Google Cloud's web preview reverse proxy, OAuth loopback redirects cannot automatically post back to the remote container browser session without manual token copy. The validated, 100% reliable onboarding flow is:

1. **Step 1 — Start Workstation & Open Code-OSS**:
   Launch your workstation and navigate to `https://<workstation>.<cluster>.cloudworkstations.dev/?authuser=0`.
2. **Step 2 — Run CLI Login**:
   Open the integrated terminal in Code-OSS (`Ctrl + \``) and run:
   ```bash
   agy
   ```
   Select **Log In** &rarr; **Google Account**.
3. **Step 3 — Consent & Paste Code**:
   Open the OAuth URL in your browser, approve permissions for your corporate account (`@yourcompany.com`), and copy the final redirected URL (containing `auth_code`). Paste it back into the CLI prompt.
4. **Step 4 — Automated Hub Reload (Zero Extra Steps)**:
   The CLI exchanges the code and writes the token to `/home/user/.gemini/jetski-standalone-oauth-token`. Within 2 seconds, the container's background **Hub Supervisor** detects the new file, restarts the Hub process on port `41969`, and loads the authenticated session (`gcp-ge-plus-tier`).
5. **Step 5 — Open Antigravity Standalone UI**:
   Open `https://41969-<workstation>.<cluster>.cloudworkstations.dev/?authuser=0` in a side-by-side browser tab. The web app is fully logged in and ready for agent development.

### Token Lifecycle & Expiration Dynamics
* **Access Token**: Valid for **1 hour** (OAuth 2.0 Bearer).
* **Refresh Token**: **Long-lived / Indefinite**. Stored persistently inside the token file on the 100 GB persistent SSD (`/home`). Subject only to Google Workspace Admin session duration controls or manual revocation.
* **Silent Background Refresh**: Both the Antigravity Web Hub and `agy` CLI automatically refresh the 1-hour access token in the background using the stored refresh token, without interrupting developer work.
* **Persistence Across Upgrades**: Because `/home` is preserved on the persistent disk, refresh tokens survive all container redeployments, maintenance cycles, and workstation reboots.

---

## 6. Operational Lifecycle: How to Release Updates

Promoting updates across your Cloud Workstations fleet follows a deterministic 5-step workflow:

### 1. Discover and Verify the Latest Release
Before triggering a build, inspect the latest approved Antigravity release:
```bash
# Check the latest release metadata manifest
curl -fsSL https://storage.googleapis.com/antigravity-releases/latest.json | jq .

# Or query the latest CLI version string directly
curl -fsSL https://storage.googleapis.com/antigravity-releases/cli/latest_version.txt
```
Review the official release notes at [cloud.google.com/antigravity/docs/release-notes](https://cloud.google.com/antigravity/docs/release-notes).

To verify the currently active version in your deployed image:
```bash
docker run --rm us-central1-docker.pkg.dev/${PROJECT_ID}/workstations/custom-dev-image:${CURRENT_TAG} /opt/antigravity/bin/agy --version
```

### 2. Build & Stage the New Container
Update the `ARG AGY_VERSION="<new-version>"` in `./docker/Dockerfile` and build:
```bash
docker build --build-arg AGY_VERSION="1.2.0" -t ... ./docker
docker push ...
```

### 3. Promote via Terraform
Update the `workstation_image_tag` variable:
```bash
terraform apply -var="workstation_image_tag=v1.7.0"
```

### 4. Cycle Workstations
When developers restart their workstations at the end of the day or during scheduled maintenance windows, the VM pulls the new container image tag. Code in `/home/user` persists intact on persistent SSDs while toolchains upgrade seamlessly.

---

## 7. Enterprise Implementation Considerations & Field Insights

### 1. The 218 MB Backend Hub Timeout
* **Symptom**: On editor startup, the extension crashes with `Unable to start Antigravity... Server failed to start at http://127.0.0.1:<port>`.
* **Root Cause**: The VS Code extension is a frontend presentation layer; it spawns `~/.gemini/bin/agy --hub`. In private VPCs without direct egress, downloading the 218 MB backend archive on the fly exceeds the extension's hardcoded 15-second initialization timeout.
* **Solution**: Pre-bake `/opt/antigravity/bin/agy` in Docker and seed it to `/home/user/.gemini/bin/agy` via `/etc/workstation-startup.d/050_install_antigravity.sh` on boot for an instant 0-second launch.

### 2. The Custom Container `ENTRYPOINT` Trap
* **Symptom**: Workstation container fails to boot with `"no users found"`.
* **Root Cause**: Overriding `ENTRYPOINT` or `CMD` in the Dockerfile clobbers Google's `/google/scripts/entrypoint.sh`, skipping user creation (`010_add-user.sh`) and home volume mounts.
* **Solution**: Never override `ENTRYPOINT` or `CMD`. Always place custom startup logic inside `/etc/workstation-startup.d/`.

### 3. Extension Overrides on Persistent Disks
* **Symptom**: Developers manually install a different `.vsix` into `~/.vscode-oss/extensions/`, overriding the corporate-mandated version.
* **Solution**: Deploy `/etc/workstation-startup.d/999_antigravity_guard.sh` to purge user-installed extension overrides on every workstation boot.

### 4. Known Platform Limitation: Browser Code-OSS Sidebar Iframe
* **Symptom**: Inside browser-based Code-OSS (`https://80-...cloudworkstations.dev/`), clicking the Antigravity sidebar icon fails to render the `#jetski-frame` with:
  > `workstations.cloud.google.com refused to connect`
* **Root Cause**:
  1. *Subdomain Rewrite*: Code-OSS resolves `http://127.0.0.1:41969` to `https://41969-...cloudworkstations.dev`.
  2. *Cross-Site Iframe Isolation*: Webviews are rendered inside sandboxed iframes hosted on `https://<uuid>.cloudworkstations.googleusercontent.com`.
  3. *Cookie Drop*: Third-party cookies (`WorkstationJwt`) are blocked in Chrome within that nested iframe, prompting an auth redirect.
  4. *CSP `frame-ancestors` Restriction*: The auth endpoint restricts `frame-ancestors` to `'self'`, blocking standard Cloud Workstation clusters from embedding the auth screen in a nested iframe.
* **Workarounds**:
  - **Browser Flow**: Open the Antigravity Web Hub directly in a dedicated tab (`https://41969-...cloudworkstations.dev/?authuser=0`).
  - **Desktop Flow**: Connect local Desktop IDE via `gcloud workstations start-tcp-tunnel` over SSH / port 41969.

### 5. Multi-Directory OAuth Token Synchronization
* **Symptom**: After authenticating in the Web UI or Code-OSS, running `agy` in terminal fails with:
  > `error getting token source: You are not logged into Antigravity`
* **Root Cause**: The Antigravity Hub stores credentials in `~/.gemini/jetski-standalone-oauth-token`, but the CLI runtime checks `~/.gemini/antigravity-cli/antigravity-oauth-token` and `~/.gemini/antigravity/antigravity-oauth-token`.
* **Solution**: Handled automatically in `050_install_antigravity.sh` by pre-creating symlinks pointing both CLI paths to `jetski-standalone-oauth-token` on boot.

### 6. Hub In-Memory State & Automated Watcher Reloading
* **Symptom**: After successfully authenticating in the CLI, the Standalone Web Hub (`:41969`) remains unauthenticated or shows a login button.
* **Root Cause**: The Antigravity language server daemon reads token files from disk on boot. If the daemon starts prior to the user's first login, it caches the unauthenticated state in memory and does not poll the filesystem for new tokens.
* **Solution**: Managed by `/usr/local/bin/antigravity-hub-supervisor.sh`:
  1. *Respawn Loop*: Keeps `agy --hub` persistently active.
  2. *Token Watcher*: Continuously monitors the `mtime` of `/home/user/.gemini/jetski-standalone-oauth-token`. When a new token is created or refreshed, it terminates the stale Hub process (`pkill -f 'agy.*--hub'`).
  3. The supervisor loop immediately restarts the Hub, loading the fresh `gcp-ge-plus-tier` credentials seamlessly.
* **Manual Control**: Developers can run `agy-hub-restart` at any time to force a credential reload.

---

## 8. License & Disclaimers

Licensed under the **Apache License, Version 2.0** (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0).

### Disclaimer
* **Not an Officially Supported Google Product**: This repository is an open-source community reference architecture provided for informational and educational purposes. It is not an officially supported Google product or service.
* **Shared Responsibility**: Users and enterprise organizations remain responsible for verifying their own security, compliance, and regulatory requirements when deploying infrastructure on Google Cloud.
* **Trademarks**: All product names, trademarks, and registered trademarks (including Jamf Pro, Microsoft Intune, Microsoft Defender for Endpoint, CrowdStrike Falcon, Docker, and Terraform) are property of their respective owners. Mention of these platforms does not imply endorsement or affiliation.
