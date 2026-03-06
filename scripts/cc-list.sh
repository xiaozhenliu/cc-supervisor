#!/usr/bin/env bash
# cc-list.sh — List known supervision instances and their current routing state.

set -euo pipefail

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export CC_PROJECT_DIR

source "${CC_PROJECT_DIR}/scripts/lib/runtime_context.sh"
source "${CC_PROJECT_DIR}/scripts/lib/log.sh"

OUTPUT_JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

runtime_context_init "${CC_SUPERVISION_ID:-default}"

KNOWN_IDS="$(jq -r '.[].supervision_id // empty' "$CC_SUPERVISIONS_REGISTRY_FILE")"
while IFS= read -r supervision_id; do
  if [[ -n "$supervision_id" ]] && ! supervision_tmux_exists "$supervision_id"; then
    unregister_supervision "$supervision_id" "stale"
  fi
done <<< "$KNOWN_IDS"

if [[ "$OUTPUT_JSON" == "true" ]]; then
  cat "$CC_SUPERVISIONS_REGISTRY_FILE"
  exit 0
fi

COUNT="$(jq 'length' "$CC_SUPERVISIONS_REGISTRY_FILE")"
if [[ "$COUNT" == "0" ]]; then
  echo "No supervision instances found."
  exit 0
fi

printf '%-16s %-24s %-10s %-16s %s\n' "ID" "TMUX" "MODE" "STATUS" "PROJECT"
jq -r '
  sort_by(.started_at, .supervision_id)
  | .[]
  | [
      .supervision_id,
      .tmux_session,
      (.mode // "-"),
      (.status // "-"),
      (.project_dir // "-")
    ]
  | @tsv
' "$CC_SUPERVISIONS_REGISTRY_FILE" | while IFS=$'\t' read -r id tmux_session mode status project_dir; do
  printf '%-16s %-24s %-10s %-16s %s\n' "$id" "$tmux_session" "$mode" "$status" "$project_dir"
done
