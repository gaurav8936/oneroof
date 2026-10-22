# SwiftUI: `.onReceive(model.$x)` fires before `model.x` holds the new value

**Found:** 2026-10-21 (LAB-518 self-test) · **Where:** `NewSessionSheet.selfTestPick`

**Symptom:** a hook on `.onReceive(model.$issues)` that read `model.issues` (via a computed property) saw the old, empty list, so nothing was picked. Once it read the published value it ran twice (Linear publishes the list more than once while loading) and the second pass unticked everything.

**Rule:** inside `onReceive`, use the value it passes, not the property (`@Published` sends on willSet). Make one-shot hooks idempotent with a flag that is not view state.
