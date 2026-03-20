#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Brad (custom)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source:  https://github.com/fscorrupt/Posterizarr
#
# This script runs INSIDE the LXC container (via lxc-attach / pct exec).
# It is called automatically by build.func after the container is created.

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ─── Base Dependencies ────────────────────────────────────────────────────────
msg_info "Installing Base Dependencies"
$STD apt-get install -y \
  curl \
  wget \
  git \
  gnupg2 \
  ca-certificates \
  apt-transport-https \
  software-properties-common \
  imagemagick \
  unzip
msg_ok "Installed Base Dependencies"

# ─── PowerShell ──────────────────────────────────────────────────────────────
msg_info "Installing PowerShell"
wget -q "https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb" \
  -O /tmp/packages-microsoft-prod.deb
$STD dpkg -i /tmp/packages-microsoft-prod.deb
$STD apt-get update
$STD apt-get install -y powershell
rm -f /tmp/packages-microsoft-prod.deb
msg_ok "Installed PowerShell"

# ─── Node.js 20.x ────────────────────────────────────────────────────────────
msg_info "Installing Node.js 20.x"
curl -fsSL https://deb.nodesource.com/setup_20.x | $STD bash -
$STD apt-get install -y nodejs
msg_ok "Installed Node.js $(node --version)"

# ─── Python 3 ────────────────────────────────────────────────────────────────
msg_info "Installing Python3"
$STD apt-get install -y python3 python3-pip python3-venv
msg_ok "Installed Python $(python3 --version | awk '{print $2}')"

# ─── FanartTV PowerShell Module ───────────────────────────────────────────────
msg_info "Installing FanartTV PowerShell Module"
$STD pwsh -Command "Install-Module -Name FanartTvAPI -Force -Scope AllUsers -Repository PSGallery"
msg_ok "Installed FanartTV PowerShell Module"

# ─── Posterizarr ─────────────────────────────────────────────────────────────
msg_info "Fetching Latest Posterizarr Release"
RELEASE=$(curl -fsSL https://api.github.com/repos/fscorrupt/Posterizarr/releases/latest \
  | grep '"tag_name"' | cut -d'"' -f4)
msg_ok "Latest Release: ${RELEASE}"

msg_info "Downloading Posterizarr ${RELEASE}"
mkdir -p /opt/posterizarr
curl -fsSL "https://github.com/fscorrupt/Posterizarr/archive/refs/tags/${RELEASE}.tar.gz" \
  | tar -xz --strip-components=1 -C /opt/posterizarr
echo "${RELEASE}" >/opt/posterizarr_version.txt
msg_ok "Downloaded Posterizarr ${RELEASE}"

# ─── Directory Layout ─────────────────────────────────────────────────────────
msg_info "Creating Directory Structure"
mkdir -p /config /assets /assetsbackup /manualassets
if [[ -f /opt/posterizarr/config.example.json && ! -f /config/config.json ]]; then
  cp /opt/posterizarr/config.example.json /config/config.json
fi
msg_ok "Directories Created"

# ─── Web UI Setup ─────────────────────────────────────────────────────────────
msg_info "Setting Up Web UI Backend (Python)"
cd /opt/posterizarr/webui
$STD bash setup.sh
msg_ok "Web UI Dependencies Installed"

msg_info "Building Web UI Frontend (Node.js)"
cd /opt/posterizarr/webui/frontend
$STD npm run build
msg_ok "Frontend Built"

# ─── systemd Service ──────────────────────────────────────────────────────────
msg_info "Creating posterizarr-backend systemd Service"
cat <<EOF >/etc/systemd/system/posterizarr-backend.service
[Unit]
Description=Posterizarr Web UI Backend
Documentation=https://fscorrupt.github.io/posterizarr/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/posterizarr/webui/backend
ExecStart=/usr/bin/python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=TERM=xterm
Environment=RUN_TIME=disabled

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now posterizarr-backend
msg_ok "Posterizarr Service Started"

# ─── Cleanup ─────────────────────────────────────────────────────────────────
motd_ssh
customize

msg_info "Cleaning Up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned Up"

msg_info "Setting Version File"
echo "${RELEASE}" >/opt/${APP}_version.txt
msg_ok "Version set to ${RELEASE}"
