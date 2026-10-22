# roofd: a reply with an `error` key makes `Sock.holderRequest` throw, so the caller never sees the answer

**Found:** 2026-10-21 (LAB-518) · **Where:** `app/roofd/Sources/roofd/Wire.swift` (`if let e = obj["error"] … throw`)

**Symptom:** `roofd issue LAB-9 --state Done` waited 20 s and printed "queued" although the app had refused it.

**Cause:** the holder answered `issueStatus` with `["done": true, "error": reason]`. The socket helper treats any reply carrying `error` as a failed call and throws; the CLI's `try?` turned that into "no answer yet" and kept polling.

**Rule:** a reply that is a successful call carrying a negative result must use another key (`refused`). Keep `error` for real call failures.
