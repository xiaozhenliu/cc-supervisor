#!/usr/bin/env bash
# install-hooks.sh — Install Claude Code Hook config into the project-local settings.
#
# Reads config/claude-hooks.json, substitutes __HOOK_SCRIPT_PATH__ with the
# absolute path of on-cc-event.sh, and deep-merges into
# <target>/.claude/settings.local.json while preserving existing configuration.
#
# By default the target is CC_PROJECT_DIR (this repo). Set CLAUDE_WORKDIR to
# register hooks in a different project's settings instead:
#
#   CLAUDE_WORKDIR=~/Projects/my-app ./scripts/install-hooks.sh
#
# Idempotent: safe to run multiple times.

set -euo pipefail

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export CC_PROJECT_DIR

# CLAUDE_WORKDIR is the project whose .claude/settings.local.json gets the hooks.
# Defaults to CC_PROJECT_DIR for single-project (self-supervised) setups.
CLAUDE_WORKDIR="${CLAUDE_WORKDIR:-$CC_PROJECT_DIR}"

source "$(dirname "$0")/lib/log.sh"

TEMPLATE="${CC_PROJECT_DIR}/config/claude-hooks.json"
HOOK_SCRIPT="${CC_PROJECT_DIR}/scripts/on-cc-event.sh"
SETTINGS_FILE="${CLAUDE_WORKDIR}/.claude/settings.local.json"
SETTINGS_BACKUP="${SETTINGS_FILE}.bak"

# ── Preflight ─────────────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  log_error "jq is required. Install with: brew install jq"
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  log_error "Hook template not found: $TEMPLATE"
  exit 1
fi

if [[ ! -f "$HOOK_SCRIPT" ]]; then
  log_error "Hook script not found: $HOOK_SCRIPT"
  exit 1
fi

# Ensure hook script is executable
chmod +x "$HOOK_SCRIPT"
log_info "Hook script: $HOOK_SCRIPT"

# ── Substitute placeholder ────────────────────────────────────────────────────
HOOK_JSON="$(sed "s|__HOOK_SCRIPT_PATH__|${HOOK_SCRIPT}|g" "$TEMPLATE")"

if ! echo "$HOOK_JSON" | jq empty 2>/dev/null; then
  log_error "Substituted hook JSON is invalid — check config/claude-hooks.json"
  exit 1
fi

# ── Ensure .claude/ directory exists and settings.local.json is present ──────
mkdir -p "$(dirname "$SETTINGS_FILE")"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  log_info ".claude/settings.local.json not found — creating empty base"
  echo '{}' > "$SETTINGS_FILE"
fi

# ── Backup original ───────────────────────────────────────────────────────────
cp "$SETTINGS_FILE" "$SETTINGS_BACKUP"
log_info "Backed up settings.json → $SETTINGS_BACKUP"

# ── Deep-merge: existing hooks + new hook arrays (idempotent per event type) ──
# The merge strategy: for each hook event key, replace the entire array with
# the new value from the template. This prevents duplicates on re-runs.
MERGED="$(jq -s \
  '.[0] as $existing | .[1] as $new |
   $existing * { "hooks": (($existing.hooks // {}) + $new.hooks) }' \
  "$SETTINGS_FILE" - <<< "$HOOK_JSON")"

if ! echo "$MERGED" | jq empty 2>/dev/null; then
  log_error "Merged JSON is invalid — aborting (original unchanged)"
  exit 1
fi

echo "$MERGED" | jq '.' > "$SETTINGS_FILE"

# ── Summary ───────────────────────────────────────────────────────────────────
EVENTS="$(echo "$HOOK_JSON" | jq -r '.hooks | keys | join(", ")')"
log_info "Hooks installed for events: $EVENTS"
log_info "Supervisor home: $CC_PROJECT_DIR"
log_info "Settings updated: $SETTINGS_FILE"
echo "Done. Verify with: cat ${SETTINGS_FILE} | jq .hooks"
