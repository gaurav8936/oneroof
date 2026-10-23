# roofd

**A session manager for terminal coding agents on macOS.** roofd runs Claude Code, Codex, Gemini CLI and other agent
CLIs in sessions that outlive the app showing them. A session keeps running when its window closes, when the app
quits or updates, and when the daemon itself crashes. Any terminal can reattach to it later and see the screen
exactly as the agent left it.

roofd is the runtime inside [One Roof](https://github.com/gaurav8936/oneroof), a native Mac command center for coding
agents. This repository is a **read-only copy for reading and building**. Development happens in One Roof, and this
copy is regenerated from it. See `PUBLISHED_FROM` for the exact commit.

## How it works

```
 terminal (libghostty) ── roofd attach <id> ──┐             roofd daemon  ── control: create · list · info · read
                                              │  frames       (no session      input · signal · close (JSON lines
                                              ▼               state)           on roofd.sock)
                                     ┌─────────────────┐            │
                                     │ holder process  │◄───────────┘ one socket per session
                                     │  PTY + child    │
                                     │  RoofVT screen  │  headless Ghostty terminal: redraw on attach, `read`
                                     │  status engine  │  working · blocked · done, from hooks and the screen
                                     └─────────────────┘
```

- **One holder process per session.** It owns the PTY and the agent process, and serves attach clients and control
  requests on its own Unix socket. Sessions are isolated from each other and from the daemon. A crash in one never
  ends another, and a restarted daemon finds the running holders again by their sockets.
- **The daemon keeps no session state.** It is the control plane: newline-delimited JSON on `roofd.sock`, one daemon
  per folder (enforced with a file lock), started by launchd. On upgrade, the new binary takes over the lock while
  every session keeps running.
- **Bytes are forwarded first and parsed second.** Agent output goes straight to the attached terminal. A copy is fed
  to **RoofVT** (a small Zig library over [Ghostty](https://github.com/ghostty-org/ghostty)'s `ghostty-vt` core) on a
  separate queue, off the hot path. RoofVT holds the screen, so a reattach gets an exact redraw, and `read` returns the
  text on screen.
- **`roofd attach` is transparent.** It has no screen, keys or alternate screen of its own; it just moves bytes. Native
  selection, scrollback and shell prompt marks therefore work in the outer terminal, and each byte passes through only
  one terminal emulator.
- **Detached sessions don't hang.** With no terminal attached, the holder answers the agent's terminal queries (device
  attributes, colours) itself, in order. Full-screen CLIs such as Codex wait for those answers before drawing anything.
- **Agent status lives in the holder,** so it stays accurate with the app closed. It comes from Claude Code's hooks
  (`roofd report claude`) when available, then from prompts on screen, then from screen activity.
- **Memory guards.** Holders warn at 1 GB and end the session at 2 GB. The daemon restarts itself if its own footprint
  grows. Every loop turn runs in its own autorelease pool. Input queues and frame sizes are bounded.
- **Process spawning is done in C** (`CRoofSpawn`: fork, setsid, controlling TTY, execve), the one part Swift must not
  do itself. The session's environment, which can contain API keys, reaches the holder over a pipe on stdin, never on
  its command line, where `ps` would show it.

The full design record, including why roofd replaced the herdr session manager, is in [docs/design.md](docs/design.md).

## Commands

```
roofd daemon                                   the control plane (launchd runs it)
roofd create --id ID [--cwd D] [--label L] [--cols N --rows N] [--env K=V ...] -- <argv...>
roofd attach ID                                show a session in this terminal
roofd list | info ID | read ID [lines] | input ID TEXT [--submit] | close ID
roofd hello                                    protocol version and daemon build
```

`ROOFD_DIR` sets the socket folder (the default is `~/Library/Application Support/One Roof/roofd`).

```bash
export ROOFD_DIR=/tmp/roofd-demo
.build/debug/roofd daemon &
.build/debug/roofd create --id demo -- /bin/zsh -l
.build/debug/roofd attach demo        # detach by closing the terminal; the session keeps running
.build/debug/roofd read demo 20       # the last 20 lines on its screen
```

## Build and test

Needs macOS 14+, Xcode 16+ (Swift 6) and zig 0.15.

```bash
brew install zig@0.15
scripts/build-roofvt.sh     # once: fetches Ghostty v1.3.1 and builds Vendor/RoofVT.xcframework
swift build
swift test                  # protocol and memory tests against a real daemon in a temp folder
```

## Layout

| Path | What it is |
|---|---|
| `Sources/roofd/` | The session manager: `Daemon` (control plane), `Holder` (one session), `Attach` (the byte pipe), `Wire` (sockets and framing), `Scheduler` (scheduled runs, from One Roof's session store), `main` (commands). |
| `Sources/CRoofSpawn/` | Spawning a child on a new PTY, in C. |
| `RoofVT/` | The Zig library over Ghostty's VT core: one headless terminal per session. |
| `Sources/OneRoofCore/` | The part of One Roof's core library that roofd builds against, unchanged: the status engine, agent kinds, process probe and the session store the scheduler reads. It also contains app-side code that those files reference. |
| `Tests/RoofdTests/` | Framing, idempotent create, redraw-before-output ordering, upgrade hand-over and memory limits, against a real daemon. |

## License

MIT, see [LICENSE](LICENSE). RoofVT builds against Ghostty, which is also MIT licensed.
