# Running agents in parallel

**Status:** ACTIVE · installed by oneroof

1. **One worktree per worker.** Never let two agents edit the same checkout. `tools/swarmlet.py` creates them.
2. **One owner per shared contract.** Schema, migrations, lockfiles and shared types each belong to exactly one
   worker. Two workers that claim the same file must be serialized by a dependency (swarmlet warns if not).
3. **Foundation first, then waves.** Land the shared base yourself, then fan out.
4. **Workers don't spawn workers.** Only the coordinator fans out.
5. **Assumptions are written down, not asked.** A worker logs assumptions in `ASSUMPTIONS.md` and keeps going.
6. **Green means verified.** A worker's exit code or summary is not evidence; its `verify` command passing is.
7. **Bound the fan-out.** A hard cap on concurrent workers (swarmlet: 8, default 3), a timeout per worker, bounded
   retries, and a resource check before dispatch. Your laptop is the real concurrency limit.
