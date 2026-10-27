#!/usr/bin/env python3
"""Time Profiler trace → main-thread busy % and stalls (LAB-1325). Usage: parse_tp.py <trace> <out.json>

Exports the time-profile table (xctrace export), resolves id/ref, keeps the app's main thread (the thread whose
backtraces hold NSApplication run / main). A stall is a run of consecutive running samples (1 ms each, gaps ≤ 1.5 ms):
counted at ≥ 16.7 ms (a missed frame) and ≥ 50 ms (a visible hitch). This is the frame-miss proxy used when the
Animation Hitches template can't record (it needs root). Also lists the top One Roof frames and SwiftUI view bodies."""
import json, re, subprocess, sys, xml.etree.ElementTree as ET
from collections import Counter

trace, dest = sys.argv[1], sys.argv[2]
xml = subprocess.run(['xcrun', 'xctrace', 'export', '--input', trace, '--xpath',
                      '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'], capture_output=True, text=True).stdout
root = ET.fromstring(xml)
ids = {}


def reg(e):
    for x in e.iter():
        if x.get('id'): ids[x.get('id')] = x


def res(e):
    return ids[e.get('ref')] if e is not None and e.get('ref') is not None else e


rows = []
for row in root.iter('row'):
    reg(row)
    th = res(row.find('thread')).get('fmt', '')
    t = int(res(row.find('sample-time')).text)
    frames = []
    bt = res(row.find('backtrace'))
    if bt is not None:
        for f in bt.findall('frame'):
            f = res(f); b = f.find('binary')
            frames.append((f.get('name', '?'), res(b).get('name', '') if b is not None else ''))
    rows.append((t, th, frames))

mt = Counter(th for _, th, fr in rows if any(n in ('main', 'OneRoof_main') or 'NSApplication run' in n for n, _ in fr))
main = mt.most_common(1)[0][0] if mt else None
mrows = sorted((r for r in rows if r[1] == main), key=lambda r: r[0])
dur = (rows[-1][0] - rows[0][0]) / 1e9 if len(rows) > 1 else 0
ofr, bodies = Counter(), Counter()
for _, _, fr in mrows:
    for n in set(n for n, b in fr if b == 'OneRoof' and n not in ('main',) and not n.startswith('OneRoof_main')): ofr[n] += 1
    for n in set(re.sub(r'^.* in ', '', n) for n, b in fr if b == 'OneRoof' and n.endswith('.body.getter')): bodies[n] += 1
stalls, start, last = [], None, None
for t, *_ in mrows:
    if last is None or t - last > 1_500_000:
        if start is not None: stalls.append((last - start + 1_000_000) / 1e6)
        start = t
    last = t
if start is not None: stalls.append((last - start + 1_000_000) / 1e6)
n = len(mrows)
out = dict(duration_s=round(dur, 1), main_samples=n, main_busy_pct=round(n / (dur * 1000) * 100, 1) if dur else 0,
           process_cpu_pct=round(len(rows) / (dur * 1000) * 100, 1) if dur else 0,
           stalls_16_per_min=round(sum(s >= 16.7 for s in stalls) / dur * 60, 1) if dur else 0,
           stalls_50_per_min=round(sum(s >= 50 for s in stalls) / dur * 60, 1) if dur else 0,
           stall_ms_per_s=round(sum(s for s in stalls if s >= 16.7) / dur, 1) if dur else 0,
           longest_stall_ms=round(max(stalls), 1) if stalls else 0,
           top_frames=[(k[:140], round(v / n * 100, 1)) for k, v in ofr.most_common(15)] if n else [],
           top_bodies=[(k.replace('.body.getter', ''), round(v / n * 100, 1)) for k, v in bodies.most_common(12)] if n else [])
json.dump(out, open(dest, 'w'), indent=1)
print(json.dumps({k: v for k, v in out.items() if not k.startswith('top_')}))
