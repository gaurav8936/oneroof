# ADR · roofd, One Roof's own session manager, replaces herdr

**Status:** ACCEPTED (shipped in One Roof 0.4.0) · **Date:** 2026-10-20 · **Supersedes in part:** [20261017_01_one-roof-swift-libghostty-herdr.md](20261017_01_one-roof-swift-libghostty-herdr.md) (the herdr runtime; the Swift app and libghostty terminals stand)

> **One line:** One Roof runs its sessions in roofd, a small session manager shipped inside the app (a daemon plus one holder process per session, with RoofVT, a headless Ghostty terminal, in each holder), so every byte from an agent passes through one terminal emulator, libghostty, and herdr is no longer installed or used.

## Context

Since 0.1 every One Roof terminal was a libghostty surface running `herdr agent attach`. herdr parsed each agent's output into its own grid and re-rendered it through a full-screen attach client, so each byte went through two terminal emulators. That layering caused the problems users saw:

- **Copy needed a workaround:** herdr's client turned on mouse tracking, so a plain drag went to herdr, not to libghostty's selection.
- **No real scrollback:** the client drew on the alternate screen, so nothing reached libghostty's history; search and step rewind had nothing to scroll into.
- **Shell prompt marks were lost:** herdr did not forward OSC 133.
- **Extra latency** from parsing and repainting twice.
- **An install step** (`brew install herdr`) and a red startup check without it.
- **A pre-1.0 protocol** One Roof did not control, floating with Homebrew.

herdr's API had no raw byte stream per pane, so none of this could be fixed from One Roof's side.

## Decision

**Build roofd, One Roof's own session manager, in Swift inside the app's package, and remove herdr completely in one cut-over (no fallback runtime).**

- **`roofd daemon`** is the control plane: create, list, info, read, input, close (and a scheduler setting) as newline-delimited JSON on `roofd.sock`. It holds no session state of its own.
- **One holder process per session** owns the PTY and the child, serves attach clients and control requests on its own socket, and keeps **RoofVT** (a Zig shim over Ghostty's `ghostty-vt`) as headless terminal state for redraw and `read`. Bytes are forwarded first, then fed to RoofVT, off the hot path.
- **`roofd attach <id>`** is what each libghostty surface runs: a byte pipe with no screen of its own.
- **Status lives in the holder:** Claude's hooks (`roofd report claude`), then prompts on screen, then screen activity.
- **The holder delivers the opening message** once the agent is ready, with the same rules the app used.
- **A scheduler in the daemon** starts Tonight, Nightly and repeating sessions from the session store when the owner allows scheduled runs.
- **launchd runs roofd** as the app's background item (`SMAppService`, label `io.github.gaurav8936.oneroof.roofd`).
- The app reaches roofd only through its `SessionRuntime` interface (`RoofdRuntime`), so the views do not know which runtime is underneath.
- Swift, not Zig or Rust, because the status engine, agent kinds, process probe and protocol types are written once in `OneRoofCore` and tested in the same `swift test` run as the app. Small shims cover what Swift cannot do: a C target for spawning, Zig for RoofVT.

## Why

- **One emulator end to end:** native selection and copy, real scrollback, prompt marks, and much faster keystroke echo (see the 0.4.0 changelog).
- **Nothing to install** but the agents themselves; the same team ships both ends of the protocol in one bundle.
- **Sessions still outlive the app:** every holder is its own process, so quitting, updating or a daemon crash never ends a session, and one session's crash never ends another.
- **Status gets better signals:** hooks first for Claude, the same screen rules for every agent, and an output sequence number that drives captions.
- **Schedules and loops run with the app closed**, because the daemon and the holders do the launching and the typing.

## Rejected

- **Keep herdr** — the two-emulator problems cannot be fixed from outside it.
- **Keep herdr as a fallback for one release** — rejected by the owner: one runtime, one cut-over, no mixed fleet.
- **Write roofd in Zig or Rust** — protocol, agent kinds and status rules would be duplicated in a second (or third) language and kept in sync by tests.
- **A second emulator in the daemon (a Rust VT crate)** — Ghostty's own VT state matches what libghostty draws.

## Consequences

- **As built (0.4.0, 2026-10-20):** roofd is the only runtime; `HerdrRuntime` and every herdr call are deleted (herdr is left only in comments and stored key names). `Session.herdrAgent` / `herdrWorkspace` became `runtimeId` / `runtimeGroup`; the stored keys are unchanged, so old rows load.
- Building needs zig 0.15 for RoofVT as well as GhosttyKit (`app/roofd/build-roofvt.sh`, same pinned Ghostty v1.3.1 source). A release build uses a neutral zig package cache so no build-machine path ends up in the binary.
- roofd's sockets live in `~/Library/Application Support/One Roof/roofd/` (one daemon per folder, `roofd.lock`). The app compares the running daemon's build with the one in its bundle and hands over to launchd's daemon; after a rebuild with a new signature it registers the background item again.
- Sessions end at logout and Mac restart, as with herdr; their rows show Exited with Relaunch.
- The app polls `list` once a second; there is no event stream yet. The protocol is version 1 only.
- Until the background item is approved in System Settings › General › Login Items, One Roof starts roofd itself (it then stops at logout); the startup check shows this as a warning with a fix that opens Login Items.
