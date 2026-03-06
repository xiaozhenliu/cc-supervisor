# Troubleshooting

## No notifications arrive

1. Check `OPENCLAW_SESSION_ID` is set to a valid UUID from an active session.
2. Check `logs/notification.queue` for queued entries.
3. Run `scripts/flush-queue.sh` after fixing routing or `openclaw` availability.

## Hook callback did not log events

1. Check the target project's `.claude/settings.local.json` includes `Stop`, `PostToolUse`, `Notification`, and `SessionEnd`.
2. Check `logs/supervisor.log` for `Hook fallback` messages.
3. If inherited env is missing, ensure `logs/hook.env` exists for the first callback after startup.

## Claude Code did not become ready

1. Attach with `tmux attach -t cc-supervise`.
2. If Claude asks to trust the directory, confirm it manually and detach.
3. Re-run startup after clearing stale sessions with `tmux kill-session -t cc-supervise`.

## Notifications go to the wrong channel

1. Check `OPENCLAW_TARGET` and `OPENCLAW_CHANNEL`.
2. Verify the session store still contains the expected routing metadata.
3. Run `scripts/test-session-routing.sh "$OPENCLAW_SESSION_ID"` to inspect inferred routing.
