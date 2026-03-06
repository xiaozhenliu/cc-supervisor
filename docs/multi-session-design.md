# Multi-Session Technical Design

## Purpose

This document turns the next product requirement into an implementation plan.

Target feature:

1. Multi-session supervision
2. Multi-project concurrent supervision
3. No cross-talk between supervision instances

This is a development/design document, not a runtime guide.

## Status

Status as of 2026-03-07:

1. V1 runtime implementation completed
2. Default-instance backward compatibility preserved
3. Named-instance isolation implemented for tmux session, runtime files, queue, watchdog, poller, and hook bootstrap fallback
4. Registry-based instance/project resolution implemented
5. `cc-list` and `--id` targeting implemented for the main operator commands

Implemented artifacts:

1. `scripts/lib/runtime_context.sh`
2. instance-aware updates in startup/runtime scripts
3. basic multi-session regression coverage via `scripts/test-multi-session-runtime.sh`

Remaining follow-up work:

1. Expand real `claude + tmux + hook` integration coverage for concurrent named instances
2. Continue updating runtime-facing docs/examples that still describe only the default instance path

---

## Decision Summary

### Primary Decision

Introduce a first-class runtime identity: `CC_SUPERVISION_ID`.

All runtime resources that are currently single-instance must become instance-scoped through that identity:

1. tmux session name
2. event log
3. supervisor state
4. notification queue
5. watchdog pid / guard pid
6. poll pid
7. hook bootstrap fallback file

### Compatibility Decision

Backward compatibility is preserved through a reserved default instance:

1. If no instance is specified, the system uses `default`
2. Existing single-instance commands continue to work against `default`
3. Multi-session usage requires explicit instance selection for non-default instances

### Scope Decision for V1

V1 supports:

1. Multiple active supervision instances on one machine
2. Multiple different project directories at the same time

V1 does **not** support:

1. More than one active supervision instance for the exact same `CLAUDE_WORKDIR`

This restriction is intentional in V1 because Hook fallback recovery is otherwise ambiguous.

---

## Current Single-Instance Assumptions

The current implementation hard-codes one supervision loop in several places:

### 1. Fixed tmux session name

The following scripts assume `cc-supervise`:

1. `scripts/supervisor_run.sh`
2. `scripts/cc_send.sh`
3. `scripts/cc_capture.sh`
4. `scripts/cc-watchdog.sh`
5. `scripts/cc-poll.sh`
6. `scripts/on-cc-event.sh`
7. several tests and diagnostics

### 2. Shared runtime files under one `logs/` root

The following are currently shared globally:

1. `logs/events.ndjson`
2. `logs/supervisor-state.json`
3. `logs/notification.queue`
4. `logs/watchdog.pid`
5. `logs/watchdog-guard.pid`
6. `logs/poll.pid`
7. `logs/hook.env`

### 3. Implicit targeting in operator commands

Commands such as `cc-send`, `cc-capture`, and queue/watchdog helpers currently assume there is only one live instance to talk to.

### 4. Hook fallback assumes a single active bootstrap file

`scripts/on-cc-event.sh` currently knows only one fallback file:

1. `logs/hook.env`

That model cannot distinguish concurrent supervision instances.

---

## Goals

### Functional Goals

1. Start and supervise two or more projects concurrently
2. Route operator actions to the intended supervision instance
3. Keep Hook events and runtime state isolated per instance
4. Preserve current single-instance behavior when no explicit instance is selected

### Operational Goals

1. Deterministic instance resolution
2. Clear diagnostics when routing or targeting fails
3. Minimal surprise for existing users

---

## Non-Goals

The following are out of scope for V1:

1. Distributed supervision across machines
2. Shared multi-user coordination
3. Advanced scheduling or session pooling
4. Concurrent supervision of the same project directory
5. Redesign of the relay/auto product model

---

## Runtime Model

### 1. Core Identity

Introduce:

1. `CC_SUPERVISION_ID`

Rules:

1. Must be non-empty
2. Must be shell/path safe after sanitization
3. Reserved value `default` keeps backward compatibility
4. Must be unique among active supervision instances

Suggested normalization:

1. lowercase
2. allow `[a-z0-9._-]`
3. replace other characters with `-`

---

### 2. tmux Session Naming

Replace the fixed session name with:

1. `cc-supervise` for `default`
2. `cc-supervise-<supervision_id>` for named instances

Examples:

1. `default` → `cc-supervise`
2. `webapp` → `cc-supervise-webapp`
3. `client-a` → `cc-supervise-client-a`

This preserves current operator habits for the default path while making concurrent sessions unambiguous.

---

### 3. Runtime Directory Layout

### Reserved Default Instance

Keep the current layout for `default`:

1. `logs/events.ndjson`
2. `logs/supervisor-state.json`
3. `logs/notification.queue`
4. `logs/watchdog.pid`
5. `logs/watchdog-guard.pid`
6. `logs/poll.pid`
7. `logs/hook.env`

### Named Instances

Named instances move to:

1. `logs/instances/<supervision_id>/events.ndjson`
2. `logs/instances/<supervision_id>/supervisor-state.json`
3. `logs/instances/<supervision_id>/notification.queue`
4. `logs/instances/<supervision_id>/watchdog.pid`
5. `logs/instances/<supervision_id>/watchdog-guard.pid`
6. `logs/instances/<supervision_id>/poll.pid`
7. `logs/instances/<supervision_id>/hook.env`

### Shared Registry Area

Introduce shared metadata files under `logs/registry/`:

1. `logs/registry/supervisions.json`
2. `logs/registry/projects.json`

Purpose:

1. instance discovery
2. project-to-instance mapping
3. status inspection
4. conflict detection

---

### 4. Registry Model

### `supervisions.json`

Each active or recently known instance should record:

1. `supervision_id`
2. `tmux_session`
3. `project_dir`
4. `runtime_dir`
5. `mode`
6. `status`
7. `started_at`
8. `updated_at`
9. `openclaw_session_id`
10. `claude_session_id` when known

### `projects.json`

Map canonical project paths to active supervision instances.

V1 rule:

1. one canonical `project_dir` maps to at most one active `supervision_id`

If a second instance tries to supervise the same project path, startup must fail with an explicit message instead of guessing.

---

### 5. Shared Runtime Resolution Helper

Add a shared helper library, for example:

1. `scripts/lib/runtime_context.sh`

It should become the only place that knows:

1. how to normalize `CC_SUPERVISION_ID`
2. how to derive tmux session name
3. how to derive runtime file paths
4. how to read/write registry metadata
5. how to resolve the effective target instance from CLI flags or environment

Representative helper functions:

1. `resolve_supervision_id`
2. `supervision_tmux_session`
3. `supervision_runtime_dir`
4. `supervision_events_file`
5. `supervision_queue_file`
6. `supervision_state_file`
7. `register_supervision`
8. `unregister_supervision`
9. `resolve_project_supervision`

The key design rule is:

1. no script should build instance paths ad hoc once this helper exists

---

## Hook Design

### 1. Runtime Environment Export

`scripts/supervisor_run.sh` must export the following into the tmux session:

1. `CC_SUPERVISION_ID`
2. `CC_TMUX_SESSION`
3. `CC_RUNTIME_DIR`
4. `CC_EVENTS_FILE`
5. `CC_SUPERVISOR_STATE_FILE`
6. `CC_NOTIFICATION_QUEUE_FILE`
7. `CC_HOOK_ENV_FILE`

This keeps Hook callbacks instance-aware when environment inheritance works normally.

### 2. Hook Bootstrap Fallback

Each supervision instance writes its own bootstrap file:

1. default: `logs/hook.env`
2. named instance: `logs/instances/<id>/hook.env`

`scripts/on-cc-event.sh` should resolve fallback in this order:

1. Use inherited `CC_SUPERVISION_ID` / `CC_RUNTIME_DIR` if present
2. Otherwise, resolve by canonical `CLAUDE_WORKDIR` or current working directory through `projects.json`
3. Load that instance's `hook.env`
4. Validate required keys
5. Consume and delete the fallback file after successful use

### 3. Why V1 Forbids Two Active Instances for the Same Project

If environment inheritance fails and two active instances point to the same project path, the Hook callback cannot know which instance bootstrap file it should load.

That ambiguity makes same-project concurrency unsafe in V1.

### 4. Optional Future Hardening

Once V1 is stable, the registry may record the Claude internal `session_id` after the first successful Hook event. That would enable stronger matching for later callbacks.

This is future hardening, not a V1 requirement.

---

## Command Model

### 1. Instance Targeting

The following commands should accept explicit instance selection:

1. `cc-start`
2. `cc-supervise`
3. `cc-send`
4. `cc-capture`
5. `cc-flush-queue`
6. diagnostics and future list/status helpers

Recommended interface:

1. `--id <supervision_id>`
2. fallback to `CC_SUPERVISION_ID`
3. fallback to `default`

### Example Behavior

1. `cc-supervise ~/Projects/a` → starts or reuses `default`
2. `cc-supervise --id api ~/Projects/api` → starts or reuses `api`
3. `cc-send --id api "run tests"` → targets only `api`
4. `cc-capture --id api --tail 20` → captures only `api`

### 2. Diagnostics

Add a lightweight instance discovery command, for example:

1. `cc-list`

It should show:

1. `supervision_id`
2. tmux session name
3. project directory
4. mode
5. status
6. last update timestamp

This is important because multi-session operation is otherwise difficult to debug.

---

## Script-Level Change Plan

### Phase A: Shared Context Layer

Update or introduce shared helpers first:

1. `scripts/lib/runtime_context.sh`
2. `scripts/lib/log.sh`
3. `scripts/lib/supervisor_state.sh`

`log.sh` should become instance-aware so logs clearly identify which supervision instance emitted a line.

### Phase B: Startup / Registration

Update:

1. `scripts/cc-start.sh`
2. `scripts/supervisor_run.sh`
3. `scripts/install-hooks.sh`

Responsibilities:

1. resolve or validate `CC_SUPERVISION_ID`
2. reject same-project duplicate active supervision
3. register the instance
4. export instance-scoped environment into tmux
5. write the correct instance-scoped bootstrap file

### Phase C: Runtime Operation

Update:

1. `scripts/cc_send.sh`
2. `scripts/cc_capture.sh`
3. `scripts/on-cc-event.sh`
4. `scripts/cc-watchdog.sh`
5. `scripts/watchdog-guard.sh`
6. `scripts/flush-queue.sh`
7. `scripts/cc-poll.sh`
8. `scripts/handle-human-reply.sh`

Responsibilities:

1. resolve target instance
2. use instance-scoped paths
3. avoid global pid/queue/event collisions

### Phase D: Diagnostics and UX

Add or update:

1. `scripts/diagnose-routing.sh`
2. new `scripts/cc-list.sh` or equivalent
3. README/runtime docs after implementation stabilizes

### Phase E: Tests

Update:

1. real Hook integration tests
2. queue/watchdog tests
3. parser/execution tests where instance-aware paths are involved

Add:

1. two-project concurrent supervision test
2. same-project duplicate-start rejection test
3. per-instance queue isolation test
4. per-instance watchdog isolation test

---

## Backward Compatibility Rules

V1 must preserve the following:

1. Existing single-instance commands work unchanged
2. Existing default tmux session remains `cc-supervise`
3. Existing default runtime files remain under top-level `logs/`
4. Existing docs and habits remain valid for users who supervise only one project at a time

What changes:

1. advanced/concurrent usage requires explicit `--id`
2. diagnostics and runtime code must stop assuming there is only one session

---

## Failure Handling Rules

The implementation should fail closed in the following cases:

1. requested `--id` conflicts with an active instance bound to another project
2. project path is already supervised by another active instance
3. command targets a non-existent instance
4. Hook callback cannot deterministically resolve its runtime instance

Failure behavior should be explicit:

1. log the instance/project conflict
2. do not guess
3. do not silently route to `default`

---

## Suggested Rollout Sequence

1. Add the runtime helper and registry primitives
2. Convert startup flow to instance-aware registration
3. Convert send/capture/watchdog/queue paths
4. Convert Hook path and fallback logic
5. add `cc-list`
6. add concurrent regression tests
7. update runtime-facing docs

This order reduces the chance of partial multi-instance behavior with hidden cross-talk.

---

## Open Questions

These do not block V1, but should be decided during implementation:

1. Whether `--id` should be required for every non-default concurrent session or whether project-derived IDs should be auto-generated
2. Whether inactive registry entries should be retained for history or removed immediately
3. Whether default-instance top-level files should remain physical files forever or later become compatibility shims
4. Whether `cc-list` should show only active instances or also stale/broken ones

---

## Recommendation

Implement V1 with the simplest safe rule set:

1. one active supervision per project path
2. explicit `--id` for any non-default concurrent instance
3. default instance keeps current behavior
4. shared helper owns all runtime path/session derivation

That gives the project safe concurrency without forcing an immediate full redesign of the supervisor model.
