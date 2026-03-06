#!/usr/bin/env bash
# Install cc-supervisor skill to openclaw skills directory.
# Excludes development-only files that should not be loaded by openclaw.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$HOME/.openclaw/skills/cc-supervisor}"

# Directories and files excluded from skill installation (dev/test artifacts)
EXCLUDES=(
  tests
  docs
  ref
  example-project
  CHANGELOG.md
  CLAUDE.md
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
  --exclude=".git" \
  --exclude="logs/" \
  --exclude="*.backup-*" \
  "$SKILL_DIR/" "$DEST/"

echo "Done."
