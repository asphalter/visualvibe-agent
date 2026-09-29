FROM almalinux:10

# Environment variables
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV DISPLAY=:1

# 1. Install base system utilities, locale, build tools, EPEL and CRB
RUN dnf install -y \
    ca-certificates \
    curl \
    wget \
    gnupg2 \
    glibc-langpack-en \
    sudo \
    procps-ng \
    bash \
    git \
    nano \
    tar \
    gzip \
    xz \
    python3 \
    gcc \
    gcc-c++ \
    make \
    dnf-plugins-core \
    epel-release \
    && crb enable \
    && dnf clean all

# 2. Install Chromium, X11 runtime, wmctrl, Electron runtime dependencies, and Podman-in-Podman
RUN dnf install -y \
    chromium \
    wmctrl \
    xprop \
    xorg-x11-xauth \
    mesa-libGL \
    mesa-dri-drivers \
    mesa-libgbm \
    gtk3 \
    dbus \
    xdg-utils \
    alsa-lib \
    libsecret \
    nss \
    at-spi2-atk \
    cups-libs \
    libdrm \
    libXcomposite \
    libXdamage \
    libXfixes \
    libXrandr \
    libxshmfence \
    libxkbfile \
    podman \
    netavark \
    aardvark-dns \
    catatonit \
    fuse-overlayfs \
    slirp4netns \
    shadow-utils \
    && dnf clean all \
    && mkdir -p /etc/chromium \
    && echo 'CHROMIUM_FLAGS="--no-sandbox --test-type --no-first-run --no-default-browser-check --disable-dev-shm-usage --disable-gpu --password-store=basic"' > /etc/chromium/chromium.conf

# 3. Install Openbox Window Manager & xdotool (Fedora 43 RPMs, compatible with EL10)
RUN curl -fSL -o /tmp/openbox-libs.rpm \
    "https://kojipkgs.fedoraproject.org/packages/openbox/3.6.1/29.fc43/x86_64/openbox-libs-3.6.1-29.fc43.x86_64.rpm" \
    && curl -fSL -o /tmp/openbox.rpm \
    "https://kojipkgs.fedoraproject.org/packages/openbox/3.6.1/29.fc43/x86_64/openbox-3.6.1-29.fc43.x86_64.rpm" \
    && curl -fSL -o /tmp/libxdo.rpm \
    "https://kojipkgs.fedoraproject.org/packages/xdotool/3.20211022.1/9.fc43/x86_64/libxdo-3.20211022.1-9.fc43.x86_64.rpm" \
    && curl -fSL -o /tmp/xdotool.rpm \
    "https://kojipkgs.fedoraproject.org/packages/xdotool/3.20211022.1/9.fc43/x86_64/xdotool-3.20211022.1-9.fc43.x86_64.rpm" \
    && dnf install -y /tmp/openbox-libs.rpm /tmp/openbox.rpm /tmp/libxdo.rpm /tmp/xdotool.rpm \
    && rm -f /tmp/*.rpm \
    && dnf clean all

# 4. Install KasmVNC Server 1.5.0 (Fedora 43 RPM, compatible with AlmaLinux 10 / RHEL 10)
RUN curl -fSL -o /tmp/kasmvncserver.rpm \
    "https://github.com/kasmtech/KasmVNC/releases/download/v1.5.0/kasmvncserver_fedora_43_1.5.0_x86_64.rpm" \
    && dnf install -y /tmp/kasmvncserver.rpm \
    && rm -f /tmp/kasmvncserver.rpm \
    && dnf clean all \
    && ln -sf /usr/share/kasmvnc /usr/local/share/kasmvnc

# 5. Install FileBrowser Quantum for Web-Native File Transfer (Upload/Download)
RUN curl -fsSL -o /usr/local/bin/filebrowser \
    "https://github.com/gtsteffaniak/filebrowser/releases/download/v1.5.6-stable/linux-amd64-filebrowser" \
    && chmod +x /usr/local/bin/filebrowser

# 6. Install Visual Studio Code (from official Microsoft RPM repository)
RUN rpm --import https://packages.microsoft.com/keys/microsoft.asc \
    && printf '[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' \
       > /etc/yum.repos.d/vscode.repo \
    && dnf install -y code python3-pillow \
    && rm -rf /usr/share/code/resources/app/extensions/copilot \
    && rm -rf /usr/share/code/resources/app/extensions/TypeScriptTeam.jsts-chat-features \
    && rm -rf /usr/share/code/resources/app/node_modules.asar.unpacked/@github \
    && dnf clean all

# 7. Configure non-root 'vvagent' user (UID 1000) and subuid/subgid mapping
RUN useradd -m -u 1000 -s /bin/bash vvagent \
    && echo "vvagent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vvagent \
    && chmod 0440 /etc/sudoers.d/vvagent \
    && echo "vvagent:100000:65536" > /etc/subuid \
    && echo "vvagent:100000:65536" > /etc/subgid \
    && (usermod -a -G kasmvnc-cert vvagent 2>/dev/null || true)

# 8. Pre-install Cline extension for VS Code and stage in /opt/visualvibe/extensions
# FIX C-04: removed '|| true' — if Cline fails to install, the build must fail.
# A container without Cline violates the core project requirement.
RUN runuser -u vvagent -- code --install-extension saoudrizwan.claude-dev --force \
    && mkdir -p /opt/visualvibe/extensions \
    && cp -a /home/vvagent/.vscode/extensions/* /opt/visualvibe/extensions/ \
    && python3 -c 'import json, glob; [open(p, "w").write(json.dumps({**d, "activationEvents": ["*", "onView:claude-dev.SidebarProvider", "onStartupFinished"], "contributes": {**d.get("contributes", {}), "viewsContainers": {"secondarySidebar": d.get("contributes", {}).get("viewsContainers", {}).pop("activitybar", [])}}}, indent=2)) for p in glob.glob("/opt/visualvibe/extensions/saoudrizwan.claude-dev-*/package.json") + glob.glob("/home/vvagent/.vscode/extensions/saoudrizwan.claude-dev-*/package.json") for d in [json.load(open(p))] if "activitybar" in d.get("contributes", {}).get("viewsContainers", {})]'

# 9. Pre-configure VS Code settings (window title, telemetry, auto-update, right sidebar, workspace trust)
# Note: this file lives in /home/vvagent which is a volume mount at runtime.
# entrypoint.sh re-creates it on boot if missing or updated.
RUN mkdir -p /home/vvagent/.config/Code/User \
    && printf '{\n  "window.title": "VisualVibe Agent",\n  "window.titleBarStyle": "custom",\n  "editor.formatOnSave": false,\n  "editor.minimap.enabled": false,\n  "telemetry.telemetryLevel": "off",\n  "update.mode": "none",\n  "extensions.autoUpdate": false,\n  "security.workspace.trust.enabled": false,\n  "security.workspace.trust.startupPrompt": "never",\n  "workbench.startupEditor": "none",\n  "workbench.welcomePage.experimentalOnboarding": false,\n  "workbench.welcomePage.walkthroughs.openOnInstall": false,\n  "chat.disableAIFeatures": true,\n  "chat.commandCenter.enabled": false,\n  "chat.agent.enabled": false,\n  "chat.welcomePage.signIn.enabled": false,\n  "chat.titleBar.signIn.enabled": false,\n  "github.copilot.enable": { "*": false }\n}\n' \
       > /home/vvagent/.config/Code/User/settings.json \
    && printf '[\n  {\n    "key": "ctrl+alt+c",\n    "command": "claude-dev.SidebarProvider.focus"\n  },\n  {\n    "key": "ctrl+alt+b",\n    "command": "workbench.action.toggleAuxiliaryBar"\n  }\n]\n' \
       > /home/vvagent/.config/Code/User/keybindings.json \
    && chown -R vvagent:vvagent /home/vvagent

# 10. Default nested Podman configuration
RUN mkdir -p /etc/containers \
    && printf '[containers]\ncgroups = "disabled"\n\n[engine]\ncgroup_manager = "cgroupfs"\n' \
       > /etc/containers/containers.conf \
    && printf 'unqualified-search-registries = ["docker.io"]\n' \
       > /etc/containers/registries.conf

# 11. Prepare staging directories and copy configuration, media assets, and scripts
RUN mkdir -p /etc/visualvibe /etc/visualvibe/media /etc/visualvibe/scripts
COPY config/ /etc/visualvibe/
COPY media/ /etc/visualvibe/media/
COPY scripts/ /etc/visualvibe/scripts/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    /etc/visualvibe/scripts/openbox-autostart \
    /etc/visualvibe/scripts/brand_kasmvnc.py \
    /etc/visualvibe/scripts/open-browser \
    && ln -sf /etc/visualvibe/scripts/open-browser /usr/local/bin/open-browser \
    && ln -sf /usr/bin/chromium-browser /usr/local/bin/chromium

# 12. Customize KasmVNC Web UI branding with VisualVibe Agent assets
# FIX B-03: removed '|| true' — branding failure is a build error, not a warning.
# If brand_kasmvnc.py fails, the marker file won't exist, making the failure obvious.
RUN python3 /etc/visualvibe/scripts/brand_kasmvnc.py \
    && test -f /usr/share/kasmvnc/www/assets/.visualvibe_branded

# 13. Expose KasmVNC Web UI (8080) and FileBrowser (8081)
EXPOSE 8080 8081

# Working directory
WORKDIR /home/vvagent

# 14. Display VisualVibe Agent banner upon compilation completion
ARG BANNER_CACHEBUST=""
RUN bash /etc/visualvibe/scripts/print_banner.sh

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
