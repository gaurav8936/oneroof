# ⛔ Launch-folder rule (global, all Gemini sessions) · oneroof

If your current working directory is NOT `{{WORKSPACE}}` or a folder inside it: do NO work. Tell the user:
"Wrong folder: exit and restart with `cd {{WORKSPACE}} && gemini`". Do not read, write, or save anything.

If you ARE inside {{WORKSPACE}}: follow `{{SHARED}}/AGENTS.md` and `{{SHARED}}/docs/READ-FIRST.md`.
Durable facts go in `{{SHARED}}/docs/`, not in this file or in saved memories.
