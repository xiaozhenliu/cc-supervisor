# Changelog

All notable changes to cc-supervisor will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Replaced the old free-form forwarding boundary with an explicit `cc` prefix protocol for human replies
  - Only messages starting with `cc` are forwarded to Claude Code
  - All other messages stay on the supervisor side unless they match explicit supervisor commands (`cmd继续`, `cmd停止`, `cmd检查`, `cmd退出`)
- Added `scripts/parse-human-command.sh` to turn raw human messages into deterministic JSON actions
- Added `scripts/handle-human-reply.sh` as the Phase 3 execution gate, so fixed actions are executed by script instead of re-decided by the agent

### Added
- `scripts/test-human-command-parser.sh` to verify `cc` forwarding, shortcuts, empty-body handling, and non-forward defaults
- `scripts/test-handle-human-reply.sh` to verify reply execution for forward/continue/pause/status/done/meta
- `scripts/lib/message_templates.sh` and `scripts/test-notification-template.sh` so Hook notifications consistently include the `cc` reply contract

### Fixed
- Fixed `CC_PROJECT_DIR` fallback command substitution in startup scripts to avoid path resolution failures when running directly from the repository
  - `scripts/cc-start.sh`
  - `scripts/supervisor_run.sh`
- Unified Session ID policy across scripts/docs: no random UUID fallback, require active OpenClaw session ID
  - Updated command checks (`scripts/check-commands.sh`)
  - Updated manual guidance (`scripts/get-session-id.sh`)
  - Updated preflight docs (`docs/preflight-checks.md`)
- Hardened notification channel behavior for unsupported channels: queue with explicit warning instead of silent Discord fallback
  - `scripts/lib/notify.sh`

### Documentation
- Replaced dead links in core docs with existing references
  - `README.md`, `README_en.md`, `docs/README.md`
  - `scripts/diagnose-routing.sh`, `scripts/test-session-routing.sh`
- Updated OpenClaw integration reference to match current routing behavior (`--deliver` + `--reply-channel` + optional `--reply-to`)
  - `docs/openclaw-reference.md`
- Aligned file organization and installer excludes with current repository contents
  - `FILE_ORGANIZATION.md`, `install.sh`, `scripts/install-skill.sh`

## [1.1.0] - 2026-03-07

### Added

- Added first-class multi-session runtime identity via `CC_SUPERVISION_ID`
- Added `scripts/lib/runtime_context.sh` to centralize supervision ID normalization, tmux naming, runtime path derivation, and registry resolution
- Added shared registry files under `logs/registry/` for instance discovery and project binding
- Added `scripts/cc-list.sh` to inspect known supervision instances
- Added `scripts/test-multi-session-runtime.sh` for basic multi-session regression coverage

### Changed

- `cc-start`, `supervisor_run`, `cc-send`, `cc-capture`, `flush-queue`, `diagnose-routing`, and `handle-human-reply` now support instance targeting with `--id`
- Runtime files for named instances now live under `logs/instances/<supervision_id>/...` while `default` keeps the top-level `logs/` layout
- Hook callback resolution is now instance-aware and uses inherited runtime context or project registry lookup instead of assuming a single global `logs/hook.env`
- Watchdog, poll daemon, queue handling, structured logs, and supervisor state are now isolated per supervision instance
- Startup now rejects ambiguous V1 cases where a second active supervision targets the same canonical project path

### Documentation

- Updated `docs/multi-session-design.md` with implementation status
- Updated `README.md`, `README_en.md`, `docs/TROUBLESHOOTING.md`, `docs/phase-1.md`, and `docs/phase-4.md` for multi-instance usage and diagnostics

## [1.0.3] - 2026-03-07

### Added

- Added a stable regression entrypoint: `scripts/test-regression.sh`
- Added minimal real-hook integration fixtures:
  - `example-project/`
  - `tests/fixtures/bin/openclaw`
- Added first-phase real Claude Hook integration tests:
  - `scripts/test-real-claude-hook-post-tool-use.sh`
  - `scripts/test-real-claude-hook-notification.sh`
  - `scripts/test-real-claude-hook-stop.sh`
  - `scripts/test-real-claude-hook-session-end.sh`
  - `scripts/test-install-layout.sh`
- Added second-phase exception-path tests:
  - `scripts/test-notification-queue-fallback.sh`
  - `scripts/test-install-hooks-failure.sh`

### Changed

- `scripts/on-cc-event.sh` now generates a fallback `event_id` when Claude Hook payloads omit it
- `scripts/supervisor_run.sh` now explicitly passes `PATH` and `OPENCLAW_*` runtime variables into tmux sessions
- `scripts/lib/notify.sh` now supports `OPENCLAW_BIN` so tests and constrained environments can pin the `openclaw` executable
- `scripts/install-skill.sh` now keeps runtime docs required by `SKILL.md` while still excluding development-only docs

### Documentation

- Added `docs/TROUBLESHOOTING.md`
- Updated `README.md`, `README_en.md`, and `docs/real-claude-hook-test-plan.md` to document the new regression path, current Notification-test status, and the real PostToolUse coverage/semantics

## [1.0.2] - 2026-03-07

### Changed

- **Supervisor protocol aligned with implementation**:
  - `auto` mode no longer documents an implicit test → commit → merge pipeline
  - completion now flows through Phase 4 verification instead of the old L6/L7 terminal model
  - human simple replies (`y/n/1/2/Enter`) are now first-class documented inputs
- **Meta-instruction persistence documented and implemented**:
  - added `logs/supervisor-state.json` as the persisted supervisor preference store
  - documented review-gate and auto-continue preferences for `auto` mode
- **Startup confirmation clarified**:
  - non-interactive `auto` mode now requires explicit `CC_AUTO_MODE_CONFIRMED=yes`

### Documentation

- Updated `README.md` and `README_en.md` to reflect `openclaw agent --session-id ... --deliver`
- Updated phase docs and mode docs to match the reduced low-risk auto state machine
- Archived outdated agent hierarchy design documents under `docs/archive/`

## [1.0.1] - 2026-03-04

### Changed

- **Auto mode state-machine hardening docs**: Added three explicit hard rules to prevent supervision loop stalls
  - Only L6/L7 terminate a supervision round; L1/L2/L3/L4/L5 return to `WAIT_EVENT`
  - L4 → L5 requires explicit `TEST_PASS` marker
  - L5 succeeds only when commit + merge + post-merge tests all pass; otherwise route to L7
- **Transition clarity**: Added concise state transition tables (`from/to/guard`) to reduce ambiguity in execution behavior
  - Updated in `docs/auto-mode.md`
  - Updated in `docs/DESIGN_DECISIONS.md`

## [1.0.0] - 2026-03-03

### Changed - Major Documentation Restructure

**BREAKING**: SKILL.md structure significantly changed. Agents must adapt to new documentation layout.

- **SKILL.md drastically simplified**: 536 lines → 219 lines (59% reduction)
  - Removed verbose examples and redundant explanations
  - Phases now reference external detailed guides
  - Mode-specific logic moved to separate files

- **Modular documentation architecture**: Content split into focused, on-demand files
  - `docs/phase-0.md` - Phase 0: Gather inputs
  - `docs/phase-1.md` - Phase 1: Start (automated)
  - `docs/phase-2.md` - Phase 2: Send initial task
  - `docs/phase-3.md` - Phase 3: Notification loop
  - `docs/phase-4.md` - Phase 4: Verify and report
  - `docs/relay-mode.md` - Relay mode detailed guide
  - `docs/auto-mode.md` - Auto mode detailed guide

- **Agent workflow optimization**: Read SKILL.md for overview, then load phase details as needed
  - Reduces initial cognitive load
  - Enables step-by-step execution
  - Each phase document includes "Next Step" pointer

### Fixed

- **Session ID resolution**: `find-active-session.sh` now correctly matches sessions using `OPENCLAW_AGENT_ID` + `OPENCLAW_CHANNEL` + `OPENCLAW_TARGET`
  - Previous: Used "most recent session" heuristic (unreliable)
  - Now: Precise matching against `deliveryContext.channel` and `deliveryContext.to`
  - Requires `OPENCLAW_AGENT_ID` to be set (no default value)
  - Prevents wrong session selection in multi-agent scenarios

- **Installation script**: Updated to include new documentation files
  - Excludes only development docs (DESIGN_DECISIONS.md, ARCHITECTURE.md, etc.)
  - Includes all required phase and mode guides
  - Added `docs/README.md` to document which files are required

### Documentation

- Added `docs/README.md`: Documents which files are required vs development-only
- Simplified sections: Stop event classification, Other notification types, Role Check, Command Execution Context
- Removed redundant key name listings and verbose examples

## [0.9.0] - 2026-03-03

### Added
- **Flexible agent hierarchy**: Agents can now dynamically identify their role without hardcoded IDs
  - New environment variable: `CC_SUPERVISOR_ROLE`
    - Unset: Agent can invoke cc-supervisor skill
    - `supervisor`: Agent is executing supervision, cannot invoke skill again (prevents recursion)
  - Any agent can invoke the skill (main, ruyi, custom agents)
  - Supervisor state is set automatically when skill is invoked
  - Recursion prevention: Supervising agents cannot call cc-supervisor again
  - Files changed: `SKILL.md`, `supervisor_run.sh`, `logs/hook.env`

- **Forced session ID validation**: Entry scripts now require valid OPENCLAW_SESSION_ID before any operations
  - New script: `find-active-session.sh` - queries OpenClaw session store for active sessions
  - Session ID obtained from active sessions, NEVER auto-generated
  - Validation happens at script entry, before preflight/hooks/tmux
  - Strict UUID format validation
  - Clear error messages when session not found
  - Files changed: `cc-start.sh`, `supervisor_run.sh`

### Fixed
- **Hook session routing**: Clarified that hooks should notify the **caller** (supervisor agent), not Claude Code's internal session
  - Root cause: Confusion between two different session IDs:
    - `OPENCLAW_SESSION_ID` (env var) = caller's session (main/ruyi agent) ✓ Use this
    - `session_id` (hook JSON) = Claude Code's internal session ✗ Don't use for routing
  - Solution: Hook uses `OPENCLAW_SESSION_ID` environment variable to notify the caller
  - Changes:
    - `on-cc-event.sh`: Uses `OPENCLAW_SESSION_ID` (caller's session) for notifications
    - `supervisor_run.sh`: Writes `logs/hook.env` with caller's session ID for reliability
    - `on-cc-event.sh`: Auto-sources `logs/hook.env` if environment variables are missing
  - Architecture: Primary agent → Supervisor agent → cc-supervisor skill → Claude Code (tool)
  - Hook notifications flow: Claude Code → Supervisor agent → (Supervisor decides) → Primary agent
  - Impact: Notifications now correctly route to the skill caller (supervisor agent), not to Claude Code's internal session

- **Preflight check session ID validation**: Removed meaningless auto-generation of random session IDs
  - Previous behavior: When `OPENCLAW_SESSION_ID` was unavailable, preflight check would generate a random UUID
  - Problem: Random session IDs cannot deliver notifications correctly
  - New behavior: Preflight check now fails with clear error message if session ID is unavailable
  - Files changed: `scripts/preflight-check.sh`

### Documentation
- Added `docs/agent-hierarchy.md`: Comprehensive architecture documentation explaining:
  - Claude Code is a tool, not an agent
  - Hook notification routing logic
  - Session ID disambiguation
  - Call flow examples
  - Troubleshooting guide
- Added `docs/flexible-agent-hierarchy.md`: Design document for flexible agent hierarchy
- Added `docs/flexible-hierarchy-examples.md`: Usage examples for different agent scenarios

## [0.8.0] - 2026-03-02

### Changed
- **auto mode redesign**: OpenClaw is now a strict state machine — no free-form content generation
  - Replaced ad-hoc Stop type handling with 7 explicit action chains (L1–L7)
  - Removed `Blocked` self-recovery logic (OpenClaw no longer generates technical suggestions)
  - `Complete` now triggers testing (L4) before reporting success, not direct Phase 4
  - Added explicit test→commit+merge→report pipeline: L4 → L5 → L6
  - `Question` and `Choice` unified into L3: select Claude's recommended option
  - `Blocked` now always escalates to human (L7) instead of retrying with suggestions

### Documentation
- `docs/DESIGN_DECISIONS.md`: Updated auto mode section with L1–L7 chain definitions and rationale

## [0.7.0] - 2026-03-02

### Added
- **Modular preflight check system**: New unified validation with independent, reusable scripts
  - `preflight-check.sh`: Orchestrator that calls independent validation scripts
  - `check-commands.sh`: Verify required commands (openclaw, tmux, jq, uuidgen)
  - `check-env.sh`: Check optional environment variables
  - `check-structure.sh`: Verify project structure
  - Auto-generates OPENCLAW_SESSION_ID if not available
  - Clear error messages with installation instructions
- **Distinctive test notifications**: Test messages now include timestamps, session IDs, routing info, and emoji markers for easy verification
- Documentation: `docs/preflight-checks.md` explaining architecture and usage

### Changed
- **Session-based routing**: Notifications now query OpenClaw session metadata to determine source channel, ensuring messages return to the correct channel instead of webchat
  - `scripts/lib/notify.sh`: Added session metadata query functions
  - Always use `--deliver` and `--reply-channel` parameters
  - Fallback to environment variables if session metadata unavailable
- **cc-start.sh**: Now runs preflight checks at Step 0 before any other operations
- **SKILL.md**: Simplified workflow - Phase 0 collects inputs, Phase 1 handles all checks internally
- **Agent autonomy**: Agent can now auto-generate session ID without human intervention

### Fixed
- Notification routing: Messages no longer incorrectly route to webchat when sent from Discord
- Session ID reliability: Proactive validation prevents "session ID not set" errors during execution

### Documentation
- `docs/preflight-checks.md`: Preflight check architecture and usage
- `docs/openclaw-reference.md`: OpenClaw routing parameters and integration notes
- Updated SKILL.md with clearer phase responsibilities

## [0.6.9] - Previous releases

See git history for earlier changes.
