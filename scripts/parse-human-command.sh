#!/usr/bin/env bash
# parse-human-command.sh — Parse a human message into an explicit supervision action.
#
# Policy:
#   - Only messages starting with `cc` are forwarded to Claude Code.
#   - All other messages are handled as supervisor commands or meta-instructions.
#
# Usage:
#   ./scripts/parse-human-command.sh --mode auto --message "cc 修复登录超时"
#   echo "cc 修复登录超时" | ./scripts/parse-human-command.sh --mode relay
#
# Output: JSON describing the parsed action.

set -euo pipefail

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export CC_PROJECT_DIR

source "$(dirname "$0")/lib/log.sh"

MODE="relay"
MESSAGE=""

usage() {
  cat <<'EOF'
Usage: parse-human-command.sh [--mode relay|auto] [--message <text>]

If --message is omitted, the script reads the full message from stdin.
EOF
}

trim_leading_ws() {
  local value="$1"
  while [[ -n "$value" ]]; do
    case "${value:0:1}" in
      [[:space:]]) value="${value:1}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$value"
}

trim_trailing_ws() {
  local value="$1"
  while [[ -n "$value" ]]; do
    case "${value: -1}" in
      [[:space:]]) value="${value%?}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$value"
}

json_result() {
  local ok="$1"
  local action="$2"
  local reason="$3"
  local content="$4"
  jq -cn \
    --argjson ok "$ok" \
    --arg mode "$MODE" \
    --arg action "$action" \
    --arg reason "$reason" \
    --arg content "$content" \
    '{ok:$ok, mode:$mode, action:$action, reason:$reason, content:$content}'
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

RAW_MESSAGE="$MESSAGE"
TRIMMED="$(trim_trailing_ws "$(trim_leading_ws "$RAW_MESSAGE")")"
LOWER_TRIMMED="$(printf '%s' "$TRIMMED" | tr '[:upper:]' '[:lower:]')"

if [[ -z "$TRIMMED" ]]; then
  json_result true "meta" "empty_message" ""
  exit 0
fi

if [[ ${#TRIMMED} -ge 2 && "${LOWER_TRIMMED:0:2}" == "cc" ]]; then
  DELIM="${TRIMMED:2:1}"
  case "$DELIM" in
    ""|[[:space:]]|:|：)
      CONTENT="${TRIMMED:2}"
      CONTENT="$(trim_leading_ws "$CONTENT")"
      case "${CONTENT:0:1}" in
        :|：)
          CONTENT="${CONTENT:1}"
          CONTENT="$(trim_leading_ws "$CONTENT")"
          ;;
      esac
      if [[ -z "$CONTENT" ]]; then
        json_result false "error" "empty_forward_content" ""
        exit 0
      fi
      json_result true "forward" "cc_prefix" "$CONTENT"
      exit 0
      ;;
  esac
fi

if [[ ${#LOWER_TRIMMED} -ge 3 && "${LOWER_TRIMMED:0:3}" == "cmd" ]]; then
  CMD_BODY="${TRIMMED:3}"
  CMD_BODY="$(trim_leading_ws "$CMD_BODY")"
  case "${CMD_BODY:0:1}" in
    :|：)
      CMD_BODY="${CMD_BODY:1}"
      CMD_BODY="$(trim_leading_ws "$CMD_BODY")"
      ;;
  esac

  case "$CMD_BODY" in
    继续)
      json_result true "continue" "cmd_continue" ""
      exit 0
      ;;
    停止)
      json_result true "pause" "cmd_pause" ""
      exit 0
      ;;
    检查)
      json_result true "status" "cmd_status" ""
      exit 0
      ;;
    退出)
      json_result true "exit" "cmd_exit" ""
      exit 0
      ;;
  esac
fi

case "$LOWER_TRIMMED" in
  *)
    json_result true "meta" "default_meta" "$TRIMMED"
    ;;
esac
