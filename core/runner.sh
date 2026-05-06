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
LOG_MAX_SIZE_MB="${LOG_MAX_SIZE_MB:-5}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-14}"
LOG_ROTATE_KEEP="${LOG_ROTATE_KEEP:-5}"

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

cleanup_logs() {
  local log_dir log_base max_bytes current_bytes rotated_log
  log_dir="$(dirname "$LOG_FILE")"
  log_base="$(basename "$LOG_FILE")"

  mkdir -p "$log_dir"

  if printf "%s" "$LOG_RETENTION_DAYS" | grep -Eq '^[0-9]+$'; then
    find "$log_dir" -maxdepth 1 -type f -name "${log_base}.*" -mtime +"$LOG_RETENTION_DAYS" -exec rm -f {} + 2>/dev/null || true
  fi

  if printf "%s" "$LOG_ROTATE_KEEP" | grep -Eq '^[0-9]+$' && [ "$LOG_ROTATE_KEEP" -gt 0 ]; then
    find "$log_dir" -maxdepth 1 -type f -name "${log_base}.*" -printf '%T@ %p\n' 2>/dev/null \
      | sort -rn \
      | awk -v keep="$LOG_ROTATE_KEEP" 'NR > keep { $1=""; sub(/^ /, ""); print }' \
      | while IFS= read -r old_log; do
          [ -n "$old_log" ] && rm -f "$old_log"
        done
  fi

  if ! printf "%s" "$LOG_MAX_SIZE_MB" | grep -Eq '^[0-9]+$'; then
    return 0
  fi
  [ "$LOG_MAX_SIZE_MB" -le 0 ] && return 0
  [ ! -f "$LOG_FILE" ] && return 0

  max_bytes=$((LOG_MAX_SIZE_MB * 1024 * 1024))
  current_bytes=$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' ')
  [ -z "$current_bytes" ] && return 0

  if [ "$current_bytes" -gt "$max_bytes" ]; then
    rotated_log="${LOG_FILE}.$(date -u '+%Y%m%d%H%M%S')"
    mv "$LOG_FILE" "$rotated_log"
    : > "$LOG_FILE"
    if command -v gzip >/dev/null 2>&1; then
      gzip -f "$rotated_log" 2>/dev/null || true
    fi
    log "SYSTEM" "INFO" "rotated log after ${current_bytes} bytes"
  fi
}

export -f log
export INSTALL_DIR CONFIG_FILE LOG_FILE

cleanup_logs

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
