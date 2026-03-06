#!/usr/bin/env bash
# log.sh — Shared logging utilities for cc-supervisor scripts.
# Source this file: source "$(dirname "$0")/lib/log.sh"
#
# Provides: log_info, log_warn, log_error
# Writes to both stderr (human-readable) and $LOG_FILE (structured).

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
RUNTIME_CONTEXT_LIB="${CC_PROJECT_DIR}/scripts/lib/runtime_context.sh"

if [[ -f "$RUNTIME_CONTEXT_LIB" ]]; then
  # shellcheck disable=SC1090
  source "$RUNTIME_CONTEXT_LIB"
fi

_log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  local caller="${BASH_SOURCE[2]##*/}"
  local log_file

  if declare -F runtime_context_init >/dev/null 2>&1; then
    runtime_context_init "${CC_SUPERVISION_ID:-default}" >/dev/null 2>&1 || true
  fi

  log_file="${CC_LOG_FILE:-${CC_PROJECT_DIR}/logs/supervisor.log}"
  mkdir -p "$(dirname "$log_file")"

  # Human-readable to stderr
  echo "[$ts] [$level] [${CC_SUPERVISION_ID:-default}] [$caller] $msg" >&2

  # Structured append to log file — use jq so all values are properly escaped
  if command -v jq &>/dev/null; then
    jq -cn \
      --arg ts "$ts" \
      --arg level "$level" \
      --arg script "$caller" \
      --arg msg "$msg" \
      --arg supervision_id "${CC_SUPERVISION_ID:-default}" \
      --arg runtime_dir "${CC_RUNTIME_DIR:-${CC_PROJECT_DIR}/logs}" \
      '{ts:$ts,level:$level,script:$script,supervision_id:$supervision_id,runtime_dir:$runtime_dir,msg:$msg}' \
      >> "$log_file"
  else
    # Fallback: escape backslashes and double quotes manually
    local safe_msg="${msg//\\/\\\\}"; safe_msg="${safe_msg//\"/\\\"}"
    echo "{\"ts\":\"$ts\",\"level\":\"$level\",\"script\":\"$caller\",\"supervision_id\":\"${CC_SUPERVISION_ID:-default}\",\"runtime_dir\":\"${CC_RUNTIME_DIR:-${CC_PROJECT_DIR}/logs}\",\"msg\":\"$safe_msg\"}" >> "$log_file"
  fi
}

log_info()  { _log "INFO"  "$@"; }
log_warn()  { _log "WARN"  "$@"; }
log_error() { _log "ERROR" "$@"; }
