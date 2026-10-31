# Hosted-agent performance investigation

**Status:** IN REVIEW · **Date:** 2026-10-31 · **Project:** LAB-AE-OPEN-AGENTS / LAB-1898

> **One line:** performance acceptance remains unresolved; existing evidence does not establish a specific root cause or justify a source fix.

## Evidence and method

The release session reported isolated baseline/candidate medians of 12.1/42.5 ms/s for Full and 37.2/48.6 for Sessions-edge dragging. Its gate correctly held the release. Inspection found different saved window/pane state, three archived-session differences and seven feed-row differences between the saved profiles. Quick/full modes change scenario windows, not the three gesture scripts. One original baseline trial already reached 42.4 ms/s for Full, showing overlap concealed by the headline medians.

Retested both existing binaries sequentially on the same copied baseline profile and unchanged gesture script. The installed app and source were untouched. Each run had its own copied store and private test daemon. Two initial runs were profiled and are excluded from the following unprofiled comparison. Two additional unprofiled trials per binary yielded hitch ms/s:

- Full: baseline 30.3, 27.9; candidate 25.0, 34.5.
- Sessions-edge dragging: baseline 61.4, 45.1; candidate 54.7, 38.0.
- Wide: baseline 60.9, 23.6; candidate 26.3, 25.5.
- Focus: baseline 11.6, 12.3; candidate 24.4, 31.4.
- Sessions: baseline 20.8, 25.8; candidate 38.0, 40.3.

These are small diagnostic samples, not a replacement release gate or a statistically established effect size. They do not consistently reproduce the Full/drag magnitude; Focus/Sessions still warrant investigation.

## Hypotheses tested

The inline hosted launch payload is 160 bytes; the current Session size is 594 bytes and BoardItem 752 bytes. This creates a plausible shared copying cost even when hostedLaunch is nil, but CPU evidence does not establish causation. No boxing fix was applied.

General gesture CPU samples found synchronous stack symbolication in the pre-existing WindowFrameLog resize logger. Similar cost appeared in both binaries; this does not explain the differential. Repeated-focus samples (25 seconds each at 1 ms nominal interval, identical scratch script/profile) showed main-thread waiting in the run loop for approximately 94.1% baseline and 94.4% candidate. Session/BoardItem copy samples were similar and sparse. No hosted session existed in either test profile; hosted request work was not exercised.

## Conclusion and next step

Root cause UNPROVEN. The original comparison had workload and run-variance limitations; that does not clear the integration or invalidate the release hold. Neither session boxing nor the logger is established as the regression cause. No source fix, waiver, deployment or installed-app change was made.

Owner explicitly requested analysis only and then closed the session. Controlled diagnostic source experiments that vary one part of the change require explicit permission before proceeding. Preserve the existing evidence, obtain that permission if desired, isolate causation, then have the release owner run the full gate after a proved fix. Do not ship based on unit/functional passes alone.
