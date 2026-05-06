#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/ip_sentinel"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo bash uninstall_local.sh" >&2
  exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now ip-sentinel.timer 2>/dev/null || true
  rm -f /etc/systemd/system/ip-sentinel.timer /etc/systemd/system/ip-sentinel.service
  systemctl daemon-reload 2>/dev/null || true
fi

tmp_cron="$(mktemp)"
crontab -l 2>/dev/null | grep -v "ip_sentinel_local_safe" > "$tmp_cron" || true
crontab "$tmp_cron" 2>/dev/null || true
rm -f "$tmp_cron"

rm -rf "$INSTALL_DIR"

echo "ip-sentinel-local-safe uninstalled"

