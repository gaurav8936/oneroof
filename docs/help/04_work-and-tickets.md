# One Roof help: work and tickets

**Status:** LIVE · **Date:** 2026-11-01

> **One line:** the Projects view (⇧⌘W) shows every project from Linear, team by team, filtered by status, with its milestones and tickets; New work item (⌃⌘N) decides what a piece of work is before creating it; and tickets and sessions update each other. All of this is optional and needs a Linear API key.

![The Projects view: teams and their projects on the left with the status chips, the selected project's roadmap on the right](img/work.png)

## Goal

Each tool owns one thing: Linear owns **projects** and **tickets**, One Roof owns **sessions** and is where work starts. You should never have to copy a ticket into a session by hand, or remember to move a ticket when a session starts or ends.

## Connect Linear

The Projects view and tickets are optional. Without Linear, the rest of One Roof works the same, and the Projects view explains how to connect.

- **The key:** a Linear personal API key, in the `LINEAR_API_KEY` environment variable or in `~/.config/oneroof/linear-api-key`. The first-run setup (One Roof › Setup…) can save it there for you. One Roof never shows the key.
- **Check the connection:** `OneRoof --linear` in a terminal prints your teams and how many projects it found, with each project's code.
- **Test a full round trip:** `OneRoof --linear --linear-roundtrip <TEAM>` (for example `ENG`) creates a test project with two milestones and a Bug ticket, prints what Linear stored, then deletes both (they go to Linear's trash).
- **Limits:** up to 150 tickets per project and 20 milestones are fetched.

## Three words, with examples

| Word | What it is | Example |
|---|---|---|
| Project | An outcome that needs several sessions and more than one deliverable. A Linear project (any project in your workspace). | `ENG-CHECKOUT · New checkout` |
| Ticket | One deliverable, defect, spike, decision or chore, in a Linear team and usually in a project. | `ENG-42`, the payment form |
| Session | One agent run, usually on one ticket. | "Payment form" on Claude1, linked to ENG-42 |

## The Projects view (was Work)

Open it with **⇧⌘W** (View › Projects), **Projects** on the left rail (it was called Work before 2.0), or the palette.

- **Left: teams, then their projects.** Each team is a header such as `▾ ENG · Engineering   4` (key, name, how many projects show). Click it to fold or unfold the team; **⌥-click** folds or unfolds every team. Every team starts unfolded, and One Roof remembers the ones you fold. A team with no project in the chosen statuses is hidden, and a line at the end says how many ("2 teams have no projects in these statuses").
- **Each project** shows its title first (up to two lines, never cut mid-word), then its code, its status pill and, when sessions are running on it, how many.
- **Status chips:** **Backlog · Planned · In progress · In review · Completed · Canceled**, each with its count, in the same style as All sessions' filters. Pick several at once; with none picked, every status shows. The list opens on **In progress + In review**; when you change that, **Reset** brings it back (and clears the text). Your chips and filter text are remembered.
  - *All In progress projects in ENG:* click **In review** off (one click) and read the ENG group, or fold the other teams.
  - *Everything In review in WEB:* click **In progress** off (one click) and read the WEB group.
- **In review** is worked out by One Roof, since Linear has no In Review project status: a project that is In Progress in Linear shows **In review** when it has open tickets In Review and none In Progress. (If you add a project status named "In Review" in Linear, it counts too.) Paused projects count as In progress. Linear's Completed shows as **Completed** (it said "Shipped" before 2.0).
- **Filter by name or code** matches the project code and the title. **⌘F** jumps to it. The reload and back-to-terminals buttons sit under the chips; a spinner shows while projects load, with **Try again** if Linear fails, and **Connect Linear…** when there is no key.
- **Keys:** ↑ and ↓ move through the projects you can see (folded teams are skipped) and open each one; ← folds the selected project's team and → unfolds it; Return reloads the open project.
- **Right, for the selected project:** its code and status, its title, "12 of 20 tickets done", links to **Linear**, the **Tracker pane** and the **Docs** folder when they exist, then the **Roadmap**: each milestone with its open tickets (tick **Show done** for all). The project page shows the project only: sessions live in Sessions and All sessions, where each session row shows its ticket and project.
- **On each ticket:** its key, type (Deliverable, Defect, Spike, Decision, Chore), title, a state pill you can click to change the state in Linear, a play button (▷) to **plan a session** for it, and a link to Linear. To find a ticket's running session, search its key in All sessions.

**Tracker pane and Docs are optional.** The Tracker pane link appears when a `_MASTER-TRACKER.html` file in your projects folder, one of its subfolders or your shared folder has a section for the project. The Docs link appears when a `docs/projects/<code>/` or `docs/workstreams/<id>/` folder exists for it, in your shared folder, at the root of a `*-docs` repo, or in a repo's `docs/`.

## From a ticket to a session

1. Press the play button on a ticket, or pick it under **Issue ▾** in the New session sheet (⌘N). One Roof plans a session with the ticket key, the project, and an opening message that says to work on that ticket and commit as `ENG-42 · [eng-checkout] …`.
2. Launch it. The ticket moves to **In Progress** in Linear.
3. The row shows the ticket key, and the plan panel's **Ticket** tab shows the live state with buttons **In Progress**, **In Review** and **Done**.
4. When you close the agent (Close Agent…), a box (on by default) posts a summary comment to the ticket (agent, seat, run time, newest handoff for the project, your notes) and moves it to **In Review**. Committing from the review panel can do the same ([Review](10_review-split-panes-and-session-rows.md)).

## One session, several issues

A session can work on more than one issue, including ones that come in while it runs.

- **Add an issue:** **Issue…** (or **Add issue…**) in the session menu, **Add Issue…** on right-click, or **Add issue…** on the plan panel's **Ticket** tab. Pick an open issue or create one. An issue already on the session is not added twice.
- **Telling the agent:** with **Tell the agent** on, the agent gets a message naming the issue and how to commit for it. If the agent is working, the message waits and is sent the moment it is back at its prompt (it survives a restart).
- **What you see:** the row shows `KEY +N`; the **Ticket** tab lists each issue with its state and an ✕ to take it off the session. A running session's new issue moves to **In Progress**.
- **On commit:** when a commit made after launch names one of the session's issues (`ENG-42 · …`), that issue moves to **In Review** once, with the commit in a comment.
- **On close:** Close Agent… shows one box per issue, so you choose which ones move to **In Review**.

### Start a session on several issues at once

In the New session sheet (⌘N), pick the team and project, then click **Issue ▾**. A **Pick issues** panel opens beside the sheet: a table of the project's open issues (tick · order · key · title · state): In Progress, To do, Backlog, and In Review last. Ticking a row never moves it; the order column numbers the ticked ones in the order you ticked them. Filter by state with the chips (**All**, **Picked** for just the ones you ticked, plus each state, with counts) or by text (key, title or description). Drag the panel's edges to make it bigger and drag the column dividers to widen a column; the panel remembers its size. **Click a column header to sort** by it (Key by number, Title, State, **Created** or **Updated**; click again to reverse); **Default order** goes back to In Progress, To do, Backlog, In Review, and the panel remembers your sort. The list comes fresh from Linear each time the panel opens, on every chip click, every minute while it is open, and from the **↻** button next to the title, so issues created after you opened the window show up (a spinner shows while it loads). Select a row to read the whole issue (title, state, milestone, description, link) in the pane under the table, then **Add to session** there, tick its box, or double-click the row. Press **Done** when you have them all.

- **One session, all of them.** Creating it makes one session holding every ticked issue. Its name carries each key: `LAB-1, LAB-2, LAB-3 · <your title>` (or `· 3 issues` when you leave the title empty). The first issue you ticked is its main ticket.
- **The opening message** lists every issue (key, title, state, link) and asks the agent to read them all, look for shared causes and dependencies, and write **one plan** that resolves them in the best order. It shows you the plan and carries on unless an issue needs your decision. If you write your own words into the message, they stay: ticking or unticking more issues afterwards only updates the list of issues in it.
- **The agent keeps each issue up to date.** It posts the plan on each issue, moves an issue to **In Progress** when it starts on it, commits that issue's work under its own key, and moves it to **In Review** with a short summary when it is done. Launching does not move them all to In Progress at once.
- **How the agent does it:** inside a One Roof session an agent runs `"$ONEROOF_ROOFD_BIN" issue LAB-1 --state "In Progress"` or `… issue LAB-1 --state "In Review" --comment "what changed"` (`--comment -` reads the text from stdin, `--comment-file <path>` from a file). One Roof applies it with your Linear key and the agent sees `done: …` or the reason it was refused. An agent can only update **its own session's** issues, and only to **In Progress** or **In Review** (or comment); **Done** and **Canceled** stay with you.
- Sessions started before One Roof 0.4.6 cannot take these updates; relaunch them.

## New work item: decide what it is first

Press **⌃⌘N** (File › New Work Item…), **New item** in the Projects view, or **+ New work item** on the Overview. The New session sheet (⌘N) can also create an issue or a project, as the last item of its **Issue ▾** and **Project ▾** menus, and then starts the session on it ([New session](02_planning-a-session.md#when-the-work-is-not-in-linear-yet)).

1. Say what you want done ("Login fails on Safari") and optional details.
2. Tick "It needs several sessions and more than one deliverable" if it is bigger than a ticket.
3. One Roof suggests **what it is** (project, deliverable, defect, spike, decision, chore, or just a session) and **which project** it belongs to. You can change both.
4. If a ticket with a similar title already exists, it says "Looks like an existing ticket. Use it instead?" with **Plan a session for it**.
5. Create it: the ticket is made in Linear (Backlog, with its Type label: Deliverable, Bug, Task, Spike or Decision), and "Plan a session for it now" plans the session in the same step.

A **new project**, with Linear connected, is created straight in Linear (named "CODE · title", state Planned, with the milestones you list), and then One Roof plans a Claude session that writes its docs folder, adds the first tickets and posts a first project update. Without Linear, the Claude session does every step. See [When the work is not in Linear yet](02_planning-a-session.md#when-the-work-is-not-in-linear-yet).

## Which Linear projects and codes

One Roof reads **every** project in your Linear workspace.

- **A project's code** is the part of its name before " · ", when that part looks like an id: TEAM-TOPIC or TEAM-TOPIC-NN. `ENG-CHECKOUT · New checkout` has the code `ENG-CHECKOUT`; `ENG-KNOW-03 · Knowledge v3` has `ENG-KNOW-03`. Older names that start with `WS-` still work.
- **In free text** (session names, commit tags) One Roof recognises `WS-…` ids, commit tags like `[eng-know-03]`, and bare upper-case codes like `ENG-KNOW-03`.
- **Issue keys** like `ENG-42` are never read as projects.
