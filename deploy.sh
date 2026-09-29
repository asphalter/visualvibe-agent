#!/bin/bash

# ==============================================================================
# deploy.sh — Deploy VisualVibe Agent (KasmVNC Desktop) via Systemd Quadlet
#
# Usage:
#   ./deploy.sh user@server                             # Remote deploy
#   ./deploy.sh user@server --port 9090                 # With custom host port
#   ./deploy.sh --local                                 # Local deploy
#   ./deploy.sh --local --port 9090                     # Local deploy with custom port
#
# Target Server Requirements:
#   - Podman >= 4.4 (Quadlet support)
#   - SSH access
# ==============================================================================

set -euo pipefail

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
REMOTE_HOST=""
LOCAL_DEPLOY=false
SSH_PORT=22
HOST_PORT=8080
FB_PORT=8081
IMAGE_NAME="visualvibe-agent:latest"
SERVICE_NAME="visualvibe-agent.service"
CONTAINER_NAME="visualvibe-agent"

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
usage() {
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  VisualVibe Agent — Deploy Script (Quadlet Systemd)${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Usage:${NC}"
    echo -e "    ${CYAN}./deploy.sh user@server${NC}                   Remote deploy"
    echo -e "    ${CYAN}./deploy.sh user@server --port 9090${NC}       Custom IDE port (default: 8080)"
    echo -e "    ${CYAN}./deploy.sh --local${NC}                         Local deploy"
    echo -e "    ${CYAN}./deploy.sh --local --port 9090${NC}             Local deploy with custom port"
    echo ""
    echo -e "  ${BOLD}Options:${NC}"
    echo -e "    --port PORT         Published IDE host port (default: 8080)"
    echo -e "    --fb-port PORT      Published FileBrowser host port (default: 8081)"
    echo -e "    --ssh-port PORT     Remote SSH port for deployment (default: 22)"
    echo -e "    --local             Deploy to local machine"
    echo -e "    -h, --help          Show this help message"
    echo ""
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            HOST_PORT="$2"
            shift 2
            ;;
        --fb-port)
            FB_PORT="$2"
            shift 2
            ;;
        --ssh-port)
            SSH_PORT="$2"
            shift 2
            ;;
        --local)
            LOCAL_DEPLOY=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            usage
            ;;
        *)
            REMOTE_HOST="$1"
            shift
            ;;
    esac
done

if [ "$LOCAL_DEPLOY" = false ] && [ -z "$REMOTE_HOST" ]; then
    echo -e "${RED}Error: specify a remote host (e.g. user@server) or use --local${NC}" >&2
    echo ""
    usage
fi

QUADLET_SRC_DIR="${SCRIPT_DIR}/quadlet"

# --------------------------------------------------------------------------
# Helper functions
# --------------------------------------------------------------------------
header() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

step() {
    echo -e "${YELLOW}[$1]${NC} $2"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Run command on target (local or remote)
# FIX D-01: The command string passed to this function must be pre-quoted.
# Variables interpolated into the command should be single-quoted in the
# caller to avoid double shell expansion (once here, once in bash -c/ssh).
run_on_target() {
    local cmd="$1"
    if [ "$LOCAL_DEPLOY" = true ]; then
        bash -c "$cmd"
    else
        ssh -p "${SSH_PORT}" "${REMOTE_HOST}" "$cmd"
    fi
}

# Copy file to target
copy_to_target() {
    local src="$1"
    local dest="$2"
    if [ "$LOCAL_DEPLOY" = true ]; then
        mkdir -p "$(dirname "$dest")"
        cp -r "$src" "$dest"
    else
        scp -P "${SSH_PORT}" -r "$src" "${REMOTE_HOST}:${dest}"
    fi
}

# --------------------------------------------------------------------------
# Determine paths for rootless user deployment
# --------------------------------------------------------------------------
if [ "$LOCAL_DEPLOY" = true ]; then
    REMOTE_HOME="${HOME}"
else
    # FIX D-02: 'echo $HOME' can return empty on non-login shells;
    # fall back to tilde expansion which always works.
    REMOTE_HOME=$(run_on_target 'echo ${HOME:-~}')
    if [ -z "$REMOTE_HOME" ] || [ "$REMOTE_HOME" = "~" ]; then
        REMOTE_HOME=$(run_on_target 'cd ~ && pwd')
    fi
fi
QUADLET_DEST="${REMOTE_HOME}/.config/containers/systemd"
SYSTEMCTL_CMD="systemctl --user"
BUILD_DIR="${REMOTE_HOME}/visualvibe-agent-build"

# FIX D-03: Ensure temp quadlet file is cleaned up on any exit (e.g. errors with set -euo pipefail)
TMP_CONTAINER_QUADLET=""
_cleanup_tmp() { [ -n "${TMP_CONTAINER_QUADLET}" ] && rm -f "${TMP_CONTAINER_QUADLET}" 2>/dev/null || true; }
trap _cleanup_tmp EXIT

# --------------------------------------------------------------------------
# Deployment execution
# --------------------------------------------------------------------------
if [ -f "${SCRIPT_DIR}/scripts/print_banner.sh" ]; then
    "${SCRIPT_DIR}/scripts/print_banner.sh"
fi

header "VisualVibe Agent — Deploy"

if [ "$LOCAL_DEPLOY" = true ]; then
    echo -e "  Target:       ${BOLD}local${NC}"
else
    echo -e "  Target:       ${BOLD}${REMOTE_HOST}${NC} (SSH port ${SSH_PORT})"
fi
echo -e "  Mode:         ${BOLD}rootless${NC}"
echo -e "  Web Port:     ${BOLD}${HOST_PORT}${NC}"
echo -e "  Quadlet Dest: ${QUADLET_DEST}"
echo -e "  Build Dir:    ${BUILD_DIR}"
echo ""

# --------------------------------------------------------------------------
# 1. Verify target prerequisites
# --------------------------------------------------------------------------
step "1/6" "Checking target prerequisites..."

PODMAN_VER=$(run_on_target "podman --version 2>/dev/null" || true)
if [ -z "$PODMAN_VER" ]; then
    fail "Podman not found on target. Please install Podman >= 4.4 with Quadlet support."
fi
ok "Podman detected: ${PODMAN_VER}"

# --------------------------------------------------------------------------
# 2. Prepare build directory on target
# --------------------------------------------------------------------------
step "2/6" "Preparing build directory..."

run_on_target "rm -rf '${BUILD_DIR}' && mkdir -p '${BUILD_DIR}'"
ok "Directory ${BUILD_DIR} ready on target"

# --------------------------------------------------------------------------
# 3. Transfer build files
# --------------------------------------------------------------------------
step "3/6" "Transferring build files to target..."

BUILD_FILES=(
    "Containerfile"
    "config"
    "media"
    "scripts"
    "entrypoint.sh"
    ".containerignore"
)

for f in "${BUILD_FILES[@]}"; do
    if [ ! -e "${SCRIPT_DIR}/${f}" ]; then
        fail "Required file or directory missing: ${SCRIPT_DIR}/${f}"
    fi
    copy_to_target "${SCRIPT_DIR}/${f}" "${BUILD_DIR}/${f}"
done
ok "Build configuration files transferred successfully"

# --------------------------------------------------------------------------
# 4. Build container image on target
# --------------------------------------------------------------------------
step "4/6" "Building image '${IMAGE_NAME}' on target..."
echo -e "       (Compiling AlmaLinux 10 base image with VS Code, Cline, and KasmVNC)"

BUILD_CMD="cd '${BUILD_DIR}' && podman build -t '${IMAGE_NAME}' . < /dev/null"
run_on_target "$BUILD_CMD"
ok "Container image built successfully"

# --------------------------------------------------------------------------
# 5. Install Quadlet service definitions
# --------------------------------------------------------------------------
step "5/6" "Installing Quadlet service files..."

run_on_target "mkdir -p '${QUADLET_DEST}'"

TMP_CONTAINER_QUADLET="/tmp/visualvibe-agent-$$.container"
sed -e "s/PublishPort=8080:8080/PublishPort=${HOST_PORT}:8080/g" \
    -e "s/PublishPort=8081:8081/PublishPort=${FB_PORT}:8081/g" \
    "${QUADLET_SRC_DIR}/visualvibe-agent.container" > "${TMP_CONTAINER_QUADLET}"

copy_to_target "${TMP_CONTAINER_QUADLET}" "${QUADLET_DEST}/visualvibe-agent.container"
copy_to_target "${QUADLET_SRC_DIR}/visualvibe-home.volume" "${QUADLET_DEST}/visualvibe-home.volume"

rm -f "${TMP_CONTAINER_QUADLET}"
ok "Quadlet files installed in ${QUADLET_DEST} (IDE port: ${HOST_PORT}, FileBrowser port: ${FB_PORT})"

# --------------------------------------------------------------------------
# 6. Reload systemd and start service
# --------------------------------------------------------------------------
step "6/6" "Activating systemd service..."

run_on_target "${SYSTEMCTL_CMD} daemon-reload"
ok "daemon-reload completed"

run_on_target "${SYSTEMCTL_CMD} stop ${SERVICE_NAME} 2>/dev/null" || true
run_on_target "${SYSTEMCTL_CMD} start ${SERVICE_NAME}"
ok "Service ${SERVICE_NAME} started"

run_on_target "${SYSTEMCTL_CMD} enable ${SERVICE_NAME} 2>/dev/null" || true
ok "Service enabled on system boot"

echo -e "  Waiting for service initialization..."
sleep 4

STATUS=$(run_on_target "${SYSTEMCTL_CMD} is-active ${SERVICE_NAME}" || true)
if [ "$STATUS" = "active" ]; then
    ok "Service is active and running"
else
    echo -e "  ${YELLOW}⚠️  Service status: ${STATUS}${NC}"
    echo -e "  ${YELLOW}    Inspect with: ${SYSTEMCTL_CMD} status ${SERVICE_NAME}${NC}"
fi

# --------------------------------------------------------------------------
# Final summary
# --------------------------------------------------------------------------
header "Deployment Completed Successfully!"

if [ "$LOCAL_DEPLOY" = true ]; then
    TARGET_HOST="localhost"
else
    TARGET_HOST=$(echo "${REMOTE_HOST}" | sed 's/.*@//')
fi

echo -e "  ${CYAN}Web Browser Access:${NC}"
echo -e "    IDE Desktop:  ${BOLD}http://${TARGET_HOST}:${HOST_PORT}/${NC}"
echo -e "    File Manager: ${BOLD}http://${TARGET_HOST}:${FB_PORT}/filebrowser/${NC}"
echo -e "    Cloudflare:   Path /filebrowser* -> port ${FB_PORT}"
echo -e "    Auth:         Disabled locally (enforce via Cloudflare Access / VPN)"
echo -e "    Display:      Dynamic resolution (1080p, 4K UHD adaptive)"
echo ""
echo -e "  ${CYAN}Service Management:${NC}"
if [ "$LOCAL_DEPLOY" = false ]; then
    echo -e "    ${BOLD}(On server ${REMOTE_HOST})${NC}"
fi
echo -e "    Status:       ${SYSTEMCTL_CMD} status ${SERVICE_NAME}"
echo -e "    Stop:         ${SYSTEMCTL_CMD} stop ${SERVICE_NAME}"
echo -e "    Start:        ${SYSTEMCTL_CMD} start ${SERVICE_NAME}"
echo -e "    Restart:      ${SYSTEMCTL_CMD} restart ${SERVICE_NAME}"
echo ""
echo -e "  ${CYAN}Container Logs:${NC}"
echo -e "    Container:    podman logs -f ${CONTAINER_NAME}"
echo -e "    Journal:      journalctl --user -u ${SERVICE_NAME} -f"
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
