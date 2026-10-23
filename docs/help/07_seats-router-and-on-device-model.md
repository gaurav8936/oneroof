# One Roof help: seats, the router and the on-device model

**Status:** LIVE · **Date:** 2026-10-19

> **One line:** One Roof shows how full each seat is, suggests an agent by rules from your agentic engineering folder plus each seat's remaining capacity, can use a small on-device model to sort a task into a kind, and moves a step to another agent when its seat runs out.

## Goal

Choosing an agent should take one click and always say why. The rules live in one file you can edit, so changing them changes One Roof with no new release. The small local model only sorts; it never plans and never decides alone.

## Seats

A seat is one subscription an agent runs on.

- **Claude1** is your default Claude config (`~/.claude`).
- **Claude2** appears only if you have a second Claude config at `~/.claude-2`. Sessions on it run with `CLAUDE_CONFIG_DIR` set to that folder.
- **Codex, Kimi, Gemini CLI and Antigravity:** one seat each, when installed. Gemini CLI and Antigravity are both Google.

| Seat | Where the numbers come from | Shown |
|---|---|---|
| Claude1, Claude2 | Optional: a Claude Code status line that writes usage files (see below). Otherwise the gauges stay empty. | seat bars in the sidebar, agent cards in New session, and Seats on the Overview, with reset times |
| Codex | Codex's own session logs in `~/.codex/sessions/` | the same places |
| Kimi, Gemini, Antigravity | they publish no usage | the Overview counts their sessions instead |

**Claude usage files.** Claude Code passes its rate-limit figures to your status line command. If your status line also writes them to `~/Library/Application Support/One Roof/usage/Claude1.json` (and `Claude2.json` for the second seat), One Roof shows them. Each file holds the status line's `rate_limits` object (`five_hour` and `seven_day`, each with `used_percentage` and `resets_at`) and an `updated` time in seconds. Numbers older than 6 hours are ignored by the router.

## How a choice is made

1. **What kind of task?** A plan step already has a kind (research, design, code, review, test, docs, chore), or the on-device model reads the name and objective and picks one. Without the model, the kind is "code".
2. **Rules for that kind** come from `skills/fleet/agent-routing/routing.json` in your agentic engineering folder: an ordered list of agents per kind. The bundled rules are:

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

You see it as **Suggested:** in the New session sheet and on each step card in an objective (Suggest, Route all steps). Roles (from `roles.json` next to `routing.json`, for example a second-opinion review on Codex) fill agent and model directly.

## The on-device model

- **What:** an optional add-on. One Roof works fully without it: task kinds come from the plan or from you, and captions from the built-in rules. With it, a small model sorts a task into a kind in about 0.2 s and can write the one-line captions. It runs only on this Mac, through `llama-server` from llama.cpp on `127.0.0.1:8749`.
- **Install it yourself (for now):** `brew install llama.cpp`, then download `Arch-Router-1.5B-Q4_K_M.gguf` from the `katanemo/Arch-Router-1.5B.gguf` repository on Hugging Face into `~/Library/Application Support/One Roof/models/` (or choose the file in Settings › Foundations). That model has its own licence (the DigitalOcean Community License, which restricts commercial use); read it before you download.
- **Coming:** a one-click download of a freely licensed model, with `llama-server` built into the app.
- **When:** started on first use (the first call waits for it to load), stopped when One Roof quits, and also when One Roof is force-quit or crashes (a watchdog ends it within about 2 seconds). Restarted if it grows past 3 GB. About 0.2 seconds per question once loaded.
- **What it answers:** one word, the kind. Anything else is ignored.
- **Try it:** `OneRoof --route "add a dark mode toggle to settings"` prints the kind and the router's choice.
- **Missing:** the startup check shows amber. Suggestions still work, from the rules alone.

The model can also write the one-line captions on session rows (Settings › Captions). Off, or without the model, captions come from the terminal text.

## Rotation: when a seat runs out mid-step

During an objective run, a step on a Claude or Codex seat that passes the limit is asked, only when it is between turns, to stop at a safe point and write a handoff file. One Roof then closes that agent, routes the step again (avoiding the same agent), and starts it on the new agent with "read the handoff first". At most two rotations per step. Kimi, Gemini and Antigravity steps never rotate, because they publish no usage.

## Change the rules

Edit `routing.json` or `roles.json` under `skills/fleet/agent-routing/` in the agentic engineering folder in use. If that is the bundled copy, choose your own folder first (Settings › Foundations). One Roof reads the files on every suggestion, so the next click uses the new rules.
