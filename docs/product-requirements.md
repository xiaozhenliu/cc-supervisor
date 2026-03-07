# Product Requirements

## Purpose

This document records the currently confirmed product priorities for `cc-supervisor`.

It is a development document, not a runtime guide. Its goal is to prevent the team from mixing:

1. Already-accepted product tradeoffs
2. The next feature to implement
3. Product issues that should be revisited later

---

## Current Product Position

`cc-supervisor` is an event-driven supervisor for Claude Code. Its current product goal is:

1. Keep the supervision loop stable and deterministic
2. Minimize unnecessary OpenClaw token usage while idle
3. Preserve clear safety boundaries between human judgment and automated forwarding

The following points are treated as confirmed product decisions, not current defects:

1. Real end-to-end closed-loop verification has already been executed multiple times in practice; documentation may lag behind reality
2. First-time directory trust confirmation remains a required human action for safety boundary and operator accountability
3. `auto` mode is intentionally simplified; it only handles low-risk automation and does not need to become a general decision-maker
4. Feishu and other channel expansion are not part of the immediate roadmap

---

## Next Feature: Multi-Session / Multi-Project Concurrent Supervision

### Problem Statement

The current implementation is effectively single-instance:

1. Many scripts assume a fixed tmux session name
2. Runtime logs and state are organized around a single default supervision instance
3. Human/operator actions can become ambiguous once multiple supervised projects exist at the same time

This is now the highest-priority product gap.

### Product Goal

Support supervising multiple Claude Code sessions concurrently without cross-talk.

### Success Criteria

The feature is complete only when all of the following are true:

1. Two or more projects can be supervised at the same time
2. Each supervision instance has an isolated runtime context
3. Human replies and OpenClaw replies are routed to the correct supervision instance
4. Hook events, capture output, watchdog alerts, and supervisor preferences do not leak across instances
5. Existing single-instance usage remains backward compatible by default

### Scope

The first implementation should focus on single-user, same-machine concurrency only.

Included:

1. Multiple tmux supervision sessions on one machine
2. Per-instance logs, state, and watchdog lifecycle
3. Per-instance command targeting
4. Backward-compatible default instance behavior

Not included in the first implementation:

1. Cross-machine coordination
2. Shared multi-user scheduling
3. Session pools or advanced orchestration
4. New notification channels
5. More than one active supervision instance for the same project directory

### Functional Requirements

1. Introduce a stable supervision identity, such as `supervision_id`
2. Derive tmux session name from that identity instead of assuming one fixed session
3. Derive runtime paths from that identity:
   - event log
   - supervisor state
   - queue file
   - watchdog pid / guard pid
4. Make all operator-facing commands target a specific instance explicitly or via a default-resolution rule
5. Ensure Hook callbacks can resolve the correct runtime instance for writes and notifications
6. Keep the current default flow working when no explicit instance selector is provided
7. Reject ambiguous same-project concurrent startup instead of guessing

### Operational Requirements

1. Instance targeting must be deterministic, not heuristic by "most recent" behavior
2. Error messages must include enough instance context for debugging
3. Diagnostics must be able to show which supervision instances are running and which project each instance belongs to
4. Recovery operations must be instance-scoped rather than global where possible

### Main Risks

1. Message routing cross-talk between two live supervision loops
2. Hook events writing into the wrong runtime directory
3. Watchdog processes monitoring the wrong tmux session
4. Old single-instance assumptions surviving in helper scripts and tests

---

## Immediate Development Actions

The next implementation cycle should follow this order:

1. Define the runtime identity model:
   - choose `supervision_id`
   - define naming rules for tmux session and runtime directories
2. Inventory all single-instance assumptions:
   - fixed tmux session name
   - fixed `logs/` file paths
   - scripts that implicitly target the only running session
3. Refactor runtime path/session resolution behind shared helpers
4. Update the main operator commands to accept instance selection while preserving current defaults
5. Update Hook and watchdog flows to become instance-aware
6. Add regression coverage for at least two concurrent supervised projects
7. Add a small operator-facing diagnostic/list command or equivalent inspection path
8. Only after concurrency is stable, update README and runtime docs to teach the new model

Technical design for this feature lives in `docs/multi-session-design.md`.

---

## Future Product Issues

These items are important, but not the next feature.

### 1. Documentation Drift

The product already has a history where real verification status moved faster than docs. Future process should reduce this drift, especially for:

1. What has been validated in real end-to-end use
2. What is a tested guarantee versus a documented plan
3. Which limitations are current facts versus old assumptions

### 2. Stronger Completion Verification

Current completion verification is intentionally lightweight. In the future, the product should consider stronger completion evidence, for example:

1. Structured completion markers
2. File-change evidence
3. Automated test/result evidence
4. Better separation between "Claude says done" and "supervisor can verify done"

This is a future product hardening item, not an immediate roadmap commitment.

### 3. More Granular Automation Policy

The current split between relay/manual control and simplified `auto` mode is acceptable for now. A future version may need:

1. More granular permission classes
2. More explicit allow/deny automation policies
3. Better operator-tunable automation boundaries

This should be treated as a policy product decision, not an implementation detail.

### 4. Channel Expansion

Support for additional delivery channels such as Feishu can be added later, but it is not currently a product priority.

### 5. Operator Experience at Higher Scale

Once multi-session support exists, future product work may need to address:

1. Instance discovery and listing UX
2. Better per-instance summaries
3. Faster interruption/resume operations across many running sessions
4. Cleaner status reporting for long-lived supervision

---

## Out of Scope for the Current Step

The following are explicitly not the next action right now:

1. Replacing the human trust gate for first-time project trust
2. Turning `auto` mode into a broad autonomous agent policy engine
3. Expanding notification channels before core concurrency is stable
4. Redesigning the product around distributed supervision
