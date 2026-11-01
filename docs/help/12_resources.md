# One Roof help: Resources

**Status:** LIVE · **Date:** 2026-10-22 · **Updated:** 2026-11-01 (2.0.0: readable colours, a browser shows windows and tabs, close tabs and windows)

> **One line:** Resources shows how much memory and CPU every app on the Mac uses (with each app's processes, such as Chrome's tabs, and Quit / End buttons), and in detail what One Roof itself uses: overall, for its own app and roofd, and for each session by window (View › Resources, **⇧⌘U**); the plan panel's **Resources** tab shows the same for the selected session, process by process.

## Goal

A session's processes can grow without anyone noticing. On 21 Oct 2026 several session holders reached 5 GB each and froze a 16 GB Mac. Resources lets you see that coming: which session is heavy, whether it is getting heavier, and how close it is to roofd's memory guard.

Everything is read from macOS once every 3 seconds, the same numbers Activity Monitor shows (its Memory column and its % CPU). Reading them does not pause or slow the sessions. The charts keep the last 10 minutes, and One Roof keeps sampling while the view is closed, so the history is there when you open it.

## The Resources view (⇧⌘U)

Open it with **⇧⌘U** (View › Resources), **Resources** in the toolbar, or "resources" in the command palette (⌘K). Like Overview, it covers every window and folds the sessions panel away. From top to bottom:

- **Summary.** One Roof's total memory and CPU, each with a 10-minute chart, how many processes that is, and **This Mac**: memory used of total, the memory pressure (normal, under pressure or critical, in amber or red when it is not normal) and how much swap is in use.
- **This Mac, by app.** Every app on the Mac, heaviest first, with its memory, CPU and share of the memory in use. An app counts everything it is responsible for (its helpers and the services it started, as in Activity Monitor), so Chrome's tabs, OrbStack's virtual machine and Codex's helpers sit under their app. The top 12 show; **Show all** lists every one. Details below.
- **One Roof itself.** The app (with the helpers it starts, such as the `roofd attach` process behind each terminal) and the **roofd daemon**, each with its pid, how long it has been up, CPU and memory. The daemon's bar shows its own memory guard (warns at 512 MB, stops at 2 GB). A **Holder without a live session** row appears when an ended session's process is still winding down.
- **Sessions, by window.** One card per window, with the window's total. Each running session shows its agent, name and status, how many processes it has, a 10-minute memory chart, CPU, memory, and a bar for its holder against roofd's limits. **Heaviest** (the default) sorts by memory within each window; **Name** sorts alphabetically. Sessions whose window is closed, and sessions roofd runs that have no One Roof row, are under **Other**. A session whose agent has finished but whose terminal is still open keeps its row (status Exited): that terminal still uses memory until you close the session. Planned sessions, and sessions that are fully closed, use nothing, so they are not listed.
- **Click a session** to go to it: its window comes forward with its terminal in the centre, as from the Overview.

## This Mac, by app

Added on 22 Oct 2026 (LAB-544): the Mac was at 14 GB of 16 with 18 GB of swap and the page only showed One Roof's 1.7 GB.

- **Click an app** to open its processes, heaviest first (the top 25, then **Show all**), each with pid, CPU and memory. For apps built like Chrome (Slack, Notion, Linear, Codex, ChatGPT …) each helper says what it is: **Tab or site**, **Extension**, **Browser window (tabs, toolbar)**, **GPU**, **Network**, **Storage**, **Audio** … and a line above the list adds them up ("67 × Tab or site 10 GB · GPU 690 MB …").
- **A browser shows its windows and tabs** (2.0.0, LAB-2053). Open Chrome (or Safari, Brave, Edge, Arc, Vivaldi, Opera) and you see, top to bottom:
  1. **Open tabs**, by window (or by site), as below.
  2. **Using a lot · over 250 MB or 10 % CPU**: only the helpers or tab processes over either line, heaviest first, each with its memory, CPU and **End ▾**. A tab process reads "A tab or site (macOS does not say which)". Nothing qualifies, no block. A process that drops below both lines stays listed for 30 seconds, so the list does not flicker.
  3. One line: **Memory per tab: Google Chrome's Task Manager (⇧Esc)**, with an ⓘ that holds the full explanation, and **Show Google Chrome**.
  4. **All processes (83)**: opens today's full list (the breakdown by kind, the folded **78 tabs or sites** row, every helper with pid, CPU, memory and End / Force end). It starts closed each time.

  The small helpers (Network, Audio, crashpad …) are no longer listed by default; they are all under All processes. Apps that are not browsers look as before.
- **Open tabs** (0.4.11, LAB-554; by window since 1.8.2, LAB-853). Open a browser (Chrome, Brave, Edge, Arc, Vivaldi, Opera or Safari) and its open tabs are listed **by window** ("Window 1 · 7 tabs"), each with its title and, on the right, its site; ● marks the tab in front in its window. **By site** lists them by site instead, the site with the most tabs first. **Click a tab** to bring it forward in the browser. One Roof reads the tabs straight away when macOS already allows it to control the browser. If macOS has not asked yet, one line says so and **Show tab names** asks: macOS asks once whether One Roof may control the browser; say OK. If you said no, the page says so and **Open Automation settings** takes you to System Settings › Privacy & Security › Automation to turn it on. **Refresh** reads the tabs again. Nothing leaves this Mac.
- **Close a tab or a window** (2.0.0, LAB-2054 Chrome, LAB-2060 Safari).
  - **A tab:** hover it and press **✕** (or right-click › **Close tab**, or focus it and press **⌫**). It closes at once; the line above the list says "Closed "Inbox (3) · Gmail". Reopen it in Google Chrome with ⇧⌘T." and the list refreshes half a second later. Right-click also offers **Bring forward** and **Copy address**; **Return** brings a focused tab forward.
  - **A window:** **Close window** next to "Window 2 · 4 tabs". A window with 2 or more tabs asks first ("Close window 2 of Google Chrome? This closes its 4 tabs. Google Chrome can reopen the window with ⇧⌘T."); a one-tab window closes at once.
  - **Safe by design:** One Roof asks Chrome to close the tab with the id it read, and only if that tab still shows the same address (Safari has no tab ids: the tab at that position, with the same address). A window closes only if it still has the number of tabs that was read. If anything changed, nothing closes: the list refreshes and says "That tab changed since the list was read. The list is fresh now; try again." Closing never launches the browser. It uses the same macOS permission as reading the tab names, so there is no new prompt (Safari has its own permission, asked the first time you read its tabs).
  - **A hung browser:** if Chrome does not answer in 10 seconds, the page says "Google Chrome did not answer in 10 s. It may be busy or hung." with **Force quit Google Chrome…**, which opens the usual Force quit confirmation.
  - **What cannot be done:** macOS does not say which process is which tab, so there is **no memory per tab** and **no force-close of a single tab** here. To end one hung tab, use Chrome's Task Manager (**⇧Esc** › End process). Brave and Arc tabs are listed but not closed yet (not tested on this Mac); the page says so under the list.
- **Memory per tab.** macOS does not tell other apps which tab a browser process belongs to, so a browser's tab processes are one row under All processes, **78 tabs or sites · 14 GB**; click it to list them one by one (each can still be ended). The browser's own Task Manager does know: **⇧Esc** in Chrome (Window › Task Manager) lists every tab with its memory and can end it. **Show Google Chrome** brings Chrome forward.
- **Quit** (on an app's row) asks the app to quit, as the Dock's Quit does; it may ask to save. The arrow next to it offers **Force quit** (closes it at once, unsaved work is lost). Only apps in the Dock can be quit here; One Roof itself, Finder, the Dock and the system cannot.
- **End** (on a process row) asks that one process to stop; the arrow offers **Force end**. Ending a **Tab or site** makes that tab show as crashed until you reload it. System processes have no End.
- Every Quit and End asks you to confirm first and says how much memory it frees.
- **Left over from One Roof.** When One Roof finds its own processes that the running app did not start, they show at the top as a warning row (an amber tint with an amber bar on its left edge) with **Stop**: most often the **local model** (llama-server, the small on-device model; the row names the model, for example "Local model (Qwen3 1.7B)") left running by a force-quit, which keeps growing (8.4 GB on 22 Oct), and roofd copies from older builds. One Roof also stops a left-over local model by itself when it starts. It starts a fresh one when it needs it. Since 0.4.11 (LAB-549) a force-quit or crash can no longer leave one behind: the model runs under a small watchdog (a `sh` process under One Roof) that stops it within about 2 seconds of One Roof ending. A leftover from an older version counts in One Roof's own figures at the top, and the model One Roof runs is restarted if it ever grows past 3 GB.
- **Not counted:** macOS lets only an administrator read the system's processes and other users' (kernel, WindowServer's share and the like), so the footnote gives their count instead.
- This part is read only while the Resources view is open (about 10 ms every 3 s); the rest of the page keeps sampling all the time.

### What the numbers mean

- **Memory** for a session is its whole tree: the holder (`roofd session`, which keeps the terminal), the agent (claude, codex, node …) and everything the agent started (shells, MCP servers, language servers, test runs).
- **CPU** is the share of one core over the last 3 seconds; a session using two cores fully shows 200%.
- **The bar** is the holder alone, because that is what roofd's memory guard measures: it notes a warning at **1 GB** and ends the session at **2 GB**, before it can take the Mac down. The tick on the bar is the warning line. If roofd was started with `ROOFD_SESSION_MEM_WARN_MB` / `ROOFD_SESSION_MEM_LIMIT_MB`, the bar uses those lines.
- **Colours:** a memory figure turns amber once the holder is past the warning line (or roofd has flagged it), and red in the last 10% before the limit. A window card with a session that close to the limit gets a red edge.
- **Readable in every theme** (2.0.0, LAB-2052). Every number and note reads at 4.5:1 or more on the surface it sits on (Daylight, Graphite, Midnight and the pastel looks); bars are 6 pt on a track you can see, charts draw a 2 pt line, status pills (Ready, Idle, Working …) have an edge, and the hover on a row is visible. The layout is unchanged; the rows of One Roof itself and the sessions fit at 1280 without names wrapping. `swift test --filter ResourcesContrastTests` prints the contrast of every pair.

## The plan panel's Resources tab

Select a session and open **Resources** in the plan panel (after Artifacts). It shows:

- Memory, CPU and the number of processes now.
- Charts of memory and CPU over the last 10 minutes, with the peak.
- **Memory guard:** the holder's bar, the warning and limit lines, how much is left, and roofd's own warning when it has flagged the holder. Past the warning line it says **Relaunch to free memory**: a relaunched session starts small.
- **Processes:** every process under the session's holder, indented under its parent, with pid, CPU and memory.

A session that is not running says so: it uses no memory or CPU.

## Good to know

- Resources only stops something when you press Quit, End or Stop and confirm. For a session, relaunch or close the session instead.
- One Roof's own sampling costs about a millisecond every 3 seconds.
- Sessions started from another copy of roofd (a test folder, say) are not counted.
