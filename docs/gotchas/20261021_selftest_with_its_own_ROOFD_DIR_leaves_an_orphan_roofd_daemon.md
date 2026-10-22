# Self-test with its own ROOFD_DIR leaves an orphan roofd daemon (and long paths fail)

**Found:** 2026-10-21 (QA of 0.4.4) · **Where:** self-test runs (`ONEROOF_SELFTEST_*`) with `ROOFD_DIR` set

**Symptom:** after QA captures, `ps` showed extra `roofd daemon` processes with a test ROOFD_DIR, children of launchd, still running after the test folder was deleted. With a deeply nested ROOFD_DIR the app showed "roofd socket path too long".

**Cause:** with no daemon in that folder the test app starts its own (reparented to launchd when the app quits). Unix socket paths are limited to 104 bytes.

**Rule:** use a short ROOFD_DIR (well under 104 bytes with the socket name), and after the captures `pkill -f "<that dir>"` and delete it. Check with `ps -axo pid,command | grep "[r]oofd daemon"`: there should be exactly one (the launchd one).
