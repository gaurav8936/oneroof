#!/usr/bin/env python3
"""perf-check report (LAB-1325): per-scenario metrics → result.json + a Markdown table, compared with the baseline
(a headline number more than 15 % worse fails) and, with a phase, the gate in gates.json.

  report.py <out dir> <version> <baseline.json> <gates.json> [phase]      exit 0 pass · 1 fail"""
import json, pathlib, re, sys

out, version, base_p, gates_p = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
phase = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] else None
base = json.loads(pathlib.Path(base_p).read_text()); gates = json.loads(pathlib.Path(gates_p).read_text())
HEADLINE = ['app_cpu', 'stalls_50_per_min', 'stall_ms_per_s', 'children_per_min', 'mb_per_terminal']
TOL = 0.15
LABEL = dict(app_cpu='App CPU %', roofd_cpu='roofd CPU %', main_busy='Main thread busy %', stalls_50_per_min='Stalls ≥50 ms /min',
             stall_ms_per_s='Stall ms/s', longest_stall_ms='Longest stall ms', model_changes_per_s='Model changes/s',
             children_per_min='Processes started /min', footprint_mb='Footprint MB', mb_per_terminal='MB per terminal visited')


def mb(s):
    m = re.match(r'([\d.]+)([BKMG])', s)
    return float(m.group(1)) * {'B': 1 / 2**20, 'K': 1 / 1024, 'M': 1, 'G': 1024}[m.group(2)] if m else None


res = {}
for d in sorted(p for p in out.iterdir() if p.is_dir() and p.name not in ('build', 'work')):
    r = {}
    m = d / 'measure.json'
    if m.exists():
        j = json.loads(m.read_text())
        r.update(app_cpu=j['app']['cpu_pct'], roofd_cpu=j['roofd']['cpu_pct'], footprint_mb=j['app']['footprint_mb'],
                 children_per_min=j['children']['per_min'], model_changes_per_s=j.get('model_changes_per_s'),
                 _children_top=j['children']['top'])
    t = d / 'tp.json'
    if t.exists():
        j = json.loads(t.read_text())
        r.update(main_busy=j['main_busy_pct'], stalls_50_per_min=j['stalls_50_per_min'], stall_ms_per_s=j['stall_ms_per_s'],
                 longest_stall_ms=j['longest_stall_ms'], _top_bodies=j['top_bodies'][:6], _top_frames=j['top_frames'][:6])
    mem = d / 'mem.txt'
    if mem.exists():
        fp = [v for v in (mb(l.split()[1]) for l in mem.read_text().splitlines() if len(l.split()) > 1) if v]
        if len(fp) > 6:
            # growth from the first terminal (after the warm-up, ~10 s in) to the end, over the 10 terminals visited
            r.update(footprint_start_mb=round(fp[5]), footprint_end_mb=round(fp[-1]), mb_per_terminal=round((fp[-1] - fp[5]) / 10, 1))
    if r: res[d.name] = r

fails, rows = [], []
gate = gates.get(phase, {}) if phase else {}
if not res: fails.append('no scenario produced a measurement')
if phase and phase not in gates: fails.append(f'no gate named {phase} in gates.json')
for s, r in res.items():
    b = base.get(s, {})
    for k, v in r.items():
        if k.startswith('_') or v is None: continue
        bv = b.get(k); g = gate.get(s, {}).get(k)
        delta = f'{(v - bv) / bv * 100:+.0f} %' if bv else ''
        verdict = ''
        if k in HEADLINE and bv is not None and v > bv * (1 + TOL) and v - bv > 0.5:
            verdict = 'REGRESSION'; fails.append(f'{s} {k} {v} > baseline {bv} +15 %')
        if g is not None:
            if v > g: verdict = (verdict + ' ' if verdict else '') + f'GATE ✗ (≤{g})'; fails.append(f'{s} {k} {v} > gate {g}')
            else: verdict = (verdict + ' ' if verdict else '') + f'gate ✓ (≤{g})'
        rows.append((s, LABEL.get(k, k), v, bv if bv is not None else '–', delta, verdict))

(out / 'result.json').write_text(json.dumps(dict(version=version, baseline=base.get('version'), phase=phase, scenarios=res, fails=fails), indent=1))
md = [f'### One Roof {version} perf check' + (f' · gate {phase}' if phase else '') + f' · vs baseline {base.get("version")}', '',
      '| Scenario | Measure | Now | Baseline | Change | Verdict |', '|---|---|---|---|---|---|']
md += [f'| {s} | {k} | {v} | {bv} | {d} | {vd} |' for s, k, v, bv, d, vd in rows]
md += ['', '**PASS**' if not fails else '**FAIL**: ' + '; '.join(fails)]
for s, r in res.items():
    if r.get('_top_bodies'): md.append(f'- {s} top view bodies: ' + ', '.join(f'{n} {p}%' for n, p in r['_top_bodies']))
    if r.get('_children_top'): md.append(f'- {s} processes started: ' + ', '.join(f'{n.strip()} ×{c}' for n, c in r['_children_top'][:5]))
(out / 'result.md').write_text('\n'.join(md) + '\n')
print('\n'.join(md))
sys.exit(1 if fails else 0)
