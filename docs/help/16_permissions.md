# One Roof help: Permissions

**Status:** LIVE · **Date:** 2026-10-31

> **One line:** each agent has one permission mode, set once in Settings › Permissions: Manual, Plan, Auto or Full. Every new session starts in it. Antigravity starts in Full; the others start in Auto. You can change the mode and type your own flags.

## The four modes

- **Manual:** the agent asks before each edit or command.
- **Plan:** the agent plans first and changes nothing until you approve the plan. For Codex this is Read only.
- **Auto:** routine work runs on its own. Depending on the agent, risky actions can still ask.
- **Full:** the agent never asks. Every edit and command goes ahead without a prompt.

## What each mode does, per agent

Flags checked against each CLI's own `--help` on 2026-10-31.

| Agent | Manual | Plan | Auto | Full (never asks) | What Auto still asks |
|---|---|---|---|---|---|
| Claude | `--permission-mode manual` | `--permission-mode plan` | `--permission-mode auto` | `--dangerously-skip-permissions` | A safety check stops risky actions. |
| Codex | `--ask-for-approval on-request` | `--sandbox read-only --ask-for-approval on-request` | `--approve-for-me` | `--dangerously-bypass-approvals-and-sandbox` | Approvals are reviewed for you inside the workspace sandbox. Full also turns the sandbox off. |
| Gemini | `--approval-mode default` | `--approval-mode plan` | `--approval-mode yolo` | `--approval-mode yolo` | Nothing: Gemini's Auto already never asks. |
| Antigravity | (none: the CLI asks) | `--mode plan` | `--mode auto` | `--dangerously-skip-permissions` | Auto still asks for some tools. This is why Antigravity starts in Full. |
| Kimi | (none: the CLI asks) | `--plan` | `--yolo` | `--auto` | Risky actions, questions and plans still ask. |
| OpenCode, Goose | supervised | supervised | supervised | supervised | Hosted sessions always run under the guarded launcher. They have no unattended mode. |

## Changing it

- **The mode:** Settings › Permissions, pick Manual, Plan, Auto or Full for each agent. Your choice is saved and every new session of that agent uses it.
- **One session only:** the New session sheet can pick another mode for that session.
- **Your own flags:** the Flags field under each agent shows the standard flags as a hint. Type your own to replace them for that agent's current mode. **Reset** puts the standard ones back.
- **Extra arguments** (Settings › Seats & accounts): if a session's own arguments already set a mode, those win and the mode adds nothing.

Loops and objective steps keep their own setting.

## Full means no safety net

In Full, the agent runs everything it decides to run. Use it in repositories where every change goes through git and review. Codex's Full also turns its sandbox off.
