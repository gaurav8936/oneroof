# READ FIRST

The one list of documents every agent must read, every session. Keep it to about eight entries: a doc belongs here
only if *every* agent in *every* session would do damage without it. Everything else lives in the folder for its type.
Every repo can carry a `READ-FIRST.md` symlink to this file: one file, many doors.

## Rule zero: agents run only inside `{{WORKSPACE}}`

If your working directory is not `{{WORKSPACE}}` or a folder inside it, stop and tell the user to restart there. The
launch folder picks the rules and (for Claude Code) the memory. Detail: [standards/launch-folder.md](standards/launch-folder.md).

## Must-read set

1. [standards/launch-folder.md](standards/launch-folder.md): one launch folder, one memory, one rulebook.
2. [standards/parallel-agents.md](standards/parallel-agents.md): worktrees, file ownership, bounded fan-out.
3. *(add your deploy process here)*
