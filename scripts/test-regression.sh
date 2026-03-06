#!/usr/bin/env bash
# test-regression.sh - Run the stable cc-supervisor regression suite.
# Usage: ./scripts/test-regression.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TESTS=(
  "test-human-command-parser.sh"
  "test-handle-human-reply.sh"
  "test-hook-env-lifecycle.sh"
  "test-notification-template.sh"
  "test-install-layout.sh"
  "test-install-hooks-failure.sh"
  "test-notification-queue-fallback.sh"
  "test-real-claude-hook-post-tool-use.sh"
  "test-real-claude-hook-notification.sh"
  "test-real-claude-hook-stop.sh"
  "test-real-claude-hook-session-end.sh"
)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running cc-supervisor regression suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for test_script in "${TESTS[@]}"; do
  echo ">>> $test_script"
  bash "${SCRIPT_DIR}/${test_script}"
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Regression suite passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
