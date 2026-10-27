# Self-test terminals show "This agent has exited", and panes use the classic window

**Found:** 2026-10-26 · **Project:** LAB-ONEROOF-UI-REDESIGN

**Symptom.** In `scripts/selftest-shot.sh` runs, a launched terminal immediately reads "This agent has exited", so the Table view never shows; and the captured agent pane has the old hint strip instead of the v2 composer.

**Why.** `selftest-shot.sh` sets `ONEROOF_SELFTEST_DEMO=1`, which empties roofd's session list on every poll, so every launched session looks ended. Self-tests also run the classic window unless `ONEROOF_SELFTEST_UI2=1` (Prefs.swift).

**Fix.** Pass `ONEROOF_SELFTEST_DEMO=0 ROOFD_DIR=/tmp/<scratch> ONEROOF_SELFTEST_UI2=1 ONEROOF_FRESH_PROFILE=1` (the fresh profile keeps the owner's settings, such as Step review, out of the run). A login shell resets PATH, so a stand-in `claude` on PATH does not replace the real one.
