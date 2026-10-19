# One launch folder, one memory, one rulebook

**Status:** ACTIVE · installed by oneroof

## Rule

Start every agent session in `{{WORKSPACE}}` or below. Anywhere else is a hard stop.

## Why

Agents find their instructions from the launch folder (Claude Code: `CLAUDE.md` there and in every parent; Codex:
`AGENTS.md` from the repo root down; Kimi and Hermes: `AGENTS.md` in the folder). Claude Code also keys its private
memory on the launch folder unless `autoMemoryDirectory` pins it. Two launch folders mean two rulebooks and, for
Claude, two memories that silently drift apart.

## How it is enforced

| # | Layer | Where | Effect |
|---|---|---|---|
| 1 | Shell default | `~/.zshrc` / `~/.bashrc` | interactive shells that open in `~`, `/Users` or `/` move to the workspace |
| 2 | Agent wrappers | same file | typing `claude`, `codex`, `kimi`, … elsewhere moves you first |
| 2b | PATH stand-ins | `~/.config/oneroof/bin/` | agents without hooks refuse to start outside (exit 64) |
| 3 | Claude hook | `~/.claude/settings.json` | blocks every prompt while the session is outside |
| 4 | Home notes | `~/CLAUDE.md`, `~/AGENTS.md` | "wrong folder, stop" (conditional on being exactly in `~`); optionally locked |
| 5 | Memory pin | `autoMemoryDirectory` | one Claude memory, whatever the launch folder |

Check it any time: `roof doctor`. One-off exception (owner only): `ROOF_ALLOW_OUTSIDE=1 <agent>`.

## Memory hygiene

- Keep the memory index (`MEMORY.md`) under ~150 lines: pointers only. What doesn't load doesn't exist.
- A rule that lives only in one agent's private memory is a defect: move it to `{{SHARED}}/docs/standards/`.
