<h1 align="center">One Roof</h1>

<h3 align="center">The terminal was built for one session. You're running twenty.</h3>

<p align="center">One Roof is a Mac app that sits between a consumer app and a terminal. Every Claude Code, Codex, Kimi,
Gemini and Antigravity session you have running is in one place. Each session says in plain words what it's doing,
and your routing rules plus each subscription's remaining usage decide which agent and account takes the next task.</p>

<p align="center">
  <a href="https://github.com/gaurav8936/oneroof/releases/latest"><b>⬇ Download for Mac (.zip)</b></a> ·
  <a href="https://gaurav8936.github.io/oneroof/">Website</a> ·
  <a href="docs/help/00_getting-started.md">Getting started</a> ·
  <a href="CONTRIBUTING.md">Contribute</a>
</p>

<p align="center">
  <a href="https://github.com/gaurav8936/oneroof/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/gaurav8936/oneroof?label=release"></a>
  <a href="https://github.com/gaurav8936/oneroof/actions/workflows/test.yml"><img alt="Tests" src="https://github.com/gaurav8936/oneroof/actions/workflows/test.yml/badge.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-arm64-lightgrey">
  <a href="LICENSE"><img alt="MIT licence" src="https://img.shields.io/badge/licence-MIT-blue"></a>
</p>

<p align="center"><sub>Open source · MIT · native macOS app · macOS 14 or later · one download, plus herdr and your agents</sub></p>

<p align="center"><img src="site/shots/overview-daylight.png" alt="One Roof Overview: every window and session at once, grouped, with a live feed of what each agent did" width="960"></p>

<p align="center"><b>Side by side:</b> Claude Code · Codex · Kimi · Gemini · Antigravity<br>
<sub>Up to two Claude accounts and one of each other agent, detected automatically. Claude and Codex show live usage,
and new sessions go to the seat with room.</sub></p>

## Why we built it

**10× doesn't come from typing faster. It comes from running more at once.**

Agents don't run your work for you. A few tasks will run on their own, but deep, detailed work still needs a person:
setting direction, answering questions, checking the result. What's changed is how many things need you at once. You're
running several, and you switch between them all day.

The terminal comes from a world of one session, maybe two, and it gets hard to read the moment you have ten. **One Roof
is built to make that switching easy:** glance at a session, see where it is, decide and move on. Labels, colours,
plain-language summaries and one place for every decision, with a real terminal underneath.

## A terminal was built for one person typing. You're running a fleet.

| What goes wrong | What One Roof does |
|---|---|
| **You can't tell sessions apart.** Every tab has the same grey icon, so you type WIP: or NEXT: in front of the name. | Every session is labelled with its state, agent, account and a live one-line status. |
| **Nobody reads the wall of text.** You give an instruction and get pages of output. | A summary of what you asked, what it's doing now and how many steps are done. The stream folds into chapters. |
| **You approve without knowing why.** "Allow this command?" comes with no reason and no sense of the risk. | Every question in one place, with the agent's reason, what it touches, the risk and what happens if you say no. |
| **Subscriptions run out mid-task.** You have to remember which one is good at what and which still has room. | Your routing rules and each seat's remaining usage pick the agent, account and model. Work hands off before a limit hits. |
| **Agents drift apart.** Launch in the wrong folder and an agent works with a different memory and none of your rules. | One launch folder, one memory and one rulebook, checked every time the app starts. |
| **Work lives in three places.** The tracker, Linear and your tabs never agree. | Board, Work and tickets inside the app. Every session knows its ticket. |

## The tour

### Read the summary, not the stream.
What you asked, what it's doing right now, and steps 3 of 4. Finished steps fold into one-line chapters; the live
step stays a real terminal. Subagents sit beside it with their own captions.

<img src="site/shots/session-daylight.png" alt="A session: what you asked, steps, chapters and subagents" width="960">

### Approve with the reason in front of you. <sub>Decisions · ⌘I</sub>
Every agent waiting on you, oldest first: why it wants to do it, what it touches, the risk, what happens if you say
no. Allow once, always allow, deny, or reply with instructions. Nothing is approved for you.

<img src="site/shots/decisions-daylight.png" alt="Decisions: an agent's request with its reason, what it touches and the risk" width="960">

### Plan your day by dragging cards. <sub>Board · ⌘B</sub>
Planned, Next, Working, Needs you, Ready, Tonight: every session across every window on one board. Drag a card to
Next, or drop it on Tonight to run at 2 AM, nightly or on demand.

<img src="site/shots/board-daylight.png" alt="Board: every session as a card by status" width="960">

### See the agents your agents start. <sub>Subagents · ⇧⌘A</sub>
A timeline of every subagent: who asked it what, the model, tokens, how long it took and what it's doing now.

<img src="site/shots/subagents-daylight.png" alt="Subagents timeline" width="960">

### Say what should happen. It works out who does it. <sub>New session · ⌘N</sub>
One Roof works out whether this is a session, a ticket, a defect or a workstream, finds similar tickets, and puts the
router's suggestion on top with its reason. Launch now, queue it next, or schedule it for tonight. The routing is your
rules plus each seat's remaining usage; an optional on-device model sorts the task into a kind in about 0.2 s.

<img src="site/shots/newsession.png" alt="New work sheet with the suggested agent and account" width="960">

### Still a real terminal, with each panel in its own theme. <sub>Workspace</sub>
Sessions, files, terminal and plan side by side, built on Ghostty's renderer, with ⌘D and ⇧⌘D to split panes.
Agents keep running when you quit the app. Each panel can be light, mid-grey or dark on its own.

<img src="site/shots/workspace.png" alt="Workspace: sessions, files, terminal and plan" width="960">

### Edit, run and review without leaving. <sub>Editor · Review changes</sub>
Edit and run, with problems listed beside the code. Lines an agent changed carry its colour. Review the diff, comment
on a line to send it back to the agent, then commit.

| | |
|---|---|
| <img src="site/shots/editor.png" alt="Editor" width="470"> | <img src="site/shots/review.png" alt="Review changes" width="470"> |

### Your roadmap and a coach, built in. <sub>Work · Learn</sub>
Work shows your workstreams and tickets by phase, with the session working on each one. Learn is an
agentic-engineering coach: a 12-lesson narrated course and 17 starter skills ([`agentic_engineering/`](agentic_engineering/)).
Listen in the app, or send a skill straight to a session.

| | |
|---|---|
| <img src="site/shots/work.png" alt="Work" width="470"> | <img src="site/shots/learn.png" alt="Learn" width="470"> |

<sub>Screens show a busy, real-world workspace. Your own sessions, repos and tickets appear in their place.</sub>

## What's in this repo

| Part | Folder | What it is |
|---|---|---|
| **One Roof app** | [`app/`](app/) | The macOS app (Swift, libghostty terminals, herdr sessions) |
| **Agentic engineering starter set** | [`agentic_engineering/`](agentic_engineering/) | 17 short skills and a 12-lesson narrated course, bundled with the app |
| **The kit (`roof`)** | `bin/ guard/ shell/ lib/ templates/ tools/` | One launch folder, one memory, one rulebook for every agent, plus `roof swarm` for parallel agents in git worktrees. Works with or without the app |
| **Website** | [`site/`](site/) | The launch page, published at [gaurav8936.github.io/oneroof](https://gaurav8936.github.io/oneroof/) |

> **Early release (0.3.0).** Used daily on one Mac and tested on Apple-silicon Macs only. Expect rough edges,
> especially in first-run setup and agent detection on machines unlike ours. Please
> [open an issue](https://github.com/gaurav8936/oneroof/issues) with what you find; see [CONTRIBUTING.md](CONTRIBUTING.md).
> Known limits: Apple silicon only; the app is not yet signed with an Apple Developer ID (notarized build coming);
> the optional on-device model is a manual install for now.

## Install the app

**What you need**

| | What | How |
|---|---|---|
| Required | A Mac with Apple silicon, macOS 14 or later | |
| Required | [herdr](https://herdr.dev), which runs the agent sessions | `brew install herdr` (a ready-made package exists for macOS 15+ on Apple silicon; on macOS 14 Homebrew builds it from source, which takes a few minutes) |
| Required | git | `xcode-select --install` (Xcode Command Line Tools) |
| Required | At least one agent CLI, installed and signed in: `claude`, `codex`, `kimi`, `gemini` or `agy` | each agent's own installer |
| Optional | On-device task classifier and captions | `brew install llama.cpp` + the model file (see [app/README.md](app/README.md)) |
| Optional | Work view (workstreams and tickets) | a Linear API key, entered at setup or in Settings |
| Optional | Seat gauges for Claude | a Claude Code status line that writes usage files (see the help page on seats) |

Xcode, zig and the libghostty build are only needed to build from source.

1. Download `One-Roof-<version>.zip` from [Releases](https://github.com/gaurav8936/oneroof/releases), unzip it, and move
   **One Roof.app** to Applications.
2. **First launch:** the app is not yet signed by an Apple Developer ID, so macOS says it cannot verify it. You do this
   once:
   - **macOS 15 or later:** open the app and dismiss the warning, then System Settings › Privacy & Security › scroll
     down › **Open Anyway** next to One Roof, and confirm.
   - **macOS 14:** right-click (or Control-click) the app › **Open** › **Open**.
   - **Or, any version:** `xattr -dr com.apple.quarantine "/Applications/One Roof.app"` in Terminal.
3. **First-run setup** asks for your projects folder, an optional shared folder for rules and handoffs (it can create
   one), and which agentic-engineering folder to use (the bundled one, or your own skills repo). It shows which agents
   it found and whether each is signed in. Everything can be changed later in Settings (⌘,).
4. Optional: a Linear API key (Work view), and the on-device routing model (see [app/README.md](app/README.md)).

**Build from source** instead: see [app/README.md](app/README.md) (Xcode 26, zig 0.15, a one-time libghostty build).

The rest of this page is about **the kit**.

## The kit

If you use Claude Code, Codex, Kimi, Hermes or Gemini on the same projects, and especially if you run several sessions
at once, they only stay consistent if they read the same rules and the same notes. They usually don't:

- **Claude Code keys its memory on the launch folder.** Start a session in `~` instead of `~/Projects` and it reads
  and writes a *different* memory. Nothing warns you. We lost 26 notes to a hidden second memory over five weeks.
- **Every agent finds its instructions from the launch folder** (`CLAUDE.md`, `AGENTS.md`). Start in the wrong place
  and an agent works without your rules.
- **Codex and Kimi have no hooks**, so the usual "block it in a hook" fix doesn't reach them.

oneroof fixes this with the simplest controls that work, layered so a mistake has to get past all of them:

| # | Layer | What it does |
|---|---|---|
| 1 | Shell default | a new terminal that opens in `~` moves to your workspace |
| 2 | Agent wrappers | typing `claude` / `codex` / `kimi` elsewhere moves you first |
| 2b | PATH stand-ins | agents without hooks **refuse to start** outside the workspace (exit 64), even via `command codex` |
| 3 | Claude hook | **blocks every prompt** while a Claude session is outside the workspace |
| 4 | Home notes | `~/CLAUDE.md` + `~/AGENTS.md`: "wrong folder, stop" (conditional, optionally made immutable) |
| 5 | Memory pin | `autoMemoryDirectory`: one Claude memory, whatever the launch folder |

…plus the parts that keep agents consistent once they start in the right place:

- **A shared rulebook** (`_common/AGENTS.md`, with `CLAUDE.md` linked to it) that every agent's entry file points at,
  and a short `READ-FIRST.md` must-read list.
- **Handoffs in git**: the `next-session-handoff`, `last-call` and `where-are-we` skills write and read session
  bridges that any agent can resume from.
- **A starter set of agentic-engineering skills and a narrated course** in [`agentic_engineering/`](agentic_engineering/):
  17 short skills (plan, test-first, review, routing, parallel worktrees, shipping, gotchas) and 12 lessons. One Roof
  bundles it and uses it unless you point Settings at your own skills folder.
- **One skills folder for every agent**: `roof sync-skills` links each skill into Claude's, Codex's, Hermes's and
  Gemini's skills homes.
- **Bounded parallel agents**: `roof swarm run spec.json` runs tasks in separate git worktrees with non-overlapping file
  claims, a parallel ceiling, timeouts, capped retries and a disk check; `merge` and `clean` land and tidy the run.

The story behind it: *One workspace: the boring rules that made our agents agree* (gabblegrid.ai/blog).

### Install the kit

```bash
git clone https://github.com/gaurav8936/oneroof ~/oneroof
~/oneroof/bin/roof install                      # workspace ~/Projects, shared folder ~/Projects/_common
# or: roof install --workspace ~/code --agents "claude codex kimi hermes"
# open a new terminal, then:
roof doctor                                           # checks every layer, live
```

Add `~/oneroof/bin` to your `PATH` to type `roof`. `roof install --dry-run` shows what it would do. Install is
idempotent and **never overwrites** an existing file: your `~/CLAUDE.md`, your rulebook and your settings keys are
left alone (Claude's settings are merged, with a timestamped backup).

On macOS, `roof lock` prints the `sudo chflags` commands that make the home notes immutable. oneroof never runs
`sudo` itself.

### Commands

| Command | Does |
|---|---|
| `roof install [--workspace DIR] [--shared DIR] [--agents "…"] [--no-shell] [--no-home-notes] [--dry-run]` | set up every layer |
| `roof doctor` | check every layer live (blocks a fake session in `~`, starts a stand-in in `~`); exit 1 on any problem |
| `roof status` | show workspace, shared folder, agents, memory folder |
| `roof sync-skills <dir>` | link one skills folder into every agent's skills home (e.g. `agentic_engineering/skills`) |
| `roof swarm run spec.json [--dry-run]` | run tasks in parallel, one git worktree + branch each, non-overlapping file claims, timeouts, capped retries, disk check (`roof swarm --help`) |
| `roof swarm merge <run-dir>` | merge each green task branch into the current branch (`--no-ff`), stopping at the first conflict |
| `roof swarm clean <run-dir> [--force]` | remove the run's worktrees and its merged branches (`--force`: all its branches) |
| `roof lock` | print the commands that lock the home notes (macOS) |
| `roof uninstall` | remove what install added; your docs and memory stay |

One-off exception (owner only): `ROOF_ALLOW_OUTSIDE=1 claude`.

### What gets created

```
~/Projects/                     your workspace (any path)
  CLAUDE.md                     imports _common/AGENTS.md
  AGENTS.md                     points Codex/Kimi/Hermes at _common/AGENTS.md
  _common/                      the shared layer (the underscore sorts it first everywhere)
    AGENTS.md  CLAUDE.md → AGENTS.md
    docs/READ-FIRST.md  docs/standards/  decisions/  architecture/  runbooks/  references/  gotchas/  next-session-handoff/
~/CLAUDE.md  ~/AGENTS.md        conditional "wrong folder" notes
~/READ-FIRST.md                 link to the shared READ-FIRST
~/.claude/settings.json         + autoMemoryDirectory + two hooks (merged)
~/.config/oneroof/        config + bin/ stand-ins for codex, kimi, …
~/.zshrc / ~/.bashrc            + one line sourcing shell/oneroof.sh
```

## How it fits together

[docs/architecture/oneroof-kit.md](docs/architecture/oneroof-kit.md) explains the guarantees, the four context layers (shared truth → entry
files → private memory → session bridge) and why each layer exists. [docs/runbooks/adding-an-agent.md](docs/runbooks/adding-an-agent.md)
covers adding another agent, including Hermes, which keeps its own memory.

## Tests

```bash
bash tests/run.sh      # 59 checks in a throwaway HOME with fake agents: no real settings, shells or tokens touched
```

CI runs them on Ubuntu and macOS.

## Licence

MIT
