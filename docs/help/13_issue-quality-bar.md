# One Roof help: Issue quality bar

**Status:** LIVE · **Date:** 2026-10-23

> **One line:** Every Linear issue type has a few things it must say before an agent can work on it. An issue that is missing any of them is marked **not ready** in Pick issues and on the plan panel's Ticket tab, with a list of what is missing.

## Goal

An agent can only do as well as the issue it is given. A bug with no steps to reproduce, or a deliverable with no "done when", leads to guessing. The quality bar makes the gap visible before you start a session on that issue.

## The bar, per type

The type is the issue's Linear **Type** label. **Must have** items are required: if any is missing, the issue is not ready. **Bonus** items add points but are not required.

| Type | Must have | Bonus |
|---|---|---|
| **Bug** | Steps to reproduce · Expected vs actual · Where it was seen (version, build or screen) | Screenshot · file:line |
| **Deliverable** | Outcome · Done when · Scope | Mockup or screenshot · file:line |
| **Task** | What to do · Done when | file:line · Link to context |
| **Spike** | The question · Outcome (what the answer will look like) | Timebox · Link to context |
| **Decision** | Options · Recommendation | Context (why now) · Trade-offs |

An issue with no Type label is not ready, because the bar cannot be applied to it.

## How One Roof reads an issue

One Roof reads the issue's description (and, for a spike's question, its title). It looks for:

- **Headings or labels.** A Markdown heading (`## Steps to reproduce`), a bold label (`**Expected:**`) or a plain `Label:` line, for example *Steps to reproduce*, *Expected*, *Actual*, *Outcome*, *Scope*, *Done when*, *Acceptance criteria*, *Options*, *Recommendation*, *Context* or *Timebox*.
- **Phrases.** For example "so that", "out of scope", "should …" with "instead" or "but got", "recommend", "Option A", or a checklist (`- [ ]`) for done-when.
- **Shapes.** A numbered list of two or more steps counts as steps to reproduce. A version number such as `0.5.1` counts as where it was seen.
- **Screenshots.** A Markdown image (`![…](…)`), a file uploaded to Linear (`uploads.linear.app`), or a link to an image or video file.
- **file:line.** A path with a line number, such as `PopOutWindow.swift:61`.

The check is a quick read, not a judge: it finds the usual ways of writing these things, so the most reliable way to pass is to use the headings above.

## Score

Each issue gets a score out of 100: must-haves are worth 80 points, shared equally, and bonus items 20. A ready issue scores at least 80. The score and the full list (missing must-haves, then bonus items you could add) are in the tooltip on the **not ready** badge.

## Where you see it

- **Pick issues** (New session › Issues): a small **not ready** badge on each issue below the bar, with the missing items in its tooltip; a **Not ready** filter chip that lists only those issues; and a "Missing: …" line under the title of the issue you are reading.
- **Plan panel › Ticket tab:** a short "Missing: …" line under each attached issue that is below the bar.

To fix an issue, add what is missing in Linear. One Roof picks up the change the next time it loads the issue list.

## Template

Copy the block for the type into the issue's description and fill it in.

```markdown
## Steps to reproduce
1.
2.

**Expected:**
**Actual:**
**Seen in:** One Roof <version>, <screen>
```

```markdown
**Outcome:** <what changes for the user, and why>
**Scope:** <what is in> · Out of scope: <what is not>

## Done when
- [ ]
```
