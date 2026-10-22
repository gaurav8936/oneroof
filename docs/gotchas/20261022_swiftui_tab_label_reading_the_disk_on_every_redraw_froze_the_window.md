# A SwiftUI tab label that read the disk on every redraw froze the window (0.4.8)

**Found:** 2026-10-22 · **Issue:** LAB-540 · **Came in with:** LAB-513 / LAB-510 (0.4.8) · **Fixed in:** 0.4.9 (commit `4768e00`)

## Symptom
One Roof 0.4.8 froze: the main thread sat at 100% CPU and the window never caught up.

## Cause
The Artifacts tab label in `PlanDetail` shows a count, and that count came from a computed property
(`artifacts`) that called `SessionArtifacts.list`, which:
- listed the handoff folder (~149 files), and
- compiled one regex per file per issue key.

SwiftUI evaluates a label every time the view body runs. The tab row sits in a `ViewThatFits` with 4
layouts and builds each label twice, and `AppModel` publishes constantly while agents run. So the disk
scan ran many times per redraw, on the main thread, all the time.

The unit tests checked that the right files were listed (correctness), never how often or where the scan ran.

## Fix
- Keep the list in `@State` (`artifactItems`) and fill it from `.task(id: live.session)` on a
  `Task.detached(priority: .utility)`: once when the session changes, then every 10 s for new handoffs.
- Assign only when the list changed, so an unchanged scan does not trigger a redraw.
- In `SessionArtifacts.handoffs`, compile one alternation regex for all keys per scan.

## Rule
Nothing a SwiftUI `body` or label reaches may touch the disk, the network or a regex compile per item.
Cache it in state, refresh it off the main thread, and compare before assigning.
