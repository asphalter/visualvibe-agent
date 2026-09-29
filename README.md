<p align="center">
  <img src="media/visualvibe_biglogo.jpg" alt="VisualVibe Agent" width="720" />
</p>

# 🧠 VisualVibe Agent

VisualVibe Agent is a containerized, web-native development environment running on **AlmaLinux 10**. It delivers a high-performance desktop experience directly in the browser via **KasmVNC** (port 8080), featuring **Visual Studio Code** equipped with the **Cline AI agent** extension, paired with **FileBrowser Quantum** (port 8081) for file management.

---

## 🚀 Key Features

- **Base Operating System**: Enterprise-grade **AlmaLinux 10** with optimized package dependencies.
- **Web Desktop**: HTML5 / WebSocket streaming via **KasmVNC 1.5.0** (Fedora 43 RPM compatible with EL10) on port `8080`.
  - Dynamic display auto-fitting up to 4K UHD.
  - Custom VisualVibe Agent branding, favicon, splash screen, and responsive sidebar.
  - Borderless, maximized IDE presentation powered by Openbox.
- **Visual Studio Code & Cline**:
  - Official Microsoft VS Code RPM pre-configured with custom title and styling.
  - **Cline AI extension** (`saoudrizwan.claude-dev`) pre-installed.
  - Agnostic AI backend connectivity dynamically configurable via environment variables (`AI_API_URL`, `AI_API_KEY`).
- **Web File Management**: **FileBrowser Quantum** on port `8081` (`/filebrowser/`) with one-click sidebar transition.
- **Rootless Podman-in-Podman**: Nested container capabilities inside the development container (`/dev/fuse` + `fuse-overlayfs`).
- **Zero Startup Updates**: Immutable, build-time compilation for instant startup and total reproducibility.
- **User Environment**: Dedicated non-root user `vvagent` (UID 1000) with persistent storage at `/home/vvagent`.

---

## 📁 Project Structure

```
VisualVibe Agent/
├── Containerfile                  # AlmaLinux 10 build recipe
├── entrypoint.sh                  # Container initialization & runtime orchestration
├── .containerignore               # Podman build context ignore rules
├── run_env.sh                     # Quick local execution script
├── deploy.sh                      # Automated Systemd Quadlet deployment script
├── config/
│   ├── kasmvnc.yaml               # KasmVNC display and network settings
│   ├── filebrowser.yaml           # FileBrowser Quantum configuration
│   ├── openbox-rc.xml             # Openbox window rules (maximized borderless VS Code)
│   └── containers-storage.conf    # Nested Podman storage driver settings
├── media/
│   ├── visualvibe_icon.png        # Official high-contrast square logo & icon
│   ├── visualvibe_horizontal.png  # High-contrast horizontal banner (sidebar logo)
│   ├── favicon.ico                # Multi-layer Windows / browser tab favicon
│   └── favicon_*.png              # Multi-resolution favicons (16x16 to 192x192)
├── scripts/
│   ├── print_banner.sh            # Neon ASCII art startup banner
│   ├── brand_kasmvnc.py           # KasmVNC web UI asset & theme patcher
│   ├── open-browser               # Launch or focus Chromium inside the desktop
│   └── openbox-autostart          # Resilient VS Code supervisor loop
├── quadlet/
│   ├── visualvibe-agent.container # Rootless Quadlet container unit
│   └── visualvibe-home.volume     # Rootless persistent volume unit
```

---

## ⚙️ Configuration & Environment Variables

| Variable | Default | Description |
|---|---|---|
| `AI_API_URL` | *(empty)* | Base URL for the external AI API endpoint (OpenAI-compatible) |
| `AI_API_KEY` | *(empty)* | Optional API key for authenticating against the AI endpoint |
| `AI_MODEL_ID` | *(empty)* | Default model ID for the AI endpoint (e.g. `gpt-4o`, `claude-3-5-sonnet`) |
| `VISUALVIBE_PORT` | `8080` | Host port for the KasmVNC Web Desktop |
| `VISUALVIBE_FB_PORT` | `8081` | Host port for FileBrowser Quantum |
| `VISUALVIBE_CONTAINER`| `visualvibe-agent` | Name of the running container instance |
| `VISUALVIBE_VOLUME` | `visualvibe-home` | Podman persistent volume name |

---

## 💻 Quick Start (Local Run)

### Building the Image
To build the container image directly with Podman:
```bash
sudo podman build -t visualvibe-agent .
```

To display the ASCII art banner every time regardless of layer cache:
```bash
sudo podman build --build-arg BANNER_CACHEBUST=$(date +%s) -t visualvibe-agent .
```

### Running Locally
To launch the full local environment:
```bash
# Optional: define your AI endpoint before running
export AI_API_URL="https://api.your-ai-service.com/v1"
export AI_API_KEY="your-secret-api-key"

./run_env.sh

# Skip image rebuild (use existing image — faster for restarts):
./run_env.sh --no-build
```

Access the interfaces in your browser:
- **Web Desktop**: [http://localhost:8080/](http://localhost:8080/)
- **File Manager**: [http://localhost:8081/filebrowser/](http://localhost:8081/filebrowser/)

---

## 🚢 Production Deployment (Quadlet Systemd)

VisualVibe Agent is fully integrated with **Podman Quadlets** for native, rootless systemd service management.

```bash
# Deploy to local user systemd
./deploy.sh --local

# Deploy to remote server over SSH
./deploy.sh user@server.domain.com --port 8080 --fb-port 8081
```

### Managing the Service

```bash
# Check service status
systemctl --user status visualvibe-agent.service

# Restart service
systemctl --user restart visualvibe-agent.service

# View real-time service logs
journalctl --user -u visualvibe-agent.service -f

# View container logs
podman logs -f visualvibe-agent
```

---

## 🛡️ Security Model

- **Perimeter Security**: Container services (KasmVNC and FileBrowser) run without internal authentication to optimize performance and prevent double-login friction. Access should be secured via **Cloudflare Zero Trust / Access**, a reverse proxy with OAuth2/mTLS, or a private VPN (Tailscale/WireGuard).
- **Least Privilege**: The inner environment executes under UID `1000` (`vvagent`). Nested rootless Podman isolates containers run inside the development environment.
- **VS Code Restart Opt-out**: To prevent VS Code from auto-restarting (e.g., to use the desktop without it), create the file `/tmp/.vscode_no_restart` inside the container.
