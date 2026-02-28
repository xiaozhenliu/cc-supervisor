# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.4] - 2026-02-28

### Added
- `scripts/get-session-id.sh` — reliable session ID getter with 3-tier fallback (existing env var → openclaw CLI → generate new) and UUID format validation
- `scripts/verify-session-id.sh` — session ID verification script that validates format, tests message delivery, and compares with current OpenClaw session

### Changed
- Phase 0 — now uses `get-session-id.sh` and `verify-session-id.sh` to ensure correct session ID before starting supervision
- Phase 3.5 — added session ID re-verification before sending test message; troubleshooting steps now include checking for wrong-session routing

### Fixed
- Session ID mismatch issues — new verification scripts catch incorrect session IDs in Phase 0, preventing messages from routing to wrong sessions or default channel
- Session ID format validation — now validates UUID v4 format before use

## [0.7.3] - 2026-02-28

### Added
- Phase 3.5 — Hook notification verification step after Claude Code starts; sends test message to verify Hook routing works before sending real task; includes 30-second timeout and troubleshooting steps if verification fails

### Changed
- `SKILL.md` — simplified from 528 lines to 287 lines (-46%) to improve model compliance; condensed verbose explanations while preserving all critical information and standard format

### Fixed
- Session ID routing issues — new verification phase catches Hook notification failures early, preventing wasted time on tasks that can't receive notifications

## [0.7.2] - 2026-02-28

### Added
- `docs/AUTONOMOUS_DECISION_RULES.md` — comprehensive autonomous mode decision rules in English; defines when to auto-approve vs escalate, with detailed decision trees for all Stop event types
- `docs/自主决策规则总结.md` — Chinese quick reference for autonomous decision rules with common examples
- `docs/UPGRADE_GUIDE.md` — upgrade guide from v0.7.1 to v0.7.2 with verification steps

### Changed
- **BREAKING**: Autonomous mode now fully autonomous — all programming operations (create/delete files, install deps, modify configs, commit, push, API calls) are auto-approved; escalation only on missing external info, repeated failures (3x), or system errors
- `SKILL.md` — autonomous mode section rewritten with "fully autonomous" principles; default answer is `y` for all yes/no questions; escalation conditions drastically reduced
- `SKILL.md` — trigger rules strengthened with "MANDATORY", "MUST", "IMMEDIATELY" keywords to prevent agent from forgetting to use skill
- `SKILL.md` — description updated to emphasize mandatory usage and failure without skill
- `PRD.md` — autonomous mode description updated to reflect full autonomy and safety via sandboxing
- Round limits increased: total rounds 20→30, consecutive "Please continue" 5→8, watchdog triggers 2→3

### Fixed
- Autonomous mode over-escalation — agent no longer escalates for "risky" operations like delete, commit, push; safety ensured by sandboxing, not interactive confirmations

## [0.7.1] - 2026-02-25

### Fixed
- `scripts/on-cc-event.sh`, `scripts/cc-watchdog.sh`, `scripts/cc-poll.sh`,
  `scripts/flush-queue.sh` — remove `--agent` from `openclaw agent` calls;
  `--agent` and `--session-id` conflict when used together, causing notifications
  to route to the wrong session; now only `--session-id` is used
- `OPENCLAW_ACCOUNT` no longer required — `OPENCLAW_SESSION_ID` is the sole
  required variable for notification routing
- `SKILL.md` — Notification Routing, Phase 0, Phase 3, One-Time Setup, and
  Troubleshooting updated to remove `OPENCLAW_ACCOUNT` dependency

### Changed
- All documentation updated for v0.7.0 polling feature: `PRD.md`,
  `EXECUTION_PLAN.md`, `CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/SCRIPTS.md`,
  `example-project/E2E_TEST.md`

## [0.7.0] - 2026-02-25

### Added
- `scripts/cc-poll.sh` — proactive terminal polling daemon; periodically captures
  tmux pane output via `cc-capture` and sends `[cc-supervisor][poll]` snapshots to
  the agent, filling visibility gaps between Hook events during long-running tools
- `CC_POLL_INTERVAL` env var — minutes between poll snapshots (default: `15`,
  range: `3`–`1440`; set to `0` to disable)
- `CC_POLL_LINES` env var — terminal lines to capture per poll (default: `40`)
- `scripts/supervisor_run.sh` — forward `CC_POLL_INTERVAL` and `CC_POLL_LINES`
  into tmux session; start/stop poll daemon alongside watchdog
- `SKILL.md` — Phase 0: document optional poll configuration; Phase 3: add
  disable-polling example; Phase 5: add poll notification handling rule;
  Trigger Rules: add `poll` event type

## [0.6.15] - 2026-02-25

### Fixed
- `scripts/on-cc-event.sh`, `scripts/cc-watchdog.sh`, `scripts/flush-queue.sh` —
  use `--session-id` instead of `--channel` for `openclaw agent` calls; Hook
  callbacks now route notifications back to the exact agent session that started
  supervision, preserving full conversation context
- `scripts/supervisor_run.sh` — forward `OPENCLAW_SESSION_ID` into tmux session
  and watchdog process
- `SKILL.md` — `OPENCLAW_SESSION_ID` replaces `OPENCLAW_CHANNEL` as required
  variable; agent sets it at runtime from its own session; `OPENCLAW_CHANNEL`
  demoted to optional (reply delivery only)

## [0.6.14] - 2026-02-25

### Added
- `SKILL.md` — add Trigger Rules section: agent MUST read SKILL.md and follow
  Phase 5 when receiving any message starting with `[cc-supervisor]`; ensures
  reliable skill invocation from Hook event notifications
- `SKILL.md` — Phase 0: clarify `OPENCLAW_CHANNEL` is the channel this
  conversation is on (agent knows it, do not ask human)

## [0.6.13] - 2026-02-25

### Fixed
- `SKILL.md` — add `[cc-supervisor]` message prefix as a skill trigger condition
  in the description; agent now auto-loads this skill when receiving Hook event
  notifications, enabling it to execute Phase 5 logic without manual invocation

## [0.6.12] - 2026-02-25

### Fixed
- `scripts/on-cc-event.sh`, `scripts/cc-watchdog.sh`, `scripts/flush-queue.sh` —
  add `--channel` to `openclaw agent` call; `--channel` derives the session key
  so all Hook callbacks land in the same agent session and preserve context
- `SKILL.md` — `OPENCLAW_CHANNEL` restored as required variable; `OPENCLAW_TARGET`
  is optional (controls `--deliver` reply routing only)

## [0.6.11] - 2026-02-25

### Fixed
- `scripts/on-cc-event.sh`, `scripts/cc-watchdog.sh`, `scripts/flush-queue.sh` —
  replace `openclaw message send` with `openclaw agent --agent <name> --message`
  so Hook events actually trigger an agent turn instead of just posting a chat
  message; `OPENCLAW_ACCOUNT` is now the only required variable
- `SKILL.md` — Notification Routing section rewritten to reflect `openclaw agent`
  semantics; `OPENCLAW_ACCOUNT` marked as required, `OPENCLAW_CHANNEL`/`TARGET`
  as optional reply-delivery params; Phase 0 and One-Time Setup updated accordingly

## [0.6.10] - 2026-02-25

### Added
- `SKILL.md` — OpenClaw Behavior Rules section: act first, no confirmations,
  minimal messages to human, no status updates, terse escalations; reduces
  agent verbosity and improves throughput

## [0.6.9] - 2026-02-25

### Added
- `scripts/cc_send.sh` — add `--key <keyname>` mode for sending special keys
  (Up, Down, Enter, y, n, 1, 2, etc.) without appending Enter; text mode
  unchanged
- `SKILL.md` — Phase 5: add cursor navigation as a Stop type; map each Stop
  type to the correct `cc-send` invocation; add cc-send reference block

## [0.6.8] - 2026-02-25

### Added
- `SKILL.md` — Phase 5 rewrite: define 6 Stop event types (task complete,
  yes/no, multiple choice, open question, blocked, in progress) with
  identification criteria and per-type handling rules
- relay mode: notify human for all Stop types, always wait for reply
- autonomous mode: self-handle all Stop types, escalate only when stuck
  or task complete; consolidate other notification types into single table

## [0.6.7] - 2026-02-25

### Fixed
- `scripts/on-cc-event.sh` — relay Stop notification now shows Claude Code's
  actual output instead of fabricated numbered options; human replies verbatim
- `SKILL.md` — relay mode: agent must ask for clarification if human reply is
  ambiguous, never guess intent

## [0.6.6] - 2026-02-25

### Added
- `scripts/on-cc-event.sh` — relay mode Stop notifications now include
  numbered reply options (1: continue, 2: done, 3: intervene)
- `SKILL.md` — document numbered reply protocol: reply format, human→action
  mapping table, and phase transition rules for each option

## [0.6.5] - 2026-02-25

### Fixed
- `SKILL.md` — Phase 0: explicitly list `OPENCLAW_CHANNEL`, `OPENCLAW_ACCOUNT`,
  `OPENCLAW_TARGET` as required before proceeding, with guidance on where to
  find them
- `SKILL.md` — Phase 3: show env var injection inline in startup commands so
  agent knows exactly what to set
- `SKILL.md` — clarify `OPENCLAW_ACCOUNT` is the sending agent's own name
  (e.g. `main`), not an arbitrary account ID

## [0.6.4] - 2026-02-25

### Fixed
- `scripts/on-cc-event.sh`, `scripts/cc-watchdog.sh` — add `OPENCLAW_ACCOUNT`
  support; pass `--account` to `openclaw message send` when set (required by
  some channels such as Discord)
- `scripts/flush-queue.sh` — extend queue format to include account field
- `scripts/supervisor_run.sh` — forward `OPENCLAW_ACCOUNT` into tmux session
  and watchdog process
- `SKILL.md` — document `OPENCLAW_ACCOUNT` in Notification Routing table

## [0.6.3] - 2026-02-24

### Added
- `SKILL.md` — Phase 1: agent checks shell aliases on every invocation;
  if `cc-supervise`/`cc-send`/`cc-install-hooks` are not found, agent
  prompts human to complete One-Time Machine Setup before proceeding
- Renumber workflow phases 1–5 → 2–6 to accommodate the new check

## [0.6.2] - 2026-02-24

### Fixed
- `scripts/supervisor_run.sh` — forward `OPENCLAW_CHANNEL` and `OPENCLAW_TARGET`
  into the tmux session via `-e` flags and into the watchdog process; Hook
  callbacks (`on-cc-event.sh`) now inherit these values automatically without
  any manual injection by the operator
- `SKILL.md` — Phase 0 clarifies that `OPENCLAW_CHANNEL`/`OPENCLAW_TARGET` are
  known to OpenClaw itself (not required from human); Phase 2 startup commands
  restored to clean form; Notification Routing section updated accordingly

## [0.6.1] - 2026-02-24

### Changed
- `SKILL.md` — full rewrite to skill-creator standard:
  - Add "When to Use This Skill" section
  - Unify language to English throughout
  - Merge Supervision Modes + Workflow into single Phase 0–5 flow with explicit Actor labels
  - Mark human action points with ⚠ and provide exact escalation message text
  - Move One-Time Machine Setup to bottom (human-only, not agent workflow)
  - Tighten frontmatter description to one actionable trigger sentence
  - Remove duplicate content between Quick Reference and Workflow
- `example-project/E2E_TEST.md` — added; step-by-step test guide for both relay and autonomous modes
- `.gitignore` — whitelist `example-project/E2E_TEST.md`

## [0.6.0] - 2026-02-24

### Added
- `scripts/flush-queue.sh` — retry script for queued notifications; reads
  `logs/notification.queue` line by line, retries `openclaw message send`,
  rewrites queue with only the still-failing entries; removes queue file on
  full success
- `cc-flush-queue` shell alias in `SKILL.md` and both READMEs
- Notification queue fallback in `on-cc-event.sh` and `cc-watchdog.sh`:
  writes to `logs/notification.queue` when `openclaw message send` fails or
  `openclaw` is not in PATH
- `## 通知配置` section in `SKILL.md` documenting Agent auto-injection vs
  human manual export of `OPENCLAW_CHANNEL` / `OPENCLAW_TARGET`
- 30-minute polling convention note in `SKILL.md` Step 3
- Two-mode comparison table in both READMEs (Agent automatic vs human manual)

### Fixed
- `on-cc-event.sh`: replaced broken `openclaw send` with
  `openclaw message send --channel $OPENCLAW_CHANNEL -t $OPENCLAW_TARGET -m $msg`;
  notification routing now via env vars `OPENCLAW_CHANNEL` / `OPENCLAW_TARGET`
- `cc-watchdog.sh`: same fix — `openclaw message send` with env var routing
  and queue fallback, consistent with `on-cc-event.sh`

### Changed
- Both READMEs and `SKILL.md` troubleshooting updated to reflect env var
  diagnostics and `cc-flush-queue` retry workflow
- Architecture diagrams updated: `openclaw send` → `openclaw message send`

## [0.5.0] - 2026-02-24

### Added
- **Phase 6 — Supervision Modes**: `CC_MODE` env var selects `relay` (default) or `autonomous`
  mode; `supervisor_run.sh` forwards `CC_MODE` into the tmux session environment
- **autonomous mode Stop notification**: includes `ACTION_REQUIRED: decide_and_continue`
  marker so OpenClaw can drive tasks without human confirmation after each turn
- `SKILL.md` — new `## Supervision Modes` section documenting both modes, usage examples,
  and notification format including `ACTION_REQUIRED`

### Changed
- **Phase 5 — Stop empty summary**: fallback text changed from
  `"(Claude Code finished a response turn)"` to `"[no content]"` (per PRD)
- **Phase 5 — events.ndjson schema**: added `tool_name` field; populated for `PostToolUse`
  events, `null` for all others
- **Notification prefix**: all `openclaw send` messages now include `[cc_mode]` tag,
  e.g. `[cc-supervisor][relay] Stop: ...` for easier log filtering
- `SKILL.md` — updated notification table and event log format examples to reflect new schema

## [0.4.0] - 2026-02-24

### Added
- `SKILL.md` (repo root) — standard ClawHub skill definition with YAML frontmatter:
  `name`, `description`, `version`, `metadata.openclaw` (emoji, `requires.bins`,
  `install` array for brew deps, `os` restriction); replaces `config/cc-supervisor-skill.md`

### Changed
- Install path changed from `~/tools/cc-supervisor` to `~/.openclaw/skills/cc-supervisor`
  (standard OpenClaw skill directory); `clawhub install cc-supervisor` is now the
  primary install method
- `README.md` / `README_en.md` — updated all paths to `~/.openclaw/skills/cc-supervisor/`,
  ClawHub as primary install method, shell aliases updated accordingly
- `docs/SCRIPTS.md` — updated `supervisor_run.sh` and `install-hooks.sh` usage examples
  to use `~/.openclaw/skills/cc-supervisor/` paths

### Removed
- `config/cc-supervisor-skill.md` — superseded by `SKILL.md` at repo root

## [0.3.0] - 2026-02-24

### Added
- `CLAUDE_WORKDIR` environment variable to `supervisor_run.sh` and `install-hooks.sh`,
  separating "where cc-supervisor lives" (`CC_PROJECT_DIR`) from "where Claude Code
  works" (`CLAUDE_WORKDIR`); defaults preserve all existing behaviour

### Changed
- `README.md` / `README_en.md` — expanded "在其他项目中使用 / Using with an Existing
  Project" section with full external-project commands, shell alias examples, OpenClaw
  skill install instructions, and uninstall steps; all in a single README, no separate
  install guide
- `docs/SCRIPTS.md` — updated `supervisor_run.sh` and `install-hooks.sh` entries to
  document `CLAUDE_WORKDIR`

## [0.2.0] - 2026-02-24

### Added
- `docs/ARCHITECTURE.md` — system design, component responsibilities, complete
  data-flow trace, Hook event processing logic, environment variables reference,
  and log file formats
- `docs/SCRIPTS.md` — per-script interface reference: arguments, environment
  variables (read/set), side effects, and exit codes for all 8 scripts
- `CHANGELOG.md` and `VERSION` file (`0.2.0`)
- `README_en.md` — English README mirroring the Chinese README structure

### Changed
- `README.md` — added version badge, Quick Start section (3-line install),
  and converted the doc cross-reference list to a linked table
- `scripts/install-hooks.sh` — target changed from `~/.claude/settings.json`
  (global) to `.claude/settings.local.json` (project-local, machine-specific);
  hooks are now scoped to this project only

## [0.1.0] - 2026-02-24

### Added
- `scripts/supervisor_run.sh` — create/reuse tmux session `cc-supervise`, launch
  Claude Code, export `CC_PROJECT_DIR`, start watchdog
- `scripts/cc_send.sh` — send text + Enter to Claude Code via `tmux send-keys -l`
- `scripts/cc_capture.sh` — snapshot tmux pane output for diagnostics
- `scripts/lib/log.sh` — shared structured JSON logging to `logs/supervisor.log`
- `tests/test_phase1.sh` — 10 integration tests for Phase 1 scripts (all passing)
- `scripts/on-cc-event.sh` — unified Hook callback: dedup by `session_id+event_id`,
  append to `events.ndjson`, notify OpenClaw; graceful degradation if `openclaw`
  not in PATH
- `scripts/install-hooks.sh` — idempotent deep-merge installer for Hook config
- `config/claude-hooks.json` — hook registration template with `__HOOK_SCRIPT_PATH__`
  placeholder
- `scripts/cc-watchdog.sh` — inactivity watchdog daemon; monitors `events.ndjson`
  mtime, alerts after `CC_TIMEOUT` seconds (default 30 min); PID-file managed
- `README.md` — user-facing documentation (Simplified Chinese)
- `config/cc-supervisor-skill.md` — OpenClaw skill definition (English)
- `scripts/demo.sh` — end-to-end demo using plain bash shell; no API or network
  required

[Unreleased]: https://github.com/OWNER/cc-supervisor/compare/v0.7.1...HEAD
[0.7.1]: https://github.com/OWNER/cc-supervisor/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/OWNER/cc-supervisor/compare/v0.6.15...v0.7.0
[0.6.15]: https://github.com/OWNER/cc-supervisor/compare/v0.6.14...v0.6.15
[0.6.14]: https://github.com/OWNER/cc-supervisor/compare/v0.6.13...v0.6.14
[0.6.13]: https://github.com/OWNER/cc-supervisor/compare/v0.6.12...v0.6.13
[0.6.12]: https://github.com/OWNER/cc-supervisor/compare/v0.6.11...v0.6.12
[0.6.11]: https://github.com/OWNER/cc-supervisor/compare/v0.6.10...v0.6.11
[0.6.10]: https://github.com/OWNER/cc-supervisor/compare/v0.6.9...v0.6.10
[0.6.9]: https://github.com/OWNER/cc-supervisor/compare/v0.6.8...v0.6.9
[0.6.8]: https://github.com/OWNER/cc-supervisor/compare/v0.6.7...v0.6.8
[0.6.7]: https://github.com/OWNER/cc-supervisor/compare/v0.6.6...v0.6.7
[0.6.6]: https://github.com/OWNER/cc-supervisor/compare/v0.6.5...v0.6.6
[0.6.5]: https://github.com/OWNER/cc-supervisor/compare/v0.6.4...v0.6.5
[0.6.4]: https://github.com/OWNER/cc-supervisor/compare/v0.6.3...v0.6.4
[0.6.3]: https://github.com/OWNER/cc-supervisor/compare/v0.6.2...v0.6.3
[0.6.2]: https://github.com/OWNER/cc-supervisor/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/OWNER/cc-supervisor/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/OWNER/cc-supervisor/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/OWNER/cc-supervisor/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/OWNER/cc-supervisor/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/OWNER/cc-supervisor/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/OWNER/cc-supervisor/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/OWNER/cc-supervisor/releases/tag/v0.1.0
