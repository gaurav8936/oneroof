# One Roof help: Overview, Board, Decisions, command palette and keyboard shortcuts

**Status:** LIVE · **Date:** 2026-10-20

> **One line:** the Overview is one page of all your work, the Board is a Kanban of every session, Decisions lists every agent waiting on you, the command palette (⌘K) finds anything, and the table at the end lists every keyboard shortcut in One Roof.

## Overview (⇧⌘L)

![The Overview: every window and its sessions on the left, the feed on the right](img/overview.png)

One page that answers "what needs me, and what is going on?" across every window. Open it with **⇧⌘L** (View › Overview), **Overview** in the toolbar, or Window › All Windows (⌃↑, if macOS Mission Control does not already use that key).

- **Windows:** one card per workspace window with its sessions and how many need you.
- **What's happening:** a feed of what agents in all windows did, newest at the top. Each row reads like a table row: what happened (Finished, Step done, Error…), which agent, **Needs you** when that session is waiting on you now, and the time (with the day when it is not today); then what was done; then the window and session on one line. Click a row to open the session. The same event repeated by one session (for example "finished" every few minutes while it rests) shows once, at its newest time. Drag the edge between the window cards and the feed to make it wider or narrower; double-click the edge to reset it.
- **Objectives:** open objectives with their progress, or "Plan ready" when a plan waits for approval; **+ New objective**.
- **Agents at work:** live sessions per account (Claude1, Claude2, Kimi…), each session on its own row, and under it the subagents it is running now (for example two lanes a Claude session started with its Agent tool). Click a subagent to open its trace.
- **Seats:** Claude1, Claude2 and Codex use of the 5-hour and 7-day windows, with reset times, when usage data exists ([Seats and routing](07_seats-router-and-on-device-model.md)). Kimi and Antigravity publish no usage, so One Roof counts their sessions.
- **Just finished:** results you have not looked at yet.
- **Foundations:** the startup check in one line; **Open Foundations** when something is wrong.
- **+ New work item** at the top, and **Overview · Subagents** to switch to the subagent trace. Board and Decisions are their own tabs in the toolbar (⌘B, ⌘I).

## Board (⌘B)

![The Board](img/board.png)

A Kanban of every session in every window, left to right: **Planned · Next → Working → Needs you → Ready → Idle · Parked → Tonight → Exited → Do not use**. Drag a card onto Planned · Next, Tonight or Do not use to change it; the other columns follow the agents' live state. The Tonight column has **Schedule** with a time and an **Every night** switch. Exited and Do not use can be collapsed. Double-click a card to open that session. **By project** groups the cards by their Linear project. ⌘B again closes the Board.

## Inbox (⌘I)

The Inbox (it was called Needs you until 2.0) is one column of dark, terminal-style blocks: one per session that needs you, **newest at the top**. Sessions with nothing for you are not shown; the header counts them ("5 other sessions working ›" opens Sessions). The header also says how many things wait ("3 things waiting for your attention") and, pinned on the right, **Action log · 555 decided today · 74 rules ›**: click it for the Action log on Decisions, or click "74 rules" for its Rules tab (also View › Action Log and Search; under 1100 pt it reads "Action log ›"). Each block shows only the current ask and is answered in place, without opening the terminal:

- **A permission prompt**: the agent's words as its terminal shows them, the risk ("Same command you allowed 3 times this week"), **Details ▸** (why, in the agent's words; what it touches; if you say no; where it sits), then **one button per option the prompt shows**, in its order and words (Antigravity's four, Codex's three, …). Each presses that option's own key, exactly as if you had typed it in the terminal; the first is Return. An option that takes your words ("No, and tell Claude what to do differently") sends what is in the reply box. When the options cannot be read, **Allow once**, **Always allow this** and **Deny** stand in. Picking an "always" option is remembered as a rule for that command in that repo, with **Undo** for 5 seconds.
- **A question menu** (Claude's question tool, Gemini's sign-in menu): the question as the agent drew it and its own answers; **Cancel** (Esc). If Gemini says Google refuses the sign-in, the block says so and points to an API key or Antigravity.
- **A question at the end of a turn**: what it asked, and a reply box.
- **A finished turn** (*Finished · waiting for you*): what the agent said last (12 lines, then **Show all**), a reply box (its next message), **Set aside** (it leaves the Inbox; the session stays open) and **Close session**.
- **Plans** waiting for your approval: the steps, Done when, **Approve plan · Edit plan · Reject**.
- **Loops · Today**: loop items (a loop that stopped, a round that asks, what loops staged for you), with their own buttons.
- **Decided · N ▸**: what you answered whose session is still alive, newest first. Click to open it.

**The reply box** takes several lines (↩ sends, ⇧↩ new line). Paste an image (⌘V), drop image files on the block, or click the paperclip: each shows as a thumbnail you can remove (up to 6, 20 MB each), and the agent gets their paths in your message to read. **Open session ↗** (⌘↩) opens the session's terminal. If the session cannot be reached, the block says so in red and keeps your text and images.

After you answer, the block shows what you chose for a moment and folds away; the next one takes the focus. Nothing covers the terminal: you can always answer an agent in its own terminal instead, and its block folds with "Answered in its terminal". OpenCode's allow options can only be picked in its terminal; its Reject works here. The rail, the Dock and the menu bar show how many are waiting; the rail icon fills when something waits.

## Action log (Inbox › Action log)

What you decided, and the always-allow rules One Roof notes, in two tabs (⌘1 / ⌘2). ‹ Inbox, ⌘[ or Esc goes back. (LAB-2047, LAB-2048)

- **Decisions · N**: one list, newest first, every row with the date and time, the session (a closed one reads "<name> (closed)"), what was asked and what you chose (✓ allowed, ✕ denied, ↩ replied or chose). **Search** (⌘F) matches the ask, the command, your answer and reply and the session's name; **Date** (Last 7 days by default, up to Custom…), **Session** and **Answer** (Allowed once, Always allowed, Denied, Replied, Chose an option, Answered in the terminal, Set aside) filter it, with chips and Clear all. Click a row, or ↑ ↓ and Return, to open it: the session (with **Open session ↗** while it runs), the full ask with its command and screen, **the options it showed with the one you chose marked**, why, what it touches, the risk, and your answer. ↑ Newer / ↓ Older step through the list. Asks from before 2.0.0 say their options weren't recorded. Decisions are kept for good. There is no Remove here.
- **Rules · N**: each always-allow rule with its repo and when it was added, newest first, and **Stop noting this rule**, with **Undo** for 5 seconds. One Roof only notes when a new ask matches a rule; it never answers for you. Always allow also told the agent not to ask again, and the agent keeps that in its own settings: Stop noting this rule only removes One Roof's note.

## Subagents (⇧⌘A)

A timeline of the subagents a Claude session started, read from its conversation transcript. A session whose transcript cannot be matched shows no subagents rather than a guess.

The time axis labels every 1, 2, 5, 10, 15 or 30 minutes (or hours for long sessions), whatever fits the width. Click a subagent to see its card:

- **Task:** the name the parent gave it, and **Given by** the session that started it.
- **What it was asked:** the parent's prompt, folded to five lines; **Show all** opens the rest.
- **Status:** running for how long, or finished how long ago and how long it ran; its model and tokens.
- **Its final report** (or **Its latest message** while it runs): the subagent's own last words. It says so plainly when it has written nothing.
- **Files it read or changed:** with lines added and removed; click one to open it.

## Command palette (⌘K)

![The command palette](img/palette.png)

Press **⌘K** (⌘P works too), or click the search box in the toolbar, and type a few letters. It searches:

- **Views:** Workspace (back to the terminals), Overview, Resources, Decisions, Subagents, Board, Work, Learn, Foundations, Settings.
- **Windows:** every workspace window, and New workspace window.
- **Actions:** plan a session, new terminal, new objective, new work item, find in terminal, search in workspace, toggle each panel, review changes, split right or down, close or maximize a pane, even out panes, reopen a closed session, run the startup check, remove exited sessions, open the selected session in a new window, roof windows, How do I…?
- **Themes:** set all panels to one theme.
- **Sessions, objectives and projects** by name.
- **Files** tracked in the selected session's repo (up to 4,000), which open in the viewer.
- **Skills**, which open their card in Learn.

Letters can be spread out ("rvch" finds Review changes); runs of letters and word starts rank higher. **↑ / ↓** move, **Return** runs the item, clicking elsewhere closes the palette.

## Every keyboard shortcut

All of these are in the menu bar too. Settings › Shortcuts lets you change any of them.

| Shortcut | Menu | Does |
|---|---|---|
| ⌘, | One Roof › Settings… | Settings |
| (none) | One Roof › Setup… | The first-run setup again |
| ⇧⌘F | One Roof › Foundations… | The startup check, skills, hooks, memory |
| ⌘K (or ⌘P) | One Roof › Command Palette… | Find views, actions, sessions, files, skills |
| ⌘H / ⌥⌘H | One Roof › Hide One Roof / Hide Others | Hide the app, or the other apps |
| ⌘Q | One Roof › Quit One Roof | Quit (agents keep running in roofd) |
| ⌘N | File › New Session… | Start or plan a new session |
| ⌘T | File › New Terminal | A plain shell in your projects folder |
| ⌃⌘T | File › New Terminal in Selected Repo | A plain shell in the selected session's repo |
| ⇧⌘N | File › New Workspace Window… | A new workspace window with its own sessions |
| ⌥⌘N | File › New Roof Window for Selected Repo | Every live session of that repo in its own window ([page 11](11_roof-windows.md)) |
| ⇧⌘O | File › New Objective… | Write an objective |
| ⌃⌘N | File › New Work Item… | Decide what a piece of work is, then create it |
| ⌘O | File › Open File… | Open a file in the viewer |
| ⌘S | File › Save | Save the open file, or the session's edits in the plan panel |
| ⌘↩ | File › Launch Selected Session | Launch the selected planned or exited session |
| ⌘W | File › Close Session… | Close the selected session (asks if it is running) |
| ⇧⌘T (or ⌥⌘T) | File › Reopen Closed Session | Bring back and relaunch the last closed session |
| ⌥⌘O | File › Open in New Window | Move a running session into its own window |
| ⌃⌘W | File › Close Window | Close the window (agents keep running in roofd) |
| ⌘Z / ⇧⌘Z | Edit › Undo / Redo | Undo and redo in text fields |
| ⌘X / ⌘C / ⌘V / ⌘A | Edit › Cut / Copy / Paste / Select All | Text editing and terminal copy and paste |
| ⌥⌘K | Edit › Clear Terminal | Clear the focused terminal |
| ⌘F | Edit › Find… | Find in the focused terminal |
| ⌘G / ⇧⌘G | Edit › Find Next / Find Previous | Next or previous match |
| ⇧⌘S | Edit › Find in Workspace | Search across your repos |
| ⌘1 … ⌘5 | View › Group by Status, Repo, Project, Agent, Account | Group the sessions panel |
| ⇧⌘L | View › Overview | One page of all work |
| ⇧⌘U | View › Resources | Memory and CPU of One Roof, every window and session ([page 12](12_resources.md)) |
| ⌘B | View › Board | Kanban of every session |
| ⌘I | View › Decisions | Every agent waiting on you |
| ⇧⌘A | View › Subagents | Timeline of Claude subagents |
| ⇧⌘E | View › Learn | The narrated deck: Radio, Writing, All cards |
| ⇧⌘W | View › Work: Projects and Roadmap | Projects, milestones, tickets |
| ⌘+ / ⌘− / ⌘0 | View › Bigger Text / Smaller Text / Actual Size | Text size |
| ⌥⌘S | View › Toggle Sidebar | Show or hide the sessions panel |
| ⌥⌘P | View › Toggle Plan Panel | Show or hide the plan panel |
| ⌥⌘C | View › Terminal Panel | Show or hide the terminal (the middle panel), also the Terminal toggle in the toolbar |
| ⌥⌘B | View › File Browser | Show or hide the file browser |
| ⌥⌘R | View › Review Changes | Review the selected session's uncommitted changes |
| ⌘D | View › Split Right | Split the focused pane, new pane on the right |
| ⇧⌘D | View › Split Down | Split the focused pane, new pane below |
| ⌥⌘W | View › Close Pane | Close the focused pane (the session keeps running) |
| ⇧⌘↩ | View › Maximize Pane | Show only the focused pane; again to show all |
| (none) | View › Even Out Panes | Every split back to half and half |
| ⌥⌘← ⌥⌘→ ⌥⌘↑ ⌥⌘↓ | View › Focus Pane Left / Right / Up / Down | Move focus to the next pane |
| ⌥⌘F | View › Focus: Terminal Only | Hide both side panels; again to bring them back |
| ⌘↓ ⌘↑ | (in a terminal) | Jump to the live bottom / the top of the scrollback; **Current ↓** at the bottom right does the same |
| ⌘L | View › Focus Terminal | Leave the Overview, Board, Work, Learn or an objective and type in the terminal |
| ⌘R / ⇧⌘R | View › Raw Stream / Run, Debug | In a session: its raw output; in the editor: run or debug the file |
| ⌘. | Session › Interrupt | Interrupt the selected agent |
| ⌘] / ⌘[ | Session › Next Session / Previous Session | Move down or up the sessions panel |
| ⌘M | Window › Minimize | Minimize the window |
| ⌃↑ | Window › All Windows | The Overview |
| ⌥⌘1 … ⌥⌘9 | Window › Workspaces | Go to workspace window 1 to 9 |
| ⌥⌘/ | Help › How Do I…? | Ask Learn a question ([page 09](09_learn.md)) |

Without a shortcut, in the menus: Run Startup Check (One Roof menu); Ask Agent About Selection (Edit); the panel theme menus and Search in Workspace (View); Launch, Mark as Next, Mark as Planned, Do Not Use, Pin, Rename…, Move to Window, Schedule, Run Now, Send Handoff, Open Repo in Finder, Copy session id, Copy Working Directory, Copy Attach Command, Copy Link to Session, Close Agent…, Delete Session, Remove Exited Sessions… (Session); Zoom, Roof Windows, Foundations and Bring All to Front (Window); One Roof Help, Keyboard Shortcuts, Release Notes and the README (Help).

### Keys inside a view

| Where | Key | Does |
|---|---|---|
| New session sheet | ⌘↩ / Esc | The main button (Launch, Save as next…) / Cancel |
| Plan panel | ⌘S | Save the session's edits |
| Session name in the sidebar | double-click, then Return / Esc | Rename / cancel |
| Find bar | Return / ⇧Return / Esc | Next match / previous match / close |
| Command palette | ↑ ↓, Return | Move, run |
| Review comment box | ⌘↩ | Send the comment to the agent |
| Review panel | ⌘↩ / ⌥⌘D | Commit / side-by-side diff on or off |
| Inbox | ↑ ↓ or ⌘] ⌘[ / Return / Esc / 1–9 / ⌘↩ / Tab | Move between blocks / the first option (or Allow once) / Deny or cancel / press option n / open the session / into the reply box |
| Terminal | ⌘-click a link | Files open in the viewer, web links in the browser |
