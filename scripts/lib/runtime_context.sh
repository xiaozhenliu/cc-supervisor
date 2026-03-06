#!/usr/bin/env bash
# runtime_context.sh — Shared multi-session runtime identity helpers.
# Source this file before deriving tmux names, runtime paths, or registry data.

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

normalize_supervision_id() {
  local raw="${1:-default}"
  local normalized

  normalized="$(printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"

  if [[ -z "$normalized" ]]; then
    return 1
  fi

  printf '%s\n' "$normalized"
}

canonicalize_path() {
  local path="$1"

  if [[ -z "$path" ]]; then
    return 1
  fi

  if [[ -d "$path" ]]; then
    (cd "$path" && pwd -P)
    return
  fi

  if [[ -e "$path" ]]; then
    local parent
    parent="$(cd "$(dirname "$path")" && pwd -P)"
    printf '%s/%s\n' "$parent" "$(basename "$path")"
    return
  fi

  local parent_dir
  parent_dir="$(dirname "$path")"
  if [[ -d "$parent_dir" ]]; then
    parent_dir="$(cd "$parent_dir" && pwd -P)"
    printf '%s/%s\n' "$parent_dir" "$(basename "$path")"
    return
  fi

  return 1
}

resolve_supervision_id() {
  local requested="${1:-${CC_SUPERVISION_ID:-}}"
  local normalized

  if [[ -z "$requested" && -n "${CC_RUNTIME_DIR:-}" ]]; then
    if [[ "${CC_RUNTIME_DIR}" == "${CC_PROJECT_DIR}/logs" ]]; then
      requested="default"
    elif [[ "${CC_RUNTIME_DIR}" == "${CC_PROJECT_DIR}/logs/instances/"* ]]; then
      requested="${CC_RUNTIME_DIR##*/}"
    fi
  fi

  requested="${requested:-default}"

  normalized="$(normalize_supervision_id "$requested")" || return 1
  printf '%s\n' "$normalized"
}

supervision_tmux_session() {
  local supervision_id
  supervision_id="$(resolve_supervision_id "${1:-${CC_SUPERVISION_ID:-default}}")" || return 1

  if [[ "$supervision_id" == "default" ]]; then
    printf 'cc-supervise\n'
  else
    printf 'cc-supervise-%s\n' "$supervision_id"
  fi
}

supervision_runtime_dir() {
  local supervision_id
  supervision_id="$(resolve_supervision_id "${1:-${CC_SUPERVISION_ID:-default}}")" || return 1

  if [[ "$supervision_id" == "default" ]]; then
    printf '%s/logs\n' "$CC_PROJECT_DIR"
  else
    printf '%s/logs/instances/%s\n' "$CC_PROJECT_DIR" "$supervision_id"
  fi
}

runtime_registry_dir() {
  printf '%s/logs/registry\n' "$CC_PROJECT_DIR"
}

supervisions_registry_file() {
  printf '%s/supervisions.json\n' "$(runtime_registry_dir)"
}

projects_registry_file() {
  printf '%s/projects.json\n' "$(runtime_registry_dir)"
}

runtime_context_init() {
  local requested_id="${1:-${CC_SUPERVISION_ID:-default}}"
  local supervision_id
  supervision_id="$(resolve_supervision_id "$requested_id")" || return 1

  export CC_SUPERVISION_ID="$supervision_id"
  export CC_TMUX_SESSION="$(supervision_tmux_session "$supervision_id")"
  export CC_RUNTIME_DIR="$(supervision_runtime_dir "$supervision_id")"
  export CC_EVENTS_FILE="${CC_RUNTIME_DIR}/events.ndjson"
  export CC_SUPERVISOR_STATE_FILE="${CC_RUNTIME_DIR}/supervisor-state.json"
  export CC_NOTIFICATION_QUEUE_FILE="${CC_RUNTIME_DIR}/notification.queue"
  export CC_WATCHDOG_PID_FILE="${CC_RUNTIME_DIR}/watchdog.pid"
  export CC_WATCHDOG_GUARD_PID_FILE="${CC_RUNTIME_DIR}/watchdog-guard.pid"
  export CC_POLL_PID_FILE="${CC_RUNTIME_DIR}/poll.pid"
  export CC_HOOK_ENV_FILE="${CC_RUNTIME_DIR}/hook.env"
  export CC_LOG_FILE="${CC_RUNTIME_DIR}/supervisor.log"
  export CC_SUPERVISIONS_REGISTRY_FILE="$(supervisions_registry_file)"
  export CC_PROJECTS_REGISTRY_FILE="$(projects_registry_file)"

  mkdir -p "$CC_RUNTIME_DIR" "$(runtime_registry_dir)"

  if [[ ! -f "$CC_SUPERVISIONS_REGISTRY_FILE" ]]; then
    printf '[]\n' > "$CC_SUPERVISIONS_REGISTRY_FILE"
  fi

  if [[ ! -f "$CC_PROJECTS_REGISTRY_FILE" ]]; then
    printf '{}\n' > "$CC_PROJECTS_REGISTRY_FILE"
  fi
}

supervision_record_json() {
  local supervision_id
  supervision_id="$(resolve_supervision_id "${1:-${CC_SUPERVISION_ID:-default}}")" || return 1
  runtime_context_init "$supervision_id"

  jq -c --arg id "$supervision_id" '.[] | select(.supervision_id == $id)' \
    "$CC_SUPERVISIONS_REGISTRY_FILE" 2>/dev/null | head -1
}

supervision_tmux_exists() {
  local supervision_id
  local session_name
  supervision_id="$(resolve_supervision_id "${1:-${CC_SUPERVISION_ID:-default}}")" || return 1
  session_name="$(supervision_tmux_session "$supervision_id")" || return 1
  tmux has-session -t "$session_name" 2>/dev/null
}

_write_json_file() {
  local destination="$1"
  local content="$2"
  local tmp_file

  tmp_file="$(mktemp)"
  printf '%s\n' "$content" > "$tmp_file"
  mv "$tmp_file" "$destination"
}

register_supervision() {
  local supervision_id="$1"
  local project_dir="$2"
  local mode="${3:-${CC_MODE:-relay}}"
  local status="${4:-running}"
  local canonical_project
  local timestamp
  local supervisions_tmp projects_tmp

  supervision_id="$(resolve_supervision_id "$supervision_id")" || return 1
  runtime_context_init "$supervision_id"
  canonical_project="$(canonicalize_path "$project_dir")" || return 1
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  supervisions_tmp="$(mktemp)"
  jq \
    --arg id "$supervision_id" \
    --arg tmux_session "$CC_TMUX_SESSION" \
    --arg project_dir "$canonical_project" \
    --arg runtime_dir "$CC_RUNTIME_DIR" \
    --arg mode "$mode" \
    --arg status "$status" \
    --arg ts "$timestamp" \
    --arg openclaw_session_id "${OPENCLAW_SESSION_ID:-}" \
    --arg claude_session_id "${CLAUDE_SESSION_ID:-}" \
    '
      (map(select(.supervision_id != $id))) as $others
      | ([.[] | select(.supervision_id == $id) | .started_at] | first) as $started_at
      | $others + [{
          supervision_id: $id,
          tmux_session: $tmux_session,
          project_dir: $project_dir,
          runtime_dir: $runtime_dir,
          mode: $mode,
          status: $status,
          started_at: ($started_at // $ts),
          updated_at: $ts,
          openclaw_session_id: (if $openclaw_session_id == "" then null else $openclaw_session_id end),
          claude_session_id: (if $claude_session_id == "" then null else $claude_session_id end)
        }]
      | sort_by(.started_at, .supervision_id)
    ' "$CC_SUPERVISIONS_REGISTRY_FILE" > "$supervisions_tmp"
  mv "$supervisions_tmp" "$CC_SUPERVISIONS_REGISTRY_FILE"

  projects_tmp="$(mktemp)"
  jq \
    --arg project_dir "$canonical_project" \
    --arg supervision_id "$supervision_id" \
    --arg tmux_session "$CC_TMUX_SESSION" \
    --arg runtime_dir "$CC_RUNTIME_DIR" \
    --arg status "$status" \
    --arg ts "$timestamp" \
    '
      .[$project_dir] = {
        supervision_id: $supervision_id,
        tmux_session: $tmux_session,
        runtime_dir: $runtime_dir,
        status: $status,
        updated_at: $ts
      }
    ' "$CC_PROJECTS_REGISTRY_FILE" > "$projects_tmp"
  mv "$projects_tmp" "$CC_PROJECTS_REGISTRY_FILE"
}

update_supervision_record() {
  local supervision_id="$1"
  local status="${2:-running}"
  local claude_session_id="${3:-}"
  local openclaw_session_id="${4:-${OPENCLAW_SESSION_ID:-}}"
  local timestamp
  local tmp_file
  local record
  local project_dir=""

  supervision_id="$(resolve_supervision_id "$supervision_id")" || return 1
  runtime_context_init "$supervision_id"
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  record="$(supervision_record_json "$supervision_id" || true)"
  project_dir="$(printf '%s' "$record" | jq -r '.project_dir // empty' 2>/dev/null || true)"
  tmp_file="$(mktemp)"

  jq \
    --arg id "$supervision_id" \
    --arg status "$status" \
    --arg ts "$timestamp" \
    --arg claude_session_id "$claude_session_id" \
    --arg openclaw_session_id "$openclaw_session_id" \
    '
      map(
        if .supervision_id == $id then
          .updated_at = $ts
          | .status = $status
          | if $claude_session_id != "" then .claude_session_id = $claude_session_id else . end
          | if $openclaw_session_id != "" then .openclaw_session_id = $openclaw_session_id else . end
        else . end
      )
    ' "$CC_SUPERVISIONS_REGISTRY_FILE" > "$tmp_file"
  mv "$tmp_file" "$CC_SUPERVISIONS_REGISTRY_FILE"

  if [[ -n "$project_dir" ]]; then
    tmp_file="$(mktemp)"
    jq \
      --arg project_dir "$project_dir" \
      --arg supervision_id "$supervision_id" \
      --arg status "$status" \
      --arg ts "$timestamp" \
      '
        if .[$project_dir].supervision_id == $supervision_id then
          .[$project_dir].status = $status
          | .[$project_dir].updated_at = $ts
        else . end
      ' "$CC_PROJECTS_REGISTRY_FILE" > "$tmp_file"
    mv "$tmp_file" "$CC_PROJECTS_REGISTRY_FILE"
  fi
}

unregister_supervision() {
  local supervision_id="$1"
  local status="${2:-stopped}"
  local timestamp
  local record project_dir supervisions_tmp projects_tmp

  supervision_id="$(resolve_supervision_id "$supervision_id")" || return 1
  runtime_context_init "$supervision_id"
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  record="$(supervision_record_json "$supervision_id" || true)"
  project_dir="$(printf '%s' "$record" | jq -r '.project_dir // empty' 2>/dev/null || true)"

  supervisions_tmp="$(mktemp)"
  jq \
    --arg id "$supervision_id" \
    --arg status "$status" \
    --arg ts "$timestamp" \
    '
      map(
        if .supervision_id == $id then
          .status = $status
          | .updated_at = $ts
        else . end
      )
    ' "$CC_SUPERVISIONS_REGISTRY_FILE" > "$supervisions_tmp"
  mv "$supervisions_tmp" "$CC_SUPERVISIONS_REGISTRY_FILE"

  if [[ -n "$project_dir" ]]; then
    projects_tmp="$(mktemp)"
    jq \
      --arg project_dir "$project_dir" \
      --arg supervision_id "$supervision_id" \
      'if .[$project_dir].supervision_id == $supervision_id then del(.[$project_dir]) else . end' \
      "$CC_PROJECTS_REGISTRY_FILE" > "$projects_tmp"
    mv "$projects_tmp" "$CC_PROJECTS_REGISTRY_FILE"
  fi
}

resolve_project_supervision() {
  local input_path="$1"
  local canonical_path
  local supervision_id

  runtime_context_init "${CC_SUPERVISION_ID:-default}"
  canonical_path="$(canonicalize_path "$input_path")" || return 1

  supervision_id="$(
    jq -r --arg path "$canonical_path" '
      to_entries
      | map(.key as $project | select(($path == $project) or ($path | startswith($project + "/"))))
      | sort_by(.key | length)
      | reverse
      | .[0].value.supervision_id // empty
    ' "$CC_PROJECTS_REGISTRY_FILE" 2>/dev/null
  )"

  if [[ -z "$supervision_id" ]]; then
    return 1
  fi

  if ! supervision_tmux_exists "$supervision_id"; then
    unregister_supervision "$supervision_id" "stale"
    return 1
  fi

  printf '%s\n' "$supervision_id"
}

assert_supervision_start_allowed() {
  local supervision_id="$1"
  local project_dir="$2"
  local canonical_project existing_record existing_project existing_id

  supervision_id="$(resolve_supervision_id "$supervision_id")" || return 1
  canonical_project="$(canonicalize_path "$project_dir")" || return 1
  runtime_context_init "$supervision_id"

  existing_record="$(supervision_record_json "$supervision_id" || true)"
  if [[ -n "$existing_record" ]]; then
    existing_project="$(printf '%s' "$existing_record" | jq -r '.project_dir // empty')"
    if supervision_tmux_exists "$supervision_id"; then
      if [[ -n "$existing_project" && "$existing_project" != "$canonical_project" ]]; then
        printf 'supervision id conflict: id=%s active_project=%s requested_project=%s\n' \
          "$supervision_id" "$existing_project" "$canonical_project" >&2
        return 1
      fi
    else
      unregister_supervision "$supervision_id" "stale"
    fi
  fi

  existing_id="$(resolve_project_supervision "$canonical_project" 2>/dev/null || true)"
  if [[ -n "$existing_id" && "$existing_id" != "$supervision_id" ]]; then
    printf 'project already supervised: project=%s supervision_id=%s requested_id=%s\n' \
      "$canonical_project" "$existing_id" "$supervision_id" >&2
    return 1
  fi
}

list_supervisions_json() {
  runtime_context_init "${CC_SUPERVISION_ID:-default}"
  jq -c '.' "$CC_SUPERVISIONS_REGISTRY_FILE"
}
