# CI's tests/run.sh runs Python tests on the system Python 3.9: `X | None` in exec'd code fails

**Found:** 2026-10-31, 1.9.37 lift PR #304 (test-mac failed; LAB-1996). **Fixed in:** c02f7c0.

**Symptom.** `tests/test_eval_engine.py` passes when run directly, but `bash tests/run.sh` (and Woodpecker's
test-mac step) reports `FAIL eval engine`, with `TypeError: unsupported operand type(s) for |: 'type' and 'NoneType'`.

**Cause.** `tests/run.sh` sets `PATH=fakebin:/usr/bin:/bin:…:$PYDIR`, so `/usr/bin/python3` (macOS's 3.9) wins over
the Python you normally use. A test that `exec`s a fragment of a generated file (here the judge's task file, which
uses `def f(text: str) -> str | None`) evaluates the annotation at definition time, and 3.9 has no `X | None`.
Modules with `from __future__ import annotations` are fine; extracted fragments lose that import.

**Do.** Compile extracted fragments with `flags=__future__.annotations.compiler_flag`. Before a release, run the
whole `tests/run.sh` (as CI does), not only the one test file: `GIT_CONFIG_GLOBAL=/tmp/x bash tests/run.sh`.
