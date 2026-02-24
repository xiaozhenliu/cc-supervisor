# Architecture

## 1. System Overview

cc-supervisor wraps Claude Code in a tmux session and replaces manual polling with
Claude Code's built-in Hook system. When Claude Code finishes a turn or encounters a
notable event, a Hook fires `on-cc-event.sh`, which appends a structured record to
`logs/events.ndjson` and calls `openclaw send` to notify OpenClaw. OpenClaw then
decides the next action (send a follow-up prompt, notify a human, or wait). During
the idle period between turns, OpenClaw consumes zero tokens.

```
OpenClaw ── cc_send.sh (tmux send-keys) ──→ Claude Code (tmux: cc-supervise)
    ↑                                               │
    │                                      Hook fires on event
    │                          (Stop / PostToolUse / Notification / SessionEnd)
    │                                               │
    └─── openclaw send ←── on-cc-event.sh ──────────┘
                                  │
                     logs/events.ndjson   (append-only NDJSON)
                     logs/supervisor.log  (structured JSON, all scripts)

Human ── tmux attach -t cc-supervise ──→ observe / intervene at any time
```

---

## 2. Component Responsibilities

| Component | Role |
|-----------|------|
| `supervisor_run.sh` | Creates/reuses tmux session `cc-supervise`. Launches `claude` inside it. Exports `CC_PROJECT_DIR` into the session environment so Hook callbacks can resolve paths. Kills any stale watchdog and starts a fresh one. |
| `cc_send.sh` | Sends arbitrary text + Enter to the tmux session via `tmux send-keys -l` (the `-l` / literal flag prevents special characters from being interpreted by tmux). |
| `cc_capture.sh` | Snapshots the last N lines of the tmux pane via `capture-pane -p -S -N`. Used by `on-cc-event.sh` to build the Stop event summary. |
| `on-cc-event.sh` | The unified Hook callback. Reads JSON from stdin, deduplicates by `session_id + event_id`, appends a structured record to `events.ndjson`, and calls `openclaw send` for notification-worthy events. |
| `install-hooks.sh` | Substitutes `__HOOK_SCRIPT_PATH__` in `config/claude-hooks.json` with the absolute path of `on-cc-event.sh`, then deep-merges the result into `.claude/settings.local.json`, preserving all existing config. |
| `cc-watchdog.sh` | Background daemon that polls `events.ndjson` mtime every 30 seconds. If no new event arrives within `CC_TIMEOUT` seconds, it fires an `openclaw send` alert. Exits cleanly when the tmux session disappears or on SIGTERM/SIGINT. |
| `lib/log.sh` | Sourced (not executed) by all scripts. Provides `log_info`, `log_warn`, `log_error`. Each call writes a human-readable line to stderr and a structured JSON line to `logs/supervisor.log`. |

---

## 3. Data Flow — Full Event Lifecycle

The following trace covers a complete `Stop` event from prompt dispatch to OpenClaw notification.

```
1.  OpenClaw calls:
      cc_send.sh "implement feature X"

2.  cc_send.sh runs:
      tmux send-keys -t cc-supervise -l "implement feature X"
      tmux send-keys -t cc-supervise Enter
    → Claude Code receives the text as user input.

3.  Claude Code works: reads files, runs tools, writes output.
    Each tool use fires a PostToolUse Hook → on-cc-event.sh logs it (no notification
    unless isError=true).

4.  Claude Code finishes the turn → fires Stop Hook:
      on-cc-event.sh receives JSON on stdin:
        { "hook_event_name": "Stop", "session_id": "...", "event_id": "...",
          "transcript_path": "/path/to/transcript.json" }

5.  on-cc-event.sh deduplicates:
      grep events.ndjson for same session_id + event_id → not found, proceed.

6.  on-cc-event.sh builds summary:
      cc_capture.sh --tail 30 → last 30 pane lines (truncated to 1000 chars)
      fallback: read last assistant message from transcript_path

7.  on-cc-event.sh appends to events.ndjson:
      { "ts": "...", "event_type": "Stop", "session_id": "...",
        "event_id": "...", "summary": "<pane snapshot>" }

8.  on-cc-event.sh calls:
      openclaw send "[cc-supervisor] Stop: <summary>"

9.  OpenClaw receives notification, reads summary, decides:
      • Task incomplete → cc_send.sh "continue with Y"  (go to step 1)
      • Task complete  → notify human
      • Error detected → cc_send.sh "fix the error: ..." (go to step 1)
```

---

## 4. Hook Event Processing Logic

### Notification strategy per event type

| Event | `SHOULD_NOTIFY` | Summary source | Notes |
|-------|----------------|----------------|-------|
| `Stop` | Always | 1. `cc_capture.sh --tail 30` (truncated to 1000 chars) → 2. last assistant message from `transcript_path` → 3. hardcoded fallback string | Primary signal for OpenClaw to decide next step |
| `PostToolUse` | Only if `toolResult.isError == true` | Tool name + first 300 chars of `toolResult.content[0].text` | Normal tool use is logged only, not notified |
| `Notification` | Always | `.message` field from Hook JSON | Claude Code waiting for confirmation or input |
| `SessionEnd` | Always | Hardcoded string with `session_id` | Signals session closed; no further events expected |
| *(unknown)* | Never | Hardcoded string with event type | Defensive: log and continue |

### Deduplication

Before appending, `on-cc-event.sh` runs:
```bash
jq -r 'select(.session_id==$sid and .event_id==$eid) | .event_id' events.ndjson | head -1
```
If a match is found, the script exits 0 without appending or notifying. This prevents
double-firing if Claude Code retries a Hook callback.

### Graceful degradation

If `openclaw` is not in `$PATH`, all notification calls are skipped and a `WARN` line is
written to `supervisor.log`. The event is still appended to `events.ndjson`. The system
remains fully functional as a logging pipeline.

---

## 5. Environment Variables

| Variable | Set by | Default | Scope | Purpose |
|----------|--------|---------|-------|---------|
| `CC_PROJECT_DIR` | `supervisor_run.sh` (exported into tmux env); each script self-resolves as fallback | `$(cd "$(dirname "$0")/.." && pwd)` — absolute path | All scripts | Absolute path to the project root. Enables Hook callbacks to locate `logs/`, `scripts/`, and `config/` regardless of the working directory when invoked. |
| `CC_TIMEOUT` | Caller or `supervisor_run.sh` | `1800` | `cc-watchdog.sh`, `supervisor_run.sh` | Inactivity threshold in seconds before watchdog fires an alert. Set to a lower value (e.g. `60`) for testing. |
| `SESSION_NAME` | Hardcoded in each script | `cc-supervise` | All scripts that call `tmux` | Name of the tmux session. Not an env var by design — changing it requires editing the scripts. |

---

## 6. Log File Formats

### `logs/events.ndjson`

Append-only, one JSON object per line. Written by `on-cc-event.sh`.

```json
{
  "ts":         "2026-01-01T12:00:00Z",
  "event_type": "Stop",
  "session_id": "abc-123",
  "event_id":   "evt-456",
  "summary":    "last 30 lines of tmux pane or last assistant message (≤1000 chars)"
}
```

To query: `jq 'select(.event_type=="Stop")' logs/events.ndjson`

### `logs/supervisor.log`

Append-only, one JSON object per line. Written by `lib/log.sh` on every `log_*` call.

```json
{
  "ts":     "2026-01-01T12:00:00Z",
  "level":  "INFO",
  "script": "on-cc-event.sh",
  "msg":    "Received: type=Stop session=abc-123 event_id=evt-456"
}
```

Levels: `INFO`, `WARN`, `ERROR`. All levels also print a human-readable line to stderr.

To tail live: `tail -f logs/supervisor.log | jq .`
