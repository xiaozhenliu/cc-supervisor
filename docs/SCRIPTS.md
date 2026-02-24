# Script Reference

Per-script interface documentation: arguments, environment variables read/set,
side effects, and exit codes.

**Common conventions across all scripts:**
- All scripts use `set -euo pipefail`.
- All scripts source `lib/log.sh`, which writes structured JSON to `logs/supervisor.log`
  and human-readable lines to stderr.
- All scripts resolve `CC_PROJECT_DIR` themselves if not set in the environment,
  using `$(cd "$(dirname "$0")/.." && pwd)`.

---

## supervisor_run.sh

**Purpose:** Create or reuse the tmux session `cc-supervise`. Launch Claude Code
(`claude`) inside it at `CLAUDE_WORKDIR`. Start (or restart) the watchdog daemon
and the poll daemon.

**Usage:**
```bash
# Via shell alias (recommended):
cc-supervise ~/Projects/my-app

# Direct invocation:
CC_PROJECT_DIR=~/.openclaw/skills/cc-supervisor \
CLAUDE_WORKDIR=~/Projects/my-app \
  ~/.openclaw/skills/cc-supervisor/scripts/supervisor_run.sh
```

**Arguments:** None. Configuration is via environment variables only.

**Environment variables:**

| Variable | Direction | Default | Notes |
|----------|-----------|---------|-------|
| `CC_PROJECT_DIR` | Read + Set (exported) | Auto-resolved from script path | Path to this cc-supervisor repo (i.e. `~/.openclaw/skills/cc-supervisor`). Used to locate `scripts/`, `config/`, `logs/`. Exported into tmux session for Hook callbacks. |
| `CLAUDE_WORKDIR` | Read + Set (exported) | `$CC_PROJECT_DIR` | Directory where Claude Code starts working. Set this to the project you want to supervise. |
| `CC_TIMEOUT` | Read | `1800` | Passed to `cc-watchdog.sh` as the inactivity threshold (seconds). |
| `CC_POLL_INTERVAL` | Read | `15` | Passed to `cc-poll.sh` as the poll interval (minutes). Set to `0` to disable. |
| `CC_POLL_LINES` | Read | `40` | Passed to `cc-poll.sh` as the number of terminal lines to capture. |

**Side effects:**
- Creates tmux session `cc-supervise` (detached) starting in `CLAUDE_WORKDIR`.
- Both `CC_PROJECT_DIR` and `CLAUDE_WORKDIR` are exported into the session.
- Sends `claude` + Enter into the session to start Claude Code.
- Kills any previously running watchdog (reads `$CC_PROJECT_DIR/logs/watchdog.pid`).
- Spawns `cc-watchdog.sh` in the background.
- Kills any previously running poll daemon (reads `$CC_PROJECT_DIR/logs/poll.pid`).
- Spawns `cc-poll.sh` in the background (unless `CC_POLL_INTERVAL=0`).

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | Session created successfully. |
| `exec` | Session already existed — `exec tmux attach-session` replaces the current process. |
| `1` | `tmux` is not installed. |

---

## cc_send.sh

**Purpose:** Send a text prompt to Claude Code running inside the tmux session.
Text and Enter are sent as separate `send-keys` calls to prevent special characters
(quotes, backslashes, etc.) from being interpreted by tmux.

**Usage:**
```bash
./scripts/cc_send.sh "<text>"
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `text` | Yes | The prompt text to send. Passed with `-l` (literal) flag — safe for all printable characters. |

**Environment variables:**

| Variable | Direction | Default | Notes |
|----------|-----------|---------|-------|
| `SESSION_NAME` | Hardcoded | `cc-supervise` | Not overridable via env; edit the script to change. |

**Side effects:**
- Calls `tmux send-keys -t cc-supervise -l "<text>"` then `tmux send-keys Enter`.
- Logs the first 120 characters of the sent text to `supervisor.log`.

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | Text sent successfully. |
| `1` | Missing argument. |
| `1` | Session `cc-supervise` not found (run `supervisor_run.sh` first). |

---

## cc_capture.sh

**Purpose:** Snapshot recent output from the Claude Code tmux pane and print it to
stdout. Used by `on-cc-event.sh` to build Stop event summaries, and directly by
humans or OpenClaw for diagnostics.

**Usage:**
```bash
./scripts/cc_capture.sh [--tail N]
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `--tail N` | No | Number of lines to capture. Default: `50`. |

**Environment variables:** None beyond the common `CC_PROJECT_DIR` for logging.

**Side effects:**
- Calls `tmux capture-pane -t cc-supervise -p -S -N` and prints output to stdout.

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | Output captured and printed. |
| `1` | Session `cc-supervise` not found. |
| `1` | Unknown argument passed. |

---

## on-cc-event.sh

**Purpose:** Unified Claude Code Hook callback. Reads a Hook JSON payload from stdin,
deduplicates it, appends a structured record to `logs/events.ndjson`, and calls
`openclaw send` for notification-worthy events.

**Usage:** Invoked automatically by Claude Code hooks. Not meant to be called directly,
but can be tested by piping JSON to it:
```bash
echo '{"hook_event_name":"Stop","session_id":"s1","event_id":"e1"}' \
  | ./scripts/on-cc-event.sh
```

**Stdin:** Hook JSON payload. Required fields:

| Field | Type | Notes |
|-------|------|-------|
| `hook_event_name` | string | `Stop`, `PostToolUse`, `Notification`, or `SessionEnd` |
| `session_id` | string | Used for deduplication |
| `event_id` | string | Used for deduplication |
| `transcript_path` | string | (Stop only) Path to transcript JSON for summary fallback |
| `toolResult.isError` | boolean | (PostToolUse only) Triggers notification when `true` |
| `tool_name` | string | (PostToolUse only) Included in summary |
| `message` | string | (Notification only) Used as summary |

**Environment variables:**

| Variable | Direction | Default | Notes |
|----------|-----------|---------|-------|
| `CC_PROJECT_DIR` | Read | Self-resolved | Must point to project root; Hook callbacks run from an unspecified working directory. |

**Side effects:**
- Appends one JSON line to `$CC_PROJECT_DIR/logs/events.ndjson`.
- Calls `openclaw send "<message>"` for `Stop`, `Notification`, `SessionEnd`, and
  error `PostToolUse` events.
- If `openclaw` is not in `$PATH`: skips notification, logs a WARN, continues normally.

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | Event processed (or deduplicated and skipped). |
| `1` | Empty stdin. |
| `1` | `jq` not found. |
| `1` | Missing `hook_event_name` in payload. |

---

## install-hooks.sh

**Purpose:** Register Claude Code hooks by substituting the absolute path of
`on-cc-event.sh` into `config/claude-hooks.json` and deep-merging the result into
`<target>/.claude/settings.local.json`. Idempotent: re-running replaces hook arrays
without creating duplicates.

**Usage:**
```bash
# Via shell alias (recommended):
cc-install-hooks ~/Projects/my-app

# Direct invocation:
CC_PROJECT_DIR=~/.openclaw/skills/cc-supervisor \
CLAUDE_WORKDIR=~/Projects/my-app \
  ~/.openclaw/skills/cc-supervisor/scripts/install-hooks.sh
```

**Arguments:** None. Configuration is via environment variables only.

**Environment variables:**

| Variable | Direction | Default | Notes |
|----------|-----------|---------|-------|
| `CC_PROJECT_DIR` | Read | Self-resolved | Path to this cc-supervisor repo (i.e. `~/.openclaw/skills/cc-supervisor`). Used to locate `config/claude-hooks.json` and `scripts/on-cc-event.sh`. |
| `CLAUDE_WORKDIR` | Read | `$CC_PROJECT_DIR` | Target project directory. Hooks are written to `$CLAUDE_WORKDIR/.claude/settings.local.json`. |

**Side effects:**
- Reads `$CC_PROJECT_DIR/config/claude-hooks.json`.
- Writes `$CLAUDE_WORKDIR/.claude/settings.local.json` (project-local, globally gitignored).
- Creates `$CLAUDE_WORKDIR/.claude/settings.local.json.bak` before modification.
- Sets `on-cc-event.sh` as executable (`chmod +x`).

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | Hooks installed successfully. |
| `1` | `jq` not found. |
| `1` | `config/claude-hooks.json` template not found. |
| `1` | `scripts/on-cc-event.sh` not found. |
| `1` | JSON validation failed after substitution or merge. |

---

## cc-watchdog.sh

**Purpose:** Background daemon that monitors `logs/events.ndjson` modification time.
If no new event arrives within `CC_TIMEOUT` seconds, it sends an inactivity alert via
`openclaw send`. Resets the alert after each new event. Exits cleanly when the tmux
session disappears or on SIGTERM/SIGINT.

**Usage:** Normally started automatically by `supervisor_run.sh`. Can also be run
manually for testing:
```bash
CC_TIMEOUT=60 ./scripts/cc-watchdog.sh
```

**Arguments:** None.

**Environment variables:**

| Variable | Direction | Default | Notes |
|----------|-----------|---------|-------|
| `CC_PROJECT_DIR` | Read | Self-resolved | Used to locate `logs/events.ndjson` and `logs/watchdog.pid`. |
| `CC_TIMEOUT` | Read | `1800` | Inactivity threshold in seconds. Set to `60` for testing. |

**Side effects:**
- Writes its PID to `logs/watchdog.pid` on startup.
- Removes `logs/watchdog.pid` on exit (via `trap cleanup EXIT INT TERM`).
- Calls `openclaw send "⏰ watchdog: ..."` once per idle window (not repeatedly).
- Polls `events.ndjson` mtime every 30 seconds using `stat` (macOS/GNU compatible).

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | Exited because tmux session `cc-supervise` disappeared. |
| `0` | Exited on SIGTERM or SIGINT (clean shutdown). |

---

## cc-poll.sh

**Purpose:** Background daemon that periodically captures terminal output via
`cc_capture.sh` and sends snapshots to OpenClaw via `openclaw agent`. Fills
visibility gaps between Hook events during long-running operations. Skips the
snapshot if `events.ndjson` was updated within the last poll interval (dedup).

**Usage:** Normally started automatically by `supervisor_run.sh`. Can also be run
manually for testing:
```bash
CC_POLL_INTERVAL=3 ./scripts/cc-poll.sh
```

**Arguments:** None.

**Environment variables:**

| Variable | Direction | Default | Notes |
|----------|-----------|---------|-------|
| `CC_PROJECT_DIR` | Read | Self-resolved | Used to locate `logs/events.ndjson`, `logs/poll.pid`, and `scripts/cc_capture.sh`. |
| `CC_POLL_INTERVAL` | Read | `15` | Poll interval in minutes. Range: `3`–`1440`. Set to `0` to disable (exits immediately). |
| `CC_POLL_LINES` | Read | `40` | Number of terminal lines to capture per snapshot. |
| `OPENCLAW_SESSION_ID` | Read | *(none)* | Session ID for routing notifications back to the originating conversation. Required for notifications. |

**Side effects:**
- Writes its PID to `logs/poll.pid` on startup.
- Removes `logs/poll.pid` on exit (via `trap cleanup EXIT INT TERM`).
- Calls `cc_capture.sh --tail $CC_POLL_LINES` each cycle, truncates to 1000 chars.
- Sends `[cc-supervisor][poll] Terminal snapshot: ...` via `openclaw agent`.
- Queues to `logs/notification.queue` if `openclaw agent` fails.
- Checks `events.ndjson` mtime; skips snapshot if Hook events arrived within the interval.

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | Polling disabled (`CC_POLL_INTERVAL=0`). |
| `0` | Exited because tmux session `cc-supervise` disappeared. |
| `0` | Exited on SIGTERM or SIGINT (clean shutdown). |
| `1` | `CC_POLL_INTERVAL` out of range (not 0 and not 3–1440). |

---

## demo.sh

**Purpose:** End-to-end demonstration of the full supervision loop without requiring
a real Claude Code session or network access. Uses a plain bash shell in tmux and
fires Hook events manually via `on-cc-event.sh`.

**Usage:**
```bash
./scripts/demo.sh [--clean]
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `--clean` | No | Kill the existing `cc-supervise` session before starting, for a fresh run. |

**Environment variables:**

| Variable | Direction | Default | Notes |
|----------|-----------|---------|-------|
| `CC_PROJECT_DIR` | Read | Self-resolved | Passed to `on-cc-event.sh`. |

**Side effects:**
- Creates tmux session `cc-supervise` with a plain bash shell.
- Fires `PostToolUse`, `Stop` (×2), and `SessionEnd` Hook events via `on-cc-event.sh`.
- Appends records to `logs/events.ndjson`.
- Leaves the tmux session running after completion.

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | Demo completed successfully. |
| Non-zero | A step failed (e.g., tmux not available, jq not available). |

---

## lib/log.sh

**Purpose:** Shared logging library. Source this file — do not execute it directly.
Provides three functions that write to both stderr (human-readable) and
`logs/supervisor.log` (structured JSON).

**Usage:**
```bash
source "$(dirname "$0")/lib/log.sh"

log_info  "Session started"
log_warn  "openclaw not in PATH"
log_error "jq is required"
```

**Provides:**

| Function | Level | Description |
|----------|-------|-------------|
| `log_info  "msg"` | `INFO` | Informational progress messages |
| `log_warn  "msg"` | `WARN` | Non-fatal issues (degraded mode, skipped steps) |
| `log_error "msg"` | `ERROR` | Fatal errors (called before `exit 1`) |

**Environment variables:**

| Variable | Direction | Default | Notes |
|----------|-----------|---------|-------|
| `CC_PROJECT_DIR` | Read | `$(dirname "${BASH_SOURCE[0]}")/../..` resolved | Used to locate `logs/supervisor.log`. |

**Side effects:**
- Creates `logs/` directory if it does not exist.
- Appends one JSON line per call to `logs/supervisor.log`.
- Writes one human-readable line per call to stderr.
- Uses `jq` for JSON serialization when available; falls back to manual escaping.
