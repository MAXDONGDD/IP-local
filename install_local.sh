#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/ip_sentinel"
CONFIG_SRC="${SRC_DIR}/config.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo bash install_local.sh" >&2
  exit 1
fi

if [ ! -f "$CONFIG_SRC" ]; then
  CONFIG_SRC="${SRC_DIR}/config.example"
fi

mkdir -p "${INSTALL_DIR}/core" "${INSTALL_DIR}/data" "${INSTALL_DIR}/logs" "${INSTALL_DIR}/scripts"

cp -R "${SRC_DIR}/core/." "${INSTALL_DIR}/core/"
cp -R "${SRC_DIR}/data/." "${INSTALL_DIR}/data/"
cp -R "${SRC_DIR}/scripts/." "${INSTALL_DIR}/scripts/"
cp "${SRC_DIR}/uninstall_local.sh" "${INSTALL_DIR}/uninstall_local.sh"
cp "${SRC_DIR}/status_local.sh" "${INSTALL_DIR}/status_local.sh"
cp "${SRC_DIR}/README.md" "${INSTALL_DIR}/README.md"
cp "${SRC_DIR}/README_SAFE.md" "${INSTALL_DIR}/README_SAFE.md"

if [ ! -f "${INSTALL_DIR}/config.conf" ]; then
  cp "$CONFIG_SRC" "${INSTALL_DIR}/config.conf"
else
  cp "$CONFIG_SRC" "${INSTALL_DIR}/config.conf.new"
  echo "Existing config preserved at ${INSTALL_DIR}/config.conf"
  echo "New example copied to ${INSTALL_DIR}/config.conf.new"
fi

chmod +x "${INSTALL_DIR}/core/"*.sh "${INSTALL_DIR}/uninstall_local.sh" "${INSTALL_DIR}/status_local.sh" "${INSTALL_DIR}/scripts/"*.sh

# shellcheck disable=SC1091
source "${INSTALL_DIR}/config.conf"
RUN_INTERVAL_MINUTES="${RUN_INTERVAL_MINUTES:-30}"

if command -v systemctl >/dev/null 2>&1 && [ -d /etc/systemd/system ]; then
  cat > /etc/systemd/system/ip-sentinel.service <<SERVICE
[Unit]
Description=IP Sentinel Local Safe runner
Documentation=file:${INSTALL_DIR}/README.md

[Service]
Type=oneshot
ExecStart=${INSTALL_DIR}/core/runner.sh
Nice=19
SERVICE

  cat > /etc/systemd/system/ip-sentinel.timer <<TIMER
[Unit]
Description=Run IP Sentinel Local Safe periodically

[Timer]
OnBootSec=5min
OnUnitActiveSec=${RUN_INTERVAL_MINUTES}min
RandomizedDelaySec=120
Persistent=true

[Install]
WantedBy=timers.target
TIMER

  systemctl daemon-reload
  systemctl enable --now ip-sentinel.timer
  echo "Installed systemd timer: ip-sentinel.timer"
else
  marker="ip_sentinel_local_safe"
  tmp_cron="$(mktemp)"
  crontab -l 2>/dev/null | grep -v "$marker" > "$tmp_cron" || true
  echo "*/${RUN_INTERVAL_MINUTES} * * * * ${INSTALL_DIR}/core/runner.sh # ${marker}" >> "$tmp_cron"
  crontab "$tmp_cron"
  rm -f "$tmp_cron"
  echo "Installed root crontab entry"
fi

echo "No firewall rules changed. No public ports opened."
echo "Log: ${INSTALL_DIR}/logs/sentinel.log"
echo "Status report: sudo bash ${INSTALL_DIR}/status_local.sh"
