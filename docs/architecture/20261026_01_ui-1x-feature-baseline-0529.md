# One Roof 0.5.2.9 · feature baseline for the 1.x window (no-regression list)

**Status:** ACTIVE · **Date:** 2026-10-26 · **Project:** LAB-ONEROOF-UI-REDESIGN · **Linear:** LAB-922

> **One line:** everything One Roof 0.5.2.9 does, read from the code, so the 1.x v2 window can be checked line by line: nothing that works today may go missing.

**v2 home:** this list deliberately has no v2 column yet. The 1.6.0 parity audit (LAB-1097, sub-issues PAR.01-PAR.15, one per section below) adds it: each line gets its v2 place and screen, or the owner decision that retired it.

How to use it: every line is ticked in the 1.6.0 parity audit (LAB-1097) as "works in v2 (where)" or "retired by an owner decision". The handover's own list (NO_REGRESSION.md, 69 rows) is a second checklist. Format: `area | feature | how invoked | source` (paths under `app/Sources/`, `OR/` = `OneRoof/`, `Core/` = `OneRoofCore/`). Generated from a read-only code sweep at 0.5.2.9 (2026-10-25).

## 1. App menu (One Roof)
App menu | About One Roof | menu | OR/AppDelegate.swift:481
App menu | Settings… | ⌘, | OR/AppDelegate.swift:483
App menu | Setup… (first-run window: folders, agents, Linear key) | menu; opens automatically on first run or with --fresh-profile | OR/AppDelegate.swift:484, :88
App menu | Foundations… | ⇧⌘F | OR/AppDelegate.swift:485
App menu | Run Startup Check | menu (no shortcut) | OR/AppDelegate.swift:486
App menu | Command Palette… | ⌘K | OR/AppDelegate.swift:487
App menu | Command Palette (hidden duplicate) | ⌘P | OR/AppDelegate.swift:488
App menu | Services submenu | menu | OR/AppDelegate.swift:492
App menu | Hide One Roof / Hide Others / Show All | ⌘H / ⌥⌘H / menu | OR/AppDelegate.swift:496-500
App menu | Quit One Roof (all windows come back at next launch, LAB-706) | ⌘Q | OR/AppDelegate.swift:502, :94

## 2. File menu
File | New Session… (opens the New session sheet) | ⌘N | OR/AppDelegate.swift:507
File | New Terminal (plain shell in ~/Projects) | ⌘T | OR/AppDelegate.swift:508
File | New Terminal in Selected Repo | ⌃⌘T | OR/AppDelegate.swift:509
File | New Workspace Window… | ⇧⌘N | OR/AppDelegate.swift:510
File | New Roof Window for Selected Repo | ⌥⌘N | OR/AppDelegate.swift:511
File | New Objective… | ⇧⌘O | OR/AppDelegate.swift:512
File | New Work Item… (opens Work and the intake sheet) | ⌃⌘N | OR/AppDelegate.swift:513
File | Open File… (NSOpenPanel, opens in the centre viewer) | ⌘O | OR/AppDelegate.swift:515, :232
File | Save (editor file) | ⌘S | OR/AppDelegate.swift:516
File | Launch Selected Session | ⌘↩ | OR/AppDelegate.swift:518
File | Close Session… (asks first) | ⌘W | OR/AppDelegate.swift:519
File | Reopen Closed Session | ⇧⌘T (hidden alias ⌥⌘T) | OR/AppDelegate.swift:520-523
File | Open in New Window (pop-out) | ⌥⌘O | OR/AppDelegate.swift:524
File | Close Window (with confirm-tick sheet) | ⌃⌘W | OR/AppDelegate.swift:526; OR/WindowCloseGuard.swift:11

## 3. Edit menu
Edit | Undo / Redo | ⌘Z / ⇧⌘Z | OR/AppDelegate.swift:533-534
Edit | Cut / Copy / Paste / Select All | ⌘X/⌘C/⌘V/⌘A | OR/AppDelegate.swift:536-539
Edit | Clear Terminal | ⌥⌘K | OR/AppDelegate.swift:541
Edit | Find… (find in terminal) | ⌘F | OR/AppDelegate.swift:543
Edit | Find Next / Find Previous | ⌘G / ⇧⌘G | OR/AppDelegate.swift:544-545
Edit | Find in Workspace (git grep search) | ⇧⌘S | OR/AppDelegate.swift:546
Edit | Ask Agent About Selection (editor) | menu; ⌘I inside the editor text view | OR/AppDelegate.swift:547; OR/UI/EditorView.swift:440

## 4. View menu
View | Group by Status / Repo / Project / Agent / Account / Folder | ⌘1–⌘6 (tag order: status, repo, workstream, agent, account, domain) | OR/AppDelegate.swift:552; Core/Board.swift:43
View | Sessions Panel Theme ▸ (Daylight, Graphite, Midnight, Mint, Sky, Lavender, Peach) | submenu | OR/AppDelegate.swift:558-569; Core/Theme.swift:18
View | File Browser Theme ▸ | submenu | same
View | Terminal Theme ▸ (the 7 above plus hidden Blueprint) | submenu | Core/Theme.swift:19
View | Plan Panel Theme ▸ | submenu | same
View | Centre Views Theme ▸ | submenu | same
View | Overview (shows a check mark when on) | ⇧⌘L | OR/AppDelegate.swift:571
View | Resources | ⇧⌘U | OR/AppDelegate.swift:572
View | Board | ⌘B | OR/AppDelegate.swift:573
View | Decisions | ⌘I | OR/AppDelegate.swift:574
View | Subagents | ⇧⌘A | OR/AppDelegate.swift:575
View | Loops | menu (no key) | OR/AppDelegate.swift:576
View | Learn | ⇧⌘E | OR/AppDelegate.swift:577
View | Work: Projects and Roadmap | ⇧⌘W | OR/AppDelegate.swift:578
View | Bigger Text / Smaller Text / Actual Size (per-window UI scale 0.85–1.3, also changes terminal font) | ⌘+ / ⌘− / ⌘0 | OR/AppDelegate.swift:580-582, :205
View | Toggle Sidebar | ⌥⌘S | OR/AppDelegate.swift:584
View | Toggle Plan Panel | ⌥⌘P | OR/AppDelegate.swift:585
View | Terminal Panel (centre) | ⌥⌘C | OR/AppDelegate.swift:586
View | File Browser | ⌥⌘B | OR/AppDelegate.swift:587
View | Search in Workspace | menu | OR/AppDelegate.swift:588
View | Review Changes (disabled outside a git repo) | ⌥⌘R | OR/AppDelegate.swift:589, :733
View | Split Right / Split Down | ⌘D / ⇧⌘D | OR/AppDelegate.swift:592-593
View | Close Pane | ⌥⌘W | OR/AppDelegate.swift:594
View | Maximize Pane | ⇧⌘↩ | OR/AppDelegate.swift:595
View | Even Out Panes | menu | OR/AppDelegate.swift:596
View | Focus Pane Left / Right / Up / Down | ⌥⌘← → ↑ ↓ | OR/AppDelegate.swift:597-602
View | Focus: Terminal Only (hide both side panels; again restores) | ⌥⌘F | OR/AppDelegate.swift:604; OR/MainWindowController.swift:272
View | Focus Terminal | ⌘L | OR/AppDelegate.swift:605
View | Raw Stream / Run (Raw stream in a session; Run in the Editor) | ⌘R | OR/AppDelegate.swift:606, :225
View | Debug (Editor only) | ⇧⌘R | OR/AppDelegate.swift:607

## 5. Session menu
Session | Launch (also Run Now) | menu | OR/AppDelegate.swift:612, :630
Session | Mark as Next / Mark as Planned | menu (disabled for live sessions) | OR/AppDelegate.swift:613-614
Session | Do Not Use (checkable; toggles back to planned or idle) | menu | OR/AppDelegate.swift:615, :170
Session | Pin / Unpin (title changes) | menu | OR/AppDelegate.swift:616, :726
Session | Rename… (NSAlert with a text field) | menu | OR/AppDelegate.swift:617, :240
Session | Move to Window ▸ (every workspace, current one checked; New Workspace Window… moves the session there) | submenu | OR/AppDelegate.swift:618, :781-804
Session | Schedule ▸ Tonight 2:00 AM / Nightly at 2:00 AM / On Demand | submenu | OR/AppDelegate.swift:623-629
Session | Interrupt (Esc for Claude, Ctrl-C for the others) | ⌘. | OR/AppDelegate.swift:631; OR/AppModel+Engines.swift:192
Session | Send Handoff (asks the agent to write a handoff, between turns only) | menu | OR/AppDelegate.swift:632; OR/AppModel+Engines.swift:200
Session | Open in New Window | menu | OR/AppDelegate.swift:634
Session | Open Repo in Finder | menu | OR/AppDelegate.swift:635
Session | Copy session id / Copy Working Directory / Copy Attach Command / Copy Link to Session (oneroof://) | menu | OR/AppDelegate.swift:636-639
Session | Close Agent… | menu | OR/AppDelegate.swift:641
Session | Delete Session (not for adopted sessions) | menu | OR/AppDelegate.swift:642
Session | Remove Exited Sessions… (confirm alert; pinned sessions stay) | menu | OR/AppDelegate.swift:643, :190
Session | Next Session / Previous Session | ⌘] / ⌘[ | OR/AppDelegate.swift:645-646

## 6. Window menu
Window | Minimize / Zoom | ⌘M / menu | OR/AppDelegate.swift:651-652
Window | All Windows (goes to Overview) | ⌃↑ | OR/AppDelegate.swift:654
Window | Rename Window… (alert: "Name this window") | menu | OR/AppDelegate.swift:655; OR/WindowState.swift:83
Window | Window Colour ▸ None, Coral, Peach, Butter, Mint, Aqua, Sky, Periwinkle, Lavender, Rose (tints the toolbar band, adds a 2 pt stripe, colours the name) | submenu | OR/AppDelegate.swift:656-664; OR/MainWindowController.swift:215
Window | Workspaces ▸ (every workspace, open or "(closed)", ⌥⌘1–9, plus New Workspace Window…) | submenu | OR/AppDelegate.swift:665; :807-833
Window | Workspace 1–9 (hidden key items) | ⌥⌘1–⌥⌘9 | OR/AppDelegate.swift:669-673
Window | Roof Windows ▸ (one item per repo or workstream with live sessions, with counts) | submenu | OR/AppDelegate.swift:674; :836-858
Window | Foundations | menu | OR/AppDelegate.swift:678
Window | Bring All to Front | menu | OR/AppDelegate.swift:680

## 7. Help menu
Help | One Roof Help (opens the bundled help in Learn) | menu | OR/AppDelegate.swift:686, :271
Help | How Do I…? | ⌥⌘/ | OR/AppDelegate.swift:687
Help | Keyboard Shortcuts (Settings › Shortcuts tab) | menu | OR/AppDelegate.swift:688
Help | Release Notes (bundled CHANGELOG, opened in the viewer) | menu | OR/AppDelegate.swift:689
Help | One Roof README | menu | OR/AppDelegate.swift:691
Help | Help Pages Folder | menu | OR/AppDelegate.swift:692

## 8. Global keys and shortcut customisation
Shortcuts | Override any menu shortcut by menu title (Record, Reset, Reset all, filter) | Settings › Shortcuts | OR/UI/ShortcutsSettings.swift:36-50; OR/ShortcutBridge.swift
Shortcuts | Global hotkey: show or hide One Roof from any app (Record / Clear) | Settings › Shortcuts | OR/UI/ShortcutsSettings.swift:26-30; OR/AppDelegate.swift:404
Keys | Control-key combos go to the terminal, not the menu | terminal focus | OR/Ghostty/TerminalSurfaceView.swift:406

## 9. Toolbar (one per main window)
Toolbar | View switcher: Workspace · Overview · Resources · Board · Decisions (with open count) · Work · Learn | segmented buttons | OR/UI/Toolbar.swift:123-161; OR/WindowState.swift:28
Toolbar | Switcher highlight rules: Editor, Review and Objective light Workspace; Subagents lights Overview | — | OR/UI/Toolbar.swift:154
Toolbar | Window name (bold, in its colour, with swatch) plus a menu: Rename Workspace…, Colour ▸, New Workspace Window…, the other windows | click name | OR/UI/Toolbar.swift:167-223
Toolbar | "window N of M" label | static | OR/UI/Toolbar.swift:192
Toolbar | App version label (click for release notes) | click | OR/UI/Toolbar.swift:239
Toolbar | Search field "Search sessions, files, docs ⌘K" (opens the palette) | click | OR/UI/Toolbar.swift:254
Toolbar | Labelled panel toggles Sessions · Files · Terminal · Plan; the last open panel can't close (the row shakes) | click | OR/UI/Toolbar.swift:276-313; OR/MainWindowController.swift:261
Toolbar | Mini player (play/pause, open in Learn) while Learn audio is loaded | click | OR/UI/Toolbar.swift:324; OR/CoursePlayer.swift:205
Toolbar | Editor only: ▶ Run ⌘R · Debug ⇧⌘R · interpreter label | click | OR/UI/EditorView.swift:766
Toolbar | + New session | ⌘N / button | OR/UI/Toolbar.swift:332
Toolbar | Overflow » menu items for every control (View, This Window, Search, Panels, New Session) | toolbar overflow | OR/UI/Toolbar.swift:79-110
Toolbar | Double-clicks on controls count as single clicks; a title-bar double-click never shrinks the window | — | OR/MainWindowController.swift:154, :179

## 10. Main window layout and panels
Layout | 4-panel split: Sessions · Files · Centre · Plan, each collapsible; widths autosaved per workspace; defaults 300 and 330 pt | — | OR/MainWindowController.swift:68-132
Layout | Closing the centre gives its width to the Plan panel | ⌥⌘C | OR/MainWindowController.swift:240
Layout | Fleet views (Overview, Resources, Board, Decisions, Subagents, Work, Learn, Loops) fold the Sessions panel away; Workspace restores it | automatic | OR/MainWindowController.swift:282; OR/WindowState.swift:31
Layout | Editor folds Sessions to a 56 pt rail, hides Plan, opens Files | automatic | OR/MainWindowController.swift:292
Layout | Centre views crossfade (0.18 s; respects Reduce Motion) | — | OR/MainWindowController.swift:431
Layout | Panel ✕ close buttons on Sessions, Files, Plan | button | OR/UI/Components/Basics.swift:284
Layout | First launch: window opens at 85% of the screen (max 1700×1000) on Overview; later windows cascade | — | OR/MainWindowController.swift:116; OR/AppDelegate.swift:118

## 11. Sessions panel (sidebar)
Sessions | Seat usage bars (Claude1, Claude2, Codex, Kimi, Gemini; tooltip shows 5 h / 7 d % and reset time) | hover | OR/UI/SessionsPanel.swift:120-128, :258
Sessions | Count chips: All · Need you · Active · Exited (filter; Exited counts agents only) | click chip | OR/UI/SessionsPanel.swift:130-153; OR/WindowState.swift:124
Sessions | "Remove all exited sessions" link (Exited filter) | link | OR/UI/SessionsPanel.swift:67
Sessions | Group ▾ menu (6 groupings, each with ⌘n hint) | menu | OR/UI/SessionsPanel.swift:99
Sessions | Filter text field with ✕ clear | type | OR/UI/SessionsPanel.swift:106
Sessions | Group headers with counts; Pinned group on top; status groups Needs you · Active · Next · Planned · Exited; group changes are debounced | — | OR/UI/SessionsPanel.swift:187; docs/help/01_sessions.md:28
Sessions | Empty and filtered states ("Show all N sessions") | — | OR/UI/SessionsPanel.swift:202
Sessions | Row click selects the session and shows the Workspace view | click | OR/UI/SessionsPanel.swift:169
Sessions | Row double-click on the name renames inline (Return / Esc) | double-click | OR/UI/Components/SessionRow.swift:117
Sessions | Row ✕ (on hover or when selected): close a live session (asks) or remove a stopped one | button | OR/UI/SessionsPanel.swift:159
Sessions | Row drag (oneroof-session payload) onto Board, Overview cards | drag | OR/UI/SessionsPanel.swift:183
Sessions | Row shows agent badge + status dot, name, emoji, pinned dot, unread dot, busy spinner, schedule/status pill, age, caption, account · branch +/−, up to 2 stickers (+N), ticket and project chips; exited rows greyed; selected row has outline and left bar; optional colour fill | — | OR/UI/Components/SessionRow.swift:105-157
Sessions | Run-terminal rows indented under their agent with ↳ | — | OR/UI/SessionsPanel.swift:391
Sessions | Rail mode (narrow): badges only, widen button, accent ring on the file claimer | drag narrow / Editor | OR/UI/SessionsPanel.swift:31; Core/WindowZoom.swift:43
Sessions | Footer: roofd status dot + runtime state, "· older than app" note, Foundations status button (Checking… / N issues / ok) | click opens Foundations | OR/UI/SessionsPanel.swift:220-245
Sessions | Row popover (•••): see §13 | — | OR/UI/SessionsPanel.swift:171

## 12. Session context menu (rows, Board cards, Overview cards)
Ctx menu | Launch / Relaunch / Open | right-click | OR/UI/SessionsPanel.swift:278-282
Ctx menu | Mark as Next / Mark as Planned (live: Next sticker toggle "Not Next") | right-click | :284-289
Ctx menu | Do Not Use / Use Again | right-click | :290
Ctx menu | Pin / Unpin | right-click | :291
Ctx menu | Attach Issue… / Add Issue… | right-click | :293
Ctx menu | Repeat ▸ Every 15 min/30 min/1 h/2 h/4 h, Stop Repeating (needs an opening message first) | right-click | :299-314; Core/Schedules.swift:16
Ctx menu | Stickers section (toggles with icons) | right-click | :318
Ctx menu | Row Colour palette (No Colour + 9 pastels) | right-click | :326
Ctx menu | Emoji palette (No Emoji + 14 emoji in two rows) | right-click | :340; Core/Stickers.swift:106
Ctx menu | Emoji, New Sticker and Rename… (opens the popover) | right-click (sidebar only) | :354
Ctx menu | Move to Window ▸ / New Workspace Window… | right-click | :356
Ctx menu | Open in New Window; Roof Window for <repo> (live only) | right-click | :363-366
Ctx menu | Review Changes · Terminal Here · Show Folder in Finder · Copy Folder Path · Copy Link to Session · Copy Attach Command | right-click | :367-383
Ctx menu | Close Agent… / Delete | right-click | :385-386

## 13. Session popover (••• in the Plan panel, or "Emoji, New Sticker and Rename…")
Popover | Header with agent logo, emoji, name, agent · account · repo | — | OR/UI/SessionPopover.swift:28
Popover | Quick-action chips: Launch/Relaunch, Open, Next, Pin, Rename, Issue…, Highlight (Important), Do not use, Delete | click | OR/UI/SessionPopover.swift:81-105; Core/Stickers.swift:159
Popover | Sticker picker: 10 built-ins (Next, WIP, Important, Blocked, Review, Idea, Bug, Research, Shipped, Do not use) + custom stickers + "New sticker…" field | click / type | OR/UI/StickerViews.swift:69-89; Core/Stickers.swift:59-68
Popover | Colour swatches, Emoji grid | click | OR/UI/SessionPopover.swift:46-73
Close dialog | Close <name>? with one "Comment on KEY and move it to In Review" box per issue | NSAlert | OR/UI/SessionPopover.swift:138-163

## 14. Centre: terminal area (Workspace view)
Terminal | libghostty terminal attached to roofd per session, cached per agent so switching is instant | select row | OR/UI/TerminalAreaController.swift:326
Terminal | Split panes (tree), drag dividers, saved per workspace, focus follows click; a new pane waits for a pick | ⌘D/⇧⌘D, drag | :445, :372, :139
Terminal | Maximize pane (zoom), close pane (the last pane stays), even out, directional focus | keys / pane buttons | :454-479
Pane header | Badge, name, account · model · branch (or cwd for shells), ticket chip, project chip, key hints | — | OR/UI/PaneChrome.swift:53-128
Pane header | + Terminal (new shell in this session's folder) | button | OR/UI/PaneChrome.swift:89
Pane header | Wrap (read-only re-wrapped text of the terminal, live, follows output) | button | OR/UI/PaneChrome.swift:97; OR/UI/TerminalAreaController.swift:407
Pane header | Focus terminal only | button | OR/UI/PaneChrome.swift:114
Pane header | ⤢ maximize / ✕ close pane (in split mode) | button | OR/UI/PaneChrome.swift:118-121
Summary | Summary strip (status dot, "Step n of m", caption, Summary ▾) | click | OR/UI/PaneChrome.swift:139
Summary | Summary card (You asked · Right now · Steps list; ▴ collapse; expanded by default in a tall single pane) | click | OR/UI/PaneChrome.swift:165
Chapters | Finished-step rows over the terminal (✓ n · title · summary · calls · duration); click rewinds the scrollback to that step | click | OR/UI/PaneChrome.swift:247; OR/UI/TerminalAreaController.swift:282
Chapters | Rewind bar "Viewing step n… Back to current" | button | OR/UI/PaneChrome.swift:279
Raw stream | Raw stream ⌘R / Chapters ⌘R toggle (hides the chapter rows) | ⌘R or hint-strip button | OR/UI/PaneChrome.swift:404; OR/UI/TerminalAreaController.swift:117
Hint strip | "Message <agent> · ⌃↩ run as shell · @ file · / skill · ⌘. interrupt" | — | OR/UI/PaneChrome.swift:392
Approval card | Over the terminal when it needs you: title, risk pill, Why, touches, Allow once · Always allow (hidden for unknown prompts) · Deny · Reply… field | buttons | OR/UI/PaneChrome.swift:304-369
Starting strip | "Starting <agent>… your login shell runs first" | automatic | OR/UI/PaneChrome.swift:420
Placeholders | Empty pane (New terminal), popped out (Show window / Bring back here), scheduled (Run now / Change schedule), starting, exited (Relaunch / Open <KEY> handoff), parked (Use again), not started (Launch <agent> ⌘↩), nothing selected (New terminal) | buttons | OR/UI/PaneChrome.swift:451-524
Placeholders | "Showing in another window" + Show here (one window shows a session at a time) | button | OR/UI/TerminalAreaController.swift:794
Subagents column | Beside the terminal when the Plan panel is closed and the session has subagents (Trace ▸, files touched) | automatic | OR/UI/TerminalAreaController.swift:306; OR/UI/PaneChrome.swift:527
Find | Find bar: live highlight, "n of m", ↑/↓, Return/⇧Return, Esc | ⌘F, ⌘G, ⇧⌘G | OR/UI/TerminalAreaController.swift:761
Links | ⌘-click: local paths (with :line:col dropped) open in the viewer, web links in the browser | ⌘-click | OR/UI/TerminalAreaController.swift:548
Mouse | Plain drag selects even when a TUI captures the mouse; ⌥ sends the mouse to the program | drag | OR/Ghostty/TerminalSurfaceView.swift:180-213
Ctx menu (terminal) | Copy · Paste · Select All · Run in Terminal (selection, to the run terminal) · New Terminal Here · Split Right with New Terminal · Clear; ⌥-right-click goes to the program | right-click | OR/Ghostty/TerminalSurfaceView.swift:223-277
Paste | Image on the clipboard is saved as a PNG (~/Library/Caches/OneRoof/pastes, cleared after 7 days) and its path typed | ⌘V | Core/TerminalMouse.swift:19-80
Drag & drop | Files dropped on a terminal type shell-quoted paths; dropped images are saved and their path typed | drop | OR/Ghostty/TerminalSurfaceView.swift:495-503
Terminal | Command-finished and OSC 9/777 notification hooks; title updates | automatic | OR/Ghostty/GhosttyRuntime.swift:103-171
Run terminal | Right-click › Run in Terminal types into a floating per-agent run shell ("press Return to run", Back to agent button); nothing runs until Return | right-click | OR/AppModel+RunTerminal.swift:4-45; OR/PopOutWindow.swift:39-63

## 15. Centre file tabs, viewer, editor, search
File tabs | Strip "Terminals" + one tab per open file (click, ✕ close; closing the front tab shows its neighbour; only 30 pt tall while a file is open) | click | OR/UI/CentreTabStrip.swift:6-57; Core/CentreTabs.swift
Viewer | Header: Back, kind icon, name, path, Preview/Source switch (Markdown, HTML), Reload, Reveal in Finder, Open in default app, Close tab | buttons | OR/UI/FileViewer.swift:37-62
Viewer | Native Markdown (headings, task lists, tables, code with copy button, images, local and #anchor links) | — | OR/UI/DocumentPages.swift:78-357
Viewer | HTML in WebKit (relative assets; web links open in the browser) | — | OR/UI/DocumentPages.swift:11
Viewer | Code/text with line numbers (first 2 MB), scroll to a line; images; folder listing (README first); otherwise "Open in its default app" | — | OR/UI/FileViewer.swift:140-194
Editor | NSTextView editor: syntax colours (in-house lexers), gutter with line numbers, agent attribution bar, click for breakpoint dots, problem lines, dirty dot | — | OR/UI/EditorView.swift:280-520
Editor | File claim banner ("<agent> has claimed this file"), save queued until the step ends, "· Take over" (interrupts the agent and asks it to pause) | button | OR/UI/EditorView.swift:181-226
Editor | Run / Debug in a dock of real terminals (runs, agent sessions in this repo, shell); pdb breakpoints typed at start; ⌃` hide | ⌘R / ⇧⌘R / ⌃` | OR/UI/EditorView.swift:235-258, :526-570
Editor | Inspector tabs: Outline (jump to a symbol) · Problems n (ruff/swiftlint/tsc; Quick fix; Ask agent ⌘I) · Git (last 12 commits) · Plan (the claiming session), plus "On this file" | tabs | OR/UI/EditorView.swift:584-720
Editor | Ask Agent sheet: pick a session, question, Send ⌘↩ (file and lines attached) | ⌘I with a selection | OR/UI/EditorView.swift:727-760
Search | Search in Workspace: query, Workspace / This repo, Aa match case, results by file, click opens at the line | ⇧⌘S | OR/UI/SearchView.swift:7-95

## 16. Files panel
Files | Lazy tree of the selected session's repo (the open file's repo in the Editor) with git badges; header shows repo + branch | — | OR/UI/FileBrowserView.swift:23-50
Files | Header context menu: Show/Hide Hidden Files · Open in Finder · Refresh | right-click header | OR/UI/FileBrowserView.swift:41-45
Files | Node: single click opens a file or expands a folder; double-click opens | click | OR/UI/FileBrowserView.swift:148-149
Files | Node context menu: Open · Open in Default App · Reveal in Finder · Copy Path · Type Path into Terminal · Attach to Agent Message (@path) · New Terminal Here (folders) | right-click | OR/UI/FileBrowserView.swift:150-164
Files | Drag a file out (as a file URL) | drag | OR/UI/FileBrowserView.swift:166
Files | Footer: "Changes N", +/− counts, "Review changes ⌥⌘R" button | button | OR/UI/FileBrowserView.swift:55-75

## 17. Plan panel (right)
Plan | No selection: window name, counts, help text, last error | — | OR/UI/PlanPanelView.swift:32
Plan | Per-panel theme block: Sessions · Files · Terminal · This panel · Centre | menus | OR/UI/PlanPanelView.swift:45-71
Plan | Tabs Plan · Ticket · Notes · Artifacts N · Resources (remembered per session; labels shrink to icons when narrow) | tabs | OR/UI/PlanPanelView.swift:76, :153-221
Plan tab | Status pill, Launch/Relaunch/Stop, ••• popover, editable name, facts (agent, repo, start folder + "one memory", roofd id, title, launched, source), Step review, ticket boxes, Project field + "Linear ▾" picker, Objective · done when, Plan steps, Stickers (+ New), Related in Learn + "More: how do I…" | fields / buttons | OR/UI/PlanPanelView.swift:225-385
Step review | On/off switch (one Claude call per step), Latest, re-read ↻ | toggle / button | OR/UI/PaneChrome.swift:608-660
Ticket tab | Ticket boxes (Backlog / In Progress / In Review / Done; becomes a "Move to" menu when narrow; Linear ↗; ✕ detach; quality-bar warning) | buttons | OR/UI/PlanPanelView.swift:583-683
Ticket tab | "Not attached, but this session works on:" issues found in its text and terminal, each with Attach | button | OR/UI/PlanPanelView.swift:417-453
Ticket tab | Attach issue… / Add issue…; Opening message editor; Agent arguments | fields | OR/UI/PlanPanelView.swift:398-410
Notes tab | Notes editor, Save ⌘S, "Unsaved changes" / "Saved hh:mm" | ⌘S | OR/UI/PlanPanelView.swift:457-471
Artifacts tab | Written files · plan · handoffs · screenshots, click opens in the viewer (refreshed every 10 s) | click | OR/UI/PlanPanelView.swift:487-516
Resources tab | Session memory/CPU now, 10-minute sparklines, watchdog headroom, process list | — | OR/UI/ResourcesView.swift:376-441
Plan | Edits merge with outside changes; Save writes only changed fields | — | OR/UI/PlanPanelView.swift:555-578

## 18. Overview (⇧⌘L / ⌃↑)
Overview | Title "All windows" + subtitle counts (windows, sessions, working, finished, queued, on a ticket, subagents running, scheduled tonight) | — | OR/UI/OverviewView.swift:21, :44
Overview | + New work item button; Overview/Subagents segmented control | button | OR/UI/OverviewView.swift:22-25
Overview | 3-column window cards: header (focus window), up to 6 compact rows ranked by status, "+N more", need-you count | click | OR/UI/OverviewView.swift:58-108
Overview | Card rows: click reveals; context menu; drag; subagent branches with tree lines (click opens the trace) | click / right-click / drag | OR/UI/OverviewView.swift:83-95, :412
Overview | Drop a session on a window card to move it there | drop | OR/UI/OverviewView.swift:110
Overview | Resizable rail (drag; double-click resets to 330) | drag | OR/UI/OverviewView.swift:132-146
Overview rail | Tabs: Feed · Agents · Objectives · Projects · Foundations | tabs | OR/UI/OverviewView.swift:154
Overview rail | Feed "What's happening" (newest first, rows reveal the session), Mute ▸ per window | menu | OR/UI/OverviewView.swift:182-194, :352
Overview rail | Objectives list (click opens; + New objective ⇧⌘O) | click | OR/UI/OverviewView.swift:209-225
Overview rail | Projects in play (code, live count, done/total, next ticket; click opens Work) | click | OR/UI/OverviewView.swift:246
Overview rail | Agents: agents at work, seat cards with reset time, Just finished | click | OR/UI/OverviewView.swift:271-323
Overview rail | Foundations results + Open Foundations | button | OR/UI/OverviewView.swift:325-343

## 19. Board (⌘B)
Board | Group: All windows (status) / By agent / By project | segmented | OR/UI/BoardView.swift:30
Board | Status columns: Planned · Next, Working, Needs you, Ready, Idle · Parked, Tonight, Exited (collapsible), Do not use (collapsible) | — | OR/UI/BoardView.swift:84-95
Board | Agent columns with seat gauges; project columns with progress | — | OR/UI/BoardView.swift:56-77, :123
Board | Cards: badge, name, caption, stickers, window name, subagent count, age/planned/tonight; click selects, double-click reveals, context menu, drag | click / drag | OR/UI/BoardView.swift:179-213
Board | Drop rules: onto Planned·Next / Do not use changes the lifecycle; live columns refuse (flash); Tonight opens a time picker (time + Every night + Schedule) | drop | OR/UI/BoardView.swift:217-262
Board | Esc returns to Workspace | Esc | OR/UI/BoardView.swift:46

## 20. Decisions (⌘I) and approvals
Decisions | List of waiting prompts (oldest first) and plans awaiting approval; count; "Earlier today · N decided · N rules learned" | click | OR/UI/DecisionsView.swift:60-115
Decisions | Detail: context line, Open session ⌘↩, headline, command box, Why (in the agent's words), What it touches, Risk card (with rule suggestion), If you say no, Where this sits | — | OR/UI/DecisionsView.swift:125-160
Decisions | Reply field (focused when the agent gave no reason) | type | OR/UI/DecisionsView.swift:164
Decisions | Allow once ↩ · Always allow <pattern> in <repo> · Deny esc · Next decision ⌘] / previous ⌘[ | Return / Esc / ⌘] / ⌘[ | OR/UI/DecisionsView.swift:171-177
Decisions | Undo toast for a learned "always allow" rule | button | OR/UI/DecisionsView.swift:282
Decisions | Plan approval: steps with account/model/cost; Approve plan · Edit plan · Reject | buttons | OR/UI/DecisionsView.swift:233-259
Decisions | Empty state "Nothing waiting." | — | OR/UI/DecisionsView.swift:272
Approvals | Answers are sent as the agent's own keys; One Roof never auto-approves | — | OR/EngineHub.swift:202
Dock badge | Open decisions across windows, else sessions that need you (toggle in Settings) | automatic | OR/AppModel+Engines.swift:76

## 21. Subagents (⇧⌘A)
Subagents | Left: sessions with subagents (running counts); right: timeline trace (├ └ │ depth, minute ticks, tokens) | click | OR/UI/SubagentTraceView.swift:60-160
Subagents | Detail card: Task, Given by, What it was asked (fold/unfold), Status, summary, Files it read or changed (open), "Open the parent session's raw stream ⌘R" | buttons | OR/UI/SubagentTraceView.swift:197-250
Subagents | Context menu "Ask the parent to stop <name>" (no direct kill) | right-click | OR/UI/SubagentTraceView.swift:149
Subagents | Claude subagents are exact; Codex/Kimi/Gemini are marked "inferred" | — | Core/Subagents.swift

## 22. Work (⇧⌘W) and Linear integration
Work | Project list with filter, Show shipped, Reload from Linear, Back to terminals, New item (⌘⇧N), "Connect Linear…" when there is no key | buttons | OR/UI/WorkView.swift:48-72
Work | Project detail: code, state, title, done/total, New item here, Tracker pane, Docs, refresh, Sessions list, tickets by phase, Show done | buttons | OR/UI/WorkView.swift:141-237
Work | Ticket row: open its session, state menu (moves it in Linear), Plan a session (▶), Open in Linear | buttons | OR/UI/WorkView.swift:254-274
Intake sheet | New work item: title, details, "needs several sessions", kind picker (workstream/deliverable/defect/spike/decision/chore/session), project, phase, duplicate warning + "Plan a session for it", "Plan a session for it now" | sheet | OR/UI/WorkView.swift:290-368; Core/Linear.swift:363
Attach Issue sheet | Pick a project, pick an issue or New <type>…, title, "Tell the agent now", Attach ⌘↩ / Create and attach | sheet | OR/UI/AttachIssueSheet.swift:44-89
Issue picker | Floating checklist: refresh, filter, state chips, "Not ready N" (quality bar), sortable columns # · Key · Title · State · Created · Updated, Default order, detail pane with Add/Remove, New <type> links, Clear, Done | panel | OR/UI/IssuePickerPanel.swift:56-271
Linear | Issue quality bar per type (missing-field line, tooltip) | — | Core/IssueQuality.swift
Linear | Close session → comment and move each issue to In Review (per-issue tick boxes) | close dialog | OR/UI/SessionPopover.swift:146
Linear | Commit watch: a commit naming an issue key moves it to In Review once | automatic, every 60 s | OR/AppModel+Work.swift:259; Core/CommitWatch.swift
Linear | Agents request issue comment/state through `roofd issue`; applied with the owner's key | automatic, every 3 s | OR/AppModel+Work.swift:306; Core/IssueUpdates.swift
Linear | Pending messages delivered once the agent is at its prompt | automatic | OR/AppModel+Work.swift:290
Linear | Create a project with milestones; create tickets by Type label | sheet | OR/AppModel+Work.swift:87-134
CLI | --check, --linear, --linear-roundtrip <TEAM>, --route "<task>" | command line | OR/main.swift:7-58

## 23. New session sheet (⌘N)
New session | Team / Project / Issue pickers (when Linear is connected); "New project…", new issue kinds | menus | OR/UI/NewSessionSheet.swift:73-80, :279-345
New session | "What should happen" field | type | OR/UI/NewSessionSheet.swift:86
New session | Image attachments by paste (⌘V) or drop, with thumbnails and remove | paste / drop | OR/UI/NewSessionSheet.swift:169, :456-492
New session | Similar-ticket banner "Plan a session for KEY instead" | button | OR/UI/NewSessionSheet.swift:552
New session | Project fields for a new project (code, milestones) | fields | OR/UI/NewSessionSheet.swift:422-428
New session | Agent cards (Claude1, Claude2, Codex, Kimi, Gemini, Antigravity, Shell) with seat gauges; router suggestion with reason + "Use it" | click | OR/UI/NewSessionSheet.swift:101-113, :607-614
New session | Model menu (CLI default + suggested), Repo menu, Start in (~/Projects one memory vs repo folder ⚠), Project code (no Linear) | menus | OR/UI/NewSessionSheet.swift:116-125, :641-664
New session | Done when (optional), Opening message (auto-built until you edit it) | text | OR/UI/NewSessionSheet.swift:131-146
New session | Advanced: agent arguments, Role, Resume a Claude conversation (warns if active), Own git worktree (disabled, "not connected") | disclosure | OR/UI/NewSessionSheet.swift:676-713
New session | When: Now · Next · Tonight 2 AM / Nightly ▾ · Every N ▾ · On demand | segmented | OR/UI/NewSessionSheet.swift:723-751
New session | Cancel (Esc) · Save as planned · primary (Launch ⌘↩ / Create issue, launch / Create project, launch / Plan the project) | buttons | OR/UI/NewSessionSheet.swift:221-225, :757

## 24. Objectives
New objective sheet | Objective, Done when, Repo, Project, Urgency (Today/This week/Whenever), Budget (Light/Normal/Whatever it takes), Notes; Cancel · Save as draft · Plan it | ⇧⌘O | OR/UI/ObjectiveView.swift:6-40
Objective view | Plan it, Watch the planner, Check for the plan now, open the plan file, Re-plan, Reload plan from file, Delete objective, close | buttons | OR/UI/ObjectiveView.swift:79-116
Objective view | Approve and run / Resume, Pause, "Steps run without asking" toggle, Route all steps | buttons | OR/UI/ObjectiveView.swift:138-157
Step card | Agent/account/model pickers, Suggest (router), Open session, move up/down, delete, expand | buttons | OR/UI/ObjectiveView.swift:206-266
Objectives | Seat rotation: a step that hits its limit writes a handoff and is re-routed (max 2 rotations) | automatic | docs/help/07_seats-router-and-on-device-model.md:70

## 25. Loops and schedules
Loops | List (pinned first; state dot, last-check health strip, repo); Resume all / ⏸ Pause all / + New loop; templates when empty (Fix until green, Nightly tidy) | buttons | OR/UI/LoopsView.swift:99-200; Core/Loops.swift:510-518
Loops | Detail: Goal, Check, Agent, Repo, Worktree/branch, Limits, Gates; Run now · Resume · Pause · Stop · Edit · Pin/Unpin · Delete (confirm); rounds with Open ↗ and expandable log | buttons | OR/UI/LoopsView.swift:282-424, :142
Loops | Editor: template, Name, Goal, Repo (fixed once created), Agent + model, Check + "Test the check", Until done / Nightly, max rounds, max duration, same-failure stop, check timeout, wait between rounds, nightly time, extra round prompt, Pinned; Cancel · Save · Save and run | sheet | OR/UI/LoopsView.swift:445-600
Loops | Palette "New loop"; roofd runs loops, never push/merge/deploy | palette | OR/AppDelegate.swift:305
Schedules | Tonight / Nightly / On demand (Session menu, Board Tonight drop, sheet When); roofd fires them when "Allow scheduled runs" is on, otherwise the app ticks every 30 s and reports "missed · run now?" | menus | OR/AppModel+Engines.swift:90-140, :231; OR/AppModel.swift:239
Repeat | Repeat every N minutes (resends the message while the agent waits) | context menu / sheet | OR/AppModel+Engines.swift:96

## 26. Resources (⇧⌘U)
Resources | Subtitle with One Roof's total footprint, CPU, process count; leftovers note | — | OR/UI/ResourcesView.swift:53
Resources | Sort: Heaviest / Name | segmented | OR/UI/ResourcesView.swift:28
Resources | Summary tiles with 10-minute sparklines, Mac memory meter, swap and pressure | — | OR/UI/ResourcesView.swift:90-110, :289-340
Resources | One Roof's own processes (app + helpers, roofd daemon: pid, uptime, CPU, memory) | — | OR/UI/ResourcesView.swift:135
Resources | Sessions by window with headroom bar against the roofd memory guard (warn 1 GB, end 2 GB); click reveals | click | OR/UI/ResourcesView.swift:226, :342; Core/MemoryWatchdog.swift
Resources | This Mac, by app: apps heaviest first, expand to processes (Chrome/Electron helper kinds), Quit / Force quit, End / Force end (confirm), Show all, leftover One Roof processes with Stop | buttons | OR/UI/MacAppsView.swift:10-250
Resources | Browser open tabs by site over Apple Events ("Show tab names", Refresh, click a tab to bring it forward, Open Automation settings) | buttons | OR/UI/MacAppsView.swift:305-410

## 27. Learn (⇧⌘E) and How do I (⌥⌘/)
Learn | Sidebar: search "How do I…? or search N pages", Best matches, sections (Course, Agentic Engineering cards by track, Skills, One Roof Help, extra Learn folders), Back to terminals | type / click | OR/UI/LearnView.swift:89-120, :150-224
Learn | Page: title/section, Play/Continue part n, "Use in a session ▸" (sends /skill to a live agent), Open in browser | buttons | OR/UI/LearnView.swift:25-42
Learn | Renders Markdown natively, HTML cards in WebKit (animated explainer cards), narration folders as track lists | — | OR/UI/LearnView.swift:46-48
Learn | Exclusions: career-agent pages hidden, unsearchable, links removed, opening refused | automatic | Core/LearnMatch.swift:59-93
Player | Player bar: open page, Part n of m, previous / play-pause / next, scrubber, speed 0.75–2×, queue popover, stop; resumes where each page left off; keeps playing in other views | buttons | OR/CoursePlayer.swift:17, :131-200
Player | Mini player in the toolbar | buttons | OR/CoursePlayer.swift:205
How do I | Question opens Learn and selects the best page (menu, palette, Plan panel "More: how do I…") | ⌥⌘/ | OR/UI/LearnView.swift:70; OR/AppModel.swift:382
Learn folders | Add/remove extra folders (Markdown, .mp3 narration folders) | Settings › Foundations | OR/UI/SettingsView.swift:236-255

## 28. Command palette (⌘K / ⌘P)
Palette | Fuzzy search; ↑/↓ move, Return run, Esc close | ⌘K | OR/UI/CommandPalette.swift:5-53
Palette | Views: Workspace, Overview, Resources, Decisions, Subagents, Loops, Board, Work, Learn, Foundations, Settings, How do I | type | OR/AppDelegate.swift:299-342
Palette | Actions: New loop, New workspace window, Plan a session, New terminal, New objective, New work item, Find in terminal, panel toggles, Review changes, Search, Split right/down, Reopen closed, Close/Maximize/Even out panes, Focus, Run startup check, Remove exited, Open <session> in new window | type | OR/AppDelegate.swift:305-341
Palette | Windows, open decisions, Roof windows, "Theme: all panels X", every session, objectives, open projects, up to 4,000 git-tracked files of the selected repo, skills | type | OR/AppDelegate.swift:310-377

## 29. Settings (⌘,) — tabs General 0, Appearance 1, Agents 2, Foundations 3, Shortcuts 4, Captions 5
General | Start folder (read-only) | — | OR/UI/SettingsView.swift:28
General | Show sessions that need you on the Dock icon | toggle | :33
General | Check the foundations every time One Roof starts | toggle | :35
General | Sessions runtime status | — | :38
General | Notify when an agent needs me / finishes its turn / a long command finishes; "Long means at least N s" (5–3600, step 5) | toggles + stepper | :47-51
General | macOS permission: Allow notifications… / Open Notification Settings… | buttons | :63-67
Appearance | Theme grid: Sessions · Files · Terminal · Plan · Centre views × 7 themes | click | :85-97, :125
Appearance | Follow macOS light and dark | toggle | :100
Appearance | Text size slider 85–130% (front window) | slider | :102-107
Appearance | Fill rows with their colour | toggle | :109
Appearance | Sticker style Bold / Soft | picker | :111
Agents | Per agent: Account picker (Codex shows one seat), Model (CLI default + suggestions), Extra arguments | fields | :157-170, :320
Captions | Use the on-device model for captions and reasons | toggle | :141
Captions | Step review: Claude reads each finished step | toggle | :144
Captions | Allow scheduled runs (Tonight, Nightly) | toggle | :147
Captions | Menu-bar extra | toggle | :150
Foundations | Projects folder (Choose…/Show; ONEROOF_PROJECTS overrides) | field | :190
Foundations | Shared rules and docs (optional; ONEROOF_SHARED) | field | :192
Foundations | Agentic engineering (bundled; ONEROOF_AE_PATH dev override, shown when set) | row | :292
Foundations | Learn folders (Add…/Remove) | list | :236-255
Foundations | On-device model path (Choose…) + model download row | field | :264-286; OR/UI/ModelDownloadRow.swift
Foundations | Claude memory path (Show) | row | :198
Shortcuts | See §8 | — | OR/UI/ShortcutsSettings.swift

## 30. Foundations window (⇧⌘F) and Setup
Foundations | Check tab: results ✓ ! ✕, checked-at time, Run again, Fix (runs in a One Roof terminal), model download row | buttons | OR/UI/FoundationsView.swift:39-80
Foundations | Skills tab: search, linked-into-home badges, insert /skill into the selected session (not sent), open SKILL.md, open in Learn | buttons | OR/UI/FoundationsView.swift:91-140
Foundations | Hooks & rules tab: rules every agent reads, Claude hooks (script present/missing) | links | OR/UI/FoundationsView.swift:163-199
Foundations | Memory tab: latest handoff per project (Resume plans a Claude session, open), recent gotchas | buttons | OR/UI/FoundationsView.swift:205-235
Launch guard | Red foundations ask before a launch: Fix and launch · Open Foundations · Launch anyway · Cancel | alert | OR/AppModel.swift:536-550
Setup | Projects folder, Shared folder (Use one / Create it / Skip), Agentic engineering (bundled), Required tools (git), Agents on this Mac, Linear API key (SecureField), Start | window | OR/UI/SetupView.swift:33-128

## 31. Workspaces, windows, pop-outs, roof windows
Workspaces | One main window per workspace; all restore at launch; closing remembers it as closed (sessions keep running in roofd); reopen from Window › Workspaces | menus | OR/AppDelegate.swift:39; OR/MainWindowController.swift:189-208
Workspaces | New workspace window sheet: name, colour swatches, Create window; optional session to move in | ⇧⌘N | OR/UI/NewWorkspaceSheet.swift:5-35
Workspaces | Per-window state: selection, centre view, viewer, filter, chips, text scale, pane layout | — | OR/WindowState.swift:36-64
Workspaces | Move a session between windows (menu, context menu, Overview drop) | various | OR/AppModel+Windows.swift:103
Pop-out | Session in its own window; main pane shows "Open in its own window" with Show window / Bring back here; retries if the attach is refused | ⌥⌘O | OR/PopOutWindow.swift:84-175
Roof window | Every live session of a repo or workstream in a grid; new ones join; per-pane header with zoom and ✕ (hands back to main); "Attaching…"; empty state | Window › Roof Windows, ⌥⌘N, context menu, palette | OR/RoofWindow.swift:6-170
Links | oneroof:// session/<id or name>, objective/<id>, view/<terminals or launchpad or board or work or learn or review or search>[?q=], open?path=&line=, new?agent=&repo=&name=&message= (plans only, never launches) | URL | Core/RoofLink.swift:3-48; OR/AppModel.swift:634
iPad / handoff | No "Move to iPad", Continuity or Handoff code exists in this version. "Handoff" here means agent handoff files only (Send Handoff, Open KEY handoff, Memory tab Resume) | — | (none found)

## 32. Menu bar extra, notifications, roofd, memory guard
Menu bar | "● n ▶ m" (need you / working); popover: Needs you with Allow / Open, Working, Tonight, Open One Roof | click status item | OR/StatusItemController.swift:1-100
Notifications | Needs you, finished turn, long command (exit code), program OSC 9/777; none for the session in focus; replaced, not stacked; rate-limited; click opens the session | automatic | OR/Notifier.swift:5-188; Core/Notifications.swift:8-96
roofd | Background launchd item (SMAppService): registered at start and again after a rebuild; owner re-checked every 30 s; Foundations row + Login Items link | automatic | OR/RoofdService.swift:5-128; OR/AppModel.swift:227
roofd | Footer status and "older than app" note | — | OR/UI/SessionsPanel.swift:222-228
Memory guard | roofd holders/daemon warn at 1 GB and stop at 2 GB (env `<prefix>_MEM_WARN_MB` / `_MEM_LIMIT_MB`); shown in Resources | automatic | Core/MemoryWatchdog.swift:4-65
App Nap | Disabled so background watching keeps running | automatic | OR/AppDelegate.swift:27
Seats | Usage from Claude status line and Codex logs every 30 s; Kimi/Antigravity count sessions only | automatic | OR/AppModel.swift:588
Captions/feed | Caption engine (deterministic, optional on-device Qwen model), FYI feed (200 in memory), decisions engine | automatic | OR/EngineHub.swift; Core/Captions.swift; Core/Feed.swift
Router | Agent/account/model suggestions from rules + seat capacity | sheet / objective | OR/AppModel.swift:596-602; Core/Router.swift
Unread | Ready = finished a turn you haven't seen; unread dot | — | OR/AppModel.swift:424
Reopen closed | Restores the last closed or removed session | ⇧⌘T | OR/AppModel.swift:440
Adoption | Agents started outside One Roof are adopted as rows (no delete) | automatic | Core/Board.swift:63
Migration | One-time preference move from the old domain | automatic | Core/LegacyMigration.swift:3

## 33. Self-test and developer env hooks (`ONEROOF_SELFTEST_*` turns on self-test mode: no autosave, windows stay behind, no global hotkey, no notifications)
SelfTest | SCRIPT=<file> (steps: wait, terminal, type, send, plan, select, rename, steps, checktop, launch, close, delete, reopen, interrupt, popout, roof, centre, menu, answer, group, chip, newsession, keys, probe, snap, copytest, dump, screen, quit) | env | OR/SelfTestScript.swift:5-130
SelfTest | SELECT, TYPE, WAIT, LAUNCH, MENU=<Menu>/<Item>, OUT, QUIT, COPYTEST | env | OR/SelfTest.swift:224-250
SelfTest | CENTRE=<view>, CENTRE_AFTER, TEXTSIZE, THEMES (1/3/4/5 values), GROUP, STICKERS=soft, DEMO=1 | env | OR/SelfTest.swift:33-40, :199-209, :239
SelfTest | FOUNDATIONS, FOUNDATIONS_TAB, SETTINGS, SETTINGS_TAB, WORK[=WS id], TICKET=WS/KEY, OBJECTIVE="title|done|repo|ws", APPROVE, INTAKE, LAUNCHPAD, FILES, LEARN[=page], VIEW=<path> + LINE, NOCENTRE | env | OR/SelfTest.swift:41-95; OR/AppDelegate.swift:149,163
SelfTest | SPLIT=right,term,down,term,zoom,close,closeagent,reopen; SHORTCUT=<title>=<keys>; LINK; SEARCH; DIFF; PLAY=<page>[@terminals]; HOWDOI | env | OR/SelfTest.swift:97-134
SelfTest | ROOF=<n> + ROOF_REPO + ROOF_BACK; POPOUT; FIND; PALETTE; BOARD; POPOVER; TERMINAL; TERMSTICKER | env | OR/SelfTest.swift:135-192
SelfTest | PLAN="name|agent|account|repo|opening|launch[|model]"; SHEET; KIND; TEAM; PROJECT; PICK; ISSUES; OPENING; WHEN | env | OR/SelfTest.swift:210-222; OR/UI/NewSessionSheet.swift:186-201, :782-784
SelfTest | PLANTAB, RAILTAB, WORKSPACE | env | OR/UI/PlanPanelView.swift:130; OR/UI/OverviewView.swift:18; OR/AppDelegate.swift:35
SelfTest | Snapshot writes .png (all windows), .txt (terminal text), .json (rows, menus with shortcuts/enabled, player, windows) | — | OR/SelfTest.swift:314-349
Dev env | ONEROOF_FRESH_PROFILE / --fresh-profile, ONEROOF_STORE, ONEROOF_PROJECTS, ONEROOF_SHARED, ONEROOF_AE_PATH, ONEROOF_MODEL, ONEROOF_ROOFD, ONEROOF_ROOFD_BIN, ONEROOF_SESSION, ONEROOF_BUNDLE_OUT | env | OR/Prefs.swift:10; OR/AppModel.swift:164; Core/RoofdRuntime.swift:29,247

## Half-built, hidden or likely dead
- "Own git worktree" in the New session sheet's Advanced section is a disabled toggle labelled "not connected" (OR/UI/NewSessionSheet.swift:712).
- The Editor's "Split editor ⌘\" label is text only. No ⌘\ binding or split-editor code exists (OR/UI/EditorView.swift:175).
- The `DiffView` code-review panel (per-hunk Comment/Revert, refresh every 3 s) looks unreachable: diff paths now route to the Review changes view (OR/UI/DiffView.swift; OR/AppModel+Windows.swift:53).
- `toggleMute(session:)` exists but no UI calls it. Only per-window Mute is exposed (OR/AppModel+Engines.swift:185).
- Blueprint is a hidden terminal-only theme. The Paper theme is retired and mapped to Daylight (Core/Theme.swift:4-19).
- The hidden duplicate menu items (⌘P palette, ⌥⌘T reopen, ⌥⌘1–9 workspaces) exist only for their key equivalents.
- Hint-strip text ("⌃↩ run as shell · @ file · / skill") only describes the agent CLI's own behaviour; One Roof doesn't implement it.
- The Loops view is in the View menu and palette but not in the toolbar switcher. Subagents and Objective have no switcher tab either.
- No Move to iPad, Continuity, Learn "posts" or "radio" features exist in this build. Learn "cards" are the Agentic Engineering HTML explainer cards.
- The status-item comment says notifications "need a signed build and are not sent from this one". Notifier works only in a real app bundle and never during a self-test (OR/StatusItemController.swift:3; OR/Notifier.swift:21).
- Debug only feeds breakpoints for pdb, and Quick fix only exists for some ruff/swiftlint/tsc problems (OR/UI/EditorView.swift:242, :663).
- Writes to APIs that aren't wired yet are meant to show "not connected" and do nothing (app/CLAUDE.md §6). The worktree toggle is the only such control found.