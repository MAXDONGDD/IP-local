#!/usr/bin/env bash
set -euo pipefail

UPSTREAM="${UPSTREAM:-https://github.com/hotyue/IP-Sentinel.git}"

if ! command -v git >/dev/null 2>&1; then
  echo "git is required to check upstream" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

git ls-remote "$UPSTREAM" HEAD

cat <<'NOTE'

Review upstream manually before porting anything.
Continue excluding Master, Telegram, Webhook, OTA, telemetry, firewall changes, and public listeners.
Prefer copying only reviewed data updates under data/ or small safe logic fixes in core modules.
NOTE

