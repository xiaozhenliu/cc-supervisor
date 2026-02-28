#!/usr/bin/env bash
# cc-watchdog.sh — Monitor events.ndjson freshness and alert on inactivity.
# Usage: CC_TIMEOUT=1800 ./scripts/cc-watchdog.sh
#
# Reads CC_PROJECT_DIR and CC_TIMEOUT from environment.
# Writes PID to logs/watchdog.pid; removes it on clean exit.

set -euo pipefail

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
CC_TIMEOUT="${CC_TIMEOUT:-1800}"   # seconds before alerting (default: 30 min)
SESSION_NAME="cc-supervise"
POLL_INTERVAL=30                   # check every 30 seconds
EVENTS_FILE="${CC_PROJECT_DIR}/logs/events.ndjson"
PID_FILE="${CC_PROJECT_DIR}/logs/watchdog.pid"

source "$(dirname "$0")/lib/log.sh"

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
  rm -f "$PID_FILE"
  log_info "watchdog stopped"
}
trap cleanup EXIT INT TERM

# ── Write PID ─────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$PID_FILE")"
echo "$$" > "$PID_FILE"
log_info "watchdog started (PID=$$, timeout=${CC_TIMEOUT}s, poll=${POLL_INTERVAL}s)"

# ── Helper: queue alert for later retry ───────────────────────────────────────
_enqueue_alert() {
  local msg="$1"
  local queue_file="${CC_PROJECT_DIR}/logs/notification.queue"
  mkdir -p "$(dirname "$queue_file")"
  printf '%s|%s|%s|%s|%s|%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "${OPENCLAW_CHANNEL:-unknown}" \
    "${OPENCLAW_ACCOUNT:-}" \
    "${OPENCLAW_TARGET:-unknown}" \
    "watchdog" \
    "$msg" >> "$queue_file"
  log_info "Alert queued for retry"
}

# ── Helper: send alert ────────────────────────────────────────────────────────
send_alert() {
  local msg="$1"
  log_warn "$msg"
  if [[ -z "${OPENCLAW_SESSION_ID:-}" ]]; then
    log_warn "OPENCLAW_SESSION_ID not set — queuing alert for later replay"
    _enqueue_alert "$msg"
  elif ! command -v openclaw &>/dev/null; then
    log_warn "openclaw not in PATH — queuing alert"
    _enqueue_alert "$msg"
  elif openclaw agent \
      --session-id "$OPENCLAW_SESSION_ID" \
      --message "$msg" \
      ${OPENCLAW_TARGET:+--deliver} \
      ${OPENCLAW_TARGET:+--reply-to "$OPENCLAW_TARGET"} \
      2>/dev/null; then
    log_info "openclaw agent triggered (watchdog alert) session=$OPENCLAW_SESSION_ID"
  else
    log_warn "openclaw agent failed — queuing alert"
    _enqueue_alert "$msg"
  fi
}

# ── Helper: seconds since file was last modified ──────────────────────────────
seconds_since_modified() {
  local file="$1"
  local now
  now=$(date +%s)
  if [[ ! -f "$file" ]]; then
    # File doesn't exist yet — treat as stale from now
    echo "$now"
    return
  fi
  local mtime
  # macOS stat uses -f %m; GNU stat uses -c %Y — support both
  if stat --version &>/dev/null 2>&1; then
    mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
  else
    mtime=$(stat -f %m "$file" 2>/dev/null || echo 0)
  fi
  echo $((now - mtime))
}

# ── Main loop ─────────────────────────────────────────────────────────────────
alerted=false   # avoid repeated alerts within the same idle window

while true; do
  sleep "$POLL_INTERVAL"

  # Exit if the supervised tmux session is gone
  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log_info "tmux session '$SESSION_NAME' gone — watchdog exiting"
    exit 0
  fi

  idle_secs=$(seconds_since_modified "$EVENTS_FILE")

  if (( idle_secs >= CC_TIMEOUT )); then
    if [[ "$alerted" == "false" ]]; then
      send_alert "⏰ watchdog: no activity for ${idle_secs}s (threshold=${CC_TIMEOUT}s) — check Claude Code session '${SESSION_NAME}'"
      alerted=true
    fi
  else
    # Activity detected — reset alert flag so next silence triggers a fresh alert
    alerted=false
  fi
done
