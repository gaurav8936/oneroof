#!/usr/bin/env bash
# Re-render site/og.png (the link card) from og.html with headless Chrome. LAB-2212.
set -euo pipefail; D=$(cd "$(dirname "$0")" && pwd)
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --window-size=1200,630 \
  --virtual-time-budget=5000 --screenshot="$D/../og.png" "file://$D/og.html" >/dev/null 2>&1
sips -g pixelWidth -g pixelHeight "$D/../og.png" | tail -2
