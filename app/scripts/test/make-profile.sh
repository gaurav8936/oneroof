#!/usr/bin/env bash
# make-profile.sh <dir> — a COPY of the owner's real One Roof profile for test runs (LAB-1595): sessions.sqlite through
# sqlite's online backup (read-only on the live store) and the defaults domain exported to defaults.plist.
# The live store and preferences are only read. Exit 2 when there is no profile on this Mac.
set -u
D=$1; mkdir -p "$D"
LIVE="$HOME/Library/Application Support/One Roof/sessions.sqlite"
PREFS="$HOME/Library/Preferences/io.github.gaurav8936.oneroof.plist"
[ -f "$LIVE" ] || { echo "make-profile: no store at $LIVE" >&2; exit 2; }
sqlite3 -readonly "$LIVE" ".backup '$D/sessions.sqlite'" || exit 2
python3 - "$PREFS" "$D/defaults.plist" <<'PY'
import plistlib, sys, os
src, dst = sys.argv[1], sys.argv[2]
d = plistlib.load(open(src, 'rb')) if os.path.exists(src) else {}
plistlib.dump(d, open(dst, 'wb'))
PY
