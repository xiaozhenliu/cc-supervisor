# Troubleshooting

## No notifications arrive

1. Check `OPENCLAW_SESSION_ID` is set to a valid UUID from an active session.
2. Check `logs/notification.queue` for queued entries.
3. For named instances, check `logs/instances/<id>/notification.queue` instead.
4. Run `scripts/flush-queue.sh` after fixing routing or `openclaw` availability.
5. For named instances, use `scripts/flush-queue.sh --id <id>`.

## Hook callback did not log events

1. Check the target project's `.claude/settings.local.json` includes `Stop`, `PostToolUse`, `Notification`, and `SessionEnd`.
2. Check `logs/supervisor.log` for `Hook fallback` messages.
3. For named instances, inspect `logs/instances/<id>/supervisor.log`.
4. If inherited env is missing, ensure `logs/hook.env` exists for the first callback after startup.
5. For named instances, the fallback file is `logs/instances/<id>/hook.env`.

## Claude Code did not become ready

1. Attach with `tmux attach -t cc-supervise`.
2. For named instances, attach with `tmux attach -t cc-supervise-<id>`.
3. If Claude asks to trust the directory, confirm it manually and detach.
4. Re-run startup after clearing stale sessions with `tmux kill-session -t cc-supervise` or `tmux kill-session -t cc-supervise-<id>`.

## Cannot start a second supervision for the same project

1. V1 intentionally forbids more than one active supervision instance for the same canonical project path.
2. Run `scripts/cc-list.sh` to see which instance currently owns that project.
3. Stop the existing tmux session first, then start the new instance.

## Notifications go to the wrong channel

1. Check `OPENCLAW_TARGET` and `OPENCLAW_CHANNEL`.
2. Verify the session store still contains the expected routing metadata.
3. Run `scripts/test-session-routing.sh "$OPENCLAW_SESSION_ID"` to inspect inferred routing.
