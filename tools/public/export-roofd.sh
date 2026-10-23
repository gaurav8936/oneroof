#!/usr/bin/env bash
# oneroof · rebuild the public roofd copy (LAB-555) from this repo's committed HEAD.
#
#   tools/public/export-roofd.sh [DEST] [--verify] [--commit]
#       DEST      the public repo checkout (default ~/Projects/labs/public/roofd)
#       --verify  build RoofVT, then swift build + swift test in DEST
#       --commit  commit DEST as "roofd from oneroof <sha>" (never pushes; publishing is a separate, owner-approved push)
#
# The copy is for distribution only: One Roof stays the source of truth and is not changed for it. Fixes land here in
# oneroof, then this script runs again. Every published file is named below (an allowlist, never a folder copy minus
# exclusions), so a new file in oneroof can never reach the public repo by accident. Files come from `git archive HEAD`,
# so uncommitted work is never published. Source files are copied byte for byte; only Package.swift, the RoofVT build
# script, README and .gitignore are the copy's own (tools/public/roofd/).
#
# roofd shares OneRoofCore with the app (status engine, agent kinds, process probe, the session store its scheduler
# reads). OneRoofCore's files link to each other, so the copy carries the 29 that roofd's build reaches. When a One Roof
# change makes roofd need another one, --verify fails with "cannot find ... in scope": add that file to CORE below.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
DEST="$HOME/Projects/labs/public/roofd"
VERIFY=0; COMMIT=0
for a in "$@"; do
  case "$a" in
    --verify) VERIFY=1 ;;
    --commit) COMMIT=1 ;;
    -*) echo "export-roofd: unknown option $a" >&2; exit 2 ;;
    *) DEST="$a" ;;
  esac
done

# Published path ← path in oneroof.
FILES=(
  "Sources/roofd/main.swift=app/roofd/Sources/roofd/main.swift"
  "Sources/roofd/Daemon.swift=app/roofd/Sources/roofd/Daemon.swift"
  "Sources/roofd/Holder.swift=app/roofd/Sources/roofd/Holder.swift"
  "Sources/roofd/Attach.swift=app/roofd/Sources/roofd/Attach.swift"
  "Sources/roofd/Wire.swift=app/roofd/Sources/roofd/Wire.swift"
  "Sources/roofd/Scheduler.swift=app/roofd/Sources/roofd/Scheduler.swift"
  "Sources/roofd/WorkPath.swift=app/roofd/Sources/roofd/WorkPath.swift"
  "Sources/CRoofSpawn/spawn.c=app/roofd/Sources/CRoofSpawn/spawn.c"
  "Sources/CRoofSpawn/include/CRoofSpawn.h=app/roofd/Sources/CRoofSpawn/include/CRoofSpawn.h"
  "Tests/RoofdTests/RoofProtocolTests.swift=app/roofd/Tests/RoofdTests/RoofProtocolTests.swift"
  "Tests/RoofdTests/RoofdMemoryTests.swift=app/roofd/Tests/RoofdTests/RoofdMemoryTests.swift"
  "RoofVT/build.zig=app/roofd/RoofVT/build.zig"
  "RoofVT/build.zig.zon=app/roofd/RoofVT/build.zig.zon"
  "RoofVT/include/RoofVT.h=app/roofd/RoofVT/include/RoofVT.h"
  "RoofVT/src/roofvt.zig=app/roofd/RoofVT/src/roofvt.zig"
  "docs/design.md=docs/decisions/20261020_01_roofd-replaces-herdr.md"
  "LICENSE=LICENSE"
)
CORE=(
  AEFolder AppResources Board Captions Decisions Feed Foundations ImageAttachments IssueUpdates LaunchPlan
  LegacyMigration Linear LocalModel MemoryWatchdog Objectives Openings ProcessProbe RoofdRuntime Router Schedules
  Session SessionRuntime SessionStore SessionStoreV2 Settings Shortcut StatusEngine TerminalMouse Workspace
)
for c in "${CORE[@]}"; do FILES+=("Sources/OneRoofCore/$c.swift=app/Sources/OneRoofCore/$c.swift"); done
# The copy's own files.
OWN=(Package.swift README.md .gitignore scripts/build-roofvt.sh)

[ -d "$DEST/.git" ] || { mkdir -p "$DEST"; git -C "$DEST" init -q -b main; }
SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
git -C "$ROOT" archive HEAD | tar -x -C "$STAGE"

# Replace everything but .git and build output, so a file dropped from the list disappears from the copy too.
find "$DEST" -mindepth 1 -maxdepth 1 ! -name .git ! -name .build ! -name Vendor -exec rm -rf {} +
for f in "${FILES[@]}"; do
  dst="${f%%=*}"; src="${f#*=}"
  [ -f "$STAGE/$src" ] || { echo "export-roofd: $src is not in HEAD" >&2; exit 1; }
  mkdir -p "$DEST/$(dirname "$dst")"; cp "$STAGE/$src" "$DEST/$dst"
done
for f in "${OWN[@]}"; do
  [ -f "$STAGE/tools/public/roofd/$f" ] || { echo "export-roofd: tools/public/roofd/$f is not in HEAD" >&2; exit 1; }
  mkdir -p "$DEST/$(dirname "$f")"; cp "$STAGE/tools/public/roofd/$f" "$DEST/$f"
done
chmod +x "$DEST/scripts/build-roofvt.sh"
printf 'oneroof %s\nhttps://github.com/gaurav8936/oneroof/tree/%s\n' "$(git -C "$ROOT" rev-parse HEAD)" "$(git -C "$ROOT" rev-parse HEAD)" > "$DEST/PUBLISHED_FROM"

# Leak gate: no home-folder paths, no key-shaped strings.
if grep -rnE '/Users/[a-z]|lin_api_|sk-ant-|xox[bp]-|ghp_[A-Za-z0-9]{20}|BEGIN [A-Z ]*PRIVATE KEY' "$DEST" --exclude-dir=.git --exclude-dir=.build --exclude-dir=Vendor; then
  echo "export-roofd: the copy has a private-looking string (above); not exported" >&2; exit 1
fi
echo "export-roofd: $(find "$DEST" -type f ! -path '*/.git/*' ! -path '*/.build/*' ! -path '*/Vendor/*' | wc -l | tr -d ' ') files from oneroof $SHA → $DEST"

if [ "$VERIFY" = 1 ]; then
  ( cd "$DEST" && scripts/build-roofvt.sh && swift build && swift test )
fi
if [ "$COMMIT" = 1 ]; then
  git -C "$DEST" add -A
  if git -C "$DEST" diff --cached --quiet; then echo "export-roofd: no changes to commit"
  else git -C "$DEST" commit -q -m "roofd from oneroof $SHA" && echo "export-roofd: committed $(git -C "$DEST" rev-parse --short HEAD)"; fi
fi
