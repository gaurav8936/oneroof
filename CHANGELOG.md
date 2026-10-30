# Changelog

## 1.9.27 — Learn: a bigger card, sit-back listening, code that looks like code (29 Oct 2026)

- **Includes 1.9.26** (below), which was not released on its own: the Sessions column drags back open, and the
  window buttons sit inside the rail.
- **The card fills the window** (LAB-1619). Learn › a card's Listen tab no longer sits in a narrow column: the card
  grows with the window, in width and height. The panel on the right (Say it in a session, Pairs with, Read about it,
  Next on the band) is narrower and folds away with Hide side panel; One Roof remembers it.
- **Roll over to the next card** (LAB-1621). When a card finishes, "Next: <title> in 3…" counts down, then the next
  card on the band opens and keeps playing (at the end of a band, the next band's first start-here card). Stay, Esc or
  pressing play cancels it. Speed, voice and captions carry over. Settings › Learn › Auto-advance to the next card
  turns it off.
- **Previous card, next card, back to the band** (LAB-1629). The card's player bar ⏮ ⏭ and Band buttons work in One
  Roof, and One Roof's own player bar has them too.
- **People, in six themes** (LAB-1668). Learn › Context › People worth hearing lists the 41 people by theme (labs,
  coding-agent builders, frameworks, evals, practitioners, strategy), each with a photo or initials and their
  contribution. A person's card shows their profile beside it: role, a short bio, where to start, their main work
  with links, and where they publish. Previous card, next card and the roll-over follow the theme order.
- **Code looks like code** (LAB-1628). Code blocks, a card's Skill file and All cards › By folder previews show code in
  one dark panel, in light and dark mode: monospace, coloured, with Copy, and long lines wrap instead of being cut. A
  SKILL.md shows its front-matter as YAML with the rest rendered below.

## 1.9.26 — the Sessions column drags back open (29 Oct 2026)

- **Drag the Sessions column back open** (LAB-1612). After dragging the column closed, dragging its edge back to the
  right did nothing; only the rail's Sessions button or a step change brought it back. Now the drag reopens it. At
  the Sessions step the rail also stays on screen while the column is closed, so there is always an edge to drag.
- **Window buttons inside the rail** (LAB-1620). The green button no longer sits half across the rail's edge: the three
  buttons move a little to the left, with their usual spacing.

## 1.9.25 — Focus is smooth (29 Oct 2026)

- **Clicking Focus no longer locks the window** (LAB-1601). The click was read as the end of a drag of the Focus
  lane, so the lane and the step fought over its width for about two seconds. Focus now takes a third of a second,
  as smoothly as Full and Wide.
- **Terminals resize once per step.** Switching Full, Wide or Focus no longer re-fits the terminal (and makes the
  agent redraw) on every frame of the switch: the terminal takes its new size when the panels stop.
- **Less work on every width change.** Pages you are not looking at (Files, the catalog, Learn…) no longer take part
  in the window's layout.

## 1.9.24 — permission mode per agent, a steadier session catalog, Needs you fixes, the test harness (29 Oct 2026)

- **Permission mode per agent** (LAB-1600). Settings › Permissions sets how much each agent may do without asking:
  Manual, Plan or Auto (Codex: Manual, Read only, Auto). New sessions start in Auto unless you choose otherwise; the
  New session sheet can change it for one session. Each session shows its mode in its header and in the Plan panel.
- **The session catalog holds still** (LAB-1584). Rows keep their place while the page is open, so a row you act on
  does not jump; a row you resumed stays listed under the filter you found it with. Resume says what it is doing on
  the row itself: Starting…, then its new state, or why it did not work.
- **Resume, stress-tested** (LAB-1583). Every resumable session in a copy of a real profile was resumed one by one
  (35 of 35 came back with their conversation).
- **Search by what a session worked on** (LAB-1585). The catalog's search reads each session's conversation, not just
  its name, and shows the line that matched. Press Return to widen the question with related words from the
  on-device model ("a bug where the screen hangs" also finds stalls and freezes).
- **Needs you** (LAB-1592). A permission you denied, or a question you cancelled, no longer leaves the session stuck in
  Needs you. Claude's newer command prompts show the real command, and prompts with long or wrapped options are
  recognised without hooks.
- **For testing One Roof**: a simulator that runs sessions of every agent over three windows and keeps the
  conversations going, and `app/scripts/oneroof-test`, one command for functional journeys, performance against the
  last release and a side-by-side comparison, with HTML and Markdown reports (LAB-1590–1599).

## 1.9.23 — Claude's last screen stays after it exits (29 Oct 2026)

- **The last screen stays when Claude exits** (LAB-1582). Since 1.9.20 Claude runs in its fullscreen view, which draws
  on a separate screen that the terminal drops on exit, so Ctrl+D twice left an empty terminal. When an agent leaves
  that screen, roofd now copies it into the terminal's history first, so the end of the conversation stays in view.
  Editors and pagers run from a plain shell still clear on exit, as usual. Applies to sessions started after updating.

## 1.9.22 — the Sessions column can be dragged closed again (29 Oct 2026)

- **Drag the Sessions column closed** (LAB-1576). 1.9.21 stopped the column at its narrowest, so it could no longer be
  closed by dragging its edge left. A drag left folds it away again; the old folder panel stays shut. One click on
  Sessions in the rail, or ⌥⌘S, brings the column back.

## 1.9.21 — clicks reach Claude, the Sessions column stays, searchable pickers (29 Oct 2026)

- **Clicks reach Claude's fullscreen view** (LAB-1554). Every plain click in a terminal was turned into a text-selection
  click, so Claude's own buttons ("Jump to bottom") did nothing. When the program in a terminal asks for the mouse,
  clicks now go to it, as in other Mac terminals; hold Option to select text there instead.
- **Dragging the Sessions column can't trap you** (LAB-1556). Dragging its edge far to the left folded the column away
  and opened an old folder panel in its place; closing that left no way back but Home → Sessions. The column now stops
  at its narrowest, and the old panel never opens.
- **Search in New session** (LAB-1559). Team and Project open a list with a search box (type any words, any order;
  ↑ ↓ and Return to pick); the Issue picker's filter is ready to type into as soon as it opens.
- **Active only** (LAB-1571). The Project picker shows In Progress projects only (switch it off to see all); the Issue
  picker has the same switch for In Progress and In Review issues (off by default). Both remember your choice.

## 1.9.20 — terminal text stays whole when a pane changes width (29 Oct 2026)

- **Claude starts in its fullscreen view** (LAB-1550). Claude has two ways of drawing; in the older one it reprinted
  the whole conversation into the terminal's history on every width change (switching Full / Wide, resizing a
  window), so copies piled up at different widths and tables broke. One Roof now starts Claude in the fullscreen view,
  which redraws cleanly at any width. A session already running keeps its old view until restarted
  (`/tui fullscreen` inside it restarts and resumes the same conversation).
- **History reflows after a terminal reconnects** (LAB-1550). When a pane reconnected to its session (switching
  sessions, showing a window again, restarting the app), long wrapped lines came back as fixed line breaks and stayed
  at that width. Wrapped lines now stay wrapped, so older text fills the pane as it widens or narrows. Applies to
  sessions started after the update.

## 1.9.19 — finished sessions really close (29 Oct 2026)

- **Finished sessions close as promised** (LAB-1545). A session whose agent had ended was never actually closed: "Close
  finished" (1.9.16), Close in All sessions and the 10-minute rule (1.9.18) all stopped short because such a session has
  no live agent. They now close the shell the agent left, as described in 1.9.18.

## 1.9.18 — sessions look after themselves (29 Oct 2026)

- **Exiting an agent closes its session after 10 minutes** (LAB-1535). Ctrl+D twice or /exit ends Claude; its terminal
  stays for 10 minutes so you can read the last screen, then the shell and roofd's holder close. The bar says so, and
  says the conversation stays in All sessions (⌃⌘O). Settings › General › When an agent ends: keep, right away,
  10 minutes, 1 hour.
- **Sessions nobody touched for a day close by themselves** (LAB-1535). Never one that is working, waiting for you,
  pinned, a loop, or one that cannot be resumed. Settings › General › Close sessions untouched for. Closing a window
  still only hides it.
- **Remove never deletes** (LAB-1537). A removed session leaves its window's list and stays in All sessions; ⇧⌘T
  brings it back, and resuming it puts it back in its window. Delete forever, in All sessions, asks first.
- **All sessions for maintenance** (LAB-1538). It shows what runs at each level (working, waiting, finished shells);
  Close ends anything that runs, and asks first if an agent is working.
- **Keep agent conversations on this Mac** (LAB-1533). Claude Code deletes its conversations after 30 days unless told
  otherwise, and Resume needs them. One setting for every Claude account: 30 days (Claude's default), 90 days, 1 year
  or Forever. Lowering it asks first. Codex and Kimi keep theirs until you delete them.

## 1.9.17 — the catalog, one click from your sessions (28 Oct 2026)

- **This window · All sessions** (LAB-1530). A switch at the top of the Sessions column: All sessions opens the session
  catalog (every session from every window, by repo, with Resume); This window is today's list. Where older sessions
  left the list, a link says how many and opens them. ⌃⌘O does the same from anywhere.

## 1.9.16 — the session catalog, and no more quit on launch (28 Oct 2026)

- **Session catalog** (View › Session Catalog, LAB-1509). Every session One Roof knows — live and history, every
  window, open or closed — grouped by repo, newest first, with search and Working / Waiting / Finished / History /
  Planned filters. Each row says what it can do: Open (running), Resume (a saved Claude conversation), Launch (planned),
  New terminal here (a shell), or why it cannot be resumed (LAB-1512, LAB-1513).
- **Older Claude sessions found again** (LAB-1511). On first opening the catalog, One Roof matches sessions saved before
  1.9.15 to their conversations on disk — only confident matches (first message within 10 minutes of the launch, and
  the opening message when there was one); the rest say so instead of guessing.
- **Close finished sessions in one step** (LAB-1514). Shells whose agent has ended are closed together; their rows stay.
- **New Session picks its window** (LAB-1514), each window shown with its session count. History older than a day
  leaves the All list (still under Exited and in the catalog; nothing is deleted).
- **Finished sessions tidy themselves** (LAB-1524). When an agent ends, its shell stays so you can read the last
  screen; after an hour untouched One Roof now closes it (Settings › When an agent ends: keep, right away, 15 min,
  1 hour, 4 hours). Never while something runs in it, never a pinned session; the row stays, resumable from the catalog.
- **No more quit on launch** (LAB-1385). A caption claiming a billion-billion steps made the Plan panel try to draw them
  and the app aborted. Step counts are now kept only when they are a real plan (1–50), on load as well.

## 1.9.15 — sessions you can trust: resume, safe saves, honest closing (28 Oct 2026)

- **Every Claude session remembers its conversation** (LAB-1510). One Roof saves the conversation id the first time it
  sees it, so Resume works after the terminal is gone or One Roof restarts. First step of the session catalog (LAB-1509).
- **No more lost updates between roofd and the app** (LAB-1516). When a scheduled run or a loop starts a session, roofd
  writes only the launch fields, and an app save never erases a newer launch.
- **An older One Roof will not open a newer store** (LAB-1517). It says why and writes nothing.
- **roofd tidies its folder** (LAB-1518). Lock and socket files left by sessions that ended without cleaning up are
  removed when roofd starts; live sessions keep theirs.
- **Closing a window says what is in it** (LAB-1485). How many sessions keep running, which agents are working or
  waiting, which are finished shells, and how many are saved rows — no more "keep running in roofd" for an empty window.
- **Repro copies clean up after themselves** (LAB-1486). `app/scripts/test-copy.sh` runs a throwaway copy that always
  stops its roofd and unregisters itself.

## 1.9.14 — All cards › By band shows every card (28 Oct 2026)

- **By band draws the whole deck again** (LAB-1411). Since the deck dropped suits, each band in Learn › All cards ›
  By band showed only its Start here cards (7, 5, 5, 5). Now every band lists all its cards under Start here, track by
  track: Context 35, Loops 62, Evidence 19, Procedure 46. The fix was written for 1.9.9 but missed the release.

## 1.9.13 — the Focus lane, properly (27 Oct 2026)

- **The Focus lane fills in as you drag it** (LAB-1382). Widening the thin avatar lane showed an empty box with one
  avatar until you let go. Now the session list appears as soon as it is wide enough, names cut off at first and more
  of them as it widens, and it stays where you let go. Closing the classic Files panel no longer widens the lane.
- **Focus snaps the lane back** (LAB-1383). With the lane widened, clicking **Focus** (or ⌥⌘F, or 3 · Focus) returns
  to the thin avatar lane; Focus always opens with the thin lane.
- Performance check: two new place-switch scenarios (into/out of Sessions, and between the other places) for
  LAB-1370, the place-switch hitch that is still being worked on.

## 1.9.12 — bug fixes: blank terminals, Current ↓, resume (27 Oct 2026)

- **Terminals no longer come back cut off or blank** (LAB-1365). Since 1.9.10 a terminal you have not shown lately is
  re-attached when you show it again, and roofd redraws its history. A long session's redraw is bigger than roofd's
  4 MB send limit, so roofd dropped the terminal part way: part of the history or nothing when you scrolled back. The
  redraw is now exempt (live output still has the limit). And a terminal resized or re-attached while hidden is
  redrawn in full at its size when it shows, instead of at its old size until the program printed again.
- **Current ↓ and ⌘↓** (LAB-1363). Scrolled up in a terminal, a **Current** button floats at the bottom right; click
  it or press ⌘↓ to jump to the live bottom (⌘↑ to the top).
- **Edge panels wait for you** (LAB-1367, LAB-1368). At Focus the session list (left edge) and the Plan (right edge)
  open after the pointer rests at the edge for a second, not the moment it touches it.
- **The Focus lane widens** (LAB-1366). Drag the thin avatar lane out to see the full session list; drag it back to
  return to avatars. **+N** widens it too.
- **Resume after you quit Claude** (LAB-1362). Quitting Claude (⌃D) keeps the terminal and its text; a strip says the
  session ended, with **Resume** (the same conversation, in the same terminal and folder), **New session** and the
  handoff. "Relaunch", which started a new session, is gone from there.

## 1.9.11 — lighter under heavy output (27 Oct 2026)

- **roofd spends a third less CPU on heavy output** (LAB-1324). A session's process read the terminal a few KB at a
  time, with a wake-up and a hand-off to its parser for each piece; under heavy output those system calls and thread
  wake-ups, not the parsing, were most of its CPU. It now reads everything waiting (up to 64 KB) before forwarding
  and parsing once. Measured with five terminals printing as fast as they can: 1.0 → 0.66 CPU-seconds per MB, total
  CPU about 300–400 % → 200 %. Applies to sessions started after the update (running sessions keep their process).
- Decision record: `docs/decisions/20261027_01_heavy-output-path.md`.

## 1.9.10 — memory, sessions and layout (27 Oct 2026)

- **Terminal memory stays bounded** (LAB-1321). Every terminal you visited stayed alive (about 30 MB each, never
  freed). Now the 8 most recently shown stay live; older ones are freed and attach again when you show them, with
  their text restored by roofd.
- **Quiet session processes** (LAB-1322). Each session's process woke 10 times a second doing nothing; now once a
  second when quiet, four times a second while output flows.
- **Session saves off the main thread** (LAB-1336): written in order on their own queue, and edited-file updates
  from the engines saved together with one rebuild instead of one per session.
- **Smoother resizing and place changes** (LAB-1337): during a live resize only the toolbar band follows each frame
  (the toolbar and Plan fit once at the end); places that share a layout (Learn, Home, Work) no longer re-lay out every
  panel when you move between them.
- **Captions and the feed redraw only what shows them** (LAB-1338): captions, the feed, step chapters and subagents
  live in their own store, so a caption update no longer redraws every view; Home's feed rows redraw only when their
  own entry changes, and their time labels no longer build date formatters on every redraw.
- A terminal re-attached in a test window drew nothing (test windows are off screen and counted as hidden); they now
  count as on screen.

## 1.9.9 — light in the background (27 Oct 2026)

- **Hidden terminals stop drawing** (LAB-1320). The terminal engine was told a terminal was visible once and never
  told otherwise, so terminals behind another pane, in a hidden or minimised window kept rendering. Now each one is
  told when it is hidden and again just before it shows.
- **Learn plays lightly** (LAB-1332). The playback position redrew the whole Learn page twice a second; now only the
  clock and the progress bar redraw. Posts and release notes are parsed once per file change. Learn playing:
  16 % → 4 % CPU, main-thread stalls 54 → 0 a minute.
- **The on-device caption model is asked less, and never blocks** (LAB-1330): at most every 30 s per session, only
  for sessions on screen or when a status changes, off the engines' queue.
- **Transcripts are read incrementally** (LAB-1331, LAB-1335): only what an agent appended since the last read, and
  the Table view reads a terminal's text only when the session wrote something.
- **Less background work** (LAB-1323, LAB-1333, LAB-1334): App Nap is held off only while an agent works or needs
  you (or a schedule is set); the poll slows to every 3 s with no window on screen; timers allow the system to batch
  wake-ups; the resource monitor announces samples only while a view shows them; the "running" marker in a pane is
  looked up when the session writes output, not every 2 s.
- Measured against 1.9.3 with `app/scripts/perf/perf-check.sh`: idle 9.6 % → 0.6 % CPU, six busy terminals 14 % →
  3.8 %, Learn playing 16 % → 4 %.

## 1.9.8 — quiet when idle (26 Oct 2026)

- **One Roof does nothing when nothing changes** (LAB-1314). The app model announced a change twice a second with
  nothing happening (two status values were set again on every poll), so every panel redrew and the main thread
  stalled about once a second. Values are now set only when they change. Measured on the same Mac against 1.9.3:
  idle CPU 9.6 % → 0.6 %, main-thread stalls of 50 ms or more 58 → 0 a minute.
- **No background git storm** (LAB-1319, LAB-1327). Branch and diff counts were read for every session, exited ones
  included, every 10 s (about 240 git processes a minute). Now: every 10 s for a working or visible session, every
  60 s for other live ones, every 5 min for the rest; finding a file's repo no longer starts git at all. Idle: 0
  processes a minute.
- **Lighter redraws** (LAB-1315, LAB-1316, LAB-1317, LAB-1318, LAB-1328). The handoff lookup and the Related in Learn
  ranking are kept instead of being redone in every redraw; the session tab strip has a fixed height instead of being
  measured on every update; the running dot's halo is a Core Animation layer; the poll tick sets the Dock badge only
  when it changes and builds its session table once. Switching places once a second: stall time 251 → 71 ms a
  second; six busy terminals: 14 % → 6 % CPU, stalls 43 → 0 a minute.
- **View timers fire** (LAB-1329). Timers made inside views (the editor's 2 s save flush among them) were made again
  on every redraw and could miss while the app was busy; they are now shared clocks.
- **A performance check in the repo** (LAB-1325): `app/scripts/perf/perf-check.sh` builds a test copy, runs fixed
  scenarios on a copy of a profile, and compares CPU, main-thread stalls, processes started and memory with the 1.9.3
  baseline and each release's targets.

## 1.9.7 — the Files panel closes (26 Oct 2026)

- **The Files panel's × closes it** (LAB-1306). In the new window the file tree lives in the Files tab, but the old
  Files side panel could still come back (from a saved window layout). Its × sent the same action as ⌥⌘B, which in
  the new window opens the Files tab, so clicking × opened a second tree instead of closing the first, and the panel
  could not be closed at all. The × now closes it, and the new window keeps that old panel hidden.

## 1.9.6 — Learn shows the deck's own card pages, a quieter session column (26 Oct 2026)

- **Includes the Table view fix from 1.9.5** (1.9.5 was never published: a test string failed the release check).
- **Learn cards are the deck's own pages** (LAB-1305). A card's Listen tab shows the card's page from the Agentic
  Engineering deck exactly as the repo and GabbleGrid show it (its diagram, steps, sections and its own player)
  instead of One Roof's redrawn scenes. When the page narrates, One Roof's player pauses, and the other way round;
  while One Roof plays the card, the page follows the scene being heard. Transcript, Skill file and the side column
  (say it in a session, pairs, posts, next on the band) stay. One Roof's own scene view remains only for a card
  without a page.
- **The narrow session column shows running sessions only** (LAB-1302). In Focus, exited, parked and not-started
  sessions no longer look like running agents; they are one "+N" button that opens the session list.

## 1.9.5 — Table view on a live terminal (26 Oct 2026)

- **Table view finds tables in a live terminal** (LAB-1299). 1.9.4 was checked with whole lines, but a live
  terminal hands its text over as screen rows: every row wider than the pane is cut at the edge, and after One Roof
  restarts, output that roofd kept is cut again at the width roofd drew it. The Table view showed those pieces
  instead of tables. Cut table rows are now glued back before tables are looked for (a box row is whole once it is
  as wide as its top frame, a Markdown row once it ends with `|`), and text cut at exactly the terminal's width is
  rejoined, so paragraphs wrap at words again. Checked against the owner's own terminal text and the same sample cut
  at 67, 80, 131 and 156 columns.

## 1.9.4 — Table view fixes, one place to type (26 Oct 2026)

- **Table view reads wide tables correctly** (LAB-1299). A box-drawing table printed right before a Markdown table
  swallowed it: the box table's bottom frame didn't end it, so every row ended up merged into one cell and the second
  table became a row. A bottom frame now ends a box table, and the two print as two tables.
- **Table view cells stay on one line** (LAB-1299). Cells are drawn in the terminal's font without wrapping, so the
  columns line up and a wide table scrolls sideways; rows no longer draw over each other, and the row stripes and
  rules run the table's full width. Markdown column alignment (centre, right) is kept.
- **One place to type to an agent** (LAB-1298). You type in the agent's own prompt; One Roof's composer is hidden by
  default and opens with **Compose** in the pane header, shows by itself in the Table view (so you can keep talking
  to the agent there), or stays on with Settings › Always show the composer under agents. Skill and file pickers,
  run as shell and interrupt are all still in it. Its Raw stream chip is gone (Raw is in the session tabs and ⌘R).
- The Focus reminder ("Focus · ⌥⌘F leaves …") shows for a few seconds when Focus starts, then fades.

## 1.9.3 — Table view, remembered windows, fresh Linear projects (26 Oct 2026)

- **Table view replaces Wrap** (LAB-1286, LAB-1271). A pane's **Table** button (also View › Table View) shows the
  session formatted: prose wraps to the pane, and every table is a real table with aligned columns that scrolls
  sideways when it is wider than the pane. Claude sessions read their transcript, so replies appear exactly as
  written, with one short line per tool call; other terminals have their Markdown and box-drawing tables found and
  drawn as tables. Back to live, Table again, or Esc while the view has the keyboard returns to the terminal; Esc in
  the terminal still goes to the agent. The session tabs' "Split ⌘D · Raw ⌘R · Wrap" text is now Split, Raw and
  Table buttons with the keys in their tooltips.
- **One Roof remembers where each window was** (LAB-1281). No main window's position or size was ever saved, so after
  every launch or update windows came back at 1700 × 1000, and a half-screen window could snap back to that shape.
  Opening Learn never changes the window's frame.
- **The project list refreshes from Linear** (LAB-1255): every 30 seconds, when a window comes to the front and when
  you open New session, so renamed and new projects show up. A project's issues are read in full (up to 1,000).
- The seat bars at the foot of the rail are labelled and open Settings › Seats & accounts (LAB-1266).
- Clicking the Focus button at Focus now goes round to Full; ⌥⌘F still leaves Focus.

## 1.9.2 — Learn is three views; clearer Focus button and Plan close (26 Oct 2026)

- **Learn is now three views: Radio, Writing and All cards** (by band, by kind or by folder) (LAB-1274). The Pages
  list and the Course are gone; the deck's skills are all still here. Every link into Learn opens what these views
  show: a skill or Search result opens its card, How Do I…? (⌥⌘/) opens the best-matching card, and One Roof Help opens
  on the Help page.
- Track names under a band's dial no longer print over each other (LAB-1272), and All cards › By folder explains its
  table.
- **The Focus step button explains itself** (LAB-1284): hover it and a hint shows what a click and a hold do and lists
  the four steps, with the current one marked.
- **The Plan panel has a clear close button** (LAB-1285): a round ✕ at the end of its tabs, "Close panel (⌥⌘P)".

## 1.9.1 — A steady terminal: the summary band no longer moves it (26 Oct 2026)

- **The terminal stops jumping** (LAB-1270). The session summary above the terminal grew with every finished step
  (rows under the card, a step list growing to six, "Right now" wrapping between one and two lines), so the terminal
  moved up and down while an agent worked. The summary now starts as its one-line strip in every pane (Summary ▾
  opens it, ▴ closes it), and the open card is one fixed height, about seven rows: the header, then five steps
  beside You asked and Right now; more steps scroll inside the list. The rows of finished steps under the card are
  gone; each step in the list shows its calls and duration instead.
- Releases are notarized with an App Store Connect API key when one is set, so they no longer depend on a keychain
  profile.

## 1.9.0 — One source for agentic engineering; Learn home navigation; All cards by folder (26 Oct 2026)

- **One source for agentic engineering** (LAB-1257). One Roof no longer writes any agentic-engineering content of its
  own. Every build packages the Agentic Engineering deck from its repository's main branch: every skill and card, the
  12-lesson course and the two hooks. Learn's bands (Context · Loops · Evidence · Procedure), plain track names and By
  kind groups now come from the deck's catalog; Learn looks and works exactly as before. The 17 older starter skills
  are gone (six were stale copies that could override the deck's newer versions), and skill linking only ever links
  the deck's skills. The routing rules are One Roof's own settings; your copies in `~/.config/oneroof/agent-routing/`
  still win.
- **Learn's Radio home is the way in** (LAB-1247). Clicking a band key opens that band's page, so you choose what to
  hear before anything plays, and each "On this band" chip opens the band at that track. Playback starts only from
  the play controls; the band page has a breadcrumb back to Radio.
- **All cards › By folder** (LAB-1253): the skills folder exactly as this build packages it, with each folder's band
  and size. Select a folder to play it or list its cards, a skill to see its files and send it to a session, or a
  file to read SKILL.md, spec.json or video.yaml right there.

## 1.8.2 — Backlog fixes: subagents, toolbar, Grid, Writing, busy terminals (26 Oct 2026)

- **The Subagents column is gone** (LAB-1240). It opened on its own beside the terminal with no way to close it; open a
  session's Subagents tab instead. The classic window keeps its column.
- **The toolbar no longer clips Focus or + New** (LAB-1237). The title truncates first, then the shortcut labels and
  Single · Grid · Wall step aside (still in the View menu).
- **The window goes down to 600 pt**, about a third of the screen (LAB-831). The Plan folds to its edge tab when it no
  longer fits; the session tabs and the status dock shorten instead of spilling over. Switching places never resizes
  the window (LAB-874), and a dragged session-column or Plan width is kept reliably (LAB-829).
- **Tooltips on every toolbar icon** (LAB-1236), including the place icons, which had none in the title bar.
- **Grid shows every live session, two across** (LAB-1239), as many rows as needed, and scrolls; ⌥⌘arrows scroll the
  focused tile into view. Back on Single, a session picked in the Grid now shows its own pane.
- The terminal pane header no longer shows loose shortcut text (LAB-826); the shortcuts are in tooltips and menus.
- While you read an earlier step, a second **Back to current** floats at the bottom of the terminal (LAB-825).
- **A busy terminal says so** (LAB-861): when a program other than the shell is in front (a local web server, say), the
  pane header shows "running: <command>" with a Stop button that sends Ctrl-C.
- **Learn › Writing fills in from the Zibajoon blog** (LAB-1251): the same hub the sites read, saved on this Mac so posts,
  the broadcast schedule and each band's posts show at once and offline. Posts in your Learn folders still appear and
  win on the same name. Diagrams and charts are drawn only on the web version, linked from each post.
- **Machine lists Chrome's open tabs by window** (LAB-853), with title and site, and folds the anonymous "Tab or site"
  processes into one row with their total memory. If One Roof isn't allowed to read the browser yet, one line says why.

## 1.8.1 — Learn as designed, and fixes from a real profile (26 Oct 2026)

- ⌥⌘F leaves Focus again at step 3, so a window can no longer stay stuck in Focus with no dock or session list.
- A window you had in 0.5.2.9 opens once at Full, with the Plan and the full dock showing, instead of folding them away.
- Sessions comes back at the step you left it at after you visit Home, Work or another place (it reset to step 1).
- The selected session always shows in the list, even when it is past the first four exited ones.
- The Files and Changes tabs, ⌥⌘R and Review Changes open the repo the session works in, not the workspace root it
  started in ("not in a git repo").
- A coloured window shows its colour again: a stripe under the toolbar.
- The session column and Plan keep the width you drag them to.
- **Learn redrawn to the design** (LAB-1233): one header across the top of Learn (where you are on the left; the card's
  actions, Radio · Writing · All cards · Pages and "How do I…? or search" on the right), with no separate band above it.
  Radio is now the dial: the dot-grid speaker with play, speed and next keys, a dark now-playing display with the whole
  deck drawn as a dial you can click to tune in, the four bands (Context, Loops, Evidence, Procedure) as keys, the knob,
  and the programmes. New: each band's own page, a card station with Listen (scene by scene, following the narration),
  Transcript and Skill file tabs, programmes that play in order, All cards as a map (by band or by kind) with search,
  and Writing with a post reader for posts found in your Learn folders. Pages (today's Learn) keeps every feature and
  now sits in the panel theme with Play page, Use in a session ▾ and Open in browser in the header.
- **Tests no longer touch your running roofd.** A self-test or fresh-profile run gets its own roofd folder and never
  registers the background item, and the capture script unregisters its test bundle afterwards. Before, a test build
  could take over the installed app's daemon (your sessions kept running, but were served by the test build).
- **Deck cards play again.** The bundled 0.2.0 deck wrote its narration list in a form Learn did not recognise, so a
  card's Play did nothing; it plays now. Playing a band or a programme queues the cards that follow (shown under Up
  next in the player's queue).

## 1.8.0 — Wall, seat routing rules and Learn Radio (26 Oct 2026)

- **Wall** (⌃⌥⌘3 or the layout control, LAB-1127): every window's live sessions on one page — ten tiles, fifteen on
  a very wide screen — each with its window, state, Right now line and last terminal lines. Click a tile to open that
  window on that session; Esc or ‹ Single goes back.
- **Seat routing rules** in Settings › Seats & accounts: the point at which a running objective step hands off to
  another agent (and new work skips a seat), and whether reviews go to a different model family. The router already
  followed these rules; now you can see and change them.
- **Learn Radio and All cards** (Learn › Radio, All cards): the Agentic Engineering deck as bands you tune into, with a
  now-playing panel that drives the player (it keeps playing while you work) and each band's narrated cards; All cards
  is the whole deck by suit and band. Learn's pages stay the first view.

## 1.7.0 — the composer and Grid (26 Oct 2026)

- **A real composer under every agent's terminal** (LAB-1125, NEW-1): type your message in the box and press ↩; it
  goes to the agent as if typed in the terminal. ⇧↩ adds a line, ↑ brings back what you sent, ⌃↩ runs it as a shell
  command (Claude's ! mode), ⌘. interrupts, and each session keeps its draft. While an agent waits on a decision the
  composer holds your text instead of sending it (Enter would answer the prompt): answer the card first.
- **Grid** (NEW-2, ⌃⌥⌘2 or the layout control): up to four live sessions of the window side by side, six on a wide
  window, each with its own terminal, composer and focus ring; ⌥⌘arrows move between tiles; Single puts your own panes
  back. Wall arrives in 1.8.0.
- The classic window stays available (Settings › General › Classic layout); its removal waits for your call (LAB-1225).

## 1.6.0 — the new window is the One Roof window (26 Oct 2026)

- **One Roof opens in the new window** (LAB-1091, milestone 6). If you never picked a window, you move to it now;
  Settings › General › Classic layout brings the 0.5.2.9 window back (and stays chosen), and Use the new window…
  there switches again.
- **Menus with the new names:** View has Home, Needs You, Sessions ⌘L, Work, Machine, Loops, Learn, Subagents; Single ·
  Grid · Wall (Grid and Wall arrive in 1.7.0 and 1.8.0); Focus: Step On ⌥⌘F and Step Back ⇧⌥⌘F; Sessions Column,
  Plan, Files Tab (⌥⌘B opens the Files tab), Changes, Dock ⌃⌘J and Look…. Shortcuts you set under the old names keep
  working. Edit gains **Copy Session Output** (the shown terminal's screen).
- **Fixes:** the app no longer crashes on a menu when only a pop-out or Roof window is left open (since 1.2.0, both
  windows); the editor in the Files tab no longer hides the start of every line; the Learn player and Run · Debug no
  longer cover Single · Grid · Wall; ⌥⌘C no longer resizes the new window (it brings the terminal forward); the hidden
  ⌃⌘1–7 place keys no longer clash with Learn's and Loops' shortcuts; a page (Settings, Help) closes when you pick a
  session from a notification, link or the menu bar; ⇧⌘A opens every session's subagents.

## 1.5.0 — Settings, Help and Setup in the new window (26 Oct 2026)

- **Settings, Help and Release notes open as pages** over the place you are in (LAB-997, milestone 5 of the new
  window; still off by default). The rail stays; Esc, ⌘[ or ‹ Back returns.
- **Settings has nine panes:** General, Appearance, Seats & accounts, Notifications, On-device model, Foundations,
  Learn, Shortcuts and **Updates** (this version, roofd, release notes, and Check now, which opens the download page).
  Every setting from before is in one of them.
- **Classic layout** (Settings › General) switches back to the 0.5.2.9 window after a restart, and **Use the new
  window…** in the classic window's Settings switches again.
- **Done when required** (off by default): New session waits for a Done when.
- **Foundations › Fix all** runs every failing check's fix in one terminal, one after another.
- **Setup** comes in three steps (agents; folders and tools; kit, look and Linear) and ends with Open One Roof.
## 1.4.1 — the places, part 2, in the new window (26 Oct 2026)

- **Needs you** (still behind the new-window setting): the card's button says **Always allow this** (the tooltip says
  what it allows and where), the count sits by the title, and a line under the buttons lists the keys.
- **Objectives:** **Send all to** puts every step of a plan on one seat this Mac has (each step's pickers still change
  it; the router's Route all steps stays).
- **Board** groups by Status, Agent or Project; **Loops** rows show each loop's trigger, limits and repo, where it
  stands, its last checks and its state.
- With the setting off, nothing changes.

## 1.4.0 — the places, part 1, in the new window (26 Oct 2026)

- **Places redrawn** (LAB-973, milestone 4 of the new window; still off by default): Home, Needs you, Work, Machine
  and Loops sit flat on the window's colour with white cards, as in the design.
- **Machine:** four meters (One Roof memory, CPU, this Mac, roofd), then this Mac by app beside One Roof itself and the
  sessions (this window's first). Sort, Quit, End and leftovers are all still there.
- **Loops:** the loops beside a **Tonight** panel (scheduled sessions and nightly loops, + Schedule a session, what
  ran last night); a loop opens as its own page (‹ Loops or ⌘[ back) with its **fences**: what is enforced and what the
  loop is only told.
- **Needs you › Rules:** click "Earlier today · n decided · m rules learned" to see your always-allow rules (Remove)
  and what you decided today.
- **Home:** + New objective beside + New work item; active projects show their done percentage.
- With the setting off, nothing changes. Next: 1.4.1 finishes the places (Work, the planner, plan approval, rows).

## 1.3.0 — Looks, Search and the row menu in the new window (26 Oct 2026)

- **Looks** (LAB-962, milestone 3 of the new window; still off by default): Settings › Appearance opens on six looks —
  Sky Studio, Mint Garden, Lavender Dusk, Peach Paper, Daylight, Midnight — each setting every panel at once.
  Customize each panel… keeps today's per-panel grid; text size, Follow macOS, row colours, sticker style and the
  window's colour sit below.
- **Search ⌘K** groups what it finds by source (views, actions, windows, decisions, Roof windows, looks, sessions,
  objectives, projects, the selected repo's files, skills, Learn) with Learn's best answer first and "Show all n" under a
  long group. **⌘↩ sends what you typed to the selected session.**
- **Right-click a session** for Rename…, Schedule, Interrupt, Send Handoff and a Copy menu too; the menu ends Close
  Agent… · Delete · Remove Exited Sessions….
- **Find in Workspace ⇧⌘S** fills the centre on its own, and Markdown, HTML, folder and search pages follow the window's
  look instead of the terminal's colours.
- With the setting off, nothing changes.

## 1.2.0 — session tabs and the Plan inspector in the new window (26 Oct 2026)

- **Session tabs** (LAB-929, milestone 2 of the new window; still off by default): Terminal · Files · Changes · Subagents
  · + Terminal above the terminal card, with Split ⌘D · Raw ⌘R · Wrap on the right.
- **Files** is the session's file tree beside the editor, with the open files as tabs (unsaved files keep their dot).
  Every editor feature stays: Outline · Problems · Git, Ask ⌘I, the claim banner, the Run dock, Markdown and HTML preview.
  **Split editor ⌘\** now shows a second open file beside the one you edit (for reading; open its tab to edit it).
- **Changes** is Review changes for the session's repo, plus **Ask the agent to commit** (it never pushes) and
  **Discard…**, which asks first and only restores files the last commit has; new, renamed and binary files are kept.
- **Subagents** shows a card per subagent (asked, doing or done, model, tokens, age) and the files they touched;
  Trace ▸ and Whole trace ▸ open today's trace, ‹ Subagents goes back.
- **The Plan inspector** has one row of text tabs: Plan · Ticket · Notes · Files · Usage.
- **Always allow** on a terminal's approval card shows Undo for 5 seconds, as in Needs you.
- With the setting off, nothing changes.

## 1.1.0 — the new window's shell, behind a setting (26 Oct 2026)

- **The One Roof 1 window, part 1** (LAB-929, milestone 1 of the new window; still off by default). With the new-window
  setting on, a window has places down a rail or as a row of icons (Home, Needs you, Sessions, Work, Machine, Loops,
  Learn), a session column with a window switcher, search and filter chips, the terminal as a rounded card, the Plan as
  an inspector or a slim edge tab, and a dock with seats, roofd, the startup check, Mac load, Needs you and Tonight.
- **The Focus ladder:** ⌥⌘F steps from everything (Full) to Sessions, Wide and Focus (just the terminal), ⇧⌥⌘F steps
  back, and each window remembers its step. At Focus, hover the left edge for the session list; the Plan slides over the
  terminal from its edge tab without moving it. ⌃⌘J folds or opens the dock; ⌃⌘1–⌃⌘7 open the places.
- Every place still opens the view you know until it gets its own new page in 1.4.0; with the setting off, nothing
  changes.

## 1.0.0 — One Roof 1: groundwork for the new window (26 Oct 2026)

- **Version numbers are now 1.x.y** (LAB-1209): 1 is the major release, x the milestone, y a fix or a smaller step
  inside it. This build is milestone 0 of the new window; 1.1.0 to 1.6.0 follow, and 1.6.0 turns the new window on.
- **Nothing changes on screen yet.** This release adds the groundwork for the new One Roof window behind a setting
  that is off: looks (six presets that set every panel at once), the Focus ladder, places, and per-window memory of
  each (LAB-921).
- Everything One Roof 0.5.2.9 does is written down as a checklist the new window must keep, line by line.

## 0.5.2.9 — Agentic Engineering cards play as animated explainers (25 Oct 2026)

- **Every card in Learn is new** (LAB-918, from Agentic Engineering 0.2.0). Each of the 156 cards now plays as a short
  animated explainer: one diagram per section, the step being narrated lights up, dots run along its arrows, and the
  panel beside it shows the same words the voice says. Plain-language narration, a warmer voice, all offline.

## 0.5.2.8 — every Agentic Engineering card opens as a card (25 Oct 2026)

- **No more raw text in Learn** (LAB-858). Four new cards (context-as-structure, handoff-read, weekly-review, cost-check)
  opened their skill file as plain text from the track pages, and two older cards (slack-dm-bot, plan-objective) had no
  narrated page at all. All 156 cards now open as narrated cards with audio.

## 0.5.2.7 — Agentic Engineering, bundled (25 Oct 2026)

- **The whole Agentic Engineering deck ships inside One Roof** (LAB-768). Learn (⇧⌘E) now has every narrated card, the
  deck's home and track pages, and all their audio, offline. The skills come too: One Roof links them into each agent's
  skills folder alongside its own, and never replaces a link that already points at your own copy of a skill.
- **No folder to choose.** Settings and first-run Setup no longer ask for an agentic-engineering folder; they show what is
  bundled. (Developers can still point One Roof elsewhere with `ONEROOF_AE_PATH`.)

## 0.5.2.6 — files open as tabs (24 Oct 2026)

- **Files open as tabs beside the terminals** (LAB-799). Opening a Markdown file, image, page, folder or code file used
  to replace the terminals in the centre. Now a strip at the top of the centre shows **Terminals** and one tab per open
  file: click Terminals to get them back as you left them, click a file's tab to see it again, and × closes it. Closing
  the last file brings the terminals back.

## 0.5.2.5 — the bug backlog (24 Oct 2026)

Fixes for the 23 One Roof bugs in the LAB-ONEROOF-BUGS backlog. Each one stays open until it is checked in this build.

**Windows**
- **A session stays in the window it was made in** (LAB-705). A new session used to join whichever window was in front
  when its launch finished, and a closed window's sessions showed up in the first window. Now a window lists only its
  own sessions; a closed window's sessions wait for it (Window › Workspaces reopens it).
- **Every window comes back after a quit or an install** (LAB-706). Quitting no longer counts as closing each window.
- **Move to Window › New Workspace Window… moves the session** (LAB-707), and **Open in New Window opens it** (LAB-708).

**Layout**
- **The window keeps its size** (LAB-596, LAB-653). The panels' minimum widths now fit the window, so opening Files or
  leaving the editor never grows it, a title-bar double-click never shrinks it, and quick clicks on toolbar tabs no
  longer count as a double-click.
- **The Sessions panel is a badge rail only while it is narrow** (LAB-651, LAB-714). Opening a file no longer leaves it
  stuck as icons; drag it wider or click the chevron at the top of the rail.
- **Sessions · Files · Terminal · Plan stay visible in the toolbar** (LAB-715); a long window name truncates instead,
  and anything that does overflow works from ».

**Terminal**
- **No blank block in terminal output after a reattach** (LAB-606). Terminals start at their real size, and roofd waits
  for that size before it redraws the session.
- **Wrap** (LAB-657): a toggle at the top right of each pane shows the terminal's text re-wrapped at word boundaries
  for reading; click it again to type in the live terminal.
- **The permission card shows the whole question** (LAB-716), and its buttons say what they do: Allow once, Always
  allow, Deny, Reply…. Always allow is hidden for prompts One Roof cannot read.
- **New Terminal from the centre panel** (LAB-745): New Terminal Here and Split Right with New Terminal in the
  terminal's right-click menu, a + Terminal button in the pane header, and New terminal in an empty pane.
- **Exited terminals move to Exited** (LAB-726) instead of staying in Active under their parent.

**Overview, Subagents, Learn**
- **Feed: newest on top** (LAB-591), resizable (drag the gap beside it), and each row says what happened, which agent,
  and whether it needs you; the session name shows once, on one line, and repeated events fold into one (LAB-659).
- **Overview drops its Board and Decisions sub-tabs** (LAB-593); they repeated the toolbar tabs.
- **Agents lists each live session with the subagents (lanes) it is running** (LAB-635).
- **Subagents timeline labels no longer overlap** (LAB-694), and the detail card explains itself: the task, who gave
  it, its status, its own final report, and the files it changed (LAB-695).
- **Career Agent is no longer in Learn** (LAB-713).

**New session**
- **The opening message is built from what you pick** (LAB-638): Where Are We, then the team, project and issues by key
  and title, then your own words. It follows your picks until you edit it.
- **Done when is explained** (LAB-639): it is told to the agent ("when that is true, tell me and stop there"); it never
  ends the session or runs last call.

## 0.5.2.4 — Back to agent, for real (23 Oct 2026)

- **Back to agent puts the run window away** (LAB-598). The floating run window stayed on top of the agent's terminal,
  so in 0.5.2.2 and 0.5.2.3 Back to agent seemed to do nothing. It now steps the run window out of the way and gives
  the agent's terminal the keyboard. The run terminal keeps running; the next Run in Terminal, or **Show window** on its
  ↳ row in Sessions, brings it back.

## 0.5.2.3 — Back to agent (23 Oct 2026)

- **Back to agent works** (LAB-598). In a run terminal's floating window, **Back to agent** now brings the agent's
  window forward on its terminal and gives it the keyboard. In 0.5.2.2 it only selected the agent, and the floating run
  window kept the keyboard, so nothing seemed to happen.

## 0.5.2.2 — no repeated notification prompt (23 Oct 2026)

- **"Allow notifications" no longer comes back again and again** (LAB-718). One Roof now reads macOS's own answer
  every time instead of remembering the first one, so it only asks when macOS has never been asked, and at most once
  per launch. Allowing One Roof in System Settings › Notifications takes effect straight away, without a restart.
  Settings › General shows no button once notifications are allowed, and **Open Notification Settings…** when they
  are turned off (macOS will not ask a second time).

## 0.5.2.1 — round 2 fixes (23 Oct 2026)

Two things in 0.5.2 did not work on a real Mac. This fix build makes them work.

- **Loops work in their own worktree from the first check** (LAB-677). In 0.5.2 roofd read every command's result as
  "success", so the loop's worktree was never made, its first check failed with "Folder not found", round 1 started in
  a folder that did not exist, and a failing check could have counted as a pass. roofd now reads real exit codes, makes
  and checks the worktree before the first check, and never starts a round outside it. A loop whose id starts with
  `loop-` no longer gets a doubled `loop-loop-` folder.
- **Get the model is in Settings › Foundations too** (LAB-675). In 0.5.2 the button showed only on the Foundations
  check; the Settings model row now has it, and the folder rows no longer do.

## 0.5.2 — loops, notifications, a model you may use for anything (23 Oct 2026)

Round 2 of One Roof 0.5.

- **Loops** (LAB-86). A new Loops screen (View › Loops, or "Loops" in the command palette) for work that repeats
  until a check passes, or runs every night. Give a loop a goal, a check command (exit 0 = done), an agent and limits
  (default 8 rounds, 3 hours, stop when the same failure repeats twice). One Roof runs the check and decides whether
  another round starts; the agent works in the loop's own worktree (`<repo>/.worktrees/loop-<id>`), never in your
  checkout, and nothing is pushed or merged. Loops run with One Roof open or closed. A round that asks permission shows
  in Decisions. **Test the check** before you save; start from **Fix until green** or **Nightly tidy**. Help › Loops.
- **Desktop notifications** (LAB-197). One Roof tells you when an agent needs you, when one finishes its turn, and
  when a command that ran longer than 30 s finishes in a terminal you are not looking at; programs' own notifications
  (OSC 9 and 777) come through too. Click one to jump to the session. Turn each kind on or off in Settings › General.
- **Run in Terminal** (LAB-598). Select a command in a terminal, right-click › Run in Terminal: One Roof types it into
  the agent's own run terminal (a shell in the same repo, in a small floating window) and you press Return to run it.
  One run terminal per agent, listed under it; **Back to agent** returns you.
- **Issue quality bar** (LAB-533). Pick issues marks issues that are missing what their type needs (for a bug: steps
  to reproduce, expected vs actual, where seen) as **not ready**, with a filter chip; the Ticket tab shows what is
  missing. Help › Issue quality bar.
- **The on-device model is now Qwen3 1.7B (Apache-2.0)** (LAB-673, LAB-674), replacing Arch-Router 1.5B, whose licence
  did not allow commercial use. On 38 test sentences it picks the right task kind 37 times (Arch-Router: 32), in about
  0.15 s. If Settings still points at Arch-Router it keeps working, with a note about its licence.
- **Get the model** (LAB-675). One click in Settings › Foundations, or on the Foundations check, downloads the model
  (1.1 GB), checks its size and SHA-256, and installs it with its licence. Stop and continue later; a file that does
  not match is thrown away.
- Captions ask the model for a fixed reply shape, so fewer are rejected. Resources names the model a leftover
  llama-server is running. Third-party notices now ship in the app.

## 0.5.1.1 — round 1 fixes (23 Oct 2026)

Two things in 0.5.1 did not work on a real Mac. This fix build makes them work.

- **The window name really is big and bold now** (LAB-590). In 0.5.1 the name at the top showed in plain, regular
  text with no colour. It is now large and bold, drawn in the window's colour with a small swatch when it has one;
  click it for Rename, Colour and the other windows.
- **Subagents show up in Overview and Subagents** (LAB-652, LAB-595). One Roof now finds each Claude session's exact
  conversation from its running claude process, instead of matching titles that rarely agree, and reads every
  subagent's own file, so subagents from early in a long session are found too. A subagent started in the background
  no longer shows as finished the moment it starts.

## 0.5.1 — window names, formatted files (23 Oct 2026)

The first release of One Roof 0.5 (round 1 of 5). It also carries the two fixes that were waiting for 0.4.11.

- **Each window has a big, bold name and its own colour** (LAB-509, LAB-590). Click the window's name at the top (or
  use Window › Rename Window… and Window › Window Colour). A coloured window gets a tinted title bar with the name and
  a stripe in that colour, so several windows are easy to tell apart. Mission Control and the Window menu show the
  name. A window with no colour looks as before.
- **Every window shows which One Roof is running** (LAB-526): "One Roof 0.5.1 (15)" next to "window N of M"; click it
  for these release notes. The sidebar footer shows roofd's real version instead of a stale "roofd 0.4.0", and
  quietly notes "older than app" while a roofd from an older One Roof is still running.
- **Four pastel themes** (LAB-601): Mint, Sky, Lavender and Peach, for any panel and the terminal, beside Daylight,
  Graphite and Midnight (Settings › Appearance or View › Theme). They turn Midnight in Dark Mode when following macOS.
- **Markdown opens formatted** (LAB-479). A `.md` file shows as a proper page in the centre panel: headings, nested
  and task lists, tables, coloured code blocks with Copy, quotes and images next to the file. Links to other files
  open in the viewer, `#links` jump to the heading, web links open in your browser. **Preview | Source** at the top
  switches to the editor and back; the preview shows unsaved edits.
- **HTML opens like a browser page** (LAB-480). `.html` files render in the centre panel with their CSS, scripts and
  images (relative paths across the repo work). Clicked web links open in your browser. **Preview | Source** edits
  the page, and ↻ reloads it from disk.
- **Subagents hang under their agent in Overview** (LAB-595). Each session in a window card shows the subagents it
  started, joined to it by tree lines, with a status dot, what each is doing and how long it has run. Click one to
  open its trace.
- **Settings › Allow scheduled runs says what it does** (LAB-285): roofd starts Tonight, Nightly and repeating
  sessions with One Roof open or closed. Leftover code for an old launchd scheduler that was never used is gone.
- **Browser tabs by name** (LAB-554). In Resources › This Mac, open Chrome (or Brave, Edge, Arc, Vivaldi, Opera,
  Safari) and press **Show tab names**: its open tabs are listed by site with their titles, and clicking one brings it
  forward. macOS asks once whether One Roof may control the browser. Memory per tab stays in the browser's Task
  Manager (⇧Esc), because macOS does not say which process is which tab.
- **A force-quit no longer leaves the local model running** (LAB-549). The on-device model (llama-server) now runs
  under a small watchdog that stops it within about 2 seconds of One Roof ending, however it ended: Quit, Force Quit,
  a crash. One that an older version left behind counts in One Roof's figures at the top of Resources, and the model
  is restarted if it ever grows past 3 GB (one grew to 8.4 GB over a day on 22 Oct).

## 0.4.10 — the whole Mac in Resources (22 Oct 2026)

- **Resources covers the whole Mac** (LAB-544). A new **This Mac, by app** card lists every app with its memory and
  CPU; open one to see its processes, with Chrome's (and other Chromium apps') helpers named: tab or site, extension,
  GPU, network … **Quit** an app or **End** a process from there, after a confirmation. One Roof's leftovers (a local
  model a force-quit left running, roofd from older builds) show at the top with **Stop**, and One Roof stops a
  left-over local model by itself when it starts.
- **Pick issues refreshes from Linear** (LAB-546): on opening, on every chip click, every minute, and with a ↻ button,
  so new issues show up without restarting. **Columns sort** (LAB-547): Key (by number), Title, State, and the new
  Created and Updated columns.
- **Narrow plan panel fits** (LAB-548): the tab bar tightens, then shows icons, instead of pushing the panel off both
  edges. The Ticket tab's state buttons no longer wrap letter by letter; when they don't fit they become one
  **Move to** menu (LAB-530).

## 0.4.9 — no more freeze (22 Oct 2026)

- **0.4.8 froze the window** (LAB-540). The Artifacts tab's label worked out its count by rereading the handoff folder
  on every redraw, several times per redraw, so the window never caught up. The list is now kept and refreshed in the
  background (when the session changes, and every 10 s for new handoffs), and the folder is matched with one pattern.

## 0.4.8 — the backlog batch (22 Oct 2026)

- **Sessions list stays put** (LAB-515, LAB-490). Working, Ready and Idle are one **Active** group and chip (the row's
  dot and caption still say which). Rows keep their place while agents work and rest, and a status moves a row to
  another group only once it has held (2 s for Needs you, 6 s otherwise). Chips: All · Needs you · Active · Exited.
- **Rename persists** (LAB-487). The plan panel wrote its own stale copy of every field back when you left a session,
  undoing a rename made from the menu or popover. It now saves only the fields you edited there. **Notes › Save** says
  Saved (with the time) or Unsaved changes (LAB-512).
- **Ticket tab lists the issues a session works on** (LAB-511): keys in its name, opening message, notes and terminal
  ("LAB-474", "bugs 298 and 460"), with their Linear title and state and one-click Attach.
- **Artifacts tab is the session's own** (LAB-513): files its agent wrote or edited (kept after each turn), its plan,
  handoffs it wrote, and screenshots it was given. The exited pane offers only a handoff written during the session
  (LAB-510).
- **Opening messages start with Where Are We** (LAB-491), anchored in the session's project and team.
- **Toolbar toggles in panel order: Sessions · Files · Terminal · Plan** (LAB-522); Terminal is new. A toolbar
  double-click no longer shrinks a window that fills the screen (LAB-520). The pane header is never cut off (LAB-521).
- **Finder icons in the Files panel** (LAB-478).
- **Dotted project codes** like LAB-ONEROOF-v0.50 are read whole; their commit tag drops the dot (LAB-519).
- **Ask to fix** won't type into a working or waiting agent (LAB-284).
- **roofd repairs its background item** when launchd's job is stuck after a dev → release switch (LAB-516). CI runs
  roofd's tests again (LAB-283).

## 0.4.7 — pick issues in a panel (21 Oct 2026)

- **Pick issues in a panel you can resize and read** (LAB-523). Issue ▾ in New session opens a **Pick issues** panel
  beside the sheet instead of a fixed popover: a table with resizable columns (tick · order · key · title · state), the
  rows in one order (In Progress, To do, Backlog, In Review last), state filters with counts, a filter that also
  searches the description, and a pane under the table that shows the selected issue in full before you add it. The
  panel remembers its size.
- **Ticking an issue no longer moves it** (LAB-527). Picked issues used to jump to the top, so the list scrolled under
  the pointer. Rows stay put; a **Picked** chip shows just the ones you ticked, in the order you ticked them.
- **The opening message names every picked issue** (LAB-528). Once you had typed into the opening message it stopped
  following your picks, so a session started on 20 issues told its agent about the first 3. Your words now stay and
  only the list of issues in the message changes as you tick.
- **Agents in a session reach the right roofd** (LAB-529). One Roof opened from a terminal inside one of its own
  sessions passed that session's roofd path on to every new session, so agents could call an older roofd (their issue
  updates failed). Each session now gets its own.
- **Small fixes.** A finished turn's caption says **Ready**, the same word as its status (it said Done) (LAB-241). The
  exited pane's **Open … handoff** also finds a handoff named after any of the session's issues and says which one, and
  no longer matches a longer id that merely contains the key (LAB-250).

## 0.4.6 — one session on several issues (21 Oct 2026)

- **Start one session on several issues** (LAB-518). In New session, **Issue ▾** is now a checklist: tick several of the
  project's open issues (active, to do or backlog) and One Roof makes one session for all of them, named with every key
  (`LAB-1, LAB-2, LAB-3 · title`). Its opening message asks the agent to read them all and write one plan that resolves
  them in the best order, then work through them in that order.
- **Agents keep each issue up to date.** Inside a session an agent can run `"$ONEROOF_ROOFD_BIN" issue KEY --state "In
  Progress"|"In Review" --comment "…"`; One Roof applies it to Linear with your key, only for that session's own issues
  and never to Done. A session on several issues no longer moves them all to In Progress at launch.

## 0.4.5 — Resources names every session (21 Oct 2026)

- **Resources names every session correctly** (LAB-517). A session whose agent had finished while its terminal stayed
  open showed under Other as `roof-…`, "not a One Roof row". It now stays in its window under its own name (status
  Exited), and its Resources tab in the plan panel shows the memory that terminal still holds.

## 0.4.4 — Resources: what One Roof uses (21 Oct 2026)

- **Resources: see what One Roof itself uses** (LAB-493). View › Resources (⇧⌘U, or Resources in the toolbar) shows
  One Roof's total memory and CPU with 10-minute charts, the Mac's memory, pressure and swap, the app and the roofd
  daemon, and every running session by window, heaviest first, with a bar against roofd's memory guard (warns at
  1 GB, ends the session at 2 GB). Click a session to go to it. The plan panel has a **Resources** tab for the
  selected session: memory and CPU now and over 10 minutes, the guard, and every process under it.

## 0.4.3 — roofd memory fix (21 Oct 2026)

- **roofd no longer eats the Mac's memory.** Each session's process kept every answer it gave the app, so a session
  open for a day grew to several GB and macOS froze. It now stays at a few MB, and as a safety net a session that
  passes 2 GB ends itself (noted in `roofd-memory.log` in roofd's folder) instead of taking the Mac down.
- **A session can work on several issues** (LAB-474). Add issue… (session menu, right-click, or the Ticket tab) adds
  an open issue or a new one at any point; the row shows `KEY +N`, the Ticket tab lists each one, and closing asks
  per issue. A commit that names an issue moves it to In Review on its own, once. If the agent is busy when you add
  one, the note waits and goes in as soon as it is back at its prompt.
- **New session no longer slides off the screen** (LAB-472): picking New bug made the bottom row too wide; it now
  wraps to two lines when it does not fit.

## 0.4.2 — a one-click session menu, and pasting images (21 Oct 2026)

- **The session menu is one click for everything.** Stickers are labels only, colours are swatches and emoji sit in the menu itself; the colourful menu has a row of buttons (Open, Next, Pin, Rename, Highlight) instead of tiles, and no Close.
- **Paste or drop screenshots into New session** (LAB-462): ⌘V or a drop attaches them as removable thumbnails; the opening message names them for the agent, and a new Linear issue gets them uploaded into its description.
- **A launched agent's terminal shows at once** (LAB-299), with a "Starting…" strip while your login shell and the agent start, instead of a blank pane for 2–3 s.

## 0.4.1 — closing things, and fixes (21 Oct 2026)

- **Closing a window works.** Tick "Yes, I'm sure" and press Close, and the window closes (it stayed open before).
- **An ✕ on every session row.** Point at a row (or select it) and click ✕: a running session asks first, then
  closes; a stopped one is removed, and File › Reopen Closed Session (⇧⌘T) brings it back.
- **Exited sessions look stopped.** Their rows are grey and faded until you point at or select them.
- **A second window no longer blinks** while attaching, and no longer shows the doors dialog on launch.
- **Sessions don't inherit self-test settings**, so One Roof opened from a terminal session starts normally.

## 0.4.0 — roofd, One Roof's own session manager (20 Oct 2026)

- **herdr is gone: nothing to install but your agents.** Sessions run in roofd, a small session manager inside the
  app. One terminal emulator end to end: real scrollback, native selection and copy, prompt marks, and keystroke echo
  about a hundred times faster than before.
- **Sessions outlive the app, and a crash costs only what it must.** Quit, update or reopen One Roof and every session
  comes back with its history; one session's crash never ends another.
- **Status from the agents themselves:** Claude's hooks, screen prompts and screen activity give Working, Needs you
  and Ready for all five agents, including first-run menus.
- **Tonight and Nightly run with the app closed** when scheduled runs are allowed; roofd sends the opening message once
  the agent is ready.
- **Steps you can rewind and explain.** The steps list at the top of a pane is capped at six (it scrolls); click a
  step to scroll the terminal back to it and read on, **Back to current** to return. The right panel's **Step review**
  has Claude's reading of the latest step (or the one you clicked): what was asked, what happened, decisions and risks.
  It is off until you switch it on in that box, since each reviewed step is one more model call.
- **Loops.** Repeat a session every 15 min to 4 h (right-click › Repeat, or When › Every): roofd launches it, or
  sends its message again when the agent waits, never mid-work, even with the app closed.
- **Paste images into a terminal.** ⌘V with a screenshot or copied image saves it and types its path, so the agent
  attaches it; files copied in Finder paste as full paths; images dragged in from a browser work too.
- **Linear projects, all of them.** One Roof reads every Linear project (code = the part of the name before " · ",
  like `ENG-CHECKOUT`; older `WS-` names still work), and "Workstream" is now called Project everywhere. The New work
  sheet has Team and Project pickers, tickets get Linear's Type label (Deliverable, Bug, Task, Spike, Decision), and
  a new project is created in Linear with its milestones before a Claude session sets up its docs and first tickets.
- **The New session sheet starts sessions on existing work.** ⌘N has **Team ▾ · Project ▾ · Issue ▾** pickers
  instead of kind tabs: pick an open issue and the session works on it; the **New issue** types and **New project…** are the
  last menu items, for work not in Linear yet. Status names are the same in the filter chips and the group headings
  (Needs you · Working · Ready · Idle · Exited, with meanings on hover), and the session shown in the terminal stands
  out in the sidebar with an accent outline and a left bar.
- Agents typed into a One Roof terminal still show as that agent. Agents started in other terminal apps are no longer
  listed; Copy attach opens any One Roof session from another terminal.

## 0.3.1 — signed and notarized

- **The app is signed with an Apple Developer ID and notarized by Apple.** It opens on first launch like any other
  app: no "cannot verify" warning, no Privacy & Security › Open Anyway step.

## 0.3.0 — first public release

- **One Roof app (macOS 14+, Apple silicon).** libghostty terminals on herdr sessions for Claude Code, Codex, Kimi,
  Gemini CLI and Antigravity; live status, stickers, grouping, Board and Launchpad; planned sessions; objectives that
  are planned by a visible planner session and run step by step after approval; seat capacity and agent routing with
  an optional on-device classifier; code review panel, split panes, roof windows; Learn with a narrated course.
- **First-run setup.** Choose your projects folder, shared folder and agentic-engineering folder; see which agents are
  installed and signed in. Everything is a setting; nothing assumes a particular workspace layout.
- **Agentic engineering starter set** (`agentic_engineering/`): 17 skills and 12 narrated lessons, bundled with the app.
- **The kit (`roof`).** One launch folder, one memory, one rulebook for every agent; `roof swarm` for parallel tasks in
  git worktrees with file claims, timeouts, retries and one-at-a-time merging.
- **Terminals:** drag to select, ⌘C / ⌘V, right-click Copy · Paste · Select All · Clear, drop a file to type its
  path; Option sends the mouse to the program. Checked before every release with `tools/terminal-basics.sh`.
- The app download is not yet signed with an Apple Developer ID: allow it once on first launch (macOS 15+: System Settings › Privacy & Security › Open Anyway; macOS 14: right-click › Open).
