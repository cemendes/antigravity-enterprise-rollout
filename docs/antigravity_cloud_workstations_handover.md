# TL;DR & Engineering Handover: Antigravity (`AGY`) on Google Cloud Workstations

## 1. Current Status & Tested Versions
- **Container & Extension Versions Tested:**
  - Upgraded from `AGY 1.1.11` (`MIN_AGY_VERSION`) to the latest production release: **AGY CLI/Server `1.2.7`** (`1.2.7-6731160148115456`, `linux_amd64`) + **VS Code Extension `google.google-antigravity` `1.4.0`**.
- **What Works 100%:**
  - **Standalone Antigravity Web Hub (`agy --hub` on port `41969`):** Opening `https://41969-<workstation>.<cluster>.cloudworkstations.dev/` directly in a separate browser tab works 100% (OAuth, chat, diff viewer, and Gemini Enterprise Plus inference).
  - **Desktop VS Code / Antigravity Client via SSH Tunnel:** Connecting from a local machine over `gcloud workstations start-tcp-tunnel <workstation> 22` works 100% because `127.0.0.1:41969` is tunneled locally without going through `*.cloudworkstations.dev`.
- **Known Platform Limitation (Broken in Browser Code-OSS):**
  - Clicking the **Antigravity sidebar icon** inside browser-based **Code-OSS for Web** (`https://80-<workstation>.<cluster>.cloudworkstations.dev/`) fails to load the inner `#jetski-frame` webview with:
    `workstations.cloud.google.com refused to connect`
  - **Confirmed:** Upgrading the container to `AGY 1.2.7` / extension `1.4.0` does **not** resolve the sidebar iframe issue because it is an architectural/CSP conflict between the VS Code extension webview and the Cloud Workstations auth gateway.

## 2. Exact Root Cause (Verified in `google3`)
1. **Subdomain Rewrite (`extension.ts:105-108`):** `//cloud/developer_experience/antigravity_extensions/vscode/extension.ts` calls `vscode.env.asExternalUri("http://127.0.0.1:41969")`, which Cloud Workstations Code-OSS resolves to a separate port subdomain: `https://41969-<workstation>.<cluster>.cloudworkstations.dev`.
2. **3-Level Cross-Site Iframe Nesting (`desktop_webview_delegate.ts:276`):** Code-OSS isolates extension webviews inside a sandbox iframe on `https://<uuid>.cloudworkstations.googleusercontent.com`. Inside that sandbox, `DesktopWebviewDelegate.renderIframe` injects `<iframe id="jetski-frame" src="https://41969-<workstation>...cloudworkstations.dev/">`.
3. **Cookie Drop & Auth Redirect (`WorkstationAuthAction.java:169`):** Because `WorkstationJwt` cookies on `*.cloudworkstations.dev` are host-only (`80-...` is not shared with `41969-...`) and Chrome blocks 3P cookie forwarding (`/_workstation/forwardCookie`) inside the `*.cloudworkstations.googleusercontent.com` parent frame, the gateway redirects `#jetski-frame` to `https://workstations.cloud.google.com/_workstation/login`.
4. **Hardcoded CSP `frame-ancestors` Block (`IframeHeaders.java:110-112`):** In `//java/com/google/cloud/workstations/frontend/service/IframeHeaders.java`, `workstations.cloud.google.com` only adds `https://*.cloudworkstations.googleusercontent.com` (`MONOSPACE_ALLOWED_FRAME_ANCESTORS`) to `Content-Security-Policy: frame-ancestors` if the cluster matches `MONOSPACE_DOMAINS` (9 hardcoded Firebase Studio / Project IDX cluster domains). Standard Cloud Workstation clusters receive `frame-ancestors 'self'`, causing Chrome to block the sidebar iframe.

## 3. Buganizer Tracking
- **Primary Bug Filed:** **[b/563594437](http://b/563594437)** — `[VSC][AGY] Antigravity 1.4.0 (AGY 1.2.7) sidebar fails with 'workstations.cloud.google.com refused to connect' in Cloud Workstations Code-OSS`
  - **Component:** `2158091` (`Antigravity VS Code Extension`)
  - **Priority:** `P2` (`ASSIGNED` to `vishrutm@`, CC `sairamsrinivas@`, `wilford@`, `caseyflynn@`)
  - **Attachment:** `code-oss-antigravity-sidebar-refused-to-connect.png` (`ID: 82184302`)
- **Related Platform Bugs:**
  - `b/561558857` (PSO + Cloud Workstations engineering effort to support Antigravity inside Code-OSS)
  - `b/543580982` & `b/353397697` (`*.cloudworkstations.googleusercontent.com` `frame-ancestors` / Nginx proxy fixes)

## 4. What to Document in the Installation / User Guide
1. **Container Build (`Dockerfile` & `cloudbuild.yaml`):**
   - Pin `ARG AGY_VERSION="1.2.7"` (and `_AGY_VERSION: '1.2.7'`) instead of `1.1.11` so new workstations already bake the latest `agy` binary and avoid a ~200 MB auto-update download on startup.
2. **Recommended User Workflows (Until `b/563594437` is fixed):**
   - **Option A (Browser-Only / Zero Local Setup):** Open Code-OSS on port 80 (`https://<workstation>.<cluster>.cloudworkstations.dev/`) for editing/terminals, and open the **Standalone Antigravity Hub** (`https://41969-<workstation>.<cluster>.cloudworkstations.dev/`) in a pinned browser tab side-by-side.
   - **Option B (Native Sidebar Experience):** Connect **Desktop VS Code / Antigravity** via SSH tunnel (`gcloud workstations start-tcp-tunnel <workstation> 22`), where the inline sidebar webview works natively without hitting `workstations.cloud.google.com`.
   - **Known Issue Callout:** Explicitly add a *"Known Limitation (b/563594437)"* note in the docs explaining that clicking the Antigravity icon inside browser-based Code-OSS shows `workstations.cloud.google.com refused to connect` due to Cloud Workstations' CSP `frame-ancestors` policy on `*.cloudworkstations.googleusercontent.com` webviews, and direct users to Option A or Option B.

## 5. Standalone UI Hub Management & Automated Credential Reloading
- **Architecture**:
  - `antigravity-hub-supervisor.sh` (`/usr/local/bin/antigravity-hub-supervisor.sh`) runs as a persistent background daemon under user `user`.
  - **Process 1 (Respawn Loop)**: Keeps `agy --hub --hub-port=41969 --app_data_dir=antigravity` continuously running and automatically recovers if terminated.
  - **Process 2 (Token Watcher)**: Monitors `/home/user/.gemini/jetski-standalone-oauth-token`. When a developer logs in via `agy` CLI or credentials refresh, the watcher detects the `mtime` update, sends `pkill -f 'agy.*--hub'`, and the respawn loop immediately spins up a new instance authenticated with the updated token (`gcp-ge-plus-tier`).
- **Manual Control**:
  - Developers or admins can trigger an on-demand restart at any time using:
    ```bash
    agy-hub-restart
    ```

