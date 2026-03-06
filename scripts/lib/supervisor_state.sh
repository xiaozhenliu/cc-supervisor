#!/usr/bin/env bash
# supervisor_state.sh — Persist lightweight supervisor preferences across turns.
# Source this file: source "$(dirname "$0")/lib/supervisor_state.sh"

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CC_SUPERVISOR_STATE_FILE="${CC_SUPERVISOR_STATE_FILE:-${CC_PROJECT_DIR}/logs/supervisor-state.json}"

_supervisor_state_default_json() {
  jq -cn \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{
      updated_at: $ts,
      preferences: {
        auto_continue_simple_prompts: true,
        require_review_before_phase_4: false
      },
      meta_history: []
    }'
}

supervisor_state_init() {
  mkdir -p "$(dirname "$CC_SUPERVISOR_STATE_FILE")"
  if [[ ! -f "$CC_SUPERVISOR_STATE_FILE" ]]; then
    _supervisor_state_default_json > "$CC_SUPERVISOR_STATE_FILE"
  fi
}

supervisor_state_record_meta() {
  local mode="$1"
  local message="$2"
  local normalized
  local auto_continue=""
  local require_review=""
  local effects=()
  local tmp_file

  supervisor_state_init

  normalized="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  case "$normalized" in
    *不要自动确认*|*不要自动继续*|*别自动继续*|*不要直接确认*)
      auto_continue="false"
      effects+=("auto_continue_simple_prompts=false")
      ;;
    *恢复自动确认*|*恢复自动继续*|*可以自动继续*|*继续自动确认*)
      auto_continue="true"
      effects+=("auto_continue_simple_prompts=true")
      ;;
  esac

  case "$normalized" in
    *完成前先通知我*|*完成前先让我看*|*先给我review*|*让我review后再结束*|*先别结束*)
      require_review="true"
      effects+=("require_review_before_phase_4=true")
      ;;
    *完成了直接结束*|*完成后直接汇报*|*不用先通知我review*|*恢复直接结束*)
      require_review="false"
      effects+=("require_review_before_phase_4=false")
      ;;
  esac

  tmp_file="$(mktemp)"
  jq \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg mode "$mode" \
    --arg message "$message" \
    --arg auto_continue "$auto_continue" \
    --arg require_review "$require_review" \
    --argjson effects "$(printf '%s\n' "${effects[@]}" | jq -R . | jq -s .)" \
    '
      .updated_at = $ts
      | if $auto_continue != "" then
          .preferences.auto_continue_simple_prompts = ($auto_continue == "true")
        else . end
      | if $require_review != "" then
          .preferences.require_review_before_phase_4 = ($require_review == "true")
        else . end
      | .meta_history = (
          (.meta_history // [])
          + [{
              ts: $ts,
              mode: $mode,
              message: $message,
              effects: $effects
            }]
        )
      | .meta_history = (.meta_history | if length > 20 then .[-20:] else . end)
    ' "$CC_SUPERVISOR_STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$CC_SUPERVISOR_STATE_FILE"
}

supervisor_state_summary() {
  supervisor_state_init
  jq -r '
    [
      "auto_continue_simple_prompts=" + (.preferences.auto_continue_simple_prompts | tostring),
      "require_review_before_phase_4=" + (.preferences.require_review_before_phase_4 | tostring)
    ] | join(", ")
  ' "$CC_SUPERVISOR_STATE_FILE"
}
