#!/usr/bin/env bash
set -u

MODULE_NAME="Trust"
INSTALL_DIR="${INSTALL_DIR:-/opt/ip_sentinel}"
CONFIG_FILE="${CONFIG_FILE:-${INSTALL_DIR}/config.conf}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "config missing: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

LOG_FILE="${LOG_FILE:-${INSTALL_DIR}/logs/sentinel.log}"
UA_FILE="${INSTALL_DIR}/data/user_agents.txt"
TRUST_FILE="${INSTALL_DIR}/data/trust/trust_${REGION_CODE}.txt"

if ! type log >/dev/null 2>&1; then
  log() {
    local module="$1"
    local level="$2"
    local msg="$3"
    mkdir -p "${INSTALL_DIR}/logs"
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [v${LOCAL_SAFE_VERSION:-unknown}] [${level}] [${module}] [${REGION_CODE:-NA}] ${msg}" >> "$LOG_FILE"
  }
fi

if [ ! -f "$TRUST_FILE" ]; then
  log "$MODULE_NAME" "WARN" "trust list missing for ${REGION_CODE}, skipping optional module"
  exit 0
fi

mapfile -t UA_POOL < <(grep -v '^[[:space:]]*$' "$UA_FILE")
mapfile -t TRUST_URLS < <(grep -v '^[[:space:]]*$' "$TRUST_FILE" | grep -v '^#')

[ "${#UA_POOL[@]}" -eq 0 ] && UA_POOL=("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")

CURL_ARGS=(-m 12 -s -L -A "${UA_POOL[$((RANDOM % ${#UA_POOL[@]}))]}")
if [ "${IP_PREF:-4}" = "6" ]; then
  CURL_ARGS=(-6 "${CURL_ARGS[@]}")
else
  CURL_ARGS=(-4 "${CURL_ARGS[@]}")
fi
if [ -n "${BIND_IP:-}" ]; then
  CURL_ARGS=(--interface "$BIND_IP" "${CURL_ARGS[@]}")
fi

log "$MODULE_NAME" "START" "optional trust warmup enabled"

count=0
for url in "${TRUST_URLS[@]}"; do
  count=$((count + 1))
  code=$(curl "${CURL_ARGS[@]}" -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || true)
  log "$MODULE_NAME" "EXEC" "url=${url} http=${code:-000}"
  [ "$count" -ge 3 ] && break
  sleep $((30 + RANDOM % 31))
done

log "$MODULE_NAME" "END" "optional trust warmup complete"

