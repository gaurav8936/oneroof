# A fourth permission mode, Full (never asks); Antigravity starts in it

**Status:** DECIDED · **Date:** 2026-10-31 · **Linear:** LAB-1935 · **Extends:** `20261029_01_permission-mode-per-agent.md`

> **One line:** Settings › Permissions gains **Full**, each CLI's own never-ask flag. Antigravity starts in Full, the
> other agents stay in Auto, and the owner can change the mode and edit each mode's flags.

## The question

The owner, 2026-10-31: Antigravity's Auto (`--mode auto`) still stopped to ask, so "auto was not sufficient". They
wanted Antigravity "permanently" in full Turbo mode (`--dangerously-skip-permissions`), and still editable: "make
sure it's editable and I can change it if I need to." The only workaround, Extra arguments, could not be edited
(LAB-1934).

## Decision

- **Full** joins Manual · Plan · Auto. Each agent maps to its CLI's own never-ask flag, checked against `--help` on
  2026-10-31: Claude `--dangerously-skip-permissions`, Codex `--dangerously-bypass-approvals-and-sandbox`, Kimi
  `--auto`, Gemini `--approval-mode yolo` (the same as its Auto), Antigravity `--dangerously-skip-permissions`.
  Hosted agents (OpenCode, Goose) stay supervised.
- **Defaults:** Antigravity Full; every other agent Auto (unchanged, LAB-1600).
- **Migration:** the first time 1.9.34 reads a profile, a saved Antigravity Auto (or no choice) becomes Full, once
  (`permissionDefaultsVersion`). A choice made after that is kept, and a deliberate Manual or Plan is never touched.
- **Editable flags:** each agent's mode shows its flags in an editable field (`permissionFlags`, keyed
  `<agent>.<mode>`); blank means the standard flags, and Reset clears an edit. A session copies the flags when it is
  made (`Session.permissionFlags`), so a later edit doesn't change sessions that already exist.
- Loops and objective steps keep `AgentKind.autoApproveArgs` (Antigravity's already uses
  `--dangerously-skip-permissions`).

## Consequences

- Full has no safety net, and Codex's Full also turns its sandbox off. The help page (`docs/help/16_permissions.md`)
  says so, with the per-agent table of what Auto still asks.
- A profile written by 1.9.34 that holds `full` reads as the default mode in an older build, because the whole mode
  map fails to decode there. Downgrades are rare; reinstalling 1.9.34 restores it.
