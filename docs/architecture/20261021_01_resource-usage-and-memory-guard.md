# Resource usage and the roofd memory guard

**Status:** ACTIVE · **Date:** 2026-10-21 · **Project:** LAB-ONEROOF-v0.50 · **Read with:** [help: Resources](../help/12_resources.md)

> **One line:** roofd's session holders now drain an autorelease pool every turn and stop themselves at 2 GB, and One Roof samples its own process trees every 3 s so the owner can see memory growing before it hurts the Mac.

## Why

On 2026-10-21 the Mac froze overnight. The "roofd" processes were session holders, not daemons: each one kept every JSON reply it had sent (`Holder.run()` never drained an autorelease pool), so a day-old holder reached 5.7 GB and three of them took 13 GB of a 16 GB Mac (LAB-310). The fix stopped the leak; the owner then asked to see resource use all the time (LAB-493).

## The memory guard (roofd, 0.4.3)

| Part | What it does | Where |
|---|---|---|
| Autorelease pool per turn | Every holder and daemon loop turn runs inside `autoreleasepool`, so reply data is freed | `app/roofd/Sources/roofd/Holder.swift` |
| Watchdog | Reads the process footprint every 10 s. Holder: warns at 1 GB, ends its session at 2 GB. Daemon: warns at 512 MB, exits at 2 GB. Overrides: `ROOFD_SESSION_MEM_WARN_MB`, `ROOFD_SESSION_MEM_LIMIT_MB`, `ROOFD_DAEMON_MEM_*` | `app/Sources/OneRoofCore/MemoryWatchdog.swift` |
| Log | Warnings and stops go to `roofd-memory.log` in roofd's folder (capped at 256 KB) | roofd |
| One holder per session | A holder takes `<id>.lock` before starting its program, so racing creates cannot leave an orphan | roofd |
| Bounds | Input queue 1 MB, frame 1 MB, daemon request 4 MB | roofd |

`info` reports `footprint` and `memoryWarning`; `hello` reports the daemon's `footprint`.

## Resource sampling (app, 0.4.4)

```
every 3 s, background queue
  sysctl KERN_PROC_ALL  →  pid / parent / name for every process
  roofd list            →  each session's pid  →  its parent (named roofd) = the holder
  proc_pid_rusage       →  phys_footprint (Activity Monitor "Memory") and CPU time, per relevant pid
  host_statistics64     →  Mac memory used, pressure, swap
  → ResourceSnapshot on the main thread, 10-minute ring buffer (200 points)
```

- **Trees:** the app = `getpid()` and its children (minus the daemon and holders); the daemon = the pid `hello` returns (re-asked every 30 s); a session = its holder and everything under it. Every pid is counted once.
- **CPU %** = change in CPU time over change in wall time, so it can pass 100% like Activity Monitor.
- **Cost:** about 1 ms per tick for 50 processes; it always runs so the history is there when a view opens.
- **Guard bar** uses the holder's own footprint, the number the watchdog acts on; the row total also includes the agent.

## Where it shows

| View | What | Code |
|---|---|---|
| Resources (centre, after Overview, ⇧⌘U) | One Roof totals and charts, This Mac, the app and daemon, sessions by window heaviest first | `UI/ResourcesView.swift`, `ResourceMonitor.swift` |
| Plan panel › Resources (after Artifacts) | One session: memory and CPU now and over 10 minutes, the guard, its processes | `UI/ResourcesView.swift` (`SessionResourcesTab`) |

## Known limits

- The "This Mac" figure is all apps on the Mac, not One Roof; LAB-504 will show One Roof's share of it.
- Sessions started before 0.4.3 keep the old holder (and its leak) until relaunched.
- launchd's "Code Signature Invalid" kills of roofd after ad-hoc rebuilds (10-20) are not addressed here.
