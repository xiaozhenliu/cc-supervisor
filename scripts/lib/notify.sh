#!/usr/bin/env bash
# notify.sh — Channel dispatch layer for cc-supervisor notifications.
# Source this file: source "$(dirname "$0")/lib/notify.sh"
#
# Public interface:
#   notify <session_id> <message> [event_type]
#   notify_from_queue <session_id> <channel> <target> <event_type> <msg>
#
# Routing: controlled by $OPENCLAW_CHANNEL (default: discord)
# On failure: enqueues to logs/notification.queue for later retry

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# ── Internal: write to notification queue ────────────────────────────────────
_notify_enqueue() {
  local msg="$1"
  local event_type="${2:-unknown}"
  local queue_file="${CC_PROJECT_DIR}/logs/notification.queue"
  mkdir -p "$(dirname "$queue_file")"
  printf '%s|%s|%s|%s|%s|%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "${OPENCLAW_CHANNEL:-unknown}" \
    "${OPENCLAW_ACCOUNT:-}" \
    "${OPENCLAW_TARGET:-unknown}" \
    "$event_type" \
    "$msg" >> "$queue_file"
  log_info "Notification queued: $event_type"
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

  if ! command -v openclaw &>/dev/null; then
    log_warn "openclaw not in PATH — queuing notification (event=$event_type)"
    _notify_enqueue "$msg" "$event_type"
    return 0
  fi

  if openclaw agent \
      --session-id "$session_id" \
      --message "$msg" \
      ${OPENCLAW_TARGET:+--deliver} \
      ${OPENCLAW_TARGET:+--reply-to "$OPENCLAW_TARGET"} \
      2>/dev/null; then
    log_info "openclaw agent triggered: channel=discord event=$event_type session=$session_id"
  else
    log_warn "openclaw agent failed — queuing (event=$event_type)"
    _notify_enqueue "$msg" "$event_type"
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
  _notify_enqueue "$msg" "$event_type"
}

# ── Public: route notification to configured channel ─────────────────────────
notify() {
  local session_id="$1"
  local msg="$2"
  local event_type="${3:-unknown}"

  case "${OPENCLAW_CHANNEL:-discord}" in
    discord)
      _notify_discord "$session_id" "$msg" "$event_type"
      ;;
    feishu)
      _notify_feishu "$session_id" "$msg" "$event_type"
      ;;
    *)
      log_warn "Unknown channel '${OPENCLAW_CHANNEL}', fallback to discord"
      _notify_discord "$session_id" "$msg" "$event_type"
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
