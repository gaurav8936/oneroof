---
name: parallel-worktrees
description: Run several agents on one repository at once without collisions — a git worktree and branch per task, non-overlapping file claims, and landing one task at a time with tests after each merge.
runtime: [shared]
dependencies: [fan-out-or-not]
triggers: [worktree, parallel agents, run in parallel, roof swarm]
---

# parallel-worktrees — separate copies, separate files, one landing at a time

## By hand

```bash
git worktree add .worktrees/<task> -b work/<task>      # one per task, from your working branch
cd .worktrees/<task>                                     # the agent works and commits only here
# ...when done, from the main checkout:
git merge --no-ff work/<task> && <run the tests>         # one task at a time
git worktree remove .worktrees/<task> && git branch -d work/<task>
```

Add `.worktrees/` to `.gitignore`. Each worktree installs its own dependencies and uses its own port; never share a
`node_modules` or a dev server between them.

## With the kit: `roof swarm`

Write a spec with one entry per task, each naming the files it may change:

```json
{"repo": ".", "max_parallel": 2, "timeout_s": 900, "retries": 1,
 "tasks": [{"id": "api", "files": ["src/api"], "cmd": "codex exec 'add the /health route'", "check": "npm test"},
           {"id": "docs", "files": ["docs/health.md"], "cmd": "kimi -p 'document the /health route'"}]}
```

```bash
roof swarm run spec.json --dry-run     # validates claims, shows the plan
roof swarm run spec.json               # worktree per task, timeouts, retries; refuses overlapping claims
roof swarm merge .fanout/<run-id>      # merges green tasks one by one; stops at the first conflict
roof swarm clean .fanout/<run-id>
```

A task that edits a file outside its claim fails. One Roof shows each task's claims live, so you can see who owns
which file.

## Rules

- Claims never overlap. If two tasks need the same file, they are one task.
- Land one at a time and run the tests after each merge.
- Never push task branches; they are scratch.
