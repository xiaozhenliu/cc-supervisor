#!/usr/bin/env bash
# get-session-id.sh - Reliably get current OpenClaw session ID
# Usage: source this script or run: eval "$(./get-session-id.sh)"

set -euo pipefail

# ONLY use existing OPENCLAW_SESSION_ID environment variable
# Do NOT call openclaw session-id (unreliable) or generate new UUID

if [ -n "${OPENCLAW_SESSION_ID:-}" ]; then
  # Validate UUID format
  if echo "$OPENCLAW_SESSION_ID" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
    echo "# ✓ Using existing session ID: $OPENCLAW_SESSION_ID" >&2
    echo "export OPENCLAW_SESSION_ID='$OPENCLAW_SESSION_ID'"
    exit 0
  else
    echo "# ERROR: OPENCLAW_SESSION_ID has invalid format: $OPENCLAW_SESSION_ID" >&2
    echo "# Expected UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (lowercase hex)" >&2
    exit 1
  fi
fi

# OPENCLAW_SESSION_ID not set - this is an error
echo "# ERROR: OPENCLAW_SESSION_ID environment variable is not set" >&2
echo "# This skill must be run from within an OpenClaw agent session" >&2
echo "# The OpenClaw agent should automatically set OPENCLAW_SESSION_ID" >&2
echo "#" >&2
echo "# If you are running this manually for testing, set it first:" >&2
echo "#   export OPENCLAW_SESSION_ID=<existing-active-session-id>" >&2
echo "# Or resolve it from session store via scripts/find-active-session.sh" >&2
echo "#" >&2
echo "# If you are in an OpenClaw agent session and seeing this error," >&2
echo "# please report this as a bug." >&2
exit 1
