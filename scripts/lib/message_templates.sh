#!/usr/bin/env bash
# message_templates.sh — Shared notification templates for cc-supervisor.
# Source this file: source "$(dirname "$0")/lib/message_templates.sh"

build_human_reply_help() {
  cat <<'EOF'

回复约定：
- 发给 Claude：cc <内容>
- supervisor 命令：cmd继续 / cmd停止 / cmd检查 / cmd退出
- 其他消息：默认只给 supervisor，不转发
EOF
}

build_supervisor_notification() {
  local mode="$1"
  local event_type="$2"
  local summary="$3"
  local base_message=""

  case "$event_type" in
    Stop)
      if [[ "$mode" == "auto" ]]; then
        base_message="[cc-supervisor][auto] Stop:
${summary}"
      else
        base_message="[cc-supervisor][relay] Stop:
${summary}"
      fi
      ;;
    *)
      base_message="[cc-supervisor][${mode}] ${event_type}:
${summary}"
      ;;
  esac

  printf '%s%s\n' "$base_message" "$(build_human_reply_help)"
}
