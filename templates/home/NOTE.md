# ⛔ WRONG FOLDER (applies ONLY if your working directory is exactly {{HOME}})

<!-- oneroof home note: conditional on purpose. Claude Code reads CLAUDE.md from every PARENT folder, so this
     file is also read by sessions inside {{WORKSPACE}}; they must ignore it. -->

- If your current working directory is **exactly `{{HOME}}`**: do no work. Do not read, write or save memory.
  Tell the user: "Wrong folder: exit and restart with `cd {{WORKSPACE}} && <agent>`."
- If your working directory is `{{WORKSPACE}}` or inside it: **ignore this file**. Your rules are in
  `{{SHARED}}/AGENTS.md`.

Why: one launch folder gives every agent the same rules and Claude one memory. Installed by oneroof (`roof doctor`).
