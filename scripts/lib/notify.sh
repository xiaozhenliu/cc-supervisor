#!/usr/bin/env bash
# notify.sh — Channel dispatch layer for cc-supervisor notifications.
# Source this file: source "$(dirname "$0")/lib/notify.sh"
#
# Public interface:
#   notify <session_id> <message> [event_type]
#   notify_from_queue <session_id> <channel> <target> <event_type> <msg>
#
# Routing strategy:
#   1. Query session metadata for actual source channel/target (most reliable)
#   2. Fallback to environment variables if session not found
#   3. Always use --deliver and --reply-channel for explicit routing
#
# On failure: enqueues to logs/notification.queue for later retry

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

resolve_openclaw_cmd() {
  local cmd="${OPENCLAW_BIN:-openclaw}"

  if [[ "$cmd" == */* ]]; then
    [[ -x "$cmd" ]] || return 1
    printf '%s\n' "$cmd"
    return 0
  fi

  command -v "$cmd" 2>/dev/null
}

# ── Helper: Query session routing info from OpenClaw session store ────────────
get_session_routing_info() {
  local session_id="$1"
  local agent_id="${OPENCLAW_AGENT_ID:-main}"
  local session_file="$HOME/.openclaw/agents/$agent_id/sessions/sessions.json"

  # Check if session file exists
  if [ ! -f "$session_file" ]; then
    return 1
  fi

  # Check if jq is available
  if ! command -v jq &>/dev/null; then
    return 1
  fi

  # Query session data
  local session_data=$(jq -r \
    --arg sid "$session_id" \
    'to_entries[] | select(.value.sessionId == $sid) | .value' \
    "$session_file" 2>/dev/null)

  if [ -z "$session_data" ]; then
    return 1
  fi

  # Extract routing target (priority: deliveryContext.to > lastTo > origin.to)
  local delivery_to=$(echo "$session_data" | jq -r '.deliveryContext.to // .lastTo // .origin.to // empty')

  if [ -n "$delivery_to" ]; then
    echo "$delivery_to"
    return 0
  else
    return 1
  fi
}

# ── Helper: Infer channel from target format ──────────────────────────────────
infer_channel_from_target() {
  local target="$1"

  # Discord: channel:123456789 or user:123456789
  if [[ "$target" =~ ^(channel|user): ]]; then
    echo "discord"
  # Telegram: chat:123456789
  elif [[ "$target" =~ ^chat: ]]; then
    echo "telegram"
  # WhatsApp: +1234567890 (E.164)
  elif [[ "$target" =~ ^\+[0-9]+ ]]; then
    echo "whatsapp"
  # Default
  else
    echo "discord"
  fi
}

# ── Internal: write to notification queue ────────────────────────────────────
_notify_enqueue() {
  local msg="$1"
  local event_type="${2:-unknown}"
  local channel="${3:-${OPENCLAW_CHANNEL:-unknown}}"
  local target="${4:-${OPENCLAW_TARGET:-unknown}}"
  local queue_file="${CC_PROJECT_DIR}/logs/notification.queue"
  mkdir -p "$(dirname "$queue_file")"
  printf '%s|%s|%s|%s|%s|%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "$channel" \
    "${OPENCLAW_ACCOUNT:-}" \
    "$target" \
    "$event_type" \
    "$msg" >> "$queue_file"
  log_info "Notification queued: $event_type (channel=$channel target=$target)"
}

# ── Internal: Discord implementation ─────────────────────────────────────────
_notify_discord() {
  local session_id="$1"
  local msg="$2"
  local event_type="${3:-unknown}"

  if [[ -z "$session_id" ]]; then
    log_warn "OPENCLAW_SESSION_ID not set — queuing for later replay (event=$event_type)"
    _notify_enqueue "$msg" "$event_type"
    return 0
  fi

  local openclaw_cmd=""
  if ! openclaw_cmd="$(resolve_openclaw_cmd)"; then
    log_warn "openclaw not in PATH — queuing notification (event=$event_type)"
    _notify_enqueue "$msg" "$event_type"
    return 0
  fi

  # Get routing info: prioritize session metadata, fallback to environment variables
  local target="${OPENCLAW_TARGET:-}"
  local channel="${OPENCLAW_CHANNEL:-discord}"
  local routing_source="env"

  if [ -z "$target" ]; then
    # Environment variable not set, query session metadata
    if target=$(get_session_routing_info "$session_id"); then
      channel=$(infer_channel_from_target "$target")
      routing_source="session"
      log_info "Routing from session metadata: channel=$channel target=$target"
    else
      log_warn "Failed to get routing info from session, will use channel default"
    fi
  else
    log_info "Routing from environment: channel=$channel target=$target"
  fi

  # Send notification with explicit routing
  # Always use --deliver and --reply-channel for reliable routing
  if "$openclaw_cmd" agent \
      --session-id "$session_id" \
      --message "$msg" \
      --deliver \
      --reply-channel "$channel" \
      ${target:+--reply-to "$target"} \
      2>/dev/null; then
    log_info "openclaw agent triggered: channel=$channel target=${target:-<default>} source=$routing_source event=$event_type session=$session_id"
  else
    log_warn "openclaw agent failed — queuing (event=$event_type)"
    _notify_enqueue "$msg" "$event_type" "$channel" "$target"
  fi
}

# ── Internal: Feishu placeholder ─────────────────────────────────────────────
_notify_feishu() {
  local session_id="$1"
  local msg="$2"
  local event_type="${3:-unknown}"
  # TODO: implement Feishu webhook delivery
  # Read $FEISHU_WEBHOOK_URL and POST via curl
  # For now, enqueue so no notifications are lost
  log_warn "Feishu channel not yet implemented — queuing (event=$event_type)"
  _notify_enqueue "$msg" "$event_type" "feishu" "${OPENCLAW_TARGET:-unknown}"
}

# ── Public: route notification to configured channel ─────────────────────────
notify() {
  local session_id="$1"
  local msg="$2"
  local event_type="${3:-unknown}"

  case "${OPENCLAW_CHANNEL:-discord}" in
    discord|telegram|whatsapp)
      _notify_discord "$session_id" "$msg" "$event_type"
      ;;
    feishu)
      _notify_feishu "$session_id" "$msg" "$event_type"
      ;;
    *)
      log_warn "Unsupported channel '${OPENCLAW_CHANNEL}' — queuing (event=$event_type)"
      _notify_enqueue "$msg" "$event_type" "${OPENCLAW_CHANNEL:-unknown}" "${OPENCLAW_TARGET:-unknown}"
      ;;
  esac
}

# ── Public: send a single queued entry (used by flush-queue.sh) ──────────────
# Args: <session_id> <channel> <target> <event_type> <msg>
notify_from_queue() {
  local session_id="$1"
  local channel="$2"
  local target="$3"
  local event_type="$4"
  local msg="$5"

  # Temporarily override channel/target for this delivery
  local saved_channel="${OPENCLAW_CHANNEL:-}"
  local saved_target="${OPENCLAW_TARGET:-}"
  export OPENCLAW_CHANNEL="$channel"
  export OPENCLAW_TARGET="$target"

  notify "$session_id" "$msg" "$event_type"
  local exit_code=$?

  # Restore
  export OPENCLAW_CHANNEL="$saved_channel"
  export OPENCLAW_TARGET="$saved_target"

  return $exit_code
}
