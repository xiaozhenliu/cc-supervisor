#!/usr/bin/env bash
# Install cc-supervisor skill to openclaw skills directory.
# Excludes development-only files that should not be loaded by openclaw.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$HOME/.openclaw/skills/cc-supervisor}"

# Directories and files excluded from skill installation (dev/test artifacts)
EXCLUDES=(
  tests
  docs/archive
  docs/README.md
  docs/DESIGN_DECISIONS.md
  docs/multi-session-design.md
  docs/product-requirements.md
  docs/preflight-checks.md
  docs/real-claude-hook-test-plan.md
  ref
  example-project
  .claude
  AGENTS.md
  CHANGELOG.md
  CLAUDE.md
  FILE_ORGANIZATION.md
  README_en.md
)

echo "Installing cc-supervisor skill to: $DEST"

mkdir -p "$DEST"

# Remove dev artifacts that may already exist in destination
for item in "${EXCLUDES[@]}"; do
  rm -rf "${DEST:?}/$item"
done

# Build rsync exclude args
EXCLUDE_ARGS=()
for item in "${EXCLUDES[@]}"; do
  EXCLUDE_ARGS+=(--exclude="$item")
done

rsync -a --delete \
  "${EXCLUDE_ARGS[@]}" \
  --exclude=".DS_Store" \
  --exclude=".git" \
  --exclude=".github" \
  --exclude=".worktrees" \
  --exclude="logs/" \
  --exclude="*.bak" \
  --exclude="*.backup" \
  --exclude="scripts/test-*.sh" \
  --exclude="scripts/send-test-notification.sh" \
  --exclude="*.backup-*" \
  "$SKILL_DIR/" "$DEST/"

echo "Done."
