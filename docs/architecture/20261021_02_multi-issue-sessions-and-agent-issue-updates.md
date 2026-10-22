# Multi-issue sessions and agent issue updates

**Status:** ACTIVE · **Date:** 2026-10-21 · **Project:** LAB-ONEROOF-v0.50 (LAB-518, LAB-523) · **Read with:** [help: work and tickets](../help/04_work-and-tickets.md#start-a-session-on-several-issues-at-once)

> **One line:** New session can start one session on several Linear issues, with a plan-first opening message, and the agent in that session keeps each issue up to date by asking One Roof (`roofd issue`), which applies the change with the owner's Linear key.

## Why

The owner wanted to pick several issues of a project (backlog or active) when creating a session, have one session own all of them, and have the agent plan one order that resolves them all and then work through them, updating each issue in Linear as it goes (2026-10-21). LAB-474 (0.4.3) had already made a session hold several issues (`ticket` + `moreTickets`), but only by adding them one at a time after creation, and only the owner or the commit watch moved their states.

Sessions that should be split into several sessions by a model are out of scope (LAB-483).

## What happens

```
New session sheet                               One Roof app                          Linear
  Issue ▾ → Pick issues panel (LAB-523)
  tick LAB-1, LAB-2, LAB-3
  Create ─────────────► Session(ticket: LAB-1, moreTickets: [LAB-2, LAB-3])
                        name "LAB-1, LAB-2, LAB-3 · <title>"
                        opening = Intake.multiTicketOpening(...)
                        launch: issues NOT moved to In Progress (ticketsToStartOnLaunch = [] for >1 issue)

Agent (inside the session)
  "$ONEROOF_ROOFD_BIN" issue LAB-2 --state "In Progress" --comment "starting"
        │  op "issue" on the holder socket ($ONEROOF_ROOFD dir/<id>.sock)
        ▼
  roofd holder: issueQueue += {seq, key, state, comment}; info/list → "issues": [...]
        ▲                                                         │ every 3 s (roofd list)
        │ op "issueStatus" every 250 ms, up to 20 s               ▼
        │                                     AppModel.applyIssueRequests()
        │                                       IssueRequest.check(against: session)
        │                                         · key must be one of the session's issues
        │                                         · state only In Progress / In Review
        │                                       moveIssue / comment ─────────────────────► state + comment
        │                                       roofd.issueDone(id, seq, error)
  holder: issueAnswers[seq] = "" or reason ◄──── (via daemon passthrough "issueDone")
  CLI prints "done: move LAB-2 to In Progress + comment"  or  "roofd: issue: <reason>" (exit 1)
  (no answer in 20 s: "queued: … (One Roof applies it when it is running)")
```

## Decisions

| Decision | Why |
|---|---|
| The agent asks One Roof; it never gets a Linear key | One key, the owner's, stays in the app; any agent (Claude, Codex, Kimi…) can do it with one shell command |
| Only the session's own issues, only In Progress / In Review, or a comment | Humans stay in the loop: Done and Canceled are the owner's (agent rules §9) |
| Applied at most once | The app remembers `runtime-id:seq`; it forgets a tag only after roofd took the answer. If roofd cannot take it (an older daemon right after an upgrade) the tag stays, so Linear never gets the same comment twice |
| A refusal is `refused`, not `error`, in the `issueStatus` reply | roofd's socket helper throws on any reply with an `error` key, so the asking CLI would never see the reason |
| A multi-issue session does not move its issues to In Progress at launch | The agent moves each one when it actually starts on it, so Linear shows the real order |
| The commit watch (LAB-474) stays | A commit naming an issue still moves it to In Review once; the agent's own In Review adds the summary |
| Picked issues live in a shared `IssueSelection` object (LAB-523) | The sheet and the picker panel are separate hosting views; a closure into the sheet's `@State` read a stale copy |
| The picker is a resizable panel with a table, not a popover (LAB-523) | A popover cannot be resized; long issues need wide columns and a pane to read them in full before adding |

## Where the code is

| Part | File |
|---|---|
| Request model, permission check, session name, opening message, launch rule | `app/Sources/OneRoofCore/IssueUpdates.swift` (tests `IssueUpdateTests.swift`) |
| Picker order and state filters | `app/Sources/OneRoofCore/IssuePick.swift` (tests `IssuePickTests.swift`) |
| Requests read from `roofd list` | `app/Sources/OneRoofCore/RoofdRuntime.swift` (`sessionState`, `issueDone`) |
| Apply + answer | `app/Sources/OneRoof/AppModel+Work.swift` (`applyIssueRequests`, every 3 s) |
| Holder queue, `issue` / `issueStatus` / `issueDone` ops | `app/roofd/Sources/roofd/Holder.swift`; passthrough in `Daemon.swift` |
| `roofd issue` CLI (+ harness-only `roofd issue-done`) | `app/roofd/Sources/roofd/main.swift` |
| Sheet + panel | `app/Sources/OneRoof/UI/NewSessionSheet.swift`, `UI/IssuePickerPanel.swift` |
| Self-test | `ONEROOF_SELFTEST_PICK=KEY,KEY` ticks issues once they load; `ONEROOF_SELFTEST_ISSUES=1` opens the panel |

## Limits

- Sessions started before 0.4.6 run older holders: `roofd issue` says to relaunch the session.
- The project code is read from the Linear project name; codes with a dot (`LAB-ONEROOF-v0.50`) parse as `LAB-ONEROOF` (LAB-519), so their commit tag in the opening message is wrong until that is fixed.
- Released: LAB-518 in 0.4.6 (2026-10-21). LAB-523 is built and tested but not yet released (next: 0.4.7).
