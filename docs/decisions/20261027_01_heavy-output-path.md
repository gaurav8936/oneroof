# Heavy terminal output: what to change in the output path

**Status:** DECIDED · **Date:** 2026-10-27 · **Linear:** LAB-1324 (study), LAB-ONEROOF-PERFORMANCE-IMPROVEMENTS · **Release:** 1.9.11

> **One line:** the session process (holder) spent most of its CPU on system calls and thread wake-ups, not on
> parsing; reading the PTY in batches cuts roofd's CPU per MB of output by about a third. The attach relay and the
> terminal engine stay as they are.

## The question

Under heavy output (five terminals printing as fast as they can) One Roof and roofd together used more than four
CPU cores. Each byte crosses three processes: the PTY into the session's holder (which forwards it and parses it with
its own terminal model, so sessions survive app restarts), the `roofd attach` relay, and libghostty in the app.
Should the path change, and where?

## What was measured

`app/scripts/perf/perf-check.sh` (busy scenario) plus a CPU-only Time Profiler trace of one flooding holder, on the
owner's Mac under normal load (other sessions running; load 45–70):

| Holder, flooding | Share of its CPU |
|---|---|
| `poll` + `read` system calls (one per few KB) | ~47 % |
| Handing each read to the parse queue (dispatch, worker-thread start) | ~30 % |
| Parsing (the terminal model) | a few % |

A PTY read returns a few KB, and the holder read once per wake-up, so it made a poll, a read and a parse dispatch
for every few KB.

## Options

1. **Batch the holder's reads** (read until the PTY is empty, up to 64 KB, then forward and parse once). Small,
   local, keeps every guarantee (order, nothing lost, redraw before live output).
2. **Stop parsing while a terminal is attached.** Little to gain (parsing is a few percent), and the parse is what
   lets a session redraw after the app restarts. Rejected.
3. **Remove the attach relay** (let the app read the holder's socket directly). Needs an embedding API libghostty
   does not offer (a surface runs a command); One Roof never modifies libghostty. Rejected.

## Decision

Option 1, shipped in 1.9.11, together with one parse block in flight at a time (bytes queued in read order). Measured
on the same Mac, same scenario, before and after, twice each:

| | 1.9.10 | 1.9.11 |
|---|---|---|
| CPU per MB of output (roofd) | 1.14 · 0.92 CPU-s | 0.70 · 0.62 CPU-s |
| Total CPU, five flooding sessions | 421 % · 298 % | 197 % · 208 % |

The app side (libghostty drawing the output) is unchanged by this release; with 1.9.8–1.9.10 the app's main thread
already stays free under heavy output (no stalls of 50 ms or more).
