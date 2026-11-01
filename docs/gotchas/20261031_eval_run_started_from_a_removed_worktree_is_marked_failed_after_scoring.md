# An eval run started from a worktree that is later removed is marked failed after it scored every question

**Found:** 2026-10-31 (LAB-1993). **Fixed in:** 1.9.37 (`run_cwd`, `final_status` in `roof_eval.py`).

**Symptom.** A long run (SWE-bench with Claude Code, 10/10 graded, 7 solved) ends `failed` with
`FileNotFoundError: [Errno 2] No such file or directory`; the console shows the same error in "Error occurred shutting
down sandbox environments", and the traceback ends in Inspect's `cwd_relative_path` → `os.getcwd()`.

**Cause.** Before 1.9.37 a registry task (not a `.py` file) ran Inspect in the caller's working folder. The run was
started from a release worktree that `wt-land` removed mid-run; Inspect's closing panel then cannot read its cwd and
exits non-zero, after the log was written as `success`.

**Do.** 1.9.37 runs Inspect in the run's own folder and lets a complete, scored log decide `done` (the closing error
is kept as `closing_error`). Older runs marked this way still have valid scores in their log.
