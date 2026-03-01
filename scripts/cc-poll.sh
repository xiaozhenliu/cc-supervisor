#!/usr/bin/env bash
# cc-poll.sh — Proactive terminal polling daemon with smart state detection.
# Periodically captures terminal output and analyzes Claude Code state;
# only notifies Agent when intervention is clearly needed.
#
# Smart detection rules:
# - Contains ellipsis (…) → Working, DON'T notify
# - Error signals → Notify: "Tool error detected"
# - Choice prompts → Notify: "Choice pending"
# - Question prompts → Notify: "Question pending"
# - Unknown state → Notify: "Unknown status detected"
#
# Reads CC_PROJECT_DIR, CC_POLL_INTERVAL, CC_POLL_LINES from environment.
# Writes PID to logs/poll.pid; removes it on clean exit.

set -euo pipefail

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
CC_POLL_INTERVAL="${CC_POLL_INTERVAL:-15}"   # minutes (3–1440, 0=disabled)
CC_POLL_LINES="${CC_POLL_LINES:-10}"         # reduced from 40 to focus on recent output
SESSION_NAME="cc-supervise"
EVENTS_FILE="${CC_PROJECT_DIR}/logs/events.ndjson"
PID_FILE="${CC_PROJECT_DIR}/logs/poll.pid"

source "$(dirname "$0")/lib/log.sh"
source "$(dirname "$0")/lib/notify.sh"

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

SLEEP_SECS=$((CC_POLL_INTERVAL * 60))

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
  rm -f "$PID_FILE"
  log_info "poll daemon stopped"
}
trap cleanup EXIT INT TERM

# ── Write PID ─────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$PID_FILE")"
echo "$$" > "$PID_FILE"
log_info "poll daemon started (PID=$$, interval=${CC_POLL_INTERVAL}m, lines=${CC_POLL_LINES}, smart-detection=enabled)"

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
  if stat --version &>/dev/null 2>&1; then
    mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
  else
    mtime=$(stat -f %m "$file" 2>/dev/null || echo 0)
  fi
  echo $((now - mtime))
}

# ── Helper: extract Claude output region (above separators) ───────────────────
# Returns lines above the first separator (─────), which is the Claude output area
_extract_claude_output() {
  local capture="$1"
  # Find the first separator line and get everything above it
  echo "$capture" | sed -n '/^[-─]\+/,$d; p'
}

# ── Helper: smart state detection ────────────────────────────────────────────
# Analyzes terminal output and returns:
# - "working" (contains ellipsis) → DON'T notify
# - "error" → notify: error detected
# - "choice" → notify: choice pending
# - "question" → notify: question pending
# - "unknown" → notify: unknown status
# - "silent" → don't notify
_detect_state() {
  local output="$1"

  # Extract Claude output region (above separators)
  local claude_output
  claude_output=$(_extract_claude_output "$output")

  # Get last 5 lines for state detection (most recent)
  local recent
  recent=$(echo "$claude_output" | tail -5)

  # 1. Working state: ellipsis (…) = Claude is processing, don't disturb
  if echo "$recent" | grep -q "…"; then
    echo "working"
    return
  fi

  # 2. Error detection: red error messages
  if echo "$recent" | grep -qiE "(error|denied|failed|unauthorized|permission denied|api error|connection refused)"; then
    echo "error"
    return
  fi

  # 3. Choice detection: arrow + option number (→ 1) 2) 3))
  if echo "$recent" | grep -qE "(→|➜|▸)\s*[0-9]" || echo "$recent" | grep -qE "[0-9]\)\s"; then
    echo "choice"
    return
  fi

  # 4. Question detection: ends with ? and contains question words
  if echo "$recent" | grep -qE "\?" && echo "$recent" | grep -qiE "(what|how|should|would|could|which|where|when|why|do you|should i|can i)"; then
    echo "question"
    return
  fi

  # 5. Unknown state: can't determine, notify Agent to verify manually
  echo "unknown"
}

# ── Helper: send notification ────────────────────────────────────────────────
send_poll_alert() {
  local msg="$1"
  local event_type="$2"
  log_info "sending poll alert: $event_type"
  notify "${OPENCLAW_SESSION_ID:-}" "$msg" "$event_type"
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
  local captured
  captured=$("${CC_PROJECT_DIR}/scripts/cc_capture.sh" --tail "$CC_POLL_LINES" 2>/dev/null || true)
  if [[ -z "$captured" ]]; then
    log_info "empty capture — skipping poll"
    continue
  fi

  # Smart state detection
  local state
  state=$(_detect_state "$captured")

  log_info "poll state: $state"

  case "$state" in
    working)
      # Claude is working (ellipsis detected) — stay silent
      ;;
    error)
      send_poll_alert "[cc-supervisor][poll-alert] Tool error detected in terminal — verify and intervene if needed" "poll-error"
      ;;
    choice)
      send_poll_alert "[cc-supervisor][poll-alert] Choice prompt detected — verify and respond" "poll-choice"
      ;;
    question)
      send_poll_alert "[cc-supervisor][poll-alert] Question pending — verify and respond" "poll-question"
      ;;
    unknown)
      # Can't determine state — notify Agent to verify manually
      send_poll_alert "[cc-supervisor][poll-alert] Unknown status detected — verify manually" "poll-unknown"
      ;;
  esac
done
