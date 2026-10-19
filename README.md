# One Roof

**A native Mac command center for the coding agents you run, plus the kit that keeps them consistent.**

| Part | Folder | What it is |
|---|---|---|
| **One Roof app** | [`app/`](app/) | A macOS app with real (libghostty) terminals for every agent session — Claude Code, Codex, Kimi, Gemini CLI, Antigravity — with live status, grouping, planned sessions, objectives that plan and run themselves, seat capacity and routing, code review, and a built-in course |
| **Agentic engineering starter set** | [`agentic_engineering/`](agentic_engineering/) | 17 short skills and a 12-lesson narrated course; bundled with the app and usable by any agent on its own |
| **The kit (`roof`)** | `bin/ guard/ shell/ lib/ templates/ tools/` | Shell layers that make every agent start in one workspace with one memory and one rulebook, plus `roof swarm` for parallel agents in git worktrees |

> **Early release (0.3.0).** One Roof has been used daily on one Mac and tested on Apple-silicon Macs only. Expect
> rough edges, especially on first-run setup and agent detection on machines unlike ours. Please
> [open an issue](https://github.com/gaurav8936/oneroof/issues) with what you find; see [CONTRIBUTING.md](CONTRIBUTING.md).
> Known limits: Apple silicon only; the app is not yet signed with an Apple Developer ID; the optional on-device model
> is a manual install for now.

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
