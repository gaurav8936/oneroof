# One Roof help: setup guide

**Status:** LIVE · **Date:** 2026-11-01

> **One line:** every choice in the setup window and in Settings that changes what One Roof does on your Mac: what it does, where it starts, and what changes if you change it. Nothing here is permanent; every answer can be changed later.

The setup window opens once, the first time One Roof starts. Open it again any time with **One Roof › Setup…**. Every answer is also in **Settings** (⌘,).

Some choices are marked:

| Mark | Means |
|---|---|
| **Acts** | Lets an agent change files or run commands without asking you first. |
| **Costs** | Uses your agent account (tokens or plan limits) on top of the work you ask for. |
| **Schedule** | Runs something at a set time, possibly while you are away. |
| **Network** | Talks to a service outside this Mac. |
| **Writes elsewhere** | Changes a file that belongs to another program. |

## The setup window, step by step

### Step 1 · Agents on this Mac

One Roof looks for `claude` (Claude Code), `codex`, `kimi`, `gemini` (Gemini CLI) and `agy` (Antigravity) on your PATH, and for Claude it shows which accounts are signed in.

- **Nothing to choose.** It only tells you what is there.
- **Missing an agent?** Install its CLI and sign in once from any terminal; One Roof finds it the next time it starts. You need at least one agent to start a session.
- **Impact:** an agent that is not installed is still offered in New session, but it cannot start.

### Step 2 · Folders and tools

**Projects folder.** The folder that holds your code repos.

- **Starts as:** `~/Projects` when that folder exists. If it does not, Setup asks you to choose a folder or press **Create ~/Projects**, and goes on only once you have one.
- **Impact:** every agent starts in this folder, and New session, Search and Loops list the repos inside it. Agents can read everything below it.
- **Choose a folder that holds only your code.** Not your home folder: agents would start there with your documents in reach. One Roof never lists the home folder's contents as repos.
- **Later:** Settings › Foundations. A single session can start inside one repo instead (New session › Start in › Repo folder).

**Shared rules and docs (optional).** A folder for the rules, handoffs and gotchas that all your agents share.

- **Starts as:** `_common` inside your projects folder. **Create it** makes it for you.
- **Impact when set:** session handoffs and gotchas are written there, the startup check also checks it, objective plans and your own loops are saved there.
- **Skip:** nothing is lost from sessions. Handoffs, gotchas and the shared-folder checks stay off. You can add a folder later in Settings › Foundations.

**Required tools.** One Roof checks that `git` works.

- **Missing git:** you can still start sessions, but diffs and review need it. Run `xcode-select --install`, then reopen One Roof.

### Step 3 · Kit, look and Linear

**Agentic engineering.** The skills and the narrated Agentic Engineering deck (Learn, ⇧⌘E) are bundled with the app. Nothing to choose.

**Look.** Daylight, Graphite or Midnight set every panel at once.

- **Impact:** looks only. Change it any time in Settings › Appearance, or mix themes per panel there.

**Linear (optional)** · *Network*

- **What it does:** connects the Projects place and tickets to your Linear workspace. Later: Settings › Linear.
- **Starts as:** not connected. Without a key, Projects shows a **Connect Linear** card and everything else works.
- **Where the key goes:** `~/.config/oneroof/linear-api-key`, readable only by you. `LINEAR_API_KEY` in the environment also works.
- **Impact:** One Roof reads your Linear teams, projects and issues. It changes an issue only when you ask it to (for example New work item, or moving an issue's state).

Press **Open One Roof** to finish.

## Choices in Settings that matter

### Permissions (Settings › Permissions) · *Acts*

The most important choice. Each agent has one mode; every new session starts in it.

| Mode | What the agent does |
|---|---|
| **Manual** (the start) | Asks before it edits a file or runs a command. |
| **Plan** | Reads and plans, changes nothing. |
| **Auto** | Runs routine edits and commands on its own. How much still asks depends on the agent: Claude stops risky actions, Gemini's Auto never asks. |
| **Full** | Never asks. Use it only in a folder you can afford to lose changes in. |

- **Starts as:** Manual for every agent.
- **Impact of Auto or Full:** work goes faster and the Inbox fills less, but the agent changes files without showing you first. Review its changes afterwards (Review, or `git diff`).
- One session can use a different mode (New session sheet). Loops and objective steps keep their own setting; the objective planner uses Claude's mode. Detail, with each agent's flags: [Permissions](16_permissions.md).

### General (Settings › General)

| Choice | Starts as | Impact |
|---|---|---|
| Check the foundations every time One Roof starts | On | Checks roofd, agent logins, skills, hooks and the shared folder. Red items ask before an agent launches. Off: faster start, no warning. |
| When an agent ends | 10 minutes | How long a finished agent's shell stays on screen before One Roof closes it. Never a pinned session or one still running something. The row stays; Resume works from All sessions (⌃⌘O). |
| Close sessions untouched for | 24 hours | Closes sessions nobody touched for that long. Never one that is working, waiting for you, pinned, or a loop. Resume brings the conversation back. |
| Keep agent conversations on this Mac · *Writes elsewhere* | Claude's default: 30 days | Resume needs the agent's conversation file. Changing this writes `cleanupPeriodDays` into each Claude account's own settings. A lower number lets Claude delete older conversations. Codex and Kimi keep theirs until you delete them. |
| Done when required | Off | On: New session needs a "Done when" before it launches. |
| Step review: Claude reads each finished step · *Costs* | Off | Each reviewed step is one Claude call on your account. |
| Always show the composer under agents | Off | Off: you type into the agent's own prompt in the terminal. |
| Allow scheduled runs (Tonight, Nightly) · *Schedule* | Off | On: roofd starts Tonight, Nightly and repeating sessions on time, even with One Roof closed. Off: they run only while One Roof is open. Nothing is merged or committed on its own. |
| Menu-bar extra | On | A One Roof icon in the menu bar. |

### Notifications (Settings › Notifications)

All on at the start: when an agent needs you, when one finishes its turn, and when a long command finishes in a terminal you are not looking at. Plus the Dock badge for sessions that need you. Turn off any you find noisy. Detail: [Notifications and run terminals](15_notifications-and-run-terminals.md).

### Seats & accounts (Settings › Seats & accounts)

Per agent: which account new sessions use, which model, and extra command-line arguments. **Arguments that set a permission mode win over the Permissions setting.**

### Routing and the on-device model (Settings › Seats & accounts, On-device model)

- **Use the on-device model for captions and reasons:** on, but it does nothing until you install `llama.cpp` and press **Get the model** (1.1 GB download · *Network*, once). The model runs on this Mac; nothing you type leaves it. Without it, captions come from the terminal text.
- **Prefer a different model family for review:** on. When One Roof picks an agent to review work, it prefers one from a different company than the one that wrote it. Detail: [Seats, router and on-device model](07_seats-router-and-on-device-model.md).

### Loops · *Schedule* · *Acts* · *Costs*

Loops repeat work until a check passes, or run every night. The built-in loops are **off** until you turn one on. Each round uses your agent account; a nightly loop runs only when **Allow scheduled runs** is on or One Roof is open. A loop works in its own git worktree and never merges by itself. Detail: [Loops](14_loops.md).

### Evals · *Costs* · *Network*

Evals measures your agents and models. A run uses your agent accounts or API keys, at a size you choose before it starts. Detail: [Evals](17_evals.md).

## What One Roof always does

- **roofd, the background item.** On first launch macOS says "One Roof added a background item". That is roofd: it keeps your sessions running when you quit One Roof. Leave it on in System Settings › General › Login Items.
- **Fix buttons** in the startup check (Foundations) can change your agents' own settings, for example linking skills or adding a hook. *Writes elsewhere.* Nothing changes until you press one.
- **Updates:** One Roof does not check for updates on its own. Settings › Updates › **Check now** opens the download page in your browser; new versions install from there.

## Starting over

- **Run setup again:** One Roof › Setup….
- **Remove the Linear key:** delete `~/.config/oneroof/linear-api-key`.
- **Next:** [Getting started](00_getting-started.md) walks you through your first session.
