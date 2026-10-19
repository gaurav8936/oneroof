# Course

Twelve short lessons on agentic engineering. Each is a Markdown file; every `##` section is one narrated part, and its
audio lives in `audio/<lesson file name>/`. One Roof's Learn view (⌘⇧E) lists them in file-name order.

| # | Lesson | Skills it points to |
|---|---|---|
| 01 | Start here | — |
| 02 | You steer, agents build | plan-objective, write-the-spec |
| 03 | Every task is a loop | bounded-loops, test-first |
| 04 | Small skills that combine | all |
| 05 | One workspace, one memory | where-are-we, next-session-handoff, repo-map |
| 06 | The right agent for the job | agent-routing, second-opinion |
| 07 | Parallel without collisions | fan-out-or-not, parallel-worktrees |
| 08 | Trust comes from evidence | test-first, show-the-evidence, ask-before-irreversible, keep-secrets-out |
| 09 | Sessions have a beginning and an end | where-are-we, last-call, next-session-handoff |
| 10 | Shipping safely | ship-domain |
| 11 | Learning from mistakes | capture-gotchas, last-call |
| 12 | Voices worth reading | — |

Regenerate audio after editing a lesson: `python3 ../scripts/make-audio.py` (needs `OPENAI_API_KEY`; only changed
sections are re-recorded).
