#!/usr/bin/env bash
# log.sh — Shared logging utilities for cc-supervisor scripts.
# Source this file: source "$(dirname "$0")/lib/log.sh"
#
# Provides: log_info, log_warn, log_error
# Writes to both stderr (human-readable) and $LOG_FILE (structured).

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG_FILE="${CC_PROJECT_DIR}/logs/supervisor.log"

mkdir -p "$(dirname "$LOG_FILE")"

_log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  local caller="${BASH_SOURCE[2]##*/}"

  # Human-readable to stderr
  echo "[$ts] [$level] [$caller] $msg" >&2

  # Structured append to log file — use jq so all values are properly escaped
  if command -v jq &>/dev/null; then
    jq -cn --arg ts "$ts" --arg level "$level" --arg script "$caller" --arg msg "$msg" \
      '{ts:$ts,level:$level,script:$script,msg:$msg}' >> "$LOG_FILE"
  else
    # Fallback: escape backslashes and double quotes manually
    local safe_msg="${msg//\\/\\\\}"; safe_msg="${safe_msg//\"/\\\"}"
    echo "{\"ts\":\"$ts\",\"level\":\"$level\",\"script\":\"$caller\",\"msg\":\"$safe_msg\"}" >> "$LOG_FILE"
  fi
}

log_info()  { _log "INFO"  "$@"; }
log_warn()  { _log "WARN"  "$@"; }
log_error() { _log "ERROR" "$@"; }
