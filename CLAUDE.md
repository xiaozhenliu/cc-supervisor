# Development Guidelines for cc-supervisor

## OpenClaw Integration Rules

**CRITICAL**: This project integrates deeply with OpenClaw. Before modifying any OpenClaw-related code, you MUST follow these rules:

### 1. Consult Documentation First

Before writing or modifying code that interacts with OpenClaw:

1. **Read** `docs/openclaw-reference.md` to find relevant documentation
2. **Verify** the actual behavior from official OpenClaw docs
3. **Do NOT guess** or assume OpenClaw behavior based on variable names or comments

### 2. What Requires Documentation Check

You MUST consult `docs/openclaw-reference.md` when working on:

- OpenClaw CLI commands (`openclaw agent`, `openclaw message send`, etc.)
- Environment variables (`OPENCLAW_SESSION_ID`, `OPENCLAW_CHANNEL`, etc.)
- Message routing and delivery behavior
- Session management
- Error handling and error codes
- Hook integration patterns

### 3. Verification Steps

After implementing OpenClaw integration:

1. **Test with real commands**: Run actual `openclaw` commands to verify behavior
2. **Check environment**: Verify required environment variables are set
3. **Handle errors**: Implement proper error handling based on documented error codes
4. **Document assumptions**: If documentation is unclear, document your assumptions in code comments

### 4. When Documentation is Missing

If `docs/openclaw-reference.md` doesn't cover your use case:

1. **Ask the user** for clarification or documentation links
2. **Do NOT proceed** with guessed behavior
3. **Update the reference** once you have verified information

---

## Code Style

- Use structured logging (JSON format) for all logs
- Include context in error messages (session ID, command, etc.)
- Handle edge cases explicitly (missing env vars, command not found, etc.)
- Write defensive code (check preconditions, validate inputs)

---

## Testing

- Test with actual OpenClaw commands when possible
- Mock OpenClaw behavior only when documented
- Include error cases in tests
- Verify environment variable handling

---

## Documentation

- Update `docs/openclaw-reference.md` when you discover new OpenClaw behavior
- Document workarounds for OpenClaw limitations
- Keep examples up-to-date with actual usage
