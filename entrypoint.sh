#!/bin/bash
set -e

# If custom command arguments are passed, execute them directly
if [ $# -gt 0 ]; then
    exec "$@"
fi

# Print official VisualVibe Agent neon banner on container startup
if [ -f /etc/visualvibe/scripts/print_banner.sh ]; then
    bash /etc/visualvibe/scripts/print_banner.sh
fi

echo "=========================================================="
echo "    Initializing VisualVibe Agent (KasmVNC Desktop)"
echo "=========================================================="

# 1. Ensure permissions on /dev/fuse for nested Podman
if [ -e /dev/fuse ]; then
    chmod 666 /dev/fuse 2>/dev/null || true
fi

# 2. Setup home directory and ownership for vvagent user
mkdir -p /home/vvagent
# Only fix ownership on the home dir itself — NOT recursively.
# Recursive chown would walk the entire persistent volume on every boot,
# causing multi-minute startup delays as files accumulate.
chown vvagent:vvagent /home/vvagent

# 3. Configure Podman storage for persistent volume (first boot only)
if [ ! -f /home/vvagent/.config/containers/storage.conf ]; then
    echo "[Init] Configuring Podman storage (fuse-overlayfs)..."
    mkdir -p /home/vvagent/.config/containers
    cp /etc/visualvibe/containers-storage.conf /home/vvagent/.config/containers/storage.conf
    chown -R vvagent:vvagent /home/vvagent/.config
fi

# Ensure default workspace directory exists in the volume
workdirs="/home/vvagent/VisualVibe Workdirs"
if [ ! -d "$workdirs" ]; then
    echo "[Init] Creating workspace directory: $workdirs"
    mkdir -p "$workdirs"
fi
# Only fix ownership on the workdir itself — NOT recursively.
# Recursive chown would walk the entire workspace on every boot.
chown vvagent:vvagent "$workdirs"

# 4. Configure Openbox Window Manager and Browser Launcher
echo "[Init] Configuring Openbox window manager and desktop shortcuts..."
mkdir -p /home/vvagent/.config/openbox

# Ensure Chromium first-run markers exist in persistent volume (prevents welcome dialogs)
if [ -f /usr/bin/chromium-browser ]; then
    mkdir -p /home/vvagent/.config/chromium
    touch "/home/vvagent/.config/chromium/EULA Accepted" "/home/vvagent/.config/chromium/First Run" 2>/dev/null || true
    chown -R vvagent:vvagent /home/vvagent/.config/chromium 2>/dev/null || true
fi

if [ ! -f /home/vvagent/.config/openbox/rc.xml ] || ! grep -q "open-browser" /home/vvagent/.config/openbox/rc.xml; then
    cp /etc/visualvibe/openbox-rc.xml /home/vvagent/.config/openbox/rc.xml
fi
if [ -f /etc/visualvibe/scripts/openbox-autostart ]; then
    cp /etc/visualvibe/scripts/openbox-autostart /home/vvagent/.config/openbox/autostart
fi
chmod +x /home/vvagent/.config/openbox/autostart
chown -R vvagent:vvagent /home/vvagent/.config/openbox

# 5. Restore or install Cline extension in persistent volume
mkdir -p /home/vvagent/.vscode/extensions
if [ -d /opt/visualvibe/extensions ] && ! ls -d /home/vvagent/.vscode/extensions/saoudrizwan.claude-dev-* >/dev/null 2>&1; then
    echo "[Init] Restoring pre-installed Cline extension into /home/vvagent/.vscode/extensions..."
    cp -a /opt/visualvibe/extensions/* /home/vvagent/.vscode/extensions/ 2>/dev/null || true
fi
if ! ls -d /home/vvagent/.vscode/extensions/saoudrizwan.claude-dev-* >/dev/null 2>&1; then
    echo "[Init] Cline extension not found in volume. Installing via code CLI..."
    runuser -u vvagent -- code --install-extension saoudrizwan.claude-dev --force 2>/dev/null || true
fi
chown -R vvagent:vvagent /home/vvagent/.vscode
#    - Place Cline in Secondary Side Bar (right sidebar where Copilot was)
#    - Mark welcome / onboarding view completed so Cline is immediately ready
#    - AI endpoint & API key pre-configured from environment variables
#    - Full-access auto-approval mode (mirrors Antigravity full access)
#    - Disable workspace trust prompts and pre-seed workspace auxiliary bar state
ai_api_url="${AI_API_URL:-}"
ai_api_key="${AI_API_KEY:-}"
ai_model_id="${AI_MODEL_ID:-}"
echo "[Init] Configuring Cline (auto-approval + AI endpoint + right sidebar layout)..."
python3 -c '
import json, os, glob, sqlite3
from datetime import datetime, timezone

home     = "/home/vvagent"
api_url  = os.environ.get("AI_API_URL", "").strip()
api_key  = os.environ.get("AI_API_KEY", "").strip()
model_id = os.environ.get("AI_MODEL_ID", "").strip()

# ── 1. Patch Cline package.json: Move to Secondary Side Bar & Enable Auto-Activate ──
for pkg_path in glob.glob(os.path.join(home, ".vscode/extensions/saoudrizwan.claude-dev-*/package.json")):
    try:
        with open(pkg_path, "r", encoding="utf-8") as f:
            pkg = json.load(f)
        modified = False
        vc = pkg.get("contributes", {}).get("viewsContainers", {})
        if "activitybar" in vc:
            vc["secondarySidebar"] = vc.pop("activitybar")
            modified = True
        act_events = pkg.get("activationEvents", [])
        if "onView:claude-dev.SidebarProvider" not in act_events or "*" not in act_events:
            pkg["activationEvents"] = ["*", "onView:claude-dev.SidebarProvider", "onStartupFinished"]
            modified = True
        if modified:
            with open(pkg_path, "w", encoding="utf-8") as f:
                json.dump(pkg, f, indent=2)
            print("[Init] Patched Cline package.json: secondarySidebar and activationEvents updated.")
    except Exception as e:
        print(f"[Init] Warning: Could not patch Cline package.json: {e}")

# ── 2. Write Cline providers.json & global-settings.json ────────────────────
now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
cline_settings_dir = os.path.join(home, ".cline/data/settings")
os.makedirs(cline_settings_dir, exist_ok=True)

openai_cfg = {
    "provider": "openai",
    "tokenSource": "manual"
}
if api_url:
    openai_cfg["baseUrl"] = api_url
if api_key:
    openai_cfg["apiKey"] = api_key
if model_id:
    openai_cfg["model"] = model_id

openai_compatible_cfg = {
    "provider": "openai-compatible",
    "tokenSource": "manual"
}
if api_url:
    openai_compatible_cfg["baseUrl"] = api_url
if api_key:
    openai_compatible_cfg["apiKey"] = api_key
if model_id:
    openai_compatible_cfg["model"] = model_id

providers_data = {
    "version": 1,
    "lastUsedProvider": "openai",
    "modes": {},
    "providers": {
        "openai": {
            "settings": openai_cfg,
            "updatedAt": now_iso,
            "tokenSource": "manual"
        },
        "openai-compatible": {
            "settings": openai_compatible_cfg,
            "updatedAt": now_iso,
            "tokenSource": "manual"
        }
    }
}
try:
    with open(os.path.join(cline_settings_dir, "providers.json"), "w", encoding="utf-8") as f:
        json.dump(providers_data, f, indent=2)
except Exception as e:
    print(f"[Init] Warning: Could not write Cline providers.json: {e}")

try:
    with open(os.path.join(cline_settings_dir, "global-settings.json"), "w", encoding="utf-8") as f:
        json.dump({
            "telemetryOptOut": True,
            "autoUpdateEnabled": False,
            "planActMode": "act",
            "toolAutoApprove": True,
            "mcpEnabled": True,
            "mcpDisplayMode": "rich"
        }, f, indent=2)
except Exception as e:
    pass

# ── 3. Write Cline 4.x native globalState.json & secrets.json ───────────────
cline_data_dir = os.path.join(home, ".cline/data")
os.makedirs(cline_data_dir, exist_ok=True)

auto_approval = {
    "version": 1,
    "enabled": True,
    "favorites": [],
    "maxRequests": 50,
    "actions": {
        "readFiles":           True,
        "readFilesExternally": True,
        "editFiles":           True,
        "editFilesExternally": True,
        "executeSafeCommands": True,
        "executeAllCommands":  True,
        "useBrowser":          True,
        "useMcp":              True
    },
    "enableNotifications": False
}

gs_path = os.path.join(cline_data_dir, "globalState.json")
gs = {}
if os.path.exists(gs_path):
    try:
        with open(gs_path, "r", encoding="utf-8") as f:
            gs = json.load(f)
    except Exception:
        gs = {}

gs.update({
    "welcomeViewCompleted": True,
    "isNewUser": False,
    "clineVersion": "4.1.21",
    "__vscodeMigrationVersion": 3,
    "lastShownAnnouncementId": "4.1.21",
    "lastDismissedInfoBannerVersion": 999,
    "lastDismissedModelBannerVersion": 999,
    "lastDismissedCliBannerVersion": 999,
    "mode": "act",
    "planModeApiProvider": "openai",
    "actModeApiProvider": "openai",
    "apiProvider": "openai",
    "telemetrySetting": "disabled",
    "mcpEnabled": True,
    "mcpDisplayMode": "rich",
    "autoApprovalSettings": auto_approval,
    "browserSettings": {
        "viewport": {"width": 1280, "height": 800},
        "headless": False
    }
})
if api_url:
    gs["openAiBaseUrl"] = api_url
if model_id:
    gs["openAiModelId"] = model_id
    gs["planModeOpenAiModelId"] = model_id
    gs["actModeOpenAiModelId"] = model_id
    gs["planModeApiModelId"] = model_id
    gs["actModeApiModelId"] = model_id

try:
    with open(gs_path, "w", encoding="utf-8") as f:
        json.dump(gs, f, indent=2)
except Exception as e:
    print(f"[Init] Warning: Could not write Cline globalState.json: {e}")

if api_key:
    secrets_path = os.path.join(cline_data_dir, "secrets.json")
    try:
        with open(secrets_path, "w", encoding="utf-8") as f:
            json.dump({
                "apiKey": api_key,
                "openAiApiKey": api_key
            }, f, indent=2)
        os.chmod(secrets_path, 0o600)
    except Exception as e:
        print(f"[Init] Warning: Could not write Cline secrets.json: {e}")

# ── 4. Pre-seed VS Code workspaceStorage ──────────────────
# Pre-seed hashes for file:///home/vvagent/VisualVibe%20Workdirs and file:///home/vvagent
ws_configs = [
    ("8cee3ca57c50ceb3405b6d0073e1a60c", "file:///home/vvagent/VisualVibe%20Workdirs"),
    ("e8169bd1fb62d0f9cb9918a0a00b431c", "file:///home/vvagent/VisualVibe%20Workdirs"),
    ("f10b6778337533fa2377e489b26d0793", "file:///home/vvagent"),
    ("85c05856cc1d643c064058b563b7a4ce", "file:///home/vvagent")
]
for ws_hash, folder_uri in ws_configs:
    ws_dir = os.path.join(home, f".config/Code/User/workspaceStorage/{ws_hash}")
    os.makedirs(ws_dir, exist_ok=True)
    try:
        with open(os.path.join(ws_dir, "workspace.json"), "w", encoding="utf-8") as f:
            json.dump({"folder": folder_uri}, f, indent=2)
    except Exception:
        pass

    try:
        ws_db = os.path.join(ws_dir, "state.vscdb")
        ws_conn = sqlite3.connect(ws_db)
        ws_cur = ws_conn.cursor()
        ws_cur.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)")
        aux_panel_id = "workbench.view.extension.claude-dev-ActivityBar"
        ws_cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (\"workbench.auxiliarybar.activepanelid\", ?)", (json.dumps(aux_panel_id),))
        ws_cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (\"workbench.auxiliarybar.viewContainersWorkspaceState\", ?)", (json.dumps([{"id": aux_panel_id, "visible": True}]),))
        ws_cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (\"workbench.auxiliaryBar.hidden\", \"false\")")
        ws_cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (\"workbench.auxiliarybar.pinnedPanels\", ?)", (json.dumps([{"id": aux_panel_id, "pinned": True, "visible": True, "order": 0}]),))
        ws_cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (\"workbench.view.extension.claude-dev-ActivityBar.state\", ?)", (json.dumps({"claude-dev.SidebarProvider": {"collapsed": False, "isHidden": False}}),))
        ws_cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (\"welcomeOnboarding.state\", \"true\")")
        ws_cur.execute("DELETE FROM ItemTable WHERE key LIKE \"%copilot%\" OR key LIKE \"%chat%\"")
        ws_conn.commit()
        ws_conn.close()
    except Exception as e:
        print(f"[Init] Warning: Could not pre-seed workspaceStorage {ws_hash}: {e}")

# ── 5. Configure VS Code globalStorage/state.vscdb ───────────────────────────
db_dir  = os.path.join(home, ".config/Code/User/globalStorage")
db_path = os.path.join(db_dir, "state.vscdb")
os.makedirs(db_dir, exist_ok=True)

try:
    conn = sqlite3.connect(db_path)
    cur  = conn.cursor()
    cur.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)")

    api_config = {
        "apiProvider":            "openai",
        "planModeApiProvider":    "openai",
        "actModeApiProvider":     "openai",
        "openAiBaseUrl":          api_url,
        "openAiApiKey":           api_key,
        "openAiModelId":          model_id,
        "planModeOpenAiModelId":  model_id,
        "actModeOpenAiModelId":   model_id
    }

    aux_panel_id = "workbench.view.extension.claude-dev-ActivityBar"
    pinned_panels = [{"id": aux_panel_id, "pinned": True, "visible": True, "order": 0}]

    items = {
        # Bypass welcome / onboarding prompt
        "welcomeViewCompleted": "true",
        "saoudrizwan.claude-dev.welcomeViewCompleted": "true",
        "isNewUser": "false",
        "saoudrizwan.claude-dev.isNewUser": "false",
        "lastShownAnnouncementId": json.dumps("4.1.21"),
        "saoudrizwan.claude-dev.lastShownAnnouncementId": json.dumps("4.1.21"),
        "lastDismissedInfoBannerVersion": "999",
        "lastDismissedModelBannerVersion": "999",
        "lastDismissedCliBannerVersion": "999",
        "saoudrizwan.claude-dev.lastDismissedInfoBannerVersion": "999",
        "saoudrizwan.claude-dev.lastDismissedModelBannerVersion": "999",
        "saoudrizwan.claude-dev.lastDismissedCliBannerVersion": "999",

        # Mode, auto-approval, and MCP (Full Access + Rich Text)
        "mode": json.dumps("act"),
        "saoudrizwan.claude-dev.mode": json.dumps("act"),
        "autoApprovalSettings": json.dumps(auto_approval),
        "saoudrizwan.claude-dev.autoApprovalSettings": json.dumps(auto_approval),
        "mcpEnabled": json.dumps(True),
        "saoudrizwan.claude-dev.mcpEnabled": json.dumps(True),
        "mcpDisplayMode": json.dumps("rich"),
        "saoudrizwan.claude-dev.mcpDisplayMode": json.dumps("rich"),

        # API Configuration
        "apiProvider": json.dumps("openai"),
        "saoudrizwan.claude-dev.apiProvider": json.dumps("openai"),
        "planModeApiProvider": json.dumps("openai"),
        "saoudrizwan.claude-dev.planModeApiProvider": json.dumps("openai"),
        "actModeApiProvider": json.dumps("openai"),
        "saoudrizwan.claude-dev.actModeApiProvider": json.dumps("openai"),
        "apiConfiguration": json.dumps(api_config),
        "saoudrizwan.claude-dev.apiConfiguration": json.dumps(api_config),

        # Extension global state blob
        "saoudrizwan.claude-dev": json.dumps({
            "welcomeViewCompleted": True,
            "isNewUser": False,
            "apiProvider": "openai",
            "planModeApiProvider": "openai",
            "actModeApiProvider": "openai",
            "mode": "act",
            "telemetrySetting": "disabled",
            "mcpEnabled": True,
            "mcpDisplayMode": "rich",
            "lastShownAnnouncementId": "4.1.21"
        }),

        # Layout: Auxiliary bar (Secondary Side Bar on the right)
        "workbench.auxiliarybar.pinnedPanels": json.dumps(pinned_panels),
        "workbench.auxiliarybar.activepanelid": json.dumps(aux_panel_id),
        "workbench.auxiliarybar.hidden": "false",
        "welcomeOnboarding.state": "true"
    }

    if api_url:
        items["openAiBaseUrl"] = json.dumps(api_url)
        items["saoudrizwan.claude-dev.openAiBaseUrl"] = json.dumps(api_url)
    if api_key:
        items["openAiApiKey"] = json.dumps(api_key)
        items["saoudrizwan.claude-dev.openAiApiKey"] = json.dumps(api_key)
        items["secret://{\"extensionId\":\"saoudrizwan.claude-dev\",\"key\":\"openAiApiKey\"}"] = api_key
        items["secret://{\"extensionId\":\"saoudrizwan.claude-dev\",\"key\":\"apiKey\"}"] = api_key
        items["secret://openAiApiKey"] = api_key
        items["secret://saoudrizwan.claude-dev.openAiApiKey"] = api_key
    if model_id:
        items["openAiModelId"] = json.dumps(model_id)
        items["saoudrizwan.claude-dev.openAiModelId"] = json.dumps(model_id)
        items["planModeOpenAiModelId"] = json.dumps(model_id)
        items["saoudrizwan.claude-dev.planModeOpenAiModelId"] = json.dumps(model_id)
        items["actModeOpenAiModelId"] = json.dumps(model_id)
        items["saoudrizwan.claude-dev.actModeOpenAiModelId"] = json.dumps(model_id)

    for k, v in items.items():
        cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (k, v))

    conn.commit()
    conn.close()
    print("[Init] Cline state & layout pre-configured in state.vscdb.")
except Exception as e:
    print(f"[Init] Warning: Could not configure Cline state DB: {e}")
' 2>/dev/null || true

# ── 6. Pre-configure VS Code settings and keybindings ───────────────────────
mkdir -p /home/vvagent/.config/Code/User
python3 -c '
import json, os

home = "/home/vvagent"
settings_path = os.path.join(home, ".config/Code/User/settings.json")
current = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path, "r", encoding="utf-8") as f:
            current = json.load(f)
    except Exception:
        current = {}

current.update({
    "window.title": "VisualVibe Agent",
    "window.titleBarStyle": "custom",
    "editor.formatOnSave": False,
    "editor.minimap.enabled": False,
    "telemetry.telemetryLevel": "off",
    "update.mode": "none",
    "extensions.autoUpdate": False,
    "security.workspace.trust.enabled": False,
    "security.workspace.trust.startupPrompt": "never",
    "workbench.startupEditor": "none",
    "workbench.welcomePage.experimentalOnboarding": False,
    "workbench.welcomePage.walkthroughs.openOnInstall": False,
    "chat.disableAIFeatures": True,
    "chat.commandCenter.enabled": False,
    "chat.agent.enabled": False,
    "chat.welcomePage.signIn.enabled": False,
    "chat.titleBar.signIn.enabled": False,
    "github.copilot.enable": {"*": False}
})

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(current, f, indent=2)

# Shortcuts to focus Cline view directly and toggle auxiliary bar
keybindings_path = os.path.join(home, ".config/Code/User/keybindings.json")
keybindings = [
    {
        "key": "ctrl+alt+c",
        "command": "claude-dev.SidebarProvider.focus"
    },
    {
        "key": "ctrl+alt+b",
        "command": "workbench.action.toggleAuxiliaryBar"
    }
]
with open(keybindings_path, "w", encoding="utf-8") as f:
    json.dump(keybindings, f, indent=2)
' 2>/dev/null || true

# Clean up any residual Copilot and chat feature directories
rm -rf /usr/share/code/resources/app/extensions/copilot \
       /usr/share/code/resources/app/extensions/TypeScriptTeam.jsts-chat-features \
       /usr/share/code/resources/app/node_modules.asar.unpacked/@github \
       /home/vvagent/.vscode/extensions/*copilot* 2>/dev/null || true

chown -R vvagent:vvagent /home/vvagent/.config /home/vvagent/.cline /home/vvagent/.vscode 2>/dev/null || true

# 7. Configure KasmVNC Server
echo "[Init] Configuring KasmVNC server..."
usermod -a -G kasmvnc-cert vvagent 2>/dev/null || true
chown root:kasmvnc-cert /etc/pki/tls/private/kasmvnc.pem 2>/dev/null || chown root:vvagent /etc/pki/tls/private/kasmvnc.pem 2>/dev/null || true
chmod 640 /etc/pki/tls/private/kasmvnc.pem 2>/dev/null || true
touch /home/vvagent/.Xauthority 2>/dev/null || true
chown vvagent:vvagent /home/vvagent/.Xauthority 2>/dev/null || true
mkdir -p /home/vvagent/.vnc
cp /etc/visualvibe/kasmvnc.yaml /home/vvagent/.vnc/kasmvnc.yaml
# FIX E-04: removed duplicate copy to /etc/kasmvnc (KasmVNC uses ~/.vnc/kasmvnc.yaml when run as user)

# Create dummy credential to satisfy KasmVNC's internal password validator.
# Authentication is fully disabled (-SecurityTypes None -DisableBasicAuth),
# so this password is never actually checked or used.
echo -e "vvagent\nvvagent\n" | kasmvncpasswd -u vvagent -wo /home/vvagent/.kasmpasswd 2>/dev/null || true

# Mark DE selection as completed to avoid interactive prompts
touch /home/vvagent/.vnc/.de-was-selected

# X11 session startup script for KasmVNC
cat << 'EOF' > /home/vvagent/.vnc/xstartup
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec openbox-session
EOF
chmod +x /home/vvagent/.vnc/xstartup
chown -R vvagent:vvagent /home/vvagent/.vnc /home/vvagent/.kasmpasswd 2>/dev/null || true

# 8. Clean up any stale X11 locks
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

# 9. FIX E-05: Branding is baked at build time (Containerfile step 13).
# Re-running brand_kasmvnc.py at runtime is redundant since KasmVNC www files
# are in the immutable image layer and never change between boots.

# 10. Start KasmVNC Server (port 8080, no built-in auth, display :1)
# Note: /usr/bin/vncserver is already patched at build-time by brand_kasmvnc.py
# (http URLs, VisualVibe Agent branding, desktopName default).
echo "[KasmVNC] Starting VNC/Web server on port 8080 (Desktop Name: VisualVibe Agent)..."

runuser -u vvagent -- vncserver :1 \
    -desktop "VisualVibe Agent" \
    -geometry 1920x1080 \
    -depth 24 \
    -websocketPort 8080 \
    -SecurityTypes None \
    -DisableBasicAuth

# 11. Start FileBrowser Quantum (port 8081, baseurl /filebrowser, root /home/vvagent)
echo "[FileBrowser] Starting FileBrowser Quantum on port 8081..."
mkdir -p /tmp/filebrowser_cache
chown -R vvagent:vvagent /tmp/filebrowser_cache
# FIX F-01: Ensure persistent DB directory exists (DB is now in the volume, not /tmp)
mkdir -p /home/vvagent/.local/share/filebrowser
chown -R vvagent:vvagent /home/vvagent/.local
# FIX G-02: Log redirected to /dev/null (accessory service; avoids unbounded log growth in /tmp)
runuser -u vvagent -- filebrowser -c /etc/visualvibe/filebrowser.yaml >/dev/null 2>&1 &
sleep 1
if ! pgrep -u vvagent -x filebrowser >/dev/null 2>&1; then
    echo "[FileBrowser] WARNING: FileBrowser process did not stay running!"
else
    echo "[FileBrowser] FileBrowser Quantum is running successfully (PID $(pgrep -u vvagent -x filebrowser))."
fi

CONTAINER_IP=$(hostname -i 2>/dev/null | awk '{print $1}')
[ -z "$CONTAINER_IP" ] && CONTAINER_IP="127.0.0.1"

echo "=========================================================="
echo " VisualVibe Agent is ACTIVE and ready!"
echo " VisualVibe Agent:     http://${CONTAINER_IP}:8080"
echo " FileBrowser Quantum:  http://${CONTAINER_IP}:8081/filebrowser"
echo " Resolution:           Dynamic (1080p, 4K UHD auto-fit)"
echo "=========================================================="

# FIX G-01: Verify the KasmVNC HTTP server is actually reachable after startup
echo "[HealthCheck] Waiting for KasmVNC HTTP to become ready..."
for _hc_attempt in 1 2 3 4 5; do
    if curl -fsSo /dev/null http://localhost:8080/ 2>/dev/null; then
        echo "[HealthCheck] KasmVNC HTTP is up and responding on port 8080."
        break
    fi
    echo "[HealthCheck] Not ready yet (attempt ${_hc_attempt}/5), retrying in 2s..."
    sleep 2
done

# Graceful shutdown cleanup trap
cleanup() {
    echo "[Shutdown] Terminating services and active processes..."
    pkill -u vvagent filebrowser 2>/dev/null || true
    pkill -9 -u vvagent Xvnc 2>/dev/null || pkill -9 -u vvagent Xkasmvnc 2>/dev/null || true
    exit 0
}

# FIX E-01: Use 'sleep N & wait $!' instead of 'sleep N' so SIGTERM is
# delivered immediately to Bash rather than being deferred until sleep exits.
# Without this, shutdown can be delayed up to 2s and Podman may escalate to SIGKILL.
trap cleanup SIGTERM SIGINT SIGQUIT

# Keep container running while Xvnc is active
while pgrep -u vvagent Xvnc > /dev/null 2>&1 || pgrep -u vvagent Xkasmvnc > /dev/null 2>&1; do
    sleep 2 &
    wait $!
done

echo "[Error] KasmVNC server terminated unexpectedly."
exit 1
