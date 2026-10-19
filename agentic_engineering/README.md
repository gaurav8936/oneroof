# agentic_engineering

The starter set of agentic-engineering skills, a short narrated course, and two hooks that ship with One Roof. It is
self-contained: nothing here depends on any other repository.

```
course/      12 short lessons (Markdown) + narration in course/audio/<lesson>/
skills/      17 skills, one folder each: skills/<group>/<name>/SKILL.md
  session/   where-are-we · last-call · next-session-handoff
  plan/      plan-objective · write-the-spec
  build/     test-first · show-the-evidence · second-opinion
  fleet/     agent-routing (routing.json, roles.json) · fan-out-or-not · parallel-worktrees · bounded-loops
  guard/     ask-before-irreversible · keep-secrets-out
  ship/      ship-domain
  learn/     capture-gotchas · repo-map
hooks/       optional Claude Code hooks (reminders only)
scripts/     sync-skills.sh · make-audio.py · check.sh
```

## Use it

```bash
agentic_engineering/scripts/sync-skills.sh --dry-run   # shows the links it would make
agentic_engineering/scripts/sync-skills.sh             # links every skill into each agent's skills folder
```

Then ask any agent for a skill by name ("where are we", "use the test-first skill"). In One Roof, Learn (⌘⇧E) shows
the course and every skill; the planner uses `plan-objective`, and routing reads `skills/fleet/agent-routing/`.

## Which folder One Roof reads

One Roof looks for its agentic-engineering folder in this order:

1. the `ONEROOF_AE_PATH` environment variable, if set;
2. Settings › Foundations › Agentic engineering, if you chose a folder;
3. this bundled copy (inside the app, or next to it in a source checkout).

Point it at your own skills repository to use your own set; switch back with "Use bundled".

## Add or change a skill

1. Create `skills/<group>/<name>/SKILL.md` with frontmatter `name` (same as the folder), `description` (one sentence:
   what it does and when), `runtime: [shared]` and `triggers`.
2. Keep it under a page: purpose, steps, a short example, and what never to do.
3. Run `scripts/check.sh`, then `scripts/sync-skills.sh`.

Edit a lesson, then run `scripts/make-audio.py` (needs `OPENAI_API_KEY`); only edited sections are re-recorded.
