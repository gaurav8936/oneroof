# Hooks

Two small Claude Code hooks that back up the session skills. Neither blocks anything; they only remind.

| Hook | Event | Does |
|---|---|---|
| `session-start-read-first.sh` | SessionStart | tells the agent to read the shared `READ-FIRST.md` and names the newest handoff |
| `stop-unsaved-work.sh` | Stop | if the repo has uncommitted changes, says so and points to `last-call` |

Install by adding them to `~/.claude/settings.json` (the header of each file shows the exact JSON). Agents without
hooks (Codex, Kimi, Gemini) get the same guidance from the `where-are-we` and `last-call` skills. The One Roof kit
adds its own launch-folder hook separately (`roof install`).
