# One Roof (Mac app)

A native macOS command center for running several CLI coding agents at once (Claude on one or two accounts, Codex, Kimi,
Antigravity, Gemini). Each session is a real interactive CLI running in roofd, One Roof's own session manager, drawn by
[libghostty](https://github.com/ghostty-org/ghostty) inside One Roof. The sidebar shows every session's live status,
agent, account, repo and project, grouped automatically. Design docs live in `../docs/` of this repo.

## One Roof v2 (2026-10-18)

The interface was rebuilt from the UI v2 packet (`ui_mockups/20261018_01_initial_v2/`, shared spec copied to
`labs/oneroof/docs/architecture/v2-ui/`); the runtime then was herdr; since 0.4.0 it is roofd (libghostty, SQLite, no new dependencies). Everything below from v0.1 still
works; deviations and moved shortcuts are in `IMPLEMENTATION_NOTES.md`. Rollback: tag `v0.3.0-final-v1ui`.

- **Three themes per panel**: Daylight · Graphite · Midnight for Sessions, Files, Terminal, Plan and centre views
  (Settings › Appearance grid, View › … Theme). v0.1 choices migrate once (Paper retired, Blueprint terminal-only).
- **Workspace windows** (⇧⌘N): each main window is a workspace with its own sessions; Move to Window from any row;
  Window ▸ Workspaces (⌥⌘1–9). Overview, Board, Decisions and Subagents show every window.
- **Toolbar**: Workspace · Overview · Board · Decisions · Work · Learn, the workspace menu, search (⌘K), panel toggles,
  + New session.
- **Captions** (one line per session: what it is doing now), an **FYI feed**, **chapters** over the terminal, from the
  caption engine (heuristic first; the on-device model when llama-server runs).
- **Decisions** (⌘I): every agent waiting on you with its reason in its own words, what the command touches, risk,
  what happens if you say no; Allow once · Always · Deny · Reply send the agent's own keys. Plans to approve too.
- **Subagents** (⇧⌘A): Claude subagents as a timeline from the transcript.
- **Editor** (open a text file): tabs, syntax colours, problems (ruff / swiftlint / tsc), Run ⌘R / Debug ⇧⌘R in a dock
  terminal, ⌘I asks an agent about the selection, saves wait while an agent's step claims the file.
- **Review changes** (⌥⌘R): files, diff with "What the agent did", comments sent to the agent, checks from its output,
  Commit (never pushes).
- **New work** (⌘N): intake (session · ticket · defect · project), duplicate check, agent cards with seat usage and the
  router's suggestion, start folder, opening message, When (Now · Next · Tonight · On demand).
- **Menu-bar extra**: needs you / working counts; Allow from the popover.

## What it does (v0.1, MVP)

- **Three panels, three themes, each panel themed on its own.** Light / Dark / Dim. Default: light sidebar, dark
  terminal, dark plan panel. Change them at the bottom of the right panel or in View › … Theme.
- **Live status from roofd**: Needs you (agent is blocked on a question or permission), Working, Ready (finished a turn
  you have not looked at), Idle, plus One Roof's own Planned, Next, Exited and Do not use. The Dock badge counts sessions
  that need you.
- **Account detection from the running process.** One Roof reads `CLAUDE_CONFIG_DIR` / `CODEX_HOME` from the agent's
  own environment (sysctl), so Claude1 vs Claude2 is right however the agent was started.
- **Automatic grouping** by status, repo, project, agent or account (View › Group by, ⌘1–⌘5). No dragging.
- **Planned sessions (⌘N).** Name, agent, account, repo, project, objective, opening message, optional agent
  arguments. Launch starts it in roofd; the opening message is sent only once the agent is ready and idle.
- **Bring a conversation over from another terminal.** In ⌘N, *Resume* lists your recent Claude conversations by their titles (both
  accounts share one conversation folder). Pick one, launch, and the conversation continues inside One Roof. If it was
  active in the last 15 minutes One Roof warns you: close it in the other terminal first so two Claudes don't write to it.
- **Agents survive One Roof.** roofd owns the terminals (one small holder process per session, run by a background
  item). Quit or update One Roof and every agent keeps running; reopen it and they are all still there.
- **A regular terminal too (⌘T).** File › New Terminal opens a plain shell in the projects folder (⌘⇧T: in the selected
  session's repo). roofd keeps it like any session, colours are untouched and the prompt follows the output.
- **Agent, account and model per session.** The model goes to the CLI as `--model <name>` (Claude: opus / sonnet /
  haiku; Kimi: its two coding models; any name works). Defaults per agent live in Settings › Agents.
- **Settings (⌘,):** General (Dock badge, startup check switch for I6, roofd status), Appearance (the three panel
  themes), Agents (default account, model, extra arguments), Foundations (the projects folder, the agentic-engineering and shared
  folders One Roof reads from; it never copies them). The agentic-engineering folder is a setting: `ONEROOF_AE_PATH`
  wins, then the folder chosen here (Choose…), then the copy bundled with the app (`agentic_engineering/`, Use
  bundled). A chosen folder that disappears falls back to the bundled copy.
- **Stickers, colours and icons ("Apple meets terminal", I5).** Bold stickers with icons (Next, WIP, Important,
  Blocked, Review, Idea, Bug, Research, Shipped, Do not use, or any word of your own, which keeps its colour) that pop
  on a light or dark sidebar; a colour per row; an emoji or the agent's logo; pinned sessions on top; double-click a
  name to rename; time since last active. Right-click (or •••) opens a colourful menu with big action tiles and the
  sticker, colour and icon pickers. Settings › Appearance switches stickers between Bold and Soft.
- **Objectives with visible planning (⌘⇧O, I7).** Type an objective (what, done when, repo, urgency, budget). A
  planner session (Claude, in a terminal you can watch) uses the `plan-objective` skill from the agentic-engineering folder
  to write a plan file (Markdown + a `oneroof-plan` JSON block) next to the project's docs. The plan shows as step
  cards: change agent, account, model or order, delete steps, then Approve. One Roof runs ready steps as sessions,
  at most 3 at a time, in dependency order; each step writes a `.done` / `.failed` marker and the next steps start.
  Objectives appear on the Launchpad.
- **Launchpad (⌘⇧L).** One page of all the work: what needs you, what is running, up next, just finished; the
  projects in play with ticket progress and the next ticket; agents at work; the foundations. Covers every One Roof
  window on this Mac (one store, one roofd).
- **Board (⌘B).** A Kanban of every session, left to right: Planned → Next → Working → Needs you → Ready → Idle →
  Exited → Do not use. Drag between Planned, Next and Do not use.
- **Work (⌘⇧W): projects, roadmap and tickets in one place.** Every project from Linear with its phases and
  tickets (status, type), the sessions working on it, and links to its tracker pane and docs. Plan a session from any
  ticket (launching it moves the ticket to In Progress); the session row shows the ticket key. Change a ticket's state
  from its pill; closing a ticket's session posts a summary comment (run time, newest handoff, notes) and moves it to
  In Review; the plan panel shows the live ticket with In Progress / In Review / Done.
- **New work item (⌘⇧N): decide what it is before creating it.** One Roof suggests project, ticket (deliverable,
  defect, spike, decision, chore) or just a session, checks the project for a similar ticket, then creates the
  ticket in Linear. A new project is created in Linear with its milestones, then a planned Claude session sets up its docs
  and first tickets.
- **Foundations (⌘⇧F) and the startup check.** At every launch One Roof runs the workspace's own checks (doors, MCP
  list, skills links vs `sync-skills --dry-run`, memory pin, launch guard, hooks, logins, roofd). Red problems block
  starting an agent (with Launch anyway); Fix runs the command in a One Roof terminal. Tabs show the skills in the
  agentic-engineering folder (which agent homes have each), the hooks and rules, and the memory, handoffs (Resume) and
  gotchas. `OneRoof --check` prints the same check in a terminal. Nothing is copied from those repos.
- **Notes and stickers** per session (right panel), stored in
  `~/Library/Application Support/One Roof/sessions.sqlite`.

- **Orchestrator (I8).** Seat gauges (Claude1/2 from the status line, Codex from its logs) on the Launchpad and in
  the sidebar. A router reads `routing.json` and `roles.json` in place from the agentic-engineering folder
  (`skills/*/agent-routing/`, or `harness-routing/` in older skill libraries):
  kind → agent and model, budget, skip seats near their limit, the emptier Claude seat, reviews off the author.
  Suggest / Route all in the plan view; Suggest agent and Role in Plan a session. An on-device model (Arch-Router
  1.5B via llama.cpp, `brew install llama.cpp`, model file set in Settings › Foundations) classifies a task's kind in ~0.2 s. Rotation: a
  step whose seat is near its limit writes a handoff and continues on the next agent.

- **Learn (⌘⇧E, I9).** The course (`course/NN-*.md`, narrated from `course/audio/<lesson>/`), the field manual and
  narrated skill pages when the folder has them, every skill's `SKILL.md`, One Roof's Help and your extra Learn folders, browsable and
  searchable inside One Roof, read where they live. Foundations ›
  Skills has a Learn button per skill.

- **Layout and navigation (owner round + terminal-app parity).** Title bar: Terminals · Launchpad · Board · Work · Learn and
  buttons to open or close every panel, the centre included (⌘⌥S / ⌘⌥B / ⌘⌥C / ⌘⌥P). Files, plans and docs open in a
  centre viewer (code with line numbers, Markdown, images, HTML, folders). Session › Open in New Window (⌘⌥O) moves a
  session into its own window. Find in terminal (⌘F, ⌘G). ⌘-clicked links open files in the viewer. Command palette
  (⌘P) over views, actions, sessions, objectives, projects, repo files and skills. Five themes (Light, Paper, Dim,
  Dark, Blueprint), chosen per panel: sessions, files, terminal, plan.

Not yet (terminal-app parity, see 05_warp-parity.md): split panes, git diff panel, branch/diff on rows, notifications.

## Install on a new Mac

1. **Required tools.** git, from the Xcode Command Line Tools (`xcode-select --install`). Sessions run in roofd, which
   ships inside the app as a background item (macOS asks once to allow it); nothing else to install.
2. **Agents.** Install whichever agent CLIs you use (`claude`, `codex`, `kimi`, `gemini`, `agy`); One Roof finds them on
   your PATH. Claude is "Claude1" (`~/.claude`); a second Claude account appears as "Claude2" only when
   `~/.claude-2` exists (start it with `CLAUDE_CONFIG_DIR=~/.claude-2 claude`).
3. **Get the app.** Build it (below) and copy `build/One Roof.app` to `/Applications`, or run `scripts/install.sh`.
4. **First launch opens Setup** (also One Roof › Setup… at any time):
   - **Projects folder:** where agents start and where repos are listed (`<projects>/<domain>/<repo>`). Default
     `~/Projects` if it exists, else your home folder.
   - **Shared rules and docs (optional):** a folder with your shared rules, handoffs (`docs/next-session-handoff/`),
     gotchas (`docs/gotchas/`), plans and workspace check scripts. Default `<projects>/_common`. "Create it" makes an
     empty one; "Skip" leaves it out: handoffs, gotchas and the doors/MCP checks then stay quiet (amber, never a crash),
     and plans go to `~/Library/Application Support/One Roof/plans/`.
   - **Agentic engineering:** the skills, routing rules and course bundled with the app, or your own folder with a
     `skills/` tree.
   - **Required tools and agents:** git, then claude (with the signed-in email of each account), codex, kimi,
     gemini and agy, each found or not. Nothing here blocks Start.
   - **Linear (optional):** paste an API key; it is saved to `~/.config/oneroof/linear-api-key` (mode 0600).
     `LINEAR_API_KEY` in the environment also works. Without a key the Work view says Linear is not connected.
5. **On-device model (optional).** For one-line captions and task routing, `brew install llama.cpp` and download
   the Arch-Router-1.5B GGUF (Q4_K_M quantisation, published on Hugging Face) to
   `~/Library/Application Support/One Roof/models/Arch-Router-1.5B-Q4_K_M.gguf` (or choose another path in
   Settings › Foundations). Without it, captions and routing use heuristics.

```bash
open "/Applications/One Roof.app"          # installed build
# or from this folder:
scripts/bundle.sh release && open "build/One Roof.app"
open "build/One Roof.app" --args --fresh-profile   # try it as a brand-new user (see below)
```

Keys: ⌘N plan a session · ⌘T new terminal · ⌘↩ launch the selected session · ⌘] / ⌘[ next / previous session ·
⌘L focus the terminal · ⌘K clear the terminal · ⌘+ / ⌘− / ⌘0 text size · ⌘⌥S / ⌘⌥P toggle sidebar / plan panel ·
⌘1–⌘5 group by · ⌘, Settings · ⌘⌥F focus (terminal only) · ⌘⇧L Launchpad · ⌘B Board · ⌘⇧W Work ·
⌘⇧O new objective · ⌘⇧N new work item · ⌘⇧F Foundations. The terminal header has buttons to hide either panel. The Session menu has Launch, Mark as Next / Planned, Do Not Use, Open Repo in Finder,
Copy Attach Command, Close Agent and Delete; Help opens One Roof Help, this README and the release notes (all bundled
in the app).

**Launch folder.** Agents start in the projects folder. Tick "Start inside the repo folder" to start in the repo
instead; Claude may then ask to trust that folder once, and the session shows **Needs you** until you answer in its
terminal.

### Settings (⌘,) › Foundations

| Setting | Default | Environment override |
|---|---|---|
| Projects folder (`projectsPath`) | `~/Projects` if it exists, else home | `ONEROOF_PROJECTS` |
| Shared rules and docs (`commonPath`) | `<projects>/_common` | `ONEROOF_SHARED` |
| Agentic engineering (`agenticEngineeringPath`) | the copy bundled in the app | `ONEROOF_AE_PATH` |
| Learn folders (`learnFolders`) | none. Each folder's `.md` files become pages; each sub-folder of `.mp3` files a narration list | |
| On-device model (`localModelPath`) | `~/Library/Application Support/One Roof/models/Arch-Router-1.5B-Q4_K_M.gguf` | `ONEROOF_MODEL` |
| Linear key | `~/.config/oneroof/linear-api-key` | `LINEAR_API_KEY` |

The other tabs: General (Dock badge, startup check), Appearance (theme per panel, text size, stickers), Agents (default
account, model and arguments per agent), Captions (on-device captions, scheduled runs, menu-bar extra), Shortcuts.
Settings are JSON under the `settings` key of the `io.github.gaurav8936.oneroof` defaults domain; `setupDone` records
that Setup was completed.

### `--fresh-profile`

`OneRoof --fresh-profile` (or `ONEROOF_FRESH_PROFILE=1`) starts One Roof as on a new Mac: preferences come from a
separate suite (`io.github.gaurav8936.oneroof.fresh`, emptied at every start), sessions go to a throw-away store in the
temporary folder (unless `ONEROOF_STORE` names one), and nothing is migrated, so Setup opens every time. Your real
settings and sessions are not touched. Screenshot it with `scripts/selftest-shot.sh setup ONEROOF_FRESH_PROFILE=1`.

### Upgrading from an early build

Builds before 0.2 used the bundle id `com.gaurav8936.oneroof`. On first launch One Roof copies every preference from
that domain once (read-only; the old domain is left as it was), fills in the folders those builds assumed, marks Setup
as done and sets `migratedFromLegacy`.

## Build from source

```bash
brew install zig@0.15
xcodebuild -downloadComponent MetalToolchain   # Xcode 26 required by Ghostty
scripts/build-ghosttykit.sh                    # Ghostty v1.3.1 → ~/Library/Caches/oneroof/ghostty (135 MB, not in git; ONEROOF_GHOSTTY_DIR overrides)
scripts/bundle.sh release                      # → build/One Roof.app (ad-hoc signed; bundles agentic_engineering, docs/help, README, release notes)
scripts/install.sh                             # → /Applications/One Roof.app
swift test                                     # unit tests (OneRoofCore)
```

**Release zip.** `tools/package-app.sh` (repo root, clean tree only) makes `dist/One-Roof-<version>.zip` + `.sha256`
without touching this checkout: it copies the Ghostty source to `/private/tmp/oneroof-release/ghostty` and rebuilds
libghostty there with zig's caches beside it (`build-ghosttykit.sh --release-build`), builds the app from `git archive
HEAD` in `/private/tmp/oneroof-release/src` with debug-info paths mapped to `.` (`bundle.sh release`; a release build
compiles no source path and reads its folders from the app's Resources only), and zips with `ditto --norsrc --noextattr --noacl`.
The gate (`tools/release-check.sh --app` / `--zip`) fails the run if the app holds a home-folder path, a zig cache
path, an absolute `.swift` source path or the build machine's hostname, or the zip has `__MACOSX` entries. `ONEROOF_RELEASE_DIR` moves the staging folder.

**A release is finished only when it can be downloaded everywhere.** Merging to `main` builds no app. After the zip:
publish GitHub release `v<version>` with the zip and its `.sha256` and make it Latest; point every download link in
`site/` (`index.html`, `assets/site.js`) at `One-Roof-<version>.zip` and ship that to `main`, which republishes the
Pages site; update any other launch page that links the zip. Then open each page and check that it serves the new file.

## Layout

| Path | What it is |
|---|---|
| `Package.swift` | Swift 6 package: `OneRoofCore` library, `OneRoof` app, tests, `GhosttyKit` and `RoofVT` binary targets, `roofd` daemon |
| `Sources/OneRoofCore/` | No UI. `Session` (model + statuses), `RoofdRuntime` (roofd unix-socket JSON API), `ProcessProbe` (argv/env of a PID via sysctl), `Workspace` (repo labels, project codes, accounts), `Board` (merge stored sessions with live agents, grouping), `SessionStore` (SQLite), `Theme` (3 themes, contrast-checked) |
| `Sources/OneRoof/Ghostty/` | `GhosttyRuntime` (one libghostty app, one config per theme) and `TerminalSurfaceView` (libghostty surface in an NSView; keyboard/IME/mouse ported from Ghostty's macOS app, MIT) |
| `Sources/OneRoof/UI/` | SwiftUI sidebar, plan panel, new-session sheet; AppKit terminal area |
| `Sources/OneRoof/AppModel.swift` | State: polls roofd every second, probes accounts, launches sessions, delivers opening messages |
| `Sources/OneRoof/SelfTest.swift` | In-process test hooks (`ONEROOF_SELFTEST_*` env vars): select, type, snapshot the window to PNG + terminal text + JSON |
| `scripts/` | `build-ghosttykit.sh`, `bundle.sh`, `install.sh`, `make-icon.py`, `ax-drive.swift` (drive a running One Roof by pid through Accessibility) |
| `Vendor/GhosttyKit.xcframework` | Symlink to the libghostty build made by `scripts/build-ghosttykit.sh` (gitignored) |

## Testing without taking over the screen

- **In-process:** `ONEROOF_SELFTEST_*` variables (see `SelfTest.swift`) open terminals, plan and launch sessions, open
  Settings, press menu items and write a PNG of every window plus the terminal text. A self-test window stays behind
  your other windows and never takes keyboard focus.
- **Accessibility:** `swift scripts/ax-drive.swift <pid> menus | menu "Session" "Do Not Use" | texts | tree | press "<button>"`
  presses menu items and buttons and reads the sidebar of one One Roof process, not whatever app is in front. Run
  test copies with `ONEROOF_STORE=<scratch file>` so your sessions are untouched.

## Safety rules built in

- Agents start only inside the projects folder.
- One Roof never types into a busy or blocked agent; roofd sends an opening message only once the agent is ready and
  idle, and once more if it did not start working.
- Each session gets a clean environment: account variables, other agents' markers and test settings are removed unless
  the launch sets them.
- Claude1 launches never set `CLAUDE_CONFIG_DIR` at all: an empty value makes Claude use the current folder as its
  config folder.

## Licences

One Roof's code: see the repo `LICENSE`. libghostty (Ghostty) is MIT; roofd's terminal core (RoofVT) is built on Ghostty's ghostty-vt (MIT). `TerminalSurfaceView.swift` and `GhosttyRuntime.swift` adapt code from Ghostty's macOS app (MIT,
© Mitchell Hashimoto and Ghostty contributors).

## Signing and notarization (removes the "cannot verify" warning)

One-time setup, by the maintainer:

1. Join the Apple Developer Program (developer.apple.com/programs, individual or organization).
2. Xcode › Settings › Accounts › Manage Certificates › **+** › **Developer ID Application**. Check it with
   `security find-identity -v -p codesigning`.
3. Store notary credentials (an app-specific password from appleid.apple.com, or an App Store Connect API key):
   `xcrun notarytool store-credentials oneroof-notary --apple-id <apple id> --team-id <TEAM ID>`.

Then every release is the usual command with two variables set:

```bash
ONEROOF_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAM ID>)" ONEROOF_NOTARY_PROFILE=oneroof-notary \
  tools/package-app.sh
```

`tools/sign-and-notarize.sh` signs every executable in the bundle inside-out with the hardened runtime
(`app/Resources/OneRoof.entitlements`, no exceptions), submits to Apple, staples the ticket and checks it with
`spctl`. `tools/sign-and-notarize.sh <app> --runtime-test` applies the hardened runtime with an ad-hoc signature, to
check the app still works without an Apple account.
