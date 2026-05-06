#!/usr/bin/env bash
set -u

INSTALL_DIR="${INSTALL_DIR:-/opt/ip_sentinel}"
CONFIG_FILE="${CONFIG_FILE:-${INSTALL_DIR}/config.conf}"

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

LOG_FILE="${LOG_FILE:-${INSTALL_DIR}/logs/sentinel.log}"
RUN_INTERVAL_MINUTES="${RUN_INTERVAL_MINUTES:-30}"
REGION_CODE="${REGION_CODE:-unknown}"
ENABLE_GOOGLE="${ENABLE_GOOGLE:-unknown}"
ENABLE_TRUST="${ENABLE_TRUST:-unknown}"
LOCAL_SAFE_VERSION="${LOCAL_SAFE_VERSION:-unknown}"
LOG_MAX_SIZE_MB="${LOG_MAX_SIZE_MB:-5}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-14}"
LOG_ROTATE_KEEP="${LOG_ROTATE_KEEP:-5}"

now_utc="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
if cutoff="$(date -u -d '7 days ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"; then
  :
else
  cutoff="$(date -u -v-7d '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
fi

if [ -z "$cutoff" ]; then
  echo "无法计算 7 天前时间：当前系统 date 不支持 -d 或 -v。"
  exit 1
fi

tmp_recent="$(mktemp)"
trap 'rm -f "$tmp_recent"' EXIT

if [ -f "$LOG_FILE" ]; then
  awk -v cutoff="$cutoff" '
    substr($0, 1, 1) == "[" && substr($0, 22, 3) == "UTC" {
      ts = substr($0, 2, 19)
      if (ts >= cutoff) print
    }
  ' "$LOG_FILE" > "$tmp_recent"
fi

count_lines() {
  grep -c "$1" "$tmp_recent" 2>/dev/null || true
}

last_match() {
  grep "$1" "$tmp_recent" 2>/dev/null | tail -n 1 || true
}

total_lines=$(wc -l < "$tmp_recent" 2>/dev/null | tr -d ' ')
start_count=$(count_lines '\[START[[:space:]]*\]')
end_count=$(count_lines '\[END[[:space:]]*\]')
score_count=$(count_lines '\[SCORE[[:space:]]*\]')
exec_count=$(count_lines '\[EXEC[[:space:]]*\]')
warn_count=$(count_lines '\[WARN[[:space:]]*\]')
error_count=$(count_lines '\[ERROR[[:space:]]*\]')
skip_count=$(count_lines 'previous run still active')
cn_risk_count=$(count_lines 'CN risk detected')
target_count=$(count_lines 'target reached or warming')
drift_count=$(count_lines 'region drift')
http_000_count=$(count_lines 'http=000')

expected_runs="unknown"
if printf "%s" "$RUN_INTERVAL_MINUTES" | grep -Eq '^[0-9]+$' && [ "$RUN_INTERVAL_MINUTES" -gt 0 ]; then
  expected_runs=$((7 * 24 * 60 / RUN_INTERVAL_MINUTES))
fi

timer_status="not found"
timer_next="not found"
service_status="unknown"
if command -v systemctl >/dev/null 2>&1; then
  timer_status="$(systemctl is-active ip-sentinel.timer 2>/dev/null || true)"
  service_status="$(systemctl is-active ip-sentinel.service 2>/dev/null || true)"
  timer_next="$(systemctl list-timers --all ip-sentinel.timer --no-pager --no-legend 2>/dev/null | awk '{print $1, $2, $3, $4, $5}' | sed 's/[[:space:]]*$//' || true)"
  [ -z "$timer_next" ] && timer_next="not scheduled"
fi

cron_line="$(crontab -l 2>/dev/null | grep 'ip_sentinel_local_safe' || true)"
[ -z "$cron_line" ] && cron_line="not found in current user crontab"

listener_lines=""
if command -v ss >/dev/null 2>&1; then
  listener_lines="$(ss -lntp 2>/dev/null | grep 'ip_sentinel' || true)"
else
  listener_lines="ss command not found"
fi
[ -z "$listener_lines" ] && listener_lines="none"

log_dir="$(dirname "$LOG_FILE")"
log_usage="unknown"
rotated_logs="0"
if [ -d "$log_dir" ]; then
  log_usage="$(du -sh "$log_dir" 2>/dev/null | awk '{print $1}')"
  [ -z "$log_usage" ] && log_usage="unknown"
  rotated_logs="$(find "$log_dir" -maxdepth 1 -type f -name "$(basename "$LOG_FILE").*" 2>/dev/null | wc -l | tr -d ' ')"
fi

last_start="$(last_match '\[START[[:space:]]*\]')"
last_end="$(last_match '\[END[[:space:]]*\]')"
last_score="$(last_match '\[SCORE[[:space:]]*\]')"
last_warn="$(last_match '\[WARN[[:space:]]*\]')"
last_error="$(last_match '\[ERROR[[:space:]]*\]')"

module_summary="$(awk '
  /\[START[[:space:]]*\]/ {
    if ($0 ~ /\[Google[[:space:]]*\]/) google++
    else if ($0 ~ /\[Trust[[:space:]]*\]/) trust++
    else other++
  }
  END {
    printf "Google=%d Trust=%d Other=%d", google + 0, trust + 0, other + 0
  }
' "$tmp_recent")"

http_summary="$(awk '
  {
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^http=[0-9][0-9][0-9]/) {
        split($i, a, "=")
        codes[a[2]]++
      }
    }
  }
  END {
    first = 1
    for (code in codes) {
      if (!first) printf " "
      printf "%s=%d", code, codes[code]
      first = 0
    }
    if (first) printf "none"
  }
' "$tmp_recent")"

health="OK"
if [ "$error_count" -gt 0 ]; then
  health="ERROR"
elif [ "$cn_risk_count" -gt 0 ] || [ "$http_000_count" -gt 0 ] || [ "$warn_count" -gt 0 ]; then
  health="WARN"
elif [ "$total_lines" -eq 0 ] && [ "$service_status" = "activating" ]; then
  health="INIT_RUNNING"
elif [ "$total_lines" -eq 0 ]; then
  health="NO_RUNS"
fi

cat <<REPORT
IP-Sentinel Local Safe 近 7 天运行报告
生成时间: ${now_utc}
安装目录: ${INSTALL_DIR}
配置文件: ${CONFIG_FILE}
日志文件: ${LOG_FILE}
日志目录占用: ${log_usage}

结论: ${health}
目标区域: ${REGION_CODE}
版本: ${LOCAL_SAFE_VERSION}
Google/YouTube 模块: ${ENABLE_GOOGLE}
Trust 模块: ${ENABLE_TRUST}
计划间隔: ${RUN_INTERVAL_MINUTES} 分钟
日志最大单文件: ${LOG_MAX_SIZE_MB} MB
日志保留天数: ${LOG_RETENTION_DAYS}
日志归档保留数: ${LOG_ROTATE_KEEP}

调度状态:
systemd timer: ${timer_status}
systemd service: ${service_status}
next timer: ${timer_next}
cron: ${cron_line}

公网监听检查:
${listener_lines}

近 7 天统计:
日志行数: ${total_lines}
日志归档数: ${rotated_logs}
模块启动次数: ${start_count}
模块完成次数: ${end_count}
预计触发次数: ${expected_runs}
访问动作数: ${exec_count}
判区记录数: ${score_count}
模块分布: ${module_summary}
HTTP 分布: ${http_summary}
WARN 数: ${warn_count}
ERROR 数: ${error_count}
重叠跳过数: ${skip_count}
http=000 数: ${http_000_count}
CN 风险次数: ${cn_risk_count}
目标/养护中次数: ${target_count}
区域漂移次数: ${drift_count}

最近记录:
最近启动: ${last_start:-none}
最近完成: ${last_end:-none}
最近判区: ${last_score:-none}
最近 WARN: ${last_warn:-none}
最近 ERROR: ${last_error:-none}

最近 10 条判区:
REPORT

grep '\[SCORE[[:space:]]*\]' "$tmp_recent" 2>/dev/null | tail -n 10 || true

cat <<'REPORT'

建议:
- 公网监听检查应为 none。
- 如果 ERROR 或 http=000 较多，先检查 VPS DNS、IPv4/IPv6、出口路由和 curl 连通性。
- 如果仍频繁出现 CN risk detected，继续观察数天到数周；这不是即时修复工具。
REPORT
