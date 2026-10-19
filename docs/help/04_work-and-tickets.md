# One Roof help: work and tickets

**Status:** LIVE · **Date:** 2026-10-19

> **One line:** the Work view (⇧⌘W) shows every workstream from Linear with its phases, tickets and sessions; New work item (⌃⌘N) decides what a piece of work is before creating it; and tickets and sessions update each other. All of this is optional and needs a Linear API key.

![The Work view: workstreams on the left, the selected workstream's sessions and roadmap on the right](img/work.png)

## Goal

Each tool owns one thing: Linear owns **workstreams** and **tickets**, One Roof owns **sessions** and is where work starts. You should never have to copy a ticket into a session by hand, or remember to move a ticket when a session starts or ends.

## Connect Linear

The Work view and tickets are optional. Without Linear, the rest of One Roof works the same, and the Work view explains how to connect.

- **The key:** a Linear personal API key, in the `LINEAR_API_KEY` environment variable or in `~/.config/oneroof/linear-api-key`. The first-run setup (One Roof › Setup…) can save it there for you. One Roof never shows the key.
- **Check the connection:** `OneRoof --linear` in a terminal prints how many workstreams it found.
- **Limits:** up to 150 tickets per workstream and 20 phases are fetched.

## Three words, with examples

| Word | What it is | Example |
|---|---|---|
| Workstream | An outcome that needs several sessions and more than one deliverable. A Linear project whose name starts with `WS-`. | `WS-WEB-12 · Checkout redesign` |
| Ticket | One deliverable, defect, spike, decision or chore inside a workstream, in Linear. | `ENG-42`, the payment form |
| Session | One agent run, usually on one ticket. | "Payment form" on Claude1, linked to ENG-42 |

## The Work view

Open it with **⇧⌘W** (View › Work: Workstreams and Roadmap), **Work** in the toolbar, or the palette.

- **Left:** every workstream (Linear projects whose names start with `WS-`), grouped by team, with its state and a count of live sessions. Filter them, tick **Show shipped**, reload from Linear, or go back to the terminals.
- **Right, for the selected workstream:** its name and state, "12 of 20 tickets done", links to **Linear**, the **Tracker pane** and the **Docs** folder when they exist, then **Sessions** (the sessions working on it) and the **Roadmap**: each phase with its open tickets (tick **Show done** for all).
- **On each ticket:** its key, type (Deliverable, Defect, Spike, Decision, Chore), title, a state pill you can click to change the state in Linear, a play button to **plan a session** for it, a link to its session if one exists, and a link to Linear.

**Tracker pane and Docs are optional.** The Tracker pane link appears when a `_MASTER-TRACKER.html` file in your projects folder, one of its subfolders or your shared folder has a section for the workstream. The Docs link appears when a `docs/workstreams/<id>/` folder exists for it.

## From a ticket to a session

1. Press the play button on a ticket. One Roof plans a session with the ticket key, the workstream, and an opening message that says to work on that ticket and commit as `ENG-42 · [ws-web-12] …`.
2. Launch it. The ticket moves to **In Progress** in Linear.
3. The row shows the ticket key, and the plan panel's **Ticket** tab shows the live state with buttons **In Progress**, **In Review** and **Done**.
4. When you close the agent (Close Agent…), a box (on by default) posts a summary comment to the ticket (agent, seat, run time, newest handoff for the workstream, your notes) and moves it to **In Review**. Committing from the review panel can do the same ([Review](10_review-split-panes-and-session-rows.md)).

## New work item: decide what it is first

Press **⌃⌘N** (File › New Work Item…), **New item** in the Work view, or **+ New work item** on the Overview. The New session sheet (⌘N) can create tickets too ([New session](02_planning-a-session.md)).

1. Say what you want done ("Login fails on Safari") and optional details.
2. Tick "It needs several sessions and more than one deliverable" if it is bigger than a ticket.
3. One Roof suggests **what it is** (workstream, deliverable, defect, spike, decision, chore, or just a session) and **which workstream** it belongs to. You can change both.
4. If a ticket with a similar title already exists, it says "Looks like an existing ticket. Use it instead?" with **Plan a session for it**.
5. Create it: the ticket is made in Linear (Backlog, with its type label and the `[ws-…]` prefix), and "Plan a session for it now" plans the session in the same step.

A **new workstream** is never created straight in Linear. One Roof plans a Claude session that opens it the way your rules describe (its id, its docs, its Linear project), so your notes and Linear do not drift apart.
