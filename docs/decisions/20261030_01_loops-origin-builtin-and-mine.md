# Unified Loops screen: Built-in kit loops and Mine loops in one list

**Status:** DECIDED · **Date:** 2026-10-30 · **Linear:** LAB-1663

> **One line:** One Roof's Loops screen merges the 8 built-in Agentic Engineering kit loops (`kit/loops/catalog.json`) with user-created loops (`<shared>/loops/<id>/loop.json`), grouped into **Pinned · Mine · Built-in** with origin badges.

## The question

One Roof's `LoopStore` previously scanned only `<shared>/loops/*/loop.json` (`~/Projects/_common/loops/` or `~/.oneroof/loops/`), while the 8 pre-packaged loops lived in `labs-agentic-engineering/kit/loops/*.loop.yaml`. As a result, the Loops screen only showed user-authored loops and had no visibility into the built-in kit loops.

## Decision

- **Bundle the kit loop catalog:** `app/scripts/bundle.sh` archives `kit/loops` into `Contents/Resources/agentic_engineering/deck/kit/loops/catalog.json`, resolved at runtime by `AEFolder.loopsCatalog(_:)` (falling back to `~/Projects/labs/labs-agentic-engineering/kit/loops/catalog.json` in dev).
- **Merge in `LoopStore` (`OneRoofCore/LoopStore.swift`):**
  - `LoopStore.all()` and `LoopStore.load(_:)` seed from `LoopBuiltIns.all()` (`origin: .builtIn`) and overlay `<shared>/loops/*/loop.json`.
  - If a disk file shares a built-in ID (because the owner paused, pinned, ran, or edited a built-in loop), `origin` stays `.builtIn` and `LoopStore.hasDiskOverride(_:)` is `true`.
  - **Reset** deletes `<shared>/loops/<id>` for a customized built-in loop, restoring the bundled definition; **Delete** is shown only for `.mine` loops.
  - **Duplicate as mine** forks any loop into a new `.mine` loop ID, and `LoopStore.newId(for:)` avoids colliding with `LoopBuiltIns.ids`.
- **Loops UI (`OneRoof/UI/LoopsView.swift`):**
  - Left pane groups loops into **Pinned**, **Mine**, and **Built-in**, with `Mine` / `Built-in` origin badges in both the list row and detail header.
  - The `+` New Loop template picker exposes both starter patterns and the 8 built-in kit templates.
