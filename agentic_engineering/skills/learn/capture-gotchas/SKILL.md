---
name: capture-gotchas
description: When something surprising breaks, write one short note — symptom, cause, fix, how to check — named after the symptom, in the shared gotchas folder, so the next session finds it before repeating the mistake.
runtime: [shared]
triggers: [gotcha, write that down, remember this failure, lesson learned]
---

# capture-gotchas — one fact per file

## When

Any time a session loses more than a few minutes to something non-obvious: a misleading error, a tool that behaves
differently than documented, a step that silently does nothing. Write it while the details are fresh.

## Where and how it is named

`<shared>/docs/gotchas/YYYYMMDD_<symptom-in-plain-words>.md`, e.g.
`20261018_deploy_reports_success_but_site_serves_old_version.md`. Name it after what someone would *see*, not the
cause, because the symptom is what they will search for.

## Template

```markdown
# <the symptom, as a sentence>

**Seen:** YYYY-MM-DD · **Where:** <repo / tool / version>
**Symptom:** what you observe.
**Cause:** why it happens (with evidence: a doc link, a file and line, a command).
**Fix:** the exact steps or command.
**Check:** how to confirm it is fixed or not happening.
```

## Rules

- One fact per file. A second lesson gets a second file.
- Before writing, search the folder (`grep -ril <keyword> <shared>/docs/gotchas`); update an existing note instead
  of adding a near-duplicate.
- If the gotcha implies a rule everyone must follow, add the rule to the shared rulebook and link the note.
- Delete a note when it stops being true, such as when the tool is fixed.
