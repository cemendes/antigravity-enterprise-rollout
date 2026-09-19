# Enterprise Governance & Version Control Guide: Google Antigravity (AGY)
*A strategic blueprint for IT administrators, CISOs, and security teams managing AI developer tooling, auto-updates, and compliance across enterprise fleets.*

---

## 1. Executive Summary & Strategic Dilemma

### The Enterprise Dilemma
Modern generative AI developer tools—including Google Antigravity (AGY)—are designed for rapid innovation, defaulting to continuous background auto-updates. In enterprise environments, however, unmanaged client updates present critical organizational risks:
* **Compliance & Audit Violations**: Tooling updates can introduce unauthorized features, modified data telemetry, or changed network egress paths that violate SOC 2, ISO 27001, HIPAA, or internal change control policies.
* **Developer Environment Breakage**: Silent background updates can introduce breaking CLI flags, alter language server dependencies, or cause unexpected incompatibilities with corporate proxies and VPNs.
* **Configuration Drift**: Without centralized version pinning, different engineers across the organization end up running different software versions, complicating debugging and support.

### The Objective
This guide provides platform teams and security administrators with a deterministic framework to:
1. **Completely disable client-side background auto-updates** across VS Code and JetBrains IDE environments.
2. **Centrally lock and manage Antigravity versions** using existing enterprise device management (MDM) fleet tooling (Jamf Pro, Microsoft Intune, Ansible).
3. **Establish a phased release ring governance process** (Ring 0 / Ring 1 / Ring 2) to validate new releases before fleet-wide general availability.

> [!NOTE]
> **Enterprise Scope & Compliance Notice**:  
> This guide covers enterprise deployment and version control of Antigravity (AGY) across **Google Cloud Workstations**, the official **VS Code extension** (`Google.google-antigravity`), and the official **JetBrains plugin**. It specifically **does not cover the standalone Antigravity IDE application**, which is a consumer preview product and is not covered under the Google Cloud Business Associate Agreement (BAA) or enterprise commercial terms.

---

## 2. Strategic Decision Matrix: Choosing Your Deployment Model

Enterprise security and platform teams have two primary models for deploying and version-controlling Antigravity:

```mermaid
graph TD
    A[Enterprise Antigravity Rollout] --> B{Choose Operating Model}
    B -->|High Security / Regulated Data / Contractors| C[Path 1: Google Cloud Workstations]
    B -->|Full-Time Core Engineers / Native Hardware| D[Path 2: Physical Laptops via Enterprise MDM]

    C --> C1[100% Perimeter Isolation in Private VPC]
    C --> C2[Immutable Docker Containers in Artifact Registry]
    C --> C3[Managed via Terraform & Cloud Build]

    D --> D1[OS-Level Administrative Policies Override User Settings]
    D --> D2[Jamf Pro macOS .mobileconfig / Intune Registry / Ansible]
    D --> D3[Phased Deployment Rings + Optional EDR Hash Whitelisting]
```

### Core Comparison Dimensions

| Dimension | Google Cloud Workstations | Physical Laptops via Enterprise MDM |
| :--- | :--- | :--- |
| **Data Governance & Exfiltration** | **100% Perimeter Isolation**. The developer's physical machine operates purely as a display terminal. Source code, secrets, and agent interactions remain strictly within your private Google Cloud VPC perimeter. | **Shared Boundary**. Source code and configuration files reside on physical local storage. Local policies act as managed guardrails unless paired with strict EDR application hash whitelisting. |
| **Environment Determinism** | **Bit-for-Bit Identical**. Every developer runs from an immutable container image hosted in Artifact Registry. Toolchains, extensions, and configurations are guaranteed consistent across the entire fleet. | **Fleet Variation**. Prone to configuration drift across operating system versions, local environment variables, and user-level customizations. |
| **Mobility & Offline Access** | **Always-Connected**. Requires an active internet connection to access the remote workstation instance. | **Hybrid Offline**. Developers can view, edit, and compile code locally without internet. However, **all Antigravity AI capabilities require internet** to reach Google Cloud foundation models. |
| **Operational & Change Management** | **Managed as Code (IaC)**. Managed via Terraform and Cloud Build. Releasing an update means publishing a new container tag to Artifact Registry, updating the workstation configuration, and cycling instances. | **Centralized IT Policies**. Managed by corporate IT via `.mobileconfig` profiles, Intune PowerShell remediation scripts, and phased deployment rings. |

### How to Decide
* **Choose Cloud Workstations if**: You are provisioning environments for contractors, offshore development teams, or projects handling high-value intellectual property, sensitive financial/healthcare data, or regulated compliance workloads that prohibit corporate code on endpoints. *(See the companion [Cloud Workstations Deployment Guide](cloud_workstations_deployment_guide.md) for full setup).*
* **Choose Local MDM if**: You are supporting full-time core engineers who need local editor workflows, and whose physical endpoints are already protected by corporate Endpoint Detection and Response (EDR) agents.

---

## 3. Disabling Auto-Updates: The Core Mechanism

Developer IDEs prioritize configurations in a specific hierarchy:
1. **OS-Level Administrative / Machine Policies** (Highest priority — locked by IT)
2. **Workspace / Folder Settings** (`.vscode/settings.json`)
3. **User Settings** (`~/.config/Code/User/settings.json` or `%APPDATA%` — editable by the developer)

> [!CAUTION]
> **Never rely on user-level settings files** for enterprise compliance. If an IT team distributes settings to `~/.config/Code/User/settings.json`, any developer can overwrite, modify, or delete them.

To reliably prevent auto-updates, MDM tools must write directly to **OS-level administrative policy stores**. When injected at this layer, the IDE disables background update checking and greys out manual update options in the user interface.

### The Required Policy Configuration
The following settings must be enforced across all client environments:

```json
{
  "update.mode": "none",
  "extensions.autoCheckUpdates": false,
  "extensions.autoUpdate": false,
  "app.autoCheckUpdates": false
}
```

* `"update.mode": "none"`: Completely disables editor background application update checks and downloads.
* `"extensions.autoCheckUpdates": false`: Prevents the editor from polling extension marketplaces for new versions.
* `"extensions.autoUpdate": false`: Disables automatic installation of extension updates.
* `"app.autoCheckUpdates": false`: Blocks auxiliary update checking daemons.

---

## 4. Enterprise MDM Implementation Blueprints

```mermaid
graph TD
    subgraph "1. Release Staging & Rings"
        Release[Google Antigravity Plugin Release] --> Ring0[Ring 0: Platform Security Validation]
        Ring0 --> Ring1[Ring 1: Canary / Pilot Engineers]
        Ring1 --> Ring2[Ring 2: General Availability Catalog]
    end

    subgraph "2. OS Policy Distribution"
        Ring2 -->|Jamf Pro / Intune| MacPol[macOS: com.microsoft.VSCode Policy Domain]
        Ring2 -->|Microsoft Intune| WinPol[Windows: HKLM:\SOFTWARE\Policies\Microsoft\VSCode]
        Ring2 -->|Ansible / Puppet| LinPol[Linux: /etc/antigravity/settings.json]
    end

    subgraph "3. Local Enforcement"
        MacPol --> MacClient[Developer Editor Client]
        WinPol --> WinClient[Developer Editor Client]
        LinPol --> LinClient[Developer Editor Client]

        MacClient --> State[Auto-Updates Disabled<br/>Manual Checks Greyed Out]
        WinClient --> State
        LinClient --> State
    end
```

### 1. macOS: Jamf Pro / Microsoft Intune (`.mobileconfig`)

On macOS, configuration profiles targeting the application preference domain (`com.microsoft.VSCode`) write to `/Library/Managed Preferences/com.microsoft.VSCode.plist`. This plist cannot be edited by unprivileged or standard users.

**Configuration Profile Payload (`antigravity_policy.mobileconfig`)**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key>
            <string>com.microsoft.VSCode</string>
            <key>PayloadIdentifier</key>
            <string>com.company.antigravity.policy</string>
            <key>PayloadUUID</key>
            <string>4F2A1C3E-9B8D-4E7A-A123-8B7C9D0E1F2A</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>PayloadEnabled</key>
            <true/>
            <!-- Disable Application & Extension Auto Updates -->
            <key>update.mode</key>
            <string>none</string>
            <key>extensions.autoCheckUpdates</key>
            <false/>
            <key>extensions.autoUpdate</key>
            <false/>
            <key>app.autoCheckUpdates</key>
            <false/>
        </dict>
    </array>
    <key>PayloadDisplayName</key>
    <string>Antigravity Enterprise Version Control Policy</string>
    <key>PayloadIdentifier</key>
    <string>com.company.antigravity.profile</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>1A2B3C4D-5E6F-7A8B-9C0D-1E2F3A4B5C6D</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
```

---

### 2. Windows: Microsoft Intune (PowerShell / Registry GPO)

On Windows, deploy via Intune Proactive Remediation, Group Policy (GPO), or a Win32 app package to lock values into the system registry under `HKLM:\SOFTWARE\Policies`.

**Remediation Script (`enforce_antigravity_lockdown.ps1`)**:
```powershell
$ErrorActionPreference = "Stop"

# 1. Enforce update lockdown at machine policy root
$RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\VSCode"
if (!(Test-Path -Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}
Set-ItemProperty -Path $RegPath -Name "update.mode" -Value "none" -Type String
Set-ItemProperty -Path $RegPath -Name "extensions.autoCheckUpdates" -Value 0 -Type DWord
Set-ItemProperty -Path $RegPath -Name "extensions.autoUpdate" -Value 0 -Type DWord

# 2. Antigravity Desktop / CLI Policy Lockdown
$AgyRegPath = "HKLM:\SOFTWARE\Policies\Google\Antigravity"
if (!(Test-Path -Path $AgyRegPath)) {
    New-Item -Path $AgyRegPath -Force | Out-Null
}
Set-ItemProperty -Path $AgyRegPath -Name "autoCheckUpdates" -Value 0 -Type DWord
Write-Host "Antigravity machine policy successfully applied."
```

---

### 3. Linux: Ansible Playbook

On Linux workstations, deploy a root-owned, read-only configuration file at `/etc/antigravity/settings.json` or within the system-wide IDE settings directory:

```yaml
- name: Deploy Antigravity Enterprise Machine Policy
  hosts: developer_workstations
  become: true
  tasks:
    - name: Ensure system configuration directory exists
      ansible.builtin.file:
        path: /etc/antigravity
        state: directory
        owner: root
        group: root
        mode: '0755'

    - name: Write locked machine settings
      ansible.builtin.copy:
        dest: /etc/antigravity/settings.json
        owner: root
        group: root
        mode: '0644'
        content: |
          {
            "update.mode": "none",
            "app.autoCheckUpdates": false,
            "extensions.autoCheckUpdates": false,
            "extensions.autoUpdate": false
          }
```

---

## 5. Release Governance & Deployment Rings

To roll out updates safely without risking fleet-wide outages or unexpected regressions, organizations should adopt a phased deployment ring architecture:

```
[Google Upstream Release]
           │
           ▼
┌───────────────────────────────────────┐
│ Ring 0: Platform & SecOps Validation  │  (1-3 Days: TLS proxy inspection, CVE verification)
└───────────────────────────────────────┘
           │
           ▼
┌───────────────────────────────────────┐
│ Ring 1: Canary / Pilot Engineers      │  (1-2 Weeks: 5-10% of engineering team, language servers)
└───────────────────────────────────────┘
           │
           ▼
┌───────────────────────────────────────┐
│ Ring 2: General Availability (GA)     │  (100% Fleet: Promoted to Jamf/Intune self-service catalog)
└───────────────────────────────────────┘
```

1. **Ring 0 (Platform Security & IT Validation)**:
   * Test the candidate binary/extension against internal corporate proxies, TLS inspection certificates, and egress firewall rules.
   * Verify that authentication against Google Cloud uses authorized identity providers and scopes.
2. **Ring 1 (Canary & Pilot Engineering Cohort)**:
   * Deploy to a representative 5–10% sample of software engineers across multiple language stacks (Python, Java, Go, TypeScript).
   * Confirm that language servers, indexing, and daily IDE extensions function without conflict.
3. **Ring 2 (Fleet-Wide General Availability)**:
   * Package the approved version into the corporate self-service software portal (Jamf Self Service or Intune Company Portal).
   * Increment the mandatory minimum version in corporate compliance scripts.

---

## 6. The Local Admin Reality & EDR Whitelisting

Platform security teams must account for a fundamental security truth on physical developer hardware:
> **If developers possess local `sudo` or local administrator rights, client-side configuration files are managed guardrails—not an impenetrable security boundary.**

A user with administrative privileges can alter `/Library/Managed Preferences`, stop Intune management services, or install standalone binaries into unmanaged user directories (`~/.local/bin`).

### Production Hardening: Pairing MDM with EDR
For organizations operating in zero-trust, healthcare, or defense environments where strict binary integrity is required on local hardware:
1. **Application Hash Whitelisting**: Leverage corporate Endpoint Detection and Response (EDR) platforms (such as CrowdStrike Falcon, Microsoft Defender for Endpoint, or VMware Carbon Black).
2. **Enforce Binary Execution Policies**: Configure the EDR agent to permit execution only of binaries matching the exact SHA-256 hash of the IT-vetted Antigravity (`agy`) release.
3. **Block Unvetted Binaries**: If a developer attempts to download or run an ad-hoc or updated `agy` executable, the EDR agent terminates the process at the OS kernel level, regardless of the user's `sudo` permissions.

---

## 7. Governance Implementation Checklist

- [ ] **Model Selection**: Determine whether your workload requires Cloud Workstations (100% cloud perimeter isolation) or Local MDM (governed native endpoints).
- [ ] **Policy Distribution**: Deploy machine-level `update.mode = "none"` policies via Jamf Pro, Intune, or Ansible.
- [ ] **Verification**: Confirm in developer IDEs that automatic update checks are disabled and manual "Check for Updates" options are greyed out.
- [ ] **Pilot Ring Setup**: Establish Ring 0 (Security/Platform) and Ring 1 (Canary) device groups in your MDM catalog.
- [ ] **EDR Baseline**: If local users have admin rights and strict compliance is required, register the SHA-256 hashes of approved Antigravity binaries in your EDR platform.

---

## 8. Related Guides & Resources

* 🛠️ **Hands-on Deployment**: See the [Cloud Workstations Deployment Guide](cloud_workstations_deployment_guide.md) for Docker pre-baking, startup hooks, and supervisor auto-reloading.
* 📦 **Production Code Repository**: All Terraform modules, Dockerfile configurations, and MDM policy templates are available at [github.com/cemendes/antigravity-enterprise-rollout](https://github.com/cemendes/antigravity-enterprise-rollout).
