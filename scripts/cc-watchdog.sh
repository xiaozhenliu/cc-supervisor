#!/usr/bin/env bash
# cc-watchdog.sh — Monitor events.ndjson freshness and flush pending notifications.
# Two responsibilities:
#   1. Alert on inactivity (no Hook events for CC_TIMEOUT seconds)
#   2. Retry failed notifications from queue every cycle (prevents dead-lock
#      when on-cc-event.sh logs an event but notify() fails)
#
# Usage: CC_TIMEOUT=1800 ./scripts/cc-watchdog.sh
#
# Reads CC_PROJECT_DIR and CC_TIMEOUT from environment.
# Writes PID to logs/watchdog.pid; removes it on clean exit.

set -euo pipefail

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export CC_PROJECT_DIR
source "$(dirname "$0")/lib/runtime_context.sh"
runtime_context_init "${CC_SUPERVISION_ID:-default}"

CC_TIMEOUT="${CC_TIMEOUT:-1800}"   # seconds before alerting (default: 30 min)
FLUSH_INTERVAL=300                 # retry queue flush every 5 minutes
SESSION_NAME="$CC_TMUX_SESSION"
POLL_INTERVAL=30                   # check every 30 seconds
EVENTS_FILE="$CC_EVENTS_FILE"
QUEUE_FILE="$CC_NOTIFICATION_QUEUE_FILE"
PID_FILE="$CC_WATCHDOG_PID_FILE"
FLUSH_SCRIPT="${CC_PROJECT_DIR}/scripts/flush-queue.sh"

source "$(dirname "$0")/lib/log.sh"
source "$(dirname "$0")/lib/notify.sh"

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
  rm -f "$PID_FILE"
  log_info "watchdog stopped"
}
trap cleanup EXIT INT TERM

# ── Write PID ─────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$PID_FILE")"
echo "$$" > "$PID_FILE"
log_info "watchdog started (PID=$$, timeout=${CC_TIMEOUT}s, poll=${POLL_INTERVAL}s, flush_interval=${FLUSH_INTERVAL}s)"

# ── Helper: send alert ────────────────────────────────────────────────────────
send_alert() {
  local msg="$1"
  log_warn "$msg"
  notify "${OPENCLAW_SESSION_ID:-}" "$msg" "watchdog"
}

# ── Helper: seconds since file was last modified ──────────────────────────────
seconds_since_modified() {
  local file="$1"
  local now
  now=$(date +%s)
  if [[ ! -f "$file" ]]; then
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
last_flush=0    # epoch of last flush attempt

while true; do
  sleep "$POLL_INTERVAL"

  # Exit if the supervised tmux session is gone
  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log_info "tmux session '$SESSION_NAME' gone — watchdog exiting"
    exit 0
  fi

  # ── Flush pending notifications (rate-limited to every FLUSH_INTERVAL seconds) ─
  now=$(date +%s)
  if [[ -f "$QUEUE_FILE" && -s "$QUEUE_FILE" ]] && (( now - last_flush >= FLUSH_INTERVAL )); then
    log_info "notification queue has pending items — flushing"
    "$FLUSH_SCRIPT" --id "$CC_SUPERVISION_ID" 2>/dev/null || log_warn "flush-queue failed"
    last_flush=$now
  fi

  # ── Inactivity check ─────────────────────────────────────────────────────
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
