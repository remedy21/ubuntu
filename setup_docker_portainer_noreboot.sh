#!/bin/bash
# ==============================================
# Ubuntu 24.x Automated Docker, Cockpit & Portainer Setup (No Reboot)
# Author: Dickson Remedy
# ==============================================

LOGFILE="/var/log/setup_docker_portainer.log"

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

echo "=============================================="
echo "Starting setup at $(date)"
echo "Logs will be saved in $LOGFILE"
echo "=============================================="

# ---------- System Update ----------
run_step "Updating system packages..." apt update -y
run_step "Upgrading system packages..." apt upgrade -y

# ---------- Directory Setup ----------
run_step "Creating Docker directories..." bash -c '
  mkdir -p /docker/apps/portainer /docker/storage
'

# ---------- Dependencies ----------
run_step "Installing prerequisites..." apt install -y ca-certificates curl gnupg lsb-release

# ---------- Docker Repository ----------
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

# ---------- Docker Installation ----------
run_step "Installing Docker & Compose..." apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
run_step "Enabling Docker service..." systemctl enable --now docker
run_step "Verifying Docker installation..." docker --version

# ---------- Cockpit Installation ----------
run_step "Installing Cockpit..." apt install -y cockpit
run_step "Enabling Cockpit service..." systemctl enable --now cockpit.socket

# ---------- SSH Configuration ----------
run_step "Allowing root SSH login..." bash -c '
  sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config
  systemctl restart ssh
'

# ---------- Portainer Deployment ----------
run_step "Deploying Portainer container..." docker run -d \
  -p 8000:8000 -p 9443:9443 \
  --name portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /docker/apps/portainer:/data \
  portainer/p
