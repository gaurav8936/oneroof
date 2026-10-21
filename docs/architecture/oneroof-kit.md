# Architecture

## Guarantees

| # | Guarantee | Made true by |
|---|---|---|
| G1 | **One launch point**: no agent works outside the workspace | layers 1, 2, 2b, 3, 4 |
| G2 | **One memory**: exactly one Claude memory folder receives writes | layer 5 (`autoMemoryDirectory`) |
| G3 | **One rulebook**: every agent's entry file resolves to the shared folder | workspace `CLAUDE.md` / `AGENTS.md` → `_common/AGENTS.md` |
| G4 | **Memory loads fully**: the memory index stays ≤ 150 lines, pointers only | `roof doctor` check · `last-call` step 4 |
| G5 | **Durable facts are shared facts**: anything another agent needs lives in the shared docs | rulebook rule 2 · `last-call` step 3 |
| G6 | **One copy of shared content**: written once, linked everywhere | rulebook rule 3 |

## How each agent loads context

| | Claude Code | Codex CLI | Kimi Code | Hermes Agent |
|---|---|---|---|---|
| Instruction files | `CLAUDE.md` in the launch folder **and every parent**; `@path` imports | `AGENTS.md` from the repo root down to the launch folder, plus `~/.codex/AGENTS.md` | `AGENTS.md` in the launch folder | `AGENTS.md` (or `.hermes.md`) in the project |
| Private memory | per launch folder, unless `autoMemoryDirectory` pins it | — | — | global `~/.hermes/memories/` (MEMORY.md, USER.md) |
| Hooks | yes | no | no | no |
| Guard used | hook (layer 3) | PATH stand-in (2b) | PATH stand-in (2b) | PATH stand-in (2b) |

Three consequences drive the design:

1. **The launch folder is load-bearing.** It picks Claude's memory and every agent's instruction files.
2. **Parent folders leak.** Claude reads `~/CLAUDE.md` from inside `~/Projects` too, so the home note must be
   conditional ("only if you are exactly in `~`").
3. **Agents without hooks can only be stopped before they start**: by the shell and by a stand-in first on `PATH`.

## Four context layers

```
 L0  SHARED TRUTH    <workspace>/_common/docs/      git-tracked · every agent reads it
                     READ-FIRST.md · standards/ · decisions/ · gotchas/ · next-session-handoff/ (L3)
 L1  ENTRY FILES     <workspace>/CLAUDE.md (@import) · AGENTS.md (pointer) · per-repo banners → L0
 L2  PRIVATE MEMORY  Claude: ONE pinned folder · Hermes: ~/.hermes/memories · small index, pointers to L0
 L3  SESSION BRIDGE  handoffs written into L0 by the handoff skill → any agent resumes from git
```

| Layer | Rule |
|---|---|
| L0 | Anything durable goes here. If another agent would need it, it must be in L0. |
| L1 | Pointers and imports only, never the only copy of a rule. |
| L2 | One folder per agent, small index, working notes. A rule that exists *only* here is a defect: lift it to L0. |
| L3 | Always written into L0 (git), never into a private folder. |

## Design decisions

| Decision | Chosen | Rejected, and why |
|---|---|---|
| Unify Claude's memory | `autoMemoryDirectory` in user settings | symlinking the stray memory to the real one: makes the wrong folder *work* and hides the mistake |
| What the hook does | block prompts | auto-cd (a hook can't change the session's folder) · warn only (ignorable) |
| Home-note wording | conditional on cwd = `~` | unconditional "stop": would stop every workspace session (parent-folder loading) |
| Hard stop for Codex/Kimi | PATH stand-in | instruction text only: soft · renaming the real binaries: breaks upgrades |
| Shell behaviour | move, don't refuse | refusing adds friction without adding safety (layers 2b–5 back it up) |
| Path comparison | logical **and** physical paths, case-folded on macOS, whole segments | plain string prefix: `~/ProjectsOld` would pass, a symlinked workspace would fail |
| Installer | idempotent merge, never overwrite, backup first | templated overwrite: destroys user edits |

## The One Roof app: where sessions run

The app's sessions run in **roofd**, One Roof's own session manager (since 0.4.0; it replaced herdr, see
[the decision](../decisions/20261020_01_roofd-replaces-herdr.md)). It ships inside the app; there is nothing else to install.

- **One daemon, one holder per session.** `roofd daemon` is the control plane (create, list, info, read, input,
  close over newline-delimited JSON on `roofd.sock`). Each session is its own holder process with its own socket; it
  owns the PTY and the child. Holders outlive the app and the daemon, so quitting, updating or a crash never ends a session.
- **RoofVT** (Zig over Ghostty's `ghostty-vt`) is the headless terminal in each holder: it redraws a reattached
  surface and answers `read`. The app draws the terminal with libghostty, which runs `roofd attach <id>`.
- **Status** comes from the holder: Claude's hooks (`roofd report claude`), prompts on screen, then output activity,
  giving Needs you · Working · Ready · Idle · Exited.
- **Scheduler:** with "Allow scheduled runs" on, the daemon starts Tonight, Nightly and repeating sessions from the
  session store, app open or closed; the holder sends the opening message once the agent is ready.
- **Background item:** launchd runs roofd at login (`SMAppService`, label `io.github.gaurav8936.oneroof.roofd`);
  until it is approved in Login Items, the app starts roofd itself.
  Sockets live in `~/Library/Application Support/One Roof/roofd/`. Sessions end at logout or restart.
- **G1 still holds:** a scheduled run uses the same launch plan as the Launch button and is refused outside the workspace.

## Residual risks

- Agents with neither hooks nor a CLI on `PATH` (some editor-embedded agents) are covered by the shell layer only.
- Cloud sessions have no local memory; they stay consistent only through L0 in git (why G5 matters).
- A second machine needs `roof install` too.
- Any agent that adds its own memory reopens G2 for that agent: see [adding-an-agent.md](../runbooks/adding-an-agent.md).
