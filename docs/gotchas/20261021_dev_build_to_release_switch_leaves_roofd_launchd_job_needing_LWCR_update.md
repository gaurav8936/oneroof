# Switching from an ad-hoc dev build to the notarized release leaves roofd's launchd job broken (exit 78)

**Found:** 2026-10-21 (QA of 0.4.4) · **Tracked:** LAB-516

**Symptom:** after quitting `app/build/One Roof.app` (ad-hoc) and opening the notarized `/Applications` build, `launchctl print gui/$UID/io.github.gaurav8936.oneroof.roofd` showed `needs LWCR update`, `last exit code = 78: EX_CONFIG`, dozens of runs; the app quietly ran roofd as its own child (stops at logout).

**Cause:** the old SMAppService registration keeps the old launch constraint; `RoofdService.register()` stores the new build and believes it is enabled, so it never re-registers. After `launchctl bootout` the background-items database still says enabled while launchd has no job.

**Fix on a Mac:** quit One Roof → `launchctl bootout gui/$(id -u)/io.github.gaurav8936.oneroof.roofd` → `defaults delete io.github.gaurav8936.oneroof roofd.registeredBuild` → open One Roof. Sessions (holders) survive. Release → release upgrades (same Developer ID) re-register fine (verified 0.4.4 → 0.4.5 → 0.4.6).
