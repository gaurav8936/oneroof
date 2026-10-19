# Adding an agent

Every agent you add must meet the same three conditions as the ones already here.

1. **It starts only inside the workspace.** If it has hooks, block prompts outside (like `guard/claude-hook.sh`). If
   it doesn't, add it to `--agents` so `roof install` writes a PATH stand-in for it:
   `roof install --agents "claude codex kimi hermes"`.
2. **It reads the shared rulebook.** Most agents read `AGENTS.md`; the workspace `AGENTS.md` points at
   `_common/AGENTS.md`. If it reads a different file name, add a one-line file of that name next to `AGENTS.md`
   pointing at the same place (never a second copy of the rules).
3. **Its private memory never holds the only copy of a fact.** Either it has no memory, or its memory holds pointers
   into the shared docs, and `last-call` lifts anything durable into `_common/docs/`.

Then: link your skills into its skills home (`ROOF_SKILL_HOMES="~/.newagent/skills" roof sync-skills <dir>`), add a row to
the table in [architecture](../architecture/oneroof-kit.md), and run `roof doctor`.

## Hermes Agent (Nous Research)

Hermes keeps **its own persistent memory**: `MEMORY.md` (agent notes) and `USER.md` (user profile) in
`~/.hermes/memories/`, injected at session start and edited by the agent's memory tool. It reads project rules from
`AGENTS.md` (or `.hermes.md`) in the project, and it creates skills as it works.
([memory](https://hermes-agent.nousresearch.com/docs/user-guide/features/memory) ·
[which file does what](https://hermes-agent.nousresearch.com/docs/user-guide/which-file-does-what))

What that means here:

- **Its memory is global, not per folder**, so it can't split by launch folder the way Claude's did. But it is a
  second private store next to Claude's, which is exactly the G5 risk: a fact Hermes learns and keeps only in
  `MEMORY.md` is invisible to Claude, Codex and Kimi.
- **Launch folder still matters**: Hermes finds `AGENTS.md` from where it starts. Add `hermes` to `--agents` for the
  stand-in.
- **Recommended setup:** keep Hermes's `MEMORY.md` for environment facts about Hermes itself, and seed it with one
  line: "Durable rules and project state live in `<workspace>/_common/docs/`; read `READ-FIRST.md` there; write new
  rules there, not here." Include `~/.hermes/memories/` in your `last-call` sweep so anything durable gets lifted.
- **Skills:** `roof sync-skills` links into `~/.hermes/skills` when that folder exists. Skills Hermes creates on its
  own stay in its home until you move them into your shared skills folder.

Check your Hermes version's docs for exact paths; they have changed between releases.
