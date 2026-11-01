# One Roof help: seats, the router and the on-device model

**Status:** LIVE · **Date:** 2026-10-19 · accounts per agent 2026-10-31 (LAB-1999)

> **One line:** One Roof shows how full each seat is, suggests an agent by One Roof's routing rules plus each seat's remaining capacity, can use a small on-device model to sort a task into a kind, and moves a step to another agent when its seat runs out.

## Goal

Choosing an agent should take one click and always say why. The rules live in one file you can edit, so changing them changes One Roof with no new release. The small local model only sorts; it never plans and never decides alone.

## Seats

A seat is one subscription an agent runs on: one agent on one account.

- **Claude1** is your default Claude config (`~/.claude`).
- **Claude2** appears if you have a second Claude config at `~/.claude-2`, or once you add it. Sessions on it run with `CLAUDE_CONFIG_DIR` set to that folder.
- **Codex, Gemini CLI and Kimi** start with one account each (Codex1, Gemini1, Kimi1), and you can add more. **Antigravity, OpenCode and Goose** have one account each. Gemini CLI and Antigravity are both Google.

### Adding an account

Settings › Seats & accounts › **Accounts** lists every agent's accounts: its number and name, its folder, and whether it is signed in (as far as a look at that folder tells; One Roof does not ask the agent).

1. Press **+ Add account** next to the agent. One Roof says which folder it will use and asks first; nothing is made until you confirm.
2. Confirm. One Roof creates the folder and lists the account (Codex2, Gemini2, Claude3 …).
3. Sign in once, in Terminal, with the command One Roof shows (**Copy** puts it on the clipboard). **Sign in…** on the account's row shows it again later.

| Agent | Account 1 | Added accounts | Sign-in command (example) |
|---|---|---|---|
| Claude | `~/.claude` | `~/.claude-N` (`CLAUDE_CONFIG_DIR`) | `CLAUDE_CONFIG_DIR=~/.claude-3 claude`, then sign in when it asks |
| Codex | `~/.codex` | `~/.codex-N` (`CODEX_HOME`) | `CODEX_HOME=~/.codex-2 codex login` |
| Gemini CLI | your home folder | `~/.gemini-home-N` (`GEMINI_CLI_HOME`; Gemini makes `.gemini` inside it) | `GEMINI_CLI_HOME=~/.gemini-home-2 gemini` |
| Kimi | `~/.kimi-code` | `~/.kimi-code-N` (`KIMI_CODE_HOME`) | `KIMI_CODE_HOME=~/.kimi-code-2 kimi`, then `/login` |

Antigravity and Goose have no setting that moves their sign-in, and OpenCode's `OPENCODE_CONFIG_DIR` moves its settings but not its sign-in, so their **+ Add account** is off (its help says why).

Every added account is a seat of its own: a card in New session, a choice in Settings › Agents › Account, and a chip in the bottom bar (badges `X2` for Codex2, `G3` for Gemini3, `K2` for Kimi2, `C3` for Claude3, in the agent's colour; the first accounts keep C1, C2, CX, GM, KM). Sessions, Tonight and loops start on the account's folder whether One Roof is open or not. The first account of every agent starts with no variable set, as before.

- **Rename…** gives an account your own name (shown in Settings, New session and the bottom bar's help); sessions keep its id, such as Codex2. An empty name puts the id back.
- **Remove…** takes an account out of One Roof. Its folder and sign-in stay on this Mac; nothing is deleted. Add it again to use it. The first account of an agent can't be removed.

| Seat | Where the numbers come from | Shown |
|---|---|---|
| Claude1, Claude2 | Optional: a Claude Code status line that writes usage files (see below). Otherwise the gauges stay empty. | seat bars in the sidebar, agent cards in New session, and Seats on the Overview, with reset times |
| Codex, Codex2 … | each account's own session logs (`~/.codex/sessions/`, `~/.codex-2/sessions/` …) | the same places |
| Kimi, Gemini, Antigravity | they publish no usage | the Overview counts their sessions instead |

**Claude usage files.** Claude Code passes its rate-limit figures to your status line command. If your status line also writes them to `~/Library/Application Support/One Roof/usage/Claude1.json` (and `Claude2.json`, `Claude3.json` … for the other accounts), One Roof shows them. Each file holds the status line's `rate_limits` object (`five_hour` and `seven_day`, each with `used_percentage` and `resets_at`) and an `updated` time in seconds. Numbers older than 6 hours are ignored by the router.

## How a choice is made

1. **What kind of task?** A plan step already has a kind (research, design, code, review, test, docs, chore), or the on-device model reads the name and objective and picks one. Without the model, the kind is "code".
2. **Rules for that kind** come from One Roof's own `agent-routing/routing.json` (in the app's Resources; yours in `~/.config/oneroof/agent-routing/` win): an ordered list of agents per kind. The bundled rules are:

   | Kind | Tried in this order |
   |---|---|
   | research | Kimi, Gemini, Claude Sonnet |
   | design, code | Claude Opus, Codex, Claude Sonnet |
   | review | Codex, Claude Sonnet, Kimi |
   | test | Codex, Claude Sonnet |
   | docs | Kimi, Claude Sonnet |
   | chore | Claude Haiku, Kimi, Codex |

3. **Budget** moves choices: Light puts Claude Opus last; Whatever it takes puts Opus first for design, code and review.
4. **Capacity:** a Claude or Codex seat at 90% of its 5-hour window (or 95% of its 7-day window) is skipped. The limits are `skip_above` in `routing.json`. Between the two Claude seats, the emptier one wins.
5. **Reviews avoid the author:** Route all steps never gives a review to the same vendor family as the step that wrote the code.
6. **Nothing fits:** Claude1, with "no rule fits".

## The reason line

Every suggestion says why, in one line:

- `code → Claude opus on Claude2 (2% of its 5-hour window)`: kind code, first choice Claude Opus, Claude2 picked because it is emptier.
- `review → Codex (12% of 5 h)`: kind review, Codex first, with its use.
- `… · skipped: both Claude seats near their limit`: what was passed over and why.

You see it as **Suggested:** in the New session sheet and on each step card in an objective (Suggest, Route all steps). Roles (from `roles.json` next to `routing.json`, for example a code review on Codex) fill agent and model directly.

## The on-device model

- **What:** an optional add-on. One Roof works fully without it: task kinds come from the plan or from you, and captions from the built-in rules. With it, a small model sorts a task into a kind in about 0.15 s and can write the one-line captions. It runs only on this Mac, through `llama-server` from llama.cpp on `127.0.0.1:8749`.
- **Which model:** Qwen3 1.7B (`Qwen3-1.7B-Q4_K_M.gguf`, 1.1 GB on disk, about 1.6 GB of memory while it runs), under the Apache-2.0 licence, so you may use it for any purpose. On a fixed set of 38 task sentences it picked the right kind 37 times; Arch-Router, the model up to 0.5.1, 32 times.
- **Install it:** `brew install llama.cpp`, then press **Get the model (1.1 GB)** in Settings › Foundations (on-device model row) or on the On-device router model row of Window › Foundations. One Roof downloads the file from Hugging Face (a fixed revision), shows progress, checks its size and SHA-256, and only then puts it in `~/Library/Application Support/One Roof/models/`, with its licence next to it (`Qwen3-1.7B-LICENSE.txt`). It checks there is enough free disk space first. **Stop** keeps what has arrived; **Get the model again** continues from there. If the file does not match, it is deleted and nothing changes. You can also put the file there yourself, or choose another file in Settings.
- **Still on Arch-Router?** If Settings points at `Arch-Router-1.5B-Q4_K_M.gguf`, it keeps working, and Settings and the startup check show an amber note: its licence (the DigitalOcean Community License) needs a separate licence for commercial use. **Get the model** downloads Qwen3 1.7B and switches Settings to it (your Arch-Router file is left where it is). If you chose some other model of your own, Settings keeps it.
- **Coming:** `llama-server` built into the app, so no Homebrew step.
- **When:** started on first use (the first call waits for it to load), stopped when One Roof quits, and also when One Roof is force-quit or crashes (a watchdog ends it within about 2 seconds). Restarted if it grows past 3 GB. About 0.15 seconds per question once loaded.
- **What it answers:** one word, the kind, held to the seven kinds. Anything else is ignored.
- **Try it:** `OneRoof --route "add a dark mode toggle to settings"` prints the kind and the router's choice.
- **Missing:** the startup check shows amber. Suggestions still work, from the rules alone.

The model can also write the one-line captions on session rows (Settings › Captions). Off, or without the model, captions come from the terminal text.

## Rotation: when a seat runs out mid-step

During an objective run, a step on a Claude or Codex seat that passes the limit is asked, only when it is between turns, to stop at a safe point and write a handoff file. One Roof then closes that agent, routes the step again (avoiding the same agent), and starts it on the new agent with "read the handoff first". At most two rotations per step. Kimi, Gemini and Antigravity steps never rotate, because they publish no usage.

## Change the rules

To change the rules, copy `routing.json` or `roles.json` from the app's `Contents/Resources/agent-routing/` (Settings › Foundations › **Show**, then one folder up) into `~/.config/oneroof/agent-routing/` and edit your copy: a file there wins over the bundled one. One Roof reads the files on every suggestion, so the next click uses the new rules.
