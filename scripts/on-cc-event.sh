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
source "$(dirname "$0")/lib/notify.sh"
source "$(dirname "$0")/lib/message_templates.sh"

# Restore hook environment from transient bootstrap fallback only when required
# values are missing from current process env.
# (hook execution environment may not reliably inherit shell variables)
HOOK_ENV_FILE="${CC_PROJECT_DIR}/logs/hook.env"
FALLBACK_NEEDED=false
FALLBACK_USED=false
FALLBACK_DELETED=false

if [[ -z "${OPENCLAW_SESSION_ID:-}" || -z "${OPENCLAW_AGENT_ID:-}" ]]; then
  FALLBACK_NEEDED=true
fi

if [[ "$FALLBACK_NEEDED" == "true" ]]; then
  if [[ -f "$HOOK_ENV_FILE" ]]; then
    log_info "Hook fallback required; loading environment from $HOOK_ENV_FILE"
    # shellcheck disable=SC1090
    source "$HOOK_ENV_FILE"

    missing_keys=()
    [[ -z "${OPENCLAW_SESSION_ID:-}" ]] && missing_keys+=("OPENCLAW_SESSION_ID")
    [[ -z "${OPENCLAW_AGENT_ID:-}" ]] && missing_keys+=("OPENCLAW_AGENT_ID")

    if [[ ${#missing_keys[@]} -eq 0 ]]; then
      FALLBACK_USED=true
      log_info "Hook fallback load succeeded (required keys present)"
      if rm -f "$HOOK_ENV_FILE"; then
        FALLBACK_DELETED=true
        log_info "Hook fallback file deleted after successful load: $HOOK_ENV_FILE"
      else
        log_warn "Hook fallback file could not be deleted: $HOOK_ENV_FILE"
      fi
    else
      log_warn "Hook fallback load failed validation; missing required keys: ${missing_keys[*]}"
      log_warn "Hook fallback file retained for troubleshooting: $HOOK_ENV_FILE"
    fi
  else
    log_warn "Hook fallback required but file not found: $HOOK_ENV_FILE"
  fi
else
  log_info "Hook fallback not needed; using inherited process environment"
fi

if [[ "$FALLBACK_USED" != "true" ]]; then
  log_info "Hook fallback not used for this callback"
fi
if [[ "$FALLBACK_DELETED" != "true" ]]; then
  log_info "Hook fallback file not deleted in this callback"
fi

EVENTS_FILE="${CC_PROJECT_DIR}/logs/events.ndjson"
SCRIPTS_DIR="${CC_PROJECT_DIR}/scripts"
SESSION_NAME="cc-supervise"

# Supervision mode: relay (default) or auto.
CC_MODE="${CC_MODE:-relay}"
# Backward compatibility: map old 'autonomous' to new 'auto'
if [[ "$CC_MODE" == "autonomous" ]]; then
  CC_MODE="auto"
fi
if [[ "$CC_MODE" != "relay" && "$CC_MODE" != "auto" ]]; then
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

# Claude hook payloads do not consistently include event_id for every event
# type/version. Generate a fallback so logs preserve a stable non-empty key.
if [[ -z "$EVENT_ID" ]]; then
  TS_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
  EVENT_ID="generated-${EVENT_TYPE}-${SESSION_ID:-unknown}-${TS_ID}-$$"
  log_warn "Hook JSON missing event_id; generated fallback event_id=${EVENT_ID}"
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
    # Prefer live pane capture as summary — keep short; Agent can cc-capture more if needed
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
      SUMMARY="$("${SCRIPTS_DIR}/cc_capture.sh" --tail 10 2>/dev/null | tail -c 500 || true)"
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
      # Extract HTTP status code if present (403, 400, 500, 429, 401, 404, etc.)
      HTTP_STATUS="$(echo "$ERROR_TEXT" | grep -oE '\b(4[0-9]{2}|5[0-9]{2})\b' | head -1 || true)"
      if [[ -n "$HTTP_STATUS" ]]; then
        SUMMARY="API error ${HTTP_STATUS} — ${TOOL_NAME}: ${ERROR_TEXT}"
      else
        SUMMARY="Tool error — ${TOOL_NAME}: ${ERROR_TEXT}"
      fi
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

if ! jq -cn \
  --arg ts         "$TS" \
  --arg event_type "$EVENT_TYPE" \
  --arg session_id "$SESSION_ID" \
  --arg event_id   "$EVENT_ID" \
  --arg summary    "$SUMMARY" \
  --arg tool_name  "$TOOL_NAME" \
  '{ts:$ts, event_type:$event_type, session_id:$session_id, event_id:$event_id,
    summary:$summary, tool_name:(if $tool_name == "" then null else $tool_name end)}' \
  >> "$EVENTS_FILE" 2>/dev/null; then
  log_error "Failed to write event to events.ndjson (disk full or permission error?)"
  _notify_enqueue "[cc-supervisor] CRITICAL: event logging failed for $EVENT_TYPE (session=${SESSION_ID:-unknown})" "error"
  exit 1
fi

log_info "Logged to events.ndjson: $EVENT_TYPE"

# ── Notify OpenClaw ───────────────────────────────────────────────────────────
if [[ "$SHOULD_NOTIFY" == "true" ]]; then
  NOTIFY_MSG="$(build_supervisor_notification "$CC_MODE" "$EVENT_TYPE" "$SUMMARY")"

  # Use OPENCLAW_SESSION_ID env var (caller's session, e.g., ruyi agent),
  # NOT SESSION_ID from hook JSON (which is Claude Code's internal session)
  notify "${OPENCLAW_SESSION_ID:-}" "$NOTIFY_MSG" "$EVENT_TYPE"
fi
