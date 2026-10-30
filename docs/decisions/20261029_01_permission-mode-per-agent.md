# Permission mode per agent, set once in Settings (default Auto)

**Status:** DECIDED · **Date:** 2026-10-29 · **Linear:** LAB-1600 · **Supersedes:** the "sessions never auto-approve" rule (app/CLAUDE.md §9, "Don't auto-approve…")

> **One line:** every new session starts in the permission mode the owner set for its agent in Settings › Permissions,
> and that mode is Auto unless the owner picks Manual or Plan.

## The question

Sessions started in each CLI's own default mode, which asks before each edit or command. Auto mode was only for loops
and objective steps with Auto-approve on. The owner kept finding sessions in manual mode without meaning to:
"I'm able to set it up in one place without having to know that I'm in manual mode all of a sudden, whereas I should
have been in auto." And: "It'll be auto by default and manual only if I need to. That way, I'm able to run more of
the sessions autonomously."

## Decision

- One setting per agent: **Manual · Plan · Auto**, default **Auto** (stored in the app settings, `permissionModes`).
- Each mode maps to the CLI's own flags, checked against each CLI's `--help` on 2026-10-29
  (`OneRoofCore/PermissionMode.swift`):

| Agent (version checked) | Manual | Plan | Auto |
|---|---|---|---|
| Claude Code 2.1.287 | `--permission-mode manual` | `--permission-mode plan` | `--permission-mode auto` (classifier-gated) |
| Codex 0.164.0 | `--ask-for-approval on-request` | Read only: `--sandbox read-only --ask-for-approval on-request` | `--approve-for-me` |
| Kimi 2.3.1 | no flag (asks) | `--plan` | `--yolo` (Ask When Needed: risky actions still ask) |
| Gemini 0.64.0 | `--approval-mode default` | `--approval-mode plan` | `--approval-mode yolo` |
| Antigravity 1.4.3 | no flag (asks) | `--mode plan` | `--mode auto` |

- The mode is stamped on the session when it is made (`Session.permissionMode`) and its flags are added at launch.
  The New session sheet can pick another mode for one session. Arguments that already set a mode (for example
  `--permission-mode plan` typed in Agent arguments) win: no flag is doubled.
- Sessions made before 1.9.24 have no mode and launch exactly as before.
- Loops keep their own auto behaviour; objective steps keep their Auto-approve switch (off = Manual).
- The mode shows on each session: in the terminal header line and in the plan panel's details.

## What does not change

One Roof never answers an agent's permission prompt itself, and never auto-merges or auto-commits. In Auto the CLI's
own safeguards apply (Claude's safety classifier, Codex's sandbox and review, Kimi's ask-when-needed). Gemini's only
hands-off mode approves every tool; pick Manual or Plan for Gemini when that is too much.
