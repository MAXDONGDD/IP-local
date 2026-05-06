#!/usr/bin/env bash
set -u

INSTALL_DIR="${INSTALL_DIR:-/opt/ip_sentinel}"
CONFIG_FILE="${CONFIG_FILE:-${INSTALL_DIR}/config.conf}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "config missing: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

LOG_FILE="${LOG_FILE:-${INSTALL_DIR}/logs/sentinel.log}"
JITTER_SECONDS="${JITTER_SECONDS:-180}"
LOCAL_SAFE_VERSION="${LOCAL_SAFE_VERSION:-unknown}"

mkdir -p "${INSTALL_DIR}/logs"

exec 200>"/tmp/ip_sentinel_local_safe.lock"
if ! flock -n 200; then
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [v${LOCAL_SAFE_VERSION}] [WARN ] [SYSTEM ] [${REGION_CODE:-NA}] previous run still active, skipping" >> "$LOG_FILE"
  exit 0
fi

log() {
  local module="$1"
  local level="$2"
  local msg="$3"
  local line
  line=$(printf "[v%-7s] [%-5s] [%-7s] [%s] %s" "$LOCAL_SAFE_VERSION" "$level" "$module" "${REGION_CODE:-NA}" "$msg")
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $line" >> "$LOG_FILE"
  if command -v logger >/dev/null 2>&1; then
    logger -t ip-sentinel-local-safe "$line"
  fi
}

export -f log
export INSTALL_DIR CONFIG_FILE LOG_FILE

if [ -t 1 ]; then
  log "SYSTEM" "INFO" "interactive run detected, skipping startup jitter"
else
  jitter=$((RANDOM % (JITTER_SECONDS + 1)))
  log "SYSTEM" "INFO" "timer wakeup, sleeping ${jitter}s before run"
  sleep "$jitter"
fi

target_mod=""
target_name=""

if [ "${ENABLE_GOOGLE:-true}" = "true" ] && [ "${ENABLE_TRUST:-false}" = "true" ]; then
  roll=$((RANDOM % 100 + 1))
  if [ "$roll" -le 80 ]; then
    target_mod="mod_google.sh"
    target_name="Google/YouTube region correction"
  else
    target_mod="mod_trust.sh"
    target_name="optional trust warmup"
  fi
elif [ "${ENABLE_GOOGLE:-true}" = "true" ]; then
  target_mod="mod_google.sh"
  target_name="Google/YouTube region correction"
elif [ "${ENABLE_TRUST:-false}" = "true" ]; then
  target_mod="mod_trust.sh"
  target_name="optional trust warmup"
else
  log "SYSTEM" "WARN" "all modules disabled"
  exit 0
fi

if [ -x "${INSTALL_DIR}/core/${target_mod}" ]; then
  log "SYSTEM" "INFO" "running ${target_name}"
  nice -n 19 bash "${INSTALL_DIR}/core/${target_mod}" 200>&-
else
  log "SYSTEM" "ERROR" "module not found or not executable: ${target_mod}"
  exit 1
fi

log "SYSTEM" "INFO" "run complete"

