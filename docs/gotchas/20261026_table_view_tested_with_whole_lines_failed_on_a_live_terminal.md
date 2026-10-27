# The Table view passed its tests with whole lines and failed on a live terminal

**Found:** 2026-10-26 · **Project:** LAB-ONEROOF-UI-REDESIGN (LAB-1299, 1.9.4 → 1.9.5)

**Symptom.** 1.9.4's Table view found two 15-column tables in every test and capture, but on the owner's terminal it showed the raw pieces: no table at all.

**Why.** The tests and the `ONEROOF_SELFTEST_TERMTEXT` fixture fed the text as logical lines. A live terminal hands it over as screen rows: each row wider than the pane is cut at the edge, and after the app reattaches to roofd the replayed output is cut again at roofd's width. The self-test build has no libghostty text (`alltext` is "(none)"), so the real path was never exercised.

**Check.** Test terminal parsing with the text cut into rows (e.g. 67, 80, 131, 156 columns) and with the real text from `roofd read <id> 400` (read-only). `TerminalFormat.rejoinTableRows` and `rejoin(columns:skipTableRows:)` handle the cuts.
