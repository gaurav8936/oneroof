# `swift build` in a worktree says "no product named 'OneRoof'"

**Found:** 2026-10-26 · **Project:** LAB-ONEROOF-UI-REDESIGN

**Symptom.** In a fresh `.worktrees/<unit>/app`, `swift build --product OneRoof` fails with `no product named 'OneRoof'`, even after `Vendor/*.xcframework` is in place; `swift package dump-package` lists no products.

**Why.** Package.swift only declares the app when `Vendor/GhosttyKit.xcframework` exists, and SwiftPM reuses a cached manifest evaluated before Vendor was there. Symlinking Vendor to the main checkout does not help either: the manifest sandbox cannot see outside the package.

**Fix.** Copy the vendor folders (`cp -R <main>/app/Vendor/*.xcframework <wt>/app/Vendor/`, they are git-ignored) and build and test with `--manifest-cache none`.
