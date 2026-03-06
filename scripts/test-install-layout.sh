#!/usr/bin/env bash
# test-install-layout.sh - Verify install-skill output contains runtime files only.
# Usage: ./scripts/test-install-layout.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CC_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SCRIPT="${CC_PROJECT_DIR}/scripts/install-skill.sh"
TEST_DIR="$(mktemp -d)"
DEST_DIR="${TEST_DIR}/installed-skill"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

assert_exists() {
  local path="$1"
  local description="$2"

  if [[ -e "$path" ]]; then
    echo "✓ PASS: $description"
  else
    echo "✗ FAIL: $description"
    echo "  missing: $path"
    exit 1
  fi
}

assert_not_exists() {
  local path="$1"
  local description="$2"

  if [[ ! -e "$path" ]]; then
    echo "✓ PASS: $description"
  else
    echo "✗ FAIL: $description"
    echo "  should be excluded: $path"
    exit 1
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Install Layout"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

bash "$INSTALL_SCRIPT" "$DEST_DIR" >/dev/null

assert_exists "$DEST_DIR/SKILL.md" "SKILL.md installed"
assert_exists "$DEST_DIR/scripts/on-cc-event.sh" "hook callback script installed"
assert_exists "$DEST_DIR/scripts/install-hooks.sh" "hook installer installed"
assert_exists "$DEST_DIR/config/claude-hooks.json" "hook config template installed"
assert_exists "$DEST_DIR/docs/phase-0.md" "runtime docs installed"
assert_exists "$DEST_DIR/docs/phase-4.md" "phase docs installed"

HOOK_SCRIPT_REF="$DEST_DIR/scripts/on-cc-event.sh"
if grep -Fq "$HOOK_SCRIPT_REF" "$DEST_DIR/.claude/settings.local.json" 2>/dev/null; then
  echo "✗ FAIL: install output should not contain baked runtime settings"
  exit 1
else
  echo "✓ PASS: install output does not bake project-local settings"
fi

while IFS= read -r relative_path; do
  [[ -z "$relative_path" ]] && continue
  assert_exists "$DEST_DIR/$relative_path" "SKILL.md reference exists: $relative_path"
done < <(grep -oE 'docs/[A-Za-z0-9._/-]+|scripts/[A-Za-z0-9._/-]+' "$DEST_DIR/SKILL.md" | sort -u)

assert_not_exists "$DEST_DIR/tests" "tests excluded from install tree"
assert_not_exists "$DEST_DIR/example-project" "example-project excluded from install tree"
assert_not_exists "$DEST_DIR/CLAUDE.md" "CLAUDE.md excluded from install tree"
assert_not_exists "$DEST_DIR/CHANGELOG.md" "CHANGELOG.md excluded from install tree"
assert_not_exists "$DEST_DIR/docs/archive" "archive docs excluded from install tree"
assert_not_exists "$DEST_DIR/docs/DESIGN_DECISIONS.md" "design notes excluded from install tree"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Install layout test passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
