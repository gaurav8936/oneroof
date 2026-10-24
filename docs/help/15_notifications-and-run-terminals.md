# One Roof help: Notifications and run terminals

**Status:** LIVE · **Date:** 2026-10-23

> **One line:** One Roof tells you when an agent needs you, when one finishes, and when a long command ends where you aren't looking. Right-click a command an agent printed to type it into a terminal next to that agent, ready for you to run.

## Notifications

One Roof posts a macOS notification when:

- **an agent needs you**: it asks permission or asks a question. The notification says what it wants.
- **an agent is ready**: it finished its turn.
- **a long command finished**: a command in a terminal ran longer than the threshold (30 seconds by default). A failed command says "failed (exit N)".
- **a program sends one**: terminal programs that send their own notifications (OSC 9 or 777) come through too.

There is no notification for the session you are looking at while One Roof is in front. Repeats replace each other instead of stacking. Click a notification to open its session.

Turn each kind on or off, and set what counts as long, in **Settings › General**. The first time, macOS asks whether One Roof may send notifications; **Allow notifications…** in the same place asks again.

Notifications come from the app, so none arrive while One Roof is closed.

## Run in Terminal

Agents often print a command for you to run. Select it, right-click, and choose **Run in Terminal**:

- One Roof types the command into that agent's **run terminal**, a shell in the same repo, shown in a small floating window. It is **not run**: press **Return** when you are ready.
- Prompt marks (`$`, `❯`), box borders and wrapped lines are cleaned up. Several lines go in together.
- Each agent has one run terminal. The next Run in Terminal from the same agent reuses it, so its history stays in one place.
- It is listed under its agent in the Sessions list (↳). **Back to agent** puts the run window away and returns you to the agent's terminal; the run terminal keeps running, and the next Run in Terminal (or **Show window** on its ↳ row) brings it back.
- With nothing selected, Run in Terminal is greyed out.
