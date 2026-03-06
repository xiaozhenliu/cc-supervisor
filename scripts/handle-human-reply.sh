#!/usr/bin/env bash
# handle-human-reply.sh — Phase 3 execution gate for human replies.
#
# This script turns a raw human message into a deterministic supervision action:
#   1. Parse via parse-human-command.sh
#   2. Execute fixed actions where possible
#   3. Return JSON describing what happened
#
# Exit codes:
#   0 - handled successfully
#   1 - execution failure
#   2 - invalid human input (for example: empty `cc` body)

set -euo pipefail

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export CC_PROJECT_DIR

source "$(dirname "$0")/lib/log.sh"
source "$(dirname "$0")/lib/supervisor_state.sh"

MODE="relay"
MESSAGE=""

PARSER_SCRIPT="${CC_HUMAN_COMMAND_PARSER:-${CC_PROJECT_DIR}/scripts/parse-human-command.sh}"
SEND_SCRIPT="${CC_SEND_SCRIPT:-${CC_PROJECT_DIR}/scripts/cc_send.sh}"
CAPTURE_SCRIPT="${CC_CAPTURE_SCRIPT:-${CC_PROJECT_DIR}/scripts/cc_capture.sh}"

usage() {
  cat <<'EOF'
Usage: handle-human-reply.sh [--mode relay|auto] [--message <text>]

If --message is omitted, the script reads the full message from stdin.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      if [[ $# -lt 2 ]]; then
        usage >&2
        exit 1
      fi
      MODE="$2"
      shift 2
      ;;
    --message)
      if [[ $# -lt 2 ]]; then
        usage >&2
        exit 1
      fi
      MESSAGE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$MODE" != "relay" && "$MODE" != "auto" ]]; then
  log_error "Invalid mode: $MODE"
  exit 1
fi

if [[ -z "$MESSAGE" ]]; then
  MESSAGE="$(cat)"
fi

if [[ ! -x "$PARSER_SCRIPT" && ! -f "$PARSER_SCRIPT" ]]; then
  log_error "Parser script not found: $PARSER_SCRIPT"
  exit 1
fi

PARSE_JSON="$(bash "$PARSER_SCRIPT" --mode "$MODE" --message "$MESSAGE")"
PARSE_OK="$(echo "$PARSE_JSON" | jq -r '.ok')"
ACTION="$(echo "$PARSE_JSON" | jq -r '.action')"
REASON="$(echo "$PARSE_JSON" | jq -r '.reason')"
CONTENT="$(echo "$PARSE_JSON" | jq -r '.content')"

if [[ "$PARSE_OK" != "true" ]]; then
  jq -cn \
    --arg mode "$MODE" \
    --arg action "$ACTION" \
    --arg reason "$REASON" \
    --arg content "$CONTENT" \
    '{ok:false, mode:$mode, action:$action, reason:$reason, content:$content, executed:false}'
  exit 2
fi

EXECUTED=false
COMMAND_KIND=""
COMMAND_VALUE=""
SNAPSHOT=""
NEXT_PHASE=""
STATE_SUMMARY="$(supervisor_state_summary)"

case "$ACTION" in
  forward)
    bash "$SEND_SCRIPT" "$CONTENT"
    EXECUTED=true
    COMMAND_KIND="send_text"
    COMMAND_VALUE="$CONTENT"
    ;;
  send_key)
    bash "$SEND_SCRIPT" --key "$CONTENT"
    EXECUTED=true
    COMMAND_KIND="send_key"
    COMMAND_VALUE="$CONTENT"
    ;;
  continue)
    bash "$SEND_SCRIPT" "Please continue."
    EXECUTED=true
    COMMAND_KIND="send_text"
    COMMAND_VALUE="Please continue."
    ;;
  pause)
    bash "$SEND_SCRIPT" --key Escape
    EXECUTED=true
    COMMAND_KIND="send_key"
    COMMAND_VALUE="Escape"
    ;;
  status)
    SNAPSHOT="$(bash "$CAPTURE_SCRIPT" --tail 20 2>/dev/null || true)"
    COMMAND_KIND="capture"
    COMMAND_VALUE="--tail 20"
    ;;
  exit)
    SNAPSHOT="$(bash "$CAPTURE_SCRIPT" --tail 20 --grep "complete|done|error|fail|summary" 2>/dev/null || true)"
    COMMAND_KIND="capture"
    COMMAND_VALUE="--tail 20 --grep complete|done|error|fail|summary"
    NEXT_PHASE="phase_4"
    ;;
  meta)
    supervisor_state_record_meta "$MODE" "$CONTENT"
    STATE_SUMMARY="$(supervisor_state_summary)"
    EXECUTED=true
    COMMAND_KIND="state_update"
    COMMAND_VALUE="$STATE_SUMMARY"
    ;;
  *)
    log_error "Unsupported parsed action: $ACTION"
    exit 1
    ;;
esac

jq -cn \
  --argjson executed "$EXECUTED" \
  --arg mode "$MODE" \
  --arg action "$ACTION" \
  --arg reason "$REASON" \
  --arg content "$CONTENT" \
  --arg command_kind "$COMMAND_KIND" \
  --arg command_value "$COMMAND_VALUE" \
  --arg snapshot "$SNAPSHOT" \
  --arg next_phase "$NEXT_PHASE" \
  --arg state_summary "$STATE_SUMMARY" \
  '{
    ok:true,
    mode:$mode,
    action:$action,
    reason:$reason,
    content:$content,
    executed:$executed,
    command_kind:(if $command_kind == "" then null else $command_kind end),
    command_value:(if $command_value == "" then null else $command_value end),
    snapshot:(if $snapshot == "" then null else $snapshot end),
    next_phase:(if $next_phase == "" then null else $next_phase end),
    state_summary:(if $state_summary == "" then null else $state_summary end)
  }'
