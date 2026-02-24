#!/usr/bin/env bash
# cc-poll.sh — Proactive terminal polling daemon.
# Periodically captures terminal output and sends it to the agent,
# filling the gap between Hook events during long-running operations.
#
# Reads CC_PROJECT_DIR, CC_POLL_INTERVAL, CC_POLL_LINES from environment.
# Writes PID to logs/poll.pid; removes it on clean exit.

set -euo pipefail

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
CC_POLL_INTERVAL="${CC_POLL_INTERVAL:-15}"   # minutes (3–1440, 0=disabled)
CC_POLL_LINES="${CC_POLL_LINES:-40}"
SESSION_NAME="cc-supervise"
EVENTS_FILE="${CC_PROJECT_DIR}/logs/events.ndjson"
PID_FILE="${CC_PROJECT_DIR}/logs/poll.pid"

source "$(dirname "$0")/lib/log.sh"

# ── Disabled check ───────────────────────────────────────────────────────────
if (( CC_POLL_INTERVAL == 0 )); then
  log_info "polling disabled (CC_POLL_INTERVAL=0), exiting"
  exit 0
fi

# ── Validate range ───────────────────────────────────────────────────────────
if (( CC_POLL_INTERVAL < 3 || CC_POLL_INTERVAL > 1440 )); then
  log_error "CC_POLL_INTERVAL must be 0 (disabled) or 3–1440 minutes, got $CC_POLL_INTERVAL"
  exit 1
fi

SLEEP_SECS=$((CC_POLL_INTERVAL * 60))   # convert to seconds for sleep

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
  rm -f "$PID_FILE"
  log_info "poll daemon stopped"
}
trap cleanup EXIT INT TERM

# ── Write PID ─────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$PID_FILE")"
echo "$$" > "$PID_FILE"
log_info "poll daemon started (PID=$$, interval=${CC_POLL_INTERVAL}m, lines=${CC_POLL_LINES})"

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

# ── Helper: queue poll for later retry ────────────────────────────────────────
_enqueue_poll() {
  local msg="$1"
  local queue_file="${CC_PROJECT_DIR}/logs/notification.queue"
  mkdir -p "$(dirname "$queue_file")"
  printf '%s|%s|%s|%s|%s|%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "${OPENCLAW_CHANNEL:-unknown}" \
    "${OPENCLAW_ACCOUNT:-}" \
    "${OPENCLAW_TARGET:-unknown}" \
    "poll" \
    "$msg" >> "$queue_file"
  log_info "Poll queued for retry"
}

# ── Helper: send poll snapshot ────────────────────────────────────────────────
send_poll() {
  local msg="$1"
  log_info "sending poll snapshot"
  if [[ -z "${OPENCLAW_SESSION_ID:-}" ]]; then
    log_warn "OPENCLAW_SESSION_ID not set — poll skipped"
    log_warn "OPENCLAW_SESSION_ID not set — poll skipped"
  elif ! command -v openclaw &>/dev/null; then
    log_warn "openclaw not in PATH — queuing poll"
    _enqueue_poll "$msg"
  elif openclaw agent \
      --session-id "$OPENCLAW_SESSION_ID" \
      --message "$msg" \
      ${OPENCLAW_TARGET:+--deliver} \
      ${OPENCLAW_TARGET:+--reply-to "$OPENCLAW_TARGET"} \
      2>/dev/null; then
    log_info "openclaw agent triggered (poll) session=$OPENCLAW_SESSION_ID"
  else
    log_warn "openclaw agent failed — queuing poll"
    _enqueue_poll "$msg"
  fi
}

# ── Main loop ─────────────────────────────────────────────────────────────────
while true; do
  sleep "$SLEEP_SECS"

  # Exit if the supervised tmux session is gone
  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log_info "tmux session '$SESSION_NAME' gone — poll daemon exiting"
    exit 0
  fi

  # Dedup: skip if Hook events arrived within the last poll interval
  idle_secs=$(seconds_since_modified "$EVENTS_FILE")
  if (( idle_secs < SLEEP_SECS )); then
    log_info "events.ndjson updated ${idle_secs}s ago (< ${SLEEP_SECS}s) — skipping poll"
    continue
  fi

  # Capture terminal output
  CAPTURED="$("${CC_PROJECT_DIR}/scripts/cc_capture.sh" --tail "$CC_POLL_LINES" 2>/dev/null | tail -c 1000 || true)"
  if [[ -z "$CAPTURED" ]]; then
    log_info "empty capture — skipping poll"
    continue
  fi

  send_poll "[cc-supervisor][poll] Terminal snapshot:
${CAPTURED}"
done
