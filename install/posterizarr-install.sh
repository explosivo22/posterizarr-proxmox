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
  unzip \
  jq \
  cron \
  build-essential \
  libjpeg-dev \
  libpng-dev \
  libfreetype-dev \
  libwebp-dev \
  libtiff-dev \
  libopenjp2-7-dev \
  pkg-config
msg_ok "Installed Base Dependencies"

# ─── ImageMagick 7 (compiled from source) ────────────────────────────────────
# Debian 12 apt ships ImageMagick 6.x; Posterizarr requires 7.x.
# Per walkthrough ARM section: download from imagemagick.org/archive (official source).
msg_info "Compiling ImageMagick 7 from source (takes a few minutes)"
wget -q "https://imagemagick.org/archive/ImageMagick.tar.gz" -O /tmp/imagemagick.tar.gz
tar -xzf /tmp/imagemagick.tar.gz -C /tmp
IM_DIR=$(find /tmp -maxdepth 1 -type d -name "ImageMagick-*" | head -1)
cd "${IM_DIR}"
$STD ./configure --with-jpeg=yes --with-png=yes --with-freetype=yes --with-webp=yes
$STD make -j"$(nproc)"
$STD make install
$STD ldconfig /usr/local/lib
rm -rf /tmp/imagemagick.tar.gz "${IM_DIR}"
cd /
msg_ok "Installed ImageMagick $(magick -version 2>&1 | head -1 | awk '{print $3}')"

# ─── PowerShell 7.x ──────────────────────────────────────────────────────────
msg_info "Installing PowerShell 7"
wget -q "https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb" \
  -O /tmp/packages-microsoft-prod.deb
$STD dpkg -i /tmp/packages-microsoft-prod.deb
$STD apt-get update
$STD apt-get install -y powershell
rm -f /tmp/packages-microsoft-prod.deb
msg_ok "Installed PowerShell $(pwsh --version)"

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

# Per walkthrough: create the global PS profile and add the import statement so
# FanartTvAPI is auto-loaded every time pwsh starts.
msg_info "Configuring PowerShell Global Profile"
mkdir -p /etc/powershell
PROFILE_FILE="/etc/powershell/profile.ps1"
touch "${PROFILE_FILE}"
if ! grep -q "FanartTvAPI" "${PROFILE_FILE}"; then
  echo "Import-Module FanartTvAPI -Force" >>"${PROFILE_FILE}"
fi
msg_ok "PowerShell Profile Configured (${PROFILE_FILE})"

# ─── Posterizarr (git clone) ─────────────────────────────────────────────────
# Walkthrough uses git clone (not tarball) so the working directory and
# relative internal paths behave as the developer expects.
msg_info "Cloning Posterizarr"
RELEASE=$(curl -fsSL https://api.github.com/repos/fscorrupt/Posterizarr/releases/latest \
  | grep '"tag_name"' | cut -d'"' -f4)
$STD git clone --depth=1 --branch "${RELEASE}" \
  https://github.com/fscorrupt/Posterizarr.git /opt/posterizarr
echo "${RELEASE}" >/opt/posterizarr_version.txt
msg_ok "Cloned Posterizarr ${RELEASE} to /opt/posterizarr"

# ─── Directory Layout ─────────────────────────────────────────────────────────
msg_info "Creating Directory Structure"
mkdir -p /config /assets /assetsbackup /manualassets

# Posterizarr.ps1 looks for config.json in its own working directory (/opt/posterizarr).
# We keep the canonical copy in /config (persistent, survives updates) and symlink it
# into the repo root so the script finds it at both locations.
if [[ -f /opt/posterizarr/config.example.json && ! -f /config/config.json ]]; then
  cp /opt/posterizarr/config.example.json /config/config.json
  # Set AssetPath to /assets per walkthrough guidance for non-Docker Linux installs
  sed -i 's|"AssetPath"[[:space:]]*:[[:space:]]*"[^"]*"|"AssetPath": "/assets"|g' /config/config.json
fi
# Symlink so Posterizarr.ps1 finds config.json at its expected relative path
ln -sf /config/config.json /opt/posterizarr/config.json
msg_ok "Directories Created"

# ─── Web UI Setup ─────────────────────────────────────────────────────────────
msg_info "Setting Up Web UI Backend (Python)"
cd /opt/posterizarr/webui
$STD bash setup.sh
msg_ok "Web UI Backend Dependencies Installed"

msg_info "Building Web UI Frontend (Node.js)"
cd /opt/posterizarr/webui/frontend
$STD npm run build
msg_ok "Frontend Built"

# ─── systemd Service — Web UI Backend ────────────────────────────────────────
msg_info "Creating posterizarr-backend systemd Service"
# Detect the Python binary — setup.sh may have created a virtualenv
if [ -f /opt/posterizarr/webui/backend/.venv/bin/python3 ]; then
  PYTHON_BIN="/opt/posterizarr/webui/backend/.venv/bin/python3"
elif [ -f /opt/posterizarr/webui/backend/venv/bin/python3 ]; then
  PYTHON_BIN="/opt/posterizarr/webui/backend/venv/bin/python3"
else
  PYTHON_BIN="/usr/bin/python3"
fi
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
ExecStart=${PYTHON_BIN} -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=TERM=xterm
Environment=RUN_TIME=disabled
Environment=TZ=UTC

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now posterizarr-backend
msg_ok "Posterizarr Backend Service Started"

# ─── First Run (initializes PS module self-install & validates environment) ───
# Per walkthrough: the script must be run once as root/sudo before scheduled use
# because on first run it installs additional PowerShell components itself.
msg_info "Running Posterizarr.ps1 first-time initialization"
cd /opt/posterizarr
pwsh Posterizarr.ps1 -Testing >/var/log/posterizarr-firstrun.log 2>&1 || true
msg_ok "First-run initialization complete (see /var/log/posterizarr-firstrun.log)"

# ─── Cron — Scheduled Poster Generation ──────────────────────────────────────
# Per walkthrough: on non-Docker installs, scheduling is done via cron.
# Default: every 2 hours. User can edit with: crontab -e
msg_info "Installing Scheduled Cron Job (every 2 hours)"
systemctl enable -q cron
(crontab -l 2>/dev/null; \
  echo "0 */2 * * * cd /opt/posterizarr && pwsh Posterizarr.ps1 >>/var/log/posterizarr.log 2>&1") \
  | crontab -
msg_ok "Cron Job Installed (edit schedule with: crontab -e)"

# ─── Cleanup ─────────────────────────────────────────────────────────────────
motd_ssh
customize

msg_info "Cleaning Up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned Up"
