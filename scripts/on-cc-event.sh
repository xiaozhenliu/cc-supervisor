#!/usr/bin/env bash
# on-cc-event.sh — Unified Hook callback for Claude Code events.
#
# Invoked by Claude Code hooks; receives event JSON on stdin.
# Appends structured record to logs/events.ndjson, then notifies OpenClaw
# for selected event types (Stop, Notification, SessionEnd, PostToolUse errors).
#
# Required env: CC_PROJECT_DIR (set by supervisor_run.sh; falls back to
# resolving from this script's own path when running as a hook callback).

set -euo pipefail

# Resolve project root — hook callbacks run from an unknown working directory.
CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export CC_PROJECT_DIR

source "$(dirname "$0")/lib/log.sh"

EVENTS_FILE="${CC_PROJECT_DIR}/logs/events.ndjson"
SCRIPTS_DIR="${CC_PROJECT_DIR}/scripts"
SESSION_NAME="cc-supervise"

# Supervision mode: relay (default) or autonomous.
CC_MODE="${CC_MODE:-relay}"
if [[ "$CC_MODE" != "relay" && "$CC_MODE" != "autonomous" ]]; then
  log_warn "Unknown CC_MODE='$CC_MODE', falling back to relay"
  CC_MODE="relay"
fi

# ── Read Hook JSON from stdin ─────────────────────────────────────────────────
HOOK_JSON="$(cat)"

if [[ -z "$HOOK_JSON" ]]; then
  log_error "No JSON received on stdin"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  log_error "jq is required but not found in PATH"
  exit 1
fi

# ── Extract key fields ────────────────────────────────────────────────────────
EVENT_TYPE="$(echo "$HOOK_JSON" | jq -r '.hook_event_name // empty')"
SESSION_ID="$(echo "$HOOK_JSON"  | jq -r '.session_id   // empty')"
EVENT_ID="$(echo "$HOOK_JSON"    | jq -r '.event_id     // empty')"

if [[ -z "$EVENT_TYPE" ]]; then
  log_error "Missing hook_event_name in Hook JSON"
  exit 1
fi

log_info "Received: type=$EVENT_TYPE session=${SESSION_ID:-?} event_id=${EVENT_ID:-?}"

# ── Deduplication: skip if same session_id + event_id already logged ──────────
if [[ -n "$SESSION_ID" && -n "$EVENT_ID" && -f "$EVENTS_FILE" ]]; then
  DUPLICATE="$(jq -r --arg sid "$SESSION_ID" --arg eid "$EVENT_ID" \
    'select(.session_id==$sid and .event_id==$eid) | .event_id' \
    "$EVENTS_FILE" 2>/dev/null | head -1 || true)"
  if [[ -n "$DUPLICATE" ]]; then
    log_warn "Duplicate skipped: session=$SESSION_ID event_id=$EVENT_ID"
    exit 0
  fi
fi

# ── Build summary and decide whether to notify OpenClaw ──────────────────────
SUMMARY=""
TOOL_NAME=""  # populated for PostToolUse events only
SHOULD_NOTIFY=false

case "$EVENT_TYPE" in
  Stop)
    SHOULD_NOTIFY=true
    # Prefer live pane capture as summary (most readable)
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
      SUMMARY="$("${SCRIPTS_DIR}/cc_capture.sh" --tail 30 2>/dev/null | tail -c 1000 || true)"
    fi
    # Fall back to last assistant message in transcript
    if [[ -z "$SUMMARY" ]]; then
      TRANSCRIPT="$(echo "$HOOK_JSON" | jq -r '.transcript_path // empty')"
      if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
        SUMMARY="$(jq -r \
          '[.[] | select(.role=="assistant") | .content |
            if type=="array" then (.[].text? // "") else . end
          ] | last // ""' \
          "$TRANSCRIPT" 2>/dev/null | head -c 500 || true)"
      fi
    fi
    [[ -z "$SUMMARY" ]] && SUMMARY="[no content]"
    ;;

  PostToolUse)
    IS_ERROR="$(echo "$HOOK_JSON" | jq -r '.toolResult.isError // false')"
    TOOL_NAME="$(echo "$HOOK_JSON" | jq -r '.tool_name // "unknown"')"
    if [[ "$IS_ERROR" == "true" ]]; then
      SHOULD_NOTIFY=true
      ERROR_TEXT="$(echo "$HOOK_JSON" | jq -r \
        '.toolResult.content | if type=="array" then .[0].text? // "" else . end' \
        2>/dev/null | head -c 300 || true)"
      SUMMARY="Tool error — ${TOOL_NAME}: ${ERROR_TEXT}"
    else
      SUMMARY="Tool: ${TOOL_NAME}"
    fi
    ;;

  Notification)
    SHOULD_NOTIFY=true
    SUMMARY="$(echo "$HOOK_JSON" | jq -r '.message // "(no message)"')"
    ;;

  SessionEnd)
    SHOULD_NOTIFY=true
    SUMMARY="Session ended (session_id=${SESSION_ID:-unknown})"
    ;;

  *)
    log_warn "Unknown event type: $EVENT_TYPE — logging only"
    SUMMARY="Unknown event: $EVENT_TYPE"
    ;;
esac

# ── Append structured record to events.ndjson ────────────────────────────────
mkdir -p "$(dirname "$EVENTS_FILE")"
TS="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

jq -cn \
  --arg ts         "$TS" \
  --arg event_type "$EVENT_TYPE" \
  --arg session_id "$SESSION_ID" \
  --arg event_id   "$EVENT_ID" \
  --arg summary    "$SUMMARY" \
  --arg tool_name  "$TOOL_NAME" \
  '{ts:$ts, event_type:$event_type, session_id:$session_id, event_id:$event_id,
    summary:$summary, tool_name:(if $tool_name == "" then null else $tool_name end)}' \
  >> "$EVENTS_FILE"

log_info "Logged to events.ndjson: $EVENT_TYPE"

# ── Notify OpenClaw ───────────────────────────────────────────────────────────
_enqueue_notification() {
  local msg="$1"
  local queue_file="${CC_PROJECT_DIR}/logs/notification.queue"
  mkdir -p "$(dirname "$queue_file")"
  printf '%s|%s|%s|%s|%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "${OPENCLAW_CHANNEL:-unknown}" \
    "${OPENCLAW_TARGET:-unknown}" \
    "$EVENT_TYPE" \
    "$msg" >> "$queue_file"
  log_info "Notification queued: $EVENT_TYPE"
}

if [[ "$SHOULD_NOTIFY" == "true" ]]; then
  if [[ "$CC_MODE" == "autonomous" && "$EVENT_TYPE" == "Stop" ]]; then
    NOTIFY_MSG="[cc-supervisor][autonomous] Stop: ${SUMMARY} | ACTION_REQUIRED: decide_and_continue"
  else
    NOTIFY_MSG="[cc-supervisor][${CC_MODE}] ${EVENT_TYPE}: ${SUMMARY}"
  fi

  if [[ -z "${OPENCLAW_CHANNEL:-}" || -z "${OPENCLAW_TARGET:-}" ]]; then
    log_warn "OPENCLAW_CHANNEL or OPENCLAW_TARGET not set — notification skipped (event=$EVENT_TYPE)"
  elif ! command -v openclaw &>/dev/null; then
    log_warn "openclaw not in PATH — queuing notification (event=$EVENT_TYPE)"
    _enqueue_notification "$NOTIFY_MSG"
  elif openclaw message send \
      --channel "$OPENCLAW_CHANNEL" \
      -t "$OPENCLAW_TARGET" \
      -m "$NOTIFY_MSG" 2>/dev/null; then
    log_info "openclaw message send ok: mode=$CC_MODE event=$EVENT_TYPE"
  else
    log_warn "openclaw message send failed — queuing (event=$EVENT_TYPE)"
    _enqueue_notification "$NOTIFY_MSG"
  fi
fi
