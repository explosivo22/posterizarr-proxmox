#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Brad (custom)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source:  https://github.com/fscorrupt/Posterizarr

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

function header_info {
  clear
  cat <<"EOF"
    ____           __            _                     
   / __ \____  ___/ /____  _____(_)___  ____ ___________
  / /_/ / __ \/ __  / __ \/ ___/ /_  / / __ `/ ___/ ___/
 / ____/ /_/ / /_/ / /_/ (__  ) / / /_/ /_/ / /  / /    
/_/    \____/\__,_/\____/____/_/ /___/\__,_/_/  /_/     
EOF
}

header_info
echo -e "Loading..."
APP="Posterizarr"
var_disk="12"
var_cpu="2"
var_ram="2048"
var_os="debian"
var_version="12"
var_unprivileged="1"

variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /opt/posterizarr_version.txt ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -fsSL https://api.github.com/repos/fscorrupt/Posterizarr/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
  if [[ "${RELEASE}" != "$(cat /opt/posterizarr_version.txt)" ]]; then
    msg_info "Updating ${APP} to ${RELEASE}"
    systemctl stop posterizarr-backend
    rm -rf /opt/posterizarr
    git clone --depth=1 --branch "${RELEASE}" \
      https://github.com/fscorrupt/Posterizarr.git /opt/posterizarr
    # Re-create symlink so Posterizarr.ps1 finds config.json in its working directory
    ln -sf /config/config.json /opt/posterizarr/config.json
    cd /opt/posterizarr/webui && bash setup.sh
    cd /opt/posterizarr/webui/frontend && npm run build
    echo "${RELEASE}" >/opt/posterizarr_version.txt
    systemctl start posterizarr-backend
    msg_ok "Updated ${APP} to ${RELEASE}"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been completed successfully!${CL}"
echo -e "${INFO}${YW} Access the Posterizarr Web UI:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
echo -e "${INFO}${YW} Config directory inside container: /config${CL}"
echo -e "${INFO}${YW} Assets directory inside container: /assets${CL}"
echo -e "${INFO}${YW} To update, re-run this script and choose 'update'${CL}"
