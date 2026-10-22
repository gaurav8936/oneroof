# One Roof help: Resources

**Status:** LIVE · **Date:** 2026-10-21

> **One line:** Resources shows how much memory and CPU One Roof itself uses: overall, for its own app and roofd, and for each session by window (View › Resources, **⇧⌘U**), and the plan panel's **Resources** tab shows the same for the selected session, process by process.

## Goal

A session's processes can grow without anyone noticing. On 21 Oct 2026 several session holders reached 5 GB each and froze a 16 GB Mac. Resources lets you see that coming: which session is heavy, whether it is getting heavier, and how close it is to roofd's memory guard.

Everything is read from macOS once every 3 seconds, the same numbers Activity Monitor shows (its Memory column and its % CPU). Reading them does not pause or slow the sessions. The charts keep the last 10 minutes, and One Roof keeps sampling while the view is closed, so the history is there when you open it.

## The Resources view (⇧⌘U)

Open it with **⇧⌘U** (View › Resources), **Resources** in the toolbar, or "resources" in the command palette (⌘K). Like Overview, it covers every window and folds the sessions panel away. From top to bottom:

- **Summary.** One Roof's total memory and CPU, each with a 10-minute chart, how many processes that is, and **This Mac**: memory used of total, the memory pressure (normal, under pressure or critical, in amber or red when it is not normal) and how much swap is in use.
- **One Roof itself.** The app (with the helpers it starts, such as the `roofd attach` process behind each terminal) and the **roofd daemon**, each with its pid, how long it has been up, CPU and memory. The daemon's bar shows its own memory guard (warns at 512 MB, stops at 2 GB). A **Holder without a live session** row appears when an ended session's process is still winding down.
- **Sessions, by window.** One card per window, with the window's total. Each running session shows its agent, name and status, how many processes it has, a 10-minute memory chart, CPU, memory, and a bar for its holder against roofd's limits. **Heaviest** (the default) sorts by memory within each window; **Name** sorts alphabetically. Sessions whose window is closed, and sessions roofd runs that have no One Roof row, are under **Other**. Planned and exited sessions use nothing, so they are not listed.
- **Click a session** to go to it: its window comes forward with its terminal in the centre, as from the Overview.

### What the numbers mean

- **Memory** for a session is its whole tree: the holder (`roofd session`, which keeps the terminal), the agent (claude, codex, node …) and everything the agent started (shells, MCP servers, language servers, test runs).
- **CPU** is the share of one core over the last 3 seconds; a session using two cores fully shows 200%.
- **The bar** is the holder alone, because that is what roofd's memory guard measures: it notes a warning at **1 GB** and ends the session at **2 GB**, before it can take the Mac down. The tick on the bar is the warning line. If roofd was started with `ROOFD_SESSION_MEM_WARN_MB` / `ROOFD_SESSION_MEM_LIMIT_MB`, the bar uses those lines.
- **Colours:** a memory figure turns amber once the holder is past the warning line (or roofd has flagged it), and red in the last 10% before the limit. A window card with a session that close to the limit gets a red edge.

## The plan panel's Resources tab

Select a session and open **Resources** in the plan panel (after Artifacts). It shows:

- Memory, CPU and the number of processes now.
- Charts of memory and CPU over the last 10 minutes, with the peak.
- **Memory guard:** the holder's bar, the warning and limit lines, how much is left, and roofd's own warning when it has flagged the holder. Past the warning line it says **Relaunch to free memory**: a relaunched session starts small.
- **Processes:** every process under the session's holder, indented under its parent, with pid, CPU and memory.

A session that is not running says so: it uses no memory or CPU.

## Good to know

- The numbers are read-only: Resources never stops, pauses or signals a process. To free memory, relaunch or close the session yourself.
- One Roof's own sampling costs about a millisecond every 3 seconds.
- Sessions started from another copy of roofd (a test folder, say) are not counted.
