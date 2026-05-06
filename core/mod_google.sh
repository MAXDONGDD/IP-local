#!/usr/bin/env bash
set -u

MODULE_NAME="Google"
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
KW_FILE="${INSTALL_DIR}/data/keywords/kw_${REGION_CODE}.txt"

if ! type log >/dev/null 2>&1; then
  log() {
    local module="$1"
    local level="$2"
    local msg="$3"
    mkdir -p "${INSTALL_DIR}/logs"
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [v${LOCAL_SAFE_VERSION:-unknown}] [${level}] [${module}] [${REGION_CODE:-NA}] ${msg}" >> "$LOG_FILE"
  }
fi

if [ ! -f "$UA_FILE" ] || [ ! -f "$KW_FILE" ]; then
  log "$MODULE_NAME" "ERROR" "missing data files: ${UA_FILE} or ${KW_FILE}"
  exit 1
fi

mapfile -t UA_POOL < <(grep -v '^[[:space:]]*$' "$UA_FILE")
mapfile -t KEYWORDS < <(grep -v '^[[:space:]]*$' "$KW_FILE")

if [ "${#UA_POOL[@]}" -eq 0 ] || [ "${#KEYWORDS[@]}" -eq 0 ]; then
  log "$MODULE_NAME" "ERROR" "empty user agent or keyword pool"
  exit 1
fi

url_encode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))' 2>/dev/null
}

get_random_coord() {
  local base="$1"
  local range="$2"
  awk -v base="$base" -v r="$range" -v seed="$RANDOM" 'BEGIN { srand(seed); printf "%.6f", base + ((rand() * r * 2 - r) / 10000) }'
}

curl_code() {
  curl "${CURL_ARGS[@]}" -o /dev/null -w "%{http_code}" "$@" 2>/dev/null || true
}

CURRENT_IP="${PUBLIC_IP:-}"
if [ -z "$CURRENT_IP" ]; then
  CURRENT_IP=$(curl -4 -m 5 -s https://api.ipify.org 2>/dev/null || true)
fi
[ -z "$CURRENT_IP" ] && CURRENT_IP="${BIND_IP:-unknown}"

seed=$(printf "%s" "$CURRENT_IP" | cksum | awk '{print $1}')
total_ua="${#UA_POOL[@]}"
session_ua="${UA_POOL[$((seed % total_ua))]}"
session_lat=$(get_random_coord "${BASE_LAT}" 270)
session_lon=$(get_random_coord "${BASE_LON}" 270)
target_cc="${REGION_CODE%%-*}"
[ "$target_cc" = "UK" ] && target_cc="GB"

CURL_ARGS=(-m 15 -s -L -A "$session_ua")
if [ "${IP_PREF:-4}" = "6" ]; then
  CURL_ARGS=(-6 "${CURL_ARGS[@]}")
else
  CURL_ARGS=(-4 "${CURL_ARGS[@]}")
fi
if [ -n "${BIND_IP:-}" ]; then
  CURL_ARGS=(--interface "$BIND_IP" "${CURL_ARGS[@]}")
fi

log "$MODULE_NAME" "START" "region=${REGION_CODE} public_ip=${CURRENT_IP} anchor=${session_lat},${session_lon}"

actions=$((4 + RANDOM % 3))
for ((i = 1; i <= actions; i++)); do
  keyword="${KEYWORDS[$((RANDOM % ${#KEYWORDS[@]}))]}"
  encoded_keyword=$(printf "%s" "$keyword" | url_encode)
  [ -z "$encoded_keyword" ] && encoded_keyword="${keyword// /+}"

  action=$((1 + RANDOM % 5))
  lat=$(get_random_coord "$session_lat" 1)
  lon=$(get_random_coord "$session_lon" 1)

  case "$action" in
    1) code=$(curl_code "https://www.google.com/search?q=${encoded_keyword}&${LANG_PARAMS}") ;;
    2) code=$(curl_code "https://news.google.com/home?${LANG_PARAMS}") ;;
    3) code=$(curl_code "https://www.google.com/maps/search/${encoded_keyword}/@${lat},${lon},17z?${LANG_PARAMS}") ;;
    4) code=$(curl_code "https://www.youtube.com/results?search_query=${encoded_keyword}&gl=${target_cc}") ;;
    *) code=$(curl_code "https://connectivitycheck.gstatic.com/generate_204") ;;
  esac

  log "$MODULE_NAME" "EXEC" "action=${i}/${actions} http=${code:-000} keyword=${keyword}"
  if [ "$i" -lt "$actions" ]; then
    sleep_time=$((45 + RANDOM % 46))
    log "$MODULE_NAME" "WAIT" "sleeping ${sleep_time}s"
    sleep "$sleep_time"
  fi
done

log "$MODULE_NAME" "INFO" "starting Google/YouTube region probes"

jump_headers=$(curl "${CURL_ARGS[@]}" -I "http://www.google.com/" 2>/dev/null || true)
jump_location=$(printf "%s" "$jump_headers" | awk 'tolower($1)=="location:" {print $2}' | tr -d '\r' | head -n 1)
jump_gl=""
case "$jump_location" in
  *google.cn*|*gl=CN*) jump_gl="CN" ;;
  *gl=*) jump_gl=$(printf "%s" "$jump_location" | grep -o 'gl=[A-Za-z][A-Za-z]' | head -n 1 | cut -d= -f2 | tr '[:lower:]' '[:upper:]') ;;
  "") jump_gl="US" ;;
esac

yt_premium=$(curl "${CURL_ARGS[@]}" "https://www.youtube.com/premium" 2>/dev/null || true)
yt_music=$(curl "${CURL_ARGS[@]}" "https://music.youtube.com/" 2>/dev/null || true)

extract_gl() {
  grep -Eo '"(contentRegion|countryCode|INNERTUBE_CONTEXT_GL|GL)":"[A-Za-z]{2}"' | head -n 1 | awk -F'"' '{print $4}' | tr '[:lower:]' '[:upper:]'
}

yt_pr_gl=$(printf "%s" "$yt_premium" | extract_gl)
yt_mu_gl=$(printf "%s" "$yt_music" | extract_gl)
printf "%s" "$yt_premium" | grep -q 'www.google.cn' && yt_pr_gl="CN"
printf "%s" "$yt_music" | grep -q 'www.google.cn' && yt_mu_gl="CN"

if [ "$jump_gl" = "CN" ] || [ "$yt_pr_gl" = "CN" ] || [ "$yt_mu_gl" = "CN" ]; then
  status="CN risk detected: jump=${jump_gl:-unknown} premium=${yt_pr_gl:-unknown} music=${yt_mu_gl:-unknown}"
elif [ "$yt_pr_gl" = "$target_cc" ] || [ "$yt_mu_gl" = "$target_cc" ]; then
  status="target reached or warming: target=${target_cc} jump=${jump_gl:-unknown} premium=${yt_pr_gl:-unknown} music=${yt_mu_gl:-unknown}"
else
  status="region drift: target=${target_cc} jump=${jump_gl:-unknown} premium=${yt_pr_gl:-unknown} music=${yt_mu_gl:-unknown}"
fi

log "$MODULE_NAME" "SCORE" "$status"
log "$MODULE_NAME" "END" "session complete"

