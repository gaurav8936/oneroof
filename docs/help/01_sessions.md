# One Roof help: sessions

**Status:** LIVE · **Date:** 2026-10-20

> **One line:** the sessions panel on the left shows every agent and terminal in this window with its live state, agent, account, repo and stickers; this page explains every part of it, the session menu, the plan panel and pop-out windows.

![The sessions panel grouped by status, with the plan panel for the selected session](img/sessions.png)

## Goal

You should be able to look at the left panel and know, without clicking, which agent needs you, which finished, which is still working and what each one is for. You never need to type prefixes like `WIP:` into a name: states come from the agents themselves (roofd), and labels are stickers.

## The states

| State | Where it comes from | What it means for you |
|---|---|---|
| Needs you | roofd (a prompt is waiting) | It is waiting on a question or a permission prompt. Answer in its terminal, or in Decisions (⌘I). Counted on the Dock badge. |
| Ready | roofd | It finished a turn you have not looked at yet. |
| Working | roofd | It is working right now. |
| Idle | roofd | At its prompt, nothing new. |
| Next | One Roof | Planned and up next (When › Next, Mark as Next, or the Next sticker). |
| Planned | One Roof | Written ahead of time, not started. |
| Exited | One Roof | It was launched, and roofd no longer has it. Relaunch brings it back. |
| Parked (Do not use) | One Roof | Put aside by you. The name is struck through. |

Grouped by status, the panel lists them in that order (needs you first). Pinned sessions always sit in a Pinned group on top.

## Where sessions live (roofd)

Every session runs in **roofd**, One Roof's own session manager, which ships inside the app and runs in the background (macOS lists it under Login Items). One Roof draws the terminals; roofd keeps the programs.

| When | Your sessions |
|---|---|
| You quit, update or reopen One Roof | keep running; each terminal comes back with its screen and history |
| One session's process crashes | only that session ends (Exited, with Relaunch) |
| The Mac sleeps | keep running |
| You log out or restart the Mac | end; their rows stay, with Relaunch (Claude and Codex can resume the conversation) |

- **History:** each session keeps 8 MB of scrollback in memory. It is never written to disk, because agents print keys and file contents.
- **Status:** roofd reads each agent's screen (permission prompts, menus, spinners) and, for Claude, its hooks, so Working, Needs you and Done stay right even with One Roof closed.
- **Tonight and Nightly** run with One Roof closed when Settings › Allow scheduled runs is on; roofd sends the opening message once the agent is ready.
- **Copy attach** gives `roofd attach <id>`: paste it into any terminal to see the same session there.

## Workspace windows

Each main window is a **workspace** with its own sessions. File › New Workspace Window… (⇧⌘N) opens another one; Window › Workspaces (⌥⌘1 to ⌥⌘9) switches between them; right-click a row › Move to Window moves a session. Closing a workspace window keeps its sessions. Overview, Board and Decisions show every window. Agents you start by typing their name in a One Roof terminal show that agent in their row; agents started in other terminal apps are not listed (Copy attach opens a One Roof session from any terminal). Rows started outside One Roof.

## The top of the panel

- **Seat bars:** how much of each seat's usage window is used (Claude1, Claude2, Codex). They stay empty when there is no usage data. See [Seats and routing](07_seats-router-and-on-device-model.md).
- **Count chips:** all, need you, working, ready (finished, not yet looked at), idle, exited (agent sessions whose agent has ended; terminals are not counted). Click one to show only that state; click **all** (or the same chip again) to get the full list back. Under **exited**, *Remove all exited sessions* clears them. Next and planned sessions are under all.
- **Group ▾:** Status, Repo, Project, Agent, Account or Folder (also View › Group by, ⌘1 to ⌘6).
  - **Repo** is the git repo a session works in. Sessions start at the workspace root, which is not a repo, so One Roof learns the repo as the agent works: from the files Claude's tools touch and the folders its commands `cd` into, or from a terminal's current folder. It keeps the last one after the session ends. Until then the session is under **Workspace root · no repo yet** (last). Codex, Kimi, Gemini and Antigravity have no hooks, so they show their repo only when started in one.
  - **Folder** is the top-level folder under the workspace (one per product or area), for a coarser view.
- **Filter:** type to narrow the list; ✕ clears it.

## A session row

- **Agent logo** on the left, always the same for an agent (your emoji never replaces it), with a small **status dot**.
- **Pin**, the **unread dot** (new since you last looked, see [Review, split panes and session rows](10_review-split-panes-and-session-rows.md)), your **emoji** if you picked one, and the **name**. Double-click the name to rename it; Return saves, Esc cancels.
- **Second line:** the account (Claude1, Claude2) or the agent name, the repo, the time since it was last active, and a status pill when the list is not grouped by status.
- **Caption:** one line on what the session is doing right now, read from its terminal.
- **Third line:** the **branch and uncommitted change** chip (`⎇ main +34 −5`), **stickers**, the **Linear ticket** key and the **project** code.
- **Colour:** a row colour fills the whole row (Settings › Appearance › Fill rows with their colour).
- **Click** selects the session and shows its terminal. ⌘] and ⌘[ move to the next and previous row.

## The session menu

![The session menu: action tiles, stickers, colour and emoji](img/session-menu.png)

**Right-click a row** for the quick menu: Launch or Relaunch, Mark as Next / Mark as Planned, Do Not Use / Use Again, Pin / Unpin, every sticker as a tick box, Colour, **Emoji and New Sticker…**, Move to Window, Open in New Window, Roof Window for the repo, Review Changes, Terminal Here, Copy Link to Session, Close Agent… (running) and Delete.

**••• on hover** opens the larger menu:

- **Action tiles:** Launch or Relaunch (not running) or Focus (running), Next / Not next, Pin / Unpin, Rename, Do not use / Use again, and Close (running: ends the agent, after asking) or Delete (not running).
- **Stickers:** Next, WIP, Important, Blocked, Review, Idea, Bug, Research, Shipped, Do not use, or a word of your own (it keeps the same colour every time).
- **Colour** and **emoji** pickers.
- **Links:** Open repo (Finder), Terminal here (a plain shell in the repo), Copy folder, New window, Roof window for the repo, and Copy attach (the `roofd attach …` command, to open the same agent from any terminal).

Settings › Appearance switches stickers between Bold and Soft.

## The Session menu in the menu bar

Launch, Mark as Next, Mark as Planned, Do Not Use, Pin, Rename…, Move to Window, Schedule (Tonight 2:00 AM, Nightly at 2:00 AM, On Demand), Run Now, Interrupt (⌘.), Send Handoff, Open in New Window, Open Repo in Finder, Copy session id, Copy Working Directory, Copy Attach Command, Copy Link to Session, Close Agent…, Delete Session, Remove Exited Sessions…, Next Session (⌘]) and Previous Session (⌘[). Items that do not apply to the selected row are greyed out.

- **Close Agent** asks first. If the session has a ticket, a box (on by default) also comments a summary on the ticket and moves it to In Review. The conversation stays on disk and can be resumed later.
- **Delete Session** removes the row (and its notes and stickers). Sessions started outside One Roof cannot be deleted; they disappear when their agent ends.
- **Remove Exited Sessions** clears every exited row at once, except pinned ones.
- **Reopen Closed Session** (File menu, ⇧⌘T) brings back the last one you closed or deleted and launches it again.

## The plan panel (right, ⌥⌘P)

With a session selected it has four tabs:

- **Plan:** the state with **Launch** / **Relaunch**, the name, the **Project**, **Objective · done when**, the plan steps when the session belongs to an objective, **Stickers**, **Related in Learn**, the **Opening message** (sent when the agent is ready), **Agent arguments** and the **Start folder**. **Save** (⌘S) keeps your edits; they are also saved when you select another row.
- **Ticket:** the linked Linear ticket with its live state and buttons, or how to link one.
- **Notes:** your own notes for this session.
- **Artifacts:** plan files, handoffs and screenshots for this session.

With nothing selected it shows today's counts and a short how-to. The **Appearance** box at the bottom sets the theme of each panel ([Themes and layout](08_themes-layout-viewer-and-find.md)).

## A session in its own window

Session › Open in New Window (⌥⌘O), or New window in the session menu, moves a running session's terminal into its own window. The centre then says "Open in its own window" with **Show window** and **Bring back here**.

## The footer

The bottom of the panel shows the startup check: a count of foundations issues, or "Checking…". Click it to open Foundations. If One Roof cannot reach roofd, see [Foundations](06_foundations.md).
