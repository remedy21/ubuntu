#!/bin/bash
# ==============================================
# Ubuntu 24.x Automated Docker, Cockpit & Portainer Setup
# Author: Dickson Remedy
# ==============================================

LOGFILE="/var/log/setup_docker_portainer.log"
STAGE_FILE="/var/run/docker_portainer_stage"

exec > >(tee -a "$LOGFILE") 2>&1
set -o errexit
set -o pipefail
set -o nounset

# Disable immediate exit for noncritical steps
trap 'echo "⚠️ A non-critical step failed. Continuing..."' ERR

# Ensure root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo privileges."
  exit 1
fi

# Helper for safe execution
run_step() {
  echo -e "\n-----> $1"
  shift
  "$@" || echo "⚠️ [Warning] Step '$1' failed but continuing..."
}

# Detect stage (so we can resume)
STAGE=$(cat "$STAGE_FILE" 2>/dev/null || echo "0")

echo "=============================================="
echo "Starting setup stage $STAGE at $(date)"
echo "Logs will be saved in $LOGFILE"
echo "=============================================="

# ---------- Stage 0: Initial system update ----------
if [ "$STAGE" = "0" ]; then
  run_step "Updating system packages..." apt update -y
  run_step "Upgrading system packages..." apt upgrade -y

  echo "✅ Base system update complete. Preparing for reboot..."
  echo "1" > "$STAGE_FILE"

  # Create systemd service to auto-resume after reboot
  cat >/etc/systemd/system/setup-docker-portainer.service <<'EOF'
[Unit]
Description=Resume Docker & Portainer setup after reboot
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /root/setup_docker_portainer.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable setup-docker-portainer.service
  echo "System will reboot in 10 seconds to continue setup..."
  sleep 10
  reboot
fi

# ---------- Stage 1: Post-reboot setup ----------
if [ "$STAGE" = "1" ]; then
  run_step "Creating Docker directories..." bash -c '
    mkdir -p /docker/apps/portainer /docker/storage
  '

  run_step "Installing prerequisites..." apt install -y ca-certificates curl gnupg lsb-release

  run_step "Adding Docker GPG key..." bash -c '
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  '

  run_step "Adding Docker repository..." bash -c '
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
  '

  run_step "Updating package list..." apt update -y

  run_step "Installing Docker & Compose..." apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  run_step "Enabling Docker service..." systemctl enable --now docker
  run_step "Verifying Docker..." docker --version

  run_step "Installing Cockpit..." apt install -y cockpit
  run_step "Enabling Cockpit service..." systemctl enable --now cockpit.socket

  run_step "Allowing root SSH login..." bash -c '
    sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config
    systemctl restart ssh
  '

  run_step "Deploying Portainer..." docker run -d \
    -p 8000:8000 -p 9443:9443 \
    --name portainer \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /docker/apps/portainer:/data \
    portainer/portainer-ce:lts

  run_step "Verifying Portainer container..." docker ps | grep portainer || echo "⚠️ Portainer not found, check Docker logs."

  echo "✅ Setup complete! Cleaning up..."
  echo "2" > "$STAGE_FILE"

  # Disable auto-resume
  systemctl disable setup-docker-portainer.service
  rm -f /etc/systemd/system/setup-docker-portainer.service

  echo "System will reboot in 20 seconds..."
  sleep 20
  reboot
fi
